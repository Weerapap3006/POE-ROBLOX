--[[
   Unit Test for EnemyData.luau
   Run via: lune run tests/test_enemy_data.luau
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

local enemyDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/EnemyData.luau"))
local EnemyData = luau.load(enemyDataBytecode, { environment = mockEnv })()

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

local function isPositive(value: any): boolean
	return type(value) == "number" and value > 0
end

print("🧪 Running Unit Tests: EnemyData")

test("Every attack kind has the fields EnemyService needs", function()
	local kinds = { Melee = true, Slam = true, Projectile = true, Explode = true }
	for typeId, enemy in pairs(EnemyData) do
		local attack = enemy.Attack
		assertEq(kinds[attack.Kind], true, typeId .. " has a known attack kind")
		assertEq(isPositive(attack.Range) and isPositive(attack.Windup), true, typeId .. " has Range and Windup")
		assertEq(attack.MinDamage <= attack.MaxDamage, true, typeId .. " MinDamage <= MaxDamage")
		if attack.Kind == "Slam" or attack.Kind == "Explode" then
			assertEq(isPositive(attack.Radius), true, typeId .. " circle attacks need Radius")
		elseif attack.Kind == "Projectile" then
			assertEq(
				isPositive(attack.Speed) and isPositive(attack.Width),
				true,
				typeId .. " shots need Speed and Width"
			)
		end
	end
end)

test("Packs only contain monsters that exist (and no bosses)", function()
	for typeId, enemy in pairs(EnemyData) do
		local pack = enemy.Pack
		if pack then
			assertEq(pack.Size >= 1, true, typeId .. " pack has at least one member")
			local total = 0
			for memberId, weight in pairs(pack.Weights) do
				assertEq(EnemyData[memberId] ~= nil, true, typeId .. " pack member " .. memberId .. " exists")
				assertEq(EnemyData[memberId].IsBoss, false, typeId .. " pack never rolls a boss")
				total += weight
			end
			assertEq(total > 0, true, typeId .. " pack weights add up to more than 0")
		end
	end
end)

test("Drop tables have every expected count", function()
	for typeId, enemy in pairs(EnemyData) do
		local drops = enemy.Drops
		for _, key in ipairs({ "RuneChance", "SkillChance", "SpiritChance", "StoneChance", "TabletChance" }) do
			assertEq(type(drops[key]) == "number" and drops[key] >= 0, true, typeId .. " Drops." .. key)
		end
	end
	assertEq(EnemyData.Brute.Drops.SpiritChance > 0, true, "The boss can drop Stone Spirits")
end)

print(string.format("\n📊 Results: %d passed, %d failed\n", passed, failed))

if failed > 0 then
	error(string.format("Test suite failed with %d errors", failed))
end
