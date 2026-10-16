local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))
local Maid = require(ReplicatedStorage.Modules:WaitForChild("Maid"))
local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)

local EnvironmentService = {}
local localPlayer = Players.LocalPlayer

local MODULE_NAME = "EnvironmentService"
local OWNED_EFFECT_ATTRIBUTE = "EnvironmentServiceOwned"
local EVENT_DECORATION_ATTRIBUTE = "EnvironmentServiceEventDecoration"
local PHYSICAL_CANDY_SHOP_NAME = "PhysicalCandyShop"
local TRANSITION_COMPLETE_ATTRIBUTE = "EnvironmentTransitionComplete"
local environmentConfig = CoreConfig.environment
local transitionDurationSeconds = if typeof(environmentConfig) == "table"
		and typeof(environmentConfig.transitionDurationSeconds) == "number"
	then math.max(0, environmentConfig.transitionDurationSeconds)
	else 2
local atmosphereLeadSeconds = if typeof(environmentConfig) == "table"
		and typeof(environmentConfig.atmosphereLeadSeconds) == "number"
	then math.max(0, environmentConfig.atmosphereLeadSeconds)
	else 0.5
local transitionTweenInfo = TweenConfig.WithDuration(transitionDurationSeconds, TweenConfig.EnvironmentTransition)
local atmosphereLeadTweenInfo = TweenConfig.WithDuration(atmosphereLeadSeconds, TweenConfig.EnvironmentTransition)

local LIGHTING_PROPERTIES = {
	"Ambient",
	"Brightness",
	"ClockTime",
	"ColorShift_Bottom",
	"ColorShift_Top",
	"EnvironmentDiffuseScale",
	"EnvironmentSpecularScale",
	"GeographicLatitude",
	"GlobalShadows",
	"OutdoorAmbient",
}

local EFFECT_PROPERTIES: { [string]: { string } } = {
	Atmosphere = { "Color", "Decay", "Density", "Glare", "Haze", "Offset" },
	ColorCorrectionEffect = { "Brightness", "Contrast", "Enabled", "Saturation", "TintColor" },
	DepthOfFieldEffect = { "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
	Sky = {
		"CelestialBodiesShown",
		"MoonAngularSize",
		"MoonTextureId",
		"SkyboxBk",
		"SkyboxDn",
		"SkyboxFt",
		"SkyboxLf",
		"SkyboxRt",
		"SkyboxUp",
		"StarCount",
		"SunAngularSize",
		"SunTextureId",
	},
}

local maid = Maid.new()
local initialized = false
local stateFolder: Folder? = nil
local currentEnvironmentName = ""
local requestedEnvironmentName = "Default"
local globalShadowsOverride: boolean? = nil
local ownedEffects: { [string]: Instance } = {}
local transitionMaid = Maid.new()
local eventDecorationWorldsMaid = Maid.new()
local eventDecorationWorldMaid = Maid.new()
local eventDecorationTemplatesMaid = Maid.new()
local eventDecorationWorlds: Instance? = nil
local eventDecorationTemplates: Folder? = nil
local activeEventDecoration: Model? = nil
local activeEventDecorationTemplate: Model? = nil
local activePhysicalCandyShop: Model? = nil
local activePhysicalCandyShopTemplate: Model? = nil

local function clearEventDecoration()
	local decoration = activeEventDecoration
	activeEventDecoration = nil
	activeEventDecorationTemplate = nil
	if decoration then
		decoration:Destroy()
	end
end

local function reconcileEventDecoration(environmentName: string)
	local sourceFolder = ReplicatedStorage:FindFirstChild("EventDecorations")
	local candidate = sourceFolder and sourceFolder:FindFirstChild(environmentName)
	local template = if candidate and candidate:IsA("Model") then candidate else nil
	local worlds = Workspace:FindFirstChild("Worlds")
	local world = worlds and worlds:FindFirstChild("World1")
	local destination = world and world:FindFirstChild("Decorations")

	if template == nil or destination == nil then
		clearEventDecoration()
		return
	end

	if activeEventDecoration
		and activeEventDecoration.Parent == destination
		and activeEventDecorationTemplate == template
	then
		return
	end

	clearEventDecoration()
	local clone = template:Clone()
	if clone == nil then
		DebugModule.debugWarn("Could not clone event decoration | name=" .. environmentName, MODULE_NAME)
		return
	end

	clone:SetAttribute(EVENT_DECORATION_ATTRIBUTE, true)
	clone:SetAttribute("EnvironmentServiceEnvironmentName", environmentName)
	clone.Parent = destination
	activeEventDecoration = clone
	activeEventDecorationTemplate = template
	DebugModule.debugInfo("Event decoration applied | name=" .. environmentName, MODULE_NAME)
end

local function clearPhysicalCandyShop()
	local shop = activePhysicalCandyShop
	activePhysicalCandyShop = nil
	activePhysicalCandyShopTemplate = nil
	if shop then
		shop:Destroy()
	end
end

local function reconcilePhysicalCandyShop()
	local isAvailable = stateFolder ~= nil and stateFolder:GetAttribute("HalloweenPartTwoActive") == true
	local decorations = ReplicatedStorage:FindFirstChild("EventDecorations")
	local templateInstance = decorations and decorations:FindFirstChild(PHYSICAL_CANDY_SHOP_NAME)
	local template = if templateInstance and templateInstance:IsA("Model") then templateInstance else nil
	local worlds = Workspace:FindFirstChild("Worlds")
	local world = worlds and worlds:FindFirstChild("World1")
	local destination = world and world:FindFirstChild("Decorations")

	if not isAvailable or not template or not destination then
		clearPhysicalCandyShop()
		return
	end

	if activePhysicalCandyShop
		and activePhysicalCandyShop.Parent == destination
		and activePhysicalCandyShopTemplate == template
	then
		return
	end

	clearPhysicalCandyShop()
	local clone = template:Clone()
	clone:SetAttribute(EVENT_DECORATION_ATTRIBUTE, true)
	clone:SetAttribute("EnvironmentServiceEnvironmentName", "Halloween")
	clone.Parent = destination
	activePhysicalCandyShop = clone
	activePhysicalCandyShopTemplate = template
	DebugModule.debugInfo("Halloween physical candy shop applied", MODULE_NAME)
end

local function bindEventDecorationWorld(world: Instance?)
	eventDecorationWorldMaid:DoCleaning()
	if world then
		eventDecorationWorldMaid.DecorationsAdded = world.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Decorations" then
				reconcileEventDecoration(requestedEnvironmentName)
				reconcilePhysicalCandyShop()
			end
		end)
		eventDecorationWorldMaid.DecorationsRemoved = world.ChildRemoved:Connect(function(child: Instance)
			if child.Name == "Decorations" then
				clearEventDecoration()
				clearPhysicalCandyShop()
			end
		end)
	end
	reconcileEventDecoration(requestedEnvironmentName)
	reconcilePhysicalCandyShop()
