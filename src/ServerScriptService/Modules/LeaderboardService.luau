local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DebugModule = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("DebugModule"))
local Maid = require(Modules:WaitForChild("Maid"))
local NumberFormatting = require(Modules.Shared:WaitForChild("NumberFormatting"))
local SharedFolder = game:GetService("ServerScriptService").Modules:WaitForChild("Shared")
local CoreConfig = require(SharedFolder:WaitForChild("CoreConfig_Server"))
local DataStoreRequestGate = require(game:GetService("ServerScriptService").Modules:WaitForChild("DataStoreRequestGate"))

local LeaderboardService = {}

local leaderboardDebugConfig = CoreConfig.leaderboard
local persistenceConfig = CoreConfig.persistence
local DATASTORE_BUDGET_WAIT_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.datastoreBudgetWaitSeconds) == "number"
	then math.max(0.25, persistenceConfig.datastoreBudgetWaitSeconds)
	else 5
LeaderboardService.DEBUG_USE_FAKE_DATA = if leaderboardDebugConfig
		and typeof(leaderboardDebugConfig.debugUseFakeData) == "boolean"
	then RunService:IsStudio() and leaderboardDebugConfig.debugUseFakeData
	else false
LeaderboardService.DEBUG_APPEND_FAKE_DATA = if leaderboardDebugConfig
		and typeof(leaderboardDebugConfig.debugAppendFakeData) == "boolean"
	then RunService:IsStudio() and leaderboardDebugConfig.debugAppendFakeData
	else false

export type LeaderboardConfig = {
	Name: string,
	OrderedStoreName: string,
	LegacyOrderedStoreName: string?,
	AttributeName: string,
	BoardPath: { string },
	MaxEntries: number,
	RefreshInterval: number,
	WriteInterval: number,
}

type LeaderboardEntryData = {
	rank: number,
	userId: number,
	username: string,
	value: number,
	sortValue: number,
}

type OrderedStoreEntry = {
	key: string,
	value: any,
}

type OrderedStorePage = { OrderedStoreEntry }

type LeaderboardBoardCache = {
	scrollingFrame: ScrollingFrame,
	template: Frame,
	entryFrames: { Frame },
	lastSignature: string?,
}

local PLACE_COLORS: { [number]: Color3 } = {
	[1] = Color3.fromRGB(255, 183, 0),
	[2] = Color3.fromRGB(176, 176, 176),
	[3] = Color3.fromRGB(139, 99, 31),
}
local DEFAULT_PLACE_COLOR = Color3.fromRGB(0, 102, 255)
local EXACT_LUA_INTEGER_LIMIT = 9007199254740991
local SIGNIFICANT_DIGITS = 13
local SIGNIFICAND_LIMIT = 10 ^ SIGNIFICANT_DIGITS
local SIGNIFICAND_SCALE = 10 ^ (SIGNIFICANT_DIGITS - 1)
local MIN_SCORE_EXPONENT = -308
local MAX_SCORE_EXPONENT = 308
local MAX_EXPONENT_INDEX = MAX_SCORE_EXPONENT - MIN_SCORE_EXPONENT
assert(
	(MAX_EXPONENT_INDEX + 1) * SIGNIFICAND_LIMIT < EXACT_LUA_INTEGER_LIMIT,
	"Leaderboard score encoding must stay below Luau's exact integer limit"
)

LeaderboardService.Configs = {
	WinLeaderboard = {
		Name = "WinLeaderboard",
		OrderedStoreName = "WinLeaderboard_v2",
		LegacyOrderedStoreName = "WinLeaderboard_v1",
		AttributeName = "WinCount",
		BoardPath = { "Folder", "WinLeaderboard", "Leaderboard", "SurfaceGui", "ScrollingFrame" },
		MaxEntries = 100,
		RefreshInterval = 60,
		WriteInterval = 120,
	},
	SpeedLeaderboard = {
		Name = "SpeedLeaderboard",
		OrderedStoreName = "SpeedLeaderboard_v2",
		LegacyOrderedStoreName = "SpeedLeaderboard_v1",
		AttributeName = "AllXPSpeed",
		BoardPath = { "Folder", "SpeedLeaderboard", "Leaderboard", "SurfaceGui", "ScrollingFrame" },
		MaxEntries = 100,
		RefreshInterval = 60,
		WriteInterval = 120,
	},
}

