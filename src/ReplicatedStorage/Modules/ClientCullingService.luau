local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local ClientDeviceProfile = require(ReplicatedStorage.Modules.ClientDeviceProfile)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)

type SupportedCullInstance = Instance

type CullState = {
	wasCulled: boolean,
	previousEnabled: boolean?,
	previousLocalTransparencyModifier: number?,
	previousCastShadow: boolean?,
	previousRate: number?,
	wasRateReduced: boolean,
}

type CullConfig = {
	enabled: boolean,
	updateInterval: number,
	mobileDistanceMultiplier: number,
	mobileParticleDistanceMultiplier: number,
	mobileParticleReducedRateMultiplier: number,
	autoTagBillboards: boolean,
	autoTagSurfaceGuis: boolean,
	autoTagDecorativeEffects: boolean,
	autoTagDecorativeTextures: boolean,
	billboardDistance: number,
	surfaceGuiDistance: number,
	particleDistance: number,
	particleReducedDistance: number,
	particleReducedRateMultiplier: number,
	cullHysteresisDistance: number,
	lightDistance: number,
	beamDistance: number,
	trailDistance: number,
	textureDistance: number,
	autoCullDecorativeShadows: boolean,
	shadowDistance: number,
}

local ClientCullingService = {}

ClientCullingService.Tags = table.freeze({
	Billboard = "ClientCullableBillboard",
	SurfaceGui = "ClientCullableSurfaceGui",
	Particle = "ClientCullableParticle",
	Light = "ClientCullableLight",
	Beam = "ClientCullableBeam",
	Trail = "ClientCullableTrail",
	Texture = "ClientCullableTexture",
	Decal = "ClientCullableDecal",
	Shadow = "ClientCullableShadow",
})

local DEFAULT_CONFIG: CullConfig = {
	enabled = true,
	updateInterval = 0.25,
	mobileDistanceMultiplier = 0.65,
	mobileParticleDistanceMultiplier = 0.5,
	mobileParticleReducedRateMultiplier = 0.4,
	autoTagBillboards = true,
	autoTagSurfaceGuis = true,
	autoTagDecorativeEffects = true,
	autoTagDecorativeTextures = true,
	billboardDistance = 300,
	surfaceGuiDistance = 300,
	particleDistance = 180,
	particleReducedDistance = 120,
	particleReducedRateMultiplier = 0.55,
	cullHysteresisDistance = 20,
	lightDistance = 220,
	beamDistance = 250,
	trailDistance = 200,
	textureDistance = 600,
	autoCullDecorativeShadows = true,
	shadowDistance = 400,
}

local MAX_INSTANCES_PER_TAG_UPDATE = 128 -- Spread large tagged sets across successive culling passes.

local serviceMaid = Maid.new()
local instanceStates: { [Instance]: CullState } = {}
local taggedInstances: { [string]: { [Instance]: boolean } } = {}
local taggedInstanceCursors: { [string]: Instance? } = {}
local playerCharacterModels: { [Model]: boolean } = {}
local playerCharacterConnections: { [Player]: { RBXScriptConnection } } = {}
local localShadowLights: { [Light]: boolean } = {}
local localShadowLightConnections: { [Light]: RBXScriptConnection } = {}
local localShadowLightCount = 0
local shadowCullingActive = false
local shadowRestorePending = false
local heartbeatConnection: RBXScriptConnection? = nil
local updateAccumulator = 0
local isRunning = false

