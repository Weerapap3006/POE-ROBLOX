-- ==========================================
-- ENEMY SERVICE (Spawning, Chase/Attack AI, Damage, Death -> EXP & Loot)
-- Path: ServerStorage.Modules.EnemyService
-- ==========================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EnemyData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EnemyData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Loot = require(script.Parent:WaitForChild("Loot"))

local combatRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatRemote") :: RemoteEvent

-- ==========================================
-- CONFIGURATION
-- ==========================================
local AI_TICK = 0.15 -- Seconds between AI decisions
local SPAWN_FOLDER_NAME = "EnemySpawns" -- Workspace folder of spawn marker parts (made in Studio)
local MELEE_REACH_BONUS = 1.5 -- A melee hit still lands if the target is this much past Range after the windup
local BOSS_CLEAR_COLOR = Color3.fromRGB(255, 215, 70)

-- Blockout body at Scale 1. Offsets are from the HumanoidRootPart center, -Z is the front
local ROOT_SIZE = Vector3.new(2, 2, 1)
local HIP_HEIGHT = 1.5 -- Root center floats HIP_HEIGHT + ROOT_SIZE.Y / 2 above the ground, so the legs touch it
local BODY_PARTS = {
	{ Name = "Body", Size = Vector3.new(2.4, 2.2, 1.6), Offset = Vector3.new(0, 0, 0), IsEye = false },
	{ Name = "Head", Size = Vector3.new(1.8, 1.5, 1.5), Offset = Vector3.new(0, 1.85, -0.1), IsEye = false },
	{ Name = "LeftEye", Size = Vector3.new(0.35, 0.3, 0.1), Offset = Vector3.new(-0.4, 1.95, -0.86), IsEye = true },
	{ Name = "RightEye", Size = Vector3.new(0.35, 0.3, 0.1), Offset = Vector3.new(0.4, 1.95, -0.86), IsEye = true },
	{ Name = "LeftArm", Size = Vector3.new(0.8, 2, 0.8), Offset = Vector3.new(-1.65, -0.2, 0), IsEye = false },
	{ Name = "RightArm", Size = Vector3.new(0.8, 2, 0.8), Offset = Vector3.new(1.65, -0.2, 0), IsEye = false },
	{ Name = "LeftLeg", Size = Vector3.new(0.9, 1.4, 0.9), Offset = Vector3.new(-0.6, -1.8, 0), IsEye = false },
	{ Name = "RightLeg", Size = Vector3.new(0.9, 1.4, 0.9), Offset = Vector3.new(0.6, -1.8, 0), IsEye = false },
}

type SpawnPoint = {
	TypeId: string,
	Position: Vector3,
}

type EnemyState = {
	Data: EnemyData.EnemyType,
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Home: Vector3, -- Ground position of its spawn point
	Target: Model?, -- Player character being chased
	Returning: boolean, -- Walking home after being pulled past LeashRange
	Attacking: boolean, -- In an attack windup
	Dead: boolean,
	NextAttackTime: number,
	Contributors: { [Player]: boolean }, -- Everyone who hit it gets the EXP
}

local EnemyService = {}

local enemies: { [Model]: EnemyState } = {}
local random = Random.new()

-- ==========================================
-- 1. HELPERS
-- ==========================================
local function getEnemiesFolder(): Instance
	local folder = workspace:FindFirstChild("Enemies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Enemies"
		folder.Parent = workspace
	end
	return folder
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- HumanoidRootPart of a living character, or nil
local function getAliveRoot(character: Model?): BasePart?
	if not character or not character.Parent then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	return root
end

local function findGround(position: Vector3): Vector3
	local ignore: { Instance } = { getEnemiesFolder() }
	local spawnFolder = workspace:FindFirstChild(SPAWN_FOLDER_NAME)
	if spawnFolder then
		table.insert(ignore, spawnFolder)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -200, 0), params)
	return if result then result.Position else position
end

-- ==========================================
-- 2. SPAWN POINTS
-- ==========================================
-- Used when the map has no Workspace.EnemySpawns folder yet, so the game is playable on a plain baseplate
local function defaultSpawnPoints(): { SpawnPoint }
	local origin = Vector3.zero
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		origin = spawnLocation.Position
	end

	local points: { SpawnPoint } = {}
	-- Two packs of 3 Grunts, then the Brute boss further away (up-screen from the isometric camera)
	for _, packCenter in ipairs({ Vector3.new(-35, 0, -10), Vector3.new(-10, 0, -40) }) do
		for i = 1, 3 do
			local angle = (i / 3) * math.pi * 2
			local offset = Vector3.new(math.cos(angle) * 5, 0, math.sin(angle) * 5)
			table.insert(points, { TypeId = "Grunt", Position = origin + packCenter + offset })
		end
	end
	table.insert(points, { TypeId = "Brute", Position = origin + Vector3.new(-55, 0, -55) })
	return points
