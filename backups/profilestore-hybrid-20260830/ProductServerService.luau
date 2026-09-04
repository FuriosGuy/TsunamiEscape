--!strict
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local shutdownBound = false
local PLAYER_STORE_NAME = ProductService.DataStores["PlayerStats"]
local PROFILE_REGISTRY_STORE_NAME = ProductService.DataStores["ProfileRegistry"]
local playerStore = DataStoreService:GetDataStore(PLAYER_STORE_NAME)
local receiptStore = DataStoreService:GetDataStore("ProcessedDevProductReceipts_v1")
local profileRegistryStore = DataStoreService:GetDataStore(PROFILE_REGISTRY_STORE_NAME)
local RECEIPT_RESERVATION_LEASE_SECONDS = 120
local receiptJobId = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(os.clock()))
local profileRegistryJobId = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(os.clock()))
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

-- STATE
type StoredPlayerData = { [string]: any }
type StoredDataMutator = (data: StoredPlayerData) -> StoredPlayerData
type LoadResult = "Loaded" | "New" | "Failed"
type ProfileMarker = {
	MarkerId: string,
	UserId: number,
	UniverseId: number,
	RegisteredAt: number,
}

local lastSaveTimes: { [number]: number } = {}
local pendingSaveTasks: { [number]: boolean } = {}
local pendingSaveThreads: { [number]: thread } = {}
local saveGenerations: { [number]: number } = {}
local loadStates: { [number]: "Loading" | "Loaded" | "Failed" } = {}
local loadedRevisions: { [number]: number } = {}
local profileMarkersRegistered: { [number]: boolean } = {}
local blockedSaveWarnings: { [number]: boolean } = {}
local devProductCallbacks: { [number]: (...any) -> () } = {}
local gamePassCallbacks: { [number]: (...any) -> () } = {}
local marketplaceInfoCache: { [string]: any } = {}
local processingReceipts: { [string]: boolean } = {}
local grantedReceipts: { [string]: boolean } = {}
local grantedReceiptOrder: { string } = {}
local serviceMaid = Maid.new()

local function dataKeyForUserId(userId: number): string
	return "player_" .. tostring(userId)
end

local function dataKey(player: Player): string
	return dataKeyForUserId(player.UserId)
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
	local thread = pendingSaveThreads[userId]
	pendingSaveThreads[userId] = nil
	pendingSaveTasks[userId] = nil
	saveGenerations[userId] = (saveGenerations[userId] or 0) + 1

	if thread then
		if coroutine.status(thread) ~= "dead" then
			local ok, err = pcall(task.cancel, thread)
			if not ok and coroutine.status(thread) ~= "dead" then
				DebugModule.debugWarn(
					"Pending save cancellation failed | userId=" .. tostring(userId) .. " | err=" .. tostring(err),
					MODULE_NAME
				)
			end
		end
	end
end

local function isDataLoaded(player: Player): boolean
	if player:GetAttribute("Data_Loaded") ~= true then
		return false
	end

	local state = loadStates[player.UserId]
	return state == nil or state == "Loaded"
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

