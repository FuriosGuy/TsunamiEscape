--!strict

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CoreConfig = require(ReplicatedStorage.Modules.Shared:WaitForChild("CoreConfig_Shared"))
local ColorConfig = require(ReplicatedStorage.Modules.Config:WaitForChild("ColorConfig"))
local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))
local Maid = require(ReplicatedStorage.Modules:WaitForChild("Maid"))
local NumberFormatting = require(ReplicatedStorage.Modules.Shared:WaitForChild("NumberFormatting"))
local ClientCullingService = require(ReplicatedStorage.Modules:WaitForChild("ClientCullingService"))
local VisualFunctions = require(ReplicatedStorage.Modules.UI:WaitForChild("VisualFunctions"))

local HalloweenCandyUIController = {}
HalloweenCandyUIController.__index = HalloweenCandyUIController

local MODULE_NAME = "HalloweenCandyUIController"
local CANDY_COUNT_ATTRIBUTE = "HalloweenCandyCount"
local CANDY_BOOST = require(ReplicatedStorage.Modules.Shared.HalloweenCandyShopConfig).CandyBoost
local CONFIG = CoreConfig.halloweenCandies
assert(typeof(CONFIG) == "table", "CoreConfig_Shared.halloweenCandies is required")

type CandyConfig = { [string]: any }
type CandyEntry = {
	id: number,
	position: Vector3,
	modelName: string,
}
type AnimatedCandy = {
	part: MeshPart,
	hitbox: Part,
	baseCFrame: CFrame,
	animationAccumulator: number,
	animationInterval: number,
	touchConnection: RBXScriptConnection,
	collectionTweens: { Tween }?,
	collectionFadeConnection: RBXScriptConnection?,
	isCollecting: boolean,
}
type HalloweenCandyUIControllerType = {
	root: ScreenGui,
	player: Player,
	config: CandyConfig,
	maid: any,
	characterMaid: any,
	character: Model?,
	rootPart: BasePart?,
	lastRootPosition: Vector3?,
	frame: Frame?,
	countLabel: TextLabel?,
	boostCountdownLabel: TextLabel?,
	localFolder: Folder?,
	templates: { [string]: MeshPart },
	candies: { [number]: AnimatedCandy },
	pendingRequests: { [number]: number },
	queuedRequests: { [number]: boolean },
	enabled: boolean,
	alive: boolean,
	checkAccumulator: number,
	countdownAccumulator: number,
	animationSchedulerAccumulator: number,
	animationDistanceRefreshAccumulator: number,
	lastRequestAt: number,
	snapshotGeneration: number,
	actionRemote: RemoteEvent?,
	_updateCount: (self: HalloweenCandyUIControllerType) -> (),
	_updateBoostCountdown: (self: HalloweenCandyUIControllerType) -> (),
	_setEnabled: (self: HalloweenCandyUIControllerType, enabled: boolean) -> (),
	_destroyCandy: (self: HalloweenCandyUIControllerType, id: number) -> (),
	_clearCandies: (self: HalloweenCandyUIControllerType) -> (),
	_requestCollection: (self: HalloweenCandyUIControllerType, id: number) -> (),
	_collectCandy: (self: HalloweenCandyUIControllerType, id: number) -> (),
	_addCandy: (self: HalloweenCandyUIControllerType, entry: CandyEntry) -> (),
	_updateCandyAnimations: (self: HalloweenCandyUIControllerType, deltaTime: number) -> (),
	_buildSnapshot: (self: HalloweenCandyUIControllerType, rawEntries: any) -> (),
	_showCandyPopup: (self: HalloweenCandyUIControllerType, rewardAmount: number) -> (),
	_onServerUpdate: (self: HalloweenCandyUIControllerType, action: any, payload: any) -> (),
	_flushQueuedRequests: (self: HalloweenCandyUIControllerType) -> (),
	_checkNearbyCandy: (self: HalloweenCandyUIControllerType) -> (),
	_bindCharacter: (self: HalloweenCandyUIControllerType, character: Model) -> (),
	Init: (self: HalloweenCandyUIControllerType) -> (),
	Destroy: (self: HalloweenCandyUIControllerType) -> (),
}

local config = CONFIG :: CandyConfig

local function readPositiveNumber(key: string, fallback: number, minimum: number, maximum: number): number
	local value = config[key]
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local ICON_ASSET_ID = if typeof(config.iconAssetId) == "string"
	then config.iconAssetId
	else "rbxassetid://83732686719326"
