--!strict
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

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
local PROFILE_REGISTRY_STORE_NAME = ProductService.DataStores["ProfileRegistry"]
local playerStore = DataStoreService:GetDataStore(PLAYER_STORE_NAME)
local receiptStore = DataStoreService:GetDataStore("ProcessedDevProductReceipts_v1")
local profileRegistryStore = DataStoreService:GetDataStore(PROFILE_REGISTRY_STORE_NAME)
local RECEIPT_RESERVATION_LEASE_SECONDS = 120
local serverLockIdentity = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))
local receiptJobId = serverLockIdentity
local profileRegistryJobId = serverLockIdentity
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
local SESSION_LOCK_LEASE_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.sessionLockLeaseSeconds) == "number"
	then math.max(30, math.floor(persistenceConfig.sessionLockLeaseSeconds))
	else 180
local STUDIO_SESSION_LOCK_LEASE_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.studioSessionLockLeaseSeconds) == "number"
	then math.max(5, math.floor(persistenceConfig.studioSessionLockLeaseSeconds))
	else 30
local EFFECTIVE_SESSION_LOCK_LEASE_SECONDS = if RunService:IsStudio()
	then STUDIO_SESSION_LOCK_LEASE_SECONDS
	else SESSION_LOCK_LEASE_SECONDS
local SESSION_LOCK_ACQUIRE_TIMEOUT_SECONDS = if RunService:IsStudio()
		and persistenceConfig
		and typeof(persistenceConfig.studioSessionLockAcquireTimeoutSeconds) == "number"
	then math.max(1, persistenceConfig.studioSessionLockAcquireTimeoutSeconds)
	else if persistenceConfig
		and typeof(persistenceConfig.sessionLockAcquireTimeoutSeconds) == "number"
	then math.max(1, persistenceConfig.sessionLockAcquireTimeoutSeconds)
	else 20
local SESSION_LOCK_RETRY_DELAY_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.sessionLockRetryDelaySeconds) == "number"
	then math.max(0.1, persistenceConfig.sessionLockRetryDelaySeconds)
	else 1
local DURABLE_RECEIPT_HISTORY_LIMIT = if persistenceConfig
		and typeof(persistenceConfig.durableReceiptHistoryLimit) == "number"
	then math.max(1, math.floor(persistenceConfig.durableReceiptHistoryLimit))
	else 128
local DEBUG_VERBOSE = persistenceConfig and persistenceConfig.debugVerbose == true

-- STATE
type StoredPlayerData = { [string]: any }
type StoredDataMutator = (data: StoredPlayerData) -> StoredPlayerData
type LoadResult = "Loaded" | "New" | "Failed"
type LoadState = "Loading" | LoadResult
type SessionAcquireResult = "Acquired" | "Locked" | "Malformed" | "Failed"
type Metadata = { [string]: any }
type ProfileMarker = {
	MarkerId: string,
	UserId: number,
	UniverseId: number,
	RegisteredAt: number,
}

local lastSaveTimes: { [number]: number } = {}
local pendingSaveTasks: { [number]: boolean } = {}
local pendingSaveThreads: { [number]: thread } = {}
local activeSaveLocks: { [number]: boolean } = {}
local saveGenerations: { [number]: number } = {}
local loadStates: { [number]: LoadState } = {}
local loadedRevisions: { [number]: number } = {}
local sessionLockIds: { [number]: string } = {}
local invalidatedSessions: { [number]: boolean } = {}
local profileMarkersRegistered: { [number]: boolean } = {}
local blockedSaveWarnings: { [number]: boolean } = {}
local devProductCallbacks: { [number]: (...any) -> () } = {}
local gamePassCallbacks: { [number]: (...any) -> () } = {}
local marketplaceInfoCache: { [string]: any } = {}
local processingReceipts: { [string]: boolean } = {}
local grantedReceipts: { [string]: boolean } = {}
local grantedReceiptOrder: { string } = {}
local processedProfileReceipts: { [number]: { [string]: boolean } } = {}
local processedProfileReceiptOrder: { [number]: { string } } = {}
local serviceMaid = Maid.new()
local serviceShuttingDown = false

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
	return os.time() - math.floor(updatedAt) < EFFECTIVE_SESSION_LOCK_LEASE_SECONDS
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

