local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SystemChatService =
	require(game:GetService("ServerScriptService").Modules.Shared:WaitForChild("SystemChatService_Server"))

SystemChatService.InitServer()
