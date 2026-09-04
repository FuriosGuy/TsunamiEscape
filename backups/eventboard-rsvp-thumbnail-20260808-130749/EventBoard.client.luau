--!strict
local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)

local localPlayer = Players.LocalPlayer

local EVENT_FETCH_INTERVAL = 30
local EVENT_EMPTY_RETRY_INTERVAL = 3
local EVENT_ERROR_RETRY_INTERVAL = 5
local EVENT_STARTUP_RETRY_INTERVAL = 2
local EVENT_STARTUP_RETRY_COUNT = 15
local EVENT_TOUCH_DEBOUNCE = 3
local BOARD_STARTUP_RETRY_INTERVAL = 0.5
local BOARD_STARTUP_RETRY_COUNT = 20
local EVENT_STATUS_NOW = "NOW HAPPENING!"
local EVENT_STATUS_NONE = "NO EVENT YET"
local EVENT_STATUS_LOADING = "LOADING EVENT..."
local EVENT_COUNTDOWN_NONE = "CHECK BACK SOON"
local EVENT_COUNTDOWN_FINISHED = "EVENT FINISHED!"
local EVENT_COUNTDOWN_PREFIX = "LIVE IN: "
local EVENT_PLACEHOLDER_IMAGE = "rbxassetid://81072563465880"

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
	eventLabel: TextLabel?,
	countdownLabel: TextLabel?,
	imageLabel: ImageLabel?,
	lastTouchTime: number,
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
local rsvpRefreshToken = 0
local eventBoardConfig = if typeof(CoreConfig.eventBoard) == "table" then CoreConfig.eventBoard else {}
local scheduleSelectedEventBoundaryRefresh: ((EventDictionary?) -> ())? = nil

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
	for _, key in ipairs({ "mediaId", "MediaId", "id", "Id", "assetId", "AssetId" }) do
		local nestedId = getPositiveAssetId(thumbnailData[key])
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

local function getEventThumbnailId(eventData: EventDictionary?): number?
	if not eventData then
		return nil
	end

	local thumbnailIds = eventData.ThumbnailIds
	if typeof(thumbnailIds) == "table" then
		local primaryThumbnailId = thumbnailIds[1]
		if typeof(primaryThumbnailId) == "number" and primaryThumbnailId > 0 then
			return primaryThumbnailId
		end
	end

	for _, thumbnailId in ipairs({ eventData.ThumbnailId, eventData.PreviewAssetId }) do
		local positiveThumbnailId = getPositiveAssetId(thumbnailId)
		if positiveThumbnailId then
			return positiveThumbnailId
		end
	end

	for _, thumbnailData in ipairs({
		eventData.thumbnails,
		eventData.Thumbnails,
		eventData.thumbnail,
		eventData.Thumbnail,
	}) do
		local nestedThumbnailId = getNestedThumbnailId(thumbnailData)
		if nestedThumbnailId then
			return nestedThumbnailId
		end
	end

	local configuredThumbnailId = getConfiguredEventThumbnailId(getEventId(eventData))
	if configuredThumbnailId then
		return configuredThumbnailId
	end

	return nil
end

local function getEventImageContent(eventData: EventDictionary?): string
	local thumbnailId = getEventThumbnailId(eventData)
	if thumbnailId then
		return "rbxassetid://" .. tostring(thumbnailId)
	end

	return EVENT_PLACEHOLDER_IMAGE
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
		boardState.imageLabel.Image = getEventImageContent(selectedEvent)
	end
end

local function applyAllBoards()
	for _, boardState in ipairs(eventBoards) do
		applyBoardState(boardState)
	end
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

	for _, eventData in ipairs(normalizedEvents) do
		if getEventLifecycleState(eventData) == "Active" then
			return eventData
		end
	end

	for _, eventData in ipairs(normalizedEvents) do
		if getEventLifecycleState(eventData) == "Upcoming" then
			return eventData
		end
	end

	for _, eventData in ipairs(normalizedEvents) do
		if eventData.HasEnded ~= true then
			return eventData
		end
	end

	return nil
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
	if getEventThumbnailId(eventData) then
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
			DebugModule.debugWarn("Failed to load event details for " .. eventId .. ": " .. tostring(result), "EventBoard")
		end
		return eventData
	end

	local detailedEvent = table.clone(eventData) :: any
	for key, value in pairs(result :: { [string]: any }) do
		detailedEvent[key] = value
	end

	return detailedEvent :: EventDictionary
