local Selection = game:GetService("Selection")

local MIN_SCALE = 1.0
local MAX_SCALE = 1.5
local SCALE_STEP = 0.05
local INNER_PART_BASE_SIZE = Vector3.new(2, 1, 2)
local OUTER_PART_BASE_SIZE = Vector3.new(1, 1.2, 2.5)

local MIN_X_TILT_DEGREES = -10
local MAX_X_TILT_DEGREES = 10

local MIN_Y_ROTATION_DEGREES = -5
local MAX_Y_ROTATION_DEGREES = 5

local MIN_Z_TILT_DEGREES = -10
local MAX_Z_TILT_DEGREES = 10

local MIN_SURFACE_COLOR_FACTOR = 0.9
local MAX_SURFACE_COLOR_FACTOR = 1.1
local SURFACE_COLOR_FACTOR_STEP = 0.05

local CRATER_REFERENCE_NAME = "Cylinder"
local MIN_INWARD_TILT_DEGREES = 5
local MAX_INWARD_TILT_DEGREES = 15

local random = Random.new()

local function hasValidSteps(minimum, maximum, step)
	return step > 0 and math.ceil(minimum / step) <= math.floor(maximum / step)
end

local function randomStep(minimum, maximum, step)
	return random:NextInteger(
		math.ceil(minimum / step),
		math.floor(maximum / step)
	) * step
end

if MIN_SCALE <= 0
	or MAX_SCALE < MIN_SCALE
	or not hasValidSteps(MIN_SCALE, MAX_SCALE, SCALE_STEP)
	or not hasValidSteps(MIN_SURFACE_COLOR_FACTOR, MAX_SURFACE_COLOR_FACTOR, SURFACE_COLOR_FACTOR_STEP)
	or MAX_X_TILT_DEGREES < MIN_X_TILT_DEGREES
	or MAX_Y_ROTATION_DEGREES < MIN_Y_ROTATION_DEGREES
	or MAX_Z_TILT_DEGREES < MIN_Z_TILT_DEGREES
	or MAX_INWARD_TILT_DEGREES < MIN_INWARD_TILT_DEGREES then
	warn("Invalid scale or tilt range")
	return
end

local parts = {}
local seen = {}
local craterReference = workspace:FindFirstChild(CRATER_REFERENCE_NAME, true)

if not craterReference or not craterReference:IsA("BasePart") then
	warn(string.format("Workspace BasePart named %q was not found", CRATER_REFERENCE_NAME))
	return
end

local craterModel = craterReference:FindFirstAncestorOfClass("Model") or craterReference.Parent
local surfaceRaycastParams = RaycastParams.new()
surfaceRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
surfaceRaycastParams.FilterDescendantsInstances = { craterModel }
surfaceRaycastParams.IgnoreWater = true

local function addPart(instance)
	local isCraterPart = instance.Name == "InnerPart" or instance.Name == "OuterPart"
	if instance:IsA("BasePart") and isCraterPart and not seen[instance] then
		seen[instance] = true
		table.insert(parts, instance)
	end
end

for _, selected in Selection:Get() do
	addPart(selected)

	for _, descendant in selected:GetDescendants() do
		addPart(descendant)
	end
end

if #parts == 0 then
	warn("Select InnerPart/OuterPart parts or their containing model")
	return
end

for _, part in parts do
	local offset = part.Position - craterReference.Position
	local radialDirection = Vector3.new(offset.X, 0, offset.Z)
	if radialDirection.Magnitude == 0 then
		continue
	end

	local outwardDirection = radialDirection.Unit
	local tangentDirection = Vector3.yAxis:Cross(outwardDirection)
	local lookDirection = if part.Name == "InnerPart"
		then -tangentDirection
		else tangentDirection
	local baseSize = if part.Name == "InnerPart" then INNER_PART_BASE_SIZE else OUTER_PART_BASE_SIZE
	part.Size = baseSize * randomStep(MIN_SCALE, MAX_SCALE, SCALE_STEP)

	local facingCFrame = CFrame.lookAt(part.Position, part.Position + lookDirection, Vector3.yAxis)

	local xTilt = math.rad(random:NextInteger(MIN_X_TILT_DEGREES, MAX_X_TILT_DEGREES))
	local yRotation = math.rad(random:NextInteger(MIN_Y_ROTATION_DEGREES, MAX_Y_ROTATION_DEGREES))
	local zTilt = math.rad(random:NextInteger(MIN_Z_TILT_DEGREES, MAX_Z_TILT_DEGREES))
	part.CFrame = facingCFrame * CFrame.Angles(xTilt, yRotation, zTilt)

	local inwardTilt = math.rad(random:NextInteger(
		MIN_INWARD_TILT_DEGREES,
		MAX_INWARD_TILT_DEGREES
	))
	local radialRotation = CFrame.fromAxisAngle(tangentDirection, -inwardTilt)
	part.CFrame = CFrame.new(part.Position) * radialRotation * part.CFrame.Rotation

	local rayOrigin = part.Position - Vector3.yAxis * (part.Size.Y / 2 + 0.05)
	local surfaceHit = workspace:Raycast(rayOrigin, -Vector3.yAxis * 500, surfaceRaycastParams)
	if surfaceHit and surfaceHit.Instance:IsA("BasePart") then
		local brightness = randomStep(
			MIN_SURFACE_COLOR_FACTOR,
			MAX_SURFACE_COLOR_FACTOR,
			SURFACE_COLOR_FACTOR_STEP
		)
		local surfaceColor = surfaceHit.Instance.Color
		part.Color = Color3.new(
			math.clamp(surfaceColor.R * brightness, 0, 1),
			math.clamp(surfaceColor.G * brightness, 0, 1),
			math.clamp(surfaceColor.B * brightness, 0, 1)
		)
	end
end

print(string.format("Randomized size and crater tilt on %d BaseParts", #parts))
