local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local RobloxSoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local ClientDeviceProfile = require(ReplicatedStorage.Modules.ClientDeviceProfile)
local PlayerHandler = require(ReplicatedStorage.Modules.Shared:WaitForChild("PlayerHandler_Client"))
local MainFunctions = require(ReplicatedStorage.Modules.UI.MainFunctions)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)
local SoundService = require(ReplicatedStorage.Modules.SoundService)

local player = Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local camera = Workspace.CurrentCamera
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local KartVisualResync = Remotes:WaitForChild("KartVisualResync") :: RemoteEvent
local PLAYER_CLIENT_HANDLER_SINGLETON_KEY = "SpeedBrainrotPlayerClientHandlerState"

type PlayerClientHandlerSingletonState = {
	ownerToken: string?,
	cleanup: ((string) -> ())?,
}

local singletonState = (shared :: any)[PLAYER_CLIENT_HANDLER_SINGLETON_KEY] :: PlayerClientHandlerSingletonState?
if singletonState == nil then
	singletonState = {
		ownerToken = nil,
		cleanup = nil,
	}
	(shared :: any)[PLAYER_CLIENT_HANDLER_SINGLETON_KEY] = singletonState
end

local handlerToken = string.format("%s:%d", tostring(os.clock()), math.random(1, 1_000_000_000))
local previousHandlerCleanup = singletonState.cleanup
singletonState.ownerToken = handlerToken

local CLIENT_HANDLER_CONFIG = table.freeze({
	DEFAULT_FOV = if camera then camera.FieldOfView else 70,
	TREADMILL_FOV = 100,
	SPEED_FOV_MAX = 95,
	FOV_TWEEN_TIME = 0.2,
	MUSIC_FADE_TIME = 0.35,
	LOBBY_MUSIC_VOLUME = 0.3,
	RECOVERY_FORCE_UPRIGHT_WINDOW = 0.35,
	KART_SHOWCASE_BOB_AMPLITUDE = 1,
	POLICE_LIGHT_PHASE_DURATION = 0.25,
	POLICE_SPOTLIGHT_STROBE_CYCLE = 0.35,
	POLICE_SPOTLIGHT_ON_DURATION = 0.25,
	KART_ENGINE_REFERENCE_SPEED = 120,
	LOCAL_KART_SOUND_MISSING_GRACE = 0.75,
	CLIENT_KART_ENGINE_SOUND_NAME = "ClientKartEngineLocal",
	CLIENT_KART_SMOKE_NAME_PREFIX = "ClientKartSmoke_",
	TREADMILL_TEXTURE_SCROLL_SPEED = 16,
	TREADMILL_TEXTURE_UPDATE_INTERVAL = 1 / 60,
	TREADMILL_TEXTURE_NEAR_DISTANCE = 90,
	TREADMILL_TEXTURE_FAR_DISTANCE = 180,
	TREADMILL_TEXTURE_PAUSE_DISTANCE = 260,
	TREADMILL_TEXTURE_FAR_UPDATE_INTERVAL = 1 / 30,
	TREADMILL_HIGHLIGHT_UPDATE_INTERVAL = 0.1,
	TREADMILL_HIGHLIGHT_MAX_DISTANCE = 25,
	TREADMILL_HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0, 0, 0),
	TREADMILL_HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255),
	WORLD_MUSIC_UPDATE_INTERVAL = 0.3,
	KART_VISUAL_FRAMELOCK_INTERVAL = 1 / 60,
	KART_SHOWCASE_FRAMELOCK_INTERVAL = 1 / 30,
	REMOTE_KART_WHEEL_UPDATE_INTERVAL = 1 / 30,
	FOV_UPDATE_INTERVAL = 1 / 30,
	KART_VISUAL_HOLDER_NAME = "EquippedKarts",
	SHOWCASE_MODEL_CONFIG = table.freeze({
		kartModelName = "KartShowcaseModel",
		luckyBlockFolderName = "LuckyBlocks",
		luckyBlockRotationDuration = 15,
		luckyBlockModelNames = table.freeze({
			Tier1_LuckyBlock = true,
			Tier2_LuckyBlock = true,
			Tier3_LuckyBlock = true,
			Bloodmoon_LuckyBlock = true,
			Robux_LuckyBlock = true,
			Neon_LuckyBlock = true,
			Frostbite_LuckyBlock = true,
		}),
	}),
	EQUIPPED_KART_MODEL_NAME = "EquippedKart",
	CLIENT_TRAIL_ATTACHMENT0_NAME = "ClientTrailAttachment0",
	CLIENT_TRAIL_ATTACHMENT1_NAME = "ClientTrailAttachment1",
	CLIENT_TRAIL_VISUAL_PREFIX = "ClientTrailVisual_",
	TRAIL_VISUAL_MISSING_GRACE = 2,
	POLICE_BLUE_COLOR = Color3.fromRGB(9, 137, 207),
	POLICE_RED_COLOR = Color3.fromRGB(196, 40, 28),
	KART_VISUAL_NEAR_DISTANCE = 512,
	KART_VISUAL_FAR_DISTANCE = 1024,
	KART_VISUAL_MID_INTERVAL = 0.08,
	KART_VISUAL_FAR_INTERVAL = 0.2,
	KART_VISUAL_OFFSCREEN_INTERVAL = 0.35,
	KART_STATE_REFRESH_INTERVAL = 0.2,
	KART_STATE_REFRESH_MID_INTERVAL = 0.5,
	KART_STATE_REFRESH_FAR_INTERVAL = 1.0,
	KART_CAMERA_BUCKET_REFRESH_INTERVAL = 0.2,
	REMOTE_KART_IDLE_EFFECT_INTERVAL = 0.35,
	KART_CLIENT_VISUAL_HEALTH_INTERVAL = 0.25,
	KART_CLIENT_VISUAL_MISSING_GRACE = 0.5,
	KART_CLIENT_VISUAL_RESYNC_COOLDOWN = 5,
	KART_SHOWCASE_NEAR_DISTANCE = 256,
	KART_SHOWCASE_FAR_DISTANCE = 384,
	KART_SHOWCASE_PAUSE_DISTANCE = 512,
	KART_SHOWCASE_FULL_RATE_DISTANCE = 64,
	KART_SHOWCASE_TARGET_FPS_FULL = 60,
	KART_SHOWCASE_TARGET_FPS_NEAR = 30,
	KART_SHOWCASE_TARGET_FPS_FAR = 15,
	KART_SHOWCASE_TARGET_FPS_VERY_FAR = 10,
	FREECAM_BLOCK_ACTION = "SB_BlockRobloxFreecamToggle",
})

type VisualDistanceBucket = "near" | "mid" | "far" | "offscreen"

type ShowcasePartState = {
	part: BasePart,
	relativeCFrame: CFrame,
}

type ShowcaseVisualState = {
	model: Model,
	basePivot: CFrame,
	visualOffset: number,
	visualUpdatePhase: number,
	visualUpdatePhaseInitialized: boolean,
	rotationDuration: number,
	parts: { ShowcasePartState },
	trackedParts: { [BasePart]: boolean },
	usePartCFrameAnimation: boolean,
	descendantAddedConnection: RBXScriptConnection?,
	descendantRemovingConnection: RBXScriptConnection?,
	visualUpdateAccumulator: number,
	cameraBucket: VisualDistanceBucket?,
	cameraBucketDistance: number?,
	cameraBucketOnScreen: boolean?,
	cameraBucketAccumulator: number,
	isPoliceKart: boolean,
	lightBarBlue: BasePart?,
	lightBarRed: BasePart?,
	spotlightLensL: BasePart?,
	spotlightLensR: BasePart?,
}

type EquippedKartVisualState = {
	model: Model,
	owner: Player?,
	ownerCharacter: Model?,
	ownerHumanoid: Humanoid?,
	rootPart: BasePart?,
	engineParent: BasePart?,
	engineSound: Sound?,
	engineSoundId: string?,
	smokeEmitters: { ParticleEmitter },
	emitterSpeeds: { [ParticleEmitter]: NumberRange },
	visualOffset: number,
	isPoliceKart: boolean,
	lightBarBlue: BasePart?,
	lightBarRed: BasePart?,
	spotlightLensL: BasePart?,
	spotlightLensR: BasePart?,
	wheelMotors: { { motor: Motor6D, baseC0: CFrame, radius: number } },
	spinAngle: number,
	visualUpdateAccumulator: number,
	wheelUpdateAccumulator: number,
	idleEffectsAccumulator: number,
	stateRefreshAccumulator: number,
	cameraBucket: VisualDistanceBucket?,
	cameraBucketDistance: number?,
	cameraBucketOnScreen: boolean?,
	cameraBucketAccumulator: number,
	lastMoving: boolean?,
	lastPlaybackSpeed: number?,
	offscreenEffectsDisabled: boolean?,
}

type ObservedTrailVisualState = {
	player: Player,
	character: Model?,
	rootPart: BasePart?,
	equippedTrail: string,
	attachment0: Attachment?,
	attachment1: Attachment?,
	trails: { Trail },
	emitters: { ParticleEmitter },
	emitterRates: { [ParticleEmitter]: number },
	emitterSpeeds: { [ParticleEmitter]: NumberRange },
	lastMoving: boolean?,
	missingUntil: number?,
	quality: "full" | "reduced" | "disabled"?,
}

type RemoteTrailQuality = "full" | "reduced" | "disabled"

type RemoteTrailBudgetConfig = {
	enabled: boolean,
	updateInterval: number,
	mobileDistanceMultiplier: number,
	fullDistance: number,
	disableDistance: number,
	reducedRateMultiplier: number,
	maxVisiblePlayers: number,
}

type RemoteTrailCandidate = {
	state: ObservedTrailVisualState,
	distance: number,
}

type TreadmillTextureVisualState = {
	scrollSpeed: number,
	updateAccumulator: number,
	worldPosition: Vector3,
}

local activeFovTween: Tween? = nil
local lastTargetFov: number? = nil
local recoveryUntil = 0
local registeredRainbowGradients: { [UIGradient]: boolean } = {}
local observedKartShowcases: { [Model]: ShowcaseVisualState } = {}
local showcaseRegistrationSequence = 0
local observedEquippedKarts: { [Model]: EquippedKartVisualState } = {}
local localKartEngineSound: Sound? = nil
local localKartEngineSoundLastSeenAt: number? = nil
local observedTrailVisuals: { [Player]: ObservedTrailVisualState } = {}
local observedTreadmillTextures: { [Texture]: TreadmillTextureVisualState } = {}
local observedTreadmillTouchParts: { [BasePart]: Instance } = {}
local activeTreadmillHighlight: Highlight? = nil
local activeTreadmillHighlightAdornee: Instance? = nil
local treadmillHighlightUpdateAccumulator = 0
local trailVisualUpdateAccumulator = 0
local worldMusicUpdateAccumulator = 0
local kartVisualFrameAccumulator = 0
local kartShowcaseFrameAccumulator = 0
local kartVisualHealthAccumulator = 0
local treadmillTextureUpdateAccumulator = 0
local cachedCharacterRootPart: BasePart? = nil
local fovUpdateAccumulator = 0
local localKartVisualMissingSince: number? = nil
local lastKartVisualResyncAt = 0
local lobbyMusicSound = RobloxSoundService:FindFirstChild("LobbyMusic") :: Sound?
if not lobbyMusicSound then
	lobbyMusicSound = Instance.new("Sound")
	lobbyMusicSound.Name = "LobbyMusic"
	lobbyMusicSound.Parent = RobloxSoundService
end
lobbyMusicSound.Volume = CLIENT_HANDLER_CONFIG.LOBBY_MUSIC_VOLUME
lobbyMusicSound.PlaybackSpeed = 1
lobbyMusicSound.Looped = false
local currentMusicPlaylistKey: string? = nil
local currentMusicTracks: { string | number } = {}
local currentMusicIndex = 0
local currentMusicToken = 0
local activeMusicTween: Tween? = nil
local movementLifecycleMaid = Maid.new()
local topLevelMaid = Maid.new()
local observedTrailPlayerMaids: { [Player]: any } = {}
local registeredRainbowGradientMaids: { [UIGradient]: Maid } = {}
local observedKartVisualSourceRoots: { [Instance]: Maid } = {}
local observedWorldSourceRoots: { [Instance]: Maid } = {}
local isCleaningUp = false

local function deferTopLevel(callback: () -> ())
	local thread = task.defer(function()
		if isCleaningUp then
			return
		end
		callback()
	end)
	topLevelMaid:GiveTask(thread)
end

topLevelMaid:GiveTask(function()
	for root, rootMaid in pairs(observedKartVisualSourceRoots) do
		rootMaid:DoCleaning()
		observedKartVisualSourceRoots[root] = nil
	end
	for root, rootMaid in pairs(observedWorldSourceRoots) do
		rootMaid:DoCleaning()
		observedWorldSourceRoots[root] = nil
	end
end)

local function countTrackedEquippedKartStates(): number
	local count = 0
	for _ in pairs(observedEquippedKarts) do
		count += 1
	end

	return count
end

local function listContainsModule(moduleList: { any }?, moduleName: string): boolean
	if typeof(moduleList) ~= "table" then
		return false
	end

	for _, entry in ipairs(moduleList) do
		if entry == moduleName then
			return true
		end
	end

	return false