end

local function bindEventDecorationWorlds(worlds: Instance)
	eventDecorationWorldsMaid:DoCleaning()
	eventDecorationWorlds = worlds
	eventDecorationWorldsMaid.WorldAdded = worlds.ChildAdded:Connect(function(child: Instance)
		if child.Name == "World1" then
			bindEventDecorationWorld(child)
		end
	end)
	eventDecorationWorldsMaid.WorldRemoved = worlds.ChildRemoved:Connect(function(child: Instance)
		if child.Name == "World1" then
			bindEventDecorationWorld(nil)
		end
	end)
	bindEventDecorationWorld(worlds:FindFirstChild("World1"))
end

local function bindEventDecorationTemplates(folder: Folder)
	eventDecorationTemplatesMaid:DoCleaning()
	eventDecorationTemplates = folder
	eventDecorationTemplatesMaid.TemplateAdded = folder.ChildAdded:Connect(function(child: Instance)
		if child.Name == requestedEnvironmentName then
			reconcileEventDecoration(requestedEnvironmentName)
		elseif child.Name == PHYSICAL_CANDY_SHOP_NAME then
			reconcilePhysicalCandyShop()
		end
	end)
	eventDecorationTemplatesMaid.TemplateRemoved = folder.ChildRemoved:Connect(function(child: Instance)
		if child == activeEventDecorationTemplate or child.Name == requestedEnvironmentName then
			reconcileEventDecoration(requestedEnvironmentName)
		end
		if child == activePhysicalCandyShopTemplate or child.Name == PHYSICAL_CANDY_SHOP_NAME then
			reconcilePhysicalCandyShop()
		end
	end)
	reconcileEventDecoration(requestedEnvironmentName)
	reconcilePhysicalCandyShop()
end

local function getEnvironmentProfile(environmentName: string): Folder?
	local environments = ReplicatedStorage:FindFirstChild("Environments")
	if not environments or not environments:IsA("Folder") then
		DebugModule.debugWarn("ReplicatedStorage.Environments is missing", MODULE_NAME)
		return nil
	end

	local profile = environments:FindFirstChild(environmentName)
	if profile and profile:IsA("Folder") then
		return profile
	end

	if environmentName ~= "Default" then
		DebugModule.debugWarn(
			"Environment profile missing: " .. environmentName .. "; falling back to Default",
			MODULE_NAME
		)
		local defaultProfile = environments:FindFirstChild("Default")
		if defaultProfile and defaultProfile:IsA("Folder") then
			return defaultProfile
		end
	end

	DebugModule.debugWarn("Default environment profile is missing", MODULE_NAME)
	return nil
