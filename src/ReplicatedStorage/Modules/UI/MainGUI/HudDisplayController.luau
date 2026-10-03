local DebugModule = require(game:GetService("ReplicatedStorage").Modules.DebugModule)

local HudDisplayController = {}
HudDisplayController.__index = HudDisplayController

type ControllerOptions = {
	player: Player,
	visualFunctions: any,
	playerHandler: any,
	levelDisplayController: any,
	winDisplayController: any,
	refreshRebirthReadyState: () -> (),
	defaultPlayerSpeed: number,
	defaultMaxPlayerSpeed: number,
}

type Controller = {
	player: Player,
	visualFunctions: any,
	playerHandler: any,
	levelDisplayController: any,
	winDisplayController: any,
	refreshRebirthReadyState: () -> (),
	defaultPlayerSpeed: number,
	defaultMaxPlayerSpeed: number,
	lastAllXP: number,
	alive: boolean,
}

local function getNumberAttribute(player: Player, attributeName: string, fallback: number): number
	local value = player:GetAttribute(attributeName)
	return if typeof(value) == "number" then value else fallback
end

function HudDisplayController.new(options: ControllerOptions): Controller
	return setmetatable({
		player = options.player,
		visualFunctions = options.visualFunctions,
		playerHandler = options.playerHandler,
		levelDisplayController = options.levelDisplayController,
		winDisplayController = options.winDisplayController,
		refreshRebirthReadyState = options.refreshRebirthReadyState,
		defaultPlayerSpeed = options.defaultPlayerSpeed,
		defaultMaxPlayerSpeed = options.defaultMaxPlayerSpeed,
		lastAllXP = getNumberAttribute(options.player, "AllXPSpeed", 0),
		alive = true,
	}, HudDisplayController) :: Controller
end

function HudDisplayController:UpdateXPProductLabels()
	if not self.alive then
		return
	end

	local devMultiplier = getNumberAttribute(self.player, "DevProduct_XPSpeedMultiplier", 1)
	DebugModule.debugPrint(string.format("updateXPProductLabels - DevMult=%.1f", devMultiplier), "MainOrchestrator")

	local mappings = {
		{ label = self.visualFunctions.Labels.Xp100KValueLabel, value = 100000, name = "100K" },
		{ label = self.visualFunctions.Labels.Xp1MValueLabel, value = 1000000, name = "1M" },
		{ label = self.visualFunctions.Labels.Xp10MValueLabel, value = 10000000, name = "10M" },
	}

	for _, entry in ipairs(mappings) do
		local label = entry.label
		if label then
			if label:IsA("TextLabel") or label:IsA("TextButton") then
				local oldText = label.Text
				label.Text = "+" .. self.visualFunctions.FormatNumber(entry.value * devMultiplier)
				DebugModule.debugPrint(
					string.format("Updated %s Label: %s -> %s", entry.name, oldText, label.Text),
					"MainOrchestrator"
				)
			else
				DebugModule.debugPrint(
					string.format("Label for %s exists but is NOT a TextLabel/TextButton", entry.name),
					"MainOrchestrator"
				)
			end
		else
			DebugModule.debugPrint(
				string.format("Label for %s is MISSING from mappings", entry.name),
				"MainOrchestrator"
			)
		end
	end
end

function HudDisplayController:UpdateTrailMultiplierDisplay()
	if not self.alive then
		return
	end

	local equippedTrail = self.player:GetAttribute("Trail_Equipped")
	if typeof(equippedTrail) ~= "string" or equippedTrail == "" or equippedTrail == "None" then
		self.visualFunctions.UpdateTrailMultiplierLabel(nil, nil, nil, nil)
		return
	end

	local trailConfig = self.playerHandler.GetTrailConfig(equippedTrail)
	if not trailConfig then
		self.visualFunctions.UpdateTrailMultiplierLabel(nil, nil, nil, nil)
		return
	end

	self.visualFunctions.UpdateTrailMultiplierLabel(
		equippedTrail,
		trailConfig.XPMultiplier,
		trailConfig.BackgroundColor,
		trailConfig.GradientBottomColor
	)
end

