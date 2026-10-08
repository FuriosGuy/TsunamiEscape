--!strict
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ProductService = require(Modules:WaitForChild("ProductService"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local SystemChatService = require(Modules:WaitForChild("SystemChatService"))
local Maid = require(Modules:WaitForChild("Maid"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local ProductServerService = {}

-- CONFIG
local MODULE_NAME = "ProductServerService"
local isInitialized = false
local PLAYER_STORE_NAME = ProductService.DataStores["PlayerStats"]
local playerStore = DataStoreService:GetDataStore(PLAYER_STORE_NAME)
local receiptStore = DataStoreService:GetDataStore("ProcessedDevProductReceipts_v1")
local RECEIPT_RESERVATION_LEASE_SECONDS = 120
local serverLockIdentity = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))
local receiptJobId = serverLockIdentity
local SESSION_LOCK_ID_METADATA_KEY = "SessionLockId"
local SESSION_LOCK_UPDATED_AT_METADATA_KEY = "SessionLockUpdatedAt"
local PROCESSED_RECEIPTS_FIELD = "ProcessedDevProductReceipts"
local PROFILE_INITIALIZED_FIELD = "ProfileInitialized"
local persistenceConfig = CoreConfig.persistence
local SAVE_DEBOUNCE_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.saveDebounceSeconds) == "number"
	then math.max(0, persistenceConfig.saveDebounceSeconds)
	else 10
local LOAD_RETRY_ATTEMPTS = if persistenceConfig and typeof(persistenceConfig.loadRetryAttempts) == "number"
	then math.max(1, math.floor(persistenceConfig.loadRetryAttempts))
	else 3
local LOAD_RETRY_DELAY_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.loadRetryDelaySeconds) == "number"
	then math.max(0, persistenceConfig.loadRetryDelaySeconds)
	else 1
local FINAL_SAVE_RETRY_ATTEMPTS = if persistenceConfig
		and typeof(persistenceConfig.finalSaveRetryAttempts) == "number"
	then math.max(1, math.floor(persistenceConfig.finalSaveRetryAttempts))
	else 3
local FINAL_SAVE_RETRY_DELAY_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.finalSaveRetryDelaySeconds) == "number"
	then math.max(0, persistenceConfig.finalSaveRetryDelaySeconds)
	else 1
local GRANTED_RECEIPT_CACHE_LIMIT = if persistenceConfig
		and typeof(persistenceConfig.grantedReceiptCacheLimit) == "number"
	then math.max(0, math.floor(persistenceConfig.grantedReceiptCacheLimit))
	else 256
local SESSION_LOCK_RECOVERY_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.sessionLockRecoverySeconds) == "number"
	then math.max(15, math.floor(persistenceConfig.sessionLockRecoverySeconds))
	else 60
local SESSION_LOCK_RETRY_DELAY_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.sessionLockRetryDelaySeconds) == "number"
	then math.max(0.1, persistenceConfig.sessionLockRetryDelaySeconds)
	else 1
local SESSION_LOCK_RETRY_MAX_DELAY_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.sessionLockRetryMaxDelaySeconds) == "number"
	then math.max(SESSION_LOCK_RETRY_DELAY_SECONDS, persistenceConfig.sessionLockRetryMaxDelaySeconds)
	else 5
local SESSION_LOCK_WAIT_GRACE_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.sessionLockWaitGraceSeconds) == "number"
	then math.max(1, persistenceConfig.sessionLockWaitGraceSeconds)
	else 10
local SESSION_LOCK_HEARTBEAT_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.sessionLockHeartbeatSeconds) == "number"
	then math.max(5, math.floor(persistenceConfig.sessionLockHeartbeatSeconds))
	else 15
local DURABLE_RECEIPT_HISTORY_LIMIT = if persistenceConfig
		and typeof(persistenceConfig.durableReceiptHistoryLimit) == "number"
	then math.max(1, math.floor(persistenceConfig.durableReceiptHistoryLimit))
	else 128
local DEBUG_VERBOSE = persistenceConfig and persistenceConfig.debugVerbose == true

-- STATE
type StoredPlayerData = { [string]: any }
type StoredDataMutator = (data: StoredPlayerData) -> StoredPlayerData
type LoadResult = "Loaded" | "New" | "LegacyMigration" | "Failed" | "RecoveryRequired"
type LoadState = "Loading" | LoadResult
type SessionAcquireResult = "Acquired" | "Locked" | "Malformed" | "Failed"
type Metadata = { [string]: any }
type PlayerStoreQueue = {
	busy: boolean,
	waiters: { thread },
}
local lastSaveTimes: { [Player]: number } = {}
local pendingSaveTasks: { [Player]: boolean } = {}
local pendingSaveThreads: { [Player]: thread } = {}
local activeSaveLocks: { [Player]: boolean } = {}
local saveGenerations: { [Player]: number } = {}
local loadStates: { [Player]: LoadState } = {}
local sessionLockIds: { [Player]: string } = {}
local invalidatedSessions: { [Player]: boolean } = {}
local blockedSaveWarnings: { [Player]: boolean } = {}
local blockedSaveWarningTimes: { [Player]: number } = {}
local BLOCKED_SAVE_WARNING_INTERVAL_SECONDS = 30
local devProductCallbacks: { [number]: (...any) -> () } = {}
local gamePassCallbacks: { [number]: (...any) -> () } = {}
local marketplaceInfoCache: { [string]: any } = {}
local processingReceipts: { [string]: boolean } = {}
local grantedReceipts: { [string]: boolean } = {}
local grantedReceiptOrder: { string } = {}
local processedProfileReceipts: { [Player]: { [string]: boolean } } = {}
local processedProfileReceiptOrder: { [Player]: { string } } = {}
local announcedGamePasses: { [Player]: { [number]: boolean } } = {}
local creatorGrantLocks: { [Player]: boolean } = {}
local playerStoreQueues: { [number]: PlayerStoreQueue } = {}
local heartbeatTokens: { [Player]: number } = {}
local heartbeatInFlight: { [Player]: boolean } = {}
local heartbeatFailureCounts: { [Player]: number } = {}
local activePlayerSessions: { [number]: Player } = {}
local creatorUserId: number? = nil
local serviceMaid = Maid.new()
local serviceShuttingDown = false
local sessionLockHeartbeatGeneration = 0

local function dataKeyForUserId(userId: number): string
	return "player_" .. tostring(userId)
end

local function dataKey(player: Player): string
	return dataKeyForUserId(player.UserId)
end

local function debugVerbose(message: string)
	if DEBUG_VERBOSE then
		DebugModule.debugPrint(message, MODULE_NAME)
	end
end

