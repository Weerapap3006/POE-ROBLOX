-- ==========================================
-- ENEMY DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.EnemyData
-- ==========================================
-- Key = enemy type id. Spawn markers in Workspace.EnemySpawns use it as their name or EnemyType attribute.
-- A type with Pack spawns a whole mixed pack around each of its markers (dense maps); the rest spawn alone
-- Attack kinds (EnemyService): Melee = hits its target, Slam = circle around itself, Projectile = throws a shot along
-- a line that players can step out of, Explode = runs in, then blows itself up (a circle, it dies)
export type EnemyType = {
	DisplayName: string,
	IsBoss: boolean,
	MaxHealth: number,
	WalkSpeed: number,
	Scale: number, -- Size multiplier of the blockout body
	BodyColor: Color3,
	EyeColor: Color3,
	AggroRange: number, -- Starts chasing a player this close
	LeashRange: number, -- Gives up and walks home (healing to full) when pulled this far from its spawn
	Attack: {
		Kind: "Melee" | "Slam" | "Projectile" | "Explode",
		-- Fire / Cold / Lightning hits are reduced by the player's resistance and inflict ailments (see Elements)
		Element: "Physical" | "Fire" | "Cold" | "Lightning",
		Range: number, -- Starts the attack when the target is this close (Projectile: and in sight)
		Radius: number?, -- Slam / Explode: damage circle around the enemy
		Speed: number?, -- Projectile: studs per second
		Width: number?, -- Projectile: how close to its line a player must be to get hit
		Windup: number, -- Seconds of warning before the hit lands (time for players to dodge)
		Cooldown: number,
		MinDamage: number,
		MaxDamage: number,
	},
	-- Each marker of this type spawns Size enemies, each type picked by Weights (EnemyData keys). nil = just one
	Pack: { Size: number, Weights: { [string]: number } }?,
	Exp: number, -- Given to every player who damaged it
	RespawnTime: number,
	Drops: {
		Rolls: number, -- How many times to roll for an item
		Chance: number, -- Chance per roll to drop an item (0-1)
		RarityWeights: { [string]: number }, -- Weight per rarity in ItemData.Rarities
		-- Expected counts (0.1 = 10% for one, 2 = two). A Stone Tablet run adds its loot bonus on top (TabletData)
		RuneChance: number, -- Random stone rune (RuneData)
		SkillChance: number, -- Random Skill Stone (SkillData)
		SpiritChance: number, -- Random Stone Spirit (SpiritData)
		StoneChance: number, -- Random crafting stone (StoneData)
		TabletChance: number, -- Stone Tablet (Tier 1 from a plain run, the run's tier from a tablet run)
	},
}

-- Drops of the small monsters in a pack (lower than before packs: three times as many monsters now)
local PACK_DROPS = {
	Rolls = 1,
	Chance = 0.3,
	RarityWeights = { Normal = 60, Magic = 32, Rare = 8 },
	RuneChance = 0.06,
	SkillChance = 0.02,
	SpiritChance = 0,
	StoneChance = 0.12,
	TabletChance = 0.015,
}

local EnemyData: { [string]: EnemyType } = {
	Grunt = {
		DisplayName = "Stone Grunt",
		IsBoss = false,
		MaxHealth = 120,
		WalkSpeed = 13, -- Slower than the player (18) so you can kite
		Scale = 1,
		BodyColor = Color3.fromRGB(125, 115, 105),
		EyeColor = Color3.fromRGB(255, 70, 60),
		AggroRange = 35,
		LeashRange = 70,
		Attack = {
			Kind = "Melee",
			Element = "Physical",
			Range = 4.5,
			Windup = 0.45,
			Cooldown = 1.6,
			MinDamage = 8,
			MaxDamage = 12,
		},
		Exp = 20,
		RespawnTime = 30,
		-- Every Grunt marker on the map spawns a mixed pack of 3
		Pack = { Size = 3, Weights = { Grunt = 5, Slinger = 3, Bomber = 2 } },
		Drops = PACK_DROPS,
	},
	Slinger = {
		DisplayName = "Stone Slinger",
		IsBoss = false,
		MaxHealth = 70,
		WalkSpeed = 12,
		Scale = 0.9,
		BodyColor = Color3.fromRGB(150, 135, 110),
		EyeColor = Color3.fromRGB(120, 220, 255),
		AggroRange = 40,
		LeashRange = 70,
		Attack = {
			Kind = "Projectile", -- Stops at range, aims (red line), throws a stone along that line
			Element = "Physical",
			Range = 22,
			Speed = 45,
			Width = 2,
			Windup = 0.6,
			Cooldown = 1.8,
			MinDamage = 6,
			MaxDamage = 10,
		},
		Exp = 20,
		RespawnTime = 30,
		Drops = PACK_DROPS,
	},
	Bomber = {
		DisplayName = "Rubble Bomber",
		IsBoss = false,
		MaxHealth = 50,
		WalkSpeed = 17, -- Almost as fast as the player
		Scale = 0.8,
		BodyColor = Color3.fromRGB(170, 90, 60),
		EyeColor = Color3.fromRGB(255, 200, 60),
		AggroRange = 35,
		LeashRange = 70,
		Attack = {
			Kind = "Explode", -- Runs in, glows (red circle), then blows up and dies (no loot or EXP when it does)
			Element = "Fire",
			Range = 4,
			Radius = 7,
			Windup = 0.8,
			Cooldown = 0,
			MinDamage = 20,
			MaxDamage = 30,
		},
		Exp = 15,
		RespawnTime = 30,
		Drops = PACK_DROPS,
	},
	Brute = {
		DisplayName = "Stone Guardian",
		IsBoss = true,
		MaxHealth = 1500,
		WalkSpeed = 10,
		Scale = 2.4,
		BodyColor = Color3.fromRGB(85, 75, 100),
		EyeColor = Color3.fromRGB(255, 170, 40),
		AggroRange = 45,
		LeashRange = 90,
		Attack = {
			Kind = "Slam",
			Element = "Fire", -- Burns players it hits; Fire Resistance helps
			Range = 9,
			Radius = 12,
			Windup = 1.0,
			Cooldown = 2.5,
			MinDamage = 25,
			MaxDamage = 40,
		},
		Exp = 300,
		RespawnTime = 90,
		Drops = {
			Rolls = 3,
			Chance = 1,
			RarityWeights = { Magic = 50, Rare = 50 },
			RuneChance = 1, -- The boss always drops a rune,
			SkillChance = 0.5, -- a Skill Stone half the time,
			SpiritChance = 0.3, -- a Stone Spirit 30% of the time,
			StoneChance = 2, -- two crafting stones
			TabletChance = 1, -- and a Stone Tablet
		},
	},
}

return EnemyData
