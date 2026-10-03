local DailyRewardPromptController = {}
DailyRewardPromptController.__index = DailyRewardPromptController

type ControllerOptions = {
	player: Player,
	badgeState: {
		buttonFrame: GuiObject?,
		template: GuiObject?,
		badge: GuiObject?,
		refresh: (() -> ())?,
	},
	updateButtonNotificationBadge: (any, boolean, string, string) -> (),
	getDailyRewardFrame: () -> Frame?,
	closeOtherFrames: (Frame?) -> (),
	openWindow: (Frame) -> (),
	canAutoOpen: (() -> boolean)?,
}

function DailyRewardPromptController.new(options: ControllerOptions)
	local self = setmetatable({}, DailyRewardPromptController)

	self.player = options.player
	self.badgeState = options.badgeState
	self.updateButtonNotificationBadge = options.updateButtonNotificationBadge
	self.getDailyRewardFrame = options.getDailyRewardFrame
	self.closeOtherFrames = options.closeOtherFrames
	self.openWindow = options.openWindow
	self.canAutoOpen = options.canAutoOpen
	self.isClaimable = false
	self.didAutoOpen = false
	self.lightRay = options.badgeState.buttonFrame
		and options.badgeState.buttonFrame:FindFirstChild("LightRay")
	if self.lightRay and self.lightRay:IsA("GuiObject") then
		self.lightRay.Visible = false
	else
		self.lightRay = nil
	end

	return self
end

function DailyRewardPromptController:RefreshBadge()
	local dailyButtonFrame = self.badgeState.buttonFrame
	local dataLoaded = self.player:GetAttribute("Data_Loaded") == true
	local dailyButtonLabel = dailyButtonFrame and dailyButtonFrame:FindFirstChild("TextLabel", true)
	if dailyButtonLabel and dailyButtonLabel:IsA("TextLabel") then
		dailyButtonLabel.Text = if self.isClaimable then "CLAIM" else "DAILY"
	end

	if self.lightRay and self.lightRay.Parent then
		self.lightRay.Visible = dataLoaded and self.isClaimable
	end

	if not dataLoaded then
		self.updateButtonNotificationBadge(self.badgeState, false, "DailyClaimableNotification", "0")
		return
	end

	self.updateButtonNotificationBadge(
		self.badgeState,
		self.isClaimable,
		"DailyClaimableNotification",
		if self.isClaimable then "1" else "0"
	)
end

function DailyRewardPromptController:TryAutoOpen()
	if self.didAutoOpen then
		return
	end

	if self.canAutoOpen and not self.canAutoOpen() then
		return
	end

	if self.player:GetAttribute("Data_Loaded") ~= true then
		return
	end

	if not self.isClaimable then
		return
	end

	if self.player:GetAttribute("TutorialCompleted") ~= true then
		return
	end

	local dailyRewardFrame = self.getDailyRewardFrame()
	if not dailyRewardFrame then
		return
	end

	self.didAutoOpen = true
	task.spawn(function()
		self.closeOtherFrames(dailyRewardFrame)
		if not dailyRewardFrame.Visible then
			self.openWindow(dailyRewardFrame)
		end
	end)
end

function DailyRewardPromptController:HandleClaimableChanged(isClaimable: boolean)
	self.isClaimable = isClaimable
	self:RefreshBadge()
	self:TryAutoOpen()
end

function DailyRewardPromptController:OnTutorialCompletedChanged()
	self:TryAutoOpen()
end

function DailyRewardPromptController:Reset()
	self.badgeState.refresh = nil
	self.isClaimable = false
	self.didAutoOpen = false
	if self.lightRay and self.lightRay.Parent then
		self.lightRay.Visible = false
	end
	self.updateButtonNotificationBadge(self.badgeState, false, "DailyClaimableNotification", "0")
end

return DailyRewardPromptController
