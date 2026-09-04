--!strict

local SpinWheelConfig = {}

export type RewardId = "SpeedSmall" | "SpeedLarge" | "Wins" | "Rebirth" | "FlameTrail" | "FlameKart"

export type RewardDefinition = {
	id: RewardId,
	frameName: string,
	chance: number,
	displayName: string,
}

export type PurchasePack = {
	buttonName: string,
	productKey: string,
	spins: number,
}

SpinWheelConfig.Rewards = {
	{ id = "SpeedSmall", frameName = "Reward_SpeedSmall", chance = 35, displayName = "+SPEED" },
	{ id = "SpeedLarge", frameName = "Reward_SpeedLarge", chance = 20, displayName = "+BIG SPEED" },
	{ id = "Wins", frameName = "Reward_Wins", chance = 20, displayName = "+WINS" },
	{ id = "Rebirth", frameName = "Reward_Rebirth", chance = 15, displayName = "+1 REBIRTH" },
	{ id = "FlameTrail", frameName = "Reward_FlameTrail", chance = 7, displayName = "FLAME TRAIL" },
	{ id = "FlameKart", frameName = "Reward_FlameKart", chance = 3, displayName = "FLAME KART" },
} :: { RewardDefinition }

SpinWheelConfig.PurchasePacks = {
	{ buttonName = "Buy1SpinButtonFrame", productKey = "Spin1", spins = 1 },
	{ buttonName = "Buy3SpinButtonFrame", productKey = "Spin3", spins = 3 },
	{ buttonName = "Buy5SpinButtonFrame", productKey = "Spin5", spins = 5 },
	{ buttonName = "Buy10SpinButtonFrame", productKey = "Spin10", spins = 10 },
} :: { PurchasePack }

function SpinWheelConfig.GetReward(rewardId: string): RewardDefinition?
	for _, reward in ipairs(SpinWheelConfig.Rewards) do
		if reward.id == rewardId then
			return reward
		end
	end
	return nil
end

function SpinWheelConfig.GetWheelWinsBase(totalWins: number): number
	local wins = math.max(0, totalWins)
	local multiplier = 1
	if wins >= 100000 then
		multiplier = 0.1
	elseif wins >= 10000 then
		multiplier = 0.25
	elseif wins >= 1000 then
		multiplier = 0.5
	end

	return math.max(100, math.round(wins * multiplier))
end

function SpinWheelConfig.GetSmallSpeedBase(currentXPSpeed: number, maxXPSpeed: number): number
	return math.max(1, math.round(maxXPSpeed - currentXPSpeed))
end

return SpinWheelConfig
