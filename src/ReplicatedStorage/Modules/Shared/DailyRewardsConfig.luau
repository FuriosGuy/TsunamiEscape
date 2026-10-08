local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)

local DailyRewardsConfig = {}

export type RewardKind = "XPSpeed" | "Wins" | "Level" | "Rebirth" | "LuckyBlockRoll"
export type LuckyBlockRewardGroup = "Premium" | "Tier3"

export type DailyRewardDefinition = {
	day: number,
	kind: RewardKind,
	amount: number,
	levelRequirementPercent: number?,
	currentWinsPercent: number?,
	luckyBlockGroup: LuckyBlockRewardGroup?,
	topColor: Color3,
	bottomColor: Color3,
	gradient: ColorSequence?,
	image: string,
}

DailyRewardsConfig.DAY_COUNT = 7
DailyRewardsConfig.SECONDS_PER_DAY = 24 * 60 * 60
DailyRewardsConfig.MIN_TIMEZONE_OFFSET_MINUTES = -14 * 60
DailyRewardsConfig.MAX_TIMEZONE_OFFSET_MINUTES = 14 * 60
DailyRewardsConfig.CYCLE_SCALE_MULTIPLIER = 1.1
DailyRewardsConfig.CURRENT_DAY_ATTRIBUTE = "DailyRewardCurrentDay"
DailyRewardsConfig.NEXT_CLAIM_ATTRIBUTE = "DailyRewardNextClaimUnix"
DailyRewardsConfig.CYCLE_COUNT_ATTRIBUTE = "DailyRewardCycleCount"

local REWARDS: { DailyRewardDefinition } = table.freeze({
	{
		day = 1,
		kind = "XPSpeed",
		amount = 5000,
		levelRequirementPercent = 0.05,
		topColor = ColorConfig.Colors.Red.Color,
		bottomColor = ColorConfig.Colors.Red.Gradient.Keypoints[2].Value,
		image = "rbxassetid://104159835173600",
	},
	{
		day = 2,
		kind = "Wins",
		amount = 100,
		currentWinsPercent = 0.05,
		topColor = ColorConfig.Colors.WheelGold.Color,
		bottomColor = ColorConfig.Colors.WheelGold.Gradient.Keypoints[2].Value,
		image = "rbxassetid://89376319048073",
	},
	{
		day = 3,
		kind = "XPSpeed",
		amount = 10000,
		levelRequirementPercent = 0.15,
		topColor = ColorConfig.Colors.Red.Color,
		bottomColor = ColorConfig.Colors.Red.Gradient.Keypoints[2].Value,
		image = "rbxassetid://104159835173600",
	},
	{
		day = 4,
		kind = "Wins",
		amount = 250,
		currentWinsPercent = 0.10,
		topColor = ColorConfig.Colors.WheelGold.Color,
		bottomColor = ColorConfig.Colors.WheelGold.Gradient.Keypoints[2].Value,
		image = "rbxassetid://89376319048073",
	},
	{
		day = 5,
		kind = "Level",
		amount = 5,
		topColor = ColorConfig.Colors.Blue.Color,
		bottomColor = ColorConfig.Colors.Blue.Gradient.Keypoints[2].Value,
		image = "rbxassetid://102578932898871",
	},
	{
		day = 6,
		kind = "Rebirth",
		amount = 1,
		topColor = ColorConfig.Colors.Purple.Color,
		bottomColor = ColorConfig.Colors.Purple.Gradient.Keypoints[2].Value,
		image = "rbxassetid://71940044763334",
	},
	{
		day = 7,
		kind = "LuckyBlockRoll",
		amount = 1,
		luckyBlockGroup = "Premium",
		topColor = Color3.new(1, 1, 1),
		bottomColor = ColorConfig.Colors.LuckyBlockPremium.Color,
		gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, ColorConfig.Colors.LuckyBlockPremium.Color),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(1, ColorConfig.Colors.LuckyBlockPremium.Color),
		}),
		image = "",
	},
})

local REPEAT_WEEK_DAY_7_REWARD: DailyRewardDefinition = table.freeze({
	day = 7,
	kind = "LuckyBlockRoll",
	amount = 1,
	luckyBlockGroup = "Tier3",
	topColor = Color3.new(1, 1, 1),
	bottomColor = ColorConfig.Colors.LuckyBlockTier3.Color,
	gradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, ColorConfig.Colors.LuckyBlockTier3.Color),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, ColorConfig.Colors.LuckyBlockTier3.Color),
	}),
	image = "",
})

local REPEAT_PREMIUM_WEEK_DAY_7_REWARD: DailyRewardDefinition = table.freeze({
	day = 7,
	kind = "LuckyBlockRoll",
	amount = 1,
	luckyBlockGroup = "Premium",
	topColor = Color3.new(1, 1, 1),
	bottomColor = ColorConfig.Colors.LuckyBlockPremium.Gradient.Keypoints[2].Value,
	gradient = ColorSequence.new({
		ColorSequenceKeypoint.new(0, ColorConfig.Colors.LuckyBlockPremium.Color),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, ColorConfig.Colors.LuckyBlockPremium.Color),
	}),
	image = "",
})