end

-- Marker = any part inside Workspace.EnemySpawns, named after an EnemyData key (or with an EnemyType attribute)
local function collectSpawnPoints(): { SpawnPoint }
	local points: { SpawnPoint } = {}
	local folder = workspace:FindFirstChild(SPAWN_FOLDER_NAME)
	if folder then
		for _, marker in ipairs(folder:GetDescendants()) do
			if marker:IsA("BasePart") then
				local typeId = marker:GetAttribute("EnemyType") or marker.Name
				if EnemyData[typeId] then
					marker.Transparency = 1
					marker.CanCollide = false
					marker.CanQuery = false
					marker.CanTouch = false
					table.insert(points, { TypeId = typeId, Position = marker.Position })
				else
					warn(("[EnemyService] %s: unknown enemy type '%s'"):format(marker:GetFullName(), tostring(typeId)))
				end
			end
		end
	end

	if #points == 0 then
		points = defaultSpawnPoints()
	end
	return points
end

-- ==========================================
-- 3. BUILD & SPAWN ENEMIES (blockout bodies, no animations)
-- ==========================================
local function buildModel(typeId: string, data: EnemyData.EnemyType): (Model, Humanoid, BasePart)
	local scale = data.Scale
	local model = Instance.new("Model")
	model.Name = typeId
	-- With StreamingEnabled, send the whole body at once (HudClient needs HumanoidRootPart for the health bar)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = ROOT_SIZE * scale
	root.Transparency = 1
	root.CFrame = CFrame.identity
	root.Parent = model

	for _, info in ipairs(BODY_PARTS) do
		local part = Instance.new("Part")
		part.Name = info.Name
		part.Size = info.Size * scale
		part.CFrame = CFrame.new(info.Offset * scale)
		part.Color = if info.IsEye then data.EyeColor else data.BodyColor
		part.Material = if info.IsEye then Enum.Material.Neon else Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.Massless = true
		part.Parent = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = part
		weld.Parent = part
	end

	-- Cel-shade outline (CombatClient flashes it white on hit and red during attack windups)
	local outline = Instance.new("Highlight")
	outline.Name = "CelShadeOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = Color3.fromRGB(15, 15, 20)
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = HIP_HEIGHT * scale
	humanoid.MaxHealth = data.MaxHealth
	humanoid.Health = data.MaxHealth
	humanoid.WalkSpeed = data.WalkSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model

	model.PrimaryPart = root
	return model, humanoid, root
end

local onDeath: (state: EnemyState, point: SpawnPoint) -> ()

local function spawnEnemy(point: SpawnPoint)
	local data = EnemyData[point.TypeId]
	local model, humanoid, root = buildModel(point.TypeId, data)

	local ground = findGround(point.Position)
	local rootHeight = (HIP_HEIGHT + ROOT_SIZE.Y / 2) * data.Scale
	local facing = random:NextNumber(0, math.pi * 2)
	model:PivotTo(CFrame.new(ground + Vector3.new(0, rootHeight, 0)) * CFrame.Angles(0, facing, 0))

	-- Read by HudClient for health bars and the boss bar
	model:SetAttribute("DisplayName", data.DisplayName)
	model:SetAttribute("IsBoss", data.IsBoss)
	model.Parent = getEnemiesFolder()

	-- Server owns the physics so enemies don't stutter when a player walks close
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	local state: EnemyState = {
		Data = data,
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Home = ground,
		Target = nil,
		Returning = false,
		Attacking = false,
		Dead = false,
		NextAttackTime = 0,
		Contributors = {},
	}
	enemies[model] = state

	humanoid.Died:Connect(function()
		onDeath(state, point)
	end)
end

