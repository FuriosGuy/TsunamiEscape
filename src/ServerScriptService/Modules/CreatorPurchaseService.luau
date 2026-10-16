local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Maid = require(Modules:WaitForChild("Maid"))
local DebugModule = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("DebugModule"))
local ProductService = require(script.Parent.Shared:WaitForChild("ProductService_Server"))
local ProductServerService = require(script.Parent:WaitForChild("ProductServerService"))
local ReturnToStageService = require(script.Parent:WaitForChild("ReturnToStageService"))

local CreatorPurchaseService = {}

local MODULE_NAME = "CreatorPurchaseService"
local REQUEST_COOLDOWN_SECONDS = 0.75
local CREATOR_READY_ATTRIBUTE = "CreatorPurchaseServiceReady"
local CREATOR_USER_ID_ATTRIBUTE = "CreatorPurchaseUserId"
local CREATOR_IDENTITY_READY_ATTRIBUTE = "CreatorPurchaseIdentityReady"

type PurchaseKind = "Product"
type GrantCallback = () -> (boolean, string)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CreatorPurchaseRequest = Remotes:WaitForChild("CreatorPurchaseRequest") :: RemoteEvent
local CreatorPurchaseResult = Remotes:WaitForChild("CreatorPurchaseResult") :: RemoteEvent

local serviceMaid = Maid.new()
local requestTimes: { [Player]: number } = {}
local requestInFlight: { [Player]: boolean } = {}
local creatorUserId: number? = nil
local initialized = false

local function isExperienceCreator(player: Player): boolean
	return creatorUserId ~= nil and player.UserId == creatorUserId
end

local function resolveCreatorUserId(): number?
	if game.CreatorType == Enum.CreatorType.User then
		return game.CreatorId > 0 and game.CreatorId or nil
	end
	if game.CreatorType ~= Enum.CreatorType.Group or game.CreatorId <= 0 then
		return nil
	end

	local success, groupInfo = pcall(function()
		return GroupService:GetGroupInfoAsync(game.CreatorId)
	end)
	if not success or typeof(groupInfo) ~= "table" or typeof(groupInfo.Owner) ~= "table" then
		DebugModule.debugWarn(
			"Could not resolve group owner for creator purchases | groupId=" .. tostring(game.CreatorId),
			MODULE_NAME
		)
		return nil
	end

	local ownerId = groupInfo.Owner.Id
	return typeof(ownerId) == "number" and ownerId > 0 and ownerId or nil
end

local function findProductKey(products: { [string]: any }, productId: number): string?
	for productKey, rawProductId in pairs(products) do
		if typeof(rawProductId) == "number" and rawProductId == productId then
			return productKey
		end
	end

	return nil
end

local function isLiveEventActive(eventName: string): boolean
	local stateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
	if not stateFolder or not stateFolder:IsA("Folder") then
		return false
	end

	local activeEventIds = stateFolder:GetAttribute("ActiveEventIds")
	return typeof(activeEventIds) == "string"
		and string.find("," .. activeEventIds .. ",", "," .. eventName .. ",", 1, true) ~= nil
end

local function isEventProductAvailable(productKey: string): boolean
	local eventKartProducts = ProductService.EventKartProducts
	if typeof(eventKartProducts) == "table" then
		for eventName, eventProducts in pairs(eventKartProducts) do
			if typeof(eventProducts) == "table" and eventProducts[productKey] ~= nil then
				if eventName == "Halloween" then
					local stateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
					return stateFolder ~= nil and stateFolder:GetAttribute("HalloweenPartTwoActive") == true
				end
				return isLiveEventActive(tostring(eventName))
			end
		end
	end

	return true
end

local function sendResult(player: Player, purchaseKind: string, productId: number, success: boolean, reason: string)
	if player.Parent then
		CreatorPurchaseResult:FireClient(player, purchaseKind, productId, success, reason)
	end
end

local function completeGrant(
	player: Player,
	purchaseKind: PurchaseKind,
	productId: number,
	productKey: string,
	grantCallback: GrantCallback
)
	requestInFlight[player] = true
	local callOk, granted, reason = pcall(grantCallback)
	requestInFlight[player] = nil

	if not callOk then
		local callError = granted
		granted = false
		reason = "GrantError"
		DebugModule.debugWarn(
			string.format(
				"Creator purchase grant errored | player=%s | kind=%s | productId=%d | error=%s",
				player.Name,
				purchaseKind,
				productId,
				tostring(callError)
			),
			MODULE_NAME
		)
	end

	local success = granted == true
	local resultReason = if typeof(reason) == "string" then reason else if success then "Granted" else "GrantFailed"
	sendResult(player, purchaseKind, productId, success, resultReason)
	DebugModule.debugInfo(
		string.format(
			"Creator purchase request completed | player=%s | kind=%s | product=%s | success=%s | reason=%s",
			player.Name,
			purchaseKind,
			productKey,
			tostring(success),
			resultReason
		),
		MODULE_NAME
	)
