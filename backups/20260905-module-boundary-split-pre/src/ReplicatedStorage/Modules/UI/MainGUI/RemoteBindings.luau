--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductService = require(ReplicatedStorage.Modules.ProductService)

type MaidLike = {
	GiveTask: (self: MaidLike, task: any) -> any,
}

export type BindContext = {
	remotes: Instance,
	sessionMaid: MaidLike,
	localPlayer: Player,
	onXPGainAwarded: (amount: number) -> (),
	onWinAwarded: (amount: number, source: string?) -> (),
	onVerifyRewardResult: (success: boolean, nextClaimUnix: number?) -> (),
	onRebirthResult: () -> (),
	onShowNotification: (message: string, themeName: string?, notificationStyle: string?) -> (),
	onReturnToStageOffer: (shouldShow: boolean, stage: number?, duration: number?) -> (),
	onOpenVerifyFrameRequested: () -> (),
	onTriggerJumpscare: () -> (),
	onTrackedPlayerRemoving: (removingPlayer: Player) -> (),
	onLocalCharacterAdded: () -> (),
	onRequestReturnToStageOffer: () -> (),
	onPromptProductPurchaseFinished: (productId: number, wasPurchased: boolean) -> (),
	onPromptReturnToStageDeclined: (productId: number, wasPurchased: boolean) -> (),
}

local RemoteBindings = {}

function RemoteBindings.Bind(context: BindContext)
	local remotes = context.remotes
	local sessionMaid = context.sessionMaid

	local winRemote = remotes:WaitForChild("WinButtonPressed") :: RemoteEvent
	local bloodmoonWinRemote = remotes:WaitForChild("BloodmoonWinAwarded") :: RemoteEvent
	local xpRemote = remotes:WaitForChild("XPGainAwarded") :: RemoteEvent
	local verifyResultRemote = remotes:WaitForChild("VerifyRewardResult") :: RemoteEvent
	local rebirthResultRemote = remotes:WaitForChild("RebirthResult") :: RemoteEvent
	local showNotificationRemote = remotes:WaitForChild("ShowNotification") :: RemoteEvent
	local returnToStageOfferRemote = remotes:WaitForChild("ReturnToStageOffer") :: RemoteEvent
	local openVerifyFrameRemote = remotes:WaitForChild("OpenVerifyFrame") :: RemoteEvent
	local triggerJumpscareRemote = remotes:WaitForChild("TriggerJumpscare") :: RemoteEvent

	sessionMaid:GiveTask(xpRemote.OnClientEvent:Connect(context.onXPGainAwarded))
	sessionMaid:GiveTask(winRemote.OnClientEvent:Connect(context.onWinAwarded))
	sessionMaid:GiveTask(bloodmoonWinRemote.OnClientEvent:Connect(function(amount: number)
		context.onWinAwarded(amount, "BloodmoonWin")
	end))
	sessionMaid:GiveTask(verifyResultRemote.OnClientEvent:Connect(context.onVerifyRewardResult))
	sessionMaid:GiveTask(rebirthResultRemote.OnClientEvent:Connect(context.onRebirthResult))
	sessionMaid:GiveTask(showNotificationRemote.OnClientEvent:Connect(context.onShowNotification))
	sessionMaid:GiveTask(returnToStageOfferRemote.OnClientEvent:Connect(context.onReturnToStageOffer))
	sessionMaid:GiveTask(openVerifyFrameRemote.OnClientEvent:Connect(context.onOpenVerifyFrameRequested))
	sessionMaid:GiveTask(triggerJumpscareRemote.OnClientEvent:Connect(context.onTriggerJumpscare))

	sessionMaid:GiveTask(Players.PlayerRemoving:Connect(context.onTrackedPlayerRemoving))
	sessionMaid:GiveTask(context.localPlayer.CharacterAdded:Connect(context.onLocalCharacterAdded))
	sessionMaid:GiveTask(task.defer(context.onRequestReturnToStageOffer))

	sessionMaid:GiveTask(MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, productId, wasPurchased)
		context.onPromptProductPurchaseFinished(productId, wasPurchased)
	end))
	sessionMaid:GiveTask(ProductService.ConnectCreatorPurchaseFinished(function(
		purchaseKind: string,
		productId: number,
		wasPurchased: boolean,
		_reason: string
	)
		if purchaseKind == "Product" then
			context.onPromptProductPurchaseFinished(productId, wasPurchased)
		end
	end))
	sessionMaid:GiveTask(MarketplaceService.PromptProductPurchaseFinished:Connect(function(_, productId, wasPurchased)
		context.onPromptReturnToStageDeclined(productId, wasPurchased)
	end))
end

return RemoteBindings
