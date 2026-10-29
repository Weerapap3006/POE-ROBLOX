-- ==========================================
-- MINIMAP CLIENT (Corner Radar + M Overlay Map with Enemies, Boss, Portals & Walls + Categorized Settings)
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
local TOGGLE_OVERLAY_KEY = Enum.KeyCode.M -- ปุ่มสลับขยายแผนที่กลางจอแบบ PoE
local TOGGLE_SETTING_KEY = Enum.KeyCode.P -- ปุ่มเปิด/ปิดหน้าต่าง Settings

-- 1. โหมดมุมขวาบน (Corner Radar Mode)
local cornerMapSize = 185 -- ขนาดกรอบมินิแมพมุมขวาบน
local cornerViewRadius = 130 -- ระยะมองเห็นในมินิแมพมุมขวาบน
local cornerBgTransparency = 0.2 -- ความโปร่งใสพื้นหลังตอนอยู่มุมขวาบน

-- 2. โหมดกด M ขยายกลางจอ (Overlay Mode แบบ PoE)
local overlayMapSize = 460 -- ขนาดแผนที่ตอนกด M มาอยู่กลางจอ
local overlayViewRadius = 240 -- ระยะมองเห็นตอนกด M กลางจอ
local overlayBgTransparency = 0.45 -- ความโปร่งใสพื้นหลังตอนกด M กลางจอ
local overlayStrokeTransparency = 0.3

-- 3. สีและขนาดของจุดสัญลักษณ์ต่างๆ ในแผนที่
local SELF_COLOR = Color3.fromRGB(255, 255, 255) -- สีจุดตัวเรา (สีขาว)
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
-- STATE & UI CREATION
-- ==========================================
local isOverlayMode = false
local isTouchOnly = Ui.isTouchOnly()
local gui = Ui.screenGui("Minimap", 2)

-- Container สำหรับจัดวางมินิแมพมุมขวาบน
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

-- ปุ่ม Setting ⚙️ วางอยู่ข้างๆ มินิแมพ (มุมขวาบน)
local settingButton = Ui.button({
	Name = "SettingButton",
	AnchorPoint = Vector2.new(1, 0),
	Position = if isTouchOnly then UDim2.new(1, -8, 0, 56) else UDim2.new(1, -12, 0, 16),
	Size = UDim2.fromOffset(38, 38),
	BackgroundColor3 = Ui.Colors.Panel,
	BackgroundTransparency = 0.15,
	Text = "⚙️",
	TextSize = 20,
	Parent = gui,
}, { Ui.corner(8), Ui.stroke(Ui.Colors.Accent, 2) })

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
	Text = "แผนที่ [M]",
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
		mapFrame.Size = UDim2.fromOffset(overlayMapSize, overlayMapSize)
		mapFrame.BackgroundTransparency = overlayBgTransparency
		mapStroke.Transparency = overlayStrokeTransparency
		titleLabel.Text = "แผนที่กลางจอ (กด M เพื่อย่อ)"
	else
		mapFrame.AnchorPoint = Vector2.new(1, 0)
		mapFrame.Position = if isTouchOnly then UDim2.new(1, -54, 0, 56) else UDim2.new(1, -58, 0, 16)
		mapFrame.Size = UDim2.fromOffset(cornerMapSize, cornerMapSize)
		mapFrame.BackgroundTransparency = cornerBgTransparency
		mapStroke.Transparency = 0
		titleLabel.Text = if isTouchOnly then "แตะเพื่อขยาย" else "แผนที่ [M]"
	end
end

local function toggleOverlayMode()
	isOverlayMode = not isOverlayMode
	applyMapMode()
end

clickToggle.Activated:Connect(toggleOverlayMode)

-- ==========================================
-- CATEGORIZED SETTINGS WINDOW (หน้าต่างตั้งค่าแบ่งหมวดหมู่)
-- ==========================================
local settingsWindow = Ui.new("Frame", {
	Name = "SettingsWindow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(400, 420),
	BackgroundColor3 = Ui.Colors.Panel,
	BackgroundTransparency = 0.04,
	Visible = false,
	Active = true,
	ZIndex = 30,
	Parent = gui,
}, { Ui.corner(12), Ui.stroke(Ui.Colors.Accent, 2) })

-- Header
Ui.text({
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -70, 0, 28),
	Text = "⚙️ การตั้งค่า (Settings) [P]",
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
	ZIndex = 31,
	Parent = settingsWindow,
}, { Ui.corner(6) })

