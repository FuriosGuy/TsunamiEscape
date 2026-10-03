--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local ClientCullingService = require(ReplicatedStorage.Modules.ClientCullingService)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local PetLuckyBlockRevealController = require(ReplicatedStorage.Modules.UI.MainGUI.PetLuckyBlockRevealController)

type LuckyBlockGroup = PetConfig.LuckyBlockGroup

type CraterVisualObject = BasePart | Texture | Decal
type MaskedTransparencyObject = BasePart | Texture | Decal
type MaskedEnabledObject =
	BillboardGui
	| SurfaceGui
	| ParticleEmitter
	| Light
	| Beam
	| Trail
	| Highlight
	| Fire
	| Smoke
	| Sparkles

type ModelVisibilityConnections = {
	descendantAdded: RBXScriptConnection,
	descendantRemoving: RBXScriptConnection,
	ancestryChanged: RBXScriptConnection,
}

type PlayerVisibilityConnections = {
	characterAdded: RBXScriptConnection,
	characterRemoving: RBXScriptConnection,
}

type WorldVisibilityMask = {
	localTransparency: { [MaskedTransparencyObject]: number },
	enabled: { [MaskedEnabledObject]: boolean },
	humanoidDisplayDistance: { [Humanoid]: Enum.HumanoidDisplayDistanceType },
	humanoidHealthDisplay: { [Humanoid]: Enum.HumanoidHealthDisplayType },
	soundVolumes: { [Sound]: number },
	models: { [Model]: ModelVisibilityConnections },
	players: { [Player]: PlayerVisibilityConnections },
	workspaceDescendantAdded: RBXScriptConnection?,
	playerAdded: RBXScriptConnection?,
	playerRemoving: RBXScriptConnection?,
}

type RockFlight = {
	rock: BasePart,
	startCFrame: CFrame,
	landingCFrame: CFrame,
	apexHeight: number,
	flightDuration: number,
}

type CraterVisualState = {
	model: Model,
	originalScale: number,
	cameraMarker: BasePart?,
	localTransparency: { [CraterVisualObject]: number },
	visible: boolean,
	descendantConnection: RBXScriptConnection?,
}

type CutsceneController = {
	alive: boolean,
	isPlaying: boolean,
	generation: number,
	model: Model?,
	cameraSnapshot: CameraSnapshot?,
	guiSnapshot: GuiSnapshot?,
	mainGui: ScreenGui,
	playerGui: PlayerGui,
	fadeFrame: Frame,
	fadeTween: Tween?,
	runMaid: any,
	onFinished: (() -> ())?,
	craterVisualState: CraterVisualState?,
	worldVisibilityMask: WorldVisibilityMask?,
	workspaceDescendantConnection: RBXScriptConnection?,
	Play: (
		self: CutsceneController,
		group: LuckyBlockGroup,
		petIds: { string },
		fasterOpen: boolean,
		onFinished: (() -> ())?
	) -> boolean,
	Stop: (self: CutsceneController) -> (),
	Destroy: (self: CutsceneController) -> (),
}

type CameraSnapshot = {
	camera: Camera,
	cameraType: Enum.CameraType,
	cameraSubject: Instance?,
	cframe: CFrame,
	focus: CFrame,
	fieldOfView: number,
}

type GuiSnapshot = {
	screenGuis: { [ScreenGui]: boolean },
	mainGuiChildren: { [GuiObject]: boolean },
	fadeChildren: { [GuiObject]: boolean },
	mainGuiDisplayOrder: number,
	fadeVisible: boolean,
	fadeTransparency: number,
	fadeZIndex: number,
}

local PetLuckyBlockCutsceneController = {}
PetLuckyBlockCutsceneController.__index = PetLuckyBlockCutsceneController

local MODULE_NAME = "PetLuckyBlockCutsceneController"
local MODEL_FOLDER_NAME = "Luckyblock_Models"
local DROPOFF_NAME = "DropoffCrater"
local LANDING_PART_NAME = "Cylinder"
local CAMERA_MARKER_NAME = "CameraMain"
local KART_HOLDER_NAME = "EquippedKarts"
local KART_MODEL_NAME = "EquippedKart"
local DROP_HEIGHT = 48
local INTRO_CAMERA_PITCH = math.rad(45)
local TUMBLE_X_TURNS = 2
local TUMBLE_Y_TURNS = 3
local TUMBLE_Z_TURNS = 1
local CAMERA_MOVE_DURATION = 0.65
local CAMERA_FOCUS_DURATION = 0.78
local DROP_DURATION = 1.75
local IMPACT_SOUND_LEAD = 0.3
local IMPACT_SHAKE_DURATION = 0.85
local IMPACT_CAMERA_SHAKE_FREQUENCY = 28
local IMPACT_CAMERA_SHAKE_DISTANCE = 0.72
local IMPACT_CAMERA_SHAKE_VERTICAL = 0.46
local IMPACT_CAMERA_SHAKE_DEPTH = 0.3
local IMPACT_CAMERA_SHAKE_ANGLE = math.rad(12)
local STUMBLE_DURATION = 1.8
local STUMBLE_DAMPING = 1.8
local STUMBLE_ANGULAR_FREQUENCY = 10
local STUMBLE_YAW_FREQUENCY = 6.5
local STUMBLE_X_ANGLE = math.rad(34)
local STUMBLE_X_PHASE = 0.55
local STUMBLE_YAW_ANGLE = math.rad(12)
local STUMBLE_YAW_PHASE = 0.95
local STUMBLE_Z_ANGLE = math.rad(32)
local STUMBLE_Z_PHASE = 1.25
local IMPACT_BOUNCE_HEIGHT = 1.3
local IMPACT_BOUNCE_DURATION = 0.42
local IMPACT_BOUNCE_DAMPING = 2.4
local CRATER_IMPACT_START_SCALE = 0.08
local CRATER_SCALE_DURATION = 0.62
local ROCK_DEBRIS_COUNT = 16
local ROCK_DEBRIS_MIN_SIZE = 1
local ROCK_DEBRIS_MAX_SIZE = 2
local ROCK_DEBRIS_START_RADIUS_MIN = 5.2
local ROCK_DEBRIS_START_RADIUS_MAX = 7.2
local ROCK_DEBRIS_LANDING_RADIUS_MIN = 10
local ROCK_DEBRIS_LANDING_RADIUS_MAX = 32
local ROCK_DEBRIS_LAUNCH_ANGLE_MIN = math.rad(30)
local ROCK_DEBRIS_LAUNCH_ANGLE_MAX = math.rad(36)
local ROCK_DEBRIS_LIFETIME = 0.5
local ROCK_DEBRIS_FADE_DURATION = 0.24
local CAMERA_RETURN_DURATION = 0.5
local FADE_DURATION = 0.24
local CUTSCENE_Z_INDEX = 1000

