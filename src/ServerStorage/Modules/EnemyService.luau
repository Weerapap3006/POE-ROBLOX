-- ==========================================
-- ENEMY SERVICE (Spawning, Chase/Attack AI, Damage, Death -> EXP, Flask Charges & Loot)
-- Path: ServerStorage.Modules.EnemyService
-- ==========================================
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EnemyData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EnemyData"))
local PlayerStats = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PlayerStats"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local PlayerResources = require(script.Parent:WaitForChild("PlayerResources"))
local Loot = require(script.Parent:WaitForChild("Loot"))

local combatRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CombatRemote") :: RemoteEvent

-- ==========================================
-- CONFIGURATION
-- ==========================================
local AI_TICK = 0.15 -- Seconds between AI decisions
local SPAWN_FOLDER_NAME = "EnemySpawns" -- Workspace folder of spawn marker parts (made in Studio)
local MELEE_REACH_BONUS = 1.5 -- A melee hit still lands if the target is this much past Range after the windup
local BOSS_CLEAR_COLOR = Color3.fromRGB(255, 215, 70)
local HEALTH_PER_EXTRA_PLAYER = 0.5 -- Each player after the first adds +50% max health to every enemy
local DROPS_FOLDER_NAME = "Drops" -- Loot's folder of items on the ground
local ALERT_TIME = 0.6 -- Seconds an enemy stands still (with a "!" over its head) after spotting a player
local EYE_HEIGHT = 1.9 -- Studs above the root center at Scale 1; players must be visible from here to be spotted
local PORTAL_STREAM_TIMEOUT = 3 -- Max seconds the dungeon portal waits for the entrance area to load on the client

-- Pathfinding: enemies walk straight at their goal unless the map blocks the way, then follow a detour
local PATH_AGENT_RADIUS = 2 -- Studs at Scale 1 (the body is ~4 studs arm to arm)
local PATH_AGENT_HEIGHT = 5 -- Studs at Scale 1, feet to top of head
local PATH_REFRESH_TIME = 1 -- Seconds before a detour can be recomputed
local PATH_GOAL_TOLERANCE = 4 -- Recompute the detour when the goal moved this far from where it leads
local WAYPOINT_REACHED = 3 -- Studs (flat) to count a detour waypoint as reached
local STEP_HEIGHT = 0.5 -- Bumps lower than this don't count as blocking the way

-- Blockout body at Scale 1. Offsets are from the HumanoidRootPart center, -Z is the front
-- Joint = Motor6D name for limbs that EnemyVisualsClient swings while walking (the rest is welded)
local ROOT_SIZE = Vector3.new(2, 2, 1)
local HIP_HEIGHT = 1.5 -- Root center floats HIP_HEIGHT + ROOT_SIZE.Y / 2 above the ground, so the legs touch it
local BODY_PARTS: { { Name: string, Size: Vector3, Offset: Vector3, IsEye: boolean, Joint: string? } } = {
	{ Name = "Body", Size = Vector3.new(2.4, 2.2, 1.6), Offset = Vector3.new(0, 0, 0), IsEye = false },
	{ Name = "Head", Size = Vector3.new(1.8, 1.5, 1.5), Offset = Vector3.new(0, 1.85, -0.1), IsEye = false },
	{ Name = "LeftEye", Size = Vector3.new(0.35, 0.3, 0.1), Offset = Vector3.new(-0.4, 1.95, -0.86), IsEye = true },
	{ Name = "RightEye", Size = Vector3.new(0.35, 0.3, 0.1), Offset = Vector3.new(0.4, 1.95, -0.86), IsEye = true },
	{ Name = "LeftArm", Size = Vector3.new(0.8, 2, 0.8), Offset = Vector3.new(-1.65, -0.2, 0), IsEye = false, Joint = "LeftShoulder" },
	{ Name = "RightArm", Size = Vector3.new(0.8, 2, 0.8), Offset = Vector3.new(1.65, -0.2, 0), IsEye = false, Joint = "RightShoulder" },
	{ Name = "LeftLeg", Size = Vector3.new(0.9, 1.4, 0.9), Offset = Vector3.new(-0.6, -1.8, 0), IsEye = false, Joint = "LeftHip" },
	{ Name = "RightLeg", Size = Vector3.new(0.9, 1.4, 0.9), Offset = Vector3.new(0.6, -1.8, 0), IsEye = false, Joint = "RightHip" },
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
	AlertUntil: number, -- Just spotted its target: stands still until this time
	Contributors: { [Player]: boolean }, -- Everyone who hit it gets the EXP
	Path: Path, -- PathfindingService path sized for this enemy's body
	Waypoints: { PathWaypoint }?, -- Current detour around obstacles (nil = walking straight)
	WaypointIndex: number,
	PathGoal: Vector3?, -- Where the current detour leads
	PathTime: number, -- When the last detour was requested
	PathBusy: boolean, -- ComputeAsync yields, so it runs in its own thread
}