local function acquirePlayerStoreQueue(userId: number, operationName: string): PlayerStoreQueue
	local queue = playerStoreQueues[userId]
	if queue == nil then
		queue = {
			busy = false,
			waiters = {},
		}
		playerStoreQueues[userId] = queue
	end

	if queue.busy then
		local waitStartedAt = os.clock()
		local currentThread = coroutine.running()
		assert(currentThread ~= nil, "Player datastore operations must run in a yielding thread")
		table.insert(queue.waiters, currentThread)
		debugVerbose(
			"Datastore operation queued | userId="
				.. tostring(userId)
				.. " | operation="
				.. operationName
				.. " | position="
				.. tostring(#queue.waiters)
		)
		coroutine.yield()
		debugVerbose(
			"Datastore queue resumed | userId="
				.. tostring(userId)
				.. " | operation="
				.. operationName
				.. " | waitedSeconds="
				.. string.format("%.2f", os.clock() - waitStartedAt)
		)
	end

	queue.busy = true
	return queue
end

local function releasePlayerStoreQueue(userId: number, queue: PlayerStoreQueue)
	while #queue.waiters > 0 do
		local nextThread = table.remove(queue.waiters, 1)
		if nextThread and coroutine.status(nextThread) == "suspended" then
			task.defer(function()
				local ok, err = coroutine.resume(nextThread)
				if not ok then
					DebugModule.debugError(
						"Player datastore queue waiter failed | userId=" .. tostring(userId),
						err,
						MODULE_NAME
					)
				end
			end)
			return
		end
	end

	queue.busy = false
	if playerStoreQueues[userId] == queue then
		playerStoreQueues[userId] = nil
	end
end

local function runQueuedPlayerStoreOperation(
	userId: number,
	operationName: string,
	operation: () -> any
): (boolean, any)
	local operationStartedAt = os.clock()
	local queue = acquirePlayerStoreQueue(userId, operationName)
	debugVerbose("Datastore operation started | userId=" .. tostring(userId) .. " | operation=" .. operationName)
	local ok, result = pcall(operation)
	releasePlayerStoreQueue(userId, queue)
	debugVerbose(
		"Datastore operation finished | userId="
			.. tostring(userId)
			.. " | operation="
			.. operationName
			.. " | success="
			.. tostring(ok)
			.. " | elapsedSeconds="
			.. string.format("%.2f", os.clock() - operationStartedAt)
	)
	return ok, result
end

local function cloneMetadata(keyInfo: any): Metadata
	if keyInfo == nil then
		return {}
	end

	local ok, metadata = pcall(function()
		return keyInfo:GetMetadata()
	end)
	if not ok or typeof(metadata) ~= "table" then
		return {}
	end
	return table.clone(metadata)
end

local function cloneUserIds(keyInfo: any): { any }
	if keyInfo == nil then
		return {}
	end

	local ok, userIds = pcall(function()
		return keyInfo:GetUserIds()
	end)
	if not ok or typeof(userIds) ~= "table" then
		return {}
	end
	return table.clone(userIds)
end

local function isSessionLockActive(metadata: Metadata, expectedLockId: string?): boolean
	local lockId = metadata[SESSION_LOCK_ID_METADATA_KEY]
	if typeof(lockId) ~= "string" or lockId == "" or lockId == expectedLockId then
		return false
	end

	local updatedAt = metadata[SESSION_LOCK_UPDATED_AT_METADATA_KEY]
	if typeof(updatedAt) ~= "number" then
		return false
	end
	return os.time() - math.floor(updatedAt) < SESSION_LOCK_RECOVERY_SECONDS
end

local function setSessionLockMetadata(metadata: Metadata, lockId: string?)
	if lockId == nil then
		metadata[SESSION_LOCK_ID_METADATA_KEY] = nil
		metadata[SESSION_LOCK_UPDATED_AT_METADATA_KEY] = nil
		return
	end

	metadata[SESSION_LOCK_ID_METADATA_KEY] = lockId
	metadata[SESSION_LOCK_UPDATED_AT_METADATA_KEY] = os.time()
end

local function sessionLockIdForPlayer(player: Player): string
	return serverLockIdentity .. ":" .. tostring(player.UserId) .. ":" .. HttpService:GenerateGUID(false)
end

local function loadProcessedReceiptHistory(player: Player, data: StoredPlayerData?)
	local receiptSet: { [string]: boolean } = {}
	local receiptOrder: { string } = {}
	local storedReceipts = if data then data[PROCESSED_RECEIPTS_FIELD] else nil
	if typeof(storedReceipts) == "table" then
		for _, receiptId in ipairs(storedReceipts) do
			if typeof(receiptId) == "string" and receiptId ~= "" and not receiptSet[receiptId] then
				receiptSet[receiptId] = true
				table.insert(receiptOrder, receiptId)
				if #receiptOrder >= DURABLE_RECEIPT_HISTORY_LIMIT then
					break
				end
			end
		end
	end
	processedProfileReceipts[player] = receiptSet
	processedProfileReceiptOrder[player] = receiptOrder
end

local function hasProcessedProfileReceipt(player: Player, receiptId: string): boolean
	local receiptSet = processedProfileReceipts[player]
	return receiptSet ~= nil and receiptSet[receiptId] == true
end

local function markProcessedProfileReceipt(player: Player, receiptId: string)
	local receiptSet = processedProfileReceipts[player]
	local receiptOrder = processedProfileReceiptOrder[player]
	if receiptSet == nil or receiptOrder == nil then
		receiptSet = {}
		receiptOrder = {}
		processedProfileReceipts[player] = receiptSet
		processedProfileReceiptOrder[player] = receiptOrder
	end
	if receiptSet[receiptId] then
		return
	end

	receiptSet[receiptId] = true
	table.insert(receiptOrder, receiptId)
	while #receiptOrder > DURABLE_RECEIPT_HISTORY_LIMIT do
		local oldestReceiptId = table.remove(receiptOrder, 1)
		if oldestReceiptId then
			receiptSet[oldestReceiptId] = nil
		end
	end
end

local function createStoredDataSnapshot(player: Player): StoredPlayerData
	local data: StoredPlayerData = {}
	for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
		local value = player:GetAttribute(entry.name)
		data[entry.name] = if value ~= nil then value else entry.default
	end

	local receiptOrder = processedProfileReceiptOrder[player] or {}
	data[PROCESSED_RECEIPTS_FIELD] = table.clone(receiptOrder)
	data[PROFILE_INITIALIZED_FIELD] = true
	return data
end

local function hasSavedProfileValues(data: StoredPlayerData): boolean
	for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
		if data[entry.name] ~= nil then
			return true
		end
	end

	return false
end

local function classifyProfileData(data: StoredPlayerData, createdNew: boolean): LoadResult
	if createdNew then
		return "New"
	end
	if data[PROFILE_INITIALIZED_FIELD] == true then
		return "Loaded"
	end
	if hasSavedProfileValues(data) then
		-- Legacy profiles predate ProfileInitialized. Their stored values are
		-- authoritative and will be migrated through the active session lock.
		return "LegacyMigration"
	end

	-- This shape is only produced by an interrupted first-profile placeholder.
	-- Never turn it into defaults without a durable source profile.
	return "RecoveryRequired"
end

local function cancelPendingSaveThread(player: Player)
	-- In-flight UpdateAsync calls must finish; generation invalidation cancels delayed work safely.
	pendingSaveThreads[player] = nil
	pendingSaveTasks[player] = nil
	saveGenerations[player] = (saveGenerations[player] or 0) + 1
end

local function invalidateSession(player: Player, reason: string)
	local userId = player.UserId
	if invalidatedSessions[player] or player.Parent == nil then
		return
	end

	invalidatedSessions[player] = true
	player:SetAttribute("Data_Loaded", false)
	player:SetAttribute("Data_LoadState", "Unavailable")
	DebugModule.debugWarn(
		"Persistence session invalidated | player="
			.. player.Name
			.. " | userId="
			.. tostring(userId)
			.. " | reason="
			.. reason,
		MODULE_NAME
	)
end

local function releaseSessionLock(player: Player, reason: string): boolean
	local userId = player.UserId
	local lockId = sessionLockIds[player]
	if lockId == nil then
		return true
	end

	debugVerbose("Session lock release requested | player=" .. player.Name .. " | reason=" .. reason)
	local queuedOk, outcome = runQueuedPlayerStoreOperation(userId, "ReleaseSessionLock", function()
		local released = false
		local ok, err = pcall(function()
			playerStore:UpdateAsync(dataKey(player), function(existingData, keyInfo)
				local metadata = cloneMetadata(keyInfo)
				if metadata[SESSION_LOCK_ID_METADATA_KEY] ~= lockId then
					return nil
				end
				setSessionLockMetadata(metadata, nil)
				released = true
				return existingData, cloneUserIds(keyInfo), metadata
			end)
		end)
		return {
			ok = ok,
			err = err,
			released = released,
		}
	end)
	if not queuedOk or typeof(outcome) ~= "table" or outcome.ok ~= true then
		DebugModule.debugWarn(
			"Session lock release failed | player="
				.. player.Name
				.. " | reason="
				.. reason
				.. " | err="
				.. tostring(if typeof(outcome) == "table" then outcome.err else outcome),
			MODULE_NAME
		)
		return false
	end
	if outcome.released ~= true then
		DebugModule.debugWarn(
			"Session lock release skipped because ownership changed | player=" .. player.Name .. " | reason=" .. reason,
			MODULE_NAME
		)
		return false
	end

	sessionLockIds[player] = nil
	debugVerbose("Session lock released | player=" .. player.Name .. " | reason=" .. reason)
	return true
end

local function acquireSessionLock(player: Player): (SessionAcquireResult, StoredPlayerData?, any?, boolean, string?)
	local userId = player.UserId
	local desiredLockId = sessionLockIdForPlayer(player)
	local result: SessionAcquireResult = "Failed"
	local createdNew = false
	local storedData: any = nil
	local storedKeyInfo: any = nil
	local lockContext: string? = nil

	debugVerbose("Session lock acquisition requested | player=" .. player.Name .. " | userId=" .. tostring(userId))
	local queuedOk, outcome = runQueuedPlayerStoreOperation(userId, "AcquireSessionLock", function()
		local ok, err = pcall(function()
			storedData, storedKeyInfo = playerStore:UpdateAsync(dataKey(player), function(existingData, keyInfo)
				local metadata = cloneMetadata(keyInfo)
				if isSessionLockActive(metadata, desiredLockId) then
					local updatedAt = metadata[SESSION_LOCK_UPDATED_AT_METADATA_KEY]
					local lockAge = if typeof(updatedAt) == "number"
						then math.max(0, os.time() - math.floor(updatedAt))
						else -1
					lockContext = "activeLockAge=" .. tostring(lockAge)
					result = "Locked"
					return nil
				end
				if existingData ~= nil and typeof(existingData) ~= "table" then
					result = "Malformed"
					return nil
				end

				createdNew = existingData == nil
				local nextData: StoredPlayerData = if typeof(existingData) == "table"
					then table.clone(existingData)
					else { [PROFILE_INITIALIZED_FIELD] = false }
				setSessionLockMetadata(metadata, desiredLockId)
				result = "Acquired"
				return nextData, cloneUserIds(keyInfo), metadata
			end)
		end)
		return {
			ok = ok,
			err = err,
		}
	end)
	if not queuedOk or typeof(outcome) ~= "table" or outcome.ok ~= true then
		return "Failed", nil, nil, false, tostring(if typeof(outcome) == "table" then outcome.err else outcome)
	end
	if result ~= "Acquired" or typeof(storedData) ~= "table" then
		return result, nil, storedKeyInfo, false, lockContext
	end

	sessionLockIds[player] = desiredLockId
	debugVerbose(
		"Session lock acquired | player="
			.. player.Name
			.. " | userId="
			.. tostring(userId)
			.. " | newProfile="
			.. tostring(createdNew)
	)
	return "Acquired", storedData, storedKeyInfo, createdNew, nil
end

local function isDataLoaded(player: Player): boolean
	if player:GetAttribute("Data_Loaded") ~= true then
		return false
	end

	local state = loadStates[player]
	return state == nil or state == "Loaded" or state == "New" or state == "LegacyMigration"
end

local function isExperienceCreator(player: Player): boolean
	return creatorUserId ~= nil and player.UserId == creatorUserId
end

local function isCanonicalDeveloperProduct(productId: number): boolean
	for _, configuredProductId in pairs(ProductService.DevProducts) do
		if configuredProductId == productId then
			return true
		end
	end
	return false
end

local function canPersistPlayerData(player: Player, allowPendingInitialization: boolean): boolean
	if isDataLoaded(player) then
		return true
	end

	if not allowPendingInitialization or player.Parent == nil then
		return false
	end

	local state = loadStates[player]
	return state == "New" or state == "LegacyMigration"
end

local function cacheGrantedReceipt(receiptId: string)
	if grantedReceipts[receiptId] or GRANTED_RECEIPT_CACHE_LIMIT <= 0 then
		return
	end

	grantedReceipts[receiptId] = true
	table.insert(grantedReceiptOrder, receiptId)
	while #grantedReceiptOrder > GRANTED_RECEIPT_CACHE_LIMIT do
		local oldestReceiptId = table.remove(grantedReceiptOrder, 1)
		if oldestReceiptId then
			grantedReceipts[oldestReceiptId] = nil
		end
	end
end

local function getMarketplaceInfoCached(itemId: number, infoType: Enum.InfoType)
	local key = infoType.Name .. ":" .. tostring(itemId)
	if marketplaceInfoCache[key] then
		return marketplaceInfoCache[key]
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(itemId, infoType)
	end)
	if ok then
		marketplaceInfoCache[key] = info
		return info
	end
	return nil
