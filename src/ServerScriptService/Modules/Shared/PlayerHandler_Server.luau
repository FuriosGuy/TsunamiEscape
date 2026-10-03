local PlayerHandler = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local PetInventoryService = require(ServerScriptService.Modules:WaitForChild("PetInventoryService"))
local SharedFolder = ReplicatedStorage.Modules:WaitForChild("Shared")
local ServerSharedFolder = game:GetService("ServerScriptService").Modules:WaitForChild("Shared")
local CoreConfig = require(ServerSharedFolder:WaitForChild("CoreConfig_Server"))
local PlayerDataConfig = require(SharedFolder:WaitForChild("PlayerDataConfig"))

PlayerHandler.DEFAULT_ATTRIBUTES = PlayerDataConfig.DEFAULT_ATTRIBUTES
PlayerHandler.FRIEND_INVITE_MULTIPLIER_STEP = PlayerDataConfig.FRIEND_INVITE_MULTIPLIER_STEP
PlayerHandler.TRAIL_ORDER = PlayerDataConfig.TRAIL_ORDER
PlayerHandler.TRAIL_CONFIGS = PlayerDataConfig.TRAIL_CONFIGS
PlayerHandler.MOVEMENT_CONFIG = PlayerDataConfig.MOVEMENT_CONFIG

local DefaultAttributes = PlayerHandler.DEFAULT_ATTRIBUTES
local FRIEND_INVITE_MULTIPLIER_STEP = PlayerHandler.FRIEND_INVITE_MULTIPLIER_STEP
local DEFAULT_PLAYER_SPEED = PlayerDataConfig.DEFAULT_PLAYER_SPEED
local DEFAULT_MAX_PLAYER_SPEED = PlayerDataConfig.DEFAULT_MAX_PLAYER_SPEED
local PREMIUM_MULTIPLIER = if typeof(PlayerDataConfig.PREMIUM_MULTIPLIER) == "number"
	then math.max(1, PlayerDataConfig.PREMIUM_MULTIPLIER)
	else 1.25

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
local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function getFiniteNumberAttribute(player: Player, name: string, fallback: number): number?
	local value = player:GetAttribute(name)
	if value == nil then
		return fallback
	end
	if not isFiniteNumber(value) then
		return nil
	end
	return value
end

function PlayerHandler.SetAttribute(player: Player, name: string, value: any)
	if typeof(value) == "number" and not isFiniteNumber(value) then
		DebugModule.debugWarn(
			string.format(
				"Rejected non-finite player attribute | player=%s | attribute=%s | value=%s",
				player.Name,
				name,
				tostring(value)
			),
			"PlayerHandler"
		)
		return
	end

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
	if not isFiniteNumber(finalAmount) or finalAmount < 0 then
		DebugModule.debugWarn(
			string.format("Rejected non-finite XP award | player=%s | amount=%s", player.Name, tostring(finalAmount)),
			"PlayerHandler"
		)
		return 0
	end

	local currentLevel = getFiniteNumberAttribute(player, "CurrentLevel", 1)
	local maxLevel = getFiniteNumberAttribute(player, "MaxLevel", 25)
	local currentXP = getFiniteNumberAttribute(player, "CurrentXPSpeed", 0)
	local maxXP = getFiniteNumberAttribute(player, "MaxXPSpeed", 25)
	local maxPlayerSpeed = getFiniteNumberAttribute(player, "Max_Player_Speed", DEFAULT_MAX_PLAYER_SPEED)
	local playerSpeed = getFiniteNumberAttribute(player, "Player_Speed", DEFAULT_PLAYER_SPEED)
	local allXP = getFiniteNumberAttribute(player, "AllXPSpeed", 0)
	if
		not currentLevel
		or not maxLevel
		or not currentXP
		or not maxXP
		or not maxPlayerSpeed
		or not playerSpeed
		or not allXP
	then
		DebugModule.debugWarn(
			string.format(
				"Rejected XP award because player progression contains a non-finite value | player=%s",
				player.Name
			),
			"PlayerHandler"
		)
		return 0
	end

	if maxXP <= 0 or currentXP < 0 or currentLevel < 1 or maxLevel < currentLevel then
		DebugModule.debugWarn(
			string.format("Rejected XP award because player progression is invalid | player=%s", player.Name),
			"PlayerHandler"
		)
		return 0
	end

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
	if isFiniteNumber(value) then
		return value
	end

	return fallback
