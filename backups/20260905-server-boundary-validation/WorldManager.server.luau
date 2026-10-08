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
local KartCatalog = require(ReplicatedStorage.Modules.KartCatalog)
local EconomyAnalytics = require(script.Parent.Modules:WaitForChild("EconomyAnalytics"))
local ProductServerService = require(script.Parent.Modules:WaitForChild("ProductServerService"))
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
local BloodmoonWinAwarded = Remotes:FindFirstChild("BloodmoonWinAwarded") :: RemoteEvent?
if not BloodmoonWinAwarded then
	BloodmoonWinAwarded = Instance.new("RemoteEvent")
	BloodmoonWinAwarded.Name = "BloodmoonWinAwarded"
	BloodmoonWinAwarded.Parent = Remotes
end
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
local PurchasePrompt = Remotes:FindFirstChild("PurchasePrompt") :: RemoteEvent?
if not PurchasePrompt then
	PurchasePrompt = Instance.new("RemoteEvent")
	PurchasePrompt.Name = "PurchasePrompt"
	PurchasePrompt.Parent = Remotes
end
local KartAction = Remotes:FindFirstChild("KartAction") :: RemoteEvent?
if not KartAction then
	KartAction = Instance.new("RemoteEvent")
	KartAction.Name = "KartAction"
	KartAction.Parent = Remotes
end
local ReturnToStageService = require(script.Parent.Modules:WaitForChild("ReturnToStageService"))

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
local worldMaid = Maid.new()
local scriptAlive = true
local worldManagerCleanedUp = false
local DEBUG_DISABLE_KART_EQUIPPING = if worldManagerConfig
		and typeof(worldManagerConfig.debugDisableKartEquipping) == "boolean"
	then RunService:IsStudio() and worldManagerConfig.debugDisableKartEquipping
	else false
local DEBUG_DISABLE_KART_SOUNDS = if worldManagerConfig
		and typeof(worldManagerConfig.debugDisableKartSounds) == "boolean"
	then RunService:IsStudio() and worldManagerConfig.debugDisableKartSounds
	else false
local DEBUG_DISABLE_KART_MOTORS = if worldManagerConfig
		and typeof(worldManagerConfig.debugDisableKartMotors) == "boolean"
	then RunService:IsStudio() and worldManagerConfig.debugDisableKartMotors
	else false
local DEBUG_DISABLE_KART_WELDS = if worldManagerConfig
		and typeof(worldManagerConfig.debugDisableKartWelds) == "boolean"
	then RunService:IsStudio() and worldManagerConfig.debugDisableKartWelds
	else false
local INVIS_END_TELEPORT_COOLDOWN = if worldManagerConfig
		and typeof(worldManagerConfig.invisEndTeleportCooldown) == "number"
	then math.max(0.25, worldManagerConfig.invisEndTeleportCooldown)
	else 1

local playerDebounce = {}
local touchInteractionDebounce: { [Player]: { [string]: number } } = {}
local treadmillPromptDebounce: { [Player]: { [string]: number } } = {}
local verifyOpenDebounce: { [Player]: number } = {}
local vipNotifyDebounce: { [Player]: number } = {}
local invisEndTeleportDebounce: { [Player]: number } = {}
local worldFinalStages: { [string]: number } = {}

local function isLiveEventActive(eventId: string): boolean
	local liveEventState = ReplicatedStorage:FindFirstChild("LiveEventState")
	if not liveEventState or not liveEventState:IsA("Folder") then
		return false
	end

	local activeEventIds = liveEventState:GetAttribute("ActiveEventIds")
	if typeof(activeEventIds) ~= "string" then
		return false
	end

	local searchableIds = "," .. activeEventIds .. ","
	return string.find(searchableIds, "," .. eventId .. ",", 1, true) ~= nil
end

local function isBloodmoonActive(): boolean
	return isLiveEventActive("Bloodmoon")
end

local eventBlockOriginalStates: { [Instance]: boolean } = {}
local eventBlockStateFolder: Folder? = nil

