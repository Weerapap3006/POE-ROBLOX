--[[
   Unit Test for HeroData.luau
   Run via: lune run tests/test_hero_data.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local mockEnv: { [string]: any } = {}
for k, v in pairs(getfenv()) do
	mockEnv[k] = v
end
mockEnv.Color3 = {
	fromRGB = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
}
mockEnv.Vector2 = {
	new = function(x, y)
		return { X = x, Y = y }
	end,
}

local heroDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/HeroData.luau"))
local HeroData = luau.load(heroDataBytecode, { environment = mockEnv })()

local passiveDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/PassiveData.luau"))
local PassiveData = luau.load(passiveDataBytecode, { environment = mockEnv })()

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

print("🧪 Running Unit Tests: HeroData")

test("Every class has a hero mechanic with two paths", function()
	for _, classId in ipairs(PassiveData.ClassOrder) do
		local hero = HeroData.get(classId)
		assertEq(hero ~= nil, true, classId .. " has a hero entry")
		assertEq(#hero.VariantOrder, 2, classId .. " has exactly two paths (the window shows two cards)")
		local count = 0
		for variantId in pairs(hero.Variants) do
			count += 1
			assertEq(table.find(hero.VariantOrder, variantId) ~= nil, true, variantId .. " is in VariantOrder")
		end
		assertEq(count, 2, classId .. " Variants matches VariantOrder")
	end
	assertEq(HeroData.get(nil), nil, "No class = no hero")
end)

test("Paths unlock at VARIANT_LEVEL and only for their own class", function()
	local level = HeroData.VARIANT_LEVEL
	assertEq(HeroData.canChoose("Warrior", "Berserker", level), true, "Warrior can take Berserker at the unlock level")
	assertEq(HeroData.canChoose("Warrior", "Berserker", level - 1), false, "Locked one level before")
	assertEq(HeroData.canChoose("Warrior", "Deadeye", level), false, "Another class's path is refused")
	assertEq(HeroData.canChoose(nil, "Berserker", level), false, "No class = no path")
	assertEq(HeroData.canChoose("Mystic", "Nonsense", level), false, "Unknown path is refused")
end)

test("Mechanic numbers are sane", function()
	assertEq(HeroData.FURY_MAX > 0 and HeroData.FURY_PER_HIT > 0, true, "Fury builds up to a max")
	assertEq(HeroData.FURY_RELEASE_MULTIPLIER > 1, true, "Full Fury hits harder")
	assertEq(
		HeroData.EARTHBREAKER_MULTIPLIER >= HeroData.FURY_RELEASE_MULTIPLIER,
		true,
		"Earthbreaker is the bigger release"
	)
	assertEq(HeroData.MOMENTUM_MAX > 0 and HeroData.MOMENTUM_STUDS_PER_STACK > 0, true, "Momentum stacks from walking")
	assertEq(
		HeroData.ORB_MAX > 0 and HeroData.ORB_MANA > 0 and HeroData.ORB_DURATION > 0,
		true,
		"Orbs come from mana and expire"
	)
	assertEq(HeroData.STORMCALLER_INTERVAL < HeroData.ORB_INTERVAL, true, "Stormcaller orbs shoot faster")
end)

print(string.format("\n📊 Results: %d passed, %d failed\n", passed, failed))

if failed > 0 then
	error(string.format("Test suite failed with %d errors", failed))
end
