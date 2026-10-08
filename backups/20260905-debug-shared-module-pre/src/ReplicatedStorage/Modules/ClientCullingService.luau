--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig_Client)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule_Client)
local Maid = require(ReplicatedStorage.Modules.Maid)

type SupportedCullInstance = Instance

type CullState = {
	wasCulled: boolean,
	previousEnabled: boolean?,
}

type CullConfig = {
	enabled: boolean,
	updateInterval: number,
	mobileDistanceMultiplier: number,
	autoTagBillboards: boolean,
	autoTagSurfaceGuis: boolean,
	autoTagDecorativeEffects: boolean,
	billboardDistance: number,
	surfaceGuiDistance: number,
	particleDistance: number,
	lightDistance: number,
	beamDistance: number,
	trailDistance: number,
}

local ClientCullingService = {}

ClientCullingService.Tags = table.freeze({
	Billboard = "ClientCullableBillboard",
	SurfaceGui = "ClientCullableSurfaceGui",
	Particle = "ClientCullableParticle",
	Light = "ClientCullableLight",
	Beam = "ClientCullableBeam",
	Trail = "ClientCullableTrail",
})

local DEFAULT_CONFIG: CullConfig = {
	enabled = true,
	updateInterval = 0.25,
	mobileDistanceMultiplier = 0.65,
	autoTagBillboards = true,
	autoTagSurfaceGuis = true,
	autoTagDecorativeEffects = true,
	billboardDistance = 300,
	surfaceGuiDistance = 300,
	particleDistance = 180,
	lightDistance = 220,
	beamDistance = 250,
	trailDistance = 200,
}

local serviceMaid = Maid.new()
local instanceStates: { [Instance]: CullState } = {}
local taggedInstances: { [string]: { [Instance]: boolean } } = {}
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
		autoTagBillboards = readBoolean(rawConfig.autoTagBillboards, DEFAULT_CONFIG.autoTagBillboards),
		autoTagSurfaceGuis = readBoolean(rawConfig.autoTagSurfaceGuis, DEFAULT_CONFIG.autoTagSurfaceGuis),
		autoTagDecorativeEffects = readBoolean(
			rawConfig.autoTagDecorativeEffects,
			DEFAULT_CONFIG.autoTagDecorativeEffects
		),
		billboardDistance = readNumber(rawConfig.billboardDistance, DEFAULT_CONFIG.billboardDistance),
		surfaceGuiDistance = readNumber(rawConfig.surfaceGuiDistance, DEFAULT_CONFIG.surfaceGuiDistance),
		particleDistance = readNumber(rawConfig.particleDistance, DEFAULT_CONFIG.particleDistance),
		lightDistance = readNumber(rawConfig.lightDistance, DEFAULT_CONFIG.lightDistance),
		beamDistance = readNumber(rawConfig.beamDistance, DEFAULT_CONFIG.beamDistance),
		trailDistance = readNumber(rawConfig.trailDistance, DEFAULT_CONFIG.trailDistance),
	}
end

