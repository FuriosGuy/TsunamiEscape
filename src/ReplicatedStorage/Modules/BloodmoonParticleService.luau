local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local ClientDeviceProfile = require(ReplicatedStorage.Modules.ClientDeviceProfile)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)

type ParticleConfig = {
	enabled: boolean,
	size: number,
	verticalOffset: number,
	positionUpdateFps: number,
	positionMovementThreshold: number,
	rotationThresholdDegrees: number,
	groundRaycastInterval: number,
	mobileRateMultiplier: number,
}

type ParticleDefinition = {
	templateName: string,
	instanceName: string,
	placementMode: "Ground" | "AbovePlayer",
	verticalOffset: number?,
	size: number?,
}

type BloodmoonParticleController = {
	player: Player,
	config: ParticleConfig,
	maid: any,
	stateMaid: any?,
	characterMaid: any?,
	visualMaid: any?,
	raycastParams: RaycastParams,
	visualGeneration: number,
	lastRootPosition: Vector3?,
	lastRootLookVector: Vector3?,
	lastGrounded: boolean?,
	groundRaycastAccumulator: number,
	lastGroundY: number?,
	stateFolder: Folder?,
	character: Model?,
	humanoid: Humanoid?,
	rootPart: BasePart?,
	visual: BasePart?,
	visualTemplateName: string?,
	visualPlacementMode: ("Ground" | "AbovePlayer")?,
	visualVerticalOffset: number?,
	started: boolean,
	destroyed: boolean,
	templateWarningShown: boolean,
}

local BloodmoonParticleService = {}
BloodmoonParticleService.__index = BloodmoonParticleService

local MODULE_NAME = "BloodmoonParticleService"
local TRANSITION_COMPLETE_ATTRIBUTE = "EnvironmentTransitionComplete"
local PARTICLE_DEFINITIONS: { [string]: ParticleDefinition } = {
	Bloodmoon = {
		templateName = "BloodmoonParticle",
		instanceName = "BloodmoonParticle_Local",
		placementMode = "Ground",
	},
	NeonRush = {
		templateName = "NeonrushParticle",
		instanceName = "NeonrushParticle_Local",
		placementMode = "Ground",
	},
	FrostbiteRally = {
		templateName = "FrostbiteRallyParticle",
		instanceName = "FrostbiteRallyParticle_Local",
		placementMode = "AbovePlayer",
		verticalOffset = 64,
	},
	Halloween = {
		templateName = "HalloweenParticle",
		instanceName = "HalloweenParticle_Local",
		placementMode = "Ground",
		size = 128,
	},
}

local function getConfig(): ParticleConfig
	local rawConfig = CoreConfig.bloodmoonParticle
	if typeof(rawConfig) ~= "table" then
		return {
			enabled = true,
			size = 128,
			verticalOffset = -5,
			positionUpdateFps = 15,
			positionMovementThreshold = 2,
			rotationThresholdDegrees = 20,
			groundRaycastInterval = 0.25,
			mobileRateMultiplier = 0.55,
		}
	end

	local size = if typeof(rawConfig.size) == "number" then math.clamp(rawConfig.size, 1, 512) else 128
	local verticalOffset = if typeof(rawConfig.verticalOffset) == "number" then rawConfig.verticalOffset else -5
	local positionUpdateFps = if typeof(rawConfig.positionUpdateFps) == "number"
		then math.clamp(rawConfig.positionUpdateFps, 1, 60)
		else 15
	local positionMovementThreshold = if typeof(rawConfig.positionMovementThreshold) == "number"
		then math.clamp(rawConfig.positionMovementThreshold, 0, 10)
		else 2
	local rotationThresholdDegrees = if typeof(rawConfig.rotationThresholdDegrees) == "number"
		then math.clamp(rawConfig.rotationThresholdDegrees, 0, 45)
		else 20
	local groundRaycastInterval = if typeof(rawConfig.groundRaycastInterval) == "number"
		then math.clamp(rawConfig.groundRaycastInterval, 0.1, 2)
		else 0.25
	local mobileRateMultiplier = if typeof(rawConfig.mobileRateMultiplier) == "number"
		then math.clamp(rawConfig.mobileRateMultiplier, 0.5, 1)
		else 0.55
	return {
		enabled = rawConfig.enabled ~= false,
		size = size,
		verticalOffset = verticalOffset,
		positionUpdateFps = positionUpdateFps,
		positionMovementThreshold = positionMovementThreshold,
		rotationThresholdDegrees = rotationThresholdDegrees,
		groundRaycastInterval = groundRaycastInterval,
		mobileRateMultiplier = mobileRateMultiplier,
	}