local function sessionLockIdForUser(userId: number): string
	return serverLockIdentity .. ":" .. tostring(userId)
end

local function loadProcessedReceiptHistory(userId: number, data: StoredPlayerData?)
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
	processedProfileReceipts[userId] = receiptSet
	processedProfileReceiptOrder[userId] = receiptOrder
end

local function hasProcessedProfileReceipt(userId: number, receiptId: string): boolean
	local receiptSet = processedProfileReceipts[userId]
	return receiptSet ~= nil and receiptSet[receiptId] == true
end

local function markProcessedProfileReceipt(userId: number, receiptId: string)
	local receiptSet = processedProfileReceipts[userId]
	local receiptOrder = processedProfileReceiptOrder[userId]
	if receiptSet == nil or receiptOrder == nil then
		receiptSet = {}
		receiptOrder = {}
		processedProfileReceipts[userId] = receiptSet
		processedProfileReceiptOrder[userId] = receiptOrder
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

	local receiptOrder = processedProfileReceiptOrder[player.UserId] or {}
	data[PROCESSED_RECEIPTS_FIELD] = table.clone(receiptOrder)
	data[PROFILE_INITIALIZED_FIELD] = true
	return data
end

local function createProfileMarker(userId: number): "Created" | "Existing" | "Failed"
	local markerId = profileRegistryJobId .. ":" .. tostring(userId)
	local marker: ProfileMarker = {
		MarkerId = markerId,
		UserId = userId,
		UniverseId = game.GameId,
		RegisteredAt = os.time(),
	}

	local ok, storedMarker = pcall(function()
		return profileRegistryStore:UpdateAsync(dataKeyForUserId(userId), function(existingMarker)
			if existingMarker ~= nil then
				return existingMarker
			end
			return marker
		end)
	end)
	if not ok then
		DebugModule.debugWarn(
			"Profile marker write failed | userId=" .. tostring(userId) .. " | err=" .. tostring(storedMarker),
			MODULE_NAME
		)
		return "Failed"
	end

	if typeof(storedMarker) == "table" and storedMarker.MarkerId == markerId then
		return "Created"
	end
	return if storedMarker ~= nil then "Existing" else "Failed"
end

local function registerExistingProfile(userId: number): boolean
	local ok, existingMarker = pcall(function()
		return profileRegistryStore:GetAsync(dataKeyForUserId(userId))
	end)
	if not ok then
		DebugModule.debugWarn(
			"Profile marker read failed for existing profile | userId="
				.. tostring(userId)
				.. " | err="
				.. tostring(existingMarker),
			MODULE_NAME
		)
		return false
	end

	if existingMarker ~= nil then
		profileMarkersRegistered[userId] = true
		return true
	end

	local result = createProfileMarker(userId)
	if result == "Failed" then
		DebugModule.debugWarn(
			"Existing profile loaded without registration marker | userId=" .. tostring(userId),
			MODULE_NAME
		)
		return false
	end
	profileMarkersRegistered[userId] = true
	return true
end

local function classifyMissingProfile(userId: number): "New" | "Failed"
	local ok, existingMarker = pcall(function()
		return profileRegistryStore:GetAsync(dataKeyForUserId(userId))
	end)
	if not ok then
		DebugModule.debugWarn(
			"Profile marker read failed for missing profile | userId="
				.. tostring(userId)
				.. " | err="
				.. tostring(existingMarker),
			MODULE_NAME
		)
		return "Failed"
	end

	if existingMarker ~= nil then
		-- Older builds registered this marker before the first stats write. Treat
		-- that marker-only state as a fresh profile instead of kicking the player.
		profileMarkersRegistered[userId] = true
		DebugModule.debugWarn(
			"Missing player data with existing profile marker; resetting to defaults | userId="
				.. tostring(userId),
			MODULE_NAME
		)
		return "New"
	end

	-- Do not mark a profile as established before its first stats write.
	-- Otherwise an interrupted first session becomes a false recovery case.
	profileMarkersRegistered[userId] = false
	return "New"
end