end

local function setLightingProperty(propertyName: string, value: any)
	if propertyName == "GlobalShadows" and globalShadowsOverride ~= nil then
		return
	end

	local ok, errorMessage = pcall(function()
		(Lighting :: any)[propertyName] = value
	end)
	if not ok then
		DebugModule.debugWarn(
			"Failed to apply lighting property | property=" .. propertyName .. " | error=" .. tostring(errorMessage),
			MODULE_NAME
		)
	end
end

local function setTransitionComplete(value: boolean)
	if stateFolder then
		stateFolder:SetAttribute(TRANSITION_COMPLETE_ATTRIBUTE, value)
	end
end

local function scheduleTransitionComplete()
	local totalDuration = atmosphereLeadSeconds + transitionDurationSeconds
	if totalDuration <= 0 then
		setTransitionComplete(true)
		return
	end

	local completionAnchor = Instance.new("NumberValue")
	completionAnchor.Value = 0
	local completionTween =
		TweenService:Create(completionAnchor, TweenConfig.WithDuration(totalDuration, TweenConfig.EnvironmentLinear), { Value = 1 })
	transitionMaid:GiveTask(completionAnchor)
	transitionMaid:GiveTask(completionTween)
	transitionMaid:GiveTask(completionTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed then
			setTransitionComplete(true)
		end
	end))
	completionTween:Play()
end

local function isTweenableValue(value: any): boolean
	local valueType = typeof(value)
	return valueType == "number" or valueType == "Color3"
end

local function applyClockTimeProperty(value: number, context: string, animate: boolean): boolean
	if not animate or transitionDurationSeconds <= 0 then
		setLightingProperty("ClockTime", value)
		return true
	end

	local currentClockTime = Lighting.ClockTime
	local tweenTarget = value
	if tweenTarget < currentClockTime then
		tweenTarget += 24
	end

	local clockTimeAnchor = Instance.new("NumberValue")
	clockTimeAnchor.Value = currentClockTime
	local ok, tweenOrError = pcall(function()
		return TweenService:Create(clockTimeAnchor, transitionTweenInfo, { Value = tweenTarget })
	end)
	if not ok then
		clockTimeAnchor:Destroy()
		DebugModule.debugWarn(
			"Failed to create ClockTime tween | target=" .. context .. " | error=" .. tostring(tweenOrError),
			MODULE_NAME
		)
		return false
	end

	local tween = tweenOrError :: Tween
	transitionMaid:GiveTask(clockTimeAnchor)
	transitionMaid:GiveTask(tween)
	transitionMaid:GiveTask(clockTimeAnchor:GetPropertyChangedSignal("Value"):Connect(function()
		setLightingProperty("ClockTime", clockTimeAnchor.Value % 24)
	end))
	transitionMaid:GiveTask(tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed then
			setLightingProperty("ClockTime", value)
		end
	end))
	tween:Play()
	return true
end

local function applyEnvironmentProperty(
	target: Instance,
	propertyName: string,
	value: any,
	context: string,
	animate: boolean
)
	if target == Lighting and propertyName == "ClockTime" and typeof(value) == "number" then
		applyClockTimeProperty(value, context, animate)
		return
	end

	if not animate or not isTweenableValue(value) or transitionDurationSeconds <= 0 then
		local ok, errorMessage = pcall(function()
			(target :: any)[propertyName] = value
		end)
		if not ok then
			DebugModule.debugWarn(
				"Failed to apply environment property | target="
					.. context
					.. " | property="
					.. propertyName
					.. " | error="
					.. tostring(errorMessage),
				MODULE_NAME
			)
		end
		return
	end

	local ok, tweenOrError = pcall(function()
		return TweenService:Create(target, transitionTweenInfo, { [propertyName] = value })
	end)
	if not ok then
		DebugModule.debugWarn(
			"Failed to create environment tween | target="
				.. context
				.. " | property="
				.. propertyName
				.. " | error="
				.. tostring(tweenOrError),
			MODULE_NAME
		)
		return
	end

	local tween = tweenOrError :: Tween
	transitionMaid:GiveTask(tween)
	tween:Play()
end

