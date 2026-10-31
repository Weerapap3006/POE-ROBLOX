-- ==========================================
-- COMBAT CLIENT (Aiming, Skill Input & Skill Bar, Dodge Dash, Life/Mana Flasks, VFX, Enemy Telegraphs & Damage Numbers)
-- Path: StarterPlayer.StarterPlayerScripts.CombatClient
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local combatRemote = remotesFolder:WaitForChild("CombatRemote") :: RemoteEvent
local dodgeRemote = remotesFolder:WaitForChild("DodgeRemote") :: RemoteEvent
local flaskRemote = remotesFolder:WaitForChild("FlaskRemote") :: RemoteEvent

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local SkillData = require(modulesFolder:WaitForChild("SkillData"))
local PlayerStats = require(modulesFolder:WaitForChild("PlayerStats"))
local Elements = require(modulesFolder:WaitForChild("Elements"))
local RuneData = require(modulesFolder:WaitForChild("RuneData"))
local SkillCast = require(modulesFolder:WaitForChild("SkillCast"))
local Ui = require(modulesFolder:WaitForChild("Ui"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
-- Skill bar slots, left to right. Which skill sits in each slot comes from the server ("SkillBar" attribute,
-- changed in the inventory). Inputs = mouse buttons / keys of the slot, in the same order as
-- PlayerStats.SKILL_BAR_KEYS (the text shown on the buttons). Mobile taps the buttons instead
local SKILL_SLOT_INPUTS: { { EnumItem } } = {
	{ Enum.UserInputType.MouseButton1 },
	{ Enum.UserInputType.MouseButton2 },
	{ Enum.KeyCode.Q },
	{ Enum.KeyCode.R },
}
local TOUCH_AUTO_AIM_RANGE = 25 -- Mobile: skills aim at the nearest enemy within this many studs
local DODGE_KEY = Enum.KeyCode.Space -- Takes over the jump key (jumping is turned off)
local DASH_CROUCH = 0.25 -- Studs the body lowers slightly during a dash
local DASH_LEAN_ANGLE = math.rad(38) -- Forward lean angle (radians) during a dash (no 360 flip)
local DASH_MAX_FORCE = 18000 -- Finite force so hitting a wall never flings the character into the sky
-- Flask slots after the skills (Kind = key in PlayerStats.FLASKS). Sparkle = rises from a player drinking it
local FLASK_SLOTS: { { Kind: string, KeyText: string, Key: Enum.KeyCode, Liquid: Color3, Sparkle: Color3 } } = {
	{ Kind = "Life", KeyText = "1", Key = Enum.KeyCode.One, Liquid = Ui.Colors.Health, Sparkle = Color3.fromRGB(255, 110, 120) },
	{ Kind = "Mana", KeyText = "2", Key = Enum.KeyCode.Two, Liquid = Ui.Colors.Mana, Sparkle = Color3.fromRGB(110, 160, 255) },
}
local NO_MANA_SHADE = Color3.fromRGB(20, 50, 140) -- Covers a skill slot while there isn't enough mana for it
local SLASH_COLOR = Color3.fromRGB(120, 210, 255) -- Anime cyan energy slash
local ENEMY_ATTACK_COLOR = Color3.fromRGB(255, 60, 50)
local ENEMY_ALERT_COLOR = Color3.fromRGB(255, 200, 60) -- "!" over an enemy that just spotted a player
local OUTLINE_COLOR = Color3.fromRGB(15, 15, 20)
local PLAYER_HURT_COLOR = Color3.fromRGB(255, 80, 80)

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local lastUseTimes: { [string]: number } = {} -- Per skill id (cooldowns follow the skill, not the slot)
local heldSlots: { [number]: boolean } = {} -- Holding a slot's button keeps using its skill
local slotSkills: { string } = {} -- Skill id in each skill bar slot, "" = empty (from the "SkillBar" attribute)
local comboStep = 1
local currentMouseWorldPos = Vector3.zero
local dodgeEndTime = 0 -- Dashing until this time: no attacks, no turning toward the mouse
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

	-- Dashing: keep facing the dash direction set when it started
	if os.clock() < dodgeEndTime then
		humanoid.AutoRotate = false
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

-- Dodge Dash: locks torso, legs, and arms into a fixed forward Dash pose over DODGE_DURATION
-- (overrides the walking animation completely so the character glides/dashes instead of pedaling feet)
type RollState = {
	startTime: number,
	targetPose: CFrame,
	basePose: CFrame,
	lastWritten: CFrame?,
}
local activeRolls: { [Motor6D]: RollState } = {}

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

	for motor, roll in pairs(activeRolls) do
		if motor.Transform ~= roll.lastWritten then
			roll.basePose = motor.Transform
		end

		local t = (now - roll.startTime) / PlayerStats.DODGE_DURATION
		if t >= 1 or not motor:IsDescendantOf(workspace) then
			motor.Transform = roll.basePose
			activeRolls[motor] = nil
		else
			-- Snap quickly into the fixed Dash pose and hold it (overrides walk cycle completely)
			local weight = math.sin(math.pi * math.clamp(t, 0, 1)) ^ 0.4
			local pose = roll.basePose:Lerp(roll.targetPose, weight)
			motor.Transform = pose
			roll.lastWritten = pose
		end
	end
end)

local function lockDashJoint(character: Model, partName: string, jointName: string, targetPose: CFrame, now: number)
	local part = character:FindFirstChild(partName)
	local motor = part and part:FindFirstChild(jointName) :: Motor6D?
	if motor then
		activeRolls[motor] = {
			startTime = now,
			targetPose = targetPose,
			basePose = motor.Transform,
			lastWritten = nil,
		}
	end
end

local function playRollPose(character: Model)
	local now = os.clock()
	-- Torso leans forward, legs freeze in a dash stride (no walking), arms sweep back
	lockDashJoint(character, "LowerTorso", "Root", CFrame.new(0, -DASH_CROUCH, 0) * CFrame.Angles(-DASH_LEAN_ANGLE, 0, 0), now)
	lockDashJoint(character, "LeftUpperLeg", "LeftHip", CFrame.Angles(math.rad(28), 0, 0), now)
	lockDashJoint(character, "LeftLowerLeg", "LeftKnee", CFrame.Angles(math.rad(-40), 0, 0), now)
	lockDashJoint(character, "RightUpperLeg", "RightHip", CFrame.Angles(math.rad(-38), 0, 0), now)
	lockDashJoint(character, "RightLowerLeg", "RightKnee", CFrame.Angles(math.rad(-25), 0, 0), now)
	lockDashJoint(character, "RightUpperArm", "RightShoulder", CFrame.Angles(math.rad(-50), 0, math.rad(12)), now)
	lockDashJoint(character, "LeftUpperArm", "LeftShoulder", CFrame.Angles(math.rad(-50), 0, math.rad(-12)), now)
end

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

-- How a skill looks: spells glow in their element's color, physical skills are cyan. Stone runes change it
-- (same rules as CombatServer): Reach = bigger / longer, Split = side slashes / shots, Ember / Frost / Storm =
-- that element's color on a physical skill. Read from the owner's "SkillRunes_<skillId>" attribute
type SkillLook = { Color: Color3, Scale: number, Split: boolean }

local function getSkillLook(character: Model, skillId: string): SkillLook
	local owner = Players:GetPlayerFromCharacter(character)
	local runes = RuneData.parse(if owner then owner:GetAttribute("SkillRunes_" .. skillId) else nil)
	local skill = SkillData[skillId]
	local color = if skill and Elements.Colors[skill.Element] then Elements.Colors[skill.Element] else SLASH_COLOR
	for _, element in ipairs(Elements.Types) do
		if color ~= SLASH_COLOR then
			break -- A spell's own color, or the first element in Elements.Types order when several are converted
		end
		for runeId in pairs(runes) do
			if RuneData.Runes[runeId].Convert == element then
				color = Elements.Colors[element]
			end
		end
	end
	return {
		Color = color,
		Scale = if runes.Reach then RuneData.AREA_MULTIPLIER else 1,
		Split = runes.Split == true,
	}
end

-- Flat direction from the character toward the aim point (where it faces when aiming at itself)
local function getAimDirection(rootPart: BasePart, aimPoint: Vector3): Vector3
	local flat = Vector3.new(aimPoint.X - rootPart.Position.X, 0, aimPoint.Z - rootPart.Position.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end
	return flat.Unit
end

-- Body pose of a skill (SkillData Animation), layered on top of the walk animation
local function playPose(character: Model, animation: string, step: number)
	local rightShoulder, waist = getSwingMotors(character)
	if animation == "Slash" then
		-- Arm swing + waist twist, alternating left/right each combo step
		local swingAngle = if step == 1 then math.rad(110) else math.rad(75)
		local sideAngle = if step == 1 then math.rad(-35) else math.rad(35)
		startSwing(rightShoulder, CFrame.Angles(swingAngle, sideAngle, 0))
		startSwing(waist, CFrame.Angles(0, if step == 1 then math.rad(25) else math.rad(-25), 0))
	elseif animation == "Spin" then
		-- Upper body whirls around
		startSwing(waist, CFrame.Angles(0, math.rad(170), 0))
		startSwing(rightShoulder, CFrame.Angles(math.rad(90), 0, 0))
	elseif animation == "Slam" then
		-- Arm raised high while the upper body bends forward into the ground
		startSwing(rightShoulder, CFrame.Angles(math.rad(150), 0, 0))
		startSwing(waist, CFrame.Angles(math.rad(-25), 0, 0))
	else
		-- Cast: arm thrust out toward the aim
		startSwing(rightShoulder, CFrame.Angles(math.rad(95), 0, 0))
		startSwing(waist, CFrame.Angles(0, math.rad(-15), 0))
	end
end

-- Box (Slash): crescent wave toward the aim, plus one to each side with the Split rune
local function playSlashEffect(rootPart: BasePart, direction: Vector3, step: number, look: SkillLook)
	local tiltAngle = if step == 1 then math.rad(15) else math.rad(-15)
	local lookCF = CFrame.lookAt(rootPart.Position, rootPart.Position + direction)
	spawnCrescent(lookCF, tiltAngle, look.Color, look.Scale)
	if look.Split then
		for _, side in ipairs({ 1, -1 }) do
			spawnCrescent(lookCF * CFrame.Angles(0, math.rad(RuneData.SPLIT_ANGLE * side), 0), tiltAngle, look.Color, look.Scale)
		end
	end
end

-- Radius: a ring wave that expands to the skill's radius, around the character (Spin Slash, Frost Nova)
-- or CenterOffset studs in front of it (Ground Slam)
local function playRingEffect(character: Model, rootPart: BasePart, direction: Vector3, skill: SkillData.Skill, look: SkillLook)
	local center = getGroundBelow(character, rootPart) + direction * (skill.CenterOffset or 0) * look.Scale
	local ring = makeDisc(center + Vector3.new(0, 0.6, 0), 2, look.Color, 0.2)
	ring.Name = "SkillRingVFX"
	local diameter = (skill.Radius or 10) * look.Scale * 2
	TweenService:Create(ring, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, diameter, diameter),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.3)
end

-- Glowing ball that pops outward and fades (projectile impacts)
local function spawnBurst(position: Vector3, diameter: number, color: Color3)
	local burst = Instance.new("Part")
	burst.Name = "BurstVFX"
	burst.Shape = Enum.PartType.Ball
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.CanTouch = false
	burst.CastShadow = false
	burst.Material = Enum.Material.Neon
	burst.Color = color
	burst.Transparency = 0.25
	burst.Size = Vector3.one
	burst.CFrame = CFrame.new(position)
	burst.Parent = workspace
	TweenService:Create(burst, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.one * diameter,
		Transparency = 1,
	}):Play()
	Debris:AddItem(burst, 0.3)
