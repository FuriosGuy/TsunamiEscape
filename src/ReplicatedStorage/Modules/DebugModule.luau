local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CoreConfig = if RunService:IsServer()
	then require(game:GetService("ServerScriptService").Modules.Shared:WaitForChild("CoreConfig_Server"))
	else require(ReplicatedStorage.Modules.Shared:WaitForChild("CoreConfig_Client"))
local DebugModuleCore = require(ReplicatedStorage.Modules:WaitForChild("DebugModuleCore"))

return DebugModuleCore.new(function()
	return CoreConfig.debugSystem
end)