end

local function savePlayerData(
	player: Player,
	forceSave: boolean?,
	releaseLock: boolean?,
	allowPendingInitialization: boolean
): boolean
	local userId = player.UserId
	local isForcedSave = forceSave == true
	local shouldReleaseLock = releaseLock == true
	local dataLoaded = canPersistPlayerData(player, allowPendingInitialization)
	local isPlayerParented = player.Parent ~= nil
	debugVerbose(
		"Save requested | player="
			.. player.Name
			.. " | userId="
			.. tostring(userId)
			.. " | level="
			.. tostring(player:GetAttribute("CurrentLevel"))
			.. " | kart="
			.. tostring(player:GetAttribute("Kart_Equipped"))
			.. " | force="
			.. tostring(isForcedSave)
			.. " | releaseLock="
			.. tostring(shouldReleaseLock)
			.. " | dataLoaded="
			.. tostring(dataLoaded)
			.. " | parented="
			.. tostring(isPlayerParented)
	)
	if (not isPlayerParented and not isForcedSave) or not dataLoaded then
		local warningNow = os.clock()
		local lastWarningAt = blockedSaveWarningTimes[player]
		if
			not blockedSaveWarnings[player]
			or lastWarningAt == nil
			or warningNow - lastWarningAt >= BLOCKED_SAVE_WARNING_INTERVAL_SECONDS
		then
			blockedSaveWarnings[player] = true
			blockedSaveWarningTimes[player] = warningNow
			local reason = if not dataLoaded
				then "data load has not succeeded"
				else "player is no longer parented for a non-forced save"
			DebugModule.debugWarn(
				"Save blocked | reason="
					.. reason
					.. " | player="
					.. player.Name
					.. " | force="
					.. tostring(forceSave == true),
				MODULE_NAME
			)
		end
		return false
	end
	if sessionLockIds[player] == nil then
		DebugModule.debugWarn(
			"Save blocked because session lock is missing | player="
				.. player.Name
				.. " | force="
				.. tostring(isForcedSave),
			MODULE_NAME
		)
		return false
	end
	if shouldReleaseLock and not isForcedSave then
		DebugModule.debugWarn(
			"Save blocked because lock release requires force save | player=" .. player.Name,
			MODULE_NAME
		)
		return false
	end

	local now = os.clock()
	local lastSave = lastSaveTimes[player] or 0
	local hardSessionFailure = false

	local function perform(expectedGeneration: number?): boolean
		if
			(player.Parent == nil and not isForcedSave) or not canPersistPlayerData(player, allowPendingInitialization)
		then
			return false
		end
		if expectedGeneration ~= nil and saveGenerations[player] ~= expectedGeneration then
			return false
		end
		if activeSaveLocks[player] then
			return false
		end
		activeSaveLocks[player] = true

		local data = createStoredDataSnapshot(player)
		debugVerbose(
			"Save snapshot created | player="
				.. player.Name
				.. " | level="
				.. tostring(data.CurrentLevel)
				.. " | kart="
				.. tostring(data.Kart_Equipped)
				.. " | allXPSpeed="
				.. tostring(data.AllXPSpeed)
				.. " | wins="
				.. tostring(data.WinCount)
		)
		local sessionLockLost = false
		local recoveredLegacyLock = false
		local staleGeneration = false
		local ok, err = pcall(function()
			playerStore:UpdateAsync(dataKey(player), function(existingData, keyInfo)
				if expectedGeneration ~= nil and saveGenerations[player] ~= expectedGeneration then
					staleGeneration = true
					return nil
				end
				if typeof(existingData) ~= "table" then
					sessionLockLost = true
					return nil
				end

				local metadata = cloneMetadata(keyInfo)
				local storedLockId = metadata[SESSION_LOCK_ID_METADATA_KEY]
				if storedLockId ~= sessionLockIds[player] and storedLockId ~= nil and storedLockId ~= "" then
					sessionLockLost = true
					return nil
				end
				if storedLockId ~= sessionLockIds[player] then
					recoveredLegacyLock = true
				end
				local nextData: StoredPlayerData = if typeof(existingData) == "table"
					then table.clone(existingData)
					else {}
				for name, value in pairs(data) do
					nextData[name] = value
				end
				if shouldReleaseLock then
					setSessionLockMetadata(metadata, nil)
				else
					setSessionLockMetadata(metadata, sessionLockIds[player])
				end
				return nextData, cloneUserIds(keyInfo), metadata
			end)
		end)
		activeSaveLocks[player] = nil
		if staleGeneration then
			return false
		end
		if sessionLockLost then
			hardSessionFailure = true
			DebugModule.debugWarn(
				"Save rejected because session lock ownership changed | player=" .. player.Name,
				MODULE_NAME
			)
			invalidateSession(player, "SessionLockLost")
			return false
		end
		if recoveredLegacyLock then
			DebugModule.debugWarn("Recovered session lock metadata during save | player=" .. player.Name, MODULE_NAME)
		end
		if not ok then
			DebugModule.debugWarn("Save failed | player=" .. player.Name .. " | err=" .. tostring(err), MODULE_NAME)
			return false
		end

		blockedSaveWarnings[player] = nil
		blockedSaveWarningTimes[player] = nil
		lastSaveTimes[player] = os.clock()
		if shouldReleaseLock then
			sessionLockIds[player] = nil
		end
		local saveMessage = "Saved player data | player="
			.. player.Name
			.. " | level="
			.. tostring(data.CurrentLevel)
			.. " | force="
			.. tostring(isForcedSave)
			.. " | released="
			.. tostring(shouldReleaseLock)
		if isForcedSave or shouldReleaseLock then
			DebugModule.debugInfo(saveMessage, MODULE_NAME)
		else
			debugVerbose(saveMessage)
		end
		return true
	end

	if forceSave then
		cancelPendingSaveThread(player)
		for attempt = 1, FINAL_SAVE_RETRY_ATTEMPTS do
			debugVerbose(
				"Forced save attempt | player="
					.. player.Name
					.. " | attempt="
					.. tostring(attempt)
					.. "/"
					.. tostring(FINAL_SAVE_RETRY_ATTEMPTS)
			)
			local queuedOk, saveResult = runQueuedPlayerStoreOperation(userId, "ForcedSave", function()
				-- Forced saves own their lifetime. Do not let shutdown cancellation
				-- invalidate an in-flight final UpdateAsync callback.
				return perform(nil)
			end)
			if queuedOk and saveResult == true then
				return true
			end
			if hardSessionFailure then
				return false
			end
			if attempt < FINAL_SAVE_RETRY_ATTEMPTS and FINAL_SAVE_RETRY_DELAY_SECONDS > 0 then
				task.wait(FINAL_SAVE_RETRY_DELAY_SECONDS * attempt)
			end
		end
		return false
	end

	if pendingSaveTasks[player] then
		return true
	end
	local waitTime = math.max(0, SAVE_DEBOUNCE_SECONDS - (now - lastSave))
	pendingSaveTasks[player] = true
	local generation = saveGenerations[player] or 0
	debugVerbose(
		"Regular save scheduled | player="
			.. player.Name
			.. " | delaySeconds="
			.. string.format("%.2f", waitTime)
			.. " | generation="
			.. tostring(generation)
	)
	pendingSaveThreads[player] = task.spawn(function()
		if waitTime > 0 then
			task.wait(waitTime)
		end
		if saveGenerations[player] ~= generation then
			return
		end
		pendingSaveTasks[player] = nil
		pendingSaveThreads[player] = nil
		runQueuedPlayerStoreOperation(userId, "RegularSave", function()
			return perform(generation)
		end)
	end)
	return true