end

-- Projectile: a glowing ball flies to where SkillCast says it lands (first enemy / wall / max range, the same
-- rule the server uses), then bursts there (an explosive one bursts as big as its explosion)
local function spawnProjectile(character: Model, origin: Vector3, direction: Vector3, skill: SkillData.Skill, look: SkillLook)
	local landing, distance = SkillCast.castProjectile(origin, direction, (skill.Range or 0) * look.Scale, skill.Width or 1, character)
	local size = (skill.Width or 1) * 0.6

	local ball = Instance.new("Part")
	ball.Name = "ProjectileVFX"
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Neon
	ball.Color = look.Color
	ball.Size = Vector3.one * size
	ball.CFrame = CFrame.new(origin)
	ball.Parent = workspace

	local travelTime = math.max(distance, 0.1) / (skill.Speed or 100)
	TweenService:Create(ball, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), { CFrame = CFrame.new(landing) }):Play()
	Debris:AddItem(ball, travelTime + 0.05)
	task.delay(travelTime, function()
		local diameter = if skill.ExplosionRadius then skill.ExplosionRadius * look.Scale * 2 else size * 3
		spawnBurst(landing, diameter, look.Color)
	end)
end

-- One jagged lightning bolt between two points (3 short neon segments that flicker out)
local function spawnBolt(from: Vector3, to: Vector3, color: Color3)
	local points = { from }
	for step = 1, 2 do
		local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.4
		table.insert(points, from:Lerp(to, step / 3) + jitter)
	end
	table.insert(points, to)
	for index = 1, #points - 1 do
		local a, b = points[index], points[index + 1]
		local length = (b - a).Magnitude
		if length > 0.05 then
			local segment = Instance.new("Part")
			segment.Name = "BoltVFX"
			segment.Anchored = true
			segment.CanCollide = false
			segment.CanQuery = false
			segment.CanTouch = false
			segment.CastShadow = false
			segment.Material = Enum.Material.Neon
			segment.Color = color
			segment.Size = Vector3.new(0.3, 0.3, length)
			segment.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -length / 2)
			segment.Parent = workspace
			TweenService:Create(segment, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			}):Play()
			Debris:AddItem(segment, 0.3)
		end
	end
