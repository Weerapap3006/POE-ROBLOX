-- ==========================================
-- INVENTORY CLIENT (Inventory window: view items, equip / unequip / discard)
-- Path: StarterPlayer.StarterPlayerScripts.InventoryClient
-- ==========================================
-- The server owns the inventory. This script only shows the last "Sync" and sends requests
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local inventoryRemote = remotesFolder:WaitForChild("InventoryRemote") :: RemoteEvent

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ItemData = require(modulesFolder:WaitForChild("ItemData"))
local Ui = require(modulesFolder:WaitForChild("Ui"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
local TOGGLE_KEY = Enum.KeyCode.B
local GRID_COLUMNS = 5
local CELL_SIZE = 54
local CELL_GAP = 6
local SIDE_WIDTH = 200
local CONTENT_HEIGHT = 340
local GRID_WIDTH = GRID_COLUMNS * CELL_SIZE + (GRID_COLUMNS - 1) * CELL_GAP
local WINDOW_WIDTH = 12 + SIDE_WIDTH + 12 + GRID_WIDTH + 12 + SIDE_WIDTH + 12
local WINDOW_HEIGHT = 48 + CONTENT_HEIGHT + 12

-- ==========================================
-- STATE (replaced by every "Sync" from the server)
-- ==========================================
local inventory: { ItemData.Item } = {}
local equipped: { [string]: ItemData.Item } = {}
local capacity = 20
local selectedId: string? = nil
local confirmingDiscard = false

local isTouchOnly = Ui.isTouchOnly()

-- Returns the item and, if it's equipped, which slot it's in
local function findItem(itemId: string?): (ItemData.Item?, string?)
	if not itemId then
		return nil, nil
	end
	for _, item in ipairs(inventory) do
		if item.Id == itemId then
			return item, nil
		end
	end
	for slot, item in pairs(equipped) do
		if item.Id == itemId then
			return item, slot
		end
	end
	return nil, nil
end

local function getRarityColor(item: ItemData.Item): Color3
	local rarity = ItemData.Rarities[item.Rarity]
	return if rarity then rarity.Color else Ui.Colors.Text
end

-- ==========================================
-- 1. WINDOW LAYOUT (equipped + stats | item grid | item details)
-- ==========================================
local gui = Ui.screenGui("Inventory", 5)

-- PC: bottom-right. Mobile: top-right (bottom corners are the thumbstick and jump button)
local toggleButton = Ui.button({
	Name = "ToggleButton",
	AnchorPoint = if isTouchOnly then Vector2.new(1, 0) else Vector2.new(1, 1),
	Position = if isTouchOnly then UDim2.new(1, -12, 0, 8) else UDim2.new(1, -16, 1, -16),
	Size = UDim2.fromOffset(130, 40),
	BackgroundColor3 = Ui.Colors.Panel,
	BackgroundTransparency = 0.15,
	Text = if isTouchOnly then "Inventory" else "Inventory [B]",
	Parent = gui,
}, { Ui.corner(8), Ui.stroke(Ui.Colors.Accent, 2) })

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
}, { Ui.corner(10), Ui.stroke(Ui.Colors.Accent, 2) })

-- Shrink the window to fit small (phone) screens
local uiScale = Ui.new("UIScale", { Parent = window })
local function updateScale()
	local viewport = workspace.CurrentCamera.ViewportSize
	uiScale.Scale = math.min(1, (viewport.X - 20) / WINDOW_WIDTH, (viewport.Y - 20) / WINDOW_HEIGHT)
end
updateScale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)

Ui.text({
	Position = UDim2.fromOffset(16, 8),
	Size = UDim2.new(1, -80, 0, 32),
	Text = "Inventory & Equipment [B]",
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = window,
})
local closeButton = Ui.button({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 8),
	Size = UDim2.fromOffset(32, 32),
	Text = "X",
	Parent = window,
}, { Ui.corner(6) })

