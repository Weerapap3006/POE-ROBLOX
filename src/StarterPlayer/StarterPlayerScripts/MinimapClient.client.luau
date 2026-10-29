-- ==========================================
-- MINIMAP CLIENT (Corner Radar + Tab Overlay Map with Enemies, Boss, Portals & Walls)
-- Path: StarterPlayer.StarterPlayerScripts.MinimapClient
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Ui = require(modulesFolder:WaitForChild("Ui"))

-- ==========================================
-- CONFIGURATION (ปรับค่าขนาด, ระยะ, สี, ความโปร่งใส ได้ที่นี่)
-- ==========================================
local TOGGLE_OVERLAY_KEY = Enum.KeyCode.Tab -- ปุ่มสลับขยายแผนที่กลางจอแบบ PoE

-- 1. โหมดมุมขวาบน (Corner Radar Mode)
local CORNER_MAP_SIZE = 185 -- ขนาดกรอบมินิแมพมุมขวาบน (พิกเซล)
local CORNER_VIEW_RADIUS = 130 -- ระยะมองเห็นในมินิแมพมุมขวาบน (studs รอบตัวเรา)
local CORNER_BG_TRANSPARENCY = 0.2 -- ความโปร่งใสพื้นหลังตอนอยู่มุมขวาบน (0 = ทึบ, 1 = ใส)

-- 2. โหมดกด Tab ขยายกลางจอ (Overlay Mode แบบ PoE)
local OVERLAY_MAP_SIZE = 460 -- ขนาดแผนที่ตอนกด Tab มาอยู่กลางจอ (พิกเซล)
local OVERLAY_VIEW_RADIUS = 240 -- ระยะมองเห็นตอนกด Tab กลางจอ (studs รอบตัวเรา เห็นกว้างขึ้น)
local OVERLAY_BG_TRANSPARENCY = 0.45 -- ความโปร่งใสพื้นหลังตอนกด Tab กลางจอ
local OVERLAY_STROKE_TRANSPARENCY = 0.3 -- ความโปร่งใสเส้นขอบตอนกด Tab กลางจอ

-- 3. สีและขนาดของจุดสัญลักษณ์ต่างๆ ในแผนที่
local SELF_COLOR = Color3.fromRGB(255, 255, 255) -- สีจุดตัวเรา (สีขาวตามที่ตั้งไว้)
local SELF_DOT_SIZE = 9

local ALLY_COLOR = Color3.fromRGB(90, 200, 255) -- สีจุดผู้เล่นคนอื่น
local ALLY_DOT_SIZE = 8

local ENEMY_COLOR = Color3.fromRGB(255, 65, 65) -- สีจุดมอนสเตอร์ทั่วไป (สีแดง)
local ENEMY_DOT_SIZE = 7

local BOSS_COLOR = Color3.fromRGB(255, 165, 40) -- สีจุดบอส (สีส้มทองใหญ่)
local BOSS_DOT_SIZE = 13

local ENTER_PORTAL_COLOR = Color3.fromRGB(80, 210, 255) -- สีประตูเข้าด่าน
local RETURN_PORTAL_COLOR = Color3.fromRGB(255, 215, 70) -- สีประตูกลับ Lobby
local PORTAL_DOT_SIZE = 11

local WALL_COLOR = Color3.fromRGB(130, 140, 165) -- สีแท่งกำแพงด่าน
local WALL_TRANSPARENCY = 0.35

-- ==========================================
-- STATE & UI CREATION
-- ==========================================
local isOverlayMode = false
local isTouchOnly = Ui.isTouchOnly()
local gui = Ui.screenGui("Minimap", 2)

local mapFrame = Ui.new("Frame", {
	Name = "MapContainer",
	AnchorPoint = Vector2.new(1, 0),
	Position = if isTouchOnly then UDim2.new(1, -12, 0, 56) else UDim2.new(1, -16, 0, 16),
	Size = UDim2.fromOffset(CORNER_MAP_SIZE, CORNER_MAP_SIZE),
	BackgroundColor3 = Ui.Colors.Panel,
	BackgroundTransparency = CORNER_BG_TRANSPARENCY,
	ClipsDescendants = true,
	Parent = gui,
}, { Ui.corner(10) })