end

local function isGrounded(humanoid: Humanoid): boolean
	if humanoid.Health <= 0 or humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end

	local state = humanoid:GetState()
	return state ~= Enum.HumanoidStateType.Freefall
		and state ~= Enum.HumanoidStateType.Jumping
		and state ~= Enum.HumanoidStateType.FallingDown
		and state ~= Enum.HumanoidStateType.Flying
		and state ~= Enum.HumanoidStateType.Swimming
		and state ~= Enum.HumanoidStateType.Climbing
		and state ~= Enum.HumanoidStateType.Dead
end

local function getRootPart(character: Model): BasePart?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	return if rootPart and rootPart:IsA("BasePart") then rootPart else nil
end

local function getGroundResult(controller: BloodmoonParticleController, rootPart: BasePart): RaycastResult?
	local rayDepth = math.max(8, math.abs(controller.config.verticalOffset) + 3)
	return Workspace:Raycast(rootPart.Position, Vector3.new(0, -rayDepth, 0), controller.raycastParams)
end

local function getGroundCFrame(rootPart: BasePart, groundY: number, height: number): CFrame
	local _, yaw, _ = rootPart.CFrame:ToOrientation()
	return CFrame.new(rootPart.Position.X, groundY + height * 0.5, rootPart.Position.Z) * CFrame.Angles(0, yaw, 0)
end

local function getAbovePlayerCFrame(rootPart: BasePart, verticalOffset: number): CFrame
	local _, yaw, _ = rootPart.CFrame:ToOrientation()
	return CFrame.new(rootPart.Position + Vector3.new(0, verticalOffset, 0)) * CFrame.Angles(0, yaw, 0)
end

local function normalizeParticleRates(
	visual: BasePart,
	sourceSize: Vector3,
	targetSize: number,
	rateMultiplier: number
)
	local sourceArea = math.max(math.abs(sourceSize.X * sourceSize.Z), 0.01)
	local targetArea = math.max(targetSize * targetSize, 0.01)
	-- Scale emission with area so the larger ground effect keeps the same density.
	local rateScale = (targetArea / sourceArea) * rateMultiplier
	if rateScale == 1 then
		return
	end

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Rate *= rateScale
		end
	end
end

function BloodmoonParticleService.new(player: Player): BloodmoonParticleController
	return setmetatable({
		player = player,
		config = getConfig(),
		maid = Maid.new(),
		stateMaid = nil,
		characterMaid = nil,
		visualMaid = nil,
		visualGeneration = 0,
		lastRootPosition = nil,
		lastRootLookVector = nil,
		lastGrounded = nil,
		groundRaycastAccumulator = 0,
		lastGroundY = nil,
		raycastParams = (function(): RaycastParams
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.IgnoreWater = true
			params.RespectCanCollide = true
			return params
		end)(),
		stateFolder = nil,
		character = nil,
		humanoid = nil,
		rootPart = nil,
		visual = nil,
		visualTemplateName = nil,
		visualPlacementMode = nil,
		visualVerticalOffset = nil,
		started = false,
		destroyed = false,
		templateWarningShown = false,
	}, BloodmoonParticleService) :: BloodmoonParticleController
end

function BloodmoonParticleService:_getActiveParticleDefinition(): ParticleDefinition?
	local stateFolder = self.stateFolder
	if not stateFolder then
		return nil
	end
	if self.player:GetAttribute("EventEnvironmentEnabled") == false then
		return nil
	end

	local environmentName = stateFolder:GetAttribute("EnvironmentName")
	if typeof(environmentName) ~= "string" then
		return nil
	end

	local definition = PARTICLE_DEFINITIONS[environmentName]
	if not definition or stateFolder:GetAttribute(TRANSITION_COMPLETE_ATTRIBUTE) ~= true then
		return nil
	end

	return definition
