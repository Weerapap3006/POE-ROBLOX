-- ==========================================
-- PLAYER DATA (Level, EXP, Inventory, Equipment + DataStore Save/Load)
-- Path: ServerStorage.Modules.PlayerData
-- ==========================================
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ItemData = require(modulesFolder:WaitForChild("ItemData"))
local PlayerStats = require(modulesFolder:WaitForChild("PlayerStats"))

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
	Stats: PlayerStats.Stats,
	-- False when loading failed: saving would overwrite the player's real data with this empty profile
	CanSave: boolean,
}

local PlayerData = {}

local profiles: { [Player]: Profile } = {}
local pendingSaves = 0

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
	local affixes = {}
	if type(raw.Affixes) == "table" then
		for _, affix in ipairs(raw.Affixes) do
			if type(affix) == "table" and ItemData.Affixes[affix.Id] and type(affix.Value) == "number" then
				table.insert(affixes, { Id = affix.Id, Value = affix.Value })
			end
		end
	end
	return { Id = raw.Id, Base = raw.Base, Rarity = raw.Rarity, Affixes = affixes }
end

local function buildProfile(data: any, canSave: boolean): Profile
	local profile: Profile = {
		Level = 1,
		Exp = 0,
		Inventory = {},
		Equipped = {},
		Stats = PlayerStats.compute(1, {}),
		CanSave = canSave,
	}
	if type(data) ~= "table" then
		return profile -- New player (or load failed)
	end

	if type(data.Level) == "number" then
		profile.Level = math.clamp(math.floor(data.Level), 1, PlayerStats.MAX_LEVEL)
	end
	if type(data.Exp) == "number" then
		profile.Exp = math.max(0, math.floor(data.Exp))
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
	profile.Stats = PlayerStats.compute(profile.Level, profile.Equipped)

	-- Attributes replicate to every client automatically: HudClient / InventoryClient / CombatClient read these
	player:SetAttribute("Level", profile.Level)
	player:SetAttribute("Exp", profile.Exp)
	player:SetAttribute("ExpToNext", PlayerStats.expToNext(profile.Level))
	player:SetAttribute("MaxHealth", profile.Stats.MaxHealth)
	player:SetAttribute("FlatDamage", profile.Stats.FlatDamage)
	player:SetAttribute("AttackSpeed", profile.Stats.AttackSpeed)

	applyToCharacter(player, profile, healToFull)
end

local function sync(player: Player, profile: Profile)
	inventoryRemote:FireClient(player, "Sync", {
		Inventory = profile.Inventory,
		Equipped = profile.Equipped,
		Capacity = INVENTORY_CAPACITY,
	})
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

local function equip(profile: Profile, itemId: string)
	local index = findInInventory(profile, itemId)
	if not index then
		return
	end
	local item = profile.Inventory[index]
	local slot = ItemData.getTargetSlot(ItemData.Bases[item.Base].Slot, profile.Equipped)

	-- Swap: the previously equipped item takes the new item's place in the inventory
	local previous = profile.Equipped[slot]
	if previous then
		profile.Inventory[index] = previous
	else
		table.remove(profile.Inventory, index)
	end
	profile.Equipped[slot] = item
end

local function unequip(player: Player, profile: Profile, slot: string)
	local item = profile.Equipped[slot]
	if not item then
		return
	end
	if #profile.Inventory >= INVENTORY_CAPACITY then
		PlayerData.notify(player, "กระเป๋าเต็ม!", WARNING_COLOR)
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

local function onInventoryRequest(player: Player, action: any, arg: any)
	local profile = profiles[player]
	if not profile then
		return
	end

	if action == "Equip" and type(arg) == "string" then
		equip(profile, arg)
	elseif action == "Unequip" and type(arg) == "string" then
		unequip(player, profile, arg)
	elseif action == "Discard" and type(arg) == "string" then
		discard(profile, arg)
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
		PlayerData.notify(player, ("เลเวลอัป! Lv %d"):format(profile.Level), LEVEL_UP_COLOR)
	end
end

-- Returns false (and tells the player) when the inventory is full
function PlayerData.addItem(player: Player, item: ItemData.Item): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if #profile.Inventory >= INVENTORY_CAPACITY then
		PlayerData.notify(player, "กระเป๋าเต็ม! สวมใส่หรือทิ้งของก่อน", WARNING_COLOR)
		return false
	end

	table.insert(profile.Inventory, item)
	sync(player, profile)
	local rarity = ItemData.Rarities[item.Rarity]
	PlayerData.notify(player, "ได้รับ " .. ItemData.getName(item), rarity and rarity.Color)
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
		PlayerData.notify(player, "เทสใน Studio: เล่นได้ปกติ แต่ไม่บันทึกความคืบหน้า", INFO_COLOR)
	elseif status == "Failed" then
		PlayerData.notify(player, "โหลดข้อมูลไม่สำเร็จ รอบนี้จะไม่บันทึกความคืบหน้า", WARNING_COLOR)
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
