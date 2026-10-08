--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))
local SpinWheelConfig = require(ConfigFolder:WaitForChild("SpinWheelConfig"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local Maid = require(Modules:WaitForChild("Maid"))
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local ProductService = require(Modules:WaitForChild("ProductService"))
local ProductServerService = require(script.Parent:WaitForChild("ProductServerService"))
local LevelingService = require(script.Parent:WaitForChild("LevelingService"))
local EconomyAnalytics = require(script.Parent:WaitForChild("EconomyAnalytics"))

local SpinWheelService = {}

local MODULE_NAME = "SpinWheelService"
local SPINS_ATTRIBUTE = "SpinWheelSpins"
local NEXT_FREE_SPIN_ATTRIBUTE = "SpinWheelNextFreeSpinUnix"
local REWARDED_AD_NEXT_AVAILABLE_ATTRIBUTE = "SpinWheelRewardedAdNextAvailableUnix"
local REWARDED_AD_RESET_ATTRIBUTE = "SpinWheelRewardedAdResetUnix"
local INITIALIZED_ATTRIBUTE = "SpinWheelFreeSpinInitialized"
local PROCESSED_RECEIPTS_ATTRIBUTE = "SpinWheelProcessedReceiptIds"
local REQUEST_COOLDOWN_SECONDS = 0.15
local MAX_STORED_RECEIPTS = 40
local spinWheelConfig = if CoreConfig.spinWheel then CoreConfig.spinWheel else {}
local SPIN_ANIMATION_DURATION_SECONDS = if typeof(spinWheelConfig.spinRotationDuration) == "number"
	then math.max(0.5, spinWheelConfig.spinRotationDuration)
	else 4
local PENDING_SPIN_TIMEOUT_SECONDS = SPIN_ANIMATION_DURATION_SECONDS + 10

local FREE_SPIN_COOLDOWN_SECONDS = if typeof(spinWheelConfig.freeSpinCooldownSeconds) == "number"
	then math.max(1, math.floor(spinWheelConfig.freeSpinCooldownSeconds))
	else 24 * 60 * 60
local REWARDED_AD_COOLDOWN_SECONDS = if typeof(spinWheelConfig.rewardedAdCooldownSeconds) == "number"
	then math.max(1, math.floor(spinWheelConfig.rewardedAdCooldownSeconds))
	else 5 * 60
local DEBUG_FREE_SPIN_READY_IN_STUDIO = spinWheelConfig.debugFreeSpinReadyInStudio == true

local requestInFlight: { [Player]: boolean } = {}
local lastRequestTimes: { [Player]: number } = {}
local processedReceipts: { [Player]: { [string]: boolean } } = {}
local serviceMaid = Maid.new()

type PendingSpin = {
	token: string,
	reward: SpinWheelConfig.RewardDefinition,
	previousSpinCount: number,
	previousNextFreeSpinUnix: number,
	startedAt: number,
	expiresAt: number,
	status: "Started" | "Ready",
	preparedResult: { [string]: any }?,
}

local pendingSpins: { [Player]: PendingSpin } = {}
local initialized = false

local function getOrCreateRemote(name: string): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local existing = remotes:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local spinRequestRemote = getOrCreateRemote("SpinWheelRequest")
local spinResultRemote = getOrCreateRemote("SpinWheelResult")
local spinClaimRemote = getOrCreateRemote("SpinWheelClaim")
local spinGrantRemote = getOrCreateRemote("SpinWheelGrant")
local spinAdRewardedRemote = getOrCreateRemote("SpinWheelAdRewarded")

local function getNumberAttribute(player: Player, name: string, defaultValue: number): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else defaultValue
end

local function getSpinCount(player: Player): number
	return math.max(0, math.floor(getNumberAttribute(player, SPINS_ATTRIBUTE, 0)))
end

local function setSpinCount(player: Player, count: number)
	player:SetAttribute(SPINS_ATTRIBUTE, math.max(0, math.floor(count)))
end

local function addSpins(player: Player, amount: number)
	setSpinCount(player, getSpinCount(player) + math.max(0, math.floor(amount)))
end

local function isStudioFreeSpinDebugEnabled(): boolean
	return RunService:IsStudio() and DEBUG_FREE_SPIN_READY_IN_STUDIO
end

local function readReceiptHistory(player: Player): { [string]: boolean }
	local history = processedReceipts[player]
	if history then
		return history
	end

	history = {}
	local serialized = player:GetAttribute(PROCESSED_RECEIPTS_ATTRIBUTE)
	if typeof(serialized) == "string" then
		for receiptId in string.gmatch(serialized, "[^,]+") do
			history[receiptId] = true
		end
	end
	processedReceipts[player] = history
	return history
end

local function rememberReceipt(player: Player, receiptId: string): boolean
	if receiptId == "" then
		return true
	end

	local history = readReceiptHistory(player)
	if history[receiptId] then
		return false
	end
	history[receiptId] = true

	local receiptIds = {}
	for storedReceiptId in pairs(history) do
		table.insert(receiptIds, storedReceiptId)
	end
	table.sort(receiptIds)
	while #receiptIds > MAX_STORED_RECEIPTS do
		history[table.remove(receiptIds, 1) :: string] = nil
	end
	player:SetAttribute(PROCESSED_RECEIPTS_ATTRIBUTE, table.concat(receiptIds, ","))
	return true
end

local function getNextFreeSpinUnix(player: Player): number
	return math.max(0, math.floor(getNumberAttribute(player, NEXT_FREE_SPIN_ATTRIBUTE, 0)))
end

local function makeFreeSpinReadyIfDue(player: Player): boolean
	local spins = getSpinCount(player)
	if spins > 0 then
		return true
	end

	if isStudioFreeSpinDebugEnabled() then
		addSpins(player, 1)
		player:SetAttribute(NEXT_FREE_SPIN_ATTRIBUTE, 0)
		return true
	end

	local now = os.time()
	local nextFreeSpinUnix = getNextFreeSpinUnix(player)
	local hasInitialized = player:GetAttribute(INITIALIZED_ATTRIBUTE) == true
	if not hasInitialized then
		player:SetAttribute(INITIALIZED_ATTRIBUTE, true)
		addSpins(player, 1)
		player:SetAttribute(NEXT_FREE_SPIN_ATTRIBUTE, 0)
		return true
	end

	if nextFreeSpinUnix > 0 and now >= nextFreeSpinUnix then
		addSpins(player, 1)
		player:SetAttribute(NEXT_FREE_SPIN_ATTRIBUTE, now + FREE_SPIN_COOLDOWN_SECONDS)
		return true
	end

	return false
end

local function chooseReward(): SpinWheelConfig.RewardDefinition
	local totalChance = 0
	for _, reward in ipairs(SpinWheelConfig.Rewards) do
		totalChance += reward.chance
	end

	local roll = Random.new():NextNumber(0, totalChance)
	local cumulativeChance = 0
	for _, reward in ipairs(SpinWheelConfig.Rewards) do
		cumulativeChance += reward.chance
		if roll <= cumulativeChance then
			return reward
		end
	end

	return SpinWheelConfig.Rewards[#SpinWheelConfig.Rewards]
end

local function getSmallSpeedBase(player: Player): number
	return SpinWheelConfig.GetSmallSpeedBase(getNumberAttribute(player, "MaxXPSpeed", 1))
end

local function getLargeSpeedBase(player: Player): number
	return SpinWheelConfig.GetLargeSpeedBase(getNumberAttribute(player, "MaxXPSpeed", 1))
end

local function calculateReward(player: Player, reward: SpinWheelConfig.RewardDefinition): { [string]: any }
	local result: { [string]: any } = {
		rewardId = reward.id,
		duplicate = false,
		awardedSpeed = 0,
		awardedWins = 0,
		awardedRebirth = 0,
	}

	if reward.id == "SpeedSmall" then
		result.awardedSpeed = getSmallSpeedBase(player)
	elseif reward.id == "SpeedLarge" then
		result.awardedSpeed = getLargeSpeedBase(player)
	elseif reward.id == "Wins" then
		result.awardedWins = SpinWheelConfig.GetWheelWinsBase(getNumberAttribute(player, "WinCount", 0))
	elseif reward.id == "Rebirth" then
		-- Wheel rewards grant the rebirth directly, like Daily/Playtime rewards.
		result.awardedRebirth = 1
	elseif reward.id == "FlameTrail" then
		if PlayerHandler.OwnsTrail(player, "FlameTrail") then
			result.duplicate = true
			result.awardedSpeed = getSmallSpeedBase(player)
			result.awardedWins = SpinWheelConfig.GetWheelWinsBase(getNumberAttribute(player, "WinCount", 0))
		else
		end
	elseif reward.id == "FlameKart" then
		if PlayerHandler.OwnsKart(player, "1_FlameKart") then
			result.duplicate = true
			result.awardedSpeed = getLargeSpeedBase(player)
			result.awardedWins = SpinWheelConfig.GetWheelWinsBase(getNumberAttribute(player, "WinCount", 0))
		else
		end
	end

	return result
end

local function logReward(player: Player, result: { [string]: any })
	local rewardId = tostring(result.rewardId)

	if result.awardedSpeed > 0 then
		EconomyAnalytics.LogSource(
			player,
			"XPSpeed",
			result.awardedSpeed,
			Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
			"SpinWheel_" .. rewardId
		)
	end
	if result.awardedWins > 0 then
		EconomyAnalytics.LogSource(
			player,
			"Wins",
			result.awardedWins,
			Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
			"SpinWheel_" .. rewardId
		)
	end
end

local function processReward(player: Player, reward: SpinWheelConfig.RewardDefinition, result: { [string]: any })
	if result.awardedSpeed > 0 then
		PlayerHandler.AddExactXPSpeed(player, result.awardedSpeed)
	end
	if result.awardedWins > 0 then
		PlayerHandler.AddExactWins(player, result.awardedWins)
	end

	if reward.id == "Rebirth" and result.awardedRebirth > 0 then
		if not LevelingService.PerformRebirth(player, true) then
			DebugModule.debugError("Rebirth could not be completed", nil, MODULE_NAME)
			return
		end
	elseif reward.id == "FlameTrail" and not result.duplicate then
		PlayerHandler.AddOwnedTrail(player, "FlameTrail")
	elseif reward.id == "FlameKart" and not result.duplicate then
		PlayerHandler.AddOwnedKart(player, "1_FlameKart")
	end

	logReward(player, result)
end

local function restorePendingSpin(player: Player): boolean
	local pending = pendingSpins[player]
	if not pending then
		return false
	end

	setSpinCount(player, pending.previousSpinCount)
	player:SetAttribute(NEXT_FREE_SPIN_ATTRIBUTE, pending.previousNextFreeSpinUnix)
	pendingSpins[player] = nil
	return true
end

local function expirePendingSpin(player: Player)
	local pending = pendingSpins[player]
	if pending and os.clock() >= pending.expiresAt then
		restorePendingSpin(player)
	end
end

local function handleSpinRequest(player: Player)
	if player.Parent == nil or player:GetAttribute("Data_Loaded") ~= true then
		return
	end

	local now = os.clock()
	if requestInFlight[player] or now < (lastRequestTimes[player] or 0) + REQUEST_COOLDOWN_SECONDS then
		return
	end
	requestInFlight[player] = true
	lastRequestTimes[player] = now
	expirePendingSpin(player)
	if pendingSpins[player] then
		requestInFlight[player] = nil
		return
	end

	local ready = makeFreeSpinReadyIfDue(player)
	if not ready or getSpinCount(player) <= 0 then
		requestInFlight[player] = nil
		return
	end

	local previousSpinCount = getSpinCount(player)
	local previousNextFreeSpinUnix = getNextFreeSpinUnix(player)
	setSpinCount(player, previousSpinCount - 1)
	local nextFreeSpinUnix = getNextFreeSpinUnix(player)
	if isStudioFreeSpinDebugEnabled() and getSpinCount(player) <= 0 then
		addSpins(player, 1)
		player:SetAttribute(NEXT_FREE_SPIN_ATTRIBUTE, 0)
	elseif nextFreeSpinUnix <= os.time() then
		player:SetAttribute(NEXT_FREE_SPIN_ATTRIBUTE, os.time() + FREE_SPIN_COOLDOWN_SECONDS)
	end

	local reward = chooseReward()
	local token = HttpService:GenerateGUID(false)
	pendingSpins[player] = {
		token = token,
		reward = reward,
		previousSpinCount = previousSpinCount,
		previousNextFreeSpinUnix = previousNextFreeSpinUnix,
		startedAt = os.clock(),
		expiresAt = os.clock() + PENDING_SPIN_TIMEOUT_SECONDS,
		status = "Started",
	}
	spinResultRemote:FireClient(player, {
		phase = "Started",
		token = token,
		rewardId = reward.id,
		remainingSpins = getSpinCount(player),
	})
	requestInFlight[player] = nil
end

local function handleSpinClaim(player: Player, token: any)
	if typeof(token) ~= "string" or token == "" then
		return
	end

	expirePendingSpin(player)
	local pending = pendingSpins[player]
	if not pending or pending.token ~= token or pending.status ~= "Started" then
		return
	end
	if os.clock() < pending.startedAt + SPIN_ANIMATION_DURATION_SECONDS then
		DebugModule.debugWarn("Spin claim arrived before animation finished for " .. player.Name, MODULE_NAME)
		return
	end

	local ok, resultOrError = pcall(calculateReward, player, pending.reward)
	if not ok then
		restorePendingSpin(player)
		DebugModule.debugWarn(
			"Spin calculation failed for " .. player.Name .. ": " .. tostring(resultOrError),
			MODULE_NAME
		)
		return
	end

	local result = resultOrError :: { [string]: any }
	pending.status = "Ready"
	pending.preparedResult = result
	result.phase = "RewardReady"
	result.token = token
	result.remainingSpins = getSpinCount(player)
	spinResultRemote:FireClient(player, result)
end

local function handleSpinGrant(player: Player, token: any)
	if typeof(token) ~= "string" or token == "" then
		return
	end

	expirePendingSpin(player)
	local pending = pendingSpins[player]
	if not pending or pending.token ~= token or pending.status ~= "Ready" or not pending.preparedResult then
		return
	end

	local result = pending.preparedResult
	local ok, grantError = pcall(processReward, player, pending.reward, result)
	if not ok then
		restorePendingSpin(player)
		DebugModule.debugWarn("Spin reward failed for " .. player.Name .. ": " .. tostring(grantError), MODULE_NAME)
		return
	end

	pendingSpins[player] = nil
	result.phase = "Granted"
	result.token = token
	result.remainingSpins = getSpinCount(player)
	spinResultRemote:FireClient(player, result)
	ProductServerService.SavePlayerData(player)
end

local function registerPurchaseCallbacks()
	for _, pack in ipairs(SpinWheelConfig.PurchasePacks) do
		local productId = ProductService.DevProducts[pack.productKey]
		if productId then
			DebugModule.debugPrint(
				"Registered spin product "
					.. pack.productKey
					.. " ("
					.. tostring(productId)
					.. ") for "
					.. tostring(pack.spins)
					.. " spins",
				MODULE_NAME
			)
			ProductServerService.SetProductCallback(
				productId,
				function(
					player: Player,
					_: number,
					bought: boolean,
					purchaseId: string?,
					purchaseChannel: EnumItem?
				)
					if not bought then
						return
					end
					if purchaseId and not rememberReceipt(player, purchaseId) then
						return
					end
					addSpins(player, pack.spins)
					if pack.productKey == "Spin1" and purchaseChannel == Enum.ProductPurchaseChannel.AdReward then
						player:SetAttribute(
							REWARDED_AD_NEXT_AVAILABLE_ATTRIBUTE,
							os.time() + REWARDED_AD_COOLDOWN_SECONDS
						)
						spinAdRewardedRemote:FireClient(
							player,
							getSpinCount(player),
							player:GetAttribute("SpinWheelRewardedAdSpinsRemaining"),
							player:GetAttribute(REWARDED_AD_NEXT_AVAILABLE_ATTRIBUTE),
							player:GetAttribute(REWARDED_AD_RESET_ATTRIBUTE)
						)
						DebugModule.debugInfo(
							"Rewarded spin granted; requesting automatic wheel spin | player=" .. player.Name,
							MODULE_NAME
						)
					end
					ProductServerService.SavePlayerData(player)
				end
			)
		end
	end
end

function SpinWheelService.OnPlayerAdded(player: Player)
	if player:GetAttribute(INITIALIZED_ATTRIBUTE) ~= true then
		local now = os.time()
		local existingSpins = getSpinCount(player)
		local existingNextFreeSpinUnix = getNextFreeSpinUnix(player)

		-- Existing ad/product spins must not be mistaken for the initial free spin.
		if existingSpins <= 0 and existingNextFreeSpinUnix <= now then
			addSpins(player, 1)
			player:SetAttribute(NEXT_FREE_SPIN_ATTRIBUTE, 0)
		elseif existingSpins > 0 and existingNextFreeSpinUnix <= 0 then
			player:SetAttribute(NEXT_FREE_SPIN_ATTRIBUTE, now + FREE_SPIN_COOLDOWN_SECONDS)
		end

		player:SetAttribute(INITIALIZED_ATTRIBUTE, true)
	end
	readReceiptHistory(player)
end

function SpinWheelService.CleanupPlayer(player: Player)
	if pendingSpins[player] then
		restorePendingSpin(player)
	end
	requestInFlight[player] = nil
	lastRequestTimes[player] = nil
	processedReceipts[player] = nil
end

function SpinWheelService.Init()
	if initialized then
		return
	end
	initialized = true
	serviceMaid.SpinRequest = spinRequestRemote.OnServerEvent:Connect(handleSpinRequest)
	serviceMaid.SpinClaim = spinClaimRemote.OnServerEvent:Connect(handleSpinClaim)
	serviceMaid.SpinGrant = spinGrantRemote.OnServerEvent:Connect(handleSpinGrant)
	registerPurchaseCallbacks()
	serviceMaid.PlayerRemoving = Players.PlayerRemoving:Connect(SpinWheelService.CleanupPlayer)
	DebugModule.debugPrint("Spin wheel service initialized", MODULE_NAME)
end

function SpinWheelService.Shutdown()
	for player in pairs(table.clone(pendingSpins)) do
		restorePendingSpin(player)
	end
	serviceMaid:DoCleaning()
	table.clear(requestInFlight)
	table.clear(lastRequestTimes)
	table.clear(processedReceipts)
	table.clear(pendingSpins)
	initialized = false
end

return SpinWheelService