end

local function isModuleDebugEnabled(moduleName: string): boolean
	local settings = DebugModule.getSettings()
	if not settings.enabled then
		return false
	end

	local moduleOverrides = settings.moduleOverrides
	if typeof(moduleOverrides) == "table" then
		local overrideValue = moduleOverrides[moduleName]
		if typeof(overrideValue) == "boolean" then
			return overrideValue
		end
	end

	if listContainsModule(settings.disabledModules, moduleName) then
		return false
	end

	local enabledModules = settings.enabledModules
	if typeof(enabledModules) == "table" and #enabledModules > 0 then
		return listContainsModule(enabledModules, moduleName)
	end

	return true
end

local function isKartRespawnProbeEnabled(): boolean
	return isModuleDebugEnabled("PlayerClientHandler")
end

local function logKartRespawnProbe(reason: string)
	if not isKartRespawnProbeEnabled() then
		return
	end

	local equippedKartCount = 0
	local motorCount = 0
	local clientKartEngineSoundCount = 0
	local motorNames = {}
	local equippedKartName = player:GetAttribute("Kart_Equipped")

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant.Name == "EquippedKart" then
			local ownerUserId = descendant:GetAttribute("OwnerUserId")
			if typeof(ownerUserId) == "number" and ownerUserId == player.UserId then
				equippedKartCount += 1
			end
		elseif descendant:IsA("Motor6D") and string.match(descendant.Name, "_Motor$") then
			local equippedKartModel = descendant:FindFirstAncestor(CLIENT_HANDLER_CONFIG.EQUIPPED_KART_MODEL_NAME)
			if equippedKartModel and equippedKartModel:IsA("Model") then
				local ownerUserId = equippedKartModel:GetAttribute("OwnerUserId")
				if typeof(ownerUserId) == "number" and ownerUserId == player.UserId then
					motorCount += 1
					table.insert(motorNames, descendant.Name)
				end
			end
		elseif descendant:IsA("Sound") and descendant.Name == CLIENT_HANDLER_CONFIG.CLIENT_KART_ENGINE_SOUND_NAME then
			local equippedKartModel = descendant:FindFirstAncestor("EquippedKart")
			local ownerUserId = equippedKartModel and equippedKartModel:GetAttribute("OwnerUserId")
			if typeof(ownerUserId) == "number" and ownerUserId == player.UserId then
				clientKartEngineSoundCount += 1
			end
		end
	end

	DebugModule.debugInfo(
		string.format(
			"Kart respawn probe | reason=%s | equippedKart=%s | equippedKarts=%d | rootMotors=%d | clientKartEngineSounds=%d | trackedEquippedKartStates=%d | motorNames=%s",
			reason,
			tostring(equippedKartName),
			equippedKartCount,
			motorCount,
			clientKartEngineSoundCount,
			countTrackedEquippedKartStates(),
			table.concat(motorNames, ",")
		),
		"PlayerClientHandler"
	)
end

local function scheduleKartRespawnProbe(reason: string, delaySeconds: number)
	if not isKartRespawnProbeEnabled() then
		return
	end

	topLevelMaid:GiveTask(task.delay(delaySeconds, function()
		if isCleaningUp or not player.Parent or not isKartRespawnProbeEnabled() then
			return
		end

		logKartRespawnProbe(reason)
	end))
end

local function normalizeTrackId(trackId: string | number): string
	if typeof(trackId) == "number" then
		return "rbxassetid://" .. tostring(trackId)
	end

	if string.find(trackId, "rbxassetid://") == 1 then
		return trackId
	end

	return "rbxassetid://" .. trackId
end

local function normalizeSoundId(soundId: string | number): string
	if typeof(soundId) == "number" then
		return "rbxassetid://" .. tostring(soundId)
	end

	if string.find(soundId, "rbxassetid://") == 1 then
		return soundId
	end

	return "rbxassetid://" .. soundId
end

local function findBasePartByName(root: Instance, partName: string): BasePart?
	local part = root:FindFirstChild(partName, true)
	if part and part:IsA("BasePart") then
		return part
	end

	return nil
end

local function getEngineParent(model: Model): BasePart?
	local seatBase = model:FindFirstChild("SeatBase", true)
	if seatBase and seatBase:IsA("BasePart") then
		return seatBase
	end

	return nil
end

local function destroyClientKartSmokeEmitters(rootPart: BasePart)
	for _, child in ipairs(rootPart:GetChildren()) do
		if child:IsA("ParticleEmitter") and string.find(child.Name, CLIENT_HANDLER_CONFIG.CLIENT_KART_SMOKE_NAME_PREFIX, 1, true) == 1 then
			child:Destroy()
		end
	end
end

