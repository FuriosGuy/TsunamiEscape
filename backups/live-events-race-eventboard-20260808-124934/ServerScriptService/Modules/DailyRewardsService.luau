--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local FunnelAnalytics = require(Modules:WaitForChild("FunnelAnalytics"))
local Maid = require(Modules:WaitForChild("Maid"))
local DailyRewardsConfig = require(Modules.UI.MainGUI:WaitForChild("DailyRewardsConfig"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local LevelingService = require(script.Parent:WaitForChild("LevelingService"))
local EconomyAnalytics = require(script.Parent:WaitForChild("EconomyAnalytics"))

local DailyRewardsService = {}

local MODULE_NAME = "DailyRewardsService"
local REQUEST_COOLDOWN_SECONDS = 0.15
local CURRENT_DAY_ATTRIBUTE = DailyRewardsConfig.CURRENT_DAY_ATTRIBUTE
local NEXT_CLAIM_ATTRIBUTE = DailyRewardsConfig.NEXT_CLAIM_ATTRIBUTE
local CYCLE_COUNT_ATTRIBUTE = DailyRewardsConfig.CYCLE_COUNT_ATTRIBUTE
local CLAIM_COOLDOWN_SECONDS = DailyRewardsConfig.CLAIM_COOLDOWN_SECONDS
local DAY_COUNT = DailyRewardsConfig.DAY_COUNT
local dailyRewardsConfig = if CoreConfig.server and CoreConfig.server.dailyRewards
	then CoreConfig.server.dailyRewards
	else nil
local DEBUG_SEQUENTIAL_CLAIM_MODE = RunService:IsStudio()
	and dailyRewardsConfig
	and typeof(dailyRewardsConfig.debugSequentialClaimMode) == "boolean"
	and dailyRewardsConfig.debugSequentialClaimMode == true
local analyticsConfig = if CoreConfig.analytics then CoreConfig.analytics else nil
local analyticsFunnels = if analyticsConfig and typeof(analyticsConfig.funnels) == "table"
	then analyticsConfig.funnels
	else nil
local DAILY_REWARD_FUNNEL_NAME = if analyticsFunnels and typeof(analyticsFunnels.dailyReward) == "string"
	then analyticsFunnels.dailyReward
	else "DailyRewardClaim"
local DAILY_REWARD_CLAIM_ALL_FUNNEL_NAME = if analyticsFunnels
		and typeof(analyticsFunnels.dailyRewardClaimAll) == "string"
	then analyticsFunnels.dailyRewardClaimAll
	else "DailyRewardClaimAll"

type DailyRewardDefinition = DailyRewardsConfig.DailyRewardDefinition

local isInitialized = false
local serviceMaid = Maid.new()
local requestInFlight: { [Player]: boolean } = {}
local lastRequestAt: { [Player]: number } = {}
local claimAllFunnelSessions: { [Player]: string } = {}

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local dailyRewardAction = Remotes:FindFirstChild("DailyRewardAction") :: RemoteEvent?
if not dailyRewardAction then
	local createdRemote = Instance.new("RemoteEvent")
	createdRemote.Name = "DailyRewardAction"
	createdRemote.Parent = Remotes
	dailyRewardAction = createdRemote
end

local XPGainAwarded = Remotes:WaitForChild("XPGainAwarded") :: RemoteEvent
local WinButtonPressed = Remotes:WaitForChild("WinButtonPressed") :: RemoteEvent
local ShowNotification = Remotes:WaitForChild("ShowNotification") :: RemoteEvent

local function sanitizeCurrentDay(rawValue: any): number
	if typeof(rawValue) ~= "number" then
		return 1
	end

	return math.clamp(math.floor(rawValue), 1, DAY_COUNT)
end

local function sanitizeNextClaimUnix(rawValue: any): number
	if typeof(rawValue) ~= "number" then
		return 0
	end

	return math.max(0, math.floor(rawValue))
end

local function sanitizeCycleCount(rawValue: any): number
	if typeof(rawValue) ~= "number" then
		return 0
	end

	return math.max(0, math.floor(rawValue))
end

local function ensurePlayerState(player: Player)
	player:SetAttribute(CURRENT_DAY_ATTRIBUTE, sanitizeCurrentDay(player:GetAttribute(CURRENT_DAY_ATTRIBUTE)))
	player:SetAttribute(NEXT_CLAIM_ATTRIBUTE, sanitizeNextClaimUnix(player:GetAttribute(NEXT_CLAIM_ATTRIBUTE)))
	player:SetAttribute(CYCLE_COUNT_ATTRIBUTE, sanitizeCycleCount(player:GetAttribute(CYCLE_COUNT_ATTRIBUTE)))
end

local function canClaimCurrentReward(player: Player, nowUnix: number): boolean
	if DEBUG_SEQUENTIAL_CLAIM_MODE then
		return true
	end

	local nextClaimUnix = sanitizeNextClaimUnix(player:GetAttribute(NEXT_CLAIM_ATTRIBUTE))
	return nowUnix >= nextClaimUnix
end

local function applyRewardGrant(
	player: Player,
	reward: DailyRewardDefinition,
	cycleCount: number,
	transactionTypeName: string?,
	itemSku: string?
)
	local scaledAmount = DailyRewardsConfig.GetScaledAmount(reward, cycleCount)
	local resolvedTransactionType = transactionTypeName or Enum.AnalyticsEconomyTransactionType.TimedReward.Name
	local resolvedItemSku = itemSku or "DailyReward"

	if reward.kind == "XPSpeed" then
		local awardedAmount = PlayerHandler.AddXPSpeed(player, scaledAmount)
		EconomyAnalytics.LogSource(
			player,
			"XPSpeed",
			awardedAmount,
			resolvedTransactionType,
			resolvedItemSku,
			{ customField01 = reward.kind, customField02 = tostring(cycleCount) }
		)
		XPGainAwarded:FireClient(player, awardedAmount)
		return
	end

	if reward.kind == "Wins" then
		local awardedWins = PlayerHandler.CalculateDailyWinsAward(player, scaledAmount)
		local finalWins = PlayerHandler.AddExactWins(player, awardedWins)
		EconomyAnalytics.LogSource(
			player,
			"Wins",
			finalWins,
			resolvedTransactionType,
			resolvedItemSku,
			{ customField01 = reward.kind, customField02 = tostring(cycleCount) }
		)
		WinButtonPressed:FireClient(player, finalWins, "DailyReward")
		return
	end

	if reward.kind == "Level" then
		PlayerHandler.AddLevels(player, scaledAmount)
		return
	end

	if reward.kind == "Rebirth" then
		for _ = 1, scaledAmount do
			LevelingService.PerformRebirth(player, true)
		end
		return
	end

	DebugModule.debugWarn(
		string.format("Unsupported daily reward kind '%s' for %s", tostring(reward.kind), player.Name),
		MODULE_NAME
	)
end

local function getCurrentDayFields(player: Player)
	return {
		customField01 = tostring(sanitizeCurrentDay(player:GetAttribute(CURRENT_DAY_ATTRIBUTE))),
		customField02 = tostring(sanitizeCycleCount(player:GetAttribute(CYCLE_COUNT_ATTRIBUTE))),
	}
end

local function advanceAfterSingleClaim(player: Player, claimedDay: number, nowUnix: number)
	if claimedDay >= DAY_COUNT then
		local currentCycleCount = sanitizeCycleCount(player:GetAttribute(CYCLE_COUNT_ATTRIBUTE))
		player:SetAttribute(CURRENT_DAY_ATTRIBUTE, 1)
		player:SetAttribute(CYCLE_COUNT_ATTRIBUTE, currentCycleCount + 1)
	else
		player:SetAttribute(CURRENT_DAY_ATTRIBUTE, claimedDay + 1)
	end

	player:SetAttribute(
		NEXT_CLAIM_ATTRIBUTE,
		if DEBUG_SEQUENTIAL_CLAIM_MODE then 0 else nowUnix + CLAIM_COOLDOWN_SECONDS
	)
end

local function resetAfterClaimAll(player: Player, nowUnix: number)
	local currentCycleCount = sanitizeCycleCount(player:GetAttribute(CYCLE_COUNT_ATTRIBUTE))
	player:SetAttribute(CURRENT_DAY_ATTRIBUTE, 1)
	player:SetAttribute(CYCLE_COUNT_ATTRIBUTE, currentCycleCount + 1)
	player:SetAttribute(
		NEXT_CLAIM_ATTRIBUTE,
		if DEBUG_SEQUENTIAL_CLAIM_MODE then 0 else nowUnix + CLAIM_COOLDOWN_SECONDS
	)
end

function DailyRewardsService.ClaimCurrent(player: Player): boolean
	ensurePlayerState(player)

	local nowUnix = os.time()
	local currentDay = sanitizeCurrentDay(player:GetAttribute(CURRENT_DAY_ATTRIBUTE))
	local claimSessionId = FunnelAnalytics.OpenRecurringFunnel(
		player,
		DAILY_REWARD_FUNNEL_NAME,
		"Daily Reward Claim Clicked",
		getCurrentDayFields(player)
	)

	if not canClaimCurrentReward(player, nowUnix) then
		if claimSessionId then
			FunnelAnalytics.LogRecurringStep(
				player,
				DAILY_REWARD_FUNNEL_NAME,
				claimSessionId,
				2,
				"Daily Reward Not Ready",
				getCurrentDayFields(player)
			)
		end
		ShowNotification:FireClient(player, "DAILY REWARD NOT READY!", "Red")
		return false
	end

	local cycleCount = sanitizeCycleCount(player:GetAttribute(CYCLE_COUNT_ATTRIBUTE))
	local reward = DailyRewardsConfig.GetReward(currentDay)
	if not reward then
		return false
	end

	local grantOk, grantError = pcall(function()
		applyRewardGrant(player, reward, cycleCount)
	end)
	if not grantOk then
		DebugModule.debugWarn(
			string.format(
				"Daily reward claim failed | player=%s day=%d err=%s",
				player.Name,
				currentDay,
				tostring(grantError)
			),
			MODULE_NAME
		)
		ShowNotification:FireClient(player, "DAILY REWARD CLAIM FAILED!", "Red")
		return false
	end

	if claimSessionId then
		FunnelAnalytics.LogRecurringStep(
			player,
			DAILY_REWARD_FUNNEL_NAME,
			claimSessionId,
			2,
			"Daily Reward Granted",
			getCurrentDayFields(player)
		)
	end

	advanceAfterSingleClaim(player, currentDay, nowUnix)
	ShowNotification:FireClient(player, "DAILY REWARD CLAIMED!", "Green")
	return true
end

function DailyRewardsService.ClaimAllRemaining(player: Player): boolean
	ensurePlayerState(player)

	local currentDay = sanitizeCurrentDay(player:GetAttribute(CURRENT_DAY_ATTRIBUTE))
	local cycleCount = sanitizeCycleCount(player:GetAttribute(CYCLE_COUNT_ATTRIBUTE))
	local nowUnix = os.time()
	local claimAllSessionId = claimAllFunnelSessions[player]
	if not claimAllSessionId then
		claimAllSessionId = FunnelAnalytics.OpenRecurringFunnel(
			player,
			DAILY_REWARD_CLAIM_ALL_FUNNEL_NAME,
			"Claim All Purchased",
			getCurrentDayFields(player)
		)
	else
		FunnelAnalytics.LogRecurringStep(
			player,
			DAILY_REWARD_CLAIM_ALL_FUNNEL_NAME,
			claimAllSessionId,
			2,
			"Claim All Purchased",
			getCurrentDayFields(player)
		)
	end

	local grantOk, grantError = pcall(function()
		for day = currentDay, DAY_COUNT do
			local reward = DailyRewardsConfig.GetReward(day)
			if reward then
				applyRewardGrant(
					player,
					reward,
					cycleCount,
					Enum.AnalyticsEconomyTransactionType.IAP.Name,
					"DailyRewardClaimAll"
				)
			end
		end
	end)
	if not grantOk then
		DebugModule.debugWarn(
			string.format(
				"Claim all daily rewards failed | player=%s startDay=%d err=%s",
				player.Name,
				currentDay,
				tostring(grantError)
			),
			MODULE_NAME
		)
		ShowNotification:FireClient(player, "CLAIM ALL FAILED!", "Red")
		return false
	end

	if claimAllSessionId then
		FunnelAnalytics.LogRecurringStep(
			player,
			DAILY_REWARD_CLAIM_ALL_FUNNEL_NAME,
			claimAllSessionId,
			if claimAllFunnelSessions[player] then 3 else 2,
			"Claim All Rewards Granted",
			getCurrentDayFields(player)
		)
	end
	claimAllFunnelSessions[player] = nil

	resetAfterClaimAll(player, nowUnix)
	ShowNotification:FireClient(player, "CLAIMED ALL DAILY REWARDS!", "Green")
	return true
end

local function handleClaimAllPromptOpened(player: Player, payload: { [string]: any })
	local currentDay = sanitizeCurrentDay(player:GetAttribute(CURRENT_DAY_ATTRIBUTE))
	local cycleCount = sanitizeCycleCount(player:GetAttribute(CYCLE_COUNT_ATTRIBUTE))
	local sessionId =
		FunnelAnalytics.OpenRecurringFunnel(player, DAILY_REWARD_CLAIM_ALL_FUNNEL_NAME, "Claim All Prompt Opened", {
			customField01 = tostring(currentDay),
			customField02 = tostring(cycleCount),
			customField03 = tostring(payload.source or "DailyRewardsUI"),
		})
	if sessionId then
		claimAllFunnelSessions[player] = sessionId
	end
end

function DailyRewardsService.OnRewardAction(player: Player, action: string)
	if typeof(action) ~= "string" then
		return
	end

	if action ~= "ClaimCurrent" then
		return
	end

	local now = os.clock()
	local lastRequest = lastRequestAt[player] or 0
	if now - lastRequest < REQUEST_COOLDOWN_SECONDS then
		return
	end
	lastRequestAt[player] = now

	if requestInFlight[player] == true then
		return
	end

	requestInFlight[player] = true
	DailyRewardsService.ClaimCurrent(player)
	requestInFlight[player] = nil
end

function DailyRewardsService.OnPlayerAdded(player: Player)
	ensurePlayerState(player)
end

function DailyRewardsService.CleanupPlayer(player: Player)
	requestInFlight[player] = nil
	lastRequestAt[player] = nil
	claimAllFunnelSessions[player] = nil
end

function DailyRewardsService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	serviceMaid.RewardAction = dailyRewardAction.OnServerEvent:Connect(DailyRewardsService.OnRewardAction)
	FunnelAnalytics.RegisterClientAction("DailyRewardClaimAllPromptOpened", handleClaimAllPromptOpened)
	serviceMaid.PlayerRemoving = Players.PlayerRemoving:Connect(DailyRewardsService.CleanupPlayer)
	DebugModule.debugInfo("DailyRewardsService initialized", MODULE_NAME)
end

function DailyRewardsService.Shutdown()
	serviceMaid:DoCleaning()
	table.clear(requestInFlight)
	table.clear(lastRequestAt)
	table.clear(claimAllFunnelSessions)
	isInitialized = false
end

return DailyRewardsService