end

function ProductServerService.SavePlayerData(player: Player, forceSave: boolean?, releaseLock: boolean?): boolean
	local state = loadStates[player]
	local allowsPendingInitialization = forceSave == true
		and releaseLock ~= true
		and (state == "New" or state == "LegacyMigration")
	local saved = savePlayerData(player, forceSave, releaseLock, allowsPendingInitialization)
	if saved and allowsPendingInitialization then
		loadStates[player] = "Loaded"
	end
	return saved
end

local function renewSessionLock(player: Player): boolean
	local userId = player.UserId
	local lockId = sessionLockIds[player]
	if lockId == nil or serviceShuttingDown or player.Parent == nil or not isDataLoaded(player) then
		return false
	end

	local queuedOk, outcome = runQueuedPlayerStoreOperation(userId, "RenewSessionLock", function()
		if
			serviceShuttingDown
			or player.Parent == nil
			or sessionLockIds[player] ~= lockId
			or not isDataLoaded(player)
		then
			return {
				status = "Skipped",
			}
		end

		local renewed = false
		local lockLost = false
		local recoveredLegacyLock = false
		local ok, err = pcall(function()
			playerStore:UpdateAsync(dataKey(player), function(existingData, keyInfo)
				if typeof(existingData) ~= "table" then
					lockLost = true
					return nil
				end

				local metadata = cloneMetadata(keyInfo)
				local storedLockId = metadata[SESSION_LOCK_ID_METADATA_KEY]
				if storedLockId ~= lockId and storedLockId ~= nil and storedLockId ~= "" then
					lockLost = true
					return nil
				end
				if storedLockId ~= lockId then
					recoveredLegacyLock = true
				end

				setSessionLockMetadata(metadata, lockId)
				renewed = true
				return existingData, cloneUserIds(keyInfo), metadata
			end)
		end)

		return {
			status = if lockLost then "Lost" elseif renewed then "Renewed" else "Skipped",
			err = err,
			ok = ok,
			recoveredLegacyLock = recoveredLegacyLock,
		}
	end)

	if not queuedOk or typeof(outcome) ~= "table" then
		return false
	end
	if outcome.status == "Lost" then
		invalidateSession(player, "SessionLockLostDuringHeartbeat")
		return false
	end
	if outcome.ok ~= true then
		local failureCount = (heartbeatFailureCounts[player] or 0) + 1
		heartbeatFailureCounts[player] = failureCount
		if failureCount == 1 or failureCount % 3 == 0 then
			DebugModule.debugWarn(
				"Session lock heartbeat failed | player="
					.. player.Name
					.. " | failureCount="
					.. tostring(failureCount)
					.. " | err="
					.. tostring(outcome.err),
				MODULE_NAME
			)
		end
		return false
	end
	if outcome.recoveredLegacyLock == true then
		DebugModule.debugWarn("Session lock metadata recovered during heartbeat | player=" .. player.Name, MODULE_NAME)
	end

	heartbeatFailureCounts[player] = nil
	return outcome.status == "Renewed"
