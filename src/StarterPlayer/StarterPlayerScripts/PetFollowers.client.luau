--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PetFollowerController = require(ReplicatedStorage.Modules.UI.PetFollowerController)

PetFollowerController.Init()

local shutDown = false
local function shutdown(): ()
	if shutDown then
		return
	end
	shutDown = true
	PetFollowerController.Shutdown()
end

script.Destroying:Connect(shutdown)
script.AncestryChanged:Connect(function(_, parent: Instance?)
	if parent == nil then
		shutdown()
	end
end)
