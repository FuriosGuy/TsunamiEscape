local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("DebugModule"))
local PlayerHandler =
	require(game:GetService("ServerScriptService").Modules.Shared:WaitForChild("PlayerHandler_Server"))

local ValidationService = {}

type PositionSample = {
	character: Model,
	position: Vector3,
	observedAt: number,
	worldName: string?,
	previousPosition: Vector3?,
	previousObservedAt: number?,
}

type PathSample = {
	position: Vector3,
	observedAt: number,
}

type PartBounds = {
	frame: CFrame,
	halfSize: Vector3,
}

-- Movement validation is intentionally soft: it blocks rewards, never players.
local POSITION_SAMPLE_INTERVAL = 0.1
local MAX_SAMPLE_ELAPSED = 1.5
local SERVER_TELEPORT_GRACE_SECONDS = 0.75
local SUSPICIOUS_MOVEMENT_SECONDS = 3
local MIN_SUSPICIOUS_DISTANCE = 100
local SPEED_TOLERANCE_RATIO = 0.35
local MIN_DISTANCE_TOLERANCE = 50
local SUSPICIOUS_LOG_COOLDOWN = 2
local MAX_TRAVEL_TIME_PING_GRACE_SECONDS = 0.35
local MAX_GENERIC_PING_DISTANCE_GRACE = 50
local MOVEMENT_EVIDENCE_DECAY_PER_SECOND = 1.5
local MOVEMENT_EVIDENCE_BLOCK_THRESHOLD = 2.5
local HARD_MOVEMENT_DISTANCE = 300
local HARD_MOVEMENT_RATIO = 4
local MIN_RELIABLE_SAMPLE_ELAPSED = 0.05
local MAX_PATH_SAMPLES = 64
local MAX_STAGE_PATH_AGE_SECONDS = 6
-- Ignore sub-centimeter physics jitter while retaining cumulative slow movement.
local MIN_PATH_SAMPLE_MOVEMENT_SQUARED = 0.0025

local positionSamples: { [Player]: PositionSample } = {}
local pathSamples: { [Player]: { PathSample } } = {}
local stageReconcileRevisionByPlayer: { [Player]: number } = {}
local nextPositionObservation: { [Player]: number } = {}
local serverTeleportGraceUntil: { [Player]: number } = {}
local suspiciousMovementUntil: { [Player]: number } = {}
local lastSuspiciousLogAt: { [Player]: number } = {}
local lastRewardBlockLogAt: { [Player]: number } = {}
local movementEvidenceScore: { [Player]: number } = {}
local movementEvidenceObservedAt: { [Player]: number } = {}
local highestPassedStageByPlayer: { [Player]: { [string]: number } } = {}

local function getWorldName(player: Player): string?
	local worldName = player:GetAttribute("Current_World")
	return if typeof(worldName) == "string" then worldName else nil
end

local function bumpStageReconcileRevision(player: Player): ()
	stageReconcileRevisionByPlayer[player] = (stageReconcileRevisionByPlayer[player] or 0) + 1
end

local function clearPathSamples(player: Player): ()
	if pathSamples[player] ~= nil then
		pathSamples[player] = nil
		bumpStageReconcileRevision(player)
	end
end

