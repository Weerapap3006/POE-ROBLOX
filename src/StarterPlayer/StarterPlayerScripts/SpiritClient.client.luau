-- ==========================================
-- SPIRIT CLIENT (Every Stone Spirit in a slot floats along with its player)
-- Path: StarterPlayer.StarterPlayerScripts.SpiritClient
-- ==========================================
-- Reads every player's "Spirits" attribute ("GemBeetle,,MossGolem" from PlayerData) and draws each spirit as a
-- glowing stone at its slot's spot around them. Only a look: the bonuses are applied on the server (SpiritData stats)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpiritData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SpiritData"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
-- Where each slot's spirit floats, in the character's own space (+X = right, +Y = up, +Z = behind)
local SLOT_OFFSETS: { CFrame } = {
	CFrame.new(-2.5, 3, 2), -- Slot 1: behind on the left
	CFrame.new(2.5, 3, 2), -- Slot 2: behind on the right
	CFrame.new(0, 4.2, 3), -- Slot 3: behind, a little higher
}
local FOLLOW_SPEED = 6 -- Higher = catches up faster
local BOB_HEIGHT = 0.35
local BOB_SPEED = 2.5
local CORE_SIZE = 0.8
local SHELL_SIZE = 1.4

type Follower = { SpiritId: string, Core: BasePart, Shell: BasePart }
local followers: { [Player]: { [number]: Follower } } = {} -- [player][slot]

-- Spirit id in each slot of a player ("" or unknown = empty)
local function getSpirits(owner: Player): { string }
	local text = owner:GetAttribute("Spirits")
	local slots = if type(text) == "string" then string.split(text, ",") else {}
	for slot = 1, #SLOT_OFFSETS do
		slots[slot] = if slots[slot] and SpiritData.Spirits[slots[slot]] then slots[slot] else ""
	end
	return slots
end

local function makeBall(name: string, size: number, color: Color3, material: Enum.Material, transparency: number): Part
	local ball = Instance.new("Part")
	ball.Name = name
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.CastShadow = false
	ball.Material = material
	ball.Color = color
	ball.Transparency = transparency
	ball.Size = Vector3.one * size
	ball.Parent = workspace
	return ball
end

-- A bright core inside a soft glassy shell, lit in the spirit's color
local function makeFollower(spiritId: string, position: Vector3): Follower
	local color = SpiritData.Spirits[spiritId].Color
	local core = makeBall("SpiritCoreVFX", CORE_SIZE, color, Enum.Material.Neon, 0)
	local shell = makeBall("SpiritShellVFX", SHELL_SIZE, color:Lerp(Color3.new(1, 1, 1), 0.4), Enum.Material.Glass, 0.55)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 6
	light.Brightness = 1
	light.Shadows = false
	light.Parent = core
	core.CFrame = CFrame.new(position)
	shell.CFrame = CFrame.new(position)
	return { SpiritId = spiritId, Core = core, Shell = shell }
end

local function destroyFollower(follower: Follower)
	follower.Core:Destroy()
	follower.Shell:Destroy()
end

local function removeAll(owner: Player)
	for _, follower in pairs(followers[owner] or {}) do
		destroyFollower(follower)
	end
	followers[owner] = nil
end

Players.PlayerRemoving:Connect(removeAll)

RunService.RenderStepped:Connect(function(deltaTime: number)
	local now = os.clock()
	local alpha = 1 - math.exp(-FOLLOW_SPEED * deltaTime)
	for _, owner in ipairs(Players:GetPlayers()) do
		local character = owner.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then
			removeAll(owner)
			continue
		end

		local spirits = getSpirits(owner)
		local slots = followers[owner] or {}
		followers[owner] = slots
		for slot, offset in ipairs(SLOT_OFFSETS) do
			local spiritId = spirits[slot]
			local follower = slots[slot]
			if follower and follower.SpiritId ~= spiritId then
				destroyFollower(follower) -- Slot emptied, or another spirit moved in
				slots[slot] = nil
				follower = nil
			end
			if spiritId ~= "" then
				-- Each slot bobs a little out of step with the others
				local bob = math.sin(now * BOB_SPEED + slot * 2.1) * BOB_HEIGHT
				local target = (rootPart.CFrame * offset).Position + Vector3.new(0, bob, 0)
				if not follower then
					follower = makeFollower(spiritId, target)
					slots[slot] = follower
				end
				local position = follower.Core.Position:Lerp(target, alpha)
				follower.Core.CFrame = CFrame.new(position)
				follower.Shell.CFrame = CFrame.new(position)
			end
		end
	end
end)