-- แถบเลือกหมวดหมู่ (Category Tabs)
local tabBar = Ui.new("Frame", {
	Name = "CategoryTabBar",
	Position = UDim2.fromOffset(16, 48),
	Size = UDim2.new(1, -32, 0, 36),
	BackgroundTransparency = 1,
	ZIndex = 31,
	Parent = settingsWindow,
})

local tabMapBtn = Ui.button({
	Position = UDim2.fromScale(0, 0),
	Size = UDim2.new(0.32, 0, 1, 0),
	Text = "🗺️ แผนที่",
	TextSize = 14,
	ZIndex = 32,
	Parent = tabBar,
}, { Ui.corner(8) })

local tabGeneralBtn = Ui.button({
	Position = UDim2.fromScale(0.34, 0),
	Size = UDim2.new(0.32, 0, 1, 0),
	Text = "🏠 ทั่วไป / วาร์ป",
	TextSize = 14,
	ZIndex = 32,
	Parent = tabBar,
}, { Ui.corner(8) })

local tabOtherBtn = Ui.button({
	Position = UDim2.fromScale(0.68, 0),
	Size = UDim2.new(0.32, 0, 1, 0),
	Text = "🔧 อื่นๆ",
	TextSize = 14,
	ZIndex = 32,
	Parent = tabBar,
}, { Ui.corner(8) })

-- เส้นคั่นใต้แถบหมวดหมู่
Ui.new("Frame", {
	Position = UDim2.fromOffset(16, 92),
	Size = UDim2.new(1, -32, 0, 1),
	BackgroundColor3 = Ui.Colors.Stroke,
	BackgroundTransparency = 0.4,
	BorderSizePixel = 0,
	ZIndex = 31,
	Parent = settingsWindow,
})

-- เนื้อหาแต่ละหมวดหมู่ (Category Pages)
local contentAreaPos = UDim2.fromOffset(16, 102)
local contentAreaSize = UDim2.new(1, -32, 1, -116)

local mapPage = Ui.new("Frame", {
	Name = "MapCategoryPage",
	Position = contentAreaPos,
	Size = contentAreaSize,
	BackgroundTransparency = 1,
	Visible = true,
	ZIndex = 31,
	Parent = settingsWindow,
})

local generalPage = Ui.new("Frame", {
	Name = "GeneralCategoryPage",
	Position = contentAreaPos,
	Size = contentAreaSize,
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 31,
	Parent = settingsWindow,
})

local otherPage = Ui.new("Frame", {
	Name = "OtherCategoryPage",
	Position = contentAreaPos,
	Size = contentAreaSize,
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 31,
	Parent = settingsWindow,
})

-- ==========================================
-- หมวดที่ 1: 🗺️ แผนที่ (MAP CATEGORY)
-- ==========================================
local toggleMapBtn = Ui.button({
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundColor3 = Ui.Colors.PanelLight,
	Text = "🗺️ สลับโหมดแผนที่ (มุมขวาบน / กลางจอ [M])",
	TextSize = 14,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(8) })

toggleMapBtn.Activated:Connect(function()
	toggleOverlayMode()
end)

-- 1.1 ขนาดมินิแมพมุมจอ
local sizeLabel = Ui.text({
	Position = UDim2.fromOffset(0, 44),
	Size = UDim2.new(1, 0, 0, 20),
	Text = ("ขนาดมินิแมพมุมจอ: %d px"):format(cornerMapSize),
	TextSize = 13,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 32,
	Parent = mapPage,
})

