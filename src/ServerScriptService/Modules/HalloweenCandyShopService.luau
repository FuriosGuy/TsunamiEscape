--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local HalloweenCandyShopConfig = require(ReplicatedStorage.Modules.Shared.HalloweenCandyShopConfig)
local HalloweenCandyService = require(script.Parent.HalloweenCandyService)
local Maid = require(ReplicatedStorage.Modules.Maid)
local PlayerHandler = require(script.Parent.Shared.PlayerHandler_Server)

local HalloweenCandyShopService = {}

local MODULE_NAME = "HalloweenCandyShopService"
local REQUEST_COOLDOWN_SECONDS = 0.5
local requestTimes: { [Player]: number } = {}
local inFlight: { [Player]: boolean } = {}
local remote: RemoteEvent? = nil
local maid = Maid.new()
local initialized = false

local function findProduct(productKey: string): HalloweenCandyShopConfig.Product?
	for _, product in ipairs(HalloweenCandyShopConfig.Products) do
		if product.productKey == productKey then
			return product
		end
	end
	return nil
end

local function isPartTwoActive(): boolean
	local state = ReplicatedStorage:FindFirstChild("LiveEventState")
	return state ~= nil and state:GetAttribute("HalloweenPartTwoActive") == true
end

local function ownsProduct(player: Player, product: HalloweenCandyShopConfig.Product): boolean
	if product.kind == "Kart" then
		return PlayerHandler.OwnsKart(player, product.ownedName)
	end
	if product.kind == "Trail" then
		return PlayerHandler.OwnsTrail(player, product.ownedName)
	end
	return false
end

local function sendResult(player: Player, productKey: string, succeeded: boolean, reason: string)
	local resultRemote = remote
	if resultRemote and player.Parent == Players then
		resultRemote:FireClient(player, "Result", productKey, succeeded, reason)
	end
end

local function handlePurchase(player: Player, action: unknown, productKeyValue: unknown)
	if action ~= "Purchase" or typeof(productKeyValue) ~= "string" or #productKeyValue > 40 then
		return
	end
	local product = findProduct(productKeyValue)
	if not product then
		sendResult(player, productKeyValue, false, "InvalidProduct")
		return
	end
	if inFlight[player] then
		return
	end
	local now = os.clock()
	if now - (requestTimes[player] or 0) < REQUEST_COOLDOWN_SECONDS then
		return
	end
	requestTimes[player] = now
	inFlight[player] = true

	local success, reason = pcall(function(): string
		if product.candyPurchasable == false then
			return "NotCandyPurchasable"
		end
		if not isPartTwoActive() then
			return "EventUnavailable"
		end
		if player:GetAttribute("Data_Loaded") ~= true then
			return "DataUnavailable"
		end
		if ownsProduct(player, product) then
			return "AlreadyOwned"
		end
		if not HalloweenCandyService.TrySpendCandy(player, product.candyPrice) then
			return "NotEnoughCandy"
		end

		local granted, grantError = pcall(function()
			if product.kind == "Kart" then
				PlayerHandler.AddOwnedKart(player, product.ownedName)
			else
				PlayerHandler.AddOwnedTrail(player, product.ownedName)
			end
		end)
		if not granted or not ownsProduct(player, product) then
			if not HalloweenCandyService.RefundCandy(player, product.candyPrice) then
				DebugModule.debugWarn("Candy refund failed after grant failure | player=" .. player.Name, MODULE_NAME)
			end
			if not granted then
				DebugModule.debugWarn(
					"Ownership grant failed | player=" .. player.Name .. " | product=" .. product.productKey .. " | error=" .. tostring(grantError),
					MODULE_NAME
				)
			end
			return "GrantFailed"
		end
		return "Purchased"
	end)

	inFlight[player] = nil
	if not success then
		DebugModule.debugWarn("Candy product purchase failed | player=" .. player.Name .. " | error=" .. tostring(reason), MODULE_NAME)
		sendResult(player, product.productKey, false, "PurchaseFailed")
		return
	end
	local resultReason = reason :: string
	sendResult(player, product.productKey, resultReason == "Purchased", resultReason)
end

function HalloweenCandyShopService.Init()
	if initialized then
		return
	end
	initialized = true
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local existing = remotes:FindFirstChild("HalloweenCandyShopPurchase")
	if existing and not existing:IsA("RemoteEvent") then
		initialized = false
		error("HalloweenCandyShopPurchase must be a RemoteEvent")
	end
	local purchaseRemote = existing or Instance.new("RemoteEvent")
	purchaseRemote.Name = "HalloweenCandyShopPurchase"
	purchaseRemote.Parent = remotes
	remote = purchaseRemote :: RemoteEvent
	maid:GiveTask(remote.OnServerEvent:Connect(handlePurchase))
	maid:GiveTask(Players.PlayerRemoving:Connect(function(player: Player)
		requestTimes[player] = nil
		inFlight[player] = nil
	end))
end

function HalloweenCandyShopService.Destroy()
	if remote then
		remote = nil
	end
	maid:DoCleaning()
	table.clear(requestTimes)
	table.clear(inFlight)
	initialized = false
end

return HalloweenCandyShopService
