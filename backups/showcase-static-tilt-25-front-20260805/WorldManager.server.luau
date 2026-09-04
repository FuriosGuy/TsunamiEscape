--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")

local Maid = require(ReplicatedStorage.Modules.Maid)
local PlayerHandler = require(ReplicatedStorage.Modules.PlayerHandler)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local ValidationService = require(ReplicatedStorage.Modules.ValidationService)
local ProductService = require(ReplicatedStorage.Modules.ProductService)
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local FunnelAnalytics = require(ReplicatedStorage.Modules.FunnelAnalytics)
local EconomyAnalytics = require(script.Parent.Modules:WaitForChild("EconomyAnalytics"))
local ConfigFolder = ReplicatedStorage.Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

-- Create Remote if not exists
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local WinButtonPressed = Remotes:FindFirstChild("WinButtonPressed")
local XPGainAwarded = Remotes:FindFirstChild("XPGainAwarded") :: RemoteEvent?
if not XPGainAwarded then
	XPGainAwarded = Instance.new("RemoteEvent")
	XPGainAwarded.Name = "XPGainAwarded"
	XPGainAwarded.Parent = Remotes
end
local OpenVerifyFrame = Remotes:FindFirstChild("OpenVerifyFrame") :: RemoteEvent?
if not OpenVerifyFrame then
	OpenVerifyFrame = Instance.new("RemoteEvent")
	OpenVerifyFrame.Name = "OpenVerifyFrame"
	OpenVerifyFrame.Parent = Remotes
end
local ShowNotification = Remotes:FindFirstChild("ShowNotification") :: RemoteEvent?
if not ShowNotification then
	ShowNotification = Instance.new("RemoteEvent")
	ShowNotification.Name = "ShowNotification"
	ShowNotification.Parent = Remotes
end
local KartAction = Remotes:FindFirstChild("KartAction") :: RemoteEvent?
if not KartAction then
	KartAction = Instance.new("RemoteEvent")
	KartAction.Name = "KartAction"
	KartAction.Parent = Remotes
end

local worldManagerConfig = if CoreConfig.server and CoreConfig.server.worldManager
	then CoreConfig.server.worldManager
	else nil
local analyticsConfig = if CoreConfig.analytics then CoreConfig.analytics else nil
local analyticsFunnels = if analyticsConfig and typeof(analyticsConfig.funnels) == "table"
	then analyticsConfig.funnels
	else nil
local KART_PROGRESSION_FUNNEL_NAME = if analyticsFunnels
		and typeof(analyticsFunnels.kartProgression) == "string"
	then analyticsFunnels.kartProgression
	else "KartProgressionFlow"
local DEBOUNCE_TIME = if worldManagerConfig and typeof(worldManagerConfig.debounceTime) == "number"
	then math.max(0, worldManagerConfig.debounceTime)
	else 1.0
local activeMaid = Maid.new()
local scriptAlive = true
local DEBUG_DISABLE_KART_EQUIPPING = if worldManagerConfig
		and typeof(worldManagerConfig.debugDisableKartEquipping) == "boolean"
	then worldManagerConfig.debugDisableKartEquipping
	else false
local DEBUG_DISABLE_KART_SOUNDS = if worldManagerConfig
		and typeof(worldManagerConfig.debugDisableKartSounds) == "boolean"
	then worldManagerConfig.debugDisableKartSounds
	else false
local DEBUG_DISABLE_KART_MOTORS = if worldManagerConfig
		and typeof(worldManagerConfig.debugDisableKartMotors) == "boolean"
	then worldManagerConfig.debugDisableKartMotors
	else false
local DEBUG_DISABLE_KART_WELDS = if worldManagerConfig
		and typeof(worldManagerConfig.debugDisableKartWelds) == "boolean"
	then worldManagerConfig.debugDisableKartWelds
	else false

local playerDebounce = {}
local touchInteractionDebounce: { [Player]: { [string]: number } } = {}
local treadmillPromptDebounce: { [Player]: { [string]: number } } = {}
local verifyOpenDebounce: { [Player]: number } = {}
local vipNotifyDebounce: { [Player]: number } = {}

local KART_HOLDER_NAME = if worldManagerConfig and typeof(worldManagerConfig.kartHolderName) == "string"
	then worldManagerConfig.kartHolderName
	else "EquippedKarts"
local kartHolder = Workspace:FindFirstChild(KART_HOLDER_NAME)
if not kartHolder then
	kartHolder = Instance.new("Folder")
	kartHolder.Name = KART_HOLDER_NAME
	kartHolder.Parent = Workspace
end

type TreadmillDefinition = {
	instance: Instance,
	worldName: string,
	triggerPart: BasePart,
	xpMultiplier: number,
	xpGainInterval: number,
	gamePassId: number?,
}

type ActiveTreadmillState = {
	instance: Instance,
	lastAwardTime: number,
	triggerPart: BasePart,
	worldName: string,
	xpMultiplier: number,
	xpGainInterval: number,
	gamePassId: number?,
}

type EquippedKartState = {
	model: Model,
	templateName: string,
	worldName: string,
	character: Model,
	rootPart: BasePart,
	seatBase: BasePart,
	motors: { Motor6D },
	welds: { WeldConstraint },
}

local treadmillDefinitions: { TreadmillDefinition } = {}
local activeTreadmills: { [Player]: ActiveTreadmillState } = {}
local equippedKarts: { [Player]: EquippedKartState } = {}
local playerBindingMaids: { [Player]: Maid } = {}
local pendingKartResyncs: { [Player]: thread } = {}
local kartCharacterGenerations: { [Player]: number } = {}
local readNumericAttribute: (instance: Instance, attributeName: string) -> number?
local queueKartResync: (player: Player) -> ()
local GAMEPASS_KART_SHOWCASE_TILT_DEGREES = if worldManagerConfig
		and typeof(worldManagerConfig.gamepassKartShowcaseTiltDegrees) == "number"
	then worldManagerConfig.gamepassKartShowcaseTiltDegrees
	else 45
local ACTIVE_TREADMILL_UPDATE_INTERVAL = if worldManagerConfig
		and typeof(worldManagerConfig.activeTreadmillUpdateInterval) == "number"
	then math.max(0.01, worldManagerConfig.activeTreadmillUpdateInterval)
	else 0.1
local TREADMILL_SCAN_INTERVAL = if worldManagerConfig
		and typeof(worldManagerConfig.treadmillScanInterval) == "number"
	then math.max(0.01, worldManagerConfig.treadmillScanInterval)
	else 0.25
local IDLE_TREADMILL_SCAN_INTERVAL = if worldManagerConfig
		and typeof(worldManagerConfig.idleTreadmillScanInterval) == "number"
	then math.max(TREADMILL_SCAN_INTERVAL, worldManagerConfig.idleTreadmillScanInterval)
	else math.max(TREADMILL_SCAN_INTERVAL, 0.6)
local EQUIPPED_KART_RUNTIME_TAG = "SB_EquippedKartRuntime"
local EQUIPPED_KART_MODEL_TAG = "SB_EquippedKartModel"
local EQUIPPED_KART_MOTOR_TAG = "SB_EquippedKartMotor"
local KART_SEAT_FORWARD_OFFSET = -0.15
local KART_SEAT_GROUND_CLEARANCE = 0.01
local KART_SEAT_MIN_Y_OFFSET = 0.1
local KART_SEAT_MAX_Y_OFFSET = 6
local KART_SEAT_GROUND_RAYCAST_DISTANCE = 24
local KART_GROUND_SAMPLE_RADIUS_SCALE = 0.95
local KART_GROUND_MIN_NORMAL_Y = 0.6

