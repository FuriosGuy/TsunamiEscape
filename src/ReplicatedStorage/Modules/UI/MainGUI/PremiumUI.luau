--!strict

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local CoreConfig = require(ReplicatedStorage.Modules.Shared:WaitForChild("CoreConfig_Shared"))
local PlayerDataConfig = require(ReplicatedStorage.Modules.Shared:WaitForChild("PlayerDataConfig"))
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)

local PremiumUI = {}
PremiumUI.__index = PremiumUI

type PremiumUIObject = {
	screenGui: ScreenGui,
	player: Player,
	maid: any,
	frame: GuiObject?,
	promptButton: GuiButton?,
	statusLabel: TextLabel?,
	multiplierLabel: TextLabel?,
	timerLabel: TextLabel?,
	multiplier: number,
	initialized: boolean,
	alive: boolean,
}

local MODULE_NAME = "PremiumUI"
local PREMIUM_STATUS_COLOR = ColorConfig.UI.NotificationThemes.Green.textColor
local PREMIUM_MULTIPLIER = if typeof(PlayerDataConfig.PREMIUM_MULTIPLIER) == "number"
	then math.max(1, PlayerDataConfig.PREMIUM_MULTIPLIER)
	else 1.25

function PremiumUI.new(screenGui: ScreenGui): PremiumUIObject
	local player = assert(Players.LocalPlayer, "PremiumUI requires a local player")

	return setmetatable({
		screenGui = screenGui,
		player = player,
		maid = Maid.new(),
		frame = nil,
		promptButton = nil,
		statusLabel = nil,
		multiplierLabel = nil,
		timerLabel = nil,
		multiplier = PREMIUM_MULTIPLIER,
		initialized = false,
		alive = true,
	}, PremiumUI) :: PremiumUIObject
end

function PremiumUI:refresh()
	if not self.alive or not self.frame or not self.promptButton then
		return
	end

	local isPremium = self.player.MembershipType == Enum.MembershipType.Premium
	self.frame.Visible = true
	self.frame.Active = true
	self.frame:SetAttribute("UiDisabled", false)
	self.promptButton.Active = true

	if self.statusLabel then
		self.statusLabel.Text = "+"
		self.statusLabel.TextColor3 = PREMIUM_STATUS_COLOR
		self.statusLabel.Visible = not isPremium
	end
	if self.multiplierLabel then
		self.multiplierLabel.Text = string.format("%.2fx", self.multiplier)
		self.multiplierLabel.Visible = true
	end
	if self.timerLabel then
		self.timerLabel.Visible = false
	end
end

function PremiumUI:Init()
	if self.initialized then
		return
	end
	self.initialized = true

	local frame = self.screenGui:FindFirstChild("PremiumMultiplierFrame", true)
	local promptButton = frame and frame:FindFirstChild("PromptButton", true)
	local statusLabel = frame and frame:FindFirstChild("TextLabel", true)
	local multiplierLabel = frame and frame:FindFirstChild("Multiplier", true)
	local timerLabel = frame and frame:FindFirstChild("TimerLabel", true)

	if not frame or not frame:IsA("GuiObject") then
		DebugModule.debugWarn("PremiumMultiplierFrame was not found", MODULE_NAME)
		return
	end
	if not promptButton or not promptButton:IsA("GuiButton") then
		DebugModule.debugWarn("PremiumMultiplierFrame PromptButton was not found", MODULE_NAME)
		return
	end
	if not statusLabel or not statusLabel:IsA("TextLabel") then
		DebugModule.debugWarn("PremiumMultiplierFrame TextLabel was not found", MODULE_NAME)
		return
	end
	if not multiplierLabel or not multiplierLabel:IsA("TextLabel") then
		DebugModule.debugWarn("PremiumMultiplierFrame Multiplier was not found", MODULE_NAME)
		return
	end

	self.frame = frame
	self.promptButton = promptButton
	self.statusLabel = statusLabel
	self.multiplierLabel = multiplierLabel
	self.timerLabel = if timerLabel and timerLabel:IsA("TextLabel") then timerLabel else nil

	frame.Active = true
	promptButton.Active = true
	VisualFunctions.SetupFrameHover(frame, 1.1, 15, 1.5)
	VisualFunctions.SetupFrameClick(frame, 0.95, -15, 0.75)

	self.maid:GiveTask(promptButton.Activated:Connect(function()
		if not CoreConfig.canShowPremiumPrompt(self.player.MembershipType, RunService:IsStudio()) then
			self:refresh()
			return
		end

		SoundService.PlayGuiSound("Click")
		local promptOk, promptError = pcall(function()
			MarketplaceService:PromptPremiumPurchase(self.player)
		end)
		if not promptOk then
			DebugModule.debugWarn("Premium purchase prompt failed: " .. tostring(promptError), MODULE_NAME)
		end
	end))
	self.maid:GiveTask(self.player:GetPropertyChangedSignal("MembershipType"):Connect(function()
		self:refresh()
	end))

	self:refresh()
end

function PremiumUI:Destroy()
	if not self.alive then
		return
	end

	self.alive = false
	self.maid:DoCleaning()
	self.frame = nil
	self.promptButton = nil
	self.statusLabel = nil
	self.multiplierLabel = nil
	self.timerLabel = nil
end

return PremiumUI
