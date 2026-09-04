local PlayerHandler = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local ConfigFolder = ReplicatedStorage.Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local DefaultAttributes = {
	Rebirths = 0,
	Rebirth_XPMultiplier = 1,
	DevProduct_XPSpeedMultiplier = 1,
	Misc_XPSpeedMultiplier = 1,
	Friend_XPMultiplier = 1,
	FriendInviteCount = 0,

	Player_Speed = 16,
	Max_Player_Speed = 16, -- Base and Max start at 16
	Trail_Equipped = "None",
	OwnedTrails = "",
	OwnedKarts = "1_Default",
	Kart_Equipped = "1_Default",
	Current_World = "World1",
	CurrentStage = 0,
	MinigameRaceWins = 0,

	WinCount = 0,
	WinMultiplier = 1,
	HasVIPPass = false,
	VerifyRewardClaimed = false,
	VerifyRewardNextClaimUnix = 0,
	VerifyRewardClaimCount = 0,
	StarterPackRewardClaimed = false,
	TutorialSeen = false,
	TutorialCompleted = false,
	Data_Loaded = false,
	PlaytimeRewardElapsed = 0,
	TotalPlaytimeSeconds = 0,
	PlaytimeRewardsClaimed = "",
	DailyRewardCurrentDay = 1,
	DailyRewardNextClaimUnix = 0,
	DailyRewardCycleCount = 0,
	SpinWheelSpins = 0,
	SpinWheelNextFreeSpinUnix = 0,
	SpinWheelFreeSpinInitialized = false,
	SpinWheelProcessedReceiptIds = "",

	CurrentLevel = 1,
	MaxLevel = 25,

	AllXPSpeed = 0,
	CurrentXPSpeed = 0,
	MaxXPSpeed = 25,

	Treadmill_XPMultiplier = 1,
	Treadmill_Active = false,
	Movement_XPGainRate = 10,
	Movement_XPGainInterval = 0.25,
}

PlayerHandler.DEFAULT_ATTRIBUTES = DefaultAttributes
local socialConfig = CoreConfig.social
local FRIEND_INVITE_MULTIPLIER_STEP = if socialConfig
		and typeof(socialConfig.friendInviteMultiplierStep) == "number"
	then math.max(0, socialConfig.friendInviteMultiplierStep)
	else 0.1
PlayerHandler.FRIEND_INVITE_MULTIPLIER_STEP = FRIEND_INVITE_MULTIPLIER_STEP
local DEFAULT_PLAYER_SPEED = if typeof(DefaultAttributes.Player_Speed) == "number"
	then DefaultAttributes.Player_Speed
	else 16
local DEFAULT_MAX_PLAYER_SPEED = if typeof(DefaultAttributes.Max_Player_Speed) == "number"
	then DefaultAttributes.Max_Player_Speed
	else 16

PlayerHandler.TRAIL_ORDER = {
	"GalaxyTrail",
	"DemonTrail",
	"FlameTrail",
	"GreenTrail",
	"BlueTrail",
	"PurpleTrail",
	"GoldTrail",
}

