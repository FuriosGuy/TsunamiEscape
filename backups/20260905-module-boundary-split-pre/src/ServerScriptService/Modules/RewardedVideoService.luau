--!strict

local AdService = game:GetService("AdService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CoreConfig = require(Modules.Config.CoreConfig)
local DebugModule = require(Modules.DebugModule)
local Maid = require(Modules.Maid)
local ProductService = require(Modules.ProductService)
local ReturnToStageService = require(script.Parent.ReturnToStageService)

local RewardedVideoService = {}

local MODULE_NAME = "RewardedVideoService"
local rewardedVideoConfig: any = CoreConfig.rewardedVideo or {}
local ENABLED = rewardedVideoConfig.enabled ~= false
local REQUEST_COOLDOWN_SECONDS = math.max(0, tonumber(rewardedVideoConfig.requestCooldownSeconds) or 3)
local spinWheelConfig: any = CoreConfig.spinWheel or {}
local SPIN_WHEEL_REWARDED_AD_MAX_SPINS = math.max(1, math.floor(tonumber(spinWheelConfig.rewardedAdMaxSpins) or 5))
local SPIN_WHEEL_REWARDED_AD_COOLDOWN_SECONDS =
	math.max(1, math.floor(tonumber(spinWheelConfig.rewardedAdCooldownSeconds) or (5 * 60)))
local SPIN_WHEEL_REWARDED_AD_RESET_SECONDS =
	math.max(1, math.floor(tonumber(spinWheelConfig.rewardedAdResetSeconds) or (24 * 60 * 60)))

local SPIN_WHEEL_AD_REMAINING_ATTRIBUTE = "SpinWheelRewardedAdSpinsRemaining"
local SPIN_WHEEL_AD_NEXT_AVAILABLE_ATTRIBUTE = "SpinWheelRewardedAdNextAvailableUnix"
local SPIN_WHEEL_AD_RESET_ATTRIBUTE = "SpinWheelRewardedAdResetUnix"

type Placement = {
	productKey: string,
	placementId: number?,
	remainingAttribute: string?,
	nextAvailableAttribute: string?,
	resetAttribute: string?,
	maxUses: number?,
	cooldownSeconds: number?,
	resetSeconds: number?,
}

local placements: { [string]: Placement } = {
	PromptTempSpeedBoost = {
		productKey = "TempSpeedBoost",
		placementId = nil,
	},
	PromptTempWinBoost = {
		productKey = "TempWinBoost",
		placementId = nil,
	},
	ReturnToStage = {
		productKey = "ReturnToStage",
		placementId = nil,
	},
	SpinWheel = {
		productKey = "Spin1",
		placementId = nil,
		remainingAttribute = SPIN_WHEEL_AD_REMAINING_ATTRIBUTE,
		nextAvailableAttribute = SPIN_WHEEL_AD_NEXT_AVAILABLE_ATTRIBUTE,
		resetAttribute = SPIN_WHEEL_AD_RESET_ATTRIBUTE,
		maxUses = SPIN_WHEEL_REWARDED_AD_MAX_SPINS,
		cooldownSeconds = SPIN_WHEEL_REWARDED_AD_COOLDOWN_SECONDS,
		resetSeconds = SPIN_WHEEL_REWARDED_AD_RESET_SECONDS,
	},
}

local configuredPlacements: any = rewardedVideoConfig.placements
if typeof(configuredPlacements) == "table" then
	for placementName, placement in pairs(placements) do
		local rawPlacementId = configuredPlacements[placementName]
		if typeof(rawPlacementId) == "number" and rawPlacementId > 0 then
			placement.placementId = math.floor(rawPlacementId)
		end
	end
end

local isInitialized = false
local serviceMaid = Maid.new()
local requestRemote: RemoteEvent? = nil
local resultRemote: RemoteEvent? = nil
local requestInFlight: { [Player]: boolean } = {}
local requestThreads: { [Player]: thread } = {}
local lastRequestAt: { [Player]: number } = {}

type Reservation = {
	placement: Placement,
	previousRemaining: number,
	previousNextAvailableUnix: number,
	previousResetUnix: number,
}

local reservations: { [Player]: Reservation } = {}

local function getOrCreateRemote(name: string): RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local existing = remotes:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), string.format("%s must be a RemoteEvent", name))
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local function getPlacementState(player: Player, placement: Placement): (number?, number?, number?)
	if not placement.remainingAttribute or not placement.nextAvailableAttribute then
		return nil, nil, nil
	end

	local remaining = player:GetAttribute(placement.remainingAttribute)
	local nextAvailableUnix = player:GetAttribute(placement.nextAvailableAttribute)
	local resetUnix = if placement.resetAttribute then player:GetAttribute(placement.resetAttribute) else nil
	return if typeof(remaining) == "number" then math.max(0, math.floor(remaining)) else nil,
		if typeof(nextAvailableUnix) == "number" then math.max(0, math.floor(nextAvailableUnix)) else nil,
		if typeof(resetUnix) == "number" then math.max(0, math.floor(resetUnix)) else nil
