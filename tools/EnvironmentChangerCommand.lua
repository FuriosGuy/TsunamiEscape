-- Paste this file into the Roblox Studio Command Bar.
-- Use "Default" to restore the normal environment.

local TARGET_ENVIRONMENT = "Halloween"
local HOLD_MANUAL_ENVIRONMENT = true

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local environments = ReplicatedStorage:FindFirstChild("Environments")
local profile = environments and environments:FindFirstChild(TARGET_ENVIRONMENT)
if not profile or not profile:IsA("Folder") then
	warn("[EnvironmentChanger] Environment profile missing: " .. TARGET_ENVIRONMENT)
	return
end

local stateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
if RunService:IsServer() then
	if not stateFolder or not stateFolder:IsA("Folder") then
		warn("[EnvironmentChanger] LiveEventState is missing. Start a play session first.")
		return
	end

	if HOLD_MANUAL_ENVIRONMENT then
		local serverScriptService = game:GetService("ServerScriptService")
		local modules = serverScriptService:FindFirstChild("Modules")
		local liveEventModule = modules and modules:FindFirstChild("LiveEventService")
		local held = false
		if liveEventModule and liveEventModule:IsA("ModuleScript") then
			local success, liveEventService = pcall(require, liveEventModule)
			if success and type(liveEventService) == "table" and type(liveEventService.Destroy) == "function" then
				liveEventService.Destroy()
				held = true
			end
		end
		if not held then
			warn("[EnvironmentChanger] Could not stop LiveEventService; scheduler may overwrite test environment.")
		end
	end

	stateFolder:SetAttribute("EnvironmentName", TARGET_ENVIRONMENT)
	print("[EnvironmentChanger] Applied replicated environment: " .. TARGET_ENVIRONMENT)
	return
end

local modules = ReplicatedStorage:FindFirstChild("Modules")
local sharedModules = modules and modules:FindFirstChild("Shared")
local sharedConfigModule = sharedModules and sharedModules:FindFirstChild("CoreConfig_Shared")
if not sharedConfigModule or not sharedConfigModule:IsA("ModuleScript") then
	warn("[EnvironmentChanger] CoreConfig_Shared is missing.")
	return
end

local configSuccess, coreConfig = pcall(require, sharedConfigModule)
if not configSuccess or type(coreConfig) ~= "table" then
	warn("[EnvironmentChanger] Could not load CoreConfig_Shared.")
	return
end

local environmentServiceModule = modules and modules:FindFirstChild("EnvironmentService")
if not environmentServiceModule or not environmentServiceModule:IsA("ModuleScript") then
	warn("[EnvironmentChanger] EnvironmentService is missing.")
	return
end

local freshEnvironmentServiceModule = environmentServiceModule:Clone()
freshEnvironmentServiceModule.Name = "EnvironmentService_CommandBar"
freshEnvironmentServiceModule.Parent = modules
local serviceSuccess, environmentService = pcall(require, freshEnvironmentServiceModule)
freshEnvironmentServiceModule:Destroy()
if not serviceSuccess or type(environmentService) ~= "table" or type(environmentService.ApplyForStudio) ~= "function" then
	warn("[EnvironmentChanger] EnvironmentService manual API unavailable. Resync project first.")
	return
end

local ATMOSPHERE_PROPERTIES = { "Color", "Decay", "Density", "Glare", "Haze", "Offset" }

local function applyProfileClockTimeAndAtmosphere()
	local expectedClockTime = profile:GetAttribute("ClockTime")
	if typeof(expectedClockTime) == "number" then
		Lighting.ClockTime = expectedClockTime
	end

	local sourceAtmosphere = profile:FindFirstChildOfClass("Atmosphere")
	if not sourceAtmosphere then
		return
	end

	local target = Lighting:FindFirstChild(sourceAtmosphere.Name)
	if target and not target:IsA("Atmosphere") then
		warn("[EnvironmentChanger] Atmosphere name is occupied by another class: " .. sourceAtmosphere.Name)
		return
	end

	local targetAtmosphere: Atmosphere
	if target and target:IsA("Atmosphere") then
		targetAtmosphere = target
	else
		targetAtmosphere = sourceAtmosphere:Clone()
		targetAtmosphere:SetAttribute("EnvironmentServiceOwned", true)
		targetAtmosphere.Parent = Lighting
	end

	for _, propertyName in ipairs(ATMOSPHERE_PROPERTIES) do
		(targetAtmosphere :: any)[propertyName] = (sourceAtmosphere :: any)[propertyName]
	end