local MODEL_NAME_BY_GROUP: { [string]: string } = {
	Tier1 = "Tier1_LuckyBlock",
	Tier2 = "Tier2_LuckyBlock",
	Tier3 = "Tier3_LuckyBlock",
	Premium = "Robux_LuckyBlock",
	BloodMoon = "Bloodmoon_LuckyBlock",
	NeonRush = "Neon_LuckyBlock",
	FrostbiteRally = "Frostbite_LuckyBlock",
}

local function getExtentAlong(frame: CFrame, size: Vector3, axis: Vector3): number
	return math.abs(frame.RightVector:Dot(axis)) * size.X
		+ math.abs(frame.UpVector:Dot(axis)) * size.Y
		+ math.abs(frame.LookVector:Dot(axis)) * size.Z
end

local function getWorldHeight(frame: CFrame, size: Vector3): number
	return getExtentAlong(frame, size, Vector3.yAxis)
end

local function getOffscreenDropHeight(
	cameraFrame: CFrame,
	cameraFieldOfView: number,
	landingBounds: CFrame,
	boundsSize: Vector3
): number
	local halfBlockHeight = getExtentAlong(landingBounds, boundsSize, cameraFrame.UpVector) * 0.5
	local dropHeight = DROP_HEIGHT
	for _ = 1, 24 do
		local candidatePosition = landingBounds.Position + Vector3.yAxis * dropHeight
		local cameraSpacePosition = cameraFrame:PointToObjectSpace(candidatePosition)
		if cameraSpacePosition.Z < 0 then
			local depth = -cameraSpacePosition.Z
			local screenHalfHeight = depth * math.tan(math.rad(cameraFieldOfView * 0.5))
			if cameraSpacePosition.Y - halfBlockHeight > screenHalfHeight * 1.08 then
				return dropHeight
			end
		end
		dropHeight += 12
	end
	return dropHeight
end

local function isCraterVisualObject(instance: Instance): boolean
	return instance:IsA("BasePart") or instance:IsA("Texture") or instance:IsA("Decal")
end

local function setCraterObjectVisible(state: CraterVisualState, instance: CraterVisualObject): ()
	if state.cameraMarker and (instance == state.cameraMarker or instance:IsDescendantOf(state.cameraMarker)) then
		instance.LocalTransparencyModifier = 1
		return
	end
	local originalTransparency = state.localTransparency[instance]
	if originalTransparency == nil then
		originalTransparency = instance.LocalTransparencyModifier
		state.localTransparency[instance] = originalTransparency
	end
	instance.LocalTransparencyModifier = if state.visible then originalTransparency else 1
end

local function setCraterVisible(state: CraterVisualState, visible: boolean): ()
	state.visible = visible
	for instance in pairs(state.localTransparency) do
		if instance.Parent then
			setCraterObjectVisible(state, instance)
		end
	end
end

local function createCraterVisualState(model: Model): CraterVisualState
	local markerCandidate = model:FindFirstChild(CAMERA_MARKER_NAME, true)
	local cameraMarker = if markerCandidate and markerCandidate:IsA("BasePart") then markerCandidate else nil
	local state: CraterVisualState = {
		model = model,
		originalScale = model:GetScale(),
		cameraMarker = cameraMarker,
		localTransparency = {},
		visible = false,
		descendantConnection = nil,
	}
	for _, descendant in ipairs(model:GetDescendants()) do
		if isCraterVisualObject(descendant) then
			setCraterObjectVisible(state, descendant :: CraterVisualObject)
		end
	end
	state.descendantConnection = model.DescendantAdded:Connect(function(descendant: Instance)
		if isCraterVisualObject(descendant) then
			setCraterObjectVisible(state, descendant :: CraterVisualObject)
		end
	end)
	return state
end

local function resetCraterVisualState(state: CraterVisualState): ()
	setCraterVisible(state, false)
	if state.model.Parent then
		state.model:ScaleTo(state.originalScale)
	end
end

local function releaseCraterVisualState(state: CraterVisualState): ()
	resetCraterVisualState(state)
	if state.descendantConnection then
		state.descendantConnection:Disconnect()
		state.descendantConnection = nil
	end
end

local function ensureCraterVisualState(self: CutsceneController, model: Model): CraterVisualState
	local currentState = self.craterVisualState
	if currentState and currentState.model == model then
		return currentState
	end
	if currentState then
		releaseCraterVisualState(currentState)
	end
	local state = createCraterVisualState(model)
	self.craterVisualState = state
	return state
end

local function restoreMaskedInstance(state: WorldVisibilityMask, instance: Instance): ()
	if instance:IsA("BasePart") or instance:IsA("Texture") or instance:IsA("Decal") then
		local maskedInstance = instance :: MaskedTransparencyObject
		local originalTransparency = state.localTransparency[maskedInstance]
		if originalTransparency ~= nil then
			if instance.Parent then
				instance.LocalTransparencyModifier = originalTransparency
			end
			state.localTransparency[maskedInstance] = nil
		end
	end

	if
		instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("ParticleEmitter")
		or instance:IsA("Light")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Highlight")
		or instance:IsA("Fire")
		or instance:IsA("Smoke")
		or instance:IsA("Sparkles")
	then
		local maskedInstance = instance :: MaskedEnabledObject
		local originalEnabled = state.enabled[maskedInstance]
		if originalEnabled ~= nil then
			if instance.Parent then
				maskedInstance.Enabled = originalEnabled
			end
			state.enabled[maskedInstance] = nil
		end
	end

	if instance:IsA("Humanoid") then
		local displayDistance = state.humanoidDisplayDistance[instance]
		local healthDisplay = state.humanoidHealthDisplay[instance]
		if instance.Parent then
			if displayDistance ~= nil then
				instance.DisplayDistanceType = displayDistance
			end
			if healthDisplay ~= nil then
				instance.HealthDisplayType = healthDisplay
			end
		end
		state.humanoidDisplayDistance[instance] = nil
		state.humanoidHealthDisplay[instance] = nil
	end

	if instance:IsA("Sound") then
		local originalVolume = state.soundVolumes[instance]
		if originalVolume ~= nil then
			if instance.Parent then
				instance.Volume = originalVolume
			end
			state.soundVolumes[instance] = nil
		end
	end
end

