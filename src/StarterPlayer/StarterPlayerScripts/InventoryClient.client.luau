-- ==========================================
-- INVENTORY CLIENT (Inventory window: view items, equip / unequip / discard, skill bar (Skill Stones) + rune
-- sockets, crafting stones, Stone Tablets -> portal, Shift+Click and X hotkeys)
-- Path: StarterPlayer.StarterPlayerScripts.InventoryClient
-- ==========================================
-- The server owns the inventory. This script only shows the last "Sync" and sends requests
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local inventoryRemote = remotesFolder:WaitForChild("InventoryRemote") :: RemoteEvent

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ItemData = require(modulesFolder:WaitForChild("ItemData"))
local SkillData = require(modulesFolder:WaitForChild("SkillData"))
local RuneData = require(modulesFolder:WaitForChild("RuneData"))
local StoneData = require(modulesFolder:WaitForChild("StoneData"))
local Elements = require(modulesFolder:WaitForChild("Elements"))
local PlayerStats = require(modulesFolder:WaitForChild("PlayerStats"))
local Ui = require(modulesFolder:WaitForChild("Ui"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
local TOGGLE_KEY = Enum.KeyCode.B
local DISCARD_KEY = Enum.KeyCode.X -- Discards the inventory item under the mouse right away (no confirm)
-- Hold Shift while clicking: inventory item = equip right away (rune = socket, Skill Stone = onto the skill bar),
-- equipped slot / socket / skill bar slot = take out
local GRID_COLUMNS = 5
local CELL_SIZE = 54
local CELL_GAP = 6
local SIDE_WIDTH = 200
local CONTENT_HEIGHT = 340
local RUNE_STRIP_HEIGHT = 70 -- Skill bar slots + their rune sockets along the bottom of the window
local SOCKET_SIZE = 40
local SKILL_GROUP_WIDTH = 138 -- One skill bar slot in that strip (3 sockets wide)
local GRID_ROWS = 4 -- Rows shown before the grid scrolls (crafting stones sit below them)
local GRID_WIDTH = GRID_COLUMNS * CELL_SIZE + (GRID_COLUMNS - 1) * CELL_GAP
local GRID_HEIGHT = GRID_ROWS * CELL_SIZE + (GRID_ROWS - 1) * CELL_GAP
local WINDOW_WIDTH = 12 + SIDE_WIDTH + 12 + GRID_WIDTH + 12 + SIDE_WIDTH + 12
local WINDOW_HEIGHT = 48 + CONTENT_HEIGHT + 12 + RUNE_STRIP_HEIGHT

-- Every skill, A-Z (a rune's details list the ones it fits)
local SKILL_ORDER: { string } = {}
local MAX_SOCKETS = 0
for skillId, skill in pairs(SkillData) do
	table.insert(SKILL_ORDER, skillId)
	MAX_SOCKETS = math.max(MAX_SOCKETS, skill.Sockets)
end
table.sort(SKILL_ORDER)
-- A skill bar slot picked in the strip is "selected" with this pseudo item id + the slot number
local BAR_SELECTION = "SkillSlot:"

-- ==========================================
-- STATE (replaced by every "Sync" from the server)
-- ==========================================
local inventory: { ItemData.Item } = {}
local equipped: { [string]: ItemData.Item } = {}
local skillBar: { string } = {} -- Skill id in each skill bar slot, "" = empty
local skillRunes: { [string]: { ItemData.Item } } = {} -- Runes socketed in each skill, in socket order
local stones: { [string]: number } = {} -- Crafting stones owned (StoneData id -> count)
local capacity = 20
local selectedId: string? = nil
local confirmingDiscard = false
-- Crafting stone whose valid targets light up: hovered tile (PC) or a tile tapped with nothing selected (pinned)
local hoveredStone: string? = nil
local pinnedStone: string? = nil

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

-- A rune socketed in a skill: returns it, the skill and the socket number
local function findSocketed(itemId: string?): (ItemData.Item?, string?, number?)
	for skillId, socketed in pairs(skillRunes) do
		for index, item in ipairs(socketed) do
			if item.Id == itemId then
				return item, skillId, index
			end
		end
	end
	return nil, nil, nil
end

-- The skill bar slot picked in the strip (nil when an item or nothing is selected)
local function getSelectedBarSlot(): number?
	if selectedId and string.sub(selectedId, 1, #BAR_SELECTION) == BAR_SELECTION then
		return tonumber(string.sub(selectedId, #BAR_SELECTION + 1))
	end
	return nil
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
-- Hotkey hint (PC only: phones have no Shift / X)
Ui.text({
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -52, 0, 8),
	Size = UDim2.fromOffset(320, 32),
	Text = "Shift+Click: Equip / Unequip   |   X: Discard",
	TextSize = 13,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Right,
	Visible = not isTouchOnly,
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
	TextSize = 11, -- 5 lines have to fit under the slots
	RichText = true, -- Elemental numbers in their element's color
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Text = "",
	Parent = leftColumn,
})

-- Middle: item grid (scrolls if capacity grows past GRID_ROWS)
local grid = Ui.new("ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, GRID_HEIGHT),
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

-- Under the grid: crafting stones owned (StoneData). They're a count, not bag items, so they take no slots.
-- Select gear or a Stone Tablet, then click a stone to use one on it (the server checks the rules)
local STONES_TOP = GRID_HEIGHT + 8
Ui.text({
	Position = UDim2.fromOffset(0, STONES_TOP),
	Size = UDim2.new(1, 0, 0, 16),
	Text = "CRAFTING STONES",
	TextSize = 13,
	TextColor3 = StoneData.COLOR,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = gridColumn,
})
Ui.text({
	Position = UDim2.fromOffset(0, STONES_TOP),
	Size = UDim2.new(1, 0, 0, 16),
	Text = if isTouchOnly then "Select an item, then tap a stone" else "Select an item, then a stone",
	TextSize = 11,
	TextColor3 = Ui.Colors.TextDim,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = gridColumn,
})
local stoneRow = Ui.new("Frame", {
	Name = "CraftingStones",
	Position = UDim2.fromOffset(0, STONES_TOP + 20),
	Size = UDim2.new(1, 0, 0, CONTENT_HEIGHT - STONES_TOP - 20),
	BackgroundTransparency = 1,
	Parent = gridColumn,
}, {
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
local stoneButtons: { [string]: TextButton } = {}
for order, stoneId in ipairs(StoneData.Order) do
	stoneButtons[stoneId] = Ui.button({
		Name = stoneId,
		LayoutOrder = order,
		Size = UDim2.new(1 / #StoneData.Order, -4, 1, 0),
		BackgroundColor3 = Ui.Colors.Panel,
		TextScaled = true,
		Text = "",
		Parent = stoneRow,
	}, {
		Ui.corner(6),
		Ui.stroke(StoneData.COLOR, 1),
		Ui.new("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		}),
		Ui.new("UITextSizeConstraint", { MaxTextSize = 13 }),
	})
end

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

-- Bottom: the skill bar (same slots and keys as the bar on screen). Each slot = the skill's name (click it with a
-- Skill Stone selected to put that skill there) and its round rune sockets (click an empty one with a rune selected)
local runeStrip = Ui.new("Frame", {
	Name = "SkillBar",
	Position = UDim2.fromOffset(12, 48 + CONTENT_HEIGHT + 4),
	Size = UDim2.new(1, -24, 0, RUNE_STRIP_HEIGHT - 12),
	BackgroundTransparency = 1,
	Parent = window,
}, {
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
Ui.text({
	LayoutOrder = 0,
	Size = UDim2.fromOffset(70, SOCKET_SIZE),
	Text = "SKILLS\n+ RUNES",
	TextSize = 14,
	TextColor3 = ItemData.Rarities.Skill.Color,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = runeStrip,
})

local skillSlotButtons: { TextButton } = {}
local socketButtons: { { TextButton } } = {} -- [bar slot][socket number]; sockets past the skill's count are hidden
for slot = 1, PlayerStats.SKILL_BAR_SLOTS do
	local group = Ui.new("Frame", {
		LayoutOrder = slot,
		Size = UDim2.fromOffset(SKILL_GROUP_WIDTH, SOCKET_SIZE + 18),
		BackgroundTransparency = 1,
		Parent = runeStrip,
	})
	skillSlotButtons[slot] = Ui.button({
		Name = "Skill",
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		Parent = group,
	}, { Ui.corner(4) })
	socketButtons[slot] = {}
	for index = 1, MAX_SOCKETS do
		socketButtons[slot][index] = Ui.button({
			Name = "Socket" .. index,
			Position = UDim2.fromOffset((index - 1) * (SOCKET_SIZE + 6), 18),
			Size = UDim2.fromOffset(SOCKET_SIZE, SOCKET_SIZE),
			TextScaled = true,
			Parent = group,
		}, {
			Ui.corner(SOCKET_SIZE / 2),
			Ui.stroke(Ui.Colors.Stroke, 1.5),
			Ui.new("UIPadding", {
				PaddingLeft = UDim.new(0, 3),
				PaddingRight = UDim.new(0, 3),
			}),
			Ui.new("UITextSizeConstraint", { MaxTextSize = 14 }),
		})
	end
end

-- ==========================================
-- 2. RENDERING (rebuilt from state after every change)
-- ==========================================
local render: () -> ()

local function selectItem(itemId: string?)
	selectedId = itemId
	confirmingDiscard = false
	render()
end

local function isShiftDown(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

-- True when the highlighted crafting stone (hovered / pinned tile) can be used on this item
local function isStoneTarget(item: ItemData.Item?): boolean
	local stoneId = hoveredStone or pinnedStone
	return stoneId ~= nil and item ~= nil and StoneData.whyNot(stoneId, item) == nil
end

local function getCellColor(item: ItemData.Item?): Color3
	if item and item.Id == selectedId then
		return Ui.Colors.Accent:Lerp(Ui.Colors.PanelLight, 0.6)
	elseif isStoneTarget(item) then
		return StoneData.COLOR:Lerp(Ui.Colors.PanelLight, 0.55)
	end
	return Ui.Colors.PanelLight
end

-- Affix pips along the bottom of a gear / tablet cell: filled = an affix it has, hollow = a free spot
-- (a Carving Stone can fill it). Normal items have no spots until an Ascension Stone makes them Magic
local PIP_SIZE = 6
local function renderPips(cell: GuiObject, item: ItemData.Item?)
	local old = cell:FindFirstChild("AffixPips")
	if old then
		old:Destroy()
	end
	local padding = cell:FindFirstChildOfClass("UIPadding")
	local rarityInfo = if item and not ItemData.getRuneId(item) then ItemData.Rarities[item.Rarity] else nil
	local spots = if rarityInfo then rarityInfo.MaxAffixes else 0
	if padding then
		padding.PaddingBottom = UDim.new(0, if spots > 0 then 11 else 3) -- Keep the name clear of the pips
	end
	if not item or spots == 0 then
		return
	end

	local color = getRarityColor(item)
	local pips = Ui.new("Frame", {
		Name = "AffixPips",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 8),
		Size = UDim2.new(1, 0, 0, PIP_SIZE),
		BackgroundTransparency = 1,
		Parent = cell,
	}, {
		Ui.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 3),
		}),
	})
	for index = 1, spots do
		Ui.new("Frame", {
			Size = UDim2.fromOffset(PIP_SIZE, PIP_SIZE),
			BackgroundColor3 = color,
			BackgroundTransparency = if index <= #item.Affixes then 0 else 1,
			Parent = pips,
		}, { Ui.corner(PIP_SIZE / 2), Ui.stroke(color, 1) })
	end
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
			BackgroundColor3 = getCellColor(item),
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
		renderPips(cell, item)
		if item then
			cell:SetAttribute("ItemId", item.Id) -- Lets the X hotkey find which item is under the mouse
			cell.Activated:Connect(function()
				-- Shift + click: equip right away, socket a rune into the first skill it fits, put a Skill Stone in
				-- the first empty skill bar slot, or put a tablet in the portal (the server says why if it can't,
				-- e.g. Off-Hand locked / no free socket / skill bar full)
				if isShiftDown() then
					selectedId = item.Id
					confirmingDiscard = false
					local action = if ItemData.getRuneId(item)
						then "Socket"
						elseif ItemData.getSkillId(item) then "SetSkill"
						elseif ItemData.isTablet(item) then "PlaceTablet"
						else "Equip"
					inventoryRemote:FireServer(action, item.Id)
					return
				end
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
		renderPips(button, item)
		if slot == "OffHand" and offHandLocked and not item then
			button.Text = slotName .. "\n[Locked]"
			button.TextColor3 = Color3.fromRGB(190, 95, 95)
			button.BackgroundColor3 = Color3.fromRGB(35, 24, 28)
		else
			button.Text = if item then slotName .. "\n" .. ItemData.getName(item) else slotName
			button.TextColor3 = if item then getRarityColor(item) else Ui.Colors.TextDim
			button.BackgroundColor3 = getCellColor(item)
		end
	end
end

local function renderStats()
	-- Fire / Cold / Lightning values side by side, each in its element's color
	local function elementLine(prefix: string, suffix: string, format: string): string
		local parts = {}
		for _, element in ipairs(Elements.Types) do
			local value = player:GetAttribute(element .. suffix) or 0
			table.insert(parts, string.format('<font color="#%s">' .. format .. "</font>", Elements.Colors[element]:ToHex(), value))
		end
		return prefix .. table.concat(parts, " / ")
	end

	statsLabel.Text = string.format(
		"Lv %d  |  HP %d  |  MP %d\nDMG +%d  |  ATK SPD +%d%%\nES %d  |  ES RECHARGE +%d%%\n%s\n%s",
		player:GetAttribute("Level") or 1,
		player:GetAttribute("MaxHealth") or 100,
		player:GetAttribute("MaxMana") or 50,
		player:GetAttribute("FlatDamage") or 0,
		player:GetAttribute("AttackSpeed") or 0,
		player:GetAttribute("MaxEnergyShield") or 0,
		player:GetAttribute("EnergyShieldRecharge") or 0,
		elementLine("ELE DMG ", "Damage", "+%d"),
		elementLine("RES ", "Resistance", "%d%%")
	)
end

-- Skill bar strip: each slot's key + skill name and its sockets. A Skill Stone selected in the bag lights up the
-- slots it can go into; a rune selected in the bag lights up the empty sockets it can go into
local function renderSkillBar()
	local selected, equippedSlot = findItem(selectedId)
	local selectedRune = if selected and not equippedSlot then ItemData.getRuneId(selected) else nil
	local selectedSkill = if selected and not equippedSlot then ItemData.getSkillId(selected) else nil
	local selectedSlot = getSelectedBarSlot()
	local skillColor = ItemData.Rarities.Skill.Color

	for slot, header in ipairs(skillSlotButtons) do
		local skillId = skillBar[slot] or ""
		local skill = SkillData[skillId]
		header.Text = string.format("%s · %s", PlayerStats.SKILL_BAR_KEYS[slot] or tostring(slot), if skill then skill.Name else "Empty")
		header.TextColor3 = if skill then skillColor else Ui.Colors.TextDim
		local canPlace = selectedSkill ~= nil and selectedSkill ~= skillId and not table.find(skillBar, selectedSkill)
		header.BackgroundTransparency = if selectedSlot == slot or canPlace then 0.35 else 1
		header.BackgroundColor3 = if selectedSlot == slot
			then Ui.Colors.Accent:Lerp(Ui.Colors.PanelLight, 0.6)
			else skillColor:Lerp(Ui.Colors.Panel, 0.65)

		local socketed = if skill then skillRunes[skillId] or {} else {}
		local canTake = skill ~= nil and selectedRune ~= nil and RuneData.fits(selectedRune, skill)
		for _, item in ipairs(socketed) do
			if ItemData.getRuneId(item) == selectedRune then
				canTake = false -- One of each rune per skill
			end
		end

		for index, button in ipairs(socketButtons[slot]) do
			button.Visible = skill ~= nil and index <= skill.Sockets
			local item = socketed[index]
			if item then
				button.Text = ItemData.getRuneId(item) or "?"
				button.TextColor3 = getRarityColor(item)
				button.BackgroundColor3 = if item.Id == selectedId
					then Ui.Colors.Accent:Lerp(Ui.Colors.PanelLight, 0.6)
					else Ui.Colors.PanelLight
			else
				local runeColor = ItemData.Rarities.Rune.Color
				button.Text = "+"
				button.TextColor3 = if canTake then runeColor else Ui.Colors.TextDim
				button.BackgroundColor3 = if canTake then runeColor:Lerp(Ui.Colors.Panel, 0.75) else Ui.Colors.Panel
			end
		end
	end
end

-- Stone runes show what they do and which skills they fit instead of stats
local function renderRuneDetails(item: ItemData.Item, runeId: string, socketSkill: string?)
	local rune = RuneData.Runes[runeId]
	local dim = Ui.Colors.TextDim:ToHex()
	detailName.Text = rune.Name
	detailName.TextColor3 = getRarityColor(item)
	detailInfo.Text = if socketSkill then "Socketed in " .. SkillData[socketSkill].Name else "Stone Rune"

	local fits = {}
	for _, skillId in ipairs(SKILL_ORDER) do
		if RuneData.fits(runeId, SkillData[skillId]) then
			table.insert(fits, SkillData[skillId].Name)
		end
	end
	local lines = { rune.Description, "", string.format('<font color="#%s">Fits: %s</font>', dim, table.concat(fits, ", ")) }
	if not socketSkill then
		local hint = if isTouchOnly
			then "Tap an empty socket below (skills on your skill bar)"
			else "Click an empty socket below (skills on your skill bar)"
		table.insert(lines, string.format('<font color="#%s">%s</font>', dim, hint))
	end
	detailLines.Text = table.concat(lines, "\n")

	actionButton.Visible = true
	actionButton.Text = if socketSkill then "Remove from Skill" else "Auto-Socket"
	actionButton.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
	discardButton.Visible = socketSkill == nil
	discardButton.Text = if confirmingDiscard then "Click Again to Confirm" else "Discard"
end

-- A Skill Stone in the bag (slot = nil) or a skill on the bar: what it does, its numbers and its runes
local function renderSkillDetails(skillId: string, slot: number?)
	local skill = SkillData[skillId]
	local dim = Ui.Colors.TextDim:ToHex()
	local elementColor = Elements.Colors[skill.Element] or Ui.Colors.Text
	detailName.Text = skill.Name
	detailName.TextColor3 = ItemData.Rarities.Skill.Color
	detailInfo.Text = string.format(
		"%s · %s · %s",
		skill.Kind,
		skill.Element,
		if slot then "Skill bar " .. (PlayerStats.SKILL_BAR_KEYS[slot] or tostring(slot)) else "Skill Stone"
	)

	local runeNames = {}
	for _, rune in ipairs(skillRunes[skillId] or {}) do
		table.insert(runeNames, ItemData.getName(rune))
	end
	local onBar = table.find(skillBar, skillId) ~= nil
	local hint = if slot
		then "Select a rune in your bag, then an empty socket below"
		elseif onBar then "Already on your skill bar"
		else "Select it, then a skill bar slot below (or Put on Skill Bar)"
	local lines = {
		skill.Description,
		"",
		string.format('<font color="#%s">%d-%d %s damage</font>', elementColor:ToHex(), skill.MinDamage, skill.MaxDamage, skill.Element),
		string.format("Cooldown %gs · Mana %d · %d sockets", skill.Cooldown, skill.ManaCost, skill.Sockets),
		string.format(
			'<font color="#%s">Runes: %s</font>',
			ItemData.Rarities.Rune.Color:ToHex(),
			if #runeNames > 0 then table.concat(runeNames, ", ") else "none"
		),
		string.format('<font color="#%s">%s</font>', dim, hint),
	}
	detailLines.Text = table.concat(lines, "\n")

	actionButton.Visible = slot ~= nil or not onBar
	actionButton.Text = if slot then "Remove from Skill Bar" else "Put on Skill Bar"
	actionButton.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
	discardButton.Visible = slot == nil
	discardButton.Text = if confirmingDiscard then "Click Again to Confirm" else "Discard"
end

local function renderDetails()
	-- A skill bar slot picked in the strip
	local barSlot = getSelectedBarSlot()
	if barSlot then
		local skillId = skillBar[barSlot] or ""
		if SkillData[skillId] then
			renderSkillDetails(skillId, barSlot)
		else
			detailName.Text = "Empty skill slot"
			detailName.TextColor3 = Ui.Colors.TextDim
			detailInfo.Text = "Key " .. (PlayerStats.SKILL_BAR_KEYS[barSlot] or tostring(barSlot))
			detailLines.Text = "Select a Skill Stone in your bag, then click this slot to put its skill here"
			actionButton.Visible = false
			discardButton.Visible = false
		end
		return
	end

	local item, equippedSlot = findItem(selectedId)
	local socketSkill: string? = nil
	if not item then
		item, socketSkill = findSocketed(selectedId)
	end
	if not item then
		detailName.Text = "Select an item to view details"
		detailName.TextColor3 = Ui.Colors.TextDim
		detailInfo.Text = ""
		detailLines.Text = ""
		actionButton.Visible = false
		discardButton.Visible = false
		return
	end

	local runeId = ItemData.getRuneId(item)
	if runeId then
		renderRuneDetails(item, runeId, socketSkill)
		return
	end
	local skillId = ItemData.getSkillId(item)
	if skillId then
		renderSkillDetails(skillId, nil)
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

	-- How many affixes out of the rarity's maximum, and whether a Carving Stone can add one
	local maxAffixes = if rarity then rarity.MaxAffixes else 0
	local hasRoom = StoneData.hasAffixRoom(item)
	local status = if maxAffixes == 0
		then "No affix spots: an Ascension Stone makes it Magic"
		elseif hasRoom then string.format("Affixes %d/%d: room for more (Carving Stone)", #item.Affixes, maxAffixes)
		else string.format("Affixes %d/%d: full", #item.Affixes, maxAffixes)
	local statusColor = if hasRoom then Color3.fromRGB(130, 220, 140) else Ui.Colors.TextDim
	table.insert(lines, "")
	table.insert(lines, string.format('<font color="#%s">%s</font>', statusColor:ToHex(), status))
	detailLines.Text = table.concat(lines, "\n")

	actionButton.Visible = true
	local isBlockedOffHand = not equippedSlot
		and base ~= nil
		and base.Slot == "OffHand"
		and not ItemData.allowsOffHand(equipped.MainHand)
	if equippedSlot then
		actionButton.Text = "Unequip"
		actionButton.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
	elseif ItemData.isTablet(item) then
		actionButton.Text = "Place in Portal" -- The next dungeon run (for everyone) uses it
		actionButton.BackgroundColor3 = Color3.fromRGB(90, 75, 40)
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

-- Stone tiles: name, how many you have, what it does. A tile lights up when you have it and it can be used
-- on the selected item (StoneData.whyNot, the server's rules); a pinned tile gets a thick outline
local function renderStones()
	local selected = findItem(selectedId)
	for stoneId, button in pairs(stoneButtons) do
		local stone = StoneData.Stones[stoneId]
		local count = stones[stoneId] or 0
		local usable = selected ~= nil and count > 0 and StoneData.whyNot(stoneId, selected) == nil
		button.Text = string.format("%s\nx%d\n%s", stone.Name, count, stone.Action)
		button.TextColor3 = if count > 0 then Ui.Colors.Text else Ui.Colors.TextDim
		button.BackgroundColor3 = if usable then StoneData.COLOR:Lerp(Ui.Colors.Panel, 0.7) else Ui.Colors.Panel
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = if pinnedStone == stoneId then 3 else 1
		end
	end
end

function render()
	renderGrid()
	renderEquipped()
	renderSkillBar()
	renderStones()
	renderStats()
	renderDetails()
end

-- ==========================================
-- 3. BUTTONS & REQUESTS TO THE SERVER
-- ==========================================
for slot, button in pairs(slotButtons) do
	button.Activated:Connect(function()
		local item = equipped[slot]
		-- Shift + click an equipped item: take it off right away
		if item and isShiftDown() then
			inventoryRemote:FireServer("Unequip", slot)
		end
		selectItem(if item then item.Id else nil)
	end)
end

-- Skill bar slot name: with a Skill Stone selected in the bag, put its skill here (the skill already there goes
-- back into the bag). Otherwise select the slot (Shift + click: take its skill off right away)
for slot, header in ipairs(skillSlotButtons) do
	header.Activated:Connect(function()
		local selected, equippedSlot = findItem(selectedId)
		if selected and not equippedSlot and ItemData.getSkillId(selected) then
			inventoryRemote:FireServer("SetSkill", selected.Id, slot)
			selectItem(BAR_SELECTION .. slot)
			return
		end
		if isShiftDown() and (skillBar[slot] or "") ~= "" then
			inventoryRemote:FireServer("ClearSkill", slot)
		end
		selectItem(BAR_SELECTION .. slot)
	end)
end

for slot, buttons in ipairs(socketButtons) do
	for index, button in ipairs(buttons) do
		button.Activated:Connect(function()
			local skillId = skillBar[slot] or ""
			if not SkillData[skillId] then
				return
			end
			local item = (skillRunes[skillId] or {})[index]
			if item then
				-- Shift + click a socketed rune: take it out right away
				if isShiftDown() then
					inventoryRemote:FireServer("Unsocket", skillId, index)
				end
				selectItem(item.Id)
				return
			end
			-- Empty socket: put the rune selected in the bag into this skill (the server checks it fits)
			local selected, equippedSlot = findItem(selectedId)
			if selected and not equippedSlot and ItemData.getRuneId(selected) then
				inventoryRemote:FireServer("Socket", selected.Id, skillId)
			end
		end)
	end
end

-- Crafting stone tiles: use one on the selected item (bag or equipped; the server checks the rules).
-- Hover (PC) lights up every item the stone can be used on; with nothing selected, a click / tap pins that
-- highlight instead (how phones see it), click the same stone again to unpin
for stoneId, button in pairs(stoneButtons) do
	if not isTouchOnly then
		button.MouseEnter:Connect(function()
			hoveredStone = stoneId
			render()
		end)
		button.MouseLeave:Connect(function()
			if hoveredStone == stoneId then
				hoveredStone = nil
				render()
			end
		end)
	end
	button.Activated:Connect(function()
		local item = findItem(selectedId)
		if item then
			inventoryRemote:FireServer("Craft", stoneId, item.Id)
		else
			pinnedStone = if pinnedStone == stoneId then nil else stoneId
			render()
		end
	end)
end

actionButton.Activated:Connect(function()
	local barSlot = getSelectedBarSlot()
	if barSlot then
		inventoryRemote:FireServer("ClearSkill", barSlot) -- Back into the bag as a Skill Stone
		return
	end
	local item, equippedSlot = findItem(selectedId)
	if not item then
		-- A socketed rune: take it out of its skill
		local _, socketSkill, socketIndex = findSocketed(selectedId)
		if socketSkill and socketIndex then
			inventoryRemote:FireServer("Unsocket", socketSkill, socketIndex)
		end
		return
	end
	if equippedSlot then
		inventoryRemote:FireServer("Unequip", equippedSlot)
	elseif ItemData.getRuneId(item) then
		inventoryRemote:FireServer("Socket", item.Id) -- Auto-Socket: first skill on the bar it fits with a free socket
	elseif ItemData.getSkillId(item) then
		inventoryRemote:FireServer("SetSkill", item.Id) -- First empty skill bar slot
	elseif ItemData.isTablet(item) then
		inventoryRemote:FireServer("PlaceTablet", item.Id)
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
	pinnedStone = nil
	hoveredStone = nil
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

-- Inventory item under the mouse (grid cells carry their item's id in the ItemId attribute)
local function getHoveredItemId(): string?
	-- Mouse location counts the top bar, GUI positions don't
	local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	local function isOver(object: GuiObject): boolean
		local topLeft, size = object.AbsolutePosition, object.AbsoluteSize
		return mouse.X >= topLeft.X and mouse.X <= topLeft.X + size.X and mouse.Y >= topLeft.Y and mouse.Y <= topLeft.Y + size.Y
	end
	if not isOver(grid) then
		return nil -- Also skips cells scrolled out of view
	end
	for _, cell in ipairs(grid:GetChildren()) do
		local itemId = cell:GetAttribute("ItemId")
		if itemId and cell:IsA("GuiObject") and isOver(cell) then
			return itemId
		end
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input: InputObject)
	if UserInputService:GetFocusedTextBox() then
		return
	end
	if input.KeyCode == TOGGLE_KEY then
		setOpen(not window.Visible)
	elseif input.KeyCode == DISCARD_KEY and window.Visible then
		-- X over an item: throw it away right away (equipped items aren't in the grid, so they're safe)
		local itemId = getHoveredItemId()
		if itemId then
			inventoryRemote:FireServer("Discard", itemId)
			if selectedId == itemId then
				selectedId = nil
			end
			confirmingDiscard = false
		end
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
	skillBar = data.SkillBar or {}
	skillRunes = data.SkillRunes or {}
	stones = data.Stones or {}
	capacity = data.Capacity or capacity
	if not findItem(selectedId) and not findSocketed(selectedId) and not getSelectedBarSlot() then
		selectedId = nil
	end
	if window.Visible then
		render()
	end
end)

-- Ask for the current inventory in case the server's first Sync was sent before this script started
inventoryRemote:FireServer("RequestSync")
