--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))

local WinStreakService = {}

local MODULE_NAME = "WinStreakService"
local REQUIRED_STAGE = 20
local BASE_MULTIPLIER = 1
local MULTIPLIER_STEP = 0.2
local STREAK_COUNT_ATTRIBUTE = "WinStreakCount"
local STREAK_MULTIPLIER_ATTRIBUTE = "WinStreakMultiplier"

local initializedPlayers: { [Player]: boolean } = {}
local pendingReturnRestoreCounts: { [Player]: number } = {}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getStreakCount(player: Player): number
	local value = player:GetAttribute(STREAK_COUNT_ATTRIBUTE)
	if not isFiniteNumber(value) then
		return 0
	end

	return math.max(0, math.floor(value))
end

local function setStreakState(player: Player, count: number)
	local normalizedCount = math.max(0, math.floor(count))
	player:SetAttribute(STREAK_COUNT_ATTRIBUTE, normalizedCount)
	player:SetAttribute(
		STREAK_MULTIPLIER_ATTRIBUTE,
		BASE_MULTIPLIER + normalizedCount * MULTIPLIER_STEP
	)
end

function WinStreakService.InitializePlayer(player: Player)
	if player.Parent == nil then
		return
	end

	initializedPlayers[player] = true
	setStreakState(player, getStreakCount(player))
end

function WinStreakService.GetMultiplier(player: Player): number
	local value = player:GetAttribute(STREAK_MULTIPLIER_ATTRIBUTE)
	if not isFiniteNumber(value) then
		return BASE_MULTIPLIER
	end

	return math.max(BASE_MULTIPLIER, value)
end

function WinStreakService.RecordFinish(player: Player, requiredStage: number): boolean
	if not initializedPlayers[player] or player.Parent == nil or requiredStage < REQUIRED_STAGE then
		return false
	end

	local nextCount = getStreakCount(player) + 1
	setStreakState(player, nextCount)
	DebugModule.debugInfo(
		("Win streak increased | player=%s | count=%d | multiplier=%.2fx"):format(
			player.Name,
			nextCount,
			WinStreakService.GetMultiplier(player)
		),
		MODULE_NAME
	)
	return true
end

function WinStreakService.ResetForDeath(player: Player)
	if not initializedPlayers[player] then
		return
	end

	local previousCount = getStreakCount(player)
	pendingReturnRestoreCounts[player] = previousCount
	setStreakState(player, 0)
	if previousCount > 0 then
		DebugModule.debugInfo("Win streak reset after death | player=" .. player.Name, MODULE_NAME)
	end
end

function WinStreakService.RestoreAfterReturn(player: Player)
	if not initializedPlayers[player] or player.Parent == nil then
		pendingReturnRestoreCounts[player] = nil
		return
	end

	local previousCount = pendingReturnRestoreCounts[player]
	pendingReturnRestoreCounts[player] = nil
	if not previousCount or previousCount <= 0 then
		return
	end

	setStreakState(player, previousCount)
	DebugModule.debugInfo(
		("Win streak restored after ReturnToStage | player=%s | count=%d | multiplier=%.2fx"):format(
			player.Name,
			previousCount,
			WinStreakService.GetMultiplier(player)
		),
		MODULE_NAME
	)
end

function WinStreakService.CleanupPlayer(player: Player)
	initializedPlayers[player] = nil
	pendingReturnRestoreCounts[player] = nil
end

return WinStreakService
