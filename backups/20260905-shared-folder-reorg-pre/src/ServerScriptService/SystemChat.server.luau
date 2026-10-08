--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SystemChatService = require(game:GetService("ServerScriptService").Modules:WaitForChild("SystemChatService_Server"))

SystemChatService.InitServer()
