-- ==========================================
-- MINIMAP CLIENT (Corner Radar + M Overlay Map + Settings Menu with Sub-Pages & Sliders)
-- Path: StarterPlayer.StarterPlayerScripts.MinimapClient
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local teleportRemote = remotesFolder:WaitForChild("TeleportRemote") :: RemoteEvent

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Ui = require(modulesFolder:WaitForChild("Ui"))

-- ==========================================
-- CONFIGURATION & SETTINGS STATE
-- ==========================================
local TOGGLE_OVERLAY_KEY = Enum.KeyCode.M -- Toggle Center Overlay Map
local TOGGLE_SETTING_KEY = Enum.KeyCode.P -- Toggle Settings Window

-- 1. Corner Radar Mode
local cornerMapSize = 185 -- Corner minimap frame size (px)
local cornerViewRadius = 130 -- Corner radar view radius (studs)
local cornerBgTransparency = 0.2 -- Corner background transparency

-- 2. Center Overlay Mode [M]
local overlayMapSize = 460 -- Center overlay map size (px)
local overlayViewRadius = 240 -- Center overlay view radius (studs)
local overlayBgTransparency = 0.45 -- Center overlay background transparency
local overlayStrokeTransparency = 0.3

-- 3. Map Marker Colors & Sizes
local SELF_COLOR = Color3.fromRGB(255, 255, 255) -- Player dot (White)
local SELF_DOT_SIZE = 9

local ALLY_COLOR = Color3.fromRGB(90, 200, 255)
local ALLY_DOT_SIZE = 8

local ENEMY_COLOR = Color3.fromRGB(255, 65, 65)
local ENEMY_DOT_SIZE = 7

local BOSS_COLOR = Color3.fromRGB(255, 165, 40)
local BOSS_DOT_SIZE = 13

local ENTER_PORTAL_COLOR = Color3.fromRGB(80, 210, 255)
local RETURN_PORTAL_COLOR = Color3.fromRGB(255, 215, 70)
local PORTAL_DOT_SIZE = 11

local WALL_COLOR = Color3.fromRGB(130, 140, 165)
local WALL_TRANSPARENCY = 0.35

-- ==========================================
-- STATE & MINIMAP UI CREATION
-- ==========================================
local isOverlayMode = false
local isTouchOnly = Ui.isTouchOnly()
local gui = Ui.screenGui("Minimap", 2)

-- Top-right Corner Minimap Container
local mapFrame = Ui.new("Frame", {
	Name = "MapContainer",
	AnchorPoint = Vector2.new(1, 0),
	Position = if isTouchOnly then UDim2.new(1, -54, 0, 56) else UDim2.new(1, -58, 0, 16),
	Size = UDim2.fromOffset(cornerMapSize, cornerMapSize),
	BackgroundColor3 = Ui.Colors.Panel,
	BackgroundTransparency = cornerBgTransparency,
	ClipsDescendants = true,
	Parent = gui,
}, { Ui.corner(10) })

local mapStroke = Ui.stroke(Ui.Colors.Stroke, 2)
mapStroke.Parent = mapFrame

-- Settings Button next to the Minimap at top-right (no emoji icon)
local settingButton = Ui.button({
	Name = "SettingButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = if isTouchOnly then UDim2.new(1, -8, 0, 56) else UDim2.new(1, -12, 0, 16),
	Size = UDim2.fromOffset(38, 38),
	BackgroundColor3 = Ui.Colors.Panel,
	BackgroundTransparency = 0.15,
	Text = "SET",
	TextSize = 13,
	Parent = gui,
}, { Ui.corner(8), Ui.stroke(Ui.Colors.Accent, 2) })