local function createClientKartSmokeEmitters(
	rootPart: BasePart
): ({ ParticleEmitter }, { [ParticleEmitter]: NumberRange })
	destroyClientKartSmokeEmitters(rootPart)

	local particlesFolder = ReplicatedStorage:FindFirstChild("Particles")
	local smokeTrailFolder = particlesFolder and particlesFolder:FindFirstChild("SmokeTrail")
	if not smokeTrailFolder then
		return {}, {}
	end

	local smokeEmitters = {}
	local emitterSpeeds: { [ParticleEmitter]: NumberRange } = {}
	local emitterIndex = 0

	for _, descendant in ipairs(smokeTrailFolder:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			emitterIndex += 1
			local clone = descendant:Clone()
			clone.Name = CLIENT_HANDLER_CONFIG.CLIENT_KART_SMOKE_NAME_PREFIX .. tostring(emitterIndex)
			clone.Enabled = false
			clone.Parent = rootPart
			table.insert(smokeEmitters, clone)
			emitterSpeeds[clone] = clone.Speed
		end
	end

	return smokeEmitters, emitterSpeeds
end

local function createOrUpdateClientKartEngineSound(parent: Instance, soundIdValue: string): Sound?
	local existing = parent:FindFirstChild(CLIENT_HANDLER_CONFIG.CLIENT_KART_ENGINE_SOUND_NAME)
	local sound = if existing and existing:IsA("Sound") then existing else nil
	if not sound then
		sound = SoundService.CreateSound(parent, "KartEngine", {
			SoundId = normalizeSoundId(soundIdValue),
		})
		if not sound then
			return nil
		end
		sound.Name = CLIENT_HANDLER_CONFIG.CLIENT_KART_ENGINE_SOUND_NAME
	end

	local soundTemplateFolder = ReplicatedStorage:FindFirstChild("Sounds")
	local soundTemplate = soundTemplateFolder and soundTemplateFolder:FindFirstChild("KartEngine")
	if soundTemplate and soundTemplate:IsA("Sound") then
		sound.Volume = soundTemplate.Volume
		sound.Looped = soundTemplate.Looped
		sound.PlaybackSpeed = soundTemplate.PlaybackSpeed
		sound.RollOffMode = soundTemplate.RollOffMode
		sound.RollOffMinDistance = soundTemplate.RollOffMinDistance
		sound.RollOffMaxDistance = soundTemplate.RollOffMaxDistance
	end

	local normalizedSoundId = normalizeSoundId(soundIdValue)
	if sound.SoundId ~= normalizedSoundId then
		sound:Stop()
		sound.SoundId = normalizedSoundId
	end

	if not sound.IsPlaying then
		sound:Play()
	end

	return sound
end

local function applyPoliceKartVisuals(
	phaseTime: number,
	lightBarBlue: BasePart?,
	lightBarRed: BasePart?,
	spotlightLensL: BasePart?,
	spotlightLensR: BasePart?
)
	local alternatePhase = math.floor(phaseTime / CLIENT_HANDLER_CONFIG.POLICE_LIGHT_PHASE_DURATION) % 2
	local blueOn = alternatePhase == 0
	local redOn = not blueOn

	if lightBarBlue then
		lightBarBlue.Color = if blueOn then CLIENT_HANDLER_CONFIG.POLICE_BLUE_COLOR else CLIENT_HANDLER_CONFIG.POLICE_RED_COLOR
		lightBarBlue.Transparency = 0
	end

	if lightBarRed then
		lightBarRed.Color = if redOn then CLIENT_HANDLER_CONFIG.POLICE_BLUE_COLOR else CLIENT_HANDLER_CONFIG.POLICE_RED_COLOR
		lightBarRed.Transparency = 0
	end

	local strobeCycle = phaseTime % CLIENT_HANDLER_CONFIG.POLICE_SPOTLIGHT_STROBE_CYCLE
	local spotlightOn = strobeCycle < CLIENT_HANDLER_CONFIG.POLICE_SPOTLIGHT_ON_DURATION

	if spotlightLensL then
		spotlightLensL.Transparency = if spotlightOn then 0 else 1
	end

	if spotlightLensR then
		spotlightLensR.Transparency = if spotlightOn then 0 else 1
	end
end

local function applyCurrentPoliceKartVisuals(
	visualOffset: number,
	lightBarBlue: BasePart?,
	lightBarRed: BasePart?,
	spotlightLensL: BasePart?,
	spotlightLensR: BasePart?
)
	applyPoliceKartVisuals(
		Workspace:GetServerTimeNow() + visualOffset,
		lightBarBlue,
		lightBarRed,
		spotlightLensL,
		spotlightLensR
	)
end

local function getClientWheelMotors(seatBase: BasePart?): { { motor: Motor6D, baseC0: CFrame, radius: number } }
	if not seatBase then
		return {}
	end

	local wheelMotors = {}
	for _, child in ipairs(seatBase:GetChildren()) do
		if child:IsA("Motor6D") and string.match(child.Name, "_Motor$") then
			local wheelPart = child.Part1
			local radius = 1
			if wheelPart and wheelPart:IsA("BasePart") then
				radius = math.max(0.05, math.max(wheelPart.Size.Y, wheelPart.Size.Z) * 0.5)
			end

			table.insert(wheelMotors, {
				motor = child,
				baseC0 = child.C0,
				radius = radius,
			})
		end
	end

	return wheelMotors
end

local function registerTreadmillTexture(instance: Instance)
	if not instance:IsA("Texture") then
		return
	end

	local movementPart = instance:FindFirstAncestor("MovementPart")
	if not movementPart or not movementPart:IsA("BasePart") then
		return
	end

	observedTreadmillTextures[instance] = {
		scrollSpeed = CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_SCROLL_SPEED,
		updateAccumulator = 0,
		worldPosition = movementPart.Position,
	}
end

local function registerTreadmillTouchPart(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end

	local isTouchPart = instance.Name == "TouchPart"
	local isStandaloneTreadmill = typeof(instance:GetAttribute("XP_Multiplier")) == "number"
		and typeof(instance:GetAttribute("XPGainInterval")) == "number"
	if not isTouchPart and not isStandaloneTreadmill then
		return
	end

	local treadmillRoot = instance:FindFirstAncestorOfClass("Model")
	if treadmillRoot then
		observedTreadmillTouchParts[instance] = treadmillRoot
		return
	end

	observedTreadmillTouchParts[instance] = instance
end

local function distanceFromPointToPartBounds(part: BasePart, point: Vector3): number
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5
	local dx = math.max(math.abs(localPoint.X) - halfSize.X, 0)
	local dy = math.max(math.abs(localPoint.Y) - halfSize.Y, 0)
	local dz = math.max(math.abs(localPoint.Z) - halfSize.Z, 0)
	return Vector3.new(dx, dy, dz).Magnitude
end

local function setActiveTreadmillHighlightAdornee(adornee: Instance?)
	if not activeTreadmillHighlight then
		local highlight = Instance.new("Highlight")
		highlight.Name = "ClientActiveTreadmillHighlight"
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = CLIENT_HANDLER_CONFIG.TREADMILL_HIGHLIGHT_FILL_COLOR
		highlight.FillTransparency = 1
		highlight.OutlineColor = CLIENT_HANDLER_CONFIG.TREADMILL_HIGHLIGHT_OUTLINE_COLOR
		highlight.OutlineTransparency = 0
		highlight.Enabled = false
		highlight.Parent = Workspace
		activeTreadmillHighlight = highlight
	end

	if not adornee then
		activeTreadmillHighlightAdornee = nil
		activeTreadmillHighlight.Adornee = nil
		activeTreadmillHighlight.Enabled = false
		return
	end

	if activeTreadmillHighlightAdornee == adornee and activeTreadmillHighlight.Enabled then
		return
	end

	activeTreadmillHighlightAdornee = adornee
	activeTreadmillHighlight.Adornee = adornee
	activeTreadmillHighlight.Enabled = true
end

local function getCurrentTreadmillHighlightAdornee(): Instance?
	if player:GetAttribute("Treadmill_Active") ~= true then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	local currentWorld = player:GetAttribute("Current_World")
	if typeof(currentWorld) ~= "string" or currentWorld == "" then
		return nil
	end

	local worldsFolder = Workspace:FindFirstChild("Worlds")
	local world = worldsFolder and worldsFolder:FindFirstChild(currentWorld)
	if not world then
		return nil
	end

	local closestDistance = math.huge
	local closestAdornee: Instance? = nil
	for touchPart, adornee in pairs(observedTreadmillTouchParts) do
		if not touchPart.Parent then
			observedTreadmillTouchParts[touchPart] = nil
			continue
		end

		if not touchPart:IsDescendantOf(world) then
			continue
		end

		local distance = distanceFromPointToPartBounds(touchPart, rootPart.Position)
		if distance <= CLIENT_HANDLER_CONFIG.TREADMILL_HIGHLIGHT_MAX_DISTANCE and distance < closestDistance then
			closestDistance = distance
			closestAdornee = adornee
		end
	end

	return closestAdornee
end

local function updateTreadmillHighlight(dt: number)
	treadmillHighlightUpdateAccumulator += dt
	if treadmillHighlightUpdateAccumulator < CLIENT_HANDLER_CONFIG.TREADMILL_HIGHLIGHT_UPDATE_INTERVAL then
		return
	end

	treadmillHighlightUpdateAccumulator = 0
	setActiveTreadmillHighlightAdornee(getCurrentTreadmillHighlightAdornee())
end

local function onBlockRobloxFreecamAction(
	_: string,
	inputState: Enum.UserInputState,
	inputObject: InputObject
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	if inputObject.KeyCode ~= Enum.KeyCode.P then
		return Enum.ContextActionResult.Pass
	end

	local shiftHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	if shiftHeld then
		return Enum.ContextActionResult.Pass
	end

	return Enum.ContextActionResult.Sink
end

local function cleanupObservedEquippedKart(state: EquippedKartVisualState)
	if state.engineSound and state.engineSound ~= localKartEngineSound and state.engineSound.Parent then
		state.engineSound:Destroy()
	end

	for _, emitter in ipairs(state.smokeEmitters) do
		if emitter.Parent then
			emitter:Destroy()
		end
	end
end

local function setKartSmokeEmittersActive(state: EquippedKartVisualState, enabled: boolean, moving: boolean)
	for _, emitter in ipairs(state.smokeEmitters) do
		if emitter.Parent then
			local shouldEmit = enabled and moving
			emitter.Enabled = shouldEmit
			emitter.Speed = if shouldEmit
				then (state.emitterSpeeds[emitter] or NumberRange.new(0))
				else NumberRange.new(0)
		end
	end
end

local function cleanupObservedTrailVisual(playerToCleanup: Player)
	local trailState = observedTrailVisuals[playerToCleanup]
	if not trailState then
		return
	end

	observedTrailVisuals[playerToCleanup] = nil

	for _, trail in ipairs(trailState.trails) do
		if trail.Parent then
			trail:Destroy()
		end
	end

	for _, emitter in ipairs(trailState.emitters) do
		if emitter.Parent then
			emitter:Destroy()
		end
	end

	if trailState.attachment0 and trailState.attachment0.Parent then
		trailState.attachment0:Destroy()
	end

	if trailState.attachment1 and trailState.attachment1.Parent then
		trailState.attachment1:Destroy()
	end
end

local function cleanupObservedTrailPlayerBindings(playerToCleanup: Player)
	local playerMaid = observedTrailPlayerMaids[playerToCleanup]
	if not playerMaid then
		return
	end

	playerMaid:DoCleaning()
	observedTrailPlayerMaids[playerToCleanup] = nil
end

local function getRemoteTrailBudgetConfig(): RemoteTrailBudgetConfig
	local rawConfig = CoreConfig.clientCulling
	if typeof(rawConfig) ~= "table" then
		return {
			enabled = true,
			updateInterval = 0.25,
			mobileDistanceMultiplier = 0.65,
			fullDistance = 120,
			disableDistance = 360,
			reducedRateMultiplier = 0.5,
			maxVisiblePlayers = 6,
		}
	end

	local function readNumber(value: any, fallback: number): number
		return if typeof(value) == "number" then value else fallback
	end

	return {
		enabled = rawConfig.remoteTrailEnabled ~= false,
		updateInterval = math.max(0.1, readNumber(rawConfig.remoteTrailUpdateInterval, 0.25)),
		mobileDistanceMultiplier = math.clamp(
			readNumber(rawConfig.remoteTrailMobileDistanceMultiplier, 0.65),
			0.1,
			1
		),
		fullDistance = math.max(0, readNumber(rawConfig.remoteTrailFullDistance, 120)),
		disableDistance = math.max(
			readNumber(rawConfig.remoteTrailDisableDistance, 360),
			readNumber(rawConfig.remoteTrailFullDistance, 120)
		),
		reducedRateMultiplier = math.clamp(
			readNumber(rawConfig.remoteTrailReducedRateMultiplier, 0.5),
			0.1,
			1
		),
		maxVisiblePlayers = math.max(0, math.floor(readNumber(rawConfig.remoteTrailMaxVisiblePlayers, 6))),
	}
end

local function setObservedTrailQuality(
	state: ObservedTrailVisualState,
	quality: RemoteTrailQuality,
	reducedRateMultiplier: number
)
	if state.quality == quality then
		return
	end

	local isEnabled = quality ~= "disabled"
	for _, trail in ipairs(state.trails) do
		if trail.Parent then
			trail.Enabled = isEnabled
		end
	end

	for _, emitter in ipairs(state.emitters) do
		if emitter.Parent then
			emitter.Enabled = isEnabled
			local baseRate = state.emitterRates[emitter] or emitter.Rate
			emitter.Rate = if quality == "reduced"
				then baseRate * reducedRateMultiplier
				else baseRate
		end
	end

	state.quality = quality
end

local function syncObservedTrailVisual(playerToSync: Player)
	local equippedTrail = playerToSync:GetAttribute("Trail_Equipped")
	local characterToSync = playerToSync.Character
	local rootPart = characterToSync and (characterToSync:FindFirstChild("HumanoidRootPart") :: BasePart?) or nil
	if typeof(equippedTrail) ~= "string" or equippedTrail == "" or equippedTrail == "None" then
		cleanupObservedTrailVisual(playerToSync)
		return
	end

	if not rootPart then
		local existingState = observedTrailVisuals[playerToSync]
		if existingState then
			existingState.missingUntil = existingState.missingUntil or (os.clock() + CLIENT_HANDLER_CONFIG.TRAIL_VISUAL_MISSING_GRACE)
		end
		return
	end

	local existingState = observedTrailVisuals[playerToSync]
	if
		existingState
		and existingState.character == characterToSync
		and existingState.rootPart == rootPart
		and existingState.equippedTrail == equippedTrail
	then
		existingState.missingUntil = nil
		return
	end

	cleanupObservedTrailVisual(playerToSync)

	local particlesFolder = ReplicatedStorage:FindFirstChild("Particles")
	local trailFolder = particlesFolder and particlesFolder:FindFirstChild(equippedTrail)
	if not trailFolder then
		return
	end

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = CLIENT_HANDLER_CONFIG.CLIENT_TRAIL_ATTACHMENT0_NAME
	attachment0.Position = Vector3.new(0, rootPart.Size.Y * 0.5, 0)
	attachment0.Parent = rootPart

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = CLIENT_HANDLER_CONFIG.CLIENT_TRAIL_ATTACHMENT1_NAME
	attachment1.Position = Vector3.new(0, -rootPart.Size.Y * 0.5, 0)
	attachment1.Parent = rootPart

	local clonedTrails = {}
	local clonedEmitters = {}
	local emitterRates: { [ParticleEmitter]: number } = {}
	local emitterSpeeds: { [ParticleEmitter]: NumberRange } = {}

	for _, descendant in ipairs(trailFolder:GetDescendants()) do
		if descendant:IsA("Trail") then
			local clone = descendant:Clone()
			clone.Name = CLIENT_HANDLER_CONFIG.CLIENT_TRAIL_VISUAL_PREFIX .. descendant.Name
			clone.Attachment0 = attachment0
			clone.Attachment1 = attachment1
			clone.Enabled = true
			clone.Parent = rootPart
			table.insert(clonedTrails, clone)
		elseif descendant:IsA("ParticleEmitter") then
			local clone = descendant:Clone()
			clone.Name = CLIENT_HANDLER_CONFIG.CLIENT_TRAIL_VISUAL_PREFIX .. descendant.Name
			clone.Enabled = true
			clone.Parent = rootPart
			table.insert(clonedEmitters, clone)
			emitterRates[clone] = clone.Rate
			emitterSpeeds[clone] = clone.Speed
		end
	end

	observedTrailVisuals[playerToSync] = {
		player = playerToSync,
		character = characterToSync,
		rootPart = rootPart,
		equippedTrail = equippedTrail,
		attachment0 = attachment0,
		attachment1 = attachment1,
		trails = clonedTrails,
		emitters = clonedEmitters,
		emitterRates = emitterRates,
		emitterSpeeds = emitterSpeeds,
		lastMoving = nil,
		missingUntil = nil,
		quality = nil,
	}
end

local function reconcileObservedTrailVisual(playerToSync: Player)
	local equippedTrail = playerToSync:GetAttribute("Trail_Equipped")
	if typeof(equippedTrail) == "string" and equippedTrail ~= "" and equippedTrail ~= "None" then
		syncObservedTrailVisual(playerToSync)
	else
		cleanupObservedTrailVisual(playerToSync)
	end
end

local function bindObservedTrailPlayer(playerToBind: Player)
	if observedTrailPlayerMaids[playerToBind] then
		return
	end

	local playerMaid = Maid.new()
	observedTrailPlayerMaids[playerToBind] = playerMaid
	local rootWatchConnection: RBXScriptConnection? = nil

	local function refreshRootWatch()
		if rootWatchConnection then
			rootWatchConnection:Disconnect()
			rootWatchConnection = nil
		end

		local currentCharacter = playerToBind.Character
		if not currentCharacter then
			return
		end

		if currentCharacter:FindFirstChild("HumanoidRootPart") then
			return
		end

		rootWatchConnection = currentCharacter.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") and child.Name == "HumanoidRootPart" then
				if rootWatchConnection then
					rootWatchConnection:Disconnect()
					rootWatchConnection = nil
				end
				if playerToBind.Parent then
					reconcileObservedTrailVisual(playerToBind)
				end
			end
		end)
	end

	playerMaid:GiveTask(playerToBind:GetAttributeChangedSignal("Trail_Equipped"):Connect(function()
		reconcileObservedTrailVisual(playerToBind)
	end))

	playerMaid:GiveTask(playerToBind.CharacterAdded:Connect(function()
		refreshRootWatch()
		deferTopLevel(function()
			if playerToBind.Parent then
				reconcileObservedTrailVisual(playerToBind)
			end
		end)
	end))

	playerMaid:GiveTask(playerToBind.CharacterRemoving:Connect(function()
		local existingState = observedTrailVisuals[playerToBind]
		if existingState then
			existingState.missingUntil = os.clock() + CLIENT_HANDLER_CONFIG.TRAIL_VISUAL_MISSING_GRACE
		end
	end))

	playerMaid:GiveTask(function()
		if rootWatchConnection then
			rootWatchConnection:Disconnect()
			rootWatchConnection = nil
		end
		cleanupObservedTrailVisual(playerToBind)
	end)

	refreshRootWatch()
	deferTopLevel(function()
		if playerToBind.Parent then
			reconcileObservedTrailVisual(playerToBind)
		end
	end)
end

local function registerKartShowcase(model: Model)
	if observedKartShowcases[model] then
		return
	end

	local parent = model.Parent
	local isLuckyBlockShowcase = CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockModelNames[model.Name] == true
		and parent ~= nil
		and parent.Name == CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockFolderName
	local basePivot = if not isLuckyBlockShowcase and typeof(model:GetAttribute("ShowcaseBasePivot")) == "CFrame"
		then model:GetAttribute("ShowcaseBasePivot") :: CFrame
		else model:GetPivot()
	local usePartCFrameAnimation = model:GetAttribute("UsePartCFrameAnimation") == true
	local parts: { ShowcasePartState } = {}
	local trackedParts: { [BasePart]: boolean } = {}
	if usePartCFrameAnimation then
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				local relativeCFrame = descendant:GetAttribute("ShowcaseRelativeCFrame")
				table.insert(parts, {
					part = descendant,
					relativeCFrame = if not isLuckyBlockShowcase and typeof(relativeCFrame) == "CFrame"
						then relativeCFrame :: CFrame
						else basePivot:ToObjectSpace(descendant.CFrame),
				})
				trackedParts[descendant] = true
			end
		end
	end

	local configuredRotationDuration = model:GetAttribute("ShowcaseRotationDuration")
	local configuredVisualOffset = model:GetAttribute("VisualOffset")
	showcaseRegistrationSequence += 1
	local visualUpdatePhase = (showcaseRegistrationSequence * 0.61803398875) % 1
	local rotationDuration = if typeof(configuredRotationDuration) == "number"
		then math.max(0, configuredRotationDuration)
		elseif isLuckyBlockShowcase then CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockRotationDuration
		else 0
	local visualOffset = if typeof(configuredVisualOffset) == "number"
		then configuredVisualOffset
		elseif isLuckyBlockShowcase then math.random()
		else 0

	local showcaseState: ShowcaseVisualState = {
		model = model,
		basePivot = basePivot,
		visualOffset = visualOffset,
		visualUpdatePhase = visualUpdatePhase,
		visualUpdatePhaseInitialized = false,
		rotationDuration = rotationDuration,
		parts = parts,
		trackedParts = trackedParts,
		usePartCFrameAnimation = usePartCFrameAnimation,
		descendantAddedConnection = nil,
		descendantRemovingConnection = nil,
		visualUpdateAccumulator = 0,
		cameraBucket = nil,
		cameraBucketDistance = nil,
		cameraBucketOnScreen = nil,
		cameraBucketAccumulator = CLIENT_HANDLER_CONFIG.KART_CAMERA_BUCKET_REFRESH_INTERVAL,
		isPoliceKart = model:GetAttribute("IsPoliceKart") == true,
		lightBarBlue = findBasePartByName(model, "LightBarBlue"),
		lightBarRed = findBasePartByName(model, "LightBarRed"),
		spotlightLensL = findBasePartByName(model, "SpotlightLensL"),
		spotlightLensR = findBasePartByName(model, "SpotlightLensR"),
	}
	observedKartShowcases[model] = showcaseState

	if usePartCFrameAnimation then
		showcaseState.descendantAddedConnection = model.DescendantAdded:Connect(function(descendant)
			if not descendant:IsA("BasePart") or showcaseState.trackedParts[descendant] then
				return
			end

			local relativeCFrame = descendant:GetAttribute("ShowcaseRelativeCFrame")
			table.insert(showcaseState.parts, {
				part = descendant,
				relativeCFrame = if not isLuckyBlockShowcase and typeof(relativeCFrame) == "CFrame"
					then relativeCFrame :: CFrame
					else basePivot:ToObjectSpace(descendant.CFrame),
			})
			showcaseState.trackedParts[descendant] = true
		end)
		showcaseState.descendantRemovingConnection = model.DescendantRemoving:Connect(function(descendant)
			if not descendant:IsA("BasePart") then
				return
			end

			showcaseState.trackedParts[descendant] = nil
			for index = #showcaseState.parts, 1, -1 do
				if showcaseState.parts[index].part == descendant then
					table.remove(showcaseState.parts, index)
				end
			end
		end)
	end
end

local function cleanupKartShowcase(model: Model, restoreBasePose: boolean)
	local showcaseState = observedKartShowcases[model]
	if not showcaseState then
		return
	end

	if showcaseState.descendantAddedConnection then
		showcaseState.descendantAddedConnection:Disconnect()
		showcaseState.descendantAddedConnection = nil
	end
	if showcaseState.descendantRemovingConnection then
		showcaseState.descendantRemovingConnection:Disconnect()
		showcaseState.descendantRemovingConnection = nil
	end

	if restoreBasePose and model.Parent then
		if showcaseState.usePartCFrameAnimation then
			for _, partState in ipairs(showcaseState.parts) do
				if partState.part.Parent then
					partState.part.CFrame = showcaseState.basePivot * partState.relativeCFrame
				end
			end
		else
			model:PivotTo(showcaseState.basePivot)
		end
	end

	observedKartShowcases[model] = nil
end

local function getKartOwner(model: Model): Player?
	local ownerUserId = model:GetAttribute("OwnerUserId")
	if typeof(ownerUserId) == "number" then
		return Players:GetPlayerByUserId(ownerUserId)
	end

	local taggedOwnerUserId = model:GetAttribute("KartOwnerUserId")
	if typeof(taggedOwnerUserId) == "number" then
		return Players:GetPlayerByUserId(taggedOwnerUserId)
	end

	-- Fallback to legacy character parenting
	return Players:GetPlayerFromCharacter(model.Parent)
end

local function registerEquippedKart(model: Model)
	if observedEquippedKarts[model] then
		return
	end

	local owner = getKartOwner(model)
	local ownerCharacter = owner and owner.Character or nil
	local ownerHumanoid = ownerCharacter and (ownerCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?) or nil
	local rootPart = ownerCharacter and (ownerCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?) or nil
	local engineParent = getEngineParent(model)
	local engineSoundId = model:GetAttribute("EngineSoundId")
	local engineSoundParent = if owner == player then rootPart else engineParent
	if owner == player and model:GetAttribute("DisableEngineSound") == true then
		if localKartEngineSound then
			localKartEngineSound:Stop()
			localKartEngineSound:Destroy()
			localKartEngineSound = nil
		end
		localKartEngineSoundLastSeenAt = nil
	end
	if
		owner == player
		and localKartEngineSound
		and localKartEngineSound.Parent
		and rootPart
		and localKartEngineSound.Parent ~= rootPart
	then
		localKartEngineSound.Parent = rootPart
	end
	local engineSound = if engineSoundParent and typeof(engineSoundId) == "string" and engineSoundId ~= ""
		then createOrUpdateClientKartEngineSound(engineSoundParent, engineSoundId)
		else nil
	if owner == player and engineSound then
		localKartEngineSound = engineSound
		localKartEngineSoundLastSeenAt = os.clock()
	end
	local smokeEmitters = {}
	local emitterSpeeds: { [ParticleEmitter]: NumberRange } = {}
	if rootPart then
		smokeEmitters, emitterSpeeds = createClientKartSmokeEmitters(rootPart)
	end

	observedEquippedKarts[model] = {
		model = model,
		owner = owner,
		ownerCharacter = ownerCharacter,
		ownerHumanoid = ownerHumanoid,
		rootPart = rootPart,
		engineParent = engineParent,
		engineSound = engineSound,
		engineSoundId = if typeof(engineSoundId) == "string" then engineSoundId else nil,
		smokeEmitters = smokeEmitters,
		emitterSpeeds = emitterSpeeds,
		visualOffset = model:GetAttribute("VisualOffset") or 0,
		isPoliceKart = model:GetAttribute("IsPoliceKart") == true,
		lightBarBlue = findBasePartByName(model, "LightBarBlue"),
		lightBarRed = findBasePartByName(model, "LightBarRed"),
		spotlightLensL = findBasePartByName(model, "SpotlightLensL"),
		spotlightLensR = findBasePartByName(model, "SpotlightLensR"),
		wheelMotors = getClientWheelMotors(engineParent),
		spinAngle = 0,
		visualUpdateAccumulator = 0,
		wheelUpdateAccumulator = 0,
		idleEffectsAccumulator = 0,
		stateRefreshAccumulator = 0,
		cameraBucket = nil,
		cameraBucketDistance = nil,
		cameraBucketOnScreen = nil,
		cameraBucketAccumulator = CLIENT_HANDLER_CONFIG.KART_CAMERA_BUCKET_REFRESH_INTERVAL,
		lastMoving = nil,
		lastPlaybackSpeed = nil,
		offscreenEffectsDisabled = false,
	}

	local registeredState = observedEquippedKarts[model]
	if registeredState.isPoliceKart then
		applyCurrentPoliceKartVisuals(
			registeredState.visualOffset,
			registeredState.lightBarBlue,
			registeredState.lightBarRed,
			registeredState.spotlightLensL,
			registeredState.spotlightLensR
		)
	end

	DebugModule.debugInfo(
		string.format(
			"registerEquippedKart | equippedKart=%s | model=%s | owner=%s | rootPart=%s | engineParent=%s | engineSound=%s | smokeEmitters=%d | wheelMotors=%d",
			tostring(player:GetAttribute("Kart_Equipped")),
			model:GetFullName(),
			if owner then owner.Name else "nil",
			tostring(rootPart ~= nil),
			tostring(engineParent ~= nil),
			tostring(engineSound ~= nil),
			#smokeEmitters,
			#observedEquippedKarts[model].wheelMotors
		),
		"PlayerClientHandler"
	)
end

local function registerObservedKartVisual(instance: Instance)
	local showcaseModel = if instance:IsA("Model") and instance.Name == CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.kartModelName
		then instance
		else instance:FindFirstAncestor(CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.kartModelName)
	if not showcaseModel and instance:IsA("Model") then
		local parent = instance.Parent
		if CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockModelNames[instance.Name] == true
			and parent ~= nil
			and parent.Name == CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockFolderName then
			showcaseModel = instance
		end
	end
	if showcaseModel and showcaseModel:IsA("Model") then
		registerKartShowcase(showcaseModel)
	end

	local equippedKartModel = if instance:IsA("Model") and instance.Name == CLIENT_HANDLER_CONFIG.EQUIPPED_KART_MODEL_NAME
		then instance
		else instance:FindFirstAncestor(CLIENT_HANDLER_CONFIG.EQUIPPED_KART_MODEL_NAME)
	if equippedKartModel and equippedKartModel:IsA("Model") then
		registerEquippedKart(equippedKartModel)
	end
end

local function isKartVisualModel(instance: Instance): boolean
	if not instance:IsA("Model") then
		return false
	end
	local parent = instance.Parent
	return instance.Name == CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.kartModelName
		or instance.Name == CLIENT_HANDLER_CONFIG.EQUIPPED_KART_MODEL_NAME
		or (
			CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockModelNames[instance.Name] == true
			and parent ~= nil
			and parent.Name == CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockFolderName
		)
end

local function beginSourceRootBinding(root: Instance, bindings: { [Instance]: Maid }): Maid
	local rootMaid = Maid.new()
	local cleanedRoot = false
	bindings[root] = rootMaid

	local function cleanupRootBinding()
		if cleanedRoot then
			return
		end
		cleanedRoot = true
		if bindings[root] == rootMaid then
			bindings[root] = nil
		end
		rootMaid:DoCleaning()
	end

	rootMaid:GiveTask(root.AncestryChanged:Connect(function()
		if not root:IsDescendantOf(Workspace) then
			cleanupRootBinding()
		end
	end))

	return rootMaid
end

local function bindKartVisualSourceRoot(root: Instance)
	if observedKartVisualSourceRoots[root] or not root:IsDescendantOf(Workspace) then
		return
	end

	local rootMaid = beginSourceRootBinding(root, observedKartVisualSourceRoots)
	rootMaid:GiveTask(root.DescendantAdded:Connect(function(descendant)
		if isKartVisualModel(descendant) then
			registerObservedKartVisual(descendant)
		end
	end))
	rootMaid:GiveTask(root.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("Model")
			and (
				descendant.Name == CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.kartModelName
				or CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockModelNames[descendant.Name] == true
			) then
			cleanupKartShowcase(descendant, true)
		end
	end))

	for _, descendant in ipairs(root:GetDescendants()) do
		if isKartVisualModel(descendant) then
			registerObservedKartVisual(descendant)
		end
	end
end

local function refreshKartVisualSourceBindings()
	local worldsFolder = Workspace:FindFirstChild("Worlds")
	if worldsFolder then
		for _, world in ipairs(worldsFolder:GetChildren()) do
			local kartButtonsFolder = world:FindFirstChild("KartButtons")
			if kartButtonsFolder then
				bindKartVisualSourceRoot(kartButtonsFolder)
			end

			local eventKartButtonsFolder = world:FindFirstChild("EventKartButtons")
			if eventKartButtonsFolder then
				bindKartVisualSourceRoot(eventKartButtonsFolder)
			end

			local luckyBlocksFolder = world:FindFirstChild(CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockFolderName)
			if luckyBlocksFolder then
				bindKartVisualSourceRoot(luckyBlocksFolder)
			end
		end
	end

	local kartHolderFolder = Workspace:FindFirstChild(CLIENT_HANDLER_CONFIG.KART_VISUAL_HOLDER_NAME)
	if kartHolderFolder then
		bindKartVisualSourceRoot(kartHolderFolder)
	end
end

local function findLocalEquippedKartModel(): Model?
	local kartHolder = Workspace:FindFirstChild(CLIENT_HANDLER_CONFIG.KART_VISUAL_HOLDER_NAME)
	if not kartHolder then
		return nil
	end

	for _, child in ipairs(kartHolder:GetChildren()) do
		if child:IsA("Model") and child.Name == CLIENT_HANDLER_CONFIG.EQUIPPED_KART_MODEL_NAME then
			local ownerUserId = child:GetAttribute("OwnerUserId")
			local taggedOwnerUserId = child:GetAttribute("KartOwnerUserId")
			if ownerUserId == player.UserId or taggedOwnerUserId == player.UserId then
				return child
			end
		end
	end

	return nil
end

local function isClientKartVisualHealthy(model: Model?): boolean
	if not model or not model:IsDescendantOf(Workspace) then
		return false
	end

	local seatBase = model:FindFirstChild("SeatBase", true)
	return seatBase ~= nil
		and seatBase:IsA("BasePart")
		and model:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

local function reconcileLocalKartVisual()
	if isCleaningUp or player:GetAttribute("Data_Loaded") ~= true or humanoid.Health <= 0 then
		localKartVisualMissingSince = nil
		return
	end

	local model = findLocalEquippedKartModel()
	if model then
		registerObservedKartVisual(model)
	end

	if isClientKartVisualHealthy(model) then
		localKartVisualMissingSince = nil
		return
	end

	local now = os.clock()
	local missingSince = localKartVisualMissingSince
	if missingSince == nil then
		localKartVisualMissingSince = now
		return
	end

	if now - missingSince < CLIENT_HANDLER_CONFIG.KART_CLIENT_VISUAL_MISSING_GRACE then
		return
	end
	if now - lastKartVisualResyncAt < CLIENT_HANDLER_CONFIG.KART_CLIENT_VISUAL_RESYNC_COOLDOWN then
		return
	end

	lastKartVisualResyncAt = now
	KartVisualResync:FireServer()
	DebugModule.debugWarn(
		"Client equipped kart visual incomplete; requested server resync | model=" .. tostring(model ~= nil),
		"PlayerClientHandler"
	)
end

local function refreshEquippedKartState(state: EquippedKartVisualState)
	local owner = getKartOwner(state.model)
	state.owner = owner

	local nextOwnerCharacter = owner and owner.Character or nil
	if nextOwnerCharacter ~= state.ownerCharacter then
		state.ownerCharacter = nextOwnerCharacter
		state.ownerHumanoid = if nextOwnerCharacter
			then nextOwnerCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?
			else nil
	elseif state.ownerHumanoid and state.ownerHumanoid.Parent == nil then
		state.ownerHumanoid = nil
	end

	local nextRootPart = nextOwnerCharacter and (nextOwnerCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?)
		or nil
	local nextEngineParent = getEngineParent(state.model)
	local nextEngineSoundId = state.model:GetAttribute("EngineSoundId")

	-- If rootPart changed OR if we previously had no motors but the engineParent (seatBase) just appeared
	if nextRootPart ~= state.rootPart or (#state.wheelMotors == 0 and nextEngineParent ~= nil) then
		for _, emitter in ipairs(state.smokeEmitters) do
			if emitter.Parent then
				emitter:Destroy()
			end
		end

		state.rootPart = nextRootPart
		state.smokeEmitters = {}
		state.emitterSpeeds = {}
		state.wheelMotors = getClientWheelMotors(nextEngineParent)
		state.spinAngle = 0
		state.wheelUpdateAccumulator = 0
		state.idleEffectsAccumulator = 0
		state.lastMoving = nil
		state.offscreenEffectsDisabled = false
		if nextOwnerCharacter then
			state.ownerHumanoid = nextOwnerCharacter:FindFirstChildOfClass("Humanoid") :: Humanoid?
		end
		if nextRootPart then
			state.smokeEmitters, state.emitterSpeeds = createClientKartSmokeEmitters(nextRootPart)
		end

		if nextRootPart ~= state.rootPart then
			DebugModule.debugInfo(
				string.format(
					"refreshEquippedKartState root/motor refresh | equippedKart=%s | model=%s | owner=%s | rootPart=%s | smokeEmitters=%d | wheelMotors=%d",
					tostring(player:GetAttribute("Kart_Equipped")),
					state.model:GetFullName(),
					if owner then owner.Name else "nil",
					tostring(nextRootPart ~= nil),
					#state.smokeEmitters,
					#state.wheelMotors
				),
				"PlayerClientHandler"
			)
		end
	end

	if nextEngineParent ~= state.engineParent then
		state.engineParent = nextEngineParent
		state.wheelMotors = getClientWheelMotors(nextEngineParent)
		state.lastPlaybackSpeed = nil

		DebugModule.debugInfo(
			string.format(
				"refreshEquippedKartState engine parent swap | equippedKart=%s | model=%s | engineParent=%s",
				tostring(player:GetAttribute("Kart_Equipped")),
				state.model:GetFullName(),
				tostring(nextEngineParent ~= nil)
			),
			"PlayerClientHandler"
		)
	end

	local nextEngineSoundParent = if owner == player then nextRootPart else nextEngineParent
	if
		owner == player
		and localKartEngineSound
		and localKartEngineSound.Parent
		and nextRootPart
		and localKartEngineSound.Parent ~= nextRootPart
	then
		localKartEngineSound.Parent = nextRootPart
	end
	if typeof(nextEngineSoundId) == "string" and nextEngineSoundId ~= "" and nextEngineSoundParent then
		if
			state.engineSoundId ~= nextEngineSoundId
			or not state.engineSound
			or state.engineSound.Parent ~= nextEngineSoundParent
		then
			if state.engineSound and state.engineSound ~= localKartEngineSound and state.engineSound.Parent then
				state.engineSound:Destroy()
			end
			state.engineSound = createOrUpdateClientKartEngineSound(nextEngineSoundParent, nextEngineSoundId)
			state.engineSoundId = nextEngineSoundId
			if owner == player and state.engineSound then
				localKartEngineSound = state.engineSound
				localKartEngineSoundLastSeenAt = os.clock()
			end

			DebugModule.debugInfo(
				string.format(
					"refreshEquippedKartState engine sound recreate | equippedKart=%s | model=%s | soundId=%s | parent=%s",
					tostring(player:GetAttribute("Kart_Equipped")),
					state.model:GetFullName(),
					nextEngineSoundId,
					nextEngineSoundParent:GetFullName()
				),
				"PlayerClientHandler"
			)
		end
	elseif state.engineSound and state.engineSound ~= localKartEngineSound and state.engineSound.Parent then
		state.engineSound:Destroy()
		state.engineSound = nil
		state.engineSoundId = nil
		state.lastPlaybackSpeed = nil
	elseif state.engineSound == localKartEngineSound then
		state.engineSound = nil
		state.engineSoundId = nil
		state.lastPlaybackSpeed = nil
	end

	state.visualOffset = state.model:GetAttribute("VisualOffset") or state.visualOffset
	state.isPoliceKart = state.model:GetAttribute("IsPoliceKart") == true
	state.lightBarBlue = findBasePartByName(state.model, "LightBarBlue")
	state.lightBarRed = findBasePartByName(state.model, "LightBarRed")
	state.spotlightLensL = findBasePartByName(state.model, "SpotlightLensL")
	state.spotlightLensR = findBasePartByName(state.model, "SpotlightLensR")
	if state.isPoliceKart then
		applyCurrentPoliceKartVisuals(
			state.visualOffset,
			state.lightBarBlue,
			state.lightBarRed,
			state.spotlightLensL,
			state.spotlightLensR
		)
	end
end

local function resolveVisualDistanceBucket(
	distance: number,
	onScreen: boolean,
	nearDistance: number,
	farDistance: number
): VisualDistanceBucket
	if distance <= nearDistance then
		return "near"
	end

	if onScreen and distance <= farDistance then
		return "mid"
	end

	if onScreen then
		return "far"
	end

	return "offscreen"
end

local function getKartVisualUpdateIntervalForBucket(bucket: VisualDistanceBucket, owner: Player?): number
	if owner == player then
		return 0
	end

	if bucket == "near" then
		return 0
	end
	if bucket == "mid" then
		return CLIENT_HANDLER_CONFIG.KART_VISUAL_MID_INTERVAL
	end
	if bucket == "far" then
		return CLIENT_HANDLER_CONFIG.KART_VISUAL_FAR_INTERVAL
	end

	return CLIENT_HANDLER_CONFIG.KART_VISUAL_OFFSCREEN_INTERVAL
end

local function getKartStateRefreshIntervalForBucket(bucket: VisualDistanceBucket): number
	if bucket == "near" then
		return CLIENT_HANDLER_CONFIG.KART_STATE_REFRESH_INTERVAL
	end
	if bucket == "mid" then
		return CLIENT_HANDLER_CONFIG.KART_STATE_REFRESH_MID_INTERVAL
	end

	return CLIENT_HANDLER_CONFIG.KART_STATE_REFRESH_FAR_INTERVAL
end

local function getShowcaseVisualUpdateInterval(distance: number, onScreen: boolean): number
	if not onScreen then
		return math.huge
	end

	if distance <= CLIENT_HANDLER_CONFIG.KART_SHOWCASE_FULL_RATE_DISTANCE then
		return 1 / CLIENT_HANDLER_CONFIG.KART_SHOWCASE_TARGET_FPS_FULL
	end

	local targetFps: number
	if distance <= CLIENT_HANDLER_CONFIG.KART_SHOWCASE_NEAR_DISTANCE then
		local nearSpan = math.max(CLIENT_HANDLER_CONFIG.KART_SHOWCASE_NEAR_DISTANCE - CLIENT_HANDLER_CONFIG.KART_SHOWCASE_FULL_RATE_DISTANCE, 1)
		local nearAlpha = math.clamp((distance - CLIENT_HANDLER_CONFIG.KART_SHOWCASE_FULL_RATE_DISTANCE) / nearSpan, 0, 1)
		targetFps = CLIENT_HANDLER_CONFIG.KART_SHOWCASE_TARGET_FPS_FULL
			+ ((CLIENT_HANDLER_CONFIG.KART_SHOWCASE_TARGET_FPS_FAR - CLIENT_HANDLER_CONFIG.KART_SHOWCASE_TARGET_FPS_FULL) * nearAlpha)
	elseif distance <= CLIENT_HANDLER_CONFIG.KART_SHOWCASE_FAR_DISTANCE then
		local farSpan = math.max(CLIENT_HANDLER_CONFIG.KART_SHOWCASE_FAR_DISTANCE - CLIENT_HANDLER_CONFIG.KART_SHOWCASE_NEAR_DISTANCE, 1)
		local farAlpha = math.clamp((distance - CLIENT_HANDLER_CONFIG.KART_SHOWCASE_NEAR_DISTANCE) / farSpan, 0, 1)
		targetFps = CLIENT_HANDLER_CONFIG.KART_SHOWCASE_TARGET_FPS_FAR
			+ ((CLIENT_HANDLER_CONFIG.KART_SHOWCASE_TARGET_FPS_VERY_FAR - CLIENT_HANDLER_CONFIG.KART_SHOWCASE_TARGET_FPS_FAR) * farAlpha)
	elseif distance <= CLIENT_HANDLER_CONFIG.KART_SHOWCASE_PAUSE_DISTANCE then
		targetFps = CLIENT_HANDLER_CONFIG.KART_SHOWCASE_TARGET_FPS_VERY_FAR
	else
		return math.huge
	end

	local clampedTargetFps = math.clamp(targetFps, CLIENT_HANDLER_CONFIG.KART_SHOWCASE_TARGET_FPS_VERY_FAR, CLIENT_HANDLER_CONFIG.KART_SHOWCASE_TARGET_FPS_FULL)
	return 1 / clampedTargetFps
end

local function computeEquippedKartCameraBucket(
	kartState: EquippedKartVisualState
): (VisualDistanceBucket, number, boolean)
	if kartState.owner == player then
		return "near", 0, true
	end

	local currentCamera = Workspace.CurrentCamera
	local rootPart = kartState.rootPart
	if not currentCamera or not rootPart then
		return "offscreen", math.huge, false
	end

	local distance = (rootPart.Position - currentCamera.CFrame.Position).Magnitude
	local _, onScreen = currentCamera:WorldToViewportPoint(rootPart.Position)
	local bucket = resolveVisualDistanceBucket(distance, onScreen, CLIENT_HANDLER_CONFIG.KART_VISUAL_NEAR_DISTANCE, CLIENT_HANDLER_CONFIG.KART_VISUAL_FAR_DISTANCE)
	return bucket, distance, onScreen
end

local function getCachedEquippedKartCameraBucket(
	kartState: EquippedKartVisualState,
	dt: number
): (VisualDistanceBucket, number, boolean)
	kartState.cameraBucketAccumulator += dt
	if
		kartState.cameraBucket ~= nil
		and kartState.cameraBucketAccumulator < CLIENT_HANDLER_CONFIG.KART_CAMERA_BUCKET_REFRESH_INTERVAL
		and kartState.cameraBucketDistance ~= nil
		and kartState.cameraBucketOnScreen ~= nil
	then
		return kartState.cameraBucket, kartState.cameraBucketDistance, kartState.cameraBucketOnScreen
	end

	local bucket, distance, onScreen = computeEquippedKartCameraBucket(kartState)
	kartState.cameraBucket = bucket
	kartState.cameraBucketDistance = distance
	kartState.cameraBucketOnScreen = onScreen
	kartState.cameraBucketAccumulator = 0
	return bucket, distance, onScreen
end

local function computeShowcaseCameraBucket(showcaseState: ShowcaseVisualState): (VisualDistanceBucket, number, boolean)
	local currentCamera = Workspace.CurrentCamera
	if not currentCamera then
		return "offscreen", math.huge, false
	end

	local showcasePosition = showcaseState.basePivot.Position
	local distance = (showcasePosition - currentCamera.CFrame.Position).Magnitude
	local _, onScreen = currentCamera:WorldToViewportPoint(showcasePosition)
	local bucket =
		resolveVisualDistanceBucket(distance, onScreen, CLIENT_HANDLER_CONFIG.KART_SHOWCASE_NEAR_DISTANCE, CLIENT_HANDLER_CONFIG.KART_SHOWCASE_FAR_DISTANCE)
	return bucket, distance, onScreen
end

local function getCachedShowcaseCameraBucket(
	showcaseState: ShowcaseVisualState,
	dt: number
): (VisualDistanceBucket, number, boolean)
	showcaseState.cameraBucketAccumulator += dt
	if
		showcaseState.cameraBucket ~= nil
		and showcaseState.cameraBucketAccumulator < CLIENT_HANDLER_CONFIG.KART_CAMERA_BUCKET_REFRESH_INTERVAL
		and showcaseState.cameraBucketDistance ~= nil
		and showcaseState.cameraBucketOnScreen ~= nil
	then
		return showcaseState.cameraBucket, showcaseState.cameraBucketDistance, showcaseState.cameraBucketOnScreen
	end

	local bucket, distance, onScreen = computeShowcaseCameraBucket(showcaseState)
	showcaseState.cameraBucket = bucket
	showcaseState.cameraBucketDistance = distance
	showcaseState.cameraBucketOnScreen = onScreen
	showcaseState.cameraBucketAccumulator = 0
	return bucket, distance, onScreen
end

local function getWheelMotorUpdateInterval(kartState: EquippedKartVisualState, visualUpdateInterval: number): number
	if kartState.owner == player then
		return 0
	end

	local effectiveVisualInterval = if visualUpdateInterval > 0
		then visualUpdateInterval
		else CLIENT_HANDLER_CONFIG.KART_VISUAL_FRAMELOCK_INTERVAL
	return math.max(CLIENT_HANDLER_CONFIG.REMOTE_KART_WHEEL_UPDATE_INTERVAL, effectiveVisualInterval)
end

local function updateObservedKartShowcases(dt: number)
	if next(observedKartShowcases) == nil then
		return
	end

	local syncedTime = Workspace:GetServerTimeNow()

	for model, showcaseState in pairs(observedKartShowcases) do
		if not model.Parent then
			cleanupKartShowcase(model, false)
			continue
		end

		local showcaseBucket, showcaseDistance, showcaseOnScreen = getCachedShowcaseCameraBucket(showcaseState, dt)
		local showcaseUpdateInterval = getShowcaseVisualUpdateInterval(showcaseDistance, showcaseOnScreen)
		if showcaseUpdateInterval == math.huge then
			showcaseState.visualUpdateAccumulator = 0
			continue
		end
		if not showcaseState.visualUpdatePhaseInitialized then
			showcaseState.visualUpdateAccumulator = showcaseUpdateInterval * showcaseState.visualUpdatePhase
			showcaseState.visualUpdatePhaseInitialized = true
		end
		showcaseState.visualUpdateAccumulator += dt
		if showcaseState.visualUpdateAccumulator < showcaseUpdateInterval then
			continue
		end
		showcaseState.visualUpdateAccumulator %= showcaseUpdateInterval

		local bobOffset = math.sin((syncedTime + showcaseState.visualOffset) * 2) * CLIENT_HANDLER_CONFIG.KART_SHOWCASE_BOB_AMPLITUDE
		local showcasePivot = showcaseState.basePivot * CFrame.new(0, bobOffset, 0)
		if showcaseState.rotationDuration > 0 then
			local rotationAlpha = ((syncedTime + showcaseState.visualOffset) % showcaseState.rotationDuration)
				/ showcaseState.rotationDuration
			showcasePivot *= CFrame.Angles(0, math.rad(rotationAlpha * 360), 0)
		end

		if showcaseState.usePartCFrameAnimation then
			for _, partState in ipairs(showcaseState.parts) do
				if partState.part.Parent then
					partState.part.CFrame = showcasePivot * partState.relativeCFrame
				end
			end
		else
			showcaseState.model:PivotTo(showcasePivot)
		end

		if showcaseState.isPoliceKart and showcaseOnScreen then
			applyPoliceKartVisuals(
				syncedTime + showcaseState.visualOffset,
				showcaseState.lightBarBlue,
				showcaseState.lightBarRed,
				showcaseState.spotlightLensL,
				showcaseState.spotlightLensR
			)
		end
	end
end

local function updateObservedEquippedKartVisuals(dt: number)
	local syncedTime = Workspace:GetServerTimeNow()
	local localKartObserved = false

	for model, kartState in pairs(observedEquippedKarts) do
		if not model.Parent then
			cleanupObservedEquippedKart(kartState)
			observedEquippedKarts[model] = nil
			continue
		end

		local cameraBucket, cameraDistance, _ = getCachedEquippedKartCameraBucket(kartState, dt)
		local stateRefreshInterval = getKartStateRefreshIntervalForBucket(cameraBucket)
		kartState.stateRefreshAccumulator += dt
		local shouldRefreshState = kartState.stateRefreshAccumulator >= stateRefreshInterval
		if not kartState.owner or not kartState.owner.Parent then
			shouldRefreshState = true
		end
		if not kartState.rootPart or not kartState.rootPart.Parent then
			shouldRefreshState = true
		end
		if not kartState.engineParent or not kartState.engineParent.Parent then
			shouldRefreshState = true
		end
		if shouldRefreshState then
			refreshEquippedKartState(kartState)
			kartState.stateRefreshAccumulator = 0
			local refreshedOnScreen = false
			cameraBucket, cameraDistance, refreshedOnScreen = computeEquippedKartCameraBucket(kartState)
			kartState.cameraBucket = cameraBucket
			kartState.cameraBucketDistance = cameraDistance
			kartState.cameraBucketOnScreen = refreshedOnScreen
			kartState.cameraBucketAccumulator = 0
		end
		if kartState.owner == player then
			localKartObserved = true
			localKartEngineSoundLastSeenAt = os.clock()
		end

		local isRemoteOffscreen = kartState.owner ~= player and cameraBucket == "offscreen"
		if isRemoteOffscreen then
			if not kartState.offscreenEffectsDisabled then
				setKartSmokeEmittersActive(kartState, false, false)
				kartState.offscreenEffectsDisabled = true
				kartState.lastMoving = nil
			end

			kartState.visualUpdateAccumulator = 0
			kartState.wheelUpdateAccumulator = 0
			kartState.idleEffectsAccumulator = 0
			continue
		elseif kartState.offscreenEffectsDisabled then
			kartState.offscreenEffectsDisabled = false
			kartState.lastMoving = nil
		end

		kartState.visualUpdateAccumulator += dt

		local updateInterval = getKartVisualUpdateIntervalForBucket(cameraBucket, kartState.owner)
		if updateInterval > 0 and kartState.visualUpdateAccumulator < updateInterval then
			continue
		end

		local effectiveDt = if updateInterval > 0 then kartState.visualUpdateAccumulator else dt
		kartState.visualUpdateAccumulator = 0

		local horizontalVelocity = 0
		local treadmillActive = false
		local humanoidForSpeed = kartState.ownerHumanoid
		if humanoidForSpeed and humanoidForSpeed.Parent == nil then
			humanoidForSpeed = nil
			kartState.ownerHumanoid = nil
		end
		if kartState.owner and kartState.rootPart then
			treadmillActive = kartState.owner:GetAttribute("Treadmill_Active") == true
			horizontalVelocity = Vector3.new(
				kartState.rootPart.AssemblyLinearVelocity.X,
				0,
				kartState.rootPart.AssemblyLinearVelocity.Z
			).Magnitude
		end

		local moving = horizontalVelocity > 0.05 or treadmillActive
		local wheelSpeed = horizontalVelocity
		if treadmillActive and wheelSpeed < 0.05 and humanoidForSpeed then
			wheelSpeed = humanoidForSpeed.WalkSpeed
		end

		kartState.wheelUpdateAccumulator += effectiveDt
		local wheelUpdateInterval = getWheelMotorUpdateInterval(kartState, updateInterval)
		if wheelUpdateInterval <= 0 or kartState.wheelUpdateAccumulator >= wheelUpdateInterval then
			local wheelDt = if wheelUpdateInterval <= 0 then effectiveDt else kartState.wheelUpdateAccumulator
			kartState.wheelUpdateAccumulator = 0

			if moving then
				local referenceRadius = kartState.wheelMotors[1] and kartState.wheelMotors[1].radius or 1
				kartState.spinAngle += (wheelSpeed / math.max(referenceRadius, 0.05)) * wheelDt
			end

			for _, wheelState in ipairs(kartState.wheelMotors) do
				if wheelState.motor.Parent then
					wheelState.motor.C0 = wheelState.baseC0 * CFrame.Angles(-kartState.spinAngle, 0, 0)
				end
			end
		end

		local movingStateChanged = kartState.lastMoving ~= moving
		local shouldRunEffectsUpdate = movingStateChanged
		if not shouldRunEffectsUpdate then
			if kartState.owner ~= player and not moving and not treadmillActive then
				kartState.idleEffectsAccumulator += effectiveDt
				if kartState.idleEffectsAccumulator >= CLIENT_HANDLER_CONFIG.REMOTE_KART_IDLE_EFFECT_INTERVAL then
					kartState.idleEffectsAccumulator = 0
					shouldRunEffectsUpdate = true
				end
			else
				kartState.idleEffectsAccumulator = 0
				shouldRunEffectsUpdate = true
			end
		else
			kartState.idleEffectsAccumulator = 0
		end

		if shouldRunEffectsUpdate and kartState.engineSound and kartState.engineSound.Parent then
			local normalizedSpeed = math.clamp(horizontalVelocity / CLIENT_HANDLER_CONFIG.KART_ENGINE_REFERENCE_SPEED, 0, 1)
			local playbackSpeed = 0.5 + (normalizedSpeed * 1.5)
			if treadmillActive then
				playbackSpeed = 2.0
			end
			if humanoidForSpeed and treadmillActive and horizontalVelocity < 0.05 then
				local walkSpeedNormalized = math.clamp(humanoidForSpeed.WalkSpeed / CLIENT_HANDLER_CONFIG.KART_ENGINE_REFERENCE_SPEED, 0, 1)
				playbackSpeed = 0.5 + (walkSpeedNormalized * 1.5)
				playbackSpeed = math.max(playbackSpeed, 2.0)
			end
			local clampedPlaybackSpeed = math.clamp(playbackSpeed, 0.5, 2.0)
			if
				kartState.lastPlaybackSpeed == nil
				or math.abs(kartState.lastPlaybackSpeed - clampedPlaybackSpeed) > 0.01
			then
				kartState.engineSound.PlaybackSpeed = clampedPlaybackSpeed
				kartState.lastPlaybackSpeed = clampedPlaybackSpeed
			end
		end

		if shouldRunEffectsUpdate and movingStateChanged then
			setKartSmokeEmittersActive(kartState, true, moving)
			kartState.lastMoving = moving
		end

		local shouldUpdatePoliceLights = kartState.owner == player
			or cameraBucket ~= "offscreen"
			or cameraDistance <= CLIENT_HANDLER_CONFIG.KART_VISUAL_FAR_DISTANCE
		if kartState.isPoliceKart and shouldUpdatePoliceLights then
			applyPoliceKartVisuals(
				syncedTime + kartState.visualOffset,
				kartState.lightBarBlue,
				kartState.lightBarRed,
				kartState.spotlightLensL,
				kartState.spotlightLensR
			)
		end
	end

	if localKartObserved then
		localKartEngineSoundLastSeenAt = os.clock()
	elseif localKartEngineSound
		and localKartEngineSound.IsPlaying
		and localKartEngineSoundLastSeenAt
		and os.clock() - localKartEngineSoundLastSeenAt >= CLIENT_HANDLER_CONFIG.LOCAL_KART_SOUND_MISSING_GRACE
	then
		localKartEngineSound:Stop()
		localKartEngineSoundLastSeenAt = nil
	end
end

local function getCurrentCharacterRootPart(): BasePart?
	if cachedCharacterRootPart and cachedCharacterRootPart.Parent == character then
		return cachedCharacterRootPart
	end

	local rootCandidate = character:FindFirstChild("HumanoidRootPart")
	if rootCandidate and rootCandidate:IsA("BasePart") then
		cachedCharacterRootPart = rootCandidate
		return rootCandidate
	end

	cachedCharacterRootPart = nil
	return nil
end

local function getTreadmillTextureUpdateInterval(rootPart: BasePart?, texturePosition: Vector3?): number
	if not rootPart or not texturePosition then
		return math.huge
	end

	local distance = (rootPart.Position - texturePosition).Magnitude
	if distance > CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_PAUSE_DISTANCE then
		return math.huge
	end

	local currentCamera = Workspace.CurrentCamera
	if currentCamera and distance > CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_NEAR_DISTANCE then
		local _, onScreen = currentCamera:WorldToViewportPoint(texturePosition)
		if not onScreen then
			return math.huge
		end
	end

	if distance <= CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_NEAR_DISTANCE then
		return CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_UPDATE_INTERVAL
	end

	if distance <= CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_FAR_DISTANCE then
		return CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_FAR_UPDATE_INTERVAL
	end

	return CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_FAR_UPDATE_INTERVAL * 2
end

local function updateTreadmillTextureVisuals(dt: number)
	local rootPart = getCurrentCharacterRootPart()
	for texture, state in pairs(observedTreadmillTextures) do
		if not texture.Parent then
			observedTreadmillTextures[texture] = nil
			continue
		end

		local updateInterval = getTreadmillTextureUpdateInterval(rootPart, state.worldPosition)
		if updateInterval == math.huge then
			state.updateAccumulator = 0
			continue
		end

		state.updateAccumulator = math.min(state.updateAccumulator + dt, updateInterval * 3)
		if state.updateAccumulator < updateInterval then
			continue
		end

		local elapsed = state.updateAccumulator
		state.updateAccumulator = 0

		local nextOffset = texture.OffsetStudsV + (state.scrollSpeed * elapsed)
		if nextOffset >= 64 then
			nextOffset = 0
		end
		texture.OffsetStudsV = nextOffset
	end
end

local function updateObservedTrailVisuals()
	local budget = getRemoteTrailBudgetConfig()
	local localRootPart = getCurrentCharacterRootPart()
	local distanceMultiplier = if ClientDeviceProfile.IsMobile() then budget.mobileDistanceMultiplier else 1
	local fullDistance = budget.fullDistance * distanceMultiplier
	local disableDistance = math.max(budget.disableDistance * distanceMultiplier, fullDistance)
	local candidates: { RemoteTrailCandidate } = {}

	for targetPlayer, trailState in pairs(observedTrailVisuals) do
		local equippedTrail = targetPlayer:GetAttribute("Trail_Equipped")
		if typeof(equippedTrail) ~= "string" or equippedTrail == "" or equippedTrail == "None" then
			cleanupObservedTrailVisual(targetPlayer)
			continue
		end

		local characterToSync = targetPlayer.Character
		local rootPart = characterToSync and (characterToSync:FindFirstChild("HumanoidRootPart") :: BasePart?) or nil
		if not targetPlayer.Parent or not characterToSync or not rootPart then
			trailState.missingUntil = trailState.missingUntil or (os.clock() + CLIENT_HANDLER_CONFIG.TRAIL_VISUAL_MISSING_GRACE)
			if os.clock() > trailState.missingUntil then
				cleanupObservedTrailVisual(targetPlayer)
			end
			continue
		end

		trailState.missingUntil = nil

		if characterToSync ~= trailState.character or rootPart ~= trailState.rootPart then
			syncObservedTrailVisual(targetPlayer)
			continue
		end

		if targetPlayer ~= player and budget.enabled and localRootPart then
			table.insert(candidates, {
				state = trailState,
				distance = (rootPart.Position - localRootPart.Position).Magnitude,
			})
		elseif targetPlayer == player or not budget.enabled or not localRootPart then
			setObservedTrailQuality(trailState, "full", budget.reducedRateMultiplier)
		end

		local horizontalVelocity =
			Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
		local moving = horizontalVelocity > 0.05 or targetPlayer:GetAttribute("Treadmill_Active") == true
		if trailState.lastMoving == moving then
			continue
		end

		trailState.lastMoving = moving
		for _, emitter in ipairs(trailState.emitters) do
			if emitter.Parent then
				emitter.Speed = if moving
					then (trailState.emitterSpeeds[emitter] or NumberRange.new(0))
					else NumberRange.new(0)
			end
		end
	end

	table.sort(candidates, function(left, right)
		return left.distance < right.distance
	end)

	for index, candidate in ipairs(candidates) do
		local quality: RemoteTrailQuality
		if index > budget.maxVisiblePlayers or candidate.distance > disableDistance then
			quality = "disabled"
		elseif candidate.distance <= fullDistance then
			quality = "full"
		elseif candidate.distance <= disableDistance then
			quality = "reduced"
		else
			quality = "disabled"
		end

		setObservedTrailQuality(candidate.state, quality, budget.reducedRateMultiplier)
	end
end

local function clonePlaylist(playlist: { string | number }): { string | number }
	local cloned = table.clone(playlist)
	for index = #cloned, 2, -1 do
		local swapIndex = math.random(index)
		cloned[index], cloned[swapIndex] = cloned[swapIndex], cloned[index]
	end
	return cloned
end

local function stopLobbyMusic()
	currentMusicToken += 1
	currentMusicTracks = {}
	currentMusicIndex = 0
	currentMusicPlaylistKey = nil

	if lobbyMusicSound then
		if activeMusicTween then
			activeMusicTween:Cancel()
			activeMusicTween = nil
		end
		lobbyMusicSound:Stop()
		lobbyMusicSound.TimePosition = 0
	end
end

local function playNextLobbyTrack(token: number)
	if token ~= currentMusicToken or not lobbyMusicSound then
		return
	end

	if #currentMusicTracks == 0 then
		lobbyMusicSound:Stop()
		return
	end

	currentMusicIndex += 1
	if currentMusicIndex > #currentMusicTracks then
		currentMusicTracks = clonePlaylist(currentMusicTracks)
		currentMusicIndex = 1
	end

	local trackId = currentMusicTracks[currentMusicIndex]
	lobbyMusicSound.SoundId = normalizeTrackId(trackId)
	lobbyMusicSound.Volume = 0
	lobbyMusicSound.TimePosition = 0
	lobbyMusicSound:Play()

	if activeMusicTween then
		activeMusicTween:Cancel()
	end

	activeMusicTween = TweenService:Create(lobbyMusicSound, TweenConfig.WithDuration(CLIENT_HANDLER_CONFIG.MUSIC_FADE_TIME, TweenConfig.MusicFade), {
		Volume = CLIENT_HANDLER_CONFIG.LOBBY_MUSIC_VOLUME,
	})
	activeMusicTween:Play()

	lobbyMusicSound.Ended:Once(function()
		playNextLobbyTrack(token)
	end)
end

local function isPointInsidePart(part: BasePart, point: Vector3): boolean
	local localPosition = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function findLobbyRegionPart(world: Instance?): BasePart?
	if not world then
		return nil
	end

	local lobbyRegionContainer = world:FindFirstChild("LobbyRegion_Model")
	if lobbyRegionContainer then
		local nestedLobbyRegion = lobbyRegionContainer:FindFirstChild("LobbyRegion", true)
		if nestedLobbyRegion and nestedLobbyRegion:IsA("BasePart") then
			return nestedLobbyRegion
		end
	end

	return nil
end

local function getCurrentMusicType(currentWorld: string): string
	if player:GetAttribute("MinigameParticipant") == true then
		return if player:GetAttribute("MinigameState") == "Racing" then "ActionMusicList" else "LobbyMusicList"
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local currentStage = player:GetAttribute("CurrentStage") or 0
	if not rootPart then
		return if currentStage > 0 then "ActionMusicList" else "LobbyMusicList"
	end

	local worldsFolder = Workspace:FindFirstChild("Worlds")
	local world = worldsFolder and worldsFolder:FindFirstChild(currentWorld)
	local lobbyRegion = findLobbyRegionPart(world)
	if lobbyRegion then
		if isPointInsidePart(lobbyRegion, rootPart.Position) then
			return "LobbyMusicList"
		end
		return "ActionMusicList"
	end

	return if currentStage > 0 then "ActionMusicList" else "LobbyMusicList"
end

local function updateWorldMusic()
	if player:GetAttribute("MusicEnabled") == false then
		stopLobbyMusic()
		return
	end

	local currentWorld = player:GetAttribute("Current_World")
	if typeof(currentWorld) ~= "string" then
		stopLobbyMusic()
		return
	end

	local musicType = getCurrentMusicType(currentWorld)
	local selectedPlaylist = SoundService.GetWorldMusicPlaylist(currentWorld, musicType)
	local playlistTrackIds = table.create(#selectedPlaylist)
	for index, soundId in ipairs(selectedPlaylist) do
		playlistTrackIds[index] = tostring(soundId)
	end
	local worldConfig = SoundService.WorldMusicPlaylists[currentWorld]
	local playlistSource = if worldConfig and worldConfig[musicType] and #worldConfig[musicType] > 0
		then currentWorld
		else "Fallback"
	local playlistKey = playlistSource .. ":" .. musicType .. ":" .. table.concat(playlistTrackIds, ",")

	if playlistKey == currentMusicPlaylistKey and lobbyMusicSound and lobbyMusicSound.IsPlaying then
		return
	end

	currentMusicToken += 1
	currentMusicPlaylistKey = playlistKey
	currentMusicTracks = clonePlaylist(selectedPlaylist)
	currentMusicIndex = 0

	if not lobbyMusicSound or #currentMusicTracks == 0 then
		if lobbyMusicSound then
			if activeMusicTween then
				activeMusicTween:Cancel()
				activeMusicTween = nil
			end
			lobbyMusicSound:Stop()
		end
		return
	end

	local nextToken = currentMusicToken
	if activeMusicTween then
		activeMusicTween:Cancel()
	end

	if lobbyMusicSound.IsPlaying and lobbyMusicSound.Volume > 0 then
		activeMusicTween = TweenService:Create(lobbyMusicSound, TweenConfig.WithDuration(CLIENT_HANDLER_CONFIG.MUSIC_FADE_TIME, TweenConfig.MusicFade), {
			Volume = 0,
		})
		activeMusicTween:Play()
		activeMusicTween.Completed:Once(function()
			if nextToken ~= currentMusicToken then
				return
			end

			lobbyMusicSound:Stop()
			lobbyMusicSound.TimePosition = 0
			playNextLobbyTrack(nextToken)
		end)
	else
		lobbyMusicSound:Stop()
		lobbyMusicSound.TimePosition = 0
		playNextLobbyTrack(nextToken)
	end
end

local stopMovementDetection = MainFunctions.StartMovementDetection(humanoid)

local function teardownPlayerClientHandler(reason: string)
	if isCleaningUp then
		return
	end
	isCleaningUp = true

	if activeFovTween then
		activeFovTween:Cancel()
		activeFovTween = nil
	end
	lastTargetFov = nil
	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		currentCamera.FieldOfView = CLIENT_HANDLER_CONFIG.DEFAULT_FOV
	end

	stopMovementDetection()
	movementLifecycleMaid:DoCleaning()
	topLevelMaid:DoCleaning()
	for model, kartState in pairs(observedEquippedKarts) do
		cleanupObservedEquippedKart(kartState)
		observedEquippedKarts[model] = nil
	end
	if reason ~= "ReplacedByNewCharacterScript" then
		if localKartEngineSound then
			localKartEngineSound:Stop()
			localKartEngineSound:Destroy()
			localKartEngineSound = nil
		end
		localKartEngineSoundLastSeenAt = nil
	end

	for trackedPlayer in pairs(observedTrailPlayerMaids) do
		cleanupObservedTrailPlayerBindings(trackedPlayer)
	end

	for trackedPlayer in pairs(observedTrailVisuals) do
		cleanupObservedTrailVisual(trackedPlayer)
	end

	for gradientInstance, gradientMaid in pairs(registeredRainbowGradientMaids) do
		registeredRainbowGradients[gradientInstance] = nil
		registeredRainbowGradientMaids[gradientInstance] = nil
		gradientMaid:DoCleaning()
	end

	for model in pairs(table.clone(observedKartShowcases)) do
		cleanupKartShowcase(model, true)
	end
	table.clear(observedTreadmillTextures)
	table.clear(observedTreadmillTouchParts)
	table.clear(observedKartVisualSourceRoots)
	cachedCharacterRootPart = nil
	kartVisualFrameAccumulator = 0
	kartVisualHealthAccumulator = 0
	localKartVisualMissingSince = nil
	lastKartVisualResyncAt = 0
	setActiveTreadmillHighlightAdornee(nil)
	if activeTreadmillHighlight then
		activeTreadmillHighlight:Destroy()
		activeTreadmillHighlight = nil
	end

	if singletonState and singletonState.ownerToken == handlerToken then
		singletonState.cleanup = nil
		singletonState.ownerToken = nil
	end
end

singletonState.cleanup = teardownPlayerClientHandler
if previousHandlerCleanup then
	previousHandlerCleanup("ReplacedByNewCharacterScript")
end

movementLifecycleMaid:GiveTask(stopMovementDetection)
movementLifecycleMaid:GiveTask(humanoid.Died:Connect(function()
	stopMovementDetection()
	teardownPlayerClientHandler("Humanoid.Died")
end))
movementLifecycleMaid:GiveTask(humanoid.AncestryChanged:Connect(function(_, parent)
	if parent ~= nil then
		return
	end

	stopMovementDetection()
	teardownPlayerClientHandler("HumanoidRemoved")
end))
movementLifecycleMaid:GiveTask(character.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		DebugModule.debugWarn("Character.AncestryChanged removed character, forcing cleanup", "PlayerClientHandler")
		stopMovementDetection()
		teardownPlayerClientHandler("CharacterRemoved")
	end
end))

local function scheduleHumanoidRecovery()
	recoveryUntil = tick() + CLIENT_HANDLER_CONFIG.RECOVERY_FORCE_UPRIGHT_WINDOW
	deferTopLevel(function()
		if humanoid.Health <= 0 then
			return
		end

		humanoid.PlatformStand = false
		humanoid.Sit = false
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
end

local function setupRecoveryStates()
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	movementLifecycleMaid:GiveTask(humanoid.StateChanged:Connect(function(_, newState)
		if humanoid.Health <= 0 then
			return
		end

		if
			newState == Enum.HumanoidStateType.FallingDown
			or newState == Enum.HumanoidStateType.Ragdoll
			or newState == Enum.HumanoidStateType.PlatformStanding
		then
			scheduleHumanoidRecovery()
		end
	end))
end

setupRecoveryStates()


local WorldSourceBindings = {}

function WorldSourceBindings.updateVIPDoorCollision()
	PlayerHandler.UpdateVIPRoomCollision(player)
end

local function tweenCameraFov(targetFov: number)
	local currentCamera = Workspace.CurrentCamera
	if not currentCamera then
		return
	end

	if lastTargetFov and math.abs(lastTargetFov - targetFov) < 0.25 then
		return
	end

	lastTargetFov = targetFov
	if activeFovTween then
		activeFovTween:Cancel()
	end

	activeFovTween = TweenService:Create(
		currentCamera,
		TweenConfig.WithDuration(CLIENT_HANDLER_CONFIG.FOV_TWEEN_TIME, TweenConfig.CameraFov),
		{ FieldOfView = targetFov }
	)
	activeFovTween:Play()
end

local function updateDynamicFov()
	local currentCamera = Workspace.CurrentCamera
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not currentCamera or not rootPart then
		return
	end

	if player:GetAttribute("Ui_TrollFrameOpen") == true then
		tweenCameraFov(CLIENT_HANDLER_CONFIG.DEFAULT_FOV)
		return
	end

	if player:GetAttribute("Treadmill_Active") == true then
		tweenCameraFov(CLIENT_HANDLER_CONFIG.TREADMILL_FOV)
		return
	end

	local horizontalVelocity =
		Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
	local maxSpeed = math.max(player:GetAttribute("Max_Player_Speed") or humanoid.WalkSpeed, 1)
	local normalizedSpeed = math.clamp(horizontalVelocity / maxSpeed, 0, 1)
	local targetFov = CLIENT_HANDLER_CONFIG.DEFAULT_FOV + ((CLIENT_HANDLER_CONFIG.SPEED_FOV_MAX - CLIENT_HANDLER_CONFIG.DEFAULT_FOV) * normalizedSpeed)
	tweenCameraFov(targetFov)
end

function WorldSourceBindings.isVIPRoomDescendant(instance: Instance): boolean
	local vipRooms = instance:FindFirstAncestor("VIPRooms")
	return vipRooms ~= nil
end

function WorldSourceBindings.registerRainbowGradient(instance: Instance)
	if not instance:IsA("UIGradient") or instance.Name ~= "RainbowGradient" then
		return
	end

	if registeredRainbowGradients[instance] then
		return
	end

	registeredRainbowGradients[instance] = true
	local gradientMaid = Maid.new()
	registeredRainbowGradientMaids[instance] = gradientMaid

	local function cleanupGradientRegistration()
		registeredRainbowGradients[instance] = nil
		local existingMaid = registeredRainbowGradientMaids[instance]
		if existingMaid == gradientMaid then
			registeredRainbowGradientMaids[instance] = nil
			gradientMaid:DoCleaning()
		end
	end

	gradientMaid:GiveTask(instance.Destroying:Connect(cleanupGradientRegistration))
	gradientMaid:GiveTask(instance.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupGradientRegistration()
		end
	end))

	VisualFunctions.SetupRainbowGradient(instance)
end

function WorldSourceBindings.bindWorldSourceRoot(root: Instance)
	if observedWorldSourceRoots[root] or not root:IsDescendantOf(Workspace) then
		return
	end

	local rootMaid = beginSourceRootBinding(root, observedWorldSourceRoots)
	rootMaid:GiveTask(root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Folder") and descendant.Name == CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockFolderName then
			bindKartVisualSourceRoot(descendant)
		end

		if
			descendant:IsA("BasePart")
			and descendant.Name == "VIPDoor"
			and WorldSourceBindings.isVIPRoomDescendant(descendant)
		then
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local distanceText = "unknown distance"
			if rootPart then
				distanceText = string.format("%.0f studs away", (descendant.Position - rootPart.Position).Magnitude)
			end

			DebugModule.debugPrint(
				string.format(
					"New VIPDoor detected at %s, updating collision (%s)",
					tostring(descendant.Position),
					distanceText
				),
				"PlayerClientHandler"
			)
			deferTopLevel(WorldSourceBindings.updateVIPDoorCollision)
		end

		WorldSourceBindings.registerRainbowGradient(descendant)
		registerTreadmillTexture(descendant)
		registerTreadmillTouchPart(descendant)
	end))

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Folder") and descendant.Name == CLIENT_HANDLER_CONFIG.SHOWCASE_MODEL_CONFIG.luckyBlockFolderName then
			bindKartVisualSourceRoot(descendant)
		end

		WorldSourceBindings.registerRainbowGradient(descendant)
		registerTreadmillTexture(descendant)
		registerTreadmillTouchPart(descendant)
	end
end

function WorldSourceBindings.refreshWorldSourceBindings()
	local worldsFolder = Workspace:FindFirstChild("Worlds")
	if worldsFolder then
		WorldSourceBindings.bindWorldSourceRoot(worldsFolder)
	end
end

if not RunService:IsStudio() then
	ContextActionService:UnbindAction(CLIENT_HANDLER_CONFIG.FREECAM_BLOCK_ACTION)
	ContextActionService:BindActionAtPriority(
		CLIENT_HANDLER_CONFIG.FREECAM_BLOCK_ACTION,
		onBlockRobloxFreecamAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.P
	)
	topLevelMaid:GiveTask(function()
		ContextActionService:UnbindAction(CLIENT_HANDLER_CONFIG.FREECAM_BLOCK_ACTION)
	end)
else
	ContextActionService:UnbindAction(CLIENT_HANDLER_CONFIG.FREECAM_BLOCK_ACTION)
end

topLevelMaid:GiveTask(
	player:GetAttributeChangedSignal("HasVIPPass"):Connect(WorldSourceBindings.updateVIPDoorCollision)
)
topLevelMaid:GiveTask(player:GetAttributeChangedSignal("Treadmill_Active"):Connect(updateDynamicFov))
topLevelMaid:GiveTask(player:GetAttributeChangedSignal("Treadmill_Active"):Connect(function()
	treadmillHighlightUpdateAccumulator = CLIENT_HANDLER_CONFIG.TREADMILL_HIGHLIGHT_UPDATE_INTERVAL
	setActiveTreadmillHighlightAdornee(getCurrentTreadmillHighlightAdornee())
end))
topLevelMaid:GiveTask(player:GetAttributeChangedSignal("Current_World"):Connect(updateWorldMusic))
topLevelMaid:GiveTask(player:GetAttributeChangedSignal("MusicEnabled"):Connect(updateWorldMusic))
topLevelMaid:GiveTask(player:GetAttributeChangedSignal("EventEnvironmentEnabled"):Connect(updateWorldMusic))
topLevelMaid:GiveTask(player:GetAttributeChangedSignal("CurrentStage"):Connect(updateWorldMusic))
topLevelMaid:GiveTask(player:GetAttributeChangedSignal("MinigameParticipant"):Connect(updateWorldMusic))
topLevelMaid:GiveTask(player:GetAttributeChangedSignal("MinigameState"):Connect(updateWorldMusic))

local liveEventMusicMaid = Maid.new()
topLevelMaid:GiveTask(liveEventMusicMaid)
local function bindLiveEventMusicState(folder: Instance)
	if not folder:IsA("Folder") then
		return
	end

	liveEventMusicMaid.EnvironmentName = folder:GetAttributeChangedSignal("EnvironmentName"):Connect(updateWorldMusic)
	liveEventMusicMaid.TestCountdownEnded = folder:GetAttributeChangedSignal("StudioSeasonalEnvironmentTestEnded"):Connect(updateWorldMusic)
	updateWorldMusic()
end

local liveEventState = ReplicatedStorage:FindFirstChild("LiveEventState")
if liveEventState then
	bindLiveEventMusicState(liveEventState)
end
topLevelMaid:GiveTask(ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "LiveEventState" then
		bindLiveEventMusicState(child)
	end
end))
topLevelMaid:GiveTask(ReplicatedStorage.ChildRemoved:Connect(function(child)
	if child.Name == "LiveEventState" then
		liveEventMusicMaid.EnvironmentName = nil
		liveEventMusicMaid.TestCountdownEnded = nil
		updateWorldMusic()
	end
end))


