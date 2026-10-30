-- ==========================================
-- AILMENTS (Ignite / Chill / Freeze / Shock from elemental hits)
-- Path: ServerStorage.Modules.Ailments
-- ==========================================
-- Works on any Model with a Humanoid: enemies hit by players (CombatServer) and players hit by elemental enemy
-- attacks (EnemyService). Numbers live in ReplicatedStorage.Modules.Elements. Clients see active ailments as
-- true attributes on the Model: Ignited, Chilled, Frozen, Shocked (HudClient shows them, CombatClient blocks
-- attacking / rolling while Frozen)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Elements = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Elements"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
local TICK = 0.1 -- Seconds between updates (ailments end on time, chill / freeze speed is kept up to date)
local BURN_INTERVAL = 0.5 -- Burn damage is dealt (and shown as a number) this often

type Target = {
	Humanoid: Humanoid,
	BaseWalkSpeed: number, -- Speed before any chill / freeze, restored when they end
	IgniteRemaining: number, -- Burn damage still to deal
	IgniteDps: number,
	IgniteCarry: number, -- Burn damage built up since the last burn tick
	NextBurnTime: number,
	DealBurn: ((amount: number) -> ())?, -- Deals burn damage, given by whoever ignited it (credits the right player)
	ChillUntil: number,
	FreezeUntil: number,
	ShockUntil: number,
	ShockEffect: number, -- Extra damage taken while shocked (0.2 = +20%)
}

local Ailments = {}

local targets: { [Model]: Target } = {}
local running = false

-- ==========================================
-- 1. HELPERS
-- ==========================================
local function setFlag(model: Model, name: string, active: boolean)
	local value = if active then true else nil
	if model:GetAttribute(name) ~= value then
		model:SetAttribute(name, value)
	end
end

-- Movement speed + the attributes clients read
local function refresh(model: Model, target: Target, now: number)
	local frozen = now < target.FreezeUntil
	local chilled = now < target.ChillUntil
	local speed = if frozen then 0 elseif chilled then target.BaseWalkSpeed * (1 - Elements.CHILL_SLOW) else target.BaseWalkSpeed
	if target.Humanoid.WalkSpeed ~= speed then
		target.Humanoid.WalkSpeed = speed
	end
	setFlag(model, "Ignited", target.IgniteRemaining > 0)
	setFlag(model, "Chilled", chilled)
	setFlag(model, "Frozen", frozen)
	setFlag(model, "Shocked", now < target.ShockUntil)
end

local function isActive(target: Target, now: number): boolean
	return target.IgniteRemaining > 0 or now < target.ChillUntil or now < target.FreezeUntil or now < target.ShockUntil
end

local function getTarget(model: Model, humanoid: Humanoid): Target
	local target = targets[model]
	if not target then
		target = {
			Humanoid = humanoid,
			BaseWalkSpeed = humanoid.WalkSpeed,
			IgniteRemaining = 0,
			IgniteDps = 0,
			IgniteCarry = 0,
			NextBurnTime = 0,
			DealBurn = nil,
			ChillUntil = 0,
			FreezeUntil = 0,
			ShockUntil = 0,
			ShockEffect = 0,
		}
		targets[model] = target
	end
	return target
end

-- ==========================================
-- 2. EVERY TICK: BURN DAMAGE, ENDING AILMENTS
-- ==========================================
local function update(model: Model, target: Target, deltaTime: number, now: number)
	local humanoid = target.Humanoid
	if not model.Parent or humanoid.Parent ~= model or humanoid.Health <= 0 then
		-- Died or removed: drop it (a dead body doesn't need its speed back)
		targets[model] = nil
		for _, label in ipairs(Elements.AilmentLabels) do
			setFlag(model, label.Attribute, false)
		end
		return
	end

	if target.IgniteRemaining > 0 then
		local burn = math.min(target.IgniteDps * deltaTime, target.IgniteRemaining)
		target.IgniteRemaining -= burn
		target.IgniteCarry += burn
		if now >= target.NextBurnTime or target.IgniteRemaining <= 0 then
			target.NextBurnTime = now + BURN_INTERVAL
			-- Shock makes the burn hurt more too
			local amount = math.floor(target.IgniteCarry * Ailments.getDamageTakenMultiplier(model) + 0.5)
			target.IgniteCarry = 0
			if amount >= 1 and target.DealBurn then
				target.DealBurn(amount)
			end
		end
	end

	refresh(model, target, now)
	if not isActive(target, now) then
		targets[model] = nil -- All ended: refresh already put the speed back and cleared the attributes
	end
end

local function ensureRunning()
	if running then
		return
	end
	running = true
	task.spawn(function()
		local lastTime = os.clock()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local deltaTime = now - lastTime
			lastTime = now
			for model, target in pairs(targets) do
				local ok, err = pcall(update, model, target, deltaTime, now)
				if not ok then
					targets[model] = nil
					warn("[Ailments] Update error:", err)
				end
			end
		end
	end)
end

-- ==========================================
-- 3. PUBLIC API (used by CombatServer / EnemyService)
-- ==========================================
-- A hit landed: damage = how much of it was each element (after resistances).
-- dealBurn deals ignite damage later, so the kill / EXP goes to whoever started the burn
function Ailments.applyHit(model: Model, humanoid: Humanoid, damage: { [string]: number }, dealBurn: (amount: number) -> ())
	local fire = damage.Fire or 0
	local cold = damage.Cold or 0
	local lightning = damage.Lightning or 0
	if (fire <= 0 and cold <= 0 and lightning <= 0) or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	local target = getTarget(model, humanoid)

	if fire > 0 then
		local total = fire * Elements.IGNITE_DAMAGE_PERCENT
		local dps = total / Elements.IGNITE_DURATION
		-- Only the strongest burn counts: a weaker ignite doesn't replace one that is still burning
		if target.IgniteRemaining <= 0 or dps >= target.IgniteDps then
			if target.IgniteRemaining <= 0 then
				target.NextBurnTime = now + BURN_INTERVAL
			end
			target.IgniteRemaining = total
			target.IgniteDps = dps
			target.DealBurn = dealBurn
		end
	end

	if cold > 0 then
		target.ChillUntil = math.max(target.ChillUntil, now + Elements.CHILL_DURATION)
		if cold >= humanoid.MaxHealth * Elements.FREEZE_THRESHOLD then
			target.FreezeUntil = math.max(target.FreezeUntil, now + Elements.FREEZE_DURATION)
		end
	end

	if lightning > 0 then
		local effect = math.clamp(lightning / humanoid.MaxHealth * Elements.SHOCK_SCALE, Elements.SHOCK_MIN, Elements.SHOCK_MAX)
		-- A weaker shock doesn't replace (or extend) a stronger one that is still active
		if now >= target.ShockUntil or effect >= target.ShockEffect then
			target.ShockEffect = effect
			target.ShockUntil = now + Elements.SHOCK_DURATION
		end
	end

	refresh(model, target, now)
	ensureRunning()
end

-- 1 normally, more while shocked. Multiply incoming damage by this
function Ailments.getDamageTakenMultiplier(model: Model): number
	local target = targets[model]
	if target and os.clock() < target.ShockUntil then
		return 1 + target.ShockEffect
	end
	return 1
end

-- Frozen: can't move (speed 0), attack or dodge
function Ailments.isFrozen(model: Model): boolean
	local target = targets[model]
	return target ~= nil and os.clock() < target.FreezeUntil
end

return Ailments
