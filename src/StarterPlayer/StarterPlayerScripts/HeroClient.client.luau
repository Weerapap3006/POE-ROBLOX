-- ==========================================
-- HERO CLIENT (Hero mechanic meter above the skill bar + Stone Orbs floating around Mystics)
-- Path: StarterPlayer.StarterPlayerScripts.HeroClient
-- ==========================================
-- Only shows what the server (HeroService / PlayerData) puts in player attributes:
-- HeroClass, HeroVariant, Fury, Momentum, HeroAttackSpeed, Orbs. Shots / pulses / blocks are drawn by CombatClient
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local HeroData = require(modulesFolder:WaitForChild("HeroData"))
local Elements = require(modulesFolder:WaitForChild("Elements"))
local Ui = require(modulesFolder:WaitForChild("Ui"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
local METER_WIDTH = 260
local METER_HEIGHT = 30
local ORB_SIZE = 0.8
local ORB_RADIUS = 3 -- Studs from the character's center
local ORB_HEIGHT = 2.5
local ORB_SPIN_SPEED = 2 -- Radians per second
local WARDSTONE_COLOR = Color3.fromRGB(205, 205, 220)

local isTouchOnly = Ui.isTouchOnly()

-- ==========================================
-- 1. METER (PC: above the skill bar / mobile: above the skill buttons)
-- ==========================================
local gui = Ui.screenGui("HeroMeter", 1)
local meter = Ui.new("Frame", {
	Name = "Meter",
	AnchorPoint = if isTouchOnly then Vector2.new(1, 1) else Vector2.new(0.5, 1),
	Position = if isTouchOnly then UDim2.new(1, -24, 1, -244) else UDim2.new(0.5, 0, 1, -90),
	Size = UDim2.fromOffset(METER_WIDTH, METER_HEIGHT),
	BackgroundColor3 = Ui.Colors.Panel,
	BackgroundTransparency = 0.2,
	Visible = false,
	Parent = gui,
}, { Ui.corner(8), Ui.stroke(Ui.Colors.Stroke, 1.5) })
local title = Ui.text({
	Position = UDim2.fromOffset(8, 0),
	Size = UDim2.new(0, 96, 1, 0),
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Text = "",
	Parent = meter,
})
local barBack = Ui.new("Frame", {
	Position = UDim2.fromOffset(108, 8),
	Size = UDim2.new(1, -116, 1, -16),
	BackgroundColor3 = Ui.Colors.PanelLight,
	BorderSizePixel = 0,
	Parent = meter,
}, { Ui.corner(4) })
local barFill = Ui.new("Frame", {
	Size = UDim2.fromScale(0, 1),
	BorderSizePixel = 0,
	Parent = barBack,
}, { Ui.corner(4) })
local valueText = Ui.text({
	Size = UDim2.fromScale(1, 1),
	TextSize = 12,
	Text = "",
	ZIndex = 2,
	Parent = barBack,
})

local function renderMeter()
	local hero = HeroData.get(player:GetAttribute("HeroClass"))
	meter.Visible = hero ~= nil
	if not hero then
		return
	end
	local variant = hero.Variants[player:GetAttribute("HeroVariant") or ""]
	title.Text = if variant then string.upper(hero.Mechanic) .. " · " .. variant.Name else string.upper(hero.Mechanic)
	title.TextColor3 = hero.Color
	barFill.BackgroundColor3 = hero.Color

	local ratio, text
	if hero == HeroData.Heroes.Warrior then
		local fury = player:GetAttribute("Fury") or 0
		ratio = fury / HeroData.FURY_MAX
		local berserker = variant == hero.Variants.Berserker
		text = if berserker
			then string.format("%d  +%d%% damage", fury, math.floor(fury / 10) * HeroData.BERSERKER_DAMAGE_PER_10_FURY * 100)
			elseif fury >= HeroData.FURY_MAX then "FULL: next skill hits hard"
			else tostring(fury)
	elseif hero == HeroData.Heroes.Ranger then
		local stacks = player:GetAttribute("Momentum") or 0
		ratio = stacks / HeroData.MOMENTUM_MAX
		text = string.format("%d  +%d%% attack speed", stacks, player:GetAttribute("HeroAttackSpeed") or 0)
	else
		local orbs = player:GetAttribute("Orbs") or 0
		ratio = orbs / HeroData.ORB_MAX
		text = string.format("%d / %d orbs", orbs, HeroData.ORB_MAX)
	end
	barFill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	valueText.Text = text
end

for _, name in ipairs({ "HeroClass", "HeroVariant", "Fury", "Momentum", "HeroAttackSpeed", "Orbs" }) do
	player:GetAttributeChangedSignal(name):Connect(renderMeter)
end
renderMeter()

-- ==========================================
-- 2. STONE ORBS (every player with orbs, not just us)
-- ==========================================
local orbParts: { [Player]: { BasePart } } = {}

local function getOrbColor(owner: Player): Color3
	local variant = owner:GetAttribute("HeroVariant")
	if variant == "Stormcaller" then
		return Elements.Colors.Lightning
	elseif variant == "Wardstone" then
		return WARDSTONE_COLOR
	end
	return HeroData.Heroes.Mystic.Color
end

local function makeOrb(): BasePart
	local orb = Instance.new("Part")
	orb.Name = "StoneOrbVFX"
	orb.Shape = Enum.PartType.Ball
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanQuery = false
	orb.CanTouch = false
	orb.CastShadow = false
	orb.Material = Enum.Material.Neon
	orb.Size = Vector3.one * ORB_SIZE
	orb.Parent = workspace
	return orb
end

local function clearOrbs(owner: Player)
	for _, orb in ipairs(orbParts[owner] or {}) do
		orb:Destroy()
	end
	orbParts[owner] = nil
end

Players.PlayerRemoving:Connect(clearOrbs)

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for _, owner in ipairs(Players:GetPlayers()) do
		local count = owner:GetAttribute("Orbs") or 0
		local character = owner.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if count <= 0 or not rootPart then
			if orbParts[owner] then
				clearOrbs(owner)
			end
			continue
		end

		local orbs = orbParts[owner] or {}
		orbParts[owner] = orbs
		while #orbs < count do
			table.insert(orbs, makeOrb())
		end
		while #orbs > count do
			table.remove(orbs):Destroy()
		end

		local color = getOrbColor(owner)
		for index, orb in ipairs(orbs) do
			local angle = now * ORB_SPIN_SPEED + (index - 1) * (2 * math.pi / count)
			orb.Color = color
			orb.CFrame = CFrame.new(rootPart.Position + Vector3.new(math.cos(angle) * ORB_RADIUS, ORB_HEIGHT, math.sin(angle) * ORB_RADIUS))
		end
	end
end)