end

-- Keep saved speed attributes canonical; live events derive a temporary effective speed and cap.
function PlayerHandler.GetLiveEventWalkSpeedMultiplier(player: Player): number
	return math.max(0, getNumericAttribute(player, "LiveEvent_WalkSpeedMultiplier", 1))
end

function PlayerHandler.GetEffectiveMaxPlayerSpeed(player: Player): number
	local maxSpeed = math.max(0, getNumericAttribute(player, "Max_Player_Speed", DEFAULT_MAX_PLAYER_SPEED))
	return maxSpeed * PlayerHandler.GetLiveEventWalkSpeedMultiplier(player)
end

function PlayerHandler.GetEffectiveWalkSpeed(player: Player): number
	local playerSpeed = math.max(0, getNumericAttribute(player, "Player_Speed", DEFAULT_PLAYER_SPEED))
	local maxSpeed = math.max(0, getNumericAttribute(player, "Max_Player_Speed", DEFAULT_MAX_PLAYER_SPEED))
	local canonicalSpeed = math.min(playerSpeed, maxSpeed)
	return canonicalSpeed * PlayerHandler.GetLiveEventWalkSpeedMultiplier(player)
end

local function getTemporaryBoostMultiplier(player: Player, endAttributeName: string): number
	local endUnix = getNumericAttribute(player, endAttributeName, 0)
	return if endUnix > os.time() then 2 else 1
end

function PlayerHandler.HasPremiumMembership(player: Player?): boolean
	return player ~= nil and player.MembershipType == Enum.MembershipType.Premium
end

function PlayerHandler.GetPremiumMultiplier(player: Player): number
	return if PlayerHandler.HasPremiumMembership(player) then PREMIUM_MULTIPLIER else 1
end

function PlayerHandler.GetWinStreakMultiplier(player: Player): number
	local value = getNumericAttribute(player, "WinStreakMultiplier", 1)
	return math.max(1, value)
end

local function combineWinMultipliers(
	winMultiplier: number,
	liveEventMultiplier: number?,
	temporaryBoostMultiplier: number?,
	premiumMultiplier: number?,
	winStreakMultiplier: number?
): number
	-- Add each multiplier's bonus over 1x so two 2x sources produce 3x, not 4x.
	local combinedMultiplier = 1 + (math.max(0, winMultiplier) - 1)
	if liveEventMultiplier ~= nil then
		combinedMultiplier += math.max(0, liveEventMultiplier) - 1
	end
	if temporaryBoostMultiplier ~= nil then
		combinedMultiplier += math.max(0, temporaryBoostMultiplier) - 1
	end
	if premiumMultiplier ~= nil then
		combinedMultiplier += math.max(0, premiumMultiplier) - 1
	end
	if winStreakMultiplier ~= nil then
		combinedMultiplier += math.max(0, winStreakMultiplier) - 1
	end

	return math.max(0, combinedMultiplier)
end

local function getStandardXPSpeedMultiplier(player: Player): number
	local rebirthMult = getNumericAttribute(player, "Rebirth_XPMultiplier", 1)
	local devMult = getNumericAttribute(player, "DevProduct_XPSpeedMultiplier", 1)
	local miscMult = getNumericAttribute(player, "Misc_XPSpeedMultiplier", 1)
	local friendMult = getNumericAttribute(player, "Friend_XPMultiplier", 1)
	local treadmillMult = getNumericAttribute(player, "Treadmill_XPMultiplier", 1)

	return rebirthMult * devMult * miscMult * friendMult * treadmillMult * PlayerHandler.GetPremiumMultiplier(player)
end

local function multiplyEquippedPetMultiplier(player: Player, baseMultiplier: number): number
	local petMultiplier = PetInventoryService.GetEquippedMultiplier(player)
	return math.max(0, baseMultiplier * petMultiplier)