end

local function resetExpiredPlacementQuota(player: Player, placement: Placement, now: number)
	if not placement.resetAttribute or not placement.remainingAttribute then
		return
	end

	local resetUnix = player:GetAttribute(placement.resetAttribute)
	if typeof(resetUnix) ~= "number" or resetUnix <= 0 or now < resetUnix then
		return
	end

	player:SetAttribute(placement.remainingAttribute, placement.maxUses or 0)
	player:SetAttribute(placement.resetAttribute, 0)
	if placement.nextAvailableAttribute then
		local nextAvailableUnix = player:GetAttribute(placement.nextAvailableAttribute)
		if typeof(nextAvailableUnix) ~= "number" or nextAvailableUnix <= now then
			player:SetAttribute(placement.nextAvailableAttribute, 0)
		end
	end
end

local function sendResult(player: Player, placementName: string, completed: boolean, resultName: string)
	if resultRemote and player.Parent then
		local placement = placements[placementName]
		local remaining, nextAvailableUnix, resetUnix =
			if placement then getPlacementState(player, placement) else nil, nil, nil
		if remaining ~= nil then
			resultRemote:FireClient(
				player,
				placementName,
				completed,
				resultName,
				remaining,
				nextAvailableUnix or 0,
				resetUnix or 0
			)
		else
			resultRemote:FireClient(player, placementName, completed, resultName)
		end
	end
end

local function initializePlacementState(player: Player, placement: Placement)
	if not placement.remainingAttribute or not placement.nextAvailableAttribute then
		return
	end

	local currentRemaining = player:GetAttribute(placement.remainingAttribute)
	if typeof(currentRemaining) ~= "number" then
		player:SetAttribute(placement.remainingAttribute, placement.maxUses or 0)
	end

	local currentNextAvailableUnix = player:GetAttribute(placement.nextAvailableAttribute)
	if typeof(currentNextAvailableUnix) ~= "number" then
		player:SetAttribute(placement.nextAvailableAttribute, 0)
	end

	if placement.resetAttribute then
		local currentResetUnix = player:GetAttribute(placement.resetAttribute)
		if typeof(currentResetUnix) ~= "number" then
			player:SetAttribute(placement.resetAttribute, 0)
			currentResetUnix = 0
		end
		if
			typeof(currentRemaining) == "number"
			and currentRemaining <= 0
			and currentResetUnix <= 0
			and placement.maxUses
		then
			-- Migrate the old session-only quota into a fresh daily quota once.
			player:SetAttribute(placement.remainingAttribute, placement.maxUses)
		end
	end

	resetExpiredPlacementQuota(player, placement, os.time())
end

local function initializePlayerState(player: Player)
	for _, placement in pairs(placements) do
		initializePlacementState(player, placement)
	end
end

local function reservePlacementUse(player: Player, placement: Placement): (Reservation?, string?)
	if not placement.remainingAttribute or not placement.nextAvailableAttribute then
		return nil, nil
	end

	initializePlacementState(player, placement)
	local now = os.time()
	resetExpiredPlacementQuota(player, placement, now)
	local remaining, nextAvailableUnix, resetUnix = getPlacementState(player, placement)
	local safeRemaining = remaining or 0
	local safeNextAvailableUnix = nextAvailableUnix or 0
	local safeResetUnix = resetUnix or 0
	if safeRemaining <= 0 then
		return nil, "NoSpinsRemaining"
	end
	if safeNextAvailableUnix > os.time() then
		return nil, "Cooldown"
	end

	local reservation: Reservation = {
		placement = placement,
		previousRemaining = safeRemaining,
		previousNextAvailableUnix = safeNextAvailableUnix,
		previousResetUnix = safeResetUnix,
	}
	player:SetAttribute(placement.remainingAttribute, safeRemaining - 1)
	player:SetAttribute(placement.nextAvailableAttribute, now + math.max(1, math.floor(placement.cooldownSeconds or 0)))
	if placement.resetAttribute and safeResetUnix <= 0 then
		player:SetAttribute(placement.resetAttribute, now + math.max(1, math.floor(placement.resetSeconds or 0)))
	end
	return reservation, nil
end

local function restoreReservation(player: Player)
	local reservation = reservations[player]
	if not reservation or player.Parent == nil then
		reservations[player] = nil
		return
	end

	local placement = reservation.placement
	if placement.remainingAttribute and placement.nextAvailableAttribute then
		player:SetAttribute(placement.remainingAttribute, reservation.previousRemaining)
		player:SetAttribute(placement.nextAvailableAttribute, reservation.previousNextAvailableUnix)
		if placement.resetAttribute then
			player:SetAttribute(placement.resetAttribute, reservation.previousResetUnix)
		end
	end
	reservations[player] = nil
end

local function getShowResultName(result: any): string
	if typeof(result) == "EnumItem" then
		return result.Name
	end
	return tostring(result)
end

