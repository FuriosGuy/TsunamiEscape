local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Maid = require(ReplicatedStorage.Modules.Maid)
local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))
local CoreConfig = require(ServerScriptService.Modules.Shared:WaitForChild("CoreConfig_Server"))
local ProductService = require(script.Parent:WaitForChild("ProductService_Server"))

local SystemChatService = {}
local REMOTE_NAME = "GlobalSystemChat"
local TOPIC_NAME = "GlobalSystemChat_v1"
local MODULE_NAME = "SystemChatService_Server"
local ROBUX_ICON = utf8.char(0xE002)
local serverSubscription: RBXScriptConnection? = nil
local serverInstanceId = game.JobId ~= "" and game.JobId or ("studio-" .. tostring(os.clock()))
local promotionalLoopStarted = false
local playerAnnouncementsStarted = false
local promotionalLoopAlive = false
local serverMaid = Maid.new()
local serverShutdownBound = false
local systemChatConfig = CoreConfig.systemChat
local PURCHASE_ANNOUNCEMENT_DEDUPE_SECONDS = 10
local purchaseAnnouncementTimes: { [string]: number } = {}

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
local DEFAULT_BLOODMOON_REWARD_TEMPLATES = {
	"🌑 Earn {WINS} Blood Moon Wins to unlock {REWARD}!",
}
local DEFAULT_BLOODMOON_PROMOTIONAL_TEMPLATES = {
	"🌑 BLOOD MOON IS LIVE! Chase {REWARD} before the event ends!",
	"⚡ Want to earn Blood Moon Wins faster? Try {BOOST} or unlock 2X Wins!",
	"🚗 {KART} is permanent after purchase, but paid Blood Moon karts are only available while the event is live!",
	"🔥 Keep pushing toward {REWARD} and collect exclusive Blood Moon gear!",
	"🎯 Check out {KART} in the Blood Moon shop while the event is active!",
}
local DEFAULT_BLOODMOON_TIP_MESSAGES = {
	"🌑 Reach stage 16 for 1, stage 18 for 2, or stage 20 for 3 Blood Moon Wins!",
	"🔴 The waves glow red while Blood Moon is active!",
	"🎯 Stay alert and time your movement carefully!",
	"🏁 Finish your run and touch the Win button before leaving the course!",
	"🏆 Blood Moon Wins reset when the next event begins, but unlocked rewards stay yours permanently!",
}
local DEFAULT_LIVE_EVENT_MESSAGES = {
	"✨ {EVENT} is live! Check the event progress before it ends!",
	"🏆 {EVENT} is live! Earn event wins before it ends!",
}
local DEFAULT_EVENT_REWARD_TEMPLATES = {
	"🏆 Earn {WINS} {EVENT} Wins to unlock {REWARD}!",
}
local DEFAULT_EVENT_PROMOTIONAL_TEMPLATES = {
	"✨ {EVENT} is live! Chase {REWARD} before the event ends!",
	"🏎️ Keep going to earn {EVENT} Wins and unlock {REWARD}!",
}

SystemChatService.Config = {
	DefaultColor = Color3.fromRGB(254, 200, 42),
	RebirthColor = Color3.fromRGB(227, 74, 255),
	PromoColor = Color3.fromRGB(255, 255, 255),
	BloodmoonColor = if systemChatConfig and typeof(systemChatConfig.bloodmoonColor) == "Color3"
		then systemChatConfig.bloodmoonColor
		else Color3.fromRGB(255, 65, 65),
	PlayerJoinColor = Color3.fromRGB(70, 255, 120),
	PlayerLeaveColor = Color3.fromRGB(255, 70, 70),
	PromoMinDelay = if systemChatConfig and typeof(systemChatConfig.promoMinDelay) == "number"
		then math.max(1, systemChatConfig.promoMinDelay)
		else 120,
	PromoMaxDelay = if systemChatConfig and typeof(systemChatConfig.promoMaxDelay) == "number"
		then math.max(1, systemChatConfig.promoMaxDelay)
		else 300,
	BloodmoonSelectionWeight = if systemChatConfig
			and typeof(systemChatConfig.bloodmoonSelectionWeight) == "number"
		then math.max(1, math.floor(systemChatConfig.bloodmoonSelectionWeight))
		else 4,
	NormalSelectionWeight = if systemChatConfig and typeof(systemChatConfig.normalSelectionWeight) == "number"
		then math.max(1, math.floor(systemChatConfig.normalSelectionWeight))
		else 1,
	LiveEventSelectionWeight = if systemChatConfig
			and typeof(systemChatConfig.liveEventSelectionWeight) == "number"
		then math.max(1, math.floor(systemChatConfig.liveEventSelectionWeight))
		else 4,
}

