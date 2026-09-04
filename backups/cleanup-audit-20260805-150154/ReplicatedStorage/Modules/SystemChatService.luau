--!strict
local MessagingService = game:GetService("MessagingService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local Maid = require(ReplicatedStorage.Modules.Maid)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig)
local ProductService = require(ReplicatedStorage.Modules.ProductService)

local SystemChatService = {}
local REMOTE_NAME = "GlobalSystemChat"
local TOPIC_NAME = "GlobalSystemChat_v1"
local MODULE_NAME = "SystemChatService"
local serverSubscription: RBXScriptConnection? = nil
local serverInstanceId = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(os.clock()))
local promotionalLoopStarted = false
local playerAnnouncementsStarted = false
local promotionalLoopAlive = false
local serverMaid = Maid.new()
local serverShutdownBound = false
local systemChatConfig = CoreConfig.systemChat

local DEFAULT_LIKE_FAVORITE_EMOJIS = { "👍", "⭐", "🔥", "🎉", "💛", "💬", "📌", "🌟" }
local DEFAULT_GROUP_EMOJIS = { "👥", "🎁", "✨", "🚀", "🏆", "🤝", "📣", "🎊" }
local DEFAULT_SHOP_EMOJIS = { "🛒", "💎", "⚡", "🚗", "🔥", "🧪", "💥", "🎯" }
local DEFAULT_SHOP_PROMOTIONAL_TEMPLATES = {
	"Boost your run with {ITEM}!",
	"Try {ITEM} from the shop!",
	"Power up now with {ITEM}!",
	"Upgrade your progress using {ITEM}!",
	"Check out {ITEM} in the shop!",
}
local DEFAULT_SHOP_PROMOTION_OFFER_KEYS = {
	"VIP",
	"2xWins",
	"3xTreadmill",
	"15xTreadmill",
	"35xTreadmill",
	"100xTreadmill",
	"AdvancedTank",
	"ShoppingKart",
	"FormulaCar",
	"+1000",
	"+5000",
	"+10000",
	"+100K",
	"+1M",
	"+10M",
	"2x",
	"4x",
	"8x",
	"16x",
	"32x",
	"64x",
	"100x",
}

SystemChatService.Config = {
	DefaultColor = Color3.fromRGB(254, 200, 42),
	RebirthColor = Color3.fromRGB(227, 74, 255),
	PromoColor = Color3.fromRGB(255, 255, 255),
	PlayerJoinColor = Color3.fromRGB(70, 255, 120),
	PlayerLeaveColor = Color3.fromRGB(255, 70, 70),
	PromoMinDelay = if systemChatConfig and typeof(systemChatConfig.promoMinDelay) == "number"
		then math.max(1, systemChatConfig.promoMinDelay)
		else 120,
	PromoMaxDelay = if systemChatConfig and typeof(systemChatConfig.promoMaxDelay) == "number"
		then math.max(1, systemChatConfig.promoMaxDelay)
		else 300,
}

SystemChatService.LikeFavoriteEmojis = if systemChatConfig
		and typeof(systemChatConfig.likeFavoriteEmojis) == "table"
		and #systemChatConfig.likeFavoriteEmojis > 0
	then
		systemChatConfig.likeFavoriteEmojis
	else
		DEFAULT_LIKE_FAVORITE_EMOJIS

SystemChatService.GroupEmojis = if systemChatConfig
		and typeof(systemChatConfig.groupEmojis) == "table"
		and #systemChatConfig.groupEmojis > 0
	then
		systemChatConfig.groupEmojis
	else
		DEFAULT_GROUP_EMOJIS

SystemChatService.ShopEmojis = if systemChatConfig and typeof(systemChatConfig.shopEmojis) == "table" and #systemChatConfig.shopEmojis > 0
	then
		systemChatConfig.shopEmojis
	else
		DEFAULT_SHOP_EMOJIS

