-- ==========================================
-- COMBAT CLIENT (Aiming, Skill Input & Skill Bar, VFX, Enemy Telegraphs & Damage Numbers)
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
local PlayerStats = require(modulesFolder:WaitForChild("PlayerStats"))
local Ui = require(modulesFolder:WaitForChild("Ui"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
-- Skill bar order on screen. Inputs = mouse buttons / keys for the skill (mobile taps the button instead)
local SKILL_BAR: { { SkillId: string, KeyText: string, Inputs: { EnumItem } } } = {
	{ SkillId = "BasicSlash", KeyText = "คลิกซ้าย", Inputs = { Enum.UserInputType.MouseButton1 } },
	{ SkillId = "SpinSlash", KeyText = "คลิกขวา / Q", Inputs = { Enum.UserInputType.MouseButton2, Enum.KeyCode.Q } },
}
local TOUCH_AUTO_AIM_RANGE = 25 -- Mobile: skills aim at the nearest enemy within this many studs
local SLASH_COLOR = Color3.fromRGB(120, 210, 255) -- Anime cyan energy slash
local ENEMY_ATTACK_COLOR = Color3.fromRGB(255, 60, 50)
local OUTLINE_COLOR = Color3.fromRGB(15, 15, 20)
local PLAYER_HURT_COLOR = Color3.fromRGB(255, 80, 80)

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local lastUseTimes: { [string]: number } = {}
local heldSkills: { [string]: boolean } = {} -- Holding the button keeps attacking
local comboStep = 1
local currentMouseWorldPos = Vector3.zero
local isTouchOnly = Ui.isTouchOnly()

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

-- Mobile has no cursor: aim at the nearest living enemy in range, otherwise straight ahead
local function getTouchAimPoint(rootPart: BasePart): Vector3
	local bestPosition = rootPart.Position + rootPart.CFrame.LookVector * 10
	local bestDistance = TOUCH_AUTO_AIM_RANGE
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	if enemiesFolder then
		for _, enemy in ipairs(enemiesFolder:GetChildren()) do
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			local enemyRoot = enemy:FindFirstChild("HumanoidRootPart") :: BasePart?
			if humanoid and enemyRoot and humanoid.Health > 0 then
				local distance = (enemyRoot.Position - rootPart.Position).Magnitude
				if distance < bestDistance then
					bestDistance = distance
					bestPosition = enemyRoot.Position
				end
			end
		end
	end
	return bestPosition
end

local function getAimPoint(rootPart: BasePart): Vector3
	if isTouchOnly then
		return getTouchAimPoint(rootPart)
	end
	return getMouseWorldPosition(rootPart.Position)
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

	-- Mobile: face the walking direction (thumbstick) instead, skills auto-aim
	if isTouchOnly then
		humanoid.AutoRotate = true
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
-- 2. PROCEDURAL SWING & CEL-SHADED SKILL VFX
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

local function getSwingMotors(character: Model): (Motor6D?, Motor6D?)
	local rightUpperArm = character:FindFirstChild("RightUpperArm")
	local rightShoulder = rightUpperArm and rightUpperArm:FindFirstChild("RightShoulder") :: Motor6D?
	local upperTorso = character:FindFirstChild("UpperTorso")
	local waist = upperTorso and upperTorso:FindFirstChild("Waist") :: Motor6D?
	return rightShoulder, waist
end

-- Anime cel-shaded crescent wave that flies forward from lookCF and fades out (scale 1 = player size)
local function spawnCrescent(lookCF: CFrame, tiltAngle: number, color: Color3, scale: number)
	local slashPart = Instance.new("Part")
	slashPart.Name = "SlashArcVFX"
	slashPart.Anchored = true
	slashPart.CanCollide = false
	slashPart.CanQuery = false
	slashPart.Material = Enum.Material.Neon
	slashPart.Color = color
	slashPart.Size = Vector3.new(2 * scale, 0.25, 2 * scale)
	slashPart.CFrame = lookCF * CFrame.new(0, 0.5 * scale, -2.5 * scale) * CFrame.Angles(0, 0, tiltAngle)

	-- Sphere mesh flattened into a crescent blade wave
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1.2, 0.15, 0.7)
	mesh.Parent = slashPart

	-- Cel-shaded black ink outline on the slash wave
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 0.2
	hl.FillColor = color:Lerp(Color3.new(1, 1, 1), 0.7)
	hl.OutlineColor = OUTLINE_COLOR
	hl.OutlineTransparency = 0
	hl.Parent = slashPart

	slashPart.Parent = workspace

	-- Tween the slash wave forward and wider, then fade out
	local targetCF = lookCF * CFrame.new(0, 0.5 * scale, -6.0 * scale) * CFrame.Angles(0, 0, tiltAngle)
	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local tween = TweenService:Create(slashPart, tweenInfo, {
		CFrame = targetCF,
		Size = Vector3.new(9.5 * scale, 0.25, 6.5 * scale),
		Transparency = 1,
	})
	tween:Play()
	Debris:AddItem(slashPart, 0.22)
end

-- Flat neon disc lying on the ground (cylinder turned upright), used for rings and warning circles
local function makeDisc(center: Vector3, diameter: number, color: Color3, transparency: number): Part
	local disc = Instance.new("Part")
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.Neon
	disc.Color = color
	disc.Transparency = transparency
	disc.Size = Vector3.new(0.2, diameter, diameter)
	disc.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = workspace
	return disc
end

local function getGroundBelow(character: Model, rootPart: BasePart): Vector3
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hipHeight = if humanoid then humanoid.HipHeight else 2
	return rootPart.Position - Vector3.new(0, hipHeight + rootPart.Size.Y / 2, 0)
end

-- BasicSlash: arm swing + waist twist, alternating left/right each combo step
local function playSlashVFX(character: Model, aimPoint: Vector3, currentCombo: number)
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	local rightShoulder, waist = getSwingMotors(character)
	local swingAngle = if currentCombo == 1 then math.rad(110) else math.rad(75)
	local sideAngle = if currentCombo == 1 then math.rad(-35) else math.rad(35)
	startSwing(rightShoulder, CFrame.Angles(swingAngle, sideAngle, 0))

	local twist = if currentCombo == 1 then math.rad(25) else math.rad(-25)
	startSwing(waist, CFrame.Angles(0, twist, 0))

	local flatAim = Vector3.new(aimPoint.X, rootPart.Position.Y, aimPoint.Z)
	if (flatAim - rootPart.Position).Magnitude < 0.1 then
		flatAim = rootPart.Position + rootPart.CFrame.LookVector
	end
	local tiltAngle = if currentCombo == 1 then math.rad(15) else math.rad(-15)
	spawnCrescent(CFrame.lookAt(rootPart.Position, flatAim), tiltAngle, SLASH_COLOR, 1)
end

-- SpinSlash: upper body whirls around while a ring wave expands to the skill radius
local function playSpinVFX(character: Model, radius: number)
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	local rightShoulder, waist = getSwingMotors(character)
	startSwing(waist, CFrame.Angles(0, math.rad(170), 0))
	startSwing(rightShoulder, CFrame.Angles(math.rad(90), 0, 0))

	local ring = makeDisc(getGroundBelow(character, rootPart) + Vector3.new(0, 0.6, 0), 2, SLASH_COLOR, 0.2)
	ring.Name = "SpinSlashVFX"
	TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.3)
