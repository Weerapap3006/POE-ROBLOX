-- ==========================================
-- PASSIVE TREE CLIENT (Class picker + passive tree window, key K)
-- Path: StarterPlayer.StarterPlayerScripts.PassiveTreeClient
-- ==========================================
-- The server owns the tree (PlayerData). This window shows the last "Sync" (Class, Passives) and sends
-- ChooseClass / AllocatePassive / ResetPassives through InventoryRemote. Points = level - 1 (Level attribute).
-- The tree itself (nodes, links, classes, rules) is ReplicatedStorage.Modules.PassiveData
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local inventoryRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InventoryRemote") :: RemoteEvent

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local PassiveData = require(modulesFolder:WaitForChild("PassiveData"))
local ItemData = require(modulesFolder:WaitForChild("ItemData"))
local HeroData = require(modulesFolder:WaitForChild("HeroData"))
local Ui = require(modulesFolder:WaitForChild("Ui"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
local TOGGLE_KEY = Enum.KeyCode.K
local SPACING = 50 -- Pixels between grid cells (PassiveData Position)
local MARGIN = 24 -- Empty space around the tree
local NODE_SIZES = { Start = 42, Notable = 36, Small = 26 }
local SIDE_WIDTH = 220
local TREE_WIDTH = (PassiveData.GRID_SIZE.X - 1) * SPACING + MARGIN * 2
local TREE_HEIGHT = (PassiveData.GRID_SIZE.Y - 1) * SPACING + MARGIN * 2
local WINDOW_WIDTH = 16 + TREE_WIDTH + 16 + SIDE_WIDTH + 16
local WINDOW_HEIGHT = 52 + TREE_HEIGHT + 16
local ALLOCATED_COLOR = Color3.fromRGB(240, 190, 60)
local LINE_COLOR = Color3.fromRGB(70, 75, 90)
local CAN_TAKE_COLOR = Color3.fromRGB(130, 220, 140)

-- ==========================================
-- STATE (class + passives replaced by every "Sync" from the server)
-- ==========================================
local classId: string? = nil
local heroVariant: string? = nil -- Hero path of the class (HeroData), from HeroData.VARIANT_LEVEL
local passives: { string } = {}
local synced = false
local selectedNode: string? = nil
local confirmingReset = false
local showingClassPicker = false -- "Change Class" pressed (with no class yet the picker always shows)
local showingPathPicker = false -- "Hero Path" pressed

local isTouchOnly = Ui.isTouchOnly()

local function getLevel(): number
	return player:GetAttribute("Level") or 1
end

local function getPointsLeft(): number
	return PassiveData.getPoints(getLevel()) - #passives
end

local function isAllocated(nodeId: string): boolean
	local class = if classId then PassiveData.Classes[classId] else nil
	return (class ~= nil and class.Start == nodeId) or table.find(passives, nodeId) ~= nil
end

-- The class whose Start node this is (nil for every other node)
local function getStartClass(nodeId: string): PassiveData.Class?
	for _, class in pairs(PassiveData.Classes) do
		if class.Start == nodeId then
			return class
		end
	end
	return nil
end

local function canTake(nodeId: string): boolean
	return classId ~= nil and getPointsLeft() > 0 and PassiveData.whyNot(classId, passives, nodeId) == nil
end

local function statLines(stats: { [string]: number }): { string }
	local lines = {}
	for stat, value in pairs(stats) do
		table.insert(lines, ItemData.formatStat(stat, value))
	end
	table.sort(lines)
	return lines
end

-- ==========================================
-- 1. WINDOW LAYOUT (tree | details) + class picker on top
-- ==========================================
local gui = Ui.screenGui("PassiveTree", 6)

-- PC: bottom-right, next to the Inventory button. Mobile: top-right, next to it too
local toggleButton = Ui.button({
	Name = "ToggleButton",
	AnchorPoint = if isTouchOnly then Vector2.new(1, 0) else Vector2.new(1, 1),
	Position = if isTouchOnly then UDim2.new(1, -150, 0, 8) else UDim2.new(1, -156, 1, -16),
	Size = UDim2.fromOffset(130, 40),
	BackgroundColor3 = Ui.Colors.Panel,
	BackgroundTransparency = 0.15,
	Text = "",
	Parent = gui,
}, { Ui.corner(8), Ui.stroke(ALLOCATED_COLOR, 2) })

local window = Ui.new("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT),
	BackgroundColor3 = Ui.Colors.Panel,
	BackgroundTransparency = 0.05,
	Active = true, -- Clicks on the window don't fall through and attack
	Visible = false,
	Parent = gui,
}, { Ui.corner(10), Ui.stroke(ALLOCATED_COLOR, 2) })

-- Shrink the window to fit small (phone) screens
local uiScale = Ui.new("UIScale", { Parent = window })
local function updateScale()
	local viewport = workspace.CurrentCamera.ViewportSize
	uiScale.Scale = math.min(1, (viewport.X - 20) / WINDOW_WIDTH, (viewport.Y - 20) / WINDOW_HEIGHT)
end
updateScale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

Ui.text({
	Position = UDim2.fromOffset(16, 10),
	Size = UDim2.new(1, -80, 0, 32),
	Text = if isTouchOnly then "Passive Tree" else "Passive Tree [K]",
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = window,
})
local closeButton = Ui.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 10),
	Size = UDim2.fromOffset(32, 32),
	Text = "X",
	Parent = window,
}, { Ui.corner(6) })

