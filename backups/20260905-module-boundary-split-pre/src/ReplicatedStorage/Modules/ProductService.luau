--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local SoundService = require(Modules:WaitForChild("SoundService"))
local FunnelAnalytics = require(Modules:WaitForChild("FunnelAnalytics"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))

local ProductService = {}

type CreatorPurchaseFinishedCallback = (purchaseKind: string, productId: number, success: boolean, reason: string) -> ()

local creatorPurchaseFinishedCallbacks: { CreatorPurchaseFinishedCallback } = {}
local CreatorPurchaseRequest = Remotes:WaitForChild("CreatorPurchaseRequest") :: RemoteEvent
local CreatorPurchaseResult = Remotes:WaitForChild("CreatorPurchaseResult") :: RemoteEvent

-------------------------------------------------------------------------------
-- Configurations (Shared Source of Truth)
-------------------------------------------------------------------------------

ProductService.Gamepasses = {
	["2xWins"] = 1760592086,
	["VIP"]    = 1761600143,
	["3xTreadmill"] = 1767574117,
	["15xTreadmill"] = 1766286297,
	["35xTreadmill"] = 1767831974,
	["100xTreadmill"] = 1768431922,
	["AdvancedTank"] = 1791998927,
	["ShoppingKart"] = 1790815513,
	["FormulaCar"] = 1792060852,
	["StarterPack"] = 1832483110,
}

ProductService.DevProducts = {
	["SkipRebirth"] = 3559805591,
	["DisableWaves"] = 3559813364,
	["ReturnToStage"] = 3564307894,
	["TrollPlayer"] = 3573199025,
	["+100K"] = 3559807390,
	["+1M"] = 3559807486,
	["+10M"] = 3559807556,
	["+1000"] = 3573866224,
	["+5000"] = 3573865316,
	["+10000"] = 3573900618,
	["2x"] = 3560793026,
	["4x"] = 3560793704,
	["8x"] = 3560793814,
	["16x"] = 3560795074,
	["32x"] = 3560795353,
	["64x"] = 3560795487,
	["100x"] = 3560795766,
	["GalaxyTrail"] = 3572176684,
	["DemonTrail"] = 3572176018,
	["GoldTrail"] = 3572176138,
	["PurpleTrail"] = 3572175420,
	["BlueTrail"] = 3572175233,
	["GreenTrail"] = 3572175108,
	["ClaimAllDaily"] = 3589872144,
	["Spin1"] = 3612605889,
	["Spin3"] = 3612605970,
	["Spin5"] = 3612606198,
	["Spin10"] = 3612606233,
	["TempSpeedBoost"] = 3707042010,
	["TempWinBoost"] = 3707052002,
	["CrimsonCell"] = 3710412649,
	["BloodDragon"] = 3710413009,
	["SiegeTank"] = 3710413231,
}

ProductService.BloodmoonKartProducts = {
	CrimsonCell = {
		KartName = "4_CrimsonCell",
		EventName = "Bloodmoon",
	},
	BloodDragon = {
		KartName = "5_BloodDragon",
		EventName = "Bloodmoon",
	},
	SiegeTank = {
		KartName = "6_SiegeTank",
		EventName = "Bloodmoon",
	},
}

ProductService.MULTIPLIER_TO_PRODUCT = {
	[1] = "2x",
	[2] = "4x",
	[4] = "8x",
	[8] = "16x",
	[16] = "32x",
	[32] = "64x",
	[64] = "100x",
}

ProductService.DataStores = {
	["PlayerStats"] = "PlayerStats_v1",
	["ProfileRegistry"] = "PlayerProfileRegistry_v1",
	["FriendReferralClaims"] = "FriendReferralClaims_v1",
}

-------------------------------------------------------------------------------
-- SAVED_ATTRIBUTES Setup
-------------------------------------------------------------------------------

local NON_PERSISTED = {
	WinMultiplier = true,
	Treadmill_Active = true,
	Treadmill_XPMultiplier = true,
	Friend_XPMultiplier = true,
	Movement_XPGainRate = true,
	Movement_XPGainInterval = true,
	Data_Loaded = true, -- Never persist the loading flag
	PlaytimeRewardElapsed = true, -- Session-only timer
	PlaytimeRewardsClaimed = true, -- Session-only claimed reward tracking
}

local SAVED_ATTRIBUTES = {}
for name, defaultValue in pairs(PlayerHandler.DEFAULT_ATTRIBUTES) do
	if not NON_PERSISTED[name] then
		table.insert(SAVED_ATTRIBUTES, { name = name, default = defaultValue })
	end