end

function BloodmoonParticleService:_cleanupVisual()
	if self.visualMaid then
		self.visualMaid:DoCleaning()
		self.visualMaid = nil
	end

	self.visual = nil
	self.visualTemplateName = nil
	self.visualPlacementMode = nil
	self.visualVerticalOffset = nil
	self.visualGeneration += 1
	self.lastRootPosition = nil
	self.lastRootLookVector = nil
	self.lastGrounded = nil
	self.groundRaycastAccumulator = 0
	self.lastGroundY = nil
end

function BloodmoonParticleService:_updateVisual(forceUpdate: boolean?)
	if self.destroyed then
		return
	end

	local visual = self.visual
	local character = self.character
	local humanoid = self.humanoid
	local rootPart = self.rootPart
	if not visual or not character or not humanoid or not rootPart then
		return
	end
	if visual.Parent == nil or rootPart.Parent ~= character or humanoid.Parent ~= character then
		self:_cleanupVisual()
		return
	end

	if self.visualPlacementMode == "AbovePlayer" then
		local rootPosition = rootPart.Position
		local rootLookVector = rootPart.CFrame.LookVector
		local minimumMovement = self.config.positionMovementThreshold
		local rotationThreshold = math.cos(math.rad(self.config.rotationThresholdDegrees))
		local movedEnough = self.lastRootPosition == nil
			or (rootPosition - self.lastRootPosition).Magnitude >= minimumMovement
		local rotatedEnough = self.lastRootLookVector == nil
			or self.lastRootLookVector:Dot(rootLookVector) < rotationThreshold
		if forceUpdate or movedEnough or rotatedEnough then
			visual.CFrame = getAbovePlayerCFrame(rootPart, self.visualVerticalOffset or 64)
			self.lastRootPosition = rootPosition
			self.lastRootLookVector = rootLookVector
		end
		return
	end

	-- Leave the effect at its last ground position while the character is airborne.
	local grounded = isGrounded(humanoid)
	self.lastGrounded = grounded
	if not grounded then
		return
	end

	local updateInterval = 1 / self.config.positionUpdateFps
	self.groundRaycastAccumulator += updateInterval

	local rootPosition = rootPart.Position
	local rootLookVector = rootPart.CFrame.LookVector
	local minimumMovement = self.config.positionMovementThreshold
	local rotationThreshold = math.cos(math.rad(self.config.rotationThresholdDegrees))
	local movedEnough = self.lastRootPosition == nil
		or (rootPosition - self.lastRootPosition).Magnitude >= minimumMovement
	local rotatedEnough = self.lastRootLookVector == nil
		or self.lastRootLookVector:Dot(rootLookVector) < rotationThreshold
	if not forceUpdate and not movedEnough and not rotatedEnough and self.lastGroundY ~= nil then
		return
	end

	local groundRefreshDue = self.lastGroundY == nil
		or self.groundRaycastAccumulator >= self.config.groundRaycastInterval
	if forceUpdate or groundRefreshDue or self.lastGroundY == nil then
		local groundResult = getGroundResult(self, rootPart)
		if not groundResult then
			self.lastGroundY = nil
			return
		end

		self.lastGroundY = groundResult.Position.Y
		self.groundRaycastAccumulator = 0
	end

	local groundY = self.lastGroundY
	if groundY == nil then
		return
	end

	visual.CFrame = getGroundCFrame(rootPart, groundY, visual.Size.Y)
	self.lastRootPosition = rootPosition
	self.lastRootLookVector = rootLookVector
end

