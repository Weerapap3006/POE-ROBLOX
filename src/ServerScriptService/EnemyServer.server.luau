-- ==========================================
-- ENEMY SERVER (Starts enemy spawning and AI)
-- Path: ServerScriptService.EnemyServer
-- ==========================================
-- All the logic lives in ServerStorage.Modules.EnemyService (CombatServer also uses it for damage)
local ServerStorage = game:GetService("ServerStorage")

local EnemyService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("EnemyService"))

EnemyService.start()