end

local function scheduleSessionLockHeartbeat(player: Player)
	if heartbeatInFlight[player] or sessionLockHeartbeatGeneration <= 0 then
		return
	end

	local token = (heartbeatTokens[player] or 0) + 1
	heartbeatTokens[player] = token
	heartbeatInFlight[player] = true
	task.spawn(function()
		if heartbeatTokens[player] == token then
			renewSessionLock(player)
		end
		if heartbeatTokens[player] == token then
			heartbeatInFlight[player] = nil
		end
	end)
end

local function startSessionLockHeartbeat()
	sessionLockHeartbeatGeneration += 1
	local generation = sessionLockHeartbeatGeneration
	task.spawn(function()
		while generation == sessionLockHeartbeatGeneration and not serviceShuttingDown do
			task.wait(SESSION_LOCK_HEARTBEAT_SECONDS)
			if generation ~= sessionLockHeartbeatGeneration or serviceShuttingDown then
				break
			end
			for _, player in ipairs(Players:GetPlayers()) do
				scheduleSessionLockHeartbeat(player)
			end
		end
	end)
end

function ProductServerService.LoadPlayerData(player: Player): LoadResult
	local userId = player.UserId
	local previousPlayer = activePlayerSessions[userId]
	activePlayerSessions[userId] = player
	loadStates[player] = "Loading"
	if previousPlayer ~= nil and previousPlayer ~= player then
		DebugModule.debugInfo(
			"Profile lifecycle queued behind previous player instance | userId=" .. tostring(userId),
			MODULE_NAME
		)
	end
	local data: StoredPlayerData? = nil
	local dataKeyInfo: any = nil
	local createdNew = false
	local loadFailures = 0
	local lockAttempts = 0
	local lockWaitLogged = false
	local lockWaitStartedAt: number? = nil
	local lockWaitDeadline: number? = nil
	DebugModule.debugInfo(
		"Load started | player=" .. player.Name .. " | userId=" .. tostring(userId) .. " | key=" .. dataKey(player),
		MODULE_NAME
	)

	while player.Parent and not serviceShuttingDown do
		debugVerbose(
			"Session lock acquisition attempt | player="
				.. player.Name
				.. " | attempt="
				.. tostring(lockAttempts + loadFailures + 1)
		)
		local acquireResult, acquiredData, acquiredKeyInfo, acquiredNew, acquireError = acquireSessionLock(player)
		if acquireResult == "Acquired" then
			data = acquiredData
			dataKeyInfo = acquiredKeyInfo
			createdNew = acquiredNew
			if lockWaitStartedAt ~= nil then
				DebugModule.debugInfo(
					"Session lock acquired after waiting | player="
						.. player.Name
						.. " | waitedSeconds="
						.. string.format("%.1f", os.clock() - lockWaitStartedAt),
					MODULE_NAME
				)
			end
			break
		end
		if acquireResult == "Malformed" then
			loadStates[player] = "Failed"
			DebugModule.debugWarn("Load returned malformed data | player=" .. player.Name, MODULE_NAME)
			return "Failed"
		end
		if acquireResult == "Locked" then
			lockAttempts += 1
			if not lockWaitLogged then
				lockWaitLogged = true
				lockWaitStartedAt = os.clock()
				lockWaitDeadline = lockWaitStartedAt + SESSION_LOCK_RECOVERY_SECONDS + SESSION_LOCK_WAIT_GRACE_SECONDS
				DebugModule.debugWarn(
					"Session lock busy; queued retry started | player="
						.. player.Name
						.. " | recoverySeconds="
						.. tostring(SESSION_LOCK_RECOVERY_SECONDS)
						.. " | maxWaitSeconds="
						.. tostring(SESSION_LOCK_RECOVERY_SECONDS + SESSION_LOCK_WAIT_GRACE_SECONDS)
						.. " | context="
						.. tostring(acquireError),
					MODULE_NAME
				)
			end
			if lockWaitDeadline ~= nil and os.clock() >= lockWaitDeadline then
				break
			end
		else
			loadFailures += 1
			DebugModule.debugWarn(
				"Load attempt failed | player="
					.. player.Name
					.. " | attempt="
					.. tostring(loadFailures)
					.. "/"
					.. tostring(LOAD_RETRY_ATTEMPTS)
					.. " | err="
					.. tostring(acquireError),
				MODULE_NAME
			)
			if loadFailures >= LOAD_RETRY_ATTEMPTS then
				break
			end
		end

		if acquireResult == "Locked" then
			local retryExponent = math.min(lockAttempts - 1, 8)
			local retryDelay =
				math.min(SESSION_LOCK_RETRY_MAX_DELAY_SECONDS, SESSION_LOCK_RETRY_DELAY_SECONDS * (2 ^ retryExponent))
			local remainingWait = if lockWaitDeadline ~= nil then lockWaitDeadline - os.clock() else retryDelay
			if remainingWait <= 0 then
				break
			end
			task.wait(math.min(retryDelay, remainingWait))
		else
			task.wait(LOAD_RETRY_DELAY_SECONDS)
		end
	end

	if data == nil then
		loadStates[player] = "Failed"
		DebugModule.debugWarn(
			"Load failed before session lock acquisition | player="
				.. player.Name
				.. " | lockWaited="
				.. tostring(lockWaitLogged)
				.. " | lockAttempts="
				.. tostring(lockAttempts)
				.. " | recoverySeconds="
				.. tostring(SESSION_LOCK_RECOVERY_SECONDS)
				.. " | waitedSeconds="
				.. string.format("%.1f", if lockWaitStartedAt ~= nil then os.clock() - lockWaitStartedAt else 0)
				.. " | shuttingDown="
				.. tostring(serviceShuttingDown),
			MODULE_NAME
		)
		return "Failed"
	end
	if player.Parent == nil then
		releaseSessionLock(player, "PlayerLeftDuringLoad")
		loadStates[player] = "Failed"
		return "Failed"
	end

	local loadResult = classifyProfileData(data, createdNew)
	debugVerbose(
		"Load profile classified | player="
			.. player.Name
			.. " | createdNew="
			.. tostring(createdNew)
			.. " | classification="
			.. loadResult
	)
	if loadResult == "RecoveryRequired" then
		releaseSessionLock(player, "ProfileRecoveryRequired")
		loadStates[player] = "RecoveryRequired"
		DebugModule.debugWarn(
			"Profile contains only an uninitialized placeholder; refusing default overwrite | player=" .. player.Name,
			MODULE_NAME
		)
		return "RecoveryRequired"
	end

	for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
		local saved = data[entry.name]
		if saved == nil then
			continue
		end

		if typeof(entry.default) == "number" and typeof(saved) ~= "number" then
			DebugModule.debugWarn(
				"Saved numeric attribute rejected due to type mismatch | player="
					.. player.Name
					.. " | attribute="
					.. entry.name
					.. " | savedType="
					.. typeof(saved),
				MODULE_NAME
			)
			continue
		end
		player:SetAttribute(entry.name, saved)
	end

	loadProcessedReceiptHistory(player, data)
	loadStates[player] = loadResult
	blockedSaveWarnings[player] = nil
	blockedSaveWarningTimes[player] = nil
	local loadedVersion = "none"
	if dataKeyInfo ~= nil then
		local versionOk, version = pcall(function()
			return dataKeyInfo.Version
		end)
		if versionOk and version ~= nil then
			loadedVersion = tostring(version)
		end
	end
	DebugModule.debugInfo(
		"Load succeeded | player="
			.. player.Name
			.. " | level="
			.. tostring(player:GetAttribute("CurrentLevel"))
			.. " | allXPSpeed="
			.. tostring(player:GetAttribute("AllXPSpeed"))
			.. " | kart="
			.. tostring(player:GetAttribute("Kart_Equipped"))
			.. " | wins="
			.. tostring(player:GetAttribute("WinCount"))
			.. " | version="
			.. loadedVersion
			.. " | status="
			.. loadResult
	)
	return loadResult
