-- ==========================================
-- INVENTORY CLIENT (Inventory window: view items, equip / unequip / discard, skill rune sockets, Shift+Click and X hotkeys)
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
local Elements = require(modulesFolder:WaitForChild("Elements"))
local Ui = require(modulesFolder:WaitForChild("Ui"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
local TOGGLE_KEY = Enum.KeyCode.B
local DISCARD_KEY = Enum.KeyCode.X -- Discards the inventory item under the mouse right away (no confirm)
-- Hold Shift while clicking: inventory item = equip right away (rune = socket), equipped slot / socket = take out
local GRID_COLUMNS = 5
local CELL_SIZE = 54
local CELL_GAP = 6
local SIDE_WIDTH = 200
local CONTENT_HEIGHT = 340
local RUNE_STRIP_HEIGHT = 70 -- Skill rune sockets along the bottom of the window
local SOCKET_SIZE = 40
local GRID_WIDTH = GRID_COLUMNS * CELL_SIZE + (GRID_COLUMNS - 1) * CELL_GAP
local WINDOW_WIDTH = 12 + SIDE_WIDTH + 12 + GRID_WIDTH + 12 + SIDE_WIDTH + 12
local WINDOW_HEIGHT = 48 + CONTENT_HEIGHT + 12 + RUNE_STRIP_HEIGHT

-- Skills in the rune strip, A-Z (the same order the server's Auto-Socket tries them)
local SKILL_ORDER: { string } = {}
for skillId in pairs(SkillData) do
	table.insert(SKILL_ORDER, skillId)
end
table.sort(SKILL_ORDER)

-- ==========================================
-- STATE (replaced by every "Sync" from the server)
-- ==========================================
local inventory: { ItemData.Item } = {}
local equipped: { [string]: ItemData.Item } = {}
local skillRunes: { [string]: { ItemData.Item } } = {} -- Runes socketed in each skill, in socket order
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

-- Bottom: stone rune sockets of each skill (round). Select a rune in the bag, then click an empty socket
local runeStrip = Ui.new("Frame", {
	Name = "SkillRunes",
	Position = UDim2.fromOffset(12, 48 + CONTENT_HEIGHT + 4),
	Size = UDim2.new(1, -24, 0, RUNE_STRIP_HEIGHT - 12),
	BackgroundTransparency = 1,
	Parent = window,
}, {
	Ui.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 24),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})
Ui.text({
	LayoutOrder = 0,
	Size = UDim2.fromOffset(70, SOCKET_SIZE),
	Text = "SKILL\nRUNES",
	TextSize = 14,
	TextColor3 = ItemData.Rarities.Rune.Color,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = runeStrip,
})

local socketButtons: { [string]: { TextButton } } = {}
for order, skillId in ipairs(SKILL_ORDER) do
	local skill = SkillData[skillId]
	local group = Ui.new("Frame", {
		LayoutOrder = order,
		Size = UDim2.fromOffset(math.max(skill.Sockets * (SOCKET_SIZE + 6), 90), SOCKET_SIZE + 18),
		BackgroundTransparency = 1,
		Parent = runeStrip,
	})
	Ui.text({
		Size = UDim2.new(1, 0, 0, 16),
		Text = skill.Name,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = group,
	})
	socketButtons[skillId] = {}
	for index = 1, skill.Sockets do
		socketButtons[skillId][index] = Ui.button({
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
Ui.text({
	LayoutOrder = #SKILL_ORDER + 1,
	Size = UDim2.fromOffset(260, SOCKET_SIZE),
	Text = if isTouchOnly
		then "Select a rune, then tap an empty socket"
		else "Select a rune, then click an empty socket\nShift+Click a rune: socket / take out",
	TextSize = 12,
	TextColor3 = Ui.Colors.TextDim,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = runeStrip,
})

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
			cell:SetAttribute("ItemId", item.Id) -- Lets the X hotkey find which item is under the mouse
			cell.Activated:Connect(function()
				-- Shift + click: equip right away, or socket a rune into the first skill it fits
				-- (the server says why if it can't, e.g. Off-Hand locked / no free socket)
				if isShiftDown() then
					selectedId = item.Id
					confirmingDiscard = false
					inventoryRemote:FireServer(if ItemData.getRuneId(item) then "Socket" else "Equip", item.Id)
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

local function renderRunes()
	-- A rune selected in the bag lights up the empty sockets it can go into
	local selected, equippedSlot = findItem(selectedId)
	local selectedRune = if selected and not equippedSlot then ItemData.getRuneId(selected) else nil

	for skillId, buttons in pairs(socketButtons) do
		local socketed = skillRunes[skillId] or {}
		local canTake = selectedRune ~= nil and RuneData.fits(selectedRune, SkillData[skillId].Shape)
		for _, item in ipairs(socketed) do
			if ItemData.getRuneId(item) == selectedRune then
				canTake = false -- One of each rune per skill
			end
		end

		for index, button in ipairs(buttons) do
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
		if RuneData.fits(runeId, SkillData[skillId].Shape) then
			table.insert(fits, SkillData[skillId].Name)
		end
	end
	local lines = { rune.Description, "", string.format('<font color="#%s">Fits: %s</font>', dim, table.concat(fits, ", ")) }
	if not socketSkill then
		table.insert(lines, string.format('<font color="#%s">Click an empty socket below to put it in a skill</font>', dim))
	end
	detailLines.Text = table.concat(lines, "\n")

	actionButton.Visible = true
	actionButton.Text = if socketSkill then "Remove from Skill" else "Auto-Socket"
	actionButton.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
	discardButton.Visible = socketSkill == nil
	discardButton.Text = if confirmingDiscard then "Click Again to Confirm" else "Discard"
end

local function renderDetails()
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
	renderRunes()
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

for skillId, buttons in pairs(socketButtons) do
	for index, button in ipairs(buttons) do
		button.Activated:Connect(function()
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

actionButton.Activated:Connect(function()
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
		inventoryRemote:FireServer("Socket", item.Id) -- Auto-Socket: first skill it fits with a free socket
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
	skillRunes = data.SkillRunes or {}
	capacity = data.Capacity or capacity
	if not findItem(selectedId) and not findSocketed(selectedId) then
		selectedId = nil
	end
	if window.Visible then
		render()
	end
end)

-- Ask for the current inventory in case the server's first Sync was sent before this script started
inventoryRemote:FireServer("RequestSync")
