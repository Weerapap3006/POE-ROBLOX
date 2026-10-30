-- ==========================================
-- PLAYER STATS (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.PlayerStats
-- ==========================================
-- Final stats = base + level growth + every equipped item (ItemData.getStats)
local ItemData = require(script.Parent:WaitForChild("ItemData"))

export type Stats = {
	MaxHealth: number,
	MaxMana: number,
	MaxEnergyShield: number, -- Only from items. Soaks enemy hits before health
	EnergyShieldRecharge: number, -- % faster energy shield recharge
	FlatDamage: number, -- Added to every skill's damage roll
	AttackSpeed: number, -- % faster skill cooldowns
	-- Elemental damage added to every hit (inflicts ailments, see Elements)
	FireDamage: number,
	ColdDamage: number,
	LightningDamage: number,
	-- % less damage taken from enemy hits of that element (capped at Elements.MAX_RESISTANCE)
	FireResistance: number,
	ColdResistance: number,
	LightningResistance: number,
}

local PlayerStats = {}

PlayerStats.MAX_LEVEL = 30
PlayerStats.BASE_MAX_HEALTH = 100
PlayerStats.MAX_HEALTH_PER_LEVEL = 12
PlayerStats.DAMAGE_PER_LEVEL = 2

-- Mana (skills with a ManaCost in SkillData spend it)
PlayerStats.BASE_MAX_MANA = 50
PlayerStats.MAX_MANA_PER_LEVEL = 4
PlayerStats.MANA_REGEN_PERCENT = 0.04 -- Of max mana per second, all the time

-- Energy shield: takes hits before health, recharges once the player hasn't been hit for a while
PlayerStats.ENERGY_SHIELD_RECHARGE_DELAY = 3 -- Seconds without being hit before recharging starts
PlayerStats.ENERGY_SHIELD_RECHARGE_PERCENT = 0.25 -- Of max energy shield per second (+EnergyShieldRecharge%)

-- Dodge roll (Space / mobile Dodge button). Jumping is turned off, the roll replaces it
PlayerStats.DODGE_COOLDOWN = 1 -- Seconds between rolls (AttackSpeed doesn't change it)
PlayerStats.DODGE_DURATION = 0.18 -- Seconds the dash bursts the character forward
PlayerStats.DODGE_DISTANCE = 13 -- Studs covered by one roll
PlayerStats.DODGE_INVULNERABLE_TIME = 0.4 -- Enemy hits miss for this long after the server gets the roll

-- Flasks (Life = key 1, Mana = key 2, or the mobile buttons). Charges = uses: full on spawn and at the portals,
-- kills add more. Each recovers RecoverPercent of max health / mana gradually over Duration seconds,
-- and can't be drunk again until that ends
PlayerStats.FLASKS = {
	Life = { MaxCharges = 3, RecoverPercent = 0.4, Duration = 1.5 },
	Mana = { MaxCharges = 3, RecoverPercent = 0.5, Duration = 1.5 },
} :: { [string]: { MaxCharges: number, RecoverPercent: number, Duration: number } }
PlayerStats.FLASK_CHARGE_PER_KILL = 0.25 -- Uses gained per enemy killed (4 kills = 1 use) for every flask, for everyone who hit it
PlayerStats.FLASK_CHARGE_PER_BOSS_KILL = 1

-- EXP needed to go from `level` to `level + 1`
function PlayerStats.expToNext(level: number): number
	return 60 + level * 40
end

-- bonus = extra stats on top, e.g. the passive tree (PassiveData.getStats)
function PlayerStats.compute(level: number, equipped: { [string]: ItemData.Item }, bonus: { [string]: number }?): Stats
	local stats: { [string]: number } = {
		MaxHealth = PlayerStats.BASE_MAX_HEALTH + (level - 1) * PlayerStats.MAX_HEALTH_PER_LEVEL,
		MaxMana = PlayerStats.BASE_MAX_MANA + (level - 1) * PlayerStats.MAX_MANA_PER_LEVEL,
		MaxEnergyShield = 0,
		EnergyShieldRecharge = 0,
		FlatDamage = (level - 1) * PlayerStats.DAMAGE_PER_LEVEL,
		AttackSpeed = 0,
		FireDamage = 0,
		ColdDamage = 0,
		LightningDamage = 0,
		FireResistance = 0,
		ColdResistance = 0,
		LightningResistance = 0,
	}
	for _, item in pairs(equipped) do
		for stat, value in pairs(ItemData.getStats(item)) do
			stats[stat] = (stats[stat] or 0) + value
		end
	end
	for stat, value in pairs(bonus or {}) do
		stats[stat] = (stats[stat] or 0) + value
	end
	return stats :: any
end

-- Skill cooldown after attack speed: +100% attack speed = half the cooldown
function PlayerStats.getCooldown(baseCooldown: number, attackSpeed: number): number
	return baseCooldown / (1 + attackSpeed / 100)
end

return PlayerStats
