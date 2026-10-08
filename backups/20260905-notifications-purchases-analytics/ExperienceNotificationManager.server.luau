--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local NotificationService = require(script.Parent.Modules.ExperienceNotificationService)

local MODULE_NAME = "ExperienceNotificationManager"
local DATA_LOADED_ATTRIBUTE = "Data_Loaded"
local DAILY_REWARD_NEXT_CLAIM_ATTRIBUTE = "DailyRewardNextClaimUnix"
local SPIN_NEXT_FREE_ATTRIBUTE = "SpinWheelNextFreeSpinUnix"
local SPIN_INITIALIZED_ATTRIBUTE = "SpinWheelFreeSpinInitialized"
local GROUP_REWARD_NEXT_CLAIM_ATTRIBUTE = "VerifyRewardNextClaimUnix"
local VERIFY_GROUP_ID = CoreConfig.social.verifyGroupId

type PlayerState = {
	alive: boolean,
	dataLoadedConnection: RBXScriptConnection?,
	readinessConnections: { RBXScriptConnection },
	timerThreads: { [string]: thread },
	timerGenerations: { [string]: number },
}

local LIVE_EVENT_KEYS: { [string]: "BloodMoonLive" | "AdminAbuseLive" | "TwoXWeekendLive" } = {
	bloodmoon = "BloodMoonLive",
	adminabuse = "AdminAbuseLive",
	weekend2x = "TwoXWeekendLive",
	["2xweekend"] = "TwoXWeekendLive",
}

local LIVE_EVENT_PRIORITIES: { [string]: number } = {
	bloodmoon = 300,
	adminabuse = 200,
	weekend2x = 100,
	["2xweekend"] = 100,
}

local playerStates: { [Player]: PlayerState } = {}
local globalConnections: { RBXScriptConnection } = {}
local lifecycleConnection: RBXScriptConnection?
local alive = true
local liveEventBaselineReady = false
local previousActiveEvents: { [string]: boolean } = {}

local function getUnixAttribute(player: Player, attributeName: string): number
	local value = player:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return math.floor(value)
	end
	return 0
end

local function cancelTimer(state: PlayerState, timerName: string)
	state.timerGenerations[timerName] = (state.timerGenerations[timerName] or 0) + 1
	local thread = state.timerThreads[timerName]
	if thread and coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
	end
	state.timerThreads[timerName] = nil
end

local evaluatePlayer: (player: Player) -> ()

local function scheduleTimer(player: Player, state: PlayerState, timerName: string, dueUnix: number)
	cancelTimer(state, timerName)
	local generation = (state.timerGenerations[timerName] or 0) + 1
	state.timerGenerations[timerName] = generation
	local waitSeconds = math.max(0, dueUnix - os.time())
	state.timerThreads[timerName] = task.delay(waitSeconds, function()
		if not alive or not state.alive or player.Parent ~= Players then
			return
		end
		if state.timerGenerations[timerName] ~= generation then
			return
		end
		state.timerThreads[timerName] = nil
		evaluatePlayer(player)
	end)
end

local function trySend(player: Player, key: "DailyRewardReady" | "SpinWheelReady" | "GroupRewardReady"): boolean
	local sendResult = NotificationService.Send(player, key, "source=readiness", MODULE_NAME)
	return sendResult.success
end

local function isGroupRewardReady(player: Player, now: number): boolean
	if getUnixAttribute(player, GROUP_REWARD_NEXT_CLAIM_ATTRIBUTE) > now then
		return false
	end

	local ok, isMember = pcall(function()
		return player:IsInGroup(VERIFY_GROUP_ID)
	end)
	return ok and isMember == true
end

local function evaluateDailyReward(player: Player, state: PlayerState, now: number): boolean
	local nextClaimUnix = getUnixAttribute(player, DAILY_REWARD_NEXT_CLAIM_ATTRIBUTE)
	if nextClaimUnix <= now then
		return trySend(player, "DailyRewardReady")
	end

	scheduleTimer(player, state, "DailyReward", nextClaimUnix)
	return false
end

local function evaluateSpinWheel(player: Player, state: PlayerState, now: number): boolean
	if player:GetAttribute(SPIN_INITIALIZED_ATTRIBUTE) ~= true then
		return false
	end

	local nextFreeSpinUnix = getUnixAttribute(player, SPIN_NEXT_FREE_ATTRIBUTE)
	if nextFreeSpinUnix <= now then
		return trySend(player, "SpinWheelReady")
	end

	scheduleTimer(player, state, "SpinWheel", nextFreeSpinUnix)
	return false
end

local function evaluateGroupReward(player: Player, state: PlayerState, now: number): boolean
	local nextClaimUnix = getUnixAttribute(player, GROUP_REWARD_NEXT_CLAIM_ATTRIBUTE)
	if nextClaimUnix > now then
		scheduleTimer(player, state, "GroupReward", nextClaimUnix)
		return false
	end

	return isGroupRewardReady(player, now) and trySend(player, "GroupRewardReady")
end

evaluatePlayer = function(player: Player)
	local state = playerStates[player]
	if not alive or not state or not state.alive or player.Parent ~= Players then
		return
	end
	if player:GetAttribute(DATA_LOADED_ATTRIBUTE) ~= true then
		return
	end

	local now = os.time()
	-- Schedule every future readiness source even when session budget is used.
	evaluateDailyReward(player, state, now)
	evaluateSpinWheel(player, state, now)
	evaluateGroupReward(player, state, now)
