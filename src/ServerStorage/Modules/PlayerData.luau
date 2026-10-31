-- ==========================================
-- PLAYER DATA (Level, EXP, Inventory, Equipment + DataStore Save/Load)
-- Path: ServerStorage.Modules.PlayerData
-- ==========================================
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ItemData = require(modulesFolder:WaitForChild("ItemData"))
local PlayerStats = require(modulesFolder:WaitForChild("PlayerStats"))
local SkillData = require(modulesFolder:WaitForChild("SkillData"))
local RuneData = require(modulesFolder:WaitForChild("RuneData"))
local StoneData = require(modulesFolder:WaitForChild("StoneData"))
local TabletData = require(modulesFolder:WaitForChild("TabletData"))
local PassiveData = require(modulesFolder:WaitForChild("PassiveData"))
local HeroData = require(modulesFolder:WaitForChild("HeroData"))
local SpiritData = require(modulesFolder:WaitForChild("SpiritData"))

local Crafting = require(script.Parent:WaitForChild("Crafting"))
local DungeonRun = require(script.Parent:WaitForChild("DungeonRun"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local inventoryRemote = remotesFolder:WaitForChild("InventoryRemote") :: RemoteEvent
local notifyRemote = remotesFolder:WaitForChild("NotifyRemote") :: RemoteEvent

-- ==========================================
-- CONFIGURATION
-- ==========================================
local DATASTORE_NAME = "PlayerData_v1" -- Renaming this starts every player from zero
local INVENTORY_CAPACITY = 20
local AUTOSAVE_INTERVAL = 120 -- Seconds
local RETRY_COUNT = 3
local STUDIO_ACCESS_HINT = "Studio: Game Settings -> Security -> Enable Studio Access to API Services (place must be published)"

local WARNING_COLOR = Color3.fromRGB(255, 120, 90)
local INFO_COLOR = Color3.fromRGB(150, 200, 255)
local LEVEL_UP_COLOR = Color3.fromRGB(240, 190, 60)

export type Profile = {
	Level: number,
	Exp: number,
	Inventory: { ItemData.Item },
	Equipped: { [string]: ItemData.Item },
	-- Skill bar: a SkillData id per slot (PlayerStats.SKILL_BAR_SLOTS long, "" = empty slot, no skill twice).
	-- A Skill Stone put on the bar becomes just its skill id; taking it off makes a new Skill Stone item
	SkillBar: { string },
	SkillRunes: { [string]: { ItemData.Item } }, -- Stone runes socketed in each skill (in socket order, no gaps)
	-- Stone Spirits: a SpiritData id per slot (SpiritData.SLOTS long, "" = empty, no spirit twice), like the skill bar
	Spirits: { string },
	Stones: { [string]: number }, -- Crafting stones owned, per StoneData id
	Class: string?, -- PassiveData.Classes id (nil = not chosen yet, the tree window asks)
	HeroVariant: string?, -- Hero path of the class (HeroData Variants, from HeroData.VARIANT_LEVEL; nil = none yet)
	Passives: { string }, -- Allocated passive tree nodes (not counting the class's free Start node)
	Stats: PlayerStats.Stats,
	-- False when loading failed: saving would overwrite the player's real data with this empty profile
	CanSave: boolean,
}

local PlayerData = {}

local profiles: { [Player]: Profile } = {}
local pendingSaves = 0
local heroChangedListeners: { (Player) -> () } = {} -- HeroService resets the mechanic when class / path change

-- Fails in a place that was never published (e.g. a local game.rbxl copy): the game still runs, nothing is saved
local dataStore: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		dataStore = result
	else
		warn("[PlayerData] DataStore unavailable, progress will not be saved:", result)
	end
end

-- ==========================================
-- 1. LOAD / SAVE (DataStore with retries)
-- ==========================================
local function getKey(player: Player): string
	return "Player_" .. player.UserId
end

-- Studio errors that retrying can't fix: the place isn't published or API access is turned off
local function isStudioAccessError(message: string): boolean
	if not RunService:IsStudio() then
		return false
	end
	local lower = string.lower(message)
	return string.find(lower, "studio", 1, true) ~= nil or string.find(lower, "publish", 1, true) ~= nil
end

-- Status: "Loaded", "Failed" (DataStore error) or "NoAccess" (Studio without DataStore access)
local function loadData(player: Player): (string, any)
	local store = dataStore
	if not store then
		return if RunService:IsStudio() then "NoAccess" else "Failed", nil
	end
	for attempt = 1, RETRY_COUNT do
		local ok, result = pcall(function()
			return store:GetAsync(getKey(player))
		end)
		if ok then
			return "Loaded", result
		end
		if isStudioAccessError(tostring(result)) then
			warn("[PlayerData] No DataStore access, progress will not be saved.", STUDIO_ACCESS_HINT)
			return "NoAccess", nil
		end
		warn(("[PlayerData] Load failed for %s (attempt %d): %s"):format(player.Name, attempt, tostring(result)))
		task.wait(attempt)
	end
	return "Failed", nil
end

-- Saved data may come from an older version of the game: drop anything ItemData no longer knows
local function sanitizeItem(raw: any): ItemData.Item?
	if type(raw) ~= "table" or type(raw.Id) ~= "string" then
		return nil
	end
	if not ItemData.Bases[raw.Base] or not ItemData.Rarities[raw.Rarity] then
		return nil
	end
	local pool = ItemData.getAffixPool(raw) -- Tablet mods or gear affixes
	local affixes = {}
	if type(raw.Affixes) == "table" then
		for _, affix in ipairs(raw.Affixes) do
			if type(affix) == "table" and pool[affix.Id] and type(affix.Value) == "number" then
				table.insert(affixes, { Id = affix.Id, Value = affix.Value })
			end
		end
	end
	local item: ItemData.Item = { Id = raw.Id, Base = raw.Base, Rarity = raw.Rarity, Affixes = affixes }
	if ItemData.isTablet(item) then
		item.Tier = if type(raw.Tier) == "number" then math.clamp(math.floor(raw.Tier), 1, TabletData.MAX_TIER) else 1
	end
	return item
end

-- Crafting stone counts: only stones that still exist, whole numbers, never negative
local function sanitizeStones(raw: any): { [string]: number }
	local stones = {}
	for stoneId in pairs(StoneData.Stones) do
		local count = if type(raw) == "table" then raw[stoneId] else nil
		stones[stoneId] = if type(count) == "number" then math.clamp(math.floor(count), 0, 9999) else 0
	end
	return stones
end

-- Keeps only runes that still exist, fit the skill, aren't doubled and fit in its sockets
local function sanitizeSkillRunes(raw: any): { [string]: { ItemData.Item } }
	local result = {}
	for skillId, skill in pairs(SkillData) do
		local socketed = {}
		local seen = {}
		local list = if type(raw) == "table" then raw[skillId] else nil
		if type(list) == "table" then
			for _, rawItem in ipairs(list) do
				local item = sanitizeItem(rawItem)
				local runeId = if item then ItemData.getRuneId(item) else nil
				if item and runeId and not seen[runeId] and RuneData.fits(runeId, skill) and #socketed < skill.Sockets then
					seen[runeId] = true
					table.insert(socketed, item)
				end
			end
		end
		result[skillId] = socketed
	end
	return result
end

-- Skill ids that still exist, each once. raw = nil (new player or a save from before the skill bar):
-- the starting skills
local function sanitizeSkillBar(raw: any): { string }
	local bar = {}
	local seen = {}
	for slot = 1, PlayerStats.SKILL_BAR_SLOTS do
		local skillId = if type(raw) == "table" then raw[slot] else PlayerStats.STARTING_SKILLS[slot]
		if type(skillId) == "string" and SkillData[skillId] and not seen[skillId] then
			seen[skillId] = true
			bar[slot] = skillId
		else
			bar[slot] = ""
		end
	end
	return bar
end

local function makeSkillStone(skillId: string): ItemData.Item
	return {
		Id = HttpService:GenerateGUID(false),
		Base = ItemData.getSkillStoneBase(skillId),
		Rarity = "Skill",
		Affixes = {},
	}
end

-- Spirit ids that still exist, each once ("" = empty slot). Nobody starts with a spirit
local function sanitizeSpirits(raw: any): { string }
	local slots = {}
	local seen = {}
	for slot = 1, SpiritData.SLOTS do
		local spiritId = if type(raw) == "table" then raw[slot] else nil
		if type(spiritId) == "string" and SpiritData.Spirits[spiritId] and not seen[spiritId] then
			seen[spiritId] = true
			slots[slot] = spiritId
		else
			slots[slot] = ""
		end
	end
	return slots
end

local function makeSpiritStone(spiritId: string): ItemData.Item
	return {
		Id = HttpService:GenerateGUID(false),
		Base = SpiritData.getBaseId(spiritId),
		Rarity = "Spirit",
		Affixes = {},
	}
end

local function buildProfile(data: any, canSave: boolean): Profile
	local profile: Profile = {
		Level = 1,
		Exp = 0,
		Inventory = {},
		Equipped = {},
		SkillBar = sanitizeSkillBar(nil),
		SkillRunes = sanitizeSkillRunes(nil),
		Spirits = sanitizeSpirits(nil),
		Stones = sanitizeStones(nil),
		Class = nil,
		Passives = {},
		Stats = PlayerStats.compute(1, {}),
		CanSave = canSave,
	}
	if type(data) ~= "table" then
		return profile -- New player (or load failed)
	end
	profile.SkillBar = sanitizeSkillBar(data.SkillBar)
	profile.Spirits = sanitizeSpirits(data.Spirits)
	profile.SkillRunes = sanitizeSkillRunes(data.SkillRunes)
	profile.Stones = sanitizeStones(data.Stones)

	if type(data.Level) == "number" then
		profile.Level = math.clamp(math.floor(data.Level), 1, PlayerStats.MAX_LEVEL)
	end
	if type(data.Exp) == "number" then
		profile.Exp = math.max(0, math.floor(data.Exp))
	end
	-- Passive tree: needs the level above (it decides how many points there are)
	if type(data.Class) == "string" and PassiveData.Classes[data.Class] then
		profile.Class = data.Class
		profile.Passives = PassiveData.sanitize(data.Class, data.Passives, PassiveData.getPoints(profile.Level))
		if type(data.HeroVariant) == "string" and HeroData.canChoose(data.Class, data.HeroVariant, profile.Level) then
			profile.HeroVariant = data.HeroVariant
		end
	end
	if type(data.Inventory) == "table" then
		for _, raw in ipairs(data.Inventory) do
			local item = sanitizeItem(raw)
			if item and #profile.Inventory < INVENTORY_CAPACITY then
				table.insert(profile.Inventory, item)
			end
		end
	end
	if type(data.Equipped) == "table" then
		-- Migrate legacy slot keys ("Weapon" -> "MainHand", "Armor" -> "Cloth")
		if data.Equipped.Weapon and not data.Equipped.MainHand then
			data.Equipped.MainHand = data.Equipped.Weapon
		end
		if data.Equipped.Armor and not data.Equipped.Cloth then
			data.Equipped.Cloth = data.Equipped.Armor
		end

		for _, slot in ipairs(ItemData.Slots) do
			local item = sanitizeItem(data.Equipped[slot])
			if item and ItemData.isSlotCompatible(ItemData.Bases[item.Base].Slot, slot) then
				profile.Equipped[slot] = item
			end
		end

		-- If MainHand forbids OffHand, move any equipped OffHand item back to Inventory
		if profile.Equipped.OffHand and not ItemData.allowsOffHand(profile.Equipped.MainHand) then
			if #profile.Inventory < INVENTORY_CAPACITY then
				table.insert(profile.Inventory, profile.Equipped.OffHand)
			end
			profile.Equipped.OffHand = nil
		end
	end
	return profile
end

local function saveProfile(player: Player, profile: Profile): boolean
	local store = dataStore
	if not store or not profile.CanSave then
		return false
	end

	local data = {
		Version = 1,
		Level = profile.Level,
		Exp = profile.Exp,
		Inventory = profile.Inventory,
		Equipped = profile.Equipped,
		SkillBar = profile.SkillBar,
		SkillRunes = profile.SkillRunes,
		Spirits = profile.Spirits,
		Stones = profile.Stones,
		Class = profile.Class,
		HeroVariant = profile.HeroVariant,
		Passives = profile.Passives,
	}

	pendingSaves += 1
	local saved = false
	for attempt = 1, RETRY_COUNT do
		local ok, err = pcall(function()
			store:UpdateAsync(getKey(player), function()
				return data, { player.UserId }
			end)
		end)
		if ok then
			saved = true
			break
		end
		warn(("[PlayerData] Save failed for %s (attempt %d): %s"):format(player.Name, attempt, tostring(err)))
		task.wait(attempt)
	end
	pendingSaves -= 1
	return saved
end

-- ==========================================
-- 2. STATS (level + equipment -> character & HUD)
-- ==========================================
local function applyToCharacter(player: Player, profile: Profile, healToFull: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	-- Keep the same health % when max health changes
	local healthRatio = humanoid.Health / humanoid.MaxHealth
	humanoid.MaxHealth = profile.Stats.MaxHealth
	humanoid.Health = if healToFull then humanoid.MaxHealth else humanoid.MaxHealth * healthRatio
end

local function refreshStats(player: Player, profile: Profile, healToFull: boolean)
	-- Passive tree + Stone Spirits in their slots come on top of level and gear
	local bonus = PassiveData.getStats(profile.Class, profile.Passives)
	for stat, value in pairs(SpiritData.getStats(profile.Spirits)) do
		bonus[stat] = (bonus[stat] or 0) + value
	end
	profile.Stats = PlayerStats.compute(profile.Level, profile.Equipped, bonus)

	-- Attributes replicate to every client automatically: HudClient / InventoryClient / CombatClient read these
	player:SetAttribute("Level", profile.Level)
	player:SetAttribute("Exp", profile.Exp)
	player:SetAttribute("ExpToNext", PlayerStats.expToNext(profile.Level))
	player:SetAttribute("MaxHealth", profile.Stats.MaxHealth)
	player:SetAttribute("MaxMana", profile.Stats.MaxMana)
	player:SetAttribute("MaxEnergyShield", profile.Stats.MaxEnergyShield)
	player:SetAttribute("EnergyShieldRecharge", profile.Stats.EnergyShieldRecharge)
	player:SetAttribute("FlatDamage", profile.Stats.FlatDamage)
	player:SetAttribute("AttackSpeed", profile.Stats.AttackSpeed)
	player:SetAttribute("FireDamage", profile.Stats.FireDamage)
	player:SetAttribute("ColdDamage", profile.Stats.ColdDamage)
	player:SetAttribute("LightningDamage", profile.Stats.LightningDamage)
	player:SetAttribute("FireResistance", profile.Stats.FireResistance)
	player:SetAttribute("ColdResistance", profile.Stats.ColdResistance)
	player:SetAttribute("LightningResistance", profile.Stats.LightningResistance)

	applyToCharacter(player, profile, healToFull)
end

local function sync(player: Player, profile: Profile)
	inventoryRemote:FireClient(player, "Sync", {
		Inventory = profile.Inventory,
		Equipped = profile.Equipped,
		SkillBar = profile.SkillBar,
		SkillRunes = profile.SkillRunes,
		Spirits = profile.Spirits,
		Stones = profile.Stones,
		Class = profile.Class, -- Passive tree (PassiveTreeClient listens to this Sync too)
		HeroVariant = profile.HeroVariant,
		Passives = profile.Passives,
		Capacity = INVENTORY_CAPACITY,
	})

	-- Class + hero path for HeroClient's meter (and anyone drawing this player's orbs)
	player:SetAttribute("HeroClass", profile.Class or "")
	player:SetAttribute("HeroVariant", profile.HeroVariant or "")

	-- The skill bar as "BasicSlash,SpinSlash,," (one entry per slot, empty = no skill) for CombatClient's buttons
	player:SetAttribute("SkillBar", table.concat(profile.SkillBar, ","))
	-- Spirit slots the same way: everyone's SpiritClient draws this player's spirits following them
	player:SetAttribute("Spirits", table.concat(profile.Spirits, ","))

	-- Socketed runes also go out as "SkillRunes_<skillId>" = "Reach,Ember" attributes, so every client
	-- can draw this player's skills with them (CombatClient)
	for skillId in pairs(SkillData) do
		local runeIds = {}
		for _, item in ipairs(profile.SkillRunes[skillId] or {}) do
			table.insert(runeIds, ItemData.getRuneId(item) or "")
		end
		player:SetAttribute("SkillRunes_" .. skillId, table.concat(runeIds, ","))
	end
end

-- ==========================================
-- 3. INVENTORY ACTIONS (requested by InventoryClient, validated here)
-- ==========================================
local function findInInventory(profile: Profile, itemId: string): number?
	for index, item in ipairs(profile.Inventory) do
		if item.Id == itemId then
			return index
		end
	end
	return nil
end

local function equip(player: Player, profile: Profile, itemId: string)
	local index = findInInventory(profile, itemId)
	if not index then
		return
	end
	local item = profile.Inventory[index]
	local base = ItemData.Bases[item.Base]
	if base.Slot == "Rune" then
		PlayerData.notify(player, "Runes go into skill sockets (bottom of the inventory)", WARNING_COLOR)
		return
	elseif base.Slot == "Tablet" then
		PlayerData.notify(player, "Stone Tablets go into the dungeon portal (Place in Portal)", WARNING_COLOR)
		return
	elseif base.Slot == "Skill" then
		PlayerData.notify(player, "Skill Stones go on the skill bar (bottom of the inventory)", WARNING_COLOR)
		return
	elseif base.Slot == "Spirit" then
		PlayerData.notify(player, "Stone Spirits go in the spirit slots (next to your gear)", WARNING_COLOR)
		return
	end
	local slot = ItemData.getTargetSlot(base.Slot, profile.Equipped)

	-- 1. Trying to equip an OffHand item while MainHand forbids OffHand
	if slot == "OffHand" and not ItemData.allowsOffHand(profile.Equipped.MainHand) then
		PlayerData.notify(player, "Current Main Hand weapon forbids Off-Hand!", WARNING_COLOR)
		return
	end

	-- 2. Trying to equip a MainHand weapon that forbids OffHand while an OffHand is currently equipped
	if slot == "MainHand" and not ItemData.allowsOffHand(item) and profile.Equipped.OffHand then
		-- If MainHand is also occupied, both old MainHand and old OffHand return to inventory (+1 net item in bag)
		if profile.Equipped.MainHand and #profile.Inventory >= INVENTORY_CAPACITY then
			PlayerData.notify(player, "Inventory full! Cannot auto-unequip Off-Hand", WARNING_COLOR)
			return
		end
	end

	-- Swap: the previously equipped item takes the new item's place in the inventory
	local previous = profile.Equipped[slot]
	if previous then
		profile.Inventory[index] = previous
	else
		table.remove(profile.Inventory, index)
	end
	profile.Equipped[slot] = item

	-- Auto-unequip OffHand if the newly equipped MainHand weapon forbids it
	if slot == "MainHand" and not ItemData.allowsOffHand(item) and profile.Equipped.OffHand then
		table.insert(profile.Inventory, profile.Equipped.OffHand)
		profile.Equipped.OffHand = nil
		PlayerData.notify(player, "Off-Hand unequipped to Inventory", INFO_COLOR)
	end
end

local function unequip(player: Player, profile: Profile, slot: string)
	local item = profile.Equipped[slot]
	if not item then
		return
	end
	if #profile.Inventory >= INVENTORY_CAPACITY then
		PlayerData.notify(player, "Inventory is full!", WARNING_COLOR)
		return
	end
	profile.Equipped[slot] = nil
	table.insert(profile.Inventory, item)
end

local function discard(profile: Profile, itemId: string)
	local index = findInInventory(profile, itemId)
	if index then
		table.remove(profile.Inventory, index)
	end
end

-- Moves a rune from the inventory into the next free socket of a skill on the skill bar.
-- skillId = nil: the first skill on the bar (slot order) it fits that has room (Shift+Click / Auto-Socket)
local function socketRune(player: Player, profile: Profile, itemId: string, skillId: string?)
	local index = findInInventory(profile, itemId)
	local item = if index then profile.Inventory[index] else nil
	local runeId = if item then ItemData.getRuneId(item) else nil
	if not index or not item or not runeId then
		return
	end

	-- Returns the reason when the rune can't go into this skill
	local function whyNot(id: string): string?
		local skill = SkillData[id]
		local socketed = profile.SkillRunes[id]
		if not skill or not socketed then
			return "Unknown skill"
		elseif not table.find(profile.SkillBar, id) then
			return skill.Name .. " is not on your skill bar"
		elseif not RuneData.fits(runeId, skill) then
			return ("%s doesn't fit %s"):format(ItemData.getName(item), skill.Name)
		elseif #socketed >= skill.Sockets then
			return skill.Name .. " has no free socket"
		end
		for _, other in ipairs(socketed) do
			if ItemData.getRuneId(other) == runeId then
				return skill.Name .. " already has this rune"
			end
		end
		return nil
	end

	local target = skillId
	if target then
		local reason = whyNot(target)
		if reason then
			PlayerData.notify(player, reason, WARNING_COLOR)
			return
		end
	else
		for _, id in ipairs(profile.SkillBar) do
			if id ~= "" and not whyNot(id) then
				target = id
				break
			end
		end
		if not target then
			PlayerData.notify(player, "No skill on your skill bar has a free socket for this rune", WARNING_COLOR)
			return
		end
	end

	table.remove(profile.Inventory, index)
	table.insert(profile.SkillRunes[target], item)
end

-- The skill bar and the spirit slots work the same way: a stone item from the bag goes into a slot as just its id,
-- and taking it out makes a new item. Each kind says where its slots are and how to read / make its items
type SlotKind = {
	Slots: (Profile) -> { string },
	GetId: (ItemData.Item) -> string?,
	MakeItem: (string) -> ItemData.Item,
	Name: (string) -> string,
	AlreadyText: string, -- %s = the name
	FullText: string,
}

local SKILL_SLOTS: SlotKind = {
	Slots = function(profile: Profile)
		return profile.SkillBar
	end,
	GetId = ItemData.getSkillId,
	MakeItem = makeSkillStone,
	Name = function(skillId: string)
		return SkillData[skillId].Name
	end,
	AlreadyText = "%s is already on your skill bar",
	FullText = "Skill bar is full: click a slot to swap it",
}

local SPIRIT_SLOTS: SlotKind = {
	Slots = function(profile: Profile)
		return profile.Spirits
	end,
	GetId = ItemData.getSpiritId,
	MakeItem = makeSpiritStone,
	Name = function(spiritId: string)
		return SpiritData.Spirits[spiritId].Name
	end,
	AlreadyText = "%s is already in a spirit slot",
	FullText = "Spirit slots are full: click a slot to swap it",
}

-- Puts an item from the bag into `slot`, or the first empty slot when slot = nil. Whatever was in that slot goes
-- back into the bag in the spot the new one left (so a full bag never blocks a swap). Runes stay with their skill
local function putInSlot(player: Player, profile: Profile, kind: SlotKind, itemId: string, slot: number?)
	local slots = kind.Slots(profile)
	local index = findInInventory(profile, itemId)
	local item = if index then profile.Inventory[index] else nil
	local id = if item then kind.GetId(item) else nil
	if not index or not item or not id then
		return
	end
	if table.find(slots, id) then
		PlayerData.notify(player, kind.AlreadyText:format(kind.Name(id)), WARNING_COLOR)
		return
	end

	local target = slot
	if target == nil then
		target = table.find(slots, "")
		if not target then
			PlayerData.notify(player, kind.FullText, WARNING_COLOR)
			return
		end
	elseif not slots[target] then
		return -- Not a slot number (also rejects 1.5 / NaN from the client)
	end

	local previous = slots[target]
	slots[target] = id
	if previous ~= "" then
		profile.Inventory[index] = kind.MakeItem(previous)
	else
		table.remove(profile.Inventory, index)
	end
end

-- Takes what's in a slot back into the bag as an item
local function takeFromSlot(player: Player, profile: Profile, kind: SlotKind, slot: number)
	local slots = kind.Slots(profile)
	local id = slots[slot]
	if not id or id == "" then
		return
	end
	if #profile.Inventory >= INVENTORY_CAPACITY then
		PlayerData.notify(player, "Inventory is full!", WARNING_COLOR)
		return
	end
	slots[slot] = ""
	table.insert(profile.Inventory, kind.MakeItem(id))
end

-- Takes a rune out of a skill back into the inventory (sockets after it shift left)
local function unsocketRune(player: Player, profile: Profile, skillId: string, socketIndex: number)
	local socketed = profile.SkillRunes[skillId]
	local item = if socketed then socketed[socketIndex] else nil
	if not socketed or not item then
		return
	end
	if #profile.Inventory >= INVENTORY_CAPACITY then
		PlayerData.notify(player, "Inventory is full!", WARNING_COLOR)
		return
	end
	table.remove(socketed, socketIndex)
	table.insert(profile.Inventory, item)
end

-- Uses one crafting stone on an item in the bag or equipped (equipped gear changes the player's stats right away)
local function craft(player: Player, profile: Profile, stoneId: string, itemId: string)
	local stone = StoneData.Stones[stoneId]
	if not stone then
		return
	end
	local index = findInInventory(profile, itemId)
	local item = if index then profile.Inventory[index] else nil
	if not item then
		for _, equippedItem in pairs(profile.Equipped) do
			if equippedItem.Id == itemId then
				item = equippedItem
			end
		end
	end
	if not item then
		return
	end
	if (profile.Stones[stoneId] or 0) < 1 then
		PlayerData.notify(player, "You have no " .. stone.Name, WARNING_COLOR)
		return
	end

	local reason = Crafting.useStone(stoneId, item)
	if reason then
		PlayerData.notify(player, reason, WARNING_COLOR)
		return
	end
	profile.Stones[stoneId] -= 1
	local rarity = ItemData.Rarities[item.Rarity]
	PlayerData.notify(player, ("%s used on %s"):format(stone.Name, ItemData.getName(item)), rarity and rarity.Color)
end

-- Puts a Stone Tablet from the bag into the Lobby portal: the next dungeon run (for everyone) uses it
local function placeTablet(player: Player, profile: Profile, itemId: string)
	local index = findInInventory(profile, itemId)
	local item = if index then profile.Inventory[index] else nil
	if not index or not item or not ItemData.isTablet(item) then
		return
	end
	local reason = DungeonRun.placeTablet(item)
	if reason then
		PlayerData.notify(player, reason, WARNING_COLOR)
		return
	end
	table.remove(profile.Inventory, index)
	local effects = TabletData.getEffects(item :: any)
	PlayerData.notify(nil, ("%s placed a Stone Tablet in the portal (%s)"):format(player.DisplayName, TabletData.describe(effects)), INFO_COLOR)
end

-- Picking (or changing) a class starts the tree over from that class's Start node. Free for now (testing)
local function chooseClass(player: Player, profile: Profile, classId: string)
	local class = PassiveData.Classes[classId]
	if not class then
		return
	end
	profile.Class = classId
	profile.HeroVariant = nil -- Paths belong to a class
	profile.Passives = {}
	PlayerData.notify(player, "You are now a " .. class.Name, class.Color)
end

-- Hero path of the player's class (HeroData), from HeroData.VARIANT_LEVEL. Free to switch for now (testing)
local function chooseHeroPath(player: Player, profile: Profile, variantId: string)
	local hero = HeroData.get(profile.Class)
	if not hero or not hero.Variants[variantId] then
		return
	end
	if profile.Level < HeroData.VARIANT_LEVEL then
		PlayerData.notify(player, ("Hero paths unlock at level %d"):format(HeroData.VARIANT_LEVEL), WARNING_COLOR)
		return
	end
	profile.HeroVariant = variantId
	PlayerData.notify(player, ("%s path: %s"):format(hero.Mechanic, hero.Variants[variantId].Name), hero.Color)
end

-- One point into a node that links to the tree you already have (PassiveData.whyNot, same as the window)
local function allocatePassive(player: Player, profile: Profile, nodeId: string)
	local reason = PassiveData.whyNot(profile.Class, profile.Passives, nodeId)
	if reason then
		PlayerData.notify(player, reason, WARNING_COLOR)
		return
	end
	if #profile.Passives >= PassiveData.getPoints(profile.Level) then
		PlayerData.notify(player, "No passive points left (you get one every level)", WARNING_COLOR)
		return
	end
	table.insert(profile.Passives, nodeId)
end

local function onInventoryRequest(player: Player, action: any, arg: any, arg2: any)
	local profile = profiles[player]
	if not profile then
		return
	end

	if action == "Equip" and type(arg) == "string" then
		equip(player, profile, arg)
	elseif action == "Unequip" and type(arg) == "string" then
		unequip(player, profile, arg)
	elseif action == "Discard" and type(arg) == "string" then
		discard(profile, arg)
	elseif action == "Socket" and type(arg) == "string" and (arg2 == nil or type(arg2) == "string") then
		socketRune(player, profile, arg, arg2)
	elseif action == "Unsocket" and type(arg) == "string" and type(arg2) == "number" then
		unsocketRune(player, profile, arg, arg2)
	elseif action == "SetSkill" and type(arg) == "string" and (arg2 == nil or type(arg2) == "number") then
		putInSlot(player, profile, SKILL_SLOTS, arg, arg2)
	elseif action == "ClearSkill" and type(arg) == "number" then
		takeFromSlot(player, profile, SKILL_SLOTS, arg)
	elseif action == "SetSpirit" and type(arg) == "string" and (arg2 == nil or type(arg2) == "number") then
		putInSlot(player, profile, SPIRIT_SLOTS, arg, arg2)
	elseif action == "ClearSpirit" and type(arg) == "number" then
		takeFromSlot(player, profile, SPIRIT_SLOTS, arg)
	elseif action == "Craft" and type(arg) == "string" and type(arg2) == "string" then
		craft(player, profile, arg, arg2)
	elseif action == "PlaceTablet" and type(arg) == "string" then
		placeTablet(player, profile, arg)
	elseif action == "ChooseClass" and type(arg) == "string" then
		local before = profile.Class
		chooseClass(player, profile, arg)
		if profile.Class ~= before then
			for _, listener in ipairs(heroChangedListeners) do
				task.spawn(listener, player)
			end
		end
	elseif action == "ChooseHeroPath" and type(arg) == "string" then
		local before = profile.HeroVariant
		chooseHeroPath(player, profile, arg)
		if profile.HeroVariant ~= before then
			for _, listener in ipairs(heroChangedListeners) do
				task.spawn(listener, player)
			end
		end
	elseif action == "AllocatePassive" and type(arg) == "string" then
		allocatePassive(player, profile, arg)
	elseif action == "ResetPassives" then
		table.clear(profile.Passives) -- Free respec for now (testing)
	elseif action ~= "RequestSync" then
		return
	end

	refreshStats(player, profile, false)
	sync(player, profile)
end

-- ==========================================
-- 4. PUBLIC API (used by CombatServer / EnemyService / Loot)
-- ==========================================
function PlayerData.getStats(player: Player): PlayerStats.Stats
	local profile = profiles[player]
	return if profile then profile.Stats else PlayerStats.compute(1, {})
end

-- The player's class and hero path (HeroService runs the mechanic). Both nil before the data loads
function PlayerData.getHero(player: Player): (string?, string?)
	local profile = profiles[player]
	if not profile then
		return nil, nil
	end
	return profile.Class, profile.HeroVariant
end

-- callback(player) after the class or hero path changes
function PlayerData.onHeroChanged(callback: (Player) -> ())
	table.insert(heroChangedListeners, callback)
end

-- True when the skill is on the player's skill bar (CombatServer only lets them use those)
function PlayerData.hasSkill(player: Player, skillId: string): boolean
	local profile = profiles[player]
	return profile ~= nil and table.find(profile.SkillBar, skillId) ~= nil
end

-- Rune ids socketed in a skill as a set, e.g. { Reach = true, Ember = true } (CombatServer applies them)
function PlayerData.getSkillRunes(player: Player, skillId: string): { [string]: boolean }
	local runes = {}
	local profile = profiles[player]
	local socketed = if profile then profile.SkillRunes[skillId] else nil
	for _, item in ipairs(socketed or {}) do
		local runeId = ItemData.getRuneId(item)
		if runeId then
			runes[runeId] = true
		end
	end
	return runes
end

-- Message at the top of the screen. player = nil sends it to everyone
function PlayerData.notify(player: Player?, text: string, color: Color3?)
	if player then
		notifyRemote:FireClient(player, text, color)
	else
		notifyRemote:FireAllClients(text, color)
	end
end

function PlayerData.addExp(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or profile.Level >= PlayerStats.MAX_LEVEL then
		return
	end

	profile.Exp += amount
	local leveledUp = false
	while profile.Level < PlayerStats.MAX_LEVEL and profile.Exp >= PlayerStats.expToNext(profile.Level) do
		profile.Exp -= PlayerStats.expToNext(profile.Level)
		profile.Level += 1
		leveledUp = true
	end
	if profile.Level >= PlayerStats.MAX_LEVEL then
		profile.Exp = 0
	end

	-- Leveling up also heals to full
	refreshStats(player, profile, leveledUp)
	if leveledUp then
		PlayerData.notify(player, ("Level Up! Lv %d (+Passive Point)"):format(profile.Level), LEVEL_UP_COLOR)
	end
end

-- Crafting stones are a count, not inventory items, so picking one up always works
function PlayerData.addStone(player: Player, stoneId: string, amount: number): boolean
	local profile = profiles[player]
	local stone = StoneData.Stones[stoneId]
	if not profile or not stone then
		return false
	end
	profile.Stones[stoneId] = (profile.Stones[stoneId] or 0) + amount
	sync(player, profile)
	PlayerData.notify(player, "Obtained " .. stone.Name, StoneData.COLOR)
	return true
end

-- True when the bag has a free spot (Loot asks before picking an item up by itself, without a message)
function PlayerData.hasRoom(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and #profile.Inventory < INVENTORY_CAPACITY
end

-- Returns false (and tells the player) when the inventory is full
function PlayerData.addItem(player: Player, item: ItemData.Item): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if #profile.Inventory >= INVENTORY_CAPACITY then
		PlayerData.notify(player, "Inventory is full! Equip or discard items first", WARNING_COLOR)
		return false
	end

	table.insert(profile.Inventory, item)
	sync(player, profile)
	local rarity = ItemData.Rarities[item.Rarity]
	PlayerData.notify(player, "Obtained " .. ItemData.getName(item), rarity and rarity.Color)
	return true
end

-- ==========================================
-- 5. PLAYER JOIN / LEAVE / SERVER SHUTDOWN
-- ==========================================
local function onPlayerAdded(player: Player)
	player:SetAttribute("DataStatus", "Loading")

	-- Every respawn: apply max health from level + equipment
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Humanoid", 10)
		local profile = profiles[player]
		if profile then
			applyToCharacter(player, profile, true)
		end
	end)

	local status, data = loadData(player)
	if not player.Parent then
		return -- Left while loading
	end

	local loaded = status == "Loaded"
	local profile = buildProfile(if loaded then data else nil, loaded)
	profiles[player] = profile
	player:SetAttribute("DataStatus", status)
	refreshStats(player, profile, true)
	sync(player, profile)

	if status == "NoAccess" then
		PlayerData.notify(player, "Studio Test: Playable, but progress will not be saved", INFO_COLOR)
	elseif status == "Failed" then
		PlayerData.notify(player, "Failed to load data. Progress will not be saved this session", WARNING_COLOR)
	end
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	if profile then
		saveProfile(player, profile)
	end
end

function PlayerData.start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end

	inventoryRemote.OnServerEvent:Connect(onInventoryRequest)

	-- Autosave so a server crash loses at most AUTOSAVE_INTERVAL seconds of progress
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for player, profile in pairs(profiles) do
				task.spawn(saveProfile, player, profile)
			end
		end
	end)

	-- Server shutting down: save everyone still here and wait (up to 25s) for all saves to finish
	game:BindToClose(function()
		for player, profile in pairs(profiles) do
			profiles[player] = nil
			task.spawn(saveProfile, player, profile)
		end
		local deadline = os.clock() + 25
		while pendingSaves > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return PlayerData