SystemChatService.LikeFavoritePromotionalMessages = if systemChatConfig
		and typeof(systemChatConfig.likeFavoritePromotionalMessages) == "table"
		and #systemChatConfig.likeFavoritePromotionalMessages > 0
	then
		systemChatConfig.likeFavoritePromotionalMessages
	else
		{
			"Favorite the game and leave a Like for more updates!",
			"Enjoying the game? Favorite it and drop a Like!",
			"Like + Favorite the game to support future content!",
			"Show some support by Liking and Favoriting the game!",
			"Like and Favorite the game if you want more awesome updates!",
		}

SystemChatService.GroupPromotionalMessages = if systemChatConfig
		and typeof(systemChatConfig.groupPromotionalMessages) == "table"
		and #systemChatConfig.groupPromotionalMessages > 0
	then
		systemChatConfig.groupPromotionalMessages
	else
		{
			"Join our group for exclusive rewards!",
			"Join our group to claim exclusive rewards!",
			"Group members get exclusive rewards, join us now!",
			"Join our group and grab your exclusive rewards!",
			"Want exclusive rewards? Join our group today!",
		}

SystemChatService.ShopPromotionalTemplates = if systemChatConfig
		and typeof(systemChatConfig.shopPromotionalTemplates) == "table"
		and #systemChatConfig.shopPromotionalTemplates > 0
	then
		systemChatConfig.shopPromotionalTemplates
	else
		DEFAULT_SHOP_PROMOTIONAL_TEMPLATES

SystemChatService.ShopPromotionOfferKeys = if systemChatConfig
		and typeof(systemChatConfig.shopPromotionOfferKeys) == "table"
		and #systemChatConfig.shopPromotionOfferKeys > 0
	then
		systemChatConfig.shopPromotionOfferKeys
	else
		DEFAULT_SHOP_PROMOTION_OFFER_KEYS

local OFFER_LABELS: { [string]: string } = {
	VIP = "VIP Pass",
	["2xWins"] = "2x Wins",
	["3xTreadmill"] = "3x Treadmill Pass",
	["15xTreadmill"] = "15x Treadmill Pass",
	["35xTreadmill"] = "35x Treadmill Pass",
	["100xTreadmill"] = "100x Treadmill Pass",
	AdvancedTank = "Advanced Tank Kart",
	ShoppingKart = "Shopping Kart",
	FormulaCar = "Formula Car",
	["+1000"] = "+1,000 Wins",
	["+5000"] = "+5,000 Wins",
	["+10000"] = "+10,000 Wins",
	["+100K"] = "+100K XP Speed",
	["+1M"] = "+1M XP Speed",
	["+10M"] = "+10M XP Speed",
	["2x"] = "2x XP Multiplier",
	["4x"] = "4x XP Multiplier",
	["8x"] = "8x XP Multiplier",
	["16x"] = "16x XP Multiplier",
	["32x"] = "32x XP Multiplier",
	["64x"] = "64x XP Multiplier",
	["100x"] = "100x XP Multiplier",
}
local marketplaceNameCache: { [string]: string | false } = {}

local function getRandomFromPool(pool: { string }): string?
	local count = #pool
	if count <= 0 then
		return nil
	end

	return pool[math.random(1, count)]
end

local function getMarketplaceItemName(itemId: number, infoType: Enum.InfoType): string?
	local cacheKey = string.format("%s:%d", infoType.Name, itemId)
	local cached = marketplaceNameCache[cacheKey]
	if cached == false then
		return nil
	end
	if typeof(cached) == "string" then
		return cached
	end

	local ok, result = pcall(function()
		return MarketplaceService:GetProductInfo(itemId, infoType)
	end)
	if not ok or typeof(result) ~= "table" then
		marketplaceNameCache[cacheKey] = false
		return nil
	end

	local name = result.Name
	if typeof(name) == "string" and name ~= "" then
		marketplaceNameCache[cacheKey] = name
		return name
	end

	marketplaceNameCache[cacheKey] = false
	return nil
end