-- Subtle crosshair lines in center
Ui.new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.9,
	BorderSizePixel = 0,
	Parent = mapFrame,
})
Ui.new("Frame", {
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
	Text = "Map [M]",
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

-- Click/Touch button on minimap to toggle overlay
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
		mapFrame.Size = UDim2.fromOffset(overlayMapSize, overlayMapSize)
		mapFrame.BackgroundTransparency = overlayBgTransparency
		mapStroke.Transparency = overlayStrokeTransparency
		titleLabel.Text = "Overlay Map [M]"
	else
		mapFrame.AnchorPoint = Vector2.new(1, 0)
		mapFrame.Position = if isTouchOnly then UDim2.new(1, -54, 0, 56) else UDim2.new(1, -58, 0, 16)
		mapFrame.Size = UDim2.fromOffset(cornerMapSize, cornerMapSize)
		mapFrame.BackgroundTransparency = cornerBgTransparency
		mapStroke.Transparency = 0
		titleLabel.Text = if isTouchOnly then "Tap to Expand" else "Map [M]"
	end
end

local function toggleOverlayMode()
	isOverlayMode = not isOverlayMode
	applyMapMode()
end

clickToggle.Activated:Connect(toggleOverlayMode)

-- ==========================================
-- SETTINGS WINDOW (MAIN MENU -> SUB-PAGES WITH SLIDERS)
-- ==========================================
local settingsWindow = Ui.new("Frame", {
	Name = "SettingsWindow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(370, 390),
	BackgroundColor3 = Ui.Colors.Panel,
	BackgroundTransparency = 0.04,
	Visible = false,
	Active = true,
	ZIndex = 30,
	Parent = gui,
}, { Ui.corner(12), Ui.stroke(Ui.Colors.Accent, 2) })

-- Top Header Bar
local backBtn = Ui.button({
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.fromOffset(70, 32),
	BackgroundColor3 = Ui.Colors.PanelLight,
	Text = "< Back",
	TextSize = 14,
	Visible = false,
	ZIndex = 32,
	Parent = settingsWindow,
}, { Ui.corner(6) })

local headerTitle = Ui.text({
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -70, 0, 28),
	Text = "Settings [P]",
	TextSize = 19,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 31,
	Parent = settingsWindow,
})

local closeSettingsBtn = Ui.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.fromOffset(32, 32),
	Text = "X",
	TextSize = 16,
	ZIndex = 32,
	Parent = settingsWindow,
}, { Ui.corner(6) })

-- Divider line under header
Ui.new("Frame", {
	Position = UDim2.fromOffset(16, 50),
	Size = UDim2.new(1, -32, 0, 1),
	BackgroundColor3 = Ui.Colors.Stroke,
	BackgroundTransparency = 0.4,
	BorderSizePixel = 0,
	ZIndex = 31,
	Parent = settingsWindow,
})

local pagePos = UDim2.fromOffset(16, 62)
local pageSize = UDim2.new(1, -32, 1, -76)

-- 1. MAIN MENU PAGE (Select a category first)
local mainMenuPage = Ui.new("Frame", {
	Name = "MainMenuPage",
	Position = pagePos,
	Size = pageSize,
	BackgroundTransparency = 1,
	Visible = true,
	ZIndex = 31,
	Parent = settingsWindow,
})

-- 2. MAP SETTINGS SUB-PAGE (Opened only when clicking "Map Settings")
local mapSettingsPage = Ui.new("ScrollingFrame", {
	Name = "MapSettingsPage",
	Position = pagePos,
	Size = pageSize,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = Ui.Colors.Accent,
	CanvasSize = UDim2.new(0, 0, 0, 325),
	Visible = false,
	ZIndex = 31,
	Parent = settingsWindow,
})

-- 3. OTHER SETTINGS SUB-PAGE (Placeholder for future categories)
local otherSettingsPage = Ui.new("Frame", {
	Name = "OtherSettingsPage",
	Position = pagePos,
	Size = pageSize,
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 31,
	Parent = settingsWindow,
})

local function showPage(pageName: string)
	mainMenuPage.Visible = (pageName == "Main")
	mapSettingsPage.Visible = (pageName == "Map")
	otherSettingsPage.Visible = (pageName == "Other")

	if pageName == "Main" then
		backBtn.Visible = false
		headerTitle.Position = UDim2.fromOffset(16, 12)
		headerTitle.Text = "Settings [P]"
	elseif pageName == "Map" then
		backBtn.Visible = true
		headerTitle.Position = UDim2.fromOffset(92, 12)
		headerTitle.Text = "Map Settings"
	elseif pageName == "Other" then
		backBtn.Visible = true
		headerTitle.Position = UDim2.fromOffset(92, 12)
		headerTitle.Text = "Other Settings"
	end
end

backBtn.Activated:Connect(function()
	showPage("Main")
end)

-- ==========================================
-- POPULATE MAIN MENU PAGE
-- ==========================================
Ui.text({
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, 20),
	Text = "Select Category:",
	TextSize = 14,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 32,
	Parent = mainMenuPage,
})

local openMapSettingsBtn = Ui.button({
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 0, 48),
	BackgroundColor3 = Ui.Colors.PanelLight,
	Text = "Map Settings  >",
	TextSize = 16,
	ZIndex = 32,
	Parent = mainMenuPage,
}, { Ui.corner(8), Ui.stroke(Ui.Colors.Stroke, 1) })

openMapSettingsBtn.Activated:Connect(function()
	showPage("Map")
end)

local openOtherSettingsBtn = Ui.button({
	Position = UDim2.fromOffset(0, 86),
	Size = UDim2.new(1, 0, 0, 48),
	BackgroundColor3 = Ui.Colors.PanelLight,
	Text = "Other Settings  >",
	TextSize = 16,
	ZIndex = 32,
	Parent = mainMenuPage,
}, { Ui.corner(8), Ui.stroke(Ui.Colors.Stroke, 1) })

