-- ==========================================
-- COMBAT SERVER (Validation, Hitbox, Damage, Stone Rune Effects & Anti-Exploit)
-- Path: ServerScriptService.CombatServer
-- ==========================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local combatRemote = remotesFolder:WaitForChild("CombatRemote") :: RemoteEvent
local dodgeRemote = remotesFolder:WaitForChild("DodgeRemote") :: RemoteEvent

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local SkillData = require(modulesFolder:WaitForChild("SkillData"))
local PlayerStats = require(modulesFolder:WaitForChild("PlayerStats"))
local RuneData = require(modulesFolder:WaitForChild("RuneData"))
local SkillCast = require(modulesFolder:WaitForChild("SkillCast"))

local serverModules = ServerStorage:WaitForChild("Modules")
local PlayerData = require(serverModules:WaitForChild("PlayerData"))
local EnemyService = require(serverModules:WaitForChild("EnemyService"))
local PlayerResources = require(serverModules:WaitForChild("PlayerResources"))
local Ailments = require(serverModules:WaitForChild("Ailments"))
local HeroService = require(serverModules:WaitForChild("HeroService"))

-- Track cooldowns (per skill) and combo per player on the Server (Anti-Exploit)
local playerCooldowns: { [Player]: { [string]: number } } = {}
local playerComboSteps: { [Player]: number } = {}
local playerDodgeTimes: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	playerCooldowns[player] = nil
	playerComboSteps[player] = nil
	playerDodgeTimes[player] = nil
end)

-- Every bit of player damage to an enemy goes through here (skill hits and the burns they start).
-- element = colors the damage number ("Fire" for burns, nil for normal hits)
local function damageEnemy(player: Player, enemyModel: Model, enemyHumanoid: Humanoid, amount: number, isCrit: boolean, element: string?)
	-- Enemies spawned by EnemyService handle their own death (EXP, loot, respawn)
	if not EnemyService.applyDamage(enemyModel, amount, player) then
		enemyHumanoid:TakeDamage(amount)

		-- Auto-respawn TrainingDummy when its HP reaches 0 so you can keep testing
		if enemyHumanoid.Health <= 0 and enemyModel.Name == "TrainingDummy" then
			task.delay(1.2, function()
				if enemyHumanoid and enemyHumanoid.Parent then
					enemyHumanoid.Health = enemyHumanoid.MaxHealth
				end
			end)
		end
	end

	-- Notify Clients to show Floating Damage Numbers & Hit Flash
	combatRemote:FireAllClients("DamageDealt", enemyModel, amount, isCrit, element)
end

-- Detonation rune: the corpse blows up as Fire damage around it.
-- Explosion kills don't explode again, so it can't chain through a whole pack
local function explodeCorpse(player: Player, corpse: Model, corpseHumanoid: Humanoid)
	local corpseRoot = corpse:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not corpseRoot then
		return
	end
	local center = corpseRoot.Position
	combatRemote:FireAllClients("CorpseExplosion", center, RuneData.EXPLODE_RADIUS)

	local damage = corpseHumanoid.MaxHealth * RuneData.EXPLODE_PERCENT
	local parts = workspace:GetPartBoundsInRadius(center, RuneData.EXPLODE_RADIUS, OverlapParams.new())
	for enemyModel, enemyHumanoid in pairs(SkillCast.collectEnemies(parts, corpse)) do
		local amount = math.round(damage * Ailments.getDamageTakenMultiplier(enemyModel))
		damageEnemy(player, enemyModel, enemyHumanoid, amount, false, "Fire")
		Ailments.applyHit(enemyModel, enemyHumanoid, { Fire = amount }, function(burn: number)
			damageEnemy(player, enemyModel, enemyHumanoid, burn, false, "Fire")
		end)
	end
end