end

function PlayerHandler.GetXPSpeedMultiplier(player: Player): number
	local existingMultiplier = getStandardXPSpeedMultiplier(player)
		* PlayerHandler.GetLiveEventXPMultiplier(player)
		* getTemporaryBoostMultiplier(player, "TemporarySpeedBoostEndUnix")
	return multiplyEquippedPetMultiplier(player, existingMultiplier)
end

function PlayerHandler.CalculateAwardedXPSpeed(player: Player, amount: number): number
	return amount * PlayerHandler.GetXPSpeedMultiplier(player)
end

function PlayerHandler.CalculateRewardXPSpeed(player: Player, amount: number): number
	return amount * getStandardXPSpeedMultiplier(player)
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
	local combinedMultiplier = combineWinMultipliers(
		winMultiplier,
		nil,
		nil,
		PlayerHandler.GetPremiumMultiplier(player)
	)
	return math.max(0, math.round(amount * combinedMultiplier))
end

local function getLiveEventDefinition(eventName: string): { [string]: any }?
	local liveEventsConfig = CoreConfig.liveEvents
	if typeof(liveEventsConfig) ~= "table" or typeof(liveEventsConfig.events) ~= "table" then
		return nil
	end

	for _, eventDefinition in ipairs(liveEventsConfig.events) do
		if
			type(eventDefinition) == "table"
			and typeof(eventDefinition.id) == "string"
			and string.lower(eventDefinition.id) == string.lower(eventName)
		then
			return eventDefinition
		end
	end

	return nil
end

local function getEventWinsAttribute(eventName: string, eventDefinition: { [string]: any }?): string?
	if eventDefinition and typeof(eventDefinition.kartWinsAttribute) == "string" then
		return eventDefinition.kartWinsAttribute
	end

	local normalizedName = string.gsub(eventName, "[^%w]", "")
	return if normalizedName ~= "" then normalizedName .. "Wins" else nil
end

function PlayerHandler.GetEventWinBaseAward(eventName: string, requiredStage: number): number?
	if typeof(eventName) ~= "string" or not isFiniteNumber(requiredStage) then
		return nil
	end

	local eventDefinition = getLiveEventDefinition(eventName)
	local stageWinAwards = eventDefinition and eventDefinition.stageWinAwards
	if typeof(stageWinAwards) ~= "table" and string.lower(eventName) == "bloodmoon" then
		local progressConfig = CoreConfig.bloodmoonProgress
		stageWinAwards = if typeof(progressConfig) == "table" then progressConfig.winStageRewards else nil
	end
	if typeof(stageWinAwards) ~= "table" then
		return nil
	end

	local highestMinimumStage = -math.huge
	local highestAward = 0
	for _, rawReward in ipairs(stageWinAwards) do
		if typeof(rawReward) == "table" then
			local minimumStage = rawReward.minimumStage
			local amount = rawReward.amount
			local normalizedMinimumStage = if isFiniteNumber(minimumStage) then math.floor(minimumStage) else nil
			local normalizedAmount = if isFiniteNumber(amount) then math.floor(amount) else nil
			if
				normalizedMinimumStage ~= nil
				and normalizedAmount ~= nil
				and normalizedMinimumStage >= 0
				and normalizedAmount > 0
				and normalizedMinimumStage > highestMinimumStage
				and requiredStage >= normalizedMinimumStage
			then
				highestMinimumStage = normalizedMinimumStage
				highestAward = normalizedAmount
			end
		end
	end

	return if highestAward > 0 then highestAward else nil
end

function PlayerHandler.GetBloodmoonWinBaseAward(requiredStage: number): number?
	return PlayerHandler.GetEventWinBaseAward("Bloodmoon", requiredStage)
end

