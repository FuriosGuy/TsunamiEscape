local LiveEventSchedule = {}

type ScheduleDefinition = {
	kind: string?,
	startUnix: number?,
	endUnix: number?,
	cycleStartUnix: number?,
	firstCyclePreEventCountdownStartUnix: number?,
	firstCycleStartsActive: boolean?,
	activeDurationSeconds: number?,
	graceDurationSeconds: number?,
	activeDurationMinSeconds: number?,
	activeDurationMaxSeconds: number?,
	graceDurationMinSeconds: number?,
	graceDurationMaxSeconds: number?,
	randomStepSeconds: number?,
	randomSeed: number?,
}

type DurationRange = {
	minimum: number,
	maximum: number,
}

type RecurringDefinitionValues = {
	firstActiveStartUnix: number,
	activeDurationRange: DurationRange,
	graceDurationRange: DurationRange,
	randomStepSeconds: number,
	randomSeed: number,
}

type RecurringWindow = {
	cycleIndex: number,
	activeStartUnix: number,
	activeDuration: number,
	graceDuration: number,
	nextActiveStartUnix: number,
}

type RecurringWindowCache = RecurringDefinitionValues & RecurringWindow

local recurringWindowCaches: { [any]: RecurringWindowCache } = {}
local DETERMINISTIC_MODULUS = 2147483647
local MAX_CYCLE_SEARCH = 100000

local function normalizeDuration(value: any): number?
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end

	return math.max(1, math.floor(value))
end

local function resolveDurationRange(minimumValue: any, maximumValue: any, fixedValue: any): DurationRange?
	local minimum = normalizeDuration(minimumValue) or normalizeDuration(fixedValue)
	local maximum = normalizeDuration(maximumValue) or minimum
	if minimum == nil or maximum == nil then
		return nil
	end

	if maximum < minimum then
		minimum, maximum = maximum, minimum
	end

	return {
		minimum = minimum,
		maximum = maximum,
	}
end

local function getDeterministicDuration(
	range: DurationRange,
	cycleIndex: number,
	seed: number,
	salt: number,
	stepSeconds: number
): number
	if range.minimum == range.maximum then
		return range.minimum
	end

	local step = math.max(1, math.floor(stepSeconds))
	local span = math.floor((range.maximum - range.minimum) / step) + 1
	local rawValue = (math.floor(seed) + cycleIndex * 1103515245 + salt * 12345) % DETERMINISTIC_MODULUS
	return range.minimum + (rawValue % span) * step
end

local function createRecurringWindow(
	values: RecurringDefinitionValues,
	cycleIndex: number,
	activeStartUnix: number
): RecurringWindowCache
	local activeDuration = getDeterministicDuration(
		values.activeDurationRange,
		cycleIndex,
		values.randomSeed,
		17,
		values.randomStepSeconds
	)
	local graceDuration =
		getDeterministicDuration(values.graceDurationRange, cycleIndex, values.randomSeed, 31, values.randomStepSeconds)

	return {
		firstActiveStartUnix = values.firstActiveStartUnix,
		activeDurationRange = values.activeDurationRange,
		graceDurationRange = values.graceDurationRange,
		randomStepSeconds = values.randomStepSeconds,
		randomSeed = values.randomSeed,
		cycleIndex = cycleIndex,
		activeStartUnix = activeStartUnix,
		activeDuration = activeDuration,
		graceDuration = graceDuration,
		nextActiveStartUnix = activeStartUnix + activeDuration + graceDuration,
	}
end

local function matchesRecurringDefinition(cache: RecurringWindowCache, values: RecurringDefinitionValues): boolean
	return cache.firstActiveStartUnix == values.firstActiveStartUnix
		and cache.activeDurationRange.minimum == values.activeDurationRange.minimum
		and cache.activeDurationRange.maximum == values.activeDurationRange.maximum
		and cache.graceDurationRange.minimum == values.graceDurationRange.minimum
		and cache.graceDurationRange.maximum == values.graceDurationRange.maximum
		and cache.randomStepSeconds == values.randomStepSeconds
		and cache.randomSeed == values.randomSeed
end

local function getUniversalDate(timestamp: number): { [string]: number }
	return os.date("!*t", timestamp)
end

local function getNthWeekdayOfMonth(year: number, month: number, weekday: number, occurrence: number): number
	local firstDayWeekday = getUniversalDate(DateTime.fromUniversalTime(year, month, 1).UnixTimestamp).wday
	local offset = (weekday - firstDayWeekday) % 7
	return 1 + offset + (occurrence - 1) * 7
end