local function applyEventBlockState(eventBlock: Instance)
	local eventNameAttribute = eventBlock:GetAttribute("EventName")
	local eventName = if typeof(eventNameAttribute) == "string" and eventNameAttribute ~= ""
		then eventNameAttribute
		else "Bloodmoon"
	local eventActive = isLiveEventActive(eventName)

	for _, descendant in ipairs(eventBlock:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local originalCanCollide = eventBlockOriginalStates[descendant]
			if originalCanCollide == nil then
				originalCanCollide = descendant.CanCollide
				eventBlockOriginalStates[descendant] = originalCanCollide
			end
			descendant.CanCollide = if eventActive then false else originalCanCollide
		elseif descendant:IsA("BillboardGui") then
			if descendant.Name == "EventBillboard" then
				descendant.Enabled = eventActive
				continue
			end

			local originalEnabled = eventBlockOriginalStates[descendant]
			if originalEnabled == nil then
				originalEnabled = descendant.Enabled
				eventBlockOriginalStates[descendant] = originalEnabled
			end
			descendant.Enabled = if eventActive then false else originalEnabled
		elseif descendant:IsA("SurfaceGui") then
			local originalEnabled = eventBlockOriginalStates[descendant]
			if originalEnabled == nil then
				originalEnabled = descendant.Enabled
				eventBlockOriginalStates[descendant] = originalEnabled
			end
			descendant.Enabled = if eventActive then false else originalEnabled
		end
	end
end

local function setupEventBlock(eventBlock: Instance)
	local function bindStateFolder(candidate: Instance)
		if not candidate:IsA("Folder") or eventBlockStateFolder == candidate then
			return
		end

		eventBlockStateFolder = candidate
		worldMaid.EventBlockStateChanged = candidate:GetAttributeChangedSignal("ActiveEventIds"):Connect(function()
			applyEventBlockState(eventBlock)
		end)
		applyEventBlockState(eventBlock)
	end

	local existingStateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
	if existingStateFolder then
		bindStateFolder(existingStateFolder)
	end

	worldMaid.EventBlockStateFolderAdded = ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "LiveEventState" then
			bindStateFolder(child)
		end
	end)
	applyEventBlockState(eventBlock)
end

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

local BRIGHTEST_RED_HIGHLIGHT_COLOR = Color3.fromRGB(255, 0, 0)

local GAMEPASS_KART_SHOWCASE_HIGHLIGHT_COLORS: { [string]: Color3 } = {
	AdvancedTank = Color3.fromRGB(0, 255, 255),
	ShoppingKart = Color3.fromRGB(0, 255, 0),
	FormulaCar = BRIGHTEST_RED_HIGHLIGHT_COLOR,
}

local function addKartShowcaseHighlight(showcaseModel: Model, color: Color3)
	local highlight = Instance.new("Highlight")
	highlight.Name = "KartShowcaseHighlight"
	highlight.Adornee = showcaseModel
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillTransparency = 1
	highlight.OutlineColor = color
	highlight.OutlineTransparency = 0
	highlight.Parent = showcaseModel
end

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

	if KartCatalog.FindEventModel("Bloodmoon", kartModelName) then
		local normalizedName = string.lower(kartModelName)
		if string.find(normalizedName, "siege", 1, true) and string.find(normalizedName, "tank", 1, true) then
			return soundIdsByKartName["AdvancedTank"]
		end
		return soundIdsByKartName["11_NeonRacing"]
	end

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

	local nestedSpecialMatch = KartCatalog.FindSpecialModel(equippedName)
	if nestedSpecialMatch then
		return nestedSpecialMatch
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

type MarketplaceProductInfo = {
	name: string?,
	priceInRobux: number?,
}

local productInfoCache: { [number]: MarketplaceProductInfo } = {}

