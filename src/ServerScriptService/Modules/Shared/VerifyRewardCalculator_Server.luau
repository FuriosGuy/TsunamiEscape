local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VerifyRewardCalculator = require(ReplicatedStorage.Modules.Shared:WaitForChild("VerifyRewardCalculator"))

function VerifyRewardCalculator.AdvanceClaimCount(player: Player, config: any): number
	local nextClaimCount = VerifyRewardCalculator.GetClaimCount(player, config) + 1
	player:SetAttribute(config.claimCountAttribute, nextClaimCount)
	return nextClaimCount
end

return VerifyRewardCalculator
