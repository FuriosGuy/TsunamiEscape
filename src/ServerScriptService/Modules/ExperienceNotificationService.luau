local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(game:GetService("ServerScriptService").Modules.Shared:WaitForChild("CoreConfig_Server"))
local DebugModule = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("DebugModule"))

local MODULE_NAME = "ExperienceNotificationService"
local MAX_LAUNCH_DATA_BYTES = 200

type NotificationKey =
	"DailyRewardReady"
	| "SpinWheelReady"
	| "GroupRewardReady"
	| "BloodMoonLive"
	| "AdminAbuseLive"
	| "TwoXWeekendLive"

export type SendResult = {
	success: boolean,
	reason: string,
	statusCode: number?,
	notificationId: string?,
}

type UserNotificationApi = {
	createUserNotification: (userId: number, request: any) -> any,
}

local ExperienceNotificationService = {}
local notificationConfig: any = CoreConfig.experienceNotifications or {}
local sendsByPlayer: { [Player]: number } = {}
local sentKeysByPlayer: { [Player]: { [string]: boolean } } = {}
local sentUtcDayByPlayer: { [Player]: string } = {}
local retryAfterByPlayer: { [Player]: { [string]: number } } = {}
local missingPackageWarningShown = false
local initialized = false
local TRANSIENT_RETRY_COOLDOWN_SECONDS = 30

local function logSkipped(key: NotificationKey, reason: string, source: string?): ()
	DebugModule.debugInfo(
		"Notification skipped | key=" .. key .. " | reason=" .. reason .. " | source=" .. tostring(source),
		MODULE_NAME
	)
end

local function result(success: boolean, reason: string, statusCode: number?, notificationId: string?): SendResult
	return {
		success = success,
		reason = reason,
		statusCode = statusCode,
		notificationId = notificationId,
	}
end

local function getResponseError(response: any): (string?, string?)
	if typeof(response) ~= "table" or typeof(response.error) ~= "table" then
		return nil, nil
	end

	local errorCode = if typeof(response.error.code) == "string" then response.error.code else nil
	local errorMessage = if typeof(response.error.message) == "string" then response.error.message else nil
	return errorCode, errorMessage
end

local function isTransientFailure(statusCode: number?, errorCode: string?, errorMessage: string?): boolean
	if statusCode == nil or statusCode >= 500 then
		return true
	end

	local errorText = string.lower(tostring(errorCode) .. " " .. tostring(errorMessage))
	return string.find(errorText, "netfail", 1, true) ~= nil
		or string.find(errorText, "timeout", 1, true) ~= nil
		or string.find(errorText, "temporar", 1, true) ~= nil
	end

local function isInTransientBackoff(player: Player, key: NotificationKey): boolean
	local playerRetryAfter = retryAfterByPlayer[player]
	local retryAt = playerRetryAfter and playerRetryAfter[key]
	return typeof(retryAt) == "number" and os.clock() < retryAt
end

local function markTransientFailure(player: Player, key: NotificationKey)
	local playerRetryAfter = retryAfterByPlayer[player]
	if not playerRetryAfter then
		playerRetryAfter = {}
		retryAfterByPlayer[player] = playerRetryAfter
	end
	playerRetryAfter[key] = os.clock() + TRANSIENT_RETRY_COOLDOWN_SECONDS
end

local function getUserNotificationApi(): UserNotificationApi?
	local openCloud = ServerScriptService:FindFirstChild("OpenCloud")
	local versionFolder = if openCloud then openCloud:FindFirstChild("V2") else nil
	local packageModule = if versionFolder then versionFolder:FindFirstChild("UserNotification") else nil

	if not packageModule or not packageModule:IsA("ModuleScript") then
		if not missingPackageWarningShown then
			missingPackageWarningShown = true
			DebugModule.debugWarn(
				"OpenCloud.V2.UserNotification package missing; platform notifications disabled",
				MODULE_NAME
			)
		end
		return nil
	end

	local ok, requiredModule = pcall(require, packageModule)
	if not ok or typeof(requiredModule) ~= "table" or typeof(requiredModule.createUserNotification) ~= "function" then
		DebugModule.debugWarn("OpenCloud.V2.UserNotification package loaded with invalid API", MODULE_NAME)
		return nil
	end

	return requiredModule :: UserNotificationApi
