-- ==========================================
-- LOOT (Roll random items + spawn pickups on the ground)
-- Path: ServerStorage.Modules.Loot
-- ==========================================
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
local DROP_LIFETIME = 90 -- Seconds before an item nobody picked up disappears
local PICKUP_DISTANCE = 10
local SCATTER = 3 -- Drops land up to this many studs from the enemy

export type DropTable = {
	Rolls: number,
	Chance: number,
	RarityWeights: { [string]: number },
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

local function pickRarity(weights: { [string]: number }): string?
	local total = 0
	for _, rarity in ipairs(ItemData.RarityOrder) do
		total += weights[rarity] or 0
	end
	if total <= 0 then
		return nil
	end

	local roll = random:NextNumber() * total
	local picked: string? = nil
	for _, rarity in ipairs(ItemData.RarityOrder) do
		local weight = weights[rarity] or 0
		if weight > 0 then
			picked = rarity
			if roll < weight then
				break
			end
			roll -= weight
		end
	end
	return picked
end

-- ==========================================
-- 1. ROLL ITEMS (server only: clients must never decide loot)
-- ==========================================
function Loot.rollItem(rarity: string): ItemData.Item
	local baseIds = {}
	for baseId in pairs(ItemData.Bases) do
		table.insert(baseIds, baseId)
	end
	table.sort(baseIds)
	local baseId = baseIds[random:NextInteger(1, #baseIds)]

	local rarityInfo = ItemData.Rarities[rarity]
	local affixCount = random:NextInteger(rarityInfo.MinAffixes, rarityInfo.MaxAffixes)

	-- Shuffle the affix pool, then take affixes in order while respecting the prefix / suffix limits
	local pool = {}
	for affixId in pairs(ItemData.Affixes) do
		table.insert(pool, affixId)
	end
	table.sort(pool)
	for i = #pool, 2, -1 do
		local j = random:NextInteger(1, i)
		pool[i], pool[j] = pool[j], pool[i]
	end

	local affixes: { ItemData.Affix } = {}
	local counts = { Prefix = 0, Suffix = 0 }
	local limits = { Prefix = rarityInfo.MaxPrefixes, Suffix = rarityInfo.MaxSuffixes }
	for _, affixId in ipairs(pool) do
		if #affixes >= affixCount then
			break
		end
		local affix = ItemData.Affixes[affixId]
		if counts[affix.Kind] < limits[affix.Kind] then
			counts[affix.Kind] += 1
			table.insert(affixes, { Id = affixId, Value = random:NextInteger(affix.Min, affix.Max) })
		end
	end

	-- Prefixes first so tooltips always read in the same order
	table.sort(affixes, function(a, b)
		return ItemData.Affixes[a.Id].Kind < ItemData.Affixes[b.Id].Kind
	end)

	return {
		Id = HttpService:GenerateGUID(false),
		Base = baseId,
		Rarity = rarity,
		Affixes = affixes,
	}
end

-- ==========================================
-- 2. SPAWN A PICKUP ON THE GROUND
-- ==========================================
function Loot.dropItem(item: ItemData.Item, groundPosition: Vector3)
	local rarity = ItemData.Rarities[item.Rarity]
	local itemName = ItemData.getName(item)
	local scatter = Vector3.new(random:NextNumber(-SCATTER, SCATTER), 0, random:NextNumber(-SCATTER, SCATTER))

	local part = Instance.new("Part")
	part.Name = "ItemDrop"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = rarity.Color
	part.CFrame = CFrame.new(groundPosition + scatter + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, math.rad(45), 0)

	-- Floating name tag in the rarity color, readable from a distance
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
	label.Text = itemName
	label.TextColor3 = rarity.Color
	label.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	-- Pick up with E (PC) or by tapping the prompt (mobile)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "เก็บ"
	prompt.ObjectText = itemName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	local pickedUp = false
	prompt.Triggered:Connect(function(player: Player)
		if pickedUp then
			return
		end
		if PlayerData.addItem(player, item) then
			pickedUp = true
			part:Destroy()
		end
	end)

	part.Parent = getDropsFolder()
	Debris:AddItem(part, DROP_LIFETIME)
end

-- Roll an enemy's drop table (EnemyData.Drops) and spawn whatever drops
function Loot.rollDrops(drops: DropTable, groundPosition: Vector3)
	for _ = 1, drops.Rolls do
		if random:NextNumber() < drops.Chance then
			local rarity = pickRarity(drops.RarityWeights)
			if rarity then
				Loot.dropItem(Loot.rollItem(rarity), groundPosition)
			end
		end
	end
end

return Loot