local orderedStores: { [string]: OrderedDataStore } = {}
local lastPublishedValues: { [string]: { [number]: number } } = {}
local lastWriteTimes: { [string]: { [number]: number } } = {}
local pendingWriteValues: { [string]: { [number]: number } } = {}
local pendingWriteThreads: { [string]: { [number]: thread } } = {}
local forceWriteRequests: { [string]: { [number]: boolean } } = {}
local failedWriteValues: { [string]: { [number]: number } } = {}
local lastWriteFailureLogs: { [string]: { [number]: number } } = {}
local lastSuccessfulEntries: { [string]: { LeaderboardEntryData } } = {}
local boardCaches: { [string]: LeaderboardBoardCache } = {}
local playerBindingMaids: { [Player]: Maid } = {}
local serviceMaid = Maid.new()
local isInitialized = false
local isShuttingDown = false

local FORCED_WRITE_WAIT_TIMEOUT_SECONDS = 10
local WRITE_RETRY_INITIAL_SECONDS = 5
local WRITE_RETRY_MAX_SECONDS = 30
local WRITE_FAILURE_LOG_COOLDOWN_SECONDS = 30
local LEADERBOARD_REQUEST_QUEUE = "Leaderboard"
local ORDERED_WRITE_MIN_SPACING_SECONDS = 0.2
local lastOrderedWriteAt = 0

local function isRealLeaderboardUserId(userId: number): boolean
	return userId > 0
end

local function getOrderedStore(storeName: string): OrderedDataStore
	local cached = orderedStores[storeName]
	if cached then
		return cached
	end

	local store = DataStoreService:GetOrderedDataStore(storeName)
	orderedStores[storeName] = store
	return store
end

-- OrderedDataStore writes share one game-server budget. Serialize every write
-- so per-player workers cannot flood Roblox's ordered-write request queue.
local function setOrderedValue(config: LeaderboardConfig, userId: number, value: number): (boolean, any)
	local success, result = DataStoreRequestGate.Run(
		"OrderedWrite",
		"LeaderboardSetAsync",
		function()
			local remainingSpacing = ORDERED_WRITE_MIN_SPACING_SECONDS - (os.clock() - lastOrderedWriteAt)
			if remainingSpacing > 0 then
				task.wait(remainingSpacing)
			end
			lastOrderedWriteAt = os.clock()
			return getOrderedStore(config.OrderedStoreName):SetAsync(tostring(userId), value)
		end,
		{
			maxWaitSeconds = DATASTORE_BUDGET_WAIT_SECONDS,
			queueKey = LEADERBOARD_REQUEST_QUEUE,
		}
	)
	return success, result
end

local function getBoardScrollingFrame(path: { string }): ScrollingFrame?
	local worldsFolder = Workspace:FindFirstChild("Worlds")
	if not worldsFolder then
		return nil
	end

	for _, world in ipairs(worldsFolder:GetChildren()) do
		local current: Instance = world
		local found = true

		for _, segment in ipairs(path) do
			local nextInstance = current:FindFirstChild(segment)
			if not nextInstance then
				found = false
				break
			end
			current = nextInstance
		end

		if found and current:IsA("ScrollingFrame") then
			return current
		end
	end

	return nil
end

local function getBoardCache(config: LeaderboardConfig): LeaderboardBoardCache?
	local existingCache = boardCaches[config.Name]
	if existingCache then
		if existingCache.scrollingFrame.Parent and existingCache.template.Parent == existingCache.scrollingFrame then
			return existingCache
		end

		boardCaches[config.Name] = nil
	end

	local scrollingFrame = getBoardScrollingFrame(config.BoardPath)
	if not scrollingFrame then
		return nil
	end

	local template = scrollingFrame:FindFirstChild("PlaceFrame")
	if not template or not template:IsA("Frame") then
		return nil
	end

	local cache: LeaderboardBoardCache = {
		scrollingFrame = scrollingFrame,
		template = template,
		entryFrames = {},
		lastSignature = nil,
	}
	boardCaches[config.Name] = cache
	return cache
