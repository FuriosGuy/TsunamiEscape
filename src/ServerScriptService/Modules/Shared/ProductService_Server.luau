--!strict

-- Server-only product authority. Client prompting lives in ProductService_Client.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedFolder = game:GetService("ServerScriptService").Modules:WaitForChild("Shared")
local ProductCatalog = require(ReplicatedStorage.Modules.Shared:WaitForChild("ProductCatalog"))
local PlayerHandler = require(SharedFolder:WaitForChild("PlayerHandler_Server"))

local ProductService: { [string]: any } = {}
ProductService.Gamepasses = ProductCatalog.Gamepasses
ProductService.DevProducts = ProductCatalog.DevProducts
ProductService.BloodmoonKartProducts = ProductCatalog.BloodmoonKartProducts
ProductService.EventKartProducts = ProductCatalog.EventKartProducts
ProductService.MULTIPLIER_TO_PRODUCT = ProductCatalog.MULTIPLIER_TO_PRODUCT
ProductService.DataStores = {
	PlayerStats = "PlayerStats_v1",
	ProfileRegistry = "PlayerProfileRegistry_v1",
	FriendReferralClaims = "FriendReferralClaims_v1",
}

local NON_PERSISTED = {
	WinMultiplier = true,
	Treadmill_Active = true,
	Treadmill_XPMultiplier = true,
	Friend_XPMultiplier = true,
	Movement_XPGainRate = true,
	Movement_XPGainInterval = true,
	Data_Loaded = true,
	Pet_PaidRandomItemsRestricted = true,
	Pet_RandomItemPolicyLoaded = true,
	PlaytimeRewardElapsed = true,
	PlaytimeRewardsClaimed = true,
}

local savedAttributes = {}
for name, defaultValue in pairs(PlayerHandler.DEFAULT_ATTRIBUTES) do
	if not NON_PERSISTED[name] then
		table.insert(savedAttributes, { name = name, default = defaultValue })
	end
end
ProductService.SAVED_ATTRIBUTES = savedAttributes

local ownershipCache: { [number]: { [number]: boolean } } = {}

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

Players.PlayerRemoving:Connect(function(player)
	ProductService.ClearOwnershipCache(player)
end)

return ProductService
