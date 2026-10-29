-- ==========================================
-- PLAYER DATA SERVER (Starts save/load, inventory requests and autosave)
-- Path: ServerScriptService.PlayerDataServer
-- ==========================================
-- All the logic lives in ServerStorage.Modules.PlayerData (CombatServer / EnemyService / Loot also use it)
local ServerStorage = game:GetService("ServerStorage")

local PlayerData = require(ServerStorage:WaitForChild("Modules"):WaitForChild("PlayerData"))

PlayerData.start()
