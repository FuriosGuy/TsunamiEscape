--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientGraphicsService = require(ReplicatedStorage.Modules.ClientGraphicsService)

ClientGraphicsService.Init()

local function shutdown()
	ClientGraphicsService.Shutdown()
end

script.Destroying:Connect(shutdown)
script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		shutdown()
	end
end)
