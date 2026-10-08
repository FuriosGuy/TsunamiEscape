--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TreadmillBillboardController = require(ReplicatedStorage.Modules.UI:WaitForChild("TreadmillBillboardController"))
local controller = TreadmillBillboardController.new(Players.LocalPlayer)

local shutDown = false
local function shutdown(): ()
	if shutDown then
		return
	end
	shutDown = true
	controller:Destroy()
end

script.Destroying:Connect(shutdown)
script.AncestryChanged:Connect(function(_, parent: Instance?)
	if parent == nil then
		shutdown()
	end
end)
