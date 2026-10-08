--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule_Client"))

local FunnelAnalytics = {}
local MODULE_NAME = "FunnelAnalytics_Client"
local REMOTE_NAME = "FunnelAnalyticsAction"
local MAX_CLIENT_ACTION_NAME_LENGTH = 64
local clientActionRemote: RemoteEvent? = nil

local function getClientActionRemote(): RemoteEvent?
	if clientActionRemote and clientActionRemote.Parent then
		return clientActionRemote
	end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		return nil
	end

	local remote = remotes:FindFirstChild(REMOTE_NAME)
	if remote and remote:IsA("RemoteEvent") then
		clientActionRemote = remote
		return remote
	end

	return nil
end

function FunnelAnalytics.FireClientAction(actionName: string, payload: { [string]: string | number | boolean }?)
	if typeof(actionName) ~= "string" or actionName == "" then
		return
	end

	local remote = getClientActionRemote()
	if not remote then
		DebugModule.debugWarn(
			string.format("Client analytics action skipped; remote missing | action=%s", actionName),
			MODULE_NAME
		)
		return
	end

	remote:FireServer(string.sub(actionName, 1, MAX_CLIENT_ACTION_NAME_LENGTH), payload or {})
end

return FunnelAnalytics
