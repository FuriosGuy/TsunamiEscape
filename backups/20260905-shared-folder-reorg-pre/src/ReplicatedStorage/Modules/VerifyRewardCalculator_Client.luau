--!strict
local VerifyRewardCalculator = {}

export type VerifyRewardConfig = {
	baseXP: number,
	baseWins: number,
	growthMultiplier: number,
	roundStep: number,
	claimCountAttribute: string,
}

export type VerifyRewardPreview = {
	claimCount: number,
	growthFactor: number,
	baseXP: number,
	baseWins: number,
	xpAward: number,
	winsAward: number,
}

local DEFAULT_BASE_XP = 5000
local DEFAULT_BASE_WINS = 50
local DEFAULT_GROWTH_MULTIPLIER = 1.1
local DEFAULT_ROUND_STEP = 5
local DEFAULT_CLAIM_COUNT_ATTRIBUTE = "VerifyRewardClaimCount"

local function sanitizePositiveNumber(value: any, fallback: number): number
	if typeof(value) ~= "number" then
		return fallback
	end

	if value <= 0 then
		return fallback
	end

	return value
end

local function getNumericAttribute(player: Player, attributeName: string, fallback: number): number
	local rawValue = player:GetAttribute(attributeName)
	if typeof(rawValue) == "number" then
		return rawValue
	end

	return fallback
end

local function roundUpToStep(value: number, step: number): number
	if value <= 0 then
		return 0
	end

	return math.ceil(value / step) * step
end

function VerifyRewardCalculator.GetConfig(coreConfig: any): VerifyRewardConfig
	local levelingConfig = if coreConfig then coreConfig.leveling else nil
	local baseXP = sanitizePositiveNumber(
		if levelingConfig then levelingConfig.verifyRewardXP else nil,
		DEFAULT_BASE_XP
	)
	local baseWins = sanitizePositiveNumber(
		if levelingConfig then levelingConfig.verifyRewardWins else nil,
		DEFAULT_BASE_WINS
	)
	local growthMultiplier = sanitizePositiveNumber(
		if levelingConfig then levelingConfig.verifyRewardDailyGrowthMultiplier else nil,
		DEFAULT_GROWTH_MULTIPLIER
	)
	local roundStep = math.max(
		1,
		math.floor(
			sanitizePositiveNumber(
				if levelingConfig then levelingConfig.verifyRewardRoundStep else nil,
				DEFAULT_ROUND_STEP
			)
		)
	)
	local claimCountAttribute = if levelingConfig and typeof(levelingConfig.verifyRewardClaimCountAttribute) == "string"
			and levelingConfig.verifyRewardClaimCountAttribute ~= ""
		then levelingConfig.verifyRewardClaimCountAttribute
		else DEFAULT_CLAIM_COUNT_ATTRIBUTE

	return {
		baseXP = baseXP,
		baseWins = baseWins,
		growthMultiplier = growthMultiplier,
		roundStep = roundStep,
		claimCountAttribute = claimCountAttribute,
	}
end

function VerifyRewardCalculator.GetClaimCount(player: Player, config: VerifyRewardConfig): number
	local rawValue = player:GetAttribute(config.claimCountAttribute)
	if typeof(rawValue) == "number" then
		return math.max(0, math.floor(rawValue))
	end

	return 0
end

function VerifyRewardCalculator.ComputeRewardsForNextClaim(
	player: Player,
	config: VerifyRewardConfig
): VerifyRewardPreview
	local claimCount = VerifyRewardCalculator.GetClaimCount(player, config)
	local growthFactor = math.pow(config.growthMultiplier, claimCount + 1)
	local baseXP = config.baseXP * growthFactor
	local baseWins = config.baseWins * growthFactor

	local rebirthMultiplier = getNumericAttribute(player, "Rebirth_XPMultiplier", 1)
	local devMultiplier = getNumericAttribute(player, "DevProduct_XPSpeedMultiplier", 1)
	local miscMultiplier = getNumericAttribute(player, "Misc_XPSpeedMultiplier", 1)
	local friendMultiplier = getNumericAttribute(player, "Friend_XPMultiplier", 1)
	local treadmillMultiplier = getNumericAttribute(player, "Treadmill_XPMultiplier", 1)
	local winMultiplier = getNumericAttribute(player, "WinMultiplier", 1)

	local effectiveXP = baseXP * rebirthMultiplier * devMultiplier * miscMultiplier * friendMultiplier * treadmillMultiplier
	local effectiveWins = baseWins * winMultiplier

	return {
		claimCount = claimCount,
		growthFactor = growthFactor,
		baseXP = baseXP,
		baseWins = baseWins,
		xpAward = roundUpToStep(effectiveXP, config.roundStep),
		winsAward = roundUpToStep(effectiveWins, config.roundStep),
	}
end

return VerifyRewardCalculator