function ProductServerService.SavePlayerData(player: Player, forceSave: boolean?): boolean
	local userId = player.UserId
	local isForcedSave = forceSave == true
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

	local now = os.clock()
	local lastSave = lastSaveTimes[userId] or 0
	local expectedRevision = loadedRevisions[userId]

	local function perform(): boolean
		if (player.Parent == nil and not isForcedSave) or not isDataLoaded(player) then
			return false
		end

		local data: StoredPlayerData = {}
		for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
			local val = player:GetAttribute(entry.name)
			data[entry.name] = if val ~= nil then val else entry.default
		end
		local revisionConflict = false
		local savedData: any = nil
		local ok, err = pcall(function()
			savedData = playerStore:UpdateAsync(dataKey(player), function(existingData)
				local nextData: StoredPlayerData = if typeof(existingData) == "table"
					then table.clone(existingData)
					else {}
				local currentRevision = if typeof(nextData.DataRevision) == "number"
					then math.max(0, math.floor(nextData.DataRevision))
					else 0
				if expectedRevision ~= nil and currentRevision > expectedRevision then
					revisionConflict = true
					return nextData
				end
				for name, value in pairs(data) do
					nextData[name] = value
				end
				nextData.DataRevision = currentRevision + 1
				return nextData
			end)
		end)
		if ok and not revisionConflict then
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
			DebugModule.debugPrint(
				"Saved player data | player="
					.. player.Name
					.. " | universeId="
					.. tostring(game.GameId)
					.. " | store="
					.. PLAYER_STORE_NAME
					.. " | key="
					.. dataKey(player)
					.. " | revision="
					.. tostring(loadedRevisions[userId])
					.. " | force="
					.. tostring(forceSave == true),
				MODULE_NAME
			)
		elseif ok and revisionConflict then
			DebugModule.debugWarn(
				"Save rejected because newer revision exists | player="
					.. player.Name
					.. " | expectedRevision="
					.. tostring(expectedRevision),
				MODULE_NAME
			)
		else
			DebugModule.debugWarn("Save failed | player=" .. player.Name .. " | err=" .. tostring(err), MODULE_NAME)
		end
		return ok
	end

	if forceSave then
		cancelPendingSaveThread(userId)
		for attempt = 1, FINAL_SAVE_RETRY_ATTEMPTS do
			if perform() then
				return true
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
		perform()
	end)
	return true
end

