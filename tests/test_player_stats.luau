--[[
   Unit Test for PlayerStats.luau
   Run via: lune run tests/test_player_stats.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

-- 1. Setup mock environment
local Color3 = {
	fromRGB = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
}

local mockEnv: { [string]: any } = {}
for k, v in pairs(getfenv()) do
	mockEnv[k] = v
end
mockEnv.Color3 = Color3
mockEnv.Vector3 = {
	new = function(x, y, z)
		return { X = x, Y = y, Z = z }
	end,
}

-- Load RuneData, TabletData and SkillData first
local runeDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/RuneData.luau"))
local RuneData = luau.load(runeDataBytecode, { environment = mockEnv })()

local tabletDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/TabletData.luau"))
local TabletData = luau.load(tabletDataBytecode, { environment = mockEnv })()

local skillDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/SkillData.luau"))
local SkillData = luau.load(skillDataBytecode, { environment = mockEnv })()

local spiritDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/SpiritData.luau"))
local SpiritData = luau.load(spiritDataBytecode, { environment = mockEnv })()

-- Setup script mock for ItemData
local itemDataScript = {
	Parent = {
		WaitForChild = function(_self, name)
			if name == "RuneData" then
				return "RuneData"
			elseif name == "TabletData" then
				return "TabletData"
			elseif name == "SkillData" then
				return "SkillData"
			elseif name == "SpiritData" then
				return "SpiritData"
			end
			error("Child not found: " .. tostring(name))
		end,
	},
}

local itemDataEnv: { [string]: any } = {}
for k, v in pairs(mockEnv) do
	itemDataEnv[k] = v
end
itemDataEnv.script = itemDataScript
itemDataEnv.require = function(target)
	if target == "RuneData" then
		return RuneData
	elseif target == "TabletData" then
		return TabletData
	elseif target == "SkillData" then
		return SkillData
	elseif target == "SpiritData" then
		return SpiritData
	end
	return require(target)
end

local itemDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/ItemData.luau"))
local ItemData = luau.load(itemDataBytecode, { environment = itemDataEnv })()

-- Setup script mock for PlayerStats
local playerStatsScript = {
	Parent = {
		WaitForChild = function(_self, name)
			if name == "ItemData" then
				return "ItemData"
			end
			error("Child not found: " .. tostring(name))
		end,
	},
}

local playerStatsEnv: { [string]: any } = {}
for k, v in pairs(mockEnv) do
	playerStatsEnv[k] = v
end
playerStatsEnv.script = playerStatsScript
playerStatsEnv.require = function(target)
	if target == "ItemData" or target == ItemData then
		return ItemData
	end
	return require(target)
end

local playerStatsBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/PlayerStats.luau"))
local PlayerStats = luau.load(playerStatsBytecode, { environment = playerStatsEnv })()

-- 2. Test Suite
local passed = 0
local failed = 0

local function test(name: string, fn: () -> ())
	local success, err = pcall(fn)
	if success then
		print("  ✅ PASS: " .. name)
		passed += 1
	else
		print("  ❌ FAIL: " .. name)
		print("     " .. tostring(err))
		failed += 1
	end
end

local function assertEq(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(string.format("Expected %s, got %s. %s", tostring(expected), tostring(actual), message or ""))
	end
end

print("🧪 Running Unit Tests: PlayerStats")

test("Level 1 base stats without equipment", function()
	local stats = PlayerStats.compute(1, {})
	assertEq(stats.MaxHealth, 100, "Base MaxHealth should be 100")
	assertEq(stats.MaxMana, 50, "Base MaxMana should be 50")
	assertEq(stats.FlatDamage, 0, "Base FlatDamage at level 1 should be 0")
	assertEq(stats.AttackSpeed, 0, "Base AttackSpeed should be 0")
end)

test("Level growth scaling", function()
	-- Level 2: MaxHealth = 100 + 1*12 = 112, MaxMana = 50 + 1*4 = 54, Damage = 1*2 = 2
	local statsLvl2 = PlayerStats.compute(2, {})
	assertEq(statsLvl2.MaxHealth, 112, "MaxHealth at level 2 should be 112")
	assertEq(statsLvl2.MaxMana, 54, "MaxMana at level 2 should be 54")
	assertEq(statsLvl2.FlatDamage, 2, "FlatDamage at level 2 should be 2")

	-- Level 10: MaxHealth = 100 + 9*12 = 208, MaxMana = 50 + 9*4 = 86, Damage = 9*2 = 18
	local statsLvl10 = PlayerStats.compute(10, {})
	assertEq(statsLvl10.MaxHealth, 208, "MaxHealth at level 10 should be 208")
	assertEq(statsLvl10.MaxMana, 86, "MaxMana at level 10 should be 86")
	assertEq(statsLvl10.FlatDamage, 18, "FlatDamage at level 10 should be 18")
end)

test("expToNext formula", function()
	assertEq(PlayerStats.expToNext(1), 100, "EXP for level 1 -> 2 should be 100")
	assertEq(PlayerStats.expToNext(5), 260, "EXP for level 5 -> 6 should be 260")
end)

test("Cooldown calculation with attack speed", function()
	assertEq(PlayerStats.getCooldown(1.0, 0), 1.0, "Cooldown with 0% attack speed")
	assertEq(PlayerStats.getCooldown(1.0, 100), 0.5, "Cooldown with 100% attack speed")
	assertEq(PlayerStats.getCooldown(1.0, 300), 0.25, "Cooldown with 300% attack speed")
end)

test("Equipped items stat aggregation", function()
	local fakeItem: any = {
		Id = "test_item_1",
		Base = "IronSword", -- Base IronSword has implicit FlatDamage: 5
		Rarity = "Magic",
		Affixes = {
			{ Id = "FlatDamage", Value = 5 },
			{ Id = "MaxHealth", Value = 20 },
		},
	}

	local stats = PlayerStats.compute(1, { Weapon = fakeItem })
	assertEq(stats.MaxHealth, 120, "100 base + 20 from item = 120")
	assertEq(stats.FlatDamage, 10, "5 implicit + 5 affix = 10 flat damage")
end)

test("Passive tree bonus stats integration", function()
	local bonus = {
		MaxHealth = 50,
		FireDamage = 15,
		AttackSpeed = 20,
	}

	local stats = PlayerStats.compute(1, {}, bonus)
	assertEq(stats.MaxHealth, 150, "100 base + 50 passive = 150")
	assertEq(stats.FireDamage, 15, "0 base + 15 passive = 15")
	assertEq(stats.AttackSpeed, 20, "0 base + 20 passive = 20")
end)

test("Stone Spirit stats are real stats and add up", function()
	local base = PlayerStats.compute(1, {})
	for spiritId, spirit in pairs(SpiritData.Spirits) do
		for stat in pairs(spirit.Stats) do
			assertEq(base[stat] ~= nil, true, spiritId .. " stat " .. stat .. " exists in PlayerStats.compute")
		end
	end
	local stats = SpiritData.getStats({ "MossGolem", "", "NotASpirit" })
	assertEq(stats.MaxHealth, SpiritData.Spirits.MossGolem.Stats.MaxHealth, "Empty and unknown slots add nothing")
	local withSpirits = PlayerStats.compute(1, {}, stats)
	assertEq(withSpirits.MaxHealth, base.MaxHealth + stats.MaxHealth, "Spirit stats come on top like passives")
	assertEq(base.ManaRegen, 0, "No mana regen bonus without spirits")
	assertEq(base.LootQuantity, 0, "No loot bonus without spirits")
end)

test("Skill bar settings match each other and SkillData", function()
	assertEq(#PlayerStats.STARTING_SKILLS, PlayerStats.SKILL_BAR_SLOTS, "One starting entry per skill bar slot")
	assertEq(#PlayerStats.SKILL_BAR_KEYS, PlayerStats.SKILL_BAR_SLOTS, "One key label per skill bar slot")
	local seen = {}
	for _, skillId in ipairs(PlayerStats.STARTING_SKILLS) do
		if skillId ~= "" then
			assertEq(SkillData[skillId] ~= nil, true, "Starting skill exists: " .. skillId)
			assertEq(seen[skillId], nil, "No starting skill twice: " .. skillId)
			seen[skillId] = true
		end
	end
end)

print(string.format("\n📊 Results: %d passed, %d failed\n", passed, failed))

if failed > 0 then
	error(string.format("Test suite failed with %d errors", failed))
end
