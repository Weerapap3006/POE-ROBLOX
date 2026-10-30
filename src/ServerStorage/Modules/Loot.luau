-- ==========================================
-- LOOT (Roll random items, runes, stones and tablets + spawn pickups on the ground)
-- Path: ServerStorage.Modules.Loot
-- ==========================================
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ItemData = require(modulesFolder:WaitForChild("ItemData"))
local RuneData = require(modulesFolder:WaitForChild("RuneData"))
local StoneData = require(modulesFolder:WaitForChild("StoneData"))
local TabletData = require(modulesFolder:WaitForChild("TabletData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Crafting = require(script.Parent:WaitForChild("Crafting"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
local DROP_LIFETIME = 90 -- Seconds before an item nobody picked up disappears
local PICKUP_DISTANCE = 10
local SCATTER = 3 -- Drops land up to this many studs from the enemy

-- EnemyData Drops. The *Chance values are expected counts: 0.15 = 15% for one, 1.5 = one + 50% for a second
export type DropTable = {
	Rolls: number,
	Chance: number,
	RarityWeights: { [string]: number },
	RuneChance: number?,
	StoneChance: number?,
	TabletChance: number?,
}

local Loot = {}

local random = Random.new()

local function getDropsFolder(): Instance
	local folder = workspace:FindFirstChild("Drops")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Drops"
		folder.Parent = workspace
	end
	return folder
end

local function pickWeighted(order: { string }, weights: { [string]: number }): string?
	local total = 0
	for _, key in ipairs(order) do
		total += weights[key] or 0
	end
	if total <= 0 then
		return nil
	end

	local roll = random:NextNumber() * total
	local picked: string? = nil
	for _, key in ipairs(order) do
		local weight = weights[key] or 0
		if weight > 0 then
			picked = key
			if roll < weight then
				break
			end
			roll -= weight
		end
	end
	return picked
end

-- 1.6 -> 1, plus a 60% chance of 2
local function rollCount(expected: number): number
	local whole = math.floor(expected)
	return whole + (if random:NextNumber() < expected - whole then 1 else 0)
end

-- ==========================================
-- 1. ROLL ITEMS (server only: clients must never decide loot)
-- ==========================================
function Loot.rollItem(rarity: string): ItemData.Item
	local baseIds = {}
	for baseId, base in pairs(ItemData.Bases) do
		if base.Slot ~= "Rune" and base.Slot ~= "Tablet" then -- Runes and tablets drop on their own
			table.insert(baseIds, baseId)
		end
	end
	table.sort(baseIds)

	local item: ItemData.Item = {
		Id = HttpService:GenerateGUID(false),
		Base = baseIds[random:NextInteger(1, #baseIds)],
		Rarity = rarity,
		Affixes = {},
	}
	Crafting.rerollAffixes(item)
	return item
end

-- A random stone rune (every rune equally likely)
function Loot.rollRune(): ItemData.Item
	local runeIds = {}
	for runeId in pairs(RuneData.Runes) do
		table.insert(runeIds, runeId)
	end
	table.sort(runeIds)
	return {
		Id = HttpService:GenerateGUID(false),
		Base = RuneData.getBaseId(runeIds[random:NextInteger(1, #runeIds)]),
		Rarity = "Rune",
		Affixes = {},
	}
end

-- A Stone Tablet: rarity decides how many mods it rolls, like gear
function Loot.rollTablet(tier: number, rarity: string): ItemData.Item
	local tablet: ItemData.Item = {
		Id = HttpService:GenerateGUID(false),
		Base = "StoneTablet",
		Rarity = rarity,
		Affixes = {},
		Tier = math.clamp(tier, 1, TabletData.MAX_TIER),
	}
	Crafting.rerollAffixes(tablet)
	return tablet
end

-- ==========================================
-- 2. SPAWN A PICKUP ON THE GROUND
-- ==========================================
-- onPickup returns false when the player couldn't take it (e.g. full inventory): it stays on the ground
local function spawnPickup(name: string, color: Color3, groundPosition: Vector3, onPickup: (player: Player) -> boolean)
	local scatter = Vector3.new(random:NextNumber(-SCATTER, SCATTER), 0, random:NextNumber(-SCATTER, SCATTER))

	local part = Instance.new("Part")
	part.Name = "ItemDrop"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.CFrame = CFrame.new(groundPosition + scatter + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, math.rad(45), 0)

	-- Floating name tag in the drop's color, readable from a distance
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(180, 24)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.Text = name
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	-- Pick up with E (PC) or by tapping the prompt (mobile)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	local pickedUp = false
	prompt.Triggered:Connect(function(player: Player)
		if pickedUp then
			return
		end
		if onPickup(player) then
			pickedUp = true
			part:Destroy()
		end
	end)

	part.Parent = getDropsFolder()
	Debris:AddItem(part, DROP_LIFETIME)
end

function Loot.dropItem(item: ItemData.Item, groundPosition: Vector3)
	local rarity = ItemData.Rarities[item.Rarity]
	spawnPickup(ItemData.getName(item), rarity.Color, groundPosition, function(player: Player)
		return PlayerData.addItem(player, item)
	end)
end

-- Crafting stones don't take an inventory slot: picking one up just adds to the player's count
function Loot.dropStone(stoneId: string, groundPosition: Vector3)
	spawnPickup(StoneData.Stones[stoneId].Name, StoneData.COLOR, groundPosition, function(player: Player)
		return PlayerData.addStone(player, stoneId, 1)
	end)
end

-- ==========================================
-- 3. ENEMY DROPS
-- ==========================================
-- Rolls an enemy's drop table (EnemyData.Drops). run = the current dungeon run (DungeonRun): its tablet tier and
-- mods add loot (Quantity) and make Magic / Rare more likely (RarityBoost)
function Loot.rollDrops(drops: DropTable, groundPosition: Vector3, run: TabletData.Effects, isBoss: boolean)
	local more = 1 + run.Quantity
	local weights = table.clone(drops.RarityWeights)
	for _, rarity in ipairs({ "Magic", "Rare" }) do
		if weights[rarity] then
			weights[rarity] *= 1 + run.RarityBoost
		end
	end

	for _ = 1, rollCount(drops.Rolls * more) do
		if random:NextNumber() < drops.Chance then
			local rarity = pickWeighted(ItemData.RarityOrder, weights)
			if rarity then
				Loot.dropItem(Loot.rollItem(rarity), groundPosition)
			end
		end
	end

	for _ = 1, rollCount((drops.RuneChance or 0) * more) do
		Loot.dropItem(Loot.rollRune(), groundPosition)
	end

	local stoneWeights = {}
	for stoneId, stone in pairs(StoneData.Stones) do
		stoneWeights[stoneId] = stone.DropWeight
	end
	for _ = 1, rollCount((drops.StoneChance or 0) * more) do
		local stoneId = pickWeighted(StoneData.Order, stoneWeights)
		if stoneId then
			Loot.dropStone(stoneId, groundPosition)
		end
	end

	-- Tablets: plain dungeon = Tier 1, a tablet run = its tier (the boss sometimes one higher)
	for _ = 1, rollCount((drops.TabletChance or 0) * more) do
		local tier = math.max(run.Tier, 1)
		if run.Tier > 0 and isBoss and random:NextNumber() < TabletData.BOSS_TIER_UP_CHANCE then
			tier += 1
		end
		local rarity = pickWeighted(ItemData.RarityOrder, weights) or "Normal"
		Loot.dropItem(Loot.rollTablet(tier, rarity), groundPosition)
	end
end

return Loot
