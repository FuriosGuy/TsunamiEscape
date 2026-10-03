local AdService = game:GetService("AdService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)

local RewardedVideoClient = {}

local MODULE_NAME = "RewardedVideoClient"
local rewardedVideoConfig: any = CoreConfig.rewardedVideo or {}
local ENABLED = rewardedVideoConfig.enabled ~= false
local remotes = ReplicatedStorage:WaitForChild("Remotes")

export type ResultCallback = (
	placementName: string,
	completed: boolean,
	resultName: string,
	remainingUses: number?,
	nextAvailableUnix: number?,
	resetUnix: number?
) -> ()

local function getRemote(name: string): RemoteEvent
	local remote = remotes:WaitForChild(name)
	assert(remote:IsA("RemoteEvent"), string.format("%s must be a RemoteEvent", name))
	return remote
end

function RewardedVideoClient.IsAvailable(): boolean
	if not ENABLED or RunService:IsStudio() then
		return false
	end

	local success, result = pcall(function()
		return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
	end)
	if not success or typeof(result) ~= "table" then
		DebugModule.debugWarn("Rewarded video availability check failed: " .. tostring(result), MODULE_NAME)
		return false
	end

	return (result :: any).AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable
end

function RewardedVideoClient.Request(placementName: string): boolean
	if not ENABLED or typeof(placementName) ~= "string" or placementName == "" then
		return false
	end

	if not RewardedVideoClient.IsAvailable() then
		DebugModule.debugInfo("Rewarded video unavailable | placement=" .. placementName, MODULE_NAME)
		return false
	end

	local success, err = pcall(function()
		getRemote("RewardedVideoRequest"):FireServer(placementName)
	end)
	if not success then
		DebugModule.debugWarn(
			"Rewarded video request failed | placement=" .. placementName .. " | error=" .. tostring(err),
			MODULE_NAME
		)
		return false
	end

	return true
end

function RewardedVideoClient.ConnectResult(callback: ResultCallback): RBXScriptConnection
	return getRemote("RewardedVideoResult").OnClientEvent:Connect(callback)
end

return RewardedVideoClient