local function isPacificDaylightTime(timestamp: number): boolean
	local year = getUniversalDate(timestamp).year
	local dstStartDay = getNthWeekdayOfMonth(year, 3, 1, 2)
	local dstEndDay = getNthWeekdayOfMonth(year, 11, 1, 1)
	local dstStart = DateTime.fromUniversalTime(year, 3, dstStartDay, 10).UnixTimestamp
	local dstEnd = DateTime.fromUniversalTime(year, 11, dstEndDay, 9).UnixTimestamp

	return timestamp >= dstStart and timestamp < dstEnd
end

local function isWeekendTokyoToPacific(timestamp: number): boolean
	local tokyoWeekday = getUniversalDate(timestamp + 9 * 60 * 60).wday
	if tokyoWeekday == 7 or tokyoWeekday == 1 then
		return true
	end

	-- Monday in Tokyo can still be Sunday in Pacific Time. Account for DST.
	if tokyoWeekday == 2 then
		local pacificOffset = if isPacificDaylightTime(timestamp) then -7 * 60 * 60 else -8 * 60 * 60
		return getUniversalDate(timestamp + pacificOffset).wday == 1
	end

	return false
end

local function getPacificOffset(timestamp: number): number
	return if isPacificDaylightTime(timestamp) then -7 * 60 * 60 else -8 * 60 * 60
end

local function getNextPacificMondayMidnight(timestamp: number): number
	local pacificOffset = getPacificOffset(timestamp)
	local pacificDate = getUniversalDate(timestamp + pacificOffset)
	local daysUntilMonday = (2 - pacificDate.wday) % 7
	if daysUntilMonday == 0 then
		daysUntilMonday = 7
	end

	local localMidnight = DateTime.fromUniversalTime(pacificDate.year, pacificDate.month, pacificDate.day).UnixTimestamp
	local targetLocalMidnight = localMidnight + daysUntilMonday * 24 * 60 * 60
	local candidateTimestamp = targetLocalMidnight - pacificOffset
	return targetLocalMidnight - getPacificOffset(candidateTimestamp)
end

local function getNextTokyoSaturdayMidnight(timestamp: number): number
	local tokyoDate = getUniversalDate(timestamp + 9 * 60 * 60)
	local daysUntilSaturday = (7 - tokyoDate.wday) % 7
	local localMidnight = DateTime.fromUniversalTime(tokyoDate.year, tokyoDate.month, tokyoDate.day).UnixTimestamp
	local candidateTimestamp = localMidnight + daysUntilSaturday * 24 * 60 * 60 - 9 * 60 * 60
	if candidateTimestamp <= timestamp then
		candidateTimestamp += 7 * 24 * 60 * 60
	end

	return candidateTimestamp
end

local function getRecurringDefinitionValues(definition: ScheduleDefinition): RecurringDefinitionValues?
	local cycleStartUnix = definition.cycleStartUnix
	if typeof(cycleStartUnix) ~= "number" or cycleStartUnix <= 0 then
		return nil
	end

	local activeDurationRange = resolveDurationRange(
		definition.activeDurationMinSeconds,
		definition.activeDurationMaxSeconds,
		definition.activeDurationSeconds
	)
	local graceDurationRange = resolveDurationRange(
		definition.graceDurationMinSeconds,
		definition.graceDurationMaxSeconds,
		definition.graceDurationSeconds
	)
	if not activeDurationRange or not graceDurationRange then
		return nil
	end

	local randomSeed = normalizeDuration(definition.randomSeed) or 0
	local randomStepSeconds = normalizeDuration(definition.randomStepSeconds) or 1
	local firstActiveStartUnix = cycleStartUnix
	if definition.firstCycleStartsActive == false then
		firstActiveStartUnix += getDeterministicDuration(graceDurationRange, 0, randomSeed, 31, randomStepSeconds)
	end

	return {
		firstActiveStartUnix = firstActiveStartUnix,
		activeDurationRange = activeDurationRange,
		graceDurationRange = graceDurationRange,
		randomStepSeconds = randomStepSeconds,
		randomSeed = randomSeed,
	}
end