local mapStroke = Ui.stroke(Ui.Colors.Stroke, 2)
mapStroke.Parent = mapFrame

-- Subtle crosshair lines in center
local hLine = Ui.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.9,
	BorderSizePixel = 0,
	Parent = mapFrame,
})
local vLine = Ui.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.9,
	BorderSizePixel = 0,
	Parent = mapFrame,
})

local wallLayer = Ui.new("Folder", { Name = "WallLayer", Parent = mapFrame })
local portalLayer = Ui.new("Folder", { Name = "PortalLayer", Parent = mapFrame })
local enemyLayer = Ui.new("Folder", { Name = "EnemyLayer", Parent = mapFrame })
local allyLayer = Ui.new("Folder", { Name = "AllyLayer", Parent = mapFrame })

-- Self marker at exact center (White dot + facing indicator)
local selfDot = Ui.new("Frame", {
	Name = "SelfMarker",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(SELF_DOT_SIZE, SELF_DOT_SIZE),
	BackgroundColor3 = SELF_COLOR,
	ZIndex = 10,
	Parent = mapFrame,
}, {
	Ui.corner(SELF_DOT_SIZE),
	Ui.stroke(Color3.fromRGB(10, 10, 15), 2),
	Ui.new("Frame", {
		Name = "FacingPointer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(3, 5),
		BackgroundColor3 = SELF_COLOR,
		BorderSizePixel = 0,
	}),
})

-- Header label & enemy counter
local titleLabel = Ui.text({
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.fromOffset(8, 5),
	Size = UDim2.new(1, -16, 0, 18),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = Ui.Colors.TextDim,
	Text = "แผนที่ [Tab]",
	ZIndex = 12,
	Parent = mapFrame,
})

local enemyCountLabel = Ui.text({
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -8, 1, -5),
	Size = UDim2.new(1, -16, 0, 18),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Right,
	TextColor3 = Color3.fromRGB(255, 130, 130),
	Text = "",
	ZIndex = 12,
	Parent = mapFrame,
})

-- Touch button to toggle overlay on mobile/PC click
local clickToggle = Ui.new("TextButton", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "",
	ZIndex = 15,
	Parent = mapFrame,
})

local function applyMapMode()
	if isOverlayMode then
		mapFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		mapFrame.Position = UDim2.fromScale(0.5, 0.5)
		mapFrame.Size = UDim2.fromOffset(OVERLAY_MAP_SIZE, OVERLAY_MAP_SIZE)
		mapFrame.BackgroundTransparency = OVERLAY_BG_TRANSPARENCY
		mapStroke.Transparency = OVERLAY_STROKE_TRANSPARENCY
		titleLabel.Text = "แผนที่กลางจอ (กด Tab เพื่อย่อ)"
	else
		mapFrame.AnchorPoint = Vector2.new(1, 0)
		mapFrame.Position = if isTouchOnly then UDim2.new(1, -12, 0, 56) else UDim2.new(1, -16, 0, 16)
		mapFrame.Size = UDim2.fromOffset(CORNER_MAP_SIZE, CORNER_MAP_SIZE)
		mapFrame.BackgroundTransparency = CORNER_BG_TRANSPARENCY
		mapStroke.Transparency = 0
		titleLabel.Text = if isTouchOnly then "แตะเพื่อขยาย" else "แผนที่ [Tab]"
	end
end

local function toggleOverlayMode()
	isOverlayMode = not isOverlayMode
	applyMapMode()
end

clickToggle.Activated:Connect(toggleOverlayMode)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end
	if input.KeyCode == TOGGLE_OVERLAY_KEY then
		toggleOverlayMode()
	end
end)

-- ==========================================
-- DOT POOLING & COORDINATE PROJECTION
-- ==========================================
local enemyDots: { Frame } = {}
local allyDots: { Frame } = {}
local portalDots: { Frame } = {}
local wallFrames: { Frame } = {}

