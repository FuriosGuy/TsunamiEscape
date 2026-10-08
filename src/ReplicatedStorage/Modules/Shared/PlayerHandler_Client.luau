--!strict

-- Client-safe read-only player helpers. Rewards and attribute mutations stay server-side.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SharedFolder = ReplicatedStorage.Modules:WaitForChild("Shared")
local PlayerDataConfig = require(SharedFolder:WaitForChild("PlayerDataConfig"))

local PlayerHandler: { [string]: any } = {}
PlayerHandler.DEFAULT_ATTRIBUTES = PlayerDataConfig.DEFAULT_ATTRIBUTES
PlayerHandler.FRIEND_INVITE_MULTIPLIER_STEP = PlayerDataConfig.FRIEND_INVITE_MULTIPLIER_STEP
PlayerHandler.TRAIL_ORDER = PlayerDataConfig.TRAIL_ORDER
PlayerHandler.TRAIL_CONFIGS = PlayerDataConfig.TRAIL_CONFIGS
PlayerHandler.MOVEMENT_CONFIG = PlayerDataConfig.MOVEMENT_CONFIG

local DEFAULT_PLAYER_SPEED = PlayerDataConfig.DEFAULT_PLAYER_SPEED
local DEFAULT_MAX_PLAYER_SPEED = PlayerDataConfig.DEFAULT_MAX_PLAYER_SPEED
local PREMIUM_MULTIPLIER = if typeof(PlayerDataConfig.PREMIUM_MULTIPLIER) == "number"
	then math.max(1, PlayerDataConfig.PREMIUM_MULTIPLIER)
	else 1.25

local function getNumericAttribute(player: Player, attributeName: string, fallback: number): number
	local value = player:GetAttribute(attributeName)
	if typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return fallback
end

local function getPremiumMultiplier(player: Player): number
	return if player.MembershipType == Enum.MembershipType.Premium then PREMIUM_MULTIPLIER else 1
end

local function combineWinMultipliers(winMultiplier: number, premiumMultiplier: number): number
	return 1 + math.max(0, winMultiplier - 1) + math.max(0, premiumMultiplier - 1)
end

local function parseOwned(value: any): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	if typeof(value) ~= "string" or value == "" then
		return owned
	end

	for token in string.gmatch(value, "([^,]+)") do
		if token ~= "" then
			owned[token] = true
		end
	end

	return owned
end

function PlayerHandler.GetOwnedKarts(player: Player): { [string]: boolean }
	return parseOwned(player:GetAttribute("OwnedKarts"))
end

function PlayerHandler.GetOwnedTrails(player: Player): { [string]: boolean }
	return parseOwned(player:GetAttribute("OwnedTrails"))
end

function PlayerHandler.OwnsKart(player: Player, kartName: string): boolean
	return PlayerHandler.GetOwnedKarts(player)[kartName] == true
end

function PlayerHandler.OwnsTrail(player: Player, trailName: string): boolean
	return PlayerHandler.GetOwnedTrails(player)[trailName] == true
end

function PlayerHandler.GetTrailConfig(trailName: string): { [string]: any }?
	return PlayerHandler.TRAIL_CONFIGS[trailName]
end

function PlayerHandler.GetEffectiveMaxPlayerSpeed(player: Player): number
	local maxSpeed = math.max(0, getNumericAttribute(player, "Max_Player_Speed", DEFAULT_MAX_PLAYER_SPEED))
	local eventMultiplier = math.max(0, getNumericAttribute(player, "LiveEvent_WalkSpeedMultiplier", 1))
	return maxSpeed * eventMultiplier
end

function PlayerHandler.GetEffectiveWalkSpeed(player: Player): number
	local playerSpeed = math.max(0, getNumericAttribute(player, "Player_Speed", DEFAULT_PLAYER_SPEED))
	local maxSpeed = math.max(0, getNumericAttribute(player, "Max_Player_Speed", DEFAULT_MAX_PLAYER_SPEED))
	local eventMultiplier = math.max(0, getNumericAttribute(player, "LiveEvent_WalkSpeedMultiplier", 1))
	return math.min(playerSpeed, maxSpeed) * eventMultiplier
