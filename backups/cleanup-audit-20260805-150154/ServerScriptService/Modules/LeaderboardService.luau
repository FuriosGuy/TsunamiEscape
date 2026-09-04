--!strict
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UIFolder = Modules:WaitForChild("UI")
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local Maid = require(Modules:WaitForChild("Maid"))
local VisualFunctions = require(UIFolder:WaitForChild("VisualFunctions"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local LeaderboardService = {}

local leaderboardDebugConfig = CoreConfig.leaderboard
LeaderboardService.DEBUG_USE_FAKE_DATA = if leaderboardDebugConfig
		and typeof(leaderboardDebugConfig.debugUseFakeData) == "boolean"
	then leaderboardDebugConfig.debugUseFakeData
	else false
LeaderboardService.DEBUG_APPEND_FAKE_DATA = if leaderboardDebugConfig
		and typeof(leaderboardDebugConfig.debugAppendFakeData) == "boolean"
	then leaderboardDebugConfig.debugAppendFakeData
	else false

export type LeaderboardConfig = {
	Name: string,
	OrderedStoreName: string,
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
}

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
-- OrderedDataStore accepts signed 64-bit integer-sized values. Luau numbers
-- lose exact integer precision above 2^53, but clamping at 2^53 incorrectly
-- capped the leaderboard at roughly 9.01 Qd. Keep a small margin below 2^63
-- so the value remains valid for the OrderedDataStore backend.
local MAX_ORDERED_DATASTORE_INT = 9.22e18
local EXACT_LUA_INTEGER_LIMIT = 9007199254740991
local precisionWarningIssued = false

LeaderboardService.Configs = {
	WinLeaderboard = {
		Name = "WinLeaderboard",
		OrderedStoreName = "WinLeaderboard_v1",
		AttributeName = "WinCount",
		BoardPath = { "Folder", "WinLeaderboard", "Leaderboard", "SurfaceGui", "ScrollingFrame" },
		MaxEntries = 100,
		RefreshInterval = 60,
		WriteInterval = 30,
	},
	SpeedLeaderboard = {
		Name = "SpeedLeaderboard",
		OrderedStoreName = "SpeedLeaderboard_v1",
		AttributeName = "AllXPSpeed",
		BoardPath = { "Folder", "SpeedLeaderboard", "Leaderboard", "SurfaceGui", "ScrollingFrame" },
		MaxEntries = 100,
		RefreshInterval = 60,
		WriteInterval = 30,
	},
}

local orderedStores: { [string]: OrderedDataStore } = {}
local lastPublishedValues: { [string]: { [number]: number } } = {}
local lastWriteTimes: { [string]: { [number]: number } } = {}
local pendingWriteValues: { [string]: { [number]: number } } = {}
local pendingWriteThreads: { [string]: { [number]: thread } } = {}
local boardCaches: { [string]: LeaderboardBoardCache } = {}
local playerBindingMaids: { [Player]: Maid } = {}
local serviceMaid = Maid.new()
local isInitialized = false
local isShuttingDown = false

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

local function normalizeOrderedDataStoreValue(rawValue: number): number?
	if rawValue ~= rawValue then
		return nil
	end

	if rawValue == math.huge or rawValue == -math.huge then
		return nil
	end

	if rawValue > EXACT_LUA_INTEGER_LIMIT and not precisionWarningIssued then
		precisionWarningIssued = true
		DebugModule.debugWarn(
			"Leaderboard values above 2^53 are stored with Luau number precision; OrderedDataStore support remains available up to its 64-bit limit.",
			"LeaderboardService"
		)
	end

	local clamped = math.clamp(rawValue, 0, MAX_ORDERED_DATASTORE_INT)
	local rounded = math.floor(clamped + 0.5)

	if rounded ~= rounded then
		return nil
	end

	return rounded
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
			local thread = configThreads[userId]
			if thread then
				task.cancel(thread)
				configThreads[userId] = nil
			end
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
			parts[rank] = string.format("%d:%d:%s:%d", entry.rank, entry.userId, entry.username, entry.value)
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
		amountLabel.Text = VisualFunctions.FormatNumber(value)
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

local function fetchEntries(
	config: LeaderboardConfig
): { { rank: number, userId: number, username: string, value: number } }
	if LeaderboardService.DEBUG_USE_FAKE_DATA then
		local fakeEntries = {}
		local topValue = 3.17e15
		local decayFactor = 0.82

		for rank = 1, config.MaxEntries do
			local value = math.max(0, math.floor(topValue * (decayFactor ^ (rank - 1))))

			table.insert(fakeEntries, {
				rank = rank,
				userId = 0,
				username = "FakePlayer" .. tostring(rank),
				value = value,
			})
		end

		return fakeEntries
	end

	local entries = {}
	local success, pages = pcall(function()
		return getOrderedStore(config.OrderedStoreName):GetSortedAsync(false, config.MaxEntries)
	end)

	if not success or not pages then
		DebugModule.debugWarn("Failed to fetch ordered data for " .. config.Name, "LeaderboardService")
		return entries
	end

	local currentPage = pages:GetCurrentPage()
	for index, item in ipairs(currentPage) do
		local userId = tonumber(item.key)
		local value = tonumber(item.value) or 0
		if not userId or not isRealLeaderboardUserId(userId) then
			continue
		end

		local username = tostring(userId)
		local nameSuccess, resolvedName = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if nameSuccess and resolvedName then
			username = resolvedName
		end

		table.insert(entries, {
			rank = index,
			userId = userId,
			username = username,
			value = value,
		})
	end

	if LeaderboardService.DEBUG_APPEND_FAKE_DATA then
		local realEntryCount = #entries
		local lowestRealValue = entries[#entries] and entries[#entries].value or 100
		local fakeStartValue = math.max(0, math.floor(lowestRealValue - 1))
		local rank = realEntryCount + 1

		while rank <= config.MaxEntries do
			local offset = rank - realEntryCount
			local fakeValue = math.max(0, fakeStartValue - offset + 1)
			table.insert(entries, {
				rank = rank,
				userId = 0,
				username = "FakePlayer" .. tostring(offset),
				value = fakeValue,
			})
			rank += 1
		end
	end

	return entries
end

local function writeLeaderboardValue(configName: string, player: Player, forceWrite: boolean)
	local config = LeaderboardService.Configs[configName]
	if not config then
		return
	end

	local value = player:GetAttribute(config.AttributeName)
	if typeof(value) ~= "number" then
		return
	end

	local normalizedValue = normalizeOrderedDataStoreValue(value)
	if normalizedValue == nil then
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
	if lastPublishedValues[configName][userId] == normalizedValue and not forceWrite then
		return
	end

	lastWriteTimes[configName] = lastWriteTimes[configName] or {}
	pendingWriteValues[configName] = pendingWriteValues[configName] or {}
	pendingWriteThreads[configName] = pendingWriteThreads[configName] or {}

	pendingWriteValues[configName][userId] = normalizedValue

	if forceWrite then
		local success, err = pcall(function()
			getOrderedStore(config.OrderedStoreName):SetAsync(tostring(userId), normalizedValue)
		end)

		if success then
			lastPublishedValues[configName][userId] = normalizedValue
			lastWriteTimes[configName][userId] = os.clock()
			pendingWriteValues[configName][userId] = nil
		else
			DebugModule.debugWarn(
				string.format("Failed leaderboard flush for %s (%s): %s", player.Name, configName, tostring(err)),
				"LeaderboardService"
			)
		end
		return
	end

	if pendingWriteThreads[configName][userId] then
		return
	end

	pendingWriteThreads[configName][userId] = task.spawn(function()
		local alive = true

		while alive and not isShuttingDown do
			local latestValue = pendingWriteValues[configName][userId]
			if latestValue == nil then
				break
			end

			local lastWriteTime = lastWriteTimes[configName][userId] or 0
			local timeUntilAllowed = math.max(0, config.WriteInterval - (os.clock() - lastWriteTime))
			if timeUntilAllowed > 0 then
				local deadline = os.clock() + timeUntilAllowed
				repeat
					local remaining = deadline - os.clock()
					if remaining <= 0 then
						break
					end
					task.wait(math.min(remaining, 1))
				until not alive or isShuttingDown
				continue
			end

			pendingWriteValues[configName][userId] = nil

			local success, err = pcall(function()
				getOrderedStore(config.OrderedStoreName):SetAsync(tostring(userId), latestValue)
			end)

			if success then
				lastPublishedValues[configName][userId] = latestValue
				lastWriteTimes[configName][userId] = os.clock()
			else
				pendingWriteValues[configName][userId] = latestValue
				DebugModule.debugWarn(
					string.format("Failed leaderboard update for %s (%s): %s", player.Name, configName, tostring(err)),
					"LeaderboardService"
				)

				local retryDeadline = os.clock() + 5
				repeat
					local remaining = retryDeadline - os.clock()
					if remaining <= 0 then
						break
					end
					task.wait(math.min(remaining, 1))
				until not alive or isShuttingDown
			end
		end

		local configThreads = pendingWriteThreads[configName]
		if configThreads and configThreads[userId] == coroutine.running() then
			configThreads[userId] = nil
		end
	end)
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

	serviceMaid["PlayerAdded"] = Players.PlayerAdded:Connect(function(player)
		for configName in pairs(LeaderboardService.Configs) do
			LeaderboardService.BindPlayer(configName, player)
		end
	end)

	serviceMaid["PlayerRemoving"] = Players.PlayerRemoving:Connect(function(player)
		LeaderboardService.FlushPlayer(player)
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
		isShuttingDown = true
		LeaderboardService.FlushPlayers(Players:GetPlayers())
		serviceMaid:DoCleaning()
	end)
end

return LeaderboardService