local function getOrCreateDot(pool: { Frame }, index: number, parent: Instance, size: number, color: Color3, isSquare: boolean, zIndex: number): Frame
	local dot = pool[index]
	if not dot then
		dot = Ui.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color,
			ZIndex = zIndex,
			Parent = parent,
		}, {
			Ui.corner(if isSquare then 2 else size),
			Ui.stroke(Color3.fromRGB(15, 15, 20), 1),
		})
		pool[index] = dot
	end
	dot.Size = UDim2.fromOffset(size, size)
	dot.BackgroundColor3 = color
	dot.Visible = true
	return dot
end

local function hideUnusedDots(pool: { Frame }, usedCount: number)
	for i = usedCount + 1, #pool do
		pool[i].Visible = false
	end
end

-- Project a 3D world offset into 2D minimap coordinates aligned with the camera's horizontal angle
local function worldToMinimap(worldPos: Vector3, originPos: Vector3, rightVec: Vector3, forwardVec: Vector3, viewRadius: number): (number, number, boolean)
	local delta = worldPos - originPos
	local localX = delta.X * rightVec.X + delta.Z * rightVec.Z
	local localY = -(delta.X * forwardVec.X + delta.Z * forwardVec.Z)

	local normX = 0.5 + (localX / (viewRadius * 2))
	local normY = 0.5 + (localY / (viewRadius * 2))
	local inBounds = normX >= 0.03 and normX <= 0.97 and normY >= 0.03 and normY <= 0.97
	return math.clamp(normX, 0.04, 0.96), math.clamp(normY, 0.04, 0.96), inBounds
end

