--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local FunnelAnalytics = require(Modules:WaitForChild("FunnelAnalytics"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local TopbarFolder = ReplicatedStorage:WaitForChild("Topbar")
local Icon = require(TopbarFolder:WaitForChild("Icon"))

local InviteFriendsTopbar = {}

local MODULE_NAME = "InviteFriendsTopbar"
local localPlayer = Players.LocalPlayer
local socialConfig = CoreConfig.social
local iconImage = if socialConfig and typeof(socialConfig.friendInviteTopbarIconImage) == "string"
	then socialConfig.friendInviteTopbarIconImage
	else "rbxassetid://112009101194397"
local iconLabel = if socialConfig and typeof(socialConfig.friendInviteTopbarLabel) == "string"
	then socialConfig.friendInviteTopbarLabel
	else "Invite"
local promptMessage = if socialConfig and typeof(socialConfig.friendInvitePromptMessage) == "string"
	then socialConfig.friendInvitePromptMessage
	else "Invite friends to join and earn +0.10x multiplier per unique friend!"
local iconName = "InviteFriendsTopbar"

local started = false

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

local function canSendInvite(): boolean
	local success, canSend = pcall(function()
		return SocialService:CanSendGameInviteAsync(localPlayer)
	end)

	if not success then
		DebugModule.debugWarn("CanSendGameInviteAsync failed: " .. tostring(canSend), MODULE_NAME)
		return false
	end

	return canSend == true
end

local function promptInvite()
	if not canSendInvite() then
		showClientNotification("Invites are unavailable right now on this platform or account.")
		return
	end

	local inviteOptions = Instance.new("ExperienceInviteOptions")
	inviteOptions.PromptMessage = promptMessage

	local success, err = pcall(function()
		SocialService:PromptGameInvite(localPlayer, inviteOptions)
	end)

	if not success then
		DebugModule.debugWarn("PromptGameInvite failed: " .. tostring(err), MODULE_NAME)
		showClientNotification("Failed to open the invite prompt.")
		return
	end

	FunnelAnalytics.FireClientAction("FriendInvitePromptOpened", {
		source = "Topbar",
	})
end

function InviteFriendsTopbar.Start()
	if started then
		return
	end
	started = true

	local existingIcon = Icon.getIcon(iconName)
	if existingIcon then
		existingIcon:destroy()
	end

	Icon.setTopbarEnabled(true)

	local inviteIcon = Icon.new()
		:setName(iconName)
		:setLeft()
		:setImage(iconImage)
		:setLabel(iconLabel)
		:oneClick()

	inviteIcon.selected:Connect(function()
		promptInvite()
	end)

	DebugModule.debugInfo("Invite friends topbar icon started", MODULE_NAME)
end

return InviteFriendsTopbar
