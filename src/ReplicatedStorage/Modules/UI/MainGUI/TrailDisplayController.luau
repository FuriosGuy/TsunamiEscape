local TrailDisplayController = {}

export type RefreshCallback = () -> ()

function TrailDisplayController.CreateOwnedTrailsRefreshHandler(
	updateTrailShop: RefreshCallback,
	refreshAffordableTrailBadge: RefreshCallback
): RefreshCallback
	return function()
		updateTrailShop()
		refreshAffordableTrailBadge()
	end
end

return TrailDisplayController
