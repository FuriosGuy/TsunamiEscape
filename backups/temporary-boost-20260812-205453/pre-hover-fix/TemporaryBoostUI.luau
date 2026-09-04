--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local ProductService = require(ReplicatedStorage.Modules.ProductService)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

local TemporaryBoostUI = {}
TemporaryBoostUI.__index = TemporaryBoostUI

type BoostBinding = {
	frame: GuiObject,
	promptButton: GuiButton,
	statusLabel: TextLabel,
	timerLabel: TextLabel,
	endAttributeName: string,
	productId: number,
}

type TemporaryBoostUIObject = {
	screenGui: ScreenGui,
	player: Player,
	maid: any,
	bindings: { BoostBinding },
	updateThread: thread?,
	alive: boolean,
	initialized: boolean,
	promptCooldownUntil: number,
}

local MODULE_NAME = "TemporaryBoostUI"
local ACTIVE_COLOR = Color3.fromRGB(255, 255, 255)
local INACTIVE_COLOR = Color3.fromRGB(0, 255, 0)

local function formatRemaining(seconds: number): string
	local totalSeconds = math.max(0, math.ceil(seconds))
	if totalSeconds >= 60 * 60 then
		local hours = math.floor(totalSeconds / (60 * 60))
		local minutes = math.floor((totalSeconds % (60 * 60)) / 60)
		local remainingSeconds = totalSeconds % 60
		return string.format("%02d:%02d:%02d", hours, minutes, remainingSeconds)
	end

	local minutes = math.floor(totalSeconds / 60)
	local remainingSeconds = totalSeconds % 60
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

local function getRemainingSeconds(player: Player, endAttributeName: string): number
	local endValue = player:GetAttribute(endAttributeName)
	if typeof(endValue) ~= "number" then
		return 0
	end

	return math.max(0, endValue - os.time())
end

function TemporaryBoostUI.new(screenGui: ScreenGui): TemporaryBoostUIObject
	local player = assert(Players.LocalPlayer, "TemporaryBoostUI requires a local player")

	return setmetatable({
		screenGui = screenGui,
		player = player,
		maid = Maid.new(),
		bindings = {},
		updateThread = nil,
		alive = true,
		initialized = false,
		promptCooldownUntil = 0,
	}, TemporaryBoostUI)
end

function TemporaryBoostUI:refreshBinding(binding: BoostBinding)
	local remainingSeconds = getRemainingSeconds(self.player, binding.endAttributeName)
	local isActive = remainingSeconds > 0

	binding.timerLabel.Text = formatRemaining(remainingSeconds)
	binding.statusLabel.Text = if isActive then "2x" else "+"
	binding.statusLabel.TextColor3 = if isActive then ACTIVE_COLOR else INACTIVE_COLOR
end

function TemporaryBoostUI:refresh()
	if not self.alive then
		return
	end

	for _, binding in ipairs(self.bindings) do
		self:refreshBinding(binding)
	end
end

function TemporaryBoostUI:createBinding(
		speedMultiFrame: GuiObject,
		frameName: string,
		endAttributeName: string,
		productId: number
	): BoostBinding?
	local frame = speedMultiFrame:FindFirstChild(frameName)
	local promptButton = frame and frame:FindFirstChild("PromptButton")
	local statusLabel = frame and frame:FindFirstChild("TextLabel")
	local timerLabel = frame and frame:FindFirstChild("TimerLabel")

	if not frame or not frame:IsA("GuiObject") then
		DebugModule.debugWarn("Missing boost frame: " .. frameName, MODULE_NAME)
		return nil
	end
	if not promptButton or not promptButton:IsA("GuiButton") then
		DebugModule.debugWarn("Missing boost PromptButton: " .. frameName, MODULE_NAME)
		return nil
	end
	if not statusLabel or not statusLabel:IsA("TextLabel") then
		DebugModule.debugWarn("Missing boost TextLabel: " .. frameName, MODULE_NAME)
		return nil
	end
	if not timerLabel or not timerLabel:IsA("TextLabel") then
		DebugModule.debugWarn("Missing boost TimerLabel: " .. frameName, MODULE_NAME)
		return nil
	end

	local binding: BoostBinding = {
		frame = frame,
		promptButton = promptButton,
		statusLabel = statusLabel,
		timerLabel = timerLabel,
		endAttributeName = endAttributeName,
		productId = productId,
	}

	VisualFunctions.SetupFrameHover(frame, 1.1, 15)
	VisualFunctions.SetupFrameClick(frame, 0.95, -15)

	self.maid:GiveTask(promptButton.Activated:Connect(function()
		local now = os.clock()
		if now < self.promptCooldownUntil then
			return
		end
		self.promptCooldownUntil = now + 0.5
		ProductService.promptProductPurchase(self.player, binding.productId)
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(endAttributeName):Connect(function()
		self:refreshBinding(binding)
	end))

	return binding
end

function TemporaryBoostUI:Init()
	if self.initialized then
		return
	end
	self.initialized = true

	local speedMultiFrame = self.screenGui:FindFirstChild("SpeedMultiFrame", true)
	if not speedMultiFrame or not speedMultiFrame:IsA("GuiObject") then
		DebugModule.debugWarn("SpeedMultiFrame was not found", MODULE_NAME)
		return
	end

	local speedBinding = self:createBinding(
		speedMultiFrame,
		"TempSpeedBoostBuyFrame",
		"TemporarySpeedBoostEndUnix",
		ProductService.DevProducts.TempSpeedBoost
	)
	if speedBinding then
		table.insert(self.bindings, speedBinding)
	end

	local winBinding = self:createBinding(
		speedMultiFrame,
		"TempWinBoostBuyFrame",
		"TemporaryWinBoostEndUnix",
		ProductService.DevProducts.TempWinBoost
	)
	if winBinding then
		table.insert(self.bindings, winBinding)
	end

	self:refresh()
	self.updateThread = task.spawn(function()
		while self.alive and self.screenGui.Parent do
			self:refresh()
			task.wait(1)
		end
	end)
end

function TemporaryBoostUI:Destroy()
	if not self.alive then
		return
	end

	self.alive = false
	if self.updateThread and coroutine.status(self.updateThread) ~= "dead" then
		pcall(task.cancel, self.updateThread)
	end
	self.updateThread = nil
	self.maid:DoCleaning()
	table.clear(self.bindings)
end

return TemporaryBoostUI