SystemChatService.LikeFavoriteEmojis = if systemChatConfig
		and typeof(systemChatConfig.likeFavoriteEmojis) == "table"
		and #systemChatConfig.likeFavoriteEmojis > 0
	then systemChatConfig.likeFavoriteEmojis
	else DEFAULT_LIKE_FAVORITE_EMOJIS

SystemChatService.GroupEmojis = if systemChatConfig
		and typeof(systemChatConfig.groupEmojis) == "table"
		and #systemChatConfig.groupEmojis > 0
	then systemChatConfig.groupEmojis
	else DEFAULT_GROUP_EMOJIS

SystemChatService.ShopEmojis = if systemChatConfig
		and typeof(systemChatConfig.shopEmojis) == "table"
		and #systemChatConfig.shopEmojis > 0
	then systemChatConfig.shopEmojis
	else DEFAULT_SHOP_EMOJIS

SystemChatService.LikeFavoritePromotionalMessages = if systemChatConfig
		and typeof(systemChatConfig.likeFavoritePromotionalMessages) == "table"
		and #systemChatConfig.likeFavoritePromotionalMessages > 0
	then systemChatConfig.likeFavoritePromotionalMessages
	else {
		"Favorite the game and leave a Like for more updates!",
		"Enjoying the game? Favorite it and drop a Like!",
		"Like + Favorite the game to support future content!",
		"Show some support by Liking and Favoriting the game!",
		"Like and Favorite the game if you want more awesome updates!",
	}

SystemChatService.GroupPromotionalMessages = if systemChatConfig
		and typeof(systemChatConfig.groupPromotionalMessages) == "table"
		and #systemChatConfig.groupPromotionalMessages > 0
	then systemChatConfig.groupPromotionalMessages
	else {
		"Join our group for exclusive rewards!",
		"Join our group to claim exclusive rewards!",
		"Group members get exclusive rewards, join us now!",
		"Join our group and grab your exclusive rewards!",
		"Want exclusive rewards? Join our group today!",
	}

SystemChatService.ShopPromotionalTemplates = if systemChatConfig
		and typeof(systemChatConfig.shopPromotionalTemplates) == "table"
		and #systemChatConfig.shopPromotionalTemplates > 0
	then systemChatConfig.shopPromotionalTemplates
	else DEFAULT_SHOP_PROMOTIONAL_TEMPLATES

SystemChatService.ShopPromotionOfferKeys = if systemChatConfig
		and typeof(systemChatConfig.shopPromotionOfferKeys) == "table"
		and #systemChatConfig.shopPromotionOfferKeys > 0
	then systemChatConfig.shopPromotionOfferKeys
	else DEFAULT_SHOP_PROMOTION_OFFER_KEYS

SystemChatService.BloodmoonRewardTemplates = if systemChatConfig
		and typeof(systemChatConfig.bloodmoonRewardTemplates) == "table"
		and #systemChatConfig.bloodmoonRewardTemplates > 0
	then systemChatConfig.bloodmoonRewardTemplates
	else DEFAULT_BLOODMOON_REWARD_TEMPLATES

SystemChatService.BloodmoonPromotionalTemplates = if systemChatConfig
		and typeof(systemChatConfig.bloodmoonPromotionalTemplates) == "table"
		and #systemChatConfig.bloodmoonPromotionalTemplates > 0
	then systemChatConfig.bloodmoonPromotionalTemplates
	else DEFAULT_BLOODMOON_PROMOTIONAL_TEMPLATES

SystemChatService.BloodmoonTipMessages = if systemChatConfig
		and typeof(systemChatConfig.bloodmoonTipMessages) == "table"
		and #systemChatConfig.bloodmoonTipMessages > 0
	then systemChatConfig.bloodmoonTipMessages
	else DEFAULT_BLOODMOON_TIP_MESSAGES

