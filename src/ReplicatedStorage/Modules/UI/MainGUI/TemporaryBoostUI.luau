local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local ProductService = require(ReplicatedStorage.Modules.Shared:WaitForChild("ProductService_Client"))
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)

local TemporaryBoostUI = {}
TemporaryBoostUI.__index = TemporaryBoostUI

type ColorTarget = {
	instance: Instance,
	property: string,
}

type BoostBinding = {
	frame: GuiObject,
	promptButton: GuiButton,
	uiScale: UIScale?,
	image: GuiObject?,
	statusLabel: TextLabel,
	timerLabel: TextLabel,
	endAttributeName: string,
	productId: number,
	originalSize: UDim2,
	originalScale: number,
	originalRotation: number,
	isHovering: boolean,
	isPressed: boolean,
	transformTween: Tween?,
	rotationTween: Tween?,
	colorTargets: { ColorTarget },
	colorTweens: { Tween },
	baseColors: { [Instance]: { [string]: Color3 } },
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
local ACTIVE_COLOR = ColorConfig.Colors.White.Color
local INACTIVE_COLOR = ColorConfig.UI.NotificationThemes.Green.textColor

local function scaledSize(size: UDim2, multiplier: number): UDim2
	return UDim2.new(
		size.X.Scale * multiplier,
		size.X.Offset * multiplier,
		size.Y.Scale * multiplier,
		size.Y.Offset * multiplier
	)
end

local function darkenColor(color: Color3, multiplier: number): Color3
	return Color3.new(
		math.clamp(color.R * multiplier, 0, 1),
		math.clamp(color.G * multiplier, 0, 1),
		math.clamp(color.B * multiplier, 0, 1)
	)
end

local function getColorTargets(root: GuiObject, excluded: { [Instance]: boolean }): { ColorTarget }
	local targets: { ColorTarget } = {}

	local function addTarget(instance: Instance, property: string)
		if excluded[instance] then
			return
		end
		table.insert(targets, {
			instance = instance,
			property = property,
		})
	end

	local function inspect(instance: Instance)
		if instance:IsA("Frame") or instance:IsA("ScrollingFrame") then
			addTarget(instance, "BackgroundColor3")
		elseif instance:IsA("TextLabel") then
			addTarget(instance, "TextColor3")
			addTarget(instance, "BackgroundColor3")
		elseif instance:IsA("TextButton") or instance:IsA("TextBox") then
			addTarget(instance, "BackgroundColor3")
			addTarget(instance, "TextColor3")
		elseif instance:IsA("ImageLabel") then
			addTarget(instance, "ImageColor3")
			addTarget(instance, "BackgroundColor3")
		elseif instance:IsA("ImageButton") then
			addTarget(instance, "BackgroundColor3")
			addTarget(instance, "ImageColor3")
		elseif instance:IsA("UIStroke") then
			addTarget(instance, "Color")
		end
	end

	inspect(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		inspect(descendant)
	end

	return targets
end

local function captureBaseColors(colorTargets: { ColorTarget }): { [Instance]: { [string]: Color3 } }
	local baseColors: { [Instance]: { [string]: Color3 } } = {}
	for _, target in ipairs(colorTargets) do
		local color = (target.instance :: any)[target.property]
		if typeof(color) == "Color3" then
			local instanceColors = baseColors[target.instance]
			if not instanceColors then
				instanceColors = {}
				baseColors[target.instance] = instanceColors
			end
			instanceColors[target.property] = color
		end
	end
	return baseColors
end

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
	local statusColor = if isActive then ACTIVE_COLOR else INACTIVE_COLOR

	binding.timerLabel.Text = formatRemaining(remainingSeconds)
	binding.statusLabel.Text = if isActive then "2x" else "+"
	local statusColors = binding.baseColors[binding.statusLabel]
	if statusColors then
		statusColors.TextColor3 = statusColor
	end
	binding.statusLabel.TextColor3 = if binding.isPressed then darkenColor(statusColor, 0.75) else statusColor
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
	root: Instance,
	frameName: string,
	endAttributeName: string,
	productId: number
): BoostBinding?
	local frame = root:FindFirstChild(frameName, true)
	local promptButton = frame and frame:FindFirstChild("PromptButton")
	local image = frame and (frame:FindFirstChild("RotateImage") or frame:FindFirstChild("Image"))
	local uiScale: UIScale? = nil
	if frame then
		local uiScaleInstance = frame:FindFirstChild("UIScale")
		if uiScaleInstance and uiScaleInstance:IsA("UIScale") then
			uiScale = uiScaleInstance
		end
	end
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
	if image and not image:IsA("GuiObject") then
		image = nil
	end
	local colorTargets = getColorTargets(frame, {})

	local binding: BoostBinding = {
		frame = frame,
		promptButton = promptButton,
		uiScale = uiScale,
		image = image :: GuiObject?,
		statusLabel = statusLabel,
		timerLabel = timerLabel,
		endAttributeName = endAttributeName,
		productId = productId,
		originalSize = frame.Size,
		originalScale = if uiScale then uiScale.Scale else 1,
		originalRotation = if image then image.Rotation else 0,
		isHovering = false,
		isPressed = false,
		transformTween = nil,
		rotationTween = nil,
		colorTargets = colorTargets,
		colorTweens = {},
		baseColors = captureBaseColors(colorTargets),
	}

	frame.Active = true
	promptButton.Active = true

	local function tweenVisuals(scaleMultiplier: number, rotation: number, tweenInfo: TweenInfo)
		if binding.transformTween then
			binding.transformTween:Cancel()
		end
		if binding.uiScale then
			binding.transformTween = TweenService:Create(binding.uiScale, tweenInfo, {
				Scale = binding.originalScale * scaleMultiplier,
			})
		else
			binding.transformTween = TweenService:Create(frame, tweenInfo, {
				Size = scaledSize(binding.originalSize, scaleMultiplier),
			})
		end
		binding.transformTween:Play()

		if binding.image then
			if binding.rotationTween then
				binding.rotationTween:Cancel()
			end
			binding.rotationTween = TweenService:Create(binding.image, tweenInfo, { Rotation = rotation })
			binding.rotationTween:Play()
		end
	end

	local function cancelColorTweens()
		for _, tween in ipairs(binding.colorTweens) do
			tween:Cancel()
		end
		table.clear(binding.colorTweens)
	end

	local function darkenPressedColors()
		cancelColorTweens()

		for _, target in ipairs(binding.colorTargets) do
			local colors = binding.baseColors[target.instance]
			local baseColor = colors and colors[target.property]
			if baseColor then
				local tween = TweenService:Create(target.instance, TweenConfig.Click, {
					[target.property] = darkenColor(baseColor, 0.75),
				})
				table.insert(binding.colorTweens, tween)
				tween:Play()
			end
		end
	end

	local function restorePressedColors()
		cancelColorTweens()

		for _, target in ipairs(binding.colorTargets) do
			local colors = binding.baseColors[target.instance]
			local baseColor = colors and colors[target.property]
			if baseColor then
				local tween = TweenService:Create(target.instance, TweenConfig.Click, {
					[target.property] = baseColor,
				})
				table.insert(binding.colorTweens, tween)
				tween:Play()
			end
		end
	end

	local function showHover()
		if binding.isHovering then
			return
		end
		binding.isHovering = true
		SoundService.PlayGuiSound("Hover")
		tweenVisuals(1.1, binding.originalRotation + 15, TweenConfig.Hover)
	end

	local function showPressed()
		if binding.isPressed then
			return
		end
		binding.isPressed = true
		SoundService.PlayGuiSound("Click")
		darkenPressedColors()
		tweenVisuals(0.95, binding.originalRotation - 15, TweenConfig.Click)
	end

	local function restoreVisuals()
		binding.isPressed = false
		binding.isHovering = false
		restorePressedColors()
		tweenVisuals(1, binding.originalRotation, TweenConfig.Hover)
	end

	self.maid:GiveTask(promptButton.MouseEnter:Connect(showHover))
	self.maid:GiveTask(promptButton.MouseLeave:Connect(restoreVisuals))
	self.maid:GiveTask(promptButton.MouseButton1Down:Connect(showPressed))
	self.maid:GiveTask(promptButton.MouseButton1Up:Connect(function()
		binding.isPressed = false
		restorePressedColors()
		if binding.isHovering then
			tweenVisuals(1.1, binding.originalRotation + 15, TweenConfig.Hover)
		else
			restoreVisuals()
		end
	end))

	self.maid:GiveTask(promptButton.InputBegan:Connect(function(input: InputObject)
		local inputName = input.UserInputType.Name
		if input.UserInputType == Enum.UserInputType.Touch or string.find(inputName, "Gamepad") then
			showPressed()
		end
	end))
	self.maid:GiveTask(promptButton.InputEnded:Connect(function(input: InputObject)
		local inputName = input.UserInputType.Name
		if input.UserInputType == Enum.UserInputType.Touch or string.find(inputName, "Gamepad") then
			if binding.isHovering then
				binding.isPressed = false
				restorePressedColors()
				tweenVisuals(1.1, binding.originalRotation + 15, TweenConfig.Hover)
			else
				restoreVisuals()
			end
		end
	end))

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

	local speedBinding = self:createBinding(
		self.screenGui,
		"TempSpeedBoostBuyFrame",
		"TemporarySpeedBoostEndUnix",
		ProductService.DevProducts.TempSpeedBoost
	)
	if speedBinding then
		table.insert(self.bindings, speedBinding)
	end

	local winBinding = self:createBinding(
		self.screenGui,
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
	for _, binding in ipairs(self.bindings) do
		if binding.transformTween then
			binding.transformTween:Cancel()
		end
		if binding.rotationTween then
			binding.rotationTween:Cancel()
		end
		for _, tween in ipairs(binding.colorTweens) do
			tween:Cancel()
		end
		table.clear(binding.colorTweens)
		for _, target in ipairs(binding.colorTargets) do
			local colors = binding.baseColors[target.instance]
			local baseColor = colors and colors[target.property]
			if baseColor then
				(target.instance :: any)[target.property] = baseColor
			end
		end
	end
	if self.updateThread and coroutine.status(self.updateThread) ~= "dead" then
		pcall(task.cancel, self.updateThread)
	end
	self.updateThread = nil
	self.maid:DoCleaning()
	table.clear(self.bindings)
end

return TemporaryBoostUI