-- Left: the tree. Links are thin rotated frames under the round node buttons
local tree = Ui.new("Frame", {
	Name = "Tree",
	Position = UDim2.fromOffset(16, 52),
	Size = UDim2.fromOffset(TREE_WIDTH, TREE_HEIGHT),
	BackgroundColor3 = Color3.fromRGB(12, 13, 18),
	BackgroundTransparency = 0.3,
	Parent = window,
}, { Ui.corner(8) })

local function nodeCenter(node: PassiveData.Node): Vector2
	return Vector2.new(MARGIN + node.Position.X * SPACING, MARGIN + node.Position.Y * SPACING)
end

local lineFrames: { { Frame: Frame, A: string, B: string } } = {}
for _, edge in ipairs(PassiveData.Edges) do
	local from = nodeCenter(PassiveData.Nodes[edge[1]])
	local to = nodeCenter(PassiveData.Nodes[edge[2]])
	local delta = to - from
	local line = Ui.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((from.X + to.X) / 2, (from.Y + to.Y) / 2),
		Size = UDim2.fromOffset(delta.Magnitude, 4),
		Rotation = math.deg(math.atan2(delta.Y, delta.X)),
		BackgroundColor3 = LINE_COLOR,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = tree,
	})
	table.insert(lineFrames, { Frame = line, A = edge[1], B = edge[2] })
end

local nodeButtons: { [string]: TextButton } = {}
for nodeId, node in pairs(PassiveData.Nodes) do
	local size = NODE_SIZES[node.Kind]
	local center = nodeCenter(node)
	nodeButtons[nodeId] = Ui.button({
		Name = nodeId,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(size, size),
		Text = if node.Kind == "Start" then string.sub(node.Name, 1, 1) else "",
		TextSize = 18,
		ZIndex = 2,
		Parent = tree,
	}, { Ui.corner(size / 2), Ui.stroke(LINE_COLOR, 2) })
end