local function updatePositionSample(player: Player, character: Model, rootPart: BasePart, now: number)
	local worldName = getWorldName(player)
	local previousSample = positionSamples[player]
	local path = pathSamples[player]
	if
		not path
		or not previousSample
		or previousSample.character ~= character
		or previousSample.worldName ~= worldName
	then
		path = {}
		pathSamples[player] = path
	end
	local lastPathSample = path[#path]
	local pathDelta = if lastPathSample then rootPart.Position - lastPathSample.position else Vector3.zero
	if not lastPathSample or pathDelta:Dot(pathDelta) > MIN_PATH_SAMPLE_MOVEMENT_SQUARED then
		table.insert(path, { position = rootPart.Position, observedAt = now })
		if #path > MAX_PATH_SAMPLES then
			table.remove(path, 1)
		end
		bumpStageReconcileRevision(player)
	end

	local previousPosition = if previousSample
			and previousSample.character == character
			and previousSample.worldName == worldName
		then previousSample.position
		else nil
	local previousObservedAt = if previousSample
			and previousSample.character == character
			and previousSample.worldName == worldName
		then previousSample.observedAt
		else nil
	positionSamples[player] = {
		character = character,
		position = rootPart.Position,
		observedAt = now,
		worldName = worldName,
		previousPosition = previousPosition,
		previousObservedAt = previousObservedAt,
	}
end

local function resetMovementEvidence(player: Player)
	movementEvidenceScore[player] = nil
	movementEvidenceObservedAt[player] = nil
	suspiciousMovementUntil[player] = nil
end

local function getPingGraceSeconds(player: Player): (number, number)
	local success, pingSeconds = pcall(function()
		return player:GetNetworkPing()
	end)
	if not success or typeof(pingSeconds) ~= "number" or pingSeconds < 0 then
		return 0, 0
	end

	local boundedPing = math.min(pingSeconds, 2)
	return math.min(boundedPing * 0.5, MAX_TRAVEL_TIME_PING_GRACE_SECONDS), boundedPing
end

local function getAllowedMovementDistance(player: Player, expectedSpeed: number, elapsed: number): (number, number)
	local distanceTolerance = math.max(MIN_DISTANCE_TOLERANCE, expectedSpeed * SPEED_TOLERANCE_RATIO)
	local pingGrace, pingSeconds = getPingGraceSeconds(player)
	local pingDistanceGrace = math.min(expectedSpeed * pingGrace, MAX_GENERIC_PING_DISTANCE_GRACE)
	return expectedSpeed * elapsed + distanceTolerance + pingDistanceGrace, pingSeconds
end

local function addMovementEvidence(player: Player, contribution: number, now: number): number
	local previousScore = movementEvidenceScore[player] or 0
	local previousAt = movementEvidenceObservedAt[player] or now
	local decay = math.max(0, now - previousAt) * MOVEMENT_EVIDENCE_DECAY_PER_SECOND
	local nextScore = math.max(0, previousScore - decay) + contribution
	movementEvidenceScore[player] = nextScore
	movementEvidenceObservedAt[player] = now
	return nextScore
end

local function getPartBounds(part: BasePart, padding: Vector3?): PartBounds
	-- Snapshot checkpoint geometry once; every segment in this path query reuses it.
	local extraPadding = padding or Vector3.new(0.25, 0.25, 0.25)
	local size = part.Size
	return {
		frame = part.CFrame,
		halfSize = Vector3.new(
			size.X * 0.5 + math.max(0, extraPadding.X),
			size.Y * 0.5 + math.max(0, extraPadding.Y),
			size.Z * 0.5 + math.max(0, extraPadding.Z)
		),
	}
end

local function isPointWithinPartBounds(point: Vector3, part: BasePart, padding: Vector3?): boolean
	local bounds = getPartBounds(part, padding)
	local localPosition = bounds.frame:PointToObjectSpace(point)
	local halfSize = bounds.halfSize
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function updateSegmentSlab(
	startValue: number,
	endValue: number,
	halfExtent: number,
	tMin: number,
	tMax: number
): (number, number, boolean)
	local delta = endValue - startValue
	if math.abs(delta) < 0.000001 then
		return tMin, tMax, math.abs(startValue) <= halfExtent
	end

	local first = (-halfExtent - startValue) / delta
	local second = (halfExtent - startValue) / delta
	if first > second then
		first, second = second, first
	end

	return math.max(tMin, first), math.min(tMax, second), true
end

local function doesSegmentIntersectPartBounds(
	startPoint: Vector3,
	endPoint: Vector3,
	bounds: PartBounds
): boolean
	local localStart = bounds.frame:PointToObjectSpace(startPoint)
	local localEnd = bounds.frame:PointToObjectSpace(endPoint)
	local halfSize = bounds.halfSize
	local tMin, tMax = 0, 1

	local xMin, xMax, xIntersects = updateSegmentSlab(localStart.X, localEnd.X, halfSize.X, tMin, tMax)
	if not xIntersects or xMin > xMax then
		return false
	end
	tMin, tMax = xMin, xMax
	local yMin, yMax, yIntersects = updateSegmentSlab(localStart.Y, localEnd.Y, halfSize.Y, tMin, tMax)
	if not yIntersects or yMin > yMax then
		return false
	end
	tMin, tMax = yMin, yMax
	local zMin, zMax, zIntersects = updateSegmentSlab(localStart.Z, localEnd.Z, halfSize.Z, tMin, tMax)
	return zIntersects and zMin <= zMax
end

local function didRecentSampleCrossPart(
	player: Player,
	character: Model,
	part: BasePart,
	padding: Vector3?,
	maximumAge: number?
): boolean
	local sample = positionSamples[player]
	if not sample or sample.character ~= character or sample.worldName ~= getWorldName(player) then
		return false
	end

	local now = os.clock()
	local path = pathSamples[player]
	local pathAge = maximumAge or MAX_SAMPLE_ELAPSED
	if now - sample.observedAt > pathAge or not path or #path < 2 then
		return false
	end
	local bounds = getPartBounds(part, padding)

	for index = #path - 1, 1, -1 do
		local startSample = path[index]
		local endSample = path[index + 1]
		if now - startSample.observedAt > pathAge then
			break
		end
		if doesSegmentIntersectPartBounds(startSample.position, endSample.position, bounds) then
			return true
		end
	end

	return false
end

local function flagSuspiciousMovement(
	player: Player,
	distance: number,
	elapsed: number,
	allowedDistance: number,
	now: number,
	evidenceScore: number,
	pingSeconds: number
)
	suspiciousMovementUntil[player] = now + SUSPICIOUS_MOVEMENT_SECONDS
	local lastLogAt = lastSuspiciousLogAt[player] or 0
	if now - lastLogAt >= SUSPICIOUS_LOG_COOLDOWN then
		lastSuspiciousLogAt[player] = now
		DebugModule.validationWarn(
			string.format(
				"Suspicious teleport movement | player=%s | distance=%.1f | elapsed=%.2f | allowed=%.1f | evidence=%.2f | pingMs=%.0f",
				player.Name,
				distance,
				elapsed,
				allowedDistance,
				evidenceScore,
				pingSeconds * 1000
			),
			"ValidationService"
		)
	end
end

local function evaluateCurrentMovement(player: Player, now: number): boolean
	local character = player.Character
	local humanoid = ValidationService.GetAliveHumanoid(character)
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not rootPart or not rootPart:IsA("BasePart") then
		positionSamples[player] = nil
		clearPathSamples(player)
		resetMovementEvidence(player)
		return false
	end

	local graceUntil = serverTeleportGraceUntil[player]
	if graceUntil then
		if now < graceUntil then
			resetMovementEvidence(player)
			clearPathSamples(player)
			updatePositionSample(player, character, rootPart, now)
			return false
		end
		serverTeleportGraceUntil[player] = nil
	end

	local sample = positionSamples[player]
	if
		not sample
		or sample.character ~= character
		or sample.worldName ~= getWorldName(player)
		or now <= sample.observedAt
	then
		resetMovementEvidence(player)
		clearPathSamples(player)
		updatePositionSample(player, character, rootPart, now)
		return false
	end

	local elapsed = now - sample.observedAt
	if elapsed > MAX_SAMPLE_ELAPSED then
		-- A delayed server frame is not enough evidence for a teleport.
		resetMovementEvidence(player)
		clearPathSamples(player)
		updatePositionSample(player, character, rootPart, now)
		return false
	end

	local expectedSpeed = math.clamp(PlayerHandler.GetEffectiveWalkSpeed(player), 0, 100000)
	local allowedDistance, pingSeconds = getAllowedMovementDistance(player, expectedSpeed, elapsed)
	local distance = (rootPart.Position - sample.position).Magnitude
	local suspicious = distance >= MIN_SUSPICIOUS_DISTANCE and distance > allowedDistance
	updatePositionSample(player, character, rootPart, now)

	if not suspicious then
		addMovementEvidence(player, 0, now)
		return false
	end

	local movementRatio = distance / math.max(allowedDistance, 1)
	local contribution = math.clamp((movementRatio - 1) * 0.75, 0.25, 1.5)
	if elapsed < MIN_RELIABLE_SAMPLE_ELAPSED then
		contribution *= 0.5
	end
	if pingSeconds >= 0.25 then
		contribution *= 0.75
	end

	local evidenceScore = addMovementEvidence(player, contribution, now)
	local hardMovementDistance = math.max(HARD_MOVEMENT_DISTANCE, allowedDistance * HARD_MOVEMENT_RATIO)
	local hardMovement = distance >= hardMovementDistance
	if hardMovement or evidenceScore >= MOVEMENT_EVIDENCE_BLOCK_THRESHOLD then
		flagSuspiciousMovement(player, distance, elapsed, allowedDistance, now, evidenceScore, pingSeconds)
		return true
	end

	return false
end

function ValidationService.GetAliveHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return humanoid
end

function ValidationService.IsCharacterAlive(character: Model?): boolean
	return ValidationService.GetAliveHumanoid(character) ~= nil
end

function ValidationService.IsPlayerAlive(player: Player?): boolean
	if not player then
		return false
	end

	return ValidationService.IsCharacterAlive(player.Character)
end

function ValidationService.GetAlivePlayerFromTouch(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player or not ValidationService.IsPlayerAlive(player) then
		return nil
	end

	return player
end

function ValidationService.IsRootPartWithinPartBounds(rootPart: BasePart?, part: BasePart, padding: Vector3?): boolean
	return rootPart ~= nil and isPointWithinPartBounds(rootPart.Position, part, padding)
end

function ValidationService.IsPlayerWithinPartBounds(player: Player, part: BasePart, padding: Vector3?): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	return ValidationService.IsRootPartWithinPartBounds(rootPart, part, padding)
end

-- Uses the current position plus recent server-observed movement. This avoids
-- relying on .Touched for thin checkpoints when a legitimate player is fast.
function ValidationService.IsPlayerNearPart(player: Player, part: BasePart, padding: Vector3?): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	if isPointWithinPartBounds(rootPart.Position, part, padding) then
		return true
	end

	return didRecentSampleCrossPart(player, character, part, padding)
end

-- Segment-only variant for automatic checkpoint reconciliation. It never treats
-- spawning or an already-positioned player as proof that a checkpoint was crossed.
function ValidationService.DidPlayerRecentlyCrossPart(player: Player, part: BasePart, padding: Vector3?): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	return didRecentSampleCrossPart(player, character, part, padding, MAX_STAGE_PATH_AGE_SECONDS)
end

function ValidationService.GetStageReconcileRevision(player: Player): number
	return stageReconcileRevisionByPlayer[player] or 0
end

-- Mark a server-owned movement so normal redirects do not look like exploits.
function ValidationService.MarkServerTeleport(player: Player, graceSeconds: number?)
	local now = os.clock()
	resetMovementEvidence(player)
	positionSamples[player] = nil
	clearPathSamples(player)
	local graceDuration = SERVER_TELEPORT_GRACE_SECONDS
	if typeof(graceSeconds) == "number" then
		graceDuration = math.clamp(graceSeconds, 0, 5)
	end
	serverTeleportGraceUntil[player] = now + graceDuration

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if character and rootPart and rootPart:IsA("BasePart") then
		updatePositionSample(player, character, rootPart, now)
	else
		positionSamples[player] = nil
		clearPathSamples(player)
	end
end

-- Checks a server-observed journey against the fastest legitimate travel time.
-- The optional speed override preserves a higher speed that was valid at race start.
function ValidationService.ValidateTravelTime(
	player: Player,
	origin: Vector3,
	destination: Vector3,
	startedAt: number,
	actionName: string,
	maximumSpeedOverride: number?
): boolean
	if typeof(startedAt) ~= "number" or startedAt <= 0 then
		return true
	end

	local offset = destination - origin
	local horizontalDistance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	if horizontalDistance < 1 then
		return true
	end

	local currentSpeed = math.clamp(PlayerHandler.GetEffectiveWalkSpeed(player), 1, 100000)
	local maximumSpeed = currentSpeed
	if typeof(maximumSpeedOverride) == "number" and maximumSpeedOverride > 0 then
		maximumSpeed = math.max(maximumSpeed, math.clamp(maximumSpeedOverride, 1, 100000))
	end

	local observedElapsed = math.max(0, Workspace:GetServerTimeNow() - startedAt)
	local minimumTravelTime = horizontalDistance / maximumSpeed
	local pingGrace, pingSeconds = getPingGraceSeconds(player)
	local requiredElapsed = math.max(0, minimumTravelTime - pingGrace)
	if observedElapsed + 0.05 >= requiredElapsed then
		return true
	end

	DebugModule.validationWarn(
		string.format(
			"Travel time validation failed | player=%s | action=%s | distance=%.1f | elapsed=%.2f | required=%.2f | speed=%.1f | pingMs=%.0f",
			player.Name,
			actionName,
			horizontalDistance,
			observedElapsed,
			requiredElapsed,
			maximumSpeed,
			pingSeconds * 1000
		),
		"ValidationService"
	)
	return false
end

-- Called from an existing server heartbeat. The module owns only bounded tables;
-- it does not create its own connection or heartbeat.
function ValidationService.ObservePlayerPositions(now: number?)
	local observedAt = now or os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local nextObservation = nextPositionObservation[player] or 0
		if observedAt >= nextObservation then
			nextPositionObservation[player] = observedAt + POSITION_SAMPLE_INTERVAL
			evaluateCurrentMovement(player, observedAt)
		end
	end
end

-- Reward callers use this immediately before granting value. A recent
-- unexplained jump suppresses only this reward path and never kicks the player.
function ValidationService.ValidateRewardEligibility(player: Player, rewardName: string): boolean
	local now = os.clock()
	evaluateCurrentMovement(player, now)

	local suspiciousUntil = suspiciousMovementUntil[player]
	if not suspiciousUntil or now >= suspiciousUntil then
		if suspiciousUntil then
			suspiciousMovementUntil[player] = nil
		end
		return true
	end

	local lastLogAt = lastRewardBlockLogAt[player] or 0
	if now - lastLogAt >= SUSPICIOUS_LOG_COOLDOWN then
		lastRewardBlockLogAt[player] = now
		DebugModule.validationWarn(
			string.format("Reward blocked after suspicious teleport | player=%s | reward=%s", player.Name, rewardName),
			"ValidationService"
		)
	end
	return false
end

function ValidationService.GetRewardEligibilityRetryAt(player: Player): number?
	return suspiciousMovementUntil[player]
end

-- Stage evidence is server-owned and survives missed .Touched events until the
-- player completes the current run. It is never accepted from the client.
function ValidationService.RecordPassedStage(player: Player, worldName: string, stageValue: number)
	if typeof(worldName) ~= "string" or typeof(stageValue) ~= "number" then
		return
	end

	local playerStages = highestPassedStageByPlayer[player]
	if not playerStages then
		playerStages = {}
		highestPassedStageByPlayer[player] = playerStages
	end

	local normalizedStage = math.max(0, math.floor(stageValue))
	local previousStage = playerStages[worldName] or 0
	if normalizedStage > previousStage then
		playerStages[worldName] = normalizedStage
		bumpStageReconcileRevision(player)
	end
end

function ValidationService.GetHighestPassedStage(player: Player, worldName: string): number
	local playerStages = highestPassedStageByPlayer[player]
	return if playerStages then playerStages[worldName] or 0 else 0
end

function ValidationService.ResetStageProgress(player: Player, worldName: string?)
	bumpStageReconcileRevision(player)
	if worldName then
		local playerStages = highestPassedStageByPlayer[player]
		if playerStages then
			playerStages[worldName] = nil
			if next(playerStages) == nil then
				highestPassedStageByPlayer[player] = nil
			end
		end
	else
		highestPassedStageByPlayer[player] = nil
	end
end

function ValidationService.CleanupPlayer(player: Player)
	positionSamples[player] = nil
	pathSamples[player] = nil
	stageReconcileRevisionByPlayer[player] = nil
	nextPositionObservation[player] = nil
	serverTeleportGraceUntil[player] = nil
	suspiciousMovementUntil[player] = nil
	lastSuspiciousLogAt[player] = nil
	lastRewardBlockLogAt[player] = nil
	movementEvidenceScore[player] = nil
	movementEvidenceObservedAt[player] = nil
	highestPassedStageByPlayer[player] = nil
end

function ValidationService.Cleanup()
	table.clear(positionSamples)
	table.clear(pathSamples)
	table.clear(stageReconcileRevisionByPlayer)
	table.clear(nextPositionObservation)
	table.clear(serverTeleportGraceUntil)
	table.clear(suspiciousMovementUntil)
	table.clear(lastSuspiciousLogAt)
	table.clear(lastRewardBlockLogAt)
	table.clear(movementEvidenceScore)
	table.clear(movementEvidenceObservedAt)
	table.clear(highestPassedStageByPlayer)
end

--[[
    Verifies if a player is authorized to be in a specific world.
    Kicks player if mismatch is detected.
]]
function ValidationService.ValidateWorldAccess(player: Player, expectedWorld: string): boolean
	local currentWorld = player:GetAttribute("Current_World")

	if currentWorld ~= expectedWorld then
		DebugModule.validationWarn(
			string.format(
				"Player %s attempted to interact with %s but is in %s",
				player.Name,
				expectedWorld,
				tostring(currentWorld)
			),
			"ValidationService"
		)
		player:Kick("Invalid world interaction detected")
		return false
	end

	return true
end

--[[
    Centralized check for suspicious movement speed.
]]
function ValidationService.ValidateSpeed(player: Player, reportedSpeed: number): boolean
	local maxAllowed = PlayerHandler.GetEffectiveMaxPlayerSpeed(player)
	local buffer = 5 -- Allow for slight network/physics variation

	if reportedSpeed > (maxAllowed + buffer) then
		DebugModule.validationWarn(
			string.format("Player %s reported speed %d (Max allowed: %d)", player.Name, reportedSpeed, maxAllowed),
			"ValidationService"
		)
		player:Kick("Speed modification detected")
		return false
	end

	return true
end

function ValidationService.ValidateWinButtonStage(player: Player, requiredStage: number): boolean
	local currentStage = player:GetAttribute("CurrentStage")
	if typeof(currentStage) ~= "number" then
		currentStage = 0
	end
	local currentWorld = getWorldName(player)
	local highestPassedStage = if currentWorld then ValidationService.GetHighestPassedStage(player, currentWorld) else 0
	local effectiveStage = math.max(currentStage, highestPassedStage)

	if requiredStage > effectiveStage then
		DebugModule.validationWarn(
			string.format(
				"Player %s tried to skip ahead to WinButton stage %d while on stage %d (highest passed stage %d)",
				player.Name,
				requiredStage,
				currentStage,
				highestPassedStage
			),
			"ValidationService"
		)
		return false
	end

	return true
end

return ValidationService
