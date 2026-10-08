--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("DebugModule"))
local PlayerHandler = require(ReplicatedStorage.Modules.PlayerHandler)

local ValidationService = {}

type PositionSample = {
	character: Model,
	position: Vector3,
	observedAt: number,
	worldName: string?,
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

local positionSamples: { [Player]: PositionSample } = {}
local nextPositionObservation: { [Player]: number } = {}
local serverTeleportGraceUntil: { [Player]: number } = {}
local suspiciousMovementUntil: { [Player]: number } = {}
local lastSuspiciousLogAt: { [Player]: number } = {}
local lastRewardBlockLogAt: { [Player]: number } = {}

local function getWorldName(player: Player): string?
	local worldName = player:GetAttribute("Current_World")
	return if typeof(worldName) == "string" then worldName else nil
end

local function updatePositionSample(player: Player, character: Model, rootPart: BasePart, now: number)
	positionSamples[player] = {
		character = character,
		position = rootPart.Position,
		observedAt = now,
		worldName = getWorldName(player),
	}
end

local function flagSuspiciousMovement(
	player: Player,
	distance: number,
	elapsed: number,
	allowedDistance: number,
	now: number
)
	suspiciousMovementUntil[player] = now + SUSPICIOUS_MOVEMENT_SECONDS
	local lastLogAt = lastSuspiciousLogAt[player] or 0
	if now - lastLogAt >= SUSPICIOUS_LOG_COOLDOWN then
		lastSuspiciousLogAt[player] = now
		DebugModule.validationWarn(
			string.format(
				"Suspicious teleport movement | player=%s | distance=%.1f | elapsed=%.2f | allowed=%.1f",
				player.Name,
				distance,
				elapsed,
				allowedDistance
			),
			"ValidationService_Server"
		)
	end
end

local function evaluateCurrentMovement(player: Player, now: number): boolean
	local character = player.Character
	local humanoid = ValidationService.GetAliveHumanoid(character)
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not rootPart or not rootPart:IsA("BasePart") then
		positionSamples[player] = nil
		return false
	end

	local graceUntil = serverTeleportGraceUntil[player]
	if graceUntil then
		if now < graceUntil then
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
		updatePositionSample(player, character, rootPart, now)
		return false
	end

	local elapsed = now - sample.observedAt
	if elapsed > MAX_SAMPLE_ELAPSED then
		-- A delayed server frame is not enough evidence for a teleport.
		updatePositionSample(player, character, rootPart, now)
		return false
	end

	local expectedSpeed = math.clamp(PlayerHandler.GetEffectiveWalkSpeed(player), 0, 100000)
	local distanceTolerance = math.max(MIN_DISTANCE_TOLERANCE, expectedSpeed * SPEED_TOLERANCE_RATIO)
	local allowedDistance = expectedSpeed * elapsed + distanceTolerance
	local distance = (rootPart.Position - sample.position).Magnitude
	local suspicious = distance >= MIN_SUSPICIOUS_DISTANCE and distance > allowedDistance
	updatePositionSample(player, character, rootPart, now)

	if suspicious then
		flagSuspiciousMovement(player, distance, elapsed, allowedDistance, now)
	end

	return suspicious
end

local function resetPlayerToWorldSpawn(player: Player)
	local currentWorld = player:GetAttribute("Current_World")
	if typeof(currentWorld) ~= "string" or currentWorld == "" then
		currentWorld = "World1"
	end

	player:SetAttribute("CurrentStage", 0)

	local character = player.Character
	if not character then
		return
	end

	local worldsFolder = Workspace:FindFirstChild("Worlds")
	local worldFolder = worldsFolder and worldsFolder:FindFirstChild(currentWorld)
	local spawnLocation = worldFolder and worldFolder:FindFirstChild("SpawnLocation")
	if spawnLocation and spawnLocation:IsA("BasePart") then
		character:PivotTo(spawnLocation:GetPivot() * CFrame.new(0, 3, 0))
		ValidationService.MarkServerTeleport(player)
	end
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

-- Mark a server-owned movement so normal redirects do not look like exploits.
function ValidationService.MarkServerTeleport(player: Player)
	local now = os.clock()
	serverTeleportGraceUntil[player] = now + SERVER_TELEPORT_GRACE_SECONDS

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if character and rootPart and rootPart:IsA("BasePart") then
		updatePositionSample(player, character, rootPart, now)
	else
		positionSamples[player] = nil
	end
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
			string.format(
				"Reward blocked after suspicious teleport | player=%s | reward=%s",
				player.Name,
				rewardName
			),
			"ValidationService"
		)
	end
	return false
end

function ValidationService.CleanupPlayer(player: Player)
	positionSamples[player] = nil
	nextPositionObservation[player] = nil
	serverTeleportGraceUntil[player] = nil
	suspiciousMovementUntil[player] = nil
	lastSuspiciousLogAt[player] = nil
	lastRewardBlockLogAt[player] = nil
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

	if requiredStage > currentStage then
		DebugModule.validationWarn(
			string.format(
				"Player %s tried to skip ahead to WinButton stage %d while on stage %d",
				player.Name,
				requiredStage,
				currentStage
			),
			"ValidationService"
		)
		resetPlayerToWorldSpawn(player)
		return false
	end

	return true
end

return ValidationService
