-- ==========================================
-- ITEM DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.ItemData
-- ==========================================
-- An item is plain data so it can be saved to the DataStore and sent through RemoteEvents:
-- { Id = "GUID", Base = "IronSword", Rarity = "Magic", Affixes = { { Id = "FlatDamage", Value = 7 } } }
-- Stone runes are items too: { Base = "RuneReach", Rarity = "Rune", Affixes = {} } (bases added from RuneData below)
-- Stone Tablets: { Base = "StoneTablet", Rarity = "Magic", Tier = 3, Affixes = { { Id = "MonsterSpeed", Value = 20 } } }
-- (their affixes come from TabletData.Mods, see getAffixPool)
-- Skill Stones: { Base = "SkillFireball", Rarity = "Skill", Affixes = {} } (bases added from SkillData below)
local RuneData = require(script.Parent:WaitForChild("RuneData"))
local TabletData = require(script.Parent:WaitForChild("TabletData"))
local SkillData = require(script.Parent:WaitForChild("SkillData"))

export type Affix = {
	Id: string,
	Value: number,
}

export type Item = {
	Id: string,
	Base: string,
	Rarity: string,
	Affixes: { Affix },
	Tier: number?, -- Stone Tablets only
}

type BaseInfo = {
	Name: string,
	-- "Rune" = socketed into a skill, "Tablet" = placed in the portal, "Skill" = put on the skill bar; none are worn
	Slot: string,
	Rune: string?, -- Rune bases: RuneData.Runes key
	Skill: string?, -- Skill Stone bases: SkillData key
	AllowOffHand: boolean?, -- For MainHand weapons: true = can equip OffHand, false = locks OffHand slot
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
	FlatDamage = "+%d Damage",
	MaxHealth = "+%d Max Health",
	MaxMana = "+%d Max Mana", -- No affix yet: used by the passive tree
	AttackSpeed = "+%d%% Attack Speed",
	MaxEnergyShield = "+%d Max Energy Shield",
	EnergyShieldRecharge = "+%d%% Energy Shield Recharge Rate",
	FireDamage = "+%d Fire Damage",
	ColdDamage = "+%d Cold Damage",
	LightningDamage = "+%d Lightning Damage",
	FireResistance = "+%d%% Fire Resistance",
	ColdResistance = "+%d%% Cold Resistance",
	LightningResistance = "+%d%% Lightning Resistance",
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
	Rune = "Skill Rune",
	Tablet = "Portal Tablet",
	Skill = "Skill Stone",
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

-- Returns false when a MainHand weapon explicitly forbids equipping an OffHand item (AllowOffHand == false)
function ItemData.allowsOffHand(mainHandItem: Item?): boolean
	if not mainHandItem then
		return true
	end
	local base = ItemData.Bases[mainHandItem.Base]
	if base and base.AllowOffHand == false then
		return false
	end
	return true
end

-- Item bases that can drop
ItemData.Bases = {
	IronSword = {
		Name = "Iron Sword",
		Slot = "MainHand",
		AllowOffHand = false, -- Solo MainHand weapon: locks OffHand slot (set true for weapons that allow OffHand)
		Implicit = { FlatDamage = 5 },
	},
	LeatherVest = {
		Name = "Leather Vest",
		Slot = "Cloth",
		Implicit = { MaxHealth = 30 },
	},
	-- Endgame: placed in the Lobby portal (Loot drops it on its own, see EnemyData Drops.TabletChance)
	StoneTablet = {
		Name = "Stone Tablet",
		Slot = "Tablet",
		Implicit = {},
	},
} :: { [string]: BaseInfo }

-- One item base per stone rune (Loot drops them separately from gear, see EnemyData Drops.RuneChance)
for runeId, rune in pairs(RuneData.Runes) do
	ItemData.Bases[RuneData.getBaseId(runeId)] = { Name = rune.Name, Slot = "Rune", Rune = runeId, Implicit = {} }
end

-- Stone runes have no affixes; the item's base says which rune it is
function ItemData.getRuneId(item: Item): string?
	local base = ItemData.Bases[item.Base]
	return if base then base.Rune else nil
end

-- One item base per skill: Skill Stones drop on their own (EnemyData Drops.SkillChance) and go on the skill bar
for skillId, skill in pairs(SkillData) do
	ItemData.Bases["Skill" .. skillId] = { Name = skill.Name, Slot = "Skill", Skill = skillId, Implicit = {} }
end

function ItemData.getSkillStoneBase(skillId: string): string
	return "Skill" .. skillId
end

-- Which skill a Skill Stone teaches (nil for every other item)
function ItemData.getSkillId(item: Item): string?
	local base = ItemData.Bases[item.Base]
	return if base then base.Skill else nil
end

-- Random modifiers rolled onto Magic / Rare items (each affix at most once per item)
ItemData.Affixes = {
	FlatDamage = { Kind = "Prefix", Stat = "FlatDamage", Min = 3, Max = 12 },
	MaxHealth = { Kind = "Prefix", Stat = "MaxHealth", Min = 15, Max = 60 },
	AttackSpeed = { Kind = "Suffix", Stat = "AttackSpeed", Min = 5, Max = 20 },
	EnergyShield = { Kind = "Prefix", Stat = "MaxEnergyShield", Min = 10, Max = 35 },
	EnergyShieldRecharge = { Kind = "Suffix", Stat = "EnergyShieldRecharge", Min = 10, Max = 40 },
	-- Elemental damage on every hit (each element inflicts its ailment, see Elements)
	FireDamage = { Kind = "Prefix", Stat = "FireDamage", Min = 3, Max = 12 },
	ColdDamage = { Kind = "Prefix", Stat = "ColdDamage", Min = 3, Max = 12 },
	LightningDamage = { Kind = "Prefix", Stat = "LightningDamage", Min = 3, Max = 12 },
	FireResistance = { Kind = "Suffix", Stat = "FireResistance", Min = 8, Max = 25 },
	ColdResistance = { Kind = "Suffix", Stat = "ColdResistance", Min = 8, Max = 25 },
	LightningResistance = { Kind = "Suffix", Stat = "LightningResistance", Min = 8, Max = 25 },
} :: { [string]: AffixInfo }

-- How many affixes each rarity rolls, and how many of them may be prefixes / suffixes
ItemData.Rarities = {
	Normal = {
		Name = "Normal",
		Color = Color3.fromRGB(225, 225, 225),
		MinAffixes = 0,
		MaxAffixes = 0,
		MaxPrefixes = 0,
		MaxSuffixes = 0,
	},
	Magic = {
		Name = "Magic",
		Color = Color3.fromRGB(110, 150, 255),
		MinAffixes = 1,
		MaxAffixes = 2,
		MaxPrefixes = 1,
		MaxSuffixes = 1,
	},
	Rare = {
		Name = "Rare",
		Color = Color3.fromRGB(255, 215, 70),
		MinAffixes = 3,
		MaxAffixes = 3,
		MaxPrefixes = 2,
		MaxSuffixes = 2,
	},
	-- Only stone runes use this (not in RarityOrder, so gear never rolls it)
	Rune = {
		Name = "Stone Rune",
		Color = Color3.fromRGB(235, 150, 80),
		MinAffixes = 0,
		MaxAffixes = 0,
		MaxPrefixes = 0,
		MaxSuffixes = 0,
	},
	-- Only Skill Stones use this (not in RarityOrder either)
	Skill = {
		Name = "Skill Stone",
		Color = Color3.fromRGB(90, 215, 185),
		MinAffixes = 0,
		MaxAffixes = 0,
		MaxPrefixes = 0,
		MaxSuffixes = 0,
	},
} :: { [string]: RarityInfo }
ItemData.RarityOrder = { "Normal", "Magic", "Rare" }

function ItemData.isTablet(item: Item): boolean
	local base = ItemData.Bases[item.Base]
	return base ~= nil and base.Slot == "Tablet"
end

-- Where an item's affixes come from: TabletData.Mods for Stone Tablets, ItemData.Affixes for everything else
function ItemData.getAffixPool(item: Item): { [string]: { Kind: string, Min: number, Max: number } }
	return if ItemData.isTablet(item) then TabletData.Mods :: any else ItemData.Affixes :: any
end

function ItemData.getName(item: Item): string
	local base = ItemData.Bases[item.Base]
	local name = if base then base.Name else item.Base
	return if item.Tier then string.format("%s (Tier %d)", name, item.Tier) else name
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
	-- Stone Tablets: what the whole run gets (tier + mods), then each mod
	if ItemData.isTablet(item) then
		local effects = TabletData.getEffects(item :: any)
		local lines = {}
		for _, affix in ipairs(item.Affixes) do
			local mod = TabletData.Mods[affix.Id]
			if mod then
				table.insert(lines, string.format(mod.Text, affix.Value))
			end
		end
		return { TabletData.describe(effects) }, lines
	end

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