function PlayerHandler.CalculateEventWinAward(player: Player, eventName: string, baseAward: number?): number
	local winMultiplier = getNumericAttribute(player, "WinMultiplier", 1)
	local temporaryWinMultiplier = getTemporaryBoostMultiplier(player, "TemporaryWinBoostEndUnix")
	local normalizedBaseAward = if isFiniteNumber(baseAward) and baseAward > 0 then math.floor(baseAward) else 1
	local progressConfig = if string.lower(eventName) == "bloodmoon" then CoreConfig.bloodmoonProgress else nil
	if baseAward == nil and RunService:IsStudio() and typeof(progressConfig) == "table" then
		local studioWinAmount = progressConfig.debugStudioWinAmount
		if typeof(studioWinAmount) == "number" and studioWinAmount > 0 then
			normalizedBaseAward = math.max(1, math.floor(studioWinAmount))
		end
	end

	local combinedMultiplier = combineWinMultipliers(
		winMultiplier,
		nil,
		temporaryWinMultiplier,
		PlayerHandler.GetPremiumMultiplier(player),
		PlayerHandler.GetWinStreakMultiplier(player)
	)
	return math.max(1, math.round(normalizedBaseAward * combinedMultiplier))
end

function PlayerHandler.CalculateBloodmoonWinAward(player: Player, baseAward: number?): number
	return PlayerHandler.CalculateEventWinAward(player, "Bloodmoon", baseAward)
end

function PlayerHandler.AddEventWin(player: Player, eventName: string, baseAward: number?): number
	local eventDefinition = getLiveEventDefinition(eventName)
	local winsAttribute = getEventWinsAttribute(eventName, eventDefinition)
	if not winsAttribute then
		return 0
	end

	local currentWins = getFiniteNumberAttribute(player, winsAttribute, 0)
	local awardedAmount = PlayerHandler.CalculateEventWinAward(player, eventName, baseAward)
	if not currentWins or not isFiniteNumber(awardedAmount) then
		DebugModule.debugWarn(
			string.format("Rejected invalid event win award | event=%s | player=%s", eventName, player.Name),
			"PlayerHandler"
		)
		return 0
	end

	PlayerHandler.SetAttribute(player, winsAttribute, currentWins + awardedAmount)
	return awardedAmount
end

function PlayerHandler.AddBloodmoonWin(player: Player, baseAward: number?): (number, { string })
	local awardedAmount = PlayerHandler.AddEventWin(player, "Bloodmoon", baseAward)
	if awardedAmount <= 0 then
		return 0, {}
	end

	return awardedAmount, PlayerHandler.SyncBloodmoonUnlocks(player)
end

function PlayerHandler.ResetEventWinsForCycle(player: Player, eventName: string, cycleStartUnix: number): boolean
	if typeof(eventName) ~= "string" or not isFiniteNumber(cycleStartUnix) or cycleStartUnix <= 0 then
		return false
	end

	local eventDefinition = getLiveEventDefinition(eventName)
	local winsAttribute = getEventWinsAttribute(eventName, eventDefinition)
	if not winsAttribute then
		return false
	end

	local cycleAttribute = winsAttribute .. "CycleUnix"
	local normalizedCycle = math.floor(cycleStartUnix)
	local previousCycle = getFiniteNumberAttribute(player, cycleAttribute, 0)
	if previousCycle == normalizedCycle then
		return false
	end

	PlayerHandler.SetAttribute(player, winsAttribute, 0)
	PlayerHandler.SetAttribute(player, cycleAttribute, normalizedCycle)
	return true
end

local function getEventUnlocks(eventName: string): { [number]: any }?
	local eventDefinition = getLiveEventDefinition(eventName)
	local progressUi = eventDefinition and eventDefinition.progressUi
	if typeof(progressUi) == "table" and typeof(progressUi.unlocks) == "table" then
		return progressUi.unlocks
	end

	if string.lower(eventName) == "bloodmoon" then
		local progressConfig = CoreConfig.bloodmoonProgress
		if typeof(progressConfig) == "table" and typeof(progressConfig.unlocks) == "table" then
			return progressConfig.unlocks
		end
	end

	return nil
end