end

function ProductServerService.UpdateStoredPlayerData(userId: number, mutator: StoredDataMutator): boolean
	if typeof(userId) ~= "number" or userId <= 0 then
		return false
	end
	if Players:GetPlayerByUserId(userId) then
		DebugModule.debugWarn(
			"Offline update rejected because player is online | userId=" .. tostring(userId),
			MODULE_NAME
		)
		return false
	end

	local queuedOk, outcome = runQueuedPlayerStoreOperation(userId, "OfflineUpdate", function()
		if Players:GetPlayerByUserId(userId) then
			return {
				status = "Online",
			}
		end

		local blockedBySessionLock = false
		local ok, err = pcall(function()
			playerStore:UpdateAsync(dataKeyForUserId(userId), function(existingData, keyInfo)
				local metadata = cloneMetadata(keyInfo)
				if isSessionLockActive(metadata, nil) then
					blockedBySessionLock = true
					return nil
				end
				setSessionLockMetadata(metadata, nil)
				local nextData: StoredPlayerData = if typeof(existingData) == "table"
					then table.clone(existingData)
					else {}
				local updatedData = mutator(nextData)
				if typeof(updatedData) ~= "table" then
					assert(false, "Stored data mutator must return a table")
				end
				return updatedData, cloneUserIds(keyInfo), metadata
			end)
		end)
		return {
			status = if blockedBySessionLock then "Locked" elseif ok then "Succeeded" else "Failed",
			err = err,
		}
	end)
	if not queuedOk or typeof(outcome) ~= "table" then
		DebugModule.debugWarn(
			"Stored player update failed before operation | userId="
				.. tostring(userId)
				.. " | err="
				.. tostring(outcome),
			MODULE_NAME
		)
		return false
	end
	if outcome.status == "Online" then
		DebugModule.debugWarn(
			"Offline update rejected because player joined while queued | userId=" .. tostring(userId),
			MODULE_NAME
		)
		return false
	end
	if outcome.status == "Locked" then
		DebugModule.debugWarn(
			"Offline update blocked by active session lock | userId=" .. tostring(userId),
			MODULE_NAME
		)
		return false
	end
	if outcome.status ~= "Succeeded" then
		DebugModule.debugWarn(
			"Stored player update failed | userId=" .. tostring(userId) .. " | err=" .. tostring(outcome.err),
			MODULE_NAME
		)
		return false
	end

	debugVerbose("Stored player update succeeded | userId=" .. tostring(userId))
	return true
end