local function getRecurringWindowAtTimestamp(definition: ScheduleDefinition, timestamp: number): RecurringWindowCache?
	local values = getRecurringDefinitionValues(definition)
	if not values then
		return nil
	end

	local cache = recurringWindowCaches[definition]
	if not cache or not matchesRecurringDefinition(cache, values) or timestamp < values.firstActiveStartUnix then
		cache = createRecurringWindow(values, 0, values.firstActiveStartUnix)
		recurringWindowCaches[definition] = cache
	end

	if timestamp >= cache.activeStartUnix then
		local averageCycleDuration = (
			values.activeDurationRange.minimum
			+ values.activeDurationRange.maximum
			+ values.graceDurationRange.minimum
			+ values.graceDurationRange.maximum
		) / 2
		local estimatedCycleIndex =
			math.max(cache.cycleIndex, math.floor((timestamp - values.firstActiveStartUnix) / averageCycleDuration))
		if estimatedCycleIndex > cache.cycleIndex then
			for cycleIndex = cache.cycleIndex + 1, math.min(estimatedCycleIndex, MAX_CYCLE_SEARCH) do
				cache = createRecurringWindow(values, cycleIndex, cache.nextActiveStartUnix)
			end
		end
	end

	if cache.activeStartUnix > timestamp then
		cache = createRecurringWindow(values, 0, values.firstActiveStartUnix)
		recurringWindowCaches[definition] = cache
	end

	local searchCount = 0
	while timestamp >= cache.nextActiveStartUnix and searchCount < MAX_CYCLE_SEARCH do
		searchCount += 1
		cache = createRecurringWindow(values, cache.cycleIndex + 1, cache.nextActiveStartUnix)
	end

	recurringWindowCaches[definition] = cache
	return cache
end

function LiveEventSchedule.IsActive(schedule: any, timestamp: number): boolean
	if typeof(schedule) ~= "table" then
		return false
	end

	local definition = schedule :: ScheduleDefinition
	if definition.kind == "WeekendTokyoToPacific" then
		return isWeekendTokyoToPacific(timestamp)
	end
	if definition.kind == "AbsoluteWindow" then
		return typeof(definition.startUnix) == "number"
			and typeof(definition.endUnix) == "number"
			and timestamp >= definition.startUnix
			and timestamp < definition.endUnix
	end
	if definition.kind == "RecurringWindow" then
		local recurringWindow = getRecurringWindowAtTimestamp(definition, timestamp)
		if not recurringWindow then
			return false
		end

		return timestamp >= recurringWindow.activeStartUnix
			and timestamp < recurringWindow.activeStartUnix + recurringWindow.activeDuration
	end

	return false
end

function LiveEventSchedule.GetEndUnix(schedule: any, timestamp: number): number?
	if typeof(schedule) ~= "table" then
		return nil
	end

	local definition = schedule :: ScheduleDefinition
	if definition.kind == "AbsoluteWindow" and typeof(definition.endUnix) == "number" then
		return definition.endUnix
	end
	if definition.kind == "WeekendTokyoToPacific" and isWeekendTokyoToPacific(timestamp) then
		return getNextPacificMondayMidnight(timestamp)
	end
	if definition.kind == "RecurringWindow" then
		local recurringWindow = getRecurringWindowAtTimestamp(definition, timestamp)
		if not recurringWindow then
			return nil
		end
		if timestamp < recurringWindow.activeStartUnix then
			return nil
		end

		return recurringWindow.activeStartUnix + recurringWindow.activeDuration
	end

	return nil
end

function LiveEventSchedule.GetStartUnix(schedule: any, timestamp: number): number?
	if typeof(schedule) ~= "table" then
		return nil
	end

	local definition = schedule :: ScheduleDefinition
	if definition.kind == "AbsoluteWindow" and typeof(definition.startUnix) == "number" then
		return definition.startUnix
	end
	if definition.kind == "WeekendTokyoToPacific" then
		return getNextTokyoSaturdayMidnight(timestamp)
	end
	if definition.kind == "RecurringWindow" then
		local recurringWindow = getRecurringWindowAtTimestamp(definition, timestamp)
		if not recurringWindow then
			return nil
		end
		if timestamp < recurringWindow.activeStartUnix then
			return recurringWindow.activeStartUnix
		end

		if timestamp < recurringWindow.activeStartUnix + recurringWindow.activeDuration then
			return recurringWindow.activeStartUnix
		end

		return recurringWindow.nextActiveStartUnix
	end

	return nil
end

function LiveEventSchedule.GetPreEventCountdownSeconds(
	schedule: any,
	timestamp: number,
	defaultSeconds: number?
): number?
	if typeof(defaultSeconds) ~= "number" then
		return nil
	end
	if typeof(schedule) ~= "table" then
		return defaultSeconds
	end

	local definition = schedule :: ScheduleDefinition
	if definition.kind ~= "RecurringWindow" then
		return defaultSeconds
	end

	local firstCountdownStartUnix = definition.firstCyclePreEventCountdownStartUnix
	if typeof(firstCountdownStartUnix) ~= "number" then
		return defaultSeconds
	end

	local recurringWindow = getRecurringWindowAtTimestamp(definition, timestamp)
	if
		not recurringWindow
		or recurringWindow.cycleIndex ~= 0
		or timestamp < firstCountdownStartUnix
		or timestamp >= recurringWindow.activeStartUnix
	then
		return defaultSeconds
	end

	return math.max(0, recurringWindow.activeStartUnix - firstCountdownStartUnix)
end

return LiveEventSchedule