function onDeath(state: EnemyState, point: SpawnPoint)
	if state.Dead then
		return
	end
	state.Dead = true
	local data = state.Data
	local model = state.Model

	-- EXP goes to everyone who hit it (co-op: nobody loses out on the last hit)
	for player in pairs(state.Contributors) do
		if player.Parent then
			PlayerData.addExp(player, data.Exp)
		end
	end

	Loot.rollDrops(data.Drops, findGround(state.Root.Position))

	if data.IsBoss then
		PlayerData.notify(nil, ("เคลียร์ด่าน! ปราบ %s สำเร็จ"):format(data.DisplayName), BOSS_CLEAR_COLOR)
	end

	-- Fade the body out, then remove it
	local outline = model:FindFirstChildOfClass("Highlight")
	if outline then
		outline:Destroy()
	end
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part ~= state.Root then
			TweenService:Create(part, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		end
	end
	task.delay(1, function()
		enemies[model] = nil
		model:Destroy()
	end)

	task.delay(data.RespawnTime, function()
		spawnEnemy(point)
	end)
end

-- ==========================================
-- 4. ATTACKS (windup first, so players can see it coming and dodge)
-- ==========================================
local function damagePlayer(character: Model, amount: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or character:FindFirstChildOfClass("ForceField") then
		return -- Dead, or spawn protection
	end
	humanoid:TakeDamage(amount)
	combatRemote:FireAllClients("DamageDealt", character, amount, false)
end

local function startAttack(state: EnemyState, target: Model, targetRoot: BasePart)
	local attack = state.Data.Attack
	local root = state.Root
	state.Attacking = true
	state.NextAttackTime = os.clock() + attack.Windup + attack.Cooldown

	-- Stop and face the target during the windup
	state.Humanoid:MoveTo(root.Position)
	local lookTarget = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
	if (lookTarget - root.Position).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, lookTarget)
	end

	-- Slam hits a circle around the enemy, Melee hits the target if it's still in reach
	local ground = root.Position - Vector3.new(0, state.Humanoid.HipHeight + root.Size.Y / 2, 0)
	local center = if attack.Kind == "Slam" then ground else targetRoot.Position
	local radius = attack.Radius or 0
	combatRemote:FireAllClients("EnemyAttack", state.Model, attack.Kind, center, radius, attack.Windup)

	task.delay(attack.Windup, function()
		state.Attacking = false
		if state.Dead then
			return
		end

		local damage = random:NextInteger(attack.MinDamage, attack.MaxDamage)
		if attack.Kind == "Slam" then
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local playerRoot = getAliveRoot(character)
				if character and playerRoot and flatDistance(playerRoot.Position, ground) <= radius then
					damagePlayer(character, damage)
				end
			end
		else
			local currentRoot = getAliveRoot(target)
			if currentRoot and flatDistance(currentRoot.Position, root.Position) <= attack.Range + MELEE_REACH_BONUS then
				damagePlayer(target, damage)
			end
		end
	end)
end

-- ==========================================
-- 5. AI (chase nearest player in range, attack, walk home when pulled too far)
-- ==========================================
local function findTarget(state: EnemyState): Model?
	local best: Model? = nil
	local bestDistance = state.Data.AggroRange
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = getAliveRoot(character)
		if character and root then
			local distance = flatDistance(root.Position, state.Root.Position)
			if distance < bestDistance then
				best = character
				bestDistance = distance
			end
		end
	end
	return best
end

local function updateEnemy(state: EnemyState, now: number)
	if state.Dead or state.Attacking then
		return
	end
	local data = state.Data
	local humanoid = state.Humanoid
	local root = state.Root

	-- Fell off the map / root got destroyed: count it as dead so it respawns
	if not root:IsDescendantOf(workspace) then
		humanoid.Health = 0
		return
	end

	local homeDistance = flatDistance(root.Position, state.Home)

	-- Walking home: ignore players, heal back to full on arrival
	if state.Returning then
		if homeDistance > 4 then
			humanoid:MoveTo(state.Home)
			return
		end
		state.Returning = false
		humanoid.Health = humanoid.MaxHealth
	end

	local targetRoot = getAliveRoot(state.Target)
	if targetRoot and homeDistance > data.LeashRange then
		state.Target = nil
		state.Returning = true
		state.Contributors = {}
		humanoid:MoveTo(state.Home)
		return
	end

	if not targetRoot then
		state.Target = findTarget(state)
		targetRoot = getAliveRoot(state.Target)
	end

	local target = state.Target
	if not target or not targetRoot then
		if homeDistance > 3 then
			humanoid:MoveTo(state.Home)
		end
		return
	end

	if flatDistance(targetRoot.Position, root.Position) <= data.Attack.Range then
		if now >= state.NextAttackTime then
			startAttack(state, target, targetRoot)
		else
			humanoid:MoveTo(root.Position) -- In range but on cooldown: hold position
		end
	else
		humanoid:MoveTo(targetRoot.Position)
	end
end

-- ==========================================
-- 6. PUBLIC API
-- ==========================================
-- Called by CombatServer. Returns false if the model isn't an enemy managed here (e.g. TrainingDummy)
function EnemyService.applyDamage(model: Model, amount: number, attacker: Player): boolean
	local state = enemies[model]
	if not state then
		return false
	end
	if state.Dead then
		return true
	end

	state.Contributors[attacker] = true
	-- Getting hit pulls aggro even from outside AggroRange
	if not state.Target and not state.Returning then
		state.Target = attacker.Character
	end
	state.Humanoid:TakeDamage(amount)
	return true
end

function EnemyService.start()
	for _, point in ipairs(collectSpawnPoints()) do
		spawnEnemy(point)
	end

	task.spawn(function()
		while true do
			local now = os.clock()
			for _, state in pairs(enemies) do
				local ok, err = pcall(updateEnemy, state, now)
				if not ok then
					warn("[EnemyService] AI error:", err)
				end
			end
			task.wait(AI_TICK)
		end
	end)
end

return EnemyService