-- Right: class, points, the selected node, buttons
local side = Ui.new("Frame", {
	Name = "Details",
	Position = UDim2.fromOffset(16 + TREE_WIDTH + 16, 52),
	Size = UDim2.fromOffset(SIDE_WIDTH, TREE_HEIGHT),
	BackgroundTransparency = 1,
	Parent = window,
})
local classLabel = Ui.text({
	Size = UDim2.new(1, 0, 0, 28),
	TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	Parent = side,
})
local pointsLabel = Ui.text({
	Position = UDim2.fromOffset(0, 30),
	Size = UDim2.new(1, 0, 0, 20),
	TextSize = 15,
	TextColor3 = ALLOCATED_COLOR,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	Parent = side,
})
-- Hero mechanic of the class + its path (HeroData)
local heroLabel = Ui.text({
	Position = UDim2.fromOffset(0, 50),
	Size = UDim2.new(1, 0, 0, 18),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "",
	Parent = side,
})
local nodeName = Ui.text({
	Position = UDim2.fromOffset(0, 80),
	Size = UDim2.new(1, 0, 0, 24),
	TextSize = 18,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	Parent = side,
})
local nodeInfo = Ui.text({
	Position = UDim2.fromOffset(0, 104),
	Size = UDim2.new(1, 0, 0, 18),
	TextSize = 13,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	Parent = side,
})
local nodeLines = Ui.text({
	Position = UDim2.fromOffset(0, 126),
	Size = UDim2.new(1, 0, 0, 138),
	TextSize = 15,
	TextWrapped = true,
	RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "",
	Parent = side,
})
local allocateButton = Ui.button({
	Position = UDim2.new(0, 0, 1, -128),
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundColor3 = Color3.fromRGB(40, 110, 70),
	Text = "Allocate (1 point)",
	Parent = side,
}, { Ui.corner(6) })
local changeClassButton = Ui.button({
	Position = UDim2.new(0, 0, 1, -84),
	Size = UDim2.new(0.5, -4, 0, 36),
	BackgroundColor3 = Color3.fromRGB(60, 66, 84),
	Text = "Change Class",
	TextSize = 14,
	Parent = side,
}, { Ui.corner(6) })
local heroPathButton = Ui.button({
	Position = UDim2.new(0.5, 4, 1, -84),
	Size = UDim2.new(0.5, -4, 0, 36),
	BackgroundColor3 = Color3.fromRGB(60, 66, 84),
	Text = "Hero Path",
	TextSize = 14,
	Parent = side,
}, { Ui.corner(6) })
local resetButton = Ui.button({
	Position = UDim2.new(0, 0, 1, -40),
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundColor3 = Color3.fromRGB(110, 40, 40),
	Text = "",
	Parent = side,
}, { Ui.corner(6) })

-- Class picker: covers the tree until a class is chosen (or "Change Class" is pressed)
local classPicker = Ui.new("Frame", {
	Name = "ClassPicker",
	Position = UDim2.fromOffset(0, 48),
	Size = UDim2.new(1, 0, 1, -48),
	BackgroundColor3 = Ui.Colors.Panel,
	Active = true,
	Visible = false,
	ZIndex = 10,
	Parent = window,
}, { Ui.corner(10) })
local pickerTitle = Ui.text({
	Position = UDim2.fromOffset(16, 4),
	Size = UDim2.new(1, -120, 0, 30),
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	ZIndex = 11,
	Parent = classPicker,
})
local cancelButton = Ui.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 4),
	Size = UDim2.fromOffset(90, 30),
	Text = "Cancel",
	ZIndex = 11,
	Parent = classPicker,
}, { Ui.corner(6) })
local cards = Ui.new("Frame", {
	Position = UDim2.fromOffset(16, 46),
	Size = UDim2.new(1, -32, 1, -62),
	BackgroundTransparency = 1,
	ZIndex = 11,
	Parent = classPicker,
}, {
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 20),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local chooseButtons: { [string]: TextButton } = {}
for order, id in ipairs(PassiveData.ClassOrder) do
	local class = PassiveData.Classes[id]
	local startNode = PassiveData.Nodes[class.Start]
	local card = Ui.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1 / #PassiveData.ClassOrder, -14, 1, 0),
		BackgroundColor3 = Ui.Colors.PanelLight,
		ZIndex = 12,
		Parent = cards,
	}, { Ui.corner(8), Ui.stroke(class.Color, 2) })
	Ui.text({
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 32),
		Text = class.Name,
		TextSize = 26,
		TextColor3 = class.Color,
		ZIndex = 13,
		Parent = card,
	})
	Ui.text({
		Position = UDim2.fromOffset(12, 52),
		Size = UDim2.new(1, -24, 0, 80),
		Text = class.Description,
		TextSize = 15,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 13,
		Parent = card,
	})
	Ui.text({
		Position = UDim2.fromOffset(12, 140),
		Size = UDim2.new(1, -24, 0, 80),
		Text = "Start bonus:\n" .. table.concat(statLines(startNode.Stats), "\n"),
		TextSize = 14,
		TextColor3 = ALLOCATED_COLOR,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 13,
		Parent = card,
	})
	-- Hero mechanic (HeroData) and the paths it opens at VARIANT_LEVEL
	local hero = HeroData.get(id)
	if hero then
		local pathNames = {}
		for _, variantId in ipairs(hero.VariantOrder) do
			table.insert(pathNames, hero.Variants[variantId].Name)
		end
		Ui.text({
			Position = UDim2.fromOffset(12, 222),
			Size = UDim2.new(1, -24, 0, 120),
			Text = string.format(
				'<font color="#%s">%s</font>\n%s\n<font color="#%s">Lv %d paths: %s</font>',
				hero.Color:ToHex(),
				hero.Mechanic,
				hero.Description,
				Ui.Colors.TextDim:ToHex(),
				HeroData.VARIANT_LEVEL,
				table.concat(pathNames, " / ")
			),
			TextSize = 13,
			RichText = true,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 13,
			Parent = card,
		})
	end
	chooseButtons[id] = Ui.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, 40),
		BackgroundColor3 = class.Color:Lerp(Ui.Colors.Panel, 0.5),
		Text = "Choose " .. class.Name,
		ZIndex = 13,
		Parent = card,
	}, { Ui.corner(6) })