local function cancelRequestThread(player: Player)
	restoreReservation(player)
	local requestThread = requestThreads[player]
	if requestThread then
		if coroutine.status(requestThread) ~= "dead" then
			pcall(task.cancel, requestThread)
		end
		requestThreads[player] = nil
	end
	requestInFlight[player] = nil
	lastRequestAt[player] = nil
end

local function handleRequest(player: Player, placementName: any)
	if typeof(placementName) ~= "string" then
		DebugModule.debugWarn("Rejected rewarded video request with invalid placement name", MODULE_NAME)
		return
	end

	local placement = placements[placementName]
	if not ENABLED or not placement then
		sendResult(player, placementName, false, if ENABLED then "UnknownPlacement" else "Disabled")
		return
	end

	if requestInFlight[player] then
		sendResult(player, placementName, false, "RequestInFlight")
		return
	end

	local now = os.clock()
	local lastRequest = lastRequestAt[player] or 0
	if now - lastRequest < REQUEST_COOLDOWN_SECONDS then
		sendResult(player, placementName, false, "Cooldown")
		return
	end

	if placementName == "ReturnToStage" and not ReturnToStageService.PrepareRewardedReturn(player) then
		sendResult(player, placementName, false, "OfferUnavailable")
		return
	end

	local productId = ProductService.DevProducts[placement.productKey]
	if typeof(productId) ~= "number" or productId <= 0 then
		if placementName == "ReturnToStage" then
			ReturnToStageService.CancelRewardedReturn(player)
		end
		sendResult(player, placementName, false, "ProductUnavailable")
		DebugModule.debugWarn("Rewarded video product missing | placement=" .. placementName, MODULE_NAME)
		return
	end

	local reservation, reservationError = reservePlacementUse(player, placement)
	if reservationError then
		sendResult(player, placementName, false, reservationError)
		return
	end

	requestInFlight[player] = true
	lastRequestAt[player] = now
	if reservation then
		reservations[player] = reservation
	end
	local requestThread = task.spawn(function()
		local success, result = pcall(function()
			local reward = AdService:CreateAdRewardFromDevProductId(productId)
			if placement.placementId then
				return AdService:ShowRewardedVideoAdAsync(player, reward, placement.placementId)
			end
			return AdService:ShowRewardedVideoAdAsync(player, reward)
		end)
		local completed = success and result == Enum.ShowAdResult.ShowCompleted

		requestInFlight[player] = nil
		requestThreads[player] = nil
		if not completed then
			restoreReservation(player)
		else
			reservations[player] = nil
		end

		if placementName == "ReturnToStage" and not completed then
			ReturnToStageService.CancelRewardedReturn(player)
		end

		if not success then
			DebugModule.debugWarn(
				"Rewarded video failed | player="
					.. player.Name
					.. " | placement="
					.. placementName
					.. " | error="
					.. tostring(result),
				MODULE_NAME
			)
		end

		sendResult(player, placementName, completed, if success then getShowResultName(result) else "Error")
	end)
	requestThreads[player] = requestThread

	DebugModule.debugInfo(
		"Rewarded video requested | player=" .. player.Name .. " | placement=" .. placementName,
		MODULE_NAME
	)
end

export type RequestResult = {
	success: boolean,
	reason: string,
}

function RewardedVideoService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	local createdRequestRemote = getOrCreateRemote("RewardedVideoRequest")
	local createdResultRemote = getOrCreateRemote("RewardedVideoResult")
	requestRemote = createdRequestRemote
	resultRemote = createdResultRemote
	serviceMaid.Request = createdRequestRemote.OnServerEvent:Connect(handleRequest)
	serviceMaid.PlayerAdded = Players.PlayerAdded:Connect(initializePlayerState)
	serviceMaid.PlayerRemoving = Players.PlayerRemoving:Connect(cancelRequestThread)
	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayerState(player)
	end

	DebugModule.debugInfo("Rewarded video service initialized | enabled=" .. tostring(ENABLED), MODULE_NAME)
end

function RewardedVideoService.IsEnabled(): boolean
	return ENABLED
end

function RewardedVideoService.Request(player: Player, placementId: number?): RequestResult
	if player == nil then
		return { success = false, reason = "InvalidPlayer" }
	end
	if placementId ~= nil and typeof(placementId) ~= "number" then
		return { success = false, reason = "InvalidPlacementId" }
	end
	return { success = ENABLED, reason = if ENABLED then "UseClientRequest" else "Disabled" }
end

function RewardedVideoService.Shutdown()
	if not isInitialized then
		return
	end

	for player in pairs(table.clone(requestThreads)) do
		cancelRequestThread(player)
	end
	for player in pairs(table.clone(reservations)) do
		restoreReservation(player)
	end
	table.clear(requestInFlight)
	table.clear(lastRequestAt)
	table.clear(reservations)
	serviceMaid:DoCleaning()
	requestRemote = nil
	resultRemote = nil
	isInitialized = false
end

return RewardedVideoService
