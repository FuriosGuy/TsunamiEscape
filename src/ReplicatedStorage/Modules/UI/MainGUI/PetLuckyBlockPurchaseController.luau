--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local ProductService = require(ReplicatedStorage.Modules.Shared.ProductService_Client)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

type LuckyBlockGroup = "Tier1" | "Tier2" | "Tier3" | "Premium" | "BloodMoon" | "NeonRush" | "FrostbiteRally"
type RollCount = number
type PurchaseKind = "Wins" | "Robux"

type PendingRoll = {
	group: LuckyBlockGroup,
	rollCount: RollCount,
	purchaseKind: PurchaseKind,
	productId: number?,
	startedAt: number,
}
type RollResolvedCallback = (group: LuckyBlockGroup, petIds: { string }, fasterOpen: boolean) -> ()

type Controller = {
	maid: any,
	requestRemote: RemoteEvent?,
	resultRemote: RemoteEvent?,
	pendingRoll: PendingRoll?,
	onRollResolved: RollResolvedCallback,
	alive: boolean,
	Init: (self: Controller) -> (),
	RequestRoll: (self: Controller, group: LuckyBlockGroup, rollCount: number, purchaseKind: PurchaseKind) -> (),
	Destroy: (self: Controller) -> (),
}

local PetLuckyBlockPurchaseController = {}
PetLuckyBlockPurchaseController.__index = PetLuckyBlockPurchaseController

local MODULE_NAME = "PetLuckyBlockPurchaseController"
local PENDING_REQUEST_TIMEOUT_SECONDS = 60
local function showNotification(message: string, themeName: string): ()
	local themes = VisualFunctions.NotificationThemes
	local theme = themes[themeName] or themes.Default
	VisualFunctions.ShowNotification(message, theme.textColor, theme.gradientBottomColor)
end

local function clearPending(self: Controller): ()
	self.pendingRoll = nil
end

function PetLuckyBlockPurchaseController.new(onRollResolved: RollResolvedCallback): Controller
	return setmetatable({
		maid = Maid.new(),
		requestRemote = nil,
		resultRemote = nil,
		pendingRoll = nil,
		onRollResolved = onRollResolved,
		alive = true,
	}, PetLuckyBlockPurchaseController) :: Controller
end

