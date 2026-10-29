-- ==========================================
-- COMBAT CLIENT (Mouse Aiming, Input, VFX & Damage Numbers)
-- Path: StarterPlayer.StarterPlayerScripts.CombatClient
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local combatRemote = remotesFolder:WaitForChild("CombatRemote") :: RemoteEvent

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local SkillData = require(modulesFolder:WaitForChild("SkillData"))

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local lastAttackTime = 0
local comboStep = 1
local currentMouseWorldPos = Vector3.zero
local isHoldingAttack = false

-- Raycast parameters (ignore player's own character and VFX)
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

-- ==========================================
-- 1. MOUSE RAYCAST & CHARACTER AIMING
-- ==========================================
local function getMouseWorldPosition(rootPosition: Vector3): Vector3
	local mouseLocation = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	if player.Character then
		raycastParams.FilterDescendantsInstances = { player.Character }
	end

	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500, raycastParams)
	if result then
		return result.Position
	end

	-- Fallback: intersect with horizontal plane at character's height
	if math.abs(unitRay.Direction.Y) > 0.001 then
		local t = (rootPosition.Y - unitRay.Origin.Y) / unitRay.Direction.Y
		if t > 0 then
			return unitRay.Origin + unitRay.Direction * t
		end
	end

	return rootPosition + Vector3.new(0, 0, -10)
end

local function updateMouseAiming(deltaTime: number)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	-- Disable Roblox's default AutoRotate so character always faces the mouse cursor
	humanoid.AutoRotate = false

	currentMouseWorldPos = getMouseWorldPosition(rootPart.Position)

	-- Flatten Y so character only rotates horizontally (Y-axis)
	local lookTarget = Vector3.new(currentMouseWorldPos.X, rootPart.Position.Y, currentMouseWorldPos.Z)
	local direction = lookTarget - rootPart.Position

	if direction.Magnitude > 0.1 then
		local targetRotation = CFrame.lookAt(rootPart.Position, lookTarget).Rotation
		local turnAlpha = 1 - math.exp(-20 * deltaTime)
		rootPart.CFrame = CFrame.new(rootPart.Position) * rootPart.CFrame.Rotation:Lerp(targetRotation, turnAlpha)
	end
end

RunService:BindToRenderStep("MouseAimRotation", Enum.RenderPriority.Character.Value + 1, updateMouseAiming)

-- ==========================================
-- 2. PROCEDURAL SWING & CEL-SHADED SLASH VFX
-- ==========================================
local SWING_DURATION = 0.18 -- Seconds for the arm/waist to swing out and back

-- The Animator rewrites Motor6D.Transform every frame before PreSimulation, so a pose set once
-- gets overwritten immediately. Active swings are re-applied each PreSimulation on top of the animated pose.
type SwingState = {
	startTime: number,
	offset: CFrame, -- Peak rotation layered on top of the animated pose
	basePose: CFrame, -- Pose underneath the swing (what the Animator wrote this frame)
	lastWritten: CFrame?, -- Our previous write, used to detect whether the Animator wrote since
}
local activeSwings: { [Motor6D]: SwingState } = {}

local function startSwing(motor: Motor6D?, offset: CFrame)
	if not motor then
		return
	end
	-- Restarting mid-swing: keep the previous base pose, since Transform currently holds a half-swung pose
	local previous = activeSwings[motor]
	activeSwings[motor] = {
		startTime = os.clock(),
		offset = offset,
		basePose = if previous then previous.basePose else motor.Transform,
		lastWritten = if previous then previous.lastWritten else nil,
	}
end

RunService.PreSimulation:Connect(function()
	local now = os.clock()
	for motor, swing in pairs(activeSwings) do
		-- If Transform still holds our last write, no animation touched this joint, so keep the stored base pose
		if motor.Transform ~= swing.lastWritten then
			swing.basePose = motor.Transform
		end

		local t = (now - swing.startTime) / SWING_DURATION
		if t >= 1 or not motor:IsDescendantOf(workspace) then
			motor.Transform = swing.basePose
			activeSwings[motor] = nil
		else
			-- Swing out to the peak pose and back (weight 0 -> 1 -> 0)
			local weight = math.sin(math.pi * t)
			local pose = swing.basePose * CFrame.identity:Lerp(swing.offset, weight)
			motor.Transform = pose
			swing.lastWritten = pose
		end
	end
end)

