-- ==========================================
-- UI HELPERS (Client only: used by CombatClient / HudClient / InventoryClient)
-- Path: ReplicatedStorage.Modules.Ui
-- ==========================================
-- All UI is built from code, so shared colors / fonts live here
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Ui = {}

Ui.Font = Enum.Font.GothamBold
Ui.Colors = {
	Panel = Color3.fromRGB(20, 22, 30),
	PanelLight = Color3.fromRGB(40, 44, 58),
	Stroke = Color3.fromRGB(10, 10, 14),
	Text = Color3.fromRGB(235, 235, 240),
	TextDim = Color3.fromRGB(160, 165, 180),
	Accent = Color3.fromRGB(120, 210, 255),
	Health = Color3.fromRGB(215, 50, 60),
	Exp = Color3.fromRGB(240, 190, 60),
	Warning = Color3.fromRGB(255, 120, 90),
}

-- Create an instance, set its properties and parent its children in one call:
-- Ui.new("Frame", { Size = ..., Parent = gui }, { Ui.corner(8) })
function Ui.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local target: any = instance
	local parent: Instance? = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			target[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	-- Parent last so the instance replicates / renders once, fully set up
	instance.Parent = parent
	return instance
end

local function withDefaults(defaults: { [string]: any }, props: { [string]: any }): { [string]: any }
	for key, value in pairs(props) do
		defaults[key] = value
	end
	return defaults
end

-- Text with a dark outline so it stays readable over the 3D world
function Ui.text(props: { [string]: any }, children: { Instance }?): TextLabel
	return Ui.new("TextLabel", withDefaults({
		BackgroundTransparency = 1,
		Font = Ui.Font,
		TextColor3 = Ui.Colors.Text,
		TextStrokeColor3 = Ui.Colors.Stroke,
		TextStrokeTransparency = 0.3,
		TextSize = 16,
	}, props), children)
end

function Ui.button(props: { [string]: any }, children: { Instance }?): TextButton
	return Ui.new("TextButton", withDefaults({
		BackgroundColor3 = Ui.Colors.PanelLight,
		AutoButtonColor = true,
		Font = Ui.Font,
		TextColor3 = Ui.Colors.Text,
		TextSize = 16,
	}, props), children)
end

function Ui.corner(radius: number?): UICorner
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, radius or 6) })
end

function Ui.stroke(color: Color3?, thickness: number?): UIStroke
	return Ui.new("UIStroke", {
		Color = color or Ui.Colors.Stroke,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Ui.screenGui(name: string, displayOrder: number?): ScreenGui
	return Ui.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
end

-- Phones / tablets: no mouse, so layouts move away from the thumbstick and skills auto-aim
function Ui.isTouchOnly(): boolean
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

return Ui
