local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BloodmoonParticleService = require(ReplicatedStorage.Modules.BloodmoonParticleService)
local Maid = require(ReplicatedStorage.Modules.Maid)

local controller = BloodmoonParticleService.new(Players.LocalPlayer)
controller:Start()

local lifecycleMaid = Maid.new()
local cleaned = false
local function cleanup()
	if cleaned then
		return
	end
	cleaned = true
	lifecycleMaid:DoCleaning()
end

lifecycleMaid:GiveTask(function()
	controller:Destroy()
end)
lifecycleMaid:GiveTask(script.AncestryChanged:Connect(function(_, parent: Instance?)
	if parent == nil then
		cleanup()
	end
end))
