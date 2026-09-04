--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))
local SpinWheelConfig = require(ConfigFolder:WaitForChild("SpinWheelConfig"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local ProductService = require(Modules:WaitForChild("ProductService"))
local ProductServerService = require(script.Parent:WaitForChild("ProductServerService"))
local LevelingService = require(script.Parent:WaitForChild("LevelingService"))
local EconomyAnalytics = require(script.Parent:WaitForChild("EconomyAnalytics"))

local SpinWheelService = {}

local MODULE_NAME = "SpinWheelService"
local SPINS_ATTRIBUTE = "SpinWheelSpins"
local NEXT_FREE_SPIN_ATTRIBUTE = "SpinWheelNextFreeSpinUnix"
local INITIALIZED_ATTRIBUTE = "SpinWheelFreeSpinInitialized"
local PROCESSED_RECEIPTS_ATTRIBUTE = "SpinWheelProcessedReceiptIds"
local REQUEST_COOLDOWN_SECONDS = 0.15
local MAX_STORED_RECEIPTS = 40

local spinWheelConfig = if CoreConfig.spinWheel then CoreConfig.spinWheel else {}
local FREE_SPIN_COOLDOWN_SECONDS = if typeof(spinWheelConfig.freeSpinCooldownSeconds) == "number"
	then math.max(1, math.floor(spinWheelConfig.freeSpinCooldownSeconds))
	else 24 * 60 * 60
local DEBUG_FREE_SPIN_READY_IN_STUDIO = spinWheelConfig.debugFreeSpinReadyInStudio == true

local requestInFlight: { [Player]: boolean } = {}
local lastRequestTimes: { [Player]: number } = {}
local processedReceipts: { [Player]: { [string]: boolean } } = {}
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

local function addWheelWins(player: Player): number
	local totalWins = getNumberAttribute(player, "WinCount", 0)
	return PlayerHandler.AddWins(player, SpinWheelConfig.GetWheelWinsBase(totalWins))
end

local function getSmallSpeedBase(player: Player): number
	return SpinWheelConfig.GetSmallSpeedBase(
		getNumberAttribute(player, "CurrentXPSpeed", 0),
		getNumberAttribute(player, "MaxXPSpeed", 1)
	)
end

local function processReward(player: Player, reward: SpinWheelConfig.RewardDefinition): { [string]: any }
	local result: { [string]: any } = {
		rewardId = reward.id,
		duplicate = false,
		awardedSpeed = 0,
		awardedWins = 0,
		awardedRebirth = 0,
	}

	if reward.id == "SpeedSmall" then
		result.awardedSpeed = PlayerHandler.AddXPSpeed(player, getSmallSpeedBase(player))
	elseif reward.id == "SpeedLarge" then
		result.awardedSpeed = PlayerHandler.AddXPSpeed(player, getSmallSpeedBase(player) * 3)
	elseif reward.id == "Wins" then
		result.awardedWins = addWheelWins(player)
	elseif reward.id == "Rebirth" then
		if LevelingService.PerformRebirth(player, true) then
			result.awardedRebirth = 1
		end
	elseif reward.id == "FlameTrail" then
		if PlayerHandler.OwnsTrail(player, "FlameTrail") then
			result.duplicate = true
			result.awardedSpeed = PlayerHandler.AddXPSpeed(player, getSmallSpeedBase(player))
			result.awardedWins = addWheelWins(player)
		else
			PlayerHandler.AddOwnedTrail(player, "FlameTrail")
		end
	elseif reward.id == "FlameKart" then
		if PlayerHandler.OwnsKart(player, "1_FlameKart") then
			result.duplicate = true
			result.awardedSpeed = PlayerHandler.AddXPSpeed(player, getSmallSpeedBase(player) * 3)
			result.awardedWins = addWheelWins(player)
		else
			PlayerHandler.AddOwnedKart(player, "1_FlameKart")
		end
	end

	if result.awardedSpeed > 0 then
		EconomyAnalytics.LogSource(
			player,
			"XPSpeed",
			result.awardedSpeed,
			Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
			"SpinWheel_" .. reward.id
		)
	end
	if result.awardedWins > 0 then
		EconomyAnalytics.LogSource(
			player,
			"Wins",
			result.awardedWins,
			Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
			"SpinWheel_" .. reward.id
		)
	end

	return result
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
	local ok, resultOrError = pcall(processReward, player, reward)
	if not ok then
		setSpinCount(player, previousSpinCount)
		player:SetAttribute(NEXT_FREE_SPIN_ATTRIBUTE, previousNextFreeSpinUnix)
		DebugModule.debugWarn("Spin reward failed for " .. player.Name .. ": " .. tostring(resultOrError), MODULE_NAME)
		requestInFlight[player] = nil
		return
	end

	local result = resultOrError :: { [string]: any }
	result.remainingSpins = getSpinCount(player)
	spinResultRemote:FireClient(player, result)
	ProductServerService.SavePlayerData(player)
	requestInFlight[player] = nil
end

local function registerPurchaseCallbacks()
	for _, pack in ipairs(SpinWheelConfig.PurchasePacks) do
		local productId = ProductService.DevProducts[pack.productKey]
		if productId then
			ProductServerService.SetProductCallback(productId, function(
				player: Player,
				_: number,
				bought: boolean,
				purchaseId: string?
			)
				if not bought then
					return
				end
				if purchaseId and not rememberReceipt(player, purchaseId) then
					return
				end
				addSpins(player, pack.spins)
				ProductServerService.SavePlayerData(player)
			end)
		end
	end
end

function SpinWheelService.OnPlayerAdded(player: Player)
	if player:GetAttribute(INITIALIZED_ATTRIBUTE) ~= true then
		player:SetAttribute(INITIALIZED_ATTRIBUTE, true)
		if getSpinCount(player) <= 0 then
			addSpins(player, 1)
		end
		player:SetAttribute(NEXT_FREE_SPIN_ATTRIBUTE, 0)
	end
	readReceiptHistory(player)
end

function SpinWheelService.CleanupPlayer(player: Player)
	requestInFlight[player] = nil
	lastRequestTimes[player] = nil
	processedReceipts[player] = nil
end

function SpinWheelService.Init()
	if initialized then
		return
	end
	initialized = true
	spinRequestRemote.OnServerEvent:Connect(handleSpinRequest)
	registerPurchaseCallbacks()
	Players.PlayerRemoving:Connect(SpinWheelService.CleanupPlayer)
	DebugModule.debugPrint("Spin wheel service initialized", MODULE_NAME)
end

return SpinWheelService
