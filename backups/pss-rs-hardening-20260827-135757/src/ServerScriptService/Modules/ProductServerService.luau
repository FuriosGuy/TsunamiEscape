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
local playerStore = DataStoreService:GetDataStore(ProductService.DataStores["PlayerStats"])
local receiptStore = DataStoreService:GetDataStore("ProcessedDevProductReceipts_v1")
local RECEIPT_RESERVATION_LEASE_SECONDS = 120
local receiptJobId = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(os.clock()))
local persistenceConfig = CoreConfig.persistence
local SAVE_DEBOUNCE_SECONDS = if persistenceConfig and typeof(persistenceConfig.saveDebounceSeconds) == "number"
	then math.max(0, persistenceConfig.saveDebounceSeconds)
	else 10
local FINAL_SAVE_DEBOUNCE_SECONDS = if persistenceConfig
		and typeof(persistenceConfig.finalSaveDebounceSeconds) == "number"
	then
		math.max(0, persistenceConfig.finalSaveDebounceSeconds)
	else
		2

-- STATE
local lastSaveTimes: { [number]: number } = {}
local pendingSaveTasks: { [number]: boolean } = {}
local pendingSaveThreads: { [number]: thread } = {}
local devProductCallbacks: { [number]: (...any) -> () } = {}
local gamePassCallbacks: { [number]: (...any) -> () } = {}
local marketplaceInfoCache: { [string]: any } = {}
local processingReceipts: { [string]: boolean } = {}
local grantedReceipts: { [string]: boolean } = {}
local serviceMaid = Maid.new()

local function dataKey(player: Player): string
	return "player_" .. tostring(player.UserId)
end

local function cancelPendingSaveThread(userId: number)
	local thread = pendingSaveThreads[userId]
	if thread then
		task.cancel(thread)
		pendingSaveThreads[userId] = nil
	end
	pendingSaveTasks[userId] = nil
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

function ProductServerService.SavePlayerData(player: Player, forceSave: boolean?)
	local userId = player.UserId
	local now = os.clock()
	local lastSave = lastSaveTimes[userId] or 0

	local function perform()
		local data = {}
		for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
			local val = player:GetAttribute(entry.name)
			data[entry.name] = if val ~= nil then val else entry.default
		end
		local ok, err = pcall(function()
			playerStore:SetAsync(dataKey(player), data)
		end)
		if ok then
			lastSaveTimes[userId] = os.clock()
			DebugModule.debugPrint("Saved " .. player.Name, MODULE_NAME)
		else
			DebugModule.debugWarn("Save failed: " .. tostring(err), MODULE_NAME)
		end
	end

	if forceSave then
		if now - lastSave < FINAL_SAVE_DEBOUNCE_SECONDS then
			return
		end
		cancelPendingSaveThread(userId)
		perform()
		return
	end

	if pendingSaveTasks[userId] then
		return
	end
	local waitTime = math.max(0, SAVE_DEBOUNCE_SECONDS - (now - lastSave))
	pendingSaveTasks[userId] = true
	pendingSaveThreads[userId] = task.spawn(function()
		if waitTime > 0 then
			task.wait(waitTime)
		end
		pendingSaveTasks[userId] = nil
		pendingSaveThreads[userId] = nil
		if player.Parent then
			perform()
		end
	end)
end

function ProductServerService.LoadPlayerData(player: Player)
	local ok, data = pcall(function()
		return playerStore:GetAsync(dataKey(player))
	end)
	if not ok or typeof(data) ~= "table" then
		return
	end

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

local function reserveReceipt(receiptId: string, player: Player, productId: number): "Granted" | "Reserved" | "Busy" | nil
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
		grantedReceipts[receiptId] = true
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

	grantedReceipts[receiptId] = true
	return ok
end

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
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

	local callbackOk, callbackErr = pcall(
		cb,
		player,
		info.ProductId,
		true,
		receiptId,
		info.ProductPurchaseChannel
	)
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

	serviceMaid.GamePassPurchaseFinished = MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, bought)
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
	end)

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