local function maskInstance(state: WorldVisibilityMask, instance: Instance): ()
	ClientCullingService.ReleaseInstance(instance)

	if instance:IsA("BasePart") or instance:IsA("Texture") or instance:IsA("Decal") then
		local maskedInstance = instance :: MaskedTransparencyObject
		if state.localTransparency[maskedInstance] == nil then
			state.localTransparency[maskedInstance] = instance.LocalTransparencyModifier
		end
		instance.LocalTransparencyModifier = 1
	end

	if
		instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("ParticleEmitter")
		or instance:IsA("Light")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Highlight")
		or instance:IsA("Fire")
		or instance:IsA("Smoke")
		or instance:IsA("Sparkles")
	then
		local maskedInstance = instance :: MaskedEnabledObject
		if state.enabled[maskedInstance] == nil then
			state.enabled[maskedInstance] = maskedInstance.Enabled
		end
		maskedInstance.Enabled = false
	end

	if instance:IsA("Humanoid") then
		if state.humanoidDisplayDistance[instance] == nil then
			state.humanoidDisplayDistance[instance] = instance.DisplayDistanceType
			state.humanoidHealthDisplay[instance] = instance.HealthDisplayType
		end
		instance.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		instance.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end

	if instance:IsA("Sound") then
		if state.soundVolumes[instance] == nil then
			state.soundVolumes[instance] = instance.Volume
		end
		instance.Volume = 0
	end
end

local function maskInstanceTree(state: WorldVisibilityMask, root: Instance): ()
	maskInstance(state, root)
	for _, descendant in ipairs(root:GetDescendants()) do
		maskInstance(state, descendant)
	end
end

local function restoreInstanceTree(state: WorldVisibilityMask, root: Instance): ()
	restoreMaskedInstance(state, root)
	for _, descendant in ipairs(root:GetDescendants()) do
		restoreMaskedInstance(state, descendant)
	end
end

local function getManagedVisualModel(instance: Instance): Model?
	local current: Instance? = instance
	while current do
		if current:IsA("Model") then
			if current.Name == KART_MODEL_NAME or Players:GetPlayerFromCharacter(current) ~= nil then
				return current
			end
		end
		current = current.Parent
	end
	return nil
end

local function untrackVisibilityModel(state: WorldVisibilityMask, model: Model): ()
	local connections = state.models[model]
	if not connections then
		return
	end
	state.models[model] = nil
	connections.descendantAdded:Disconnect()
	connections.descendantRemoving:Disconnect()
	connections.ancestryChanged:Disconnect()
	restoreInstanceTree(state, model)
end

local function trackVisibilityModel(state: WorldVisibilityMask, model: Model): ()
	if state.models[model] then
		return
	end

	maskInstanceTree(state, model)
	local connections: ModelVisibilityConnections = {
		descendantAdded = model.DescendantAdded:Connect(function(descendant: Instance)
			maskInstanceTree(state, descendant)
		end),
		descendantRemoving = model.DescendantRemoving:Connect(function(descendant: Instance)
			restoreInstanceTree(state, descendant)
		end),
		ancestryChanged = model.AncestryChanged:Connect(function(_, parent: Instance?)
			if parent == nil then
				untrackVisibilityModel(state, model)
			end
		end),
	}
	state.models[model] = connections
end

local function unbindVisibilityPlayer(state: WorldVisibilityMask, player: Player): ()
	local connections = state.players[player]
	if connections then
		state.players[player] = nil
		connections.characterAdded:Disconnect()
		connections.characterRemoving:Disconnect()
	end
	local character = player.Character
	if character then
		untrackVisibilityModel(state, character)
	end
end

local function bindVisibilityPlayer(state: WorldVisibilityMask, player: Player): ()
	if state.players[player] then
		return
	end
	local connections: PlayerVisibilityConnections = {
		characterAdded = player.CharacterAdded:Connect(function(character: Model)
			trackVisibilityModel(state, character)
		end),
		characterRemoving = player.CharacterRemoving:Connect(function(character: Model)
			untrackVisibilityModel(state, character)
		end),
	}
	state.players[player] = connections
	if player.Character then
		trackVisibilityModel(state, player.Character)
	end
end

local function restoreWorldVisibilityMask(self: CutsceneController): ()
	local state = self.worldVisibilityMask
	if not state then
		return
	end
	self.worldVisibilityMask = nil
	if state.workspaceDescendantAdded then
		state.workspaceDescendantAdded:Disconnect()
		state.workspaceDescendantAdded = nil
	end
	if state.playerAdded then
		state.playerAdded:Disconnect()
		state.playerAdded = nil
	end
	if state.playerRemoving then
		state.playerRemoving:Disconnect()
		state.playerRemoving = nil
	end
	for player in pairs(state.players) do
		unbindVisibilityPlayer(state, player)
	end
	for model in pairs(state.models) do
		untrackVisibilityModel(state, model)
	end
	for instance in pairs(state.localTransparency) do
		restoreMaskedInstance(state, instance)
	end
	for instance in pairs(state.enabled) do
		restoreMaskedInstance(state, instance)
	end
	for humanoid in pairs(state.humanoidDisplayDistance) do
		restoreMaskedInstance(state, humanoid)
	end
	for sound in pairs(state.soundVolumes) do
		restoreMaskedInstance(state, sound)
	end
end

