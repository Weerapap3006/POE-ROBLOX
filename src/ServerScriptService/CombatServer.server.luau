-- ==========================================
-- COMBAT SERVER (Validation, Hitbox, Damage & Anti-Exploit)
-- Path: ServerScriptService.CombatServer
-- ==========================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local combatRemote = remotesFolder:WaitForChild("CombatRemote") :: RemoteEvent

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local SkillData = require(modulesFolder:WaitForChild("SkillData"))

-- Track cooldowns and combo per player on the Server (Anti-Exploit)
local playerCooldowns: { [Player]: number } = {}
local playerComboSteps: { [Player]: number } = {}

Players.PlayerRemoving:Connect(function(player: Player)
	playerCooldowns[player] = nil
	playerComboSteps[player] = nil
end)

-- ==========================================
-- HANDLE ATTACK REQUEST FROM CLIENT
-- ==========================================
combatRemote.OnServerEvent:Connect(function(player: Player, skillId: unknown, targetPosition: unknown)
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
	local now = os.clock()
	local lastTime = playerCooldowns[player] or 0
	-- Allow slight network tolerance (0.05s) for ping jitter
	if now - lastTime < (skill.Cooldown - 0.05) then
		return
	end
	playerCooldowns[player] = now

	-- Track combo step for visual replication to other players
	local step = playerComboSteps[player] or 1
	playerComboSteps[player] = if step == 1 then 2 else 1
	combatRemote:FireAllClients("ReplicateSlash", character, targetPosition, step)

	-- 3. Server-side Hitbox Detection (Prevents Kill-Aura / Reach Exploits)
	local flatAim = Vector3.new(targetPosition.X, rootPart.Position.Y, targetPosition.Z)
	local aimDir = flatAim - rootPart.Position
	local lookCF = if aimDir.Magnitude > 0.05
		then CFrame.lookAt(rootPart.Position, flatAim)
		else rootPart.CFrame

	local hitboxCFrame = lookCF * CFrame.new(0, 0, -skill.HitboxForwardOffset)

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local partsInBox = workspace:GetPartBoundsInBox(hitboxCFrame, skill.HitboxSize, overlapParams)

	-- Collect unique enemy models hit by this swing
	local hitModels: { [Model]: Humanoid } = {}
	for _, part in ipairs(partsInBox) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= character and not hitModels[model] then
			local enemyHumanoid = model:FindFirstChildOfClass("Humanoid")
			if enemyHumanoid and enemyHumanoid.Health > 0 then
				hitModels[model] = enemyHumanoid
			end
		end
	end

	-- 4. Server-side Damage Calculation & Health Reduction
	for enemyModel, enemyHumanoid in pairs(hitModels) do
		local baseDamage = math.random(skill.MinDamage, skill.MaxDamage)
		local isCrit = math.random() < skill.CritChance
		local finalDamage = if isCrit then math.round(baseDamage * skill.CritMultiplier) else baseDamage

		enemyHumanoid:TakeDamage(finalDamage)

		-- Auto-respawn TrainingDummy when its HP reaches 0 so you can keep testing
		if enemyHumanoid.Health <= 0 and enemyModel.Name == "TrainingDummy" then
			task.delay(1.2, function()
				if enemyHumanoid and enemyHumanoid.Parent then
					enemyHumanoid.Health = enemyHumanoid.MaxHealth
				end
			end)
		end

		-- 5. Notify Clients to show Floating Damage Numbers & Hit Flash
		combatRemote:FireAllClients("DamageDealt", enemyModel, finalDamage, isCrit)
	end
end)