local function getMarketplaceProductInfo(productId: number): MarketplaceProductInfo
	local cachedInfo = productInfoCache[productId]
	if cachedInfo then
		return cachedInfo
	end

	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)

	if success and typeof(info) == "table" then
		local infoTable = info :: { [string]: any }
		local resolvedInfo: MarketplaceProductInfo = {
			name = if typeof(infoTable.Name) == "string" and infoTable.Name ~= ""
				then infoTable.Name
				else nil,
			priceInRobux = if typeof(infoTable.PriceInRobux) == "number" and infoTable.PriceInRobux >= 0
				then math.round(infoTable.PriceInRobux)
				else nil,
		}
		productInfoCache[productId] = resolvedInfo
		return resolvedInfo
	end

	DebugModule.debugWarn(
		"Failed developer product metadata lookup | productId=" .. tostring(productId),
		"WorldManager"
	)
	local fallbackInfo: MarketplaceProductInfo = {
		name = nil,
		priceInRobux = nil,
	}
	productInfoCache[productId] = fallbackInfo
	return fallbackInfo
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
		DebugModule.debugWarn("Kart missing SeatBase: " .. kartTemplate.Name, "WorldManager")
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
		return true
	end
	if player:GetAttribute("Data_Loaded") ~= true then
		DebugModule.debugWarn(
			"Kart equip rejected before data load | player=" .. player.Name .. " | kart=" .. kartName,
			"WorldManager"
		)
		return false
	end

	local previousKart = player:GetAttribute("Kart_Equipped")
	player:SetAttribute("Kart_Equipped", kartName)
	if not ProductServerService.SavePlayerData(player) then
		if typeof(previousKart) == "string" then
			player:SetAttribute("Kart_Equipped", previousKart)
		end
		DebugModule.debugWarn(
			"Kart equip save could not be scheduled | player=" .. player.Name .. " | kart=" .. kartName,
			"WorldManager"
		)
		return false
	end

	DebugModule.debugInfo(
		"Kart equipped and save scheduled | player=" .. player.Name .. " | kart=" .. kartName,
		"WorldManager"
	)
	return true
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
	if not ValidationService.ValidateRewardEligibility(player, "Treadmill") then
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
	local characterPlayer = ValidationService.GetAlivePlayerFromTouch(hit)
	if characterPlayer then
		return characterPlayer
	end

	local kartModel = hit:FindFirstAncestor("EquippedKart")
	if not kartModel or not kartModel:IsA("Model") then
		return nil
	end

	local ownerUserId = kartModel:GetAttribute("KartOwnerUserId")
	if typeof(ownerUserId) ~= "number" then
		return nil
	end

	local owner = Players:GetPlayerByUserId(ownerUserId)
	return if owner and ValidationService.IsPlayerAlive(owner) then owner else nil
end

local function setupInvisEndTeleport(triggerPart: BasePart, worldName: string)
	if worldName ~= "World1" then
		return
	end

	local destination = ReturnToStageService.GetNearestTsunamiCover(worldName, triggerPart.Position)
	if not destination then
		DebugModule.debugWarn(
			string.format(
				"InvisEnd redirect disabled: no TsunamiCover found near %s in %s",
				triggerPart.Name,
				worldName
			),
			"WorldManager"
		)
		return
	end

	triggerPart.CanTouch = true
	worldMaid:GiveTask(triggerPart.Touched:Connect(function(hit: BasePart)
		if not scriptAlive then
			return
		end

		local player = getPlayerFromTouch(hit)
		if not player or player:GetAttribute("Current_World") ~= worldName then
			return
		end
		if not ValidationService.ValidateWorldAccess(player, worldName) then
			return
		end

		local now = os.clock()
		local lastTeleport = invisEndTeleportDebounce[player] or 0
		if now - lastTeleport < INVIS_END_TELEPORT_COOLDOWN then
			return
		end
		invisEndTeleportDebounce[player] = now

		local character = player.Character
		local humanoid = ValidationService.GetAliveHumanoid(character)
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or not rootPart or not rootPart:IsA("BasePart") then
			return
		end

		local worldsFolder = Workspace:FindFirstChild("Worlds")
		local expectedWorld = worldsFolder and worldsFolder:FindFirstChild(worldName)
		if not expectedWorld or not expectedWorld:IsDescendantOf(Workspace) then
			return
		end
		if not destination.Parent or not destination:IsDescendantOf(expectedWorld) then
			destination = ReturnToStageService.GetNearestTsunamiCover(worldName, triggerPart.Position)
		end
		if not destination or not destination.Parent or not destination:IsDescendantOf(expectedWorld) then
			return
		end

		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
		character:PivotTo(destination.CFrame * CFrame.new(0, 3, 0))
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
		ValidationService.MarkServerTeleport(player)
	end))

	DebugModule.debugInfo(
		string.format(
			"%s redirect armed | world=%s | destination=%s",
			triggerPart.Name,
			worldName,
			destination:GetFullName()
		),
		"WorldManager"
	)
