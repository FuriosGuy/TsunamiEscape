--!strict

local BadgeService = game:GetService("BadgeService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)

local BadgeAwardService = {}
BadgeAwardService.__index = BadgeAwardService

local MODULE_NAME = "BadgeAwardService"
local badgeConfig: any = if typeof(CoreConfig.badges) == "table" then CoreConfig.badges else {}
local BADGE_EXPERIENCE_ID = if typeof(badgeConfig.experienceId) == "number"
	then math.floor(badgeConfig.experienceId)
	else 0
local SKIP_IN_STUDIO = badgeConfig.skipInStudio ~= false
local SUCCESS_REFRESH_SECONDS = math.max(60, math.floor(tonumber(badgeConfig.successRefreshSeconds) or 300))
local INITIAL_RETRY_SECONDS = math.max(5, math.floor(tonumber(badgeConfig.initialRetrySeconds) or 30))
local MAX_RETRY_SECONDS = math.max(INITIAL_RETRY_SECONDS, math.floor(tonumber(badgeConfig.maxRetrySeconds) or 600))
local MAX_BADGE_CHECK_COUNT = 10

type BadgeRequest = {
	badgeId: number,
	label: string,
}

type BadgeInfoCacheEntry = {
	isEnabled: boolean,
}

type PlayerState = {
	inFlight: boolean,
	pendingRequests: { BadgeRequest }?,
	knownEligible: { [number]: boolean },
	nextAttemptAt: number,
	retrySeconds: number,
	retryThread: thread?,
	requestThread: thread?,
	alive: boolean,
}

type Service = {
	playerStates: { [Player]: PlayerState },
	badgeInfoCache: { [number]: BadgeInfoCacheEntry },
	loggedSkipReasons: { [string]: boolean },
	alive: boolean,
}

local function copyRequests(requests: { BadgeRequest }): { BadgeRequest }
	local copied = {}
	for _, request in ipairs(requests) do
		table.insert(copied, {
			badgeId = request.badgeId,
			label = request.label,
		})
	end
	return copied
end

local function cancelThread(thread: thread?)
	if thread and coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
	end
end

local function getOwnedBadgeId(value: any): number?
	if typeof(value) == "number" and value > 0 then
		return math.floor(value)
	end
	if typeof(value) == "table" then
		local badgeId = value.BadgeId
		if typeof(badgeId) ~= "number" then
			badgeId = value.Id
		end
		if typeof(badgeId) ~= "number" then
			badgeId = value.id
		end
		if typeof(badgeId) == "number" and badgeId > 0 then
			return math.floor(badgeId)
		end
	end
	return nil
end

local function checkOwnedBadges(userId: number, badgeIds: { number }): (boolean, { [number]: boolean }, any)
	local ownedBadges: { [number]: boolean } = {}
	for startIndex = 1, #badgeIds, MAX_BADGE_CHECK_COUNT do
		local endIndex = math.min(startIndex + MAX_BADGE_CHECK_COUNT - 1, #badgeIds)
		local batch = {}
		for index = startIndex, endIndex do
			table.insert(batch, badgeIds[index])
		end

		local success, result = pcall(function()
			return BadgeService:CheckUserBadgesAsync(userId, batch)
		end)
		if not success or typeof(result) ~= "table" then
			return false, ownedBadges, result
		end

		for _, value in ipairs(result) do
			local badgeId = getOwnedBadgeId(value)
			if badgeId then
				ownedBadges[badgeId] = true
			end
		end
	end

	return true, ownedBadges, nil
end

function BadgeAwardService.new(): Service
	return setmetatable({
		playerStates = {},
		badgeInfoCache = {},
		loggedSkipReasons = {},
		alive = true,
	}, BadgeAwardService) :: Service
end

function BadgeAwardService:_logSkipOnce(reason: string, message: string)
	if self.loggedSkipReasons[reason] then
		return
	end
	self.loggedSkipReasons[reason] = true
	DebugModule.debugInfo(message, MODULE_NAME)
end

function BadgeAwardService:_canUseService(): boolean
	if not self.alive then
		return false
	end

	if SKIP_IN_STUDIO and RunService:IsStudio() then
		self:_logSkipOnce(
			"studio",
			"Badge API calls skipped in Studio; persistent badge awards require a published server"
		)
		return false
	end

	if BADGE_EXPERIENCE_ID <= 0 then
		self:_logSkipOnce(
			"missingExperience",
			"Badge API calls skipped because badge owning experience is not configured"
		)
		return false
	end

	if game.GameId ~= BADGE_EXPERIENCE_ID then
		self:_logSkipOnce(
			"wrongExperience",
			string.format(
				"Badge API calls skipped outside owning experience | currentUniverse=%d | badgeUniverse=%d",
				game.GameId,
				BADGE_EXPERIENCE_ID
			)
		)
		return false
	end

	return true
end

function BadgeAwardService:_getPlayerState(player: Player): PlayerState
	local existing = self.playerStates[player]
	if existing then
		return existing
	end

	local state: PlayerState = {
		inFlight = false,
		pendingRequests = nil,
		knownEligible = {},
		nextAttemptAt = 0,
		retrySeconds = INITIAL_RETRY_SECONDS,
		retryThread = nil,
		requestThread = nil,
		alive = true,
	}
	self.playerStates[player] = state
	return state
end

function BadgeAwardService:_hasNewRequest(state: PlayerState, requests: { BadgeRequest }): boolean
	for _, request in ipairs(requests) do
		if not state.knownEligible[request.badgeId] then
			return true
		end
	end
	return false
end

function BadgeAwardService:_scheduleRetry(
	player: Player,
	state: PlayerState,
	requests: { BadgeRequest },
	reason: string
)
	if not state.alive or not player.Parent then
		return
	end

	local retryAfter = state.retrySeconds
	state.retrySeconds = math.min(state.retrySeconds * 2, MAX_RETRY_SECONDS)
	state.nextAttemptAt = os.clock() + retryAfter
	DebugModule.debugWarn(
		string.format(
			"Badge sync retry scheduled | player=%s | afterSeconds=%d | reason=%s",
			player.Name,
			retryAfter,
			reason
		),
		MODULE_NAME
	)

	cancelThread(state.retryThread)
	state.retryThread = task.delay(retryAfter, function()
		state.retryThread = nil
		if not self.alive or not state.alive or not player.Parent then
			return
		end
		self:SyncPlayer(player, state.pendingRequests or requests)
	end)
end

function BadgeAwardService:_getBadgeInfo(badgeId: number): BadgeInfoCacheEntry?
	local cached = self.badgeInfoCache[badgeId]
	if cached then
		return cached
	end

	local success, result = pcall(function()
		return BadgeService:GetBadgeInfoAsync(badgeId)
	end)
	if not success or typeof(result) ~= "table" or typeof(result.IsEnabled) ~= "boolean" then
		return nil
	end

	local entry = { isEnabled = result.IsEnabled }
	self.badgeInfoCache[badgeId] = entry
	return entry
end

function BadgeAwardService:_runSync(player: Player, state: PlayerState, requests: { BadgeRequest })
	if not self.alive or not state.alive or not player.Parent then
		state.inFlight = false
		return
	end

	local badgeIds = {}
	for _, request in ipairs(requests) do
		table.insert(badgeIds, request.badgeId)
		state.knownEligible[request.badgeId] = true
	end

	local checkSuccess, ownedBadges, checkError = checkOwnedBadges(player.UserId, badgeIds)
	if not checkSuccess then
		state.inFlight = false
		state.requestThread = nil
		self:_scheduleRetry(player, state, requests, "CheckUserBadgesAsync: " .. tostring(checkError))
		return
	end

	local hasTransientFailure = false
	for _, request in ipairs(requests) do
		if not ownedBadges[request.badgeId] then
			local badgeInfo = self:_getBadgeInfo(request.badgeId)
			if not badgeInfo then
				hasTransientFailure = true
				DebugModule.debugWarn(
					string.format("%s badge metadata lookup failed for %s", request.label, player.Name),
					MODULE_NAME
				)
			elseif not badgeInfo.isEnabled then
				DebugModule.debugWarn(
					string.format("%s badge is disabled and cannot be awarded", request.label),
					MODULE_NAME
				)
			else
				local awardCallSuccess, awardedOrError = pcall(function()
					return BadgeService:AwardBadgeAsync(player.UserId, request.badgeId)
				end)
				if not awardCallSuccess or awardedOrError ~= true then
					hasTransientFailure = true
					DebugModule.debugWarn(
						string.format(
							"%s badge award failed for %s: %s",
							request.label,
							player.Name,
							tostring(awardedOrError)
						),
						MODULE_NAME
					)
				else
					ownedBadges[request.badgeId] = true
				end
			end
		end
	end

	state.inFlight = false
	state.requestThread = nil
	if hasTransientFailure then
		self:_scheduleRetry(player, state, requests, "badge metadata or award failure")
		return
	end

	state.retrySeconds = INITIAL_RETRY_SECONDS
	state.nextAttemptAt = os.clock() + SUCCESS_REFRESH_SECONDS
	if state.pendingRequests and self:_hasNewRequest(state, state.pendingRequests) then
		local pending = state.pendingRequests
		state.pendingRequests = nil
		self:SyncPlayer(player, pending)
	end
end

function BadgeAwardService:SyncPlayer(player: Player, requests: { BadgeRequest })
	if not self:_canUseService() or not player.Parent or #requests == 0 then
		return
	end

	local state = self:_getPlayerState(player)
	if not state.alive then
		return
	end

	local copiedRequests = copyRequests(requests)
	state.pendingRequests = copiedRequests
	if state.inFlight then
		return
	end

	if os.clock() < state.nextAttemptAt and not self:_hasNewRequest(state, copiedRequests) then
		return
	end

	state.pendingRequests = nil
	state.inFlight = true
	state.requestThread = task.spawn(function()
		local success, errorMessage = xpcall(function()
			self:_runSync(player, state, copiedRequests)
		end, debug.traceback)
		if not success and self.alive and state.alive and player.Parent then
			state.inFlight = false
			state.requestThread = nil
			self:_scheduleRetry(
				player,
				state,
				copiedRequests,
				"unexpected badge sync error: " .. tostring(errorMessage)
			)
		end
	end)
end

function BadgeAwardService:CleanupPlayer(player: Player)
	local state = self.playerStates[player]
	if not state then
		return
	end

	state.alive = false
	state.pendingRequests = nil
	cancelThread(state.retryThread)
	cancelThread(state.requestThread)
	state.retryThread = nil
	state.requestThread = nil
	self.playerStates[player] = nil
end

function BadgeAwardService:Shutdown()
	if not self.alive then
		return
	end

	self.alive = false
	local players = {}
	for player in pairs(self.playerStates) do
		table.insert(players, player)
	end
	for _, player in ipairs(players) do
		self:CleanupPlayer(player)
	end
	table.clear(self.badgeInfoCache)
	table.clear(self.loggedSkipReasons)
end

return BadgeAwardService