local function cancelPendingSaveThread(userId: number)
	-- In-flight UpdateAsync calls must finish; generation invalidation cancels delayed work safely.
	pendingSaveThreads[userId] = nil
	pendingSaveTasks[userId] = nil
	saveGenerations[userId] = (saveGenerations[userId] or 0) + 1
end

local function invalidateSession(player: Player, reason: string)
	local userId = player.UserId
	if invalidatedSessions[userId] or player.Parent == nil then
		return
	end

	invalidatedSessions[userId] = true
	player:SetAttribute("Data_Loaded", false)
	DebugModule.debugWarn(
		"Persistence session invalidated | player=" .. player.Name .. " | userId=" .. tostring(userId) .. " | reason=" .. reason,
		MODULE_NAME
	)
	task.defer(function()
		if player.Parent then
			player:Kick("Your saved data session changed. Please rejoin.")
		end
	end)
end

local function releaseSessionLock(player: Player, reason: string): boolean
	local userId = player.UserId
	local lockId = sessionLockIds[userId]
	if lockId == nil then
		return true
	end

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
	if not ok then
		DebugModule.debugWarn(
			"Session lock release failed | player="
				.. player.Name
				.. " | reason="
				.. reason
				.. " | err="
				.. tostring(err),
			MODULE_NAME
		)
		return false
	end
	if not released then
		DebugModule.debugWarn(
			"Session lock release skipped because ownership changed | player=" .. player.Name .. " | reason=" .. reason,
			MODULE_NAME
		)
		return false
	end

	sessionLockIds[userId] = nil
	debugVerbose("Session lock released | player=" .. player.Name .. " | reason=" .. reason)
	return true
end

local function acquireSessionLock(player: Player): (SessionAcquireResult, StoredPlayerData?, any?, boolean, string?)
	local userId = player.UserId
	local desiredLockId = sessionLockIdForUser(userId)
	local result: SessionAcquireResult = "Failed"
	local createdNew = false
	local storedData: any = nil
	local storedKeyInfo: any = nil

	local ok, err = pcall(function()
		storedData, storedKeyInfo = playerStore:UpdateAsync(dataKey(player), function(existingData, keyInfo)
			local metadata = cloneMetadata(keyInfo)
			if isSessionLockActive(metadata, desiredLockId) then
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
				else { DataRevision = 0, [PROFILE_INITIALIZED_FIELD] = false }
			setSessionLockMetadata(metadata, desiredLockId)
			result = "Acquired"
			return nextData, cloneUserIds(keyInfo), metadata
		end)
	end)
	if not ok then
		return "Failed", nil, nil, false, tostring(err)
	end
	if result ~= "Acquired" or typeof(storedData) ~= "table" then
		return result, nil, storedKeyInfo, false, nil
	end

	sessionLockIds[userId] = desiredLockId
	return "Acquired", storedData, storedKeyInfo, createdNew, nil
end

local function isDataLoaded(player: Player): boolean
	if player:GetAttribute("Data_Loaded") ~= true then
		return false
	end

	local state = loadStates[player.UserId]
	return state == nil or state == "Loaded" or state == "New"
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

