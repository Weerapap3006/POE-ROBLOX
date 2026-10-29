-- ==========================================
-- SKILL DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.SkillData
-- ==========================================
-- Damage per hit = random(MinDamage, MaxDamage) + player's FlatDamage stat (level + items)
-- Real cooldown = Cooldown / (1 + AttackSpeed% / 100) (AttackSpeed comes from items)
export type Skill = {
	Name: string,
	Cooldown: number,
	MinDamage: number,
	MaxDamage: number,
	CritChance: number,
	CritMultiplier: number,
	Shape: "Box" | "Radius",
	HitboxSize: Vector3?, -- Box: Width, Height, Length of the hit box
	HitboxForwardOffset: number?, -- Box: studs in front of the character
	Radius: number?, -- Radius: studs around the character
}

local SkillData: { [string]: Skill } = {
	BasicSlash = {
		Name = "ฟัน",
		Cooldown = 0.55, -- Seconds between attacks
		MinDamage = 26,
		MaxDamage = 50,
		CritChance = 0.25, -- 25% chance
		CritMultiplier = 2.0, -- 200% damage on crit
		Shape = "Box",
		HitboxSize = Vector3.new(9, 6, 9),
		HitboxForwardOffset = 5.0,
	},
	SpinSlash = {
		Name = "หมุนฟัน",
		Cooldown = 3.0,
		MinDamage = 40,
		MaxDamage = 70,
		CritChance = 0.15,
		CritMultiplier = 2.0,
		Shape = "Radius",
		Radius = 10,
	},
}

return SkillData