SystemChatService.LiveEventMessages = if systemChatConfig
		and typeof(systemChatConfig.liveEventMessages) == "table"
		and #systemChatConfig.liveEventMessages > 0
	then systemChatConfig.liveEventMessages
	else DEFAULT_LIVE_EVENT_MESSAGES

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
	TempWinBoost = "2x Win Boost",
}
local marketplaceNameCache: { [string]: string | false } = {}

local function getRandomFromPool(pool: { string }): string?
	local count = #pool
	if count <= 0 then
		return nil
	end

	return pool[math.random(1, count)]
end

local function getUsableText(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(value, "^%s*(.-)%s*$", "%1")
	if trimmed == "" or string.lower(trimmed) == "nil" then
		return nil
	end

	return trimmed
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

type EventReward = {
	name: string,
	winsRequired: number,
}

type LiveEventChatContext = {
	id: string,
	displayName: string,
	color: Color3,
	rewardTemplates: { string },
	promotionalTemplates: { string },
	tipMessages: { string },
	rewards: { EventReward },
	kartNames: { string },
}

local function getStringPool(source: any, key: string, fallback: { string }): { string }
	if typeof(source) == "table" then
		local pool = source[key]
		if typeof(pool) == "table" and #pool > 0 then
			local usablePool: { string } = {}
			for _, value in ipairs(pool) do
				local usableText = getUsableText(value)
				if usableText then
					table.insert(usablePool, usableText)
				end
			end
			if #usablePool > 0 then
				return usablePool
			end
		end
	end

	return fallback
end

local function getEventRewards(eventDefinition: { [string]: any }): { EventReward }
	local rewards: { EventReward } = {}
	local progressUi = eventDefinition.progressUi
	local unlocks = if typeof(progressUi) == "table" then progressUi.unlocks else nil
	if typeof(unlocks) ~= "table" then
		return rewards
	end

	for _, rawReward in ipairs(unlocks) do
		local rewardName = if type(rawReward) == "table"
			then getUsableText(rawReward.displayName) or getUsableText(rawReward.name)
			else nil
		if rewardName and type(rawReward) == "table" and typeof(rawReward.winsRequired) == "number" then
			table.insert(rewards, {
				name = rewardName,
				winsRequired = math.max(0, math.floor(rawReward.winsRequired)),
			})
		end
	end

	return rewards
end

local function getEventKartNames(eventId: string): { string }
	local kartNames: { string } = {}
	local eventProducts = ProductService.EventKartProducts[eventId]
	if typeof(eventProducts) ~= "table" then
		return kartNames
	end

	for productKey, productConfig in pairs(eventProducts) do
		if typeof(productKey) == "string" and typeof(productConfig) == "table" then
			local gamePassId = ProductService.Gamepasses[productKey]
			local devProductId = ProductService.DevProducts[productKey]
			local hasProduct = (typeof(gamePassId) == "number" and gamePassId > 0)
				or (typeof(devProductId) == "number" and devProductId > 0)
			if hasProduct then
				table.insert(kartNames, resolveOfferDisplayName(productKey))
			end
		end
	end

	table.sort(kartNames)
	return kartNames
end

local function getLiveEventDefinition(eventName: string): { [string]: any }?
	local liveEventsConfig = CoreConfig.liveEvents
	if typeof(liveEventsConfig) ~= "table" or typeof(liveEventsConfig.events) ~= "table" then
		return nil
	end

	for _, eventDefinition in ipairs(liveEventsConfig.events) do
		if
			type(eventDefinition) == "table"
			and typeof(eventDefinition.id) == "string"
			and string.lower(eventDefinition.id) == string.lower(eventName)
		then
			return eventDefinition
		end
	end

	return nil
end

local function getActiveEventContexts(): { LiveEventChatContext }
	local contexts: { LiveEventChatContext } = {}
	local stateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
	if not stateFolder or not stateFolder:IsA("Folder") then
		return contexts
	end

	local encodedEvents = stateFolder:GetAttribute("ActiveEvents")
	if typeof(encodedEvents) ~= "string" then
		return contexts
	end

	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, encodedEvents)
	if not ok or typeof(decoded) ~= "table" then
		return contexts
	end

	for _, eventEntry in ipairs(decoded) do
		local eventId = if typeof(eventEntry) == "table" then getUsableText(eventEntry.id) else nil
		if eventId then
			local eventDefinition = getLiveEventDefinition(eventId)
			if eventDefinition then
				local eventChatConfig = eventDefinition.systemChat
				local isBloodmoon = string.lower(eventId) == "bloodmoon"
				local rawDisplayName = if typeof(eventEntry.displayText) == "string"
					then getUsableText(eventEntry.displayText)
					else nil
				local displayName =
					string.upper(getUsableText(rawDisplayName) or getUsableText(eventDefinition.displayText) or eventId)
				local color = if isBloodmoon
					then SystemChatService.Config.BloodmoonColor
					elseif typeof(eventDefinition.displayColor) == "Color3" then eventDefinition.displayColor
					else SystemChatService.Config.DefaultColor
				table.insert(contexts, {
					id = eventId,
					displayName = displayName,
					color = color,
					rewardTemplates = getStringPool(
						eventChatConfig,
						"rewardTemplates",
						if isBloodmoon
							then SystemChatService.BloodmoonRewardTemplates
							else DEFAULT_EVENT_REWARD_TEMPLATES
					),
					promotionalTemplates = getStringPool(
						eventChatConfig,
						"promotionalTemplates",
						if isBloodmoon
							then SystemChatService.BloodmoonPromotionalTemplates
							else DEFAULT_EVENT_PROMOTIONAL_TEMPLATES
					),
					tipMessages = getStringPool(
						eventChatConfig,
						"tipMessages",
						if isBloodmoon
							then SystemChatService.BloodmoonTipMessages
							else SystemChatService.LiveEventMessages
					),
					rewards = getEventRewards(eventDefinition),
					kartNames = getEventKartNames(eventEntry.id),
				})
			end
		end
	end

	return contexts
