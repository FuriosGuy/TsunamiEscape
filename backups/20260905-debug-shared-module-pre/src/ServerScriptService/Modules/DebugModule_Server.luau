--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CoreConfig = require(ServerScriptService.Modules.Config:WaitForChild("CoreConfig_Server"))
local DebugModuleCore = require(ReplicatedStorage.Modules:WaitForChild("DebugModuleCore"))

return DebugModuleCore.new(function()
	return CoreConfig.debugSystem
end)
