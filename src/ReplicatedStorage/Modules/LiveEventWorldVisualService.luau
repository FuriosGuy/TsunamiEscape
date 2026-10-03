--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)

type FrostbiteVisualConfig = {
	enabled: boolean,
	eventId: string,
	targetColor: Color3,
}

local LiveEventWorldVisualService = {}

local MODULE_NAME = "LiveEventWorldVisualService"
local FROSTBITE_EVENT_ID = "FrostbiteRally"
local WORLD_NAME = "World1"
local TREE_LEAF_SOURCE_COLOR = Color3.fromRGB(44, 101, 29)
local GRASS_SOURCE_COLOR = Color3.fromRGB(58, 125, 21)

local DEFAULT_FROSTBITE_CONFIG: FrostbiteVisualConfig = {
	enabled = true,
	eventId = FROSTBITE_EVENT_ID,
	targetColor = Color3.fromRGB(202, 203, 209),
}

local serviceMaid = Maid.new()
local stateMaid = Maid.new()
local worldMaid = Maid.new()
local originalColors: { [BasePart]: Color3 } = {}
local stateFolder: Folder? = nil
local initialized = false
local frostbiteActive = false

local function getConfig(): FrostbiteVisualConfig
	local rawConfig = CoreConfig.eventWorldVisuals
	local rawFrostbiteConfig = if typeof(rawConfig) == "table" then rawConfig.frostbiteRally else nil
	if typeof(rawFrostbiteConfig) ~= "table" then
		return DEFAULT_FROSTBITE_CONFIG
	end

	return {
		enabled = if typeof(rawFrostbiteConfig.enabled) == "boolean"
			then rawFrostbiteConfig.enabled
			else DEFAULT_FROSTBITE_CONFIG.enabled,
		eventId = if typeof(rawFrostbiteConfig.eventId) == "string"
			then rawFrostbiteConfig.eventId
			else DEFAULT_FROSTBITE_CONFIG.eventId,
		targetColor = if typeof(rawFrostbiteConfig.targetColor) == "Color3"
			then rawFrostbiteConfig.targetColor
			else DEFAULT_FROSTBITE_CONFIG.targetColor,
	}
end

local function isDescendantOf(instance: Instance, root: Instance): boolean
	return instance ~= root and instance:IsDescendantOf(root)
end

local function matchesColor(actual: Color3, expected: Color3): boolean
	local channelTolerance = 1 / 255
	return math.abs(actual.R - expected.R) <= channelTolerance
		and math.abs(actual.G - expected.G) <= channelTolerance
		and math.abs(actual.B - expected.B) <= channelTolerance
end

local function isUnderVipRooms(part: BasePart, world: Instance): boolean
	local vipRooms = world:FindFirstChild("VIPRooms")
	if vipRooms == nil then
		return false
	end

	return isDescendantOf(part, vipRooms)
end

local function isFrostbiteTarget(part: BasePart, world: Instance): boolean
	local terrain = world:FindFirstChild("Terrain")
	if terrain == nil or not isDescendantOf(part, terrain) then
		return isUnderVipRooms(part, world) and matchesColor(part.Color, GRASS_SOURCE_COLOR)
	end

	if part.Name == "TreeLeaves" and matchesColor(part.Color, TREE_LEAF_SOURCE_COLOR) then
		return true
	end

	return matchesColor(part.Color, GRASS_SOURCE_COLOR)
end

local function setFrostbiteColor(part: BasePart, targetColor: Color3)
	if originalColors[part] == nil then
		originalColors[part] = part.Color
	end

	if part.Color ~= targetColor then
		part.Color = targetColor
	end
end

local function restoreOriginalColors()
	for part, originalColor in pairs(originalColors) do
		if part.Parent ~= nil then
			part.Color = originalColor
		end
		originalColors[part] = nil
	end
end