end

-- Chain (Arc): bolts from the caster to each enemy in turn (SkillCast.findChain, the same pick the server makes).
-- Nobody in range: a short fizzle toward the aim
local function playChainEffect(rootPart: BasePart, aimPoint: Vector3, direction: Vector3, skill: SkillData.Skill, look: SkillLook)
	local range = (skill.Range or 0) * look.Scale
	local targets = SkillCast.findChain(rootPart.Position, aimPoint, range, skill.Chains or 0, (skill.ChainRange or 0) * look.Scale)
	local from = rootPart.Position
	for _, model in ipairs(targets) do
		local targetRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if targetRoot then
			spawnBolt(from, targetRoot.Position, look.Color)
			from = targetRoot.Position
		end
	end
	if #targets == 0 then
		spawnBolt(rootPart.Position, rootPart.Position + direction * math.min(range, 8), look.Color)
	end
end

local function playSkillVFX(character: Model, skillId: string, aimPoint: Vector3, step: number)
	local skill = SkillData[skillId]
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not skill or not rootPart then
		return
	end
	local look = getSkillLook(character, skillId)
	local direction = getAimDirection(rootPart, aimPoint)
	playPose(character, skill.Animation, step)

	if skill.Shape == "Box" then
		playSlashEffect(rootPart, direction, step, look)
	elseif skill.Shape == "Radius" then
		playRingEffect(character, rootPart, direction, skill, look)
	elseif skill.Shape == "Projectile" then
		local lookCF = CFrame.lookAt(rootPart.Position, rootPart.Position + direction)
		local angles = if look.Split then { 0, RuneData.SPLIT_ANGLE, -RuneData.SPLIT_ANGLE } else { 0 }
		for _, angle in ipairs(angles) do
			local shotDirection = (lookCF * CFrame.Angles(0, math.rad(angle), 0)).LookVector
			spawnProjectile(character, rootPart.Position, shotDirection, skill, look)
		end
	elseif skill.Shape == "Chain" then
		playChainEffect(rootPart, aimPoint, direction, skill, look)
	end
