--!strict

local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)

local PetPaidRandomItemPolicyService = {}
local MODULE_NAME = "PetPaidRandomItemPolicyService"
local RESTRICTED_ATTRIBUTE = "Pet_PaidRandomItemsRestricted"
local LOADED_ATTRIBUTE = "Pet_RandomItemPolicyLoaded"
local POLICY_ATTEMPTS = 3
local POLICY_RETRY_DELAY_SECONDS = 2

local initialized = false
local alive = true
local playerAddedConnection: RBXScriptConnection? = nil
local playerRemovingConnection: RBXScriptConnection? = nil
local policyThreads: { [Player]: thread } = {}

local function resolvePlayerPolicy(player: Player): ()
	player:SetAttribute(RESTRICTED_ATTRIBUTE, true)
	player:SetAttribute(LOADED_ATTRIBUTE, false)

	local requestThread = task.spawn(function()
		for attempt = 1, POLICY_ATTEMPTS do
			if not alive or player.Parent ~= Players then
				return
			end

			local success, policyInfo = pcall(function()
				return PolicyService:GetPolicyInfoForPlayerAsync(player)
			end)
			if success
				and typeof(policyInfo) == "table"
				and typeof(policyInfo.ArePaidRandomItemsRestricted) == "boolean"
			then
				player:SetAttribute(RESTRICTED_ATTRIBUTE, policyInfo.ArePaidRandomItemsRestricted)
				player:SetAttribute(LOADED_ATTRIBUTE, true)
				policyThreads[player] = nil
				return
			end

			if attempt < POLICY_ATTEMPTS then
				task.wait(POLICY_RETRY_DELAY_SECONDS)
			end
		end

		if player.Parent == Players then
			player:SetAttribute(RESTRICTED_ATTRIBUTE, true)
			player:SetAttribute(LOADED_ATTRIBUTE, true)
			DebugModule.debugWarn("Policy lookup failed after retries; paid random items blocked | player=" .. player.Name, MODULE_NAME)
		end
		policyThreads[player] = nil
	end)
	policyThreads[player] = requestThread
end

function PetPaidRandomItemPolicyService.Init(): ()
	if initialized then
		return
	end
	initialized = true
	alive = true

	for _, player in ipairs(Players:GetPlayers()) do
		resolvePlayerPolicy(player)
	end
	playerAddedConnection = Players.PlayerAdded:Connect(resolvePlayerPolicy)
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		local requestThread = policyThreads[player]
		policyThreads[player] = nil
		if requestThread and coroutine.status(requestThread) ~= "dead" then
			pcall(task.cancel, requestThread)
		end
	end)
end

function PetPaidRandomItemPolicyService.CanUsePaidRandomItems(player: Player): boolean
	return player:GetAttribute(LOADED_ATTRIBUTE) == true and player:GetAttribute(RESTRICTED_ATTRIBUTE) == false
end

function PetPaidRandomItemPolicyService.Destroy(): ()
	if not initialized then
		return
	end
	initialized = false
	alive = false
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	for player, requestThread in pairs(policyThreads) do
		policyThreads[player] = nil
		if coroutine.status(requestThread) ~= "dead" then
			pcall(task.cancel, requestThread)
		end
	end
end

return PetPaidRandomItemPolicyService