topLevelMaid:GiveTask(Players.PlayerAdded:Connect(function(addedPlayer)
	bindObservedTrailPlayer(addedPlayer)
end))

topLevelMaid:GiveTask(Players.PlayerRemoving:Connect(function(removingPlayer)
	cleanupObservedTrailPlayerBindings(removingPlayer)
end))

deferTopLevel(function()
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		bindObservedTrailPlayer(targetPlayer)
	end
end)

topLevelMaid:GiveTask(Workspace.ChildAdded:Connect(function(child)
	if child.Name == "Worlds" then
		deferTopLevel(WorldSourceBindings.updateVIPDoorCollision)
		deferTopLevel(WorldSourceBindings.refreshWorldSourceBindings)
	end
	if child.Name == "Worlds" or child.Name == CLIENT_HANDLER_CONFIG.KART_VISUAL_HOLDER_NAME then
		deferTopLevel(refreshKartVisualSourceBindings)
	end
end))

deferTopLevel(WorldSourceBindings.updateVIPDoorCollision)
deferTopLevel(updateDynamicFov)
deferTopLevel(updateWorldMusic)
deferTopLevel(refreshKartVisualSourceBindings)
deferTopLevel(WorldSourceBindings.refreshWorldSourceBindings)

scheduleKartRespawnProbe("postSpawn.0.25s", 0.25)
scheduleKartRespawnProbe("postSpawn.1.5s", 1.5)