end

local function setSelectedEvent(eventData: EventDictionary?)
	selectedEvent = eventData
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
				nextFetchTime = now + (if startupFetchAttemptCount <= EVENT_STARTUP_RETRY_COUNT
					then EVENT_STARTUP_RETRY_INTERVAL
					else EVENT_ERROR_RETRY_INTERVAL)
			end
		end
		applyAllBoards()
		return
	end

	hasFetchedEvents = true
	local processingSuccess, bestEventOrError = pcall(function()
		local events = extractEventsFromResult(result)
		DebugModule.debugInfo("Automatic event fetch succeeded | eventCount=" .. tostring(#events), "EventBoard")
		return pickBestEvent(events)
	end)
	if not processingSuccess then
		DebugModule.debugWarn(
			"Failed to process upcoming experience events: " .. tostring(bestEventOrError),
			"EventBoard"
		)
		startupFetchAttemptCount += 1
		nextFetchTime = now + EVENT_STARTUP_RETRY_INTERVAL
		applyAllBoards()
		return
	end

	local bestEvent = bestEventOrError :: EventDictionary?
	if bestEvent then
		setSelectedEvent(enrichEventDetails(bestEvent))
		DebugModule.debugInfo(
			"Selected event | eventId="
				.. getEventId(selectedEvent)
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
			nextFetchTime = now + (if startupFetchAttemptCount <= EVENT_STARTUP_RETRY_COUNT
				then EVENT_STARTUP_RETRY_INTERVAL
				else EVENT_EMPTY_RETRY_INTERVAL)
		end
	end

	applyAllBoards()
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
		elseif endTimestamp and endTimestamp > nowTimestamp
		then endTimestamp
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

local function promptSelectedEvent(boardState: EventBoardGuiState)
	refreshCurrentEvent(true)

	if not selectedEvent then
		return
	end

	if not isRsvpEligibleEvent(selectedEvent) then
		return
	end

	local eventId = getEventId(selectedEvent)
	if eventId == "" then
		return
	end

	local now = os.clock()
	if now - boardState.lastTouchTime < EVENT_TOUCH_DEBOUNCE then
		return
	end

	boardState.lastTouchTime = now
	rsvpRefreshToken += 1
	local refreshToken = rsvpRefreshToken

	scriptMaid:GiveSpawnTask(task.spawn(function()
		local statusSuccess, currentStatus = pcall(function()
			return SocialService:GetEventRsvpStatusAsync(eventId)
		end)
		if statusSuccess and currentStatus == Enum.RsvpStatus.Going then
			DebugModule.debugInfo("Player is already RSVP'd to event " .. eventId, "EventBoard")
			return
		end

		local success, result = pcall(function()
			return SocialService:PromptRsvpToEventAsync(eventId)
		end)

		if not success then
			DebugModule.debugWarn("Failed to prompt event RSVP for " .. eventId .. ": " .. tostring(result), "EventBoard")
		end

		task.wait(1)
		if isCleanedUp or not isRunning then
			return
		end
		if refreshToken ~= rsvpRefreshToken then
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
	if boardState.touchPart ~= nil then
		return
	end

	boardState.touchPart = touchPart
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
end

local function createBoardState(boardModel: Model): EventBoardGuiState?
	local billboardGui = boardModel:FindFirstChild("BillboardGui", true)
	if not billboardGui then
		return nil
	end

	local touchPart = boardModel:FindFirstChild("TouchPart", true)
	local validTouchPart = if touchPart and touchPart:IsA("BasePart") then touchPart else nil

	local boardState: EventBoardGuiState = {
		model = boardModel,
		touchPart = validTouchPart,
		eventLabel = nil,
		countdownLabel = nil,
		imageLabel = nil,
		lastTouchTime = 0,
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

			DebugModule.debugInfo(
				"Board startup rescan | attempt=" .. tostring(attempt),
				"EventBoard"
			)
			scanForBoards()
		end
	end))
end

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

	scriptMaid:DoCleaning()
end

scriptMaid:GiveTask(script.Destroying:Connect(cleanupScript))
scriptMaid:GiveTask(script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanupScript()
	end
end))
