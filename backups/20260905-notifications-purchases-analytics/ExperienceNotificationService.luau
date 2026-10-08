--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)

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
local missingPackageWarningShown = false
local initialized = false

local function result(success: boolean, reason: string, statusCode: number?, notificationId: string?): SendResult
	return {
		success = success,
		reason = reason,
		statusCode = statusCode,
		notificationId = notificationId,
	}
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
		DebugModule.debugWarn(
			"OpenCloud.V2.UserNotification package loaded with invalid API",
			MODULE_NAME
		)
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
		return result(false, "Disabled", nil, nil)
	end
	if RunService:IsStudio() and notificationConfig.studioEnabled ~= true then
		return result(false, "StudioDisabled", nil, nil)
	end
	if not player:IsA("Player") or player.Parent ~= Players then
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

	local maxSends = if typeof(notificationConfig.maxSendsPerPlayerSession) == "number"
		then math.max(1, math.floor(notificationConfig.maxSendsPerPlayerSession))
		else 1
	local sendCount = sendsByPlayer[player] or 0
	if sendCount >= maxSends then
		return result(false, "SessionBudgetReached", nil, nil)
	end

	local sentKeys = sentKeysByPlayer[player]
	if not sentKeys then
		sentKeys = {}
		sentKeysByPlayer[player] = sentKeys
	end
	if sentKeys[key] then
		return result(false, "AlreadySentThisSession", nil, nil)
	end

	local api = getUserNotificationApi()
	if not api then
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
		DebugModule.debugWarn(
			"Notification request failed | key=" .. key .. " | source=" .. tostring(source) .. " | error=" .. tostring(response),
			MODULE_NAME
		)
		return result(false, "RequestFailed", nil, nil)
	end

	local statusCode = if typeof(response) == "table" and typeof(response.statusCode) == "number"
		then response.statusCode
		else nil
	if statusCode ~= 200 then
		local errorDetails = if typeof(response) == "table" and typeof(response.error) == "table"
			then " | errorCode=" .. tostring(response.error.code) .. " | errorMessage=" .. tostring(response.error.message)
			else ""
		DebugModule.debugWarn(
			"Notification rejected by API | key=" .. key .. " | statusCode=" .. tostring(statusCode) .. errorDetails .. " | source=" .. tostring(source),
			MODULE_NAME
		)
		return result(false, "ApiRejected", statusCode, nil)
	end

	local responseData = if typeof(response) == "table" and typeof(response.response) == "table" then response.response else nil
	local notificationId = if responseData and typeof(responseData.id) == "string" then responseData.id else nil
	sendsByPlayer[player] = sendCount + 1
	sentKeys[key] = true
	DebugModule.debugPrint(
		"Notification sent | key=" .. key .. " | category=" .. getCategory(key) .. " | source=" .. tostring(source),
		MODULE_NAME
	)
	return result(true, "Sent", statusCode, notificationId)
end

return ExperienceNotificationService
