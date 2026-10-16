--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)

type EventEnabledInstance = ParticleEmitter | Beam | Trail | Light | BillboardGui | SurfaceGui
	| ProximityPrompt | Smoke | Fire | Sparkles

local LiveEventWorldVisualService = {}
local localPlayer = Players.LocalPlayer

local MODULE_NAME = "LiveEventWorldVisualService"
local FROSTBITE_EVENT_ID = "FrostbiteRally"
local WORLD_NAME = "World1"
local TREE_LEAF_SOURCE_COLOR = Color3.fromRGB(44, 101, 29)
local GRASS_SOURCE_COLOR = Color3.fromRGB(58, 125, 21)
local EVENT_MODEL_IDS: { [string]: string } = {
	Frostbite_LuckyBlock = FROSTBITE_EVENT_ID,
	Neon_LuckyBlock = "NeonRush",
}
local EVENT_OBJECT_MODEL_NAMES: { [string]: boolean } = {
	Frostbite_LuckyBlock = true,
	Neon_LuckyBlock = true,
	EventGateCrater = true,
}

local serviceMaid = Maid.new()
local stateMaid = Maid.new()
local worldMaid = Maid.new()
local originalColors: { [BasePart]: Color3 } = {}
local originalEventTransparency: { [Instance]: number } = {}
local originalEventEnabled: { [Instance]: boolean } = {}
local stateFolder: Folder? = nil
local initialized = false

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

local function getSourceColor(part: BasePart): Color3
	return originalColors[part] or part.Color
end

local function isWorldVegetationTarget(part: BasePart, world: Instance): boolean
	local sourceColor = getSourceColor(part)
	local terrain = world:FindFirstChild("Terrain")
	if terrain == nil or not isDescendantOf(part, terrain) then
		return isUnderVipRooms(part, world) and matchesColor(sourceColor, GRASS_SOURCE_COLOR)
	end

	if part.Name == "TreeLeaves" and matchesColor(sourceColor, TREE_LEAF_SOURCE_COLOR) then
		return true
	end

	return matchesColor(sourceColor, GRASS_SOURCE_COLOR)
end

local function setPartColor(part: BasePart, targetColor: Color3)
	if originalColors[part] == nil then
		originalColors[part] = part.Color
	end

	if part.Color ~= targetColor then
		part.Color = targetColor
	end
end

local function setPartBrickColor(part: BasePart, targetColor: BrickColor)
	if originalColors[part] == nil then
		originalColors[part] = part.Color
	end

	if part.BrickColor ~= targetColor then
		part.BrickColor = targetColor
	end
end

local function isSeasonalEnvironmentActive(): boolean
	if stateFolder == nil then
		return false
	end

	local seasonalConfig = CoreConfig.seasonalEnvironment
	local environmentEnabled = localPlayer == nil or localPlayer:GetAttribute("EventEnvironmentEnabled") ~= false
	return environmentEnabled
		and typeof(seasonalConfig) == "table"
		and seasonalConfig.enabled == true
		and stateFolder:GetAttribute("SeasonalEnvironmentActive") == true
end

local function getSeasonalBrickColor(): BrickColor
	local seasonalConfig = CoreConfig.seasonalEnvironment
	if typeof(seasonalConfig) == "table" and typeof(seasonalConfig.worldBrickColor) == "BrickColor" then
		return seasonalConfig.worldBrickColor
	end

	return BrickColor.new("Neon orange")
end

local function getSeasonalTreeColors(part: BasePart): (Color3?, BrickColor?)
	local seasonalConfig = CoreConfig.seasonalEnvironment
	if typeof(seasonalConfig) ~= "table" then
		return nil, nil
	end

	local ancestor = part.Parent
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Model") then
			local treeName = ancestor.Name
			if typeof(seasonalConfig.darkPurpleTreeNames) == "table"
				and seasonalConfig.darkPurpleTreeNames[treeName] == true
				and typeof(seasonalConfig.darkPurpleTreeColor) == "BrickColor"
			then
				return nil, seasonalConfig.darkPurpleTreeColor
			end

			if typeof(seasonalConfig.purpleTreeNames) == "table"
				and seasonalConfig.purpleTreeNames[treeName] == true
				and typeof(seasonalConfig.purpleTreeColor) == "Color3"
			then
				return seasonalConfig.purpleTreeColor, nil
			end

			if typeof(seasonalConfig.orangeTreeBrickColors) == "table" then
				local orangeColor = seasonalConfig.orangeTreeBrickColors[treeName]
				if typeof(orangeColor) == "BrickColor" then
					return nil, orangeColor
				end
			end
		end
		ancestor = ancestor.Parent
	end

	return nil, nil