function ProductServerService.CleanupPlayerState(player: Player)
	local userId = player.UserId
	local ownsActiveSession = activePlayerSessions[userId] == player

	cancelPendingSaveThread(player)
	heartbeatTokens[player] = nil
	heartbeatInFlight[player] = nil
	heartbeatFailureCounts[player] = nil
	lastSaveTimes[player] = nil
	loadStates[player] = nil
	sessionLockIds[player] = nil
	invalidatedSessions[player] = nil
	blockedSaveWarnings[player] = nil
	blockedSaveWarningTimes[player] = nil
	processedProfileReceipts[player] = nil
	processedProfileReceiptOrder[player] = nil
	announcedGamePasses[player] = nil
	creatorGrantLocks[player] = nil
	saveGenerations[player] = nil
	if ownsActiveSession then
		activePlayerSessions[userId] = nil
	else
		debugVerbose("Cleaned stale player instance state | player=" .. player.Name .. " | userId=" .. tostring(userId))
	end
	debugVerbose("Persistence state cleaned | player=" .. player.Name .. " | userId=" .. tostring(userId))
end

function ProductServerService.ReleaseSessionLock(player: Player, reason: string?): boolean
	return releaseSessionLock(player, reason or "ExplicitRelease")
end

function ProductServerService.PrepareForShutdown()
	if serviceShuttingDown then
		return
	end

	serviceShuttingDown = true
	DebugModule.debugInfo("Persistence shutdown preparation started | activeSessions=" .. tostring((function(): number
		local count = 0
		for _ in pairs(activePlayerSessions) do
			count += 1
		end
		return count
	end)()), MODULE_NAME)
	sessionLockHeartbeatGeneration += 1
	for player in pairs(pendingSaveThreads) do
		cancelPendingSaveThread(player)
	end
end

function ProductServerService.IsShuttingDown(): boolean
	return serviceShuttingDown
end

function ProductServerService.SetCreatorUserId(userId: number?)
	creatorUserId = if typeof(userId) == "number" and userId > 0 then userId else nil
	DebugModule.debugInfo(
		"Creator identity configured | creatorUserId=" .. tostring(creatorUserId),
		MODULE_NAME
	)
end

function ProductServerService.SetProductCallback(id: number, cb: (...any) -> ())
	devProductCallbacks[id] = cb
end

function ProductServerService.SetGamePassCallback(id: number, cb: (...any) -> ())
	gamePassCallbacks[id] = cb
end

local function getReceiptId(info: any): string?
	local purchaseId = info.PurchaseId
	if purchaseId == nil then
		return nil
	end

	local receiptId = tostring(purchaseId)
	return if receiptId ~= "" then receiptId else nil
end

local function reserveReceipt(
	receiptId: string,
	player: Player,
	productId: number
): "Granted" | "Reserved" | "Busy" | nil
	if grantedReceipts[receiptId] then
		return "Granted"
	end

	local ok, record = pcall(function()
		return receiptStore:UpdateAsync("receipt_" .. receiptId, function(previous)
			if typeof(previous) == "table" then
				if previous.Status == "Granted" then
					return previous
				end

				local updatedAt = previous.UpdatedAt
				if
					previous.Status == "Processing"
					and typeof(updatedAt) == "number"
					and os.time() - updatedAt < RECEIPT_RESERVATION_LEASE_SECONDS
				then
					return previous
				end
			end

			return {
				Status = "Processing",
				JobId = receiptJobId,
				PlayerId = player.UserId,
				ProductId = productId,
				UpdatedAt = os.time(),
			}
		end)
	end)
	if not ok then
		DebugModule.debugWarn(
			"Receipt reservation failed for purchaseId=" .. receiptId .. ": " .. tostring(record),
			MODULE_NAME
		)
		return nil
	end

	if typeof(record) ~= "table" then
		return nil
	elseif record.Status == "Granted" then
		cacheGrantedReceipt(receiptId)
		return "Granted"
	elseif record.Status == "Processing" and record.JobId == receiptJobId then
		return "Reserved"
	end

	return "Busy"
end

local function releaseReceipt(receiptId: string)
	local ok, err = pcall(function()
		receiptStore:UpdateAsync("receipt_" .. receiptId, function(previous)
			if typeof(previous) == "table" and previous.Status == "Processing" and previous.JobId == receiptJobId then
				return {
					Status = "Retry",
					UpdatedAt = os.time(),
				}
			end
			return previous
		end)
	end)
	if not ok then
		DebugModule.debugWarn(
			"Receipt reservation release failed for purchaseId=" .. receiptId .. ": " .. tostring(err),
			MODULE_NAME
		)
	end
end

local function rememberGrantedReceipt(receiptId: string, player: Player, productId: number): boolean
	local ok, err = pcall(function()
		receiptStore:UpdateAsync("receipt_" .. receiptId, function(previous)
			if typeof(previous) == "table" and previous.Status == "Granted" then
				return previous
			end

			return {
				Status = "Granted",
				PlayerId = player.UserId,
				ProductId = productId,
				GrantedAt = os.time(),
			}
		end)
	end)

	if not ok then
		DebugModule.debugWarn(
			"Receipt history save failed for purchaseId=" .. receiptId .. ": " .. tostring(err),
			MODULE_NAME
		)
		return false
	end

	cacheGrantedReceipt(receiptId)
	return true
end

local function snapshotSavedAttributes(player: Player): { [string]: any }
	local snapshot: { [string]: any } = {}
	for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
		snapshot[entry.name] = player:GetAttribute(entry.name)
	end
	return snapshot
end

local function restoreSavedAttributes(player: Player, snapshot: { [string]: any })
	for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
		player:SetAttribute(entry.name, snapshot[entry.name])
	end
end

