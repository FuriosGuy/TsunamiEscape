--!strict

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local FunnelAnalytics = {}

local MODULE_NAME = "FunnelAnalytics"
local analyticsConfig = if CoreConfig.analytics then CoreConfig.analytics else nil
local ANALYTICS_ENABLED = if analyticsConfig and typeof(analyticsConfig.enabled) == "boolean"
	then analyticsConfig.enabled
	else true
local LIVE_SERVER_ONLY = if analyticsConfig and typeof(analyticsConfig.liveServerOnly) == "boolean"
	then analyticsConfig.liveServerOnly
	else true

type ScalarValue = string | number | boolean

export type CustomFields = {
	customField01: ScalarValue?,
	customField02: ScalarValue?,
	customField03: ScalarValue?,
}

local isInitialized = false
local onboardingStepsByUserId: { [number]: { [number]: true } } = {}
local recurringStepsByUserId: { [number]: { [string]: { [number]: true } } } = {}
local clientActionHandlers: { [string]: (Player, { [string]: any }) -> () } = {}
local clientActionLastAtByUserId: { [number]: { [string]: number } } = {}
local clientActionRemote: RemoteEvent? = nil
local didBindClientActionRemote = false
local CLIENT_ACTION_REMOTE_NAME = "FunnelAnalyticsAction"
local CLIENT_ACTION_COOLDOWN_SECONDS = 0.75
local MAX_CLIENT_ACTION_NAME_LENGTH = 64
local MAX_CLIENT_PAYLOAD_KEYS = 8

local function canSendAnalytics(): boolean
	if not ANALYTICS_ENABLED then
		return false
	end

	if not RunService:IsServer() then
		return false
	end

	if LIVE_SERVER_ONLY and RunService:IsStudio() then
		return false
	end

	return true
end

local function getUserId(player: Player): number?
	if player.Parent == nil then
		return nil
	end

	local userId = player.UserId
	if userId <= 0 then
		return nil
	end

	return userId
end

local function stringifyCustomFieldValue(value: ScalarValue): string
	if typeof(value) == "string" then
		return value
	end

	if typeof(value) == "number" then
		if value == math.huge then
			return "inf"
		end
		if value == -math.huge then
			return "-inf"
		end
		if value ~= value then
			return "nan"
		end
		return tostring(value)
	end

	return if value then "true" else "false"
end

local function sanitizeCustomFields(customFields: CustomFields?): { [string]: string }?
	if customFields == nil then
		return nil
	end

	local sanitized = {} :: { [string]: string }

	if customFields.customField01 ~= nil then
		sanitized[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] =
			stringifyCustomFieldValue(customFields.customField01)
	end

	if customFields.customField02 ~= nil then
		sanitized[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] =
			stringifyCustomFieldValue(customFields.customField02)
	end

	if customFields.customField03 ~= nil then
		sanitized[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] =
			stringifyCustomFieldValue(customFields.customField03)
	end

	if next(sanitized) == nil then
		return nil
	end

	return sanitized
end

local function sanitizeClientPayload(payload: any): { [string]: ScalarValue }
	local sanitized = {} :: { [string]: ScalarValue }
	if typeof(payload) ~= "table" then
		return sanitized
	end

	local count = 0
	for key, value in pairs(payload) do
		if typeof(key) ~= "string" then
			continue
		end
		if typeof(value) ~= "string" and typeof(value) ~= "number" and typeof(value) ~= "boolean" then
			continue
		end

		count += 1
		if count > MAX_CLIENT_PAYLOAD_KEYS then
			break
		end

		sanitized[string.sub(key, 1, 40)] = value
	end

	return sanitized
end

local function getClientActionRemote(): RemoteEvent?
	if clientActionRemote and clientActionRemote.Parent then
		return clientActionRemote
	end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		if not RunService:IsServer() then
			return nil
		end

		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local existingRemote = remotes:FindFirstChild(CLIENT_ACTION_REMOTE_NAME)
	if existingRemote and existingRemote:IsA("RemoteEvent") then
		clientActionRemote = existingRemote
		return existingRemote
	end

	if not RunService:IsServer() then
		local waitedRemote = remotes:WaitForChild(CLIENT_ACTION_REMOTE_NAME, 5)
		if waitedRemote and waitedRemote:IsA("RemoteEvent") then
			clientActionRemote = waitedRemote
			return waitedRemote
		end
		return nil
	end

	local createdRemote = Instance.new("RemoteEvent")
	createdRemote.Name = CLIENT_ACTION_REMOTE_NAME
	createdRemote.Parent = remotes
	clientActionRemote = createdRemote
	return createdRemote
