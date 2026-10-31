-- ==========================================
-- SKILL CAST (Shared between Client & Server)
-- Path: ReplicatedStorage.Modules.SkillCast
-- ==========================================
-- Who a skill can hit and where Projectile / Chain skills (SkillData) land. CombatServer uses it to decide hits;
-- CombatClient uses the same rules to draw the shot or the lightning, so the picture matches what the server hits
-- (enemies can move a little in between, the server's answer is the real one)
local Players = game:GetService("Players")

local SkillCast = {}

SkillCast.PATH_HEIGHT = 6 -- Studs: how tall a projectile's path is (like the Box hit boxes)
-- Folders a projectile flies through (enemies are found separately, drops / spawn markers never block)
local PASS_THROUGH_FOLDERS = { "Enemies", "Drops", "EnemySpawns" }

-- Unique living enemy models among the parts (players are skipped: co-op, no friendly fire)
function SkillCast.collectEnemies(parts: { BasePart }, ignore: Model?): { [Model]: Humanoid }
	local enemies: { [Model]: Humanoid } = {}
	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and model ~= ignore and not enemies[model] and not Players:GetPlayerFromCharacter(model) then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				enemies[model] = humanoid
			end
		end
	end
	return enemies
end

-- Raycast params that only hit the map: walls stop projectiles, players / enemies / drops / see-through decor don't
function SkillCast.getMapParams(): RaycastParams
	local ignore: { Instance } = {}
	for _, name in ipairs(PASS_THROUGH_FOLDERS) do
		local folder = workspace:FindFirstChild(name)
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
	params.RespectCanCollide = true -- CanCollide = false decor (and every VFX part) doesn't block
	return params
end

-- A projectile from origin along a flat unit direction: flies until the first enemy in its path, a wall or its range.
-- Returns where it lands, how far that is, and the enemy it hit (nil = wall / max range)
function SkillCast.castProjectile(origin: Vector3, direction: Vector3, range: number, width: number, ignore: Model?): (Vector3, number, Model?)
	local distance = range
	local wall = workspace:Raycast(origin, direction * range, SkillCast.getMapParams())
	if wall then
		distance = (wall.Position - origin).Magnitude
	end

	local target: Model? = nil
	local targetDistance = distance
	if distance > 0.1 then
		local pathCFrame = CFrame.lookAt(origin, origin + direction) * CFrame.new(0, 0, -distance / 2)
		local overlap = OverlapParams.new()
		overlap.FilterType = Enum.RaycastFilterType.Exclude
		overlap.FilterDescendantsInstances = if ignore then { ignore } else {}
		local parts = workspace:GetPartBoundsInBox(pathCFrame, Vector3.new(width, SkillCast.PATH_HEIGHT, distance), overlap)
		for model in pairs(SkillCast.collectEnemies(parts, ignore)) do
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local along = math.max((root.Position - origin):Dot(direction), 0)
				if along < targetDistance then
					targetDistance = along
					target = model
				end
			end
		end
	end
	return origin + direction * targetDistance, targetDistance, target
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Chain skills: the living enemy nearest the aim point (no further than range from the caster), then up to
-- `chains` more, each the nearest not-yet-hit enemy within chainRange of the last one. Returns them in order
function SkillCast.findChain(origin: Vector3, aimPoint: Vector3, range: number, chains: number, chainRange: number): { Model }
	local enemies: { { Model: Model, Position: Vector3 } } = {}
	local folder = workspace:FindFirstChild("Enemies")
	for _, model in ipairs(if folder then folder:GetChildren() else {}) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if model:IsA("Model") and humanoid and root and humanoid.Health > 0 then
			table.insert(enemies, { Model = model, Position = root.Position })
		end
	end

	local targets: { Model } = {}
	local used: { [Model]: boolean } = {}
	local function nearest(from: Vector3, maxFromCaster: number?, maxFromPoint: number?): { Model: Model, Position: Vector3 }?
		local best, bestDistance = nil, math.huge
		for _, enemy in ipairs(enemies) do
			local distance = flatDistance(from, enemy.Position)
			local inRange = (maxFromCaster == nil or flatDistance(origin, enemy.Position) <= maxFromCaster)
				and (maxFromPoint == nil or distance <= maxFromPoint)
			if not used[enemy.Model] and inRange and distance < bestDistance then
				best, bestDistance = enemy, distance
			end
		end
		return best
	end

	local current = nearest(aimPoint, range, nil)
	while current and #targets <= chains do
		table.insert(targets, current.Model)
		used[current.Model] = true
		current = nearest(current.Position, nil, chainRange)
	end
	return targets
end

return SkillCast