local function resolveOfferDisplayName(offerKey: string): string
	local gamePassId = ProductService.Gamepasses[offerKey]
	if typeof(gamePassId) == "number" and gamePassId > 0 then
		local liveName = getMarketplaceItemName(gamePassId, Enum.InfoType.GamePass)
		if liveName then
			return liveName
		end
	end

	local devProductId = ProductService.DevProducts[offerKey]
	if typeof(devProductId) == "number" and devProductId > 0 then
		local liveName = getMarketplaceItemName(devProductId, Enum.InfoType.Product)
		if liveName then
			return liveName
		end
	end

	return OFFER_LABELS[offerKey] or offerKey
end

local function buildShopPromotionOffers(): { string }
	local offers: { string } = {}
	for _, offerKey in ipairs(SystemChatService.ShopPromotionOfferKeys) do
		local gamePassId = ProductService.Gamepasses[offerKey]
		local devProductId = ProductService.DevProducts[offerKey]
		local hasCatalogEntry = (typeof(gamePassId) == "number" and gamePassId > 0)
			or (typeof(devProductId) == "number" and devProductId > 0)
		if hasCatalogEntry then
			table.insert(offers, resolveOfferDisplayName(offerKey))
		end
	end

	return offers
end

local shopPromotionOffers: { string }? = nil

local function buildPromotionalMessage(): string?
	local promoMode = math.random(1, 3)

	if promoMode == 1 then
		local message = getRandomFromPool(SystemChatService.LikeFavoritePromotionalMessages)
		if not message then
			return nil
		end
		local emoji = getRandomFromPool(SystemChatService.LikeFavoriteEmojis)
		return if emoji then string.format("%s %s", emoji, message) else message
	elseif promoMode == 2 then
		local message = getRandomFromPool(SystemChatService.GroupPromotionalMessages)
		if not message then
			return nil
		end
		local emoji = getRandomFromPool(SystemChatService.GroupEmojis)
		return if emoji then string.format("%s %s", emoji, message) else message
	end

	local template = getRandomFromPool(SystemChatService.ShopPromotionalTemplates)
	if not shopPromotionOffers then
		shopPromotionOffers = buildShopPromotionOffers()
	end
	local offer = getRandomFromPool(shopPromotionOffers)
	if not template or not offer then
		return nil
	end
	local emoji = getRandomFromPool(SystemChatService.ShopEmojis)
	local message = string.gsub(template, "{ITEM}", offer)
	return if emoji then string.format("%s %s", emoji, message) else message
end

local function getRemotesFolder(): Instance
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	return remotes
end

local function getRemote(): RemoteEvent
	local remotes = getRemotesFolder()
	local remote = remotes:FindFirstChild(REMOTE_NAME) :: RemoteEvent?
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = remotes
	end

	return remote
end

local function colorToHex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local function randomSteppedInteger(minValue: number, maxValue: number): number
	local resolvedMin = math.floor(math.min(minValue, maxValue))
	local resolvedMax = math.floor(math.max(minValue, maxValue))
	local step = if resolvedMax - resolvedMin >= 10 then 10 else 1

	if resolvedMin == resolvedMax then
		return resolvedMin
	end

	local stepCount = math.floor((resolvedMax - resolvedMin) / step)
	return resolvedMin + (math.random(0, stepCount) * step)
end

function SystemChatService.FormatMessage(message: string, color: Color3?): string
	local resolvedColor = color or SystemChatService.Config.DefaultColor
	return string.format('<font color="%s"><b>%s</b></font>', colorToHex(resolvedColor), message)
end

function SystemChatService.FormatPurchaseMessage(playerName: string, itemName: string, price: number, color: Color3?): string
	local message = string.format("[SYSTEM]: %s just bought '%s' for %d Robux!", playerName, itemName, price)
	return SystemChatService.FormatMessage(message, color)
end

local function formatOrdinal(value: number): string
	local mod100 = value % 100
	if mod100 >= 11 and mod100 <= 13 then
		return tostring(value) .. "th"
	end

	local mod10 = value % 10
	if mod10 == 1 then
		return tostring(value) .. "st"
	elseif mod10 == 2 then
		return tostring(value) .. "nd"
	elseif mod10 == 3 then
		return tostring(value) .. "rd"
	end

	return tostring(value) .. "th"