end

-- Hero path picker: the two paths of the current class (HeroData), chosen from HeroData.VARIANT_LEVEL
local pathPicker = Ui.new("Frame", {
	Name = "HeroPathPicker",
	Position = UDim2.fromOffset(0, 48),
	Size = UDim2.new(1, 0, 1, -48),
	BackgroundColor3 = Ui.Colors.Panel,
	Active = true,
	Visible = false,
	ZIndex = 10,
	Parent = window,
}, { Ui.corner(10) })
local pathTitle = Ui.text({
	Position = UDim2.fromOffset(16, 4),
	Size = UDim2.new(1, -120, 0, 30),
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	ZIndex = 11,
	Parent = pathPicker,
})
local pathCloseButton = Ui.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 4),
	Size = UDim2.fromOffset(90, 30),
	Text = "Close",
	ZIndex = 11,
	Parent = pathPicker,
}, { Ui.corner(6) })
local pathCards = Ui.new("Frame", {
	Position = UDim2.fromOffset(16, 46),
	Size = UDim2.new(1, -32, 1, -62),
	BackgroundTransparency = 1,
	ZIndex = 11,
	Parent = pathPicker,
}, {
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 20),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
-- Every class has two paths: two cards, filled in by render() for the current class
type PathCard = { Name: TextLabel, Description: TextLabel, Button: TextButton, Stroke: UIStroke }
local pathCardViews: { PathCard } = {}
for order = 1, 2 do
	local stroke = Ui.stroke(Ui.Colors.Stroke, 2)
	local card = Ui.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(0.5, -10, 1, 0),
		BackgroundColor3 = Ui.Colors.PanelLight,
		ZIndex = 12,
		Parent = pathCards,
	}, { Ui.corner(8), stroke })
	local nameLabel = Ui.text({
		Position = UDim2.fromOffset(12, 12),
		Size = UDim2.new(1, -24, 0, 32),
		TextSize = 26,
		Text = "",
		ZIndex = 13,
		Parent = card,
	})
	local descriptionLabel = Ui.text({
		Position = UDim2.fromOffset(12, 56),
		Size = UDim2.new(1, -24, 0, 200),
		TextSize = 16,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
		ZIndex = 13,
		Parent = card,
	})
	local button = Ui.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -12),
		Size = UDim2.new(1, -24, 0, 40),
		Text = "",
		ZIndex = 13,
		Parent = card,
	}, { Ui.corner(6) })
	pathCardViews[order] = { Name = nameLabel, Description = descriptionLabel, Button = button, Stroke = stroke }
end

Ui.text({
	Position = UDim2.fromOffset(0, 268),
	Size = UDim2.new(1, 0, 0, 36),
	TextSize = 12,
	TextColor3 = Ui.Colors.TextDim,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = if isTouchOnly
		then "Tap a passive to see it. Glowing green = can take"
		else "Click a passive to see it, Shift+Click takes it. Green outline = can take",
	Parent = side,
})