function ProductServerService.LoadPlayerData(player: Player): LoadResult
	local userId = player.UserId
	loadStates[userId] = "Loading"
	local ok = false
	local data: any = nil
	local dataKeyInfo: any = nil
	local lastError: any = nil

	for attempt = 1, LOAD_RETRY_ATTEMPTS do
		if player.Parent == nil then
			loadStates[userId] = "Failed"
			return "Failed"
		end

		ok, data, dataKeyInfo = pcall(function()
			return playerStore:GetAsync(dataKey(player))
		end)
		if ok then
			break
		end

		lastError = data
		DebugModule.debugWarn(
			"Load attempt failed | player="
				.. player.Name
				.. " | universeId="
				.. tostring(game.GameId)
				.. " | store="
				.. PLAYER_STORE_NAME
				.. " | key="
				.. dataKey(player)
				.. " | attempt="
				.. tostring(attempt)
				.. "/"
				.. tostring(LOAD_RETRY_ATTEMPTS)
				.. " | err="
				.. tostring(lastError),
			MODULE_NAME
		)
		if attempt < LOAD_RETRY_ATTEMPTS then
			task.wait(LOAD_RETRY_DELAY_SECONDS * attempt)
		end
	end

	if not ok then
		loadStates[userId] = "Failed"
		DebugModule.debugWarn(
			"Load failed after retries; player remains unsaveable | player=" .. player.Name,
			MODULE_NAME
		)
		return "Failed"
	end

	if data ~= nil and typeof(data) ~= "table" then
		loadStates[userId] = "Failed"
		DebugModule.debugWarn(
			"Load returned malformed data; player remains unsaveable | player=" .. player.Name,
			MODULE_NAME
		)
		return "Failed"
	end

	local loadResult: LoadResult = "Loaded"
	if data == nil then
		loadResult = classifyMissingProfile(userId)
		if loadResult == "Failed" then
			loadStates[userId] = loadResult
			DebugModule.debugWarn(
				"Missing player data requires safe recovery handling | player="
					.. player.Name
					.. " | universeId="
					.. tostring(game.GameId)
					.. " | store="
					.. PLAYER_STORE_NAME
					.. " | key="
					.. dataKey(player)
					.. " | result="
					.. loadResult,
				MODULE_NAME
			)
			return loadResult
		end
		DebugModule.debugInfo(
			"Missing player data accepted as first profile after registration check | player=" .. player.Name,
			MODULE_NAME
		)
	else
		-- Existing data remains playable even if the auxiliary marker cannot be written.
		registerExistingProfile(userId)
	end

	if typeof(data) == "table" then
		for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
			local saved = data[entry.name]
			if saved == nil then
				continue
			end

			if typeof(entry.default) == "number" and typeof(saved) == "number" then
				local cur = player:GetAttribute(entry.name)
				if typeof(cur) ~= "number" or saved > cur then
					player:SetAttribute(entry.name, saved)
				end
			else
				player:SetAttribute(entry.name, saved)
			end
		end
	end

	loadStates[userId] = loadResult
	loadedRevisions[userId] = if typeof(data) == "table" and typeof(data.DataRevision) == "number"
		then math.max(0, math.floor(data.DataRevision))
		else 0
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
	DebugModule.debugPrint(
		"Load succeeded | player="
			.. player.Name
			.. " | universeId="
			.. tostring(game.GameId)
			.. " | store="
			.. PLAYER_STORE_NAME
			.. " | key="
			.. dataKey(player)
			.. " | version="
			.. loadedVersion
			.. " | revision="
			.. tostring(loadedRevisions[userId])
			.. " | status="
			.. loadResult,
		MODULE_NAME
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

	local ok, err = pcall(function()
		playerStore:UpdateAsync(dataKeyForUserId(userId), function(existingData)
			local nextData: StoredPlayerData = if typeof(existingData) == "table" then table.clone(existingData) else {}
			local updatedData = mutator(nextData)
			if typeof(updatedData) ~= "table" then
				assert(false, "Stored data mutator must return a table")
			end
			local currentRevision = if typeof(updatedData.DataRevision) == "number"
				then math.max(0, math.floor(updatedData.DataRevision))
				else 0
			updatedData.DataRevision = currentRevision + 1
			return updatedData
		end)
	end)
	if not ok then
		DebugModule.debugWarn(
			"Stored player update failed | userId=" .. tostring(userId) .. " | err=" .. tostring(err),
			MODULE_NAME
		)
		return false
	end

	DebugModule.debugPrint("Stored player update succeeded | userId=" .. tostring(userId), MODULE_NAME)
	return true
end

function ProductServerService.CleanupPlayerState(player: Player)
	local userId = player.UserId
	cancelPendingSaveThread(userId)
	lastSaveTimes[userId] = nil
	loadStates[userId] = nil
	loadedRevisions[userId] = nil
	profileMarkersRegistered[userId] = nil
	blockedSaveWarnings[userId] = nil
	saveGenerations[userId] = nil
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
	end

	cacheGrantedReceipt(receiptId)
	return ok
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if player:GetAttribute("Data_Loaded") ~= true then
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

	local callbackOk, callbackErr = pcall(cb, player, info.ProductId, true, receiptId, info.ProductPurchaseChannel)
	if not callbackOk then
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

	rememberGrantedReceipt(receiptId, player, info.ProductId)
	processingReceipts[receiptId] = nil

	local itemInfo = getMarketplaceInfoCached(info.ProductId, Enum.InfoType.Product)
	if itemInfo then
		SystemChatService.BroadcastPurchase(player, itemInfo.Name, itemInfo.PriceInRobux or 0)
	end

	ProductServerService.SavePlayerData(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function ProductServerService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

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

	if not shutdownBound then
		shutdownBound = true
		game:BindToClose(function()
			ProductServerService.Shutdown()
		end)
	end
end

function ProductServerService.Shutdown()
	if not isInitialized then
		return
	end

	for userId in pairs(pendingSaveThreads) do
		cancelPendingSaveThread(userId)
	end
	serviceMaid:DoCleaning()
	isInitialized = false
	DebugModule.debugPrint("ProductServerService shutdown", MODULE_NAME)
end

return ProductServerService
