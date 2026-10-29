-- ==========================================
-- SKILL DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.SkillData
-- ==========================================
local SkillData = {
	BasicSlash = {
		Name = "Basic Slash",
		Cooldown = 0.55, -- Seconds between attacks
		MinDamage = 26,
		MaxDamage = 50,
		CritChance = 0.25, -- 25% chance
		CritMultiplier = 2.0, -- 200% damage on crit
		HitboxSize = Vector3.new(9, 6, 9), -- Width, Height, Length of slash box
		HitboxForwardOffset = 5.0, -- Studs in front of the character
	},
}

return SkillData