-- ==========================================
-- 2. RENDERING
-- ==========================================
local function render()
	local class = if classId then PassiveData.Classes[classId] else nil
	local pointsLeft = getPointsLeft()

	-- Unspent points on the toggle button so players notice them
	local buttonText = if isTouchOnly then "Passives" else "Passives [K]"
	toggleButton.Text = if class and pointsLeft > 0 then string.format("%s (%d)", buttonText, pointsLeft) else buttonText

	for _, line in ipairs(lineFrames) do
		line.Frame.BackgroundColor3 = if isAllocated(line.A) and isAllocated(line.B) then ALLOCATED_COLOR else LINE_COLOR
	end

	for nodeId, button in pairs(nodeButtons) do
		local allocated = isAllocated(nodeId)
		local available = canTake(nodeId)
		local startClass = getStartClass(nodeId)
		local stroke = button:FindFirstChildOfClass("UIStroke")
		button.BackgroundColor3 = if allocated
			then (if startClass then startClass.Color else ALLOCATED_COLOR)
			elseif available then Ui.Colors.PanelLight
			else Ui.Colors.Panel
		button.TextColor3 = if allocated then Ui.Colors.Panel else Ui.Colors.TextDim
		if stroke then
			stroke.Color = if nodeId == selectedNode
				then Color3.new(1, 1, 1)
				elseif available then CAN_TAKE_COLOR
				elseif startClass then startClass.Color
				elseif allocated then ALLOCATED_COLOR
				else LINE_COLOR
			stroke.Thickness = if nodeId == selectedNode or available then 3 else 2
		end
	end

	-- Details
	classLabel.Text = if class then class.Name else "No class yet"
	classLabel.TextColor3 = if class then class.Color else Ui.Colors.TextDim
	pointsLabel.Text = string.format("Points left: %d / %d (1 per level)", math.max(pointsLeft, 0), PassiveData.getPoints(getLevel()))

	-- Hero mechanic + path (HeroData)
	local hero = HeroData.get(classId)
	local unlocked = getLevel() >= HeroData.VARIANT_LEVEL
	local variant = if hero and heroVariant then hero.Variants[heroVariant] else nil
	heroLabel.Text = if not hero
		then ""
		elseif variant then hero.Mechanic .. " · " .. variant.Name .. " path"
		elseif unlocked then hero.Mechanic .. " · choose a path!"
		else string.format("%s · path at Lv %d", hero.Mechanic, HeroData.VARIANT_LEVEL)
	heroLabel.TextColor3 = if hero then hero.Color else Ui.Colors.TextDim
	heroPathButton.Visible = hero ~= nil
	heroPathButton.Text = if hero and unlocked and not variant then "Hero Path (!)" else "Hero Path"

	local node = if selectedNode then PassiveData.Nodes[selectedNode] else nil
	if node and selectedNode then
		local startClass = getStartClass(selectedNode)
		nodeName.Text = node.Name
		nodeInfo.Text = if node.Kind == "Start"
			then (if startClass then startClass.Name .. " start" else "Class start")
			elseif node.Kind == "Notable" then "Notable passive"
			else "Passive"
		local lines = statLines(node.Stats)
		local status: string
		local statusColor: Color3
		if isAllocated(selectedNode) then
			status, statusColor = "Allocated", ALLOCATED_COLOR
		elseif canTake(selectedNode) then
			status, statusColor = "Can take (1 point)", CAN_TAKE_COLOR
		else
			local reason = PassiveData.whyNot(classId, passives, selectedNode)
			status, statusColor = reason or "No points left (you get one every level)", Ui.Colors.TextDim
		end
		table.insert(lines, "")
		table.insert(lines, string.format('<font color="#%s">%s</font>', statusColor:ToHex(), status))
		nodeLines.Text = table.concat(lines, "\n")
		allocateButton.Visible = canTake(selectedNode)
	else
		nodeName.Text = "Select a passive"
		nodeInfo.Text = ""
		nodeLines.Text = ""
		allocateButton.Visible = false
	end

	changeClassButton.Visible = class ~= nil
	resetButton.Visible = class ~= nil and #passives > 0
	resetButton.Text = if confirmingReset then "Click Again to Reset" else "Reset Tree (free)"

	-- Class picker: forced while there's no class, otherwise only after "Change Class"
	classPicker.Visible = (synced and class == nil) or showingClassPicker
	cancelButton.Visible = class ~= nil
	pickerTitle.Text = if class then "Change class (your passive tree starts over)" else "Choose your class"
	for id, button in pairs(chooseButtons) do
		button.Text = if id == classId then "Current Class" else "Choose " .. PassiveData.Classes[id].Name
	end

	-- Hero path picker: the current class's two paths, locked below HeroData.VARIANT_LEVEL
	pathPicker.Visible = showingPathPicker and hero ~= nil and not classPicker.Visible
	if hero then
		pathTitle.Text = if unlocked
			then hero.Mechanic .. ": choose a path (free to switch)"
			else string.format("%s paths unlock at level %d", hero.Mechanic, HeroData.VARIANT_LEVEL)
		pathTitle.TextColor3 = hero.Color
		for order, view in ipairs(pathCardViews) do
			local variantId = hero.VariantOrder[order]
			local path = hero.Variants[variantId]
			local current = variantId == heroVariant
			view.Name.Text = path.Name
			view.Name.TextColor3 = hero.Color
			view.Description.Text = path.Description
			view.Stroke.Color = if current then hero.Color else Ui.Colors.Stroke
			view.Button.Text = if current
				then "Current Path"
				elseif unlocked then "Choose " .. path.Name
				else string.format("Unlocks at Lv %d", HeroData.VARIANT_LEVEL)
			view.Button.BackgroundColor3 = if unlocked and not current
				then hero.Color:Lerp(Ui.Colors.Panel, 0.5)
				else Ui.Colors.PanelLight
		end
	end