local function beginWorldVisibilityMask(self: CutsceneController): ()
	local state: WorldVisibilityMask = {
		localTransparency = {},
		enabled = {},
		humanoidDisplayDistance = {},
		humanoidHealthDisplay = {},
		soundVolumes = {},
		models = {},
		players = {},
		workspaceDescendantAdded = nil,
		playerAdded = nil,
		playerRemoving = nil,
	}
	self.worldVisibilityMask = state
	state.workspaceDescendantAdded = Workspace.DescendantAdded:Connect(function(descendant: Instance)
		local model = getManagedVisualModel(descendant)
		if model then
			trackVisibilityModel(state, model)
		end
	end)
	state.playerAdded = Players.PlayerAdded:Connect(function(player: Player)
		bindVisibilityPlayer(state, player)
	end)
	state.playerRemoving = Players.PlayerRemoving:Connect(function(player: Player)
		unbindVisibilityPlayer(state, player)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		bindVisibilityPlayer(state, player)
	end
	local kartHolder = Workspace:FindFirstChild(KART_HOLDER_NAME, true)
	if kartHolder then
		for _, descendant in ipairs(kartHolder:GetDescendants()) do
			if descendant:IsA("Model") and descendant.Name == KART_MODEL_NAME then
				trackVisibilityModel(state, descendant)
			end
		end
	end
end

local function getCameraFacingBlockCFrame(cameraPosition: Vector3, focusPosition: Vector3, shake: number): CFrame
	local aimedCFrame = CFrame.lookAt(cameraPosition, focusPosition)
	local pitch = math.rad(11 * shake)
	local roll = math.rad(8 * shake)
	return aimedCFrame * CFrame.Angles(pitch, 0, roll)
end

local function getImpactCameraOffset(shake: number): CFrame
	local phase = os.clock() * IMPACT_CAMERA_SHAKE_FREQUENCY
	local position = Vector3.new(
		math.sin(phase) * IMPACT_CAMERA_SHAKE_DISTANCE * shake,
		math.sin(phase * 1.37 + 0.6) * IMPACT_CAMERA_SHAKE_VERTICAL * shake,
		math.cos(phase * 0.83) * IMPACT_CAMERA_SHAKE_DEPTH * shake
	)
	local rotation = CFrame.Angles(
		math.sin(phase * 1.13 + 0.3) * IMPACT_CAMERA_SHAKE_ANGLE * 0.7 * shake,
		math.sin(phase * 0.91 + 0.8) * IMPACT_CAMERA_SHAKE_ANGLE * 0.45 * shake,
		math.sin(phase) * IMPACT_CAMERA_SHAKE_ANGLE * shake
	)
	return CFrame.new(position) * rotation
end

local function getIntroCameraCFrame(cameraMarker: BasePart): CFrame
	local markerLook = cameraMarker.CFrame.LookVector
	local horizontalLook = Vector3.new(markerLook.X, 0, markerLook.Z)
	if horizontalLook.Magnitude < 0.001 then
		horizontalLook = Vector3.new(0, 0, -1)
	end
	local lookDirection = (
		horizontalLook.Unit * math.cos(INTRO_CAMERA_PITCH) + Vector3.yAxis * math.sin(INTRO_CAMERA_PITCH)
	)
	return CFrame.lookAt(cameraMarker.Position, cameraMarker.Position + lookDirection)
end

local function getTargetFrame(target: Instance): (CFrame?, number?)
	if target:IsA("BasePart") then
		return target.CFrame, getWorldHeight(target.CFrame, target.Size)
	end
	if target:IsA("Model") then
		local boundsCFrame, boundsSize = target:GetBoundingBox()
		return boundsCFrame, getWorldHeight(boundsCFrame, boundsSize)
	end
	return nil, nil
end

local function restoreCamera(snapshot: CameraSnapshot): ()
	local camera = snapshot.camera
	if camera.Parent == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = snapshot.cframe
	camera.Focus = snapshot.focus
	camera.FieldOfView = snapshot.fieldOfView
	camera.CameraSubject = snapshot.cameraSubject
	camera.CameraType = snapshot.cameraType
end

local function restoreGui(self: CutsceneController, keepFadeBlack: boolean): ()
	local snapshot = self.guiSnapshot
	if not snapshot then
		return
	end
	for screenGui, wasEnabled in pairs(snapshot.screenGuis) do
		if screenGui.Parent then
			screenGui.Enabled = wasEnabled
		end
	end
	for guiObject, wasVisible in pairs(snapshot.mainGuiChildren) do
		if guiObject.Parent then
			guiObject.Visible = wasVisible
		end
	end
	if keepFadeBlack then
		self.fadeFrame.Visible = true
		self.fadeFrame.BackgroundTransparency = 0
		return
	end
	for guiObject, wasVisible in pairs(snapshot.fadeChildren) do
		if guiObject.Parent then
			guiObject.Visible = wasVisible
		end
	end
	self.fadeFrame.Visible = snapshot.fadeVisible
	self.fadeFrame.BackgroundTransparency = snapshot.fadeTransparency
	self.fadeFrame.ZIndex = snapshot.fadeZIndex
	self.mainGui.DisplayOrder = snapshot.mainGuiDisplayOrder
end

local function captureGui(self: CutsceneController): GuiSnapshot
	local snapshot: GuiSnapshot = {
		screenGuis = {},
		mainGuiChildren = {},
		fadeChildren = {},
		mainGuiDisplayOrder = self.mainGui.DisplayOrder,
		fadeVisible = self.fadeFrame.Visible,
		fadeTransparency = self.fadeFrame.BackgroundTransparency,
		fadeZIndex = self.fadeFrame.ZIndex,
	}
	for _, child in ipairs(self.playerGui:GetChildren()) do
		if child:IsA("ScreenGui") then
			snapshot.screenGuis[child] = child.Enabled
		end
	end
	local maxDisplayOrder = self.mainGui.DisplayOrder
	for screenGui in pairs(snapshot.screenGuis) do
		maxDisplayOrder = math.max(maxDisplayOrder, screenGui.DisplayOrder)
	end
	self.mainGui.DisplayOrder = maxDisplayOrder + 1
	for _, child in ipairs(self.mainGui:GetChildren()) do
		if child:IsA("GuiObject") then
			snapshot.mainGuiChildren[child] = child.Visible
		end
	end
	for _, descendant in ipairs(self.fadeFrame:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			snapshot.fadeChildren[descendant] = descendant.Visible
			descendant.Visible = false
		end
	end
	self.fadeFrame.Visible = true
	self.fadeFrame.BackgroundTransparency = 1
	self.fadeFrame.ZIndex = CUTSCENE_Z_INDEX
	return snapshot
end

local function hideOtherGui(self: CutsceneController): ()
	for screenGui in pairs(self.guiSnapshot and self.guiSnapshot.screenGuis or {}) do
		if screenGui.Parent then
			if screenGui ~= self.mainGui then
				screenGui.Enabled = false
			end
		end
	end
	for _, child in ipairs(self.mainGui:GetChildren()) do
		if child:IsA("GuiObject") and child ~= self.fadeFrame then
			child.Visible = false
		end
	end
end

local function destroyRun(self: CutsceneController, restoreOriginalCamera: boolean, invokeCallback: boolean): ()
	local snapshot = self.cameraSnapshot
	local guiSnapshot = self.guiSnapshot
	local model = self.model
	local onFinished = self.onFinished
	self.onFinished = nil
	self.isPlaying = false
	self.model = nil
	self.cameraSnapshot = nil
	self.guiSnapshot = nil
	if self.fadeTween then
		self.fadeTween:Cancel()
		self.fadeTween = nil
	end
	restoreWorldVisibilityMask(self)
	self.runMaid:DoCleaning()
	if self.craterVisualState then
		resetCraterVisualState(self.craterVisualState)
	end
	if model and model.Parent then
		model:Destroy()
	end
	if restoreOriginalCamera and snapshot then
		restoreCamera(snapshot)
	end
	if guiSnapshot then
		self.guiSnapshot = guiSnapshot
		restoreGui(self, false)
		self.guiSnapshot = nil
	end
	if invokeCallback and onFinished then
		if typeof(onFinished) == "function" then
			onFinished()
		else
			DebugModule.debugWarn(
				"Cutscene completion callback has invalid runtime type | type=" .. typeof(onFinished),
				MODULE_NAME
			)
		end
	end
end

local function isCurrentRun(self: CutsceneController, generation: number): boolean
	return self.alive and self.isPlaying and self.generation == generation
end

local function animateCraterImpact(self: CutsceneController, generation: number): ()
	local state = self.craterVisualState
	if not state or not state.model.Parent then
		DebugModule.debugWarn("DropoffCrater visual model unavailable for impact", MODULE_NAME)
		return
	end

	state.model:ScaleTo(state.originalScale * CRATER_IMPACT_START_SCALE)
	setCraterVisible(state, true)
	local scaleValue = Instance.new("NumberValue")
	scaleValue.Value = CRATER_IMPACT_START_SCALE
	self.runMaid:GiveTask(scaleValue)
	self.runMaid:GiveTask(scaleValue:GetPropertyChangedSignal("Value"):Connect(function()
		if isCurrentRun(self, generation) and state.model.Parent then
			state.model:ScaleTo(state.originalScale * scaleValue.Value)
		end
	end))
	local scaleTween = TweenService:Create(
		scaleValue,
		TweenInfo.new(CRATER_SCALE_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = 1 }
	)
	self.runMaid:GiveTask(scaleTween)
	scaleTween:Play()
end

local function getRockDebrisColor(state: CraterVisualState?): Color3
	if state then
		local surface = state.model:FindFirstChild("InnerPart", true)
		if not surface or not surface:IsA("BasePart") then
			surface = state.model:FindFirstChild("Cylinder", true)
		end
		if surface and surface:IsA("BasePart") then
			return surface.Color:Lerp(Color3.fromRGB(58, 54, 52), 0.28)
		end
	end
	return Color3.fromRGB(82, 77, 73)
end

local function createRockRaycastParams(self: CutsceneController, effectFolder: Folder): RaycastParams
	local excluded: { Instance } = { effectFolder }
	if self.craterVisualState then
		table.insert(excluded, self.craterVisualState.model)
	end
	if self.model then
		table.insert(excluded, self.model)
	end
	local player = Players.LocalPlayer
	if player and player.Character then
		table.insert(excluded, player.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excluded
	params.IgnoreWater = true
	return params
end

local function raycastPastInvisibleParts(origin: Vector3, direction: Vector3, params: RaycastParams): RaycastResult?
	for _ = 1, 32 do
		local result = Workspace:Raycast(origin, direction, params)
		if not result then
			return nil
		end
		local hit = result.Instance
		if not hit:IsA("BasePart") or hit.Transparency < 1 then
			return result
		end
		local excluded = table.clone(params.FilterDescendantsInstances)
		table.insert(excluded, hit)
		params.FilterDescendantsInstances = excluded
	end
	return nil
end

local function findRockLandingCFrame(
	impactPosition: Vector3,
	landingPosition: Vector3,
	size: Vector3,
	landingRotation: CFrame,
	params: RaycastParams
): CFrame?
	local horizontalOffset = Vector3.new(landingPosition.X - impactPosition.X, 0, landingPosition.Z - impactPosition.Z)
	for attempt = 0, 4 do
		local candidate = impactPosition + horizontalOffset * (1 - attempt * 0.12)
		local rayOrigin = candidate + Vector3.yAxis * 100
		local result = raycastPastInvisibleParts(rayOrigin, Vector3.new(0, -300, 0), params)
		if result then
			local halfHeight = getWorldHeight(landingRotation, size) * 0.5
			local restingPosition = result.Position + Vector3.yAxis * (halfHeight + 0.025)
			return CFrame.new(restingPosition) * landingRotation
		end
	end
	return nil
end

local function animateRockFlight(self: CutsceneController, generation: number, flight: RockFlight): ()
	local progress = Instance.new("NumberValue")
	progress.Value = 0
	self.runMaid:GiveTask(progress)
	local function updateFlight(): ()
		if not isCurrentRun(self, generation) or not flight.rock.Parent then
			return
		end
		local alpha = progress.Value
		local interpolated = flight.startCFrame:Lerp(flight.landingCFrame, alpha)
		local arcHeight = 4 * flight.apexHeight * alpha * (1 - alpha)
		flight.rock.CFrame = CFrame.new(interpolated.Position + Vector3.yAxis * arcHeight) * interpolated.Rotation
	end
	self.runMaid:GiveTask(progress:GetPropertyChangedSignal("Value"):Connect(updateFlight))
	local flightTween = TweenService:Create(
		progress,
		TweenInfo.new(flight.flightDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Value = 1 }
	)
	self.runMaid:GiveTask(flightTween)
	self.runMaid:GiveTask(flightTween.Completed:Connect(function(flightState: Enum.PlaybackState)
		if
			flightState ~= Enum.PlaybackState.Completed
			or not isCurrentRun(self, generation)
			or not flight.rock.Parent
		then
			return
		end
		local fadeTween = TweenService:Create(
			flight.rock,
			TweenInfo.new(
				ROCK_DEBRIS_FADE_DURATION,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out,
				0,
				false,
				math.max(ROCK_DEBRIS_LIFETIME - ROCK_DEBRIS_FADE_DURATION, 0)
			),
			{ Transparency = 1 }
		)
		self.runMaid:GiveTask(fadeTween)
		fadeTween:Play()
	end))
	updateFlight()
	flightTween:Play()
end

local function createRockSlamVfx(self: CutsceneController, generation: number, impactPosition: Vector3): ()
	if not isCurrentRun(self, generation) then
		return
	end

	local random = Random.new()
	local rockColor = getRockDebrisColor(self.craterVisualState)
	local effectFolder = Instance.new("Folder")
	effectFolder.Name = "LuckyBlockRockSlamVFX"
	self.runMaid:GiveTask(effectFolder)
	local raycastParams = createRockRaycastParams(self, effectFolder)
	local flights: { RockFlight } = {}
	local initialAngle = random:NextNumber(0, math.pi * 2)

	for index = 1, ROCK_DEBRIS_COUNT do
		local size = Vector3.new(
			random:NextNumber(ROCK_DEBRIS_MIN_SIZE, ROCK_DEBRIS_MAX_SIZE),
			random:NextNumber(ROCK_DEBRIS_MIN_SIZE, ROCK_DEBRIS_MAX_SIZE),
			random:NextNumber(ROCK_DEBRIS_MIN_SIZE, ROCK_DEBRIS_MAX_SIZE)
		)
		local spreadAngle = initialAngle
			+ (index - 1) * math.pi * 2 / ROCK_DEBRIS_COUNT
			+ random:NextNumber(-0.12, 0.12)
		local outward = Vector3.new(math.cos(spreadAngle), 0, math.sin(spreadAngle))
		local startRadius = random:NextNumber(ROCK_DEBRIS_START_RADIUS_MIN, ROCK_DEBRIS_START_RADIUS_MAX)
		local landingRadius = random:NextNumber(ROCK_DEBRIS_LANDING_RADIUS_MIN, ROCK_DEBRIS_LANDING_RADIUS_MAX)
		local startPosition = impactPosition + outward * startRadius
		local landingPosition = impactPosition + outward * landingRadius + Vector3.yAxis * (size.Y * 0.5)
		local startRotation = CFrame.Angles(
			random:NextNumber(-math.pi, math.pi),
			random:NextNumber(-math.pi, math.pi),
			random:NextNumber(-math.pi, math.pi)
		)
		local landingRotation = startRotation
			* CFrame.Angles(random:NextNumber(-1.2, 1.2), random:NextNumber(-1.2, 1.2), random:NextNumber(-1.2, 1.2))
		local startCFrame = findRockLandingCFrame(impactPosition, startPosition, size, startRotation, raycastParams)
		local landingCFrame =
			findRockLandingCFrame(impactPosition, landingPosition, size, landingRotation, raycastParams)
		if startCFrame and landingCFrame then
			local rock: BasePart
			if random:NextNumber() < 0.5 then
				rock = Instance.new("Part")
			else
				rock = Instance.new("WedgePart")
			end
			rock.Name = "RockDebris"
			rock.Size = size
			rock.Color = rockColor:Lerp(Color3.fromRGB(43, 41, 40), random:NextNumber(0, 0.22))
			rock.Material = Enum.Material.Glacier
			rock.MaterialVariant = "2022 Big Stud"
			rock.TopSurface = Enum.SurfaceType.Smooth
			rock.BottomSurface = Enum.SurfaceType.Smooth
			rock.Anchored = true
			rock.CanCollide = false
			rock.CanTouch = false
			rock.CanQuery = false
			rock.CastShadow = false
			rock.Transparency = 0.05
			rock.CFrame = startCFrame
			rock.Parent = effectFolder
			local horizontalTravel = Vector3.new(
				landingCFrame.Position.X - startCFrame.Position.X,
				0,
				landingCFrame.Position.Z - startCFrame.Position.Z
			).Magnitude
			table.insert(flights, {
				rock = rock,
				startCFrame = startCFrame,
				landingCFrame = landingCFrame,
				apexHeight = horizontalTravel * math.tan(
					random:NextNumber(ROCK_DEBRIS_LAUNCH_ANGLE_MIN, ROCK_DEBRIS_LAUNCH_ANGLE_MAX)
				) * 0.25,
				flightDuration = random:NextNumber(0.55, 0.75),
			})
		end
	end

	effectFolder.Parent = Workspace.CurrentCamera or Workspace
	for _, flight in ipairs(flights) do
		animateRockFlight(self, generation, flight)
	end
end

local function playFade(self: CutsceneController, transparency: number, generation: number, onComplete: () -> ()): ()
	if self.fadeTween then
		self.fadeTween:Cancel()
		self.fadeTween = nil
	end
	local tween = TweenService:Create(
		self.fadeFrame,
		TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ BackgroundTransparency = transparency }
	)
	self.fadeTween = tween
	self.runMaid:GiveTask(tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if self.fadeTween == tween then
			self.fadeTween = nil
		end
		if playbackState == Enum.PlaybackState.Completed and isCurrentRun(self, generation) then
			onComplete()
		end
	end))
	tween:Play()
end

local function finishRun(self: CutsceneController, generation: number): ()
	if not isCurrentRun(self, generation) then
		return
	end
	local snapshot = self.cameraSnapshot
	if not snapshot then
		destroyRun(self, true, true)
		return
	end

	playFade(self, 0, generation, function()
		local returnTween = TweenService:Create(
			snapshot.camera,
			TweenInfo.new(CAMERA_RETURN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = snapshot.cframe }
		)
		self.runMaid:GiveTask(returnTween)
		self.runMaid:GiveTask(returnTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			if playbackState ~= Enum.PlaybackState.Completed or not isCurrentRun(self, generation) then
				return
			end
			restoreGui(self, true)
			local originalTransparency = if self.guiSnapshot and self.guiSnapshot.fadeVisible
				then self.guiSnapshot.fadeTransparency
				else 1
			playFade(self, originalTransparency, generation, function()
				destroyRun(self, true, true)
			end)
		end))
		returnTween:Play()
	end)
