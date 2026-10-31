-- ==========================================
-- HERO SERVICE (Class mechanics: Warrior Fury, Ranger Momentum, Mystic Stone Orbs)
-- Path: ServerStorage.Modules.HeroService
-- ==========================================
-- Numbers and paths are in ReplicatedStorage.Modules.HeroData. The state lives here (not saved, it starts
-- empty every spawn) and goes to clients as player attributes: Fury, Momentum, Orbs, HeroAttackSpeed.
-- CombatServer calls useSkill / onEnemiesHit / onDodge / getAttackSpeedBonus and gives it the function that
-- damages enemies (setDamageHandler, so this module never needs CombatServer / EnemyService).
-- EnemyService asks absorbHit before hurting a player (Wardstone orbs)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local HeroData = require(modulesFolder:WaitForChild("HeroData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local combatRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatRemote") :: RemoteEvent

local TICK = 0.1 -- Seconds between updates (decay, movement, orb shots)
local MOVING_THRESHOLD = 0.2 -- Studs per tick that count as moving (Ranger)
local MAX_STEP = 5 -- Studs per tick counted at most, so teleports / portals don't give stacks

type State = {
	Fury: number,
	LastHitTime: number,
	Momentum: number,
	MovedDistance: number,
	StillTime: number,
	LastPosition: Vector3?,
	BaseWalkSpeed: number?, -- Windrunner: the character's normal speed
	ManaSpent: number, -- Mystic: toward the next orb
	Orbs: { number }, -- Mystic: when each orb runs out (os.clock)
	NextVolley: number,
}

export type SkillBonus = {
	DamageMultiplier: number,
	CritChance: number, -- Added to the skill's own
	PulseRadius: number?, -- Earthbreaker: also hit everything this close to the player
}

local HeroService = {}

local states: { [Player]: State } = {}
local damageHandler: ((Player, Model, Humanoid, number, string) -> ())? = nil

local function newState(): State
	return {
		Fury = 0,
		LastHitTime = -math.huge,
		Momentum = 0,
		MovedDistance = 0,
		StillTime = 0,
		LastPosition = nil,
		BaseWalkSpeed = nil,
		ManaSpent = 0,
		Orbs = {},
		NextVolley = 0,
	}
end

local function getState(player: Player): State
	local state = states[player]
	if not state then
		state = newState()
		states[player] = state
	end
	return state
end

local function setAttribute(player: Player, name: string, value: number)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

local function publish(player: Player, state: State)
	local classId = PlayerData.getHero(player)
	setAttribute(player, "Fury", if classId == "Warrior" then math.floor(state.Fury) else 0)
	setAttribute(player, "Momentum", if classId == "Ranger" then state.Momentum else 0)
	setAttribute(player, "HeroAttackSpeed", if classId == "Ranger" then state.Momentum * HeroData.MOMENTUM_ATTACK_SPEED else 0)
	setAttribute(player, "Orbs", if classId == "Mystic" then #state.Orbs else 0)
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	return root
end

-- ==========================================
-- 1. HOOKS (CombatServer / EnemyService)
-- ==========================================
-- How hero mechanics damage enemies (CombatServer passes its own damage + ailment path)
function HeroService.setDamageHandler(handler: (Player, Model, Humanoid, number, string) -> ())
	damageHandler = handler
end

-- Once per skill use, after the mana is paid. Returns what the hero adds to this skill (and spends full Fury)
function HeroService.useSkill(player: Player, manaSpent: number): SkillBonus
	local bonus: SkillBonus = { DamageMultiplier = 1, CritChance = 0, PulseRadius = nil }
	local classId, variantId = PlayerData.getHero(player)
	local state = getState(player)

	if classId == "Warrior" then
		if variantId == "Berserker" then
			bonus.DamageMultiplier = 1 + math.floor(state.Fury / 10) * HeroData.BERSERKER_DAMAGE_PER_10_FURY
		elseif state.Fury >= HeroData.FURY_MAX then
			state.Fury = 0
			local earthbreaker = variantId == "Earthbreaker"
			bonus.DamageMultiplier = if earthbreaker then HeroData.EARTHBREAKER_MULTIPLIER else HeroData.FURY_RELEASE_MULTIPLIER
			bonus.PulseRadius = if earthbreaker then HeroData.EARTHBREAKER_RADIUS else nil
			if player.Character then
				local radius = if earthbreaker then HeroData.EARTHBREAKER_RADIUS else 4
				combatRemote:FireAllClients("HeroPulse", player.Character, radius, HeroData.Heroes.Warrior.Color)
			end
		end
	elseif classId == "Ranger" then
		if variantId == "Deadeye" then
			bonus.CritChance = state.Momentum * HeroData.DEADEYE_CRIT_CHANCE
		end
	elseif classId == "Mystic" and manaSpent > 0 then
		state.ManaSpent += manaSpent
		local now = os.clock()
		while state.ManaSpent >= HeroData.ORB_MANA do
			state.ManaSpent -= HeroData.ORB_MANA
			if #state.Orbs < HeroData.ORB_MAX then
				table.insert(state.Orbs, now + HeroData.ORB_DURATION)
			else
				-- At the limit: the orb closest to running out is renewed
				table.sort(state.Orbs)
				state.Orbs[1] = now + HeroData.ORB_DURATION
			end
		end
	end

	publish(player, state)
	return bonus
end

-- A skill hit `count` enemies (Warrior: builds Fury)
function HeroService.onEnemiesHit(player: Player, count: number)
	if count <= 0 or PlayerData.getHero(player) ~= "Warrior" then
		return
	end
	local state = getState(player)
	state.Fury = math.min(state.Fury + count * HeroData.FURY_PER_HIT, HeroData.FURY_MAX)
	state.LastHitTime = os.clock()
	publish(player, state)
end

-- The server accepted a dodge (Ranger: more Momentum)
function HeroService.onDodge(player: Player)
	if PlayerData.getHero(player) ~= "Ranger" then
		return
	end
	local state = getState(player)
	state.Momentum = math.min(state.Momentum + HeroData.MOMENTUM_PER_DODGE, HeroData.MOMENTUM_MAX)
	state.StillTime = 0
	publish(player, state)
end

-- % attack speed on top of the AttackSpeed stat (Ranger Momentum). Clients read it from "HeroAttackSpeed"
function HeroService.getAttackSpeedBonus(player: Player): number
	local state = states[player]
	if not state or PlayerData.getHero(player) ~= "Ranger" then
		return 0
	end
	return state.Momentum * HeroData.MOMENTUM_ATTACK_SPEED
end

-- An enemy hit is about to land on this player: a Wardstone orb takes it instead (returns true = blocked)
function HeroService.absorbHit(player: Player): boolean
	local classId, variantId = PlayerData.getHero(player)
	local state = states[player]
	if classId ~= "Mystic" or variantId ~= "Wardstone" or not state or #state.Orbs == 0 then
		return false
	end
	table.sort(state.Orbs)
	table.remove(state.Orbs, 1) -- The orb closest to running out breaks
	publish(player, state)
	return true
end

-- ==========================================
-- 2. EVERY TICK: FURY FADES, MOMENTUM FROM WALKING, ORBS RUN OUT AND SHOOT
-- ==========================================
-- Living enemies within range, nearest first
local function findTargets(origin: Vector3, range: number): { { Model: Model, Humanoid: Humanoid, Root: BasePart } }
	local targets = {}
	local folder = workspace:FindFirstChild("Enemies")
	for _, model in ipairs(if folder then folder:GetChildren() else {}) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if model:IsA("Model") and humanoid and root and humanoid.Health > 0 and (root.Position - origin).Magnitude <= range then
			table.insert(targets, { Model = model, Humanoid = humanoid, Root = root })
		end
	end
	table.sort(targets, function(a, b)
		return (a.Root.Position - origin).Magnitude < (b.Root.Position - origin).Magnitude
	end)
	return targets
end

-- Every orb shoots once, spread over the nearest enemies (Stormcaller: Lightning, faster)
local function fireVolley(player: Player, state: State, root: BasePart, stormcaller: boolean)
	local targets = findTargets(root.Position, HeroData.ORB_RANGE)
	if #targets == 0 or not damageHandler then
		return
	end
	local element = if stormcaller then "Lightning" else "Physical"
	local damage = HeroData.ORB_DAMAGE + PlayerData.getStats(player).FlatDamage * HeroData.ORB_FLAT_DAMAGE_SHARE
	local from = root.Position + Vector3.new(0, 2.5, 0)
	for index = 1, #state.Orbs do
		local target = targets[(index - 1) % #targets + 1]
		if target.Humanoid.Health > 0 then
			combatRemote:FireAllClients("OrbShot", from, target.Root.Position, element)
			damageHandler(player, target.Model, target.Humanoid, damage, element)
		end
	end
end

local function update(player: Player, state: State, deltaTime: number, now: number)
	local classId, variantId = PlayerData.getHero(player)
	local root = getRoot(player)

	if classId == "Warrior" and now - state.LastHitTime > HeroData.FURY_DECAY_DELAY then
		local decay = if variantId == "Berserker" then HeroData.BERSERKER_DECAY_PER_SECOND else HeroData.FURY_DECAY_PER_SECOND
		state.Fury = math.max(state.Fury - decay * deltaTime, 0)
	elseif classId == "Ranger" and root then
		local position = Vector3.new(root.Position.X, 0, root.Position.Z)
		local step = if state.LastPosition then (position - state.LastPosition).Magnitude else 0
		state.LastPosition = position
		if step > MOVING_THRESHOLD then
			state.StillTime = 0
			state.MovedDistance += math.min(step, MAX_STEP)
			while state.MovedDistance >= HeroData.MOMENTUM_STUDS_PER_STACK do
				state.MovedDistance -= HeroData.MOMENTUM_STUDS_PER_STACK
				state.Momentum = math.min(state.Momentum + 1, HeroData.MOMENTUM_MAX)
			end
		else
			state.StillTime += deltaTime
			if state.StillTime >= HeroData.MOMENTUM_STILL_TIME then
				state.Momentum = 0
				state.MovedDistance = 0
			end
		end

		-- Windrunner: faster walking. Chill / freeze (Ailments) own the speed while they last
		local character = root.Parent :: Model
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and not character:GetAttribute("Chilled") and not character:GetAttribute("Frozen") then
			state.BaseWalkSpeed = state.BaseWalkSpeed or humanoid.WalkSpeed
			local bonus = if variantId == "Windrunner" then state.Momentum * HeroData.WINDRUNNER_MOVE_SPEED else 0
			local speed = (state.BaseWalkSpeed or humanoid.WalkSpeed) * (1 + bonus)
			if math.abs(humanoid.WalkSpeed - speed) > 0.01 then
				humanoid.WalkSpeed = speed
			end
		end
	elseif classId == "Mystic" then
		for index = #state.Orbs, 1, -1 do
			if state.Orbs[index] <= now then
				table.remove(state.Orbs, index)
			end
		end
		if root and variantId ~= "Wardstone" and #state.Orbs > 0 and now >= state.NextVolley then
			local stormcaller = variantId == "Stormcaller"
			state.NextVolley = now + (if stormcaller then HeroData.STORMCALLER_INTERVAL else HeroData.ORB_INTERVAL)
			fireVolley(player, state, root, stormcaller)
		end
	end

	publish(player, state)
end

-- Class or path changed (PlayerData): start the mechanic over, and give back the normal walk speed
function HeroService.reset(player: Player)
	local old = states[player]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if old and old.BaseWalkSpeed and humanoid then
		humanoid.WalkSpeed = old.BaseWalkSpeed
	end
	states[player] = newState()
	publish(player, states[player])
end

function HeroService.start()
	local function onPlayerAdded(player: Player)
		-- Every spawn starts with an empty mechanic (and the new character's own walk speed)
		player.CharacterAdded:Connect(function()
			states[player] = newState()
			publish(player, states[player])
		end)
		getState(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)

	PlayerData.onHeroChanged(HeroService.reset)

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
					warn("[HeroService] Update error:", err)
				end
			end
		end
	end)
end

return HeroService