end

local function getPlaceColor(rank: number): Color3
	return PLACE_COLORS[rank] or DEFAULT_PLACE_COLOR
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

local function encodeLeaderboardValue(rawValue: number): number?
	if rawValue ~= rawValue then
		return nil
	end

	if rawValue == math.huge or rawValue == -math.huge then
		return nil
	end

	if rawValue <= 0 then
		return 0
	end

	local exponent = math.clamp(math.floor(math.log10(rawValue)), MIN_SCORE_EXPONENT, MAX_SCORE_EXPONENT)
	local normalizedValue = rawValue / (10 ^ exponent)
	local significand = math.floor(normalizedValue * SIGNIFICAND_SCALE + 0.5)

	if significand >= SIGNIFICAND_LIMIT then
		if exponent < MAX_SCORE_EXPONENT then
			exponent += 1
			significand = SIGNIFICAND_SCALE
		else
			significand = SIGNIFICAND_LIMIT - 1
		end
	elseif significand < SIGNIFICAND_SCALE then
		-- Scores below 1e-308 share the smallest representable leaderboard bucket.
		significand = SIGNIFICAND_SCALE
	end

	local exponentIndex = exponent - MIN_SCORE_EXPONENT
	local encodedValue = exponentIndex * SIGNIFICAND_LIMIT + significand
	if encodedValue > EXACT_LUA_INTEGER_LIMIT then
		return nil
	end

	return encodedValue
end


local function decodeLeaderboardValue(encodedValue: number): number?
	if encodedValue ~= encodedValue or encodedValue == math.huge or encodedValue == -math.huge then
		return nil
	end

	if encodedValue <= 0 then
		return 0
	end

	local integerValue = math.floor(encodedValue + 0.5)
	local exponentIndex = math.floor(integerValue / SIGNIFICAND_LIMIT)
	local significand = integerValue - exponentIndex * SIGNIFICAND_LIMIT
	if exponentIndex < 0 or exponentIndex > MAX_EXPONENT_INDEX then
		return nil
	end
	if significand < SIGNIFICAND_SCALE or significand >= SIGNIFICAND_LIMIT then
		return nil
	end

	local exponent = exponentIndex + MIN_SCORE_EXPONENT
	local decodedValue = (significand / SIGNIFICAND_SCALE) * (10 ^ exponent)
	if decodedValue == math.huge then
		return 1.7976931348623157e308
	end

	return decodedValue
end

local function clearPlayerBinding(player: Player)
	local maid = playerBindingMaids[player]
	if maid then
		maid:DoCleaning()
		playerBindingMaids[player] = nil
	end
end

local function clearPlayerWriteState(userId: number)
	for configName in pairs(LeaderboardService.Configs) do
		local configThreads = pendingWriteThreads[configName]
		if configThreads then
			-- Do not cancel a worker that could currently own the global write
			-- lock. Clearing its pending value lets it exit safely at its next
			-- bounded wait point.
			configThreads[userId] = nil
		end

		local configPendingValues = pendingWriteValues[configName]
		if configPendingValues then
			configPendingValues[userId] = nil
		end

		local configLastPublishedValues = lastPublishedValues[configName]
		if configLastPublishedValues then
			configLastPublishedValues[userId] = nil
		end

		local configLastWriteTimes = lastWriteTimes[configName]
		if configLastWriteTimes then
			configLastWriteTimes[userId] = nil
		end

		local configForceRequests = forceWriteRequests[configName]
		if configForceRequests then
			configForceRequests[userId] = nil
		end

		local configFailedValues = failedWriteValues[configName]
		if configFailedValues then
			configFailedValues[userId] = nil
		end

		local configFailureLogs = lastWriteFailureLogs[configName]
		if configFailureLogs then
			configFailureLogs[userId] = nil
		end
	end
end

local function ensureEntryFrame(cache: LeaderboardBoardCache, rank: number): Frame
	local existingFrame = cache.entryFrames[rank]
	if existingFrame and existingFrame.Parent == cache.scrollingFrame then
		return existingFrame
	end

	local clone = cache.template:Clone()
	clone.Parent = cache.scrollingFrame
	cache.entryFrames[rank] = clone
	return clone