end

local function playSkillVFX(character: Model, skillId: string, aimPoint: Vector3, step: number)
	local skill = SkillData[skillId]
	if not skill then
		return
	end
	if skill.Shape == "Radius" then
		playSpinVFX(character, skill.Radius or 10)
	else
		playSlashVFX(character, aimPoint, step)
	end
end

-- ==========================================
-- 3. FLOATING DAMAGE NUMBERS & HIT FLASH
-- ==========================================
local function showHitFeedback(targetModel: Model, damage: number, isCrit: boolean)
	local rootPart = targetModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	-- Brief white anime impact flash on the hit target
	local hl = targetModel:FindFirstChildOfClass("Highlight")
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

	-- Players taking damage get red numbers, enemies white (gold on crit)
	local isPlayerHurt = Players:GetPlayerFromCharacter(targetModel) ~= nil
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = if isCrit then tostring(damage) .. "!" else tostring(damage)
	label.TextColor3 = if isPlayerHurt
		then PLAYER_HURT_COLOR
		elseif isCrit then Color3.fromRGB(255, 215, 45)
		else Color3.fromRGB(255, 255, 255)
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
-- 4. ENEMY ATTACK TELEGRAPHS (warning shown during the windup so players can dodge)
-- ==========================================
local function playEnemyAttack(enemyModel: Model, kind: string, center: Vector3, radius: number, windup: number)
	if kind == "Slam" then
		-- Red circle on the ground that fills up until the slam lands
		local area = makeDisc(center + Vector3.new(0, 0.1, 0), radius * 2, ENEMY_ATTACK_COLOR, 0.75)
		local fill = makeDisc(center + Vector3.new(0, 0.15, 0), 0.5, ENEMY_ATTACK_COLOR, 0.45)
		TweenService:Create(fill, TweenInfo.new(windup, Enum.EasingStyle.Linear), {
			Size = Vector3.new(0.2, radius * 2, radius * 2),
		}):Play()
		Debris:AddItem(area, windup + 0.5)
		Debris:AddItem(fill, windup + 0.5)

		task.delay(windup, function()
			area:Destroy()
			fill:Destroy()
			-- Impact shockwave
			local wave = makeDisc(center + Vector3.new(0, 0.2, 0), radius * 2, Color3.fromRGB(255, 235, 220), 0.2)
			TweenService:Create(wave, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.2, radius * 2.4, radius * 2.4),
				Transparency = 1,
			}):Play()
			Debris:AddItem(wave, 0.35)
		end)
	else
		-- Melee: outline glows red during the windup, then a red slash toward the target
		local outline = enemyModel:FindFirstChildOfClass("Highlight")
		if outline then
			outline.OutlineColor = ENEMY_ATTACK_COLOR
		end

		task.delay(windup, function()
			if outline then
				outline.OutlineColor = OUTLINE_COLOR
			end
			local enemyRoot = enemyModel:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not enemyRoot or not enemyModel.Parent then
				return
			end
			local flatTarget = Vector3.new(center.X, enemyRoot.Position.Y, center.Z)
			if (flatTarget - enemyRoot.Position).Magnitude > 0.1 then
				local scale = enemyRoot.Size.X / 2 -- Bigger enemies, bigger slash
				spawnCrescent(CFrame.lookAt(enemyRoot.Position, flatTarget), math.rad(-20), ENEMY_ATTACK_COLOR, scale)
			end
		end)
	end