end

function PlayerHandler.GetMovementInterval(player: Player?): number
	local minInterval = 0.2
	local maxInterval = 5
	if player then
		local value = player:GetAttribute("Movement_XPGainInterval")
		if typeof(value) == "number" then
			return math.clamp(value, minInterval, maxInterval)
		end
	end

	return math.clamp(PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_INTERVAL, minInterval, maxInterval)
end

local function getStandardXPSpeedMultiplier(player: Player): number
	return getNumericAttribute(player, "Rebirth_XPMultiplier", 1)
		* getNumericAttribute(player, "DevProduct_XPSpeedMultiplier", 1)
		* getNumericAttribute(player, "Misc_XPSpeedMultiplier", 1)
		* getNumericAttribute(player, "Friend_XPMultiplier", 1)
		* getNumericAttribute(player, "Treadmill_XPMultiplier", 1)
end

function PlayerHandler.CalculateRewardXPSpeed(player: Player, amount: number): number
	return amount * getStandardXPSpeedMultiplier(player)
end

function PlayerHandler.CalculateDailyWinsAward(player: Player, amount: number): number
	local rebirthMultiplier = getNumericAttribute(player, "Rebirth_XPMultiplier", 1)
	local winMultiplier = getNumericAttribute(player, "WinMultiplier", 1)
	local combinedMultiplier = rebirthMultiplier * winMultiplier
	local dailyMultiplier = 1 + math.max(0, combinedMultiplier - 1) * 0.5
	return math.max(0, math.round(amount * dailyMultiplier))
end

function PlayerHandler.CalculatePlaytimeWinsAward(player: Player, amount: number): number
	local rebirthMultiplier = getNumericAttribute(player, "Rebirth_XPMultiplier", 1)
	local winMultiplier = getNumericAttribute(player, "WinMultiplier", 1)
	local miscMultiplier = getNumericAttribute(player, "Misc_XPSpeedMultiplier", 1)
	local devMultiplier = getNumericAttribute(player, "DevProduct_XPSpeedMultiplier", 1)
	local reducedDevMultiplier = 1 + math.max(0, devMultiplier - 1) * 0.1
	local combinedWinMultiplier = combineWinMultipliers(winMultiplier, getPremiumMultiplier(player))
	return math.max(
		0,
		math.round(amount * rebirthMultiplier * combinedWinMultiplier * miscMultiplier * reducedDevMultiplier)
	)
end

function PlayerHandler.GetNextRebirthStats(player: Player): { NextMaxLevel: number, NextMultiplier: number }
	local maxLevel = getNumericAttribute(player, "MaxLevel", 25)
	local multiplier = getNumericAttribute(player, "Rebirth_XPMultiplier", 1)
	local rebirthConfig = PlayerHandler.MOVEMENT_CONFIG.REBIRTH_CONFIG

	return {
		NextMaxLevel = maxLevel + rebirthConfig.MAX_LEVEL_INCREMENT,
		NextMultiplier = multiplier + rebirthConfig.MULTIPLIER_INCREMENT,
	}
end

function PlayerHandler.UpdateVIPRoomCollision(player: Player?)
	if not player then
		return
	end

	local worldsFolder = Workspace:FindFirstChild("Worlds")
	local world1 = worldsFolder and worldsFolder:FindFirstChild("World1")
	local vipRooms = world1 and world1:FindFirstChild("VIPRooms")
	if not vipRooms then
		return
	end

	local hasVIPPass = player:GetAttribute("HasVIPPass") == true
	for _, descendant in ipairs(vipRooms:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "VIPDoor" then
			descendant.CanCollide = not hasVIPPass
		end
	end
end

return PlayerHandler