DailyRewardsConfig.REWARDS = REWARDS

function DailyRewardsConfig.GetReward(day: number, cycleCount: number?): DailyRewardDefinition?
	local safeCycleCount = if typeof(cycleCount) == "number" and cycleCount == cycleCount
		then math.max(0, math.floor(cycleCount))
		else 0
	if day == DailyRewardsConfig.DAY_COUNT then
		if safeCycleCount == 0 then
			return REWARDS[day]
		end
		if safeCycleCount >= 3 and (safeCycleCount - 3) % 4 == 0 then
			return REPEAT_PREMIUM_WEEK_DAY_7_REWARD
		end
		return REPEAT_WEEK_DAY_7_REWARD
	end
	return REWARDS[day]
end

function DailyRewardsConfig.GetScaledAmount(reward: DailyRewardDefinition, cycleCount: number): number
	if reward.kind ~= "XPSpeed" and reward.kind ~= "Wins" then
		return reward.amount
	end

	local safeCycleCount = math.max(0, math.floor(cycleCount))
	return math.round(reward.amount * (DailyRewardsConfig.CYCLE_SCALE_MULTIPLIER ^ safeCycleCount))
end

function DailyRewardsConfig.GetLocalDayKey(unixTimestamp: number, timezoneOffsetMinutes: number): number
	local safeTimestamp = if typeof(unixTimestamp) == "number" and unixTimestamp == unixTimestamp
		then unixTimestamp
		else 0
	local safeOffset = math.clamp(
		math.round(timezoneOffsetMinutes),
		DailyRewardsConfig.MIN_TIMEZONE_OFFSET_MINUTES,
		DailyRewardsConfig.MAX_TIMEZONE_OFFSET_MINUTES
	)
	return math.floor((safeTimestamp + safeOffset * 60) / DailyRewardsConfig.SECONDS_PER_DAY)
end

function DailyRewardsConfig.GetNextLocalResetUnix(unixTimestamp: number, timezoneOffsetMinutes: number): number
	local safeOffset = math.clamp(
		math.round(timezoneOffsetMinutes),
		DailyRewardsConfig.MIN_TIMEZONE_OFFSET_MINUTES,
		DailyRewardsConfig.MAX_TIMEZONE_OFFSET_MINUTES
	)
	local currentDayKey = DailyRewardsConfig.GetLocalDayKey(unixTimestamp, safeOffset)
	return (currentDayKey + 1) * DailyRewardsConfig.SECONDS_PER_DAY - safeOffset * 60
end

function DailyRewardsConfig.GetRewardAmount(
	reward: DailyRewardDefinition,
	cycleCount: number,
	maxXPSpeed: number?,
	currentWins: number?
): number
	local baseAmount = DailyRewardsConfig.GetScaledAmount(reward, cycleCount)
	if reward.kind == "Wins" then
		local percentage = reward.currentWinsPercent
		if typeof(percentage) ~= "number" or percentage <= 0 then
			return baseAmount
		end

		local safeCurrentWins = if typeof(currentWins) == "number"
				and currentWins == currentWins
				and currentWins ~= math.huge
				and currentWins ~= -math.huge
			then math.max(0, currentWins)
			else 0
		local percentageAmount = math.round(safeCurrentWins * percentage)
		return math.max(baseAmount, percentageAmount)
	end

	if reward.kind ~= "XPSpeed" then
		return baseAmount
	end

	local percentage = reward.levelRequirementPercent
	if typeof(percentage) ~= "number" or percentage <= 0 then
		return baseAmount
	end

	local requiredXP = if typeof(maxXPSpeed) == "number"
			and maxXPSpeed == maxXPSpeed
			and maxXPSpeed ~= math.huge
			and maxXPSpeed ~= -math.huge
		then math.max(0, maxXPSpeed)
		else 0

	return baseAmount + math.round(requiredXP * percentage)
end

function DailyRewardsConfig.GetRewardLabel(
	kind: RewardKind,
	amount: number,
	luckyBlockGroup: LuckyBlockRewardGroup?
): string
	if kind == "XPSpeed" then
		return "SPEED"
	end
	if kind == "Wins" then
		return "WINS"
	end
	if kind == "Level" then
		return if amount == 1 then "LEVEL" else "LEVELS"
	end
	if kind == "LuckyBlockRoll" then
		if luckyBlockGroup == "Premium" then
			return "PREMIUM LUCKY BLOCK"
		elseif luckyBlockGroup == "Tier3" then
			return "TIER 3 LUCKY BLOCK"
		end
		return "LUCKY BLOCK"
	end

	return if amount == 1 then "REBIRTH" else "REBIRTHS"
end

return DailyRewardsConfig