local function readNumber(value: any, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end

	return math.max(0, value)
end

local function readBoolean(value: any, fallback: boolean): boolean
	if typeof(value) ~= "boolean" then
		return fallback
	end

	return value
end

local function getConfig(): CullConfig
	local rawConfig = CoreConfig.clientCulling
	if typeof(rawConfig) ~= "table" then
		return table.clone(DEFAULT_CONFIG)
	end

	return {
		enabled = readBoolean(rawConfig.enabled, DEFAULT_CONFIG.enabled),
		updateInterval = math.max(0.05, readNumber(rawConfig.updateInterval, DEFAULT_CONFIG.updateInterval)),
		mobileDistanceMultiplier = math.clamp(
			readNumber(rawConfig.mobileDistanceMultiplier, DEFAULT_CONFIG.mobileDistanceMultiplier),
			0.1,
			1
		),
		mobileParticleDistanceMultiplier = math.clamp(
			readNumber(
				rawConfig.mobileParticleDistanceMultiplier,
				DEFAULT_CONFIG.mobileParticleDistanceMultiplier
			),
			0.1,
			1
		),
		mobileParticleReducedRateMultiplier = math.clamp(
			readNumber(
				rawConfig.mobileParticleReducedRateMultiplier,
				DEFAULT_CONFIG.mobileParticleReducedRateMultiplier
			),
			0.1,
			1
		),
		autoTagBillboards = readBoolean(rawConfig.autoTagBillboards, DEFAULT_CONFIG.autoTagBillboards),
		autoTagSurfaceGuis = readBoolean(rawConfig.autoTagSurfaceGuis, DEFAULT_CONFIG.autoTagSurfaceGuis),
		autoTagDecorativeEffects = readBoolean(
			rawConfig.autoTagDecorativeEffects,
			DEFAULT_CONFIG.autoTagDecorativeEffects
		),
		autoTagDecorativeTextures = readBoolean(
			rawConfig.autoTagDecorativeTextures,
			DEFAULT_CONFIG.autoTagDecorativeTextures
		),
		billboardDistance = readNumber(rawConfig.billboardDistance, DEFAULT_CONFIG.billboardDistance),
		surfaceGuiDistance = readNumber(rawConfig.surfaceGuiDistance, DEFAULT_CONFIG.surfaceGuiDistance),
		particleDistance = readNumber(rawConfig.particleDistance, DEFAULT_CONFIG.particleDistance),
		particleReducedDistance = readNumber(rawConfig.particleReducedDistance, DEFAULT_CONFIG.particleReducedDistance),
		particleReducedRateMultiplier = math.clamp(
			readNumber(rawConfig.particleReducedRateMultiplier, DEFAULT_CONFIG.particleReducedRateMultiplier),
			0.1,
			1
		),
		cullHysteresisDistance = readNumber(rawConfig.cullHysteresisDistance, DEFAULT_CONFIG.cullHysteresisDistance),
		lightDistance = readNumber(rawConfig.lightDistance, DEFAULT_CONFIG.lightDistance),
		beamDistance = readNumber(rawConfig.beamDistance, DEFAULT_CONFIG.beamDistance),
		trailDistance = readNumber(rawConfig.trailDistance, DEFAULT_CONFIG.trailDistance),
		textureDistance = readNumber(rawConfig.textureDistance, DEFAULT_CONFIG.textureDistance),
		autoCullDecorativeShadows = readBoolean(
			rawConfig.autoCullDecorativeShadows,
			DEFAULT_CONFIG.autoCullDecorativeShadows
		),
		shadowDistance = readNumber(rawConfig.shadowDistance, DEFAULT_CONFIG.shadowDistance),
	}
end

local function getDistanceMultiplier(config: CullConfig, isParticle: boolean): number
	if not ClientDeviceProfile.IsMobile() then
		return 1
	end

	return if isParticle then config.mobileParticleDistanceMultiplier else config.mobileDistanceMultiplier
end

local function getParticleReducedRateMultiplier(config: CullConfig): number
	return if ClientDeviceProfile.IsMobile()
		then config.mobileParticleReducedRateMultiplier
		else config.particleReducedRateMultiplier
end

local function refreshLocalShadowLight(light: Light)
	local shouldTrack = light.Shadows
	local wasTracked = localShadowLights[light] == true
	if shouldTrack and not wasTracked then
		localShadowLights[light] = true
		localShadowLightCount += 1
	elseif not shouldTrack and wasTracked then
		localShadowLights[light] = nil
		localShadowLightCount = math.max(localShadowLightCount - 1, 0)
	end
end

local function untrackLocalShadowLight(light: Light)
	if localShadowLights[light] then
		localShadowLights[light] = nil
		localShadowLightCount = math.max(localShadowLightCount - 1, 0)
	end

	local connection = localShadowLightConnections[light]
	if connection then
		connection:Disconnect()
		localShadowLightConnections[light] = nil
	end
end

local function trackLocalShadowLight(light: Light)
	if localShadowLightConnections[light] then
		refreshLocalShadowLight(light)
		return
	end

	localShadowLightConnections[light] = light:GetPropertyChangedSignal("Shadows"):Connect(function()
		refreshLocalShadowLight(light)
	end)
	refreshLocalShadowLight(light)
end

local function bindLocalShadowLightTracking()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Light") then
			trackLocalShadowLight(descendant)
		end
	end

	serviceMaid:GiveTask(Workspace.DescendantAdded:Connect(function(instance)
		if instance:IsA("Light") then
			trackLocalShadowLight(instance)
		end
	end))
	serviceMaid:GiveTask(Workspace.DescendantRemoving:Connect(function(instance)
		if instance:IsA("Light") then
			untrackLocalShadowLight(instance)
		end
	end))
	serviceMaid:GiveTask(function()
		for light in pairs(localShadowLightConnections) do
			untrackLocalShadowLight(light)
		end
		localShadowLightCount = 0
	end)
end

local function shouldCullDecorativeShadows(config: CullConfig): boolean
	return config.autoCullDecorativeShadows and (Lighting.GlobalShadows or localShadowLightCount > 0)
end

local function untrackPlayerCharacter(player: Player): ()
	local character = player.Character
	if character then
		playerCharacterModels[character] = nil
	end

	local connections = playerCharacterConnections[player]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		playerCharacterConnections[player] = nil
	end
end

local function trackPlayerCharacter(player: Player): ()
	if playerCharacterConnections[player] then
		return
	end

	local connections: { RBXScriptConnection } = {}
	playerCharacterConnections[player] = connections
	local character = player.Character
	if character then
		playerCharacterModels[character] = true
	end
	table.insert(connections, player.CharacterAdded:Connect(function(character: Model)
		playerCharacterModels[character] = true
	end))
	table.insert(connections, player.CharacterRemoving:Connect(function(character: Model)
		playerCharacterModels[character] = nil
	end))
end

local function bindPlayerCharacterTracking(): ()
	for _, player in ipairs(Players:GetPlayers()) do
		trackPlayerCharacter(player)
	end
	serviceMaid:GiveTask(Players.PlayerAdded:Connect(trackPlayerCharacter))
	serviceMaid:GiveTask(Players.PlayerRemoving:Connect(untrackPlayerCharacter))
	serviceMaid:GiveTask(function()
		for _, connections in pairs(playerCharacterConnections) do
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
		end
		table.clear(playerCharacterConnections)
		table.clear(playerCharacterModels)
	end)
end

local function getBasePartPosition(instance: Instance): Vector3?
	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("Attachment") then
		return instance.WorldPosition
	end

	local ancestorPart = instance:FindFirstAncestorWhichIsA("BasePart")
	if ancestorPart and ancestorPart:IsA("BasePart") then
		return ancestorPart.Position
	end

	return nil
end

local function getModelPosition(model: Model): Vector3?
	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if ok then
		return pivot.Position
	end

	return nil
end

local function getInstanceOrAncestorPosition(instance: Instance): Vector3?
	local directPosition = getBasePartPosition(instance)
	if directPosition then
		return directPosition
	end

	if instance:IsA("Model") then
		return getModelPosition(instance)
	end

	local parent = instance.Parent
	if parent then
		local parentPosition = getBasePartPosition(parent)
		if parentPosition then
			return parentPosition
		end
		if parent:IsA("Model") then
			return getModelPosition(parent)
		end
	end

	local ancestorModel = instance:FindFirstAncestorWhichIsA("Model")
	if ancestorModel then
		return getModelPosition(ancestorModel)
	end

	return nil
end

local function getBillboardPosition(billboardGui: BillboardGui): Vector3?
	local adornee = billboardGui.Adornee
	if adornee then
		return getInstanceOrAncestorPosition(adornee)
	end

	return getInstanceOrAncestorPosition(billboardGui)
end

local function getSurfaceGuiPosition(surfaceGui: SurfaceGui): Vector3?
	local adornee = surfaceGui.Adornee
	if adornee then
		return getInstanceOrAncestorPosition(adornee)
	end

	return getInstanceOrAncestorPosition(surfaceGui)
end

local function getBeamPosition(beam: Beam): Vector3?
	local attachment0 = beam.Attachment0
	local attachment1 = beam.Attachment1
	if attachment0 and attachment1 then
		return (attachment0.WorldPosition + attachment1.WorldPosition) * 0.5
	end
	if attachment0 then
		return attachment0.WorldPosition
	end
	if attachment1 then
		return attachment1.WorldPosition
	end

	return getBasePartPosition(beam)
end

local function isSupportedForTag(tag: string, instance: Instance): boolean
	if tag == ClientCullingService.Tags.Billboard then
		return instance:IsA("BillboardGui")
	elseif tag == ClientCullingService.Tags.SurfaceGui then
		return instance:IsA("SurfaceGui")
	elseif tag == ClientCullingService.Tags.Particle then
		return instance:IsA("ParticleEmitter")
	elseif tag == ClientCullingService.Tags.Light then
		return instance:IsA("Light")
	elseif tag == ClientCullingService.Tags.Beam then
		return instance:IsA("Beam")
	elseif tag == ClientCullingService.Tags.Trail then
		return instance:IsA("Trail")
	elseif tag == ClientCullingService.Tags.Texture then
		return instance:IsA("Texture")
	elseif tag == ClientCullingService.Tags.Decal then
		return instance:IsA("Decal")
	elseif tag == ClientCullingService.Tags.Shadow then
		return instance:IsA("BasePart")
	end

	return false
end

local function getInstancePositionForTag(tag: string, instance: Instance): Vector3?
	if tag == ClientCullingService.Tags.Billboard and instance:IsA("BillboardGui") then
		return getBillboardPosition(instance)
	elseif tag == ClientCullingService.Tags.SurfaceGui and instance:IsA("SurfaceGui") then
		return getSurfaceGuiPosition(instance)
	elseif tag == ClientCullingService.Tags.Beam and instance:IsA("Beam") then
		return getBeamPosition(instance)
	elseif tag == ClientCullingService.Tags.Shadow and instance:IsA("BasePart") then
		return instance.Position
	end

	local parent = instance.Parent
	if parent then
		return getInstanceOrAncestorPosition(parent)
	end

	return nil
end

local function getCullDistanceForTag(tag: string, config: CullConfig): number
	if tag == ClientCullingService.Tags.Billboard then
		return config.billboardDistance
	elseif tag == ClientCullingService.Tags.SurfaceGui then
		return config.surfaceGuiDistance
	elseif tag == ClientCullingService.Tags.Particle then
		return config.particleDistance
	elseif tag == ClientCullingService.Tags.Light then
		return config.lightDistance
	elseif tag == ClientCullingService.Tags.Beam then
		return config.beamDistance
	elseif tag == ClientCullingService.Tags.Trail then
		return config.trailDistance
	elseif tag == ClientCullingService.Tags.Texture or tag == ClientCullingService.Tags.Decal then
		return config.textureDistance
	elseif tag == ClientCullingService.Tags.Shadow then
		return config.shadowDistance
	end

	return 0
end

local function isTransparencyCullable(instance: SupportedCullInstance): boolean
	return instance:IsA("Texture") or instance:IsA("Decal")
end

local function isShadowCullable(instance: SupportedCullInstance): boolean
	return instance:IsA("BasePart")
end

local function getEnabled(instance: SupportedCullInstance): boolean
	return (instance :: any).Enabled == true
end

local function setEnabled(instance: SupportedCullInstance, enabled: boolean)
	(instance :: any).Enabled = enabled
end

local function restoreInstance(instance: Instance)
	local state = instanceStates[instance]
	if not state then
		return
	end

	if state.wasCulled and instance.Parent ~= nil then
		if isTransparencyCullable(instance :: SupportedCullInstance) then
			local previousTransparency = state.previousLocalTransparencyModifier
			if previousTransparency ~= nil and (instance:IsA("Texture") or instance:IsA("Decal")) then
				instance.LocalTransparencyModifier = previousTransparency
			end
		elseif isShadowCullable(instance :: SupportedCullInstance) then
			local previousCastShadow = state.previousCastShadow
			if previousCastShadow ~= nil and instance:IsA("BasePart") then
				instance.CastShadow = previousCastShadow
			end
		elseif state.previousEnabled ~= nil then
			setEnabled(instance :: SupportedCullInstance, state.previousEnabled)
		end
	end

	if state.wasRateReduced and state.previousRate ~= nil and instance:IsA("ParticleEmitter") then
		instance.Rate = state.previousRate
	end

	instanceStates[instance] = nil
end

local function applyCullState(instance: SupportedCullInstance, shouldCull: boolean, particleRateMultiplier: number?)
	local state = instanceStates[instance]
	if not state then
		state = {
			wasCulled = false,
			previousEnabled = nil,
			previousLocalTransparencyModifier = nil,
			previousCastShadow = nil,
			previousRate = nil,
			wasRateReduced = false,
		}
		instanceStates[instance] = state
	end

	if shouldCull then
		if not state.wasCulled then
			if instance:IsA("Texture") or instance:IsA("Decal") then
				state.previousLocalTransparencyModifier = instance.LocalTransparencyModifier
			elseif instance:IsA("BasePart") then
				state.previousCastShadow = instance.CastShadow
			else
				state.previousEnabled = getEnabled(instance)
			end
			state.wasCulled = true
		end

		if state.wasRateReduced and state.previousRate ~= nil and instance:IsA("ParticleEmitter") then
			instance.Rate = state.previousRate
			state.previousRate = nil
			state.wasRateReduced = false
		end
		if instance:IsA("Texture") or instance:IsA("Decal") then
			instance.LocalTransparencyModifier = 1
		elseif instance:IsA("BasePart") then
			instance.CastShadow = false
		else
			setEnabled(instance, false)
		end
		return
	end

	if state.wasCulled then
		if (instance:IsA("Texture") or instance:IsA("Decal")) and state.previousLocalTransparencyModifier ~= nil then
			instance.LocalTransparencyModifier = state.previousLocalTransparencyModifier
			state.previousLocalTransparencyModifier = nil
		elseif instance:IsA("BasePart") and state.previousCastShadow ~= nil then
			instance.CastShadow = state.previousCastShadow
			state.previousCastShadow = nil
		elseif state.previousEnabled ~= nil then
			setEnabled(instance, state.previousEnabled)
			state.previousEnabled = nil
		end
		state.wasCulled = false
		state.previousEnabled = nil
		state.previousLocalTransparencyModifier = nil
		state.previousCastShadow = nil
	end

	if instance:IsA("ParticleEmitter") then
		if particleRateMultiplier ~= nil and particleRateMultiplier < 1 then
			if not state.wasRateReduced then
				state.previousRate = instance.Rate
				state.wasRateReduced = true
			end
			instance.Rate = (state.previousRate or instance.Rate) * particleRateMultiplier
		elseif state.wasRateReduced and state.previousRate ~= nil then
			instance.Rate = state.previousRate
			state.previousRate = nil
			state.wasRateReduced = false
		end
	end
end

local function isSupportedInstance(instance: Instance): boolean
	return instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("ParticleEmitter")
		or instance:IsA("Light")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Texture")
		or instance:IsA("Decal")
		or instance:IsA("BasePart")
end

local function hasAncestorNamed(instance: Instance, names: { [string]: boolean }): boolean
	local current: Instance? = instance
	while current do
		if names[current.Name] == true then
			return true
		end
		current = current.Parent
	end

	return false
end

local function hasAncestorNamePrefix(instance: Instance, prefixes: { string }): boolean
	local current: Instance? = instance
	while current do
		for _, prefix in ipairs(prefixes) do
			if string.sub(current.Name, 1, #prefix) == prefix then
				return true
			end
		end
		current = current.Parent
	end

	return false
end

local function hasDisableClientCullingAttribute(instance: Instance): boolean
	local current: Instance? = instance
	while current do
		if current:GetAttribute("DisableClientCulling") == true then
			return true
		end
		current = current.Parent
	end

	return false
end

local function hasPlayerCharacterAncestor(instance: Instance): boolean
	local current: Instance? = instance
	while current do
		if current:IsA("Model") and playerCharacterModels[current] then
			return true
		end
		current = current.Parent
	end

	return false
end

local function isPlayerOrKartVisual(instance: Instance): boolean
	local current: Instance? = instance
	while current do
		if (current:IsA("Model") and playerCharacterModels[current])
			or current.Name == "EquippedKarts"
			or current.Name == "EquippedKart"
		then
			return true
		end
		current = current.Parent
	end

	return false
end

local function shouldSkipGuiAutoTag(instance: LayerCollector): boolean
	local localPlayer = Players.LocalPlayer
	local playerGui = if localPlayer then localPlayer:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui and instance:IsDescendantOf(playerGui) then
		return true
	end

	return hasDisableClientCullingAttribute(instance) or isPlayerOrKartVisual(instance)
end

local SKIPPED_DECORATIVE_ANCESTOR_NAMES = table.freeze({
	EquippedKarts = true,
	EquippedKart = true,
	ClientTsunamiVisuals = true,
	TutorialNotificationSystem = true,
})

local PROTECTED_DECORATIVE_ANCESTOR_NAMES = table.freeze({
	EventBoard = true,
	KartButtons = true,
	Treadmills = true,
	SpawnLocation = true,
	Roads = true,
	Road = true,
	StartLine = true,
	OutsideLine1 = true,
	OutsideLine2 = true,
})

local DECORATIVE_CULL_CANDIDATE_ANCESTOR_NAMES = table.freeze({
	Terrain = true,
	Decorations = true,
	VIPRooms = true,
})

local SKIPPED_DECORATIVE_NAME_PREFIXES = table.freeze({
	"Tutorial",
	"ClientKartSmoke_",
	"ClientTrailVisual_",
})

local function shouldSkipDecorativeAutoTag(instance: Instance): boolean
	if hasDisableClientCullingAttribute(instance) then
		return true
	end
	if hasPlayerCharacterAncestor(instance) then
		return true
	end
	if hasAncestorNamed(instance, SKIPPED_DECORATIVE_ANCESTOR_NAMES) then
		return true
	end
	if hasAncestorNamePrefix(instance, SKIPPED_DECORATIVE_NAME_PREFIXES) then
		return true
	end

	return false
end

local function shouldSkipDecorativeSpatialAutoTag(instance: Instance): boolean
	if hasDisableClientCullingAttribute(instance) then
		return true
	end
	if hasPlayerCharacterAncestor(instance) then
		return true
	end
	if hasAncestorNamed(instance, PROTECTED_DECORATIVE_ANCESTOR_NAMES) then
		return true
	end

	return not hasAncestorNamed(instance, DECORATIVE_CULL_CANDIDATE_ANCESTOR_NAMES)
end

local function getAutoTagForInstance(instance: Instance, config: CullConfig): string?
	local tag: string? = nil
	if instance:IsA("BillboardGui") then
		if not config.autoTagBillboards then
			return nil
		end
		tag = ClientCullingService.Tags.Billboard
	elseif instance:IsA("SurfaceGui") then
		if not config.autoTagSurfaceGuis then
			return nil
		end
		tag = ClientCullingService.Tags.SurfaceGui
	elseif instance:IsA("ParticleEmitter") then
		if not config.autoTagDecorativeEffects then
			return nil
		end
		tag = ClientCullingService.Tags.Particle
	elseif instance:IsA("Light") then
		if not config.autoTagDecorativeEffects then
			return nil
		end
		tag = ClientCullingService.Tags.Light
	elseif instance:IsA("Beam") then
		if not config.autoTagDecorativeEffects then
			return nil
		end
		tag = ClientCullingService.Tags.Beam
	elseif instance:IsA("Trail") then
		if not config.autoTagDecorativeEffects then
			return nil
		end
		tag = ClientCullingService.Tags.Trail
	elseif instance:IsA("Texture") then
		if not config.autoTagDecorativeTextures then
			return nil
		end
		tag = ClientCullingService.Tags.Texture
	elseif instance:IsA("Decal") then
		if not config.autoTagDecorativeTextures then
			return nil
		end
		tag = ClientCullingService.Tags.Decal
	elseif instance:IsA("BasePart") then
		if not shouldCullDecorativeShadows(config) then
			return nil
		end
		tag = ClientCullingService.Tags.Shadow
	else
		return nil
	end

	return tag
end

local function autoTagInstance(instance: Instance, config: CullConfig)
	local tag = getAutoTagForInstance(instance, config)
	if not tag then
		return
	end

	if instance:IsA("BillboardGui") or instance:IsA("SurfaceGui") then
		if shouldSkipGuiAutoTag(instance) then
			return
		end
	elseif instance:IsA("Texture") or instance:IsA("Decal") or instance:IsA("BasePart") then
		if shouldSkipDecorativeSpatialAutoTag(instance) then
			return
		end
	elseif shouldSkipDecorativeAutoTag(instance) then
		return
	end

	if tag and not CollectionService:HasTag(instance, tag) then
		CollectionService:AddTag(instance, tag)
	end
end

local function autoTagExistingCullables()
	local config = getConfig()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		autoTagInstance(descendant, config)
	end
end

local function updateTaggedSet(
	tag: string,
	config: CullConfig,
	cameraPosition: Vector3,
	distanceMultiplier: number,
	particleReducedRateMultiplier: number?
)
	local instances = taggedInstances[tag]
	if not instances then
		return
	end

	local maxDistance = getCullDistanceForTag(tag, config) * distanceMultiplier
	local maxDistanceSquared = maxDistance * maxDistance
	local releaseDistance = math.max(maxDistance - config.cullHysteresisDistance, 0)
	local releaseDistanceSquared = releaseDistance * releaseDistance
	local particleReducedDistance = config.particleReducedDistance * distanceMultiplier
	local particleReducedDistanceSquared = particleReducedDistance * particleReducedDistance

	local cursor = taggedInstanceCursors[tag]
	local processed = 0
	while processed < MAX_INSTANCES_PER_TAG_UPDATE do
		local instance: Instance?
		if cursor then
			instance = next(instances, cursor)
		else
			instance = next(instances)
		end
		if not instance then
			cursor = nil
			break
		end
		cursor = instance
		processed += 1

		if not instance.Parent then
			instances[instance] = nil
			cursor = nil
			restoreInstance(instance)
			continue
		end

		if not isSupportedForTag(tag, instance) then
			continue
		end

		local supportedInstance = instance :: SupportedCullInstance
		if isPlayerOrKartVisual(supportedInstance) then
			local state = instanceStates[supportedInstance]
			if state and state.wasCulled then
				applyCullState(supportedInstance, false)
			end
			continue
		end

		local position = getInstancePositionForTag(tag, supportedInstance)
		if not position then
			applyCullState(supportedInstance, false)
			continue
		end

		local offset = position - cameraPosition
		local distanceSquared = offset:Dot(offset)
		local state = instanceStates[supportedInstance]
		local shouldCull = if state and state.wasCulled
			then distanceSquared > releaseDistanceSquared
			else distanceSquared > maxDistanceSquared
		local particleRateMultiplier: number? = nil
		if
			tag == ClientCullingService.Tags.Particle
			and not shouldCull
			and distanceSquared > particleReducedDistanceSquared
		then
			particleRateMultiplier = particleReducedRateMultiplier or config.particleReducedRateMultiplier
		end
		applyCullState(supportedInstance, shouldCull, particleRateMultiplier)
	end
	taggedInstanceCursors[tag] = cursor
end

local function restoreTaggedSetBatch(tag: string): boolean
	local instances = taggedInstances[tag]
	if not instances then
		return true
	end

	local cursor = taggedInstanceCursors[tag]
	local processed = 0
	while processed < MAX_INSTANCES_PER_TAG_UPDATE do
		local instance: Instance?
		if cursor then
			instance = next(instances, cursor)
		else
			instance = next(instances)
		end
		if not instance then
			taggedInstanceCursors[tag] = nil
			return true
		end

		cursor = instance
		processed += 1
		restoreInstance(instance)
	end

	taggedInstanceCursors[tag] = cursor
	return false
end

local function updateCulling()
	local config = getConfig()
	if not config.enabled then
		for instance in pairs(instanceStates) do
			restoreInstance(instance)
		end
		return
	end

	local currentCamera = Workspace.CurrentCamera
	if not currentCamera then
		return
	end

	local cameraPosition = currentCamera.CFrame.Position
	local distanceMultiplier = getDistanceMultiplier(config, false)
	local particleDistanceMultiplier = getDistanceMultiplier(config, true)
	local particleReducedRateMultiplier = getParticleReducedRateMultiplier(config)
	updateTaggedSet(ClientCullingService.Tags.Billboard, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(ClientCullingService.Tags.SurfaceGui, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(
		ClientCullingService.Tags.Particle,
		config,
		cameraPosition,
		particleDistanceMultiplier,
		particleReducedRateMultiplier
	)
	updateTaggedSet(ClientCullingService.Tags.Light, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(ClientCullingService.Tags.Beam, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(ClientCullingService.Tags.Trail, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(ClientCullingService.Tags.Texture, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(ClientCullingService.Tags.Decal, config, cameraPosition, distanceMultiplier)

	local shouldCullShadows = shouldCullDecorativeShadows(config)
	if shouldCullShadows then
		shadowCullingActive = true
		shadowRestorePending = false
		updateTaggedSet(ClientCullingService.Tags.Shadow, config, cameraPosition, distanceMultiplier)
	elseif shadowCullingActive then
		shadowCullingActive = false
		shadowRestorePending = true
		taggedInstanceCursors[ClientCullingService.Tags.Shadow] = nil
	end

	if shadowRestorePending and restoreTaggedSetBatch(ClientCullingService.Tags.Shadow) then
		shadowRestorePending = false
	end
end

local function bindTagTracking(tag: string)
	local instances = taggedInstances[tag]
	if not instances then
		instances = {}
		taggedInstances[tag] = instances
	else
		table.clear(instances)
	end
	taggedInstanceCursors[tag] = nil

	for _, instance in ipairs(CollectionService:GetTagged(tag)) do
		instances[instance] = true
	end

	serviceMaid:GiveTask(CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		instances[instance] = true
		taggedInstanceCursors[tag] = nil
	end))
	serviceMaid:GiveTask(CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		instances[instance] = nil
		taggedInstanceCursors[tag] = nil
		restoreInstance(instance)
	end))
end

function ClientCullingService.Start()
	if isRunning then
		return
	end
	if not RunService:IsClient() then
		return
	end

	local config = getConfig()
	if not config.enabled then
		return
	end

	isRunning = true
	updateAccumulator = 0
	bindPlayerCharacterTracking()
	bindLocalShadowLightTracking()

	bindTagTracking(ClientCullingService.Tags.Billboard)
	bindTagTracking(ClientCullingService.Tags.SurfaceGui)
	bindTagTracking(ClientCullingService.Tags.Particle)
	bindTagTracking(ClientCullingService.Tags.Light)
	bindTagTracking(ClientCullingService.Tags.Beam)
	bindTagTracking(ClientCullingService.Tags.Trail)
	bindTagTracking(ClientCullingService.Tags.Texture)
	bindTagTracking(ClientCullingService.Tags.Decal)
	bindTagTracking(ClientCullingService.Tags.Shadow)

	if
		config.autoTagBillboards
		or config.autoTagSurfaceGuis
		or config.autoTagDecorativeEffects
		or config.autoTagDecorativeTextures
		or shouldCullDecorativeShadows(config)
	then
		autoTagExistingCullables()
		serviceMaid:GiveTask(Workspace.DescendantAdded:Connect(function(instance)
			autoTagInstance(instance, getConfig())
		end))
	end

	heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		local latestConfig = getConfig()
		updateAccumulator += deltaTime
		if updateAccumulator < latestConfig.updateInterval then
			return
		end

		updateAccumulator = 0
		updateCulling()
	end)
	serviceMaid:GiveTask(heartbeatConnection)

	DebugModule.debugInfo("Client culling service started", "ClientCullingService")
end

function ClientCullingService.Stop()
	if not isRunning then
		return
	end

	isRunning = false
	serviceMaid:DoCleaning()
	heartbeatConnection = nil
	updateAccumulator = 0
	for _, instances in pairs(taggedInstances) do
		table.clear(instances)
	end
	table.clear(taggedInstanceCursors)

	for instance in pairs(instanceStates) do
		restoreInstance(instance)
	end
	table.clear(instanceStates)
	shadowCullingActive = false
	shadowRestorePending = false
end

function ClientCullingService.TagInstance(instance: Instance, tag: string)
	assert(isSupportedInstance(instance), "ClientCullingService.TagInstance requires a supported visual instance")
	assert(typeof(tag) == "string" and tag ~= "", "ClientCullingService.TagInstance requires a non-empty tag")

	if not CollectionService:HasTag(instance, tag) then
		CollectionService:AddTag(instance, tag)
	end
end

function ClientCullingService.ReleaseInstance(instance: Instance): ()
	restoreInstance(instance)
end

return ClientCullingService