local FLOAT_OFFSET = readPositiveNumber("floatOffsetStuds", 2, 0, 10)
local BOB_HEIGHT = readPositiveNumber("bobHeightStuds", 0.65, 0.1, 5)
local BOB_DURATION = readPositiveNumber("bobDurationSeconds", 1.4, 0.3, 10)
local ROTATION_DURATION = readPositiveNumber("rotationDurationSeconds", 4, 0.5, 30)
local ANIMATION_SCHEDULER_INTERVAL = readPositiveNumber("animationSchedulerIntervalSeconds", 1 / 30, 1 / 120, 0.2)
local ANIMATION_DISTANCE_REFRESH = readPositiveNumber("animationDistanceRefreshSeconds", 0.25, 0.05, 2)
local ANIMATION_FULL_RATE_DISTANCE = readPositiveNumber("animationFullRateDistance", 64, 1, 2048)
local ANIMATION_NEAR_DISTANCE = readPositiveNumber("animationNearDistance", 256, 1, 2048)
local ANIMATION_FAR_DISTANCE = readPositiveNumber("animationFarDistance", 384, 1, 2048)
local ANIMATION_PAUSE_DISTANCE = readPositiveNumber("animationPauseDistance", 512, 1, 4096)
local ANIMATION_TARGET_FPS_FULL = readPositiveNumber("animationTargetFpsFull", 30, 1, 60)
local ANIMATION_TARGET_FPS_NEAR = readPositiveNumber("animationTargetFpsNear", 20, 1, 60)
local ANIMATION_TARGET_FPS_FAR = readPositiveNumber("animationTargetFpsFar", 10, 1, 60)
local ANIMATION_TARGET_FPS_VERY_FAR = readPositiveNumber("animationTargetFpsVeryFar", 5, 1, 60)
local CHECK_INTERVAL = readPositiveNumber("clientCollectCheckIntervalSeconds", 0.15, 0.03, 1)
local REQUEST_COOLDOWN = readPositiveNumber("collectRequestCooldownSeconds", 0.15, 0.05, 2)
local CANDY_VISUAL_SIZE_MULTIPLIER = readPositiveNumber("candyVisualSizeMultiplier", 3, 1, 3)
local HITBOX_SIZE_MULTIPLIER = readPositiveNumber("hitboxSizeMultiplier", 2, 1, 5)
local HITBOX_MINIMUM_SIZE = readPositiveNumber("hitboxMinimumSizeStuds", 8, 2, 24)
local HITBOX_COLOR = if typeof(config.hitboxColor) == "Color3" then config.hitboxColor else Color3.new(1, 0, 0)
local HITBOX_TRANSPARENCY = readPositiveNumber("hitboxTransparency", 1, 0, 1)
local HITBOX_TRIGGER_PADDING = readPositiveNumber("hitboxTriggerPaddingStuds", 1, 0, 6)
local CANDY_HIGHLIGHT_COLOR = if typeof(config.highlightColor) == "Color3"
	then config.highlightColor
	else Color3.fromRGB(255, 125, 25)
local CANDY_POINT_LIGHT_COLOR = if typeof(config.pointLightColor) == "Color3"
	then config.pointLightColor
	else Color3.fromRGB(255, 140, 45)
