--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local SoundService = require(Modules:WaitForChild("SoundService"))
local FunnelAnalytics = require(Modules:WaitForChild("FunnelAnalytics"))

local ProductService = {}

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
	if not RunService:IsClient() then return end
	local ok, err = pcall(function() MarketplaceService:PromptProductPurchase(player, id) end)
	if ok then SoundService.PlayGuiSound("BellRing") end
end

if RunService:IsClient() then
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