topLevelMaid:GiveTask(RunService.Heartbeat:Connect(function(dt)
	kartVisualHealthAccumulator += dt
	if kartVisualHealthAccumulator >= CLIENT_HANDLER_CONFIG.KART_CLIENT_VISUAL_HEALTH_INTERVAL then
		kartVisualHealthAccumulator = 0
		reconcileLocalKartVisual()
	end

	fovUpdateAccumulator = math.min(fovUpdateAccumulator + dt, CLIENT_HANDLER_CONFIG.FOV_UPDATE_INTERVAL * 2)
	if fovUpdateAccumulator >= CLIENT_HANDLER_CONFIG.FOV_UPDATE_INTERVAL then
		updateDynamicFov()
		fovUpdateAccumulator = 0
	end

	kartShowcaseFrameAccumulator = math.min(kartShowcaseFrameAccumulator + dt, CLIENT_HANDLER_CONFIG.KART_SHOWCASE_FRAMELOCK_INTERVAL * 2)
	if kartShowcaseFrameAccumulator >= CLIENT_HANDLER_CONFIG.KART_SHOWCASE_FRAMELOCK_INTERVAL then
		local showcaseDt = kartShowcaseFrameAccumulator
		kartShowcaseFrameAccumulator = 0
		updateObservedKartShowcases(showcaseDt)
	end

	kartVisualFrameAccumulator = math.min(kartVisualFrameAccumulator + dt, CLIENT_HANDLER_CONFIG.KART_VISUAL_FRAMELOCK_INTERVAL * 3)
	local kartVisualSteps = 0
	while kartVisualFrameAccumulator >= CLIENT_HANDLER_CONFIG.KART_VISUAL_FRAMELOCK_INTERVAL and kartVisualSteps < 2 do
		kartVisualFrameAccumulator -= CLIENT_HANDLER_CONFIG.KART_VISUAL_FRAMELOCK_INTERVAL
		updateObservedEquippedKartVisuals(CLIENT_HANDLER_CONFIG.KART_VISUAL_FRAMELOCK_INTERVAL)
		kartVisualSteps += 1
	end
	if kartVisualSteps >= 2 and kartVisualFrameAccumulator >= CLIENT_HANDLER_CONFIG.KART_VISUAL_FRAMELOCK_INTERVAL then
		kartVisualFrameAccumulator = 0
	end

	treadmillTextureUpdateAccumulator =
		math.min(treadmillTextureUpdateAccumulator + dt, CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_UPDATE_INTERVAL * 3)
	local treadmillTextureSteps = 0
	while treadmillTextureUpdateAccumulator >= CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_UPDATE_INTERVAL and treadmillTextureSteps < 2 do
		treadmillTextureUpdateAccumulator -= CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_UPDATE_INTERVAL
		updateTreadmillTextureVisuals(CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_UPDATE_INTERVAL)
		treadmillTextureSteps += 1
	end
	if treadmillTextureSteps >= 2 and treadmillTextureUpdateAccumulator >= CLIENT_HANDLER_CONFIG.TREADMILL_TEXTURE_UPDATE_INTERVAL then
		treadmillTextureUpdateAccumulator = 0
	end

	updateTreadmillHighlight(dt)

	trailVisualUpdateAccumulator += dt
	local remoteTrailUpdateInterval = getRemoteTrailBudgetConfig().updateInterval
	if trailVisualUpdateAccumulator >= remoteTrailUpdateInterval then
		trailVisualUpdateAccumulator = 0
		updateObservedTrailVisuals()
	end

	worldMusicUpdateAccumulator += dt
	if worldMusicUpdateAccumulator >= CLIENT_HANDLER_CONFIG.WORLD_MUSIC_UPDATE_INTERVAL then
		worldMusicUpdateAccumulator = 0
		updateWorldMusic()
	end

	if recoveryUntil > tick() then
		if humanoid.Health > 0 then
			humanoid.PlatformStand = false
			humanoid.Sit = false
			if humanoid:GetState() == Enum.HumanoidStateType.PlatformStanding then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end
end))

script.AncestryChanged:Connect(function(_, parent)
	if parent ~= nil then
		return
	end

	DebugModule.debugInfo("PlayerClientHandler ancestry removed", "PlayerClientHandler")
	setActiveTreadmillHighlightAdornee(nil)
	teardownPlayerClientHandler("ScriptRemoved")
end)

script.Destroying:Connect(function()
	DebugModule.debugInfo("PlayerClientHandler destroying", "PlayerClientHandler")
	setActiveTreadmillHighlightAdornee(nil)
	teardownPlayerClientHandler("ScriptDestroying")
end)
