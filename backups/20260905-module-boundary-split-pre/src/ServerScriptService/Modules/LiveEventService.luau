--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CoreConfig = require(Modules.Config:WaitForChild("CoreConfig"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local Maid = require(Modules:WaitForChild("Maid"))
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local LiveEventSchedule = require(script.Parent:WaitForChild("LiveEventSchedule"))

local LiveEventService = {}

type LiveEventEffects = {
	xpMultiplier: number?,
	winButtonMultiplier: number?,
	walkSpeedMultiplier: number?,
}

type LiveEventDefinition = {
	id: string?,
	enabled: boolean?,
	priority: number?,
	displayText: string?,
	displayColor: Color3?,
	showCountdown: boolean?,
	environmentName: string?,
	debugStudioEnabled: boolean?,
	debugStudioStartAfterSeconds: number?,
	debugStudioDurationSeconds: number?,
	debugStudioGraceDurationSeconds: number?,
	debugStudioForceActiveAfterSeconds: number?,
	preEventCountdownSeconds: number?,
	schedule: any,
	effects: LiveEventEffects?,
}

type UpcomingEvent = {
	definition: LiveEventDefinition,
	startsAtUnix: number,
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
local publishedEnvironmentName = "Default"
local publishedUpcomingEvents = ""
local publishedBloodmoonCycleStartUnix = 0

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

local function getConfigEvents(): { LiveEventDefinition }
	local liveEventsConfig = CoreConfig.liveEvents
	if typeof(liveEventsConfig) ~= "table" or typeof(liveEventsConfig.events) ~= "table" then
		return {}
	end

	return liveEventsConfig.events :: { LiveEventDefinition }
end

local function applyPlayerMultipliers(
	player: Player,
	xpMultiplier: number,
	winButtonMultiplier: number,
	walkSpeedMultiplier: number
)
	player:SetAttribute("LiveEvent_XPMultiplier", xpMultiplier)
	player:SetAttribute("LiveEvent_WinButtonMultiplier", winButtonMultiplier)
	player:SetAttribute("LiveEvent_WalkSpeedMultiplier", walkSpeedMultiplier)
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

local function isEventActive(eventDefinition: LiveEventDefinition, timestamp: number): boolean
	if
		RunService:IsStudio()
		and eventDefinition.debugStudioEnabled == true
		and typeof(eventDefinition.debugStudioStartAfterSeconds) == "number"
	then
		local elapsed = os.clock() - initializedAt
		local startAfter = math.max(0, eventDefinition.debugStudioStartAfterSeconds)
		local duration = eventDefinition.debugStudioDurationSeconds
		if typeof(duration) == "number" then
			local activeDuration = math.max(0, duration)
			local graceDuration = eventDefinition.debugStudioGraceDurationSeconds
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

	return LiveEventSchedule.IsActive(eventDefinition.schedule, timestamp)
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

local function formatBannerText(activeEvents: { LiveEventDefinition }): string
	local eventTexts: { string } = {}
	for _, eventDefinition in ipairs(activeEvents) do
		local displayText = eventDefinition.displayText
		if typeof(displayText) == "string" and displayText ~= "" then
			local formattedText = escapeRichText(string.upper(displayText))
			local displayColor = eventDefinition.displayColor
			if typeof(displayColor) == "Color3" then
				formattedText = string.format('<font color="%s">%s</font>', colorToHex(displayColor), formattedText)
			end
			table.insert(eventTexts, formattedText)
		end
	end

	return table.concat(eventTexts, " &amp; ")
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

	local startUnix = initializedUnixTimestamp + math.max(0, startAfter)
	local activeDuration = math.max(0, duration)
	local graceDuration = eventDefinition.debugStudioGraceDurationSeconds
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

	local startUnix = initializedUnixTimestamp + math.max(0, startAfter)
	local duration = eventDefinition.debugStudioDurationSeconds
	local graceDuration = eventDefinition.debugStudioGraceDurationSeconds
	if typeof(duration) ~= "number" or typeof(graceDuration) ~= "number" then
		return startUnix
	end

	local activeDuration = math.max(0, duration)
	local cycleDuration = activeDuration + math.max(0, graceDuration)
	if activeDuration <= 0 or cycleDuration <= 0 or timestamp < startUnix then
		return startUnix
	end

	local cycleStartUnix = startUnix + math.floor((timestamp - startUnix) / cycleDuration) * cycleDuration
	local cycleElapsed = (timestamp - startUnix) % cycleDuration
	return if cycleElapsed < activeDuration then cycleStartUnix else cycleStartUnix + cycleDuration
end

local function getEventStartUnix(eventDefinition: LiveEventDefinition, timestamp: number): number?
	return getStudioEventStartUnix(eventDefinition, timestamp)
		or LiveEventSchedule.GetStartUnix(eventDefinition.schedule, timestamp)
end

local function getEventEndUnix(eventDefinition: LiveEventDefinition, timestamp: number): number?
	return getStudioEventEndUnix(eventDefinition, timestamp)
		or LiveEventSchedule.GetEndUnix(eventDefinition.schedule, timestamp)
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

local function encodeActiveEvents(activeEvents: { LiveEventDefinition }, timestamp: number): string
	local serializedEvents: { [number]: { [string]: any } } = {}
	for _, eventDefinition in ipairs(activeEvents) do
		if typeof(eventDefinition.id) == "string" and typeof(eventDefinition.displayText) == "string" then
			local displayColor = if typeof(eventDefinition.displayColor) == "Color3"
				then colorToHex(eventDefinition.displayColor)
				else ""
			table.insert(serializedEvents, {
				id = eventDefinition.id,
				displayText = string.upper(eventDefinition.displayText),
				displayColor = displayColor,
				showCountdown = eventDefinition.showCountdown ~= false,
				environmentName = if typeof(eventDefinition.environmentName) == "string"
					then eventDefinition.environmentName
					else "",
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
				displayText = string.upper(eventDefinition.displayText),
				displayColor = displayColor,
				environmentName = if typeof(eventDefinition.environmentName) == "string"
					then eventDefinition.environmentName
					else "",
				startsAtUnix = upcomingEvent.startsAtUnix,
			})
		end
	end

	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, serializedEvents)
	return if ok then encoded else "[]"
end

local function scheduleRefresh()
	local token = refreshToken
	local refreshThread = task.delay(getRefreshInterval(), function()
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
	local timestamp = DateTime.now().UnixTimestamp
	local activeEvents: { LiveEventDefinition } = {}
	local upcomingEvents: { UpcomingEvent } = {}
	local xpMultiplier = 1
	local winButtonMultiplier = 1
	local walkSpeedMultiplier = 1

	for _, eventDefinition in ipairs(getConfigEvents()) do
		if eventDefinition.enabled ~= false then
			if isEventActive(eventDefinition, timestamp) then
				table.insert(activeEvents, eventDefinition)
				local effects = eventDefinition.effects
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
				end
			else
				local startsAtUnix = getEventStartUnix(eventDefinition, timestamp)
				local preEventCountdownSeconds = LiveEventSchedule.GetPreEventCountdownSeconds(
					eventDefinition.schedule,
					timestamp,
					eventDefinition.preEventCountdownSeconds
				)
				if
					typeof(startsAtUnix) == "number"
					and typeof(preEventCountdownSeconds) == "number"
					and startsAtUnix > timestamp
					and startsAtUnix - timestamp <= math.max(0, preEventCountdownSeconds)
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

	local bannerText = formatBannerText(activeEvents)
	local activeEventsJson = encodeActiveEvents(activeEvents, timestamp)
	local upcomingEventsJson = encodeUpcomingEvents(upcomingEvents)
	local bloodmoonCycleStartUnix = getBloodmoonCycleStartUnix(activeEvents, timestamp)
	local environmentName = "Default"
	for _, eventDefinition in ipairs(activeEvents) do
		if typeof(eventDefinition.environmentName) == "string" and eventDefinition.environmentName ~= "" then
			environmentName = eventDefinition.environmentName
			break
		end
	end
	local activeIds: { string } = {}
	for _, eventDefinition in ipairs(activeEvents) do
		if typeof(eventDefinition.id) == "string" then
			table.insert(activeIds, eventDefinition.id)
		end
	end

	local bannerActive = bannerText ~= ""
	local activeIdsText = table.concat(activeIds, ",")
	local stateChanged = not hasPublishedState
		or bannerActive ~= publishedBannerActive
		or bannerText ~= publishedBannerText
		or activeIdsText ~= publishedActiveIds
		or xpMultiplier ~= publishedXPMultiplier
		or winButtonMultiplier ~= publishedWinButtonMultiplier
		or walkSpeedMultiplier ~= publishedWalkSpeedMultiplier
		or environmentName ~= publishedEnvironmentName
		or bloodmoonCycleStartUnix ~= publishedBloodmoonCycleStartUnix
		or activeEventsJson ~= stateFolder:GetAttribute("ActiveEvents")
		or upcomingEventsJson ~= publishedUpcomingEvents
		or upcomingEventsJson ~= stateFolder:GetAttribute("UpcomingEvents")
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
	publishedEnvironmentName = environmentName
	publishedUpcomingEvents = upcomingEventsJson
	publishedBloodmoonCycleStartUnix = bloodmoonCycleStartUnix
	stateFolder:SetAttribute("BannerActive", bannerActive)
	stateFolder:SetAttribute("BannerText", bannerText)
	stateFolder:SetAttribute("ActiveEventIds", activeIdsText)
	stateFolder:SetAttribute("XPMultiplier", xpMultiplier)
	stateFolder:SetAttribute("WinButtonMultiplier", winButtonMultiplier)
	stateFolder:SetAttribute("WalkSpeedMultiplier", walkSpeedMultiplier)
	stateFolder:SetAttribute("EnvironmentName", environmentName)
	stateFolder:SetAttribute("BloodmoonCycleStartUnix", bloodmoonCycleStartUnix)
	stateFolder:SetAttribute("ActiveEvents", activeEventsJson)
	stateFolder:SetAttribute("UpcomingEvents", upcomingEventsJson)
	DebugModule.debugInfo(
		"Live event state updated | activeIds=" .. activeIdsText .. " | environment=" .. environmentName,
		MODULE_NAME
	)

	for _, player in ipairs(Players:GetPlayers()) do
		syncBloodmoonCycle(player, bloodmoonCycleStartUnix)
		applyPlayerMultipliers(player, xpMultiplier, winButtonMultiplier, walkSpeedMultiplier)
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

	maid.PlayerAdded = Players.PlayerAdded:Connect(function(player: Player)
		local dataLoadedConnectionKey = "BloodmoonDataLoaded_" .. tostring(player.UserId)
		maid[dataLoadedConnectionKey] = player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
			local bloodmoonCycleStartUnix = stateFolder:GetAttribute("BloodmoonCycleStartUnix")
			if typeof(bloodmoonCycleStartUnix) == "number" then
				syncBloodmoonCycle(player, bloodmoonCycleStartUnix)
			end
		end)

		local xpMultiplier = stateFolder:GetAttribute("XPMultiplier")
		local winButtonMultiplier = stateFolder:GetAttribute("WinButtonMultiplier")
		local walkSpeedMultiplier = stateFolder:GetAttribute("WalkSpeedMultiplier")
		local bloodmoonCycleStartUnix = stateFolder:GetAttribute("BloodmoonCycleStartUnix")
		if typeof(bloodmoonCycleStartUnix) == "number" then
			syncBloodmoonCycle(player, bloodmoonCycleStartUnix)
		end
		applyPlayerMultipliers(
			player,
			if typeof(xpMultiplier) == "number" then xpMultiplier else 1,
			if typeof(winButtonMultiplier) == "number" then winButtonMultiplier else 1,
			if typeof(walkSpeedMultiplier) == "number" then walkSpeedMultiplier else 1
		)
	end)
	maid.PlayerRemoving = Players.PlayerRemoving:Connect(function(player: Player)
		maid["BloodmoonDataLoaded_" .. tostring(player.UserId)] = nil
	end)
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

	stateFolder:SetAttribute("BannerActive", false)
	stateFolder:SetAttribute("BannerText", "")
	stateFolder:SetAttribute("ActiveEventIds", "")
	stateFolder:SetAttribute("XPMultiplier", 1)
	stateFolder:SetAttribute("WinButtonMultiplier", 1)
	stateFolder:SetAttribute("WalkSpeedMultiplier", 1)
	stateFolder:SetAttribute("EnvironmentName", "Default")
	stateFolder:SetAttribute("BloodmoonCycleStartUnix", 0)
	stateFolder:SetAttribute("ActiveEvents", "[]")
	stateFolder:SetAttribute("UpcomingEvents", "[]")
	for _, player in ipairs(Players:GetPlayers()) do
		applyPlayerMultipliers(player, 1, 1, 1)
	end
end

return LiveEventService