local EnemyService = {}

local enemies: { [Model]: EnemyState } = {}
local spawnPointsCache: { SpawnPoint } = {}
local random = Random.new()
local healthMultiplier = 1 -- From the player count, see rescaleEnemyHealth

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

-- Raycast params that only hit the map (skips enemies, players, drops, spawn markers and non-collidable decor)
local function makeMapParams(): RaycastParams
	local ignore: { Instance } = { getEnemiesFolder() }
	for _, folderName in ipairs({ SPAWN_FOLDER_NAME, DROPS_FOLDER_NAME }) do
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

local function findGround(position: Vector3): Vector3
	local result = workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -200, 0), makeMapParams())
	return if result then result.Position else position
end

local function countPlayers(leaving: Player?): number
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= leaving then
			count += 1
		end
	end
	return count
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
-- 3. BUILD & SPAWN ENEMIES (blockout bodies, limbs swung by EnemyVisualsClient)
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

		if info.Joint then
			-- Limb pivots at its top end (shoulder / hip), so swinging Transform rotates it like a real joint
			local pivot = Vector3.new(0, info.Size.Y / 2, 0) * scale
			local joint = Instance.new("Motor6D")
			joint.Name = info.Joint
			joint.Part0 = root
			joint.Part1 = part
			joint.C0 = CFrame.new(info.Offset * scale + pivot)
			joint.C1 = CFrame.new(pivot)
			joint.Parent = part
		else
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = part
			weld.Parent = part
		end
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
	humanoid.MaxHealth = data.MaxHealth * healthMultiplier
	humanoid.Health = humanoid.MaxHealth
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
		AlertUntil = 0,
		Contributors = {},
		Path = PathfindingService:CreatePath({
			AgentRadius = PATH_AGENT_RADIUS * data.Scale,
			AgentHeight = PATH_AGENT_HEIGHT * data.Scale,
			AgentCanJump = false, -- The AI never jumps, so detours avoid ledges that need a jump
		}),
		Waypoints = nil,
		WaypointIndex = 1,
		PathGoal = nil,
		PathTime = -math.huge,
		PathBusy = false,
	}
	enemies[model] = state

	humanoid.Died:Connect(function()
		onDeath(state, point)
	end)
end

function onDeath(state: EnemyState, _point: SpawnPoint)
	if state.Dead then
		return
	end
	state.Dead = true
	local data = state.Data
	local model = state.Model

	-- EXP and flask charges go to everyone who hit it (co-op: nobody loses out on the last hit)
	local flaskCharge = if data.IsBoss then PlayerStats.FLASK_CHARGE_PER_BOSS_KILL else PlayerStats.FLASK_CHARGE_PER_KILL
	for player in pairs(state.Contributors) do
		if player.Parent then
			PlayerData.addExp(player, data.Exp)
			PlayerResources.addFlaskCharges(player, flaskCharge)
		end
	end

	Loot.rollDrops(data.Drops, findGround(state.Root.Position))

	if data.IsBoss then
		PlayerData.notify(nil, ("Dungeon Cleared! Defeated %s (Use portal to return to Lobby)"):format(data.DisplayName), BOSS_CLEAR_COLOR)
	end

	-- Fade the body out, then remove it (no auto-respawn; enemies respawn only when resetting the dungeon)
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
end