end

local function getSeasonalKartShopBrickColor(part: BasePart, world: Instance): BrickColor?
	local seasonalConfig = CoreConfig.seasonalEnvironment
	local colorOverrides = if typeof(seasonalConfig) == "table" then seasonalConfig.kartShopBrickColors else nil
	local decorations = world:FindFirstChild("Decorations")
	if typeof(colorOverrides) ~= "table" or decorations == nil then
		return nil
	end

	local isKartShopDecoration = false
	for _, shopName in ipairs({ "KartShop", "EventKartShop" }) do
		local shop = decorations:FindFirstChild(shopName)
		if shop and isDescendantOf(part, shop) then
			isKartShopDecoration = true
			break
		end
	end
	if not isKartShopDecoration then
		return nil
	end

	local originalColor = originalColors[part] or part.Color
	local sourceBrickColor = BrickColor.new(originalColor)
	local targetBrickColor = colorOverrides[sourceBrickColor.Name]
	return if typeof(targetBrickColor) == "BrickColor" then targetBrickColor else nil
end

local function applyWorldColorToPart(part: BasePart, world: Instance): boolean
	if isSeasonalEnvironmentActive() then
		local kartShopBrickColor = getSeasonalKartShopBrickColor(part, world)
		if kartShopBrickColor then
			setPartBrickColor(part, kartShopBrickColor)
			return true
		end
	end

	if not isWorldVegetationTarget(part, world) then
		return false
	end

	if isSeasonalEnvironmentActive() then
		local seasonalTreeColor: Color3? = nil
		local seasonalTreeBrickColor: BrickColor? = nil
		if part.Name == "TreeLeaves" then
			seasonalTreeColor, seasonalTreeBrickColor = getSeasonalTreeColors(part)
		end

		if seasonalTreeColor then
			setPartColor(part, seasonalTreeColor)
		elseif seasonalTreeBrickColor then
			setPartBrickColor(part, seasonalTreeBrickColor)
		else
			setPartBrickColor(part, getSeasonalBrickColor())
		end
	else
		return false
	end

	return true
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
	local changedCount = 0
	for _, descendant in ipairs(world:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if applyWorldColorToPart(descendant, world) then
				changedCount += 1
			else
				local originalColor = originalColors[descendant]
				if originalColor then
					descendant.Color = originalColor
					originalColors[descendant] = nil
				end
			end
		end
	end

	if changedCount > 0 then
		DebugModule.debugInfo(
			"World visuals applied | world=" .. world:GetFullName() .. " | parts=" .. tostring(changedCount),
			MODULE_NAME
		)
	end
end

local function getEventModel(instance: Instance, world: Instance): Model?
	local ancestor = instance.Parent
	while ancestor and ancestor ~= world do
		if ancestor:IsA("Model") and EVENT_OBJECT_MODEL_NAMES[ancestor.Name] then
			return ancestor
		end
		ancestor = ancestor.Parent
	end
	return nil
end

local function hasActiveEvent(activeEventIds: string, eventId: string): boolean
	for activeEventId in string.gmatch(activeEventIds, "[^,]+") do
		if activeEventId == eventId then
			return true
		end
	end
	return false
end

local function hasAnyActiveEvent(): boolean
	if stateFolder == nil then
		return false
	end

	local activeEventIds = stateFolder:GetAttribute("ActiveEventIds")
	return typeof(activeEventIds) == "string" and activeEventIds ~= ""
end

local function isVisibleEventObjectActive(model: Model): boolean
	local eventId = EVENT_MODEL_IDS[model.Name]
	if eventId then
		local activeEventIds = if stateFolder then stateFolder:GetAttribute("ActiveEventIds") else nil
		return typeof(activeEventIds) == "string" and hasActiveEvent(activeEventIds, eventId)
	end
	return model.Name == "EventGateCrater" and hasAnyActiveEvent()
end

local function setEventObjectVisible(instance: Instance, visible: boolean): ()
	if instance:IsA("BasePart") then
		local originalTransparency = originalEventTransparency[instance]
		if originalTransparency == nil then
			originalTransparency = instance.LocalTransparencyModifier
			originalEventTransparency[instance] = originalTransparency
		end
		instance.LocalTransparencyModifier = if visible then originalTransparency else 1
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		local originalTransparency = originalEventTransparency[instance]
		if originalTransparency == nil then
			originalTransparency = instance.Transparency
			originalEventTransparency[instance] = originalTransparency
		end
		instance.Transparency = if visible then originalTransparency else 1
	end
end

local function getEventEnabledInstance(instance: Instance): EventEnabledInstance?
	local supportsEnabled = instance:IsA("ParticleEmitter")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Light")
		or instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("ProximityPrompt")
		or instance:IsA("Smoke")
		or instance:IsA("Fire")
		or instance:IsA("Sparkles")
	if not supportsEnabled then
		return nil
	end
	return instance :: EventEnabledInstance
end

local function setEventObjectEnabled(instance: Instance, visible: boolean): ()
	local enabledInstance = getEventEnabledInstance(instance)
	if not enabledInstance then
		return
	end
	local originalEnabled = originalEventEnabled[instance]
	if originalEnabled == nil then
		originalEnabled = enabledInstance.Enabled
		originalEventEnabled[instance] = originalEnabled
	end
	enabledInstance.Enabled = if visible then originalEnabled else false
end

local function restoreEventObject(instance: Instance): ()
	local transparency = originalEventTransparency[instance]
	if transparency ~= nil then
		if instance:IsA("BasePart") then
			instance.LocalTransparencyModifier = transparency
		elseif instance:IsA("Decal") or instance:IsA("Texture") then
			instance.Transparency = transparency
		end
		originalEventTransparency[instance] = nil
	end

	local enabled = originalEventEnabled[instance]
	if enabled ~= nil then
		local enabledInstance = getEventEnabledInstance(instance)
		if enabledInstance then
			enabledInstance.Enabled = enabled
		end
		originalEventEnabled[instance] = nil
	end
end

local function applyEventModelVisibility(model: Model): ()
	local visible = isVisibleEventObjectActive(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		setEventObjectVisible(descendant, visible)
		setEventObjectEnabled(descendant, visible)
	end
end

local function refreshEventObjectVisibility(world: Instance): ()
	for _, descendant in ipairs(world:GetDescendants()) do
		local model = getEventModel(descendant, world)
		if model then
			local visible = isVisibleEventObjectActive(model)
			setEventObjectVisible(descendant, visible)
			setEventObjectEnabled(descendant, visible)
		else
			restoreEventObject(descendant)
		end
	end
end

local function restoreEventObjectVisibility(): ()
	for instance in pairs(originalEventTransparency) do
		if instance.Parent ~= nil then
			restoreEventObject(instance)
		else
			originalEventTransparency[instance] = nil
			originalEventEnabled[instance] = nil
		end
	end
	for instance in pairs(originalEventEnabled) do
		if instance.Parent ~= nil then
			restoreEventObject(instance)
		else
			originalEventEnabled[instance] = nil
		end
	end
end

local function refreshWorldVisuals()
	local worlds = Workspace:FindFirstChild("Worlds")
	local world = worlds and worlds:FindFirstChild(WORLD_NAME)
	if world then
		refreshEventObjectVisibility(world)
	end

	if not isSeasonalEnvironmentActive() then
		restoreOriginalColors()
		return
	end

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
			if descendant:IsA("Model") and EVENT_OBJECT_MODEL_NAMES[descendant.Name] then
				applyEventModelVisibility(descendant)
			else
				local eventModel = getEventModel(descendant, world)
				if eventModel then
					local visible = isVisibleEventObjectActive(eventModel)
					setEventObjectVisible(descendant, visible)
					setEventObjectEnabled(descendant, visible)
				end
			end
			if not descendant:IsA("BasePart") then
				return
			end

			applyWorldColorToPart(descendant, world)
		end)
		worldMaid.DescendantRemoving = world.DescendantRemoving:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") then
				originalColors[descendant] = nil
			end
			restoreEventObject(descendant)
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
			restoreEventObjectVisibility()
		end
	end)

	refreshWorldVisuals()
end

local function refreshFromState()
	if stateFolder == nil then
		return
	end

	refreshWorldVisuals()
end

local function bindStateFolder(folder: Folder)
	stateMaid:DoCleaning()
	stateFolder = folder
	stateMaid.ActiveEventIds = folder:GetAttributeChangedSignal("ActiveEventIds"):Connect(refreshFromState)
	stateMaid.EnvironmentName = folder:GetAttributeChangedSignal("EnvironmentName"):Connect(refreshFromState)
	stateMaid.SeasonalEnvironmentActive = folder:GetAttributeChangedSignal("SeasonalEnvironmentActive")
		:Connect(refreshFromState)
	if localPlayer then
		stateMaid.EventEnvironmentEnabled = localPlayer:GetAttributeChangedSignal("EventEnvironmentEnabled")
			:Connect(refreshFromState)
	end
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
	stateMaid:DoCleaning()
	worldMaid:DoCleaning()
	serviceMaid:DoCleaning()
	stateFolder = nil
	restoreOriginalColors()
	restoreEventObjectVisibility()
end

return LiveEventWorldVisualService
