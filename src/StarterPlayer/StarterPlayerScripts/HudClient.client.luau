-- ==========================================
-- HUD CLIENT (Health / EXP bars, enemy health bars, boss bar, notifications, death screen)
-- Path: StarterPlayer.StarterPlayerScripts.HudClient
-- ==========================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local notifyRemote = remotesFolder:WaitForChild("NotifyRemote") :: RemoteEvent

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local Ui = require(modulesFolder:WaitForChild("Ui"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
local BOSS_BAR_RANGE = 80 -- Boss bar shows while the boss is this close
local NOTIFY_DURATION = 3.5 -- Seconds a message stays before fading
local MAX_NOTIFICATIONS = 5

local isTouchOnly = Ui.isTouchOnly()
local gui = Ui.screenGui("Hud", 0)

-- Our own health bar replaces Roblox's default one
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

-- Bar = dark background + colored fill (resize the fill with UDim2.fromScale(percent, 1)) + centered text
local function makeBar(parent: Instance, position: UDim2, size: UDim2, color: Color3): (Frame, TextLabel)
	local background = Ui.new("Frame", {
		Position = position,
		Size = size,
		BackgroundColor3 = Color3.fromRGB(15, 15, 20),
		BackgroundTransparency = 0.2,
		Parent = parent,
	}, { Ui.corner(4), Ui.stroke() })
	local fill = Ui.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Parent = background,
	}, { Ui.corner(4) })
	local label = Ui.text({
		Size = UDim2.fromScale(1, 1),
		TextSize = 14,
		Text = "",
		ZIndex = 2,
		Parent = background,
	})
	return fill, label
end

-- ==========================================
-- 1. PLAYER HEALTH & EXP (PC: bottom-left / mobile: top-left, away from the thumbstick)
-- ==========================================
local playerPanel = Ui.new("Frame", {
	Name = "PlayerPanel",
	AnchorPoint = if isTouchOnly then Vector2.new(0, 0) else Vector2.new(0, 1),
	Position = if isTouchOnly then UDim2.fromOffset(12, 8) else UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(300, 60),
	BackgroundTransparency = 1,
	Parent = gui,
})

local levelBadge = Ui.text({
	Size = UDim2.fromOffset(60, 60),
	BackgroundTransparency = 0.15,
	BackgroundColor3 = Ui.Colors.Panel,
	TextColor3 = Ui.Colors.Exp,
	TextSize = 18,
	Text = "Lv 1",
	Parent = playerPanel,
}, { Ui.corner(30), Ui.stroke(Ui.Colors.Exp, 2) })

local healthFill, healthText = makeBar(playerPanel, UDim2.fromOffset(68, 4), UDim2.fromOffset(232, 26), Ui.Colors.Health)
local expFill, expText = makeBar(playerPanel, UDim2.fromOffset(68, 36), UDim2.fromOffset(232, 18), Ui.Colors.Exp)
expText.TextSize = 12

local function updateHealth(humanoid: Humanoid)
	local maxHealth = math.max(humanoid.MaxHealth, 1)
	local health = math.clamp(humanoid.Health, 0, maxHealth)
	healthFill.Size = UDim2.fromScale(health / maxHealth, 1)
	healthText.Text = string.format("%d / %d", math.ceil(health), math.floor(maxHealth))
end

-- Level / EXP come from player attributes set by the server (PlayerData)
local function updateExp()
	local level = math.floor(player:GetAttribute("Level") or 1)
	local exp = math.floor(player:GetAttribute("Exp") or 0)
	local expToNext = math.max(math.floor(player:GetAttribute("ExpToNext") or 1), 1)
	levelBadge.Text = string.format("Lv %d", level)
	expFill.Size = UDim2.fromScale(math.clamp(exp / expToNext, 0, 1), 1)
	expText.Text = string.format("EXP %d / %d", exp, expToNext)
end

for _, attributeName in ipairs({ "Level", "Exp", "ExpToNext" }) do
	player:GetAttributeChangedSignal(attributeName):Connect(updateExp)
end
updateExp()

-- ==========================================
-- 2. DEATH SCREEN
-- ==========================================
local deathScreen = Ui.new("Frame", {
	Name = "DeathScreen",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.45,
	Visible = false,
	ZIndex = 10,
	Parent = gui,
})
Ui.text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.new(1, 0, 0, 60),
	Text = "คุณตายแล้ว",
	TextSize = 44,
	TextColor3 = Ui.Colors.Health,
	ZIndex = 11,
	Parent = deathScreen,
})
local respawnText = Ui.text({
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.new(1, 0, 0, 30),
	Text = "",
	TextSize = 22,
	ZIndex = 11,
	Parent = deathScreen,
})

local deathCount = 0
local function showDeathScreen()
	deathCount += 1
	local thisDeath = deathCount
	local respawnAt = os.clock() + Players.RespawnTime
	deathScreen.Visible = true
	task.spawn(function()
		while deathScreen.Visible and thisDeath == deathCount do
			respawnText.Text = string.format("เกิดใหม่ใน %d วินาที", math.max(0, math.ceil(respawnAt - os.clock())))
			task.wait(0.2)
		end
	end)
end

