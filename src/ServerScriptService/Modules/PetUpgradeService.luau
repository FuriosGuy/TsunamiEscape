--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local ProductService = require(ServerScriptService.Modules.Shared:WaitForChild("ProductService_Server"))
local ProductServerService = require(ServerScriptService.Modules:WaitForChild("ProductServerService"))
local PetPaidRandomItemPolicyService = require(ServerScriptService.Modules:WaitForChild("PetPaidRandomItemPolicyService"))

local PetUpgradeService = {}
local MODULE_NAME = "PetUpgradeService"

local function readCapacity(player: Player, attributeName: string, defaultValue: number): number
	local value = player:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return defaultValue
	end

	return math.floor(value)
end

local function registerUpgradeProduct(
	productKey: string,
	grant: (player: Player) -> boolean,
	requiresPaidRandomItemsPermission: boolean?
): ()
	local productId = ProductService.DevProducts[productKey]
	if typeof(productId) ~= "number" or productId <= 0 then
		return
	end

	ProductServerService.SetProductCallback(productId, function(player: Player): boolean
		if player:GetAttribute("Data_Loaded") ~= true then
			return false
		end
		if requiresPaidRandomItemsPermission == true
			and not PetPaidRandomItemPolicyService.CanUsePaidRandomItems(player)
		then
			DebugModule.debugWarn(
				"Luck upgrade receipt deferred by paid-random-item policy | player="
					.. player.Name
					.. " | productKey="
					.. productKey,
				MODULE_NAME
			)
			return false
		end

		return grant(player)
	end)
end

function PetUpgradeService.RegisterCallbacks()
	local upgradeConfig = PetConfig.Upgrades
	local equipCapacityAttribute = "Pet_EquipSlotCapacity"
	local backpackCapacityAttribute = "Pet_BackpackCapacity"
	local luckMultiplierAttribute = "Pet_LuckMultiplier"

	registerUpgradeProduct("PetEquipSlotPlusThree", function(player)
		local capacity = readCapacity(player, equipCapacityAttribute, PetConfig.Equip.startingSlots)
		player:SetAttribute(equipCapacityAttribute, capacity + upgradeConfig.equipSlotsPerPurchase)
		return true
	end)

	registerUpgradeProduct("PetBackpackSlotPlusFifteen", function(player)
		local capacity = readCapacity(player, backpackCapacityAttribute, PetConfig.Storage.startingCapacity)
		player:SetAttribute(backpackCapacityAttribute, capacity + upgradeConfig.backpackSlotsPerPurchase)
		return true
	end)

	for _, tier in ipairs(upgradeConfig.luckMultiplier.tiers) do
		local targetMultiplier = tier.multiplier
		local productKey = tier.productKey
		registerUpgradeProduct(productKey, function(player)
			local currentValue = player:GetAttribute(luckMultiplierAttribute)
			local currentMultiplier = if typeof(currentValue) == "number" and currentValue == currentValue
				then math.clamp(currentValue, upgradeConfig.luckMultiplier.startingMultiplier, 10)
				else upgradeConfig.luckMultiplier.startingMultiplier
			if targetMultiplier <= currentMultiplier then
				DebugModule.debugWarn(
					"Consumed duplicate Luck tier receipt without changing owned tier | player="
						.. player.Name
						.. " | productKey="
						.. productKey,
					MODULE_NAME
				)
				return true
			end

			local nextMultiplier = upgradeConfig.luckMultiplier.startingMultiplier
			local currentTierKnown = currentMultiplier == nextMultiplier
			for _, configuredTier in ipairs(upgradeConfig.luckMultiplier.tiers) do
				if configuredTier.multiplier == currentMultiplier then
					currentTierKnown = true
				end
				if configuredTier.multiplier > currentMultiplier then
					nextMultiplier = configuredTier.multiplier
					break
				end
			end
			if not currentTierKnown or targetMultiplier ~= nextMultiplier then
				DebugModule.debugWarn(
					"Luck tier receipt held until preceding tier is granted | player="
						.. player.Name
						.. " | current="
						.. tostring(currentMultiplier)
						.. " | requested="
						.. tostring(targetMultiplier),
					MODULE_NAME
				)
				return false
			end

			player:SetAttribute(luckMultiplierAttribute, targetMultiplier)
			return true
		end, true)
	end
end

return PetUpgradeService
