local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ==========================================
-- CAMERA CONFIGURATION (2.5D Isometric / ARPG)
-- ==========================================
-- Base direction vector for the isometric angle (X, Y, Z)
local BASE_OFFSET = Vector3.new(25, 35, 25)
local CAMERA_DIRECTION = BASE_OFFSET.Unit

-- Lower Field of View (FOV) flattens perspective for a more authentic 2.5D isometric feel (default is 70)
local FIELD_OF_VIEW = 40

-- Zoom Settings (Distance in studs along CAMERA_DIRECTION)
local DEFAULT_ZOOM_DISTANCE = BASE_OFFSET.Magnitude -- ~50 studs
local MIN_ZOOM_DISTANCE = 20
local MAX_ZOOM_DISTANCE = 50
local ZOOM_STEP = 6 -- How much each scroll wheel tick changes target zoom

-- Smoothing speeds (higher = faster/snappier, lower = smoother/floatier)
local FOLLOW_SMOOTH_SPEED = 12
local ZOOM_SMOOTH_SPEED = 10

-- ==========================================
-- STATE VARIABLES
-- ==========================================
local targetZoomDistance = DEFAULT_ZOOM_DISTANCE
local currentZoomDistance = DEFAULT_ZOOM_DISTANCE
local currentTargetPosition: Vector3? = nil

-- ==========================================
-- INPUT HANDLING (ZOOM IN / ZOOM OUT)
-- ==========================================
UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		-- Scroll up (Position.Z > 0) zooms in, Scroll down (Position.Z < 0) zooms out
		local scrollDelta = input.Position.Z
		targetZoomDistance = math.clamp(
			targetZoomDistance - (scrollDelta * ZOOM_STEP),
			MIN_ZOOM_DISTANCE,
			MAX_ZOOM_DISTANCE
		)
	end
end)

-- Also support Pinch-to-Zoom on trackpads/touch devices
local pinchStartDistance = DEFAULT_ZOOM_DISTANCE
UserInputService.TouchPinch:Connect(function(_touchPositions, scale: number, _velocity, state: Enum.UserInputState, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if state == Enum.UserInputState.Begin then
		pinchStartDistance = targetZoomDistance
	elseif state == Enum.UserInputState.Change and scale > 0 then
		targetZoomDistance = math.clamp(pinchStartDistance / scale, MIN_ZOOM_DISTANCE, MAX_ZOOM_DISTANCE)
	end
end)

-- ==========================================
-- CAMERA UPDATE LOGIC
-- ==========================================
local function setupCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FIELD_OF_VIEW
end

local function updateCamera(deltaTime: number)
	-- Ensure CameraType stays Scriptable so players cannot rotate camera manually
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	local desiredTargetPosition = rootPart.Position

	-- Initialize immediately on first frame or after respawn
	if not currentTargetPosition then
		currentTargetPosition = desiredTargetPosition
	else
		-- Frame-rate independent exponential smoothing for position tracking
		local followAlpha = 1 - math.exp(-FOLLOW_SMOOTH_SPEED * deltaTime)
		currentTargetPosition = currentTargetPosition:Lerp(desiredTargetPosition, followAlpha)
	end

	-- Frame-rate independent exponential smoothing for zooming
	local zoomAlpha = 1 - math.exp(-ZOOM_SMOOTH_SPEED * deltaTime)
	currentZoomDistance = currentZoomDistance + (targetZoomDistance - currentZoomDistance) * zoomAlpha

	-- Calculate final camera position using smoothed target and smoothed zoom distance
	local cameraOffset = CAMERA_DIRECTION * currentZoomDistance
	local cameraPosition = currentTargetPosition + cameraOffset

	-- Lock camera at cameraPosition looking directly at currentTargetPosition
	camera.CFrame = CFrame.lookAt(cameraPosition, currentTargetPosition)
	camera.Focus = CFrame.new(currentTargetPosition)
end

-- Initialize camera settings
setupCamera()

-- Bind to RenderStep at Camera priority so movement and zoom are completely smooth
RunService:BindToRenderStep("IsometricCameraLock", Enum.RenderPriority.Camera.Value + 1, updateCamera)

-- Re-apply camera settings and snap to character if the character respawns
player.CharacterAdded:Connect(function(character)
	local rootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if rootPart then
		currentTargetPosition = rootPart.Position
	end
	setupCamera()
end)
