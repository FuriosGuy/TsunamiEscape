local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local ProductService = require(Modules:WaitForChild("Shared"):WaitForChild("ProductService_Client"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local purchasePrompt = remotes:WaitForChild("PurchasePrompt") :: RemoteEvent
local localPlayer = Players.LocalPlayer

purchasePrompt.OnClientEvent:Connect(function(purchaseType: string, productId: number)
	if
		(purchaseType ~= "Product" and purchaseType ~= "GamePass")
		or typeof(productId) ~= "number"
		or productId <= 0
	then
		DebugModule.debugWarn("Rejected invalid purchase prompt request", "PurchasePromptClient")
		return
	end

	if purchaseType == "Product" then
		ProductService.promptProductPurchase(localPlayer, math.floor(productId))
	else
		ProductService.promptGamePassPurchase(localPlayer, math.floor(productId))
	end
end)
