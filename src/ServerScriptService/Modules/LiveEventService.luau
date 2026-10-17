local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CoreConfig = require(game:GetService("ServerScriptService").Modules.Shared:WaitForChild("CoreConfig_Server"))
local DebugModule = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("DebugModule"))
local HalloweenEventConfig = require(ReplicatedStorage.Modules.Config.HalloweenEventConfig)
local Maid = require(Modules:WaitForChild("Maid"))
local PlayerHandler = require(script.Parent.Shared:WaitForChild("PlayerHandler_Server"))
local LiveEventSchedule = require(script.Parent:WaitForChild("LiveEventSchedule"))

local LiveEventService = {}

type LiveEventEffects = {
	xpMultiplier: number?,
	winButtonMultiplier: number?,
	walkSpeedMultiplier: number?,
	luckMultiplier: number?,
}

type LiveEventUnlock = {
	id: string?,
	displayName: string?,
	winsRequired: number?,
	kind: string?,
	imageAssetId: string?,
}

type LiveEventProgressUi = {
	backgroundColor: Color3?,
	gradientColor: Color3?,
	infoText: string?,
	winsAttribute: string?,
	maxWins: number?,
	showUnlocks: boolean?,
	unlocks: { LiveEventUnlock }?,
}

type LiveEventBlockUi = {
	billboardText: string?,
	infoText: string?,
	textColor: Color3?,
	gradientColor: Color3?,
}

type LiveEventDefinition = {
	id: string?,
	eventTier: "Major" | "Minor"?,
	enabled: boolean?,
	priority: number?,
	displayText: string?,
	displayColor: Color3?,
	multiplierChoices: { number }?,
	multiplierRandomSeed: number?,
	winPopupImageAssetId: string?,
	startText: string?,
	startSound: string?,
	showCountdown: boolean?,
	environmentName: string?,
	debugStudioEnabled: boolean?,
	debugStudioStartAfterSeconds: number?,
	debugStudioDurationSeconds: number?,
	debugStudioGraceDurationSeconds: number?,
	debugStudioForceActiveAfterSeconds: number?,
	preEventCountdownSeconds: number?,
	eventBlockCountdownSeconds: number?,
	kartWinsAttribute: string?,
	kartRequirementLabel: string?,
	stageWinAwards: { any }?,
	schedule: any,
	effects: LiveEventEffects?,
	progressUi: LiveEventProgressUi?,
	eventBlockUi: LiveEventBlockUi?,
}

type UpcomingEvent = {
	definition: LiveEventDefinition,
	startsAtUnix: number,
}

type EventTier = "Major" | "Minor"

type LiveEventRotationConfig = {
	rotationStartUnix: number,
	randomSeed: number,
	version: string,
	firstEventTier: EventTier,
	firstSequenceIndex: number,
	firstEventActiveDurationSeconds: number?,
	firstEventGraceDurationSeconds: number?,
	firstEventUsesFullCountdown: boolean,
}

type RotationWindow = {
	definition: LiveEventDefinition,
	sequenceIndex: number,
	activeStartUnix: number,
	activeEndUnix: number,
	nextStartUnix: number,
}

type RotationState = {
	activeWindow: RotationWindow?,
	upcomingWindow: RotationWindow?,
}

type RotationCache = {
	rotationStartUnix: number,
	randomSeed: number,
	version: string,
	firstEventTier: EventTier,
	firstSequenceIndex: number,
	firstEventActiveDurationSeconds: number?,
	firstEventGraceDurationSeconds: number?,
	window: RotationWindow,
}

local MODULE_NAME = "LiveEventService"
local DEFAULT_REFRESH_INTERVAL = 15
local maid = Maid.new()
local initialized = false
local refreshToken = 0
local initializedAt = 0
local initializedUnixTimestamp = 0
local hasPublishedState = false
local publishedBannerActive = false
local publishedBannerText = ""
local publishedActiveIds = ""
local publishedXPMultiplier = 1
local publishedWinButtonMultiplier = 1
local publishedWalkSpeedMultiplier = 1
local publishedLuckMultiplier = 1
local publishedEnvironmentName = "Default"
local publishedUpcomingEvents = ""
local publishedEventBlockEvents = ""
local publishedBloodmoonCycleStartUnix = 0
local publishedBloodmoonNextStartUnix = 0
local studioSeasonalEnvironmentTestEnded = false
local studioDebugRandom = Random.new()
local studioDebugSelectedEventId: string? = nil
local studioDebugCycleStartedAt = 0
local liveRotationCache: RotationCache? = nil
local liveRotationWarningShown = false

local ROTATION_HASH_MODULUS = 2147483647
local ROTATION_MAX_ADVANCE_STEPS = 10000
local WEEK_SECONDS = 7 * 24 * 60 * 60

local function getStateFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild("LiveEventState")
	if existing then
		assert(existing:IsA("Folder"), "ReplicatedStorage.LiveEventState must be a Folder")
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = "LiveEventState"
	folder.Parent = ReplicatedStorage
	return folder
end

local stateFolder = getStateFolder()

local function bindEnvironmentCommand(player: Player)
	local connectionKey = "EventEnvironmentCommand_" .. tostring(player.UserId)
	maid[connectionKey] = player.Chatted:Connect(function(message: string)
		local action = string.match(string.lower(message), "^%s*/e%s+environment%s+(%a+)%s*$")
		if action ~= "on" and action ~= "off" then
			return
		end
		local isEnabled = action == "on"
		player:SetAttribute("EventEnvironmentEnabled", isEnabled)
		DebugModule.debugInfo(
			"Event environment " .. (if isEnabled then "enabled" else "disabled") .. " by " .. player.Name,
			MODULE_NAME
		)
	end)
end

local function getConfigEvents(): { LiveEventDefinition }
	local liveEventsConfig = CoreConfig.liveEvents
	if typeof(liveEventsConfig) ~= "table" or typeof(liveEventsConfig.events) ~= "table" then
		return {}
	end

	return liveEventsConfig.events :: { LiveEventDefinition }
end

local function getConfiguredStudioDebugEventId(): string?
	if not RunService:IsStudio() then
		return nil
	end

	local liveEventsConfig = CoreConfig.liveEvents
	local debugEventId = if typeof(liveEventsConfig) == "table" then liveEventsConfig.debugStudioEventId else nil
	return if typeof(debugEventId) == "string" and debugEventId ~= "" then debugEventId else nil
end

local function isRandomStudioDebugMode(): boolean
	return getConfiguredStudioDebugEventId() == "Random"
end

