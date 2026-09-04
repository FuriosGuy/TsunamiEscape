--!strict
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ProductService = require(Modules:WaitForChild("ProductService"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local SystemChatService = require(Modules:WaitForChild("SystemChatService"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local ProductServerService = {}

-- CONFIG
local MODULE_NAME = "ProductServerService"
local isInitialized = false
local playerStore = DataStoreService:GetDataStore(ProductService.DataStores["PlayerStats"])
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

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local cb = devProductCallbacks[info.ProductId]
	if not cb then
		DebugModule.debugWarn(
			"No dev product callback registered for productId=" .. tostring(info.ProductId),
			MODULE_NAME
		)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local callbackOk, callbackErr = pcall(cb, player, info.ProductId, true, tostring(info.PurchaseId or ""))
	if not callbackOk then
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

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, bought)
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

	Players.PlayerRemoving:Connect(function(player)
		cancelPendingSaveThread(player.UserId)
		lastSaveTimes[player.UserId] = nil
	end)
end

return ProductServerService