-- ==========================================
-- 4. ATTACKS (windup first, so players can see it coming and dodge)
-- ==========================================
local function damagePlayer(character: Model, amount: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or character:FindFirstChildOfClass("ForceField") then
		return -- Dead, or spawn protection
	end
	if (character:GetAttribute("InvulnerableUntil") or 0) > os.clock() then
		return -- Mid dodge roll (CombatServer sets this)
	end
	-- Players: energy shield takes the hit first (PlayerResources)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		PlayerResources.takeDamage(player, humanoid, amount)
	else
		humanoid:TakeDamage(amount)
	end
	combatRemote:FireAllClients("DamageDealt", character, amount, false)
end

-- Stops walking and turns to look at a point (flat)
local function stopAndFace(state: EnemyState, position: Vector3)
	local root = state.Root
	state.Humanoid:MoveTo(root.Position)
	local lookTarget = Vector3.new(position.X, root.Position.Y, position.Z)
	if (lookTarget - root.Position).Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, lookTarget)
	end
end

local function startAttack(state: EnemyState, target: Model, targetRoot: BasePart)
	local attack = state.Data.Attack
	local root = state.Root
	state.Attacking = true
	state.NextAttackTime = os.clock() + attack.Windup + attack.Cooldown

	-- Stop and face the target during the windup
	stopAndFace(state, targetRoot.Position)

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
-- Players behind walls go unnoticed, so enemies don't come around a corner already mid-charge
local function canSee(state: EnemyState, targetRoot: BasePart, mapParams: RaycastParams): boolean
	local eye = state.Root.Position + Vector3.new(0, EYE_HEIGHT * state.Data.Scale, 0)
	return workspace:Raycast(eye, targetRoot.Position - eye, mapParams) == nil
end

local function findTarget(state: EnemyState, mapParams: RaycastParams): Model?
	local best: Model? = nil
	local bestDistance = state.Data.AggroRange
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = getAliveRoot(character)
		if character and root then
			local distance = flatDistance(root.Position, state.Root.Position)
			if distance < bestDistance and canSee(state, root, mapParams) then
				best = character
				bestDistance = distance
			end
		end
	end
	return best
end

-- Sweeps a box the size of the body toward the goal: true when nothing on the map is in the way
local function isPathClear(state: EnemyState, goal: Vector3, mapParams: RaycastParams): boolean
	local root = state.Root
	local offset = Vector3.new(goal.X - root.Position.X, 0, goal.Z - root.Position.Z)
	if offset.Magnitude < 1 then
		return true
	end
	local scale = state.Data.Scale
	local feetY = root.Position.Y - state.Humanoid.HipHeight - root.Size.Y / 2
	local height = PATH_AGENT_HEIGHT * scale - STEP_HEIGHT
	local center = Vector3.new(root.Position.X, feetY + STEP_HEIGHT + height / 2, root.Position.Z)
	local size = Vector3.new(PATH_AGENT_RADIUS * scale * 1.5, height, 0.5)
	return workspace:Blockcast(CFrame.lookAt(center, center + offset), size, offset, mapParams) == nil
end

local function requestPath(state: EnemyState, goal: Vector3, now: number)
	state.PathBusy = true
	state.PathTime = now
	task.spawn(function()
		local ok = pcall(function()
			state.Path:ComputeAsync(state.Root.Position, goal)
		end)
		state.PathBusy = false
		if ok and state.Path.Status == Enum.PathStatus.Success then
			state.Waypoints = state.Path:GetWaypoints()
			state.WaypointIndex = 2 -- Waypoint 1 is where the enemy already stands
			state.PathGoal = goal
		else
			state.Waypoints = nil -- No way around: keeps walking straight (and retries after PATH_REFRESH_TIME)
		end
	end)
end