end

-- ==========================================
-- 5. USING SKILLS (mouse / keyboard / skill bar buttons)
-- ==========================================
local function getCooldown(skillId: string): number
	local attackSpeed = player:GetAttribute("AttackSpeed") or 0
	return PlayerStats.getCooldown(SkillData[skillId].Cooldown, attackSpeed)
end

local function useSkill(skillId: string)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	-- Client-side cooldown check for responsiveness (the server checks again for real)
	local now = os.clock()
	if now - (lastUseTimes[skillId] or -math.huge) < getCooldown(skillId) then
		return
	end
	lastUseTimes[skillId] = now

	-- Snap character rotation immediately toward the aim point when attacking
	local aimPoint = getAimPoint(rootPart)
	local flatTarget = Vector3.new(aimPoint.X, rootPart.Position.Y, aimPoint.Z)
	if (flatTarget - rootPart.Position).Magnitude > 0.1 then
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, flatTarget)
	end

	-- 1) Play instant local VFX & swing animation (0 ms delay)
	playSkillVFX(character, skillId, aimPoint, comboStep)
	if skillId == "BasicSlash" then
		comboStep = if comboStep == 1 then 2 else 1
	end

	-- 2) Tell Server which skill we used and where we aimed
	combatRemote:FireServer(skillId, aimPoint)
end

local function getSkillForInput(input: InputObject): string?
	for _, entry in ipairs(SKILL_BAR) do
		for _, inputEnum in ipairs(entry.Inputs) do
			if input.UserInputType == inputEnum or input.KeyCode == inputEnum then
				return entry.SkillId
			end
		end
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	local skillId = getSkillForInput(input)
	if skillId then
		heldSkills[skillId] = true
		useSkill(skillId)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	local skillId = getSkillForInput(input)
	if skillId then
		heldSkills[skillId] = nil
	end
