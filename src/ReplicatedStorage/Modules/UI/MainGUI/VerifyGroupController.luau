--!strict

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

local VerifyGroupController = {}
VerifyGroupController.__index = VerifyGroupController

type MaidLike = {
	GiveTask: (self: MaidLike, taskValue: any) -> any,
}

type ControllerOptions = {
	player: Player,
	groupId: number,
	remotes: Instance,
	sessionMaid: MaidLike,
	spawnSessionTask: (callback: () -> ()) -> thread,
	showNotification: (message: string, textColor: Color3?, gradientBottomColor: Color3?) -> (),
}

type Controller = typeof(setmetatable({} :: {
	player: Player,
	groupId: number,
	remotes: Instance,
	sessionMaid: MaidLike,
	spawnSessionTask: (callback: () -> ()) -> thread,
	showNotification: (message: string, textColor: Color3?, gradientBottomColor: Color3?) -> (),
	membership: boolean?,
	membershipCheckInFlight: boolean,
	requestInFlight: boolean,
	destroyed: boolean,
	buttons: { [GuiButton]: boolean },
}, VerifyGroupController))

local function getButtonTextTarget(button: GuiButton): TextButton?
	if button:IsA("TextButton") then
		return button
	end

	local textButton = button:FindFirstChildWhichIsA("TextButton", true)
	return textButton
end

function VerifyGroupController.new(options: ControllerOptions): Controller
	local self = setmetatable({
		player = options.player,
		groupId = options.groupId,
		remotes = options.remotes,
		sessionMaid = options.sessionMaid,
		spawnSessionTask = options.spawnSessionTask,
		showNotification = options.showNotification,
		membership = nil,
		membershipCheckInFlight = false,
		requestInFlight = false,
		destroyed = false,
		buttons = {},
	}, VerifyGroupController)

	return self
end

function VerifyGroupController:UpdateButtonText()
	local text = if self.membership == true
		then "Claim"
		elseif self.membership == false then "Verify & Claim"
		else "Checking..."

	for button in pairs(self.buttons) do
		if button.Parent == nil then
			self.buttons[button] = nil
		else
			local textButton = getButtonTextTarget(button)
			if textButton then
				textButton.Text = text
			end
		end
	end
end

function VerifyGroupController:BindButton(button: GuiButton)
	if self.destroyed or self.buttons[button] then
		return
	end

	self.buttons[button] = true
	self:UpdateButtonText()
	self.sessionMaid:GiveTask(button.Activated:Connect(function()
		self:HandleButtonPressed()
	end))
end

function VerifyGroupController:BindAll(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == "VerifyButton" then
			local button = if descendant:IsA("GuiButton")
				then descendant
				else descendant:FindFirstChildWhichIsA("GuiButton", true)
			if button then
				self:BindButton(button)
			end
		end
	end
end

function VerifyGroupController:RefreshMembership()
	if self.destroyed
		or self.membership ~= nil
		or self.membershipCheckInFlight
		or self.player:GetAttribute("Data_Loaded") ~= true
	then
		return
	end

	self.membershipCheckInFlight = true
	self:UpdateButtonText()
	self.spawnSessionTask(function()
		local success, result = pcall(function()
			return self.player:IsInGroupAsync(self.groupId)
		end)
		if self.destroyed then
			return
		end

		self.membershipCheckInFlight = false
		if success and typeof(result) == "boolean" then
			self.membership = result
			self:UpdateButtonText()
			return
		end

		self.membership = nil
		self:UpdateButtonText()
		DebugModule.debugWarn(
			"Group membership refresh failed: " .. tostring(result),
			"VerifyGroupController"
		)
	end)
end

function VerifyGroupController:GetVerifyRemote(): RemoteEvent?
	local remote = self.remotes:FindFirstChild("VerifyRewardRequest")
	return if remote and remote:IsA("RemoteEvent") then remote else nil
end

function VerifyGroupController:HandleButtonPressed()
	if self.destroyed or self.requestInFlight then
		return
	end

	SoundService.PlayGuiSound("Click")
	self.requestInFlight = true
	self.spawnSessionTask(function()
		local isInGroup = self.membership
		if isInGroup == nil then
			local membershipOk, membershipResult = pcall(function()
				return self.player:IsInGroupAsync(self.groupId)
			end)
			if not membershipOk or typeof(membershipResult) ~= "boolean" then
				self.requestInFlight = false
				DebugModule.debugWarn(
					"Group membership check failed: " .. tostring(membershipResult),
					"VerifyGroupController"
				)
				return
			end

			isInGroup = membershipResult
			self.membership = membershipResult
			self:UpdateButtonText()
		end

		if isInGroup then
			local verifyRemote = self:GetVerifyRemote()
			if verifyRemote then
				verifyRemote:FireServer()
			end
			self.requestInFlight = false
			return
		end

		local promptOk, promptResult = pcall(function()
			return GroupService:PromptJoinAsync(self.groupId)
		end)
		if not promptOk then
			self.requestInFlight = false
			DebugModule.debugWarn(
				"Group prompt failed: " .. tostring(promptResult),
				"VerifyGroupController"
			)
			return
		end

		local status = promptResult :: Enum.GroupMembershipStatus
		if
			status == Enum.GroupMembershipStatus.Joined
			or status == Enum.GroupMembershipStatus.AlreadyMember
		then
			self.membership = true
			self:UpdateButtonText()
			local verifyRemote = self:GetVerifyRemote()
			if verifyRemote then
				verifyRemote:FireServer()
			end
		elseif status == Enum.GroupMembershipStatus.JoinRequestPending then
			local theme = VisualFunctions.NotificationThemes.Gold
			self.showNotification("GROUP REQUEST PENDING", theme.textColor, theme.gradientBottomColor)
		elseif status == Enum.GroupMembershipStatus.None then
			local theme = VisualFunctions.NotificationThemes.Red
			self.showNotification("GROUP JOIN CANCELED", theme.textColor, theme.gradientBottomColor)
		end

		self.requestInFlight = false
	end)
end

function VerifyGroupController:Destroy()
	if self.destroyed then
		return
	end

	self.destroyed = true
	self.membership = nil
	self.membershipCheckInFlight = false
	self.requestInFlight = false
	table.clear(self.buttons)
end

return VerifyGroupController
