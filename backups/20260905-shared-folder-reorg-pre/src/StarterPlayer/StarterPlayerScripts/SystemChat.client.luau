--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SystemChatService = require(ReplicatedStorage.Modules.SystemChatService_Client)

SystemChatService.InitClient()

script.Destroying:Connect(function()
	SystemChatService.ShutdownClient()
end)

script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		SystemChatService.ShutdownClient()
	end
end)
