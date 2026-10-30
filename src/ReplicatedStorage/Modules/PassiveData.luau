-- ==========================================
-- PASSIVE DATA (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.PassiveData
-- ==========================================
-- One small passive tree shared by every class. A class = where you start on it (its Start node is free)
-- plus that node's bonus. Every level after 1 gives a point; a node can be taken when it links to one you
-- already have. Node stats add to the player's stats like gear does (PlayerStats.compute).
-- Server rules: ServerStorage.Modules.PlayerData (ChooseClass / AllocatePassive / ResetPassives), window:
-- StarterPlayerScripts.PassiveTreeClient
export type Node = {
	Name: string,
	Kind: "Start" | "Notable" | "Small",
	Stats: { [string]: number }, -- Same stat names as ItemData affixes / PlayerStats
	Position: Vector2, -- Grid cell in the tree window: X 0-10 across, Y 0-8 down
}

export type Class = {
	Name: string,
	Start: string, -- Its Start node
	Description: string,
	Color: Color3,
}

local PassiveData = {}

PassiveData.GRID_SIZE = Vector2.new(11, 9)

PassiveData.Classes = {
	Warrior = {
		Name = "Warrior",
		Start = "WarriorStart",
		Description = "Tough melee fighter. Starts near Health and Damage",
		Color = Color3.fromRGB(225, 95, 80),
	},
	Ranger = {
		Name = "Ranger",
		Start = "RangerStart",
		Description = "Fast striker. Starts near Attack Speed and Lightning",
		Color = Color3.fromRGB(120, 215, 120),
	},
	Mystic = {
		Name = "Mystic",
		Start = "MysticStart",
		Description = "Shielded caster. Starts near Energy Shield, Mana and Fire / Cold",
		Color = Color3.fromRGB(120, 160, 255),
	},
} :: { [string]: Class }

-- Order of the class cards in the class picker
PassiveData.ClassOrder = { "Warrior", "Ranger", "Mystic" }

PassiveData.Nodes = {
	-- Warrior (bottom-left)
	WarriorStart = { Name = "Warrior", Kind = "Start", Stats = { MaxHealth = 20, FlatDamage = 2 }, Position = Vector2.new(1, 8) },
	Toughness = { Name = "Toughness", Kind = "Small", Stats = { MaxHealth = 15 }, Position = Vector2.new(0, 7) },
	BruteForce = { Name = "Brute Force", Kind = "Small", Stats = { FlatDamage = 3 }, Position = Vector2.new(2, 8) },
	ThickSkin = { Name = "Thick Skin", Kind = "Small", Stats = { MaxHealth = 15 }, Position = Vector2.new(0, 6) },
	HeavyBlows = { Name = "Heavy Blows", Kind = "Small", Stats = { FlatDamage = 3 }, Position = Vector2.new(3, 8) },
	FlameHide = { Name = "Flame Hide", Kind = "Small", Stats = { FireResistance = 12 }, Position = Vector2.new(0, 5) },
	CrushingForce = { Name = "Crushing Force", Kind = "Small", Stats = { FlatDamage = 4 }, Position = Vector2.new(4, 8) },
	Unbreakable = { Name = "Unbreakable", Kind = "Notable", Stats = { MaxHealth = 40, FlatDamage = 3 }, Position = Vector2.new(1, 7) },
	Momentum = { Name = "Momentum", Kind = "Small", Stats = { MaxHealth = 10, FlatDamage = 2 }, Position = Vector2.new(2, 6) },

	-- Ranger (bottom-right)
	RangerStart = { Name = "Ranger", Kind = "Start", Stats = { AttackSpeed = 5, LightningDamage = 2 }, Position = Vector2.new(9, 8) },
	QuickHands = { Name = "Quick Hands", Kind = "Small", Stats = { AttackSpeed = 4 }, Position = Vector2.new(10, 7) },
	ChargedEdge = { Name = "Charged Edge", Kind = "Small", Stats = { LightningDamage = 3 }, Position = Vector2.new(8, 8) },
	Swiftness = { Name = "Swiftness", Kind = "Small", Stats = { AttackSpeed = 4 }, Position = Vector2.new(10, 6) },
	Spark = { Name = "Spark", Kind = "Small", Stats = { LightningDamage = 3 }, Position = Vector2.new(7, 8) },
	Grounding = { Name = "Grounding", Kind = "Small", Stats = { LightningResistance = 12 }, Position = Vector2.new(10, 5) },
	Thunderstrike = { Name = "Thunderstrike", Kind = "Small", Stats = { LightningDamage = 4 }, Position = Vector2.new(6, 8) },
	StormDancer = { Name = "Storm Dancer", Kind = "Notable", Stats = { AttackSpeed = 10, LightningDamage = 3 }, Position = Vector2.new(9, 7) },
	Flow = { Name = "Flow", Kind = "Small", Stats = { AttackSpeed = 3, MaxHealth = 5 }, Position = Vector2.new(8, 6) },

	-- Mystic (top)
	MysticStart = { Name = "Mystic", Kind = "Start", Stats = { MaxEnergyShield = 15, MaxMana = 15 }, Position = Vector2.new(5, 0) },
	Warding = { Name = "Warding", Kind = "Small", Stats = { MaxEnergyShield = 12 }, Position = Vector2.new(4, 0) },
	Clarity = { Name = "Clarity", Kind = "Small", Stats = { MaxMana = 15 }, Position = Vector2.new(6, 0) },
	FrostSigil = { Name = "Frost Sigil", Kind = "Small", Stats = { ColdDamage = 3 }, Position = Vector2.new(3, 0) },
	EmberSigil = { Name = "Ember Sigil", Kind = "Small", Stats = { FireDamage = 3 }, Position = Vector2.new(7, 0) },
	GlacialTouch = { Name = "Glacial Touch", Kind = "Small", Stats = { ColdDamage = 4 }, Position = Vector2.new(2, 1) },
	KindledMind = { Name = "Kindled Mind", Kind = "Small", Stats = { FireDamage = 4 }, Position = Vector2.new(8, 1) },
	ArcaneBarrier = { Name = "Arcane Barrier", Kind = "Notable", Stats = { MaxEnergyShield = 30, EnergyShieldRecharge = 25 }, Position = Vector2.new(5, 1) },
	InnerCalm = { Name = "Inner Calm", Kind = "Small", Stats = { MaxMana = 10, MaxEnergyShield = 8 }, Position = Vector2.new(5, 2) },

	-- Shared middle: the hub every class can reach, and the nodes around it
	HeartOfStone = { Name = "Heart of Stone", Kind = "Notable", Stats = { FireResistance = 8, ColdResistance = 8, LightningResistance = 8 }, Position = Vector2.new(5, 4) },
	Vitality = { Name = "Vitality", Kind = "Small", Stats = { MaxHealth = 12 }, Position = Vector2.new(4, 5) },
	Precision = { Name = "Precision", Kind = "Small", Stats = { FlatDamage = 3 }, Position = Vector2.new(6, 5) },
	Willpower = { Name = "Willpower", Kind = "Small", Stats = { MaxMana = 12 }, Position = Vector2.new(4, 3) },
	ElementalFocus = { Name = "Elemental Focus", Kind = "Small", Stats = { FireDamage = 2, ColdDamage = 2, LightningDamage = 2 }, Position = Vector2.new(6, 3) },

	-- Bridges along the outside, between two classes' areas
	IronboundMind = { Name = "Ironbound Mind", Kind = "Small", Stats = { MaxHealth = 10, MaxMana = 10 }, Position = Vector2.new(1, 3) },
	QuickenedWards = { Name = "Quickened Wards", Kind = "Small", Stats = { MaxEnergyShield = 10, AttackSpeed = 3 }, Position = Vector2.new(9, 3) },
	BattleRhythm = { Name = "Battle Rhythm", Kind = "Small", Stats = { FlatDamage = 3, AttackSpeed = 3 }, Position = Vector2.new(5, 8) },
} :: { [string]: Node }

-- Links between nodes (both ways)
PassiveData.Edges = {
	{ "WarriorStart", "Toughness" }, { "WarriorStart", "BruteForce" }, { "Toughness", "ThickSkin" },
	{ "BruteForce", "HeavyBlows" }, { "ThickSkin", "FlameHide" }, { "HeavyBlows", "CrushingForce" },
	{ "Toughness", "Unbreakable" }, { "BruteForce", "Unbreakable" }, { "Unbreakable", "Momentum" },
	{ "Momentum", "Vitality" }, -- Warrior's way to the hub

	{ "RangerStart", "QuickHands" }, { "RangerStart", "ChargedEdge" }, { "QuickHands", "Swiftness" },
	{ "ChargedEdge", "Spark" }, { "Swiftness", "Grounding" }, { "Spark", "Thunderstrike" },
	{ "QuickHands", "StormDancer" }, { "ChargedEdge", "StormDancer" }, { "StormDancer", "Flow" },
	{ "Flow", "Precision" }, -- Ranger's way to the hub

	{ "MysticStart", "Warding" }, { "MysticStart", "Clarity" }, { "Warding", "FrostSigil" },
	{ "Clarity", "EmberSigil" }, { "FrostSigil", "GlacialTouch" }, { "EmberSigil", "KindledMind" },
	{ "Warding", "ArcaneBarrier" }, { "Clarity", "ArcaneBarrier" }, { "ArcaneBarrier", "InnerCalm" },
	{ "InnerCalm", "HeartOfStone" },

	{ "HeartOfStone", "Vitality" }, { "HeartOfStone", "Precision" }, { "HeartOfStone", "Willpower" },
	{ "HeartOfStone", "ElementalFocus" },

	{ "FlameHide", "IronboundMind" }, { "IronboundMind", "GlacialTouch" },
	{ "KindledMind", "QuickenedWards" }, { "QuickenedWards", "Grounding" },
	{ "CrushingForce", "BattleRhythm" }, { "BattleRhythm", "Thunderstrike" },
}

local neighbors: { [string]: { string } } = {}
for _, edge in ipairs(PassiveData.Edges) do
	local a, b = edge[1], edge[2]
	neighbors[a] = neighbors[a] or {}
	neighbors[b] = neighbors[b] or {}
	table.insert(neighbors[a], b)
	table.insert(neighbors[b], a)
end

function PassiveData.getNeighbors(nodeId: string): { string }
	return neighbors[nodeId] or {}
end

-- Points earned by a level (every level after 1 gives one)
function PassiveData.getPoints(level: number): number
	return math.max(level - 1, 0)
end

-- nil = this node can be taken next (not counting points), otherwise why not.
-- The server and the tree window use the same rules
function PassiveData.whyNot(classId: string?, allocated: { string }, nodeId: string): string?
	local class = if classId then PassiveData.Classes[classId] else nil
	local node = PassiveData.Nodes[nodeId]
	if not class then
		return "Choose a class first"
	elseif not node then
		return "Unknown passive"
	elseif node.Kind == "Start" then
		return if nodeId == class.Start then "Your class's starting point (always yours)" else "Another class's starting point"
	end

	local taken: { [string]: boolean } = { [class.Start] = true }
	for _, id in ipairs(allocated) do
		taken[id] = true
	end
	if taken[nodeId] then
		return "Already allocated"
	end
	for _, neighbor in ipairs(PassiveData.getNeighbors(nodeId)) do
		if taken[neighbor] then
			return nil
		end
	end
	return "Must connect to a passive you already have"
end

-- Total stats from the class's Start node + every allocated node
function PassiveData.getStats(classId: string?, allocated: { string }): { [string]: number }
	local stats: { [string]: number } = {}
	local class = if classId then PassiveData.Classes[classId] else nil
	if not class then
		return stats
	end
	local function add(nodeId: string)
		local node = PassiveData.Nodes[nodeId]
		if node then
			for stat, value in pairs(node.Stats) do
				stats[stat] = (stats[stat] or 0) + value
			end
		end
	end
	add(class.Start)
	for _, nodeId in ipairs(allocated) do
		add(nodeId)
	end
	return stats
end

-- Saved tree from an older version: keep the nodes that still exist and still connect, up to the points
-- the level gives (order in the save doesn't matter)
function PassiveData.sanitize(classId: string?, saved: any, points: number): { string }
	local result: { string } = {}
	if not classId or not PassiveData.Classes[classId] or type(saved) ~= "table" then
		return result
	end
	local pending: { string } = {}
	for _, nodeId in ipairs(saved) do
		if type(nodeId) == "string" then
			table.insert(pending, nodeId)
		end
	end
	local added = true
	while added and #result < points do
		added = false
		for index, nodeId in ipairs(pending) do
			if PassiveData.whyNot(classId, result, nodeId) == nil then
				table.insert(result, nodeId)
				table.remove(pending, index)
				added = true
				break
			end
		end
	end
	return result
end

return PassiveData
