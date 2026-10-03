local Players = game:GetService("Players")
local UISizeAdjuster = require(script.UISizeAdjuster)

local player = Players.LocalPlayer

local function tryTagGui(instance: Instance)
	if instance:IsA("ScreenGui") then
		UISizeAdjuster:TagScreenGui(instance)
	elseif instance:IsA("BillboardGui") then
		UISizeAdjuster:TagBillboardGui(instance)
	end
end

local function initializeUIAdjuster()
	for _, child in ipairs(player.PlayerGui:GetChildren()) do
		tryTagGui(child)
	end

	for _, descendant in ipairs(workspace:GetDescendants()) do
		tryTagGui(descendant)
	end
end

initializeUIAdjuster()

workspace.DescendantAdded:Connect(function(descendant)
	tryTagGui(descendant)
end)

player.PlayerGui.DescendantAdded:Connect(function(descendant)
	tryTagGui(descendant)
end)
