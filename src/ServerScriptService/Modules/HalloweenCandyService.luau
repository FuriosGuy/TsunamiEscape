--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local Maid = require(ReplicatedStorage.Modules:WaitForChild("Maid"))
local CoreConfig = require(ReplicatedStorage.Modules.Shared:WaitForChild("CoreConfig_Shared"))
local HalloweenCandyShopConfig = require(ReplicatedStorage.Modules.Shared:WaitForChild("HalloweenCandyShopConfig"))
local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))
local ValidationService = require(ServerScriptService.Modules:WaitForChild("ValidationService"))

local HalloweenCandyService = {}

local MODULE_NAME = "HalloweenCandyService"
local CANDY_COUNT_ATTRIBUTE = "HalloweenCandyCount"
local CANDY_COLLECTED_ATTRIBUTE = "HalloweenCandyCollected"
local CANDY_STATE_ATTRIBUTE = "HalloweenCandyState"
local CANDY_BOOST = HalloweenCandyShopConfig.CandyBoost
local MODULE_CONFIG = CoreConfig.halloweenCandies
assert(typeof(MODULE_CONFIG) == "table", "CoreConfig_Shared.halloweenCandies is required")

type CandyConfig = { [string]: any }
type RoadDefinition = {
	stage: number,
	part: BasePart,
	covers: { BasePart },
	weight: number,
}
type CandySlot = {
	position: Vector3,
	stage: number,
	roadIndex: number,
}
type CandyPlayerState = {
	activeIds: { [number]: boolean },
	seed: number,
	nextRefillUnix: number,
	enabled: boolean,
	generation: number,
	refillThread: thread?,
}
type RequestTimes = {
	lastSyncAt: number,
	lastCollectAt: number,
}
type SpatialCells = { [string]: { Vector3 } }

local config = MODULE_CONFIG :: CandyConfig

local function readInteger(key: string, fallback: number, minimum: number, maximum: number): number
	local value = config[key]
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(math.floor(value), minimum, maximum)
end

local function readPositiveNumber(key: string, fallback: number, minimum: number, maximum: number): number
	local value = config[key]
	if typeof(value) ~= "number" or value ~= value then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local MAX_ACTIVE_PER_PLAYER = readInteger("maxActivePerPlayer", 100, 1, 500)
local REFILL_AMOUNT = readInteger("refillAmount", 25, 1, MAX_ACTIVE_PER_PLAYER)
local REFILL_INTERVAL_SECONDS = readInteger("refillIntervalSeconds", 180, 30, 86400)
local SPAWN_SLOT_COUNT = readInteger("spawnSlotCount", 640, MAX_ACTIVE_PER_PLAYER, 2000)
local MINIMUM_SLOTS_PER_ROAD = readInteger("minimumSlotsPerRoad", 2, 1, 32)
local MAXIMUM_SPAWN_ATTEMPTS_PER_SLOT = readInteger("maximumSpawnAttemptsPerSlot", 32, 1, 128)
local MINIMUM_SPAWN_SPACING = readPositiveNumber("minimumSpawnSpacing", 14, 4, 64)
local ROAD_EDGE_MARGIN = readPositiveNumber("roadEdgeMarginStuds", 10, 1, 32)
local ROAD_END_MARGIN = readPositiveNumber("roadEndMarginStuds", 12, 1, 64)
local SERVER_COLLECT_DISTANCE = readPositiveNumber("serverCollectDistanceStuds", 12, 4, 30)
local SERVER_COLLECT_REQUEST_COOLDOWN = readPositiveNumber("serverCollectRequestCooldownSeconds", 0.05, 0.03, 2)
local REFILL_SEED = readInteger("refillSeed", 20261011, 1, 2147483646)

local serviceMaid: any = Maid.new()
local playerMaids: { [Player]: any } = {}
local playerStates: { [Player]: CandyPlayerState } = {}
local playerRequestTimes: { [Player]: RequestTimes } = {}
local spawnSlots: { CandySlot } = {}
local candyModelNames: { string } = {}
local actionRemote: RemoteEvent? = nil
local updateRemote: RemoteEvent? = nil
local stateFolder: Folder? = nil
local initialized = false
local eventActive = false
local catalogReady = false

