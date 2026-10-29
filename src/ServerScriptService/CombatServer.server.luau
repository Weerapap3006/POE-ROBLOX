-- ==========================================
-- COMBAT SERVER (Validation, Hitbox, Damage & Anti-Exploit)
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

local serverModules = ServerStorage:WaitForChild("Modules")
local PlayerData = require(serverModules:WaitForChild("PlayerData"))
local EnemyService = require(serverModules:WaitForChild("EnemyService"))
local PlayerResources = require(serverModules:WaitForChild("PlayerResources"))

-- Track cooldowns (per skill) and combo per player on the Server (Anti-Exploit)
local playerCooldowns: { [Player]: { [string]: number } } = {}
local playerComboSteps: { [Player]: number } = {}
local playerDodgeTimes: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	playerCooldowns[player] = nil
	playerComboSteps[player] = nil
	playerDodgeTimes[player] = nil
end)

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
	if not humanoid or not rootPart or humanoid.Health <= 0 then
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
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local partsInBox: { BasePart }
	if skill.Shape == "Radius" then
		-- Circle around the character (SpinSlash)
		partsInBox = workspace:GetPartBoundsInRadius(rootPart.Position, skill.Radius or 0, overlapParams)
	else
		-- Box in front of the character, facing the aim point (BasicSlash)
		local flatAim = Vector3.new(targetPosition.X, rootPart.Position.Y, targetPosition.Z)
		local aimDir = flatAim - rootPart.Position
		local lookCF = if aimDir.Magnitude > 0.05
			then CFrame.lookAt(rootPart.Position, flatAim)
			else rootPart.CFrame

		local hitboxCFrame = lookCF * CFrame.new(0, 0, -(skill.HitboxForwardOffset or 0))
		partsInBox = workspace:GetPartBoundsInBox(hitboxCFrame, skill.HitboxSize or Vector3.one, overlapParams)
	end

	-- Collect unique enemy models hit by this skill (other players are skipped: co-op, no friendly fire)
	local hitModels: { [Model]: Humanoid } = {}
	for _, part in ipairs(partsInBox) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= character and not hitModels[model] and not Players:GetPlayerFromCharacter(model) then
			local enemyHumanoid = model:FindFirstChildOfClass("Humanoid")
			if enemyHumanoid and enemyHumanoid.Health > 0 then
				hitModels[model] = enemyHumanoid
			end
		end
	end

	-- 4. Server-side Damage Calculation & Health Reduction
	for enemyModel, enemyHumanoid in pairs(hitModels) do
		local baseDamage = math.random(skill.MinDamage, skill.MaxDamage) + stats.FlatDamage
		local isCrit = math.random() < skill.CritChance
		local finalDamage = if isCrit then math.round(baseDamage * skill.CritMultiplier) else baseDamage

		-- Enemies spawned by EnemyService handle their own death (EXP, loot, respawn)
		if not EnemyService.applyDamage(enemyModel, finalDamage, player) then
			enemyHumanoid:TakeDamage(finalDamage)

			-- Auto-respawn TrainingDummy when its HP reaches 0 so you can keep testing
			if enemyHumanoid.Health <= 0 and enemyModel.Name == "TrainingDummy" then
				task.delay(1.2, function()
					if enemyHumanoid and enemyHumanoid.Parent then
						enemyHumanoid.Health = enemyHumanoid.MaxHealth
					end
				end)
			end
		end

		-- 5. Notify Clients to show Floating Damage Numbers & Hit Flash
		combatRemote:FireAllClients("DamageDealt", enemyModel, finalDamage, isCrit)
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
	if not character or not humanoid or humanoid.Health <= 0 then
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
