--[[
   Unit Test for ItemData.luau
   Run via: lune run tests/test_item_data.luau
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

-- Load RuneData, TabletData and SkillData
local runeDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/RuneData.luau"))
local RuneData = luau.load(runeDataBytecode, { environment = mockEnv })()

local tabletDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/TabletData.luau"))
local TabletData = luau.load(tabletDataBytecode, { environment = mockEnv })()

local skillDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/SkillData.luau"))
local SkillData = luau.load(skillDataBytecode, { environment = mockEnv })()

local spiritDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/SpiritData.luau"))
local SpiritData = luau.load(spiritDataBytecode, { environment = mockEnv })()

-- Setup mock script environment for ItemData
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

print("🧪 Running Unit Tests: ItemData")

test("Slot compatibility checks", function()
	assertEq(ItemData.isSlotCompatible("MainHand", "MainHand"), true, "MainHand fits MainHand")
	assertEq(ItemData.isSlotCompatible("Weapon", "MainHand"), true, "Weapon alias fits MainHand")
	assertEq(ItemData.isSlotCompatible("Cloth", "Cloth"), true, "Cloth fits Cloth")
	assertEq(ItemData.isSlotCompatible("Armor", "Cloth"), true, "Armor alias fits Cloth")
	assertEq(ItemData.isSlotCompatible("Ring", "Ring1"), true, "Ring fits Ring1")
	assertEq(ItemData.isSlotCompatible("Ring", "Ring2"), true, "Ring fits Ring2")
	assertEq(ItemData.isSlotCompatible("Special", "Special1"), true, "Special fits Special1")
	assertEq(ItemData.isSlotCompatible("Cloth", "MainHand"), false, "Cloth does not fit MainHand")
	assertEq(ItemData.isSlotCompatible("MainHand", "Ring1"), false, "MainHand does not fit Ring1")
end)

test("Equipment target slot selection", function()
	local emptyEquip = {}
	assertEq(ItemData.getTargetSlot("Weapon", emptyEquip), "MainHand", "Empty equip targets MainHand")
	assertEq(ItemData.getTargetSlot("Cloth", emptyEquip), "Cloth", "Empty equip targets Cloth")
	assertEq(ItemData.getTargetSlot("Ring", emptyEquip), "Ring1", "Empty equip ring targets Ring1")

	local equippedRing1 = { Ring1 = { Id = "r1", Base = "TestRing", Rarity = "Normal", Affixes = {} } }
	assertEq(ItemData.getTargetSlot("Ring", equippedRing1), "Ring2", "Filled Ring1 targets Ring2")
end)

test("allowsOffHand verification", function()
	assertEq(ItemData.allowsOffHand(nil), true, "Empty hands allow OffHand")

	local sword: any = { Id = "s1", Base = "IronSword", Rarity = "Normal", Affixes = {} }
	assertEq(ItemData.allowsOffHand(sword), false, "IronSword 2H locks OffHand")

	local vest: any = { Id = "v1", Base = "LeatherVest", Rarity = "Normal", Affixes = {} }
	assertEq(ItemData.allowsOffHand(vest), true, "Non-weapon does not lock OffHand")
end)

test("Item stats calculation with implicit and affixes", function()
	local fakeItem: any = {
		Id = "i1",
		Base = "IronSword", -- Implicit: FlatDamage: 5
		Rarity = "Rare",
		Affixes = {
			{ Id = "FlatDamage", Value = 10 },
			{ Id = "AttackSpeed", Value = 15 },
			{ Id = "FireDamage", Value = 7 },
		},
	}
	local stats = ItemData.getStats(fakeItem)
	assertEq(stats.FlatDamage, 15, "5 implicit + 10 affix = 15 flat damage")
	assertEq(stats.AttackSpeed, 15, "15 attack speed")
	assertEq(stats.FireDamage, 7, "7 fire damage")
end)

test("Name formatting with tier support", function()
	local gear: any = { Id = "g1", Base = "LeatherVest", Rarity = "Normal", Affixes = {} }
	assertEq(ItemData.getName(gear), "Leather Vest", "Standard item name")

	local tablet: any = { Id = "t1", Base = "StoneTablet", Rarity = "Magic", Tier = 4, Affixes = {} }
	assertEq(ItemData.getName(tablet), "Stone Tablet (Tier 4)", "Tablet name includes tier")
end)

test("Every skill has a Skill Stone base", function()
	for skillId, skill in pairs(SkillData) do
		local baseId = ItemData.getSkillStoneBase(skillId)
		local base = ItemData.Bases[baseId]
		assertEq(base ~= nil, true, "Skill Stone base exists for " .. skillId)
		assertEq(base.Slot, "Skill", "Skill Stones go on the skill bar, not an equipment slot")
		local stone: any = { Id = "k1", Base = baseId, Rarity = "Skill", Affixes = {} }
		assertEq(ItemData.getSkillId(stone), skillId, "getSkillId reads the skill back")
		assertEq(ItemData.getName(stone), skill.Name, "Skill Stone is named after its skill")
		assertEq(ItemData.getRuneId(stone), nil, "A Skill Stone is not a rune")
	end
	local sword: any = { Id = "s1", Base = "IronSword", Rarity = "Normal", Affixes = {} }
	assertEq(ItemData.getSkillId(sword), nil, "Gear is not a Skill Stone")
	assertEq(table.find(ItemData.RarityOrder, "Skill"), nil, "Gear never rolls the Skill rarity")
end)

test("Every Stone Spirit has an item base, and only non-gear picks itself up", function()
	for spiritId, spirit in pairs(SpiritData.Spirits) do
		local item: any = { Id = "p1", Base = SpiritData.getBaseId(spiritId), Rarity = "Spirit", Affixes = {} }
		assertEq(ItemData.Bases[item.Base].Slot, "Spirit", spiritId .. " goes in a spirit slot")
		assertEq(ItemData.getSpiritId(item), spiritId, "getSpiritId reads the spirit back")
		assertEq(ItemData.getName(item), spirit.Name, "Named after the spirit")
		for stat in pairs(spirit.Stats) do
			assertEq(ItemData.StatText[stat] ~= nil, true, spiritId .. " stat " .. stat .. " has tooltip text")
		end
	end
	local sword: any = { Id = "s1", Base = "IronSword", Rarity = "Normal", Affixes = {} }
	local tablet: any = { Id = "t1", Base = "StoneTablet", Rarity = "Normal", Tier = 1, Affixes = {} }
	local skill: any = { Id = "k1", Base = ItemData.getSkillStoneBase("Arc"), Rarity = "Skill", Affixes = {} }
	assertEq(ItemData.isAutoPickup(sword), false, "Gear needs the prompt")
	assertEq(ItemData.isAutoPickup(tablet), true, "Tablets pick themselves up")
	assertEq(ItemData.isAutoPickup(skill), true, "Skill Stones pick themselves up")
	assertEq(table.find(ItemData.RarityOrder, "Spirit"), nil, "Gear never rolls the Spirit rarity")
end)

test("formatStat output patterns", function()
	assertEq(ItemData.formatStat("FlatDamage", 8), "+8 Damage", "FlatDamage text pattern")
	assertEq(ItemData.formatStat("MaxHealth", 50), "+50 Max Health", "MaxHealth text pattern")
	assertEq(ItemData.formatStat("AttackSpeed", 12), "+12% Attack Speed", "AttackSpeed text pattern")
end)

print(string.format("\n📊 Results: %d passed, %d failed\n", passed, failed))

if failed > 0 then
	error(string.format("Test suite failed with %d errors", failed))
end
