--!strict

export type RewardKind = "Level" | "XPSpeed" | "Wins" | "Rebirth"

export type RewardGrant = {
	kind: RewardKind,
	amount: number,
}

export type RewardTier = {
	id: string,
	unlockSeconds: number,
	rewards: { RewardGrant },
}

local PlaytimeRewardsConfig = {}

PlaytimeRewardsConfig.TOTAL_DURATION_SECONDS = 60 * 60
PlaytimeRewardsConfig.TIER_COUNT = 12
PlaytimeRewardsConfig.PLACEHOLDER_ICON_IMAGE = "rbxassetid://70776298167875"
PlaytimeRewardsConfig.ICON_IMAGE_BY_KIND = table.freeze({
	XPSpeed = "rbxassetid://113466904095935", -- Gift icon XP
	Wins = "rbxassetid://102626472172663", -- Gift icon Wins
	Level = "rbxassetid://113342943009305", -- Gift icon Levels
	Rebirth = "rbxassetid://102895420789840", -- Gift icon Rebirth
})
PlaytimeRewardsConfig.ICON_IMAGE_BY_TIER_ID = table.freeze({
	Gift12 = "rbxassetid://102895420789840", -- Final mixed-reward gift (purple)
})
PlaytimeRewardsConfig.CLAIMED_ICON_IMAGE_BY_KIND = table.freeze({
	XPSpeed = "rbxassetid://125552789489073",
	Wins = "rbxassetid://104709782370430",
	Level = "rbxassetid://106046877471425",
	Rebirth = "rbxassetid://138330067069857",
})
PlaytimeRewardsConfig.CLAIMED_ICON_IMAGE_BY_TIER_ID = table.freeze({
	Gift12 = "rbxassetid://76077537030305", -- Final mixed reward claimed icon
})

local REWARD_TIERS: { RewardTier } = {
	{
		id = "Gift01",
		unlockSeconds = 3 * 60,
		rewards = { { kind = "XPSpeed", amount = 5000 } },
	},
	{
		id = "Gift02",
		unlockSeconds = 5 * 60,
		rewards = { { kind = "Wins", amount = 25 } },
	},
	{
		id = "Gift03",
		unlockSeconds = 10 * 60,
		rewards = { { kind = "Level", amount = 1 } },
	},
	{
		id = "Gift04",
		unlockSeconds = 15 * 60,
		rewards = { { kind = "XPSpeed", amount = 15000 } },
	},
	{
		id = "Gift05",
		unlockSeconds = 20 * 60,
		rewards = { { kind = "Wins", amount = 100 } },
	},
	{
		id = "Gift06",
		unlockSeconds = 25 * 60,
		rewards = { { kind = "Level", amount = 3 } },
	},
	{
		id = "Gift07",
		unlockSeconds = 30 * 60,
		rewards = { { kind = "XPSpeed", amount = 30000 } },
	},
	{
		id = "Gift08",
		unlockSeconds = 35 * 60,
		rewards = { { kind = "Wins", amount = 250 } },
	},
	{
		id = "Gift09",
		unlockSeconds = 40 * 60,
		rewards = { { kind = "Level", amount = 5 } },
	},
	{
		id = "Gift10",
		unlockSeconds = 45 * 60,
		rewards = { { kind = "XPSpeed", amount = 60000 } },
	},
	{
		id = "Gift11",
		unlockSeconds = 50 * 60,
		rewards = { { kind = "Wins", amount = 500 } },
	},
	{
		id = "Gift12",
		unlockSeconds = 60 * 60,
		rewards = {
			{ kind = "XPSpeed", amount = 100000 },
			{ kind = "Wins", amount = 1000 },
			{ kind = "Level", amount = 5 },
		},
	},
}

local tierById: { [string]: RewardTier } = {}

local function validateTiers()
	assert(#REWARD_TIERS == PlaytimeRewardsConfig.TIER_COUNT, "Playtime tier count mismatch")

	local lastUnlock = 0
	for _, tier in ipairs(REWARD_TIERS) do
		assert(tier.id ~= "", "Playtime reward tier id is required")
		assert(tier.unlockSeconds > lastUnlock, "Playtime reward tiers must be strictly increasing by time")
		assert(#tier.rewards > 0, "Each playtime tier must contain at least one reward")

		for _, reward in ipairs(tier.rewards) do
			assert(reward.amount > 0, "Reward amount must be positive")
			if reward.kind == "Level" then
				assert(reward.amount <= 5, "Level reward amount must be <= 5 per tier")
			end
		end

		tierById[tier.id] = tier
		lastUnlock = tier.unlockSeconds
	end

	assert(
		REWARD_TIERS[#REWARD_TIERS].unlockSeconds == PlaytimeRewardsConfig.TOTAL_DURATION_SECONDS,
		"Final playtime tier must land on total duration"
	)
end

validateTiers()

PlaytimeRewardsConfig.TIERS = table.freeze(REWARD_TIERS)

function PlaytimeRewardsConfig.GetTier(index: number): RewardTier?
	return PlaytimeRewardsConfig.TIERS[index]
end

function PlaytimeRewardsConfig.GetTierById(tierId: string): RewardTier?
	return tierById[tierId]
end

function PlaytimeRewardsConfig.GetIconForRewardKind(kind: RewardKind): string
	local iconByKind = PlaytimeRewardsConfig.ICON_IMAGE_BY_KIND
	local icon = iconByKind[kind]
	if typeof(icon) == "string" and icon ~= "" then
		return icon
	end
	return PlaytimeRewardsConfig.PLACEHOLDER_ICON_IMAGE
end

function PlaytimeRewardsConfig.GetIconForTier(tierId: string, fallbackKind: RewardKind): string
	local tierIcon = PlaytimeRewardsConfig.ICON_IMAGE_BY_TIER_ID[tierId]
	if typeof(tierIcon) == "string" and tierIcon ~= "" then
		return tierIcon
	end

	return PlaytimeRewardsConfig.GetIconForRewardKind(fallbackKind)
end

function PlaytimeRewardsConfig.GetClaimedIconForRewardKind(kind: RewardKind): string
	local iconByKind = PlaytimeRewardsConfig.CLAIMED_ICON_IMAGE_BY_KIND
	local icon = iconByKind[kind]
	if typeof(icon) == "string" and icon ~= "" then
		return icon
	end
	return PlaytimeRewardsConfig.PLACEHOLDER_ICON_IMAGE
end

function PlaytimeRewardsConfig.GetClaimedIconForTier(tierId: string, fallbackKind: RewardKind): string
	local tierIcon = PlaytimeRewardsConfig.CLAIMED_ICON_IMAGE_BY_TIER_ID[tierId]
	if typeof(tierIcon) == "string" and tierIcon ~= "" then
		return tierIcon
	end

	return PlaytimeRewardsConfig.GetClaimedIconForRewardKind(fallbackKind)
end

function PlaytimeRewardsConfig.GetNextTierIndex(elapsedSeconds: number): number?
	for index, tier in ipairs(PlaytimeRewardsConfig.TIERS) do
		if elapsedSeconds < tier.unlockSeconds then
			return index
		end
	end

	return nil
end

function PlaytimeRewardsConfig.GetClaimableTierCount(elapsedSeconds: number): number
	local count = 0
	for _, tier in ipairs(PlaytimeRewardsConfig.TIERS) do
		if elapsedSeconds >= tier.unlockSeconds then
			count += 1
		end
	end
	return count
end

return PlaytimeRewardsConfig