PlayerHandler.TRAIL_CONFIGS = {
	GalaxyTrail = {
		DisplayName = "Galaxy Trail",
		XPMultiplier = 15,
		CanBuyWithWins = false,
		WinsRequired = 0,
		BackgroundColor = Color3.fromRGB(84, 0, 255),
		GradientBottomColor = Color3.fromRGB(100, 100, 100),
		ProductKey = "GalaxyTrail",
	},
	DemonTrail = {
		DisplayName = "Demon Trail",
		XPMultiplier = 7.5,
		CanBuyWithWins = false,
		WinsRequired = 0,
		BackgroundColor = Color3.fromRGB(255, 79, 79),
		GradientBottomColor = Color3.fromRGB(206, 0, 3),
		ProductKey = "DemonTrail",
	},
	GreenTrail = {
		DisplayName = "Green Trail",
		XPMultiplier = 1.5,
		CanBuyWithWins = true,
		WinsRequired = 250,
		BackgroundColor = Color3.fromRGB(0, 255, 0),
		GradientBottomColor = Color3.fromRGB(0, 130, 15),
		ProductKey = "GreenTrail",
	},
	BlueTrail = {
		DisplayName = "Blue Trail",
		XPMultiplier = 2,
		CanBuyWithWins = true,
		WinsRequired = 750,
		BackgroundColor = Color3.fromRGB(88, 216, 255),
		GradientBottomColor = Color3.fromRGB(0, 81, 255),
		ProductKey = "BlueTrail",
	},
	PurpleTrail = {
		DisplayName = "Purple Trail",
		XPMultiplier = 3,
		CanBuyWithWins = true,
		WinsRequired = 2500,
		BackgroundColor = Color3.fromRGB(228, 75, 255),
		GradientBottomColor = Color3.fromRGB(74, 3, 255),
		ProductKey = "PurpleTrail",
	},
	GoldTrail = {
		DisplayName = "Gold Trail",
		XPMultiplier = 4.5,
		CanBuyWithWins = true,
		WinsRequired = 7500,
		BackgroundColor = Color3.fromRGB(255, 255, 0),
		GradientBottomColor = Color3.fromRGB(255, 183, 0),
		ProductKey = "GoldTrail",
	},
	FlameTrail = {
		DisplayName = "Flame Trail",
		XPMultiplier = 6,
		CanBuyWithWins = false,
		WinsRequired = 0,
		BackgroundColor = Color3.fromRGB(254, 199, 41),
		GradientBottomColor = Color3.fromRGB(255, 85, 0),
		RewardSource = "SpinWheel",
	},
}

-- Centralized Movement and XP Configuration
PlayerHandler.MOVEMENT_CONFIG = {
	XP_GAIN_RATE = 100, -- Amount awarded each movement interval
	XP_GAIN_INTERVAL = 0.5, -- Seconds between movement awards
	XP_GAIN_TOLERANCE = 0.05, -- Seconds of slack for network jitter (must be < interval)
	PLAYER_SPEED_PER_LEVEL = 4,
	LEVEL_MULTIPLIERS = {
		{ MaxLevel = 200, Multiplier = 1.125 },
		{ MaxLevel = 400, Multiplier = 1.15 },
	},
	REBIRTH_CONFIG = {
		MAX_LEVEL_INCREMENT = 25,
		MULTIPLIER_INCREMENT = 0.5,
	},
}

local function applyDefaultMovementAttributes(player: Player)
	if player:GetAttribute("Movement_XPGainRate") == nil then
		player:SetAttribute("Movement_XPGainRate", PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_RATE)
	end

	if player:GetAttribute("Movement_XPGainInterval") == nil then
		player:SetAttribute("Movement_XPGainInterval", PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_INTERVAL)
	end
end

--[[
	Initializes a player with default attributes.
]]
function PlayerHandler.InitializePlayer(player: Player)
	for name, value in pairs(DefaultAttributes) do
		if player:GetAttribute(name) == nil then
			player:SetAttribute(name, value)
		end
	end

	applyDefaultMovementAttributes(player)
end

--[[
	Sets a specific attribute for a player.
]]
function PlayerHandler.SetAttribute(player: Player, name: string, value: any)
	if player:GetAttribute(name) == value then
		return
	end

	player:SetAttribute(name, value)
end

local function parseOwnedKarts(value: any): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	if typeof(value) ~= "string" or value == "" then
		return owned
	end

	for token in string.gmatch(value, "([^,]+)") do
		owned[token] = true
	end

	return owned
end

local function parseOwnedTrails(value: any): { [string]: boolean }
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
	return parseOwnedKarts(player:GetAttribute("OwnedKarts"))
end

function PlayerHandler.GetTrailConfig(trailName: string): { [string]: any }?
	return PlayerHandler.TRAIL_CONFIGS[trailName]
end

function PlayerHandler.GetOwnedTrails(player: Player): { [string]: boolean }
	return parseOwnedTrails(player:GetAttribute("OwnedTrails"))
end

function PlayerHandler.OwnsTrail(player: Player, trailName: string): boolean
	return PlayerHandler.GetOwnedTrails(player)[trailName] == true
end

