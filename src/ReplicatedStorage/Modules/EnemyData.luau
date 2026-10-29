-- ==========================================
-- ENEMY DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.EnemyData
-- ==========================================
-- Key = enemy type id. Spawn markers in Workspace.EnemySpawns use it as their name or EnemyType attribute
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
		Kind: "Melee" | "Slam",
		Range: number, -- Starts the attack when the target is this close
		Radius: number?, -- Slam only: damage circle around the enemy
		Windup: number, -- Seconds of warning before the hit lands (time for players to dodge)
		Cooldown: number,
		MinDamage: number,
		MaxDamage: number,
	},
	Exp: number, -- Given to every player who damaged it
	RespawnTime: number,
	Drops: {
		Rolls: number, -- How many times to roll for an item
		Chance: number, -- Chance per roll to drop an item (0-1)
		RarityWeights: { [string]: number }, -- Weight per rarity in ItemData.Rarities
	},
}

local EnemyData: { [string]: EnemyType } = {
	Grunt = {
		DisplayName = "ภูตหิน",
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
			Range = 4.5,
			Windup = 0.45,
			Cooldown = 1.6,
			MinDamage = 8,
			MaxDamage = 12,
		},
		Exp = 25,
		RespawnTime = 30,
		Drops = {
			Rolls = 1,
			Chance = 0.4,
			RarityWeights = { Normal = 60, Magic = 32, Rare = 8 },
		},
	},
	Brute = {
		DisplayName = "ยักษ์หินผู้พิทักษ์",
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
		},
	},
}

return EnemyData