local function normalizeSeed(value: number): number
	return math.floor(math.abs(value)) % 2147483646 + 1
end

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getOrCreateRemote(name: string): RemoteEvent
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	assert(remotes and remotes:IsA("Folder"), "ReplicatedStorage.Remotes must be a Folder")

	local existing = remotes:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), "ReplicatedStorage.Remotes." .. name .. " must be a RemoteEvent")
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local function getRoadDefinitions(): { RoadDefinition }
	local worlds = Workspace:FindFirstChild("Worlds")
	local world1 = worlds and worlds:FindFirstChild("World1")
	local roadsFolder = world1 and world1:FindFirstChild("Roads")
	if not roadsFolder then
		return {}
	end

	local definitions: { RoadDefinition } = {}
	for _, roadModel in ipairs(roadsFolder:GetChildren()) do
		local stage = tonumber(string.match(roadModel.Name, "^Road (%d+)$"))
		local roadPart = roadModel:FindFirstChild("Road")
		if stage and roadPart and roadPart:IsA("BasePart") then
			local covers: { BasePart } = {}
			local cover = roadModel:FindFirstChild("TsunamiCover")
			if cover and cover:IsA("BasePart") then
				table.insert(covers, cover)
			end
			table.insert(definitions, {
				stage = stage,
				part = roadPart,
				covers = covers,
				weight = 0,
			})
		end
	end

	table.sort(definitions, function(left: RoadDefinition, right: RoadDefinition): boolean
		return left.stage < right.stage
	end)
	return definitions
end

local function getCellKey(x: number, y: number, z: number): string
	return string.format("%d:%d:%d", x, y, z)
end

local function isFarEnough(position: Vector3, cells: SpatialCells): boolean
	local cellX = math.floor(position.X / MINIMUM_SPAWN_SPACING)
	local cellY = math.floor(position.Y / MINIMUM_SPAWN_SPACING)
	local cellZ = math.floor(position.Z / MINIMUM_SPAWN_SPACING)
	local minimumDistanceSquared = MINIMUM_SPAWN_SPACING * MINIMUM_SPAWN_SPACING

	for xOffset = -1, 1 do
		for yOffset = -1, 1 do
			for zOffset = -1, 1 do
				local nearby = cells[getCellKey(cellX + xOffset, cellY + yOffset, cellZ + zOffset)]
				if nearby then
					for _, otherPosition in ipairs(nearby) do
						local offset = position - otherPosition
					if offset:Dot(offset) < minimumDistanceSquared then
						return false
					end
					end
				end
			end
		end
	end
	return true
end

local function addToSpatialCells(position: Vector3, cells: SpatialCells)
	local cellX = math.floor(position.X / MINIMUM_SPAWN_SPACING)
	local cellY = math.floor(position.Y / MINIMUM_SPAWN_SPACING)
	local cellZ = math.floor(position.Z / MINIMUM_SPAWN_SPACING)
	local key = getCellKey(cellX, cellY, cellZ)
	local cell = cells[key]
	if not cell then
		cell = {}
		cells[key] = cell
	end
	table.insert(cell, position)
end

local function isInsideCover(position: Vector3, covers: { BasePart }): boolean
	for _, cover in ipairs(covers) do
		local localPosition = cover.CFrame:PointToObjectSpace(position)
		if math.abs(localPosition.X) <= cover.Size.X / 2 + 1
			and math.abs(localPosition.Z) <= cover.Size.Z / 2 + 1
		then
			return true
		end
	end
	return false
end

local function sampleRoadPosition(road: RoadDefinition, random: Random): Vector3?
	local halfWidth = road.part.Size.X / 2 - ROAD_EDGE_MARGIN
	local halfLength = road.part.Size.Z / 2 - ROAD_END_MARGIN
	if halfWidth <= 0 or halfLength <= 0 then
		return nil
	end

	local localPosition = Vector3.new(
		random:NextNumber(-halfWidth, halfWidth),
		road.part.Size.Y / 2 + 0.05,
		random:NextNumber(-halfLength, halfLength)
	)
	local worldPosition = road.part.CFrame:PointToWorldSpace(localPosition)
	if isInsideCover(worldPosition, road.covers) then
		return nil
	end
	return worldPosition
