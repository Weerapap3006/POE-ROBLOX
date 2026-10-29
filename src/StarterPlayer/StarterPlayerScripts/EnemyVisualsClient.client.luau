-- ==========================================
-- ENEMY VISUALS CLIENT (Enemy Walk Animation & Highlight Limit)
-- Path: StarterPlayer.StarterPlayerScripts.EnemyVisualsClient
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ==========================================
-- CONFIGURATION
-- ==========================================
local LEG_SWING = math.rad(35) -- Peak leg swing while walking
local ARM_SWING = math.rad(25) -- Arms swing opposite to the legs
local STRIDE_LENGTH = 5 -- Studs walked per full step cycle at Scale 1 (bigger enemies take longer steps)
local FULL_SWING_SPEED = 8 -- Studs/s at which the swing reaches full size

-- Roblox renders at most 31 Highlights at once and silently drops the rest, so only the nearest stay on
local MAX_HIGHLIGHTS = 31
local HIGHLIGHT_HEADROOM = 4 -- Slots kept free for slash VFX outlines created between updates
local HIGHLIGHT_UPDATE_INTERVAL = 0.2

-- ==========================================
-- 1. ENEMY WALK ANIMATION (swings the limb Motor6Ds that EnemyService builds)
-- ==========================================
type WalkRig = {
	Root: BasePart,
	Scale: number,
	LastPosition: Vector3,
	Phase: number,
	Weight: number, -- 0 = standing still, 1 = full walk swing
	LeftHip: Motor6D?,
	RightHip: Motor6D?,
	LeftShoulder: Motor6D?,
	RightShoulder: Motor6D?,
}
local walkRigs: { [Model]: WalkRig } = {}

local function findJoint(model: Model, name: string): Motor6D?
	local joint = model:FindFirstChild(name, true)
	return if joint and joint:IsA("Motor6D") then joint else nil
end

local function trackEnemy(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not root or not root:IsA("BasePart") then
		return
	end

	walkRigs[model] = {
		Root = root,
		Scale = root.Size.X / 2, -- EnemyService root is 2 studs wide at Scale 1
		LastPosition = root.Position,
		Phase = 0,
		Weight = 0,
		LeftHip = findJoint(model, "LeftHip"),
		RightHip = findJoint(model, "RightHip"),
		LeftShoulder = findJoint(model, "LeftShoulder"),
		RightShoulder = findJoint(model, "RightShoulder"),
	}
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			walkRigs[model] = nil
		end
	end)
end

local function setSwing(joint: Motor6D?, angle: number)
	if joint then
		joint.Transform = CFrame.Angles(angle, 0, 0)
	end
end

-- PreSimulation runs after the Animator, same as the player swing in CombatClient
RunService.PreSimulation:Connect(function(deltaTime: number)
	if deltaTime <= 0 then
		return
	end
	for _, rig in pairs(walkRigs) do
		-- Speed from how far the root moved this frame (works for server-owned enemies)
		local position = rig.Root.Position
		local moved = position - rig.LastPosition
		rig.LastPosition = position
		local speed = Vector3.new(moved.X, 0, moved.Z).Magnitude / deltaTime

		local targetWeight = math.clamp(speed / FULL_SWING_SPEED, 0, 1)
		rig.Weight += (targetWeight - rig.Weight) * (1 - math.exp(-10 * deltaTime))
		rig.Phase = (rig.Phase + speed * deltaTime / (STRIDE_LENGTH * rig.Scale) * math.pi * 2) % (math.pi * 2)

		local swing = math.sin(rig.Phase) * rig.Weight
		setSwing(rig.LeftHip, swing * LEG_SWING)
		setSwing(rig.RightHip, -swing * LEG_SWING)
		setSwing(rig.LeftShoulder, -swing * ARM_SWING)
		setSwing(rig.RightShoulder, swing * ARM_SWING)
	end
end)

local enemiesFolder = workspace:WaitForChild("Enemies")
enemiesFolder.ChildAdded:Connect(trackEnemy)
for _, child in ipairs(enemiesFolder:GetChildren()) do
	task.spawn(trackEnemy, child)
end

-- ==========================================
-- 2. HIGHLIGHT LIMIT (covers every Highlight: enemies, players, slash VFX)
-- ==========================================
-- Highlights are switched on/off here, so to hide one on purpose destroy it instead of setting Enabled
local managedHighlights: { [Highlight]: boolean } = {}

local function trackHighlight(instance: Instance)
	-- Only outlines that start enabled, so a Highlight someone disabled on purpose stays off
	if instance:IsA("Highlight") and instance.Enabled then
		managedHighlights[instance] = true
	end
end

local function getHighlightPosition(highlight: Highlight): Vector3?
	local target = highlight.Adornee or highlight.Parent
	if target and target:IsA("Model") then
		return target:GetPivot().Position
	elseif target and target:IsA("BasePart") then
		return target.Position
	end
	return nil
end

local function updateHighlights()
	local character = player.Character
	local characterRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local center = if characterRoot then characterRoot.Position else camera.CFrame.Position

	local ranked: { { Highlight: Highlight, Distance: number } } = {}
	for highlight in pairs(managedHighlights) do
		if not highlight.Parent then
			managedHighlights[highlight] = nil -- Destroyed
		elseif highlight:IsDescendantOf(workspace) then
			local position = getHighlightPosition(highlight)
			local distance = if position then (position - center).Magnitude else math.huge
			table.insert(ranked, { Highlight = highlight, Distance = distance })
		end
	end
	table.sort(ranked, function(a, b)
		return a.Distance < b.Distance
	end)

	for rank, entry in ipairs(ranked) do
		local shouldShow = rank <= MAX_HIGHLIGHTS - HIGHLIGHT_HEADROOM
		if entry.Highlight.Enabled ~= shouldShow then
			entry.Highlight.Enabled = shouldShow
		end
	end
end

workspace.DescendantAdded:Connect(trackHighlight)
for _, descendant in ipairs(workspace:GetDescendants()) do
	trackHighlight(descendant)
end

task.spawn(function()
	while true do
		updateHighlights()
		task.wait(HIGHLIGHT_UPDATE_INTERVAL)
	end
end)