end

local function getMessageId(key: NotificationKey): string?
	local messageIds = notificationConfig.messageIds
	local messageId = if typeof(messageIds) == "table" then messageIds[key] else nil
	if typeof(messageId) ~= "string" or messageId == "" then
		return nil
	end

	return messageId
end

local function getCategory(key: NotificationKey): string
	local categories = notificationConfig.categories
	local category = if typeof(categories) == "table" then categories[key] else nil
	if typeof(category) ~= "string" or category == "" then
		return key
	end

	return category
end

local function getUtcDayKey(): string
	local utcDate = os.date("!*t", os.time())
	return string.format("%04d-%02d-%02d", utcDate.year, utcDate.month, utcDate.day)
end

local function sanitizeLaunchData(launchData: string?): (string?, string?)
	if launchData == nil then
		return nil, nil
	end
	if typeof(launchData) ~= "string" then
		return nil, "LaunchData must be a string"
	end
	if #launchData > MAX_LAUNCH_DATA_BYTES then
		return nil, "LaunchData exceeds 200 bytes"
	end

	return launchData, nil
end

function ExperienceNotificationService.Init()
	if initialized then
		return
	end
	initialized = true

	Players.PlayerRemoving:Connect(function(player: Player)
		sendsByPlayer[player] = nil
		sentKeysByPlayer[player] = nil
		sentUtcDayByPlayer[player] = nil
		retryAfterByPlayer[player] = nil
	end)
end