end

local function setupKartButton(kartButton: Instance, worldName: string)
	local kartNumber = readNumericAttribute(kartButton, "KartNumber")
	local winsRequired = readNumericAttribute(kartButton, "WinsRequired")
	local eventNameAttribute = kartButton:GetAttribute("EventName")
	local eventName = if typeof(eventNameAttribute) == "string" and eventNameAttribute ~= ""
		then eventNameAttribute
		else nil
	local eventKartNameAttribute = kartButton:GetAttribute("KartName")
	local eventKartName = if typeof(eventKartNameAttribute) == "string" and eventKartNameAttribute ~= ""
		then eventKartNameAttribute
		else nil
	local productKeyAttribute = kartButton:GetAttribute("ProductKey")
	local productKey = if typeof(productKeyAttribute) == "string" and productKeyAttribute ~= ""
		then productKeyAttribute
		else nil
	local productConfig = if productKey then ProductService.BloodmoonKartProducts[productKey] else nil
	local gamepassKartName = string.match(kartButton.Name, "^KartButton_(.+)$")
	local kartTemplate: Model? = nil
	local isGamepassKart = false
	local isProductKart = typeof(productConfig) == "table"
	local isEventKart = false

	if productKey ~= nil and not isProductKart then
		DebugModule.debugWarn(
			"Kart button references unknown Bloodmoon product | button="
				.. kartButton:GetFullName()
				.. " | product="
				.. productKey,
			"WorldManager"
		)
		return
	elseif isProductKart then
		local configuredKartName = productConfig.KartName
		local configuredEventName = productConfig.EventName
		if typeof(configuredKartName) ~= "string" or typeof(configuredEventName) ~= "string" then
			DebugModule.debugWarn(
				"Bloodmoon product configuration is incomplete | product=" .. tostring(productKey),
				"WorldManager"
			)
			return
		end
		eventName = configuredEventName
		eventKartName = configuredKartName
		kartTemplate = KartCatalog.FindEventModel(configuredEventName, configuredKartName)
	elseif eventName ~= nil and eventKartName ~= nil then
		isEventKart = true
		kartTemplate = KartCatalog.FindEventModel(eventName :: string, eventKartName :: string)
	elseif kartNumber ~= nil then
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
			elseif isProductKart then
				local productId = if productKey then ProductService.DevProducts[productKey] else nil
				local productInfo = if typeof(productId) == "number"
					then getMarketplaceProductInfo(productId)
					else nil
				passNameLabel.Text = if productInfo and productInfo.name
					then productInfo.name
					else kartTemplate.Name
				if productInfo then
					local priceText = if productInfo.priceInRobux then tostring(productInfo.priceInRobux) else "--"
					for _, labelName in ipairs({ "PriceLabel", "RobuxLabel" }) do
						local priceLabel = billboardGui:FindFirstChild(labelName, true)
						if priceLabel and priceLabel:IsA("TextLabel") then
							priceLabel.Text = priceText
						end
					end
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
				if isEventKart then
					winsLabel.Text = string.format("%s Wins Required", tostring(math.round(winsRequired)))
					winsLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
					local winsGradient = winsLabel:FindFirstChildOfClass("UIGradient")
					if winsGradient then
						winsGradient.Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(130, 0, 0)),
						})
					end
				else
					winsLabel.Text = string.format("%s Wins Required", tostring(math.round(winsRequired)))
				end
			else
				winsLabel.Visible = false
			end
		end
	end

	local buttonPart = kartButton:FindFirstChild("Button") :: BasePart?
	if not buttonPart then
		DebugModule.debugWarn("KartButton " .. kartButton.Name .. " is missing Button part!", "WorldManager")
		return
	end
	if isEventKart then
		buttonPart.Color = Color3.fromRGB(255, 0, 0)
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

		local showcaseYawDegrees = if kartTemplate.Name == "AdvancedTank" then 0 else 90
		local showcaseOrientation = CFrame.Angles(0, math.rad(showcaseYawDegrees), 0)
		if isGamepassKart then
			showcaseOrientation *= CFrame.Angles(math.rad(GAMEPASS_KART_SHOWCASE_TILT_DEGREES), 0, 0)
		end

		local showcasePivot = getCenteredPivot(showcasePart.CFrame * showcaseOrientation, showcaseModel)
		showcaseModel:PivotTo(showcasePivot)
		showcaseModel:SetAttribute("ShowcaseBasePivot", showcasePivot)
		showcaseModel:SetAttribute("IsPoliceKart", kartTemplate.Name == "5_Police")
		showcaseModel:SetAttribute("VisualOffset", math.random())
		if isGamepassKart or isProductKart then
			local highlightColor = if eventName == "Bloodmoon"
				then BRIGHTEST_RED_HIGHLIGHT_COLOR
				else GAMEPASS_KART_SHOWCASE_HIGHLIGHT_COLORS[kartTemplate.Name] or buttonPart.Color
			addKartShowcaseHighlight(showcaseModel, highlightColor)
		end
		showcaseModel.Parent = kartButton
	end

	local buttonDebounceKey = "KartButton:" .. kartButton:GetFullName()

	worldMaid:GiveTask(buttonPart.Touched:Connect(function(hit)
		local player = ValidationService.GetAlivePlayerFromTouch(hit)
		if not player then
			return
		end

		if not ValidationService.ValidateWorldAccess(player, worldName) then
			return
		end
		if not ValidationService.ValidateRewardEligibility(player, "KartButton") then
			return
		end

		if not consumeTouchInteractionDebounce(player, buttonDebounceKey, DEBOUNCE_TIME) then
			return
		end

		local alreadyOwned = PlayerHandler.OwnsKart(player, kartTemplate.Name)
		if
			(isEventKart or isProductKart and not alreadyOwned)
			and (eventName == nil or not isLiveEventActive(eventName))
		then
			ShowNotification:FireClient(player, "EVENT NOT ACTIVE!", "Red")
			return
		end

		local kartFunnelSession = openKartFunnel(player, kartTemplate.Name, "PhysicalButton", "Kart Button Touched")
		if isEventKart then
			local currentBloodmoonWins = readNumericAttribute(player, "BloodmoonWins") or 0
			if not alreadyOwned and (winsRequired == nil or currentBloodmoonWins < winsRequired) then
				logKartFunnelStep(
					player,
					kartFunnelSession,
					kartTemplate.Name,
					"PhysicalButton",
					2,
					"Event Kart Not Affordable"
				)
				ShowNotification:FireClient(player, "NOT ENOUGH BLOODMOON WINS!", "Red")
				return
			end
		elseif isGamepassKart then
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
				PurchasePrompt:FireClient(player, "GamePass", gamePassId)
				return
			end
		elseif isProductKart then
			local productId = if productKey then ProductService.DevProducts[productKey] else nil
			if typeof(productId) ~= "number" or productId <= 0 then
				logKartFunnelStep(
					player,
					kartFunnelSession,
					kartTemplate.Name,
					"PhysicalButton",
					2,
					"Product Prompt Failed"
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
					"Product Prompt Requested"
				)
				PurchasePrompt:FireClient(player, "Product", productId)
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
			if isEventKart or isGamepassKart then
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

		if not equipKartForPlayer(player, kartTemplate.Name) then
			logKartFunnelStep(
				player,
				kartFunnelSession,
				kartTemplate.Name,
				"PhysicalButton",
				if alreadyOwned then 2 else 3,
				"Kart Equip Save Failed"
			)
			ShowNotification:FireClient(player, "KART EQUIP FAILED!", "Red")
			return
		end
		logKartFunnelStep(
			player,
			kartFunnelSession,
			kartTemplate.Name,
			"PhysicalButton",
			if alreadyOwned then 2 else 3,
			"Kart Equipped"
		)
	end))
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

	worldMaid:GiveTask(triggerPart.Touched:Connect(function(hit)
		local player = ValidationService.GetAlivePlayerFromTouch(hit)
		if not player then
			return
		end

		if not ValidationService.ValidateWorldAccess(player, worldName) then
			return
		end
		if not ValidationService.ValidateRewardEligibility(player, "StageProgress") then
			return
		end

		local currentStage = player:GetAttribute("CurrentStage")
		if typeof(currentStage) ~= "number" or stageValue > currentStage then
			player:SetAttribute("CurrentStage", stageValue)
		end
	end))
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
		if not ValidationService.ValidateRewardEligibility(player, "WinButton") then
			return
		end

		-- 4. Reward & Teleport
		local rewardedAmount = PlayerHandler.AddWinButtonWins(player, winAmount)
		EconomyAnalytics.LogSource(
			player,
			"Wins",
			rewardedAmount,
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			"WinButton",
			{ customField01 = worldName, customField02 = tostring(requiredStage) }
		)

		local finalStage = worldFinalStages[worldName]
		local didUnlockBloodmoonReward = false
		if isBloodmoonActive() and typeof(finalStage) == "number" and requiredStage >= finalStage then
			local bloodmoonWins, unlockedRewards = PlayerHandler.AddBloodmoonWin(player)
			if bloodmoonWins > 0 then
				EconomyAnalytics.LogSource(
					player,
					"BloodmoonWins",
					bloodmoonWins,
					Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
					"BloodmoonFinalStage",
					{ customField01 = worldName, customField02 = tostring(requiredStage) }
				)
				local bloodmoonWinRemote = BloodmoonWinAwarded
				if bloodmoonWinRemote then
					bloodmoonWinRemote:FireClient(player, bloodmoonWins)
				end
			end

			if #unlockedRewards > 0 then
				didUnlockBloodmoonReward = true
				local unlockedNames = {}
				for _, rewardId in ipairs(unlockedRewards) do
					local rewardConfig = PlayerHandler.GetTrailConfig(rewardId)
					local displayName = if rewardConfig
						then rewardConfig.DisplayName
						else PlayerHandler.GetBloodmoonUnlockDisplayName(rewardId)
					table.insert(
						unlockedNames,
						string.upper(displayName or rewardId)
					)
				end
				ShowNotification:FireClient(
					player,
					"BLOOD MOON REWARD UNLOCKED: " .. table.concat(unlockedNames, ", ") .. "!",
					"Red"
				)
			end
		end

		player:SetAttribute("CurrentStage", 0)
		resetTreadmillModifiers(player)

		if didUnlockBloodmoonReward then
			local saved = ProductServerService.SavePlayerData(player, true)
			if saved then
				DebugModule.debugInfo(
					"Bloodmoon unlock saved immediately | player=" .. player.Name,
					"WorldManager"
				)
			else
				DebugModule.debugWarn(
					"Bloodmoon unlock save failed | player=" .. player.Name,
					"WorldManager"
				)
			end
		end

		-- Teleport player to: world's SpawnLocation
		local worldsFolder = Workspace:FindFirstChild("Worlds")
		if worldsFolder then
			local worldFolder = worldsFolder:FindFirstChild(worldName)
			if worldFolder then
				local spawnLoc = worldFolder:FindFirstChild("SpawnLocation") :: BasePart?
				if spawnLoc and player.Character then
					player.Character:PivotTo(spawnLoc:GetPivot() * CFrame.new(0, 3, 0))
					ValidationService.MarkServerTeleport(player)
				end
			end
		end

		-- 5. Signal Client for Floating Text
		WinButtonPressed:FireClient(player, rewardedAmount, "WinButton")
	end

	if buttonPart then
		worldMaid:GiveTask(buttonPart.Touched:Connect(function(hit)
			local player = ValidationService.GetAlivePlayerFromTouch(hit)
			if player then
				onTrigger(player)
			end
		end))
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
	worldMaid:GiveTask(triggerPart.Touched:Connect(function(hit)
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
	end))
