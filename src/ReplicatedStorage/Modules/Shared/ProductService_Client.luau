--!strict

-- Client-only purchase prompts and local game-pass ownership cache.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ProductCatalog = require(Modules.Shared:WaitForChild("ProductCatalog"))
local SoundService = require(Modules:WaitForChild("SoundService"))
local FunnelAnalytics = require(Modules.Shared:WaitForChild("FunnelAnalytics_Client"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))

local ProductService: { [string]: any } = {}
ProductService.Gamepasses = ProductCatalog.Gamepasses
ProductService.DevProducts = ProductCatalog.DevProducts
ProductService.BloodmoonKartProducts = ProductCatalog.BloodmoonKartProducts
ProductService.MULTIPLIER_TO_PRODUCT = ProductCatalog.MULTIPLIER_TO_PRODUCT

type CreatorPurchaseFinishedCallback = (purchaseKind: string, productId: number, success: boolean, reason: string) -> ()

local ownershipCache: { [number]: { [number]: boolean } } = {}
local creatorPurchaseFinishedCallbacks: { CreatorPurchaseFinishedCallback } = {}
local CreatorPurchaseRequest = Remotes:WaitForChild("CreatorPurchaseRequest") :: RemoteEvent
local CreatorPurchaseResult = Remotes:WaitForChild("CreatorPurchaseResult") :: RemoteEvent

local function resolveUserId(playerOrUserId: Player | number): number
	if typeof(playerOrUserId) == "Instance" then
		return (playerOrUserId :: Player).UserId
	end

	return playerOrUserId
end

function ProductService.SetGamePassOwnershipCache(playerOrUserId: Player | number, id: number, owned: boolean)
	local userId = resolveUserId(playerOrUserId)
	local userCache = ownershipCache[userId]
	if not userCache then
		userCache = {}
		ownershipCache[userId] = userCache
	end

	userCache[id] = owned
end

function ProductService.ClearOwnershipCache(playerOrUserId: Player | number)
	ownershipCache[resolveUserId(playerOrUserId)] = nil
end

function ProductService.userOwnsGamePass(player: Player, id: number): boolean
	local userId = player.UserId
	local userCache = ownershipCache[userId]
	if not userCache then
		userCache = {}
		ownershipCache[userId] = userCache
	end

	if userCache[id] ~= nil then
		return userCache[id]
	end

	local success, owned = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, id)
	end)
	if success then
		ProductService.SetGamePassOwnershipCache(userId, id, owned)
		return owned
	end

	return false
end

function ProductService.IsLocalExperienceCreator(player: Player): boolean
	local creatorUserId = Remotes:GetAttribute("CreatorPurchaseUserId")
	return player == Players.LocalPlayer
		and typeof(creatorUserId) == "number"
		and player.UserId == creatorUserId
end

function ProductService.ConnectCreatorPurchaseFinished(callback: CreatorPurchaseFinishedCallback): () -> ()
	table.insert(creatorPurchaseFinishedCallbacks, callback)
	local connected = true
	return function()
		if not connected then
			return
		end
		connected = false
		local callbackIndex = table.find(creatorPurchaseFinishedCallbacks, callback)
		if callbackIndex then
			table.remove(creatorPurchaseFinishedCallbacks, callbackIndex)
		end
	end
end

function ProductService.promptGamePassPurchase(player: Player, id: number)
	local success, errorMessage = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, id)
	end)
	if success then
		if id == ProductService.Gamepasses.StarterPack then
			FunnelAnalytics.FireClientAction("StarterPackPromptOpened", {
				source = "GamePassPrompt",
			})
		end
		SoundService.PlayGuiSound("BellRing")
	else
		DebugModule.debugWarn("PromptGamePassPurchase failed: " .. tostring(errorMessage), "ProductService_Client")
	end
end

function ProductService.promptProductPurchase(player: Player, id: number)
	if typeof(id) ~= "number" or id <= 0 then
		DebugModule.debugWarn("Invalid developer product ID: " .. tostring(id), "ProductService_Client")
		return
	end

	local isCreatorProduct = ProductService.IsLocalExperienceCreator(player)
	local creatorIdentityPending = game.CreatorType == Enum.CreatorType.Group
		and Remotes:GetAttribute("CreatorPurchaseIdentityReady") ~= true
	if creatorIdentityPending then
		DebugModule.debugWarn(
			"Developer product request blocked until creator identity is resolved | productId=" .. tostring(id),
			"ProductService_Client"
		)
		return
	end

	DebugModule.debugInfo(
		"Developer product route | productId="
			.. tostring(id)
			.. " | creator="
			.. tostring(isCreatorProduct)
			.. " | serviceReady="
			.. tostring(Remotes:GetAttribute("CreatorPurchaseServiceReady")),
		"ProductService_Client"
	)

	if isCreatorProduct then
		if Remotes:GetAttribute("CreatorPurchaseServiceReady") ~= true then
			DebugModule.debugWarn(
				"Creator developer product request blocked until server service is ready | productId=" .. tostring(id),
				"ProductService_Client"
			)
			return
		end

		local requestOk, requestError = pcall(function()
			CreatorPurchaseRequest:FireServer("Product", id)
		end)
		if requestOk then
			SoundService.PlayGuiSound("BellRing")
		else
			DebugModule.debugWarn(
				"Creator developer product request failed for productId="
					.. tostring(id)
					.. ": "
					.. tostring(requestError),
				"ProductService_Client"
			)
		end
		return
	end

	local success, errorMessage = pcall(function()
		MarketplaceService:PromptProductPurchase(player, id)
	end)
	if success then
		SoundService.PlayGuiSound("BellRing")
	else
		DebugModule.debugWarn(
			"PromptProductPurchase failed for productId=" .. tostring(id) .. ": " .. tostring(errorMessage),
			"ProductService_Client"
		)
	end
end

CreatorPurchaseResult.OnClientEvent:Connect(function(rawPurchaseKind, rawProductId, rawSuccess, rawReason)
	if
		type(rawPurchaseKind) ~= "string"
		or rawPurchaseKind ~= "Product"
		or type(rawProductId) ~= "number"
		or type(rawSuccess) ~= "boolean"
		or type(rawReason) ~= "string"
	then
		DebugModule.debugWarn("Received malformed creator purchase result", "ProductService_Client")
		return
	end

	for _, callback in ipairs(table.clone(creatorPurchaseFinishedCallbacks)) do
		local callbackOk, callbackError = pcall(callback, rawPurchaseKind, rawProductId, rawSuccess, rawReason)
		if not callbackOk then
			DebugModule.debugWarn(
				"Creator purchase result callback failed: " .. tostring(callbackError),
				"ProductService_Client"
			)
		end
	end
	SoundService.PlayGuiSound(if rawSuccess then "Success" else "Close")
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, bought)
	if player == Players.LocalPlayer and bought then
		ProductService.SetGamePassOwnershipCache(player, id, true)
	end
	SoundService.PlayGuiSound(if bought then "Success" else "Close")
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, _, bought)
	SoundService.PlayGuiSound(if bought then "Success" else "Close")
end)

return ProductService
