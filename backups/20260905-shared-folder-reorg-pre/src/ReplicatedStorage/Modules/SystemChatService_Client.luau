--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")

local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))

local SystemChatService = {}
local MODULE_NAME = "SystemChatService_Client"
local REMOTE_NAME = "GlobalSystemChat"
local clientConnection: RBXScriptConnection? = nil

local function getRemote(): RemoteEvent?
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		or ReplicatedStorage:WaitForChild("Remotes", 10)
	if not remotes then
		return nil
	end

	local remote = remotes:FindFirstChild(REMOTE_NAME)
		or remotes:WaitForChild(REMOTE_NAME, 10)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	return nil
end

local function displayMessage(formattedMessage: string)
	local textChannels = TextChatService:FindFirstChild("TextChannels")
		or TextChatService:WaitForChild("TextChannels", 10)
	local generalChannel = textChannels and (textChannels:FindFirstChild("RBXGeneral")
		or textChannels:WaitForChild("RBXGeneral", 10))

	if generalChannel and generalChannel:IsA("TextChannel") then
		generalChannel:DisplaySystemMessage(formattedMessage)
		return
	end

	local success, errorMessage = pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = formattedMessage:gsub("<[^>]->", ""),
			Color = Color3.fromRGB(254, 200, 42),
		})
	end)
	if not success then
		DebugModule.debugWarn("No available chat channel for system chat: " .. tostring(errorMessage), MODULE_NAME)
	end
end

function SystemChatService.InitClient()
	if clientConnection then
		return
	end

	local remote = getRemote()
	if not remote then
		DebugModule.debugWarn("Global system chat remote missing", MODULE_NAME)
		return
	end

	clientConnection = remote.OnClientEvent:Connect(function(formattedMessage: any)
		if typeof(formattedMessage) == "string" then
			displayMessage(formattedMessage)
		end
	end)
end

function SystemChatService.ShutdownClient()
	if clientConnection then
		clientConnection:Disconnect()
		clientConnection = nil
	end
end

return SystemChatService