local function moveToward(state: EnemyState, goal: Vector3, now: number, mapParams: RaycastParams)
	local humanoid = state.Humanoid
	if isPathClear(state, goal, mapParams) then
		state.Waypoints = nil
		humanoid:MoveTo(goal)
		return
	end

	local pathGoal = state.PathGoal
	local isStale = not state.Waypoints or not pathGoal or flatDistance(pathGoal, goal) > PATH_GOAL_TOLERANCE
	if isStale and not state.PathBusy and now - state.PathTime >= PATH_REFRESH_TIME then
		requestPath(state, goal, now)
	end

	local waypoints = state.Waypoints
	local waypoint = if waypoints then waypoints[state.WaypointIndex] else nil
	while waypoints and waypoint and flatDistance(waypoint.Position, state.Root.Position) < WAYPOINT_REACHED do
		state.WaypointIndex += 1
		waypoint = waypoints[state.WaypointIndex]
	end
	if waypoint then
		humanoid:MoveTo(waypoint.Position)
	else
		state.Waypoints = nil
		humanoid:MoveTo(goal) -- Detour not ready yet (or finished): head straight for the goal
	end
end

local function updateEnemy(state: EnemyState, now: number, mapParams: RaycastParams)
	if state.Dead or state.Attacking then
		return
	end
	local data = state.Data
	local humanoid = state.Humanoid
	local root = state.Root

	-- Fell off the map / root got destroyed: count it as dead
	if not root:IsDescendantOf(workspace) then
		humanoid.Health = 0
		return
	end

	local homeDistance = flatDistance(root.Position, state.Home)

	-- Walking home: ignore players, heal back to full on arrival
	if state.Returning then
		if homeDistance > 4 then
			moveToward(state, state.Home, now, mapParams)
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
		moveToward(state, state.Home, now, mapParams)
		return
	end

	if not targetRoot then
		state.Target = findTarget(state, mapParams)
		targetRoot = getAliveRoot(state.Target)
		if targetRoot then
			-- Just spotted: freeze for a moment with a "!" so the player sees it coming before the charge
			state.AlertUntil = now + ALERT_TIME
			stopAndFace(state, targetRoot.Position)
			combatRemote:FireAllClients("EnemyAlert", state.Model, ALERT_TIME)
			return
		end
	end

	local target = state.Target
	if not target or not targetRoot then
		if homeDistance > 3 then
			moveToward(state, state.Home, now, mapParams)
		end
		return
	end

	if now < state.AlertUntil then
		return -- Still reacting to spotting the target
	end

	if flatDistance(targetRoot.Position, root.Position) <= data.Attack.Range then
		if now >= state.NextAttackTime then
			startAttack(state, target, targetRoot)
		else
			humanoid:MoveTo(root.Position) -- In range but on cooldown: hold position
		end
	else
		moveToward(state, targetRoot.Position, now, mapParams)
	end
end

-- Co-op scaling: players joined/left, so resize every living enemy's max health and keep its health %
local function rescaleEnemyHealth(playerCount: number)
	healthMultiplier = 1 + HEALTH_PER_EXTRA_PLAYER * math.max(playerCount - 1, 0)
	for _, state in pairs(enemies) do
		local humanoid = state.Humanoid
		if not state.Dead and humanoid.Health > 0 then
			local fraction = humanoid.Health / humanoid.MaxHealth
			humanoid.MaxHealth = state.Data.MaxHealth * healthMultiplier
			humanoid.Health = humanoid.MaxHealth * fraction
		end
	end
end

-- ==========================================
-- 6. DUNGEON RESET & PORTALS
-- ==========================================
function EnemyService.resetDungeon()
	-- Remove all managed enemies currently alive or fading out
	for model, state in pairs(enemies) do
		state.Dead = true
		enemies[model] = nil
		if model and model.Parent then
			model:Destroy()
		end
	end

	if #spawnPointsCache == 0 then
		spawnPointsCache = collectSpawnPoints()
	end
	for _, point in ipairs(spawnPointsCache) do
		spawnEnemy(point)
	end
end