function PlayerHandler.GetEventUnlockDisplayName(eventName: string, rewardId: string): string?
	local unlocks = getEventUnlocks(eventName)
	if not unlocks then
		return nil
	end

	for _, unlock in ipairs(unlocks) do
		if typeof(unlock) == "table" and unlock.id == rewardId and typeof(unlock.displayName) == "string" then
			return unlock.displayName
		end
	end

	return nil
end

function PlayerHandler.SyncEventUnlocks(player: Player, eventName: string): { string }
	local unlocks = getEventUnlocks(eventName)
	if not unlocks then
		return {}
	end

	local eventDefinition = getLiveEventDefinition(eventName)
	local winsAttribute = getEventWinsAttribute(eventName, eventDefinition)
	if not winsAttribute then
		return {}
	end

	local currentWins = getFiniteNumberAttribute(player, winsAttribute, 0)
	if not currentWins then
		return {}
	end

	local unlockedRewards: { string } = {}
	for _, unlock in ipairs(unlocks) do
		if typeof(unlock) ~= "table" then
			continue
		end

		local rewardId = unlock.id
		local winsRequired = unlock.winsRequired
		if
			typeof(rewardId) ~= "string"
			or typeof(winsRequired) ~= "number"
			or not isFiniteNumber(winsRequired)
			or currentWins < winsRequired
		then
			continue
		end

		local alreadyOwned = if unlock.kind == "Kart"
			then PlayerHandler.OwnsKart(player, rewardId)
			else PlayerHandler.OwnsTrail(player, rewardId)
		if alreadyOwned then
			continue
		end

		local legacyOwned = false
		local legacyIds = unlock.legacyIds
		if typeof(legacyIds) == "table" then
			for _, legacyId in ipairs(legacyIds) do
				if
					typeof(legacyId) == "string"
					and (
						(unlock.kind == "Kart" and PlayerHandler.OwnsKart(player, legacyId))
						or (unlock.kind == "Trail" and PlayerHandler.OwnsTrail(player, legacyId))
					)
				then
					legacyOwned = true
					break
				end
			end
		end
		if legacyOwned then
			if unlock.kind == "Kart" then
				PlayerHandler.AddOwnedKart(player, rewardId)
			else
				PlayerHandler.AddOwnedTrail(player, rewardId)
			end
			table.insert(unlockedRewards, rewardId)
			DebugModule.debugInfo(
				string.format("Migrated event ownership | event=%s | player=%s | reward=%s", eventName, player.Name, rewardId),
				"PlayerHandler"
			)
			continue
		end

		if unlock.kind == "Trail" then
			local trailConfig = PlayerHandler.GetTrailConfig(rewardId)
			if trailConfig and trailConfig.EventOnly == true and not PlayerHandler.OwnsTrail(player, rewardId) then
				PlayerHandler.AddOwnedTrail(player, rewardId)
				table.insert(unlockedRewards, rewardId)
				DebugModule.debugInfo(
					string.format("Unlocked permanent event trail | event=%s | player=%s | trail=%s", eventName, player.Name, rewardId),
					"PlayerHandler"
				)
			end
		elseif unlock.kind == "Kart" and not PlayerHandler.OwnsKart(player, rewardId) then
			PlayerHandler.AddOwnedKart(player, rewardId)
			table.insert(unlockedRewards, rewardId)
			DebugModule.debugInfo(
				string.format("Unlocked permanent event kart | event=%s | player=%s | kart=%s", eventName, player.Name, rewardId),
				"PlayerHandler"
			)
		end
	end

	return unlockedRewards
end

function PlayerHandler.GetBloodmoonUnlockDisplayName(rewardId: string): string?
	return PlayerHandler.GetEventUnlockDisplayName("Bloodmoon", rewardId)
end

function PlayerHandler.SyncBloodmoonUnlocks(player: Player): { string }
	return PlayerHandler.SyncEventUnlocks(player, "Bloodmoon")
end

function PlayerHandler.SyncConfiguredEventUnlocks(player: Player)
	local liveEventsConfig = CoreConfig.liveEvents
	if typeof(liveEventsConfig) ~= "table" or typeof(liveEventsConfig.events) ~= "table" then
		return
	end

	for _, eventDefinition in ipairs(liveEventsConfig.events) do
		if typeof(eventDefinition) == "table" and typeof(eventDefinition.id) == "string" then
			PlayerHandler.SyncEventUnlocks(player, eventDefinition.id)
		end
	end