-- Hero mechanics (HeroService: Mystic Stone Orbs) hit enemies through the same damage + ailment path
HeroService.setDamageHandler(function(player: Player, enemyModel: Model, enemyHumanoid: Humanoid, amount: number, element: string)
	local finalDamage = math.round(amount * Ailments.getDamageTakenMultiplier(enemyModel))
	damageEnemy(player, enemyModel, enemyHumanoid, finalDamage, false, if element ~= "Physical" then element else nil)
	if element ~= "Physical" then
		Ailments.applyHit(enemyModel, enemyHumanoid, { [element] = finalDamage }, function(burn: number)
			damageEnemy(player, enemyModel, enemyHumanoid, burn, false, "Fire")
		end)
	end
end)

-- One skill hit on every enemy in `targets`. stats / runes / hero bonus are taken when the skill was used (a
-- projectile lands a moment later with the same numbers). Hits feed the Warrior's Fury
local function hitEnemies(
	player: Player,
	skill: SkillData.Skill,
	stats: PlayerStats.Stats,
	runes: { [string]: boolean },
	hero: HeroService.SkillBonus,
	targets: { [Model]: Humanoid }
)
	-- Ember / Frost / Storm runes turn part of a Physical skill's damage into their element (scaled to 100% max)
	local conversions: { [string]: number } = {}
	local totalConversion = 0
	for runeId in pairs(runes) do
		local element = RuneData.Runes[runeId].Convert
		if element and skill.Element == "Physical" then
			conversions[element] = RuneData.CONVERT_PERCENT
			totalConversion += RuneData.CONVERT_PERCENT
		end
	end
	local conversionScale = if totalConversion > 1 then 1 / totalConversion else 1

	-- The skill's own hit = roll + FlatDamage, as the skill's element (spells are Fire / Cold / Lightning);
	-- elemental damage from items comes on top; a crit (and the hero bonus) multiplies all of it
	local hitCount = 0
	for enemyModel, enemyHumanoid in pairs(targets) do
		if enemyHumanoid.Health <= 0 or not enemyModel.Parent then
			continue -- Already killed earlier in this hit (Detonation explosion) or while a projectile flew
		end
		hitCount += 1
		local isCrit = math.random() < skill.CritChance + hero.CritChance
		local critMultiplier = (if isCrit then skill.CritMultiplier else 1) * hero.DamageMultiplier
		local rolled = (math.random(skill.MinDamage, skill.MaxDamage) + stats.FlatDamage) * critMultiplier
		local physical = 0
		local elemental = {
			Fire = stats.FireDamage * critMultiplier,
			Cold = stats.ColdDamage * critMultiplier,
			Lightning = stats.LightningDamage * critMultiplier,
		}
		if skill.Element == "Physical" then
			physical = rolled
			for element, percent in pairs(conversions) do
				local converted = rolled * percent * conversionScale
				elemental[element] += converted
				physical -= converted
			end
		elseif elemental[skill.Element] then
			elemental[skill.Element] += rolled
		end
		-- Shocked enemies take more damage from everything
		local total = physical + elemental.Fire + elemental.Cold + elemental.Lightning
		local finalDamage = math.round(total * Ailments.getDamageTakenMultiplier(enemyModel))
		damageEnemy(player, enemyModel, enemyHumanoid, finalDamage, isCrit, nil)

		-- The elemental parts inflict ailments (Ignite / Chill / Freeze / Shock); burns are credited to this player
		Ailments.applyHit(enemyModel, enemyHumanoid, elemental, function(amount: number)
			damageEnemy(player, enemyModel, enemyHumanoid, amount, false, "Fire")
		end)

		-- Detonation rune: an enemy this hit killed explodes
		if runes.Detonation and enemyHumanoid.Health <= 0 then
			explodeCorpse(player, enemyModel, enemyHumanoid)
		end
	end
	HeroService.onEnemiesHit(player, hitCount)
end