local function playSlashVFX(character: Model, aimPoint: Vector3, currentCombo: number)
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	-- Procedural upper-body slash motion on RightShoulder Motor6D
	local rightUpperArm = character:FindFirstChild("RightUpperArm")
	local rightShoulder = rightUpperArm and rightUpperArm:FindFirstChild("RightShoulder") :: Motor6D?
	local upperTorso = character:FindFirstChild("UpperTorso")
	local waist = upperTorso and upperTorso:FindFirstChild("Waist") :: Motor6D?

	local swingAngle = if currentCombo == 1 then math.rad(110) else math.rad(75)
	local sideAngle = if currentCombo == 1 then math.rad(-35) else math.rad(35)
	startSwing(rightShoulder, CFrame.Angles(swingAngle, sideAngle, 0))

	local twist = if currentCombo == 1 then math.rad(25) else math.rad(-25)
	startSwing(waist, CFrame.Angles(0, twist, 0))

	-- Create Anime Cel-Shaded Crescent Slash Arc in front of character
	local flatAim = Vector3.new(aimPoint.X, rootPart.Position.Y, aimPoint.Z)
	local lookCF = CFrame.lookAt(rootPart.Position, flatAim)
	local tiltAngle = if currentCombo == 1 then math.rad(15) else math.rad(-15)

	local slashPart = Instance.new("Part")
	slashPart.Name = "SlashArcVFX"
	slashPart.Anchored = true
	slashPart.CanCollide = false
	slashPart.CanQuery = false
	slashPart.Material = Enum.Material.Neon
	slashPart.Color = Color3.fromRGB(120, 210, 255) -- Anime cyan energy slash
	slashPart.Size = Vector3.new(2, 0.25, 2)
	slashPart.CFrame = lookCF * CFrame.new(0, 0.5, -2.5) * CFrame.Angles(0, 0, tiltAngle)

	-- Add CylinderMesh flattened into a crescent blade wave
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1.2, 0.15, 0.7)
	mesh.Parent = slashPart

	-- Cel-shaded black ink outline on the slash wave
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.2
	hl.FillColor = Color3.fromRGB(220, 245, 255)
	hl.OutlineColor = Color3.fromRGB(15, 25, 45)
	hl.OutlineTransparency = 0
	hl.Parent = slashPart

	slashPart.Parent = workspace

	-- Tween the slash wave forward and wider, then fade out
	local targetCF = lookCF * CFrame.new(0, 0.5, -6.0) * CFrame.Angles(0, 0, tiltAngle)
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local tween = TweenService:Create(slashPart, tweenInfo, {
		CFrame = targetCF,
		Size = Vector3.new(9.5, 0.25, 6.5),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(slashPart, 0.22)
end

-- ==========================================
-- 3. FLOATING DAMAGE NUMBERS & HIT FLASH
-- ==========================================
local function showHitFeedback(enemyModel: Model, damage: number, isCrit: boolean)
	local rootPart = enemyModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	-- Brief white anime impact flash on the hit enemy
	local hl = enemyModel:FindFirstChildOfClass("Highlight")
	if hl then
		local oldFillTrans = hl.FillTransparency
		local oldFillColor = hl.FillColor
		hl.FillColor = Color3.fromRGB(255, 255, 255)
		hl.FillTransparency = 0.15
		task.delay(0.1, function()
			if hl then
				hl.FillColor = oldFillColor
				hl.FillTransparency = oldFillTrans
			end
		end)
	end

	-- Create floating BillboardGui for Damage Number
	local attachment = Instance.new("Attachment")
	local randomOffset = Vector3.new(math.random(-15, 15) / 10, math.random(15, 30) / 10, math.random(-15, 15) / 10)
	attachment.Position = randomOffset
	attachment.Parent = rootPart

	local billboard = Instance.new("BillboardGui")
	billboard.Size = if isCrit then UDim2.fromOffset(140, 60) else UDim2.fromOffset(100, 45)
	billboard.AlwaysOnTop = true
	billboard.Adornee = attachment
	billboard.Parent = attachment

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = if isCrit then tostring(damage) .. "!" else tostring(damage)
	label.TextColor3 = if isCrit then Color3.fromRGB(255, 215, 45) else Color3.fromRGB(255, 255, 255)
	label.TextStrokeColor3 = Color3.fromRGB(15, 15, 20)
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	-- Float upward and fade out
	local moveTween = TweenService:Create(attachment, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = randomOffset + Vector3.new(0, 3.5, 0),
	})
	local fadeTween = TweenService:Create(label, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	moveTween:Play()
	fadeTween:Play()
	Debris:AddItem(attachment, 0.7)
end

-- ==========================================
-- 4. INPUT LISTENER (LEFT CLICK / HOLD TO ATTACK)
-- ==========================================
local function tryBasicSlash()
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	-- Client-side cooldown check for responsiveness
	local skill = SkillData.BasicSlash
	local now = os.clock()
	if now - lastAttackTime < skill.Cooldown then
		return
	end
	lastAttackTime = now

	-- Snap character rotation immediately toward mouse when attacking
	local aimPoint = getMouseWorldPosition(rootPart.Position)
	local flatTarget = Vector3.new(aimPoint.X, rootPart.Position.Y, aimPoint.Z)
	if (flatTarget - rootPart.Position).Magnitude > 0.1 then
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, flatTarget)
	end

	-- 1) Play instant local Slash VFX & Swing animation (0 ms delay)
	playSlashVFX(character, aimPoint, comboStep)
	comboStep = if comboStep == 1 then 2 else 1

	-- 2) Tell Server we used BasicSlash aiming at aimPoint
	combatRemote:FireServer("BasicSlash", aimPoint)
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isHoldingAttack = true
		tryBasicSlash()
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isHoldingAttack = false
	end
end)

RunService.Heartbeat:Connect(function()
	if isHoldingAttack then
		tryBasicSlash()
	end
end)

-- Listen for Server replication (damage numbers & other players' slashes)
combatRemote.OnClientEvent:Connect(function(action: string, ...)
	if action == "DamageDealt" then
		local enemyModel: Model, damage: number, isCrit: boolean = ...
		if enemyModel then
			showHitFeedback(enemyModel, damage, isCrit)
		end
	elseif action == "ReplicateSlash" then
		local attackerChar: Model, aimPoint: Vector3, step: number = ...
		if attackerChar and attackerChar ~= player.Character then
			playSlashVFX(attackerChar, aimPoint, step)
		end
	end
end)