function PlayerHandler.AddOwnedTrail(player: Player, trailName: string)
	local owned = PlayerHandler.GetOwnedTrails(player)
	if owned[trailName] == true then
		return
	end

	owned[trailName] = true

	local orderedNames = {}
	for _, configTrailName in ipairs(PlayerHandler.TRAIL_ORDER) do
		if owned[configTrailName] then
			table.insert(orderedNames, configTrailName)
		end
	end

	player:SetAttribute("OwnedTrails", table.concat(orderedNames, ","))
end

function PlayerHandler.ApplyTrailMultiplier(player: Player)
	local equippedTrail = player:GetAttribute("Trail_Equipped")
	if typeof(equippedTrail) ~= "string" or equippedTrail == "" or equippedTrail == "None" then
		player:SetAttribute("Misc_XPSpeedMultiplier", 1)
		return
	end

	local config = PlayerHandler.GetTrailConfig(equippedTrail)
	if not config then
		player:SetAttribute("Misc_XPSpeedMultiplier", 1)
		return
	end

	player:SetAttribute("Misc_XPSpeedMultiplier", config.XPMultiplier)
end

function PlayerHandler.GetFriendMultiplierFromCount(friendInviteCount: number): number
	return 1 + (math.max(0, math.floor(friendInviteCount)) * FRIEND_INVITE_MULTIPLIER_STEP)
end

function PlayerHandler.ApplyFriendInviteMultiplier(player: Player)
	local friendInviteCount = player:GetAttribute("FriendInviteCount")
	if typeof(friendInviteCount) ~= "number" then
		friendInviteCount = 0
	end

	player:SetAttribute("Friend_XPMultiplier", PlayerHandler.GetFriendMultiplierFromCount(friendInviteCount))
end

function PlayerHandler.AddFriendInviteCount(player: Player, amount: number?): number
	local increment = if typeof(amount) == "number" then math.max(1, math.floor(amount)) else 1
	local currentCount = player:GetAttribute("FriendInviteCount")
	if typeof(currentCount) ~= "number" then
		currentCount = 0
	end

	local nextCount = currentCount + increment
	PlayerHandler.SetAttribute(player, "FriendInviteCount", nextCount)
	PlayerHandler.ApplyFriendInviteMultiplier(player)
	return nextCount
end

function PlayerHandler.OwnsKart(player: Player, kartName: string): boolean
	return PlayerHandler.GetOwnedKarts(player)[kartName] == true
end

function PlayerHandler.AddOwnedKart(player: Player, kartName: string)
	local owned = PlayerHandler.GetOwnedKarts(player)
	if owned[kartName] == true then
		return
	end

	owned[kartName] = true

	local names = {}
	for name in pairs(owned) do
		table.insert(names, name)
	end

	table.sort(names)
	player:SetAttribute("OwnedKarts", table.concat(names, ","))
end

function PlayerHandler.SpendWins(player: Player, amount: number): boolean
	local currentWins = player:GetAttribute("WinCount") or 0
	if currentWins < amount then
		return false
	end

	player:SetAttribute("WinCount", currentWins - amount)
	return true
end

type LevelProgressResult = {
	currentLevel: number,
	currentXP: number,
	maxXP: number,
	maxPlayerSpeed: number,
	playerSpeed: number,
	levelsGained: number,
}

local function getLevelMultiplierForLevel(currentLevel: number): number
	local multiplier = 1.25

	for _, range in ipairs(PlayerHandler.MOVEMENT_CONFIG.LEVEL_MULTIPLIERS) do
		multiplier = range.Multiplier
		if currentLevel <= range.MaxLevel then
			break
		end
	end

	return multiplier
end

local function resolveLevelProgress(
	currentLevel: number,
	maxLevel: number,
	currentXP: number,
	maxXP: number,
	maxPlayerSpeed: number,
	playerSpeed: number
): LevelProgressResult
	local levelsGained = 0
	local startedAtSpeedCap = playerSpeed >= maxPlayerSpeed

	while currentXP >= maxXP and currentLevel < maxLevel do
		currentXP -= maxXP
		maxXP = math.round(maxXP * getLevelMultiplierForLevel(currentLevel))
		currentLevel += 1
		maxPlayerSpeed += PlayerHandler.MOVEMENT_CONFIG.PLAYER_SPEED_PER_LEVEL
		levelsGained += 1
	end

	if startedAtSpeedCap and levelsGained > 0 then
		playerSpeed = maxPlayerSpeed
	end

	return {
		currentLevel = currentLevel,
		currentXP = currentXP,
		maxXP = maxXP,
		maxPlayerSpeed = maxPlayerSpeed,
		playerSpeed = playerSpeed,
		levelsGained = levelsGained,
	}