local function column(x: number, width: number): Frame
	return Ui.new("Frame", {
		Position = UDim2.fromOffset(x, 48),
		Size = UDim2.fromOffset(width, CONTENT_HEIGHT),
		BackgroundTransparency = 1,
		Parent = window,
	})
end

local leftColumn = column(12, SIDE_WIDTH)
local gridColumn = column(12 + SIDE_WIDTH + 12, GRID_WIDTH)
local detailColumn = column(12 + SIDE_WIDTH + 12 + GRID_WIDTH + 12, SIDE_WIDTH)

-- Left: 9 Square Equipment Slots (3 Vertical Columns - Layout A)
-- Col 0 (Main Gear):    Helmet, Cloth, MainHand, OffHand
-- Col 1 (Accessories):  Amulet, Ring1, Ring2
-- Col 2 (Specials):     Special1, Special2
Ui.text({
	Size = UDim2.new(1, 0, 0, 20),
	Text = "Equipment Slots",
	TextSize = 14,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = leftColumn,
})

local SLOT_LAYOUT: { { Slot: string, Col: number, Row: number } } = {
	-- Column 0: Helmet, Cloth, MainHand, OffHand
	{ Slot = "Helmet", Col = 0, Row = 0 },
	{ Slot = "Cloth", Col = 0, Row = 1 },
	{ Slot = "MainHand", Col = 0, Row = 2 },
	{ Slot = "OffHand", Col = 0, Row = 3 },
	-- Column 1: Amulet, Ring1, Ring2
	{ Slot = "Amulet", Col = 1, Row = 0 },
	{ Slot = "Ring1", Col = 1, Row = 1 },
	{ Slot = "Ring2", Col = 1, Row = 2 },
	-- Column 2: Special1, Special2
	{ Slot = "Special1", Col = 2, Row = 0 },
	{ Slot = "Special2", Col = 2, Row = 1 },
}

local SLOT_SIZE = 56
local SLOT_GAP = 8