end

local function cleanupPlayer(player: Player)
	local state = playerStates[player]
	if not state then
		return
	end
	state.alive = false
	if state.dataLoadedConnection then
		state.dataLoadedConnection:Disconnect()
		state.dataLoadedConnection = nil
	end
	for _, connection in ipairs(state.readinessConnections) do
		connection:Disconnect()
	end
	table.clear(state.readinessConnections)
	local timerNames: { string } = {}
	for timerName in pairs(state.timerThreads) do
		table.insert(timerNames, timerName)
	end
	for _, timerName in ipairs(timerNames) do
		cancelTimer(state, timerName)
	end
	playerStates[player] = nil
end

local function setupPlayer(player: Player)
	if not alive then
		return
	end
	cleanupPlayer(player)
	local state: PlayerState = {
		alive = true,
		dataLoadedConnection = nil,
		readinessConnections = {},
		timerThreads = {},
		timerGenerations = {},
	}
	playerStates[player] = state
	state.dataLoadedConnection = player:GetAttributeChangedSignal(DATA_LOADED_ATTRIBUTE):Connect(function()
		if player:GetAttribute(DATA_LOADED_ATTRIBUTE) == true then
			evaluatePlayer(player)
		end
	end)
	for _, attributeName in ipairs({
		DAILY_REWARD_NEXT_CLAIM_ATTRIBUTE,
		SPIN_NEXT_FREE_ATTRIBUTE,
		SPIN_INITIALIZED_ATTRIBUTE,
		GROUP_REWARD_NEXT_CLAIM_ATTRIBUTE,
	}) do
		table.insert(
			state.readinessConnections,
			player:GetAttributeChangedSignal(attributeName):Connect(function()
				if player:GetAttribute(DATA_LOADED_ATTRIBUTE) == true then
					evaluatePlayer(player)
				end
			end)
		)
	end
	if player:GetAttribute(DATA_LOADED_ATTRIBUTE) == true then
		evaluatePlayer(player)
	end
end

local function parseActiveEvents(): { [string]: boolean }
	local stateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
	local rawActiveEvents = if stateFolder then stateFolder:GetAttribute("ActiveEventIds") else nil
	local activeEvents: { [string]: boolean } = {}
	if typeof(rawActiveEvents) ~= "string" then
		return activeEvents
	end

	for eventId in string.gmatch(rawActiveEvents, "[^,]+") do
		local normalizedEventId = string.gsub(string.lower(eventId), "[^%w]", "")
		activeEvents[normalizedEventId] = true
	end
	return activeEvents
end

local function handleLiveEventChange()
	if not alive then
		return
	end
	local activeEvents = parseActiveEvents()
	if not liveEventBaselineReady then
		previousActiveEvents = activeEvents
		liveEventBaselineReady = true
		return
	end

	local newlyActiveEvents: { string } = {}
	for eventId in pairs(activeEvents) do
		if not previousActiveEvents[eventId] then
			table.insert(newlyActiveEvents, eventId)
		end
	end
	table.sort(newlyActiveEvents, function(firstEventId, secondEventId)
		return (LIVE_EVENT_PRIORITIES[firstEventId] or 0) > (LIVE_EVENT_PRIORITIES[secondEventId] or 0)
	end)

	for _, eventId in ipairs(newlyActiveEvents) do
		local notificationKey = LIVE_EVENT_KEYS[eventId]
		if notificationKey then
			for _, player in ipairs(Players:GetPlayers()) do
				NotificationService.Send(
					player,
					notificationKey,
					"event=" .. eventId,
					MODULE_NAME
				)
			end
		end
	end
	previousActiveEvents = activeEvents
end

local function setupLiveEventState()
	local stateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
	if not stateFolder then
		stateFolder = ReplicatedStorage:WaitForChild("LiveEventState", 10)
	end
	if not alive then
		return
	end
	if not stateFolder then
		DebugModule.debugWarn("LiveEventState not found; live-event notifications disabled", MODULE_NAME)
		return
	end
	if not stateFolder:IsA("Folder") then
		DebugModule.debugWarn("LiveEventState is not a Folder; live-event notifications disabled", MODULE_NAME)
		return
	end

	previousActiveEvents = parseActiveEvents()
	liveEventBaselineReady = true
	table.insert(globalConnections, stateFolder:GetAttributeChangedSignal("ActiveEventIds"):Connect(handleLiveEventChange))
end

local function cleanup()
	if not alive then
		return
	end
	alive = false
	for _, connection in ipairs(globalConnections) do
		connection:Disconnect()
	end
	table.clear(globalConnections)
	if lifecycleConnection then
		lifecycleConnection:Disconnect()
		lifecycleConnection = nil
	end
	local playersToClean: { Player } = {}
	for player in pairs(playerStates) do
		table.insert(playersToClean, player)
	end
	for _, player in ipairs(playersToClean) do
		cleanupPlayer(player)
	end
end

lifecycleConnection = script.Destroying:Connect(cleanup)
NotificationService.Init()
table.insert(globalConnections, Players.PlayerAdded:Connect(setupPlayer))
table.insert(globalConnections, Players.PlayerRemoving:Connect(cleanupPlayer))
for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
end
setupLiveEventState()
game:BindToClose(cleanup)
