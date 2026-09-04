--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerHandler = require(ReplicatedStorage.Modules.PlayerHandler)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

local DisplayRefreshBindings = {}

local DEFAULT_PLAYER_SPEED = if typeof(PlayerHandler.DEFAULT_ATTRIBUTES.Player_Speed) == "number"
	then PlayerHandler.DEFAULT_ATTRIBUTES.Player_Speed
	else 16

type MaidLike = {
	GiveTask: (self: MaidLike, task: any) -> any,
}

type BindOptions = {
	player: Player,
	sessionMaid: MaidLike,
	updateUI: () -> (),
	updateXPProductLabels: () -> (),
	updateVerifyRewardValueLabels: () -> (),
	updateMultiplierShop: () -> (),
	updateX2WinShop: () -> (),
	updateShopButtons: () -> (),
	updateKartShop: () -> (),
	updateTrailMultiplierDisplay: () -> (),
}

function DisplayRefreshBindings.Bind(options: BindOptions)
	local function bind(attributeName: string, callback: () -> ())
		options.sessionMaid:GiveTask(options.player:GetAttributeChangedSignal(attributeName):Connect(callback))
	end

	local function updateRebirthAndProductDisplay()
		options.updateUI()
		options.updateXPProductLabels()
		options.updateVerifyRewardValueLabels()
	end

	local function updateDevProductDisplay()
		options.updateMultiplierShop()
		options.updateXPProductLabels()
		options.updateVerifyRewardValueLabels()
	end

	local function updateMiscMultiplierDisplay()
		options.updateXPProductLabels()
		options.updateTrailMultiplierDisplay()
		options.updateVerifyRewardValueLabels()
	end

	local function updateFriendMultiplierDisplay()
		local friendMultiplier = options.player:GetAttribute("Friend_XPMultiplier") or 1
		VisualFunctions.UpdateFriendMultiplierLabel(friendMultiplier)
		options.updateVerifyRewardValueLabels()
	end

	local function updateWinMultiplierDisplay()
		options.updateX2WinShop()
		options.updateXPProductLabels()
		options.updateShopButtons()
		options.updateKartShop()
		options.updateVerifyRewardValueLabels()
	end

	local function updatePlayerSpeedDisplay()
		local speedTextBox = VisualFunctions.HUD.CustomSpeedTextBox
		if speedTextBox then
			speedTextBox.PlaceholderText = tostring(PlayerHandler.GetEffectiveMaxPlayerSpeed(options.player))
			if not speedTextBox:IsFocused() then
				speedTextBox.Text = tostring(PlayerHandler.GetEffectiveWalkSpeed(options.player))
			end
		end
	end

	bind("MaxLevel", updateRebirthAndProductDisplay)
	bind("Rebirth_XPMultiplier", updateRebirthAndProductDisplay)
	bind("DevProduct_XPSpeedMultiplier", updateDevProductDisplay)
	bind("Misc_XPSpeedMultiplier", updateMiscMultiplierDisplay)
	bind("Friend_XPMultiplier", updateFriendMultiplierDisplay)
	bind("WinMultiplier", updateWinMultiplierDisplay)
	bind("Player_Speed", updatePlayerSpeedDisplay)
	bind("LiveEvent_WalkSpeedMultiplier", options.updateUI)
end

return DisplayRefreshBindings
