-- ==========================================
-- CRAFTING (Rolling affixes + crafting stone rules)
-- Path: ServerStorage.Modules.Crafting
-- ==========================================
-- Server only: clients must never decide affixes. Loot uses it to roll new items, PlayerData when a player
-- uses a crafting stone (StoneData) on an item. Works on gear (ItemData.Affixes) and Stone Tablets
-- (TabletData.Mods) the same way, through ItemData.getAffixPool
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemData"))
local StoneData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("StoneData"))

local Crafting = {}

local random = Random.new()

-- Adds up to `count` random affixes the item doesn't have yet, within its rarity's limits
-- (MaxAffixes, MaxPrefixes, MaxSuffixes). Returns how many were added
function Crafting.addRandomAffixes(item: ItemData.Item, count: number): number
	local pool = ItemData.getAffixPool(item)
	local rarityInfo = ItemData.Rarities[item.Rarity]
	if not rarityInfo then
		return 0
	end

	local counts = { Prefix = 0, Suffix = 0 }
	local owned: { [string]: boolean } = {}
	for _, affix in ipairs(item.Affixes) do
		local info = pool[affix.Id]
		if info then
			counts[info.Kind] += 1
		end
		owned[affix.Id] = true
	end

	-- Shuffle the affixes it doesn't have, then take them in order while the limits allow
	local candidates = {}
	for affixId in pairs(pool) do
		if not owned[affixId] then
			table.insert(candidates, affixId)
		end
	end
	table.sort(candidates)
	for i = #candidates, 2, -1 do
		local j = random:NextInteger(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end

	local limits = { Prefix = rarityInfo.MaxPrefixes, Suffix = rarityInfo.MaxSuffixes }
	local added = 0
	for _, affixId in ipairs(candidates) do
		if added >= count or #item.Affixes >= rarityInfo.MaxAffixes then
			break
		end
		local info = pool[affixId]
		if counts[info.Kind] < limits[info.Kind] then
			counts[info.Kind] += 1
			table.insert(item.Affixes, { Id = affixId, Value = random:NextInteger(info.Min, info.Max) })
			added += 1
		end
	end

	-- Prefixes first so tooltips always read in the same order
	table.sort(item.Affixes, function(a, b)
		local infoA, infoB = pool[a.Id], pool[b.Id]
		return (if infoA then infoA.Kind else "") < (if infoB then infoB.Kind else "")
	end)
	return added
end

-- Throws away every affix and rolls a fresh set for the item's rarity
function Crafting.rerollAffixes(item: ItemData.Item)
	table.clear(item.Affixes)
	local rarityInfo = ItemData.Rarities[item.Rarity]
	if rarityInfo then
		Crafting.addRandomAffixes(item, random:NextInteger(rarityInfo.MinAffixes, rarityInfo.MaxAffixes))
	end
end

-- Uses a crafting stone on an item (changes the item in place).
-- Returns nil when it worked, or why the stone can't be used on this item (nothing is changed then).
-- The rules are StoneData.whyNot, the same ones the inventory UI shows
function Crafting.useStone(stoneId: string, item: ItemData.Item): string?
	local reason = StoneData.whyNot(stoneId, item)
	if reason then
		return reason
	end

	if stoneId == "Ascension" then
		item.Rarity = if item.Rarity == "Normal" then "Magic" else "Rare"
		-- Normal -> Magic gets 1 affix, Magic -> Rare fills up to the Rare maximum
		Crafting.addRandomAffixes(item, if item.Rarity == "Magic" then 1 else ItemData.Rarities.Rare.MaxAffixes)
	elseif stoneId == "Carving" then
		Crafting.addRandomAffixes(item, 1)
	elseif stoneId == "Shifting" then
		Crafting.rerollAffixes(item)
	end
	return nil
end

return Crafting