function ProductServerService.SavePlayerData(player: Player, forceSave: boolean?, releaseLock: boolean?): boolean
	local userId = player.UserId
	local isForcedSave = forceSave == true
	local shouldReleaseLock = releaseLock == true
	local dataLoaded = isDataLoaded(player)
	local isPlayerParented = player.Parent ~= nil
	if (not isPlayerParented and not isForcedSave) or not dataLoaded then
		if not blockedSaveWarnings[userId] then
			blockedSaveWarnings[userId] = true
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
	if sessionLockIds[userId] == nil then
		DebugModule.debugWarn(
			"Save blocked because session lock is missing | player=" .. player.Name .. " | force=" .. tostring(isForcedSave),
			MODULE_NAME
		)
		return false
	end
	if shouldReleaseLock and not isForcedSave then
		DebugModule.debugWarn("Save blocked because lock release requires force save | player=" .. player.Name, MODULE_NAME)
		return false
	end

	local now = os.clock()
	local lastSave = lastSaveTimes[userId] or 0
	local expectedRevision = loadedRevisions[userId]
	local hardSessionFailure = false

	local function perform(expectedGeneration: number?): boolean
		if (player.Parent == nil and not isForcedSave) or not isDataLoaded(player) then
			return false
		end
		if expectedGeneration ~= nil and saveGenerations[userId] ~= expectedGeneration then
			return false
		end
		if activeSaveLocks[userId] then
			return false
		end
		activeSaveLocks[userId] = true

		local data = createStoredDataSnapshot(player)
		local revisionConflict = false
		local sessionLockLost = false
		local staleGeneration = false
		local savedData: any = nil
		local ok, err = pcall(function()
			savedData = playerStore:UpdateAsync(dataKey(player), function(existingData, keyInfo)
				if expectedGeneration ~= nil and saveGenerations[userId] ~= expectedGeneration then
					staleGeneration = true
					return nil
				end
				if typeof(existingData) ~= "table" then
					sessionLockLost = true
					return nil
				end

				local metadata = cloneMetadata(keyInfo)
				if metadata[SESSION_LOCK_ID_METADATA_KEY] ~= sessionLockIds[userId] then
					sessionLockLost = true
					return nil
				end
				local nextData: StoredPlayerData = if typeof(existingData) == "table"
					then table.clone(existingData)
					else {}
				local currentRevision = if typeof(nextData.DataRevision) == "number"
					then math.max(0, math.floor(nextData.DataRevision))
					else 0
				if expectedRevision ~= nil and currentRevision > expectedRevision then
					revisionConflict = true
					return nil
				end
				for name, value in pairs(data) do
					nextData[name] = value
				end
				nextData.DataRevision = currentRevision + 1
				if shouldReleaseLock then
					setSessionLockMetadata(metadata, nil)
				else
					setSessionLockMetadata(metadata, sessionLockIds[userId])
				end
				return nextData, cloneUserIds(keyInfo), metadata
			end)
		end)
		activeSaveLocks[userId] = nil
		if staleGeneration then
			return false
		end
		if revisionConflict then
			hardSessionFailure = true
			DebugModule.debugWarn(
				"Save rejected because newer revision exists | player="
					.. player.Name
					.. " | expectedRevision="
					.. tostring(expectedRevision),
				MODULE_NAME
			)
			invalidateSession(player, "RevisionConflict")
			return false
		end
		if sessionLockLost then
			hardSessionFailure = true
			DebugModule.debugWarn("Save rejected because session lock ownership changed | player=" .. player.Name, MODULE_NAME)
			invalidateSession(player, "SessionLockLost")
			return false
		end
		if not ok then
			DebugModule.debugWarn("Save failed | player=" .. player.Name .. " | err=" .. tostring(err), MODULE_NAME)
			return false
		end

		if profileMarkersRegistered[userId] ~= true then
			local markerResult = createProfileMarker(userId)
			if markerResult == "Failed" then
				DebugModule.debugWarn(
					"Player data saved but profile marker registration is pending | player=" .. player.Name,
					MODULE_NAME
				)
			else
				profileMarkersRegistered[userId] = true
			end
		end
		lastSaveTimes[userId] = os.clock()
		if typeof(savedData) == "table" and typeof(savedData.DataRevision) == "number" then
			loadedRevisions[userId] = math.max(0, math.floor(savedData.DataRevision))
		else
			loadedRevisions[userId] = (expectedRevision or 0) + 1
		end
		if shouldReleaseLock then
			sessionLockIds[userId] = nil
		end
		debugVerbose(
			"Saved player data | player="
				.. player.Name
				.. " | revision="
				.. tostring(loadedRevisions[userId])
				.. " | force="
				.. tostring(isForcedSave)
				.. " | released="
				.. tostring(shouldReleaseLock)
		)
		return true
	end

	if forceSave then
		cancelPendingSaveThread(userId)
		local forceGeneration = saveGenerations[userId] or 0
		for attempt = 1, FINAL_SAVE_RETRY_ATTEMPTS do
			expectedRevision = loadedRevisions[userId]
			if perform(forceGeneration) then
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

	if pendingSaveTasks[userId] then
		return true
	end
	local waitTime = math.max(0, SAVE_DEBOUNCE_SECONDS - (now - lastSave))
	pendingSaveTasks[userId] = true
	local generation = saveGenerations[userId] or 0
	pendingSaveThreads[userId] = task.spawn(function()
		if waitTime > 0 then
			task.wait(waitTime)
		end
		if saveGenerations[userId] ~= generation then
			return
		end
		pendingSaveTasks[userId] = nil
		pendingSaveThreads[userId] = nil
		perform(generation)
	end)
	return true
