-- ==========================================
-- PLAYER RESOURCES (Mana, Energy Shield, Life & Mana Flasks)
-- Path: ServerStorage.Modules.PlayerResources
-- ==========================================
-- The real current values live here on the server. Clients only see copies in player attributes:
--   Mana, EnergyShield (whole numbers), LifeFlaskCharges, ManaFlaskCharges
-- Max values come from PlayerData stats (MaxMana, MaxEnergyShield, EnergyShieldRecharge). Nothing here is saved:
-- every spawn and every portal starts full
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerStats = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerStats"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local flaskRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FlaskRemote") :: RemoteEvent

-- ==========================================
-- CONFIGURATION
-- ==========================================
local TICK = 0.1 -- Seconds between mana regen / energy shield recharge / flask recovery steps

type Recovery = {
	Remaining: number, -- Health or mana still to give
	PerSecond: number,
}

type State = {
	Mana: number,
	EnergyShield: number,
	LastHitTime: number, -- Energy shield recharge waits ENERGY_SHIELD_RECHARGE_DELAY after this
	FlaskCharges: { [string]: number }, -- Per flask kind in PlayerStats.FLASKS ("Life", "Mana")
	FlaskTimes: { [string]: number }, -- When each flask was last drunk
	Recoveries: { [string]: Recovery }, -- Flask recoveries still running, per kind
}

local PlayerResources = {}

local states: { [Player]: State } = {}

-- ==========================================
-- 1. STATE -> ATTRIBUTES
-- ==========================================
local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = {
			Mana = 0,
			EnergyShield = 0,
			LastHitTime = -math.huge,
			FlaskCharges = {},
			FlaskTimes = {},
			Recoveries = {},
		}
		states[player] = state
	end
	return state
end

local function setAttribute(player: Player, name: string, value: number)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

-- Mana / energy shield are floored, so regen only replicates when a whole point changes
local function publish(player: Player, state: State)
	setAttribute(player, "Mana", math.floor(state.Mana))
	setAttribute(player, "EnergyShield", math.floor(state.EnergyShield))
	for kind, charges in pairs(state.FlaskCharges) do
		setAttribute(player, kind .. "FlaskCharges", charges)
	end
end

-- ==========================================
-- 2. PUBLIC API (used by CombatServer / EnemyService)
-- ==========================================
-- Full mana, energy shield and flasks: every spawn, and at the portals (which also heal to full)
function PlayerResources.restoreAll(player: Player)
	local state = getState(player)
	local stats = PlayerData.getStats(player)
	state.Mana = stats.MaxMana
	state.EnergyShield = stats.MaxEnergyShield
	for kind, flask in pairs(PlayerStats.FLASKS) do
		state.FlaskCharges[kind] = flask.MaxCharges
	end
	table.clear(state.Recoveries)
	publish(player, state)
end

-- Returns false (and spends nothing) when there isn't enough mana
function PlayerResources.spendMana(player: Player, amount: number): boolean
	if amount <= 0 then
		return true
	end
	local state = getState(player)
	if state.Mana < amount then
		return false
	end
	state.Mana -= amount
	publish(player, state)
	return true
end

-- Enemy hits: energy shield takes the damage first, the rest goes to health. Every hit delays the recharge
function PlayerResources.takeDamage(player: Player, humanoid: Humanoid, amount: number)
	local state = getState(player)
	state.LastHitTime = os.clock()
	local absorbed = math.min(state.EnergyShield, amount)
	state.EnergyShield -= absorbed
	if amount > absorbed then
		humanoid:TakeDamage(amount - absorbed)
	end
	publish(player, state)
end

-- Kills top up every flask. Fractions add up; a flask can be drunk once it has 1 or more
function PlayerResources.addFlaskCharges(player: Player, amount: number)
	local state = getState(player)
	for kind, flask in pairs(PlayerStats.FLASKS) do
		-- Rounded so fractions like 0.2 add up to exactly 1 use
		local charges = math.round(((state.FlaskCharges[kind] or 0) + amount) * 100) / 100
		state.FlaskCharges[kind] = math.min(charges, flask.MaxCharges)
	end
	publish(player, state)
end

-- ==========================================
-- 3. DRINKING A FLASK (FlaskRemote from CombatClient)
-- ==========================================
local function drinkFlask(player: Player, kind: any)
	local flask = if type(kind) == "string" then PlayerStats.FLASKS[kind] else nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not flask or not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Already full: refuse, so a use isn't wasted by a misclick
	local state = getState(player)
	local stats = PlayerData.getStats(player)
	if kind == "Life" and humanoid.Health >= humanoid.MaxHealth then
		return
	elseif kind == "Mana" and state.Mana >= stats.MaxMana then
		return
	end

	-- One recovery per flask at a time, and at least one use left
	local now = os.clock()
	if now - (state.FlaskTimes[kind] or -math.huge) < flask.Duration - 0.05 then
		return
	end
	if (state.FlaskCharges[kind] or 0) < 1 then
		return
	end
	state.FlaskCharges[kind] -= 1
	state.FlaskTimes[kind] = now

	local total = (if kind == "Life" then humanoid.MaxHealth else stats.MaxMana) * flask.RecoverPercent
	state.Recoveries[kind] = { Remaining = total, PerSecond = total / flask.Duration }
	publish(player, state)
	flaskRemote:FireAllClients(character, kind) -- Everyone else sees the sparkles
end

-- ==========================================
-- 4. EVERY TICK: MANA REGEN, ENERGY SHIELD RECHARGE, FLASK RECOVERY
-- ==========================================
local function update(player: Player, state: State, deltaTime: number, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return -- Dead: nothing regenerates, the respawn refills everything
	end
	local stats = PlayerData.getStats(player)

	-- Also pulls the values down when gear that gave max mana / energy shield is removed
	state.Mana = math.min(state.Mana + stats.MaxMana * PlayerStats.MANA_REGEN_PERCENT * deltaTime, stats.MaxMana)

	if now - state.LastHitTime >= PlayerStats.ENERGY_SHIELD_RECHARGE_DELAY then
		local rate = PlayerStats.ENERGY_SHIELD_RECHARGE_PERCENT * (1 + stats.EnergyShieldRecharge / 100)
		state.EnergyShield += stats.MaxEnergyShield * rate * deltaTime
	end
	state.EnergyShield = math.min(state.EnergyShield, stats.MaxEnergyShield)

	for kind, recovery in pairs(state.Recoveries) do
		local amount = math.min(recovery.PerSecond * deltaTime, recovery.Remaining)
		recovery.Remaining -= amount
		if kind == "Life" then
			humanoid.Health = math.min(humanoid.Health + amount, humanoid.MaxHealth)
		else
			state.Mana = math.min(state.Mana + amount, stats.MaxMana)
		end
		if recovery.Remaining <= 0 then
			state.Recoveries[kind] = nil
		end
	end

	publish(player, state)
end

function PlayerResources.start()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function()
			PlayerResources.restoreAll(player)
		end)
		PlayerResources.restoreAll(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)

	flaskRemote.OnServerEvent:Connect(drinkFlask)

	task.spawn(function()
		local lastTime = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local deltaTime = now - lastTime
			lastTime = now
			for player, state in pairs(states) do
				local ok, err = pcall(update, player, state, deltaTime, now)
				if not ok then
					warn("[PlayerResources] Update error:", err)
				end
			end
		end
	end)
end

return PlayerResources