function BloodmoonParticleService:_createVisual()
	local definition = self:_getActiveParticleDefinition()
	if self.visual or not self.config.enabled or not definition then
		return
	end

	local character = self.character
	local humanoid = self.humanoid
	local rootPart = self.rootPart
	if not character or not humanoid or not rootPart then
		return
	end

	local groundY: number? = nil
	if definition.placementMode == "Ground" then
		if not isGrounded(humanoid) then
			return
		end
		local groundResult = getGroundResult(self, rootPart)
		if not groundResult then
			return
		end
		groundY = groundResult.Position.Y
	end

	local particlesFolder = ReplicatedStorage:FindFirstChild("Particles")
	local template = particlesFolder and particlesFolder:FindFirstChild(definition.templateName)
	if not template or not template:IsA("BasePart") then
		if not self.templateWarningShown then
			self.templateWarningShown = true
			DebugModule.debugWarn(
				"ReplicatedStorage.Particles."
					.. definition.templateName
					.. " is missing or is not a BasePart",
				MODULE_NAME
			)
		end
		return
	end

	local visual = template:Clone()
	visual.Name = definition.instanceName
	local visualSize = definition.size or self.config.size
	visual.Size = Vector3.new(visualSize, math.max(visual.Size.Y, 0.1), visualSize)
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanTouch = false
	visual.CanQuery = false
	visual.CastShadow = false
	visual:SetAttribute("DisableClientCulling", true)
	if definition.placementMode == "AbovePlayer" then
		visual.CFrame = getAbovePlayerCFrame(rootPart, definition.verticalOffset or 64)
	else
		visual.CFrame = getGroundCFrame(rootPart, groundY :: number, visual.Size.Y)
	end
	local mobileRateMultiplier = if ClientDeviceProfile.IsMobile() then self.config.mobileRateMultiplier else 1
	normalizeParticleRates(visual, template.Size, visualSize, mobileRateMultiplier)

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		end
	end

	local visualMaid = Maid.new()
	visualMaid:GiveTask(visual)
	self.visualMaid = visualMaid
	self.visual = visual
	self.visualTemplateName = definition.templateName
	self.visualPlacementMode = definition.placementMode
	self.visualVerticalOffset = definition.verticalOffset
	self.lastGrounded = if definition.placementMode == "Ground" then true else nil
	self.lastGroundY = groundY
	self.lastRootPosition = rootPart.Position
	self.lastRootLookVector = rootPart.CFrame.LookVector
	self.visualGeneration += 1
	local visualGeneration = self.visualGeneration
	visual.Parent = Workspace

	-- A lifetime-guarded loop avoids waking on every rendered frame just to throttle work.
	task.spawn(function()
		while not self.destroyed and self.visual == visual and self.visualGeneration == visualGeneration do
			self:_updateVisual()
			task.wait(1 / self.config.positionUpdateFps)
		end
	end)
end

function BloodmoonParticleService:_refreshVisual(forcePositionUpdate: boolean?)
	local definition = self:_getActiveParticleDefinition()
	if self.destroyed or not definition then
		self:_cleanupVisual()
		return
	end

	if not self.character or not self.humanoid or not self.rootPart then
		self:_cleanupVisual()
		return
	end

	if self.visual
		and (self.visualTemplateName ~= definition.templateName or self.visualPlacementMode ~= definition.placementMode)
	then
		self:_cleanupVisual()
	end

	if not self.visual then
		self:_createVisual()
	elseif forcePositionUpdate then
		self:_updateVisual(true)
	end
end

function BloodmoonParticleService:_clearCharacter(character: Model?)
	if character and self.character ~= character then
		return
	end

	self:_cleanupVisual()
	if self.characterMaid then
		self.characterMaid:DoCleaning()
		self.characterMaid = nil
	end

	self.character = nil
	self.humanoid = nil
	self.rootPart = nil
end

