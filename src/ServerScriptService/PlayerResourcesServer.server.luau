-- ==========================================
-- PLAYER RESOURCES SERVER (Starts mana regen, energy shield recharge and flasks)
-- Path: ServerScriptService.PlayerResourcesServer
-- ==========================================
-- All the logic lives in ServerStorage.Modules.PlayerResources (CombatServer / EnemyService also use it)
local ServerStorage = game:GetService("ServerStorage")

local PlayerResources = require(ServerStorage:WaitForChild("Modules"):WaitForChild("PlayerResources"))

PlayerResources.start()
