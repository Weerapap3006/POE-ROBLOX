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

local serverModules = ServerStorage:WaitForChild("Modules")
local PlayerData = require(serverModules:WaitForChild("PlayerData"))
local EnemyService = require(serverModules:WaitForChild("EnemyService"))
local PlayerResources = require(serverModules:WaitForChild("PlayerResources"))
local Ailments = require(serverModules:WaitForChild("Ailments"))

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

-- Unique living enemy models among the parts (other players are skipped: co-op, no friendly fire)
local function collectEnemies(parts: { BasePart }, ignore: Model?): { [Model]: Humanoid }
	local enemies: { [Model]: Humanoid } = {}
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= ignore and not enemies[model] and not Players:GetPlayerFromCharacter(model) then
			local enemyHumanoid = model:FindFirstChildOfClass("Humanoid")
			if enemyHumanoid and enemyHumanoid.Health > 0 then
				enemies[model] = enemyHumanoid
			end
		end
	end
	return enemies
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
	for enemyModel, enemyHumanoid in pairs(collectEnemies(parts, corpse)) do
		local amount = math.round(damage * Ailments.getDamageTakenMultiplier(enemyModel))
		damageEnemy(player, enemyModel, enemyHumanoid, amount, false, "Fire")
		Ailments.applyHit(enemyModel, enemyHumanoid, { Fire = amount }, function(burn: number)
			damageEnemy(player, enemyModel, enemyHumanoid, burn, false, "Fire")
		end)
	end
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
	if not skill then
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
	-- Cooldown is shortened by the AttackSpeed stat from equipped items
	local stats = PlayerData.getStats(player)
	local cooldowns = playerCooldowns[player] or {}
	playerCooldowns[player] = cooldowns
	local now = os.clock()
	local cooldown = PlayerStats.getCooldown(skill.Cooldown, stats.AttackSpeed)
	-- Allow slight network tolerance (0.05s) for ping jitter
	if now - (cooldowns[skillId] or 0) < (cooldown - 0.05) then
		return
	end
	-- Mana is paid only once the cooldown is ready (not enough = the skill doesn't fire, no cooldown starts)
	if not PlayerResources.spendMana(player, skill.ManaCost) then
		return
	end
	cooldowns[skillId] = now

	-- Track combo step (BasicSlash alternates left/right swings) for visual replication to other players
	local step = playerComboSteps[player] or 1
	if skillId == "BasicSlash" then
		playerComboSteps[player] = if step == 1 then 2 else 1
	end
	combatRemote:FireAllClients("ReplicateSkill", character, skillId, targetPosition, step)

	-- 3. Server-side Hitbox Detection (Prevents Kill-Aura / Reach Exploits)
	-- Stone runes socketed in this skill (RuneData): Reach = bigger area, Split = side slashes
	local runes = PlayerData.getSkillRunes(player, skillId)
	local area = if runes.Reach then RuneData.AREA_MULTIPLIER else 1

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local partsInBox: { BasePart } = {}
	if skill.Shape == "Radius" then
		-- Circle around the character (SpinSlash)
		partsInBox = workspace:GetPartBoundsInRadius(rootPart.Position, (skill.Radius or 0) * area, overlapParams)
	else
		-- Box in front of the character, facing the aim point (BasicSlash)
		local flatAim = Vector3.new(targetPosition.X, rootPart.Position.Y, targetPosition.Z)
		local aimDir = flatAim - rootPart.Position
		local lookCF = if aimDir.Magnitude > 0.05
			then CFrame.lookAt(rootPart.Position, flatAim)
			else rootPart.CFrame

		local baseSize = skill.HitboxSize or Vector3.one
		local boxSize = Vector3.new(baseSize.X * area, baseSize.Y, baseSize.Z * area)
		local forward = (skill.HitboxForwardOffset or 0) * area
		local angles = if runes.Split then { 0, RuneData.SPLIT_ANGLE, -RuneData.SPLIT_ANGLE } else { 0 }
		for _, angle in ipairs(angles) do
			local hitboxCFrame = lookCF * CFrame.Angles(0, math.rad(angle), 0) * CFrame.new(0, 0, -forward)
			for _, part in ipairs(workspace:GetPartBoundsInBox(hitboxCFrame, boxSize, overlapParams)) do
				table.insert(partsInBox, part)
			end
		end
	end

	-- Each enemy is hit once even if several split slashes reach it
	local hitModels = collectEnemies(partsInBox, character)

	-- Ember / Frost / Storm runes turn part of the physical damage into their element (scaled to 100% max)
	local conversions: { [string]: number } = {}
	local totalConversion = 0
	for runeId in pairs(runes) do
		local element = RuneData.Runes[runeId].Convert
		if element then
			conversions[element] = RuneData.CONVERT_PERCENT
			totalConversion += RuneData.CONVERT_PERCENT
		end
	end
	local conversionScale = if totalConversion > 1 then 1 / totalConversion else 1

	-- 4. Server-side Damage Calculation & Health Reduction
	-- Physical = skill roll + FlatDamage, elemental = item affixes + rune conversion; a crit multiplies all of it
	for enemyModel, enemyHumanoid in pairs(hitModels) do
		if enemyHumanoid.Health <= 0 then
			continue -- Already killed earlier in this swing (by a Detonation explosion)
		end
		local isCrit = math.random() < skill.CritChance
		local critMultiplier = if isCrit then skill.CritMultiplier else 1
		local rolledPhysical = (math.random(skill.MinDamage, skill.MaxDamage) + stats.FlatDamage) * critMultiplier
		local physical = rolledPhysical
		local elemental = {
			Fire = stats.FireDamage * critMultiplier,
			Cold = stats.ColdDamage * critMultiplier,
			Lightning = stats.LightningDamage * critMultiplier,
		}
		for element, percent in pairs(conversions) do
			local converted = rolledPhysical * percent * conversionScale
			elemental[element] += converted
			physical -= converted
		end
		-- Shocked enemies take more damage from everything
		local total = physical + elemental.Fire + elemental.Cold + elemental.Lightning
		local finalDamage = math.round(total * Ailments.getDamageTakenMultiplier(enemyModel))
		damageEnemy(player, enemyModel, enemyHumanoid, finalDamage, isCrit, nil)

		-- 5. The elemental parts inflict ailments (Ignite / Chill / Freeze / Shock); burns are credited to this player
		Ailments.applyHit(enemyModel, enemyHumanoid, elemental, function(amount: number)
			damageEnemy(player, enemyModel, enemyHumanoid, amount, false, "Fire")
		end)

		-- 6. Detonation rune: an enemy this hit killed explodes
		if runes.Detonation and enemyHumanoid.Health <= 0 then
			explodeCorpse(player, enemyModel, enemyHumanoid)
		end
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
end)
