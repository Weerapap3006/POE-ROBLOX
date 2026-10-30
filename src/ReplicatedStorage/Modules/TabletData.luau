-- ==========================================
-- TABLET DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.TabletData
-- ==========================================
-- Stone Tablets (endgame): an item with a Tier and random mods. Placed into the Lobby portal, it changes the next
-- dungeon run: harder monsters, more and better loot. Tablets roll and craft like gear (rarity = how many mods),
-- but their mods come from TabletData.Mods instead of ItemData.Affixes.
-- Server side: ServerStorage.Modules.DungeonRun (portal + current run), EnemyService and Loot apply the effects
export type Mod = {
	Kind: "Prefix" | "Suffix",
	Text: string, -- Tooltip line (%d = value; mods without a value have Min = Max = 0)
	Min: number,
	Max: number,
	Effect: ("Speed" | "Health" | "Damage")?, -- Monster stat it raises by Value%
	Element: string?, -- Monster attacks deal this element instead (Elements.Types)
	Quantity: number, -- Extra loot % this mod adds to the run
}

export type Effects = {
	Tier: number, -- 0 = plain dungeon (no tablet)
	Health: number, -- Monster health multiplier
	Damage: number, -- Monster damage multiplier
	Speed: number, -- Monster walk speed multiplier
	Elements: { string }, -- Attack elements forced by mods (empty = every enemy keeps its own)
	Quantity: number, -- Extra loot: 0.6 = +60% item / rune / stone / tablet drops
	RarityBoost: number, -- Magic and Rare drop weights are multiplied by 1 + this
}

local TabletData = {}

TabletData.MAX_TIER = 10
TabletData.HEALTH_PER_TIER = 0.15 -- Monster health +15% per tier
TabletData.DAMAGE_PER_TIER = 0.10 -- Monster damage +10% per tier
TabletData.QUANTITY_PER_TIER = 0.05 -- +5% loot per tier
TabletData.RARITY_PER_TIER = 0.15 -- Magic / Rare drops weigh +15% more per tier
TabletData.BOSS_TIER_UP_CHANCE = 0.5 -- A tablet run's boss drops a tablet one tier higher this often

TabletData.Mods = {
	MonsterSpeed = { Kind = "Prefix", Text = "Monsters move %d%% faster", Min = 10, Max = 25, Effect = "Speed", Quantity = 20 },
	MonsterHealth = { Kind = "Prefix", Text = "Monsters have %d%% more health", Min = 20, Max = 50, Effect = "Health", Quantity = 25 },
	MonsterDamage = { Kind = "Prefix", Text = "Monsters deal %d%% more damage", Min = 15, Max = 35, Effect = "Damage", Quantity = 25 },
	FrostAttacks = { Kind = "Suffix", Text = "Monster attacks deal Cold damage", Min = 0, Max = 0, Element = "Cold", Quantity = 15 },
	StormAttacks = { Kind = "Suffix", Text = "Monster attacks deal Lightning damage", Min = 0, Max = 0, Element = "Lightning", Quantity = 15 },
} :: { [string]: Mod }

-- What a tablet does to a run (nil = plain dungeon). Used by the server and by the tooltip
function TabletData.getEffects(tablet: { Tier: number?, Affixes: { { Id: string, Value: number } } }?): Effects
	local tier = if tablet then tablet.Tier or 1 else 0
	local effects: Effects = {
		Tier = tier,
		Health = 1 + TabletData.HEALTH_PER_TIER * tier,
		Damage = 1 + TabletData.DAMAGE_PER_TIER * tier,
		Speed = 1,
		Elements = {},
		Quantity = TabletData.QUANTITY_PER_TIER * tier,
		RarityBoost = TabletData.RARITY_PER_TIER * tier,
	}
	for _, affix in ipairs(if tablet then tablet.Affixes else {}) do
		local mod = TabletData.Mods[affix.Id]
		if mod then
			effects.Quantity += mod.Quantity / 100
			if mod.Effect == "Speed" then
				effects.Speed *= 1 + affix.Value / 100
			elseif mod.Effect == "Health" then
				effects.Health *= 1 + affix.Value / 100
			elseif mod.Effect == "Damage" then
				effects.Damage *= 1 + affix.Value / 100
			end
			if mod.Element then
				table.insert(effects.Elements, mod.Element)
			end
		end
	end
	return effects
end

-- One-line summary for the portal sign and notifications, e.g. "Tier 3: +45% health, +30% damage, +60% loot"
function TabletData.describe(effects: Effects): string
	local parts = {
		string.format("+%d%% health", math.round((effects.Health - 1) * 100)),
		string.format("+%d%% damage", math.round((effects.Damage - 1) * 100)),
	}
	if effects.Speed > 1 then
		table.insert(parts, string.format("+%d%% speed", math.round((effects.Speed - 1) * 100)))
	end
	for _, element in ipairs(effects.Elements) do
		table.insert(parts, element .. " attacks")
	end
	table.insert(parts, string.format("+%d%% loot", math.round(effects.Quantity * 100)))
	return string.format("Tier %d: %s", effects.Tier, table.concat(parts, ", "))
end

return TabletData