end

local function applyAwardedXPSpeed(player: Player, finalAmount: number): number
	local currentLevel = player:GetAttribute("CurrentLevel") or 1
	local maxLevel = player:GetAttribute("MaxLevel") or 25
	local currentXP = player:GetAttribute("CurrentXPSpeed") or 0
	local maxXP = player:GetAttribute("MaxXPSpeed") or 25
	local maxPlayerSpeed = player:GetAttribute("Max_Player_Speed") or DEFAULT_MAX_PLAYER_SPEED
	local playerSpeed = player:GetAttribute("Player_Speed") or DEFAULT_PLAYER_SPEED
	local allXP = player:GetAttribute("AllXPSpeed") or 0

	local progress =
		resolveLevelProgress(currentLevel, maxLevel, currentXP + finalAmount, maxXP, maxPlayerSpeed, playerSpeed)

	PlayerHandler.SetAttribute(player, "CurrentLevel", progress.currentLevel)
	PlayerHandler.SetAttribute(player, "Max_Player_Speed", progress.maxPlayerSpeed)
	PlayerHandler.SetAttribute(player, "Player_Speed", progress.playerSpeed)
	PlayerHandler.SetAttribute(player, "CurrentXPSpeed", progress.currentXP)
	PlayerHandler.SetAttribute(player, "MaxXPSpeed", progress.maxXP)
	PlayerHandler.SetAttribute(player, "AllXPSpeed", allXP + finalAmount)

	if progress.levelsGained > 0 then
		DebugModule.debugPrint(
			string.format(
				"Player %s gained %d levels! New level=%d MaxXPSpeed=%d",
				player.Name,
				progress.levelsGained,
				progress.currentLevel,
				progress.maxXP
			),
			"PlayerHandler"
		)
	end

	return finalAmount
end

local function getNumericAttribute(player: Player, attributeName: string, fallback: number): number
	local value = player:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	return fallback
end

local function getStandardXPSpeedMultiplier(player: Player): number
	local rebirthMult = getNumericAttribute(player, "Rebirth_XPMultiplier", 1)
	local devMult = getNumericAttribute(player, "DevProduct_XPSpeedMultiplier", 1)
	local miscMult = getNumericAttribute(player, "Misc_XPSpeedMultiplier", 1)
	local friendMult = getNumericAttribute(player, "Friend_XPMultiplier", 1)
	local treadmillMult = getNumericAttribute(player, "Treadmill_XPMultiplier", 1)

	return rebirthMult * devMult * miscMult * friendMult * treadmillMult
end

function PlayerHandler.GetXPSpeedMultiplier(player: Player): number
	return getStandardXPSpeedMultiplier(player) * PlayerHandler.GetLiveEventXPMultiplier(player)
end

function PlayerHandler.CalculateAwardedXPSpeed(player: Player, amount: number): number
	return amount * PlayerHandler.GetXPSpeedMultiplier(player)
end

function PlayerHandler.CalculateAwardedXPSpeedProduct(player: Player, amount: number): number
	local devMult = getNumericAttribute(player, "DevProduct_XPSpeedMultiplier", 1)
	return amount * devMult
end

function PlayerHandler.GetDailyWinsMultiplier(player: Player): number
	local rebirthMult = getNumericAttribute(player, "Rebirth_XPMultiplier", 1)
	local winMult = getNumericAttribute(player, "WinMultiplier", 1)
	local combinedMultiplier = rebirthMult * winMult

	return 1 + math.max(0, combinedMultiplier - 1) * 0.5
end

function PlayerHandler.CalculateDailyWinsAward(player: Player, amount: number): number
	return math.max(0, math.round(amount * PlayerHandler.GetDailyWinsMultiplier(player)))
end

function PlayerHandler.CalculateAwardedWins(player: Player, amount: number): number
	local winMultiplier = getNumericAttribute(player, "WinMultiplier", 1)
	return math.max(0, math.round(amount * winMultiplier))
end

