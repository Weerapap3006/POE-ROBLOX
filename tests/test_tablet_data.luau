--[[
   Unit Test for TabletData.luau
   Run via: lune run tests/test_tablet_data.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local mockEnv: { [string]: any } = {}
for k, v in pairs(getfenv()) do
	mockEnv[k] = v
end

local tabletDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/TabletData.luau"))
local TabletData = luau.load(tabletDataBytecode, { environment = mockEnv })()

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

local function assertApproxEq(actual: number, expected: number, epsilon: number?, message: string?)
	local eps = epsilon or 1e-5
	if math.abs(actual - expected) > eps then
		error(string.format("Expected approx %s, got %s. %s", tostring(expected), tostring(actual), message or ""))
	end
end

print("🧪 Running Unit Tests: TabletData")

test("Plain dungeon effects (nil tablet)", function()
	local effects = TabletData.getEffects(nil)
	assertEq(effects.Tier, 0, "Tier should be 0")
	assertApproxEq(effects.Health, 1, 1e-5, "Health multiplier should be 1.0")
	assertApproxEq(effects.Damage, 1, 1e-5, "Damage multiplier should be 1.0")
	assertApproxEq(effects.Speed, 1, 1e-5, "Speed multiplier should be 1.0")
	assertApproxEq(effects.Quantity, 0, 1e-5, "Extra loot quantity should be 0")
end)

test("Tier 3 tablet baseline scaling without mods", function()
	local fakeTablet = { Tier = 3, Affixes = {} }
	local effects = TabletData.getEffects(fakeTablet)
	assertEq(effects.Tier, 3, "Tier should be 3")
	assertApproxEq(effects.Health, 1.45, 1e-5, "Health should be 1.45")
	assertApproxEq(effects.Damage, 1.30, 1e-5, "Damage should be 1.30")
	assertApproxEq(effects.Quantity, 0.15, 1e-5, "Quantity should be 0.15 (+15%)")
end)

test("Tablet mod application: Speed and FrostAttacks", function()
	local fakeTablet = {
		Tier = 1,
		Affixes = {
			{ Id = "MonsterSpeed", Value = 20 },
			{ Id = "FrostAttacks", Value = 0 },
		},
	}
	local effects = TabletData.getEffects(fakeTablet)
	assertApproxEq(effects.Speed, 1.2, 1e-5, "Monster speed should be 1.2 (+20%)")
	assertEq(#effects.Elements, 1, "Should have 1 element forced")
	assertEq(effects.Elements[1], "Cold", "Element should be Cold")
	assertApproxEq(effects.Quantity, 0.40, 1e-5, "Total quantity boost should be 40%")
end)

print(string.format("\n📊 Results: %d passed, %d failed\n", passed, failed))

if failed > 0 then
	error(string.format("Test suite failed with %d errors", failed))
end