local function isMobileClient(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

local function getDistanceMultiplier(config: CullConfig): number
	return if isMobileClient() then config.mobileDistanceMultiplier else 1
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

local function getInstancePosition(instance: SupportedCullInstance): Vector3?
	if instance:IsA("BillboardGui") then
		return getBillboardPosition(instance)
	end
	if instance:IsA("SurfaceGui") then
		return getSurfaceGuiPosition(instance)
	end
	if instance:IsA("Beam") then
		return getBeamPosition(instance)
	end

	local parent = instance.Parent
	if parent then
		return getInstanceOrAncestorPosition(parent)
	end

	return nil
end

local function getCullDistance(instance: SupportedCullInstance, config: CullConfig): number
	if instance:IsA("BillboardGui") then
		return config.billboardDistance
	end
	if instance:IsA("SurfaceGui") then
		return config.surfaceGuiDistance
	end
	if instance:IsA("ParticleEmitter") then
		return config.particleDistance
	end
	if instance:IsA("Light") then
		return config.lightDistance
	end
	if instance:IsA("Beam") then
		return config.beamDistance
	end
	if instance:IsA("Trail") then
		return config.trailDistance
	end

	return 0
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

	if state.wasCulled and state.previousEnabled ~= nil then
		local supportedInstance = instance :: any
		if supportedInstance.Parent ~= nil then
			setEnabled(supportedInstance :: SupportedCullInstance, state.previousEnabled)
		end
	end

	instanceStates[instance] = nil
end

local function applyCullState(instance: SupportedCullInstance, shouldCull: boolean)
	local state = instanceStates[instance]
	if not state then
		state = {
			wasCulled = false,
			previousEnabled = nil,
		}
		instanceStates[instance] = state
	end

	if shouldCull then
		if state.wasCulled then
			return
		end

		state.previousEnabled = getEnabled(instance)
		state.wasCulled = true
		setEnabled(instance, false)
		return
	end

	if not state.wasCulled then
		return
	end

	if state.previousEnabled ~= nil then
		setEnabled(instance, state.previousEnabled)
	end
	state.wasCulled = false
	state.previousEnabled = nil
end

local function isSupportedInstance(instance: Instance): boolean
	return instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("ParticleEmitter")
		or instance:IsA("Light")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
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
		if current:IsA("Model") and Players:GetPlayerFromCharacter(current) ~= nil then
			return true
		end
		current = current.Parent
	end

	return false
end

local function shouldSkipGuiAutoTag(instance: LayerCollector): boolean
	if instance:IsDescendantOf(Players.LocalPlayer:WaitForChild("PlayerGui")) then
		return true
	end

	return hasDisableClientCullingAttribute(instance)
end

local SKIPPED_DECORATIVE_ANCESTOR_NAMES = table.freeze({
	EquippedKarts = true,
	EquippedKart = true,
	ClientTsunamiVisuals = true,
	TutorialNotificationSystem = true,
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

local function updateTaggedSet(tag: string, config: CullConfig, cameraPosition: Vector3, distanceMultiplier: number)
	local instances = taggedInstances[tag]
	if not instances then
		return
	end

	for instance in pairs(instances) do
		if not instance.Parent then
			instances[instance] = nil
			restoreInstance(instance)
			continue
		end

		if not isSupportedInstance(instance) then
			continue
		end

		local supportedInstance = instance :: SupportedCullInstance
		local position = getInstancePosition(supportedInstance)
		if not position then
			applyCullState(supportedInstance, false)
			continue
		end

		local maxDistance = getCullDistance(supportedInstance, config) * distanceMultiplier
		local shouldCull = (position - cameraPosition).Magnitude > maxDistance
		applyCullState(supportedInstance, shouldCull)
	end
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
	local distanceMultiplier = getDistanceMultiplier(config)
	updateTaggedSet(ClientCullingService.Tags.Billboard, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(ClientCullingService.Tags.SurfaceGui, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(ClientCullingService.Tags.Particle, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(ClientCullingService.Tags.Light, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(ClientCullingService.Tags.Beam, config, cameraPosition, distanceMultiplier)
	updateTaggedSet(ClientCullingService.Tags.Trail, config, cameraPosition, distanceMultiplier)
end

local function bindTagTracking(tag: string)
	local instances = taggedInstances[tag]
	if not instances then
		instances = {}
		taggedInstances[tag] = instances
	else
		table.clear(instances)
	end

	for _, instance in ipairs(CollectionService:GetTagged(tag)) do
		instances[instance] = true
	end

	serviceMaid:GiveTask(CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance)
		instances[instance] = true
	end))
	serviceMaid:GiveTask(CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance)
		instances[instance] = nil
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

	bindTagTracking(ClientCullingService.Tags.Billboard)
	bindTagTracking(ClientCullingService.Tags.SurfaceGui)
	bindTagTracking(ClientCullingService.Tags.Particle)
	bindTagTracking(ClientCullingService.Tags.Light)
	bindTagTracking(ClientCullingService.Tags.Beam)
	bindTagTracking(ClientCullingService.Tags.Trail)

	if config.autoTagBillboards or config.autoTagSurfaceGuis or config.autoTagDecorativeEffects then
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

	for instance in pairs(instanceStates) do
		restoreInstance(instance)
	end
	table.clear(instanceStates)
end

function ClientCullingService.TagInstance(instance: Instance, tag: string)
	assert(isSupportedInstance(instance), "ClientCullingService.TagInstance requires a supported visual instance")
	assert(typeof(tag) == "string" and tag ~= "", "ClientCullingService.TagInstance requires a non-empty tag")

	if not CollectionService:HasTag(instance, tag) then
		CollectionService:AddTag(instance, tag)
	end
end

return ClientCullingService