end

function ProductServerService.LoadPlayerData(player: Player): LoadResult
	local userId = player.UserId
	loadStates[userId] = "Loading"
	local data: StoredPlayerData? = nil
	local dataKeyInfo: any = nil
	local createdNew = false
	local deadline = os.clock() + SESSION_LOCK_ACQUIRE_TIMEOUT_SECONDS
	local loadFailures = 0
	local lockWaitLogged = false

	while player.Parent and not serviceShuttingDown and os.clock() < deadline do
		local acquireResult, acquiredData, acquiredKeyInfo, acquiredNew, acquireError = acquireSessionLock(player)
		if acquireResult == "Acquired" then
			data = acquiredData
			dataKeyInfo = acquiredKeyInfo
			createdNew = acquiredNew
			break
		end
		if acquireResult == "Malformed" then
			loadStates[userId] = "Failed"
			DebugModule.debugWarn("Load returned malformed data | player=" .. player.Name, MODULE_NAME)
			return "Failed"
		end
		if acquireResult == "Locked" then
			if not lockWaitLogged then
				lockWaitLogged = true
				DebugModule.debugWarn(
					"Session lock busy; waiting before load | player=" .. player.Name .. " | timeout=" .. tostring(SESSION_LOCK_ACQUIRE_TIMEOUT_SECONDS),
					MODULE_NAME
				)
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

		local remaining = deadline - os.clock()
		if remaining <= 0 then
			break
		end
		task.wait(math.min(remaining, if acquireResult == "Locked" then SESSION_LOCK_RETRY_DELAY_SECONDS else LOAD_RETRY_DELAY_SECONDS))
	end

	if data == nil then
		loadStates[userId] = "Failed"
		DebugModule.debugWarn(
			"Load failed before session lock acquisition | player="
				.. player.Name
				.. " | lockWaited="
				.. tostring(lockWaitLogged)
				.. " | shuttingDown="
				.. tostring(serviceShuttingDown),
			MODULE_NAME
		)
		return "Failed"
	end
	if player.Parent == nil then
		releaseSessionLock(player, "PlayerLeftDuringLoad")
		loadStates[userId] = "Failed"
		return "Failed"
	end

	local classificationResult: LoadResult = if createdNew then classifyMissingProfile(userId) else "Loaded"
	if classificationResult == "Failed" then
		releaseSessionLock(player, "ProfileClassificationFailed")
		loadStates[userId] = "Failed"
		return "Failed"
	end
	if classificationResult == "Loaded" then
		-- Existing data remains playable even if the auxiliary marker cannot be written.
		registerExistingProfile(userId)
	end

	for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
		local saved = data[entry.name]
		if saved == nil then
			continue
		end

		if typeof(entry.default) == "number" and typeof(saved) == "number" then
			local currentValue = player:GetAttribute(entry.name)
			if typeof(currentValue) ~= "number" or saved > currentValue then
				player:SetAttribute(entry.name, saved)
			end
		else
			player:SetAttribute(entry.name, saved)
		end
	end

	local storedRevision = if typeof(data.DataRevision) == "number" then math.max(0, math.floor(data.DataRevision)) else 0
	local requiresInitialProfileSave = createdNew or (data[PROFILE_INITIALIZED_FIELD] ~= true and storedRevision == 0)
	local loadResult: LoadResult = if requiresInitialProfileSave then "New" else "Loaded"
	loadProcessedReceiptHistory(userId, data)
	loadStates[userId] = loadResult
	loadedRevisions[userId] = storedRevision
	blockedSaveWarnings[userId] = nil
	local loadedVersion = "none"
	if dataKeyInfo ~= nil then
		local versionOk, version = pcall(function()
			return dataKeyInfo.Version
		end)
		if versionOk and version ~= nil then
			loadedVersion = tostring(version)
		end
	end
	debugVerbose(
		"Load succeeded | player="
			.. player.Name
			.. " | version="
			.. loadedVersion
			.. " | revision="
			.. tostring(loadedRevisions[userId])
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

	local blockedBySessionLock = false
	local ok, err = pcall(function()
		playerStore:UpdateAsync(dataKeyForUserId(userId), function(existingData, keyInfo)
			local metadata = cloneMetadata(keyInfo)
			if isSessionLockActive(metadata, nil) then
				blockedBySessionLock = true
				return nil
			end
			setSessionLockMetadata(metadata, nil)
			local nextData: StoredPlayerData = if typeof(existingData) == "table" then table.clone(existingData) else {}
			local updatedData = mutator(nextData)
			if typeof(updatedData) ~= "table" then
				assert(false, "Stored data mutator must return a table")
			end
			local currentRevision = if typeof(updatedData.DataRevision) == "number"
				then math.max(0, math.floor(updatedData.DataRevision))
				else 0
			updatedData.DataRevision = currentRevision + 1
			return updatedData, cloneUserIds(keyInfo), metadata
		end)
	end)
	if blockedBySessionLock then
		DebugModule.debugWarn(
			"Offline update blocked by active session lock | userId=" .. tostring(userId),
			MODULE_NAME
		)
		return false
	end
	if not ok then
		DebugModule.debugWarn(
			"Stored player update failed | userId=" .. tostring(userId) .. " | err=" .. tostring(err),
			MODULE_NAME
		)
		return false
	end

	debugVerbose("Stored player update succeeded | userId=" .. tostring(userId))
	return true
end

function ProductServerService.CleanupPlayerState(player: Player)
	local userId = player.UserId
	cancelPendingSaveThread(userId)
	lastSaveTimes[userId] = nil
	loadStates[userId] = nil
	loadedRevisions[userId] = nil
	sessionLockIds[userId] = nil
	invalidatedSessions[userId] = nil
	profileMarkersRegistered[userId] = nil
	blockedSaveWarnings[userId] = nil
	processedProfileReceipts[userId] = nil
	processedProfileReceiptOrder[userId] = nil
	saveGenerations[userId] = nil
end

function ProductServerService.ReleaseSessionLock(player: Player, reason: string?): boolean
	return releaseSessionLock(player, reason or "ExplicitRelease")
end

function ProductServerService.IsShuttingDown(): boolean
	return serviceShuttingDown
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

	local alreadyPersisted = hasProcessedProfileReceipt(player.UserId, receiptId)
	if not alreadyPersisted then
		local attributeSnapshot = snapshotSavedAttributes(player)
		local callbackOk, callbackErr = pcall(cb, player, info.ProductId, true, receiptId, info.ProductPurchaseChannel)
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
					.. tostring(callbackErr),
				MODULE_NAME
			)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		markProcessedProfileReceipt(player.UserId, receiptId)
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
	if itemInfo then
		SystemChatService.BroadcastPurchase(player, itemInfo.Name, itemInfo.PriceInRobux or 0)
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
			local resolvedBought = bought == true
			if resolvedBought then
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
			if resolvedBought then
				local itemInfo = getMarketplaceInfoCached(id, Enum.InfoType.GamePass)
				if itemInfo then
					SystemChatService.BroadcastPurchase(player, itemInfo.Name, itemInfo.PriceInRobux or 0)
				end
				ProductServerService.SavePlayerData(player)
			end
		end
	)

	serviceMaid.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
		cancelPendingSaveThread(player.UserId)
		lastSaveTimes[player.UserId] = nil
	end)

end

function ProductServerService.Shutdown()
	if not isInitialized then
		return
	end

	serviceShuttingDown = true
	for userId in pairs(pendingSaveThreads) do
		cancelPendingSaveThread(userId)
	end
	serviceMaid:DoCleaning()
	isInitialized = false
	DebugModule.debugPrint("ProductServerService shutdown", MODULE_NAME)
end

return ProductServerService
