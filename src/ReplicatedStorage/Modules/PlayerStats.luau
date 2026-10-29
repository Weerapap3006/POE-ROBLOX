-- ==========================================
-- PLAYER STATS (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.PlayerStats
-- ==========================================
-- Final stats = base + level growth + every equipped item (ItemData.getStats)
local ItemData = require(script.Parent:WaitForChild("ItemData"))

export type Stats = {
	MaxHealth: number,
	FlatDamage: number, -- Added to every skill's damage roll
	AttackSpeed: number, -- % faster skill cooldowns
}

local PlayerStats = {}

PlayerStats.MAX_LEVEL = 30
PlayerStats.BASE_MAX_HEALTH = 100
PlayerStats.MAX_HEALTH_PER_LEVEL = 12
PlayerStats.DAMAGE_PER_LEVEL = 2

-- Dodge roll (Space / mobile Dodge button). Jumping is turned off, the roll replaces it
PlayerStats.DODGE_COOLDOWN = 1 -- Seconds between rolls (AttackSpeed doesn't change it)
PlayerStats.DODGE_DURATION = 0.35 -- Seconds the roll pushes the character
PlayerStats.DODGE_DISTANCE = 13 -- Studs covered by one roll
PlayerStats.DODGE_INVULNERABLE_TIME = 0.4 -- Enemy hits miss for this long after the server gets the roll

-- EXP needed to go from `level` to `level + 1`
function PlayerStats.expToNext(level: number): number
	return 60 + level * 40
end

function PlayerStats.compute(level: number, equipped: { [string]: ItemData.Item }): Stats
	local stats: { [string]: number } = {
		MaxHealth = PlayerStats.BASE_MAX_HEALTH + (level - 1) * PlayerStats.MAX_HEALTH_PER_LEVEL,
		FlatDamage = (level - 1) * PlayerStats.DAMAGE_PER_LEVEL,
		AttackSpeed = 0,
	}
	for _, item in pairs(equipped) do
		for stat, value in pairs(ItemData.getStats(item)) do
			stats[stat] = (stats[stat] or 0) + value
		end
	end
	return stats :: any
end

-- Skill cooldown after attack speed: +100% attack speed = half the cooldown
function PlayerStats.getCooldown(baseCooldown: number, attackSpeed: number): number
	return baseCooldown / (1 + attackSpeed / 100)
end

return PlayerStats