-- ==========================================
-- RENDER STEP UPDATE
-- ==========================================
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	local originPos = rootPart.Position
	local viewRadius = if isOverlayMode then OVERLAY_VIEW_RADIUS else CORNER_VIEW_RADIUS
	local mapPixelSize = if isOverlayMode then OVERLAY_MAP_SIZE else CORNER_MAP_SIZE
	local pixelsPerStud = mapPixelSize / (viewRadius * 2)

	-- Camera horizontal basis vectors so "Up" on the minimap matches "Up" on the screen
	local camLook = camera.CFrame.LookVector
	local forwardVec = Vector3.new(camLook.X, 0, camLook.Z)
	if forwardVec.Magnitude > 0.001 then
		forwardVec = forwardVec.Unit
	else
		forwardVec = Vector3.new(0, 0, -1)
	end
	local rightVec = Vector3.new(-forwardVec.Z, 0, forwardVec.X)

	-- Rotate player's white dot pointer to match character facing relative to camera
	local charLook = rootPart.CFrame.LookVector
	local charX = charLook.X * rightVec.X + charLook.Z * rightVec.Z
	local charY = -(charLook.X * forwardVec.X + charLook.Z * forwardVec.Z)
	selfDot.Rotation = math.deg(math.atan2(charX, -charY))
	selfDot.BackgroundColor3 = SELF_COLOR

	-- 1. Draw Dungeon & Lobby Walls
	local dungeonMap = workspace:FindFirstChild("DungeonMap")
	local wallCount = 0
	if dungeonMap then
		local camYaw = math.deg(math.atan2(-forwardVec.X, -forwardVec.Z))
		for _, child in ipairs(dungeonMap:GetChildren()) do
			if child:IsA("BasePart") and child.CanCollide and child.Name ~= "DungeonEntranceSpawn" then
				local nx, ny, inside = worldToMinimap(child.Position, originPos, rightVec, forwardVec, viewRadius * 1.3)
				if inside then
					wallCount += 1
					local wFrame = wallFrames[wallCount]
					if not wFrame then
						wFrame = Ui.new("Frame", {
							AnchorPoint = Vector2.new(0.5, 0.5),
							BackgroundColor3 = WALL_COLOR,
							BackgroundTransparency = WALL_TRANSPARENCY,
							BorderSizePixel = 0,
							ZIndex = 2,
							Parent = wallLayer,
						})
						wallFrames[wallCount] = wFrame
					end
					wFrame.Visible = true
					wFrame.Position = UDim2.fromScale(nx, ny)
					wFrame.Size = UDim2.fromOffset(
						math.max(2, child.Size.X * pixelsPerStud),
						math.max(2, child.Size.Z * pixelsPerStud)
					)
					wFrame.Rotation = camYaw - child.Orientation.Y
				end
			end
		end
	end
	hideUnusedDots(wallFrames, wallCount)

	-- 2. Draw Portals (Enter Dungeon & Return to Lobby)
	local portalCount = 0
	if dungeonMap then
		for _, child in ipairs(dungeonMap:GetChildren()) do
			if child:IsA("Model") and child.PrimaryPart then
				portalCount += 1
				local isReturn = child.Name == "DungeonReturnPortal"
				local color = if isReturn then RETURN_PORTAL_COLOR else ENTER_PORTAL_COLOR
				local nx, ny = worldToMinimap(child.PrimaryPart.Position, originPos, rightVec, forwardVec, viewRadius)
				local dot = getOrCreateDot(portalDots, portalCount, portalLayer, PORTAL_DOT_SIZE, color, true, 6)
				dot.Position = UDim2.fromScale(nx, ny)
				dot.Rotation = 45 -- Diamond shape
			end
		end
	end
	hideUnusedDots(portalDots, portalCount)

	-- 3. Draw Enemies (Red dots for Grunts, Orange dot for Boss)
	local enemiesFolder = workspace:FindFirstChild("Enemies")
	local enemyDotCount = 0
	local aliveDungeonEnemies = 0
	if enemiesFolder then
		for _, model in ipairs(enemiesFolder:GetChildren()) do
			if model:IsA("Model") and model.Name ~= "TrainingDummy" then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local eRoot = model:FindFirstChild("HumanoidRootPart") :: BasePart?
				if humanoid and eRoot and humanoid.Health > 0 then
					aliveDungeonEnemies += 1
					local isBoss = model:GetAttribute("IsBoss") == true
					local nx, ny, inside = worldToMinimap(eRoot.Position, originPos, rightVec, forwardVec, viewRadius)
					-- Always clamp boss & enemies onto radar edge even if slightly beyond viewRadius so player can find stragglers
					if inside or isBoss or (eRoot.Position - originPos).Magnitude <= viewRadius * 1.6 then
						enemyDotCount += 1
						local size = if isBoss then BOSS_DOT_SIZE else ENEMY_DOT_SIZE
						local color = if isBoss then BOSS_COLOR else ENEMY_COLOR
						local dot = getOrCreateDot(enemyDots, enemyDotCount, enemyLayer, size, color, false, if isBoss then 9 else 7)
						dot.Position = UDim2.fromScale(nx, ny)
					end
				end
			end
		end
	end
	hideUnusedDots(enemyDots, enemyDotCount)
	enemyCountLabel.Text = if aliveDungeonEnemies > 0 then ("ศัตรูเหลือ: %d"):format(aliveDungeonEnemies) else "เคลียร์หมดแล้ว!"
	enemyCountLabel.TextColor3 = if aliveDungeonEnemies > 0 then Color3.fromRGB(255, 130, 130) else Color3.fromRGB(130, 245, 150)

	-- 4. Draw Other Players (Allies)
	local allyCount = 0
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer.Character then
			local aRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local aHum = otherPlayer.Character:FindFirstChildOfClass("Humanoid")
			if aRoot and aHum and aHum.Health > 0 then
				allyCount += 1
				local nx, ny = worldToMinimap(aRoot.Position, originPos, rightVec, forwardVec, viewRadius)
				local dot = getOrCreateDot(allyDots, allyCount, allyLayer, ALLY_DOT_SIZE, ALLY_COLOR, false, 8)
				dot.Position = UDim2.fromScale(nx, ny)
			end
		end
	end
	hideUnusedDots(allyDots, allyCount)
end)