end

local function bindClientActionRemote()
	if didBindClientActionRemote or not RunService:IsServer() then
		return
	end

	local remote = getClientActionRemote()
	if not remote then
		return
	end

	didBindClientActionRemote = true
	remote.OnServerEvent:Connect(function(player: Player, actionName: any, payload: any)
		if typeof(actionName) ~= "string" or actionName == "" then
			return
		end

		local sanitizedActionName = string.sub(actionName, 1, MAX_CLIENT_ACTION_NAME_LENGTH)
		local handler = clientActionHandlers[sanitizedActionName]
		if not handler then
			return
		end

		local userId = getUserId(player)
		if userId == nil then
			return
		end

		local playerCooldowns = clientActionLastAtByUserId[userId]
		if not playerCooldowns then
			playerCooldowns = {}
			clientActionLastAtByUserId[userId] = playerCooldowns
		end

		local now = os.clock()
		local lastAt = playerCooldowns[sanitizedActionName] or 0
		if now - lastAt < CLIENT_ACTION_COOLDOWN_SECONDS then
			return
		end
		playerCooldowns[sanitizedActionName] = now

		local ok, err = pcall(handler, player, sanitizeClientPayload(payload))
		if not ok then
			DebugModule.debugWarn(
				string.format(
					"Client analytics action handler failed | player=%s | action=%s | err=%s",
					player.Name,
					sanitizedActionName,
					tostring(err)
				),
				MODULE_NAME
			)
		end
	end)
end

local function getOnboardingStepCache(userId: number): { [number]: true }
	local existingCache = onboardingStepsByUserId[userId]
	if existingCache then
		return existingCache
	end

	local cache = {}
	onboardingStepsByUserId[userId] = cache
	return cache
end

local function getRecurringStepCache(userId: number, sessionId: string): { [number]: true }
	local playerCache = recurringStepsByUserId[userId]
	if not playerCache then
		playerCache = {}
		recurringStepsByUserId[userId] = playerCache
	end

	local sessionCache = playerCache[sessionId]
	if sessionCache then
		return sessionCache
	end

	sessionCache = {}
	playerCache[sessionId] = sessionCache
	return sessionCache
end

function FunnelAnalytics.Init()
	if isInitialized then
		return
	end

	isInitialized = true

	if RunService:IsServer() then
		Players.PlayerRemoving:Connect(function(player: Player)
			FunnelAnalytics.CleanupPlayer(player)
		end)
	end
end

function FunnelAnalytics.CleanupPlayer(player: Player)
	local userId = player.UserId
	if userId <= 0 then
		return
	end

	onboardingStepsByUserId[userId] = nil
	recurringStepsByUserId[userId] = nil
	clientActionLastAtByUserId[userId] = nil
end

function FunnelAnalytics.CreateSessionId(prefix: string?): string
	local guid = HttpService:GenerateGUID(false)
	if typeof(prefix) == "string" and prefix ~= "" then
		local maxPrefixLength = math.max(0, 50 - #guid - 1)
		if maxPrefixLength > 0 then
			local shortenedPrefix = string.sub(prefix, 1, maxPrefixLength)
			return string.format("%s-%s", shortenedPrefix, guid)
		end
	end

	return guid
end

function FunnelAnalytics.LogOnboardingStep(
	player: Player,
	step: number,
	stepName: string,
	customFields: CustomFields?
): boolean
	FunnelAnalytics.Init()

	local userId = getUserId(player)
	if userId == nil then
		return false
	end

	local sanitizedStep = math.floor(step)
	if sanitizedStep < 1 or sanitizedStep > 100 then
		DebugModule.debugWarn(
			string.format(
				"Invalid onboarding step ignored | player=%s | step=%s | name=%s",
				player.Name,
				tostring(step),
				stepName
			),
			MODULE_NAME
		)
		return false
	end

	local cache = getOnboardingStepCache(userId)
	if cache[sanitizedStep] == true then
		return false
	end
	cache[sanitizedStep] = true

	if not canSendAnalytics() then
		return true
	end

	local success, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(
			player,
			sanitizedStep,
			stepName,
			sanitizeCustomFields(customFields)
		)
	end)

	if not success then
		DebugModule.debugWarn(
			string.format(
				"Failed onboarding funnel log | player=%s | step=%d | name=%s | err=%s",
				player.Name,
				sanitizedStep,
				stepName,
				tostring(err)
			),
			MODULE_NAME
		)
	end

	return success
