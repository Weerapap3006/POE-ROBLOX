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

-- Load ItemData first
local itemDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/ItemData.luau"))
local ItemData = luau.load(itemDataBytecode, { environment = mockEnv })()

-- Setup script mock for PlayerStats require
local mockScript = {
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
playerStatsEnv.script = mockScript
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
	assertEq(stats.FlatDamage, 0, "Base FlatDamage at level 1 should be 0")
	assertEq(stats.AttackSpeed, 0, "Base AttackSpeed should be 0")
end)

test("Level growth scaling", function()
	-- Level 2: MaxHealth = 100 + (2-1)*12 = 112, Damage = (2-1)*2 = 2
	local statsLvl2 = PlayerStats.compute(2, {})
	assertEq(statsLvl2.MaxHealth, 112, "MaxHealth at level 2 should be 112")
	assertEq(statsLvl2.FlatDamage, 2, "FlatDamage at level 2 should be 2")

	-- Level 10: MaxHealth = 100 + 9*12 = 208, Damage = 9*2 = 18
	local statsLvl10 = PlayerStats.compute(10, {})
	assertEq(statsLvl10.MaxHealth, 208, "MaxHealth at level 10 should be 208")
	assertEq(statsLvl10.FlatDamage, 18, "FlatDamage at level 10 should be 18")
end)

test("expToNext formula", function()
	assertEq(PlayerStats.expToNext(1), 100, "EXP for level 1 -> 2 should be 100")
	assertEq(PlayerStats.expToNext(5), 260, "EXP for level 5 -> 6 should be 260")
end)

test("Cooldown calculation with attack speed", function()
	-- 0% attack speed -> full cooldown
	assertEq(PlayerStats.getCooldown(1.0, 0), 1.0, "Cooldown with 0% attack speed")

	-- 100% attack speed -> 50% cooldown (half)
	assertEq(PlayerStats.getCooldown(1.0, 100), 0.5, "Cooldown with 100% attack speed")

	-- 300% attack speed -> 25% cooldown (quarter)
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

print(string.format("\n📊 Results: %d passed, %d failed\n", passed, failed))

if failed > 0 then
	error(string.format("Test suite failed with %d errors", failed))
end
