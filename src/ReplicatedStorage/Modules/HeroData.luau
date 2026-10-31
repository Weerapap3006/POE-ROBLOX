-- ==========================================
-- HERO DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.HeroData
-- ==========================================
-- Each class (PassiveData.Classes) has its own hero mechanic that changes how it plays, on top of the shared
-- passive tree. At VARIANT_LEVEL the player picks one of two paths that change the mechanic (free to switch).
-- The rules run in ServerStorage.Modules.HeroService; HeroClient shows the meter and the orbs
--   Warrior / Fury     : hitting enemies with skills builds Fury, a full bar makes the next skill hit much harder
--   Ranger  / Momentum : moving and dodging build stacks of attack speed, standing still loses them
--   Mystic  / Stone Orbs: spending mana makes orbs that float around you and shoot enemies by themselves
export type Variant = {
	Name: string,
	Description: string,
}

export type Hero = {
	Mechanic: string, -- Shown on the meter and in the class window
	Description: string,
	Color: Color3, -- Meter color
	Variants: { [string]: Variant },
	VariantOrder: { string },
}

local HeroData = {}

HeroData.VARIANT_LEVEL = 10 -- Paths unlock at this level

HeroData.Heroes = {
	Warrior = {
		Mechanic = "Fury",
		Description = "Hitting enemies with skills builds Fury. At full Fury your next skill deals double damage",
		Color = Color3.fromRGB(235, 80, 60),
		Variants = {
			Berserker = {
				Name = "Berserker",
				Description = "Fury is never spent: every 10 Fury gives +5% damage (up to +50%) and it fades slower",
			},
			Earthbreaker = {
				Name = "Earthbreaker",
				Description = "A full-Fury skill deals triple damage and also shakes the ground around you",
			},
		},
		VariantOrder = { "Berserker", "Earthbreaker" },
	},
	Ranger = {
		Mechanic = "Momentum",
		Description = "Moving and dodging build Momentum: +3% attack speed per stack. Standing still loses it all",
		Color = Color3.fromRGB(110, 215, 110),
		Variants = {
			Windrunner = {
				Name = "Windrunner",
				Description = "Each stack also gives +2% movement speed",
			},
			Deadeye = {
				Name = "Deadeye",
				Description = "Each stack also gives +3% critical strike chance",
			},
		},
		VariantOrder = { "Windrunner", "Deadeye" },
	},
	Mystic = {
		Mechanic = "Stone Orbs",
		Description = "Every 30 mana you spend makes a Stone Orb (up to 3) that floats around you and shoots enemies",
		Color = Color3.fromRGB(150, 130, 255),
		Variants = {
			Stormcaller = {
				Name = "Stormcaller",
				Description = "Orbs shoot faster and deal Lightning damage that shocks",
			},
			Wardstone = {
				Name = "Wardstone",
				Description = "Orbs don't shoot: each one blocks an enemy hit completely",
			},
		},
		VariantOrder = { "Stormcaller", "Wardstone" },
	},
} :: { [string]: Hero }

-- Warrior: Fury
HeroData.FURY_MAX = 100
HeroData.FURY_PER_HIT = 6 -- Per enemy a skill hits
HeroData.FURY_DECAY_DELAY = 4 -- Seconds without hitting anything before Fury starts fading
HeroData.FURY_DECAY_PER_SECOND = 15
HeroData.FURY_RELEASE_MULTIPLIER = 2 -- Damage of the skill used at full Fury
HeroData.BERSERKER_DAMAGE_PER_10_FURY = 0.05 -- Berserker: +5% damage per 10 Fury, Fury is never spent
HeroData.BERSERKER_DECAY_PER_SECOND = 5
HeroData.EARTHBREAKER_MULTIPLIER = 3 -- Earthbreaker: damage of the full-Fury skill
HeroData.EARTHBREAKER_RADIUS = 10 -- and it also hits everything this close to you

-- Ranger: Momentum
HeroData.MOMENTUM_MAX = 10
HeroData.MOMENTUM_STUDS_PER_STACK = 8 -- Studs walked per stack
HeroData.MOMENTUM_PER_DODGE = 2
HeroData.MOMENTUM_STILL_TIME = 1 -- Seconds standing still before all stacks are lost
HeroData.MOMENTUM_ATTACK_SPEED = 3 -- % attack speed per stack (added to the AttackSpeed stat)
HeroData.WINDRUNNER_MOVE_SPEED = 0.02 -- Windrunner: +2% walk speed per stack
HeroData.DEADEYE_CRIT_CHANCE = 0.03 -- Deadeye: +3% crit chance per stack

-- Mystic: Stone Orbs
HeroData.ORB_MAX = 3
HeroData.ORB_MANA = 30 -- Mana spent per orb
HeroData.ORB_DURATION = 15 -- Seconds each orb lasts (a new orb at the limit refreshes the oldest)
HeroData.ORB_RANGE = 25 -- Studs: orbs shoot enemies this close to the player
HeroData.ORB_INTERVAL = 1.2 -- Seconds between volleys (every orb shoots once)
HeroData.ORB_DAMAGE = 8 -- Per shot, plus ORB_FLAT_DAMAGE_SHARE of the player's FlatDamage
HeroData.ORB_FLAT_DAMAGE_SHARE = 0.5
HeroData.STORMCALLER_INTERVAL = 0.8 -- Stormcaller: faster volleys, Lightning damage

-- The hero entry of a class, nil when there's no class
function HeroData.get(classId: string?): Hero?
	return if classId then HeroData.Heroes[classId] else nil
end

-- True when this path belongs to the class and the level is high enough
function HeroData.canChoose(classId: string?, variantId: string, level: number): boolean
	local hero = HeroData.get(classId)
	return hero ~= nil and hero.Variants[variantId] ~= nil and level >= HeroData.VARIANT_LEVEL
end

return HeroData