local function applyLightingAttributes(profile: Folder, animate: boolean)
	for _, propertyName in ipairs(LIGHTING_PROPERTIES) do
		local value = profile:GetAttribute(propertyName)
		if value ~= nil then
			if propertyName == "GlobalShadows" or globalShadowsOverride ~= nil then
				setLightingProperty(propertyName, value)
			else
				applyEnvironmentProperty(Lighting, propertyName, value, "Lighting", animate)
			end
		end
	end

	if globalShadowsOverride ~= nil then
		Lighting.GlobalShadows = globalShadowsOverride
	end
end

local function copyEffectProperties(source: Instance, target: Instance, properties: { string }, animate: boolean)
	local sourceAny = source :: any
	for _, propertyName in ipairs(properties) do
		local ok, value = pcall(function()
			return sourceAny[propertyName]
		end)
		if ok and value ~= nil then
			applyEnvironmentProperty(target, propertyName, value, source.Name, animate)
		end
	end
end

local function reconcileEffects(profile: Folder, animate: boolean, phase: "Atmosphere" | "Other" | "All")
	local previousOwnedEffects = ownedEffects
	local nextOwnedEffects: { [string]: Instance } = table.clone(previousOwnedEffects)
	local desiredEffectNames: { [string]: boolean } = {}
	local profileHasSky = false

	for _, source in ipairs(profile:GetChildren()) do
		local properties = EFFECT_PROPERTIES[source.ClassName]
		local isSky = source.ClassName == "Sky"
		if properties then
			desiredEffectNames[source.Name] = true
			if isSky then
				profileHasSky = true
			end
		end
	end

	for _, source in ipairs(profile:GetChildren()) do
		local properties = EFFECT_PROPERTIES[source.ClassName]
		local isAtmosphere = source.ClassName == "Atmosphere"
		local shouldProcess = phase == "All"
			or phase == "Atmosphere" and isAtmosphere
			or phase == "Other" and not isAtmosphere
		if properties and shouldProcess then
			local target = Lighting:FindFirstChild(source.Name)

			if target and target.ClassName ~= source.ClassName then
				if target:GetAttribute(OWNED_EFFECT_ATTRIBUTE) == true then
					target:Destroy()
					target = nil
				else
					DebugModule.debugWarn(
						"Environment effect name is used by another class | name=" .. source.Name,
						MODULE_NAME
					)
					continue
				end
			end

			if not target then
				local clone = source:Clone()
				clone:SetAttribute(OWNED_EFFECT_ATTRIBUTE, true)
				clone.Parent = Lighting
				target = clone
			end

			copyEffectProperties(source, target, properties, animate)
			if target:GetAttribute(OWNED_EFFECT_ATTRIBUTE) == true then
				nextOwnedEffects[source.Name] = target
			end
		end
	end

	if phase ~= "All" or not profileHasSky then
		for effectName, previousEffect in pairs(previousOwnedEffects) do
			if previousEffect:IsA("Sky") then
				desiredEffectNames[effectName] = true
			end
		end
	end

	for effectName, previousEffect in pairs(previousOwnedEffects) do
		if not desiredEffectNames[effectName] and previousEffect.Parent ~= nil then
			previousEffect:Destroy()
		end
	end

	ownedEffects = nextOwnedEffects
end

local function applyEnvironment(environmentName: string, animate: boolean?)
	transitionMaid:DoCleaning()

	local requestedName = if environmentName == "" then "Default" else environmentName
	local lightingProfileName = if requestedName == "Halloween" then "Default" else requestedName
	local profile = getEnvironmentProfile(lightingProfileName)
	if not profile then
		return
	end

	local resolvedName = if profile.Name == "Default" then "Default" else requestedName
	local shouldAnimate = animate ~= false and currentEnvironmentName ~= resolvedName
	if not shouldAnimate or transitionDurationSeconds <= 0 then
		reconcileEffects(profile, false, "All")
		applyLightingAttributes(profile, false)
		setTransitionComplete(true)
	else
		setTransitionComplete(false)
		reconcileEffects(profile, true, "Atmosphere")
		if atmosphereLeadSeconds <= 0 then
			applyLightingAttributes(profile, true)
			reconcileEffects(profile, true, "Other")
		else
			local atmosphereLeadAnchor = Instance.new("NumberValue")
			atmosphereLeadAnchor.Value = 0
			local atmosphereLeadTween =
				TweenService:Create(atmosphereLeadAnchor, atmosphereLeadTweenInfo, { Value = 1 })
			transitionMaid:GiveTask(atmosphereLeadAnchor)
			transitionMaid:GiveTask(atmosphereLeadTween)
			transitionMaid:GiveTask(atmosphereLeadTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
				if playbackState == Enum.PlaybackState.Completed then
					applyLightingAttributes(profile, true)
					reconcileEffects(profile, true, "Other")
				end
			end))
			atmosphereLeadTween:Play()
		end
		scheduleTransitionComplete()
	end

	if currentEnvironmentName ~= resolvedName then
		currentEnvironmentName = resolvedName
		DebugModule.debugInfo("Applied environment | name=" .. resolvedName, MODULE_NAME)
	end

	requestedEnvironmentName = requestedName
	reconcileEventDecoration(requestedName)
	reconcilePhysicalCandyShop()