end

local function playCutsceneSound(self: CutsceneController, soundName: string): ()
	local sound = SoundService.PlayGuiSound(soundName)
	if sound then
		local config = SoundService.Sounds[soundName]
		if config and config.AllowOverlap then
			self.runMaid:GiveTask(sound)
		else
			self.runMaid:GiveTask(function()
				if sound.Parent then
					SoundService.StopSound(sound)
				end
			end)
		end
	end
end

local function playImpact(
	self: CutsceneController,
	generation: number,
	shakeValue: NumberValue,
	stumbleValue: NumberValue,
	impactPosition: Vector3,
	group: LuckyBlockGroup,
	petIds: { string },
	fasterOpen: boolean
): ()
	if not isCurrentRun(self, generation) then
		return
	end
	playCutsceneSound(self, "LuckyBlockThump")
	shakeValue.Value = 1
	local shakeTween = TweenService:Create(
		shakeValue,
		TweenInfo.new(IMPACT_SHAKE_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Value = 0 }
	)
	self.runMaid:GiveTask(shakeTween)
	shakeTween:Play()
	animateCraterImpact(self, generation)
	createRockSlamVfx(self, generation, impactPosition)

	if fasterOpen then
		local block = self.model
		local cameraSnapshot = self.cameraSnapshot
		if not block or not cameraSnapshot then
			finishRun(self, generation)
			return
		end
		local revealStarted = PetLuckyBlockRevealController.Play(
			group,
			petIds,
			block,
			cameraSnapshot.camera,
			self.runMaid,
			function(): boolean
				return isCurrentRun(self, generation)
			end,
			function(): ()
				finishRun(self, generation)
			end,
			true
		)
		if not revealStarted then
			finishRun(self, generation)
		end
		return
	end

	stumbleValue.Value = 0
	local stumbleTween = TweenService:Create(
		stumbleValue,
		TweenInfo.new(STUMBLE_DURATION, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut),
		{ Value = STUMBLE_DURATION }
	)
	self.runMaid:GiveTask(stumbleTween)
	self.runMaid:GiveTask(stumbleTween.Completed:Connect(function(stumbleState: Enum.PlaybackState)
		if stumbleState == Enum.PlaybackState.Completed and isCurrentRun(self, generation) then
			local block = self.model
			local cameraSnapshot = self.cameraSnapshot
			if not block or not cameraSnapshot then
				finishRun(self, generation)
				return
			end
			local revealStarted = PetLuckyBlockRevealController.Play(
				group,
				petIds,
				block,
				cameraSnapshot.camera,
				self.runMaid,
				function(): boolean
					return isCurrentRun(self, generation)
				end,
				function(): ()
					finishRun(self, generation)
				end,
				false
			)
			if not revealStarted then
				finishRun(self, generation)
			end
		end
	end))
	stumbleTween:Play()