end)

-- Alt-tabbing while holding a button would otherwise keep attacking forever
UserInputService.WindowFocusReleased:Connect(function()
	table.clear(heldSkills)
end)

-- ==========================================
-- 6. SKILL BAR UI (cooldowns; on mobile these are the attack buttons)
-- ==========================================
local SLOT_SIZE = if isTouchOnly then 84 else 64

local skillGui = Ui.screenGui("SkillBar", 1)
local bar = Ui.new("Frame", {
	Name = "Bar",
	-- PC: bottom center. Mobile: right side, above Roblox's jump button
	AnchorPoint = if isTouchOnly then Vector2.new(1, 1) else Vector2.new(0.5, 1),
	Position = if isTouchOnly then UDim2.new(1, -24, 1, -150) else UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(#SKILL_BAR * (SLOT_SIZE + 10), SLOT_SIZE),
	BackgroundTransparency = 1,
	Parent = skillGui,
}, {
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local cooldownOverlays: { [string]: { Overlay: Frame, Text: TextLabel } } = {}

for index, entry in ipairs(SKILL_BAR) do
	local button = Ui.button({
		Name = entry.SkillId,
		LayoutOrder = index,
		Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
		BackgroundColor3 = Ui.Colors.Panel,
		BackgroundTransparency = 0.15,
		Text = "",
		Parent = bar,
	}, {
		Ui.corner(10),
		Ui.stroke(Ui.Colors.Accent, 2),
		Ui.text({
			Name = "SkillName",
			Position = UDim2.new(0, 4, 0, 6),
			Size = UDim2.new(1, -8, 0.5, 0),
			Text = SkillData[entry.SkillId].Name,
			TextScaled = true,
		}),
		Ui.text({
			Name = "KeyText",
			Position = UDim2.new(0, 4, 0.62, 0),
			Size = UDim2.new(1, -8, 0.28, 0),
			Text = if isTouchOnly then "" else entry.KeyText,
			TextScaled = true,
			TextColor3 = Ui.Colors.TextDim,
		}),
	})

	-- Dark overlay that shrinks from the top as the cooldown runs out
	local overlay = Ui.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = button,
	}, { Ui.corner(10) })
	local cooldownText = Ui.text({
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextSize = 22,
		ZIndex = 3,
		Parent = button,
	})

	button.Activated:Connect(function()
		useSkill(entry.SkillId)
	end)
	cooldownOverlays[entry.SkillId] = { Overlay = overlay, Text = cooldownText }
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for skillId, ui in pairs(cooldownOverlays) do
		local cooldown = getCooldown(skillId)
		local remaining = cooldown - (now - (lastUseTimes[skillId] or -math.huge))
		if remaining > 0 then
			ui.Overlay.Size = UDim2.fromScale(1, remaining / cooldown)
			ui.Text.Text = if remaining >= 1 then string.format("%d", math.ceil(remaining)) else ""
		else
			ui.Overlay.Size = UDim2.fromScale(1, 0)
			ui.Text.Text = ""
		end
	end

	-- Hold to keep attacking (useSkill ignores calls while on cooldown)
	for skillId in pairs(heldSkills) do
		useSkill(skillId)
	end
end)

-- ==========================================
-- SERVER EVENTS (damage numbers, other players' skills, enemy attacks)
-- ==========================================
combatRemote.OnClientEvent:Connect(function(action: string, ...)
	if action == "DamageDealt" then
		local targetModel: Model, damage: number, isCrit: boolean = ...
		if targetModel then
			showHitFeedback(targetModel, damage, isCrit)
		end
	elseif action == "ReplicateSkill" then
		local attackerChar: Model, skillId: string, aimPoint: Vector3, step: number = ...
		if attackerChar and attackerChar ~= player.Character then
			playSkillVFX(attackerChar, skillId, aimPoint, step)
		end
	elseif action == "EnemyAttack" then
		local enemyModel: Model, kind: string, center: Vector3, radius: number, windup: number = ...
		if enemyModel then
			playEnemyAttack(enemyModel, kind, center, radius, windup)
		end
	end
end)
