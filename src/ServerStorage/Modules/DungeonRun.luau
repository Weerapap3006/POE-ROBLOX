-- ==========================================
-- DUNGEON RUN (Stone Tablet in the portal -> modifiers of the current run)
-- Path: ServerStorage.Modules.DungeonRun
-- ==========================================
-- The dungeon is shared by everyone on the server, so this is server-wide state:
--   pending = the tablet a player placed in the Lobby portal (PlayerData "PlaceTablet")
--   current = what the run in progress uses (EnemyService reads it when spawning, attacking and dropping loot)
-- Entering the portal starts a new run (EnemyService.resetDungeon -> startRun): the pending tablet is used up,
-- no pending tablet = a plain run (Tier 0)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ItemData = require(modulesFolder:WaitForChild("ItemData"))
local TabletData = require(modulesFolder:WaitForChild("TabletData"))

local DungeonRun = {}

local pending: ItemData.Item? = nil
local current: TabletData.Effects = TabletData.getEffects(nil)

-- Fires when the pending tablet changes (EnemyService updates the portal sign)
local changedEvent = Instance.new("BindableEvent")
DungeonRun.Changed = changedEvent.Event

-- Returns nil when the tablet went in, or why it didn't (the caller keeps the item then)
function DungeonRun.placeTablet(tablet: ItemData.Item): string?
	if pending then
		return "The portal already holds a tablet. Enter the dungeon to use it first"
	end
	pending = tablet
	changedEvent:Fire()
	return nil
end

function DungeonRun.getPending(): ItemData.Item?
	return pending
end

-- A new run begins (someone entered the portal): the pending tablet, if any, decides its modifiers
function DungeonRun.startRun(): TabletData.Effects
	current = TabletData.getEffects(pending :: any)
	pending = nil
	changedEvent:Fire()
	return current
end

function DungeonRun.getCurrent(): TabletData.Effects
	return current
end

return DungeonRun
