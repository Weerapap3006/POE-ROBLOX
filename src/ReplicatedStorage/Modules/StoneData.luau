-- ==========================================
-- STONE DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.StoneData
-- ==========================================
-- Crafting stones: a stackable currency (a count per player, saved) used on an item from the inventory window.
-- They work on gear and Stone Tablets. whyNot (below) decides if a stone can be used: the server
-- (ServerStorage.Modules.Crafting) and the inventory UI use the same rules
local ItemData = require(script.Parent:WaitForChild("ItemData"))

export type Stone = {
	Name: string,
	Action: string, -- Button text in the inventory
	Description: string,
	DropWeight: number, -- How often this stone is the one that drops (relative to the others)
}

local StoneData = {}

StoneData.Stones = {
	Ascension = {
		Name = "Ascension Stone",
		Action = "Upgrade",
		Description = "Normal -> Magic (1 affix), Magic -> Rare (fills up to 3 affixes)",
		DropWeight = 20,
	},
	Carving = {
		Name = "Carving Stone",
		Action = "Add Affix",
		Description = "Adds one random affix to a Magic or Rare item that has room",
		DropWeight = 45,
	},
	Shifting = {
		Name = "Shifting Stone",
		Action = "Reroll",
		Description = "Rerolls every affix of a Magic or Rare item",
		DropWeight = 35,
	},
} :: { [string]: Stone }

-- Button order in the inventory
StoneData.Order = { "Ascension", "Carving", "Shifting" }

StoneData.COLOR = Color3.fromRGB(170, 190, 210) -- Stone drops on the ground and their pickup message

-- Room for one more affix: under the rarity's total, and an affix it doesn't have yet whose kind
-- (Prefix / Suffix) still has a free spot
function StoneData.hasAffixRoom(item: ItemData.Item): boolean
	local rarityInfo = ItemData.Rarities[item.Rarity]
	if not rarityInfo or #item.Affixes >= rarityInfo.MaxAffixes then
		return false
	end
	local pool = ItemData.getAffixPool(item)
	local counts = { Prefix = 0, Suffix = 0 }
	local owned: { [string]: boolean } = {}
	for _, affix in ipairs(item.Affixes) do
		local info = pool[affix.Id]
		if info then
			counts[info.Kind] += 1
		end
		owned[affix.Id] = true
	end
	local limits = { Prefix = rarityInfo.MaxPrefixes, Suffix = rarityInfo.MaxSuffixes }
	for affixId, info in pairs(pool) do
		if not owned[affixId] and counts[info.Kind] < limits[info.Kind] then
			return true
		end
	end
	return false
end

-- nil = the stone can be used on this item, otherwise why not
function StoneData.whyNot(stoneId: string, item: ItemData.Item): string?
	local base = ItemData.Bases[item.Base]
	if not StoneData.Stones[stoneId] then
		return "Unknown stone"
	elseif not base or base.Slot == "Rune" then
		return "Crafting stones only work on gear and Stone Tablets"
	end

	if stoneId == "Ascension" then
		if item.Rarity == "Rare" then
			return "This item is already Rare"
		end
	elseif stoneId == "Carving" then
		if item.Rarity == "Normal" then
			return "Upgrade it to Magic first (Ascension Stone)"
		elseif not StoneData.hasAffixRoom(item) then
			return "No room for another affix"
		end
	elseif stoneId == "Shifting" then
		if item.Rarity == "Normal" then
			return "Normal items have no affixes to reroll"
		end
	end
	return nil
end

return StoneData