local slotButtons: { [string]: TextButton } = {}
for _, info in ipairs(SLOT_LAYOUT) do
	local xOffset = info.Col * (SLOT_SIZE + SLOT_GAP)
	local yOffset = 24 + info.Row * (SLOT_SIZE + SLOT_GAP)

	slotButtons[info.Slot] = Ui.button({
		Name = info.Slot,
		Position = UDim2.fromOffset(xOffset, yOffset),
		Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
		TextSize = 11,
		TextScaled = true,
		TextWrapped = true,
		Parent = leftColumn,
	}, {
		Ui.corner(6),
		Ui.stroke(Ui.Colors.Stroke, 1.5),
		Ui.new("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		}),
		Ui.new("UITextSizeConstraint", {
			MaxTextSize = 12,
			MinTextSize = 8,
		}),
	})
end

-- Left: stats summary below the 4 rows of square equipment slots
local statsTopY = 24 + 4 * (SLOT_SIZE + SLOT_GAP) + 2
local statsLabel = Ui.text({
	Position = UDim2.fromOffset(0, statsTopY),
	Size = UDim2.new(1, 0, 1, -statsTopY),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "",
	Parent = leftColumn,
})

-- Middle: item grid (scrolls if capacity grows past what fits)
local grid = Ui.new("ScrollingFrame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	Parent = gridColumn,
}, {
	Ui.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL_SIZE, CELL_SIZE),
		CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

-- Right: details of the selected item
local detailName = Ui.text({
	Size = UDim2.new(1, 0, 0, 44),
	TextSize = 18,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	Parent = detailColumn,
})
local detailInfo = Ui.text({
	Position = UDim2.fromOffset(0, 44),
	Size = UDim2.new(1, 0, 0, 20),
	TextSize = 14,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Left,
	Text = "",
	Parent = detailColumn,
})
local detailLines = Ui.text({
	Position = UDim2.fromOffset(0, 70),
	Size = UDim2.new(1, 0, 0, 170),
	TextSize = 15,
	TextWrapped = true,
	RichText = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "",
	Parent = detailColumn,
})
local actionButton = Ui.button({
	Position = UDim2.new(0, 0, 1, -82),
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundColor3 = Color3.fromRGB(40, 110, 70),
	Text = "",
	Parent = detailColumn,
}, { Ui.corner(6) })
local discardButton = Ui.button({
	Position = UDim2.new(0, 0, 1, -38),
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundColor3 = Color3.fromRGB(110, 40, 40),
	Text = "",
	Parent = detailColumn,
}, { Ui.corner(6) })

-- ==========================================
-- 2. RENDERING (rebuilt from state after every change)
-- ==========================================
local render: () -> ()

local function selectItem(itemId: string?)
	selectedId = itemId
	confirmingDiscard = false
	render()
end

local function renderGrid()
	for _, child in ipairs(grid:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end

	for index = 1, capacity do
		local item = inventory[index]
		local isSelected = item ~= nil and item.Id == selectedId
		local cell = Ui.button({
			LayoutOrder = index,
			BackgroundColor3 = if isSelected then Ui.Colors.Accent:Lerp(Ui.Colors.PanelLight, 0.6) else Ui.Colors.PanelLight,
			Text = if item then ItemData.getName(item) else "",
			TextColor3 = if item then getRarityColor(item) else Ui.Colors.TextDim,
			TextScaled = true,
			TextWrapped = true,
			AutoButtonColor = item ~= nil,
			Parent = grid,
		}, {
			Ui.corner(6),
			Ui.stroke(if item then getRarityColor(item) else Ui.Colors.Stroke, if isSelected then 3 else 1),
			Ui.new("UIPadding", {
				PaddingLeft = UDim.new(0, 3),
				PaddingRight = UDim.new(0, 3),
				PaddingTop = UDim.new(0, 3),
				PaddingBottom = UDim.new(0, 3),
			}),
		})
		if item then
			cell.Activated:Connect(function()
				selectItem(item.Id)
			end)
		end
	end
end

local function renderEquipped()
	local offHandLocked = not ItemData.allowsOffHand(equipped.MainHand)
	for slot, button in pairs(slotButtons) do
		local item = equipped[slot]
		local slotName = ItemData.SlotNames[slot] or slot
		if slot == "OffHand" and offHandLocked and not item then
			button.Text = slotName .. "\n[Locked]"
			button.TextColor3 = Color3.fromRGB(190, 95, 95)
			button.BackgroundColor3 = Color3.fromRGB(35, 24, 28)
		else
			button.Text = if item then slotName .. "\n" .. ItemData.getName(item) else slotName
			button.TextColor3 = if item then getRarityColor(item) else Ui.Colors.TextDim
			button.BackgroundColor3 = if item and item.Id == selectedId
				then Ui.Colors.Accent:Lerp(Ui.Colors.PanelLight, 0.6)
				else Ui.Colors.PanelLight
		end
	end
end

local function renderStats()
	statsLabel.Text = string.format(
		"Lv %d  |  HP %d  |  MP %d\nDMG +%d  |  ATK SPD +%d%%\nES %d  |  ES RECHARGE +%d%%",
		player:GetAttribute("Level") or 1,
		player:GetAttribute("MaxHealth") or 100,
		player:GetAttribute("MaxMana") or 50,
		player:GetAttribute("FlatDamage") or 0,
		player:GetAttribute("AttackSpeed") or 0,
		player:GetAttribute("MaxEnergyShield") or 0,
		player:GetAttribute("EnergyShieldRecharge") or 0
	)
end

local function renderDetails()
	local item, equippedSlot = findItem(selectedId)
	if not item then
		detailName.Text = "Select an item to view details"
		detailName.TextColor3 = Ui.Colors.TextDim
		detailInfo.Text = ""
		detailLines.Text = ""
		actionButton.Visible = false
		discardButton.Visible = false
		return
	end

	local base = ItemData.Bases[item.Base]
	local rarity = ItemData.Rarities[item.Rarity]
	detailName.Text = ItemData.getName(item)
	detailName.TextColor3 = getRarityColor(item)
	local slotLabel = if base then ItemData.SlotNames[base.Slot] or base.Slot else "?"
	if base and (base.Slot == "MainHand" or base.Slot == "Weapon") then
		slotLabel ..= if base.AllowOffHand == false then " (No Off-Hand)" else " (Allows Off-Hand)"
	end
	detailInfo.Text = string.format(
		"%s · %s",
		if rarity then rarity.Name else item.Rarity,
		slotLabel
	)

	-- Implicit lines in grey, rolled affixes in the Magic blue
	local implicitLines, affixLines = ItemData.getLines(item)
	local lines = {}
	for _, line in ipairs(implicitLines) do
		table.insert(lines, string.format('<font color="#%s">%s</font>', Ui.Colors.TextDim:ToHex(), line))
	end
	for _, line in ipairs(affixLines) do
		table.insert(lines, string.format('<font color="#%s">%s</font>', ItemData.Rarities.Magic.Color:ToHex(), line))
	end
	detailLines.Text = table.concat(lines, "\n")

	actionButton.Visible = true
	local isBlockedOffHand = not equippedSlot
		and base ~= nil
		and base.Slot == "OffHand"
		and not ItemData.allowsOffHand(equipped.MainHand)
	if equippedSlot then
		actionButton.Text = "Unequip"
		actionButton.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
	elseif isBlockedOffHand then
		actionButton.Text = "Off-Hand Locked"
		actionButton.BackgroundColor3 = Color3.fromRGB(85, 65, 65)
	else
		actionButton.Text = "Equip"
		actionButton.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
	end
	-- Equipped items must be taken off before they can be thrown away
	discardButton.Visible = equippedSlot == nil
	discardButton.Text = if confirmingDiscard then "Click Again to Confirm" else "Discard"
end

function render()
	renderGrid()
	renderEquipped()
	renderStats()
	renderDetails()
end

-- ==========================================
-- 3. BUTTONS & REQUESTS TO THE SERVER
-- ==========================================
for slot, button in pairs(slotButtons) do
	button.Activated:Connect(function()
		local item = equipped[slot]
		selectItem(if item then item.Id else nil)
	end)
end

actionButton.Activated:Connect(function()
	local item, equippedSlot = findItem(selectedId)
	if not item then
		return
	end
	if equippedSlot then
		inventoryRemote:FireServer("Unequip", equippedSlot)
	else
		inventoryRemote:FireServer("Equip", item.Id)
	end
end)

discardButton.Activated:Connect(function()
	local item, equippedSlot = findItem(selectedId)
	if not item or equippedSlot then
		return
	end
	if confirmingDiscard then
		inventoryRemote:FireServer("Discard", item.Id)
		selectedId = nil
		confirmingDiscard = false
	else
		confirmingDiscard = true
	end
	render()
end)

local function setOpen(open: boolean)
	window.Visible = open
	confirmingDiscard = false
	if open then
		render()
	end
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

player.AttributeChanged:Connect(function()
	if window.Visible then
		renderStats()
	end
end)

-- ==========================================
-- 4. SYNC FROM THE SERVER
-- ==========================================
inventoryRemote.OnClientEvent:Connect(function(action: string, data: any)
	if action ~= "Sync" or type(data) ~= "table" then
		return
	end
	inventory = data.Inventory or {}
	equipped = data.Equipped or {}
	capacity = data.Capacity or capacity
	if not findItem(selectedId) then
		selectedId = nil
	end
	if window.Visible then
		render()
	end
end)

-- Ask for the current inventory in case the server's first Sync was sent before this script started
inventoryRemote:FireServer("RequestSync")