function HudDisplayController:UpdateUI()
	if not self.alive then
		return
	end

	local currentXP = getNumberAttribute(self.player, "CurrentXPSpeed", 0)
	local maxXP = getNumberAttribute(self.player, "MaxXPSpeed", 25)
	local level = getNumberAttribute(self.player, "CurrentLevel", 1)
	local maxLevel = getNumberAttribute(self.player, "MaxLevel", 25)
	local rebirthMultiplier = getNumberAttribute(self.player, "Rebirth_XPMultiplier", 1)
	local friendMultiplier = getNumberAttribute(self.player, "Friend_XPMultiplier", 1)
	local totalXP = getNumberAttribute(self.player, "AllXPSpeed", 0)
	local maxSpeed = self.playerHandler.GetEffectiveMaxPlayerSpeed(self.player)

	self.visualFunctions.UpdateXPLabel(currentXP, maxXP)
	self.visualFunctions.UpdateXPProgressBar(currentXP, maxXP)
	self.visualFunctions.UpdateLevelProgressBar(level, maxLevel)
	self.visualFunctions.UpdateLevelNeededLabel(level, maxLevel)
	self.visualFunctions.UpdateLevelLabel(level, maxLevel)
	self.visualFunctions.UpdateRebirthMultiLabel(rebirthMultiplier)
	self.visualFunctions.UpdateFriendMultiplierLabel(friendMultiplier)
	self:UpdateTrailMultiplierDisplay()
	self.visualFunctions.UpdateAllXPLabel(totalXP)
	self.visualFunctions.UpdateMaxSpeedLabel(maxSpeed)
	self.levelDisplayController:SyncState(level, maxSpeed)
	self.refreshRebirthReadyState()

	local customSpeedTextBox = self.visualFunctions.HUD.CustomSpeedTextBox
	if customSpeedTextBox then
		customSpeedTextBox.PlaceholderText = tostring(maxSpeed)
		if not customSpeedTextBox:IsFocused() then
			customSpeedTextBox.Text = tostring(self.playerHandler.GetEffectiveWalkSpeed(self.player))
		end
	end

	self.lastAllXP = totalXP
	local nextStats = self.playerHandler.GetNextRebirthStats(self.player)
	self.visualFunctions.UpdateRebirthPreview(
		rebirthMultiplier,
		nextStats.NextMultiplier,
		maxLevel,
		nextStats.NextMaxLevel
	)
	self.winDisplayController:SetDisplayedWinCount(getNumberAttribute(self.player, "WinCount", 0))
end

function HudDisplayController:UpdateAllXPDisplay()
	if not self.alive then
		return
	end

	self.lastAllXP = getNumberAttribute(self.player, "AllXPSpeed", 0)
	self.visualFunctions.UpdateAllXPLabel(self.lastAllXP)
end

function HudDisplayController:UpdateXPDisplay()
	if not self.alive then
		return
	end

	local currentXP = getNumberAttribute(self.player, "CurrentXPSpeed", 0)
	local maxXP = getNumberAttribute(self.player, "MaxXPSpeed", 25)
	self.visualFunctions.UpdateXPLabel(currentXP, maxXP)
	self.visualFunctions.UpdateXPProgressBar(currentXP, maxXP)
end

function HudDisplayController:GetUpdateUIHandler(): () -> ()
	return function()
		self:UpdateUI()
	end
end

function HudDisplayController:GetUpdateXPProductLabelsHandler(): () -> ()
	return function()
		self:UpdateXPProductLabels()
	end
end

function HudDisplayController:GetUpdateTrailMultiplierHandler(): () -> ()
	return function()
		self:UpdateTrailMultiplierDisplay()
	end
end

function HudDisplayController:GetUpdateAllXPHandler(): () -> ()
	return function()
		self:UpdateAllXPDisplay()
	end
end

function HudDisplayController:GetUpdateXPHandler(): () -> ()
	return function()
		self:UpdateXPDisplay()
	end
end

function HudDisplayController:Destroy()
	if not self.alive then
		return
	end

	self.alive = false
	self.levelDisplayController = nil
	self.winDisplayController = nil
	self.refreshRebirthReadyState = function() end
end

return HudDisplayController