local function chooseRandomStudioDebugEvent(eventTier: EventTier?, excludedEventId: string?): string?
	local candidates: { string } = {}
	for _, eventDefinition in ipairs(getConfigEvents()) do
		local matchesTier = eventTier == nil or eventDefinition.eventTier == eventTier
		if
			eventDefinition.enabled ~= false
			and eventDefinition.debugStudioEnabled == true
			and matchesTier
			and typeof(eventDefinition.id) == "string"
			and typeof(eventDefinition.debugStudioDurationSeconds) == "number"
			and eventDefinition.debugStudioDurationSeconds > 0
			and eventDefinition.id ~= excludedEventId
		then
			table.insert(candidates, eventDefinition.id)
		end
	end

	if #candidates == 0 then
		return nil
	end

	return candidates[studioDebugRandom:NextInteger(1, #candidates)]
end

local function getEventTier(eventDefinition: LiveEventDefinition): EventTier?
	if eventDefinition.eventTier == "Major" or eventDefinition.eventTier == "Minor" then
		return eventDefinition.eventTier
	end
	return nil
end

local function getNextEventTier(eventDefinition: LiveEventDefinition): EventTier?
	local eventTier = getEventTier(eventDefinition)
	if eventTier == "Major" then
		return "Minor"
	end
	if eventTier == "Minor" then
		return "Major"
	end
	return nil
end

local function getLiveRotationConfig(): LiveEventRotationConfig?
	if RunService:IsStudio() then
		return nil
	end

	local liveEventsConfig = CoreConfig.liveEvents
	local rotation = if typeof(liveEventsConfig) == "table" then liveEventsConfig.rotation else nil
	if typeof(rotation) ~= "table" or rotation.enabled == false then
		return nil
	end

	local rotationStartUnix = rotation.rotationStartUnix
	if typeof(rotationStartUnix) ~= "number" or rotationStartUnix <= 0 then
		return nil
	end

	local randomSeed = if typeof(rotation.randomSeed) == "number" then rotation.randomSeed else 1
	if randomSeed ~= randomSeed or randomSeed == math.huge or randomSeed == -math.huge then
		randomSeed = 1
	end
	local firstEventTier: EventTier = if rotation.firstEventTier == "Minor" then "Minor" else "Major"
	local firstSequenceIndex: number = if typeof(rotation.firstSequenceIndex) == "number"
		then rotation.firstSequenceIndex
		else 0
	if
		typeof(firstSequenceIndex) ~= "number"
		or firstSequenceIndex ~= firstSequenceIndex
		or firstSequenceIndex == math.huge
		or firstSequenceIndex == -math.huge
		or firstSequenceIndex < 0
	then
		firstSequenceIndex = 0
	end
	local firstEventActiveDurationSeconds: number? = if typeof(rotation.firstEventActiveDurationSeconds) == "number"
		then rotation.firstEventActiveDurationSeconds
		else nil
	if
		typeof(firstEventActiveDurationSeconds) ~= "number"
		or firstEventActiveDurationSeconds <= 0
		or firstEventActiveDurationSeconds == math.huge
		or firstEventActiveDurationSeconds == -math.huge
	then
		firstEventActiveDurationSeconds = nil
	else
		firstEventActiveDurationSeconds = math.floor(firstEventActiveDurationSeconds)
	end
	local firstEventGraceDurationSeconds: number? = if typeof(rotation.firstEventGraceDurationSeconds) == "number"
		then rotation.firstEventGraceDurationSeconds
		else nil
	if
		typeof(firstEventGraceDurationSeconds) ~= "number"
		or firstEventGraceDurationSeconds < 0
		or firstEventGraceDurationSeconds == math.huge
		or firstEventGraceDurationSeconds == -math.huge
	then
		firstEventGraceDurationSeconds = nil
	else
		firstEventGraceDurationSeconds = math.floor(firstEventGraceDurationSeconds)
	end

	return {
		rotationStartUnix = math.floor(rotationStartUnix),
		randomSeed = math.floor(randomSeed),
		version = if typeof(rotation.version) == "string" and rotation.version ~= ""
			then rotation.version
			else "1",
		firstEventTier = firstEventTier,
		firstSequenceIndex = math.floor(firstSequenceIndex),
		firstEventActiveDurationSeconds = firstEventActiveDurationSeconds,
		firstEventGraceDurationSeconds = firstEventGraceDurationSeconds,
		firstEventUsesFullCountdown = rotation.firstEventUsesFullCountdown == true,
	}
end

local function getLiveRotationDurations(eventDefinition: LiveEventDefinition): (number?, number?)
	local schedule = eventDefinition.schedule
	if typeof(schedule) ~= "table" or schedule.kind ~= "RecurringWindow" then
		return nil, nil
	end

	local activeDuration = schedule.activeDurationSeconds
	local graceDuration = schedule.graceDurationSeconds
	if
		typeof(activeDuration) ~= "number"
		or activeDuration <= 0
		or activeDuration == math.huge
		or activeDuration == -math.huge
		or typeof(graceDuration) ~= "number"
		or graceDuration < 0
		or graceDuration == math.huge
		or graceDuration == -math.huge
	then
		return nil, nil
	end

	return math.floor(activeDuration), math.floor(graceDuration)
end

local function getLiveRotationCandidates(eventTier: EventTier?): { LiveEventDefinition }
	local candidates: { LiveEventDefinition } = {}
	for _, eventDefinition in ipairs(getConfigEvents()) do
		local eventId = eventDefinition.id
		local candidateTier = getEventTier(eventDefinition)
		local activeDuration, graceDuration = getLiveRotationDurations(eventDefinition)
		if
			eventDefinition.enabled ~= false
			and candidateTier ~= nil
			and (eventTier == nil or candidateTier == eventTier)
			and typeof(eventId) == "string"
			and activeDuration ~= nil
			and graceDuration ~= nil
		then
			table.insert(candidates, eventDefinition)
		end
	end

	table.sort(candidates, function(left, right)
		return (left.id or "") < (right.id or "")
	end)
	return candidates
end

local function chooseLiveRotationEvent(
	eventTier: EventTier?,
	sequenceIndex: number,
	randomSeed: number,
	excludedEventId: string?
): LiveEventDefinition?
	local candidates = getLiveRotationCandidates(eventTier)
	if #candidates == 0 then
		return nil
	end

	local tierSalt = if eventTier == "Major" then 17 elseif eventTier == "Minor" then 31 else 47
	local hash = (
		math.floor(randomSeed)
			+ math.floor(sequenceIndex) * 1103515245
			+ tierSalt * 12345
	) % ROTATION_HASH_MODULUS
	local candidateIndex = (hash % #candidates) + 1
	local candidate = candidates[candidateIndex]
	if #candidates > 1 and candidate.id == excludedEventId then
		candidateIndex = (candidateIndex % #candidates) + 1
		candidate = candidates[candidateIndex]
	end

	return candidate
end

local function createLiveRotationWindow(
	eventDefinition: LiveEventDefinition,
	sequenceIndex: number,
	activeStartUnix: number,
	activeDurationOverride: number?,
	graceDurationOverride: number?
): RotationWindow?
	local activeDuration, graceDuration = getLiveRotationDurations(eventDefinition)
	if activeDuration == nil or graceDuration == nil then
		return nil
	end
	activeDuration = activeDurationOverride or activeDuration
	if graceDurationOverride ~= nil then
		graceDuration = graceDurationOverride
	end

	local activeEndUnix = activeStartUnix + activeDuration
	return {
		definition = eventDefinition,
		sequenceIndex = sequenceIndex,
		activeStartUnix = activeStartUnix,
		activeEndUnix = activeEndUnix,
		nextStartUnix = activeEndUnix + graceDuration,
	}
end

local function getNextLiveRotationWindow(
	window: RotationWindow,
	rotationConfig: LiveEventRotationConfig
): RotationWindow?
	local nextEventTier = getNextEventTier(window.definition)
	local nextEvent = chooseLiveRotationEvent(
		nextEventTier,
		window.sequenceIndex + 1,
		rotationConfig.randomSeed,
		window.definition.id
	)
	if not nextEvent then
		if not liveRotationWarningShown then
			liveRotationWarningShown = true
			DebugModule.debugWarn(
				"No enabled live rotation event found for tier=" .. tostring(nextEventTier),
				MODULE_NAME
			)
		end
		-- Keep rotation alive if a future tier is temporarily empty.
		nextEvent = chooseLiveRotationEvent(nil, window.sequenceIndex + 1, rotationConfig.randomSeed, nil)
	end
	if not nextEvent then
		return nil
	end

	return createLiveRotationWindow(nextEvent, window.sequenceIndex + 1, window.nextStartUnix, nil, nil)
end

local function getLiveRotationState(timestamp: number): RotationState?
	local rotationConfig = getLiveRotationConfig()
	if not rotationConfig then
		liveRotationCache = nil
		return nil
	end

	local cache = liveRotationCache
	if
		not cache
		or cache.rotationStartUnix ~= rotationConfig.rotationStartUnix
		or cache.randomSeed ~= rotationConfig.randomSeed
		or cache.version ~= rotationConfig.version
		or cache.firstEventTier ~= rotationConfig.firstEventTier
		or cache.firstSequenceIndex ~= rotationConfig.firstSequenceIndex
		or cache.firstEventActiveDurationSeconds ~= rotationConfig.firstEventActiveDurationSeconds
		or cache.firstEventGraceDurationSeconds ~= rotationConfig.firstEventGraceDurationSeconds
	then
		local firstEvent = chooseLiveRotationEvent(
			rotationConfig.firstEventTier,
			rotationConfig.firstSequenceIndex,
			rotationConfig.randomSeed,
			nil
		)
		local firstWindow = if firstEvent
			then createLiveRotationWindow(
				firstEvent,
				rotationConfig.firstSequenceIndex,
				rotationConfig.rotationStartUnix,
				rotationConfig.firstEventActiveDurationSeconds,
				rotationConfig.firstEventGraceDurationSeconds
			)
			else nil
		if not firstWindow then
			if not liveRotationWarningShown then
				liveRotationWarningShown = true
				DebugModule.debugWarn(
					"No enabled live rotation " .. rotationConfig.firstEventTier .. " event found",
					MODULE_NAME
				)
			end
			return nil
		end

		cache = {
			rotationStartUnix = rotationConfig.rotationStartUnix,
			randomSeed = rotationConfig.randomSeed,
			version = rotationConfig.version,
			firstEventTier = rotationConfig.firstEventTier,
			firstSequenceIndex = rotationConfig.firstSequenceIndex,
			firstEventActiveDurationSeconds = rotationConfig.firstEventActiveDurationSeconds,
			firstEventGraceDurationSeconds = rotationConfig.firstEventGraceDurationSeconds,
			window = firstWindow,
		}
		liveRotationCache = cache
	end

	if timestamp < cache.window.activeStartUnix then
		return {
			activeWindow = nil,
			upcomingWindow = cache.window,
		}
	end

	local advanceSteps = 0
	while timestamp >= cache.window.nextStartUnix and advanceSteps < ROTATION_MAX_ADVANCE_STEPS do
		local nextWindow = getNextLiveRotationWindow(cache.window, rotationConfig)
		if not nextWindow then
			return nil
		end
		cache.window = nextWindow
		advanceSteps += 1
	end

	if timestamp >= cache.window.nextStartUnix then
		DebugModule.debugWarn("Live rotation exceeded the advance limit", MODULE_NAME)
		return nil
	end

	if timestamp < cache.window.activeEndUnix then
		return {
			activeWindow = cache.window,
			-- Resolve the immediate next window early so the server can publish its
			-- final 24-hour countdown before the active event ends.
			upcomingWindow = getNextLiveRotationWindow(cache.window, rotationConfig),
		}
	end

	return {
		activeWindow = nil,
		upcomingWindow = getNextLiveRotationWindow(cache.window, rotationConfig),
	}
end

local function usesLiveRotation(eventDefinition: LiveEventDefinition): boolean
	return not RunService:IsStudio()
		and getEventTier(eventDefinition) ~= nil
		and getLiveRotationConfig() ~= nil
end

local function getLiveRotationEventStartUnix(eventDefinition: LiveEventDefinition, timestamp: number): number?
	local rotationState = getLiveRotationState(timestamp)
	if not rotationState then
		return nil
	end

	local activeWindow = rotationState.activeWindow
	if activeWindow and activeWindow.definition.id == eventDefinition.id then
		return activeWindow.activeStartUnix
	end

	local upcomingWindow = rotationState.upcomingWindow
	if upcomingWindow and upcomingWindow.definition.id == eventDefinition.id then
		return upcomingWindow.activeStartUnix
	end

	return nil
end

local function getLiveRotationEventEndUnix(eventDefinition: LiveEventDefinition, timestamp: number): number?
	local rotationState = getLiveRotationState(timestamp)
	local activeWindow = rotationState and rotationState.activeWindow
	if activeWindow and activeWindow.definition.id == eventDefinition.id then
		return activeWindow.activeEndUnix
	end

	return nil
end

local function getConfiguredEventDefinition(eventId: string?): LiveEventDefinition?
	if typeof(eventId) ~= "string" then
		return nil
	end

	for _, eventDefinition in ipairs(getConfigEvents()) do
		if eventDefinition.id == eventId then
			return eventDefinition
		end
	end

	return nil
end

local function refreshRandomStudioDebugSelection()
	if not isRandomStudioDebugMode() then
		return
	end

	local now = os.clock()
	if studioDebugSelectedEventId == nil or studioDebugCycleStartedAt <= 0 then
		studioDebugSelectedEventId = chooseRandomStudioDebugEvent("Major", nil)
		if studioDebugSelectedEventId == nil then
			DebugModule.debugWarn("No enabled Studio debug Major event found", MODULE_NAME)
		end
		studioDebugCycleStartedAt = now
		return
	end

	local selectedDefinition = getConfiguredEventDefinition(studioDebugSelectedEventId)
	if not selectedDefinition then
		studioDebugSelectedEventId = chooseRandomStudioDebugEvent("Major", nil)
		studioDebugCycleStartedAt = now
		return
	end

	local startAfter = if typeof(selectedDefinition.debugStudioStartAfterSeconds) == "number"
		then math.max(0, selectedDefinition.debugStudioStartAfterSeconds)
		else 0
	local activeDuration = if typeof(selectedDefinition.debugStudioDurationSeconds) == "number"
		then math.max(0, selectedDefinition.debugStudioDurationSeconds)
		else 0
	local graceDuration = if typeof(selectedDefinition.debugStudioGraceDurationSeconds) == "number"
		then math.max(0, selectedDefinition.debugStudioGraceDurationSeconds)
		else 0

	if now - studioDebugCycleStartedAt >= startAfter + activeDuration then
		local previousEventId = studioDebugSelectedEventId
		local nextEventTier = getNextEventTier(selectedDefinition)
		local nextEventId = chooseRandomStudioDebugEvent(nextEventTier, previousEventId)
		if nextEventId == nil then
			DebugModule.debugWarn(
				"No enabled Studio debug event found for next tier=" .. tostring(nextEventTier),
				MODULE_NAME
			)
			-- Keep the lifecycle alive if a future configuration temporarily has
			-- no opposite-tier event. This fallback may repeat the current event.
			nextEventId = chooseRandomStudioDebugEvent(nil, nil)
		end
		studioDebugSelectedEventId = nextEventId
		-- Pick the next event as soon as the current one ends. Its countdown
		-- must describe the event that will actually start after the gap.
		studioDebugCycleStartedAt = now + graceDuration
	end
end

local function getStudioDebugEventId(): string?
	local configuredEventId = getConfiguredStudioDebugEventId()
	return if configuredEventId == "Random" then studioDebugSelectedEventId else configuredEventId
end

local function getStudioDebugCycleBaseUnix(): number
	if isRandomStudioDebugMode() and studioDebugCycleStartedAt > 0 then
		return initializedUnixTimestamp + math.max(0, studioDebugCycleStartedAt - initializedAt)
	end

	return initializedUnixTimestamp
end

local function applyPlayerMultipliers(
	player: Player,
	xpMultiplier: number,
	winButtonMultiplier: number,
	walkSpeedMultiplier: number,
	luckMultiplier: number
)
	player:SetAttribute("LiveEvent_XPMultiplier", xpMultiplier)
	player:SetAttribute("LiveEvent_WinButtonMultiplier", winButtonMultiplier)
	player:SetAttribute("LiveEvent_WalkSpeedMultiplier", walkSpeedMultiplier)
	player:SetAttribute("LiveEvent_LuckMultiplier", luckMultiplier)
end

local function getRefreshInterval(): number
	local liveEventsConfig = CoreConfig.liveEvents
	local configuredInterval = if typeof(liveEventsConfig) == "table"
		then liveEventsConfig.refreshIntervalSeconds
		else nil
	if typeof(configuredInterval) == "number" then
		return math.clamp(configuredInterval, 1, 60)
	end

	return DEFAULT_REFRESH_INTERVAL
end

local function getStudioSeasonalEnvironmentTestDuration(): number?
	if not RunService:IsStudio() then
		return nil
	end

	local seasonalEnvironment = CoreConfig.seasonalEnvironment
	if typeof(seasonalEnvironment) ~= "table"
		or seasonalEnvironment.enabled ~= true
		or seasonalEnvironment.studioTestEndingCountdownEnabled ~= true
	then
		return nil
	end

	local duration = seasonalEnvironment.studioTestEndingCountdownSeconds
	if typeof(duration) ~= "number" or duration <= 0 then
		return nil
	end

	return duration
end

local function scheduleStudioSeasonalEnvironmentTestEnd()
	local duration = getStudioSeasonalEnvironmentTestDuration()
	studioSeasonalEnvironmentTestEnded = false
	stateFolder:SetAttribute("StudioSeasonalEnvironmentTestEnded", false)
	if duration == nil then
		return
	end

	local token = refreshToken
	local countdownThread = task.delay(duration, function()
		if not initialized or token ~= refreshToken then
			return
		end

		studioSeasonalEnvironmentTestEnded = true
		LiveEventService.Refresh()
	end)
	maid.StudioSeasonalEnvironmentCountdown = function()
		if coroutine.status(countdownThread) ~= "dead" then
			pcall(task.cancel, countdownThread)
		end
	end
end

local function isEventActive(eventDefinition: LiveEventDefinition, timestamp: number): boolean
	if
		RunService:IsStudio()
		and eventDefinition.debugStudioEnabled == true
		and typeof(eventDefinition.debugStudioStartAfterSeconds) == "number"
	then
		local debugCycleStart = if isRandomStudioDebugMode() and studioDebugCycleStartedAt > 0
			then studioDebugCycleStartedAt
			else initializedAt
		local elapsed = os.clock() - debugCycleStart
		local startAfter = math.max(0, eventDefinition.debugStudioStartAfterSeconds)
		local duration = eventDefinition.debugStudioDurationSeconds
		if typeof(duration) == "number" then
			local activeDuration = math.max(0, duration)
			local graceDuration = eventDefinition.debugStudioGraceDurationSeconds
			if isRandomStudioDebugMode() then
				return elapsed >= startAfter and elapsed < startAfter + activeDuration
			end
			if typeof(graceDuration) == "number" and activeDuration > 0 then
				local cycleDuration = activeDuration + math.max(0, graceDuration)
				if elapsed < startAfter then
					return false
				end
				return (elapsed - startAfter) % cycleDuration < activeDuration
			end
			return elapsed >= startAfter and elapsed < startAfter + activeDuration
		end
		return elapsed >= startAfter
	end

	local studioDelay = eventDefinition.debugStudioForceActiveAfterSeconds
	if RunService:IsStudio() and eventDefinition.debugStudioEnabled == true and typeof(studioDelay) == "number" then
		return os.clock() - initializedAt >= math.max(0, studioDelay)
	end

	if usesLiveRotation(eventDefinition) then
		local rotationState = getLiveRotationState(timestamp)
		local activeWindow = rotationState and rotationState.activeWindow
		return activeWindow ~= nil and activeWindow.definition.id == eventDefinition.id
	end

	return LiveEventSchedule.IsActive(eventDefinition.schedule, timestamp)
end

local function getEventMultiplier(eventDefinition: LiveEventDefinition, timestamp: number): number?
	local choices = eventDefinition.multiplierChoices
	if typeof(choices) ~= "table" or #choices == 0 then
		return nil
	end

	local schedule = eventDefinition.schedule
	local cycleStartUnix = if typeof(schedule) == "table"
		then LiveEventSchedule.GetStartUnix(schedule, timestamp)
		else nil
	if typeof(cycleStartUnix) ~= "number" then
		cycleStartUnix = timestamp - timestamp % WEEK_SECONDS
	elseif isEventActive(eventDefinition, timestamp) and schedule.kind == "WeekendTokyoToPacific" then
		cycleStartUnix -= WEEK_SECONDS
	end

	local seed = eventDefinition.multiplierRandomSeed or 1
	local normalizedSeed = math.floor(math.abs(seed)) % ROTATION_HASH_MODULUS
	local normalizedStart = math.floor(math.abs(cycleStartUnix)) % ROTATION_HASH_MODULUS
	local startText = string.format("%.0f", normalizedStart)
	local hash = normalizedSeed
	for index = 1, #startText do
		hash = (hash * 65599 + string.byte(startText, index)) % ROTATION_HASH_MODULUS
	end
	local choiceIndex = (hash % #choices) + 1
	local selectedMultiplier = choices[choiceIndex]
	return if typeof(selectedMultiplier) == "number" and selectedMultiplier >= 1 then selectedMultiplier else nil
end

local function getEventDisplayText(eventDefinition: LiveEventDefinition, timestamp: number): string
	local displayText = eventDefinition.displayText or ""
	local multiplier = getEventMultiplier(eventDefinition, timestamp)
	if multiplier ~= nil then
		displayText = string.gsub(displayText, "{MULTIPLIER}", tostring(multiplier))
	end
	return string.upper(displayText)
end

local function getResolvedEventEffects(eventDefinition: LiveEventDefinition, timestamp: number): LiveEventEffects?
	local configuredEffects = eventDefinition.effects
	if not configuredEffects then
		return nil
	end

	local resolvedEffects: LiveEventEffects = table.clone(configuredEffects)
	local multiplier = getEventMultiplier(eventDefinition, timestamp)
	if multiplier ~= nil then
		resolvedEffects.xpMultiplier = multiplier
		resolvedEffects.winButtonMultiplier = multiplier
		resolvedEffects.luckMultiplier = multiplier
	end
	return resolvedEffects
end

function LiveEventService.IsEventActive(eventId: string): boolean
	if typeof(eventId) ~= "string" or eventId == "" then
		return false
	end

	local studioDebugEventId = getStudioDebugEventId()
	for _, eventDefinition in ipairs(getConfigEvents()) do
		if eventDefinition.id == eventId then
			return eventDefinition.enabled ~= false
				and (studioDebugEventId == nil or eventDefinition.id == studioDebugEventId)
				and isEventActive(eventDefinition, DateTime.now().UnixTimestamp)
		end
	end

	return false
end

local function colorToHex(color: Color3): string
	local red = math.clamp(math.round(color.R * 255), 0, 255)
	local green = math.clamp(math.round(color.G * 255), 0, 255)
	local blue = math.clamp(math.round(color.B * 255), 0, 255)
	return string.format("#%02X%02X%02X", red, green, blue)
end

local function escapeRichText(value: string): string
	local escaped = string.gsub(value, "&", "&amp;")
	escaped = string.gsub(escaped, "<", "&lt;")
	escaped = string.gsub(escaped, ">", "&gt;")
	return escaped
end

local function formatBannerText(activeEvents: { LiveEventDefinition }, timestamp: number): string
	local eventTexts: { string } = {}
	for _, eventDefinition in ipairs(activeEvents) do
		local displayText = getEventDisplayText(eventDefinition, timestamp)
		if typeof(displayText) == "string" and displayText ~= "" then
			local formattedText = escapeRichText(displayText)
			local displayColor = eventDefinition.displayColor
			if typeof(displayColor) == "Color3" then
				formattedText = string.format('<font color="%s">%s</font>', colorToHex(displayColor), formattedText)
			end
			table.insert(eventTexts, formattedText)
		end
	end

	return table.concat(eventTexts, " &amp; ")
end

local function normalizeStageWinAwards(rawAwards: any): { [number]: { minimumStage: number, amount: number } }
	local awards: { [number]: { minimumStage: number, amount: number } } = {}
	if typeof(rawAwards) ~= "table" then
		return awards
	end

	for _, rawAward in ipairs(rawAwards) do
		if typeof(rawAward) == "table" then
			local minimumStage = rawAward.minimumStage
			local amount = rawAward.amount
			if
				typeof(minimumStage) == "number"
				and minimumStage == minimumStage
				and minimumStage < math.huge
				and typeof(amount) == "number"
				and amount == amount
				and amount < math.huge
				and minimumStage >= 0
				and amount > 0
			then
				table.insert(awards, {
					minimumStage = math.floor(minimumStage),
					amount = math.floor(amount),
				})
			end
		end
	end

	table.sort(awards, function(left, right)
		return left.minimumStage < right.minimumStage
	end)
	return awards
end

local function formatStageWinAwards(rawAwards: any): string?
	local awards = normalizeStageWinAwards(rawAwards)
	if #awards == 0 then
		return nil
	end

	local descriptions: { string } = {}
	for _, award in ipairs(awards) do
		local winLabel = if award.amount == 1 then "WIN" else "WINS"
		table.insert(descriptions, string.format("STAGE %d: %d %s", award.minimumStage, award.amount, winLabel))
	end

	return table.concat(descriptions, " | ") .. "!"
end

local function serializeStageWinAwards(rawAwards: any): { [number]: { minimumStage: number, amount: number } }?
	local awards = normalizeStageWinAwards(rawAwards)
	return if #awards > 0 then awards else nil
end

local function serializeUnlocks(rawUnlocks: any, maxWins: number): { [number]: { [string]: any } }?
	if typeof(rawUnlocks) ~= "table" then
		return nil
	end

	local unlocks: { [number]: { [string]: any } } = {}
	for _, rawUnlock in ipairs(rawUnlocks) do
		if
			typeof(rawUnlock) == "table"
			and typeof(rawUnlock.id) == "string"
			and rawUnlock.id ~= ""
			and typeof(rawUnlock.displayName) == "string"
			and rawUnlock.displayName ~= ""
			and typeof(rawUnlock.winsRequired) == "number"
			and rawUnlock.winsRequired == rawUnlock.winsRequired
			and rawUnlock.winsRequired < math.huge
			and (rawUnlock.kind == "Trail" or rawUnlock.kind == "Kart")
		then
			local unlock: { [string]: any } = {
				id = rawUnlock.id,
				displayName = rawUnlock.displayName,
				winsRequired = math.clamp(math.floor(rawUnlock.winsRequired), 1, maxWins),
				kind = rawUnlock.kind,
			}
			if typeof(rawUnlock.imageAssetId) == "string" and rawUnlock.imageAssetId ~= "" then
				unlock.imageAssetId = rawUnlock.imageAssetId
			end
			table.insert(unlocks, unlock)
		end
	end

	return if #unlocks > 0 then unlocks else nil
end

local function serializeProgressUi(eventDefinition: LiveEventDefinition): { [string]: any }?
	local progressUi = eventDefinition.progressUi
	local infoText = if typeof(progressUi) == "table" and typeof(progressUi.infoText) == "string"
		and progressUi.infoText ~= ""
		then progressUi.infoText
		else formatStageWinAwards(eventDefinition.stageWinAwards)
	if
		typeof(progressUi) ~= "table"
		or typeof(progressUi.backgroundColor) ~= "Color3"
		or typeof(progressUi.gradientColor) ~= "Color3"
		or typeof(infoText) ~= "string"
		or infoText == ""
	then
		return nil
	end

	local serializedProgressUi: { [string]: any } = {
		backgroundColor = colorToHex(progressUi.backgroundColor),
		gradientColor = colorToHex(progressUi.gradientColor),
		infoText = string.upper(infoText),
	}

	local maxWins = if typeof(progressUi.maxWins) == "number"
		and progressUi.maxWins == progressUi.maxWins
		and progressUi.maxWins < math.huge
		then math.max(1, math.floor(progressUi.maxWins))
		else 100
	local unlocks = serializeUnlocks(progressUi.unlocks, maxWins)
	if unlocks then
		serializedProgressUi.unlocks = unlocks
	end

	if typeof(progressUi.winsAttribute) == "string" and progressUi.winsAttribute ~= "" then
		serializedProgressUi.winsAttribute = progressUi.winsAttribute
	end
	if typeof(progressUi.maxWins) == "number" and progressUi.maxWins == progressUi.maxWins then
		serializedProgressUi.maxWins = math.max(1, math.floor(progressUi.maxWins))
	end
	if typeof(progressUi.showUnlocks) == "boolean" then
		serializedProgressUi.showUnlocks = progressUi.showUnlocks
	end

	return serializedProgressUi
end

local function serializeEventBlockUi(eventDefinition: LiveEventDefinition): { [string]: string }?
	local eventBlockUi = eventDefinition.eventBlockUi
	if
		typeof(eventBlockUi) ~= "table"
		or typeof(eventBlockUi.billboardText) ~= "string"
		or eventBlockUi.billboardText == ""
	then
		return nil
	end

	return {
		billboardText = string.upper(eventBlockUi.billboardText),
		infoText = if typeof(eventBlockUi.infoText) == "string" then string.upper(eventBlockUi.infoText) else "",
		textColor = if typeof(eventBlockUi.textColor) == "Color3" then colorToHex(eventBlockUi.textColor) else "",
		gradientColor = if typeof(eventBlockUi.gradientColor) == "Color3"
			then colorToHex(eventBlockUi.gradientColor)
			else "",
	}
end

local function serializeEventEffects(
	eventDefinition: LiveEventDefinition,
	timestamp: number
): { [string]: number }?
	local effects = getResolvedEventEffects(eventDefinition, timestamp)
	if not effects then
		return nil
	end

	local serializedEffects: { [string]: number } = {}
	if typeof(effects.xpMultiplier) == "number" then
		serializedEffects.xpMultiplier = effects.xpMultiplier
	end
	if typeof(effects.winButtonMultiplier) == "number" then
		serializedEffects.winButtonMultiplier = effects.winButtonMultiplier
	end
	if typeof(effects.walkSpeedMultiplier) == "number" then
		serializedEffects.walkSpeedMultiplier = effects.walkSpeedMultiplier
	end
	if typeof(effects.luckMultiplier) == "number" then
		serializedEffects.luckMultiplier = effects.luckMultiplier
	end

	return if next(serializedEffects) == nil then nil else serializedEffects
end

local function getStudioEventEndUnix(eventDefinition: LiveEventDefinition, timestamp: number): number?
	if not RunService:IsStudio() or eventDefinition.debugStudioEnabled ~= true then
		return nil
	end
	local startAfter = eventDefinition.debugStudioStartAfterSeconds
	local duration = eventDefinition.debugStudioDurationSeconds
	if typeof(startAfter) ~= "number" or typeof(duration) ~= "number" then
		return nil
	end

	local startUnix = getStudioDebugCycleBaseUnix() + math.max(0, startAfter)
	local activeDuration = math.max(0, duration)
	local graceDuration = eventDefinition.debugStudioGraceDurationSeconds
	if isRandomStudioDebugMode() then
		return startUnix + activeDuration
	end
	if typeof(graceDuration) ~= "number" or activeDuration <= 0 then
		return startUnix + activeDuration
	end

	local cycleDuration = activeDuration + math.max(0, graceDuration)
	if timestamp < startUnix then
		return startUnix + activeDuration
	end

	local cycleStartUnix = startUnix + math.floor((timestamp - startUnix) / cycleDuration) * cycleDuration
	return cycleStartUnix + activeDuration
end

local function getStudioEventStartUnix(eventDefinition: LiveEventDefinition, timestamp: number): number?
	if not RunService:IsStudio() or eventDefinition.debugStudioEnabled ~= true then
		return nil
	end

	local startAfter = eventDefinition.debugStudioStartAfterSeconds
	if typeof(startAfter) ~= "number" then
		return nil
	end

	local startUnix = getStudioDebugCycleBaseUnix() + math.max(0, startAfter)
	local duration = eventDefinition.debugStudioDurationSeconds
	local graceDuration = eventDefinition.debugStudioGraceDurationSeconds
	if typeof(duration) ~= "number" or typeof(graceDuration) ~= "number" then
		return startUnix
	end

	local activeDuration = math.max(0, duration)
	if isRandomStudioDebugMode() then
		-- Random mode selects the next event at the active event's end, so
		-- this timestamp remains the selected event's actual start while it is
		-- upcoming or live. This also keeps event-win cycle resets on the real
		-- start instead of a future repeat cycle.
		return startUnix
	end

	local cycleDuration = activeDuration + math.max(0, graceDuration)
	if activeDuration <= 0 or cycleDuration <= 0 or timestamp < startUnix then
		return startUnix
	end

	local cycleStartUnix = startUnix + math.floor((timestamp - startUnix) / cycleDuration) * cycleDuration
	local cycleElapsed = (timestamp - startUnix) % cycleDuration
	return if cycleElapsed < activeDuration then cycleStartUnix else cycleStartUnix + cycleDuration
end

local function getEventStartUnix(eventDefinition: LiveEventDefinition, timestamp: number): number?
	local studioStartUnix = getStudioEventStartUnix(eventDefinition, timestamp)
	if studioStartUnix ~= nil then
		return studioStartUnix
	end
	if usesLiveRotation(eventDefinition) then
		return getLiveRotationEventStartUnix(eventDefinition, timestamp)
	end

	return LiveEventSchedule.GetStartUnix(eventDefinition.schedule, timestamp)
end

local function getEventEndUnix(eventDefinition: LiveEventDefinition, timestamp: number): number?
	local studioEndUnix = getStudioEventEndUnix(eventDefinition, timestamp)
	if studioEndUnix ~= nil then
		return studioEndUnix
	end
	if usesLiveRotation(eventDefinition) then
		return getLiveRotationEventEndUnix(eventDefinition, timestamp)
	end

	return LiveEventSchedule.GetEndUnix(eventDefinition.schedule, timestamp)
end

local function getEventPreEventCountdownSeconds(eventDefinition: LiveEventDefinition, timestamp: number, startsAtUnix: number?): number?
	if
		RunService:IsStudio()
		and eventDefinition.debugStudioEnabled == true
		and typeof(eventDefinition.debugStudioDurationSeconds) == "number"
		and typeof(eventDefinition.debugStudioGraceDurationSeconds) == "number"
	then
		if typeof(startsAtUnix) ~= "number" then
			return nil
		end

		-- The Studio cycle is authoritative for both the active event and its grace card.
		return math.max(0, startsAtUnix - timestamp)
	end
	if usesLiveRotation(eventDefinition) then
		-- Rotation events use their configured visibility window. The first
		-- rotation event receives the full-countdown exception in Refresh.
		return if typeof(eventDefinition.preEventCountdownSeconds) == "number"
			then math.max(0, eventDefinition.preEventCountdownSeconds)
			else nil
	end

	return LiveEventSchedule.GetPreEventCountdownSeconds(
		eventDefinition.schedule,
		timestamp,
		eventDefinition.preEventCountdownSeconds
	)
end

local function isFirstRotationEventUpcoming(eventDefinition: LiveEventDefinition, timestamp: number): boolean
	local rotationConfig = getLiveRotationConfig()
	if not rotationConfig or not rotationConfig.firstEventUsesFullCountdown then
		return false
	end

	local rotationState = getLiveRotationState(timestamp)
	local upcomingWindow = rotationState and rotationState.upcomingWindow
	return upcomingWindow ~= nil
		and upcomingWindow.sequenceIndex == rotationConfig.firstSequenceIndex
		and upcomingWindow.definition.id == eventDefinition.id
end

local function getBloodmoonCycleStartUnix(activeEvents: { LiveEventDefinition }, timestamp: number): number
	for _, eventDefinition in ipairs(activeEvents) do
		if eventDefinition.id == "Bloodmoon" then
			local cycleStartUnix = getEventStartUnix(eventDefinition, timestamp)
			if typeof(cycleStartUnix) == "number" and cycleStartUnix > 0 then
				return math.floor(cycleStartUnix)
			end
		end
	end

	return 0
end

local function syncBloodmoonCycle(player: Player, cycleStartUnix: number)
	if cycleStartUnix <= 0 or player:GetAttribute("Data_Loaded") ~= true then
		return
	end

	if PlayerHandler.ResetBloodmoonWinsForCycle(player, cycleStartUnix) then
		DebugModule.debugInfo(
			"Reset Bloodmoon wins for new event cycle | player="
				.. player.Name
				.. " | cycleStartUnix="
				.. tostring(cycleStartUnix),
			MODULE_NAME
		)
	end
end

local function syncEventCycle(player: Player, eventDefinition: LiveEventDefinition, timestamp: number)
	if player:GetAttribute("Data_Loaded") ~= true then
		return
	end

	local eventId = eventDefinition.id
	local winsAttribute = eventDefinition.kartWinsAttribute
	if typeof(eventId) ~= "string" or typeof(winsAttribute) ~= "string" or winsAttribute == "" then
		return
	end

	local cycleStartUnix = getEventStartUnix(eventDefinition, timestamp)
	if typeof(cycleStartUnix) ~= "number" or cycleStartUnix <= 0 then
		return
	end

	if PlayerHandler.ResetEventWinsForCycle(player, eventId, cycleStartUnix) then
		DebugModule.debugInfo(
			"Reset event wins for new cycle | event="
				.. eventId
				.. " | player="
				.. player.Name
				.. " | cycleStartUnix="
				.. tostring(math.floor(cycleStartUnix)),
			MODULE_NAME
		)
	end
end

local function syncConfiguredEventCycles(player: Player, timestamp: number)
	local studioDebugEventId = getStudioDebugEventId()
	for _, eventDefinition in ipairs(getConfigEvents()) do
		if
			eventDefinition.enabled ~= false
			and (studioDebugEventId == nil or eventDefinition.id == studioDebugEventId)
			and isEventActive(eventDefinition, timestamp)
		then
			syncEventCycle(player, eventDefinition, timestamp)
		end
	end
end

local function encodeActiveEvents(activeEvents: { LiveEventDefinition }, timestamp: number): string
	local serializedEvents: { [number]: { [string]: any } } = {}
	for _, eventDefinition in ipairs(activeEvents) do
		if typeof(eventDefinition.id) == "string" and typeof(eventDefinition.displayText) == "string" then
			local displayColor = if typeof(eventDefinition.displayColor) == "Color3"
				then colorToHex(eventDefinition.displayColor)
				else ""
			table.insert(serializedEvents, {
				id = eventDefinition.id,
				displayText = getEventDisplayText(eventDefinition, timestamp),
				displayColor = displayColor,
				winPopupImageAssetId = if typeof(eventDefinition.winPopupImageAssetId) == "string"
					then eventDefinition.winPopupImageAssetId
					else "",
				startText = if typeof(eventDefinition.startText) == "string"
					then string.upper(eventDefinition.startText)
					else "",
				startSound = if typeof(eventDefinition.startSound) == "string"
					then eventDefinition.startSound
					else "",
				kartWinsAttribute = eventDefinition.kartWinsAttribute or "",
				stageWinAwards = serializeStageWinAwards(eventDefinition.stageWinAwards),
				effects = serializeEventEffects(eventDefinition, timestamp),
				showCountdown = eventDefinition.showCountdown ~= false,
				environmentName = if typeof(eventDefinition.environmentName) == "string"
					then eventDefinition.environmentName
					else "",
				progressUi = serializeProgressUi(eventDefinition),
				eventBlockUi = serializeEventBlockUi(eventDefinition),
				endsAtUnix = getEventEndUnix(eventDefinition, timestamp) or 0,
			})
		end
	end

	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, serializedEvents)
	return if ok then encoded else "[]"
end

local function encodeUpcomingEvents(upcomingEvents: { UpcomingEvent }): string
	local serializedEvents: { [number]: { [string]: any } } = {}
	for _, upcomingEvent in ipairs(upcomingEvents) do
		local eventDefinition = upcomingEvent.definition
		if typeof(eventDefinition.id) == "string" and typeof(eventDefinition.displayText) == "string" then
			local displayColor = if typeof(eventDefinition.displayColor) == "Color3"
				then colorToHex(eventDefinition.displayColor)
				else ""
			table.insert(serializedEvents, {
				id = eventDefinition.id,
				displayText = getEventDisplayText(eventDefinition, upcomingEvent.startsAtUnix),
				displayColor = displayColor,
				winPopupImageAssetId = if typeof(eventDefinition.winPopupImageAssetId) == "string"
					then eventDefinition.winPopupImageAssetId
					else "",
				startText = if typeof(eventDefinition.startText) == "string"
					then string.upper(eventDefinition.startText)
					else "",
				startSound = if typeof(eventDefinition.startSound) == "string"
					then eventDefinition.startSound
					else "",
				kartWinsAttribute = eventDefinition.kartWinsAttribute or "",
				stageWinAwards = serializeStageWinAwards(eventDefinition.stageWinAwards),
				effects = serializeEventEffects(eventDefinition, upcomingEvent.startsAtUnix),
				environmentName = if typeof(eventDefinition.environmentName) == "string"
					then eventDefinition.environmentName
					else "",
				eventBlockUi = serializeEventBlockUi(eventDefinition),
				startsAtUnix = upcomingEvent.startsAtUnix,
			})
		end
	end

	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, serializedEvents)
	return if ok then encoded else "[]"
end

local function scheduleRefresh()
	local token = refreshToken
	local refreshDelay = getRefreshInterval()
	local nextHalloweenUnlock = HalloweenEventConfig.GetNextUnlockUnixTimestamp(DateTime.now().UnixTimestamp)
	if nextHalloweenUnlock then
		refreshDelay = math.min(refreshDelay, math.max(nextHalloweenUnlock - DateTime.now().UnixTimestamp, 0.1))
	end
	local refreshThread = task.delay(refreshDelay, function()
		if not initialized or token ~= refreshToken then
			return
		end

		LiveEventService.Refresh()
		scheduleRefresh()
	end)
	-- A completed task.delay thread cannot be cancelled. Maid owns a guarded
	-- cleanup closure instead of the raw thread so recurring scheduling stays quiet.
	maid.RefreshThread = function()
		pcall(task.cancel, refreshThread)
	end
end

function LiveEventService.Refresh()
	refreshRandomStudioDebugSelection()
	local timestamp = DateTime.now().UnixTimestamp
	local activeEvents: { LiveEventDefinition } = {}
	local upcomingEvents: { UpcomingEvent } = {}
	local eventBlockEvents: { UpcomingEvent } = {}
	local xpMultiplier = 1
	local winButtonMultiplier = 1
	local walkSpeedMultiplier = 1
	local luckMultiplier = 1
	local bloodmoonNextStartUnix = 0
	local studioDebugEventId = getStudioDebugEventId()

	for _, eventDefinition in ipairs(getConfigEvents()) do
		if eventDefinition.enabled ~= false and (studioDebugEventId == nil or eventDefinition.id == studioDebugEventId) then
			if isEventActive(eventDefinition, timestamp) then
				table.insert(activeEvents, eventDefinition)
				local effects = getResolvedEventEffects(eventDefinition, timestamp)
				if effects then
					if typeof(effects.xpMultiplier) == "number" then
						xpMultiplier *= math.max(0, effects.xpMultiplier)
					end
					if typeof(effects.winButtonMultiplier) == "number" then
						winButtonMultiplier *= math.max(0, effects.winButtonMultiplier)
					end
					if typeof(effects.walkSpeedMultiplier) == "number" then
						walkSpeedMultiplier *= math.max(0, effects.walkSpeedMultiplier)
					end
					if typeof(effects.luckMultiplier) == "number" then
						luckMultiplier *= math.max(0, effects.luckMultiplier)
					end
				end
			else
				local startsAtUnix = getEventStartUnix(eventDefinition, timestamp)
				local preEventCountdownSeconds = getEventPreEventCountdownSeconds(eventDefinition, timestamp, startsAtUnix)
				local isLiveRotationEvent = usesLiveRotation(eventDefinition)
				local isFirstRotationEvent = isFirstRotationEventUpcoming(eventDefinition, timestamp)
				if
					typeof(startsAtUnix) == "number"
					and startsAtUnix > timestamp
				then
					-- EventBlock countdowns are independent from the event-list
					-- visibility window. Publish the next event even when it is
					-- more than 24 hours away.
					table.insert(eventBlockEvents, {
						definition = eventDefinition,
						startsAtUnix = startsAtUnix,
					})
				end
				if
					eventDefinition.id == "Bloodmoon"
					and typeof(startsAtUnix) == "number"
					and startsAtUnix > timestamp
					and (
						isLiveRotationEvent
							or (
								typeof(eventDefinition.eventBlockCountdownSeconds) == "number"
								and startsAtUnix - timestamp <= math.max(0, eventDefinition.eventBlockCountdownSeconds)
							)
					)
				then
					bloodmoonNextStartUnix = math.floor(startsAtUnix)
				end
				if
					typeof(startsAtUnix) == "number"
					and startsAtUnix > timestamp
					and (
						isFirstRotationEvent
							or (
								typeof(preEventCountdownSeconds) == "number"
								and startsAtUnix - timestamp <= math.max(0, preEventCountdownSeconds)
							)
					)
				then
					table.insert(upcomingEvents, {
						definition = eventDefinition,
						startsAtUnix = startsAtUnix,
					})
				end
			end
		end
	end

	table.sort(activeEvents, function(a, b)
		return (a.priority or 0) > (b.priority or 0)
	end)
	table.sort(upcomingEvents, function(a, b)
		if a.startsAtUnix == b.startsAtUnix then
			return (a.definition.priority or 0) > (b.definition.priority or 0)
		end
		return a.startsAtUnix < b.startsAtUnix
	end)
	-- Keep the in-game EventFrameList focused on the first upcoming event.
	-- Active events and EventBlockEvents retain their independent behavior.
	local upcomingEventsForUi: { UpcomingEvent } = {}
	if upcomingEvents[1] then
		table.insert(upcomingEventsForUi, upcomingEvents[1])
	end
	table.sort(eventBlockEvents, function(a, b)
		if a.startsAtUnix == b.startsAtUnix then
			return (a.definition.priority or 0) > (b.definition.priority or 0)
		end
		return a.startsAtUnix < b.startsAtUnix
	end)

	local bannerText = formatBannerText(activeEvents, timestamp)
	local activeEventsJson = encodeActiveEvents(activeEvents, timestamp)
	local upcomingEventsJson = encodeUpcomingEvents(upcomingEventsForUi)
	local eventBlockEventsJson = encodeUpcomingEvents(eventBlockEvents)
	local bloodmoonCycleStartUnix = getBloodmoonCycleStartUnix(activeEvents, timestamp)
	local environmentName = "Default"
	for _, eventDefinition in ipairs(activeEvents) do
		if typeof(eventDefinition.environmentName) == "string" and eventDefinition.environmentName ~= "" then
			environmentName = eventDefinition.environmentName
			break
		end
	end
	local seasonalEnvironment = CoreConfig.seasonalEnvironment
	local utcMonth = DateTime.fromUnixTimestamp(timestamp):ToUniversalTime().Month
	local studioSeasonalTestEnded = RunService:IsStudio()
		and typeof(seasonalEnvironment) == "table"
		and seasonalEnvironment.studioTestEndingCountdownEnabled == true
		and studioSeasonalEnvironmentTestEnded
	local seasonalEnvironmentActive = typeof(seasonalEnvironment) == "table"
		and seasonalEnvironment.enabled == true
		and seasonalEnvironment.month == utcMonth
		and not studioSeasonalTestEnded
	local seasonalHalloweenHasPriority = seasonalEnvironmentActive
		and seasonalEnvironment.environmentName == "Halloween"
	if seasonalHalloweenHasPriority then
		environmentName = "Halloween"
	end
	if typeof(seasonalEnvironment) == "table"
		and seasonalEnvironment.enabled == true
		and seasonalEnvironment.month == utcMonth
		and environmentName == "Default"
		and typeof(seasonalEnvironment.environmentName) == "string"
		and seasonalEnvironment.environmentName ~= ""
		and seasonalEnvironment.environmentName ~= "Default"
		and not studioSeasonalTestEnded
	then
		environmentName = seasonalEnvironment.environmentName
	end
	stateFolder:SetAttribute("StudioSeasonalEnvironmentTestEnded", studioSeasonalTestEnded)
	local activeIds: { string } = {}
	for _, eventDefinition in ipairs(activeEvents) do
		if typeof(eventDefinition.id) == "string" then
			table.insert(activeIds, eventDefinition.id)
		end
	end

	local bannerActive = bannerText ~= ""
	local activeIdsText = table.concat(activeIds, ",")
	local halloweenPartTwoActive = typeof(seasonalEnvironment) == "table"
		and seasonalEnvironment.enabled == true
		and seasonalEnvironment.month == utcMonth
		and HalloweenEventConfig.IsDateAvailable(timestamp)
	local stateChanged = not hasPublishedState
		or bannerActive ~= publishedBannerActive
		or bannerText ~= publishedBannerText
		or activeIdsText ~= publishedActiveIds
		or xpMultiplier ~= publishedXPMultiplier
		or winButtonMultiplier ~= publishedWinButtonMultiplier
		or walkSpeedMultiplier ~= publishedWalkSpeedMultiplier
		or luckMultiplier ~= publishedLuckMultiplier
		or environmentName ~= publishedEnvironmentName
		or bloodmoonCycleStartUnix ~= publishedBloodmoonCycleStartUnix
		or bloodmoonNextStartUnix ~= publishedBloodmoonNextStartUnix
		or bloodmoonNextStartUnix ~= stateFolder:GetAttribute("BloodmoonNextStartUnix")
		or halloweenPartTwoActive ~= stateFolder:GetAttribute("HalloweenPartTwoActive")
		or seasonalEnvironmentActive ~= stateFolder:GetAttribute("SeasonalEnvironmentActive")
		or activeEventsJson ~= stateFolder:GetAttribute("ActiveEvents")
		or upcomingEventsJson ~= publishedUpcomingEvents
		or upcomingEventsJson ~= stateFolder:GetAttribute("UpcomingEvents")
		or eventBlockEventsJson ~= publishedEventBlockEvents
		or eventBlockEventsJson ~= stateFolder:GetAttribute("EventBlockEvents")
	if not stateChanged then
		return
	end

	hasPublishedState = true
	publishedBannerActive = bannerActive
	publishedBannerText = bannerText
	publishedActiveIds = activeIdsText
	publishedXPMultiplier = xpMultiplier
	publishedWinButtonMultiplier = winButtonMultiplier
	publishedWalkSpeedMultiplier = walkSpeedMultiplier
	publishedLuckMultiplier = luckMultiplier
	publishedEnvironmentName = environmentName
	publishedUpcomingEvents = upcomingEventsJson
	publishedEventBlockEvents = eventBlockEventsJson
	publishedBloodmoonCycleStartUnix = bloodmoonCycleStartUnix
	publishedBloodmoonNextStartUnix = bloodmoonNextStartUnix
	stateFolder:SetAttribute("BannerActive", bannerActive)
	stateFolder:SetAttribute("BannerText", bannerText)
	stateFolder:SetAttribute("ActiveEventIds", activeIdsText)
	stateFolder:SetAttribute("XPMultiplier", xpMultiplier)
	stateFolder:SetAttribute("WinButtonMultiplier", winButtonMultiplier)
	stateFolder:SetAttribute("WalkSpeedMultiplier", walkSpeedMultiplier)
	stateFolder:SetAttribute("LuckMultiplier", luckMultiplier)
	stateFolder:SetAttribute("EnvironmentName", environmentName)
	stateFolder:SetAttribute("HalloweenPartTwoActive", halloweenPartTwoActive)
	stateFolder:SetAttribute("SeasonalEnvironmentActive", seasonalEnvironmentActive)
	stateFolder:SetAttribute("BloodmoonCycleStartUnix", bloodmoonCycleStartUnix)
	stateFolder:SetAttribute("BloodmoonNextStartUnix", bloodmoonNextStartUnix)
	stateFolder:SetAttribute("ActiveEvents", activeEventsJson)
	stateFolder:SetAttribute("UpcomingEvents", upcomingEventsJson)
	stateFolder:SetAttribute("EventBlockEvents", eventBlockEventsJson)
	DebugModule.debugInfo(
		"Live event state updated | activeIds="
			.. activeIdsText
			.. " | upcomingId="
			.. (if upcomingEventsForUi[1] then upcomingEventsForUi[1].definition.id else "")
			.. " | environment="
			.. environmentName,
		MODULE_NAME
	)

	for _, player in ipairs(Players:GetPlayers()) do
		for _, eventDefinition in ipairs(activeEvents) do
			syncEventCycle(player, eventDefinition, timestamp)
		end
		applyPlayerMultipliers(player, xpMultiplier, winButtonMultiplier, walkSpeedMultiplier, luckMultiplier)
	end
end

function LiveEventService.Init()
	if initialized then
		return
	end
	initialized = true
	refreshToken += 1
	initializedAt = os.clock()
	initializedUnixTimestamp = DateTime.now().UnixTimestamp
	scheduleStudioSeasonalEnvironmentTestEnd()

	maid.PlayerAdded = Players.PlayerAdded:Connect(function(player: Player)
		bindEnvironmentCommand(player)
		local dataLoadedConnectionKey = "LiveEventDataLoaded_" .. tostring(player.UserId)
		maid[dataLoadedConnectionKey] = player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
			syncConfiguredEventCycles(player, DateTime.now().UnixTimestamp)
		end)

		local xpMultiplier = stateFolder:GetAttribute("XPMultiplier")
		local winButtonMultiplier = stateFolder:GetAttribute("WinButtonMultiplier")
		local walkSpeedMultiplier = stateFolder:GetAttribute("WalkSpeedMultiplier")
		local luckMultiplier = stateFolder:GetAttribute("LuckMultiplier")
		syncConfiguredEventCycles(player, DateTime.now().UnixTimestamp)
		applyPlayerMultipliers(
			player,
			if typeof(xpMultiplier) == "number" then xpMultiplier else 1,
			if typeof(winButtonMultiplier) == "number" then winButtonMultiplier else 1,
			if typeof(walkSpeedMultiplier) == "number" then walkSpeedMultiplier else 1,
			if typeof(luckMultiplier) == "number" then luckMultiplier else 1
		)
	end)
	maid.PlayerRemoving = Players.PlayerRemoving:Connect(function(player: Player)
		maid["LiveEventDataLoaded_" .. tostring(player.UserId)] = nil
		maid["EventEnvironmentCommand_" .. tostring(player.UserId)] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		bindEnvironmentCommand(player)
	end
	LiveEventService.Refresh()
	scheduleRefresh()
	DebugModule.debugPrint("Live event service initialized", MODULE_NAME)
end

function LiveEventService.Destroy()
	if not initialized then
		return
	end
	initialized = false
	refreshToken += 1
	maid:DoCleaning()
	hasPublishedState = false
	studioDebugSelectedEventId = nil
	studioDebugCycleStartedAt = 0
	liveRotationCache = nil
	liveRotationWarningShown = false

	stateFolder:SetAttribute("BannerActive", false)
	stateFolder:SetAttribute("BannerText", "")
	stateFolder:SetAttribute("ActiveEventIds", "")
	stateFolder:SetAttribute("XPMultiplier", 1)
	stateFolder:SetAttribute("WinButtonMultiplier", 1)
	stateFolder:SetAttribute("WalkSpeedMultiplier", 1)
	stateFolder:SetAttribute("LuckMultiplier", 1)
	stateFolder:SetAttribute("EnvironmentName", "Default")
	stateFolder:SetAttribute("HalloweenPartTwoActive", false)
	stateFolder:SetAttribute("SeasonalEnvironmentActive", false)
	stateFolder:SetAttribute("StudioSeasonalEnvironmentTestEnded", false)
	stateFolder:SetAttribute("BloodmoonCycleStartUnix", 0)
	stateFolder:SetAttribute("BloodmoonNextStartUnix", 0)
	stateFolder:SetAttribute("ActiveEvents", "[]")
	stateFolder:SetAttribute("UpcomingEvents", "[]")
	stateFolder:SetAttribute("EventBlockEvents", "[]")
	for _, player in ipairs(Players:GetPlayers()) do
		applyPlayerMultipliers(player, 1, 1, 1, 1)
	end
end

return LiveEventService