end

local function buildEntriesSignature(entries: { LeaderboardEntryData }, maxEntries: number): string
	local parts = table.create(maxEntries)
	for rank = 1, maxEntries do
		local entry = entries[rank]
		if entry then
			parts[rank] = string.format(
				"%d:%d:%s:%.15g:%d",
				entry.rank,
				entry.userId,
				entry.username,
				entry.value,
				entry.sortValue
			)
		else
			parts[rank] = string.format("%d:0:No Data:0", rank)
		end
	end

	return table.concat(parts, "|")
end

local function setAvatarImage(imageObject: GuiObject, userId: number)
	if not (imageObject:IsA("ImageLabel") or imageObject:IsA("ImageButton")) then
		return
	end

	local nextRequestId = (imageObject:GetAttribute("LeaderboardAvatarRequestId") or 0) :: number
	nextRequestId += 1
	imageObject:SetAttribute("LeaderboardAvatarRequestId", nextRequestId)
	imageObject:SetAttribute("LeaderboardAvatarUserId", userId)
	imageObject.Image = ""

	task.spawn(function()
		local success, content = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)

		if not success then
			return
		end

		if not imageObject.Parent then
			return
		end

		local activeRequestId = imageObject:GetAttribute("LeaderboardAvatarRequestId")
		local activeUserId = imageObject:GetAttribute("LeaderboardAvatarUserId")
		if activeRequestId ~= nextRequestId or activeUserId ~= userId then
			return
		end

		imageObject.Image = content
	end)
end

local function populateEntry(entryFrame: Frame, rank: number, userId: number, username: string, value: number)
	entryFrame.Name = "Place_" .. tostring(rank)
	entryFrame.LayoutOrder = rank
	entryFrame.Visible = true
	entryFrame.BackgroundColor3 = getPlaceColor(rank)

	local avatarImage = entryFrame:FindFirstChild("Avatar Image", true)
		or entryFrame:FindFirstChild("AvatarImage", true)
	if avatarImage and (avatarImage:IsA("ImageLabel") or avatarImage:IsA("ImageButton")) then
		if userId > 0 then
			setAvatarImage(avatarImage, userId)
		else
			avatarImage.Image = ""
			avatarImage:SetAttribute(
				"LeaderboardAvatarRequestId",
				(avatarImage:GetAttribute("LeaderboardAvatarRequestId") or 0) + 1
			)
			avatarImage:SetAttribute("LeaderboardAvatarUserId", 0)
		end
	end

	local amountLabel = entryFrame:FindFirstChild("Amount", true)
	if amountLabel and amountLabel:IsA("TextLabel") then
		amountLabel.Text = NumberFormatting.FormatNumber(value)
	end

	local placeLabel = entryFrame:FindFirstChild("Place", true)
	if placeLabel and placeLabel:IsA("TextLabel") then
		placeLabel.Text = tostring(rank)
	end

	local playerLabel = entryFrame:FindFirstChild("PlayerLabel", true)
	if playerLabel and playerLabel:IsA("TextLabel") then
		playerLabel.Text = username
	end
end

local function renderLeaderboard(config: LeaderboardConfig, entries: { LeaderboardEntryData })
	local cache = getBoardCache(config)
	if not cache then
		DebugModule.debugWarn("Leaderboard scrolling frame missing for " .. config.Name, "LeaderboardService")
		return
	end

	local signature = buildEntriesSignature(entries, config.MaxEntries)
	if cache.lastSignature == signature then
		return
	end
	cache.lastSignature = signature

	cache.template.Visible = false

	for rank = 1, config.MaxEntries do
		local clone = ensureEntryFrame(cache, rank)
		local entry = entries[rank]
		if entry then
			populateEntry(clone, entry.rank, entry.userId, entry.username, entry.value)
		else
			populateEntry(clone, rank, 0, "No Data", 0)
		end
	end

	local layout = cache.scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if layout then
		task.defer(function()
			cache.scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
		end)
	end
end

