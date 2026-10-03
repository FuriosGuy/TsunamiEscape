--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Exponential damping gives a quicker stop at every speed without snapping to zero.
local BRAKE_RESPONSE = 2
local OPPOSING_BRAKE_RESPONSE = 4
local MINIMUM_BRAKE_SPEED = 1
local MOVEMENT_INPUT_EPSILON = 0.05
local OPPOSING_INPUT_DOT_THRESHOLD = -0.25

local characterConnection: RBXScriptConnection? = nil
local characterRemovingConnection: RBXScriptConnection? = nil
local preSimulationConnection: RBXScriptConnection? = nil
local bindGeneration = 0

local function disconnectCharacterBindings()
	if preSimulationConnection then
		preSimulationConnection:Disconnect()
		preSimulationConnection = nil
	end
	if characterRemovingConnection then
		characterRemovingConnection:Disconnect()
		characterRemovingConnection = nil
	end
end

local function bindCharacter(character: Model)
	bindGeneration += 1
	local currentGeneration = bindGeneration
	disconnectCharacterBindings()

	local humanoid = character:WaitForChild("Humanoid", 10)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if
		currentGeneration ~= bindGeneration
		or player.Character ~= character
		or not character.Parent
		or not humanoid
		or not humanoid:IsA("Humanoid")
		or not rootPart
		or not rootPart:IsA("BasePart")
	then
		return
	end

	preSimulationConnection = RunService.PreSimulation:Connect(function(deltaTime: number)
		if not character.Parent or humanoid.Health <= 0 or rootPart.Parent ~= character then
			return
		end

		if humanoid.FloorMaterial == Enum.Material.Air then
			return
		end

		local velocity = rootPart.AssemblyLinearVelocity
		local horizontalVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		local horizontalSpeed = horizontalVelocity.Magnitude
		if horizontalSpeed <= MINIMUM_BRAKE_SPEED then
			return
		end

		local movementDirection = humanoid.MoveDirection
		local brakeResponse = BRAKE_RESPONSE
		if movementDirection.Magnitude > MOVEMENT_INPUT_EPSILON then
			local movementDot = horizontalVelocity.Unit:Dot(movementDirection.Unit)
			if movementDot > OPPOSING_INPUT_DOT_THRESHOLD then
				return
			end
			brakeResponse = OPPOSING_BRAKE_RESPONSE
		end

		local clampedDeltaTime = math.min(deltaTime, 0.1)
		local dampingAlpha = 1 - math.exp(-brakeResponse * clampedDeltaTime)
		local dampedHorizontalVelocity = horizontalVelocity:Lerp(Vector3.zero, dampingAlpha)
		rootPart.AssemblyLinearVelocity = Vector3.new(
			dampedHorizontalVelocity.X,
			velocity.Y,
			dampedHorizontalVelocity.Z
		)
	end)

	characterRemovingConnection = character.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			disconnectCharacterBindings()
		end
	end)
end

if characterConnection then
	characterConnection:Disconnect()
end
characterConnection = player.CharacterAdded:Connect(bindCharacter)

if player.Character then
	task.defer(bindCharacter, player.Character)
end

script.Destroying:Connect(function()
	bindGeneration += 1
	if characterConnection then
		characterConnection:Disconnect()
		characterConnection = nil
	end
	disconnectCharacterBindings()
end)