local CANDY_POINT_LIGHT_BRIGHTNESS = readPositiveNumber("pointLightBrightness", 4, 0, 10)
local CANDY_POINT_LIGHT_RANGE = readPositiveNumber("pointLightRange", 16, 1, 60)
local CANDY_POINT_LIGHT_SHADOWS = config.pointLightShadows == true
local COLLECT_FADE_DURATION = readPositiveNumber("collectFadeDurationSeconds", 0.22, 0.05, 2)
local particlesFolder = ReplicatedStorage:FindFirstChild("Particles")
local candyParticleFolder = particlesFolder and particlesFolder:FindFirstChild("CandyParticle")
local candyBurstTemplate = particlesFolder and particlesFolder:FindFirstChild("CandyBurst")
local candyParticleTemplates: { ParticleEmitter } = {}
if candyParticleFolder then
	for _, child in ipairs(candyParticleFolder:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			table.insert(candyParticleTemplates, child)
		end
	end
end

local function playCandyBurst(position: Vector3)
	if not candyBurstTemplate or not candyBurstTemplate:IsA("BasePart") then
		return
	end

	local burstPart = candyBurstTemplate:Clone()
	burstPart.Anchored = true
	burstPart.CanCollide = false
	burstPart.CanTouch = false
	burstPart.CanQuery = false
	burstPart.CastShadow = false
	burstPart.Transparency = 1
	burstPart.CFrame = CFrame.new(position)

	local emitters: { ParticleEmitter } = {}
	local cleanupDelay = 0
	for _, descendant in ipairs(burstPart:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			table.insert(emitters, descendant)
			cleanupDelay = math.max(cleanupDelay, descendant.Lifetime.Max)
		end
	end

	burstPart.Parent = Workspace
	for _, emitter in ipairs(emitters) do
		ClientCullingService.TagInstance(emitter, ClientCullingService.Tags.Particle)
		local emitCount = emitter:GetAttribute("EmitCount")
		if typeof(emitCount) == "number" and emitCount > 0 then
			emitter:Emit(math.floor(emitCount))
		end
	end
	Debris:AddItem(burstPart, cleanupDelay + 0.5)
end

local function clipSegmentAxis(
	origin: number,
	delta: number,
	halfExtent: number,
	minimumT: number,
	maximumT: number
): (boolean, number, number)
	if math.abs(delta) < 1e-6 then
		return origin >= -halfExtent and origin <= halfExtent, minimumT, maximumT
	end

	local firstT = (-halfExtent - origin) / delta
	local secondT = (halfExtent - origin) / delta
	if firstT > secondT then
		firstT, secondT = secondT, firstT
	end

	minimumT = math.max(minimumT, firstT)
	maximumT = math.min(maximumT, secondT)
	return minimumT <= maximumT, minimumT, maximumT
end

local function segmentIntersectsHitbox(
	startPosition: Vector3,
	endPosition: Vector3,
	hitbox: Part
): (boolean, number)
	local startLocal = startPosition - hitbox.Position
	local endLocal = endPosition - hitbox.Position
	local direction = endLocal - startLocal
	local size = hitbox.Size
	local minimumT = 0
	local maximumT = 1
	local intersects: boolean

	intersects, minimumT, maximumT = clipSegmentAxis(
		startLocal.X,
		direction.X,
		size.X / 2 + HITBOX_TRIGGER_PADDING,
		minimumT,
		maximumT
	)
	if not intersects then
		return false, 1
	end
	intersects, minimumT, maximumT = clipSegmentAxis(
		startLocal.Y,
		direction.Y,
		size.Y / 2 + HITBOX_TRIGGER_PADDING,
		minimumT,
		maximumT
	)
	if not intersects then
		return false, 1
	end
	intersects, minimumT, maximumT = clipSegmentAxis(
		startLocal.Z,
		direction.Z,
		size.Z / 2 + HITBOX_TRIGGER_PADDING,
		minimumT,
		maximumT
	)
	return intersects, minimumT
end

local function getCandyTemplates(): { [string]: MeshPart }
	local templates: { [string]: MeshPart } = {}
	local decorations = ReplicatedStorage:FindFirstChild("EventDecorations")
	local candyModels = decorations and decorations:FindFirstChild("CandyModels")
	if not candyModels then
		return templates
	end

	for _, child in ipairs(candyModels:GetChildren()) do
		if child:IsA("MeshPart") then
			templates[child.Name] = child
		end
	end
	return templates
end

local function getCandyAnimationInterval(distance: number, isOnScreen: boolean): number
	if not isOnScreen or distance > ANIMATION_PAUSE_DISTANCE then
		return math.huge
	end

	local targetFps: number
	if distance <= ANIMATION_FULL_RATE_DISTANCE then
		return 1 / ANIMATION_TARGET_FPS_FULL
	elseif distance <= ANIMATION_NEAR_DISTANCE then
		local distanceSpan = math.max(ANIMATION_NEAR_DISTANCE - ANIMATION_FULL_RATE_DISTANCE, 1)
		local alpha = math.clamp((distance - ANIMATION_FULL_RATE_DISTANCE) / distanceSpan, 0, 1)
		targetFps = ANIMATION_TARGET_FPS_FULL + (ANIMATION_TARGET_FPS_NEAR - ANIMATION_TARGET_FPS_FULL) * alpha
	elseif distance <= ANIMATION_FAR_DISTANCE then
		local distanceSpan = math.max(ANIMATION_FAR_DISTANCE - ANIMATION_NEAR_DISTANCE, 1)
		local alpha = math.clamp((distance - ANIMATION_NEAR_DISTANCE) / distanceSpan, 0, 1)
		targetFps = ANIMATION_TARGET_FPS_NEAR + (ANIMATION_TARGET_FPS_FAR - ANIMATION_TARGET_FPS_NEAR) * alpha
	else
		local distanceSpan = math.max(ANIMATION_PAUSE_DISTANCE - ANIMATION_FAR_DISTANCE, 1)
		local alpha = math.clamp((distance - ANIMATION_FAR_DISTANCE) / distanceSpan, 0, 1)
		targetFps = ANIMATION_TARGET_FPS_FAR + (ANIMATION_TARGET_FPS_VERY_FAR - ANIMATION_TARGET_FPS_FAR) * alpha
	end

	return 1 / math.clamp(targetFps, ANIMATION_TARGET_FPS_VERY_FAR, ANIMATION_TARGET_FPS_FULL)
end

function HalloweenCandyUIController.new(root: ScreenGui): HalloweenCandyUIControllerType
	local player = Players.LocalPlayer
	assert(player, "HalloweenCandyUIController must run on the client")

	local self = setmetatable({
		root = root,
		player = player,
		config = config,
		maid = Maid.new(),
		characterMaid = Maid.new(),
		character = nil,
		rootPart = nil,
		lastRootPosition = nil,
		frame = nil,
		countLabel = nil,
		boostCountdownLabel = nil,
		localFolder = nil,
		templates = {},
		candies = {},
		pendingRequests = {},
		queuedRequests = {},
		enabled = false,
		alive = true,
		checkAccumulator = 0,
		countdownAccumulator = 0,
		animationSchedulerAccumulator = 0,
		animationDistanceRefreshAccumulator = ANIMATION_DISTANCE_REFRESH,
		lastRequestAt = -math.huge,
		snapshotGeneration = 0,
		actionRemote = nil,
	}, HalloweenCandyUIController)

	return self :: HalloweenCandyUIControllerType
end

function HalloweenCandyUIController._updateCount(self: HalloweenCandyUIControllerType)
	local label = self.countLabel
	if not label or not label.Parent then
		return
	end

	local value = self.player:GetAttribute(CANDY_COUNT_ATTRIBUTE)
	local count = if typeof(value) == "number" and value == value then math.max(0, math.floor(value)) else 0
	label.Text = NumberFormatting.FormatNumber(count)
end

function HalloweenCandyUIController._updateBoostCountdown(self: HalloweenCandyUIControllerType)
	local label = self.boostCountdownLabel
	if not label or not label.Parent then
		return
	end

	local rawEndTime = self.player:GetAttribute(CANDY_BOOST.endAttributeName)
	local remaining = if typeof(rawEndTime) == "number"
		then math.max(0, math.ceil(rawEndTime - Workspace:GetServerTimeNow()))
		else 0
	if not self.enabled or remaining <= 0 then
		label.Visible = false
		return
	end

	label.Text = string.format(
		"%dx for %02d:%02d",
		CANDY_BOOST.multiplier,
		math.floor(remaining / 60),
		remaining % 60
	)
	label.Visible = true
end

function HalloweenCandyUIController._setEnabled(self: HalloweenCandyUIControllerType, enabled: boolean)
	self.enabled = enabled
	local frame = self.frame
	if frame and frame.Parent then
		frame.Visible = enabled
	end
	if not enabled then
		self.lastRootPosition = nil
		self.animationSchedulerAccumulator = 0
		self.animationDistanceRefreshAccumulator = ANIMATION_DISTANCE_REFRESH
		self:_clearCandies()
	end
	self:_updateBoostCountdown()
end

function HalloweenCandyUIController._destroyCandy(self: HalloweenCandyUIControllerType, id: number)
	self.queuedRequests[id] = nil
	local candy = self.candies[id]
	if not candy then
		return
	end
	self.candies[id] = nil
	candy.touchConnection:Disconnect()
	if candy.collectionFadeConnection then
		candy.collectionFadeConnection:Disconnect()
		candy.collectionFadeConnection = nil
	end
	for _, tween in ipairs(candy.collectionTweens or {}) do
		tween:Cancel()
		tween:Destroy()
	end
	candy.collectionTweens = nil
	candy.part:Destroy()
	candy.hitbox:Destroy()
end

function HalloweenCandyUIController._collectCandy(self: HalloweenCandyUIControllerType, id: number)
	local candy = self.candies[id]
	if not candy or candy.isCollecting then
		return
	end
	candy.isCollecting = true
	candy.hitbox.CanTouch = false
	for _, descendant in ipairs(candy.part:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
		end
	end

	playCandyBurst(candy.part.Position)
	local fadeInfo = TweenInfo.new(COLLECT_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweens: { Tween } = {
		TweenService:Create(candy.part, fadeInfo, { Transparency = 1 }),
	}
	local highlight = candy.part:FindFirstChild("CandyHighlight")
	if highlight and highlight:IsA("Highlight") then
		table.insert(tweens, TweenService:Create(highlight, fadeInfo, { OutlineTransparency = 1 }))
	end
	local pointLight = candy.part:FindFirstChild("CandyPointLight")
	if pointLight and pointLight:IsA("PointLight") then
		table.insert(tweens, TweenService:Create(pointLight, fadeInfo, { Brightness = 0 }))
	end
	candy.collectionTweens = tweens
	candy.collectionFadeConnection = tweens[1].Completed:Connect(function(playbackState: Enum.PlaybackState)
		if playbackState == Enum.PlaybackState.Completed and self.candies[id] == candy then
			self:_destroyCandy(id)
		end
	end)
	for _, tween in ipairs(tweens) do
		tween:Play()
	end
end

function HalloweenCandyUIController._updateCandyAnimations(
	self: HalloweenCandyUIControllerType,
	deltaTime: number
)
	self.animationDistanceRefreshAccumulator += deltaTime
	if self.animationDistanceRefreshAccumulator >= ANIMATION_DISTANCE_REFRESH then
		self.animationDistanceRefreshAccumulator %= ANIMATION_DISTANCE_REFRESH
		local camera = Workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else nil
		for _, candy in pairs(self.candies) do
			if not candy.isCollecting then
				if camera and cameraPosition then
					local _, isOnScreen = camera:WorldToViewportPoint(candy.baseCFrame.Position)
					local distance = (candy.baseCFrame.Position - cameraPosition).Magnitude
					candy.animationInterval = getCandyAnimationInterval(distance, isOnScreen)
				else
					candy.animationInterval = math.huge
				end
			end
		end
	end

	local serverTime = Workspace:GetServerTimeNow()
	for _, candy in pairs(self.candies) do
		if candy.isCollecting then
			continue
		end

		local interval = candy.animationInterval
		if interval == math.huge then
			candy.animationAccumulator = 0
			continue
		end

		candy.animationAccumulator = math.min(candy.animationAccumulator + deltaTime, interval * 2)
		if candy.animationAccumulator < interval then
			continue
		end
		candy.animationAccumulator %= interval

		local cycle = BOB_DURATION * 2
		local bobAlpha = (1 - math.cos((2 * math.pi * serverTime) / cycle)) * 0.5
		local bobOffset = bobAlpha * BOB_HEIGHT
		local basePosition = candy.baseCFrame.Position
		local yaw = (serverTime % ROTATION_DURATION) / ROTATION_DURATION * (2 * math.pi)
		candy.part.CFrame = CFrame.new(basePosition + Vector3.new(0, bobOffset, 0))
			* CFrame.Angles(0, yaw, 0)
			* candy.baseCFrame.Rotation
		candy.hitbox.Position = basePosition + Vector3.new(0, bobOffset, 0)
	end
end

function HalloweenCandyUIController._clearCandies(self: HalloweenCandyUIControllerType)
	self.snapshotGeneration += 1
	self.maid.SnapshotBuild = nil
	for id in pairs(self.candies) do
		self:_destroyCandy(id)
	end
	table.clear(self.pendingRequests)
	table.clear(self.queuedRequests)
end

function HalloweenCandyUIController._requestCollection(self: HalloweenCandyUIControllerType, id: number)
	if not self.alive or not self.enabled or self.pendingRequests[id] then
		return
	end
	local remote = self.actionRemote
	if not remote then
		return
	end

	local now = os.clock()
	if now - self.lastRequestAt < REQUEST_COOLDOWN then
		self.queuedRequests[id] = true
		return
	end
	self.lastRequestAt = now
	self.queuedRequests[id] = nil
	self.pendingRequests[id] = now
	remote:FireServer("Collect", id)
end

function HalloweenCandyUIController._flushQueuedRequests(self: HalloweenCandyUIControllerType)
	if not self.alive or not self.enabled or os.clock() - self.lastRequestAt < REQUEST_COOLDOWN then
		return
	end

	for id in pairs(self.queuedRequests) do
		self:_requestCollection(id)
		return
	end
end

function HalloweenCandyUIController._addCandy(self: HalloweenCandyUIControllerType, entry: CandyEntry)
	if not self.alive or not self.enabled or self.candies[entry.id] then
		return
	end
	local folder = self.localFolder
	local template = self.templates[entry.modelName]
	if not folder or not folder.Parent or not template then
		return
	end

	local part = template:Clone()
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size *= CANDY_VISUAL_SIZE_MULTIPLIER
	local basePosition = entry.position + Vector3.new(0, part.Size.Y / 2 + FLOAT_OFFSET, 0)
	part.Position = basePosition

	local highlight = Instance.new("Highlight")
	highlight.Name = "CandyHighlight"
	highlight.Adornee = part
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 1
	highlight.OutlineColor = CANDY_HIGHLIGHT_COLOR
	highlight.OutlineTransparency = 0
	highlight.Parent = part

	local pointLight = Instance.new("PointLight")
	pointLight.Name = "CandyPointLight"
	pointLight.Color = CANDY_POINT_LIGHT_COLOR
	pointLight.Brightness = CANDY_POINT_LIGHT_BRIGHTNESS
	pointLight.Range = CANDY_POINT_LIGHT_RANGE
	pointLight.Shadows = CANDY_POINT_LIGHT_SHADOWS
	pointLight.Parent = part

	if #candyParticleTemplates > 0 then
		for _, particleTemplate in ipairs(candyParticleTemplates) do
			local particle = particleTemplate:Clone()
			particle.Parent = part
		end
	end

	local hitbox = Instance.new("Part")
	hitbox.Name = string.format("CandyHitbox_%d", entry.id)
	hitbox.Size = Vector3.new(
		math.max(part.Size.X * HITBOX_SIZE_MULTIPLIER, HITBOX_MINIMUM_SIZE),
		math.max(part.Size.Y * HITBOX_SIZE_MULTIPLIER, HITBOX_MINIMUM_SIZE),
		math.max(part.Size.Z * HITBOX_SIZE_MULTIPLIER, HITBOX_MINIMUM_SIZE)
	)
	hitbox.Position = basePosition
	hitbox.Color = HITBOX_COLOR
	hitbox.Transparency = HITBOX_TRANSPARENCY
	hitbox.Material = Enum.Material.SmoothPlastic
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = true
	hitbox.CanQuery = false
	hitbox.CastShadow = false

	local baseCFrame = part.CFrame
	local touchConnection = hitbox.Touched:Connect(function(touchedPart: BasePart)
		local character = self.character
		if character and touchedPart:IsDescendantOf(character) then
			self:_requestCollection(entry.id)
		end
	end)

	self.candies[entry.id] = {
		part = part,
		hitbox = hitbox,
		baseCFrame = baseCFrame,
		animationAccumulator = 0,
		animationInterval = 1 / ANIMATION_TARGET_FPS_FULL,
		touchConnection = touchConnection,
		collectionTweens = nil,
		collectionFadeConnection = nil,
		isCollecting = false,
	}
	part.Parent = folder
	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			ClientCullingService.TagInstance(descendant, ClientCullingService.Tags.Particle)
		elseif descendant:IsA("PointLight") then
			ClientCullingService.TagInstance(descendant, ClientCullingService.Tags.Light)
		end
	end
	hitbox.Parent = folder
end

function HalloweenCandyUIController._buildSnapshot(self: HalloweenCandyUIControllerType, rawEntries: any)
	self:_clearCandies()
	local generation = self.snapshotGeneration
	if typeof(rawEntries) ~= "table" then
		return
	end

	local entries: { CandyEntry } = {}
	for _, rawEntry in ipairs(rawEntries) do
		if typeof(rawEntry) == "table"
			and typeof(rawEntry.id) == "number"
			and rawEntry.id == math.floor(rawEntry.id)
			and rawEntry.id >= 1
			and typeof(rawEntry.position) == "Vector3"
			and typeof(rawEntry.modelName) == "string"
		then
			table.insert(entries, {
				id = rawEntry.id,
				position = rawEntry.position,
				modelName = rawEntry.modelName,
			})
		end
	end

	self.maid.SnapshotBuild = task.spawn(function()
		for index, entry in ipairs(entries) do
			if not self.alive or not self.enabled or self.snapshotGeneration ~= generation then
				return
			end
			self:_addCandy(entry)
			if index % 20 == 0 then
				task.wait()
			end
		end
	end)
end

function HalloweenCandyUIController._showCandyPopup(
	self: HalloweenCandyUIControllerType,
	rewardAmount: number
)
	local template = VisualFunctions.HUD.Float_CurrentWinFrame
	local target = self.frame
	if not template or not target then
		return
	end

	VisualFunctions.CreateFloatingText(template, rewardAmount, 1, {
		TargetFrame = target,
		IntegerOnly = true,
		ImageAssetId = ICON_ASSET_ID,
		TextColor = ColorConfig.Colors.Purple.Color,
		GradientBottomColor = ColorConfig.Colors.Purple.Gradient.Keypoints[2].Value,
	})
end

function HalloweenCandyUIController._onServerUpdate(self: HalloweenCandyUIControllerType, action: any, payload: any)
	if typeof(action) ~= "string" or not self.alive then
		return
	end

	if action == "Disabled" then
		self:_setEnabled(false)
	elseif action == "Snapshot" and typeof(payload) == "table" then
		self:_setEnabled(true)
		self:_buildSnapshot(payload.entries)
	elseif action == "Add" and typeof(payload) == "table" and self.enabled then
		for _, rawEntry in ipairs(payload) do
			if typeof(rawEntry) == "table"
				and typeof(rawEntry.id) == "number"
				and rawEntry.id == math.floor(rawEntry.id)
				and typeof(rawEntry.position) == "Vector3"
				and typeof(rawEntry.modelName) == "string"
			then
				self:_addCandy({
					id = rawEntry.id,
					position = rawEntry.position,
					modelName = rawEntry.modelName,
				})
			end
		end
	elseif action == "Remove" and typeof(payload) == "table" then
		local candyId = payload.id
		local rewardAmount = payload.rewardAmount
		if typeof(candyId) ~= "number" or candyId ~= math.floor(candyId) then
			return
		end
		if typeof(rewardAmount) ~= "number" or rewardAmount < 1 or rewardAmount ~= math.floor(rewardAmount) then
			return
		end
		self.pendingRequests[candyId] = nil
		self:_collectCandy(candyId)
		self:_showCandyPopup(rewardAmount)
	elseif action == "Reject" and typeof(payload) == "number" then
		self.pendingRequests[payload] = nil
	end
end

function HalloweenCandyUIController._checkNearbyCandy(self: HalloweenCandyUIControllerType)
	local rootPart = self.rootPart
	local remote = self.actionRemote
	if not rootPart or not rootPart.Parent or not remote then
		self.lastRootPosition = nil
		return
	end

	local now = os.clock()
	local currentPosition = rootPart.Position
	local previousPosition = self.lastRootPosition or currentPosition
	self.lastRootPosition = currentPosition
	local nearestId: number? = nil
	local firstIntersectionT = math.huge
	for id, candy in pairs(self.candies) do
		local pendingAt = self.pendingRequests[id]
		if pendingAt and now - pendingAt > 4 then
			self.pendingRequests[id] = nil
			pendingAt = nil
		end
		if not pendingAt then
			local hitbox = candy.hitbox
			local intersects, intersectionT = segmentIntersectsHitbox(previousPosition, currentPosition, hitbox)
			if intersects and intersectionT < firstIntersectionT then
				nearestId = id
				firstIntersectionT = intersectionT
			end
		end
	end

	if nearestId then
		self:_requestCollection(nearestId)
	end
end

function HalloweenCandyUIController._bindCharacter(self: HalloweenCandyUIControllerType, character: Model)
	self.characterMaid:DoCleaning()
	self.character = character
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	self.rootPart = if rootPart and rootPart:IsA("BasePart") then rootPart else nil
	self.lastRootPosition = if self.rootPart then self.rootPart.Position else nil
	self.characterMaid.ChildAdded = character.ChildAdded:Connect(function(child: Instance)
		if child.Name == "HumanoidRootPart" and child:IsA("BasePart") then
			self.rootPart = child
			self.lastRootPosition = child.Position
		end
	end)
end

function HalloweenCandyUIController.Init(self: HalloweenCandyUIControllerType)
	local frameInstance = self.root:FindFirstChild("CandyCountFrame")
	if frameInstance and frameInstance:IsA("Frame") then
		self.frame = frameInstance
		self.frame.Visible = false
		local label = frameInstance:FindFirstChild("CandyLabel", true)
		self.countLabel = if label and label:IsA("TextLabel") then label else nil
		local countdownLabel = frameInstance:FindFirstChild("CountdownLabel", true)
		self.boostCountdownLabel = if countdownLabel and countdownLabel:IsA("TextLabel")
			then countdownLabel
			else nil
		if self.boostCountdownLabel then
			self.boostCountdownLabel.Visible = false
		else
			DebugModule.debugWarn("MainGUI.CandyCountFrame.CountdownLabel TextLabel was not found", MODULE_NAME)
		end
		local image = frameInstance:FindFirstChild("RotateImage", true)
		if image and (image:IsA("ImageLabel") or image:IsA("ImageButton")) then
			image.Image = ICON_ASSET_ID
		end
	else
		DebugModule.debugWarn("MainGUI.CandyCountFrame Frame was not found", MODULE_NAME)
	end

	self.templates = getCandyTemplates()
	if next(self.templates) == nil then
		DebugModule.debugWarn("ReplicatedStorage.EventDecorations.CandyModels has no MeshPart templates", MODULE_NAME)
	end

	local folderName = "__LocalHalloweenCandies_" .. tostring(self.player.UserId)
	local existingFolder = Workspace:FindFirstChild(folderName)
	if existingFolder and existingFolder:GetAttribute("LocalHalloweenCandyVisuals") == true then
		existingFolder:Destroy()
	end
	local localFolder = Instance.new("Folder")
	localFolder.Name = folderName
	localFolder:SetAttribute("LocalHalloweenCandyVisuals", true)
	localFolder.Parent = Workspace
	self.localFolder = localFolder

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local actionInstance = remotes:WaitForChild("HalloweenCandyAction")
	local updateInstance = remotes:WaitForChild("HalloweenCandyUpdate")
	if not actionInstance:IsA("RemoteEvent") or not updateInstance:IsA("RemoteEvent") then
		DebugModule.debugWarn("Halloween candy remotes must be RemoteEvents", MODULE_NAME)
		return
	end
	local actionRemote = actionInstance :: RemoteEvent
	self.actionRemote = actionRemote
	self.maid.ServerUpdate = updateInstance.OnClientEvent:Connect(function(action: any, payload: any)
		self:_onServerUpdate(action, payload)
	end)
	self.maid.CandyCountChanged = self.player:GetAttributeChangedSignal(CANDY_COUNT_ATTRIBUTE):Connect(function()
		self:_updateCount()
	end)
	self.maid.CandyBoostChanged = self.player:GetAttributeChangedSignal(CANDY_BOOST.endAttributeName):Connect(function()
		self:_updateBoostCountdown()
	end)
	self.maid.RootDestroying = self.root.Destroying:Connect(function()
		self:Destroy()
	end)
	self.maid.CharacterAdded = self.player.CharacterAdded:Connect(function(character: Model)
		self:_bindCharacter(character)
	end)
	self.maid.CharacterRemoving = self.player.CharacterRemoving:Connect(function(character: Model)
		if self.character == character then
			self.characterMaid:DoCleaning()
			self.character = nil
			self.rootPart = nil
			self.lastRootPosition = nil
		end
	end)
	self.maid.ProximityCheck = RunService.Heartbeat:Connect(function(deltaTime: number)
		self.countdownAccumulator += deltaTime
		if self.countdownAccumulator >= 1 then
			self.countdownAccumulator %= 1
			self:_updateBoostCountdown()
		end
		if not self.enabled or not self.alive then
			return
		end
		self.checkAccumulator += deltaTime
		if self.checkAccumulator < CHECK_INTERVAL then
			return
		end
		self.checkAccumulator %= CHECK_INTERVAL
		self:_flushQueuedRequests()
		self:_checkNearbyCandy()
	end)
	self.maid.CandyAnimationUpdate = RunService.Heartbeat:Connect(function(deltaTime: number)
		if not self.enabled or not self.alive then
			return
		end
		self.animationSchedulerAccumulator = math.min(
			self.animationSchedulerAccumulator + deltaTime,
			ANIMATION_SCHEDULER_INTERVAL * 2
		)
		if self.animationSchedulerAccumulator < ANIMATION_SCHEDULER_INTERVAL then
			return
		end

		local animationDeltaTime = self.animationSchedulerAccumulator
		self.animationSchedulerAccumulator %= ANIMATION_SCHEDULER_INTERVAL
		self:_updateCandyAnimations(animationDeltaTime)
	end)

	if self.player.Character then
		self:_bindCharacter(self.player.Character)
	end
	self:_updateBoostCountdown()
	self:_updateCount()
	actionRemote:FireServer("Sync")
end

function HalloweenCandyUIController.Destroy(self: HalloweenCandyUIControllerType)
	if not self.alive then
		return
	end
	self.alive = false
	self.enabled = false
	self.characterMaid:DoCleaning()
	self.maid:DoCleaning()
	for id in pairs(self.candies) do
		self:_destroyCandy(id)
	end
	table.clear(self.pendingRequests)
	table.clear(self.queuedRequests)
	if self.localFolder then
		self.localFolder:Destroy()
		self.localFolder = nil
	end
	if self.frame and self.frame.Parent then
		self.frame.Visible = false
	end
	self.character = nil
	self.rootPart = nil
	self.actionRemote = nil
end

return HalloweenCandyUIController