end

local function getEventBoostNames(): { string }
	local boostNames: { string } = {}
	local temporaryWinBoostId = ProductService.DevProducts.TempWinBoost
	if typeof(temporaryWinBoostId) == "number" and temporaryWinBoostId > 0 then
		table.insert(boostNames, resolveOfferDisplayName("TempWinBoost"))
	end

	return boostNames
end

local function replaceTemplateValues(template: string, values: { [string]: string }): string
	local message = template
	for placeholder, value in pairs(values) do
		message = string.gsub(message, "{" .. placeholder .. "}", function()
			return value
		end)
	end

	return message
end

local function buildEventRewardMessage(context: LiveEventChatContext): string?
	local template = getRandomFromPool(context.rewardTemplates)
	local reward = if #context.rewards > 0 then context.rewards[math.random(1, #context.rewards)] else nil
	if not template or not reward then
		return nil
	end

	return replaceTemplateValues(template, {
		EVENT = context.displayName,
		WINS = tostring(reward.winsRequired),
		REWARD = reward.name,
	})
end

local function buildEventPromotionalMessage(context: LiveEventChatContext): string?
	local template = getRandomFromPool(context.promotionalTemplates)
	if not template then
		return nil
	end

	local rewardNames: { string } = {}
	for _, reward in ipairs(context.rewards) do
		table.insert(rewardNames, reward.name)
	end

	local reward = getRandomFromPool(rewardNames)
	local boost = getRandomFromPool(getEventBoostNames())
	local kart = getRandomFromPool(context.kartNames)
	local replacements: { [string]: string } = {
		EVENT = context.displayName,
	}

	if string.find(template, "{REWARD}", 1, true) then
		if not reward then
			return nil
		end
		replacements.REWARD = reward
	end
	if string.find(template, "{WINS}", 1, true) then
		if not reward then
			return nil
		end
		replacements.WINS = tostring(reward.winsRequired)
	end
	if string.find(template, "{BOOST}", 1, true) then
		if not boost then
			return nil
		end
		replacements.BOOST = boost
	end
	if string.find(template, "{KART}", 1, true) then
		if not kart then
			return nil
		end
		replacements.KART = kart
	end

	return replaceTemplateValues(template, replacements)
end

local function buildEventTipMessage(context: LiveEventChatContext): string?
	local template = getRandomFromPool(context.tipMessages)
	if not template then
		return nil
	end

	return replaceTemplateValues(template, {
		EVENT = context.displayName,
	})
end

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

