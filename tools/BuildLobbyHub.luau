-- ==========================================
-- BUILD LOBBY HUB (Studio Command Bar tool, NOT a game script)
-- File: tools/BuildLobbyHub.luau (outside src/, so Rojo never puts it in the game)
-- ==========================================
-- How to use: open the place in Studio (Team Create), View -> Command Bar, paste this whole file, press Enter.
-- It builds a blockout stone town around the Lobby's SpawnLocation into Workspace.LobbyHub:
--   * a paved plaza + a paved path to LobbyDungeonPortal (flat, no collision: players can't jump)
--   * a Stone Tablet altar next to the portal
--   * a monument with the three class banners (Warrior / Ranger / Mystic)
--   * placeholder spots for later features: Stash, Merchant, Crafting Bench, Notice Board
--     (each Model has a "HubSpot" attribute so code can find it later)
--   * lamp posts around the plaza
-- Then move / edit the pieces by hand like any other map part.
-- Safety:
--   * Only adds Workspace.LobbyHub. Running it again REPLACES that folder (hand edits inside it are lost),
--     nothing else in the map is touched. Ctrl+Z undoes the whole build
--   * A piece that would overlap something already in the map is skipped (listed in the Output window)
--   * Not inside Workspace.DungeonMap on purpose: the minimap draws DungeonMap's parts as walls
local ChangeHistoryService = game:GetService("ChangeHistoryService")

-- ==========================================
-- CONFIGURATION
-- ==========================================
local HUB_NAME = "LobbyHub"
local PLAZA_RADIUS = 34
local LAMP_RADIUS = 31
local PATH_WIDTH = 10

local STONE = Color3.fromRGB(118, 112, 106)
local STONE_DARK = Color3.fromRGB(78, 74, 70)
local PAVING = Color3.fromRGB(96, 92, 88)
local MOSAIC = Color3.fromRGB(132, 120, 104)
local WOOD = Color3.fromRGB(116, 84, 58)
local GLOW = Color3.fromRGB(255, 196, 120) -- Lamp light
local FLAME = Color3.fromRGB(255, 140, 50) -- Small neon flame inside each lantern (a big bright neon block blooms to white)
local IRON = Color3.fromRGB(45, 42, 40)
local RUNE_GLOW = Color3.fromRGB(235, 150, 80) -- Same orange as stone runes in the game
local CLASS_COLORS = {
	Warrior = Color3.fromRGB(225, 95, 80),
	Ranger = Color3.fromRGB(120, 215, 120),
	Mystic = Color3.fromRGB(120, 160, 255),
}

-- ==========================================
-- 1. FIND THE LOBBY
-- ==========================================
local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
if not spawnLocation then
	warn("[LobbyHub] No SpawnLocation in Workspace. The hub is built around it, so nothing was built")
	return
end

local function getPosition(instance: Instance?): Vector3?
	if not instance then
		return nil
	elseif instance:IsA("BasePart") then
		return instance.Position
	elseif instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	return if part then part.Position else nil
end

local dungeonMap = workspace:FindFirstChild("DungeonMap")
local portalPosition = getPosition(dungeonMap and dungeonMap:FindFirstChild("LobbyDungeonPortal"))

-- Undo support (Ctrl+Z removes the whole build)
local recording: string? = nil
pcall(function()
	recording = ChangeHistoryService:TryBeginRecording("Build Lobby Hub")
end)
if not recording then
	ChangeHistoryService:SetWaypoint("Before Lobby Hub")
end

local old = workspace:FindFirstChild(HUB_NAME)
if old then
	old:Destroy()
end
local hub = Instance.new("Folder")
hub.Name = HUB_NAME
hub.Parent = workspace
local floorFolder = Instance.new("Folder")
floorFolder.Name = "Floor"
floorFolder.Parent = hub

-- Ground height under the spawn (the spawn pad itself is skipped)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { spawnLocation, hub }
local hit = workspace:Raycast(spawnLocation.Position, Vector3.new(0, -100, 0), rayParams)
local groundY = if hit then hit.Position.Y else spawnLocation.Position.Y - spawnLocation.Size.Y / 2
local origin = Vector3.new(spawnLocation.Position.X, groundY, spawnLocation.Position.Z)

-- Local directions: forward = toward the dungeon portal (or -Z without one), right = to its right
local forward = Vector3.new(0, 0, -1)
if portalPosition then
	local flat = Vector3.new(portalPosition.X - origin.X, 0, portalPosition.Z - origin.Z)
	if flat.Magnitude > 1 then
		forward = flat.Unit
	end
end
local right = forward:Cross(Vector3.yAxis)

local function toWorld(x: number, z: number): Vector3
	return origin + right * x + forward * z
end

-- Ground-level CFrame at (x, z) turned to face the plaza center
local function facingCenter(position: Vector3): CFrame
	local look = Vector3.new(origin.X, position.Y, origin.Z)
	if (look - position).Magnitude < 0.1 then
		return CFrame.new(position)
	end
	return CFrame.lookAt(position, look)
end

-- ==========================================
-- 2. HELPERS
-- ==========================================
local function newPart(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Decoration players walk over or through: no collision, no clicks / raycasts, no shadow
local function makeDecor(part: BasePart)
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function addLight(parent: BasePart, range: number, brightness: number, color: Color3)
	local light = Instance.new("PointLight")
	light.Range = range
	light.Brightness = brightness
	light.Color = color
	light.Shadows = false
	light.Parent = parent
end

local function addLabel(parent: BasePart, title: string, subtitle: string?, height: number)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Size = UDim2.fromOffset(200, if subtitle then 46 else 26)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	billboard.MaxDistance = 70
	billboard.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 26)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(240, 230, 210)
	label.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	label.TextStrokeTransparency = 0
	label.Text = title
	label.Parent = billboard

	if subtitle then
		local sub = label:Clone()
		sub.Position = UDim2.fromOffset(0, 24)
		sub.Size = UDim2.new(1, 0, 0, 20)
		sub.TextSize = 13
		sub.TextColor3 = Color3.fromRGB(170, 165, 155)
		sub.Text = subtitle
		sub.Parent = billboard
	end
end

-- Highest point of a part (works for rotated parts too)
local function topOf(part: BasePart): number
	local cf, size = part.CFrame, part.Size
	local extent = math.abs(cf.RightVector.Y) * size.X / 2 + math.abs(cf.UpVector.Y) * size.Y / 2 + math.abs(cf.LookVector.Y) * size.Z / 2
	return cf.Position.Y + extent
end

-- Is anything already standing in this footprint? (the ground and flat floors don't count)
local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.FilterDescendantsInstances = { spawnLocation, floorFolder, workspace.Terrain }
local function findBlocker(groundCFrame: CFrame, footprint: Vector3): BasePart?
	local box = groundCFrame * CFrame.new(0, 0.6 + footprint.Y / 2, 0)
	for _, other in ipairs(workspace:GetPartBoundsInBox(box, footprint, overlapParams)) do
		if topOf(other) > groundY + 0.6 then
			return other
		end
	end
	return nil
end

local built, skipped = 0, {}
local function newModel(name: string, groundCFrame: CFrame, footprint: Vector3): Model?
	local blocker = findBlocker(groundCFrame, footprint)
	if blocker then
		table.insert(skipped, ("%s (would overlap %s)"):format(name, blocker:GetFullName()))
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = hub
	built += 1
	return model
end

-- ==========================================
-- 3. FLOOR (flat, no collision)
-- ==========================================
-- Cylinders lie on their side by default: turn them so the round face points up
local function disc(name: string, radius: number, thickness: number, color: Color3, material: Enum.Material, lift: number)
	local part = newPart(floorFolder, name, Vector3.new(thickness, radius * 2, radius * 2),
		CFrame.new(origin + Vector3.new(0, lift - thickness / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	part.Shape = Enum.PartType.Cylinder
	makeDecor(part)
end

disc("Plaza", PLAZA_RADIUS, 0.3, PAVING, Enum.Material.Cobblestone, 0.05)
disc("PlazaRing", PLAZA_RADIUS - 2, 0.3, STONE_DARK, Enum.Material.Slate, 0.07)
disc("PlazaInner", PLAZA_RADIUS - 3, 0.3, PAVING, Enum.Material.Cobblestone, 0.09)
disc("Mosaic", 10, 0.3, MOSAIC, Enum.Material.Slate, 0.11)
disc("MosaicCore", 6, 0.3, STONE_DARK, Enum.Material.Slate, 0.13)

-- Path from the plaza edge to the portal
if portalPosition then
	local distance = Vector3.new(portalPosition.X - origin.X, 0, portalPosition.Z - origin.Z).Magnitude
	local startZ, endZ = PLAZA_RADIUS - 3, distance - 4
	if endZ > startZ then
		local length = endZ - startZ
		local middle = toWorld(0, startZ + length / 2) + Vector3.new(0, 0.05 - 0.15, 0)
		local path = newPart(floorFolder, "PortalPath", Vector3.new(PATH_WIDTH, 0.3, length),
			CFrame.lookAt(middle, middle + forward), PAVING, Enum.Material.Cobblestone)
		makeDecor(path)
		for _, side in ipairs({ -1, 1 }) do
			local edge = newPart(floorFolder, "PathEdge", Vector3.new(0.8, 0.3, length),
				CFrame.lookAt(middle + right * side * (PATH_WIDTH / 2 + 0.4) + Vector3.new(0, 0.02, 0), middle + forward), STONE_DARK, Enum.Material.Slate)
			makeDecor(edge)
		end
	end
end

-- ==========================================
-- 4. STRUCTURES (solid, along the edges)
-- ==========================================
-- Monument behind the spawn: stepped base, obelisk, glowing crystal on top
local function buildMonument(position: Vector3)
	local cf = facingCenter(position)
	local model = newModel("Monument", cf, Vector3.new(10, 18, 10))
	if not model then
		return
	end
	newPart(model, "Base", Vector3.new(10, 1.2, 10), cf * CFrame.new(0, 0.6, 0), STONE_DARK, Enum.Material.Slate)
	newPart(model, "Pedestal", Vector3.new(6, 2, 6), cf * CFrame.new(0, 2.2, 0), STONE, Enum.Material.Slate)
	newPart(model, "Obelisk", Vector3.new(3, 12, 3), cf * CFrame.new(0, 9.2, 0), STONE, Enum.Material.Slate)
	local crystal = newPart(model, "Crystal", Vector3.new(2, 2, 2),
		cf * CFrame.new(0, 16.6, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), RUNE_GLOW, Enum.Material.Neon)
	crystal.CanCollide = false
	addLight(crystal, 20, 1.6, RUNE_GLOW)
end

-- Class banner on a pole
local function buildBanner(position: Vector3, classId: string)
	local cf = facingCenter(position)
	local model = newModel(classId .. "Banner", cf, Vector3.new(4, 14, 1.5))
	if not model then
		return
	end
	newPart(model, "Pole", Vector3.new(0.6, 14, 0.6), cf * CFrame.new(0, 7, 0), WOOD, Enum.Material.Wood)
	local bar = newPart(model, "Bar", Vector3.new(4.4, 0.4, 0.4), cf * CFrame.new(0, 13, -0.4), WOOD, Enum.Material.Wood)
	bar.CanCollide = false
	local cloth = newPart(model, "Cloth", Vector3.new(4, 7, 0.15), cf * CFrame.new(0, 9.3, -0.45), CLASS_COLORS[classId], Enum.Material.Fabric)
	makeDecor(cloth)
	addLabel(cloth, classId, nil, 5)
end

-- Stone Tablet altar next to the portal: steps, pillar, a tilted tablet with a glowing rune line
local function buildAltar(position: Vector3)
	local cf = facingCenter(position)
	local model = newModel("TabletAltar", cf, Vector3.new(8, 6, 8))
	if not model then
		return
	end
	model:SetAttribute("HubSpot", "TabletAltar")
	newPart(model, "Step1", Vector3.new(8, 1, 8), cf * CFrame.new(0, 0.5, 0), STONE_DARK, Enum.Material.Slate)
	newPart(model, "Step2", Vector3.new(5.5, 1, 5.5), cf * CFrame.new(0, 1.5, 0), STONE, Enum.Material.Slate)
	newPart(model, "Pillar", Vector3.new(3, 2.4, 3), cf * CFrame.new(0, 3.2, 0), STONE, Enum.Material.Slate)
	local tablet = newPart(model, "Tablet", Vector3.new(3.4, 0.5, 2.6),
		cf * CFrame.new(0, 4.7, 0) * CFrame.Angles(math.rad(-25), 0, 0), STONE_DARK, Enum.Material.Slate)
	local rune = newPart(model, "RuneLine", Vector3.new(2.4, 0.1, 0.25),
		tablet.CFrame * CFrame.new(0, 0.28, 0), RUNE_GLOW, Enum.Material.Neon)
	makeDecor(rune)
	addLight(rune, 10, 1.2, RUNE_GLOW)
	addLabel(tablet, "Stone Tablet Altar", "Place tablets from your Inventory", 3)
end

-- Market-style stall: posts, counter, cloth roof, crates. Placeholder for a later feature
local function buildStall(position: Vector3, name: string, spot: string, roofColor: Color3)
	local cf = facingCenter(position)
	local model = newModel(spot, cf, Vector3.new(10, 8, 7))
	if not model then
		return
	end
	model:SetAttribute("HubSpot", spot)
	for _, x in ipairs({ -4.5, 4.5 }) do
		for _, z in ipairs({ -3, 3 }) do
			newPart(model, "Post", Vector3.new(0.7, 7, 0.7), cf * CFrame.new(x, 3.5, z), WOOD, Enum.Material.Wood)
		end
	end
	newPart(model, "Counter", Vector3.new(8, 3, 1.6), cf * CFrame.new(0, 1.5, -2.2), WOOD, Enum.Material.WoodPlanks)
	local roof = newPart(model, "Roof", Vector3.new(10.4, 0.4, 7.6),
		cf * CFrame.new(0, 7.2, 0) * CFrame.Angles(math.rad(8), 0, 0), roofColor, Enum.Material.Fabric)
	roof.CanCollide = false
	newPart(model, "Crate", Vector3.new(2, 2, 2), cf * CFrame.new(-3, 1, 2), WOOD, Enum.Material.WoodPlanks)
	newPart(model, "Crate", Vector3.new(1.6, 1.6, 1.6), cf * CFrame.new(-0.8, 0.8, 2.3) * CFrame.Angles(0, math.rad(20), 0), WOOD, Enum.Material.WoodPlanks)
	addLabel(roof, name, "Coming soon", 2.5)
end

-- Notice board: two posts and a plank board
local function buildNoticeBoard(position: Vector3)
	local cf = facingCenter(position)
	local model = newModel("NoticeBoard", cf, Vector3.new(7, 7, 2))
	if not model then
		return
	end
	model:SetAttribute("HubSpot", "NoticeBoard")
	for _, x in ipairs({ -3, 3 }) do
		newPart(model, "Post", Vector3.new(0.6, 7, 0.6), cf * CFrame.new(x, 3.5, 0), WOOD, Enum.Material.Wood)
	end
	local board = newPart(model, "Board", Vector3.new(6.4, 3.6, 0.3), cf * CFrame.new(0, 4.6, -0.3), WOOD, Enum.Material.WoodPlanks)
	for index, size in ipairs({ Vector2.new(1.6, 1.2), Vector2.new(1.2, 1.6), Vector2.new(1.4, 1) }) do
		local note = newPart(model, "Note", Vector3.new(size.X, size.Y, 0.05),
			board.CFrame * CFrame.new(-2.2 + (index - 1) * 2.1, 0.2 * (index % 2), -0.18) * CFrame.Angles(0, 0, math.rad(4 - index * 3)),
			Color3.fromRGB(225, 215, 190), Enum.Material.SmoothPlastic)
		makeDecor(note)
	end
	addLabel(board, "Notice Board", "Coming soon", 3)
end

-- Lamp post: a dark iron lantern with a small flame inside and a warm light
-- (mobile: lights are kept few and without shadows)
local function buildLamp(position: Vector3, index: number)
	local cf = facingCenter(position)
	local model = newModel("Lamp" .. index, cf, Vector3.new(1.8, 10, 1.8))
	if not model then
		return
	end
	newPart(model, "Base", Vector3.new(1.6, 0.8, 1.6), cf * CFrame.new(0, 0.4, 0), STONE_DARK, Enum.Material.Slate)
	newPart(model, "Post", Vector3.new(0.7, 8, 0.7), cf * CFrame.new(0, 4.8, 0), STONE_DARK, Enum.Material.Slate)
	local cap = newPart(model, "LanternCap", Vector3.new(1.4, 0.3, 1.4), cf * CFrame.new(0, 10.2, 0), IRON, Enum.Material.Metal)
	cap.CanCollide = false
	local lantern = newPart(model, "Lantern", Vector3.new(1.1, 1.3, 1.1), cf * CFrame.new(0, 9.4, 0), IRON, Enum.Material.Glass)
	lantern.Transparency = 0.45
	lantern.CanCollide = false
	local flame = newPart(model, "Flame", Vector3.new(0.45, 0.6, 0.45), cf * CFrame.new(0, 9.35, 0), FLAME, Enum.Material.Neon)
	makeDecor(flame)
	addLight(flame, 18, 1.3, GLOW)
end

buildMonument(toWorld(0, -20))
buildBanner(toWorld(-10, -22), "Warrior")
buildBanner(toWorld(10, -22), "Ranger")
buildBanner(toWorld(0, -29), "Mystic")
buildAltar(if portalPosition
	then Vector3.new(portalPosition.X, groundY, portalPosition.Z) - forward * 6 + right * 11
	else toWorld(14, 22))
buildStall(toWorld(-25, 2), "Stash", "Stash", Color3.fromRGB(95, 110, 150))
buildStall(toWorld(25, 2), "Merchant", "Merchant", Color3.fromRGB(150, 95, 80))
buildStall(toWorld(-21, -15), "Crafting Bench", "CraftingBench", Color3.fromRGB(110, 120, 130))
buildNoticeBoard(toWorld(21, -15))
for index = 1, 8 do
	local angle = math.rad(22.5 + (index - 1) * 45)
	buildLamp(toWorld(math.sin(angle) * LAMP_RADIUS, math.cos(angle) * LAMP_RADIUS), index)
end

-- ==========================================
-- 5. DONE
-- ==========================================
if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
else
	ChangeHistoryService:SetWaypoint("Build Lobby Hub")
end

print(("[LobbyHub] Built %d pieces in Workspace.%s (facing %s)"):format(
	built, HUB_NAME, if portalPosition then "the dungeon portal" else "-Z: no LobbyDungeonPortal found"))
for _, line in ipairs(skipped) do
	warn("[LobbyHub] Skipped " .. line)
end