function BloodmoonParticleService:_bindCharacterReferences(character: Model, characterMaid: any)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= self.humanoid then
		self.humanoid = humanoid
		characterMaid.HumanoidDied = if humanoid
			then humanoid.Died:Connect(function()
				self:_cleanupVisual()
			end)
			else nil
		characterMaid.FloorMaterial = if humanoid
			then humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
				local grounded = isGrounded(humanoid)
				local landed = grounded and self.lastGrounded ~= true
				self.lastGrounded = grounded
				self:_refreshVisual(landed)
			end)
			else nil
		characterMaid.HumanoidState = if humanoid
			then humanoid.StateChanged:Connect(function()
				local grounded = isGrounded(humanoid)
				local landed = grounded and self.lastGrounded ~= true
				self.lastGrounded = grounded
				self:_refreshVisual(landed)
			end)
			else nil
	end

	local rootPart = getRootPart(character)
	if rootPart ~= self.rootPart then
		self:_cleanupVisual()
		self.rootPart = rootPart
		self.raycastParams.FilterDescendantsInstances = { character }
		characterMaid.RootAncestry = if rootPart
			then rootPart.AncestryChanged:Connect(function(_, parent: Instance?)
				if parent == nil and self.character == character then
					self.rootPart = nil
					self:_cleanupVisual()
				end
			end)
			else nil
	end

	self:_refreshVisual()
end

function BloodmoonParticleService:_bindCharacter(character: Model)
	self:_clearCharacter()
	self.character = character

	local characterMaid = Maid.new()
	self.characterMaid = characterMaid
	characterMaid.DescendantAdded = character.DescendantAdded:Connect(function()
		if self.character == character then
			self:_bindCharacterReferences(character, characterMaid)
		end
	end)
	characterMaid.Ancestry = character.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent == nil then
			self:_clearCharacter(character)
		end
	end)

	self:_bindCharacterReferences(character, characterMaid)
end

function BloodmoonParticleService:_unbindState()
	if self.stateMaid then
		self.stateMaid:DoCleaning()
		self.stateMaid = nil
	end
	self.stateFolder = nil
end

function BloodmoonParticleService:_bindState(folder: Folder)
	self.maid.StateAdded = nil
	self:_unbindState()
	self.stateFolder = folder

	local stateMaid = Maid.new()
	self.stateMaid = stateMaid
	local refresh = function()
		self:_refreshVisual()
	end
	stateMaid.EnvironmentName = folder:GetAttributeChangedSignal("EnvironmentName"):Connect(refresh)
	stateMaid.ActiveEventIds = folder:GetAttributeChangedSignal("ActiveEventIds"):Connect(refresh)
	stateMaid.TransitionComplete = folder:GetAttributeChangedSignal(TRANSITION_COMPLETE_ATTRIBUTE):Connect(refresh)
	stateMaid.Ancestry = folder.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent == nil and self.stateFolder == folder then
			self:_unbindState()
			self:_watchForState()
		end
	end)

	self:_refreshVisual()
end

function BloodmoonParticleService:_watchForState()
	if self.destroyed or self.stateFolder then
		return
	end

	local existingState = ReplicatedStorage:FindFirstChild("LiveEventState")
	if existingState and existingState:IsA("Folder") then
		self:_bindState(existingState)
		return
	end

	self.maid.StateAdded = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == "LiveEventState" and child:IsA("Folder") then
			self:_bindState(child)
		end
	end)
end

function BloodmoonParticleService:Start()
	if self.started or self.destroyed then
		return
	end
	self.started = true

	self.maid.CharacterAdded = self.player.CharacterAdded:Connect(function(character: Model)
		self:_bindCharacter(character)
	end)
	self.maid.CharacterRemoving = self.player.CharacterRemoving:Connect(function(character: Model)
		self:_clearCharacter(character)
	end)
	self.maid.PlayerRemoving = Players.PlayerRemoving:Connect(function(player: Player)
		if player == self.player then
			self:Destroy()
		end
	end)
	self.maid.EventEnvironmentEnabled = self.player:GetAttributeChangedSignal("EventEnvironmentEnabled"):Connect(function()
		self:_refreshVisual()
	end)

	self:_watchForState()
	if self.player.Character then
		self:_bindCharacter(self.player.Character)
	end
	self:_refreshVisual()
end

function BloodmoonParticleService:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:_cleanupVisual()
	self:_clearCharacter()
	self:_unbindState()
	self.maid:DoCleaning()
	self.started = false
end

return BloodmoonParticleService