-- ==========================================
-- HANDLE SKILL REQUEST FROM CLIENT
-- ==========================================
combatRemote.OnServerEvent:Connect(function(player: Player, skillId: any, targetPosition: any)
	-- 1. Validate arguments sent by Client (Never trust Client input types)
	if type(skillId) ~= "string" or typeof(targetPosition) ~= "Vector3" then
		return
	end

	local skill = SkillData[skillId]
	-- Only skills on the player's skill bar (Skill Stones they put there) can be used
	if not skill or not PlayerData.hasSkill(player, skillId) then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 or Ailments.isFrozen(character) then
		return
	end

	-- 2. Server-side Cooldown Check (Prevents Rapid-Fire / No-Cooldown Exploits)
	-- Cooldown is shortened by the AttackSpeed stat (items, passives) + Ranger Momentum (HeroService)
	local stats = PlayerData.getStats(player)
	local cooldowns = playerCooldowns[player] or {}
	playerCooldowns[player] = cooldowns
	local now = os.clock()
	local cooldown = PlayerStats.getCooldown(skill.Cooldown, stats.AttackSpeed + HeroService.getAttackSpeedBonus(player))
	-- Allow slight network tolerance (0.05s) for ping jitter
	if now - (cooldowns[skillId] or 0) < (cooldown - 0.05) then
		return
	end
	-- Mana is paid only once the cooldown is ready (not enough = the skill doesn't fire, no cooldown starts)
	if not PlayerResources.spendMana(player, skill.ManaCost) then
		return
	end
	cooldowns[skillId] = now
	-- Hero mechanic: full Fury / Berserker / Deadeye bonuses, mana spent toward Stone Orbs
	local hero = HeroService.useSkill(player, skill.ManaCost)

	-- Track combo step (BasicSlash alternates left/right swings) for visual replication to other players
	local step = playerComboSteps[player] or 1
	if skillId == "BasicSlash" then
		playerComboSteps[player] = if step == 1 then 2 else 1
	end
	combatRemote:FireAllClients("ReplicateSkill", character, skillId, targetPosition, step)

	-- 3. Server-side Hit Detection (Prevents Kill-Aura / Reach Exploits)
	-- Stone runes socketed in this skill (RuneData): Reach = bigger area / range, Split = side slashes / shots
	local runes = PlayerData.getSkillRunes(player, skillId)
	local area = if runes.Reach then RuneData.AREA_MULTIPLIER else 1

	-- Flat aim direction (falls back to where the character faces; also catches NaN aim points)
	local origin = rootPart.Position
	local flatAim = Vector3.new(targetPosition.X, origin.Y, targetPosition.Z)
	local aimDirection = if (flatAim - origin).Magnitude > 0.05
		then (flatAim - origin).Unit
		else Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit
	local lookCF = CFrame.lookAt(origin, origin + aimDirection)
	local angles = if runes.Split then { 0, RuneData.SPLIT_ANGLE, -RuneData.SPLIT_ANGLE } else { 0 }

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	-- Earthbreaker (Warrior at full Fury): everything around the player is hit by this skill too, once
	local pulseTargets: { [Model]: Humanoid } = {}
	if hero.PulseRadius then
		pulseTargets = SkillCast.collectEnemies(workspace:GetPartBoundsInRadius(origin, hero.PulseRadius, overlapParams), character)
	end
	local function withPulse(targets: { [Model]: Humanoid }): { [Model]: Humanoid }
		for model, enemyHumanoid in pairs(pulseTargets) do
			targets[model] = enemyHumanoid
		end
		return targets
	end

	if skill.Shape == "Radius" then
		-- Circle around the character (Spin Slash, Frost Nova) or in front of it (Ground Slam)
		local center = origin + aimDirection * (skill.CenterOffset or 0) * area
		local parts = workspace:GetPartBoundsInRadius(center, (skill.Radius or 0) * area, overlapParams)
		hitEnemies(player, skill, stats, runes, hero, withPulse(SkillCast.collectEnemies(parts, character)))
	elseif skill.Shape == "Box" then
		-- Box in front of the character, facing the aim point (Slash). Each enemy is hit once even if several
		-- split slashes reach it
		local baseSize = skill.HitboxSize or Vector3.one
		local boxSize = Vector3.new(baseSize.X * area, baseSize.Y, baseSize.Z * area)
		local forward = (skill.HitboxForwardOffset or 0) * area
		local parts: { BasePart } = {}
		for _, angle in ipairs(angles) do
			local hitboxCFrame = lookCF * CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(0, 0, -forward)
			for _, part in ipairs(workspace:GetPartBoundsInBox(hitboxCFrame, boxSize, overlapParams)) do
				table.insert(parts, part)
			end
		end
		hitEnemies(player, skill, stats, runes, hero, withPulse(SkillCast.collectEnemies(parts, character)))
	elseif skill.Shape == "Projectile" then
		-- Flies to the first enemy / wall / max range, damage lands when it gets there. Explosive projectiles
		-- (Fireball) hit everything around where they land. Split shots never hit the same enemy twice
		local alreadyHit: { [Model]: boolean } = {}
		if next(pulseTargets) then
			hitEnemies(player, skill, stats, runes, hero, pulseTargets) -- The ground shakes right away
			for model in pairs(pulseTargets) do
				alreadyHit[model] = true
			end
		end
		for _, angle in ipairs(angles) do
			local direction = (lookCF * CFrame.Angles(0, math.rad(angle), 0)).LookVector
			local landing, distance, target =
				SkillCast.castProjectile(origin, direction, (skill.Range or 0) * area, skill.Width or 1, character)
			local targets: { [Model]: Humanoid } = {}
			if skill.ExplosionRadius then
				local parts = workspace:GetPartBoundsInRadius(landing, skill.ExplosionRadius * area, overlapParams)
				targets = SkillCast.collectEnemies(parts, character)
			elseif target then
				local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
				if targetHumanoid then
					targets[target] = targetHumanoid
				end
			end
			for model in pairs(targets) do
				if alreadyHit[model] then
					targets[model] = nil
				else
					alreadyHit[model] = true
				end
			end
			if next(targets) then
				task.delay(distance / (skill.Speed or 100), hitEnemies, player, skill, stats, runes, hero, targets)
			end
		end
	elseif skill.Shape == "Chain" then
		-- Strikes the enemy nearest the aim point, then jumps from enemy to enemy (Arc)
		local chain = SkillCast.findChain(origin, targetPosition, (skill.Range or 0) * area, skill.Chains or 0, (skill.ChainRange or 0) * area)
		local targets: { [Model]: Humanoid } = {}
		for _, model in ipairs(chain) do
			local targetHumanoid = model:FindFirstChildOfClass("Humanoid")
			if targetHumanoid then
				targets[model] = targetHumanoid
			end
		end
		hitEnemies(player, skill, stats, runes, hero, withPulse(targets))
	end
end)

-- ==========================================
-- HANDLE DODGE ROLL FROM CLIENT
-- ==========================================
-- The client moves its own character; the server only grants the invulnerability window (after its own cooldown check)
dodgeRemote.OnServerEvent:Connect(function(player: Player, direction: any)
	if typeof(direction) ~= "Vector3" then
		return
	end
	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if not (flatDirection.Magnitude > 0.01) then -- Also rejects NaN
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 or Ailments.isFrozen(character) then
		return
	end

	local now = os.clock()
	if now - (playerDodgeTimes[player] or -math.huge) < PlayerStats.DODGE_COOLDOWN - 0.05 then
		return
	end
	playerDodgeTimes[player] = now

	-- EnemyService ignores hits on this character until then (server clock, only compared on the server)
	character:SetAttribute("InvulnerableUntil", now + PlayerStats.DODGE_INVULNERABLE_TIME)
	dodgeRemote:FireAllClients(character) -- Everyone else plays the roll pose
	HeroService.onDodge(player) -- Ranger: Momentum
end)
