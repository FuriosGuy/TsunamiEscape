--!strict

-- The reward table is intentionally shared with the client for previews.
-- This server wrapper keeps server consumers on the server config boundary.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpinWheelConfig = require(ReplicatedStorage.Modules.Config:WaitForChild("SpinWheelConfig_Client"))

export type RewardId = SpinWheelConfig.RewardId
export type RewardDefinition = SpinWheelConfig.RewardDefinition
export type PurchasePack = SpinWheelConfig.PurchasePack

return SpinWheelConfig
