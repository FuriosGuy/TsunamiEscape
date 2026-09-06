local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)

local MODULE_NAME = "ExperienceNotificationPrompt"
local notificationConfig: any = CoreConfig.experienceNotifications or {}
local alive = true
local promptThread: thread?
local promptClosedConnection: RBXScriptConnection?
local lifecycleConnection: RBXScriptConnection?
local promptAttempted = false
local promptInFlight = false

local function isExpectedPromptRaceError(errorValue: any): boolean
	local errorText = string.lower(tostring(errorValue))
	return string.find(errorText, "cannot be prompted", 1, true) ~= nil
		or string.find(errorText, "canpromptoptin", 1, true) ~= nil
end

local function cleanup()
	if not alive then
		return
	end
	alive = false
	if promptThread and coroutine.status(promptThread) ~= "dead" then
		pcall(task.cancel, promptThread)
	end
	promptThread = nil
	if promptClosedConnection then
		promptClosedConnection:Disconnect()
		promptClosedConnection = nil
	end
	if lifecycleConnection then
		lifecycleConnection:Disconnect()
		lifecycleConnection = nil
	end
end

local function promptForOptIn()
	if
		not alive
		or promptAttempted
		or promptInFlight
		or notificationConfig.enabled ~= true
		or notificationConfig.promptOnJoin ~= true
	then
		return
	end
	if RunService:IsStudio() and notificationConfig.studioPromptEnabled ~= true then
		return
	end

	local serviceOk, notificationService = pcall(function()
		return game:GetService("ExperienceNotificationService")
	end)
	if not serviceOk or not notificationService then
		DebugModule.debugWarn("ExperienceNotificationService unavailable", MODULE_NAME)
		return
	end
	if not promptClosedConnection then
		local connectionOk, connection = pcall(function()
			return notificationService.OptInPromptClosed:Connect(function()
				DebugModule.debugPrint("Notification opt-in prompt closed", MODULE_NAME)
			end)
		end)
		if connectionOk then
			promptClosedConnection = connection
		end
	end

	local canPromptOk, canPrompt = pcall(function()
		return notificationService:CanPromptOptInAsync()
	end)
	if not canPromptOk then
		DebugModule.debugWarn(
			"Notification opt-in eligibility check failed | error=" .. tostring(canPrompt),
			MODULE_NAME
		)
		return
	end
	if canPrompt ~= true then
		promptAttempted = true
		return
	end

	promptInFlight = true
	promptAttempted = true
	local promptOk, promptError = pcall(function()
		notificationService:PromptOptIn()
	end)
	promptInFlight = false
	if not promptOk then
		if isExpectedPromptRaceError(promptError) then
			DebugModule.debugInfo("Notification opt-in prompt no longer available", MODULE_NAME)
		else
			DebugModule.debugWarn("Notification opt-in prompt failed | error=" .. tostring(promptError), MODULE_NAME)
		end
		return
	end
	DebugModule.debugPrint("Notification opt-in prompt shown", MODULE_NAME)
end

local delaySeconds = if typeof(notificationConfig.promptDelaySeconds) == "number"
	then math.max(0, notificationConfig.promptDelaySeconds)
	else 5
promptThread = task.delay(delaySeconds, function()
	promptThread = nil
	promptForOptIn()
end)

lifecycleConnection = script.Destroying:Connect(cleanup)
