--[[
   Unit Test for SkillData.luau
   Run via: lune run tests/test_skill_data.luau
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
mockEnv.Vector3 = {
	new = function(x, y, z)
		return { X = x, Y = y, Z = z }
	end,
}

local skillDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/SkillData.luau"))
local SkillData = luau.load(skillDataBytecode, { environment = mockEnv })()

local elementsBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/Elements.luau"))
local Elements = luau.load(elementsBytecode, { environment = mockEnv })()

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

print("🧪 Running Unit Tests: SkillData")

test("Every skill has its basic numbers", function()
	for skillId, skill in pairs(SkillData) do
		assertEq(type(skill.Name), "string", skillId .. " Name")
		assertEq(type(skill.Description), "string", skillId .. " Description")
		assertEq(isPositive(skill.Cooldown), true, skillId .. " Cooldown > 0")
		assertEq(type(skill.ManaCost) == "number" and skill.ManaCost >= 0, true, skillId .. " ManaCost >= 0")
		assertEq(skill.Sockets >= 1 and skill.Sockets <= 3, true, skillId .. " has 1-3 rune sockets")
		assertEq(skill.MinDamage <= skill.MaxDamage, true, skillId .. " MinDamage <= MaxDamage")
		assertEq(skill.CritChance >= 0 and skill.CritChance <= 1, true, skillId .. " CritChance is 0-1")
	end
end)

test("Kind, Element and Animation are known values", function()
	local kinds = { Melee = true, Ranged = true, Spell = true }
	local animations = { Slash = true, Spin = true, Slam = true, Cast = true }
	for skillId, skill in pairs(SkillData) do
		assertEq(kinds[skill.Kind], true, skillId .. " Kind")
		assertEq(animations[skill.Animation], true, skillId .. " Animation")
		local element = skill.Element == "Physical" or table.find(Elements.Types, skill.Element) ~= nil
		assertEq(element, true, skillId .. " Element is Physical or an Elements type")
	end
end)

test("Each shape has the fields CombatServer needs", function()
	for skillId, skill in pairs(SkillData) do
		if skill.Shape == "Box" then
			assertEq(skill.HitboxSize ~= nil, true, skillId .. " Box needs HitboxSize")
		elseif skill.Shape == "Radius" then
			assertEq(isPositive(skill.Radius), true, skillId .. " Radius needs Radius")
		elseif skill.Shape == "Projectile" then
			assertEq(isPositive(skill.Range), true, skillId .. " Projectile needs Range")
			assertEq(isPositive(skill.Speed), true, skillId .. " Projectile needs Speed")
			assertEq(isPositive(skill.Width), true, skillId .. " Projectile needs Width")
		elseif skill.Shape == "Chain" then
			assertEq(isPositive(skill.Range), true, skillId .. " Chain needs Range")
			assertEq(isPositive(skill.Chains), true, skillId .. " Chain needs Chains")
			assertEq(isPositive(skill.ChainRange), true, skillId .. " Chain needs ChainRange")
		else
			error(skillId .. " has an unknown Shape: " .. tostring(skill.Shape))
		end
	end
end)

test("There are free basic attacks to fall back on", function()
	assertEq(SkillData.BasicSlash.ManaCost, 0, "Slash costs no mana")
	assertEq(SkillData.StoneShot.ManaCost, 0, "Stone Shot costs no mana")
end)

print(string.format("\n📊 Results: %d passed, %d failed\n", passed, failed))

if failed > 0 then
	error(string.format("Test suite failed with %d errors", failed))
end