end

local function chooseWeightedRoad(roads: { RoadDefinition }, totalWeight: number, random: Random): (RoadDefinition, number)
	local pick = random:NextNumber(0, totalWeight)
	for roadIndex, road in ipairs(roads) do
		pick -= road.weight
		if pick <= 0 then
			return road, roadIndex
		end
	end
	return roads[#roads], #roads
end

local function buildSpawnCatalog(): boolean
	if catalogReady then
		return #spawnSlots >= MAX_ACTIVE_PER_PLAYER
	end

	local roads = getRoadDefinitions()
	if #roads == 0 then
		DebugModule.debugWarn("World1 road parts were not found; candy spawning disabled", MODULE_NAME)
		return false
	end

	local eventDecorations = ReplicatedStorage:FindFirstChild("EventDecorations")
	local candyModels = eventDecorations and eventDecorations:FindFirstChild("CandyModels")
	if not candyModels then
		DebugModule.debugWarn("ReplicatedStorage.EventDecorations.CandyModels was not found", MODULE_NAME)
		return false
	end

	candyModelNames = {}
	for _, child in ipairs(candyModels:GetChildren()) do
		if child:IsA("MeshPart") then
			table.insert(candyModelNames, child.Name)
		end
	end
	table.sort(candyModelNames)
	if #candyModelNames == 0 then
		DebugModule.debugWarn("CandyModels has no MeshPart templates", MODULE_NAME)
		return false
	end

	local highestStage = roads[#roads].stage
	local totalWeight = 0
	for _, road in ipairs(roads) do
		local usableWidth = math.max(0, road.part.Size.X - ROAD_EDGE_MARGIN * 2)
		local usableLength = math.max(0, road.part.Size.Z - ROAD_END_MARGIN * 2)
		local stageProgress = road.stage / highestStage
		local stageWeight = 0.15 + 0.85 * stageProgress ^ 1.5
		road.weight = usableWidth * usableLength * stageWeight
		totalWeight += road.weight
	end

	local random = Random.new(REFILL_SEED)
	local cells: SpatialCells = {}
	spawnSlots = {}

	local function tryAddSlot(road: RoadDefinition, roadIndex: number): boolean
		for _ = 1, MAXIMUM_SPAWN_ATTEMPTS_PER_SLOT do
			local position = sampleRoadPosition(road, random)
			if position and isFarEnough(position, cells) then
				table.insert(spawnSlots, { position = position, stage = road.stage, roadIndex = roadIndex })
				addToSpatialCells(position, cells)
				return true
			end
		end
		return false
	end

	for roadIndex, road in ipairs(roads) do
		for _ = 1, MINIMUM_SLOTS_PER_ROAD do
			if #spawnSlots >= SPAWN_SLOT_COUNT then
				break
			end
			tryAddSlot(road, roadIndex)
		end
	end

	local maximumAttempts = SPAWN_SLOT_COUNT * MAXIMUM_SPAWN_ATTEMPTS_PER_SLOT
	local attempts = 0
	while #spawnSlots < SPAWN_SLOT_COUNT and attempts < maximumAttempts do
		attempts += 1
		local road, roadIndex = chooseWeightedRoad(roads, totalWeight, random)
		tryAddSlot(road, roadIndex)
	end

	catalogReady = true
	if #spawnSlots < MAX_ACTIVE_PER_PLAYER then
		DebugModule.debugWarn(
			string.format("Only %d safe candy spawn slots found; need at least %d", #spawnSlots, MAX_ACTIVE_PER_PLAYER),
			MODULE_NAME
		)
		return false
	end

	DebugModule.debugPrint(
		string.format("Built %d road candy slots across %d stages", #spawnSlots, #roads),
		MODULE_NAME
	)
	return true
end

local function countActive(state: CandyPlayerState): number
	local count = 0
	for _ in pairs(state.activeIds) do
		count += 1
	end
	return count
end

local function selectAvailableIds(
	targetCount: number,
	random: Random,
	excludedIds: { [number]: boolean }?
): { number }
	local availableIds: { number } = {}
	for id = 1, #spawnSlots do
		if not excludedIds or not excludedIds[id] then
			table.insert(availableIds, id)
		end
	end
	for index = #availableIds, 2, -1 do
		local swapIndex = random:NextInteger(1, index)
		availableIds[index], availableIds[swapIndex] = availableIds[swapIndex], availableIds[index]
	end
	local selectedIds: { number } = {}
	for index = 1, math.min(targetCount, #availableIds) do
		table.insert(selectedIds, availableIds[index])
	end
	return selectedIds
end

local function selectSpawnIdSet(targetCount: number, random: Random): { [number]: boolean }
	local selected: { [number]: boolean } = {}
	for _, id in ipairs(selectAvailableIds(targetCount, random)) do
		selected[id] = true
	end
	return selected
end

local function selectRefillIds(state: CandyPlayerState, targetCount: number, random: Random): { number }
	return selectAvailableIds(targetCount, random, state.activeIds)
end

local function serializeState(player: Player, state: CandyPlayerState)
	local ids: { number } = {}
	for id in pairs(state.activeIds) do
		table.insert(ids, id)
	end
	table.sort(ids)

	local success, encoded = pcall(function(): string
		return HttpService:JSONEncode({
			version = 3,
			seed = state.seed,
			nextRefillUnix = state.nextRefillUnix,
			activeIds = ids,
		})
	end)
	if success and typeof(encoded) == "string" then
		player:SetAttribute(CANDY_STATE_ATTRIBUTE, encoded)
	else
		DebugModule.debugWarn("Could not serialize candy state | player=" .. player.Name, MODULE_NAME)
	end
end

local function makeInitialState(player: Player): CandyPlayerState
	local seed = normalizeSeed(player.UserId + REFILL_SEED)
	local activeIds = selectSpawnIdSet(math.min(MAX_ACTIVE_PER_PLAYER, #spawnSlots), Random.new(seed))

	local state: CandyPlayerState = {
		activeIds = activeIds,
		seed = seed,
		nextRefillUnix = DateTime.now().UnixTimestamp + REFILL_INTERVAL_SECONDS,
		enabled = false,
		generation = 0,
		refillThread = nil,
	}
	serializeState(player, state)
	return state
end

local function decodeSavedState(player: Player): CandyPlayerState?
	local encoded = player:GetAttribute(CANDY_STATE_ATTRIBUTE)
	if typeof(encoded) ~= "string" or encoded == "" or encoded == "{}" then
		return nil
	end

	local success, decodedValue = pcall(function(): any
		return HttpService:JSONDecode(encoded)
	end)
	if not success or typeof(decodedValue) ~= "table" then
		DebugModule.debugWarn("Invalid saved candy state; reinitializing | player=" .. player.Name, MODULE_NAME)
		return nil
	end

	local decoded = decodedValue :: { [string]: any }
	local now = DateTime.now().UnixTimestamp
	if (decoded.version ~= 1 and decoded.version ~= 2 and decoded.version ~= 3)
		or not isFiniteNumber(decoded.seed)
		or not isFiniteNumber(decoded.nextRefillUnix)
		or typeof(decoded.activeIds) ~= "table"
	then
		DebugModule.debugWarn("Unsupported saved candy state; reinitializing | player=" .. player.Name, MODULE_NAME)
		return nil
	end

	local nextRefillUnix = math.floor(decoded.nextRefillUnix)
	if nextRefillUnix <= 0 or nextRefillUnix > now + REFILL_INTERVAL_SECONDS * 2 then
		nextRefillUnix = now + REFILL_INTERVAL_SECONDS
	end

	local activeIds: { [number]: boolean } = {}
	local activeCount = 0
	for _, rawId in ipairs(decoded.activeIds) do
		if typeof(rawId) == "number" and rawId == math.floor(rawId) and rawId >= 1 and rawId <= #spawnSlots then
			if not activeIds[rawId] then
				activeIds[rawId] = true
				activeCount += 1
				if activeCount >= MAX_ACTIVE_PER_PLAYER then
					break
				end
			end
		end
	end

	local state: CandyPlayerState = {
		activeIds = activeIds,
		seed = normalizeSeed(decoded.seed),
		nextRefillUnix = nextRefillUnix,
		enabled = false,
		generation = 0,
		refillThread = nil,
	}
	if decoded.version < 3 then
		state.activeIds = selectSpawnIdSet(activeCount, Random.new(state.seed))
		serializeState(player, state)
	end
	return state
end

local function getOrCreatePlayerState(player: Player): CandyPlayerState
	local current = playerStates[player]
	if current then
		return current
	end

	local state = decodeSavedState(player) or makeInitialState(player)
	playerStates[player] = state
	return state
end

local function makeCandyEntry(id: number): { [string]: any }?
	local slot = spawnSlots[id]
	if not slot or #candyModelNames == 0 then
		return nil
	end
	local modelIndex = ((id - 1) % #candyModelNames) + 1
	return {
		id = id,
		position = slot.position,
		modelName = candyModelNames[modelIndex],
	}
end

local function makeEntries(state: CandyPlayerState): { { [string]: any } }
	local ids: { number } = {}
	for id in pairs(state.activeIds) do
		table.insert(ids, id)
	end
	table.sort(ids)

	local entries: { { [string]: any } } = {}
	for _, id in ipairs(ids) do
		local entry = makeCandyEntry(id)
		if entry then
			table.insert(entries, entry)
		end
	end
	return entries
end

local function sendUpdate(player: Player, action: string, payload: any?)
	local remote = updateRemote
	if remote and player.Parent == Players then
		remote:FireClient(player, action, payload)
	end
end

local function sendSnapshot(player: Player, state: CandyPlayerState)
	sendUpdate(player, "Snapshot", { entries = makeEntries(state) })
end

local function cancelRefill(state: CandyPlayerState)
	local thread = state.refillThread
	state.refillThread = nil
	if thread and coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
	end
end

local function applyDueRefills(player: Player, state: CandyPlayerState): { { [string]: any } }
	local now = DateTime.now().UnixTimestamp
	if now < state.nextRefillUnix then
		return {}
	end

	local intervalsDue = math.floor((now - state.nextRefillUnix) / REFILL_INTERVAL_SECONDS) + 1
	local refillCycle = math.floor(state.nextRefillUnix / REFILL_INTERVAL_SECONDS)
	state.nextRefillUnix += intervalsDue * REFILL_INTERVAL_SECONDS

	local missingCount = math.max(0, MAX_ACTIVE_PER_PLAYER - countActive(state))
	local amountToAdd = if intervalsDue >= math.ceil(missingCount / REFILL_AMOUNT)
		then missingCount
		else math.min(missingCount, intervalsDue * REFILL_AMOUNT)
	local random = Random.new(normalizeSeed(state.seed + refillCycle))
	local addedEntries: { { [string]: any } } = {}
	for _, id in ipairs(selectRefillIds(state, amountToAdd, random)) do
		state.activeIds[id] = true
		local entry = makeCandyEntry(id)
		if entry then
			table.insert(addedEntries, entry)
		end
	end

	serializeState(player, state)
	return addedEntries
end

local function scheduleRefill(player: Player, state: CandyPlayerState)
	cancelRefill(state)
	if not state.enabled or player.Parent ~= Players or countActive(state) >= MAX_ACTIVE_PER_PLAYER then
		return
	end

	local generation = state.generation
	local delaySeconds = math.max(0, state.nextRefillUnix - DateTime.now().UnixTimestamp)
	state.refillThread = task.delay(delaySeconds, function()
		state.refillThread = nil
		if not initialized
			or not eventActive
			or player.Parent ~= Players
			or playerStates[player] ~= state
			or not state.enabled
			or state.generation ~= generation
		then
			return
		end

		local addedEntries = applyDueRefills(player, state)
		if #addedEntries > 0 then
			sendUpdate(player, "Add", addedEntries)
		end
		scheduleRefill(player, state)
	end)
end

local function synchronizePlayer(player: Player)
	if not eventActive
		or not initialized
		or player.Parent ~= Players
		or player:GetAttribute("Data_Loaded") ~= true
		or not buildSpawnCatalog()
	then
		return
	end

	local state = getOrCreatePlayerState(player)
	state.enabled = true
	state.generation += 1
	cancelRefill(state)
	applyDueRefills(player, state)
	sendSnapshot(player, state)
	scheduleRefill(player, state)
end

local function disablePlayer(player: Player, shouldNotify: boolean)
	local state = playerStates[player]
	if state then
		state.enabled = false
		state.generation += 1
		cancelRefill(state)
	end
	if shouldNotify then
		sendUpdate(player, "Disabled", nil)
	end
end

local function setEventActive(isActive: boolean)
	if isActive and config.enabled ~= true then
		isActive = false
	end
	if isActive == eventActive then
		return
	end
	if isActive and not buildSpawnCatalog() then
		return
	end

	eventActive = isActive
	for _, player in ipairs(Players:GetPlayers()) do
		if isActive then
			synchronizePlayer(player)
		else
			disablePlayer(player, true)
		end
	end
end

local function readEventActive(folder: Folder): boolean
	return folder:GetAttribute("HalloweenPartTwoActive") == true
end

local function bindStateFolder(instance: Instance)
	if not instance:IsA("Folder") or instance.Name ~= "LiveEventState" or stateFolder == instance then
		return
	end

	stateFolder = instance
	serviceMaid.EnvironmentName = instance:GetAttributeChangedSignal("EnvironmentName"):Connect(function()
		setEventActive(readEventActive(instance))
	end)
	serviceMaid.HalloweenPartTwoActive = instance:GetAttributeChangedSignal("HalloweenPartTwoActive"):Connect(function()
		setEventActive(readEventActive(instance))
	end)
	serviceMaid.StateFolderAncestry = instance.AncestryChanged:Connect(function(_, parent)
		if parent == nil and stateFolder == instance then
			stateFolder = nil
			serviceMaid.EnvironmentName = nil
			serviceMaid.HalloweenPartTwoActive = nil
			setEventActive(false)
		end
	end)
	setEventActive(readEventActive(instance))
end

local function onPlayerReadinessChanged(player: Player)
	if player.Parent ~= Players then
		return
	end
	if eventActive and player:GetAttribute("Data_Loaded") == true then
		synchronizePlayer(player)
	else
		disablePlayer(player, true)
	end
end

local function bindPlayer(player: Player)
	if playerMaids[player] then
		return
	end

	local playerMaid: any = Maid.new()
	playerMaids[player] = playerMaid
	playerMaid.DataLoaded = player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
		onPlayerReadinessChanged(player)
	end)
	onPlayerReadinessChanged(player)
end

local function cleanupPlayer(player: Player)
	disablePlayer(player, false)
	local playerMaid = playerMaids[player]
	playerMaids[player] = nil
	if playerMaid then
		playerMaid:DoCleaning()
	end
	playerStates[player] = nil
	playerRequestTimes[player] = nil
end

local function getPlayerRequestTimes(player: Player): RequestTimes
	local current = playerRequestTimes[player]
	if current then
		return current
	end
	local created: RequestTimes = {
		lastSyncAt = -math.huge,
		lastCollectAt = -math.huge,
	}
	playerRequestTimes[player] = created
	return created
end

local function isValidCandyId(value: any): boolean
	return typeof(value) == "number"
		and value == math.floor(value)
		and value >= 1
		and value <= #spawnSlots
		and value < math.huge
end

local function getCandyCount(player: Player): number
	local value = player:GetAttribute(CANDY_COUNT_ATTRIBUTE)
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function getCandyCollected(player: Player): number
	local value = player:GetAttribute(CANDY_COLLECTED_ATTRIBUTE)
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(0, math.floor(value))
end

function HalloweenCandyService.TrySpendCandy(player: Player, amount: number): boolean
	if
		not initialized
		or not eventActive
		or player.Parent ~= Players
		or player:GetAttribute("Data_Loaded") ~= true
		or not isFiniteNumber(amount)
		or amount <= 0
		or amount ~= math.floor(amount)
	then
		return false
	end

	local currentCount = getCandyCount(player)
	if currentCount < amount then
		return false
	end
	player:SetAttribute(CANDY_COUNT_ATTRIBUTE, currentCount - amount)
	return true
end

function HalloweenCandyService.RefundCandy(player: Player, amount: number): boolean
	if
		player.Parent ~= Players
		or player:GetAttribute("Data_Loaded") ~= true
		or not isFiniteNumber(amount)
		or amount <= 0
		or amount ~= math.floor(amount)
	then
		return false
	end

	player:SetAttribute(CANDY_COUNT_ATTRIBUTE, getCandyCount(player) + amount)
	return true
end

local function tryCollectCandy(player: Player, candyId: number, state: CandyPlayerState)
	if not eventActive or not state.enabled or not state.activeIds[candyId] then
		return
	end
	if player:GetAttribute("Data_Loaded") ~= true or player:GetAttribute("Current_World") ~= "World1" then
		sendUpdate(player, "Reject", candyId)
		return
	end
	if not ValidationService.ValidateRewardEligibility(player, "HalloweenCandy") then
		sendUpdate(player, "Reject", candyId)
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local slot = spawnSlots[candyId]
	if not rootPart or not rootPart:IsA("BasePart") or not slot then
		sendUpdate(player, "Reject", candyId)
		return
	end

	local candyCenter = slot.position + Vector3.new(0, 3, 0)
	if (rootPart.Position - candyCenter).Magnitude > SERVER_COLLECT_DISTANCE then
		sendUpdate(player, "Reject", candyId)
		return
	end

	state.activeIds[candyId] = nil
	serializeState(player, state)
	local boostEnd = player:GetAttribute(CANDY_BOOST.endAttributeName)
	local rewardAmount = if typeof(boostEnd) == "number" and boostEnd > os.time()
		then CANDY_BOOST.multiplier
		else 1
	player:SetAttribute(CANDY_COUNT_ATTRIBUTE, getCandyCount(player) + rewardAmount)
	player:SetAttribute(CANDY_COLLECTED_ATTRIBUTE, getCandyCollected(player) + rewardAmount)
	sendUpdate(player, "Remove", {
		id = candyId,
		rewardAmount = rewardAmount,
	})

	local addedEntries = applyDueRefills(player, state)
	if #addedEntries > 0 then
		sendUpdate(player, "Add", addedEntries)
	end
	scheduleRefill(player, state)
end

local function onAction(player: Player, action: any, value: any, ...: any)
	if player.Parent ~= Players or typeof(action) ~= "string" or select("#", ...) > 0 then
		return
	end

	local requestTimes = getPlayerRequestTimes(player)
	local now = os.clock()
	if action == "Sync" then
		if value ~= nil or now - requestTimes.lastSyncAt < 1 then
			return
		end
		requestTimes.lastSyncAt = now
		synchronizePlayer(player)
		return
	end

	if action ~= "Collect" or not isValidCandyId(value) then
		return
	end
	if now - requestTimes.lastCollectAt < SERVER_COLLECT_REQUEST_COOLDOWN then
		return
	end
	requestTimes.lastCollectAt = now

	local state = playerStates[player]
	if state then
		tryCollectCandy(player, value, state)
	else
		sendUpdate(player, "Reject", value)
	end
end

function HalloweenCandyService.Init()
	if initialized then
		return
	end
	initialized = true
	serviceMaid = Maid.new()
	actionRemote = getOrCreateRemote("HalloweenCandyAction")
	updateRemote = getOrCreateRemote("HalloweenCandyUpdate")
	serviceMaid.Action = actionRemote.OnServerEvent:Connect(onAction)
	serviceMaid.PlayerAdded = Players.PlayerAdded:Connect(bindPlayer)
	serviceMaid.PlayerRemoving = Players.PlayerRemoving:Connect(cleanupPlayer)
	serviceMaid.StateFolderAdded = ReplicatedStorage.ChildAdded:Connect(bindStateFolder)

	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	local existingStateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
	if existingStateFolder then
		bindStateFolder(existingStateFolder)
	end
	DebugModule.debugPrint("Halloween candy service initialized", MODULE_NAME)
end

function HalloweenCandyService.Destroy()
	if not initialized then
		return
	end
	initialized = false
	eventActive = false
	stateFolder = nil
	serviceMaid:DoCleaning()
	for player, playerMaid in pairs(playerMaids) do
		cleanupPlayer(player)
		if playerMaid then
			playerMaid:DoCleaning()
		end
	end
	table.clear(playerMaids)
	table.clear(playerStates)
	table.clear(playerRequestTimes)
	table.clear(spawnSlots)
	table.clear(candyModelNames)
	catalogReady = false
	actionRemote = nil
	updateRemote = nil
end

return HalloweenCandyService
