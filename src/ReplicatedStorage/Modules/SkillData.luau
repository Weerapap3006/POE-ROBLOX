-- ==========================================
-- SKILL DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.SkillData
-- ==========================================
-- Every skill is also a Skill Stone item (ItemData "Skill" .. id) that drops and goes on the 4-slot skill bar.
-- Damage per hit = random(MinDamage, MaxDamage) + player's FlatDamage stat (level + items), dealt as the skill's
-- Element, plus the player's elemental damage from items. A crit multiplies all of it
-- Real cooldown = Cooldown / (1 + AttackSpeed% / 100) (AttackSpeed comes from items)
-- ManaCost is paid on every use (not enough mana = the skill doesn't fire)
-- Shapes (hit rules in CombatServer + SkillCast, looks in CombatClient):
--   Box        = box in front of the character, toward the aim point
--   Radius     = circle around the character, or CenterOffset studs in front of it
--   Projectile = flies toward the aim point, hits the first enemy (stops at walls), may explode on impact
--   Chain      = strikes the enemy nearest the aim point, then jumps to more enemies nearby
export type Skill = {
	Name: string,
	Kind: "Melee" | "Ranged" | "Spell",
	Element: string, -- "Physical" or an Elements type (Fire / Cold / Lightning): what the skill's own hit is
	Description: string, -- Shown in the inventory
	Animation: "Slash" | "Spin" | "Slam" | "Cast", -- Body pose in CombatClient
	Cooldown: number,
	ManaCost: number,
	Sockets: number, -- How many stone runes fit in this skill (see RuneData)
	MinDamage: number,
	MaxDamage: number,
	CritChance: number,
	CritMultiplier: number,
	Shape: "Box" | "Radius" | "Projectile" | "Chain",
	HitboxSize: Vector3?, -- Box: Width, Height, Length of the hit box
	HitboxForwardOffset: number?, -- Box: studs in front of the character
	Radius: number?, -- Radius: studs around the center
	CenterOffset: number?, -- Radius: center this many studs in front of the character (nil = on the character)
	Range: number?, -- Projectile: max flight distance. Chain: max distance to the first target
	Speed: number?, -- Projectile: studs per second (damage lands when it arrives)
	Width: number?, -- Projectile: how wide its path is
	ExplosionRadius: number?, -- Projectile: hits everything this close to where it lands (nil = only the enemy it hits)
	Chains: number?, -- Chain: extra enemies after the first
	ChainRange: number?, -- Chain: max jump distance between enemies
}

local SkillData: { [string]: Skill } = {
	BasicSlash = {
		Name = "Slash",
		Kind = "Melee",
		Element = "Physical",
		Description = "Quick slash in front of you. Costs no mana",
		Animation = "Slash",
		Cooldown = 0.55, -- Seconds between attacks
		ManaCost = 0, -- Basic attack is free, so running out of mana never leaves you without an attack
		Sockets = 2,
		MinDamage = 26,
		MaxDamage = 50,
		CritChance = 0.25, -- 25% chance
		CritMultiplier = 2.0, -- 200% damage on crit
		Shape = "Box",
		HitboxSize = Vector3.new(9, 6, 9),
		HitboxForwardOffset = 5.0,
	},
	SpinSlash = {
		Name = "Spin Slash",
		Kind = "Melee",
		Element = "Physical",
		Description = "Spin and hit everything around you",
		Animation = "Spin",
		Cooldown = 3.0,
		ManaCost = 15,
		Sockets = 3,
		MinDamage = 40,
		MaxDamage = 70,
		CritChance = 0.15,
		CritMultiplier = 2.0,
		Shape = "Radius",
		Radius = 10,
	},
	GroundSlam = {
		Name = "Ground Slam",
		Kind = "Melee",
		Element = "Physical",
		Description = "Smash the ground in front of you, hitting a wide circle",
		Animation = "Slam",
		Cooldown = 4.0,
		ManaCost = 20,
		Sockets = 3,
		MinDamage = 60,
		MaxDamage = 100,
		CritChance = 0.1,
		CritMultiplier = 2.0,
		Shape = "Radius",
		Radius = 8,
		CenterOffset = 7,
	},
	StoneShot = {
		Name = "Stone Shot",
		Kind = "Ranged",
		Element = "Physical",
		Description = "Throw a fast stone at the first enemy in its path. Costs no mana",
		Animation = "Cast",
		Cooldown = 0.6,
		ManaCost = 0,
		Sockets = 2,
		MinDamage = 18,
		MaxDamage = 34,
		CritChance = 0.2,
		CritMultiplier = 2.0,
		Shape = "Projectile",
		Range = 45,
		Speed = 110,
		Width = 2,
	},
	Fireball = {
		Name = "Fireball",
		Kind = "Spell",
		Element = "Fire",
		Description = "Hurl a ball of fire that explodes where it lands and burns enemies",
		Animation = "Cast",
		Cooldown = 1.2,
		ManaCost = 10,
		Sockets = 3,
		MinDamage = 30,
		MaxDamage = 50,
		CritChance = 0.1,
		CritMultiplier = 2.0,
		Shape = "Projectile",
		Range = 40,
		Speed = 60,
		Width = 2.5,
		ExplosionRadius = 6,
	},
	FrostNova = {
		Name = "Frost Nova",
		Kind = "Spell",
		Element = "Cold",
		Description = "Burst of ice around you that chills enemies and freezes weak ones",
		Animation = "Cast",
		Cooldown = 5.0,
		ManaCost = 18,
		Sockets = 2,
		MinDamage = 30,
		MaxDamage = 45,
		CritChance = 0.1,
		CritMultiplier = 2.0,
		Shape = "Radius",
		Radius = 12,
	},
	Arc = {
		Name = "Arc",
		Kind = "Spell",
		Element = "Lightning",
		Description = "Lightning that strikes the enemy nearest your aim, then jumps to 3 more and shocks them",
		Animation = "Cast",
		Cooldown = 1.0,
		ManaCost = 8,
		Sockets = 2,
		MinDamage = 20,
		MaxDamage = 36,
		CritChance = 0.1,
		CritMultiplier = 2.0,
		Shape = "Chain",
		Range = 30,
		Chains = 3,
		ChainRange = 12,
	},
}

return SkillData
