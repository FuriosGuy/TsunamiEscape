--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CoreConfig = require(Modules.Config:WaitForChild("CoreConfig"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local Maid = require(Modules:WaitForChild("Maid"))
local LiveEventSchedule = require(script.Parent:WaitForChild("LiveEventSchedule"))

local LiveEventService = {}

type LiveEventEffects = {
	xpMultiplier: number?,
	winButtonMultiplier: number?,
}

type LiveEventDefinition = {
	id: string?,
	enabled: boolean?,
	priority: number?,
	displayText: string?,
	schedule: any,
	effects: LiveEventEffects?,
}

local MODULE_NAME = "LiveEventService"
local DEFAULT_REFRESH_INTERVAL = 15
local maid = Maid.new()
local initialized = false
local refreshToken = 0
local hasPublishedState = false
local publishedBannerActive = false
local publishedBannerText = ""
local publishedActiveIds = ""
local publishedXPMultiplier = 1
local publishedWinButtonMultiplier = 1

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

local function applyPlayerMultipliers(player: Player, xpMultiplier: number, winButtonMultiplier: number)
	player:SetAttribute("LiveEvent_XPMultiplier", xpMultiplier)
	player:SetAttribute("LiveEvent_WinButtonMultiplier", winButtonMultiplier)
end

local function getRefreshInterval(): number
	local liveEventsConfig = CoreConfig.liveEvents
	local configuredInterval = if typeof(liveEventsConfig) == "table" then liveEventsConfig.refreshIntervalSeconds else nil
	if typeof(configuredInterval) == "number" then
		return math.clamp(configuredInterval, 1, 60)
	end

	return DEFAULT_REFRESH_INTERVAL
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
	local xpMultiplier = 1
	local winButtonMultiplier = 1

	for _, eventDefinition in ipairs(getConfigEvents()) do
		if eventDefinition.enabled ~= false and LiveEventSchedule.IsActive(eventDefinition.schedule, timestamp) then
			table.insert(activeEvents, eventDefinition)
			local effects = eventDefinition.effects
			if effects then
				if typeof(effects.xpMultiplier) == "number" then
					xpMultiplier *= math.max(0, effects.xpMultiplier)
				end
				if typeof(effects.winButtonMultiplier) == "number" then
					winButtonMultiplier *= math.max(0, effects.winButtonMultiplier)
				end
			end
		end
	end

	table.sort(activeEvents, function(a, b)
		return (a.priority or 0) > (b.priority or 0)
	end)

	local primaryEvent = activeEvents[1]
	local bannerText = if primaryEvent and typeof(primaryEvent.displayText) == "string"
		then string.upper(primaryEvent.displayText)
		else ""
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
	if not stateChanged then
		return
	end

	hasPublishedState = true
	publishedBannerActive = bannerActive
	publishedBannerText = bannerText
	publishedActiveIds = activeIdsText
	publishedXPMultiplier = xpMultiplier
	publishedWinButtonMultiplier = winButtonMultiplier
	stateFolder:SetAttribute("BannerActive", bannerActive)
	stateFolder:SetAttribute("BannerText", bannerText)
	stateFolder:SetAttribute("ActiveEventIds", activeIdsText)
	stateFolder:SetAttribute("XPMultiplier", xpMultiplier)
	stateFolder:SetAttribute("WinButtonMultiplier", winButtonMultiplier)

	for _, player in ipairs(Players:GetPlayers()) do
		applyPlayerMultipliers(player, xpMultiplier, winButtonMultiplier)
	end
end

function LiveEventService.Init()
	if initialized then
		return
	end
	initialized = true
	refreshToken += 1

	maid.PlayerAdded = Players.PlayerAdded:Connect(function(player: Player)
		local xpMultiplier = stateFolder:GetAttribute("XPMultiplier")
		local winButtonMultiplier = stateFolder:GetAttribute("WinButtonMultiplier")
		applyPlayerMultipliers(
			player,
			if typeof(xpMultiplier) == "number" then xpMultiplier else 1,
			if typeof(winButtonMultiplier) == "number" then winButtonMultiplier else 1
		)
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
	for _, player in ipairs(Players:GetPlayers()) do
		applyPlayerMultipliers(player, 1, 1)
	end
end

return LiveEventService