end

function PlayerHandler.ResetBloodmoonWinsForCycle(player: Player, cycleStartUnix: number): boolean
	return PlayerHandler.ResetEventWinsForCycle(player, "Bloodmoon", cycleStartUnix)
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
	local combinedWinMult = combineWinMultipliers(
		winMult,
		nil,
		nil,
		PlayerHandler.GetPremiumMultiplier(player)
	)

	return rebirthMult * combinedWinMult * miscMult * reducedDevMult
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
	return applyAwardedXPSpeed(player, PlayerHandler.CalculateRewardXPSpeed(player, amount))
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
	local currentWins = getFiniteNumberAttribute(player, "WinCount", 0)
	if not currentWins or not isFiniteNumber(amount) or amount < 0 then
		DebugModule.debugWarn(
			string.format("Rejected invalid win award | player=%s | amount=%s", player.Name, tostring(amount)),
			"PlayerHandler"
		)
		return 0
	end

	local finalAmount = math.max(0, math.round(amount))
	if not isFiniteNumber(finalAmount) then
		DebugModule.debugWarn(
			string.format(
				"Rejected non-finite rounded win award | player=%s | amount=%s",
				player.Name,
				tostring(amount)
			),
			"PlayerHandler"
		)
		return 0
	end

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
	local currentWins = getFiniteNumberAttribute(player, "WinCount", 0)
	local finalAmount = PlayerHandler.CalculateAwardedWins(player, amount)
	if not currentWins or not isFiniteNumber(finalAmount) then
		DebugModule.debugWarn(
			string.format(
				"Rejected invalid calculated win award | player=%s | amount=%s",
				player.Name,
				tostring(amount)
			),
			"PlayerHandler"
		)
		return 0
	end

	PlayerHandler.SetAttribute(player, "WinCount", currentWins + finalAmount)
	return finalAmount
end

function PlayerHandler.AddWinButtonWins(player: Player, amount: number): number
	local currentWins = getFiniteNumberAttribute(player, "WinCount", 0)
	local combinedMultiplier = combineWinMultipliers(
		getNumericAttribute(player, "WinMultiplier", 1),
		PlayerHandler.GetLiveEventWinButtonMultiplier(player),
		getTemporaryBoostMultiplier(player, "TemporaryWinBoostEndUnix"),
		PlayerHandler.GetPremiumMultiplier(player),
		PlayerHandler.GetWinStreakMultiplier(player)
	)
	local gamePassAward = math.round(amount * combinedMultiplier)
	if not currentWins or not isFiniteNumber(gamePassAward) then
		DebugModule.debugWarn(
			string.format("Rejected invalid win-button award | player=%s | amount=%s", player.Name, tostring(amount)),
			"PlayerHandler"
		)
		return 0
	end
	local finalAmount = math.max(0, gamePassAward)
	if not isFiniteNumber(finalAmount) then
		DebugModule.debugWarn(
			string.format("Rejected non-finite win-button award | player=%s | amount=%s", player.Name, tostring(amount)),
			"PlayerHandler"
		)
		return 0
	end

	PlayerHandler.SetAttribute(player, "WinCount", currentWins + finalAmount)
	return finalAmount
end

function PlayerHandler.AddPlaytimeWins(player: Player, amount: number): number
	local currentWins = getFiniteNumberAttribute(player, "WinCount", 0)
	local finalAmount = PlayerHandler.CalculatePlaytimeWinsAward(player, amount)
	if not currentWins or not isFiniteNumber(finalAmount) then
		DebugModule.debugWarn(
			string.format("Rejected invalid playtime win award | player=%s | amount=%s", player.Name, tostring(amount)),
			"PlayerHandler"
		)
		return 0
	end

	PlayerHandler.SetAttribute(player, "WinCount", currentWins + finalAmount)
	return finalAmount
end

return PlayerHandler
