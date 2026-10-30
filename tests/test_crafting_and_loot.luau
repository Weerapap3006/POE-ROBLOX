--[[
   Unit Test for Crafting.luau, StoneData.luau & Loot.luau
   Run via: lune run tests/test_crafting_and_loot.luau
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

-- Mock Random.new()
mockEnv.Random = {
	new = function()
		return {
			NextNumber = function(_self, min, max)
				if min and max then
					return min + math.random() * (max - min)
				end
				return math.random()
			end,
			NextInteger = function(_self, min, max)
				return math.random(min, max)
			end,
		}
	end,
}

-- Load RuneData and TabletData
local runeDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/RuneData.luau"))
local RuneData = luau.load(runeDataBytecode, { environment = mockEnv })()

local tabletDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/TabletData.luau"))
local TabletData = luau.load(tabletDataBytecode, { environment = mockEnv })()

-- Setup script mock for ItemData
local itemDataScript = {
	Parent = {
		WaitForChild = function(_self, name)
			if name == "RuneData" then
				return "RuneData"
			elseif name == "TabletData" then
				return "TabletData"
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
	end
	return require(target)
end

local itemDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/ItemData.luau"))
local ItemData = luau.load(itemDataBytecode, { environment = itemDataEnv })()

-- Load StoneData
local stoneDataScript = {
	Parent = {
		WaitForChild = function(_self, name)
			if name == "ItemData" then
				return "ItemData"
			end
			error("Child not found: " .. tostring(name))
		end,
	},
}
local stoneDataEnv: { [string]: any } = {}
for k, v in pairs(mockEnv) do
	stoneDataEnv[k] = v
end
stoneDataEnv.script = stoneDataScript
stoneDataEnv.require = function(target)
	if target == "ItemData" then
		return ItemData
	end
	return require(target)
end

local stoneDataBytecode = luau.compile(fs.readFile("src/ReplicatedStorage/Modules/StoneData.luau"))
local StoneData = luau.load(stoneDataBytecode, { environment = stoneDataEnv })()

-- Load Crafting
local craftingEnv: { [string]: any } = {}
for k, v in pairs(mockEnv) do
	craftingEnv[k] = v
end
craftingEnv.game = {
	GetService = function(_self, name)
		if name == "ReplicatedStorage" then
			return {
				WaitForChild = function(_self2, _folderName)
					return {
						WaitForChild = function(_self3, moduleName)
							if moduleName == "ItemData" then
								return "ItemData"
							elseif moduleName == "StoneData" then
								return "StoneData"
							end
							error("Module not found: " .. tostring(moduleName))
						end,
					}
				end,
			}
		end
		error("Service not found: " .. tostring(name))
	end,
}
craftingEnv.require = function(target)
	if target == "ItemData" then
		return ItemData
	elseif target == "StoneData" then
		return StoneData
	end
	return require(target)
end

local craftingBytecode = luau.compile(fs.readFile("src/ServerStorage/Modules/Crafting.luau"))
local Crafting = luau.load(craftingBytecode, { environment = craftingEnv })()

-- Load Loot
local guidCounter = 0
local lootEnv: { [string]: any } = {}
for k, v in pairs(mockEnv) do
	lootEnv[k] = v
end
lootEnv.game = {
	GetService = function(_self, name)
		if name == "Debris" then
			return { AddItem = function() end }
		elseif name == "HttpService" then
			return {
				GenerateGUID = function()
					guidCounter += 1
					return "mock-guid-" .. tostring(guidCounter)
				end,
			}
		elseif name == "ReplicatedStorage" then
			return {
				WaitForChild = function(_self2, _folderName)
					return {
						WaitForChild = function(_self3, moduleName)
							return moduleName
						end,
					}
				end,
			}
		end
		error("Service not found: " .. tostring(name))
	end,
}
lootEnv.script = {
	Parent = {
		WaitForChild = function(_self, moduleName)
			return moduleName
		end,
	},
}
lootEnv.require = function(target)
	if target == "ItemData" then
		return ItemData
	elseif target == "RuneData" then
		return RuneData
	elseif target == "StoneData" then
		return StoneData
	elseif target == "TabletData" then
		return TabletData
	elseif target == "Crafting" then
		return Crafting
	elseif target == "PlayerData" then
		return {}
	end
	return require(target)
end

local lootBytecode = luau.compile(fs.readFile("src/ServerStorage/Modules/Loot.luau"))
local Loot = luau.load(lootBytecode, { environment = lootEnv })()

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

print("🧪 Running Unit Tests: Crafting & Loot")

test("Ascension Stone: Normal -> Magic (1 affix)", function()
	local item: any = { Id = "test_1", Base = "IronSword", Rarity = "Normal", Affixes = {} }
	local err = Crafting.useStone("Ascension", item)
	assertEq(err, nil, "Ascension stone should succeed on Normal")
	assertEq(item.Rarity, "Magic", "Item rarity upgraded to Magic")
	assertEq(#item.Affixes, 1, "Magic item should have exactly 1 affix after ascension")
end)

test("Carving Stone: Add affix to Magic item with room", function()
	local item: any = {
		Id = "test_2",
		Base = "IronSword",
		Rarity = "Magic",
		Affixes = { { Id = "FlatDamage", Value = 5 } },
	}
	assertEq(StoneData.hasAffixRoom(item), true, "Magic item with 1 affix has room")

	local err = Crafting.useStone("Carving", item)
	assertEq(err, nil, "Carving stone should succeed")
	assertEq(#item.Affixes, 2, "Magic item should now have 2 affixes")
end)

test("Carving Stone on full item fails with reason", function()
	local item: any = {
		Id = "test_3",
		Base = "IronSword",
		Rarity = "Magic",
		Affixes = {
			{ Id = "FlatDamage", Value = 5 },
			{ Id = "AttackSpeed", Value = 10 },
		},
	}
	assertEq(StoneData.hasAffixRoom(item), false, "Magic item with 2 affixes has no room")
	local err = Crafting.useStone("Carving", item)
	assertEq(typeof(err), "string", "Carving stone on full item returns error string")
end)

test("Ascension Stone: Magic -> Rare (up to 3 affixes)", function()
	local item: any = {
		Id = "test_4",
		Base = "IronSword",
		Rarity = "Magic",
		Affixes = { { Id = "FlatDamage", Value = 5 } },
	}
	local err = Crafting.useStone("Ascension", item)
	assertEq(err, nil, "Ascension stone succeeds on Magic item")
	assertEq(item.Rarity, "Rare", "Rarity is Rare")
	assertEq(#item.Affixes, 3, "Rare item gets filled up to 3 affixes")
end)

test("Shifting Stone: Rerolls all affixes", function()
	local item: any = {
		Id = "test_5",
		Base = "IronSword",
		Rarity = "Rare",
		Affixes = {
			{ Id = "FlatDamage", Value = 3 },
			{ Id = "MaxHealth", Value = 20 },
			{ Id = "AttackSpeed", Value = 5 },
		},
	}
	local err = Crafting.useStone("Shifting", item)
	assertEq(err, nil, "Shifting stone succeeds on Rare")
	assertEq(item.Rarity, "Rare", "Rarity remains Rare")
	assertEq(#item.Affixes, 3, "Rare item retains 3 rolled affixes")
end)

test("Cannot use Carving on Normal item", function()
	local item: any = { Id = "test_6", Base = "IronSword", Rarity = "Normal", Affixes = {} }
	local err = Crafting.useStone("Carving", item)
	assertEq(typeof(err), "string", "Cannot carve Normal item")
end)

test("Loot.rollItem generates gear with valid base and rarity", function()
	local item = Loot.rollItem("Rare")
	assertEq(item.Rarity, "Rare", "Rolled item should be Rare")
	assertEq(#item.Affixes, 3, "Rare rolled item should have 3 affixes")
	local base = ItemData.Bases[item.Base]
	assertEq(base ~= nil, true, "Base must exist in ItemData.Bases")
	assertEq(base.Slot ~= "Rune" and base.Slot ~= "Tablet", true, "Gear roll never rolls Runes or Tablets")
end)

test("Loot.rollRune generates valid Stone Rune", function()
	local runeItem = Loot.rollRune()
	assertEq(runeItem.Rarity, "Rune", "Rune item rarity should be Rune")
	assertEq(#runeItem.Affixes, 0, "Runes have 0 affixes")
	local runeId = ItemData.getRuneId(runeItem)
	assertEq(runeId ~= nil, true, "Item should resolve to a valid runeId")
end)

test("Loot.rollTablet generates StoneTablet with clamped tier", function()
	local tablet = Loot.rollTablet(15, "Magic") -- Max tier is 10
	assertEq(tablet.Base, "StoneTablet", "Base should be StoneTablet")
	assertEq(tablet.Rarity, "Magic", "Rarity should be Magic")
	assertEq(tablet.Tier, 10, "Tier 15 should be clamped to MAX_TIER (10)")
	assertEq(#tablet.Affixes >= 1 and #tablet.Affixes <= 2, true, "Magic tablet has 1-2 mods")
end)

print(string.format("\n📊 Results: %d passed, %d failed\n", passed, failed))

if failed > 0 then
	error(string.format("Test suite failed with %d errors", failed))
end