local function fetchOrderedPage(config: LeaderboardConfig, storeName: string): (OrderedStorePage?, any?)
	local lastError: any = nil
	for attempt = 1, 3 do
		local success, pages = DataStoreRequestGate.Run(
			"OrderedList",
			"LeaderboardGetSortedAsync_" .. storeName,
			function()
				return getOrderedStore(storeName):GetSortedAsync(false, math.min(config.MaxEntries, 100))
			end,
			{
				maxWaitSeconds = DATASTORE_BUDGET_WAIT_SECONDS,
				queueKey = LEADERBOARD_REQUEST_QUEUE,
			}
		)
		if success and pages ~= nil then
			local pageSuccess, currentPage = pcall(function()
				return pages:GetCurrentPage()
			end)
			if pageSuccess and typeof(currentPage) == "table" then
				return currentPage :: OrderedStorePage, nil
			end
			lastError = currentPage
		else
			lastError = pages
		end

		if attempt < 3 then
			task.wait(math.min(8, 2 ^ (attempt - 1)))
		end
	end

	return nil, lastError
end

local function fetchOrderedValues(
	config: LeaderboardConfig,
	keys: { string }
): ({ [string]: any }?, any?)
	if #keys == 0 then
		return {}, nil
	end

	local valuesByKey: { [string]: any } = {}
	local batchSize = 25
	for firstIndex = 1, #keys, batchSize do
		local batchKeys = table.create(math.min(batchSize, #keys - firstIndex + 1))
		local lastIndex = math.min(#keys, firstIndex + batchSize - 1)
		for index = firstIndex, lastIndex do
			table.insert(batchKeys, keys[index])
		end

		local lastError: any = nil
		local batchValues: { [string]: any }? = nil
		for attempt = 1, 3 do
			local success, result = DataStoreRequestGate.Run(
				"OrderedRead",
				"LeaderboardBatchGetAsync",
				function()
					return getOrderedStore(config.OrderedStoreName):BatchGetAsync(batchKeys)
				end,
				{
					maxWaitSeconds = DATASTORE_BUDGET_WAIT_SECONDS,
					budgetCost = #batchKeys,
					queueKey = LEADERBOARD_REQUEST_QUEUE,
				}
			)
			if success and typeof(result) == "table" then
				batchValues = result
				break
			end
			lastError = result
			if attempt < 3 then
				task.wait(math.min(8, 2 ^ (attempt - 1)))
			end
		end

		if batchValues == nil then
			return valuesByKey, lastError
		end
		for key, value in pairs(batchValues) do
			valuesByKey[key] = value
		end
	end

	return valuesByKey, nil
end

local function makeLeaderboardEntry(userId: number, encodedValue: number): LeaderboardEntryData?
	local value = decodeLeaderboardValue(encodedValue)
	if value == nil then
		return nil
	end

	return {
		rank = 0,
		userId = userId,
		username = tostring(userId),
		value = value,
		sortValue = encodedValue,
	}
end

local function fetchEntries(
	config: LeaderboardConfig
): { LeaderboardEntryData }
	if LeaderboardService.DEBUG_USE_FAKE_DATA then
		local fakeEntries: { LeaderboardEntryData } = {}
		local topValue = 3.17e15
		local decayFactor = 0.82

		for rank = 1, config.MaxEntries do
			local value = math.max(0, topValue * (decayFactor ^ (rank - 1)))
			local sortValue = encodeLeaderboardValue(value) or 0

			table.insert(fakeEntries, {
				rank = rank,
				userId = 0,
				username = "FakePlayer" .. tostring(rank),
				value = decodeLeaderboardValue(sortValue) or 0,
				sortValue = sortValue,
			})
		end

		return fakeEntries
	end

	local currentPage, currentPageError = fetchOrderedPage(config, config.OrderedStoreName)
	local legacyPage: OrderedStorePage? = nil
	local legacyPageError: any = nil
	if config.LegacyOrderedStoreName then
		legacyPage, legacyPageError = fetchOrderedPage(config, config.LegacyOrderedStoreName)
	end

	if currentPage == nil and legacyPage == nil then
		local lastError = currentPageError or legacyPageError
		DebugModule.debugWarn(
			"Failed to fetch ordered data for " .. config.Name .. "; using last successful snapshot | err=" .. tostring(lastError),
			"LeaderboardService"
		)
		local cachedEntries = lastSuccessfulEntries[config.Name]
		return if cachedEntries then table.clone(cachedEntries) else {}
	end

	local legacyCandidates: { { userId: number, value: number } } = {}
	local legacyKeys: { string } = {}
	if legacyPage then
		for _, item in ipairs(legacyPage) do
			local userId = tonumber(item.key)
			local value = tonumber(item.value)
			if userId and isRealLeaderboardUserId(userId) and value then
				table.insert(legacyCandidates, {
					userId = userId,
					value = value,
				})
				table.insert(legacyKeys, tostring(userId))
			end
		end
	end

	local currentValues, currentValuesError = fetchOrderedValues(config, legacyKeys)
	local entriesByUserId: { [number]: LeaderboardEntryData } = {}
	if currentPage then
		for _, item in ipairs(currentPage) do
			local userId = tonumber(item.key)
			local encodedValue = tonumber(item.value)
			if userId and encodedValue and isRealLeaderboardUserId(userId) then
				local entry = makeLeaderboardEntry(userId, encodedValue)
				if entry then
					entriesByUserId[userId] = entry
				end
			end
		end
	end

	for _, candidate in ipairs(legacyCandidates) do
		if entriesByUserId[candidate.userId] then
			continue
		end

		local latestEntry = currentValues and currentValues[tostring(candidate.userId)]
		local encodedValue = if typeof(latestEntry) == "table" then tonumber(latestEntry.value) else nil
		if encodedValue == nil then
			encodedValue = encodeLeaderboardValue(candidate.value)
		end
		if encodedValue then
			local entry = makeLeaderboardEntry(candidate.userId, encodedValue)
			if entry then
				entriesByUserId[candidate.userId] = entry
			end
		end
	end

	if currentPageError or legacyPageError or currentValuesError then
		DebugModule.debugWarn(
			"Partial leaderboard migration read for "
				.. config.Name
				.. " | current="
				.. tostring(currentPageError)
				.. " | legacy="
				.. tostring(legacyPageError)
				.. " | batch="
				.. tostring(currentValuesError),
			"LeaderboardService"
		)
	end

	local entries: { LeaderboardEntryData } = {}
	for _, entry in pairs(entriesByUserId) do
		table.insert(entries, entry)
	end
	table.sort(entries, function(a: LeaderboardEntryData, b: LeaderboardEntryData): boolean
		if a.sortValue == b.sortValue then
			return a.userId < b.userId
		end
		return a.sortValue > b.sortValue
	end)

	while #entries > config.MaxEntries do
		table.remove(entries)
	end

	for rank, entry in ipairs(entries) do
		entry.rank = rank
		local nameSuccess, resolvedName = pcall(function()
			return Players:GetNameFromUserIdAsync(entry.userId)
		end)
		if nameSuccess and resolvedName then
			entry.username = resolvedName
		end
	end

	if LeaderboardService.DEBUG_APPEND_FAKE_DATA then
		local realEntryCount = #entries
		local lowestRealValue = entries[#entries] and entries[#entries].value or 100
		local fakeStartValue = math.max(0, lowestRealValue - 1)
		local rank = realEntryCount + 1

		while rank <= config.MaxEntries do
			local offset = rank - realEntryCount
			local fakeValue = math.max(0, fakeStartValue - offset + 1)
			local sortValue = encodeLeaderboardValue(fakeValue) or 0
			table.insert(entries, {
				rank = rank,
				userId = 0,
				username = "FakePlayer" .. tostring(offset),
				value = decodeLeaderboardValue(sortValue) or 0,
				sortValue = sortValue,
			})
			rank += 1
		end
	end

	lastSuccessfulEntries[config.Name] = table.clone(entries)
	return entries
end

local function waitForForcedWrite(configName: string, userId: number, expectedValue: number, playerName: string): boolean
	local deadline = os.clock() + FORCED_WRITE_WAIT_TIMEOUT_SECONDS
	while os.clock() < deadline do
		local lastPublished = lastPublishedValues[configName]
		local pendingValues = pendingWriteValues[configName]
		local failedValues = failedWriteValues[configName]
		if lastPublished and lastPublished[userId] == expectedValue and (not pendingValues or pendingValues[userId] == nil) then
			return true
		end
		if failedValues and failedValues[userId] == expectedValue then
			return false
		end
		task.wait(0.1)
	end

	DebugModule.debugWarn(
		string.format("Leaderboard flush timed out for %s (%s)", playerName, configName),
		"LeaderboardService"
	)
	return false
end

local function writeLeaderboardValue(configName: string, player: Player, forceWrite: boolean)
	local config = LeaderboardService.Configs[configName]
	if not config or (isShuttingDown and not forceWrite) then
		return
	end

	local value = player:GetAttribute(config.AttributeName)
	if typeof(value) ~= "number" then
		return
	end

	local encodedValue = encodeLeaderboardValue(value)
	if encodedValue == nil then
		DebugModule.debugWarn(
			string.format(
				"Skipping leaderboard write for %s (%s): invalid numeric value %s",
				player.Name,
				configName,
				tostring(value)
			),
			"LeaderboardService"
		)
		return
	end

	local userId = player.UserId
	if not isRealLeaderboardUserId(userId) then
		return
	end

	lastPublishedValues[configName] = lastPublishedValues[configName] or {}
	lastWriteTimes[configName] = lastWriteTimes[configName] or {}
	pendingWriteValues[configName] = pendingWriteValues[configName] or {}
	pendingWriteThreads[configName] = pendingWriteThreads[configName] or {}
	forceWriteRequests[configName] = forceWriteRequests[configName] or {}
	failedWriteValues[configName] = failedWriteValues[configName] or {}
	lastWriteFailureLogs[configName] = lastWriteFailureLogs[configName] or {}

	local pendingValues = pendingWriteValues[configName]
	if lastPublishedValues[configName][userId] == encodedValue and pendingValues[userId] == nil then
		return
	end

	pendingValues[userId] = encodedValue
	failedWriteValues[configName][userId] = nil
	if forceWrite then
		forceWriteRequests[configName][userId] = true
	end

	if not pendingWriteThreads[configName][userId] then
		pendingWriteThreads[configName][userId] = task.spawn(function()
			local retryDelay = WRITE_RETRY_INITIAL_SECONDS

			while true do
				local latestValue = pendingWriteValues[configName][userId]
				if latestValue == nil then
					break
				end

				local forceRequested = isShuttingDown or forceWriteRequests[configName][userId] == true
				local lastWriteTime = lastWriteTimes[configName][userId] or 0
				local timeUntilAllowed = math.max(0, config.WriteInterval - (os.clock() - lastWriteTime))
				if timeUntilAllowed > 0 and not forceRequested then
					local deadline = os.clock() + timeUntilAllowed
					repeat
						local remaining = deadline - os.clock()
						if remaining <= 0 then
							break
						end
						task.wait(math.min(remaining, 1))
						forceRequested = isShuttingDown or forceWriteRequests[configName][userId] == true
					until forceRequested
				end

				latestValue = pendingWriteValues[configName][userId]
				if latestValue == nil then
					break
				end
				pendingWriteValues[configName][userId] = nil

				local success, err = setOrderedValue(config, userId, latestValue)
				if success then
					lastPublishedValues[configName][userId] = latestValue
					lastWriteTimes[configName][userId] = os.clock()
					failedWriteValues[configName][userId] = nil
					if pendingWriteValues[configName][userId] == nil then
						forceWriteRequests[configName][userId] = nil
					end
					retryDelay = WRITE_RETRY_INITIAL_SECONDS
				else
					if pendingWriteValues[configName][userId] == nil then
						pendingWriteValues[configName][userId] = latestValue
					end
					failedWriteValues[configName][userId] = latestValue

					local now = os.clock()
					local lastFailureLog = lastWriteFailureLogs[configName][userId] or 0
					if now - lastFailureLog >= WRITE_FAILURE_LOG_COOLDOWN_SECONDS or forceRequested then
						lastWriteFailureLogs[configName][userId] = now
						DebugModule.debugWarn(
							string.format(
								"Failed leaderboard update for %s (%s): %s",
								player.Name,
								configName,
								tostring(err)
							),
							"LeaderboardService"
						)
					end

					if isShuttingDown then
						break
					end
					local retryDeadline = os.clock() + retryDelay
					repeat
						local remaining = retryDeadline - os.clock()
						if remaining <= 0 then
							break
						end
						task.wait(math.min(remaining, 1))
					until isShuttingDown
					retryDelay = math.min(retryDelay * 2, WRITE_RETRY_MAX_SECONDS)
				end
			end

			local configThreads = pendingWriteThreads[configName]
			if configThreads and configThreads[userId] == coroutine.running() then
				configThreads[userId] = nil
			end
		end)
	end

	if forceWrite then
		waitForForcedWrite(configName, userId, encodedValue, player.Name)
	end
end

function LeaderboardService.UpdatePlayerStat(configName: string, player: Player)
	if not RunService:IsServer() then
		return
	end

	writeLeaderboardValue(configName, player, false)
end

function LeaderboardService.FlushPlayer(player: Player)
	if not RunService:IsServer() then
		return
	end

	for configName in pairs(LeaderboardService.Configs) do
		writeLeaderboardValue(configName, player, true)
	end
end

function LeaderboardService.FlushPlayers(playersToFlush: { Player })
	for _, player in ipairs(playersToFlush) do
		LeaderboardService.FlushPlayer(player)
	end
end

function LeaderboardService.RefreshLeaderboard(configName: string)
	local config = LeaderboardService.Configs[configName]
	if not config then
		return
	end

	local entries = fetchEntries(config)
	renderLeaderboard(config, entries)
end

function LeaderboardService.BindPlayer(configName: string, player: Player)
	local config = LeaderboardService.Configs[configName]
	if not config then
		return
	end

	local playerMaid = getPlayerBindingMaid(player)
	playerMaid["AttributeChanged_" .. configName] = player
		:GetAttributeChangedSignal(config.AttributeName)
		:Connect(function()
			LeaderboardService.UpdatePlayerStat(configName, player)
		end)

	playerMaid["InitialSync_" .. configName] = task.defer(function()
		LeaderboardService.UpdatePlayerStat(configName, player)
	end)
end

function LeaderboardService.Init()
	if isInitialized then
		return
	end
	isInitialized = true
	isShuttingDown = false

	serviceMaid["PlayerAdded"] = Players.PlayerAdded:Connect(function(player)
		for configName in pairs(LeaderboardService.Configs) do
			LeaderboardService.BindPlayer(configName, player)
		end
	end)

	serviceMaid["PlayerRemoving"] = Players.PlayerRemoving:Connect(function(player)
		if not isShuttingDown then
			LeaderboardService.FlushPlayer(player)
		end
		clearPlayerBinding(player)
		clearPlayerWriteState(player.UserId)
	end)

	for configName, config in pairs(LeaderboardService.Configs) do
		for _, player in ipairs(Players:GetPlayers()) do
			LeaderboardService.BindPlayer(configName, player)
		end

		serviceMaid["RefreshLoop_" .. configName] = task.spawn(function()
			local alive = true
			while alive and not isShuttingDown do
				LeaderboardService.RefreshLeaderboard(configName)

				local refreshDeadline = os.clock() + config.RefreshInterval
				repeat
					local remaining = refreshDeadline - os.clock()
					if remaining <= 0 then
						break
					end
					task.wait(math.min(remaining, 1))
				until not alive or isShuttingDown
			end
		end)

		task.defer(function()
			LeaderboardService.RefreshLeaderboard(configName)
		end)
	end

	game:BindToClose(function()
		LeaderboardService.Shutdown()
	end)
end

function LeaderboardService.Shutdown()
	if isShuttingDown then
		return
	end

	isShuttingDown = true
	-- Leaderboards are derived data; avoid a shutdown-wide ordered-write burst.
	-- Player profile persistence owns the critical shutdown save path.
	serviceMaid:DoCleaning()
	isInitialized = false
end

return LeaderboardService
