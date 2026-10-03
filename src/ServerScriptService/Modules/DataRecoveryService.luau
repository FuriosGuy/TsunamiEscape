--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))
local ProductServerService = require(script.Parent:WaitForChild("ProductServerService"))

local DataRecoveryService = {}

local MODULE_NAME = "DataRecoveryService"
local MAX_RECOVERY_ATTEMPTS = 3
local REQUEST_COOLDOWN_SECONDS = 1

type RetryHandler = (player: Player) -> (boolean, string?)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local requestRemote: RemoteEvent? = nil
local resultRemote: RemoteEvent? = nil
local requestConnection: RBXScriptConnection? = nil
local playerAddedConnection: RBXScriptConnection? = nil
local playerRemovingConnection: RBXScriptConnection? = nil
local recoveryAttempts: { [Player]: number } = {}
local retryAttempts: { [Player]: number } = {}
local resetAttempts: { [Player]: number } = {}
local lastRequestAt: { [Player]: number } = {}
local recoveryRequestsInFlight: { [Player]: boolean } = {}
local retryHandler: RetryHandler? = nil

local function getOrCreateRemote(name: string): RemoteEvent
	local existing = remotes:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), name .. " must be a RemoteEvent")
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local function initializePlayer(player: Player)
	recoveryAttempts[player] = 0
	retryAttempts[player] = 0
	resetAttempts[player] = 0
	lastRequestAt[player] = nil
	recoveryRequestsInFlight[player] = nil
	player:SetAttribute("DataRecoveryAttempts", 0)
end

local function cleanupPlayer(player: Player)
	recoveryAttempts[player] = nil
	retryAttempts[player] = nil
	resetAttempts[player] = nil
	lastRequestAt[player] = nil
	recoveryRequestsInFlight[player] = nil
end

local function sendResult(player: Player, success: boolean, attempts: number, message: string)
	if resultRemote and player.Parent ~= nil then
		resultRemote:FireClient(player, success, attempts, message)
	end
end

local function recordRecoveryAttempt(player: Player): number
	local attempts = (recoveryAttempts[player] or 0) + 1
	recoveryAttempts[player] = attempts
	player:SetAttribute("DataRecoveryAttempts", attempts)
	return attempts
end

local function handleRequest(player: Player, action: any)
	if typeof(action) ~= "string" then
		return
	end
	if player:GetAttribute("Data_LoadState") ~= "RecoveryRequired" then
		return
	end

	local now = os.clock()
	local lastRequest = lastRequestAt[player]
	if lastRequest ~= nil and now - lastRequest < REQUEST_COOLDOWN_SECONDS then
		return
	end
	lastRequestAt[player] = now

	if action ~= "Retry" and action ~= "Reset" then
		return
	end

	if recoveryRequestsInFlight[player] then
		return
	end

	local actionAttempts = if action == "Retry" then retryAttempts[player] or 0 else resetAttempts[player] or 0
	if actionAttempts >= MAX_RECOVERY_ATTEMPTS then
		sendResult(player, false, recoveryAttempts[player] or 0, "Attempt limit reached. Please rejoin and try again.")
		return
	end

	local attempts = recordRecoveryAttempt(player)
	recoveryRequestsInFlight[player] = true

	if action == "Retry" then
		retryAttempts[player] = actionAttempts + 1
		if retryHandler == nil then
			recoveryRequestsInFlight[player] = nil
			sendResult(player, false, attempts, "Retry is not available yet. Please rejoin and try again.")
			return
		end

		local retryOk, retrySucceeded, retryMessage = pcall(retryHandler, player)
		recoveryRequestsInFlight[player] = nil
		if retryOk and retrySucceeded then
			sendResult(player, true, attempts, "Your data loaded successfully.")
			return
		end

		DebugModule.debugWarn(
			"Recovery load retry failed | player="
				.. player.Name
				.. " | attempt="
				.. tostring(attempts)
				.. " | err="
				.. tostring(if retryOk then retryMessage else retrySucceeded),
			MODULE_NAME
		)
		sendResult(
			player,
			false,
			attempts,
			if retryOk and typeof(retryMessage) == "string"
				then retryMessage
				else "Retry failed safely. Your data was not changed."
		)
		return
	end

	resetAttempts[player] = actionAttempts + 1
	local resetSucceeded = ProductServerService.ResetRecoveryProfile(player)
	recoveryRequestsInFlight[player] = nil
	if resetSucceeded then
		player:Kick("Your profile was reset safely. Please rejoin.")
		return
	end

	DebugModule.debugWarn(
		"Recovery reset request failed | player=" .. player.Name .. " | attempt=" .. tostring(attempts),
		MODULE_NAME
	)
	sendResult(player, false, attempts, "Reset failed safely. Your data was not changed. Please try again or rejoin.")
end

function DataRecoveryService.SetRetryHandler(handler: RetryHandler?)
	retryHandler = handler
end

function DataRecoveryService.RecordInitialRecoveryAttempt(player: Player)
	if player.Parent == nil or player:GetAttribute("Data_LoadState") ~= "RecoveryRequired" then
		return
	end
	if (recoveryAttempts[player] or 0) == 0 then
		recordRecoveryAttempt(player)
	end
end

function DataRecoveryService.Init()
	if requestConnection ~= nil then
		return
	end

	requestRemote = getOrCreateRemote("DataRecoveryRequest")
	resultRemote = getOrCreateRemote("DataRecoveryResult")
	requestConnection = requestRemote.OnServerEvent:Connect(handleRequest)
	playerAddedConnection = Players.PlayerAdded:Connect(initializePlayer)
	playerRemovingConnection = Players.PlayerRemoving:Connect(cleanupPlayer)

	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayer(player)
	end
end

function DataRecoveryService.Shutdown()
	if requestConnection then
		requestConnection:Disconnect()
		requestConnection = nil
	end
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end

	requestRemote = nil
	resultRemote = nil
	retryHandler = nil
	recoveryAttempts = {}
	retryAttempts = {}
	resetAttempts = {}
	lastRequestAt = {}
	recoveryRequestsInFlight = {}
end

return DataRecoveryService