end

local function onPurchaseRequest(player: Player, rawPurchaseKind: unknown, rawProductId: unknown)
	if
		typeof(rawPurchaseKind) ~= "string"
		or rawPurchaseKind ~= "Product"
		or typeof(rawProductId) ~= "number"
		or rawProductId <= 0
		or rawProductId ~= math.floor(rawProductId)
	then
		DebugModule.debugWarn("Rejected malformed creator purchase request", MODULE_NAME)
		return
	end

	local purchaseKind = rawPurchaseKind :: PurchaseKind
	local productId = math.floor(rawProductId)
	DebugModule.debugInfo(
		string.format("Creator purchase request received | player=%s | productId=%d", player.Name, productId),
		MODULE_NAME
	)
	if not isExperienceCreator(player) then
		sendResult(player, purchaseKind, productId, false, "NotCreator")
		return
	end

	if Remotes:GetAttribute(CREATOR_READY_ATTRIBUTE) ~= true then
		sendResult(player, purchaseKind, productId, false, "ServiceUnavailable")
		return
	end

	local now = os.clock()
	local lastRequestAt = requestTimes[player] or 0
	if now - lastRequestAt < REQUEST_COOLDOWN_SECONDS then
		sendResult(player, purchaseKind, productId, false, "RateLimited")
		return
	end
	requestTimes[player] = now

	if requestInFlight[player] then
		sendResult(player, purchaseKind, productId, false, "RequestInFlight")
		return
	end

	local productKey = findProductKey(ProductService.DevProducts, productId)
	if not productKey then
		DebugModule.debugWarn(
			string.format("Rejected unknown creator purchase | kind=%s | productId=%d", purchaseKind, productId),
			MODULE_NAME
		)
		sendResult(player, purchaseKind, productId, false, "UnknownProduct")
		return
	end

	-- ReturnToStage keeps its strict offer validation and uses a dedicated grant path.
	if productKey == "ReturnToStage" then
		completeGrant(player, purchaseKind, productId, productKey, function()
			return ReturnToStageService.HandleCreatorPurchase(player, productId)
		end)
		return
	end

	if not isEventProductAvailable(productKey) then
		sendResult(player, purchaseKind, productId, false, "EventInactive")
		return
	end

	completeGrant(player, purchaseKind, productId, productKey, function()
		return ProductServerService.GrantCreatorDeveloperProduct(player, productId)
	end)
end

function CreatorPurchaseService.IsExperienceCreator(player: Player): boolean
	return isExperienceCreator(player)
end

function CreatorPurchaseService.CleanupPlayer(player: Player)
	requestTimes[player] = nil
	requestInFlight[player] = nil
end

function CreatorPurchaseService.Init()
	if initialized then
		return
	end
	initialized = true
	creatorUserId = resolveCreatorUserId()
	ProductServerService.SetCreatorUserId(creatorUserId)
	Remotes:SetAttribute(CREATOR_USER_ID_ATTRIBUTE, creatorUserId)
	Remotes:SetAttribute(CREATOR_IDENTITY_READY_ATTRIBUTE, true)
	Remotes:SetAttribute(CREATOR_READY_ATTRIBUTE, creatorUserId ~= nil)
	serviceMaid.CreatorPurchaseRequest = CreatorPurchaseRequest.OnServerEvent:Connect(onPurchaseRequest)
	serviceMaid.PlayerRemoving = Players.PlayerRemoving:Connect(CreatorPurchaseService.CleanupPlayer)
	DebugModule.debugInfo(
		"Creator free purchase service initialized | creatorType="
			.. tostring(game.CreatorType)
			.. " | creatorUserId="
			.. tostring(creatorUserId)
			.. " | ready="
			.. tostring(creatorUserId ~= nil),
		MODULE_NAME
	)
end

function CreatorPurchaseService.Shutdown()
	if not initialized then
		return
	end

	Remotes:SetAttribute(CREATOR_READY_ATTRIBUTE, false)
	Remotes:SetAttribute(CREATOR_USER_ID_ATTRIBUTE, nil)
	Remotes:SetAttribute(CREATOR_IDENTITY_READY_ATTRIBUTE, false)
	serviceMaid:DoCleaning()
	for player in pairs(table.clone(requestTimes)) do
		CreatorPurchaseService.CleanupPlayer(player)
	end
	creatorUserId = nil
	ProductServerService.SetCreatorUserId(nil)
	initialized = false
	DebugModule.debugInfo("Creator free purchase service shutdown", MODULE_NAME)
end

return CreatorPurchaseService