local function buildLiveEventMessage(context: LiveEventChatContext): string
	local template = getRandomFromPool(SystemChatService.LiveEventMessages)
	if template then
		return replaceTemplateValues(template, {
			EVENT = context.displayName,
		})
	end

	return string.format("%s is live! Check the event progress before it ends!", context.displayName)
end

local function buildEventMessage(context: LiveEventChatContext): string
	local messageType = math.random(1, 3)
	if messageType == 1 then
		return buildEventTipMessage(context) or buildLiveEventMessage(context)
	elseif messageType == 2 then
		return buildEventRewardMessage(context) or buildEventTipMessage(context) or buildLiveEventMessage(context)
	end

	return buildEventPromotionalMessage(context) or buildEventTipMessage(context) or buildLiveEventMessage(context)
end

local function buildScheduledMessage(): (string?, Color3?, string?)
	local activeEvents = getActiveEventContexts()
	if #activeEvents == 0 then
		return buildPromotionalMessage(), SystemChatService.Config.PromoColor, nil
	end

	local eventWeight = SystemChatService.Config.LiveEventSelectionWeight
	local normalWeight = SystemChatService.Config.NormalSelectionWeight
	local totalWeight = eventWeight + normalWeight
	local chooseEvent = math.random(1, totalWeight) <= eventWeight

	if chooseEvent then
		local activeEvent = activeEvents[math.random(1, #activeEvents)]
		local message = buildEventMessage(activeEvent)
		if message then
			return message, activeEvent.color, activeEvent.id
		end
	end

	return buildPromotionalMessage(), SystemChatService.Config.PromoColor, nil
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

function SystemChatService.FormatPurchaseMessage(
	playerName: string,
	itemName: string,
	price: number,
	color: Color3?
): string
	local message = string.format("[SYSTEM]: %s just bought '%s' for %s %d!", playerName, itemName, ROBUX_ICON, price)
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
	local message =
		string.format("[SYSTEM]: %s just rebirthed for the %s time!", playerName, formatOrdinal(rebirthCount))
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

local function shouldBroadcastPurchase(dedupeKey: string): boolean
	local now = os.clock()
	for key, timestamp in pairs(purchaseAnnouncementTimes) do
		if now - timestamp >= PURCHASE_ANNOUNCEMENT_DEDUPE_SECONDS then
			purchaseAnnouncementTimes[key] = nil
		end
	end

	local previousTimestamp = purchaseAnnouncementTimes[dedupeKey]
	if previousTimestamp and now - previousTimestamp < PURCHASE_ANNOUNCEMENT_DEDUPE_SECONDS then
		DebugModule.debugInfo("Duplicate purchase announcement suppressed | key=" .. dedupeKey, MODULE_NAME)
		return false
	end

	purchaseAnnouncementTimes[dedupeKey] = now
	return true
end

function SystemChatService.BroadcastPurchase(
	player: Player,
	itemName: string,
	price: number,
	color: Color3?,
	dedupeKey: string?
)
	assert(RunService:IsServer(), "BroadcastPurchase must be called on the server")
	local resolvedDedupeKey = dedupeKey or (tostring(player.UserId) .. ":" .. itemName)
	if not shouldBroadcastPurchase(resolvedDedupeKey) then
		return
	end

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
			local delayTime =
				randomSteppedInteger(SystemChatService.Config.PromoMinDelay, SystemChatService.Config.PromoMaxDelay)
			task.wait(delayTime)
			if not promotionalLoopAlive then
				break
			end

			local message, messageColor, eventId = buildScheduledMessage()
			if not message then
				continue
			end

			-- Recheck immediately before sending so a message selected during an event
			-- cannot leak after LiveEventService has published the event end.
			if eventId then
				local eventStillActive = false
				for _, currentEvent in ipairs(getActiveEventContexts()) do
					if string.lower(currentEvent.id) == string.lower(eventId) then
						eventStillActive = true
						break
					end
				end
				if not eventStillActive then
					continue
				end
			end

			SystemChatService.BroadcastLocalMessage("[SYSTEM]: " .. message, messageColor)
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
	table.clear(purchaseAnnouncementTimes)
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
			DebugModule.debugWarn(
				"Failed to subscribe to global system chat topic: " .. tostring(subscribeResult),
				MODULE_NAME
			)
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

return SystemChatService
