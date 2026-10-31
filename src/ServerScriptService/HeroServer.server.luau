-- ==========================================
-- HERO SERVER (Starts the class hero mechanics: Fury, Momentum, Stone Orbs)
-- Path: ServerScriptService.HeroServer
-- ==========================================
-- All the logic lives in ServerStorage.Modules.HeroService (CombatServer / EnemyService also use it)
local ServerStorage = game:GetService("ServerStorage")

local HeroService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HeroService"))

HeroService.start()