end

function FunnelAnalytics.OpenRecurringFunnel(
	player: Player,
	funnelName: string,
	firstStepName: string,
	customFields: CustomFields?
): string?
	local sessionId = FunnelAnalytics.CreateSessionId(funnelName)
	local didLog = FunnelAnalytics.LogRecurringStep(player, funnelName, sessionId, 1, firstStepName, customFields)
	if not didLog then
		return nil
	end

	return sessionId
end

function FunnelAnalytics.LogRecurringStep(
	player: Player,
	funnelName: string,
	sessionId: string,
	step: number,
	stepName: string,
	customFields: CustomFields?
): boolean
	FunnelAnalytics.Init()

	local userId = getUserId(player)
	if userId == nil then
		return false
	end

	if typeof(funnelName) ~= "string" or funnelName == "" then
		DebugModule.debugWarn(
			string.format("Recurring funnel log missing funnel name | player=%s", player.Name),
			MODULE_NAME
		)
		return false
	end

	if typeof(sessionId) ~= "string" or sessionId == "" then
		DebugModule.debugWarn(
			string.format(
				"Recurring funnel log missing session id | player=%s | funnel=%s",
				player.Name,
				funnelName
			),
			MODULE_NAME
		)
		return false
	end

	local sanitizedStep = math.floor(step)
	if sanitizedStep < 1 or sanitizedStep > 100 then
		DebugModule.debugWarn(
			string.format(
				"Invalid recurring funnel step ignored | player=%s | funnel=%s | step=%s | name=%s",
				player.Name,
				funnelName,
				tostring(step),
				stepName
			),
			MODULE_NAME
		)
		return false
	end

	local cache = getRecurringStepCache(userId, sessionId)
	if cache[sanitizedStep] == true then
		return false
	end
	cache[sanitizedStep] = true

	if not canSendAnalytics() then
		return true
	end

	local success, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(
			player,
			funnelName,
			sessionId,
			sanitizedStep,
			stepName,
			sanitizeCustomFields(customFields)
		)
	end)

	if not success then
		DebugModule.debugWarn(
			string.format(
				"Failed recurring funnel log | player=%s | funnel=%s | session=%s | step=%d | err=%s",
				player.Name,
				funnelName,
				sessionId,
				sanitizedStep,
				tostring(err)
			),
			MODULE_NAME
		)
	end

	return success
end

function FunnelAnalytics.RegisterClientAction(
	actionName: string,
	handler: (Player, { [string]: any }) -> ()
)
	assert(RunService:IsServer(), "RegisterClientAction can only be called on the server")
	assert(typeof(actionName) == "string" and actionName ~= "", "actionName must be a non-empty string")
	assert(typeof(handler) == "function", "handler must be a function")

	FunnelAnalytics.Init()
	bindClientActionRemote()
	clientActionHandlers[string.sub(actionName, 1, MAX_CLIENT_ACTION_NAME_LENGTH)] = handler
end

function FunnelAnalytics.FireClientAction(actionName: string, payload: { [string]: ScalarValue }?)
	if not RunService:IsClient() then
		return
	end

	if typeof(actionName) ~= "string" or actionName == "" then
		return
	end

	local remote = getClientActionRemote()
	if not remote then
		DebugModule.debugWarn(
			string.format("Client analytics action skipped; remote missing | action=%s", actionName),
			MODULE_NAME
		)
		return
	end

	remote:FireServer(string.sub(actionName, 1, MAX_CLIENT_ACTION_NAME_LENGTH), payload or {})
end

return FunnelAnalytics