end

local function verifyLightingProfile(): (boolean, string)
	local expectedClockTime = profile:GetAttribute("ClockTime")
	if typeof(expectedClockTime) == "number" and math.abs(Lighting.ClockTime - expectedClockTime) > 0.001 then
		return false, "ClockTime expected=" .. tostring(expectedClockTime) .. " actual=" .. tostring(Lighting.ClockTime)
	end

	local expectedAtmosphere = profile:FindFirstChildOfClass("Atmosphere")
	if not expectedAtmosphere then
		return true, "ClockTime=" .. tostring(Lighting.ClockTime) .. " | Atmosphere profile absent"
	end

	local actualAtmosphere = Lighting:FindFirstChild(expectedAtmosphere.Name)
	if not actualAtmosphere or not actualAtmosphere:IsA("Atmosphere") then
		return false, "Atmosphere instance missing: " .. expectedAtmosphere.Name
	end

	for _, propertyName in ipairs(ATMOSPHERE_PROPERTIES) do
		if (actualAtmosphere :: any)[propertyName] ~= (expectedAtmosphere :: any)[propertyName] then
			return false, "Atmosphere." .. propertyName .. " differs from profile"
		end
	end

	return true,
		"ClockTime=" .. tostring(Lighting.ClockTime)
			.. " | Atmosphere.Color=" .. tostring(actualAtmosphere.Color)
			.. " | Density=" .. tostring(actualAtmosphere.Density)
end

local ORIGINAL_COLOR_ATTRIBUTE = "EnvironmentChangerOriginalColor"
local EVENT_DECORATION_ATTRIBUTE = "EnvironmentChangerEventDecoration"
local TREE_LEAF_SOURCE_COLOR = Color3.fromRGB(44, 101, 29)

local function matchesColor(actual: Color3, expected: Color3): boolean
	local tolerance = 1 / 255
	return math.abs(actual.R - expected.R) <= tolerance
		and math.abs(actual.G - expected.G) <= tolerance
		and math.abs(actual.B - expected.B) <= tolerance
end

local function isWithin(instance: Instance, root: Instance?): boolean
	return root ~= nil and (instance == root or instance:IsDescendantOf(root))
end

local function getOriginalColor(part: BasePart): Color3
	local savedColor = part:GetAttribute(ORIGINAL_COLOR_ATTRIBUTE)
	return if typeof(savedColor) == "Color3" then savedColor else part.Color
end

local function setPartColor(part: BasePart, color: Color3)
	if part:GetAttribute(ORIGINAL_COLOR_ATTRIBUTE) == nil then
		part:SetAttribute(ORIGINAL_COLOR_ATTRIBUTE, part.Color)
	end
	part.Color = color
end

local function getTreeName(part: BasePart, world: Instance): string?
	local ancestor = part.Parent
	while ancestor and ancestor ~= world do
		if ancestor:IsA("Model") then
			return ancestor.Name
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function applyEditModeWorldColors(world: Instance, decorations: Instance?, seasonalConfig): number
	local changedCount = 0
	local terrain = world:FindFirstChild("Terrain")
	local vipRooms = world:FindFirstChild("VIPRooms")
	local seasonalBrickColor = seasonalConfig.worldBrickColor

	for _, descendant in ipairs(world:GetDescendants()) do
		if not descendant:IsA("BasePart") then
			continue
		end

		local sourceColor = getOriginalColor(descendant)
		local targetColor: Color3? = nil
		local isVegetation = isWithin(descendant, terrain) or isWithin(descendant, vipRooms)
		if isVegetation then
			if descendant.Name == "TreeLeaves" and matchesColor(sourceColor, TREE_LEAF_SOURCE_COLOR) then
				local treeName = getTreeName(descendant, world)
				if treeName and seasonalConfig.darkPurpleTreeNames[treeName] then
					targetColor = seasonalConfig.darkPurpleTreeColor.Color
				elseif treeName and seasonalConfig.purpleTreeNames[treeName] then
					targetColor = seasonalConfig.purpleTreeColor
				elseif treeName and seasonalConfig.orangeTreeBrickColors[treeName] then
					targetColor = seasonalConfig.orangeTreeBrickColors[treeName].Color
				else
					targetColor = seasonalBrickColor.Color
				end
			elseif matchesColor(sourceColor, Color3.fromRGB(58, 125, 21)) then
				targetColor = seasonalBrickColor.Color
			end

			if targetColor then
				setPartColor(descendant, targetColor)
				changedCount += 1
			end
		end

		if decorations and (isWithin(descendant, decorations:FindFirstChild("KartShop"))
			or isWithin(descendant, decorations:FindFirstChild("EventKartShop")))
		then
			local override = seasonalConfig.kartShopBrickColors[BrickColor.new(sourceColor).Name]
			if typeof(override) == "BrickColor" then
				setPartColor(descendant, override.Color)
				changedCount += 1
			end
		end
	end

	return changedCount