end

-- Detonation rune: a corpse bursts into a fiery ring
local function playCorpseExplosion(center: Vector3, radius: number)
	local burst = makeDisc(center, 2, Elements.Colors.Fire, 0.15)
	burst.Name = "CorpseExplosionVFX"
	TweenService:Create(burst, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(burst, 0.35)
end

-- ==========================================
-- 3. FLOATING DAMAGE NUMBERS & HIT FLASH
-- ==========================================
-- element = "Fire" / "Cold" / "Lightning" for elemental hits and burns, nil for normal hits.
-- text = shown instead of the number (e.g. "BLOCK")
local function showHitFeedback(targetModel: Model, damage: number, isCrit: boolean, element: string?, text: string?)
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

	-- Players taking damage get red numbers; enemies: element color (burns), gold on crit, otherwise white
	local isPlayerHurt = Players:GetPlayerFromCharacter(targetModel) ~= nil
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = if text then text elseif isCrit then tostring(damage) .. "!" else tostring(damage)
	label.TextColor3 = if text
		then Color3.fromRGB(200, 200, 215)
		elseif isPlayerHurt
		then PLAYER_HURT_COLOR
		elseif element and Elements.Colors[element] then Elements.Colors[element]
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

-- Enemy just spotted a player: a "!" pops up over its head while it stands still before charging
local function playEnemyAlert(enemyModel: Model, duration: number)
	local head = enemyModel:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "AlertMark"
	billboard.Size = UDim2.fromOffset(40, 60)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y + 1, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = head
	billboard.Parent = head

	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 1)
	label.Size = UDim2.fromScale(0.3, 0.3)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Text = "!"
	label.TextColor3 = ENEMY_ALERT_COLOR
	label.TextStrokeColor3 = OUTLINE_COLOR
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	-- Pop in with a little overshoot
	TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(1, 1),
	}):Play()
	Debris:AddItem(billboard, duration)