end

local function setOpen(open: boolean)
	window.Visible = open
	confirmingReset = false
	showingClassPicker = false
	showingPathPicker = false
	if open then
		render()
	end
end

-- ==========================================
-- 3. BUTTONS & REQUESTS TO THE SERVER (it checks every rule again)
-- ==========================================
for nodeId, button in pairs(nodeButtons) do
	button.Activated:Connect(function()
		local shiftDown = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if shiftDown and canTake(nodeId) then
			inventoryRemote:FireServer("AllocatePassive", nodeId)
		end
		selectedNode = nodeId
		confirmingReset = false
		render()
	end)
end

allocateButton.Activated:Connect(function()
	if selectedNode and canTake(selectedNode) then
		inventoryRemote:FireServer("AllocatePassive", selectedNode)
	end
end)

resetButton.Activated:Connect(function()
	if confirmingReset then
		inventoryRemote:FireServer("ResetPassives")
		confirmingReset = false
	else
		confirmingReset = true
	end
	render()
end)

changeClassButton.Activated:Connect(function()
	showingClassPicker = true
	showingPathPicker = false
	render()
end)

heroPathButton.Activated:Connect(function()
	showingPathPicker = true
	render()
end)

pathCloseButton.Activated:Connect(function()
	showingPathPicker = false
	render()
end)

for order, view in ipairs(pathCardViews) do
	view.Button.Activated:Connect(function()
		local hero = HeroData.get(classId)
		local variantId = if hero then hero.VariantOrder[order] else nil
		if variantId and variantId ~= heroVariant and HeroData.canChoose(classId, variantId, getLevel()) then
			inventoryRemote:FireServer("ChooseHeroPath", variantId)
		end
	end)
end

cancelButton.Activated:Connect(function()
	showingClassPicker = false
	render()
end)

for id, button in pairs(chooseButtons) do
	button.Activated:Connect(function()
		if id ~= classId then
			inventoryRemote:FireServer("ChooseClass", id)
		end
		showingClassPicker = false
		render()
	end)
end

toggleButton.Activated:Connect(function()
	setOpen(not window.Visible)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input: InputObject)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == TOGGLE_KEY then
		setOpen(not window.Visible)
	end
end)

-- New points every level
player:GetAttributeChangedSignal("Level"):Connect(render)

-- ==========================================
-- 4. SYNC FROM THE SERVER
-- ==========================================
inventoryRemote.OnClientEvent:Connect(function(action: string, data: any)
	if action ~= "Sync" or type(data) ~= "table" then
		return
	end
	local firstSync = not synced
	synced = true
	classId = data.Class
	heroVariant = data.HeroVariant
	passives = data.Passives or {}
	-- No class yet (new character or an old save): open straight to the class picker, once
	if firstSync and classId == nil then
		setOpen(true)
	end
	render()
end)

render()
-- Ask for the data in case the first Sync was sent before this script started
inventoryRemote:FireServer("RequestSync")