function ProductServerService.GrantCreatorDeveloperProduct(player: Player, productId: number): (boolean, string)
	if typeof(productId) ~= "number" or productId <= 0 or productId ~= math.floor(productId) then
		return false, "InvalidProductId"
	end
	if not isExperienceCreator(player) then
		return false, "NotCreator"
	end
	if player.Parent == nil then
		return false, "PlayerUnavailable"
	end
	if serviceShuttingDown then
		return false, "ServiceShuttingDown"
	end
	if not isDataLoaded(player) then
		return false, "DataNotLoaded"
	end
	if creatorGrantLocks[player] then
		return false, "GrantInFlight"
	end
	if not isCanonicalDeveloperProduct(productId) then
		return false, "UnknownProduct"
	end

	local callback = devProductCallbacks[productId]
	if not callback then
		return false, "ProductNotRegistered"
	end

	creatorGrantLocks[player] = true
	local attributeSnapshot = snapshotSavedAttributes(player)
	local callbackOk, callbackResult, callbackReason = pcall(
		callback,
		player,
		productId,
		true,
		nil,
		nil,
		"CreatorGrant"
	)
	if not callbackOk then
		restoreSavedAttributes(player, attributeSnapshot)
		creatorGrantLocks[player] = nil
		DebugModule.debugWarn(
			"Creator developer product callback failed | player="
				.. player.Name
				.. " | productId="
				.. tostring(productId)
				.. " | err="
				.. tostring(callbackResult),
			MODULE_NAME
		)
		return false, "CallbackFailed"
	end
	if callbackResult == false then
		restoreSavedAttributes(player, attributeSnapshot)
		creatorGrantLocks[player] = nil
		local rejectionReason = if typeof(callbackReason) == "string" then callbackReason else "CallbackRejected"
		DebugModule.debugWarn(
			"Creator developer product callback rejected | player="
				.. player.Name
				.. " | productId="
				.. tostring(productId)
				.. " | reason="
				.. rejectionReason,
			MODULE_NAME
		)
		return false, rejectionReason
	end

	local saved = ProductServerService.SavePlayerData(player, true)
	if not saved then
		restoreSavedAttributes(player, attributeSnapshot)
		creatorGrantLocks[player] = nil
		DebugModule.debugWarn(
			"Creator developer product grant rolled back because save failed | player="
				.. player.Name
				.. " | productId="
				.. tostring(productId),
			MODULE_NAME
		)
		return false, "SaveFailed"
	end

	creatorGrantLocks[player] = nil
	DebugModule.debugInfo(
		"Creator developer product granted | player=" .. player.Name .. " | productId=" .. tostring(productId),
		MODULE_NAME
	)
	return true, "Granted"
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not isDataLoaded(player) then
		DebugModule.debugWarn(
			"Receipt deferred until player data loads | player="
				.. player.Name
				.. " | productId="
				.. tostring(info.ProductId),
			MODULE_NAME
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptId = getReceiptId(info)
	if not receiptId then
		DebugModule.debugWarn("Developer product receipt had no PurchaseId", MODULE_NAME)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if info.ProductPurchaseChannel == Enum.ProductPurchaseChannel.AdReward then
		DebugModule.debugInfo(
			"Processing rewarded-video product receipt | playerId="
				.. tostring(info.PlayerId)
				.. " | productId="
				.. tostring(info.ProductId),
			MODULE_NAME
		)
	end

	if processingReceipts[receiptId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local receiptState = reserveReceipt(receiptId, player, info.ProductId)
	if receiptState == nil or receiptState == "Busy" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	elseif receiptState == "Granted" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	processingReceipts[receiptId] = true

	local cb = devProductCallbacks[info.ProductId]
	if not cb then
		DebugModule.debugWarn(
			"No dev product callback registered for productId=" .. tostring(info.ProductId),
			MODULE_NAME
		)
		processingReceipts[receiptId] = nil
		releaseReceipt(receiptId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local alreadyPersisted = hasProcessedProfileReceipt(player, receiptId)
	if not alreadyPersisted then
		local attributeSnapshot = snapshotSavedAttributes(player)
		local callbackOk, callbackResult, callbackReason = pcall(
			cb,
			player,
			info.ProductId,
			true,
			receiptId,
			info.ProductPurchaseChannel
		)
		if not callbackOk then
			restoreSavedAttributes(player, attributeSnapshot)
			processingReceipts[receiptId] = nil
			releaseReceipt(receiptId)
			DebugModule.debugWarn(
				"Dev product callback failed for player "
					.. player.Name
					.. " productId="
					.. tostring(info.ProductId)
					.. " err="
					.. tostring(callbackResult),
				MODULE_NAME
			)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		if callbackResult == false then
			restoreSavedAttributes(player, attributeSnapshot)
			processingReceipts[receiptId] = nil
			releaseReceipt(receiptId)
			DebugModule.debugWarn(
				"Dev product callback rejected; receipt will retry | player="
					.. player.Name
					.. " | productId="
					.. tostring(info.ProductId)
					.. " | reason="
					.. tostring(callbackReason),
				MODULE_NAME
			)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		markProcessedProfileReceipt(player, receiptId)
	end

	if not ProductServerService.SavePlayerData(player, true) then
		processingReceipts[receiptId] = nil
		releaseReceipt(receiptId)
		DebugModule.debugWarn(
			"Receipt reward awaiting durable profile save | player="
				.. player.Name
				.. " | productId="
				.. tostring(info.ProductId)
				.. " | purchaseId="
				.. receiptId,
			MODULE_NAME
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not rememberGrantedReceipt(receiptId, player, info.ProductId) then
		processingReceipts[receiptId] = nil
		releaseReceipt(receiptId)
		DebugModule.debugWarn(
			"Receipt reward saved but receipt finalization is pending | player="
				.. player.Name
				.. " | purchaseId="
				.. receiptId,
			MODULE_NAME
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	processingReceipts[receiptId] = nil

	local itemInfo = getMarketplaceInfoCached(info.ProductId, Enum.InfoType.Product)
	if itemInfo and not alreadyPersisted then
		SystemChatService.BroadcastPurchase(
			player,
			itemInfo.Name,
			itemInfo.PriceInRobux or 0,
			nil,
			"Product:" .. receiptId
		)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ProductServerService.Init()
	if isInitialized then
		return
	end
	isInitialized = true
	serviceShuttingDown = false

	MarketplaceService.ProcessReceipt = processReceipt

	serviceMaid.GamePassPurchaseFinished = MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player, id, bought)
			local purchaseCompleted = bought == true
			local resolvedBought = purchaseCompleted
			if purchaseCompleted then
				ProductService.SetGamePassOwnershipCache(player, id, true)
			else
				ProductService.ClearOwnershipCache(player)
				resolvedBought = ProductService.userOwnsGamePass(player, id)
				if resolvedBought then
					ProductService.SetGamePassOwnershipCache(player, id, true)
				end
			end

			local cb = gamePassCallbacks[id]
			if cb then
				pcall(cb, player, id, resolvedBought)
			end
			if purchaseCompleted then
				local itemInfo = getMarketplaceInfoCached(id, Enum.InfoType.GamePass)
				local playerAnnouncements = announcedGamePasses[player]
				if not playerAnnouncements then
					playerAnnouncements = {}
					announcedGamePasses[player] = playerAnnouncements
				end
				if itemInfo and not playerAnnouncements[id] then
					SystemChatService.BroadcastPurchase(
						player,
						itemInfo.Name,
						itemInfo.PriceInRobux or 0,
						nil,
						"GamePass:" .. tostring(player.UserId) .. ":" .. tostring(id)
					)
					playerAnnouncements[id] = true
				end
				ProductServerService.SavePlayerData(player)
			end
		end
	)

	serviceMaid.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
		heartbeatTokens[player] = nil
		heartbeatInFlight[player] = nil
		cancelPendingSaveThread(player)
		lastSaveTimes[player] = nil
		creatorGrantLocks[player] = nil
	end)
	startSessionLockHeartbeat()
end

function ProductServerService.Shutdown()
	if not isInitialized then
		return
	end

	ProductServerService.PrepareForShutdown()
	serviceMaid:DoCleaning()
	isInitialized = false
	DebugModule.debugPrint("ProductServerService shutdown", MODULE_NAME)
end

return ProductServerService
