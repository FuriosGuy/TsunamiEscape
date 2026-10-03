local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))
local Maid = require(ReplicatedStorage.Modules:WaitForChild("Maid"))
local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)

local EnvironmentService = {}

local MODULE_NAME = "EnvironmentService"
local OWNED_EFFECT_ATTRIBUTE = "EnvironmentServiceOwned"
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
local globalShadowsOverride: boolean? = nil
local ownedEffects: { [string]: Instance } = {}
local transitionMaid = Maid.new()

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
	local profile = getEnvironmentProfile(requestedName)
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
end

local function refreshFromState(animate: boolean)
	if not stateFolder then
		return
	end

	local environmentName = stateFolder:GetAttribute("EnvironmentName")
	applyEnvironment(if typeof(environmentName) == "string" then environmentName else "Default", animate)
end

local function bindStateFolder(folder: Folder)
	stateFolder = folder
	maid.EnvironmentName = folder:GetAttributeChangedSignal("EnvironmentName"):Connect(function()
		refreshFromState(true)
	end)
	refreshFromState(false)
end

function EnvironmentService.Start()
	if initialized then
		return
	end
	initialized = true
	applyEnvironment("Default", false)

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
	stateFolder = nil
	globalShadowsOverride = nil
	applyEnvironment("Default", false)
	transitionMaid:DoCleaning()
	currentEnvironmentName = ""
	ownedEffects = {}
end

return EnvironmentService
