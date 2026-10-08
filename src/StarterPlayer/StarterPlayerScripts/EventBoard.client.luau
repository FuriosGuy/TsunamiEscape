local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

local localPlayer = Players.LocalPlayer

local EVENT_FETCH_INTERVAL = 30
local EVENT_EMPTY_RETRY_INTERVAL = 3
local EVENT_ERROR_RETRY_INTERVAL = 5
local EVENT_STARTUP_RETRY_INTERVAL = 2
local EVENT_STARTUP_RETRY_COUNT = 15
local EVENT_TOUCH_DEBOUNCE = 3
local EVENT_RSVP_PROMPT_INTERVAL = 180
local BOARD_STARTUP_RETRY_INTERVAL = 0.5
local BOARD_STARTUP_RETRY_COUNT = 20
local EVENT_STATUS_NOW = "NOW HAPPENING!"
local EVENT_STATUS_NONE = "NO EVENT YET"
local EVENT_STATUS_LOADING = "LOADING EVENT..."
local EVENT_COUNTDOWN_NONE = "CHECK BACK SOON"
local EVENT_COUNTDOWN_FINISHED = "EVENT FINISHED!"
local EVENT_COUNTDOWN_PREFIX = "LIVE IN: "
local EVENT_PLACEHOLDER_IMAGE = "rbxassetid://81072563465880"
local EVENT_RSVP_PROMPT_NAME = "ProximityPrompt"
local LEGACY_EVENT_RSVP_PROMPT_NAME = "EventBoardRSVPPrompt"

type EventDictionary = {
	Id: string?,
	Title: string?,
	DisplayTitle: string?,
	Description: string?,
	HasStarted: boolean?,
	HasEnded: boolean?,
	PreviewAssetId: number?,
	ThumbnailId: number?,
	ThumbnailIds: { number }?,
	thumbnails: { [string]: any }?,
	Thumbnails: { [string]: any }?,
	thumbnail: { [string]: any }?,
	Thumbnail: { [string]: any }?,
	UserRsvpStatus: any?,
	Status: any?,
	StartTime: any?,
	EndTime: any?,
}

type EventLifecycleState = "Upcoming" | "Active" | "Ended"

type EventBoardGuiState = {
	model: Model,
	touchPart: BasePart?,
	touchConnected: boolean,
	eventLabel: TextLabel?,
	countdownLabel: TextLabel?,
	imageLabel: ImageLabel?,
	rsvpPrompt: ProximityPrompt?,
	lastTouchTime: number,
	lastAppliedImageContent: string?,
}

local eventBoards: { EventBoardGuiState } = {}
local registeredBoards: { [Instance]: boolean } = {}
local pendingBoards: { [Model]: boolean } = {}
local boardMaids: { [Model]: any } = {}
local unregisteringBoards: { [Model]: boolean } = {}
local selectedEvent: EventDictionary? = nil
local nextFetchTime = 0
local fetchInProgress = false
local hasFetchedEvents = false
local startupFetchAttemptCount = 0
local scriptMaid = Maid.new()
local isRunning = true
local isCleanedUp = false
local rsvpInProgress = false
local eventBoardConfig = if typeof(CoreConfig.eventBoard) == "table" then CoreConfig.eventBoard else {}
local scheduleSelectedEventBoundaryRefresh: ((EventDictionary?) -> ())? = nil
local requestAutomaticRsvpProcessing: (() -> ())? = nil
local lastThumbnailDiagnosticKey = ""
local upcomingRsvpEvents: { EventDictionary } = {}
local automaticRsvpHandledEventIds: { [string]: boolean } = {}
local automaticRsvpPromptWorkerRunning = false
local nextAutomaticRsvpPromptTime = 0
local startupLoadingGui: Instance? = nil

local function isStartupLoadingComplete(): boolean
	return startupLoadingGui ~= nil
		and startupLoadingGui.Parent ~= nil
		and startupLoadingGui:GetAttribute("StartupLoadingComplete") == true
end

local function getCharacterRootPart(): BasePart?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isLocalPlayerTouch(hit: BasePart): boolean
	local character = localPlayer.Character
	if not character then
		return false
	end

	return hit:IsDescendantOf(character)
end

local function getDateTableUnixTimestamp(dateValue: any): number?
	if dateValue == nil then
		return nil
	end

	local directTimestampSuccess, directTimestamp = pcall(function()
		return (dateValue :: any).UnixTimestampMillis
	end)
	if directTimestampSuccess and typeof(directTimestamp) == "number" then
		return directTimestamp
	end

	if typeof(dateValue) ~= "table" then
		return nil
	end

	local dateTable = dateValue :: { [string]: any }
	local requiredFields = {
		dateTable.Year,
		dateTable.Month,
		dateTable.Day,
		dateTable.Hour,
		dateTable.Minute,
		dateTable.Second,
	}
	for _, value in ipairs(requiredFields) do
		if typeof(value) ~= "number" then
			return nil
		end
	end

	local success, dateTime = pcall(function()
		return DateTime.fromUniversalTime(
			dateTable.Year,
			dateTable.Month,
			dateTable.Day,
			dateTable.Hour,
			dateTable.Minute,
			dateTable.Second,
			dateTable.Millisecond or 0
		)
	end)

	if success and dateTime then
		return dateTime.UnixTimestampMillis
	end

	return nil
end

local function getEventStartUnixTimestamp(eventData: EventDictionary): number?
	return getDateTableUnixTimestamp(eventData.StartTime)
end

local function getEventEndUnixTimestamp(eventData: EventDictionary): number?
	return getDateTableUnixTimestamp(eventData.EndTime)
end

local function getEventLifecycleState(eventData: EventDictionary): EventLifecycleState
	local nowTimestamp = DateTime.now().UnixTimestampMillis
	local startTimestamp = getEventStartUnixTimestamp(eventData)
	local endTimestamp = getEventEndUnixTimestamp(eventData)

	-- Timestamps are authoritative during event handoff. SocialService status fields can
	-- briefly describe the previously active event after the next event is selected.
	if endTimestamp and nowTimestamp >= endTimestamp then
		return "Ended"
	end
	if startTimestamp then
		if nowTimestamp < startTimestamp then
			return "Upcoming"
		end
		return "Active"
	end

	local status = eventData.Status
	if typeof(status) == "EnumItem" then
		if status.Name == "Active" or status.Name == "Started" or status.Name == "Live" then
			return "Active"
		end
		if status.Name == "Ended" or status.Name == "Completed" then
			return "Ended"
		end
	end

	if eventData.HasEnded == true then
		return "Ended"
	end

	if eventData.HasStarted == true then
		return "Active"
	end

	if eventData.HasStarted == false then
		return "Upcoming"
	end

	return "Upcoming"
end

local function formatCountdown(eventData: EventDictionary): string
	local lifecycleState = getEventLifecycleState(eventData)
	if lifecycleState == "Active" then
		return EVENT_STATUS_NOW
	end

	if lifecycleState == "Ended" then
		return EVENT_COUNTDOWN_FINISHED
	end

	local startTimestamp = getEventStartUnixTimestamp(eventData)
	if not startTimestamp then
		return EVENT_COUNTDOWN_NONE
	end

	local remainingSeconds = math.max(0, math.floor((startTimestamp - DateTime.now().UnixTimestampMillis) / 1000))
	local days = math.floor(remainingSeconds / 86400)
	local hours = math.floor((remainingSeconds % 86400) / 3600)
	local minutes = math.floor((remainingSeconds % 3600) / 60)
	local seconds = remainingSeconds % 60

	if days > 0 then
		return string.format("%s%dd %dh", EVENT_COUNTDOWN_PREFIX, days, hours)
	end

	if hours > 0 then
		return string.format("%s%dh %dm", EVENT_COUNTDOWN_PREFIX, hours, minutes)
	end

	if minutes > 0 then
		return string.format("%s%dm %ds", EVENT_COUNTDOWN_PREFIX, minutes, seconds)
	end

	return string.format("%s%ds", EVENT_COUNTDOWN_PREFIX, seconds)
