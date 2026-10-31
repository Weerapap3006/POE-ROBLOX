-- ==========================================
-- SPIRIT DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.SpiritData
-- ==========================================
-- Stone Spirits are companions: an item that drops from bosses (EnemyData Drops.SpiritChance) and goes into one of
-- SLOTS spirit slots in the inventory. Each gives its Stats while it's in a slot (added like passive tree stats).
-- Every spirit in a slot also floats along with the player (SpiritClient). Every spirit is an item base in ItemData
-- ("Spirit" .. id, Slot = "Spirit"), so it drops, sits in the bag and saves like any item
export type Spirit = {
	Name: string,
	Color: Color3, -- Its glow while it floats along with the player
	Stats: { [string]: number }, -- PlayerStats stat names (ItemData.StatText says how they read)
}

local SpiritData = {}

SpiritData.SLOTS = 3

SpiritData.Spirits = {
	EmberWisp = {
		Name = "Ember Wisp",
		Color = Color3.fromRGB(255, 130, 60),
		Stats = { FireResistance = 15, FireDamage = 3 },
	},
	FrostWisp = {
		Name = "Frost Wisp",
		Color = Color3.fromRGB(120, 200, 255),
		Stats = { ColdResistance = 15, ColdDamage = 3 },
	},
	StormWisp = {
		Name = "Storm Wisp",
		Color = Color3.fromRGB(255, 230, 90),
		Stats = { LightningResistance = 15, LightningDamage = 3 },
	},
	MossGolem = {
		Name = "Moss Golem",
		Color = Color3.fromRGB(110, 190, 100),
		Stats = { MaxHealth = 30 },
	},
	ShardWarden = {
		Name = "Shard Warden",
		Color = Color3.fromRGB(160, 230, 255),
		Stats = { MaxEnergyShield = 20 },
	},
	ManaSprite = {
		Name = "Mana Sprite",
		Color = Color3.fromRGB(90, 130, 255),
		Stats = { ManaRegen = 50 },
	},
	GemBeetle = {
		Name = "Gem Beetle",
		Color = Color3.fromRGB(240, 120, 220),
		Stats = { LootQuantity = 20 }, -- More drops from monsters this player helped kill
	},
} :: { [string]: Spirit }

-- Item base id of a spirit (ItemData.Bases key)
function SpiritData.getBaseId(spiritId: string): string
	return "Spirit" .. spiritId
end

-- Total stats of the spirits in the slots ("" = empty slot, unknown ids are skipped)
function SpiritData.getStats(slots: { string }): { [string]: number }
	local stats: { [string]: number } = {}
	for _, spiritId in ipairs(slots) do
		local spirit = SpiritData.Spirits[spiritId]
		if spirit then
			for stat, value in pairs(spirit.Stats) do
				stats[stat] = (stats[stat] or 0) + value
			end
		end
	end
	return stats
end

return SpiritData