end

local function setupGroupChest(groupChest: Instance, worldName: string)
	local rewardTouchPart = groupChest:FindFirstChild("RewardTouchPart", true)
	if not rewardTouchPart or not rewardTouchPart:IsA("BasePart") then
		DebugModule.debugWarn("GroupChest " .. groupChest.Name .. " is missing RewardTouchPart!", "WorldManager")
		return
	end

	worldMaid:GiveTask(rewardTouchPart.Touched:Connect(function(hit)
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
	end))
end

local function setupVIPDoor(vipDoor: BasePart)
	worldMaid:GiveTask(vipDoor.Touched:Connect(function(hit)
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
	end))
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
		local finalStage = 0
		if stagesFolder then
			for _, stageInstance in ipairs(stagesFolder:GetChildren()) do
				local stageValue = stageInstance:GetAttribute("Stage")
				if typeof(stageValue) == "number" then
					finalStage = math.max(finalStage, math.floor(stageValue))
				end
				setupStagePart(stageInstance, world.Name)
			end
		end
		worldFinalStages[world.Name] = finalStage

		if world.Name == "World1" then
			local terrain = world:FindFirstChild("Terrain")
			local invisStuff = terrain and terrain:FindFirstChild("InvisStuff")
			if invisStuff then
				for _, barrierName in ipairs({ "InvisEnd", "InvisEnd2" }) do
					local barrierInstance = invisStuff:FindFirstChild(barrierName, true)
					local barrierPart = if barrierInstance and barrierInstance:IsA("BasePart")
						then barrierInstance
						else barrierInstance and barrierInstance:FindFirstChildWhichIsA("BasePart", true)
					if barrierPart then
						setupInvisEndTeleport(barrierPart, world.Name)
					else
						DebugModule.debugWarn(
							barrierName .. " is missing a trigger BasePart in World1.Terrain.InvisStuff",
							"WorldManager"
						)
					end
				end
			else
				DebugModule.debugWarn("World1.Terrain.InvisStuff is missing", "WorldManager")
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

		local eventKartButtonsFolder = world:FindFirstChild("EventKartButtons")
		if eventKartButtonsFolder then
			for _, kartButton in ipairs(eventKartButtonsFolder:GetChildren()) do
				setupKartButton(kartButton, world.Name)
			end
		end

		local decorations = world:FindFirstChild("Decorations")
		local eventKartShop = decorations and decorations:FindFirstChild("EventKartShop")
		local eventBlock = eventKartShop and eventKartShop:FindFirstChild("EventBlock")
		if eventBlock then
			setupEventBlock(eventBlock)
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
	invisEndTeleportDebounce[player] = nil
	ValidationService.CleanupPlayer(player)
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

	if not equipKartForPlayer(player, kartName) then
		logKartFunnelStep(player, kartFunnelSession, kartName, "UI", 2, "Kart Equip Save Failed")
		ShowNotification:FireClient(player, "KART EQUIP FAILED!", "Red")
		return
	end
	logKartFunnelStep(player, kartFunnelSession, kartName, "UI", 2, "Kart Equipped")
end)

local activeTreadmillUpdateElapsed = 0
local treadmillScanElapsed = 0

activeMaid.Heartbeat = RunService.Heartbeat:Connect(function(dt)
	ValidationService.ObservePlayerPositions()
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
				if not ValidationService.ValidateRewardEligibility(player, "TreadmillXP") then
					resetTreadmillModifiers(player)
					continue
				end
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

-- Cleanup on script removal (Rule #3.21). AncestryChanged covers reloads where
-- Destroying is not delivered reliably.
local function cleanupWorldManager()
	if worldManagerCleanedUp then
		return
	end

	worldManagerCleanedUp = true
	scriptAlive = false
	worldMaid:DoCleaning()
	activeMaid:DoCleaning()
	for _, player in ipairs(Players:GetPlayers()) do
		local maid = playerBindingMaids[player]
		if maid then
			maid:DoCleaning()
		end
	end
end

script.Destroying:Connect(cleanupWorldManager)
script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanupWorldManager()
	end
end)

DebugModule.debugPrint("WorldManager initialized", "WorldManager")