-- ==========================================
-- 3. HOOK UP THE CHARACTER (every respawn)
-- ==========================================
local characterConnections: { RBXScriptConnection } = {}

local function onCharacterAdded(character: Model)
	for _, connection in ipairs(characterConnections) do
		connection:Disconnect()
	end
	table.clear(characterConnections)
	deathScreen.Visible = false

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	local function refresh()
		updateHealth(humanoid)
	end
	refresh()
	table.insert(characterConnections, humanoid.HealthChanged:Connect(refresh))
	table.insert(characterConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh))
	table.insert(characterConnections, humanoid.Died:Connect(showDeathScreen))
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

-- ==========================================
-- 4. ENEMY HEALTH BARS (+ big boss bar at the top of the screen)
-- ==========================================
local bossFrame = Ui.new("Frame", {
	Name = "BossBar",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromOffset(0, 12) + UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(440, 46),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
local bossName = Ui.text({
	Size = UDim2.new(1, 0, 0, 20),
	TextSize = 18,
	TextColor3 = Color3.fromRGB(255, 215, 70),
	Text = "",
	Parent = bossFrame,
})
local bossFill, bossText = makeBar(bossFrame, UDim2.fromOffset(0, 22), UDim2.new(1, 0, 0, 22), Ui.Colors.Health)

local bosses: { [Model]: boolean } = {}

local function trackEnemy(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local humanoid = model:WaitForChild("Humanoid", 5)
	local root = model:WaitForChild("HumanoidRootPart", 5)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		return
	end

	if model:GetAttribute("IsBoss") then
		bosses[model] = true
		model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				bosses[model] = nil
			end
		end)
		return
	end

	-- Small bar floating above the head. Parented to the enemy so it disappears with it
	local boxCFrame, boxSize = model:GetBoundingBox()
	local headHeight = boxCFrame.Position.Y + boxSize.Y / 2 - root.Position.Y
	local billboard = Ui.new("BillboardGui", {
		Name = "HealthBar",
		Size = UDim2.new(4, 0, 0.4, 0), -- Studs
		StudsOffsetWorldSpace = Vector3.new(0, headHeight + 0.8, 0),
		AlwaysOnTop = true,
		MaxDistance = 120,
		Parent = root,
	})
	local fill, label = makeBar(billboard, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), Ui.Colors.Health)
	label.Visible = false

	local function update()
		fill.Size = UDim2.fromScale(math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1), 1)
		billboard.Enabled = humanoid.Health > 0
	end
	update()
	humanoid.HealthChanged:Connect(update)
end

local enemiesFolder = workspace:WaitForChild("Enemies")
enemiesFolder.ChildAdded:Connect(function(child)
	trackEnemy(child)
end)
for _, child in ipairs(enemiesFolder:GetChildren()) do
	task.spawn(trackEnemy, child)
end

-- Boss bar: closest living boss within range
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local myRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local shownBoss: Model? = nil
	local shownHumanoid: Humanoid? = nil
	local bestDistance = BOSS_BAR_RANGE

	if myRoot then
		for boss in pairs(bosses) do
			local humanoid = boss:FindFirstChildOfClass("Humanoid")
			local root = boss:FindFirstChild("HumanoidRootPart") :: BasePart?
			if humanoid and root and humanoid.Health > 0 then
				local distance = (root.Position - myRoot.Position).Magnitude
				if distance <= bestDistance then
					shownBoss = boss
					shownHumanoid = humanoid
					bestDistance = distance
				end
			end
		end
	end

	if shownBoss and shownHumanoid then
		bossName.Text = shownBoss:GetAttribute("DisplayName") or shownBoss.Name
		bossFill.Size = UDim2.fromScale(math.clamp(shownHumanoid.Health / shownHumanoid.MaxHealth, 0, 1), 1)
		bossText.Text = string.format("%d / %d", math.ceil(shownHumanoid.Health), math.floor(shownHumanoid.MaxHealth))
	end
	bossFrame.Visible = shownBoss ~= nil
end)

-- ==========================================
-- 5. NOTIFICATIONS (loot, level up, stage clear, warnings from the server)
-- ==========================================
local notifyList = Ui.new("Frame", {
	Name = "Notifications",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromOffset(0, 70) + UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(560, 200),
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	Ui.new("UIListLayout", {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local notifyCount = 0
local function showNotification(text: string, color: Color3?)
	notifyCount += 1
	local label = Ui.text({
		LayoutOrder = notifyCount,
		Size = UDim2.new(1, 0, 0, 28),
		Text = text,
		TextSize = 22,
		TextColor3 = color or Ui.Colors.Text,
		Parent = notifyList,
	})

	-- Too many at once: drop the oldest
	local labels = {}
	for _, child in ipairs(notifyList:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(labels, child)
		end
	end
	table.sort(labels, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	for i = 1, #labels - MAX_NOTIFICATIONS do
		labels[i]:Destroy()
	end

	task.delay(NOTIFY_DURATION, function()
		if not label.Parent then
			return
		end
		local fade = TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade:Play()
		fade.Completed:Wait()
		label:Destroy()
	end)
end

notifyRemote.OnClientEvent:Connect(showNotification)