end

local function isRsvpEligibleEvent(eventData: EventDictionary?): boolean
	if eventData == nil then
		return false
	end

	-- Roblox only allows RSVP prompts for events that have not yet started.
	return getEventLifecycleState(eventData) == "Upcoming"
end

local function getEventId(eventData: EventDictionary?): string
	if eventData == nil then
		return ""
	end

	local idValue = eventData.Id
	if typeof(idValue) == "string" then
		return idValue
	end

	if typeof(idValue) == "number" then
		return tostring(idValue)
	end

	return ""
end

local function getPositiveAssetId(value: any): number?
	if typeof(value) == "number" and value > 0 then
		return value
	end

	if typeof(value) == "string" then
		local parsedValue = tonumber(value)
		if parsedValue and parsedValue > 0 then
			return parsedValue
		end

		local assetId = tonumber(string.match(value, "(%d+)$"))
		if assetId and assetId > 0 then
			return assetId
		end
	end

	return nil
end

local function getNestedThumbnailId(value: any): number?
	local directId = getPositiveAssetId(value)
	if directId then
		return directId
	end

	if typeof(value) ~= "table" then
		return nil
	end

	local thumbnailData = value :: { [any]: any }
	local thumbnailKeys = {
		"mediaId",
		"MediaId",
		"id",
		"Id",
		"assetId",
		"AssetId",
		"thumbnailId",
		"ThumbnailId",
		"thumbnailAssetId",
		"ThumbnailAssetId",
		"imageId",
		"ImageId",
		"imageAssetId",
		"ImageAssetId",
	}
	for _, key in ipairs(thumbnailKeys) do
		local nestedId = getPositiveAssetId(thumbnailData[key])
		if nestedId then
			return nestedId
		end
	end

	-- Event metadata may wrap mediaId inside an array of ranked thumbnails.
	for _, nestedValue in pairs(thumbnailData) do
		local nestedId = getNestedThumbnailId(nestedValue)
		if nestedId then
			return nestedId
		end
	end

	return nil
end

local function getConfiguredEventThumbnailId(eventId: string): number?
	local configuredIds = eventBoardConfig.eventThumbnailIdsByEvent
	if typeof(configuredIds) ~= "table" then
		return nil
	end

	return getPositiveAssetId(configuredIds[eventId])
end

local function resolveEventThumbnail(
	eventData: EventDictionary?,
	includeConfiguredFallback: boolean?
): (number?, string)
	if not eventData then
		return nil, "NoEvent"
	end

	local rawEventData = eventData :: any
	local thumbnailLists = {
		eventData.ThumbnailIds,
		rawEventData.thumbnailIds,
		rawEventData.thumbnailIDs,
		rawEventData.mediaIds,
		rawEventData.MediaIds,
	}
	local thumbnailListNames = {
		"ThumbnailIds",
		"thumbnailIds",
		"thumbnailIDs",
		"mediaIds",
		"MediaIds",
	}
	for index, thumbnailList in ipairs(thumbnailLists) do
		if typeof(thumbnailList) == "table" then
			for _, thumbnailId in pairs(thumbnailList) do
				local positiveThumbnailId = getPositiveAssetId(thumbnailId)
				if positiveThumbnailId then
					return positiveThumbnailId, thumbnailListNames[index]
				end
			end
		end
	end

	local directThumbnailIds = {
		eventData.ThumbnailId,
		eventData.PreviewAssetId,
		rawEventData.ThumbnailAssetId,
		rawEventData.ImageId,
		rawEventData.ImageAssetId,
		rawEventData.MediaAssetId,
	}
	local directThumbnailNames = {
		"ThumbnailId",
		"PreviewAssetId",
		"ThumbnailAssetId",
		"ImageId",
		"ImageAssetId",
		"MediaAssetId",
	}
	for index, thumbnailId in ipairs(directThumbnailIds) do
		local positiveThumbnailId = getPositiveAssetId(thumbnailId)
		if positiveThumbnailId then
			return positiveThumbnailId, directThumbnailNames[index]
		end
	end

	local nestedThumbnailData = {
		eventData.thumbnails,
		eventData.Thumbnails,
		eventData.thumbnail,
		eventData.Thumbnail,
	}
	local nestedThumbnailNames = {
		"thumbnails",
		"Thumbnails",
		"thumbnail",
		"Thumbnail",
	}
	for index, thumbnailData in ipairs(nestedThumbnailData) do
		local nestedThumbnailId = getNestedThumbnailId(thumbnailData)
		if nestedThumbnailId then
			return nestedThumbnailId, nestedThumbnailNames[index]
		end
	end

	if includeConfiguredFallback ~= false then
		local configuredThumbnailId = getConfiguredEventThumbnailId(getEventId(eventData))
		if configuredThumbnailId then
			return configuredThumbnailId, "ConfiguredEventThumbnail"
		end
	end

	return nil, "None"
end

local function getEventThumbnailId(eventData: EventDictionary?, includeConfiguredFallback: boolean?): number?
	local thumbnailId = resolveEventThumbnail(eventData, includeConfiguredFallback)
	return thumbnailId
end

local function getEventImageContent(eventData: EventDictionary?): (string, string)
	local thumbnailId, thumbnailSource = resolveEventThumbnail(eventData, true)
	if thumbnailId then
		return "rbxassetid://" .. tostring(thumbnailId), thumbnailSource
	end

	return EVENT_PLACEHOLDER_IMAGE, "Placeholder"
end

local function getEventTopLevelKeys(eventData: EventDictionary): string
	local keys: { string } = {}
	for key in pairs(eventData :: any) do
		table.insert(keys, tostring(key))
	end
	table.sort(keys)
	return if #keys > 0 then table.concat(keys, ",") else "none"
end

local THUMBNAIL_DIAGNOSTIC_KEYS = {
	"ThumbnailIds",
	"thumbnailIds",
	"thumbnailIDs",
	"mediaIds",
	"MediaIds",
	"ThumbnailId",
	"PreviewAssetId",
	"ThumbnailAssetId",
	"ImageId",
	"ImageAssetId",
	"MediaAssetId",
	"thumbnails",
	"Thumbnails",
	"thumbnail",
	"Thumbnail",
	"metadata",
	"Metadata",
	"eventMetadata",
	"EventMetadata",
}

local function getMetadataValueSummary(value: any): string
	if value == nil then
		return "nil"
	end

	local valueType = typeof(value)
	if valueType ~= "table" then
		return valueType .. "|value=" .. tostring(value)
	end

	local entries: { string } = {}
	local entryCount = 0
	for key, nestedValue in pairs(value :: { [any]: any }) do
		entryCount += 1
		if #entries < 8 then
			local nestedType = typeof(nestedValue)
			local nestedSummary = if nestedType == "table"
				then "table"
				else nestedType .. "(" .. tostring(nestedValue) .. ")"
			table.insert(entries, tostring(key) .. "=" .. nestedSummary)
		end
	end

	local suffix = if entryCount > #entries then ",..." else ""
	return "table|entries=" .. tostring(entryCount) .. "|sample=" .. table.concat(entries, ",") .. suffix
