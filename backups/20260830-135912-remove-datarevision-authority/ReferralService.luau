--!strict
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local ProductService = require(Modules:WaitForChild("ProductService"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local FunnelAnalytics = require(Modules:WaitForChild("FunnelAnalytics"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local ProductServerService = require(script.Parent:WaitForChild("ProductServerService"))

local ReferralService = {}

local MODULE_NAME = "ReferralService"
local socialConfig = CoreConfig.social
local FRIEND_INVITE_MULTIPLIER_STEP = if socialConfig
		and typeof(socialConfig.friendInviteMultiplierStep) == "number"
	then math.max(0, socialConfig.friendInviteMultiplierStep)
	else 0.1
local analyticsConfig = if CoreConfig.analytics then CoreConfig.analytics else nil
local analyticsFunnels = if analyticsConfig and typeof(analyticsConfig.funnels) == "table"
	then analyticsConfig.funnels
	else nil
local REFERRAL_FUNNEL_NAME = if analyticsFunnels and typeof(analyticsFunnels.referral) == "string"
	then analyticsFunnels.referral
	else "FriendInviteConversion"
local FRIEND_INVITE_PROMPT_FUNNEL_NAME = if analyticsFunnels
		and typeof(analyticsFunnels.friendInvitePrompt) == "string"
	then analyticsFunnels.friendInvitePrompt
	else "FriendInvitePrompt"

local friendReferralClaimsStore = DataStoreService:GetDataStore(ProductService.DataStores["FriendReferralClaims"])
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ShowNotification = Remotes:WaitForChild("ShowNotification") :: RemoteEvent

local function normalizeUserId(value: any): number?
	if typeof(value) ~= "number" then
		return nil
	end

	local userId = math.floor(value)
	if userId <= 0 then
		return nil
	end

	return userId
end

local function tryClaimReferralReward(inviteeUserId: number, referrerUserId: number): boolean
	local claimedReferral = false
	local success, err = pcall(function()
		friendReferralClaimsStore:UpdateAsync(tostring(inviteeUserId), function(existingValue)
			if existingValue ~= nil then
				return existingValue
			end

			claimedReferral = true
			return referrerUserId
		end)
	end)

	if not success then
		DebugModule.debugWarn(
			string.format(
				"Failed to claim referral reward | invitee=%d | referrer=%d | err=%s",
				inviteeUserId,
				referrerUserId,
				tostring(err)
			),
			MODULE_NAME
		)
		return false
	end

	return claimedReferral
end

local function incrementOfflineReferrerCount(referrerUserId: number): boolean
	for attempt = 1, 3 do
		local success = ProductServerService.UpdateStoredPlayerData(referrerUserId, function(nextData)
			local currentCount = nextData.FriendInviteCount
			if typeof(currentCount) ~= "number" then
				currentCount = 0
			end
			nextData.FriendInviteCount = math.max(0, math.floor(currentCount)) + 1
			return nextData
		end)
		if success then
			return true
		end
		if attempt < 3 then
			task.wait(attempt)
		end
	end

	DebugModule.debugWarn(
		"Offline referral update exhausted retries; claim remains recorded | referrer=" .. tostring(referrerUserId),
		MODULE_NAME
	)
	return false
end

local function grantReferralReward(referrerUserId: number): boolean
	local referrerPlayer = Players:GetPlayerByUserId(referrerUserId)
	if referrerPlayer then
		PlayerHandler.AddFriendInviteCount(referrerPlayer, 1)
		ShowNotification:FireClient(
			referrerPlayer,
			string.format("FRIEND JOINED! +%.2fx FRIENDS MULTIPLIER", FRIEND_INVITE_MULTIPLIER_STEP),
			"Green"
		)
		ProductServerService.SavePlayerData(referrerPlayer)
		return true
	end

	return incrementOfflineReferrerCount(referrerUserId)
end

local function grantInviteeReward(inviteePlayer: Player)
	PlayerHandler.AddFriendInviteCount(inviteePlayer, 1)
	ShowNotification:FireClient(
		inviteePlayer,
		string.format("FRIEND INVITE BONUS! +%.2fx FRIENDS MULTIPLIER", FRIEND_INVITE_MULTIPLIER_STEP),
		"Green"
	)
	ProductServerService.SavePlayerData(inviteePlayer)
end

function ReferralService.OnPlayerAdded(player: Player)
	local joinData = player:GetJoinData()
	local referrerUserId = normalizeUserId(joinData.ReferredByPlayerId)
	if referrerUserId == nil or referrerUserId == player.UserId then
		return
	end

	if not tryClaimReferralReward(player.UserId, referrerUserId) then
		return
	end

	local referralSessionId =
		FunnelAnalytics.OpenRecurringFunnel(player, REFERRAL_FUNNEL_NAME, "Referral Join Detected", {
			customField01 = "InviteeJoined",
		})

	grantInviteeReward(player)
	if referralSessionId then
		FunnelAnalytics.LogRecurringStep(player, REFERRAL_FUNNEL_NAME, referralSessionId, 2, "Invitee Reward Granted", {
			customField01 = "InviteeReward",
		})
	end

	if grantReferralReward(referrerUserId) then
		if referralSessionId then
			FunnelAnalytics.LogRecurringStep(
				player,
				REFERRAL_FUNNEL_NAME,
				referralSessionId,
				3,
				"Referrer Reward Granted",
				{
					customField01 = "ReferrerReward",
				}
			)
		end
		DebugModule.debugInfo(
			string.format(
				"Referral rewards granted | invitee=%s(%d) | referrer=%d | step=%.2f",
				player.Name,
				player.UserId,
				referrerUserId,
				FRIEND_INVITE_MULTIPLIER_STEP
			),
			MODULE_NAME
		)
	end
end

local function handleInvitePromptOpened(player: Player, payload: { [string]: any })
	local sessionId =
		FunnelAnalytics.OpenRecurringFunnel(player, FRIEND_INVITE_PROMPT_FUNNEL_NAME, "Invite Prompt Opened", {
			customField01 = tostring(payload.source or "Topbar"),
		})
	if sessionId then
		FunnelAnalytics.LogRecurringStep(
			player,
			FRIEND_INVITE_PROMPT_FUNNEL_NAME,
			sessionId,
			2,
			"Invite Prompt Displayed",
			{
				customField01 = tostring(payload.source or "Topbar"),
			}
		)
	end
end

function ReferralService.Init()
	FunnelAnalytics.RegisterClientAction("FriendInvitePromptOpened", handleInvitePromptOpened)
	DebugModule.debugInfo("ReferralService initialized", MODULE_NAME)
end

return ReferralService