function ExperienceNotificationService.Send(
	player: Player,
	key: NotificationKey,
	launchData: string?,
	source: string?
): SendResult
	ExperienceNotificationService.Init()

	if notificationConfig.enabled ~= true then
		logSkipped(key, "Disabled", source)
		return result(false, "Disabled", nil, nil)
	end
	if RunService:IsStudio() and notificationConfig.studioEnabled ~= true then
		logSkipped(key, "StudioDisabled", source)
		return result(false, "StudioDisabled", nil, nil)
	end
	local allowedUniverseIds = notificationConfig.allowedUniverseIds
	if typeof(allowedUniverseIds) == "table" and allowedUniverseIds[game.GameId] ~= true then
		logSkipped(key, "UniverseDisabled", source)
		return result(false, "UniverseDisabled", nil, nil)
	end
	if not player:IsA("Player") or player.Parent ~= Players then
		logSkipped(key, "PlayerUnavailable", source)
		return result(false, "PlayerUnavailable", nil, nil)
	end

	local messageId = getMessageId(key)
	if not messageId then
		DebugModule.debugWarn("Missing message ID | key=" .. key, MODULE_NAME)
		return result(false, "MissingMessageId", nil, nil)
	end

	local safeLaunchData, launchDataError = sanitizeLaunchData(launchData)
	if launchDataError then
		DebugModule.debugWarn("Notification rejected | key=" .. key .. " | reason=" .. launchDataError, MODULE_NAME)
		return result(false, launchDataError, nil, nil)
	end

	local configuredMaxSends = notificationConfig.maxSendsPerPlayerSession
	local maxSends = if typeof(configuredMaxSends) == "number"
		then math.floor(configuredMaxSends)
		else nil
	local sendCount = sendsByPlayer[player] or 0
	if maxSends and maxSends > 0 and sendCount >= maxSends then
		logSkipped(key, "SessionBudgetReached", source)
		return result(false, "SessionBudgetReached", nil, nil)
	end

	local configuredDailyLimit = notificationConfig.maxNotificationsPerPlayerPerUtcDay
	local dailyLimit = if typeof(configuredDailyLimit) == "number"
		then math.max(0, math.floor(configuredDailyLimit))
		else 1
	local utcDayKey = getUtcDayKey()
	if dailyLimit > 0 and sentUtcDayByPlayer[player] == utcDayKey then
		logSkipped(key, "DailyDeliveryLimitReached", source)
		return result(false, "DailyDeliveryLimitReached", nil, nil)
	end

	local sentKeys = sentKeysByPlayer[player]
	if not sentKeys then
		sentKeys = {}
		sentKeysByPlayer[player] = sentKeys
	end
	if sentKeys[key] then
		logSkipped(key, "AlreadySentThisSession", source)
		return result(false, "AlreadySentThisSession", nil, nil)
	end
	if isInTransientBackoff(player, key) then
		logSkipped(key, "TransientRetryBackoff", source)
		return result(false, "TransientRetryBackoff", nil, nil)
	end

	local api = getUserNotificationApi()
	if not api then
		logSkipped(key, "MissingNotificationApi", source)
		return result(false, "MissingNotificationApi", nil, nil)
	end

	local request: any = {
		payload = {
			messageId = messageId,
			type = "MOMENT",
			analyticsData = {
				category = getCategory(key),
			},
		},
	}
	if safeLaunchData then
		request.payload.joinExperience = {
			launchData = safeLaunchData,
		}
	end

	local ok, response = pcall(function()
		return api.createUserNotification(player.UserId, request)
	end)
	if not ok then
		markTransientFailure(player, key)
		DebugModule.debugInfo(
			"Notification temporarily unavailable | key="
				.. key
				.. " | retryAfterSeconds="
				.. tostring(TRANSIENT_RETRY_COOLDOWN_SECONDS)
				.. " | source="
				.. tostring(source)
				.. " | error="
				.. tostring(response),
			MODULE_NAME
		)
		return result(false, "TransientNetworkFailure", nil, nil)
	end

	local statusCode = if typeof(response) == "table" and typeof(response.statusCode) == "number"
		then response.statusCode
		else nil
	if statusCode ~= 200 then
		local errorCode, errorMessage = getResponseError(response)
		if isTransientFailure(statusCode, errorCode, errorMessage) then
			markTransientFailure(player, key)
			DebugModule.debugInfo(
				"Notification temporarily unavailable | key="
					.. key
					.. " | statusCode="
					.. tostring(statusCode)
					.. " | retryAfterSeconds="
					.. tostring(TRANSIENT_RETRY_COOLDOWN_SECONDS)
					.. " | source="
					.. tostring(source),
				MODULE_NAME
			)
			return result(false, "TransientNetworkFailure", statusCode, nil)
		end

		local errorDetails = if typeof(response) == "table" and typeof(response.error) == "table"
			then " | errorCode=" .. tostring(response.error.code) .. " | errorMessage=" .. tostring(
				response.error.message
			)
			else ""
		DebugModule.debugWarn(
			"Notification rejected by API | key="
				.. key
				.. " | statusCode="
				.. tostring(statusCode)
				.. errorDetails
				.. " | source="
				.. tostring(source),
			MODULE_NAME
		)
		return result(false, "ApiRejected", statusCode, nil)
	end

	local responseData = if typeof(response) == "table" and typeof(response.response) == "table"
		then response.response
		else nil
	local notificationId = if responseData and typeof(responseData.id) == "string" then responseData.id else nil
	sendsByPlayer[player] = sendCount + 1
	sentKeys[key] = true
	sentUtcDayByPlayer[player] = utcDayKey
	DebugModule.debugPrint(
		"Notification accepted | player="
			.. player.Name
			.. " | userId="
			.. tostring(player.UserId)
			.. " | key="
			.. key
			.. " | messageId="
			.. messageId
			.. " | statusCode="
			.. tostring(statusCode)
			.. " | notificationId="
			.. tostring(notificationId)
			.. " | category="
			.. getCategory(key)
			.. " | source="
			.. tostring(source),
		MODULE_NAME
	)
	return result(true, "Sent", statusCode, notificationId)
end

return ExperienceNotificationService
