local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("DebugModule"))
local ProductService = require(game:GetService("ServerScriptService").Modules.Shared:WaitForChild("ProductService_Server"))
local CoreConfig = require(game:GetService("ServerScriptService").Modules.Shared:WaitForChild("CoreConfig_Server"))
local ProductServerService = require(script.Parent.ProductServerService)

local TemporaryBoostService = {}

local MODULE_NAME = "TemporaryBoostService"
local temporaryBoostConfig: any = CoreConfig.temporaryBoosts or {}
local PURCHASE_DURATION_SECONDS =
	math.max(1, math.floor(tonumber(temporaryBoostConfig.purchaseDurationSeconds) or (10 * 60)))
local REWARDED_AD_DURATION_SECONDS =
	math.max(1, math.floor(tonumber(temporaryBoostConfig.rewardedAdDurationSeconds) or (5 * 60)))
local SPEED_END_ATTRIBUTE = "TemporarySpeedBoostEndUnix"
local WIN_END_ATTRIBUTE = "TemporaryWinBoostEndUnix"

local initialized = false

local function grantBoost(player: Player, endAttributeName: string, durationSeconds: number): number
	local now = os.time()
	local currentEnd = player:GetAttribute(endAttributeName)
	local existingEnd = if typeof(currentEnd) == "number" then currentEnd else 0
	local newEnd = math.max(now, existingEnd) + durationSeconds

	player:SetAttribute(endAttributeName, newEnd)
	DebugModule.debugInfo(
		string.format(
			"Granted temporary boost | player=%s | attribute=%s | endUnix=%d | addedSeconds=%d",
			player.Name,
			endAttributeName,
			newEnd,
			durationSeconds
		),
		MODULE_NAME
	)

	return newEnd
end

function TemporaryBoostService.GrantSpeedBoost(player: Player, durationSeconds: number): number
	return grantBoost(player, SPEED_END_ATTRIBUTE, math.max(1, math.floor(durationSeconds)))
end

function TemporaryBoostService.GrantWinBoost(player: Player, durationSeconds: number): number
	return grantBoost(player, WIN_END_ATTRIBUTE, math.max(1, math.floor(durationSeconds)))
end

function TemporaryBoostService.Init()
	if initialized then
		return
	end
	initialized = true

	ProductServerService.SetProductCallback(
		ProductService.DevProducts.TempSpeedBoost,
		function(player: Player, _: number?, _: boolean?, _: string?, purchaseChannel: EnumItem?)
			local durationSeconds = if purchaseChannel == Enum.ProductPurchaseChannel.AdReward
				then REWARDED_AD_DURATION_SECONDS
				else PURCHASE_DURATION_SECONDS
			grantBoost(player, SPEED_END_ATTRIBUTE, durationSeconds)
		end
	)

	ProductServerService.SetProductCallback(
		ProductService.DevProducts.TempWinBoost,
		function(player: Player, _: number?, _: boolean?, _: string?, purchaseChannel: EnumItem?)
			local durationSeconds = if purchaseChannel == Enum.ProductPurchaseChannel.AdReward
				then REWARDED_AD_DURATION_SECONDS
				else PURCHASE_DURATION_SECONDS
			grantBoost(player, WIN_END_ATTRIBUTE, durationSeconds)
		end
	)

	DebugModule.debugInfo("Temporary boost products registered", MODULE_NAME)
end

return TemporaryBoostService