end

function PetLuckyBlockCutsceneController.new(mainGui: ScreenGui): CutsceneController?
	local player = Players.LocalPlayer
	if not player then
		DebugModule.debugWarn("LocalPlayer missing; cutscene unavailable", MODULE_NAME)
		return nil
	end
	local playerGui = player:WaitForChild("PlayerGui", 10)
	if not playerGui or not playerGui:IsA("PlayerGui") then
		DebugModule.debugWarn("LocalPlayer.PlayerGui missing; cutscene unavailable", MODULE_NAME)
		return nil
	end
	local fadeFrame = mainGui:FindFirstChild("FadeFrame") or mainGui:FindFirstChild("Fadeframe")
	if not fadeFrame then
		fadeFrame = mainGui:WaitForChild("FadeFrame", 10) or mainGui:WaitForChild("Fadeframe", 10)
	end
	if not fadeFrame or not fadeFrame:IsA("Frame") then
		DebugModule.debugWarn("MainGUI FadeFrame/Fadeframe missing or not a Frame; cutscene unavailable", MODULE_NAME)
		return nil
	end
	local controller = setmetatable({
		alive = true,
		isPlaying = false,
		generation = 0,
		model = nil,
		cameraSnapshot = nil,
		guiSnapshot = nil,
		mainGui = mainGui,
		playerGui = playerGui,
		fadeFrame = fadeFrame,
		fadeTween = nil,
		runMaid = Maid.new(),
		onFinished = nil,
		craterVisualState = nil,
		worldVisibilityMask = nil,
		workspaceDescendantConnection = nil,
	}, PetLuckyBlockCutsceneController) :: CutsceneController

	local existingDropoff = Workspace:FindFirstChild(DROPOFF_NAME, true)
	if existingDropoff and existingDropoff:IsA("Model") then
		ensureCraterVisualState(controller, existingDropoff)
	end
	controller.workspaceDescendantConnection = Workspace.DescendantAdded:Connect(function(descendant: Instance)
		if controller.alive and descendant:IsA("Model") and descendant.Name == DROPOFF_NAME then
			ensureCraterVisualState(controller, descendant)
		end
	end)
	return controller