local function applyToWorld(world: Instance)
	local config = getConfig()
	if not config.enabled then
		return
	end

	local changedCount = 0
	for _, descendant in ipairs(world:GetDescendants()) do
		if descendant:IsA("BasePart") and isFrostbiteTarget(descendant, world) then
			setFrostbiteColor(descendant, config.targetColor)
			changedCount += 1
		end
	end

	if changedCount > 0 then
		DebugModule.debugInfo(
			"Frostbite world visuals applied | world=" .. world:GetFullName() .. " | parts=" .. tostring(changedCount),
			MODULE_NAME
		)
	end
end

local function refreshWorldVisuals()
	local config = getConfig()
	local shouldBeActive = frostbiteActive and config.enabled and config.eventId == FROSTBITE_EVENT_ID
	if not shouldBeActive then
		restoreOriginalColors()
		return
	end

	local worlds = Workspace:FindFirstChild("Worlds")
	local world = worlds and worlds:FindFirstChild(WORLD_NAME)
	if world == nil then
		return
	end

	applyToWorld(world)
end

local function bindWorldFolder(worlds: Instance)
	worldMaid:DoCleaning()

	local world = worlds:FindFirstChild(WORLD_NAME)
	if world then
		worldMaid.DescendantAdded = world.DescendantAdded:Connect(function(descendant: Instance)
			if not frostbiteActive or not descendant:IsA("BasePart") then
				return
			end

			local config = getConfig()
			if config.enabled and isFrostbiteTarget(descendant, world) then
				setFrostbiteColor(descendant, config.targetColor)
			end
		end)
		worldMaid.DescendantRemoving = world.DescendantRemoving:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") then
				originalColors[descendant] = nil
			end
		end)
	end

	worldMaid.WorldAdded = worlds.ChildAdded:Connect(function(child: Instance)
		if child.Name == WORLD_NAME then
			bindWorldFolder(worlds)
			refreshWorldVisuals()
		end
	end)
	worldMaid.WorldRemoved = worlds.ChildRemoved:Connect(function(child: Instance)
		if child.Name == WORLD_NAME then
			restoreOriginalColors()
		end
	end)

	refreshWorldVisuals()
end

local function hasActiveEvent(activeEventIds: string, eventId: string): boolean
	for activeEventId in string.gmatch(activeEventIds, "[^,]+") do
		if activeEventId == eventId then
			return true
		end
	end
	return false
end

local function refreshFromState()
	if stateFolder == nil then
		return
	end

	frostbiteActive = hasActiveEvent(stateFolder:GetAttribute("ActiveEventIds") or "", FROSTBITE_EVENT_ID)
	refreshWorldVisuals()
end

local function bindStateFolder(folder: Folder)
	stateMaid:DoCleaning()
	stateFolder = folder
	stateMaid.ActiveEventIds = folder:GetAttributeChangedSignal("ActiveEventIds"):Connect(refreshFromState)
	refreshFromState()
end

function LiveEventWorldVisualService.Start()
	if initialized then
		return
	end
	initialized = true

	local worlds = Workspace:FindFirstChild("Worlds")
	if worlds then
		bindWorldFolder(worlds)
	else
		serviceMaid.WorldsAdded = Workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Worlds" then
				serviceMaid.WorldsAdded = nil
				bindWorldFolder(child)
			end
		end)
	end

	local existingState = ReplicatedStorage:FindFirstChild("LiveEventState")
	if existingState and existingState:IsA("Folder") then
		bindStateFolder(existingState)
	else
		serviceMaid.StateAdded = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
			if child.Name == "LiveEventState" and child:IsA("Folder") then
				serviceMaid.StateAdded = nil
				bindStateFolder(child)
			end
		end)
	end
end

function LiveEventWorldVisualService.Stop()
	if not initialized then
		return
	end

	initialized = false
	frostbiteActive = false
	stateMaid:DoCleaning()
	worldMaid:DoCleaning()
	serviceMaid:DoCleaning()
	stateFolder = nil
	restoreOriginalColors()
end

return LiveEventWorldVisualService