end

-- ==========================================
-- 5. USING SKILLS (mouse / keyboard / skill bar buttons)
-- ==========================================
local function getCooldown(skillId: string): number
	if skillId == "Dodge" then
		return PlayerStats.DODGE_COOLDOWN
	end
	local flaskKind = string.match(skillId, "^(%a+)Flask$") -- "LifeFlask" / "ManaFlask"
	if flaskKind then
		return PlayerStats.FLASKS[flaskKind].Duration
	end
	-- AttackSpeed stat + Ranger Momentum (HeroAttackSpeed), the same sum CombatServer uses
	local attackSpeed = (player:GetAttribute("AttackSpeed") or 0) + (player:GetAttribute("HeroAttackSpeed") or 0)
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

	-- No attacking mid-dash or while frozen (held buttons pick up again once it ends)
	local now = os.clock()
	if now < dodgeEndTime or character:GetAttribute("Frozen") then
		return
	end

	-- Client-side cooldown check for responsiveness (the server checks again for real)
	if now - (lastUseTimes[skillId] or -math.huge) < getCooldown(skillId) then
		return
	end
	-- Not enough mana: nothing happens (the slot is shaded blue). The server checks the real mana again
	if (player:GetAttribute("Mana") or 0) < SkillData[skillId].ManaCost then
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

-- Uses whatever skill is in a skill bar slot (an empty slot does nothing)
local function useSlot(slot: number)
	local skillId = slotSkills[slot]
	if skillId and SkillData[skillId] then
		useSkill(skillId)
	end
end

local function getSlotForInput(input: InputObject): number?
	for slot, inputs in ipairs(SKILL_SLOT_INPUTS) do
		for _, inputEnum in ipairs(inputs) do
			if input.UserInputType == inputEnum or input.KeyCode == inputEnum then
				return slot
			end
		end
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	local slot = getSlotForInput(input)
	if slot then
		heldSlots[slot] = true
		useSlot(slot)
	end
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	local slot = getSlotForInput(input)
	if slot then
		heldSlots[slot] = nil
	end
end)

-- Alt-tabbing while holding a button would otherwise keep attacking forever
UserInputService.WindowFocusReleased:Connect(function()
	table.clear(heldSlots)
end)

