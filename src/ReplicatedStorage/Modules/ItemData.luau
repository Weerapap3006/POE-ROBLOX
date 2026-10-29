-- ==========================================
-- ITEM DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.ItemData
-- ==========================================
-- An item is plain data so it can be saved to the DataStore and sent through RemoteEvents:
-- { Id = "GUID", Base = "IronSword", Rarity = "Magic", Affixes = { { Id = "FlatDamage", Value = 7 } } }
export type Affix = {
	Id: string,
	Value: number,
}

export type Item = {
	Id: string,
	Base: string,
	Rarity: string,
	Affixes: { Affix },
}

type BaseInfo = {
	Name: string,
	Slot: string,
	Implicit: { [string]: number }, -- Stats every copy of this base always has
}

type AffixInfo = {
	Kind: "Prefix" | "Suffix",
	Stat: string,
	Min: number, -- Rolled value range
	Max: number,
}

type RarityInfo = {
	Name: string,
	Color: Color3,
	MinAffixes: number,
	MaxAffixes: number,
	MaxPrefixes: number,
	MaxSuffixes: number,
}

local ItemData = {}

-- How each stat is written in tooltips (%d = value)
ItemData.StatText = {
	FlatDamage = "+%d ดาเมจ",
	MaxHealth = "+%d เลือดสูงสุด",
	AttackSpeed = "+%d%% ความเร็วโจมตี",
} :: { [string]: string }

-- Equipment slots in display order (9 slots supported)
ItemData.Slots = {
	"Helmet",
	"Amulet",
	"MainHand",
	"OffHand",
	"Cloth",
	"Ring1",
	"Ring2",
	"Special1",
	"Special2",
}

ItemData.SlotNames = {
	Helmet = "Helmet",
	Amulet = "Amulet",
	MainHand = "Main Hand",
	OffHand = "Off Hand",
	Cloth = "Cloth",
	Ring1 = "Ring 1",
	Ring2 = "Ring 2",
	Special1 = "Special 1",
	Special2 = "Special 2",
	-- Item category aliases
	Ring = "Ring",
	Special = "Special",
	Weapon = "Main Hand",
	Armor = "Cloth",
} :: { [string]: string }

-- Check if an item's Base.Slot can be worn in a given equipment slot key
function ItemData.isSlotCompatible(baseSlot: string, equipSlot: string): boolean
	if baseSlot == equipSlot then
		return true
	end
	if (baseSlot == "Weapon" or baseSlot == "MainHand") and equipSlot == "MainHand" then
		return true
	end
	if (baseSlot == "Armor" or baseSlot == "Cloth") and equipSlot == "Cloth" then
		return true
	end
	if baseSlot == "Ring" and (equipSlot == "Ring1" or equipSlot == "Ring2") then
		return true
	end
	if baseSlot == "Special" and (equipSlot == "Special1" or equipSlot == "Special2") then
		return true
	end
	return false
end

-- Pick which equipment slot key an item should go into when equipped
function ItemData.getTargetSlot(baseSlot: string, equipped: { [string]: Item }): string
	if baseSlot == "Weapon" or baseSlot == "MainHand" then
		return "MainHand"
	elseif baseSlot == "Armor" or baseSlot == "Cloth" then
		return "Cloth"
	elseif baseSlot == "Ring" then
		if not equipped["Ring1"] then
			return "Ring1"
		elseif not equipped["Ring2"] then
			return "Ring2"
		end
		return "Ring1"
	elseif baseSlot == "Special" then
		if not equipped["Special1"] then
			return "Special1"
		elseif not equipped["Special2"] then
			return "Special2"
		end
		return "Special1"
	end
	return baseSlot
end

-- Item bases that can drop
ItemData.Bases = {
	IronSword = {
		Name = "ดาบเหล็ก",
		Slot = "MainHand",
		Implicit = { FlatDamage = 5 },
	},
	LeatherVest = {
		Name = "เสื้อเกราะหนัง",
		Slot = "Cloth",
		Implicit = { MaxHealth = 30 },
	},
} :: { [string]: BaseInfo }

-- Random modifiers rolled onto Magic / Rare items (each affix at most once per item)
ItemData.Affixes = {
	FlatDamage = { Kind = "Prefix", Stat = "FlatDamage", Min = 3, Max = 12 },
	MaxHealth = { Kind = "Prefix", Stat = "MaxHealth", Min = 15, Max = 60 },
	AttackSpeed = { Kind = "Suffix", Stat = "AttackSpeed", Min = 5, Max = 20 },
} :: { [string]: AffixInfo }

-- How many affixes each rarity rolls, and how many of them may be prefixes / suffixes
ItemData.Rarities = {
	Normal = {
		Name = "ธรรมดา",
		Color = Color3.fromRGB(225, 225, 225),
		MinAffixes = 0,
		MaxAffixes = 0,
		MaxPrefixes = 0,
		MaxSuffixes = 0,
	},
	Magic = {
		Name = "เวทมนตร์",
		Color = Color3.fromRGB(110, 150, 255),
		MinAffixes = 1,
		MaxAffixes = 2,
		MaxPrefixes = 1,
		MaxSuffixes = 1,
	},
	Rare = {
		Name = "หายาก",
		Color = Color3.fromRGB(255, 215, 70),
		MinAffixes = 3,
		MaxAffixes = 3,
		MaxPrefixes = 2,
		MaxSuffixes = 2,
	},
} :: { [string]: RarityInfo }
ItemData.RarityOrder = { "Normal", "Magic", "Rare" }

function ItemData.getName(item: Item): string
	local base = ItemData.Bases[item.Base]
	return if base then base.Name else item.Base
end

function ItemData.formatStat(stat: string, value: number): string
	local text = ItemData.StatText[stat]
	return if text then string.format(text, value) else string.format("+%d %s", value, stat)
end

-- Total stats this item gives (implicit + affixes), e.g. { FlatDamage = 12, AttackSpeed = 8 }
function ItemData.getStats(item: Item): { [string]: number }
	local stats: { [string]: number } = {}
	local base = ItemData.Bases[item.Base]
	if base then
		for stat, value in pairs(base.Implicit) do
			stats[stat] = (stats[stat] or 0) + value
		end
	end
	for _, affix in ipairs(item.Affixes) do
		local affixInfo = ItemData.Affixes[affix.Id]
		if affixInfo then
			stats[affixInfo.Stat] = (stats[affixInfo.Stat] or 0) + affix.Value
		end
	end
	return stats
end

-- Tooltip lines: implicit stats (always on this base) and rolled affixes
function ItemData.getLines(item: Item): ({ string }, { string })
	local implicitLines = {}
	local base = ItemData.Bases[item.Base]
	if base then
		for stat, value in pairs(base.Implicit) do
			table.insert(implicitLines, ItemData.formatStat(stat, value))
		end
	end

	local affixLines = {}
	for _, affix in ipairs(item.Affixes) do
		local affixInfo = ItemData.Affixes[affix.Id]
		if affixInfo then
			table.insert(affixLines, ItemData.formatStat(affixInfo.Stat, affix.Value))
		end
	end
	return implicitLines, affixLines
end

return ItemData