function PetLuckyBlockPurchaseController.Init(self: Controller): ()
	if not self.alive then
		return
	end

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local requestRemote = remotes and remotes:WaitForChild("PetLuckyBlockRollRequest", 10)
	local resultRemote = remotes and remotes:WaitForChild("PetLuckyBlockRollResult", 10)
	if not requestRemote or not requestRemote:IsA("RemoteEvent") or not resultRemote or not resultRemote:IsA("RemoteEvent") then
		DebugModule.debugWarn("Lucky Block purchase remotes are missing", MODULE_NAME)
		return
	end
	self.requestRemote = requestRemote
	self.resultRemote = resultRemote

	self.maid:GiveTask(resultRemote.OnClientEvent:Connect(function(status: unknown, value: unknown)
		local pendingRoll = self.pendingRoll
		if not self.alive or not pendingRoll or typeof(status) ~= "string" then
			return
		end

		if status == "ProductPrompted" then
			if typeof(value) == "number" and value > 0 then
				pendingRoll.productId = value
				return
			end
			clearPending(self)
			return
		end
		if status == "RollResolved" then
			if typeof(value) ~= "table" then
				DebugModule.debugWarn("Server returned malformed Lucky Block roll result", MODULE_NAME)
				clearPending(self)
				return
			end
			local resultPayload = value :: { [string]: unknown }
			local rawPetIds = resultPayload.petIds
			if typeof(rawPetIds) ~= "table" or typeof(resultPayload.fasterOpen) ~= "boolean" then
				DebugModule.debugWarn("Server returned malformed Lucky Block result payload", MODULE_NAME)
				clearPending(self)
				return
			end
			local typedPetIds = rawPetIds :: { unknown }
			if #typedPetIds ~= pendingRoll.rollCount then
				DebugModule.debugWarn("Server Lucky Block result count did not match request", MODULE_NAME)
				clearPending(self)
				return
			end
			local petIds: { string } = {}
			for _, rawPetId in ipairs(typedPetIds) do
				if typeof(rawPetId) ~= "string" then
					DebugModule.debugWarn("Server returned invalid Lucky Block pet ID", MODULE_NAME)
					clearPending(self)
					return
				end
				table.insert(petIds, rawPetId)
			end
			local group = pendingRoll.group
			local fasterOpen = resultPayload.fasterOpen :: boolean
			clearPending(self)
			self.onRollResolved(group, petIds, fasterOpen)
			return
		end

		clearPending(self)
		if status == "NotEnoughWins" then
			showNotification("NOT ENOUGH WINS!", "Red")
		elseif status == "PaidRandomItemsRestricted" then
			showNotification("PAID LUCKY BLOCKS ARE UNAVAILABLE FOR YOUR ACCOUNT!", "Red")
		elseif status == "PolicyLoading" then
			showNotification("CHECKING PAID LUCKY BLOCK ACCESS!", "Gold")
		elseif status == "InventoryFull" then
			showNotification("BACKPACK FULL! MAKE SPACE BEFORE OPENING!", "Red")
		elseif status == "GrantFailed" then
			showNotification("PET REWARD COULD NOT BE SAVED. TRY AGAIN!", "Red")
		elseif status == "EventInactive" then
			showNotification("EVENT LUCKY BLOCK NOT ACTIVE!", "Red")
		elseif status == "ProductUnavailable" then
			showNotification("LUCKY BLOCK PRODUCT UNAVAILABLE!", "Red")
		elseif status == "DataNotLoaded" then
			showNotification("DATA STILL LOADING!", "Red")
		elseif status == "InvalidRequest" or status == "RateLimited" then
			DebugModule.debugWarn("Lucky Block roll request rejected | status=" .. status, MODULE_NAME)
		end
	end))

	self.maid:GiveTask(MarketplaceService.PromptProductPurchaseFinished:Connect(function(
		userId: number,
		productId: number,
		wasPurchased: boolean
	)
		local pendingRoll = self.pendingRoll
		if userId == Players.LocalPlayer.UserId
			and pendingRoll
			and pendingRoll.productId == productId
			and not wasPurchased
		then
			clearPending(self)
		end
	end))

	self.maid:GiveTask(ProductService.ConnectCreatorPurchaseFinished(function(
		purchaseKind: string,
		productId: number,
		success: boolean,
		_reason: string
	)
		local pendingRoll = self.pendingRoll
		if purchaseKind == "Product" and pendingRoll and pendingRoll.productId == productId and not success then
			clearPending(self)
		end
	end))
end

function PetLuckyBlockPurchaseController.RequestRoll(
	self: Controller,
	group: LuckyBlockGroup,
	rollCount: number,
	purchaseKind: PurchaseKind
): ()
	if not self.alive then
		return
	end

	if rollCount ~= 1 and rollCount ~= 3 and rollCount ~= 5 then
		DebugModule.debugWarn("Rejected unsupported Lucky Block roll count", MODULE_NAME)
		return
	end
	if purchaseKind ~= "Wins" and purchaseKind ~= "Robux" then
		DebugModule.debugWarn("Rejected unsupported Lucky Block purchase kind", MODULE_NAME)
		return
	end
	local player = Players.LocalPlayer
	if player:GetAttribute("Pet_RandomItemPolicyLoaded") ~= true then
		showNotification("CHECKING LUCKY BLOCK ACCESS!", "Gold")
		return
	end
	if player:GetAttribute("Pet_PaidRandomItemsRestricted") == true then
		showNotification("LUCKY BLOCKS ARE UNAVAILABLE FOR YOUR ACCOUNT!", "Red")
		return
	end

	local pendingRoll = self.pendingRoll
	if pendingRoll and os.clock() - pendingRoll.startedAt <= PENDING_REQUEST_TIMEOUT_SECONDS then
		return
	end
	clearPending(self)

	local requestRemote = self.requestRemote
	if not requestRemote then
		showNotification("LUCKY BLOCK PURCHASE SYSTEM NOT READY!", "Red")
		return
	end

	self.pendingRoll = {
		group = group,
		rollCount = rollCount :: RollCount,
		purchaseKind = purchaseKind,
		productId = nil,
		startedAt = os.clock(),
	}
	requestRemote:FireServer(group, rollCount, purchaseKind)
end

function PetLuckyBlockPurchaseController.Destroy(self: Controller): ()
	if not self.alive then
		return
	end
	self.alive = false
	self.maid:DoCleaning()
	clearPending(self)
	self.requestRemote = nil
	self.resultRemote = nil
end

return PetLuckyBlockPurchaseController