-- ==========================================
-- 6. DODGE DASH (replaces jumping: Space / mobile Dodge button)
-- ==========================================
-- No jumping in this game. Jump power 0 also hides Roblox's mobile jump button
local function disableJump(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
end

if player.Character then
	task.spawn(disableJump, player.Character)
end
player.CharacterAdded:Connect(disableJump)

-- Dash where the player is walking; standing still dashes toward the mouse (PC) or straight ahead (mobile)
local function getDodgeDirection(humanoid: Humanoid, rootPart: BasePart): Vector3
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = if isTouchOnly then rootPart.CFrame.LookVector else currentMouseWorldPos - rootPart.Position
	end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		direction = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end
	return direction.Unit
end

local function getDodgeAttachment(rootPart: BasePart): Attachment
	local existing = rootPart:FindFirstChild("DodgeAttachment")
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "DodgeAttachment"
	attachment.Parent = rootPart
	return attachment
end

-- Pushes the character along the ground with a snappy burst ("ฟึ้บ!"), obstacle detection,
-- and upward-velocity clamping so hitting a wall/object never launches the character into the air
local function pushRoll(character: Model, rootPart: BasePart, direction: Vector3)
	local baseSpeed = PlayerStats.DODGE_DISTANCE / PlayerStats.DODGE_DURATION
	local startTime = os.clock()
	local flatDir = Vector2.new(direction.X, direction.Z)

	local mover = Instance.new("LinearVelocity")
	mover.Name = "DodgeVelocity"
	mover.Attachment0 = getDodgeAttachment(rootPart)
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.PlaneVelocity = flatDir * (baseSpeed * 1.65)
	mover.MaxForce = DASH_MAX_FORCE
	mover.Parent = rootPart

	local wallParams = RaycastParams.new()
	wallParams.FilterType = Enum.RaycastFilterType.Exclude
	wallParams.RespectCanCollide = true
	wallParams.FilterDescendantsInstances = { character }

	local stepConn: RBXScriptConnection?
	stepConn = RunService.Heartbeat:Connect(function()
		if not mover.Parent or not rootPart.Parent then
			if stepConn then
				stepConn:Disconnect()
			end
			return
		end

		-- Stop pushing forward if a wall/obstacle is directly in front of the character
		local hit = workspace:Raycast(rootPart.Position, direction * 2.6, wallParams)
		if hit then
			mover.PlaneVelocity = Vector2.zero
		else
			-- High initial burst speed that eases down smoothly at the end of the dash
			local progress = math.clamp((os.clock() - startTime) / PlayerStats.DODGE_DURATION, 0, 1)
			local burstMultiplier = 1.65 - 1.30 * progress
			mover.PlaneVelocity = flatDir * (baseSpeed * burstMultiplier)
		end

		-- Clamp any upward vertical bounce so colliding with objects never flings the player upward
		local vel = rootPart.AssemblyLinearVelocity
		if vel.Y > 1 then
			rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
		end
	end)

	task.delay(PlayerStats.DODGE_DURATION, function()
		if stepConn then
			stepConn:Disconnect()
		end
		mover:Destroy()
		if rootPart.Parent then
			local vel = rootPart.AssemblyLinearVelocity
			if vel.Y > 1 then
				rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
			end
		end
	end)
end

local function dodge()
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- Frozen (an enemy's cold hit): can't dash out of it
	if not humanoid or not rootPart or humanoid.Health <= 0 or character:GetAttribute("Frozen") then
		return
	end

	local now = os.clock()
	if now - (lastUseTimes.Dodge or -math.huge) < PlayerStats.DODGE_COOLDOWN then
		return
	end
	lastUseTimes.Dodge = now
	dodgeEndTime = now + PlayerStats.DODGE_DURATION

	local direction = getDodgeDirection(humanoid, rootPart)
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + direction)
	pushRoll(character, rootPart, direction)
	playRollPose(character)

	-- The server grants the invulnerability window (enemy hits miss) after its own cooldown check
	dodgeRemote:FireServer(direction)
end

-- Bound above Roblox's own jump action so Space never reaches it
ContextActionService:BindActionAtPriority("Dodge", function(_, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		dodge()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, DODGE_KEY)

-- ==========================================
-- 7. LIFE & MANA FLASKS (keys 1 / 2, mobile Life / Mana buttons)
-- ==========================================
-- Uses left come from the server ("LifeFlaskCharges" / "ManaFlaskCharges" attributes, see PlayerResources),
-- which also does the recovering
local function getFlaskCharges(kind: string): number
	return player:GetAttribute(kind .. "FlaskCharges") or 0
end

local function getFlaskSlot(kind: string)
	for _, flask in ipairs(FLASK_SLOTS) do
		if flask.Kind == kind then
			return flask
		end
	end
	return nil
end

-- Sparkles in the flask's color rise from the body while it recovers
local function playFlaskVFX(character: Model, kind: string)
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local flask = getFlaskSlot(kind)
	local duration = PlayerStats.FLASKS[kind] and PlayerStats.FLASKS[kind].Duration
	if not rootPart or not flask or not duration then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "FlaskVFX"
	emitter.Color = ColorSequence.new(flask.Sparkle)
	emitter.LightEmission = 0.6
	emitter.Size = NumberSequence.new(0.5, 0)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.6, 0.9)
	emitter.Speed = NumberRange.new(3, 5)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Rate = 18
	emitter.Parent = rootPart
	task.delay(duration, function()
		emitter.Enabled = false
	end)
	Debris:AddItem(emitter, duration + 1)
end

local function drinkFlask(kind: string)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Same checks as the server: not already full, at least one use, one recovery per flask at a time
	local isFull = if kind == "Life"
		then humanoid.Health >= humanoid.MaxHealth
		else (player:GetAttribute("Mana") or 0) >= (player:GetAttribute("MaxMana") or 0)
	if isFull or getFlaskCharges(kind) < 1 then
		return
	end
	local slotId = kind .. "Flask"
	local now = os.clock()
	if now - (lastUseTimes[slotId] or -math.huge) < getCooldown(slotId) then
		return
	end
	lastUseTimes[slotId] = now

	playFlaskVFX(character, kind)
	flaskRemote:FireServer(kind)
end

for _, flask in ipairs(FLASK_SLOTS) do
	ContextActionService:BindAction(flask.Kind .. "Flask", function(_, inputState: Enum.UserInputState)
		if inputState == Enum.UserInputState.Begin then
			drinkFlask(flask.Kind)
		end
		return Enum.ContextActionResult.Sink
	end, false, flask.Key)
end

-- ==========================================
-- 8. SKILL BAR UI (cooldowns; on mobile these are the attack buttons)
-- ==========================================
local SLOT_SIZE = if isTouchOnly then 84 else 64

local skillGui = Ui.screenGui("SkillBar", 1)
local bar = Ui.new("Frame", {
	Name = "Bar",
	-- PC: bottom center, the flasks and Dodge are the last slots. Mobile: right side, above the flask / Dodge buttons
	AnchorPoint = if isTouchOnly then Vector2.new(1, 1) else Vector2.new(0.5, 1),
	Position = if isTouchOnly then UDim2.new(1, -24, 1, -150) else UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.fromOffset(
		(if isTouchOnly then #SKILL_SLOT_INPUTS else #SKILL_SLOT_INPUTS + #FLASK_SLOTS + 1) * (SLOT_SIZE + 10),
		SLOT_SIZE
	),
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

-- One square slot with a cooldown overlay. id = "Slot1".."Slot4" (the skill in that bar slot),
-- "LifeFlask" / "ManaFlask" or "Dodge" (see getCooldown)
local function createSlot(id: string, displayName: string, keyText: string, layoutOrder: number, parent: Instance): TextButton
	local button = Ui.button({
		Name = id,
		LayoutOrder = layoutOrder,
		Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
		BackgroundColor3 = Ui.Colors.Panel,
		BackgroundTransparency = 0.15,
		Text = "",
		Parent = parent,
	}, {
		Ui.corner(10),
		Ui.stroke(Ui.Colors.Accent, 2),
		Ui.text({
			Name = "SkillName",
			Position = UDim2.new(0, 4, 0, 6),
			Size = UDim2.new(1, -8, 0.5, 0),
			Text = displayName,
			TextScaled = true,
		}),
		Ui.text({
			Name = "KeyText",
			Position = UDim2.new(0, 4, 0.62, 0),
			Size = UDim2.new(1, -8, 0.28, 0),
			Text = if isTouchOnly then "" else keyText,
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

	cooldownOverlays[id] = { Overlay = overlay, Text = cooldownText }
	return button
end

-- Skill slots: each shows the name of the skill in it, "Empty" when there's none
local slotNameLabels: { TextLabel } = {}
for slot = 1, #SKILL_SLOT_INPUTS do
	local button = createSlot("Slot" .. slot, "", PlayerStats.SKILL_BAR_KEYS[slot] or "", slot, bar)
	slotNameLabels[slot] = button:FindFirstChild("SkillName") :: TextLabel
	button.Activated:Connect(function()
		useSlot(slot)
	end)
end

-- "SkillBar" = "BasicSlash,SpinSlash,," from the server (PlayerData), changes when the inventory moves Skill Stones
local function readSkillBar()
	local text = player:GetAttribute("SkillBar")
	local entries = if type(text) == "string" then string.split(text, ",") else {}
	for slot = 1, #SKILL_SLOT_INPUTS do
		local skill = SkillData[entries[slot] or ""]
		slotSkills[slot] = if skill then entries[slot] else ""
		slotNameLabels[slot].Text = if skill then skill.Name else "Empty"
		slotNameLabels[slot].TextColor3 = if skill then Ui.Colors.Text else Ui.Colors.TextDim
	end
end
player:GetAttributeChangedSignal("SkillBar"):Connect(readSkillBar)
readSkillBar()

-- Flask slots: liquid level = charges / max (fills up between uses as kills add charges), name shows uses left.
-- Mobile: a row left of the Dodge button
for index, flask in ipairs(FLASK_SLOTS) do
	local button = createSlot(flask.Kind .. "Flask", flask.Kind, flask.KeyText, #SKILL_SLOT_INPUTS + index, if isTouchOnly then skillGui else bar)
	if isTouchOnly then
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = UDim2.new(1, -24 - (SLOT_SIZE + 12) * (#FLASK_SLOTS - index + 1), 1, -40)
	end
	button.Activated:Connect(function()
		drinkFlask(flask.Kind)
	end)

	local liquid = Ui.new("Frame", {
		Name = "Liquid",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = flask.Liquid,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 0, -- Behind the slot's text, under the cooldown overlay
		Parent = button,
	}, { Ui.corner(10) })
	local nameLabel = button:FindFirstChild("SkillName") :: TextLabel

	local function updateCharges()
		local charges = getFlaskCharges(flask.Kind)
		liquid.Size = UDim2.fromScale(1, math.clamp(charges / PlayerStats.FLASKS[flask.Kind].MaxCharges, 0, 1))
		nameLabel.Text = string.format("%s x%d", flask.Kind, math.floor(charges))
	end
	player:GetAttributeChangedSignal(flask.Kind .. "FlaskCharges"):Connect(updateCharges)
	updateCharges()
end

-- Mobile: Dodge takes the spot of Roblox's jump button (bottom right, under the skills)
local dodgeButton = createSlot("Dodge", "Dodge", "Space", #SKILL_SLOT_INPUTS + #FLASK_SLOTS + 1, if isTouchOnly then skillGui else bar)
if isTouchOnly then
	dodgeButton.AnchorPoint = Vector2.new(1, 1)
	dodgeButton.Position = UDim2.new(1, -24, 1, -40)
end
dodgeButton.Activated:Connect(dodge)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local mana = player:GetAttribute("Mana") or 0
	for id, ui in pairs(cooldownOverlays) do
		-- A skill slot shows the cooldown of the skill in it (an empty slot shows nothing)
		local slot = tonumber(string.match(id, "^Slot(%d+)$"))
		local skillId = if slot then slotSkills[slot] or "" else id
		if skillId == "" then
			ui.Overlay.Size = UDim2.fromScale(1, 0)
			ui.Text.Text = ""
			continue
		end
		local cooldown = getCooldown(skillId)
		local remaining = cooldown - (now - (lastUseTimes[skillId] or -math.huge))
		-- Not enough mana: the whole slot stays shaded blue until mana regenerates
		local skill = SkillData[skillId]
		local lacksMana = skill ~= nil and mana < skill.ManaCost
		ui.Overlay.BackgroundColor3 = if lacksMana then NO_MANA_SHADE else Color3.new(0, 0, 0)
		if remaining > 0 then
			ui.Overlay.Size = UDim2.fromScale(1, remaining / cooldown)
			ui.Text.Text = if remaining >= 1 then string.format("%d", math.ceil(remaining)) else ""
		elseif lacksMana then
			ui.Overlay.Size = UDim2.fromScale(1, 1)
			ui.Text.Text = ""
		else
			ui.Overlay.Size = UDim2.fromScale(1, 0)
			ui.Text.Text = ""
		end
	end

	-- Hold to keep attacking (useSkill ignores calls while on cooldown)
	for slot in pairs(heldSlots) do
		useSlot(slot)
	end
end)

-- ==========================================
-- SERVER EVENTS (damage numbers, other players' skills, rolls and flasks, enemy alerts and attacks)
-- ==========================================
dodgeRemote.OnClientEvent:Connect(function(character: Model)
	if character and character ~= player.Character then
		playRollPose(character)
	end
end)

flaskRemote.OnClientEvent:Connect(function(character: Model, kind: string)
	if character and character ~= player.Character then
		playFlaskVFX(character, kind)
	end
end)

combatRemote.OnClientEvent:Connect(function(action: string, ...)
	if action == "DamageDealt" then
		local targetModel: Model, damage: number, isCrit: boolean, element: string? = ...
		if targetModel then
			showHitFeedback(targetModel, damage, isCrit, element)
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
	elseif action == "EnemyAlert" then
		local enemyModel: Model, duration: number = ...
		if enemyModel then
			playEnemyAlert(enemyModel, duration)
		end
	elseif action == "CorpseExplosion" then
		local center: Vector3, radius: number = ...
		playCorpseExplosion(center, radius)
	elseif action == "OrbShot" then
		-- Mystic Stone Orb shot (HeroService): a short bolt from the player's orbs to the enemy
		local from: Vector3, to: Vector3, element: string = ...
		spawnBolt(from, to, Elements.Colors[element] or Color3.fromRGB(205, 195, 255))
	elseif action == "HeroPulse" then
		-- Warrior full-Fury release: a burst ring around the player (Earthbreaker: as big as the shockwave)
		local character: Model, radius: number, color: Color3 = ...
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			local ring = makeDisc(getGroundBelow(character, rootPart) + Vector3.new(0, 0.7, 0), 2, color, 0.15)
			ring.Name = "HeroPulseVFX"
			TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.2, radius * 2, radius * 2),
				Transparency = 1,
			}):Play()
			Debris:AddItem(ring, 0.4)
		end
	elseif action == "HeroBlock" then
		-- A Wardstone orb took an enemy hit for this player
		local character: Model = ...
		if character then
			showHitFeedback(character, 0, false, nil, "BLOCK")
		end
	end
end)