end

function PetLuckyBlockCutsceneController.Play(
	self: CutsceneController,
	group: LuckyBlockGroup,
	petIds: { string },
	fasterOpen: boolean,
	onFinished: (() -> ())?
): boolean
	if not self.alive then
		return false
	end
	if onFinished ~= nil and typeof(onFinished) ~= "function" then
		DebugModule.debugWarn(
			"Rejected invalid cutscene completion callback | type=" .. typeof(onFinished),
			MODULE_NAME
		)
		onFinished = nil
	end
	self:Stop()

	local modelName = MODEL_NAME_BY_GROUP[group]
	local modelFolder = ReplicatedStorage:FindFirstChild(MODEL_FOLDER_NAME)
	local template = modelFolder and modelName and modelFolder:FindFirstChild(modelName)
	if not template or not template:IsA("Model") then
		DebugModule.debugWarn(
			"Lucky Block cutscene model missing | group=" .. group .. " | model=" .. tostring(modelName),
			MODULE_NAME
		)
		return false
	end

	local dropoff = Workspace:FindFirstChild(DROPOFF_NAME, true)
	if dropoff and dropoff:IsA("Model") then
		ensureCraterVisualState(self, dropoff)
	end
	local target = dropoff and dropoff:FindFirstChild(LANDING_PART_NAME, true)
	local cameraMarker = dropoff and dropoff:FindFirstChild(CAMERA_MARKER_NAME, true)
	if not target or not target:IsA("BasePart") then
		DebugModule.debugWarn("Workspace.DropoffCrater.Cylinder missing or not a BasePart", MODULE_NAME)
		return false
	end
	if not cameraMarker or not cameraMarker:IsA("BasePart") then
		DebugModule.debugWarn("Workspace.DropoffCrater.CameraMain missing or not a BasePart", MODULE_NAME)
		return false
	end
	local targetFrame: CFrame? = nil
	local targetHeight: number? = nil
	targetFrame, targetHeight = getTargetFrame(target)
	if not targetFrame or not targetHeight then
		DebugModule.debugWarn("DropoffCrater.Cylinder has no usable bounds", MODULE_NAME)
		return false
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		DebugModule.debugWarn("CurrentCamera missing; Lucky Block cutscene skipped", MODULE_NAME)
		return false
	end

	local block = template:Clone()
	local originalPivot = block:GetPivot()
	local boundsCFrame, boundsSize = block:GetBoundingBox()
	local boundsFromPivot = originalPivot:ToObjectSpace(boundsCFrame)
	local blockHalfHeight = getWorldHeight(boundsCFrame, boundsSize) * 0.5
	local impactPosition = targetFrame.Position + Vector3.yAxis * (targetHeight * 0.5)
	local landingPosition = impactPosition + Vector3.yAxis * blockHalfHeight
	local landingBounds = CFrame.new(landingPosition) * boundsCFrame.Rotation
	local landingPivot = landingBounds * boundsFromPivot:Inverse()
	local cameraPosition = cameraMarker.Position
	local cameraStart = if fasterOpen
		then getCameraFacingBlockCFrame(cameraPosition, landingBounds.Position, 0)
		else getIntroCameraCFrame(cameraMarker)
	local dropHeight = getOffscreenDropHeight(cameraStart, camera.FieldOfView, landingBounds, boundsSize)
	local startingBounds = landingBounds + Vector3.yAxis * dropHeight
	local startingPivot = startingBounds * boundsFromPivot:Inverse()

	for _, descendant in ipairs(block:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		end
	end
	block:PivotTo(if fasterOpen then landingPivot else startingPivot)

	self.generation += 1
	local generation = self.generation
	self.isPlaying = true
	self.model = block
	self.cameraSnapshot = {
		camera = camera,
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		cframe = camera.CFrame,
		focus = camera.Focus,
		fieldOfView = camera.FieldOfView,
	}
	self.guiSnapshot = captureGui(self)
	beginWorldVisibilityMask(self)
	self.onFinished = onFinished
	camera.CameraType = Enum.CameraType.Scriptable

	playFade(self, 0, generation, function()
		hideOtherGui(self)
		block.Parent = Workspace
		local cameraMove = TweenService:Create(
			camera,
			TweenInfo.new(CAMERA_MOVE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = cameraStart }
		)
		self.runMaid:GiveTask(cameraMove)
		self.runMaid:GiveTask(cameraMove.Completed:Connect(function(playbackState: Enum.PlaybackState)
			if playbackState ~= Enum.PlaybackState.Completed or not isCurrentRun(self, generation) then
				return
			end
			playFade(self, 1, generation, function()
				local pivotValue = Instance.new("CFrameValue")
				pivotValue.Value = if fasterOpen then landingPivot else startingPivot
				self.runMaid:GiveTask(pivotValue)
				local shakeValue = Instance.new("NumberValue")
				shakeValue.Value = 0
				self.runMaid:GiveTask(shakeValue)
				local spinValue = Instance.new("NumberValue")
				spinValue.Value = 0
				self.runMaid:GiveTask(spinValue)
				local focusBlend = Instance.new("NumberValue")
				focusBlend.Value = 0
				self.runMaid:GiveTask(focusBlend)
				local stumbleValue = Instance.new("NumberValue")
				stumbleValue.Value = -1
				self.runMaid:GiveTask(stumbleValue)
				local hasEnteredViewport = false
				local impactSoundPlayed = false
				local totalDropHeight = math.max(startingPivot.Position.Y - landingPivot.Position.Y, 0)
				local impactCueDistance = totalDropHeight
					* (1 - (1 - math.clamp(IMPACT_SOUND_LEAD / DROP_DURATION, 0, 1)) ^ 2)
				local function updateShot(): ()
					if not isCurrentRun(self, generation) or not block.Parent then
						return
					end
					if
						not impactSoundPlayed
						and startingPivot.Position.Y - pivotValue.Value.Position.Y >= totalDropHeight - impactCueDistance
					then
						impactSoundPlayed = true
						playCutsceneSound(self, "LuckyBlockImpact")
					end

					local boundsFrame: CFrame
					if stumbleValue.Value >= 0 then
						local elapsed = stumbleValue.Value
						local damping = math.exp(-STUMBLE_DAMPING * elapsed)
						local bounce = (
							math.max(0, math.sin(math.pi * elapsed / IMPACT_BOUNCE_DURATION))
							* IMPACT_BOUNCE_HEIGHT
							* math.exp(-IMPACT_BOUNCE_DAMPING * elapsed)
						)
						local stumbleRotation = CFrame.Angles(
							STUMBLE_X_ANGLE * damping * math.sin(STUMBLE_ANGULAR_FREQUENCY * elapsed + STUMBLE_X_PHASE),
							STUMBLE_YAW_ANGLE * damping * math.sin(STUMBLE_YAW_FREQUENCY * elapsed + STUMBLE_YAW_PHASE),
							STUMBLE_Z_ANGLE
								* damping
								* math.sin(STUMBLE_ANGULAR_FREQUENCY * 1.13 * elapsed + STUMBLE_Z_PHASE)
						)
						local tiltedBounds = CFrame.new(landingBounds.Position)
							* landingBounds.Rotation
							* stumbleRotation
						local floorY = landingBounds.Position.Y - getWorldHeight(landingBounds, boundsSize) * 0.5
						local balancedPosition = Vector3.new(
							landingBounds.Position.X,
							floorY + getWorldHeight(tiltedBounds, boundsSize) * 0.5 + bounce,
							landingBounds.Position.Z
						)
						boundsFrame = CFrame.new(balancedPosition) * tiltedBounds.Rotation
					else
						local baseBounds = pivotValue.Value * boundsFromPivot
						local spinRotation = CFrame.Angles(
							math.rad(360 * TUMBLE_X_TURNS * spinValue.Value),
							math.rad(360 * TUMBLE_Y_TURNS * spinValue.Value),
							math.rad(360 * TUMBLE_Z_TURNS * spinValue.Value)
						)
						boundsFrame = baseBounds * spinRotation
					end

					block:PivotTo(boundsFrame * boundsFromPivot:Inverse())
					local blockFocusPosition = boundsFrame.Position
					if not hasEnteredViewport then
						local _, onScreen = camera:WorldToViewportPoint(blockFocusPosition)
						if onScreen then
							hasEnteredViewport = true
							local focusTween = TweenService:Create(
								focusBlend,
								TweenInfo.new(CAMERA_FOCUS_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
								{ Value = 1 }
							)
							self.runMaid:GiveTask(focusTween)
							focusTween:Play()
						end
					end
					local trackingCFrame =
						getCameraFacingBlockCFrame(cameraPosition, blockFocusPosition, shakeValue.Value)
					camera.CFrame = cameraStart:Lerp(trackingCFrame, focusBlend.Value)
						* getImpactCameraOffset(shakeValue.Value)
					local introFocusPosition = cameraPosition + cameraStart.LookVector * 100
					camera.Focus = CFrame.new(introFocusPosition:Lerp(blockFocusPosition, focusBlend.Value))
				end
				self.runMaid:GiveTask(pivotValue:GetPropertyChangedSignal("Value"):Connect(updateShot))
				self.runMaid:GiveTask(shakeValue:GetPropertyChangedSignal("Value"):Connect(updateShot))
				self.runMaid:GiveTask(spinValue:GetPropertyChangedSignal("Value"):Connect(updateShot))
				self.runMaid:GiveTask(focusBlend:GetPropertyChangedSignal("Value"):Connect(updateShot))
				self.runMaid:GiveTask(stumbleValue:GetPropertyChangedSignal("Value"):Connect(updateShot))
				updateShot()

				if fasterOpen then
					impactSoundPlayed = true
					spinValue.Value = 1
					updateShot()
					playImpact(self, generation, shakeValue, stumbleValue, impactPosition, group, petIds, true)
					return
				end

				local fallInfo = TweenInfo.new(DROP_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				local spinInfo = TweenInfo.new(DROP_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
				local blockTween = TweenService:Create(pivotValue, fallInfo, { Value = landingPivot })
				local spinTween = TweenService:Create(spinValue, spinInfo, { Value = 1 })
				self.runMaid:GiveTask(blockTween)
				self.runMaid:GiveTask(spinTween)
				self.runMaid:GiveTask(blockTween.Completed:Connect(function(dropState: Enum.PlaybackState)
					if dropState ~= Enum.PlaybackState.Completed or not isCurrentRun(self, generation) then
						return
					end
					spinTween:Cancel()
					spinValue.Value = 1
					updateShot()
					if not impactSoundPlayed then
						impactSoundPlayed = true
						playCutsceneSound(self, "LuckyBlockImpact")
					end
					playImpact(self, generation, shakeValue, stumbleValue, impactPosition, group, petIds, false)
				end))
				playCutsceneSound(self, "LuckyBlockFallWhoosh")
				blockTween:Play()
				spinTween:Play()
			end)
		end))
		cameraMove:Play()
	end)
	return true
end

function PetLuckyBlockCutsceneController.Stop(self: CutsceneController): ()
	if not self.isPlaying then
		return
	end
	self.generation += 1
	destroyRun(self, true, true)
end

function PetLuckyBlockCutsceneController.Destroy(self: CutsceneController): ()
	if not self.alive then
		return
	end
	self:Stop()
	self.alive = false
	self.runMaid:DoCleaning()
	if self.workspaceDescendantConnection then
		self.workspaceDescendantConnection:Disconnect()
		self.workspaceDescendantConnection = nil
	end
	if self.craterVisualState then
		releaseCraterVisualState(self.craterVisualState)
		self.craterVisualState = nil
	end
end

return PetLuckyBlockCutsceneController
