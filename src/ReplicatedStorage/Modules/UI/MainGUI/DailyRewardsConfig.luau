--!strict

local DailyRewardsConfig = {}

export type RewardKind = "XPSpeed" | "Wins" | "Level" | "Rebirth"

export type DailyRewardDefinition = {
	day: number,
	kind: RewardKind,
	amount: number,
	topColor: Color3,
	bottomColor: Color3,
	image: string,
}

DailyRewardsConfig.DAY_COUNT = 7
DailyRewardsConfig.CLAIM_COOLDOWN_SECONDS = 24 * 60 * 60
DailyRewardsConfig.CYCLE_SCALE_MULTIPLIER = 1.1
DailyRewardsConfig.CURRENT_DAY_ATTRIBUTE = "DailyRewardCurrentDay"
DailyRewardsConfig.NEXT_CLAIM_ATTRIBUTE = "DailyRewardNextClaimUnix"
DailyRewardsConfig.CYCLE_COUNT_ATTRIBUTE = "DailyRewardCycleCount"

local REWARDS: { DailyRewardDefinition } = table.freeze({
	{
		day = 1,
		kind = "XPSpeed",
		amount = 5000,
		topColor = Color3.fromRGB(255, 78, 78),
		bottomColor = Color3.fromRGB(206, 0, 3),
		image = "rbxassetid://125552789489073",
	},
	{
		day = 2,
		kind = "Wins",
		amount = 100,
		topColor = Color3.fromRGB(254, 199, 41),
		bottomColor = Color3.fromRGB(255, 85, 0),
		image = "rbxassetid://104709782370430",
	},
	{
		day = 3,
		kind = "XPSpeed",
		amount = 10000,
		topColor = Color3.fromRGB(255, 78, 78),
		bottomColor = Color3.fromRGB(206, 0, 3),
		image = "rbxassetid://125552789489073",
	},
	{
		day = 4,
		kind = "Wins",
		amount = 250,
		topColor = Color3.fromRGB(254, 199, 41),
		bottomColor = Color3.fromRGB(255, 85, 0),
		image = "rbxassetid://104709782370430",
	},
	{
		day = 5,
		kind = "Level",
		amount = 5,
		topColor = Color3.fromRGB(88, 216, 255),
		bottomColor = Color3.fromRGB(0, 81, 255),
		image = "rbxassetid://106046877471425",
	},
	{
		day = 6,
		kind = "XPSpeed",
		amount = 25000,
		topColor = Color3.fromRGB(255, 78, 78),
		bottomColor = Color3.fromRGB(206, 0, 3),
		image = "rbxassetid://125552789489073",
	},
	{
		day = 7,
		kind = "Rebirth",
		amount = 1,
		topColor = Color3.fromRGB(227, 74, 255),
		bottomColor = Color3.fromRGB(74, 3, 255),
		image = "rbxassetid://138330067069857",
	},
})

DailyRewardsConfig.REWARDS = REWARDS

function DailyRewardsConfig.GetReward(day: number): DailyRewardDefinition?
	return REWARDS[day]
end

function DailyRewardsConfig.GetScaledAmount(reward: DailyRewardDefinition, cycleCount: number): number
	if reward.kind ~= "XPSpeed" and reward.kind ~= "Wins" then
		return reward.amount
	end

	local safeCycleCount = math.max(0, math.floor(cycleCount))
	return math.round(reward.amount * (DailyRewardsConfig.CYCLE_SCALE_MULTIPLIER ^ safeCycleCount))
end

function DailyRewardsConfig.GetRewardLabel(kind: RewardKind, amount: number): string
	if kind == "XPSpeed" then
		return "SPEED"
	end
	if kind == "Wins" then
		return "WINS"
	end
	if kind == "Level" then
		return if amount == 1 then "LEVEL" else "LEVELS"
	end

	return if amount == 1 then "REBIRTH" else "REBIRTHS"
end

return DailyRewardsConfig