local function setupDungeonPortals()
	local dungeonMap = workspace:FindFirstChild("DungeonMap")
	if not dungeonMap then
		return
	end

	local entrancePad = dungeonMap:FindFirstChild("DungeonEntranceSpawn") :: BasePart?
	local lobbySpawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)

	local enterPortal = dungeonMap:FindFirstChild("LobbyDungeonPortal")
	if enterPortal then
		local label = enterPortal:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			label.Text = "Dungeon Portal\n(Reset Monsters)"
		end
	end
	local enterPrompt = enterPortal and enterPortal:FindFirstChild("PortalPrompt", true) :: ProximityPrompt?
	if enterPrompt then
		enterPrompt.ObjectText = "Stage 1: Stone Valley"
		enterPrompt.ActionText = "Enter Dungeon"
		enterPrompt.Triggered:Connect(function(player: Player)
			local character = player.Character
			local root = getAliveRoot(character)
			if not character or not root then
				return
			end

			EnemyService.resetDungeon()
			local targetPos = if entrancePad then entrancePad.Position + Vector3.new(0, 4, 0) else Vector3.new(250, 4, 0)
			-- With StreamingEnabled, load the entrance area (and its enemies) on the client before arriving,
			-- otherwise enemies near the entrance pop into view already charging
			pcall(function()
				player:RequestStreamAroundAsync(targetPos, PORTAL_STREAM_TIMEOUT)
			end)
			if getAliveRoot(character) == nil or player.Character ~= character then
				return -- Died or respawned while the area was loading
			end
			character:PivotTo(CFrame.lookAt(targetPos, targetPos + Vector3.new(0, 0, -10)))

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
			PlayerResources.restoreAll(player) -- Full mana, energy shield and flasks too
			PlayerData.notify(player, "Entered Dungeon! All monsters have been reset", Color3.fromRGB(110, 215, 255))
		end)
	end

	local returnPortal = dungeonMap:FindFirstChild("DungeonReturnPortal")
	if returnPortal then
		local label = returnPortal:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			label.Text = "Return to Lobby"
		end
	end
	local returnPrompt = returnPortal and returnPortal:FindFirstChild("PortalPrompt", true) :: ProximityPrompt?
	if returnPrompt then
		returnPrompt.ObjectText = "Safe Zone"
		returnPrompt.ActionText = "Return to Lobby"
		returnPrompt.Triggered:Connect(function(player: Player)
			local character = player.Character
			local root = getAliveRoot(character)
			if not character or not root then
				return
			end

			local targetPos = if lobbySpawn then lobbySpawn.Position + Vector3.new(0, 4, 0) else Vector3.new(-40, 4, 32)
			character:PivotTo(CFrame.new(targetPos))

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
			PlayerResources.restoreAll(player) -- Full mana, energy shield and flasks too
			PlayerData.notify(player, "Returned to Safe Zone (Lobby)", Color3.fromRGB(140, 240, 160))
		end)
	end

	-- Listen for remote teleport requests (from Settings UI button)
	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	local teleportRemote = remotesFolder:WaitForChild("TeleportRemote") :: RemoteEvent
	teleportRemote.OnServerEvent:Connect(function(player: Player, destination: string)
		local character = player.Character
		local root = getAliveRoot(character)
		if not character or not root then
			return
		end

		if destination == "Lobby" then
			local targetPos = if lobbySpawn then lobbySpawn.Position + Vector3.new(0, 4, 0) else Vector3.new(-40, 4, 32)
			character:PivotTo(CFrame.new(targetPos))
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.Health = humanoid.MaxHealth
			end
			PlayerResources.restoreAll(player) -- Full mana, energy shield and flasks too
			PlayerData.notify(player, "Returned to Safe Zone (Lobby)", Color3.fromRGB(140, 240, 160))
		end
	end)
end

-- ==========================================
-- 7. PUBLIC API
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
	rescaleEnemyHealth(countPlayers())
	Players.PlayerAdded:Connect(function()
		rescaleEnemyHealth(countPlayers())
	end)
	Players.PlayerRemoving:Connect(function(leaving)
		rescaleEnemyHealth(countPlayers(leaving)) -- The leaving player is still in GetPlayers() here
	end)

	spawnPointsCache = collectSpawnPoints()
	for _, point in ipairs(spawnPointsCache) do
		spawnEnemy(point)
	end

	setupDungeonPortals()

	task.spawn(function()
		while true do
			local now = os.clock()
			local mapParams = makeMapParams() -- Rebuilt every tick: player characters change on respawn
			for _, state in pairs(enemies) do
				local ok, err = pcall(updateEnemy, state, now, mapParams)
				if not ok then
					warn("[EnemyService] AI error:", err)
				end
			end
			task.wait(AI_TICK)
		end
	end)
end

return EnemyService