end

local function refreshFromState(animate: boolean)
	if not stateFolder then
		return
	end

	local environmentName = stateFolder:GetAttribute("EnvironmentName")
	local isEventEnvironmentEnabled = localPlayer == nil
		or localPlayer:GetAttribute("EventEnvironmentEnabled") ~= false
	applyEnvironment(
		if isEventEnvironmentEnabled and typeof(environmentName) == "string" then environmentName else "Default",
		animate
	)
end

local function bindStateFolder(folder: Folder)
	stateFolder = folder
	maid.EnvironmentName = folder:GetAttributeChangedSignal("EnvironmentName"):Connect(function()
		refreshFromState(true)
	end)
	maid.HalloweenPartTwoActive = folder:GetAttributeChangedSignal("HalloweenPartTwoActive"):Connect(function()
		refreshFromState(false)
	end)
	refreshFromState(false)
end

function EnvironmentService.Start()
	if initialized then
		return
	end
	initialized = true
	applyEnvironment("Default", false)

	local worlds = Workspace:FindFirstChild("Worlds")
	if worlds then
		bindEventDecorationWorlds(worlds)
	end
	maid.EventDecorationWorldsAdded = Workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Worlds" then
			bindEventDecorationWorlds(child)
		end
	end)
	maid.EventDecorationWorldsRemoved = Workspace.ChildRemoved:Connect(function(child: Instance)
		if child == eventDecorationWorlds then
			eventDecorationWorldsMaid:DoCleaning()
			eventDecorationWorlds = nil
			bindEventDecorationWorld(nil)
		end
	end)

	local eventDecorations = ReplicatedStorage:FindFirstChild("EventDecorations")
	if eventDecorations and eventDecorations:IsA("Folder") then
		bindEventDecorationTemplates(eventDecorations)
	end
	maid.EventDecorationTemplatesAdded = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == "EventDecorations" and child:IsA("Folder") then
			bindEventDecorationTemplates(child)
		end
	end)
	maid.EventDecorationTemplatesRemoved = ReplicatedStorage.ChildRemoved:Connect(function(child: Instance)
		if child == eventDecorationTemplates then
			eventDecorationTemplatesMaid:DoCleaning()
			eventDecorationTemplates = nil
			reconcileEventDecoration(requestedEnvironmentName)
			reconcilePhysicalCandyShop()
		end
	end)

	if localPlayer then
		maid.EventEnvironmentEnabled = localPlayer:GetAttributeChangedSignal("EventEnvironmentEnabled"):Connect(function()
			refreshFromState(false)
		end)
	end

	local existingState = ReplicatedStorage:FindFirstChild("LiveEventState")
	if existingState and existingState:IsA("Folder") then
		bindStateFolder(existingState)
	else
		maid.StateAdded = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
			if child.Name == "LiveEventState" and child:IsA("Folder") then
				maid.StateAdded = nil
				bindStateFolder(child)
			end
		end)
	end
end

function EnvironmentService.SetGlobalShadowsOverride(value: boolean?)
	globalShadowsOverride = value
	if value ~= nil then
		Lighting.GlobalShadows = value
	elseif initialized then
		applyEnvironment(currentEnvironmentName)
	end
end

function EnvironmentService.ApplyForStudio(environmentName: string)
	if typeof(environmentName) ~= "string" or environmentName == "" then
		DebugModule.debugWarn("Studio environment request was empty", MODULE_NAME)
		return
	end

	applyEnvironment(environmentName, false)
end

function EnvironmentService.Stop()
	if not initialized then
		return
	end

	initialized = false
	maid:DoCleaning()
	eventDecorationWorldsMaid:DoCleaning()
	eventDecorationWorldMaid:DoCleaning()
	eventDecorationTemplatesMaid:DoCleaning()
	eventDecorationWorlds = nil
	eventDecorationTemplates = nil
	stateFolder = nil
	globalShadowsOverride = nil
	applyEnvironment("Default", false)
	clearEventDecoration()
	transitionMaid:DoCleaning()
	currentEnvironmentName = ""
	requestedEnvironmentName = "Default"
	ownedEffects = {}
end

return EnvironmentService