end

function SystemChatService.FormatRebirthMessage(playerName: string, rebirthCount: number, color: Color3?): string
	local message = string.format("[SYSTEM]: %s just rebirthed for the %s time!", playerName, formatOrdinal(rebirthCount))
	return SystemChatService.FormatMessage(message, color or SystemChatService.Config.RebirthColor)
end

function SystemChatService.FormatPlayerJoinMessage(playerName: string, color: Color3?): string
	local message = string.format("[SYSTEM]: %s joined the server!", playerName)
	return SystemChatService.FormatMessage(message, color or SystemChatService.Config.PlayerJoinColor)
end

function SystemChatService.FormatPlayerLeaveMessage(playerName: string, color: Color3?): string
	local message = string.format("[SYSTEM]: %s left the server!", playerName)
	return SystemChatService.FormatMessage(message, color or SystemChatService.Config.PlayerLeaveColor)
end

function SystemChatService.BroadcastMessage(message: string, color: Color3?)
	assert(RunService:IsServer(), "BroadcastMessage must be called on the server")
	local formattedMessage = SystemChatService.FormatMessage(message, color)
	getRemote():FireAllClients(formattedMessage)
	local publishSuccess, publishError = pcall(function()
		MessagingService:PublishAsync(TOPIC_NAME, {
			ServerInstanceId = serverInstanceId,
			FormattedMessage = formattedMessage,
		})
	end)

	if not publishSuccess then
		DebugModule.debugWarn("Failed to publish global system chat: " .. tostring(publishError), MODULE_NAME)
	end
end

function SystemChatService.BroadcastPurchase(player: Player, itemName: string, price: number, color: Color3?)
	assert(RunService:IsServer(), "BroadcastPurchase must be called on the server")
	local formattedMessage = SystemChatService.FormatPurchaseMessage(player.Name, itemName, price, color)
	getRemote():FireAllClients(formattedMessage)
	local publishSuccess, publishError = pcall(function()
		MessagingService:PublishAsync(TOPIC_NAME, {
			ServerInstanceId = serverInstanceId,
			FormattedMessage = formattedMessage,
		})
	end)

	if not publishSuccess then
		DebugModule.debugWarn("Failed to publish global purchase chat: " .. tostring(publishError), MODULE_NAME)
	end
end

function SystemChatService.BroadcastLocalMessage(message: string, color: Color3?)
	assert(RunService:IsServer(), "BroadcastLocalMessage must be called on the server")
	getRemote():FireAllClients(SystemChatService.FormatMessage(message, color))
end

function SystemChatService.BroadcastLocalRebirth(player: Player, rebirthCount: number, color: Color3?)
	assert(RunService:IsServer(), "BroadcastLocalRebirth must be called on the server")
	getRemote():FireAllClients(SystemChatService.FormatRebirthMessage(player.Name, rebirthCount, color))
end

function SystemChatService.BroadcastLocalPlayerJoin(player: Player, color: Color3?)
	assert(RunService:IsServer(), "BroadcastLocalPlayerJoin must be called on the server")
	getRemote():FireAllClients(SystemChatService.FormatPlayerJoinMessage(player.Name, color))
end

function SystemChatService.BroadcastLocalPlayerLeave(playerName: string, color: Color3?)
	assert(RunService:IsServer(), "BroadcastLocalPlayerLeave must be called on the server")
	getRemote():FireAllClients(SystemChatService.FormatPlayerLeaveMessage(playerName, color))
end

