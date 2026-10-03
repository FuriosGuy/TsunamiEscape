--!strict

local DataStoreService = game:GetService("DataStoreService")

type RequestKind = "StandardUpdate" | "OrderedWrite" | "OrderedList"
type RunOptions = {
	maxWaitSeconds: number?,
	shouldContinue: (() -> boolean)?,
	queueKey: string?,
}

local DataStoreRequestGate = {}

local DEFAULT_MAX_WAIT_SECONDS = 5
local POLL_INTERVAL_SECONDS = 0.25

type QueueState = {
	nextTicket: number,
	servingTicket: number,
	activeRequest: boolean,
	queuedTickets: { [number]: boolean },
}

local queueStates: { [string]: QueueState } = {}

local function getQueueState(queueKey: string): QueueState
	local existingState = queueStates[queueKey]
	if existingState then
		return existingState
	end

	local state: QueueState = {
		nextTicket = 0,
		servingTicket = 1,
		activeRequest = false,
		queuedTickets = {},
	}
	queueStates[queueKey] = state
	return state
end

local function resolveRequestType(names: { string }): any
	for _, name in ipairs(names) do
		local ok, requestType = pcall(function()
			return Enum.DataStoreRequestType[name]
		end)
		if ok and requestType ~= nil then
			return requestType
		end
	end
	return nil
end

local requestTypes: { [RequestKind]: { any } } = {
	StandardUpdate = {},
	OrderedWrite = {},
	OrderedList = {},
}

local standardRead = resolveRequestType({ "StandardRead", "GetAsync" })
local standardWrite = resolveRequestType({ "StandardWrite", "SetIncrementAsync" })
local legacyUpdate = resolveRequestType({ "UpdateAsync" })
if standardRead ~= nil and standardWrite ~= nil then
	requestTypes.StandardUpdate = { standardRead, standardWrite }
elseif legacyUpdate ~= nil then
	requestTypes.StandardUpdate = { legacyUpdate }
end

local orderedWrite = resolveRequestType({ "OrderedWrite", "SetIncrementSortedAsync" })
if orderedWrite ~= nil then
	requestTypes.OrderedWrite = { orderedWrite }
end

local orderedList = resolveRequestType({ "OrderedList", "GetSortedAsync" })
if orderedList ~= nil then
	requestTypes.OrderedList = { orderedList }
end

local function advanceServingTicket(state: QueueState)
	while
		state.servingTicket <= state.nextTicket
		and state.queuedTickets[state.servingTicket] == nil
		and not state.activeRequest
	do
		state.servingTicket += 1
	end
end

local function cancelTicket(state: QueueState, ticket: number)
	state.queuedTickets[ticket] = nil
	advanceServingTicket(state)
end

local function acquireRequestSlot(
	queueKey: string,
	maxWaitSeconds: number,
	shouldContinue: (() -> boolean)?
): (boolean, number?, QueueState?)
	local state = getQueueState(queueKey)
	state.nextTicket += 1
	local ticket = state.nextTicket
	state.queuedTickets[ticket] = true
	local deadline = os.clock() + maxWaitSeconds

	while true do
		if shouldContinue ~= nil and not shouldContinue() then
			cancelTicket(state, ticket)
			return false, nil, nil
		end

		if ticket == state.servingTicket and not state.activeRequest then
			state.queuedTickets[ticket] = nil
			state.activeRequest = true
			return true, ticket, state
		end

		local remaining = deadline - os.clock()
		if remaining <= 0 then
			cancelTicket(state, ticket)
			return false, nil, nil
		end
		task.wait(math.min(POLL_INTERVAL_SECONDS, remaining))
	end
end

local function releaseRequestSlot(state: QueueState, ticket: number)
	if not state.activeRequest then
		return
	end

	state.activeRequest = false
	if state.servingTicket == ticket then
		state.servingTicket += 1
	end
	advanceServingTicket(state)
end

local function hasAvailableBudget(kind: RequestKind): boolean
	local types = requestTypes[kind]
	if #types == 0 then
		-- Older engine versions may not expose the newer budget enums. In that
		-- case, retain pcall protection and let Roblox handle the request.
		return true
	end

	for _, requestType in ipairs(types) do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(requestType)
		end)
		if not ok or typeof(budget) ~= "number" then
			return true
		end
		if budget < 1 then
			return false
		end
	end

	return true
end

function DataStoreRequestGate.Run(
	kind: RequestKind,
	operationName: string,
	operation: () -> any,
	options: RunOptions?
): (boolean, any, any, any)
	local resolvedOptions = options or {}
	local maxWaitSeconds = math.max(0, resolvedOptions.maxWaitSeconds or DEFAULT_MAX_WAIT_SECONDS)
	local shouldContinue = resolvedOptions.shouldContinue
	local queueKey = resolvedOptions.queueKey or "Default"
	local acquired, ticket, queueState = acquireRequestSlot(queueKey, maxWaitSeconds, shouldContinue)
	if not acquired or ticket == nil or queueState == nil then
		return false, "Request gate wait cancelled or timed out: " .. operationName, nil, nil
	end

	local deadline = os.clock() + maxWaitSeconds
	while not hasAvailableBudget(kind) do
		if shouldContinue ~= nil and not shouldContinue() then
			releaseRequestSlot(queueState, ticket)
			return false, "Request gate wait cancelled: " .. operationName, nil, nil
		end

		local remaining = deadline - os.clock()
		if remaining <= 0 then
			releaseRequestSlot(queueState, ticket)
			return false, "Datastore budget wait timed out: " .. operationName, nil, nil
		end
		task.wait(math.min(POLL_INTERVAL_SECONDS, remaining))
	end

	local ok, result, result2, result3 = pcall(operation)
	releaseRequestSlot(queueState, ticket)
	return ok, result, result2, result3
end

return DataStoreRequestGate