local TREADMILL_GAMEPASS_NAMES: { [string]: string } = {
	["3xTreadmill"] = "3xTreadmill",
	["15xTreadmill"] = "15xTreadmill",
	["35xTreadmill"] = "35xTreadmill",
	["100xTreadmill"] = "100xTreadmill",
}

local GAMEPASS_KART_BUTTON_CONFIGS: { [string]: { textColor: Color3 } } = {
	AdvancedTank = {
		textColor = Color3.fromRGB(0, 195, 255),
	},
	ShoppingKart = {
		textColor = Color3.fromRGB(172, 165, 170),
	},
	FormulaCar = {
		textColor = Color3.fromRGB(255, 0, 0),
	},
}

local function consumeTouchInteractionDebounce(player: Player, key: string, duration: number): boolean
	local now = os.clock()
	local playerDebounces = touchInteractionDebounce[player]
	if not playerDebounces then
		playerDebounces = {}
		touchInteractionDebounce[player] = playerDebounces
	end

	local nextAllowedTime = playerDebounces[key]
	if typeof(nextAllowedTime) == "number" and now < nextAllowedTime then
		return false
	end

	playerDebounces[key] = now + duration
	return true
end

local function resetTreadmillModifiers(player: Player)
	player:SetAttribute("Treadmill_XPMultiplier", 1)
	player:SetAttribute("Treadmill_Active", false)
	player:SetAttribute("Movement_XPGainInterval", PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_INTERVAL)
	activeTreadmills[player] = nil
end

local function getPlayerBindingMaid(player: Player): Maid
	local existingMaid = playerBindingMaids[player]
	if existingMaid then
		return existingMaid
	end

	local maid = Maid.new()
	playerBindingMaids[player] = maid
	return maid
end

local function clearPlayerBinding(player: Player)
	local maid = playerBindingMaids[player]
	if maid then
		maid:DoCleaning()
		playerBindingMaids[player] = nil
	end
end

local function clearPendingKartResync(player: Player)
	local pendingThread = pendingKartResyncs[player]
	if pendingThread then
		task.cancel(pendingThread)
		pendingKartResyncs[player] = nil
	end
end

local function getKartCharacterGeneration(player: Player): number
	return kartCharacterGenerations[player] or 0
end

local function getKartFunnelFields(kartName: string, source: string)
	return {
		customField01 = string.sub(kartName, 1, 40),
		customField02 = string.sub(source, 1, 40),
	}
end

local function openKartFunnel(player: Player, kartName: string, source: string, stepName: string): string?
	return FunnelAnalytics.OpenRecurringFunnel(
		player,
		KART_PROGRESSION_FUNNEL_NAME,
		stepName,
		getKartFunnelFields(kartName, source)
	)
end

local function logKartFunnelStep(
	player: Player,
	sessionId: string?,
	kartName: string,
	source: string,
	step: number,
	stepName: string
)
	if not sessionId then
		return
	end

	FunnelAnalytics.LogRecurringStep(
		player,
		KART_PROGRESSION_FUNNEL_NAME,
		sessionId,
		step,
		stepName,
		getKartFunnelFields(kartName, source)
	)
end

local function advanceKartCharacterGeneration(player: Player): number
	local nextGeneration = getKartCharacterGeneration(player) + 1
	kartCharacterGenerations[player] = nextGeneration
	return nextGeneration
end

local function getKartModelsFolder(worldName: string): Instance?
	local kartModelsFolder = ReplicatedStorage:FindFirstChild("KartModels")
	if not kartModelsFolder then
		return nil
	end

	return kartModelsFolder:FindFirstChild(worldName)
end

local function getGamepassKartModelsFolder(): Instance?
	local kartModelsFolder = ReplicatedStorage:FindFirstChild("KartModels")
	if not kartModelsFolder then
		return nil
	end

	return kartModelsFolder:FindFirstChild("Gamepasses")
end

local function findKartModelByNumber(worldName: string, kartNumber: number): Model?
	local worldKartFolder = getKartModelsFolder(worldName)
	if not worldKartFolder then
		return nil
	end

	local prefix = tostring(kartNumber) .. "_"
	for _, child in ipairs(worldKartFolder:GetChildren()) do
		if child:IsA("Model") and string.find(child.Name, prefix, 1, true) == 1 then
			return child
		end
	end

	return nil
end

