--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local Maid = require(Modules:WaitForChild("Maid"))
local FunnelAnalytics = require(Modules:WaitForChild("Shared"):WaitForChild("FunnelAnalytics_Client"))
local CoreConfig = require(Modules:WaitForChild("Shared"):WaitForChild("CoreConfig_Client"))
local VisualFunctions = require(Modules:WaitForChild("UI"):WaitForChild("VisualFunctions"))
local ColorConfig = require(Modules:WaitForChild("Config"):WaitForChild("ColorConfig"))

local FriendMultiplierUI = {}
FriendMultiplierUI.__index = FriendMultiplierUI

type FriendMultiplierUIObject = {
	screenGui: ScreenGui,
	player: Player,
	maid: any,
	frame: GuiObject?,
	promptButton: GuiButton?,
	inviteFriendButton: GuiButton?,
	multiplierLabel: TextLabel?,
	plusLabel: TextLabel?,
	initialized: boolean,
	alive: boolean,
	lastPromptAt: number,
	promptInvite: (self: FriendMultiplierUIObject, source: string) -> (),
	Init: (self: FriendMultiplierUIObject) -> (),
	Destroy: (self: FriendMultiplierUIObject) -> (),
}

local MODULE_NAME = "FriendMultiplierUI"
local INVITE_DEBOUNCE_SECONDS = 1.5
local PLUS_COLOR = ColorConfig.UI.NotificationThemes.Green.textColor

local function showClientNotification(message: string)
	local success, err = pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Invite Friends",
			Text = message,
			Duration = 4,
		})
	end)
	if not success then
		DebugModule.debugWarn("Failed to show invite notification: " .. tostring(err), MODULE_NAME)
	end
end

function FriendMultiplierUI.new(screenGui: ScreenGui): FriendMultiplierUIObject
	local player = assert(Players.LocalPlayer, "FriendMultiplierUI requires a local player")

	return setmetatable({
		screenGui = screenGui,
		player = player,
		maid = Maid.new(),
		frame = nil,
		promptButton = nil,
		inviteFriendButton = nil,
		multiplierLabel = nil,
		plusLabel = nil,
		initialized = false,
		alive = true,
		lastPromptAt = -math.huge,
	}, FriendMultiplierUI) :: FriendMultiplierUIObject
end

function FriendMultiplierUI:promptInvite(source: string)
	if not self.alive or os.clock() - self.lastPromptAt < INVITE_DEBOUNCE_SECONDS then
		return
	end
	self.lastPromptAt = os.clock()

	local canSendSuccess, canSendResult = pcall(function()
		return SocialService:CanSendGameInviteAsync(self.player)
	end)
	if not canSendSuccess then
		DebugModule.debugWarn("CanSendGameInviteAsync failed: " .. tostring(canSendResult), MODULE_NAME)
		showClientNotification("Invites are unavailable right now on this platform or account.")
		return
	end
	if canSendResult ~= true then
		showClientNotification("Invites are unavailable right now on this platform or account.")
		return
	end

	local socialConfig = CoreConfig.social
	local multiplierStep = if socialConfig and typeof(socialConfig.friendInviteMultiplierStep) == "number"
		then socialConfig.friendInviteMultiplierStep
		else 0.1
	local inviteOptions = Instance.new("ExperienceInviteOptions")
	inviteOptions.PromptMessage = if socialConfig and typeof(socialConfig.friendInvitePromptMessage) == "string"
		then socialConfig.friendInvitePromptMessage
		else ("Invite friends to join and earn +%.2fx multiplier per unique friend!"):format(multiplierStep)

	local promptSuccess, promptError = pcall(function()
		SocialService:PromptGameInvite(self.player, inviteOptions)
	end)
	if not promptSuccess then
		DebugModule.debugWarn("PromptGameInvite failed: " .. tostring(promptError), MODULE_NAME)
		showClientNotification("Failed to open the invite prompt.")
		return
	end

	FunnelAnalytics.FireClientAction("FriendInvitePromptOpened", {
		source = source,
	})
end

function FriendMultiplierUI:Init()
	if self.initialized or not self.alive then
		return
	end
	self.initialized = true

	local frame = self.screenGui:FindFirstChild("FriendMultiplier", true)
		or self.screenGui:FindFirstChild("FriendMultiplierFrame", true)
	local promptButton = frame and frame:FindFirstChild("PromptButton", true)
	local multiplierLabel = frame and frame:FindFirstChild("Multiplier", true)
	local plusLabel = frame and frame:FindFirstChild("TextLabel", true)
	local leftSideButtonsFrame = self.screenGui:FindFirstChild("LeftSideButtonsFrame", true)
	local gridFrame = leftSideButtonsFrame and leftSideButtonsFrame:FindFirstChild("GridFrame")
	local inviteFriendFrame = gridFrame and gridFrame:FindFirstChild("InviteFriendButtonFrame")
	local inviteFriendButton = inviteFriendFrame and inviteFriendFrame:FindFirstChild("TextButton", true)

	if not frame or not frame:IsA("GuiObject") then
		DebugModule.debugWarn("FriendMultiplier frame was not found", MODULE_NAME)
		return
	end
	if not promptButton or not promptButton:IsA("GuiButton") then
		DebugModule.debugWarn("FriendMultiplier PromptButton was not found", MODULE_NAME)
		return
	end
	if not multiplierLabel or not multiplierLabel:IsA("TextLabel") then
		DebugModule.debugWarn("FriendMultiplier Multiplier label was not found", MODULE_NAME)
		return
	end
	if not plusLabel or not plusLabel:IsA("TextLabel") then
		DebugModule.debugWarn("FriendMultiplier plus TextLabel was not found", MODULE_NAME)
		return
	end

	self.frame = frame
	self.promptButton = promptButton
	self.inviteFriendButton = if inviteFriendButton and inviteFriendButton:IsA("GuiButton")
		then inviteFriendButton
		else nil
	self.multiplierLabel = multiplierLabel
	self.plusLabel = plusLabel
	frame.Active = true
	promptButton.Active = true
	plusLabel.Text = "+"
	plusLabel.TextColor3 = PLUS_COLOR
	plusLabel.Visible = true
	VisualFunctions.SetupFrameHover(frame, 1.1, 15, 1.5)
	VisualFunctions.SetupFrameClick(frame, 0.95, -15, 0.75)

	self.maid:GiveTask(promptButton.Activated:Connect(function()
		self:promptInvite("FriendMultiplier")
	end))
	if self.inviteFriendButton then
		self.inviteFriendButton.Active = true
		self.maid:GiveTask(self.inviteFriendButton.Activated:Connect(function()
			self:promptInvite("InviteFriendButtonFrame")
		end))
	else
		DebugModule.debugWarn("InviteFriendButtonFrame TextButton was not found", MODULE_NAME)
	end
end

function FriendMultiplierUI:Destroy()
	if not self.alive then
		return
	end
	self.alive = false
	self.maid:DoCleaning()
	self.frame = nil
	self.promptButton = nil
	self.inviteFriendButton = nil
	self.multiplierLabel = nil
	self.plusLabel = nil
end

return FriendMultiplierUI