function SystemChatService.StartPromotionalLoop()
	assert(RunService:IsServer(), "StartPromotionalLoop must be called on the server")
	if promotionalLoopStarted then
		return
	end

	promotionalLoopStarted = true
	promotionalLoopAlive = true
	serverMaid.PromotionalLoopCleanup = function()
		promotionalLoopAlive = false
	end
	serverMaid.PromotionalLoopThread = task.spawn(function()
		while promotionalLoopAlive do
			local delayTime = randomSteppedInteger(
				SystemChatService.Config.PromoMinDelay,
				SystemChatService.Config.PromoMaxDelay
			)
			task.wait(delayTime)
			if not promotionalLoopAlive then
				break
			end

			local message = buildPromotionalMessage()
			if not message then
				continue
			end
			SystemChatService.BroadcastLocalMessage("[SYSTEM]: " .. message, SystemChatService.Config.PromoColor)
		end
	end)
end

function SystemChatService.StartPlayerAnnouncementLoop()
	assert(RunService:IsServer(), "StartPlayerAnnouncementLoop must be called on the server")
	if playerAnnouncementsStarted then
		return
	end

	playerAnnouncementsStarted = true

	local function announcePlayerJoin(player: Player)
		serverMaid["JoinAnnouncement:" .. player.UserId] = task.spawn(function()
			task.wait(1)
			if player.Parent == Players then
				SystemChatService.BroadcastLocalPlayerJoin(player)
			end
		end)
	end

	serverMaid.PlayerAddedConnection = Players.PlayerAdded:Connect(function(player)
		announcePlayerJoin(player)
	end)

	serverMaid.PlayerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		serverMaid["JoinAnnouncement:" .. player.UserId] = nil
		SystemChatService.BroadcastLocalPlayerLeave(player.Name)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		announcePlayerJoin(player)
	end
end

function SystemChatService.ShutdownServer()
	assert(RunService:IsServer(), "ShutdownServer must be called on the server")
	promotionalLoopStarted = false
	playerAnnouncementsStarted = false
	promotionalLoopAlive = false
	serverSubscription = nil
	serverMaid:DoCleaning()
end

function SystemChatService.InitServer()
	assert(RunService:IsServer(), "InitServer must be called on the server")
	if not serverSubscription then
		local subscribeSuccess, subscribeResult = pcall(function()
			return MessagingService:SubscribeAsync(TOPIC_NAME, function(message)
				local data = message.Data
				if typeof(data) ~= "table" then
					return
				end

				if data.ServerInstanceId == serverInstanceId then
					return
				end

				local formattedMessage = data.FormattedMessage
				if typeof(formattedMessage) ~= "string" then
					return
				end

				getRemote():FireAllClients(formattedMessage)
			end)
		end)

		if subscribeSuccess then
			serverSubscription = subscribeResult
			serverMaid.ServerSubscription = subscribeResult
		else
			DebugModule.debugWarn("Failed to subscribe to global system chat topic: " .. tostring(subscribeResult), MODULE_NAME)
		end
	end

	if not serverShutdownBound then
		serverShutdownBound = true
		game:BindToClose(function()
			SystemChatService.ShutdownServer()
		end)
	end

	SystemChatService.StartPromotionalLoop()
	SystemChatService.StartPlayerAnnouncementLoop()
end

function SystemChatService.InitClient()
	assert(RunService:IsClient(), "InitClient must be called on the client")

	local function displayMessage(formattedMessage: string)
		local textChannels = TextChatService:FindFirstChild("TextChannels")
			or TextChatService:WaitForChild("TextChannels", 10)
		local generalChannel = textChannels and textChannels:FindFirstChild("RBXGeneral")
			or (textChannels and textChannels:WaitForChild("RBXGeneral", 10))

		if generalChannel and generalChannel:IsA("TextChannel") then
			generalChannel:DisplaySystemMessage(formattedMessage)
			return
		end

		local success, err = pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = formattedMessage:gsub("<[^>]->", ""),
				Color = SystemChatService.Config.DefaultColor,
			})
		end)

		if not success then
			DebugModule.debugWarn("No available chat channel for system chat: " .. tostring(err), MODULE_NAME)
		end
	end

	local remote = getRemote()
	remote.OnClientEvent:Connect(function(formattedMessage: string)
		displayMessage(formattedMessage)
	end)
end

return SystemChatService