-- Live-event bonuses intentionally apply only to normal treadmill XP and WinButton awards.
-- Products, daily/playtime rewards, races, and wheel rewards use dedicated award APIs.
function PlayerHandler.GetLiveEventXPMultiplier(player: Player): number
	return getNumericAttribute(player, "LiveEvent_XPMultiplier", 1)
end

function PlayerHandler.GetLiveEventWinButtonMultiplier(player: Player): number
	return getNumericAttribute(player, "LiveEvent_WinButtonMultiplier", 1)
end

function PlayerHandler.GetPlaytimeWinsMultiplier(player: Player): number
	local rebirthMult = getNumericAttribute(player, "Rebirth_XPMultiplier", 1)
	local winMult = getNumericAttribute(player, "WinMultiplier", 1)
	local miscMult = getNumericAttribute(player, "Misc_XPSpeedMultiplier", 1)
	local devMult = getNumericAttribute(player, "DevProduct_XPSpeedMultiplier", 1)
	local reducedDevMult = 1 + math.max(0, devMult - 1) * 0.1

	return rebirthMult * winMult * miscMult * reducedDevMult
end

function PlayerHandler.CalculatePlaytimeWinsAward(player: Player, amount: number): number
	return math.max(0, math.round(amount * PlayerHandler.GetPlaytimeWinsMultiplier(player)))
end

--[[
	Adds XP Speed to a player and handles leveling up.
	Applies all active multipliers multiplicatively
	(Rebirth × DevProduct × Misc × Friend × Treadmill).
]]
function PlayerHandler.AddXPSpeed(player: Player, amount: number)
	local finalAmount = PlayerHandler.CalculateAwardedXPSpeed(player, amount)

	return applyAwardedXPSpeed(player, finalAmount)
end

function PlayerHandler.AddRewardXPSpeed(player: Player, amount: number): number
	return applyAwardedXPSpeed(player, amount * getStandardXPSpeedMultiplier(player))
end

--[[
	Adds a flat XP Speed purchase amount, only scaled by the DevProduct multiplier.
	Used for +100K, +1M, +10M dev products so Rebirth/Misc boosts don't
	double-dip on direct purchases (what you see in the shop is what you get).
]]
function PlayerHandler.AddXPSpeedProduct(player: Player, amount: number)
	local finalAmount = PlayerHandler.CalculateAwardedXPSpeedProduct(player, amount)

	return applyAwardedXPSpeed(player, finalAmount)
end

function PlayerHandler.AddExactXPSpeed(player: Player, amount: number): number
	return applyAwardedXPSpeed(player, amount)
end

function PlayerHandler.AddExactWins(player: Player, amount: number): number
	local currentWins = player:GetAttribute("WinCount") or 0
	local finalAmount = math.max(0, math.round(amount))

	PlayerHandler.SetAttribute(player, "WinCount", currentWins + finalAmount)
	return finalAmount
end

function PlayerHandler.AddLevels(player: Player, amount: number): number
	local levelsToGrant = math.max(0, math.floor(amount))
	if levelsToGrant <= 0 then
		return 0
	end

	local currentLevel = player:GetAttribute("CurrentLevel") or 1
	local maxLevel = player:GetAttribute("MaxLevel") or 25
	local currentXP = player:GetAttribute("CurrentXPSpeed") or 0
	local maxXP = player:GetAttribute("MaxXPSpeed") or 25

	local remainingLevels = math.max(0, maxLevel - currentLevel)
	if remainingLevels <= 0 then
		return 0
	end

	local targetLevels = math.min(levelsToGrant, remainingLevels)
	local totalXPNeeded = 0

	for _ = 1, targetLevels do
		local neededForNextLevel = math.max(0, maxXP - currentXP)
		totalXPNeeded += neededForNextLevel
		currentXP = 0
		maxXP = math.round(maxXP * getLevelMultiplierForLevel(currentLevel))
		currentLevel += 1
	end

	if totalXPNeeded <= 0 then
		return 0
	end

	applyAwardedXPSpeed(player, totalXPNeeded)
	return targetLevels
end

function PlayerHandler.GetMovementGain(player: Player?): number
	if player then
		local attributeValue = player:GetAttribute("Movement_XPGainRate")
		if typeof(attributeValue) == "number" then
			return attributeValue
		end
	end

	return PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_RATE
