--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VerifyRewardCalculator = table.clone(require(ReplicatedStorage.Modules:WaitForChild("VerifyRewardCalculator_Client")))

function VerifyRewardCalculator.AdvanceClaimCount(player: Player, config: any): number
	local nextClaimCount = VerifyRewardCalculator.GetClaimCount(player, config) + 1
	player:SetAttribute(config.claimCountAttribute, nextClaimCount)
	return nextClaimCount
end

return VerifyRewardCalculator