end

local function getThumbnailFieldDiagnostics(eventData: any): string
	if typeof(eventData) ~= "table" then
		return "eventType=" .. typeof(eventData)
	end

	local summaries: { string } = {}
	for _, key in ipairs(THUMBNAIL_DIAGNOSTIC_KEYS) do
		local value = eventData[key]
		if value ~= nil then
			local nestedId = getNestedThumbnailId(value)
			local summary = key .. "=" .. getMetadataValueSummary(value)
			if nestedId then
				summary ..= "|resolvedId=" .. tostring(nestedId)
			end
			table.insert(summaries, summary)
		end
	end

	return if #summaries > 0 then table.concat(summaries, ";") else "none"
end

local function getThumbnailMetadataSummary(eventData: EventDictionary): string
	local rawEventData = eventData :: any
	local metadataKeys = {
		"ThumbnailIds",
		"thumbnailIds",
		"thumbnailIDs",
		"mediaIds",
		"MediaIds",
		"ThumbnailId",
		"PreviewAssetId",
		"ThumbnailAssetId",
		"ImageId",
		"ImageAssetId",
		"MediaAssetId",
		"thumbnails",
		"Thumbnails",
		"thumbnail",
		"Thumbnail",
	}
	local summaries: { string } = {}
	for _, key in ipairs(metadataKeys) do
		local value = rawEventData[key]
		if value ~= nil then
			local summary = key .. "=" .. typeof(value)
			if typeof(value) == "table" then
				local nestedId = getNestedThumbnailId(value)
				summary ..= "|count=" .. tostring(#value)
				if nestedId then
					summary ..= "|resolvedId=" .. tostring(nestedId)
				end
			else
				summary ..= "|value=" .. tostring(value)
			end
			table.insert(summaries, summary)
		end
	end

	return if #summaries > 0 then table.concat(summaries, ";") else "none"
end

local function logThumbnailDiagnostics(eventData: EventDictionary)
	local eventId = getEventId(eventData)
	local apiThumbnailId, apiThumbnailSource = resolveEventThumbnail(eventData, false)
	local configuredThumbnailId = getConfiguredEventThumbnailId(eventId)
	local resolvedThumbnailId, resolvedThumbnailSource = resolveEventThumbnail(eventData, true)
	local diagnosticKey = table.concat({
		eventId,
		tostring(apiThumbnailId),
		apiThumbnailSource,
		tostring(configuredThumbnailId),
		tostring(resolvedThumbnailId),
		resolvedThumbnailSource,
		getThumbnailMetadataSummary(eventData),
	}, "|")
	if diagnosticKey == lastThumbnailDiagnosticKey then
		return
	end
	lastThumbnailDiagnosticKey = diagnosticKey

	DebugModule.debugInfo(
		"Thumbnail resolution | eventId="
			.. eventId
			.. " | apiId="
			.. tostring(apiThumbnailId)
			.. " | apiSource="
			.. apiThumbnailSource
			.. " | configuredId="
			.. tostring(configuredThumbnailId)
			.. " | resolvedId="
			.. tostring(resolvedThumbnailId)
			.. " | resolvedSource="
			.. resolvedThumbnailSource
			.. " | metadata="
			.. getThumbnailMetadataSummary(eventData),
		"EventBoard"
	)
	DebugModule.debugInfo(
		"Event metadata keys | eventId=" .. eventId .. " | keys=" .. getEventTopLevelKeys(eventData),
		"EventBoard"
	)
	DebugModule.debugInfo(
		"Event thumbnail field shapes | eventId=" .. eventId .. " | fields=" .. getThumbnailFieldDiagnostics(eventData),
		"EventBoard"
	)

	if not apiThumbnailId then
		DebugModule.debugWarn(
			"Event API returned no usable thumbnail ID | eventId="
				.. eventId
				.. " | expected=ThumbnailIds | resolvedSource="
				.. resolvedThumbnailSource,
			"EventBoard"
		)
	end
	if resolvedThumbnailSource == "ConfiguredEventThumbnail" then
		DebugModule.debugWarn(
			"Using configured event thumbnail fallback | eventId="
				.. eventId
				.. " | thumbnailId="
				.. tostring(resolvedThumbnailId),
			"EventBoard"
		)
	elseif resolvedThumbnailSource == "None" then
		DebugModule.debugWarn(
			"No event thumbnail resolved; board will use placeholder | eventId=" .. eventId,
			"EventBoard"
		)
	end
end

local function getConfiguredEventId(): string
	local activeEventIdsByUniverse = eventBoardConfig.activeEventIdsByUniverse
	if typeof(activeEventIdsByUniverse) == "table" then
		local universeEventId = activeEventIdsByUniverse[game.GameId]
		if typeof(universeEventId) == "string" and universeEventId ~= "" then
			return universeEventId
		end
	end

	local configuredEventId = eventBoardConfig.activeEventId
	if typeof(configuredEventId) == "string" and configuredEventId ~= "" then
		return configuredEventId
	end

	for _, boardState in ipairs(eventBoards) do
		for _, attributeName in ipairs({ "EventId", "EventID", "ExperienceEventId" }) do
			local attributeValue = boardState.model:GetAttribute(attributeName)
			if typeof(attributeValue) == "string" and attributeValue ~= "" then
				return attributeValue
			elseif typeof(attributeValue) == "number" and attributeValue > 0 then
				return tostring(attributeValue)
			end
		end
	end

	return ""
end

local function fetchEventById(eventId: string): (EventDictionary?, boolean)
	local success, result = pcall(function()
		return SocialService:GetExperienceEventAsync(eventId)
	end)
	if not success then
		DebugModule.debugWarn("Failed to load event details for " .. eventId .. ": " .. tostring(result), "EventBoard")
		return nil, false
	end

	if typeof(result) ~= "table" then
		DebugModule.debugWarn("GetExperienceEventAsync returned no event table | eventId=" .. eventId, "EventBoard")
		return nil, true
	end

	return result :: EventDictionary, true
end

local function applyBoardState(boardState: EventBoardGuiState)
	if selectedEvent then
		if boardState.eventLabel then
			local title = selectedEvent.DisplayTitle or selectedEvent.Title
			boardState.eventLabel.Text = tostring(title or EVENT_STATUS_NONE)
		end
		if boardState.countdownLabel then
			boardState.countdownLabel.Text = formatCountdown(selectedEvent)
		end
	else
		if boardState.eventLabel then
			boardState.eventLabel.Text = if hasFetchedEvents then EVENT_STATUS_NONE else EVENT_STATUS_LOADING
		end
		if boardState.countdownLabel then
			boardState.countdownLabel.Text = EVENT_COUNTDOWN_NONE
		end
	end

	if boardState.imageLabel then
		local imageContent, imageSource = getEventImageContent(selectedEvent)
		local imageChanged = boardState.lastAppliedImageContent ~= imageContent
			or boardState.imageLabel.Image ~= imageContent
		if imageChanged then
			boardState.lastAppliedImageContent = imageContent
			boardState.imageLabel.Image = imageContent
			DebugModule.debugInfo(
				"Event image applied | board="
					.. boardState.model:GetFullName()
					.. " | eventId="
					.. getEventId(selectedEvent)
					.. " | source="
					.. imageSource
					.. " | content="
					.. imageContent,
				"EventBoard"
			)
			if imageSource == "Placeholder" then
				DebugModule.debugWarn(
					"Board image is placeholder | board=" .. boardState.model:GetFullName(),
					"EventBoard"
				)
			end
		end
	end
	if boardState.rsvpPrompt then
		-- Keep the interaction discoverable permanently; promptSelectedEvent still
		-- validates that a current event can accept RSVPs before opening the prompt.
		boardState.rsvpPrompt.Enabled = true
	end
end

local function applyAllBoards()
	for _, boardState in ipairs(eventBoards) do
		applyBoardState(boardState)
	end
end

local function normalizeEventTitle(value: any): string
	if typeof(value) ~= "string" then
		return ""
	end

	local normalized = string.upper(value)
	normalized = string.gsub(normalized, "[^%w]+", " ")
	normalized = string.gsub(normalized, "^%s+", "")
	normalized = string.gsub(normalized, "%s+$", "")
	return normalized
end

local function isSecondaryEvent(eventData: EventDictionary): boolean
	local title = eventData.DisplayTitle or eventData.Title
	local normalizedTitle = normalizeEventTitle(title)
	if normalizedTitle == "" then
		return false
	end

	local secondaryTitles = eventBoardConfig.secondaryEventTitles
	if typeof(secondaryTitles) ~= "table" then
		return false
	end

	for _, secondaryTitle in ipairs(secondaryTitles) do
		if normalizedTitle == normalizeEventTitle(secondaryTitle) then
			return true
		end
	end

	return false
end

local function pickBestEvent(events: { any }): EventDictionary?
	local normalizedEvents: { EventDictionary } = {}
	for _, eventData in ipairs(events) do
		if typeof(eventData) == "table" then
			table.insert(normalizedEvents, eventData :: EventDictionary)
		end
	end

	table.sort(normalizedEvents, function(a, b)
		local aTimestamp = getEventStartUnixTimestamp(a) or math.huge
		local bTimestamp = getEventStartUnixTimestamp(b) or math.huge
		return aTimestamp < bTimestamp
	end)

	local function findFirstByState(state: EventLifecycleState, secondary: boolean): EventDictionary?
		for _, eventData in ipairs(normalizedEvents) do
			if getEventLifecycleState(eventData) == state and isSecondaryEvent(eventData) == secondary then
				return eventData
			end
		end
		return nil
	end

	local function findFirstNotEnded(secondary: boolean): EventDictionary?
		for _, eventData in ipairs(normalizedEvents) do
			if eventData.HasEnded ~= true and isSecondaryEvent(eventData) == secondary then
				return eventData
			end
		end
		return nil
	end

	return findFirstByState("Active", false)
		or findFirstByState("Upcoming", false)
		or findFirstByState("Active", true)
		or findFirstByState("Upcoming", true)
		or findFirstNotEnded(false)
		or findFirstNotEnded(true)
end

local function replaceUpcomingRsvpEvents(events: { any }): ()
	local nextUpcomingEvents: { EventDictionary } = {}
	local seenEventIds: { [string]: boolean } = {}

	for _, rawEvent in ipairs(events) do
		if typeof(rawEvent) == "table" then
			local eventData = rawEvent :: EventDictionary
			local eventId = getEventId(eventData)
			if eventId ~= "" and not seenEventIds[eventId] and isRsvpEligibleEvent(eventData) then
				seenEventIds[eventId] = true
				table.insert(nextUpcomingEvents, eventData)
			end
		end
	end

	table.sort(nextUpcomingEvents, function(a, b)
		return (getEventStartUnixTimestamp(a) or math.huge) < (getEventStartUnixTimestamp(b) or math.huge)
	end)

	upcomingRsvpEvents = nextUpcomingEvents
	if requestAutomaticRsvpProcessing then
		requestAutomaticRsvpProcessing()
	end
end

local function extractEventsFromResult(result: any): { any }
	if typeof(result) == "table" and #result > 0 then
		return result :: { any }
	end

	if typeof(result) == "table" then
		local dictionaryResult = result :: { [any]: any }
		if dictionaryResult.Id ~= nil then
			return { result }
		end

		for _, key in ipairs({ "Events", "events", "Data", "data", "Items", "items" }) do
			local nestedEvents = dictionaryResult[key]
			if typeof(nestedEvents) == "table" then
				if nestedEvents.Id ~= nil then
					return { nestedEvents }
				end
				return nestedEvents :: { any }
			end
		end

		if #result == 0 then
			return result :: { any }
		end
	end

	-- Some runtimes expose a pages-like object. Handle that shape too.
	local pageSuccess, pageResult = pcall(function()
		return (result :: any):GetCurrentPage()
	end)
	if pageSuccess and typeof(pageResult) == "table" then
		return pageResult :: { any }
	end

	return {}
end

local function enrichEventDetails(eventData: EventDictionary): EventDictionary
	-- Upcoming-event results sometimes omit ThumbnailIds while the detail endpoint
	-- includes them. Do not let a manual fallback prevent that richer lookup.
	if getEventThumbnailId(eventData, false) then
		return eventData
	end

	local eventId = getEventId(eventData)
	if eventId == "" then
		return eventData
	end

	local success, result = pcall(function()
		return SocialService:GetExperienceEventAsync(eventId)
	end)
	if not success or typeof(result) ~= "table" then
		if not success then
			DebugModule.debugWarn(
				"Failed to load event details for " .. eventId .. ": " .. tostring(result),
				"EventBoard"
			)
		else
			DebugModule.debugWarn("Event detail response was nil or malformed | eventId=" .. eventId, "EventBoard")
		end
		return eventData
	end

	local detailThumbnailId, detailThumbnailSource = resolveEventThumbnail(result :: EventDictionary, false)
	DebugModule.debugInfo(
		"Event detail response | eventId="
			.. eventId
			.. " | thumbnailId="
			.. tostring(detailThumbnailId)
			.. " | thumbnailSource="
			.. detailThumbnailSource
			.. " | metadata="
			.. getThumbnailMetadataSummary(result :: EventDictionary),
		"EventBoard"
	)
	DebugModule.debugInfo(
		"Event detail raw shape | eventId="
			.. eventId
			.. " | resultType="
			.. typeof(result)
			.. " | keys="
			.. getEventTopLevelKeys(result :: EventDictionary)
			.. " | fields="
			.. getThumbnailFieldDiagnostics(result),
		"EventBoard"
	)
	if not detailThumbnailId then
		DebugModule.debugWarn(
			"Event detail has no recognized thumbnail field | eventId="
				.. eventId
				.. " | expected=ThumbnailIds or thumbnails.mediaId",
			"EventBoard"
		)
	end

	local detailedEvent = table.clone(eventData) :: any
	for key, value in pairs(result :: { [string]: any }) do
		detailedEvent[key] = value
	end

	return detailedEvent :: EventDictionary
end

local function setSelectedEvent(eventData: EventDictionary?)
	selectedEvent = eventData
	if eventData then
		logThumbnailDiagnostics(eventData)
	else
		lastThumbnailDiagnosticKey = ""
	end
	if scheduleSelectedEventBoundaryRefresh then
		scheduleSelectedEventBoundaryRefresh(eventData)
	end
end

local function tryConfiguredEventFallback(now: number): (boolean, boolean)
	local fallbackEventId = getConfiguredEventId()
	if fallbackEventId == "" then
		fallbackEventId = getEventId(selectedEvent)
	end

	if fallbackEventId == "" then
		return false, true
	end

	local fallbackEvent, lookupSucceeded = fetchEventById(fallbackEventId)
	if fallbackEvent and getEventLifecycleState(fallbackEvent) ~= "Ended" then
		replaceUpcomingRsvpEvents({ fallbackEvent })
		setSelectedEvent(enrichEventDetails(fallbackEvent))
		DebugModule.debugInfo(
			"Configured event fallback selected | placeId="
				.. tostring(game.PlaceId)
				.. " | universeId="
				.. tostring(game.GameId)
				.. " | eventId="
				.. fallbackEventId,
			"EventBoard"
		)
		startupFetchAttemptCount = 0
		nextFetchTime = now + EVENT_FETCH_INTERVAL
		return true, true
	end

	return false, lookupSucceeded
end

local function refreshCurrentEvent(force: boolean?)
	local now = os.clock()
	if not force and now < nextFetchTime then
		applyAllBoards()
		return
	end

	if fetchInProgress then
		applyAllBoards()
		return
	end

	fetchInProgress = true

	local success, result = pcall(function()
		return SocialService:GetUpcomingExperienceEventsAsync()
	end)

	fetchInProgress = false

	if not success then
		DebugModule.debugWarn("Failed to load upcoming experience events: " .. tostring(result), "EventBoard")
		local fallbackApplied, fallbackLookupSucceeded = tryConfiguredEventFallback(now)
		if not fallbackApplied then
			if not fallbackLookupSucceeded and selectedEvent and getEventLifecycleState(selectedEvent) ~= "Ended" then
				startupFetchAttemptCount += 1
				nextFetchTime = now + EVENT_ERROR_RETRY_INTERVAL
			else
				setSelectedEvent(nil)
				startupFetchAttemptCount += 1
				nextFetchTime = now
					+ (
						if startupFetchAttemptCount <= EVENT_STARTUP_RETRY_COUNT
							then EVENT_STARTUP_RETRY_INTERVAL
							else EVENT_ERROR_RETRY_INTERVAL
					)
			end
		end
		applyAllBoards()
		return
	end

	hasFetchedEvents = true
	local processingSuccess, processedEventsOrError = pcall(function()
		local events = extractEventsFromResult(result)
		DebugModule.debugInfo("Automatic event fetch succeeded | eventCount=" .. tostring(#events), "EventBoard")
		return {
			events = events,
			bestEvent = pickBestEvent(events),
		}
	end)
	if not processingSuccess then
		DebugModule.debugWarn(
			"Failed to process upcoming experience events: " .. tostring(processedEventsOrError),
			"EventBoard"
		)
		startupFetchAttemptCount += 1
		nextFetchTime = now + EVENT_STARTUP_RETRY_INTERVAL
		applyAllBoards()
		return
	end

	local processedEvents = processedEventsOrError :: any
	replaceUpcomingRsvpEvents(processedEvents.events)
	local bestEvent = processedEvents.bestEvent :: EventDictionary?
	if bestEvent then
		setSelectedEvent(enrichEventDetails(bestEvent))
		local selectedEventData = selectedEvent :: any
		DebugModule.debugInfo(
			"Selected event | eventId="
				.. getEventId(selectedEvent)
				.. " | idType="
				.. typeof(selectedEventData.Id)
				.. " | title="
				.. tostring(selectedEventData.DisplayTitle or selectedEventData.Title)
				.. " | lifecycle="
				.. getEventLifecycleState(selectedEvent),
			"EventBoard"
		)
		startupFetchAttemptCount = 0
		nextFetchTime = now + EVENT_FETCH_INTERVAL
	else
		local fallbackApplied, fallbackLookupSucceeded = tryConfiguredEventFallback(now)
		if fallbackApplied then
			-- The configured event is used when the API only returns future events.
		elseif not fallbackLookupSucceeded and selectedEvent and getEventLifecycleState(selectedEvent) ~= "Ended" then
			-- Keep the last valid event visible during a temporary SocialService failure.
			startupFetchAttemptCount += 1
			nextFetchTime = now + EVENT_ERROR_RETRY_INTERVAL
		else
			setSelectedEvent(nil)
			startupFetchAttemptCount += 1
			nextFetchTime = now
				+ (
					if startupFetchAttemptCount <= EVENT_STARTUP_RETRY_COUNT
						then EVENT_STARTUP_RETRY_INTERVAL
						else EVENT_EMPTY_RETRY_INTERVAL
				)
		end
	end

	applyAllBoards()
end

local function findNextAutomaticRsvpEvent(): (EventDictionary?, string)
	for _, eventData in ipairs(upcomingRsvpEvents) do
		local eventId = getEventId(eventData)
		if eventId ~= "" and not automaticRsvpHandledEventIds[eventId] then
			return eventData, eventId
		end
	end

	return nil, ""
end

local function processAutomaticRsvpEvent(eventData: EventDictionary, eventId: string): ()
	if not isStartupLoadingComplete() then
		return
	end

	if not isRsvpEligibleEvent(eventData) then
		automaticRsvpHandledEventIds[eventId] = true
		return
	end

	local statusSuccess, currentStatus = pcall(function()
		return SocialService:GetEventRsvpStatusAsync(eventId)
	end)
	if
		isCleanedUp
		or not isRunning
		or rsvpInProgress
		or not isStartupLoadingComplete()
		or os.clock() < nextAutomaticRsvpPromptTime
	then
		return
	end

	if not statusSuccess then
		DebugModule.debugWarn(
			"Could not check automatic RSVP status | eventId=" .. eventId .. " | error=" .. tostring(currentStatus),
			"EventBoard"
		)
		nextAutomaticRsvpPromptTime = os.clock() + EVENT_RSVP_PROMPT_INTERVAL
		return
	end

	if typeof(currentStatus) ~= "EnumItem" then
		DebugModule.debugWarn(
			"Automatic RSVP status response was invalid | eventId=" .. eventId .. " | status=" .. tostring(currentStatus),
			"EventBoard"
		)
		nextAutomaticRsvpPromptTime = os.clock() + EVENT_RSVP_PROMPT_INTERVAL
		return
	end

	if currentStatus ~= Enum.RsvpStatus.None then
		automaticRsvpHandledEventIds[eventId] = true
		DebugModule.debugInfo(
			"Automatic RSVP skipped; player already responded | eventId="
				.. eventId
				.. " | status="
				.. tostring(currentStatus),
			"EventBoard"
		)
		return
	end

	if not isRsvpEligibleEvent(eventData) then
		automaticRsvpHandledEventIds[eventId] = true
		return
	end

	rsvpInProgress = true
	local promptSuccess, promptResult = pcall(function()
		return SocialService:PromptRsvpToEventAsync(eventId)
	end)
	rsvpInProgress = false
	nextAutomaticRsvpPromptTime = os.clock() + EVENT_RSVP_PROMPT_INTERVAL

	if promptSuccess then
		automaticRsvpHandledEventIds[eventId] = true
		DebugModule.debugInfo(
			"Automatic RSVP prompt completed | eventId=" .. eventId .. " | status=" .. tostring(promptResult),
			"EventBoard"
		)
	else
		DebugModule.debugWarn(
			"Automatic RSVP prompt failed | eventId=" .. eventId .. " | error=" .. tostring(promptResult),
			"EventBoard"
		)
	end
end

requestAutomaticRsvpProcessing = function(): ()
	if
		automaticRsvpPromptWorkerRunning
		or isCleanedUp
		or not isRunning
		or rsvpInProgress
		or localPlayer.Parent == nil
		or localPlayer:GetAttribute("Data_Loaded") ~= true
		or localPlayer:GetAttribute("TutorialCompleted") ~= true
		or not isStartupLoadingComplete()
	then
		return
	end

	if not findNextAutomaticRsvpEvent() then
		return
	end

	automaticRsvpPromptWorkerRunning = true
	local workerThread = task.spawn(function()
		while isRunning and not isCleanedUp and localPlayer.Parent ~= nil do
			if
				localPlayer:GetAttribute("Data_Loaded") ~= true
				or localPlayer:GetAttribute("TutorialCompleted") ~= true
				or not isStartupLoadingComplete()
				or rsvpInProgress
			then
				break
			end

			local eventData, eventId = findNextAutomaticRsvpEvent()
			if not eventData then
				break
			end

			local remainingDelay = nextAutomaticRsvpPromptTime - os.clock()
			if remainingDelay > 0 then
				task.wait(remainingDelay)
				continue
			end

			processAutomaticRsvpEvent(eventData, eventId)
		end

		automaticRsvpPromptWorkerRunning = false
		if isRunning and not isCleanedUp and not rsvpInProgress and requestAutomaticRsvpProcessing then
			requestAutomaticRsvpProcessing()
		end
	end)
	scriptMaid:GiveSpawnTask(workerThread)
end

local function scheduleForcedEventRefresh(delaySeconds: number)
	local refreshThread = task.delay(delaySeconds, function()
		if isCleanedUp or not isRunning then
			return
		end

		refreshCurrentEvent(true)
	end)
	scriptMaid:GiveTask(refreshThread)
end

scheduleSelectedEventBoundaryRefresh = function(eventData: EventDictionary?)
	scriptMaid.EventBoundaryRefresh = nil
	if not eventData then
		return
	end

	local nowTimestamp = DateTime.now().UnixTimestampMillis
	local startTimestamp = getEventStartUnixTimestamp(eventData)
	local endTimestamp = getEventEndUnixTimestamp(eventData)
	local nextBoundary = if startTimestamp and startTimestamp > nowTimestamp
		then startTimestamp
		elseif endTimestamp and endTimestamp > nowTimestamp then endTimestamp
		else nil
	if not nextBoundary then
		return
	end

	local delaySeconds = math.max(0.1, (nextBoundary - nowTimestamp) / 1000 + 0.05)
	local boundaryThread = task.delay(delaySeconds, function()
		if not isCleanedUp and isRunning then
			refreshCurrentEvent(true)
		end
	end)
	scriptMaid.EventBoundaryRefresh = function()
		pcall(task.cancel, boundaryThread)
	end
end

local function getRsvpNotificationTheme(rsvpStatus: any): (string, Color3, Color3)
	if rsvpStatus == Enum.RsvpStatus.Going then
		return "RSVP REGISTERED!", Color3.fromRGB(0, 255, 0), Color3.fromRGB(0, 130, 15)
	end

	if rsvpStatus == Enum.RsvpStatus.NotGoing or rsvpStatus == Enum.RsvpStatus.None then
		return "RSVP CANCELLED!", Color3.fromRGB(255, 78, 78), Color3.fromRGB(130, 0, 0)
	end

	return "RSVP STATUS UPDATED!", Color3.fromRGB(255, 255, 255), Color3.fromRGB(100, 100, 100)
end

local function showRsvpNotification(eventId: string, rsvpStatus: any)
	local message, textColor, gradientBottomColor = getRsvpNotificationTheme(rsvpStatus)

	-- GuiHandler can initialize after EventBoard. Wait only for a bounded time so a
	-- successful RSVP is not lost just because the notification HUD is still loading.
	for _ = 1, 50 do
		if isCleanedUp or not isRunning then
			return
		end

		local notificationFrame = VisualFunctions.HUD.NotificationFrame
		local notificationLabel = VisualFunctions.Labels.NotificationTextLabel

		if
			notificationFrame
			and notificationFrame.Parent
			and notificationLabel
			and notificationLabel.Parent
			and notificationLabel:IsDescendantOf(notificationFrame)
		then
			local notificationSuccess, notificationError = pcall(function()
				VisualFunctions.ShowNotification(message, textColor, gradientBottomColor)
			end)
			if notificationSuccess then
				DebugModule.debugInfo("RSVP notification shown | eventId=" .. eventId, "EventBoard")
			else
				DebugModule.debugWarn(
					"RSVP succeeded but notification failed | eventId="
						.. eventId
						.. " | error="
						.. tostring(notificationError),
					"EventBoard"
				)
			end
			return
		end

		task.wait(0.1)
	end

	DebugModule.debugWarn("RSVP succeeded but NotificationFrame was not ready | eventId=" .. eventId, "EventBoard")
end

local function promptSelectedEvent(boardState: EventBoardGuiState)
	if rsvpInProgress then
		DebugModule.debugInfo("RSVP ignored because another prompt is in progress", "EventBoard")
		return
	end

	if not isStartupLoadingComplete() then
		DebugModule.debugInfo("Manual RSVP ignored until startup loading completes", "EventBoard")
		return
	end

	refreshCurrentEvent(true)

	if not selectedEvent then
		DebugModule.debugWarn("RSVP ignored because no event is selected", "EventBoard")
		return
	end

	if not isRsvpEligibleEvent(selectedEvent) then
		DebugModule.debugWarn(
			"RSVP ignored because selected event is not upcoming | eventId=" .. getEventId(selectedEvent),
			"EventBoard"
		)
		return
	end

	local eventId = getEventId(selectedEvent)
	if eventId == "" then
		DebugModule.debugWarn("RSVP ignored because selected event has no ID", "EventBoard")
		return
	end

	local now = os.clock()
	if now - boardState.lastTouchTime < EVENT_TOUCH_DEBOUNCE then
		DebugModule.debugInfo("RSVP ignored by debounce | board=" .. boardState.model:GetFullName(), "EventBoard")
		return
	end

	boardState.lastTouchTime = now
	rsvpInProgress = true
	local selectedEventData = selectedEvent :: any
	DebugModule.debugInfo(
		"RSVP prompt requested | eventId="
			.. eventId
			.. " | idType="
			.. typeof(selectedEventData.Id)
			.. " | lifecycle="
			.. getEventLifecycleState(selectedEvent)
			.. " | board="
			.. boardState.model:GetFullName(),
		"EventBoard"
	)

	scriptMaid:GiveSpawnTask(task.spawn(function()
		local success, rsvpStatus = pcall(function()
			return SocialService:PromptRsvpToEventAsync(eventId)
		end)
		DebugModule.debugInfo(
			"PromptRsvpToEventAsync returned | eventId="
				.. eventId
				.. " | success="
				.. tostring(success)
				.. " | status="
				.. tostring(rsvpStatus)
				.. " | statusType="
				.. typeof(rsvpStatus),
			"EventBoard"
		)

		if success then
			automaticRsvpHandledEventIds[eventId] = true
			DebugModule.debugInfo(
				"RSVP status updated | eventId=" .. eventId .. " | status=" .. tostring(rsvpStatus),
				"EventBoard"
			)
			showRsvpNotification(eventId, rsvpStatus)
		elseif not success then
			DebugModule.debugWarn(
				"Failed to prompt event RSVP for " .. eventId .. ": " .. tostring(rsvpStatus),
				"EventBoard"
			)
		else
			DebugModule.debugInfo(
				"RSVP prompt closed without Going status | eventId=" .. eventId .. " | status=" .. tostring(rsvpStatus),
				"EventBoard"
			)
		end

		rsvpInProgress = false
		nextAutomaticRsvpPromptTime = os.clock() + EVENT_RSVP_PROMPT_INTERVAL
		if requestAutomaticRsvpProcessing then
			requestAutomaticRsvpProcessing()
		end

		task.wait(1)
		if isCleanedUp or not isRunning then
			return
		end
		if not registeredBoards[boardState.model] then
			return
		end
		refreshCurrentEvent(true)
	end))
end

local function unregisterBoard(boardModel: Model)
	if unregisteringBoards[boardModel] then
		return
	end
	unregisteringBoards[boardModel] = true

	pendingBoards[boardModel] = nil
	registeredBoards[boardModel] = nil

	local boardMaid = boardMaids[boardModel]
	if boardMaid then
		boardMaids[boardModel] = nil
		boardMaid:DoCleaning()
	end

	for index = #eventBoards, 1, -1 do
		if eventBoards[index].model == boardModel then
			table.remove(eventBoards, index)
			break
		end
	end

	unregisteringBoards[boardModel] = nil
end

local function refreshBoardVisualReferences(boardState: EventBoardGuiState)
	local billboardGui = boardState.model:FindFirstChild("BillboardGui", true)
	local eventLabel = if billboardGui then billboardGui:FindFirstChild("EventLabel", true) else nil
	local countdownLabel = if billboardGui then billboardGui:FindFirstChild("CountdownLabel", true) else nil
	local thumbnail = boardState.model:FindFirstChild("Thumbnail", true)
	local surfaceGui = if thumbnail then thumbnail:FindFirstChild("SurfaceGui", true) else nil
	local imageLabel = if surfaceGui then surfaceGui:FindFirstChild("ImageLabel", true) else nil

	boardState.eventLabel = if eventLabel and eventLabel:IsA("TextLabel") then eventLabel else nil
	boardState.countdownLabel = if countdownLabel and countdownLabel:IsA("TextLabel") then countdownLabel else nil
	boardState.imageLabel = if imageLabel and imageLabel:IsA("ImageLabel") then imageLabel else nil
end

local function connectBoardTouch(boardState: EventBoardGuiState, touchPart: BasePart, boardMaid: any)
	if boardState.touchConnected then
		return
	end

	boardState.touchPart = touchPart
	boardState.touchConnected = true
	boardMaid:GiveTask(touchPart.Touched:Connect(function(hit)
		if not hit:IsA("BasePart") then
			return
		end

		if not isLocalPlayerTouch(hit) then
			return
		end

		if not getCharacterRootPart() then
			return
		end

		promptSelectedEvent(boardState)
	end))

	-- Prefer the authored prompt. Keep the legacy lookup for already-streamed copies.
	local existingPrompt = touchPart:FindFirstChild(EVENT_RSVP_PROMPT_NAME)
		or touchPart:FindFirstChild(LEGACY_EVENT_RSVP_PROMPT_NAME)
	local rsvpPrompt = if existingPrompt and existingPrompt:IsA("ProximityPrompt") then existingPrompt else nil
	local promptSource = if existingPrompt then existingPrompt:GetFullName() else "runtime-created"
	if not rsvpPrompt then
		rsvpPrompt = Instance.new("ProximityPrompt")
		rsvpPrompt.Name = EVENT_RSVP_PROMPT_NAME
		rsvpPrompt.ActionText = "NOTIFY ME"
		rsvpPrompt.ObjectText = "UPCOMING EVENT"
		rsvpPrompt.HoldDuration = 0
		rsvpPrompt.MaxActivationDistance = 14
		rsvpPrompt.RequiresLineOfSight = false
		rsvpPrompt.Parent = touchPart
		boardMaid:GiveTask(rsvpPrompt)
	end
	boardState.rsvpPrompt = rsvpPrompt
	rsvpPrompt.Enabled = true
	DebugModule.debugInfo(
		"RSVP prompt bound | source="
			.. promptSource
			.. " | resolved="
			.. rsvpPrompt:GetFullName()
			.. " | enabled="
			.. tostring(rsvpPrompt.Enabled)
			.. " | maxDistance="
			.. tostring(rsvpPrompt.MaxActivationDistance)
			.. " | actionText="
			.. rsvpPrompt.ActionText
			.. " | objectText="
			.. rsvpPrompt.ObjectText,
		"EventBoard"
	)
	boardMaid:GiveTask(rsvpPrompt.PromptShown:Connect(function(inputType: Enum.ProximityPromptInputType)
		DebugModule.debugInfo(
			"RSVP prompt shown | inputType=" .. tostring(inputType) .. " | eventId=" .. getEventId(selectedEvent),
			"EventBoard"
		)
	end))
	boardMaid:GiveTask(rsvpPrompt.PromptHidden:Connect(function()
		DebugModule.debugInfo("RSVP prompt hidden | path=" .. rsvpPrompt:GetFullName(), "EventBoard")
	end))
	boardMaid:GiveTask(rsvpPrompt.Triggered:Connect(function()
		-- This is a LocalScript, so the prompt event is already local to this client.
		-- Do not reject the trigger when a runtime omits the Player argument.
		DebugModule.debugInfo(
			"RSVP prompt triggered | path=" .. rsvpPrompt:GetFullName() .. " | eventId=" .. getEventId(selectedEvent),
			"EventBoard"
		)
		promptSelectedEvent(boardState)
	end))
end

local function findBoardInteractionPart(boardModel: Model): BasePart?
	for _, name in ipairs({ "TouchPart", "InteractionPart", "Thumbnail" }) do
		local candidate = boardModel:FindFirstChild(name, true)
		if candidate and candidate:IsA("BasePart") then
			return candidate
		end
	end

	if boardModel.PrimaryPart then
		return boardModel.PrimaryPart
	end

	return nil
end

local function createBoardState(boardModel: Model): EventBoardGuiState?
	local billboardGui = boardModel:FindFirstChild("BillboardGui", true)
	if not billboardGui then
		return nil
	end

	local validTouchPart = findBoardInteractionPart(boardModel)

	local boardState: EventBoardGuiState = {
		model = boardModel,
		touchPart = validTouchPart,
		touchConnected = false,
		eventLabel = nil,
		countdownLabel = nil,
		imageLabel = nil,
		rsvpPrompt = nil,
		lastTouchTime = 0,
		lastAppliedImageContent = nil,
	}
	refreshBoardVisualReferences(boardState)

	return boardState
end

local function registerBoard(boardModel: Model)
	if registeredBoards[boardModel] then
		return
	end

	local boardMaid = Maid.new()
	local boardState = createBoardState(boardModel)
	if not boardState then
		boardMaid:DoCleaning()
		pendingBoards[boardModel] = true
		DebugModule.debugWarn(
			"Board registration deferred | path="
				.. boardModel:GetFullName()
				.. " | billboardGui="
				.. tostring(boardModel:FindFirstChild("BillboardGui", true) ~= nil)
				.. " | touchPart="
				.. tostring(boardModel:FindFirstChild("TouchPart", true) ~= nil),
			"EventBoard"
		)
		return
	end

	boardMaids[boardModel] = boardMaid
	boardMaid:GiveTask(boardModel.Destroying:Connect(function()
		unregisterBoard(boardModel)
	end))
	boardMaid:GiveTask(boardModel.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			unregisterBoard(boardModel)
		end
	end))
	if boardState.touchPart then
		connectBoardTouch(boardState, boardState.touchPart, boardMaid)
	end
	boardMaid:GiveTask(boardModel.DescendantAdded:Connect(function(descendant)
		if boardState.touchPart == nil and descendant.Name == "TouchPart" and descendant:IsA("BasePart") then
			connectBoardTouch(boardState, descendant, boardMaid)
		end
		if
			boardState.touchPart == nil
			and (descendant.Name == "InteractionPart" or descendant.Name == "Thumbnail")
			and descendant:IsA("BasePart")
		then
			connectBoardTouch(boardState, descendant, boardMaid)
		end

		refreshBoardVisualReferences(boardState)
		applyBoardState(boardState)
	end))

	registeredBoards[boardModel] = true
	pendingBoards[boardModel] = nil
	table.insert(eventBoards, boardState)
	DebugModule.debugInfo(
		"Registered board | count="
			.. tostring(#eventBoards)
			.. " | eventLabel="
			.. tostring(boardState.eventLabel ~= nil)
			.. " | countdownLabel="
			.. tostring(boardState.countdownLabel ~= nil),
		"EventBoard"
	)
	applyBoardState(boardState)
end

local function findAncestorEventBoard(descendant: Instance): Model?
	local ancestorBoard = descendant:FindFirstAncestorWhichIsA("Model")
	while ancestorBoard do
		if string.lower(ancestorBoard.Name) == "eventboard" then
			return ancestorBoard
		end
		ancestorBoard = ancestorBoard.Parent and ancestorBoard.Parent:FindFirstAncestorWhichIsA("Model") or nil
	end

	return nil
end

local function scanForBoards()
	local worlds = Workspace:FindFirstChild("Worlds")
	if not worlds then
		DebugModule.debugWarn("Board scan skipped: Workspace.Worlds is missing", "EventBoard")
		return
	end

	local candidateCount = 0
	local guiCandidateCount = 0
	for _, descendant in ipairs(worlds:GetDescendants()) do
		if string.lower(descendant.Name) == "eventboard" and descendant:IsA("Model") then
			candidateCount += 1
			DebugModule.debugWarn("Board candidate found | path=" .. descendant:GetFullName(), "EventBoard")
			registerBoard(descendant)
		elseif string.lower(descendant.Name) == "eventboard" then
			DebugModule.debugWarn(
				"Board candidate has unsupported class | class="
					.. descendant.ClassName
					.. " | path="
					.. descendant:GetFullName(),
				"EventBoard"
			)
		end

		if descendant:IsA("BillboardGui") then
			local eventLabel = descendant:FindFirstChild("EventLabel", true)
			local countdownLabel = descendant:FindFirstChild("CountdownLabel", true)
			if eventLabel or countdownLabel then
				guiCandidateCount += 1
				DebugModule.debugWarn(
					"Board GUI candidate found | path="
						.. descendant:GetFullName()
						.. " | eventLabel="
						.. tostring(eventLabel ~= nil)
						.. " | countdownLabel="
						.. tostring(countdownLabel ~= nil),
					"EventBoard"
				)
			end
		end
	end

	DebugModule.debugWarn(
		"Board scan complete | candidates="
			.. tostring(candidateCount)
			.. " | guiCandidates="
			.. tostring(guiCandidateCount)
			.. " | registered="
			.. tostring(#eventBoards),
		"EventBoard"
	)
end

local function scheduleBoardStartupScan()
	scriptMaid:GiveSpawnTask(task.spawn(function()
		for attempt = 1, BOARD_STARTUP_RETRY_COUNT do
			if isCleanedUp or not isRunning then
				return
			end

			if #eventBoards > 0 then
				return
			end

			task.wait(BOARD_STARTUP_RETRY_INTERVAL)
			if isCleanedUp or not isRunning then
				return
			end

			DebugModule.debugInfo("Board startup rescan | attempt=" .. tostring(attempt), "EventBoard")
			scanForBoards()
		end
	end))
end

local function onAutomaticRsvpGateChanged(): ()
	if requestAutomaticRsvpProcessing then
		requestAutomaticRsvpProcessing()
	end
end

local function bindStartupLoadingGui(mainGui: Instance?): ()
	if startupLoadingGui == mainGui then
		return
	end

	scriptMaid.StartupLoadingCompleteChanged = nil
	startupLoadingGui = mainGui
	if mainGui then
		scriptMaid.StartupLoadingCompleteChanged = mainGui
			:GetAttributeChangedSignal("StartupLoadingComplete")
			:Connect(onAutomaticRsvpGateChanged)
	end

	onAutomaticRsvpGateChanged()
end

local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui
scriptMaid.MainGuiAdded = playerGui.ChildAdded:Connect(function(child: Instance)
	if child.Name == "MainGUI" then
		bindStartupLoadingGui(child)
	end
end)
scriptMaid.MainGuiRemoved = playerGui.ChildRemoved:Connect(function(child: Instance)
	if child == startupLoadingGui then
		bindStartupLoadingGui(nil)
	end
end)
bindStartupLoadingGui(playerGui:FindFirstChild("MainGUI"))

scriptMaid:GiveTask(localPlayer:GetAttributeChangedSignal("Data_Loaded"):Connect(onAutomaticRsvpGateChanged))
scriptMaid:GiveTask(localPlayer:GetAttributeChangedSignal("TutorialCompleted"):Connect(onAutomaticRsvpGateChanged))

scanForBoards()
DebugModule.debugInfo(
	"EventBoard runtime | placeId="
		.. tostring(game.PlaceId)
		.. " | universeId="
		.. tostring(game.GameId)
		.. " | configuredEventId="
		.. getConfiguredEventId(),
	"EventBoard"
)
refreshCurrentEvent(true)
scheduleForcedEventRefresh(0.5)
scheduleForcedEventRefresh(2)
scheduleForcedEventRefresh(5)
scheduleForcedEventRefresh(10)

scriptMaid:GiveTask(Workspace.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "Worlds" or descendant.Name == "World1" then
		scanForBoards()
	end

	if string.lower(descendant.Name) == "eventboard" and descendant:IsA("Model") then
		DebugModule.debugWarn("Board candidate streamed | path=" .. descendant:GetFullName(), "EventBoard")
		registerBoard(descendant)
		refreshCurrentEvent(true)
		return
	elseif string.lower(descendant.Name) == "eventboard" then
		DebugModule.debugWarn(
			"Board candidate streamed with unsupported class | class="
				.. descendant.ClassName
				.. " | path="
				.. descendant:GetFullName(),
			"EventBoard"
		)
	end

	local ancestorBoard = findAncestorEventBoard(descendant)
	if ancestorBoard and pendingBoards[ancestorBoard] then
		registerBoard(ancestorBoard)
		refreshCurrentEvent(true)
	end
end))

scheduleBoardStartupScan()

scriptMaid:GiveTask(Workspace.DescendantRemoving:Connect(function(descendant)
	if descendant:IsA("Model") and string.lower(descendant.Name) == "eventboard" then
		unregisterBoard(descendant)
	end
end))

scriptMaid:GiveTask(task.spawn(function()
	while isRunning and script.Parent ~= nil do
		refreshCurrentEvent(false)
		task.wait(1)
	end
end))

local function cleanupScript()
	if isCleanedUp then
		return
	end

	isCleanedUp = true
	isRunning = false

	for boardModel in pairs(boardMaids) do
		unregisterBoard(boardModel)
	end

	table.clear(eventBoards)
	table.clear(registeredBoards)
	table.clear(pendingBoards)
	table.clear(unregisteringBoards)
	table.clear(upcomingRsvpEvents)
	table.clear(automaticRsvpHandledEventIds)

	scriptMaid:DoCleaning()
end

scriptMaid:GiveTask(script.Destroying:Connect(cleanupScript))
scriptMaid:GiveTask(script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanupScript()
	end
end))