openOtherSettingsBtn.Activated:Connect(function()
	showPage("Other")
end)

-- Divider in main menu
Ui.new("Frame", {
	Position = UDim2.fromOffset(0, 150),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = Ui.Colors.Stroke,
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
	ZIndex = 32,
	Parent = mainMenuPage,
})

Ui.text({
	Position = UDim2.fromOffset(0, 160),
	Size = UDim2.new(1, 0, 0, 20),
	Text = "Quick Actions:",
	TextSize = 14,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 32,
	Parent = mainMenuPage,
})

local warpLobbyBtn = Ui.button({
	Position = UDim2.fromOffset(0, 188),
	Size = UDim2.new(1, 0, 0, 48),
	BackgroundColor3 = Color3.fromRGB(50, 140, 95),
	Text = "Return to Lobby",
	TextSize = 16,
	ZIndex = 32,
	Parent = mainMenuPage,
}, { Ui.corner(8), Ui.stroke(Color3.fromRGB(90, 220, 150), 1.5) })

warpLobbyBtn.Activated:Connect(function()
	teleportRemote:FireServer("Lobby")
	settingsWindow.Visible = false
end)

Ui.text({
	Position = UDim2.fromOffset(0, 250),
	Size = UDim2.new(1, 0, 0, 56),
	Text = "Shortcuts: [B] Inventory  |  [M] Overlay Map  |  [P] Settings",
	TextSize = 13,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Center,
	ZIndex = 32,
	Parent = mainMenuPage,
})

-- ==========================================
-- SLIDER HELPER & POPULATE MAP SETTINGS SUB-PAGE
-- ==========================================
local function createSlider(
	parent: Instance,
	yPos: number,
	labelPrefix: string,
	minVal: number,
	maxVal: number,
	initialVal: number,
	unitSuffix: string,
	onValueChanged: (number) -> ()
)
	local container = Ui.new("Frame", {
		Position = UDim2.fromOffset(0, yPos),
		Size = UDim2.new(1, -12, 0, 52),
		BackgroundTransparency = 1,
		ZIndex = 32,
		Parent = parent,
	})

	local title = Ui.text({
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 20),
		Text = ("%s: %d%s"):format(labelPrefix, initialVal, unitSuffix),
		TextSize = 14,
		TextColor3 = Ui.Colors.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 33,
		Parent = container,
	})

	local track = Ui.new("Frame", {
		Position = UDim2.fromOffset(4, 30),
		Size = UDim2.new(1, -8, 0, 10),
		BackgroundColor3 = Color3.fromRGB(30, 32, 42),
		BorderSizePixel = 0,
		ZIndex = 33,
		Parent = container,
	}, { Ui.corner(5), Ui.stroke(Ui.Colors.Stroke, 1) })

	local initialRatio = math.clamp((initialVal - minVal) / (maxVal - minVal), 0, 1)

	local fill = Ui.new("Frame", {
		Size = UDim2.fromScale(initialRatio, 1),
		BackgroundColor3 = Ui.Colors.Accent,
		BorderSizePixel = 0,
		ZIndex = 34,
		Parent = track,
	}, { Ui.corner(5) })

	local knob = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(initialRatio, 0.5),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		ZIndex = 35,
		Parent = track,
	}, { Ui.corner(9), Ui.stroke(Color3.fromRGB(20, 20, 28), 2) })

	local hitBox = Ui.new("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 12, 0, 28),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 36,
		Parent = track,
	})

	local dragging = false

	local function updateFromScreenX(screenX: number)
		local trackStart = track.AbsolutePosition.X
		local trackWidth = math.max(1, track.AbsoluteSize.X)
		local ratio = math.clamp((screenX - trackStart) / trackWidth, 0, 1)
		local value = math.round(minVal + (maxVal - minVal) * ratio)
		local snappedRatio = (value - minVal) / (maxVal - minVal)

		fill.Size = UDim2.fromScale(snappedRatio, 1)
		knob.Position = UDim2.fromScale(snappedRatio, 0.5)
		title.Text = ("%s: %d%s"):format(labelPrefix, value, unitSuffix)
		onValueChanged(value)
	end

	hitBox.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			updateFromScreenX(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromScreenX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

-- Button to toggle Corner / Overlay inside Map Settings
local toggleMapModeBtn = Ui.button({
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, -12, 0, 38),
	BackgroundColor3 = Ui.Colors.PanelLight,
	Text = "Switch Mode (Corner / Overlay [M])",
	TextSize = 14,
	ZIndex = 32,
	Parent = mapSettingsPage,
}, { Ui.corner(8) })