local function getFallbackRootPartToGroundDistance(character: Model, rootPart: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hipHeight = if humanoid then humanoid.HipHeight else 2
	return hipHeight + (rootPart.Size.Y * 0.5)
end

local function isCharacterGrounded(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

local function getPartVerticalExtent(part: BasePart): number
	local halfSize = part.Size * 0.5
	return math.abs(part.CFrame.XVector.Y) * halfSize.X
		+ math.abs(part.CFrame.YVector.Y) * halfSize.Y
		+ math.abs(part.CFrame.ZVector.Y) * halfSize.Z
end

local function getPartHorizontalExtentsInModelSpace(modelPivot: CFrame, part: BasePart): (number, number)
	local halfSize = part.Size * 0.5
	local localCFrame = modelPivot:ToObjectSpace(part.CFrame)
	local xExtent = math.abs(localCFrame.XVector.X) * halfSize.X
		+ math.abs(localCFrame.YVector.X) * halfSize.Y
		+ math.abs(localCFrame.ZVector.X) * halfSize.Z
	local zExtent = math.abs(localCFrame.XVector.Z) * halfSize.X
		+ math.abs(localCFrame.YVector.Z) * halfSize.Y
		+ math.abs(localCFrame.ZVector.Z) * halfSize.Z
	return xExtent, zExtent
end

local function collectKartWheelParts(model: Model): { BasePart }
	local wheelsFolder = model:FindFirstChild("Wheels")
	local wheelParts: { BasePart } = {}
	if wheelsFolder then
		for _, part in ipairs(wheelsFolder:GetChildren()) do
			if part:IsA("BasePart") then
				table.insert(wheelParts, part)
			end
		end
	end

	if #wheelParts == 0 then
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Name:lower():find("wheel") then
				table.insert(wheelParts, descendant)
			end
		end
	end

	return wheelParts
end

local function getModelLowestLocalY(model: Model): number
	local pivot = model:GetPivot()
	local lowestLocalY = math.huge
	local foundPart = false

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			foundPart = true
			local yExtent = getPartVerticalExtent(descendant)
			local lowestWorldPoint =
				Vector3.new(descendant.Position.X, descendant.Position.Y - yExtent, descendant.Position.Z)
			local localPoint = pivot:PointToObjectSpace(lowestWorldPoint)
			lowestLocalY = math.min(lowestLocalY, localPoint.Y)
		end
	end

	if not foundPart then
		return -0.5
	end

	return lowestLocalY
end

local function getModelHorizontalFootprintRadii(model: Model): (number, number)
	local pivot = model:GetPivot()
	local maxX = 0
	local maxZ = 0

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local localPosition = pivot:PointToObjectSpace(descendant.Position)
			local xExtent, zExtent = getPartHorizontalExtentsInModelSpace(pivot, descendant)
			maxX = math.max(maxX, math.abs(localPosition.X) + xExtent)
			maxZ = math.max(maxZ, math.abs(localPosition.Z) + zExtent)
		end
	end

	return maxX, maxZ
end

local function getOctagonGroundDistance(character: Model, rootPart: BasePart, kartClone: Model): number
	if not isCharacterGrounded(character) then
		return getFallbackRootPartToGroundDistance(character, rootPart)
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true
	raycastParams.FilterDescendantsInstances = { character, kartHolder, kartClone }

	local footprintX, footprintZ = getModelHorizontalFootprintRadii(kartClone)
	local radiusX = math.max(0.5, footprintX * KART_GROUND_SAMPLE_RADIUS_SCALE)
	local radiusZ = math.max(0.5, footprintZ * KART_GROUND_SAMPLE_RADIUS_SCALE)
	local diagonalScale = 0.70710678118
	local sampleFrame = rootPart.CFrame * CFrame.new(0, 0, KART_SEAT_FORWARD_OFFSET)
	local sampleOffsets = {
		Vector3.zero,
		Vector3.new(radiusX, 0, 0),
		Vector3.new(-radiusX, 0, 0),
		Vector3.new(0, 0, radiusZ),
		Vector3.new(0, 0, -radiusZ),
		Vector3.new(radiusX * diagonalScale, 0, radiusZ * diagonalScale),
		Vector3.new(radiusX * diagonalScale, 0, -radiusZ * diagonalScale),
		Vector3.new(-radiusX * diagonalScale, 0, radiusZ * diagonalScale),
		Vector3.new(-radiusX * diagonalScale, 0, -radiusZ * diagonalScale),
	}

	local groundHeights: { number } = {}
	for _, localOffset in ipairs(sampleOffsets) do
		local samplePoint = sampleFrame:PointToWorldSpace(localOffset)
		local rayOrigin = Vector3.new(samplePoint.X, rootPart.Position.Y, samplePoint.Z)
		local rayDirection = Vector3.new(0, -KART_SEAT_GROUND_RAYCAST_DISTANCE, 0)
		local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		if rayResult and rayResult.Normal.Y >= KART_GROUND_MIN_NORMAL_Y then
			table.insert(groundHeights, rayResult.Position.Y)
		end
	end

	if #groundHeights == 0 then
		return getFallbackRootPartToGroundDistance(character, rootPart)
	end

	table.sort(groundHeights)
	local medianIndex = math.ceil(#groundHeights * 0.5)
	local medianGroundY = groundHeights[medianIndex]
	return math.max(0, rootPart.Position.Y - medianGroundY)
end

local function getKartDisplayName(kartModelName: string): string
	local splitIndex = string.find(kartModelName, "_", 1, true)
	if splitIndex then
		return string.sub(kartModelName, splitIndex + 1)
	end

	return kartModelName
end

local function getKartEngineSoundId(kartModelName: string): string | number?
	local soundIdsByKartName: { [string]: string | number } = {
		["6_Racing"] = 140163575364310,
		["7_Military"] = 7211152159,
		["8_Tank"] = 114308002809134,
		["9_Prototype"] = 140163575364310,
		["10_Dragon"] = 140163575364310,
		["11_NeonRacing"] = 79853163770493,
		["12_NeonDragon"] = 79853163770493,
		["FormulaCar"] = 140541364141992,
		["AdvancedTank"] = 7211152159,
	}

	return soundIdsByKartName[kartModelName]
end

local function findKartModelByEquippedName(worldName: string, equippedName: string): Model?
	local worldKartFolder = getKartModelsFolder(worldName)
	local foldersToSearch = {}
	if worldKartFolder then
		table.insert(foldersToSearch, worldKartFolder)
	end

	local gamepassKartFolder = getGamepassKartModelsFolder()
	if gamepassKartFolder then
		table.insert(foldersToSearch, gamepassKartFolder)
	end

	local kartModelsFolder = ReplicatedStorage:FindFirstChild("KartModels")
	local specialKartFolder = kartModelsFolder and kartModelsFolder:FindFirstChild("Specials")
	if specialKartFolder then
		table.insert(foldersToSearch, specialKartFolder)
	end

	for _, folder in ipairs(foldersToSearch) do
		local directMatch = folder:FindFirstChild(equippedName)
		if directMatch and directMatch:IsA("Model") then
			return directMatch
		end

		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") and getKartDisplayName(child.Name) == equippedName then
				return child
			end
		end
	end

	return nil
end

local function getGamepassKartPassId(kartModelName: string): number?
	return ProductService.Gamepasses[kartModelName]
end

type MarketplaceGamePassInfo = {
	name: string?,
	priceInRobux: number?,
}

local gamePassInfoCache: { [number]: MarketplaceGamePassInfo } = {}

local function getMarketplaceGamePassInfo(gamePassId: number): MarketplaceGamePassInfo
	local cachedInfo = gamePassInfoCache[gamePassId]
	if cachedInfo then
		return cachedInfo
	end

	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(gamePassId, Enum.InfoType.GamePass)
	end)

	if success and typeof(info) == "table" then
		local infoTable = info :: { [string]: any }
		local rawName = infoTable.Name
		local rawPrice = infoTable.PriceInRobux

		local resolvedInfo: MarketplaceGamePassInfo = {
			name = if typeof(rawName) == "string" and rawName ~= "" then rawName else nil,
			priceInRobux = if typeof(rawPrice) == "number" and rawPrice >= 0 then math.round(rawPrice) else nil,
		}

		gamePassInfoCache[gamePassId] = resolvedInfo
		return resolvedInfo
	end

	local fallbackInfo: MarketplaceGamePassInfo = {
		name = nil,
		priceInRobux = nil,
	}
	gamePassInfoCache[gamePassId] = fallbackInfo
	return fallbackInfo
end

local function getMarketplaceGamePassName(gamePassId: number): string?
	return getMarketplaceGamePassInfo(gamePassId).name
end

local function getMarketplaceGamePassPriceInRobux(gamePassId: number): number?
	return getMarketplaceGamePassInfo(gamePassId).priceInRobux
end

local function getGamepassKartModelByName(kartName: string): Model?
	local gamepassKartFolder = getGamepassKartModelsFolder()
	if not gamepassKartFolder then
		return nil
	end

	local directMatch = gamepassKartFolder:FindFirstChild(kartName)
	if directMatch and directMatch:IsA("Model") then
		return directMatch
	end

	for _, child in ipairs(gamepassKartFolder:GetChildren()) do
		if child:IsA("Model") and getKartDisplayName(child.Name) == kartName then
			return child
		end
	end

	return nil
end

local function setKartMovementGain(player: Player, kartTemplate: Model?)
	local xpGain = kartTemplate and readNumericAttribute(kartTemplate, "XP_Gain") or nil
	local nextMovementGain = if xpGain ~= nil then xpGain else PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_RATE

	if player:GetAttribute("Movement_XPGainRate") ~= nextMovementGain then
		player:SetAttribute("Movement_XPGainRate", nextMovementGain)
	end
end

local function getCenteredPivot(targetCFrame: CFrame, model: Model): CFrame
	local modelPivot = model:GetPivot()
	local boundingBoxCFrame = select(1, model:GetBoundingBox())
	local centerOffset = modelPivot:ToObjectSpace(boundingBoxCFrame)
	return targetCFrame * centerOffset:Inverse()
end

local function stripShowcaseRigInstances(showcaseModel: Model)
	local removedMotorCount = 0
	local removedWeldCount = 0

	for _, descendant in ipairs(showcaseModel:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			removedMotorCount += 1
			descendant:Destroy()
		elseif descendant:IsA("WeldConstraint") then
			removedWeldCount += 1
			descendant:Destroy()
		end
	end

	if removedMotorCount > 0 or removedWeldCount > 0 then
		DebugModule.debugInfo(
			string.format(
				"Showcase rig cleanup | model=%s | removedMotor6D=%d | removedWeldConstraints=%d",
				showcaseModel.Name,
				removedMotorCount,
				removedWeldCount
			),
			"WorldManager"
		)
	end
end

local function createKartSmokeEffect(rootPart: BasePart): { ParticleEmitter }
	local particlesFolder = ReplicatedStorage:FindFirstChild("Particles")
	local smokeTrailFolder = particlesFolder and particlesFolder:FindFirstChild("SmokeTrail")
	if not smokeTrailFolder then
		return {}
	end

	local smokeEmitters = {}
	for _, descendant in ipairs(smokeTrailFolder:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			local clone = descendant:Clone()
			clone.Enabled = false
			clone.Parent = rootPart
			table.insert(smokeEmitters, clone)
		end
	end

	return smokeEmitters
end

local function cleanupEquippedTrail(player: Player, characterOverride: Model?)
	local targetCharacter = characterOverride or player.Character

	-- Cleanup any server-created legacy attachments/trails (Rule #3.21 reconciliation)
	if targetCharacter then
		local rootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
		if rootPart then
			for _, child in ipairs(rootPart:GetChildren()) do
				-- Only destroy server-side trails (client-side have "ClientTrail" prefix)
				if child:IsA("Attachment") and child.Name:find("_Attachment") and not child.Name:find("Client") then
					child:Destroy()
				elseif child:IsA("Trail") and not child.Name:find("Client") then
					child:Destroy()
				elseif child:IsA("ParticleEmitter") and not child.Name:find("Client") then
					-- Detect server-created emitters by absence of client prefix
					child:Destroy()
				end
			end
		end
	end
end

local function tagKartRuntimeInstance(instance: Instance, player: Player, specificTag: string?)
	if specificTag and not CollectionService:HasTag(instance, specificTag) then
		CollectionService:AddTag(instance, specificTag)
	end

	if not CollectionService:HasTag(instance, EQUIPPED_KART_RUNTIME_TAG) then
		CollectionService:AddTag(instance, EQUIPPED_KART_RUNTIME_TAG)
	end

	instance:SetAttribute("KartOwnerUserId", player.UserId)
end

local function cleanupTaggedKartRuntimeForCharacter(player: Player, character: Model?)
	local ownerUserId = player.UserId
	for _, taggedInstance in ipairs(CollectionService:GetTagged(EQUIPPED_KART_RUNTIME_TAG)) do
		if not taggedInstance.Parent then
			continue
		end

		if taggedInstance:GetAttribute("KartOwnerUserId") ~= ownerUserId then
			continue
		end

		if character and not taggedInstance:IsDescendantOf(character) then
			continue
		end

		taggedInstance:Destroy()
	end
end

local function cleanupEquippedKart(player: Player, characterOverride: Model?)
	local kartState = equippedKarts[player]
	if not kartState then
		-- Fallback to collection service scan if no state (e.g. initial joing)
		cleanupTaggedKartRuntimeForCharacter(player, characterOverride or player.Character)
		return
	end

	-- State-based cleanup
	if kartState.model and kartState.model.Parent then
		kartState.model:Destroy()
	end

	for _, motor in ipairs(kartState.motors) do
		if motor.Parent then
			motor:Destroy()
		end
	end

	if kartState.welds then
		for _, weld in ipairs(kartState.welds) do
			if weld.Parent then
				weld:Destroy()
			end
		end
	end

	-- Fallback tagged cleanup for extra safety
	cleanupTaggedKartRuntimeForCharacter(player, characterOverride or kartState.character)

	equippedKarts[player] = nil
end

local function attachKartToPlayer(player: Player, kartTemplate: Model)
	local previousKartState = equippedKarts[player]
	local preservedVisualOffset = if previousKartState and previousKartState.model
		then previousKartState.model:GetAttribute("VisualOffset")
		else nil
	cleanupEquippedKart(player)

	local character = player.Character
	if not ValidationService.IsCharacterAlive(character) then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then
		return
	end

	local lowerTorso = character:FindFirstChild("LowerTorso") :: BasePart?

	local kartClone = kartTemplate:Clone()
	kartClone.Name = "EquippedKart"

	-- Rig it BEFORE parenting to minimize DescendantAdded churn in PAM (Rule #3)
	tagKartRuntimeInstance(kartClone, player, EQUIPPED_KART_MODEL_TAG)

	-- Identify wheels first to avoid accidental welding during internal pass
	local wheelsToMotorize = collectKartWheelParts(kartClone)

	local rootToGroundDistance = getOctagonGroundDistance(character, rootPart, kartClone)
	local lowestModelLocalY = getModelLowestLocalY(kartClone)
	local seatYOffset = math.clamp(
		rootToGroundDistance + lowestModelLocalY - KART_SEAT_GROUND_CLEARANCE,
		KART_SEAT_MIN_Y_OFFSET,
		KART_SEAT_MAX_Y_OFFSET
	)
	local seatTarget = rootPart.CFrame * CFrame.new(0, -seatYOffset, KART_SEAT_FORWARD_OFFSET)
	kartClone:PivotTo(seatTarget)

	-- Use SeatBase as the authoritative root part for connection (Rule #3.20 Contract)
	local seatBase = kartClone:FindFirstChild("SeatBase", true) :: BasePart?

	if not seatBase then
		kartClone:Destroy()
		warn("Kart missing SeatBase: " .. kartTemplate.Name)
		return
	end

	local createdMotors: { Motor6D } = {}
	local createdWelds: { WeldConstraint } = {}

	-- Fast-configure descendants (Rule #3)
	-- Assumes karts are pre-welded in the template
	for _, descendant in ipairs(kartClone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end

	-- Single attachment connection (Priority 1: SeatBase to Character Root)
	if not DEBUG_DISABLE_KART_WELDS then
		local mainWeld = Instance.new("WeldConstraint")
		mainWeld.Name = "KartMainWeld"
		mainWeld.Part0 = rootPart
		mainWeld.Part1 = seatBase
		mainWeld.Parent = seatBase
		tagKartRuntimeInstance(mainWeld, player, nil)
		table.insert(createdWelds, mainWeld)
	end

	-- Rig Wheels with Motor6Ds
	for _, wheelPart in ipairs(wheelsToMotorize) do
		local wheelMotor = Instance.new("Motor6D")
		wheelMotor.Name = wheelPart.Name .. "_Motor"
		wheelMotor.Part0 = seatBase
		wheelMotor.Part1 = wheelPart
		wheelMotor.C0 = seatBase.CFrame:ToObjectSpace(wheelPart.CFrame)
		wheelMotor.C1 = CFrame.identity
		wheelMotor.Parent = seatBase
		tagKartRuntimeInstance(wheelMotor, player, EQUIPPED_KART_MOTOR_TAG)
		table.insert(createdMotors, wheelMotor)
	end

	if not DEBUG_DISABLE_KART_SOUNDS then
		kartClone:SetAttribute("IsPoliceKart", kartTemplate.Name == "5_Police")
		kartClone:SetAttribute(
			"VisualOffset",
			if typeof(preservedVisualOffset) == "number" then preservedVisualOffset else math.random()
		)
		kartClone:SetAttribute("EngineSoundId", tostring(getKartEngineSoundId(kartTemplate.Name) or 9112787430))
		kartClone:SetAttribute("OwnerUserId", player.UserId)
	end

	-- FINAL PARENTING (Rule #3)
	-- Parenting to Workspace instead of Character to avoid poisoning character-related lifecycle events
	kartClone.Parent = kartHolder

	equippedKarts[player] = {
		model = kartClone,
		templateName = kartTemplate.Name,
		worldName = tostring(player:GetAttribute("Current_World")),
		character = character,
		rootPart = rootPart,
		seatBase = seatBase,
		motors = createdMotors,
		welds = createdWelds,
	}
end

local function isEquippedKartAlreadySynced(player: Player, kartTemplate: Model): boolean
	local kartState = equippedKarts[player]
	local character = player.Character
	if not kartState or not character then
		return false
	end

	if kartState.character ~= character or kartState.rootPart.Parent ~= character then
		return false
	end

	if not kartState.model.Parent or kartState.model.Parent ~= kartHolder then
		return false
	end

	if not kartState.seatBase.Parent or not kartState.seatBase:IsDescendantOf(kartState.model) then
		return false
	end

	for _, motor in ipairs(kartState.motors) do
		if not motor.Parent or motor.Parent ~= kartState.seatBase then
			return false
		end
	end

	for _, weld in ipairs(kartState.welds) do
		if not weld.Parent then
			return false
		end
	end

	return kartState.templateName == kartTemplate.Name
		and kartState.worldName == tostring(player:GetAttribute("Current_World"))
end

local function syncEquippedKart(player: Player)
	if DEBUG_DISABLE_KART_EQUIPPING then
		cleanupEquippedKart(player)
		return
	end

	local currentWorld = player:GetAttribute("Current_World")
	local equippedName = player:GetAttribute("Kart_Equipped")
	if typeof(currentWorld) ~= "string" or typeof(equippedName) ~= "string" then
		cleanupEquippedKart(player)
		setKartMovementGain(player, nil)
		return
	end

	if not ValidationService.IsPlayerAlive(player) then
		cleanupEquippedKart(player)
		return
	end

	local kartTemplate = findKartModelByEquippedName(currentWorld, equippedName)
	if not kartTemplate then
		cleanupEquippedKart(player)
		setKartMovementGain(player, nil)
		return
	end

	setKartMovementGain(player, kartTemplate)
	if isEquippedKartAlreadySynced(player, kartTemplate) then
		return
	end

	attachKartToPlayer(player, kartTemplate)
end

function queueKartResync(player: Player)
	if pendingKartResyncs[player] then
		return
	end

	local queuedGeneration = getKartCharacterGeneration(player)
	pendingKartResyncs[player] = task.defer(function()
		pendingKartResyncs[player] = nil
		if not player.Parent then
			return
		end

		if getKartCharacterGeneration(player) ~= queuedGeneration then
			return
		end

		syncEquippedKart(player)
	end)
end

local function equipKartForPlayer(player: Player, kartName: string)
	if player:GetAttribute("Kart_Equipped") == kartName then
		return
	end

	player:SetAttribute("Kart_Equipped", kartName)
end

local function syncEquippedTrail(player: Player)
	cleanupEquippedTrail(player)
end

local function applyTreadmillToPlayer(
	player: Player,
	worldName: string,
	treadmillInstance: Instance,
	triggerPart: BasePart,
	xpMultiplier: number,
	xpGainInterval: number,
	gamePassId: number?
)
	if not ValidationService.ValidateWorldAccess(player, worldName) then
		return
	end

	local treadmillState = activeTreadmills[player]
	if treadmillState and treadmillState.instance == treadmillInstance then
		return
	end

	activeTreadmills[player] = {
		instance = treadmillInstance,
		lastAwardTime = 0,
		triggerPart = triggerPart,
		worldName = worldName,
		xpMultiplier = xpMultiplier,
		xpGainInterval = xpGainInterval,
		gamePassId = gamePassId,
	}
	player:SetAttribute("Treadmill_XPMultiplier", xpMultiplier)
	player:SetAttribute("Treadmill_Active", true)
	player:SetAttribute("Movement_XPGainInterval", xpGainInterval)
end

local function promptTreadmillGamePass(player: Player, treadmillName: string, gamePassId: number)
	local now = tick()
	local playerPrompts = treadmillPromptDebounce[player]
	if not playerPrompts then
		playerPrompts = {}
		treadmillPromptDebounce[player] = playerPrompts
	end

	local lastPromptTime = playerPrompts[treadmillName]
	if lastPromptTime and now - lastPromptTime < 2 then
		return
	end

	playerPrompts[treadmillName] = now
	ProductService.promptGamePassPurchase(player, gamePassId)
end

function readNumericAttribute(instance: Instance, attributeName: string): number?
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	if typeof(value) == "string" then
		local parsed = tonumber(value)
		if parsed then
			return parsed
		end
	end

	return nil
end

local function isRootPartTouchingPart(rootPart: BasePart?, part: BasePart): boolean
	if not rootPart then
		return false
	end

	local localPosition = part.CFrame:PointToObjectSpace(rootPart.Position)
	local halfSize = (part.Size * 0.5) + Vector3.new(0.25, 0.25, 0.25)
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function isCharacterTouchingPart(character: Model, part: BasePart): boolean
	if not ValidationService.IsCharacterAlive(character) then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	return if rootPart and rootPart:IsA("BasePart") then isRootPartTouchingPart(rootPart, part) else false
end

local function getPlayerFromTouch(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function setupKartButton(kartButton: Instance, worldName: string)
	local kartNumber = readNumericAttribute(kartButton, "KartNumber")
	local winsRequired = readNumericAttribute(kartButton, "WinsRequired")
	local gamepassKartName = string.match(kartButton.Name, "^KartButton_(.+)$")
	local kartTemplate: Model? = nil
	local isGamepassKart = false

	if kartNumber ~= nil then
		kartTemplate = findKartModelByNumber(worldName, kartNumber)
	elseif typeof(gamepassKartName) == "string" and gamepassKartName ~= "" then
		kartTemplate = getGamepassKartModelByName(gamepassKartName)
		isGamepassKart = kartTemplate ~= nil
	else
		DebugModule.debugWarn(
			"KartButton " .. kartButton.Name .. " is missing numerical KartNumber attribute!",
			"WorldManager"
		)
		return
	end

	if not kartTemplate then
		DebugModule.debugWarn(
			string.format("No kart model found for %s in %s", kartButton.Name, worldName),
			"WorldManager"
		)
		return
	end

	local xpGain = readNumericAttribute(kartTemplate, "XP_Gain") or 0
	local billboardGui = kartButton:FindFirstChild("BillboardGui", true) :: BillboardGui?
	if billboardGui then
		local passNameLabel = billboardGui:FindFirstChild("PassName", true) :: TextLabel?
		local stepsLabel = billboardGui:FindFirstChild("StepsCount", true) :: TextLabel?
		local winsLabel = billboardGui:FindFirstChild("RequiredWinsLabel", true) :: TextLabel?
		if passNameLabel then
			if isGamepassKart then
				local gamePassId = getGamepassKartPassId(kartTemplate.Name)
				local gamePassName = if gamePassId then getMarketplaceGamePassName(gamePassId) else nil
				passNameLabel.Text = gamePassName or kartTemplate.Name

				local config = GAMEPASS_KART_BUTTON_CONFIGS[kartTemplate.Name]
				if config then
					passNameLabel.TextColor3 = config.textColor
				end
			else
				passNameLabel.Text = string.upper(kartTemplate.Name)
			end
		end
		if stepsLabel then
			stepsLabel.Text = string.format("+%s/Steps", tostring(math.round(xpGain)))
		end
		if winsLabel then
			if typeof(winsRequired) == "number" then
				winsLabel.Text = string.format("%s Wins Required", tostring(math.round(winsRequired)))
			else
				winsLabel.Visible = false
			end
		end
	end

	local showcasePart = kartButton:FindFirstChild("KartShowcase") :: BasePart?
	if showcasePart then
		local showcaseModel = kartTemplate:Clone()
		showcaseModel.Name = "KartShowcaseModel"
		stripShowcaseRigInstances(showcaseModel)

		for _, descendant in ipairs(showcaseModel:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanTouch = false
			end
		end

		local showcaseOrientation = CFrame.Angles(0, math.rad(90), 0)
		if isGamepassKart then
			showcaseOrientation *= CFrame.Angles(math.rad(GAMEPASS_KART_SHOWCASE_TILT_DEGREES), 0, 0)
		end

		local showcasePivot = getCenteredPivot(showcasePart.CFrame * showcaseOrientation, showcaseModel)
		showcaseModel:PivotTo(showcasePivot)
		showcaseModel:SetAttribute("ShowcaseBasePivot", showcasePivot)
		showcaseModel:SetAttribute("IsPoliceKart", kartTemplate.Name == "5_Police")
		showcaseModel:SetAttribute("VisualOffset", math.random())
		showcaseModel.Parent = kartButton
	end

	local buttonPart = kartButton:FindFirstChild("Button") :: BasePart?
	if not buttonPart then
		DebugModule.debugWarn("KartButton " .. kartButton.Name .. " is missing Button part!", "WorldManager")
		return
	end
	local buttonDebounceKey = "KartButton:" .. kartButton:GetFullName()

	buttonPart.Touched:Connect(function(hit)
		local player = ValidationService.GetAlivePlayerFromTouch(hit)
		if not player then
			return
		end

		if not ValidationService.ValidateWorldAccess(player, worldName) then
			return
		end

		if not consumeTouchInteractionDebounce(player, buttonDebounceKey, DEBOUNCE_TIME) then
			return
		end

		local alreadyOwned = PlayerHandler.OwnsKart(player, kartTemplate.Name)
		local kartFunnelSession = openKartFunnel(player, kartTemplate.Name, "PhysicalButton", "Kart Button Touched")
		if isGamepassKart then
			local gamePassId = getGamepassKartPassId(kartTemplate.Name)
			if not gamePassId then
				logKartFunnelStep(
					player,
					kartFunnelSession,
					kartTemplate.Name,
					"PhysicalButton",
					2,
					"Kart Purchase Failed"
				)
				ShowNotification:FireClient(player, "PURCHASE FAILED!", "Red")
				return
			end

			if not alreadyOwned then
				logKartFunnelStep(
					player,
					kartFunnelSession,
					kartTemplate.Name,
					"PhysicalButton",
					2,
					"Gamepass Prompt Requested"
				)
				ProductService.promptGamePassPurchase(player, gamePassId)
				return
			end
		else
			local currentWins = player:GetAttribute("WinCount") or 0
			if typeof(winsRequired) ~= "number" or (not alreadyOwned and currentWins < winsRequired) then
				logKartFunnelStep(
					player,
					kartFunnelSession,
					kartTemplate.Name,
					"PhysicalButton",
					2,
					"Kart Not Affordable"
				)
				ShowNotification:FireClient(player, "NOT ENOUGH WINS!", "Red")
				return
			end
		end

		if not alreadyOwned then
			if isGamepassKart then
				PlayerHandler.AddOwnedKart(player, kartTemplate.Name)
			else
				if not PlayerHandler.SpendWins(player, winsRequired :: number) then
					logKartFunnelStep(
						player,
						kartFunnelSession,
						kartTemplate.Name,
						"PhysicalButton",
						2,
						"Kart Purchase Failed"
					)
					ShowNotification:FireClient(player, "NOT ENOUGH WINS!", "Red")
					return
				end
				EconomyAnalytics.LogSink(
					player,
					"Wins",
					winsRequired :: number,
					Enum.AnalyticsEconomyTransactionType.Shop.Name,
					"Kart_" .. kartTemplate.Name,
					{ customField01 = kartTemplate.Name, customField02 = "PhysicalButton" }
				)
				PlayerHandler.AddOwnedKart(player, kartTemplate.Name)
			end
			logKartFunnelStep(player, kartFunnelSession, kartTemplate.Name, "PhysicalButton", 2, "Kart Purchased")
		end

		equipKartForPlayer(player, kartTemplate.Name)
		logKartFunnelStep(
			player,
			kartFunnelSession,
			kartTemplate.Name,
			"PhysicalButton",
			if alreadyOwned then 2 else 3,
			"Kart Equipped"
		)
	end)
end

local function setupStagePart(stageInstance: Instance, worldName: string)
	local triggerPart = if stageInstance:IsA("BasePart")
		then stageInstance
		else stageInstance:FindFirstChildWhichIsA("BasePart", true)
	if not triggerPart then
		DebugModule.debugWarn("Stage " .. stageInstance.Name .. " is missing a trigger BasePart!", "WorldManager")
		return
	end

	triggerPart.CanTouch = true

	local stageValue = stageInstance:GetAttribute("Stage")
	if typeof(stageValue) ~= "number" then
		DebugModule.debugWarn(
			"Stage " .. stageInstance.Name .. " is missing numerical Stage attribute!",
			"WorldManager"
		)
		return
	end

	triggerPart.Touched:Connect(function(hit)
		local player = ValidationService.GetAlivePlayerFromTouch(hit)
		if not player then
			return
		end

		if not ValidationService.ValidateWorldAccess(player, worldName) then
			return
		end

		local currentStage = player:GetAttribute("CurrentStage")
		if typeof(currentStage) ~= "number" or stageValue > currentStage then
			player:SetAttribute("CurrentStage", stageValue)
		end
	end)
end

-- [[ INIT WIN BUTTONS ]]
local function setupWinButton(model: Model, worldName: string)
	local isGamepassButton = model.Name == "GamepassButton"
	local twoXWinsGamePassId = ProductService.Gamepasses["2xWins"]
	local winAmount: number? = nil
	local requiredStage: number? = nil

	if isGamepassButton then
		if typeof(twoXWinsGamePassId) ~= "number" then
			DebugModule.debugWarn("GamepassButton setup failed: missing 2xWins gamepass id!", "WorldManager")
			return
		end
	else
		local rawWinAmount = model:GetAttribute("WinAmount")
		if not rawWinAmount or typeof(rawWinAmount) ~= "number" then
			DebugModule.debugWarn(
				"WinButton " .. model.Name .. " is missing numerical WinAmount attribute!",
				"WorldManager"
			)
			return
		end
		winAmount = rawWinAmount
	end

	if not isGamepassButton then
		requiredStage = tonumber(string.match(model.Name, "^WinButton_(%d+)$"))

		if requiredStage == nil then
			requiredStage = readNumericAttribute(model, "Stage")
		end

		if requiredStage == nil then
			local buttonPartForStage = model:FindFirstChild("Button", true)
			if buttonPartForStage then
				requiredStage = readNumericAttribute(buttonPartForStage, "Stage")
			end
		end

		if requiredStage == nil then
			DebugModule.debugWarn(
				"WinButton "
					.. model.Name
					.. " is missing a numerical Stage attribute or valid stage number in its name!",
				"WorldManager"
			)
			return
		end
	end

	-- Billboard UI Text
	local bbGui = model:FindFirstChildWhichIsA("BillboardGui", true)
	if bbGui then
		local label = bbGui:FindFirstChild("WinsLabel", true) :: TextLabel?
		if label and winAmount then
			label.Text = "+" .. tostring(winAmount) .. " Wins"
		end

		if isGamepassButton then
			local gamePassId = twoXWinsGamePassId :: number
			local robuxPrice = getMarketplaceGamePassPriceInRobux(gamePassId)
			local robuxText = if robuxPrice then tostring(robuxPrice) else "--"
			local priceLabel = bbGui:FindFirstChild("PriceLabel", true) :: TextLabel?
			local robuxLabel = bbGui:FindFirstChild("RobuxLabel", true) :: TextLabel?
			if priceLabel then
				priceLabel.Text = robuxText
			end
			if robuxLabel then
				robuxLabel.Text = robuxText
			end
		end
	end

	-- Interaction: Listens for .Touched on a specific part named "Button"
	local buttonPart = model:FindFirstChild("Button", true) :: BasePart?

	local function onTrigger(player: Player)
		if not ValidationService.IsPlayerAlive(player) then
			return
		end

		-- 1. Debounce
		local now = os.clock()
		local nextAllowed = playerDebounce[player]
		if typeof(nextAllowed) == "number" and now < nextAllowed then
			return
		end
		playerDebounce[player] = now + DEBOUNCE_TIME

		-- 2. Validate WinAmount
		-- 3. Anti-Cheat (Current World Validation)
		if not ValidationService.ValidateWorldAccess(player, worldName) then
			return
		end

		if isGamepassButton then
			local gamePassId = twoXWinsGamePassId :: number
			if ProductService.userOwnsGamePass(player, gamePassId) then
				ShowNotification:FireClient(player, "ALREADY OWNED", "Red")
				return
			end

			local promptSuccess, promptError = pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, gamePassId)
			end)
			if not promptSuccess then
				DebugModule.debugWarn(
					"Failed to prompt 2x Wins purchase for " .. player.Name .. ": " .. tostring(promptError),
					"WorldManager"
				)
			end
			return
		end

		if not winAmount or not requiredStage then
			return
		end

		if not ValidationService.ValidateWinButtonStage(player, requiredStage) then
			return
		end

		-- 4. Reward & Teleport
		local rewardedAmount = PlayerHandler.AddWins(player, winAmount)
		EconomyAnalytics.LogSource(
			player,
			"Wins",
			rewardedAmount,
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			"WinButton",
			{ customField01 = worldName, customField02 = tostring(requiredStage) }
		)
		player:SetAttribute("CurrentStage", 0)
		resetTreadmillModifiers(player)

		-- Teleport player to: world's SpawnLocation
		local worldsFolder = Workspace:FindFirstChild("Worlds")
		if worldsFolder then
			local worldFolder = worldsFolder:FindFirstChild(worldName)
			if worldFolder then
				local spawnLoc = worldFolder:FindFirstChild("SpawnLocation") :: BasePart?
				if spawnLoc and player.Character then
					player.Character:PivotTo(spawnLoc:GetPivot() * CFrame.new(0, 3, 0))
				end
			end
		end

		-- 5. Signal Client for Floating Text
		WinButtonPressed:FireClient(player, rewardedAmount, "WinButton")
	end

	if buttonPart then
		buttonPart.Touched:Connect(function(hit)
			local player = ValidationService.GetAlivePlayerFromTouch(hit)
			if player then
				onTrigger(player)
			end
		end)
	else
		DebugModule.debugWarn("WinButton " .. model.Name .. " is missing a child part named 'Button'!", "WorldManager")
	end
end

local function setupTreadmill(treadmillInstance: Instance, worldName: string)
	local xpMultiplier = readNumericAttribute(treadmillInstance, "XP_Multiplier")
	local xpGainInterval = readNumericAttribute(treadmillInstance, "XPGainInterval")
	if treadmillInstance:IsA("Model") then
		if xpMultiplier == nil then
			local touchPart = treadmillInstance:FindFirstChild("TouchPart", true)
			if touchPart then
				xpMultiplier = readNumericAttribute(touchPart, "XP_Multiplier")
			end
		end

		if xpGainInterval == nil then
			local touchPart = treadmillInstance:FindFirstChild("TouchPart", true)
			if touchPart then
				xpGainInterval = readNumericAttribute(touchPart, "XPGainInterval")
			end
		end
	end

	if xpMultiplier == nil then
		DebugModule.debugWarn(
			"Treadmill " .. treadmillInstance.Name .. " is missing numerical XP_Multiplier attribute!",
			"WorldManager"
		)
		return
	end

	if xpGainInterval == nil then
		DebugModule.debugWarn(
			"Treadmill " .. treadmillInstance.Name .. " is missing numerical XPGainInterval attribute!",
			"WorldManager"
		)
		return
	end

	local triggerPart: BasePart? = nil
	local movementPart: BasePart? = nil
	local gamePassId: number? = nil
	if treadmillInstance:IsA("BasePart") then
		triggerPart = treadmillInstance
	elseif treadmillInstance:IsA("Model") then
		triggerPart = treadmillInstance:FindFirstChild("TouchPart", true) :: BasePart?
		movementPart = treadmillInstance:FindFirstChild("MovementPart", true) :: BasePart?
	end

	if not triggerPart then
		DebugModule.debugWarn(
			"Treadmill " .. treadmillInstance.Name .. " is missing a TouchPart trigger!",
			"WorldManager"
		)
		return
	end

	local mappedGamePassName = TREADMILL_GAMEPASS_NAMES[treadmillInstance.Name]
	if mappedGamePassName then
		gamePassId = ProductService.Gamepasses[mappedGamePassName]
		if not gamePassId then
			DebugModule.debugWarn(
				"Treadmill " .. treadmillInstance.Name .. " is missing mapped gamepass ID!",
				"WorldManager"
			)
		end
	end

	table.insert(treadmillDefinitions, {
		instance = treadmillInstance,
		worldName = worldName,
		triggerPart = triggerPart,
		xpMultiplier = xpMultiplier,
		xpGainInterval = xpGainInterval,
		gamePassId = gamePassId,
	})

	local touchDebounceKey = "TreadmillTouch:" .. triggerPart:GetFullName()
	triggerPart.Touched:Connect(function(hit)
		local player = ValidationService.GetAlivePlayerFromTouch(hit)
		if not player then
			return
		end

		if not ValidationService.ValidateWorldAccess(player, worldName) then
			return
		end

		if not consumeTouchInteractionDebounce(player, touchDebounceKey, 0.2) then
			return
		end

		if gamePassId and not ProductService.userOwnsGamePass(player, gamePassId) then
			promptTreadmillGamePass(player, treadmillInstance.Name, gamePassId)
			return
		end

		applyTreadmillToPlayer(
			player,
			worldName,
			treadmillInstance,
			triggerPart,
			xpMultiplier,
			xpGainInterval,
			gamePassId
		)
	end)
end

local function setupGroupChest(groupChest: Instance, worldName: string)
	local rewardTouchPart = groupChest:FindFirstChild("RewardTouchPart", true)
	if not rewardTouchPart or not rewardTouchPart:IsA("BasePart") then
		DebugModule.debugWarn("GroupChest " .. groupChest.Name .. " is missing RewardTouchPart!", "WorldManager")
		return
	end

	rewardTouchPart.Touched:Connect(function(hit)
		local player = ValidationService.GetAlivePlayerFromTouch(hit)
		if not player then
			return
		end

		if not ValidationService.ValidateWorldAccess(player, worldName) then
			return
		end

		local now = tick()
		local lastOpenTime = verifyOpenDebounce[player] or 0
		if now - lastOpenTime < 1.5 then
			return
		end

		verifyOpenDebounce[player] = now
		OpenVerifyFrame:FireClient(player)
	end)
end

local function setupVIPDoor(vipDoor: BasePart)
	vipDoor.Touched:Connect(function(hit)
		local player = ValidationService.GetAlivePlayerFromTouch(hit)
		if not player then
			return
		end

		if player:GetAttribute("HasVIPPass") == true then
			return
		end

		local now = tick()
		local lastNotifyTime = vipNotifyDebounce[player] or 0
		if now - lastNotifyTime < 1.5 then
			return
		end

		vipNotifyDebounce[player] = now
		ShowNotification:FireClient(player, "VIP REQUIRED!", "Red")
	end)
end

-- Initialize Worlds
local function initWorlds()
	local worldsFolder = Workspace:FindFirstChild("Worlds")
	if not worldsFolder then
		DebugModule.debugWarn("Workspace.Worlds folder not found!", "WorldManager")
		return
	end

	for _, world in ipairs(worldsFolder:GetChildren()) do
		local stagesFolder = world:FindFirstChild("Stages")
		if stagesFolder then
			for _, stageInstance in ipairs(stagesFolder:GetChildren()) do
				setupStagePart(stageInstance, world.Name)
			end
		end

		local winButtonsFolder = world:FindFirstChild("WinButtons")
		if winButtonsFolder then
			for _, buttonModel in ipairs(winButtonsFolder:GetChildren()) do
				if
					buttonModel:IsA("Model")
					and (string.match(buttonModel.Name, "WinButton_") or buttonModel.Name == "GamepassButton")
				then
					setupWinButton(buttonModel, world.Name)
				end
			end
		end

		local treadmillsFolder = world:FindFirstChild("Treadmills")
		if treadmillsFolder then
			for _, treadmill in ipairs(treadmillsFolder:GetChildren()) do
				setupTreadmill(treadmill, world.Name)
			end
		end

		local groupChest = world:FindFirstChild("GroupChest")
		if groupChest then
			setupGroupChest(groupChest, world.Name)
		end

		local vipRooms = world:FindFirstChild("VIPRooms")
		if vipRooms then
			for _, descendant in ipairs(vipRooms:GetDescendants()) do
				if descendant:IsA("BasePart") and descendant.Name == "VIPDoor" then
					setupVIPDoor(descendant)
				end
			end
		end

		local kartButtonsFolder = world:FindFirstChild("KartButtons")
		if kartButtonsFolder then
			for _, kartButton in ipairs(kartButtonsFolder:GetChildren()) do
				setupKartButton(kartButton, world.Name)
			end
		end
	end
end

initWorlds()

local function bindKartPlayer(player: Player)
	local playerMaid = getPlayerBindingMaid(player)

	if player.Character then
		advanceKartCharacterGeneration(player)
	end

	playerMaid["KartCharacterAdded"] = player.CharacterAdded:Connect(function()
		advanceKartCharacterGeneration(player)
		queueKartResync(player)
	end)
	playerMaid["KartCharacterRemoving"] = player.CharacterRemoving:Connect(function(removingCharacter)
		clearPendingKartResync(player)
		cleanupEquippedKart(player, removingCharacter)
	end)

	playerMaid["KartEquippedChanged"] = player:GetAttributeChangedSignal("Kart_Equipped"):Connect(function()
		queueKartResync(player)
	end)
	playerMaid["KartWorldChanged"] = player:GetAttributeChangedSignal("Current_World"):Connect(function()
		queueKartResync(player)
	end)

	playerMaid["KartPendingResyncCleanup"] = function()
		clearPendingKartResync(player)
	end

	queueKartResync(player)
end

local function onPlayerAdded(player: Player)
	if player:GetAttribute("WorldManager_Initialized") == true then
		bindKartPlayer(player)
		return
	end
	player:SetAttribute("WorldManager_Initialized", true)
	bindKartPlayer(player)
end

activeMaid.PlayerAdded = Players.PlayerAdded:Connect(onPlayerAdded)
activeMaid.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
	clearPendingKartResync(player)
	cleanupEquippedKart(player)
	cleanupEquippedTrail(player)
	clearPlayerBinding(player)

	local maid = playerBindingMaids[player]
	if maid then
		maid:DoCleaning()
		playerBindingMaids[player] = nil
	end

	kartCharacterGenerations[player] = nil
	playerDebounce[player] = nil
	touchInteractionDebounce[player] = nil
	treadmillPromptDebounce[player] = nil
	activeTreadmills[player] = nil
	verifyOpenDebounce[player] = nil
	vipNotifyDebounce[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

activeMaid.KartAction = KartAction.OnServerEvent:Connect(function(player: Player, action: string, kartName: string)
	if action ~= "Equip" or typeof(kartName) ~= "string" or kartName == "" then
		return
	end

	local kartFunnelSession = openKartFunnel(player, kartName, "UI", "Kart UI Equip Clicked")
	local currentWorld = player:GetAttribute("Current_World")
	local isSpecialKart = typeof(currentWorld) == "string"
		and findKartModelByEquippedName(currentWorld, kartName) ~= nil
	if not getGamepassKartPassId(kartName) and not isSpecialKart then
		logKartFunnelStep(player, kartFunnelSession, kartName, "UI", 2, "Kart Equip Rejected")
		return
	end

	if not PlayerHandler.OwnsKart(player, kartName) then
		logKartFunnelStep(player, kartFunnelSession, kartName, "UI", 2, "Kart Equip Rejected")
		ShowNotification:FireClient(player, "PURCHASE FAILED!", "Red")
		return
	end

	equipKartForPlayer(player, kartName)
	logKartFunnelStep(player, kartFunnelSession, kartName, "UI", 2, "Kart Equipped")
end)

local activeTreadmillUpdateElapsed = 0
local treadmillScanElapsed = 0

activeMaid.Heartbeat = RunService.Heartbeat:Connect(function(dt)
	activeTreadmillUpdateElapsed += dt
	treadmillScanElapsed += dt

	if activeTreadmillUpdateElapsed >= ACTIVE_TREADMILL_UPDATE_INTERVAL then
		activeTreadmillUpdateElapsed = 0
		local now = tick()

		for player, treadmillState in pairs(activeTreadmills) do
			if not player.Parent then
				resetTreadmillModifiers(player)
				continue
			end

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not humanoid or humanoid.Health <= 0 or not rootPart then
				resetTreadmillModifiers(player)
				continue
			end

			local currentWorld = player:GetAttribute("Current_World")
			if typeof(currentWorld) ~= "string" or currentWorld ~= treadmillState.worldName then
				resetTreadmillModifiers(player)
				continue
			end

			if not isRootPartTouchingPart(rootPart, treadmillState.triggerPart) then
				resetTreadmillModifiers(player)
				continue
			end

			if now - treadmillState.lastAwardTime >= treadmillState.xpGainInterval then
				treadmillState.lastAwardTime = now
				local awardedAmount = PlayerHandler.AddXPSpeed(player, PlayerHandler.GetMovementGain(player))
				XPGainAwarded:FireClient(player, awardedAmount)
			end
		end
	end

	if treadmillScanElapsed >= TREADMILL_SCAN_INTERVAL then
		local scanInterval = if next(activeTreadmills) ~= nil
			then TREADMILL_SCAN_INTERVAL
			else IDLE_TREADMILL_SCAN_INTERVAL
		if treadmillScanElapsed < scanInterval then
			return
		end
		treadmillScanElapsed = 0
		if #treadmillDefinitions == 0 then
			return
		end

		for _, player in ipairs(Players:GetPlayers()) do
			if activeTreadmills[player] then
				continue
			end

			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local currentWorld = player:GetAttribute("Current_World")
			if
				not character
				or not humanoid
				or humanoid.Health <= 0
				or not rootPart
				or typeof(currentWorld) ~= "string"
			then
				continue
			end

			for _, treadmillDefinition in ipairs(treadmillDefinitions) do
				if
					treadmillDefinition.worldName == currentWorld
					and isRootPartTouchingPart(rootPart, treadmillDefinition.triggerPart)
				then
					if
						treadmillDefinition.gamePassId
						and not ProductService.userOwnsGamePass(player, treadmillDefinition.gamePassId)
					then
						promptTreadmillGamePass(
							player,
							treadmillDefinition.instance.Name,
							treadmillDefinition.gamePassId
						)
						break
					end

					applyTreadmillToPlayer(
						player,
						treadmillDefinition.worldName,
						treadmillDefinition.instance,
						treadmillDefinition.triggerPart,
						treadmillDefinition.xpMultiplier,
						treadmillDefinition.xpGainInterval,
						treadmillDefinition.gamePassId
					)
					break
				end
			end
		end
	end
end)

-- Cleanup on script destruction (Rule #3.21)
script.Destroying:Connect(function()
	activeMaid:DoCleaning()
	for _, player in ipairs(Players:GetPlayers()) do
		local maid = playerBindingMaids[player]
		if maid then
			maid:DoCleaning()
		end
	end
end)

DebugModule.debugPrint("WorldManager initialized", "WorldManager")
