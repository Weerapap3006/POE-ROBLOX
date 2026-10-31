-- ==========================================
-- LOOT (Roll random items, runes, skill stones, spirits, crafting stones and tablets + pickups on the ground,
-- everything but gear picks itself up when a player walks close)
-- Path: ServerStorage.Modules.Loot
-- ==========================================
local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ItemData = require(modulesFolder:WaitForChild("ItemData"))
local RuneData = require(modulesFolder:WaitForChild("RuneData"))
local SkillData = require(modulesFolder:WaitForChild("SkillData"))
local SpiritData = require(modulesFolder:WaitForChild("SpiritData"))
local StoneData = require(modulesFolder:WaitForChild("StoneData"))
local TabletData = require(modulesFolder:WaitForChild("TabletData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Crafting = require(script.Parent:WaitForChild("Crafting"))

-- ==========================================
-- CONFIGURATION
-- ==========================================
local DROP_LIFETIME = 90 -- Seconds before an item nobody picked up disappears
local PICKUP_DISTANCE = 10
local SCATTER = 3 -- Drops land up to this many studs from the enemy
-- Crafting stones, runes, tablets, Skill Stones and spirits fly into the bag when a player walks this close
-- (gear still needs the Pick Up prompt). Full bag = it stays on the ground with its prompt
local AUTO_PICKUP_RADIUS = 8
local AUTO_PICKUP_TICK = 0.2

-- EnemyData Drops. The *Chance values are expected counts: 0.15 = 15% for one, 1.5 = one + 50% for a second
export type DropTable = {
	Rolls: number,
	Chance: number,
	RarityWeights: { [string]: number },
	RuneChance: number?,
	SkillChance: number?,
	SpiritChance: number?,
	StoneChance: number?,
	TabletChance: number?,
}

local Loot = {}

local random = Random.new()
-- Drops on the ground that pick themselves up: CanTake = quiet "would it fit?" check, Take = the pickup
local autoDrops: { [BasePart]: { CanTake: (Player) -> boolean, Take: (Player) -> () } } = {}
local autoPickupRunning = false

local function getDropsFolder(): Instance
	local folder = workspace:FindFirstChild("Drops")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Drops"
		folder.Parent = workspace
	end
	return folder
end

local function pickWeighted(order: { string }, weights: { [string]: number }): string?
	local total = 0
	for _, key in ipairs(order) do
		total += weights[key] or 0
	end
	if total <= 0 then
		return nil
	end

	local roll = random:NextNumber() * total
	local picked: string? = nil
	for _, key in ipairs(order) do
		local weight = weights[key] or 0
		if weight > 0 then
			picked = key
			if roll < weight then
				break
			end
			roll -= weight
		end
	end
	return picked
end

-- 1.6 -> 1, plus a 60% chance of 2
local function rollCount(expected: number): number
	local whole = math.floor(expected)
	return whole + (if random:NextNumber() < expected - whole then 1 else 0)
end

-- ==========================================
-- 1. ROLL ITEMS (server only: clients must never decide loot)
-- ==========================================
function Loot.rollItem(rarity: string): ItemData.Item
	local baseIds = {}
	for baseId, base in pairs(ItemData.Bases) do
		-- Gear only: runes, tablets, Skill Stones and spirits drop on their own
		if not (base.Slot == "Rune" or base.Slot == "Tablet" or base.Slot == "Skill" or base.Slot == "Spirit") then
			table.insert(baseIds, baseId)
		end
	end
	table.sort(baseIds)

	local item: ItemData.Item = {
		Id = HttpService:GenerateGUID(false),
		Base = baseIds[random:NextInteger(1, #baseIds)],
		Rarity = rarity,
		Affixes = {},
	}
	Crafting.rerollAffixes(item)
	return item
end

-- A random stone rune (every rune equally likely)
function Loot.rollRune(): ItemData.Item
	local runeIds = {}
	for runeId in pairs(RuneData.Runes) do
		table.insert(runeIds, runeId)
	end
	table.sort(runeIds)
	return {
		Id = HttpService:GenerateGUID(false),
		Base = RuneData.getBaseId(runeIds[random:NextInteger(1, #runeIds)]),
		Rarity = "Rune",
		Affixes = {},
	}
end

-- A random Skill Stone (every skill equally likely, the starting ones too)
function Loot.rollSkillStone(): ItemData.Item
	local skillIds = {}
	for skillId in pairs(SkillData) do
		table.insert(skillIds, skillId)
	end
	table.sort(skillIds)
	return {
		Id = HttpService:GenerateGUID(false),
		Base = ItemData.getSkillStoneBase(skillIds[random:NextInteger(1, #skillIds)]),
		Rarity = "Skill",
		Affixes = {},
	}
end

-- A random Stone Spirit (every spirit equally likely)
function Loot.rollSpirit(): ItemData.Item
	local spiritIds = {}
	for spiritId in pairs(SpiritData.Spirits) do
		table.insert(spiritIds, spiritId)
	end
	table.sort(spiritIds)
	return {
		Id = HttpService:GenerateGUID(false),
		Base = SpiritData.getBaseId(spiritIds[random:NextInteger(1, #spiritIds)]),
		Rarity = "Spirit",
		Affixes = {},
	}
end

-- A Stone Tablet: rarity decides how many mods it rolls, like gear
function Loot.rollTablet(tier: number, rarity: string): ItemData.Item
	local tablet: ItemData.Item = {
		Id = HttpService:GenerateGUID(false),
		Base = "StoneTablet",
		Rarity = rarity,
		Affixes = {},
		Tier = math.clamp(tier, 1, TabletData.MAX_TIER),
	}
	Crafting.rerollAffixes(tablet)
	return tablet
end

-- ==========================================
-- 2. SPAWN A PICKUP ON THE GROUND
-- ==========================================
-- Every AUTO_PICKUP_TICK: a living player close enough to an auto-pickup drop that has room for it takes it
local function startAutoPickup()
	if autoPickupRunning then
		return
	end
	autoPickupRunning = true
	task.spawn(function()
		while true do
			task.wait(AUTO_PICKUP_TICK)
			for part, drop in pairs(autoDrops) do
				if not part.Parent then
					autoDrops[part] = nil -- Picked up by prompt, or expired
					continue
				end
				for _, player in ipairs(Players:GetPlayers()) do
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					local close = root ~= nil and (root.Position - part.Position).Magnitude <= AUTO_PICKUP_RADIUS
					if close and humanoid and humanoid.Health > 0 and drop.CanTake(player) then
						drop.Take(player)
						break
					end
				end
			end
		end
	end)
end

-- onPickup returns false when the player couldn't take it (e.g. full inventory): it stays on the ground.
-- canAutoPickup = quiet check (no message) that makes the drop pick itself up when a player walks close; nil = prompt only
local function spawnPickup(
	name: string,
	color: Color3,
	groundPosition: Vector3,
	onPickup: (player: Player) -> boolean,
	canAutoPickup: ((player: Player) -> boolean)?
)
	local scatter = Vector3.new(random:NextNumber(-SCATTER, SCATTER), 0, random:NextNumber(-SCATTER, SCATTER))

	local part = Instance.new("Part")
	part.Name = "ItemDrop"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.CFrame = CFrame.new(groundPosition + scatter + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, math.rad(45), 0)

	-- Floating name tag in the drop's color, readable from a distance
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(180, 24)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.Text = name
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.fromRGB(10, 10, 14)
	label.TextStrokeTransparency = 0
	label.Parent = billboard

	-- Pick up with E (PC) or by tapping the prompt (mobile)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PICKUP_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	local pickedUp = false
	local function take(player: Player)
		if pickedUp then
			return
		end
		if onPickup(player) then
			pickedUp = true
			autoDrops[part] = nil
			part:Destroy()
		end
	end
	prompt.Triggered:Connect(take)

	part.Parent = getDropsFolder()
	Debris:AddItem(part, DROP_LIFETIME)
	if canAutoPickup then
		autoDrops[part] = { CanTake = canAutoPickup, Take = take }
		startAutoPickup()
	end
end

-- Gear waits for the Pick Up prompt; runes, tablets, Skill Stones and spirits also pick themselves up
function Loot.dropItem(item: ItemData.Item, groundPosition: Vector3)
	local rarity = ItemData.Rarities[item.Rarity]
	local function onPickup(player: Player): boolean
		return PlayerData.addItem(player, item)
	end
	local canAutoPickup = if ItemData.isAutoPickup(item) then PlayerData.hasRoom else nil
	spawnPickup(ItemData.getName(item), rarity.Color, groundPosition, onPickup, canAutoPickup)
end

-- Crafting stones don't take an inventory slot: picking one up just adds to the player's count
function Loot.dropStone(stoneId: string, groundPosition: Vector3)
	local function onPickup(player: Player): boolean
		return PlayerData.addStone(player, stoneId, 1)
	end
	local function alwaysFits(): boolean
		return true
	end
	spawnPickup(StoneData.Stones[stoneId].Name, StoneData.COLOR, groundPosition, onPickup, alwaysFits)
end

-- ==========================================
-- 3. ENEMY DROPS
-- ==========================================
-- Rolls an enemy's drop table (EnemyData.Drops). run = the current dungeon run (DungeonRun): its tablet tier and
-- mods add loot (Quantity) and make Magic / Rare more likely (RarityBoost). extraQuantity = more loot on top
-- (0.2 = +20%, the Gem Beetle spirit of a player who helped kill it)
function Loot.rollDrops(drops: DropTable, groundPosition: Vector3, run: TabletData.Effects, isBoss: boolean, extraQuantity: number?)
	local more = 1 + run.Quantity + (extraQuantity or 0)
	local weights = table.clone(drops.RarityWeights)
	for _, rarity in ipairs({ "Magic", "Rare" }) do
		if weights[rarity] then
			weights[rarity] *= 1 + run.RarityBoost
		end
	end

	for _ = 1, rollCount(drops.Rolls * more) do
		if random:NextNumber() < drops.Chance then
			local rarity = pickWeighted(ItemData.RarityOrder, weights)
			if rarity then
				Loot.dropItem(Loot.rollItem(rarity), groundPosition)
			end
		end
	end

	for _ = 1, rollCount((drops.RuneChance or 0) * more) do
		Loot.dropItem(Loot.rollRune(), groundPosition)
	end

	for _ = 1, rollCount((drops.SkillChance or 0) * more) do
		Loot.dropItem(Loot.rollSkillStone(), groundPosition)
	end

	for _ = 1, rollCount((drops.SpiritChance or 0) * more) do
		Loot.dropItem(Loot.rollSpirit(), groundPosition)
	end

	local stoneWeights = {}
	for stoneId, stone in pairs(StoneData.Stones) do
		stoneWeights[stoneId] = stone.DropWeight
	end
	for _ = 1, rollCount((drops.StoneChance or 0) * more) do
		local stoneId = pickWeighted(StoneData.Order, stoneWeights)
		if stoneId then
			Loot.dropStone(stoneId, groundPosition)
		end
	end

	-- Tablets: plain dungeon = Tier 1, a tablet run = its tier (the boss sometimes one higher)
	for _ = 1, rollCount((drops.TabletChance or 0) * more) do
		local tier = math.max(run.Tier, 1)
		if run.Tier > 0 and isBoss and random:NextNumber() < TabletData.BOSS_TIER_UP_CHANCE then
			tier += 1
		end
		local rarity = pickWeighted(ItemData.RarityOrder, weights) or "Normal"
		Loot.dropItem(Loot.rollTablet(tier, rarity), groundPosition)
	end
end

return Loot