end

local function restoreEditModeWorldColors(world: Instance): number
	local restoredCount = 0
	for _, descendant in ipairs(world:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local originalColor = descendant:GetAttribute(ORIGINAL_COLOR_ATTRIBUTE)
			if typeof(originalColor) == "Color3" then
				descendant.Color = originalColor
				descendant:SetAttribute(ORIGINAL_COLOR_ATTRIBUTE, nil)
				restoredCount += 1
			end
		end
	end
	return restoredCount
end

local function applyEditModeDecoration(decorations: Instance?, eventDecorationTemplate: Instance?)
	if not decorations then
		warn("[EnvironmentChanger] World1.Decorations is missing; cannot place event decor.")
		return false
	end
	if not eventDecorationTemplate or not eventDecorationTemplate:IsA("Model") then
		warn("[EnvironmentChanger] EventDecorations template missing or not a Model: " .. TARGET_ENVIRONMENT)
		return false
	end

	for _, child in ipairs(decorations:GetChildren()) do
		if child:GetAttribute("EnvironmentServiceEventDecoration") == true
			and child:GetAttribute("EnvironmentServiceEnvironmentName") == TARGET_ENVIRONMENT
		then
			return true
		end
		if child:GetAttribute(EVENT_DECORATION_ATTRIBUTE) == true then
			child:Destroy()
		end
	end

	local clone = eventDecorationTemplate:Clone()
	clone:SetAttribute(EVENT_DECORATION_ATTRIBUTE, true)
	clone:SetAttribute("EnvironmentServiceEnvironmentName", TARGET_ENVIRONMENT)
	clone.Parent = decorations
	return true
end

local function removeEditModeDecorations(decorations: Instance?)
	if not decorations then
		return
	end
	for _, child in ipairs(decorations:GetChildren()) do
		if child:GetAttribute(EVENT_DECORATION_ATTRIBUTE) == true
			or child:GetAttribute("EnvironmentServiceEventDecoration") == true
		then
			child:Destroy()
		end
	end
end

local localPlayer = Players.LocalPlayer
if localPlayer then
	localPlayer:SetAttribute("EventEnvironmentEnabled", true)
end
if stateFolder and stateFolder:IsA("Folder") then
	stateFolder:SetAttribute("EnvironmentName", TARGET_ENVIRONMENT)
end

environmentService.ApplyForStudio(TARGET_ENVIRONMENT)
applyProfileClockTimeAndAtmosphere()
local lightingVerified, lightingDetails = verifyLightingProfile()
if lightingVerified then
	print("[EnvironmentChanger] Lighting verified | " .. lightingDetails)
else
	warn("[EnvironmentChanger] Lighting profile did not apply | " .. lightingDetails)
end

local worlds = Workspace:FindFirstChild("Worlds")
local world = worlds and worlds:FindFirstChild("World1")
local decorations = world and world:FindFirstChild("Decorations")
local seasonalConfig = coreConfig.seasonalEnvironment
local changedCount = 0

if world and typeof(seasonalConfig) == "table" then
	if TARGET_ENVIRONMENT == seasonalConfig.environmentName then
		local eventDecorations = ReplicatedStorage:FindFirstChild("EventDecorations")
		local template = eventDecorations and eventDecorations:FindFirstChild(TARGET_ENVIRONMENT)
		applyEditModeDecoration(decorations, template)
		restoreEditModeWorldColors(world)
		changedCount = applyEditModeWorldColors(world, decorations, seasonalConfig)
	else
		restoreEditModeWorldColors(world)
		removeEditModeDecorations(decorations)
	end
else
	warn("[EnvironmentChanger] World1 or seasonal environment config missing; lighting still applied.")
end

print(
	"[EnvironmentChanger] Applied "
		.. TARGET_ENVIRONMENT
		.. " locally | recolored parts="
		.. tostring(changedCount)
		.. " | edit-mode particles require a Play test"
)