end

function PlayerHandler.GetMovementInterval(player: Player?): number
	local minInterval = 0.2
	local maxInterval = 5

	if player then
		local attributeValue = player:GetAttribute("Movement_XPGainInterval")
		if typeof(attributeValue) == "number" then
			return math.clamp(attributeValue, minInterval, maxInterval)
		end
	end

	return math.clamp(PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_INTERVAL, minInterval, maxInterval)
end

function PlayerHandler.GetMovementTolerance()
	return PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_TOLERANCE
end

function PlayerHandler.HasVIPPass(player: Player?): boolean
	if not player then
		return false
	end

	return player:GetAttribute("HasVIPPass") == true
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

	local hasVIPPass = PlayerHandler.HasVIPPass(player)

	for _, descendant in ipairs(vipRooms:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "VIPDoor" then
			descendant.CanCollide = not hasVIPPass
		end
	end
end

function PlayerHandler.GetNextRebirthStats(player: Player)
	local maxLevel = player:GetAttribute("MaxLevel") or 25
	local multiplier = player:GetAttribute("Rebirth_XPMultiplier") or 1

	return {
		NextMaxLevel = maxLevel + PlayerHandler.MOVEMENT_CONFIG.REBIRTH_CONFIG.MAX_LEVEL_INCREMENT,
		NextMultiplier = multiplier + PlayerHandler.MOVEMENT_CONFIG.REBIRTH_CONFIG.MULTIPLIER_INCREMENT,
	}
end

--[[
	Performs a rebirth operation.
]]
function PlayerHandler.PerformRebirth(player: Player, skipLevelReset: boolean)
	local isSkipping = skipLevelReset or false
	local currentLevel = player:GetAttribute("CurrentLevel") or 1
	local currentMaxLevel = player:GetAttribute("MaxLevel") or 25

	if not isSkipping and currentLevel < currentMaxLevel then
		return false
	end

	local rebirths = player:GetAttribute("Rebirths") or 0
	local nextStats = PlayerHandler.GetNextRebirthStats(player)

	PlayerHandler.SetAttribute(player, "Rebirths", rebirths + 1)
	PlayerHandler.SetAttribute(player, "Rebirth_XPMultiplier", nextStats.NextMultiplier)
	PlayerHandler.SetAttribute(player, "MaxLevel", nextStats.NextMaxLevel)

	if not isSkipping then
		PlayerHandler.SetAttribute(player, "CurrentLevel", 1)
		PlayerHandler.SetAttribute(player, "CurrentXPSpeed", 0)
		PlayerHandler.SetAttribute(player, "MaxXPSpeed", 25)
		PlayerHandler.SetAttribute(player, "Player_Speed", DEFAULT_PLAYER_SPEED)
		PlayerHandler.SetAttribute(player, "Max_Player_Speed", DEFAULT_MAX_PLAYER_SPEED) -- Reset both to base at lvl 1
	end

	return true
end

--[[
	Adds Wins to a player.
]]
function PlayerHandler.AddWins(player: Player, amount: number): number
	local currentWins = player:GetAttribute("WinCount") or 0
	local finalAmount = PlayerHandler.CalculateAwardedWins(player, amount)

	PlayerHandler.SetAttribute(player, "WinCount", currentWins + finalAmount)
	return finalAmount
end

function PlayerHandler.AddWinButtonWins(player: Player, amount: number): number
	local currentWins = player:GetAttribute("WinCount") or 0
	local gamePassAward = PlayerHandler.CalculateAwardedWins(player, amount)
	local finalAmount = math.max(
		0,
		math.round(gamePassAward * PlayerHandler.GetLiveEventWinButtonMultiplier(player))
	)

	PlayerHandler.SetAttribute(player, "WinCount", currentWins + finalAmount)
	return finalAmount
end

function PlayerHandler.AddPlaytimeWins(player: Player, amount: number): number
	local currentWins = player:GetAttribute("WinCount") or 0
	local finalAmount = PlayerHandler.CalculatePlaytimeWinsAward(player, amount)

	PlayerHandler.SetAttribute(player, "WinCount", currentWins + finalAmount)
	return finalAmount
end

return PlayerHandler