end
ProductService.SAVED_ATTRIBUTES = SAVED_ATTRIBUTES

-------------------------------------------------------------------------------
-- Shared Methods
-------------------------------------------------------------------------------

local cache: { [number]: { [number]: boolean } } = {}

local function resolveUserId(playerOrUserId: Player | number): number
	if typeof(playerOrUserId) == "Instance" then
		return (playerOrUserId :: Player).UserId
	end

	return playerOrUserId
end

function ProductService.SetGamePassOwnershipCache(playerOrUserId: Player | number, id: number, owned: boolean)
	local uid = resolveUserId(playerOrUserId)
	if not cache[uid] then
		cache[uid] = {}
	end

	cache[uid][id] = owned
end

function ProductService.ClearOwnershipCache(playerOrUserId: Player | number)
	local uid = resolveUserId(playerOrUserId)
	cache[uid] = nil
end

function ProductService.userOwnsGamePass(player: Player, id: number): boolean
	local uid = player.UserId
	if not cache[uid] then cache[uid] = {} end
	if cache[uid][id] ~= nil then return cache[uid][id] end

	local ok, owned = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(uid, id) end)
	if ok then
		ProductService.SetGamePassOwnershipCache(uid, id, owned)
		return owned
	end
	return false
end

function ProductService.IsLocalExperienceCreator(player: Player): boolean
	local creatorUserId = Remotes:GetAttribute("CreatorPurchaseUserId")
	return RunService:IsClient()
		and player == Players.LocalPlayer
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

-------------------------------------------------------------------------------
-- Client-Only Prompting
-------------------------------------------------------------------------------

function ProductService.promptGamePassPurchase(player: Player, id: number)
	if not RunService:IsClient() then return end
	local ok, err = pcall(function() MarketplaceService:PromptGamePassPurchase(player, id) end)
	if ok then
		if id == ProductService.Gamepasses["StarterPack"] then
			FunnelAnalytics.FireClientAction("StarterPackPromptOpened", {
				source = "GamePassPrompt",
			})
		end
		SoundService.PlayGuiSound("BellRing")
	end
end

function ProductService.promptProductPurchase(player: Player, id: number)
	if not RunService:IsClient() then
		return
	end
	if typeof(id) ~= "number" or id <= 0 then
		DebugModule.debugWarn("Invalid developer product ID: " .. tostring(id), "ProductService")
		return
	end

	local isCreatorProduct = ProductService.IsLocalExperienceCreator(player)
	local creatorIdentityPending = game.CreatorType == Enum.CreatorType.Group
		and Remotes:GetAttribute("CreatorPurchaseIdentityReady") ~= true
	if creatorIdentityPending then
		DebugModule.debugWarn(
			"Developer product request blocked until creator identity is resolved | productId=" .. tostring(id),
			"ProductService"
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
		"ProductService"
	)
	if isCreatorProduct then
		if Remotes:GetAttribute("CreatorPurchaseServiceReady") ~= true then
			DebugModule.debugWarn(
				"Creator developer product request blocked until server service is ready | productId=" .. tostring(id),
				"ProductService"
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
				"ProductService"
			)
		end
		return
	end

	local ok, err = pcall(function()
		MarketplaceService:PromptProductPurchase(player, id)
	end)
	if ok then
		SoundService.PlayGuiSound("BellRing")
	else
		DebugModule.debugWarn(
			"PromptProductPurchase failed for productId=" .. tostring(id) .. ": " .. tostring(err),
			"ProductService"
		)
	end
end

if RunService:IsClient() then
	CreatorPurchaseResult.OnClientEvent:Connect(function(rawPurchaseKind, rawProductId, rawSuccess, rawReason)
		if typeof(rawPurchaseKind) ~= "string"
			or rawPurchaseKind ~= "Product"
			or typeof(rawProductId) ~= "number"
			or typeof(rawSuccess) ~= "boolean"
			or typeof(rawReason) ~= "string"
		then
			DebugModule.debugWarn("Received malformed creator purchase result", "ProductService")
			return
		end

		for _, callback in ipairs(table.clone(creatorPurchaseFinishedCallbacks)) do
			local callbackOk, callbackError = pcall(
				callback,
				rawPurchaseKind,
				rawProductId,
				rawSuccess,
				rawReason
			)
			if not callbackOk then
				DebugModule.debugWarn(
					"Creator purchase result callback failed: " .. tostring(callbackError),
					"ProductService"
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
else
	Players.PlayerRemoving:Connect(function(player)
		ProductService.ClearOwnershipCache(player)
	end)
end

return ProductService
