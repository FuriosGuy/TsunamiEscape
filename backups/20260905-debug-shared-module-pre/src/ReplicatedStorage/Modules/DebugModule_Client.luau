--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Config:WaitForChild("CoreConfig_Client"))
local DebugModuleCore = require(ReplicatedStorage.Modules:WaitForChild("DebugModuleCore"))

return DebugModuleCore.new(function()
	return CoreConfig.debugSystem
end)