toggleMapModeBtn.Activated:Connect(function()
	toggleOverlayMode()
end)

-- Slider 1: Corner Map Size (120 px - 260 px)
createSlider(mapSettingsPage, 48, "Corner Map Size", 120, 260, cornerMapSize, " px", function(val)
	cornerMapSize = val
	applyMapMode()
end)

-- Slider 2: Overlay Map Size [M] (300 px - 620 px)
createSlider(mapSettingsPage, 108, "Overlay Map Size [M]", 300, 620, overlayMapSize, " px", function(val)
	overlayMapSize = val
	applyMapMode()
end)

-- Slider 3: Corner Radar Zoom Range (70 studs - 240 studs)
createSlider(mapSettingsPage, 168, "Corner Radar Range", 70, 240, cornerViewRadius, " studs", function(val)
	cornerViewRadius = val
end)

-- Slider 4: Overlay Radar Zoom Range (140 studs - 380 studs)
createSlider(mapSettingsPage, 228, "Overlay Radar Range [M]", 140, 380, overlayViewRadius, " studs", function(val)
	overlayViewRadius = val
end)

-- Slider 5: Map Background Opacity (10% - 95%)
local initialOpacityPct = math.round((1 - cornerBgTransparency) * 100)
createSlider(mapSettingsPage, 288, "Background Opacity", 10, 95, initialOpacityPct, "%", function(val)
	cornerBgTransparency = math.clamp(1 - (val / 100), 0.05, 0.9)
	overlayBgTransparency = math.clamp(cornerBgTransparency + 0.2, 0.1, 0.92)
	applyMapMode()
end)

mapSettingsPage.CanvasSize = UDim2.new(0, 0, 0, 350)

-- ==========================================
-- POPULATE OTHER SETTINGS SUB-PAGE
-- ==========================================
local otherCard = Ui.new("Frame", {
	Position = UDim2.fromOffset(0, 4),
	Size = UDim2.new(1, 0, 0, 260),
	BackgroundColor3 = Ui.Colors.PanelLight,
	BackgroundTransparency = 0.25,
	ZIndex = 32,
	Parent = otherSettingsPage,
}, { Ui.corner(8), Ui.stroke(Ui.Colors.Stroke, 1) })

Ui.text({
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.new(1, -28, 0, 24),
	Text = "Other Settings (Coming Soon)",
	TextSize = 15,
	TextColor3 = Ui.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 33,
	Parent = otherCard,
})

Ui.text({
	Position = UDim2.fromOffset(14, 46),
	Size = UDim2.new(1, -28, 1, -56),
	Text = "Reserved for future settings:\n\n• Audio Volume (BGM / SFX)\n• Show / Hide Damage Numbers\n• Cel-Shade Outline Toggle\n• Camera Sensitivity & Screen Shake",
	TextSize = 14,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	ZIndex = 33,
	Parent = otherCard,
})

local function toggleSettings()
	settingsWindow.Visible = not settingsWindow.Visible
	if settingsWindow.Visible then
		showPage("Main") -- Always start at the Main category menu when opening Settings
	end
end

settingButton.Activated:Connect(toggleSettings)
closeSettingsBtn.Activated:Connect(function()
	settingsWindow.Visible = false
end)

UserInputService.InputBegan:Connect(function(input: InputObject)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == TOGGLE_OVERLAY_KEY then
		toggleOverlayMode()
	elseif input.KeyCode == TOGGLE_SETTING_KEY then
		toggleSettings()
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
	local viewRadius = if isOverlayMode then overlayViewRadius else cornerViewRadius
	local mapPixelSize = if isOverlayMode then overlayMapSize else cornerMapSize
	local pixelsPerStud = mapPixelSize / (viewRadius * 2)

	local camLook = camera.CFrame.LookVector
	local forwardVec = Vector3.new(camLook.X, 0, camLook.Z)
	if forwardVec.Magnitude > 0.001 then
		forwardVec = forwardVec.Unit
	else
		forwardVec = Vector3.new(0, 0, -1)
	end
	local rightVec = Vector3.new(-forwardVec.Z, 0, forwardVec.X)

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

	-- 2. Draw Portals
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
				dot.Rotation = 45
			end
		end
	end
	hideUnusedDots(portalDots, portalCount)

	-- 3. Draw Enemies
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
	enemyCountLabel.Text = if aliveDungeonEnemies > 0 then ("Enemies: %d"):format(aliveDungeonEnemies) else "Cleared!"
	enemyCountLabel.TextColor3 = if aliveDungeonEnemies > 0 then Color3.fromRGB(255, 130, 130) else Color3.fromRGB(130, 245, 150)

	-- 4. Draw Other Players
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