local btnSmall = Ui.button({
	Position = UDim2.fromOffset(0, 66),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "เล็ก (150)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local btnMed = Ui.button({
	Position = UDim2.new(0.345, 0, 0, 66),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "กลาง (185)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local btnBig = Ui.button({
	Position = UDim2.new(0.69, 0, 0, 66),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "ใหญ่ (230)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local function setCornerSize(sz: number)
	cornerMapSize = sz
	sizeLabel.Text = ("ขนาดมินิแมพมุมจอ: %d px"):format(cornerMapSize)
	applyMapMode()
end
btnSmall.Activated:Connect(function() setCornerSize(150) end)
btnMed.Activated:Connect(function() setCornerSize(185) end)
btnBig.Activated:Connect(function() setCornerSize(230) end)

-- 1.2 ขนาดแผนที่กลางจอตอนกด M
local overlaySizeLabel = Ui.text({
	Position = UDim2.fromOffset(0, 104),
	Size = UDim2.new(1, 0, 0, 20),
	Text = ("ขนาดแผนที่กลางจอ [M]: %d px"):format(overlayMapSize),
	TextSize = 13,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 32,
	Parent = mapPage,
})

local btnOvSmall = Ui.button({
	Position = UDim2.fromOffset(0, 126),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "เล็ก (380)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local btnOvMed = Ui.button({
	Position = UDim2.new(0.345, 0, 0, 126),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "กลาง (460)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local btnOvBig = Ui.button({
	Position = UDim2.new(0.69, 0, 0, 126),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "ใหญ่ (560)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local function setOverlaySize(sz: number)
	overlayMapSize = sz
	overlaySizeLabel.Text = ("ขนาดแผนที่กลางจอ [M]: %d px"):format(overlayMapSize)
	applyMapMode()
end
btnOvSmall.Activated:Connect(function() setOverlaySize(380) end)
btnOvMed.Activated:Connect(function() setOverlaySize(460) end)
btnOvBig.Activated:Connect(function() setOverlaySize(560) end)

-- 1.3 ระยะเรดาร์ (Zoom)
local zoomLabel = Ui.text({
	Position = UDim2.fromOffset(0, 164),
	Size = UDim2.new(1, 0, 0, 20),
	Text = ("ระยะเรดาร์มินิแมพ: %d studs"):format(cornerViewRadius),
	TextSize = 13,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 32,
	Parent = mapPage,
})

local btnZoomNear = Ui.button({
	Position = UDim2.fromOffset(0, 186),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "ใกล้ (90)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local btnZoomMed = Ui.button({
	Position = UDim2.new(0.345, 0, 0, 186),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "ปกติ (130)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local btnZoomFar = Ui.button({
	Position = UDim2.new(0.69, 0, 0, 186),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "ไกล (200)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local function setZoomRadius(rad: number)
	cornerViewRadius = rad
	zoomLabel.Text = ("ระยะเรดาร์มินิแมพ: %d studs"):format(cornerViewRadius)
end
btnZoomNear.Activated:Connect(function() setZoomRadius(90) end)
btnZoomMed.Activated:Connect(function() setZoomRadius(130) end)
btnZoomFar.Activated:Connect(function() setZoomRadius(200) end)

-- 1.4 ความโปร่งใสพื้นหลัง
Ui.text({
	Position = UDim2.fromOffset(0, 224),
	Size = UDim2.new(1, 0, 0, 20),
	Text = "ความโปร่งใสพื้นหลังแผนที่:",
	TextSize = 13,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 32,
	Parent = mapPage,
})

local btnTransSolid = Ui.button({
	Position = UDim2.fromOffset(0, 246),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "ทึบ (ชัดเจน)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local btnTransNormal = Ui.button({
	Position = UDim2.new(0.345, 0, 0, 246),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "ปกติ",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

local btnTransGlass = Ui.button({
	Position = UDim2.new(0.69, 0, 0, 246),
	Size = UDim2.new(0.31, 0, 0, 30),
	Text = "ใส (มองทะลุ)",
	TextSize = 13,
	ZIndex = 32,
	Parent = mapPage,
}, { Ui.corner(6) })

btnTransSolid.Activated:Connect(function()
	cornerBgTransparency = 0.05
	overlayBgTransparency = 0.2
	applyMapMode()
end)

btnTransNormal.Activated:Connect(function()
	cornerBgTransparency = 0.2
	overlayBgTransparency = 0.45
	applyMapMode()
end)

btnTransGlass.Activated:Connect(function()
	cornerBgTransparency = 0.5
	overlayBgTransparency = 0.65
	applyMapMode()
end)

-- ==========================================
-- หมวดที่ 2: 🏠 ทั่วไป / วาร์ป (GENERAL CATEGORY)
-- ==========================================
Ui.text({
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(1, 0, 0, 22),
	Text = "คำสั่งด่วนและการเดินทาง:",
	TextSize = 14,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 32,
	Parent = generalPage,
})

local warpLobbyBtn = Ui.button({
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundColor3 = Color3.fromRGB(50, 140, 95),
	Text = "🏠 วาร์ปกลับโซนปลอดภัย (Lobby) ทันที",
	TextSize = 16,
	ZIndex = 32,
	Parent = generalPage,
}, { Ui.corner(8), Ui.stroke(Color3.fromRGB(90, 220, 150), 1.5) })

warpLobbyBtn.Activated:Connect(function()
	teleportRemote:FireServer("Lobby")
	settingsWindow.Visible = false
end)

local keybindCard = Ui.new("Frame", {
	Position = UDim2.fromOffset(0, 90),
	Size = UDim2.new(1, 0, 0, 180),
	BackgroundColor3 = Ui.Colors.PanelLight,
	BackgroundTransparency = 0.2,
	ZIndex = 32,
	Parent = generalPage,
}, { Ui.corner(8), Ui.stroke(Ui.Colors.Stroke, 1) })

Ui.text({
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.new(1, -24, 0, 22),
	Text = "⌨️ ปุ่มลัดในเกม (Shortcuts)",
	TextSize = 15,
	TextColor3 = Ui.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 33,
	Parent = keybindCard,
})

Ui.text({
	Position = UDim2.fromOffset(12, 38),
	Size = UDim2.new(1, -24, 1, -46),
	Text = "• ปุ่ม [B] : เปิด / ปิด กระเป๋าไอเทม\n• ปุ่ม [M] : สลับแผนที่มุมจอ / ขยายกลางจอ\n• ปุ่ม [P] : เปิด / ปิด หน้าต่างตั้งค่า\n• คลิกซ้าย (ค้างได้) : โจมตีปกติ (ฟันดาบ)\n• คลิกขวา หรือ [Q] : สกิลหมุนฟันรอบตัว\n• ลูกกลิ้งเมาส์ : ซูมกล้องเข้า - ออก",
	TextSize = 14,
	TextColor3 = Ui.Colors.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 33,
	Parent = keybindCard,
})

-- ==========================================
-- หมวดที่ 3: 🔧 อื่นๆ (OTHERS CATEGORY - เผื่อเพิ่มในอนาคต)
-- ==========================================
local otherCard = Ui.new("Frame", {
	Position = UDim2.fromOffset(0, 8),
	Size = UDim2.new(1, 0, 0, 260),
	BackgroundColor3 = Ui.Colors.PanelLight,
	BackgroundTransparency = 0.25,
	ZIndex = 32,
	Parent = otherPage,
}, { Ui.corner(8), Ui.stroke(Ui.Colors.Stroke, 1) })

Ui.text({
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.new(1, -28, 0, 24),
	Text = "🔧 หมวดตั้งค่าอื่นๆ (เตรียมไว้สำหรับอัปเดตถัดไป)",
	TextSize = 15,
	TextColor3 = Ui.Colors.Accent,
	TextXAlignment = Enum.TextXAlignment.Left,
	ZIndex = 33,
	Parent = otherCard,
})

Ui.text({
	Position = UDim2.fromOffset(14, 46),
	Size = UDim2.new(1, -28, 1, -56),
	Text = "หมวดหมู่นี้เตรียมโครงสร้างไว้สำหรับใส่การตั้งค่าเพิ่มเติมในอนาคต เช่น:\n\n• 🔊 ปรับระดับเสียงเพลงประกอบ (BGM) และเสียงฟันดาบ (SFX)\n• ✨ เปิด / ปิด ตัวเลขดาเมจเด้ง (Damage Numbers)\n• 🎨 เปิด / ปิด เส้นขอบการ์ตูน (Cel-Shade Outline) เพื่อลดแลค\n• 📷 ตั้งค่าความไวกล้องและการสั่นหน้าจอ (Screen Shake)",
	TextSize = 14,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	ZIndex = 33,
	Parent = otherCard,
})

-- ฟังก์ชันสลับหมวดหมู่ (Switch Category Tab)
local function selectCategory(category: string)
	mapPage.Visible = (category == "Map")
	generalPage.Visible = (category == "General")
	otherPage.Visible = (category == "Other")

	tabMapBtn.BackgroundColor3 = if category == "Map" then Ui.Colors.Accent else Ui.Colors.PanelLight
	tabGeneralBtn.BackgroundColor3 = if category == "General" then Ui.Colors.Accent else Ui.Colors.PanelLight
	tabOtherBtn.BackgroundColor3 = if category == "Other" then Ui.Colors.Accent else Ui.Colors.PanelLight
end

tabMapBtn.Activated:Connect(function() selectCategory("Map") end)
tabGeneralBtn.Activated:Connect(function() selectCategory("General") end)
tabOtherBtn.Activated:Connect(function() selectCategory("Other") end)

-- เริ่มต้นที่หมวดหมู่แผนที่
selectCategory("Map")

local function toggleSettings()
	settingsWindow.Visible = not settingsWindow.Visible
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
	enemyCountLabel.Text = if aliveDungeonEnemies > 0 then ("ศัตรูเหลือ: %d"):format(aliveDungeonEnemies) else "เคลียร์หมดแล้ว!"
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
