--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))
local Maid = require(ReplicatedStorage.Modules:WaitForChild("Maid"))
local TweenConfig = require(ReplicatedStorage.Modules.UI:WaitForChild("TweenConfig"))

local WinStreakUI = {}
WinStreakUI.__index = WinStreakUI

local MODULE_NAME = "WinStreakUI"
local STREAK_MULTIPLIER_ATTRIBUTE = "WinStreakMultiplier"
local BASE_MULTIPLIER = 1
local HOVER_ROTATION = 4
local HOVER_SCALE = 1.05
local FINISH_SHAKE_ROTATIONS = { 10, -7, 4, -2, 0 }

export type Controller = {
	Destroy: (self: Controller) -> (),
	PlayFinishShake: (self: Controller) -> (),
}

type ControllerState = Controller & {
	player: Player,
	label: TextLabel?,
	maid: any,
	originalPosition: UDim2?,
	originalRotation: number,
	scale: UIScale?,
	originalScale: number,
	hoverPositionTween: Tween?,
	hoverRotationTween: Tween?,
	hoverScaleTween: Tween?,
	resetPositionTween: Tween?,
	resetRotationTween: Tween?,
	resetScaleTween: Tween?,
	finishTween: Tween?,
	finishScaleTween: Tween?,
	animationToken: number,
	lastMultiplier: number,
	isHovering: boolean,
	isDestroyed: boolean,
}

local function isFiniteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function normalizeMultiplier(value: any): number
	if not isFiniteNumber(value) then
		return BASE_MULTIPLIER
	end

	return math.max(BASE_MULTIPLIER, value)
end

local function formatMultiplier(value: number): string
	local formatted = string.format("%.2f", normalizeMultiplier(value))
	formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
	return ("Win Streak %sx"):format(formatted)
end

local function cancelTween(tween: Tween?): Tween?
	if tween then
		tween:Cancel()
		tween:Destroy()
	end
	return nil
end

local function cancelAnimations(self: ControllerState)
	self.animationToken += 1
	self.hoverPositionTween = cancelTween(self.hoverPositionTween)
	self.hoverRotationTween = cancelTween(self.hoverRotationTween)
	self.hoverScaleTween = cancelTween(self.hoverScaleTween)
	self.resetPositionTween = cancelTween(self.resetPositionTween)
	self.resetRotationTween = cancelTween(self.resetRotationTween)
	self.resetScaleTween = cancelTween(self.resetScaleTween)
	self.finishTween = cancelTween(self.finishTween)
	self.finishScaleTween = cancelTween(self.finishScaleTween)
end

local function resetToOriginal(self: ControllerState)
	local label = self.label
	local originalPosition = self.originalPosition
	if not label or not originalPosition then
		return
	end

	local resetPositionTween = TweenService:Create(label, TweenConfig.WinStreakReset, {
		Position = originalPosition,
	})
	local resetRotationTween = TweenService:Create(label, TweenConfig.WinStreakReset, {
		Rotation = self.originalRotation,
	})
	local resetScaleTween = if self.scale
		then TweenService:Create(self.scale, TweenConfig.WinStreakReset, { Scale = self.originalScale })
		else nil
	self.resetPositionTween = resetPositionTween
	self.resetRotationTween = resetRotationTween
	self.resetScaleTween = resetScaleTween
	resetPositionTween.Completed:Once(function()
		resetPositionTween:Destroy()
		if self.resetPositionTween == resetPositionTween then
			self.resetPositionTween = nil
		end
	end)
	resetRotationTween.Completed:Once(function()
		resetRotationTween:Destroy()
		if self.resetRotationTween == resetRotationTween then
			self.resetRotationTween = nil
		end
	end)
	resetPositionTween:Play()
	resetRotationTween:Play()
	if resetScaleTween then
		resetScaleTween.Completed:Once(function()
			resetScaleTween:Destroy()
			if self.resetScaleTween == resetScaleTween then
				self.resetScaleTween = nil
			end
		end)
		resetScaleTween:Play()
	end
end

local function startHoverAnimation(self: ControllerState)
	local label = self.label
	if self.isDestroyed or not label then
		return
	end

	cancelAnimations(self)
	label.Rotation = self.originalRotation - HOVER_ROTATION
	local hoverRotationTween = TweenService:Create(label, TweenConfig.WinStreakHoverSwing, {
		Rotation = self.originalRotation + HOVER_ROTATION,
	})
	local hoverScaleTween = if self.scale
		then TweenService:Create(self.scale, TweenConfig.WinStreakHoverScale, {
			Scale = self.originalScale * HOVER_SCALE,
		})
		else nil
	self.hoverRotationTween = hoverRotationTween
	self.hoverScaleTween = hoverScaleTween
	hoverRotationTween:Play()
	if hoverScaleTween then
		hoverScaleTween:Play()
	end
end

function WinStreakUI.new(root: Instance, player: Player): Controller
	local self = setmetatable({
		player = player,
		label = nil :: TextLabel?,
		maid = Maid.new(),
		originalPosition = nil :: UDim2?,
		originalRotation = 0,
		scale = nil :: UIScale?,
		originalScale = 1,
		hoverPositionTween = nil :: Tween?,
		hoverRotationTween = nil :: Tween?,
		hoverScaleTween = nil :: Tween?,
		resetPositionTween = nil :: Tween?,
		resetRotationTween = nil :: Tween?,
		resetScaleTween = nil :: Tween?,
		finishTween = nil :: Tween?,
		finishScaleTween = nil :: Tween?,
		animationToken = 0,
		lastMultiplier = BASE_MULTIPLIER,
		isHovering = false,
		isDestroyed = false,
	}, WinStreakUI) :: ControllerState

	local label = root:FindFirstChild("WinStreak", true)
	if not label or not label:IsA("TextLabel") then
		DebugModule.debugWarn("WinStreak TextLabel was not found", MODULE_NAME)
		return self
	end

	self.label = label
	self.originalPosition = label.Position
	self.originalRotation = label.Rotation
	local scale = label:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "WinStreakScale"
		scale.Scale = 1
		scale.Parent = label
		self.maid:GiveTask(scale)
	end
	self.scale = scale
	self.originalScale = scale.Scale
	label.Active = true
	label.Interactable = true
	label.Text = formatMultiplier(player:GetAttribute(STREAK_MULTIPLIER_ATTRIBUTE))
	self.lastMultiplier = normalizeMultiplier(player:GetAttribute(STREAK_MULTIPLIER_ATTRIBUTE))

	self.maid:GiveTask(player:GetAttributeChangedSignal(STREAK_MULTIPLIER_ATTRIBUTE):Connect(function()
		if self.isDestroyed or not self.label then
			return
		end

		local nextMultiplier = normalizeMultiplier(player:GetAttribute(STREAK_MULTIPLIER_ATTRIBUTE))
		self.label.Text = formatMultiplier(nextMultiplier)
		local shouldShake = nextMultiplier > self.lastMultiplier
		self.lastMultiplier = nextMultiplier
		if shouldShake then
			self:PlayFinishShake()
		end
	end))

	self.maid:GiveTask(label.MouseEnter:Connect(function()
		if self.isDestroyed or not self.originalPosition then
			return
		end

		self.isHovering = true
		startHoverAnimation(self)
	end))

	self.maid:GiveTask(label.MouseLeave:Connect(function()
		if self.isDestroyed then
			return
		end

		self.isHovering = false
		cancelAnimations(self)
		resetToOriginal(self)
	end))

	self.maid:GiveTask(label.Destroying:Connect(function()
		self:Destroy()
	end))

	return self
end

local function startFinishScalePulse(self: ControllerState, animationToken: number)
	local scale = self.scale
	if not scale or self.isDestroyed then
		return
	end

	scale.Scale = self.originalScale
	local scaleUpTween = TweenService:Create(scale, TweenConfig.WinStreakFinishScaleUp, {
		Scale = self.originalScale * 2,
	})
	self.finishScaleTween = scaleUpTween
	scaleUpTween.Completed:Once(function(playbackState: Enum.PlaybackState)
		scaleUpTween:Destroy()
		if self.finishScaleTween == scaleUpTween then
			self.finishScaleTween = nil
		end
		if
			playbackState ~= Enum.PlaybackState.Completed
			or self.isDestroyed
			or self.animationToken ~= animationToken
		then
			return
		end

		local scaleDownTween = TweenService:Create(scale, TweenConfig.WinStreakFinishScaleDown, {
			Scale = self.originalScale,
		})
		self.finishScaleTween = scaleDownTween
		scaleDownTween.Completed:Once(function()
			scaleDownTween:Destroy()
			if self.finishScaleTween == scaleDownTween then
				self.finishScaleTween = nil
			end
		end)
		scaleDownTween:Play()
	end)
	scaleUpTween:Play()
end

function WinStreakUI.PlayFinishShake(self: ControllerState)
	local label = self.label
	local originalPosition = self.originalPosition
	if self.isDestroyed or not label or not originalPosition then
		return
	end

	cancelAnimations(self)
	local animationToken = self.animationToken
	startFinishScalePulse(self, animationToken)
	local stepIndex = 1

	local function playNextStep()
		if self.isDestroyed or self.animationToken ~= animationToken then
			return
		end

		local targetRotation = FINISH_SHAKE_ROTATIONS[stepIndex]
		if targetRotation == nil then
			if self.isHovering then
				startHoverAnimation(self)
			else
				resetToOriginal(self)
			end
			return
		end

		local tween = TweenService:Create(label, TweenConfig.WinStreakFinishShake, {
			Rotation = self.originalRotation + targetRotation,
		})
		self.finishTween = tween
		tween.Completed:Once(function(playbackState: Enum.PlaybackState)
			tween:Destroy()
			if self.finishTween == tween then
				self.finishTween = nil
			end
			if playbackState ~= Enum.PlaybackState.Completed then
				return
			end

			stepIndex += 1
			playNextStep()
		end)
		tween:Play()
	end

	playNextStep()
end

function WinStreakUI:Destroy()
	if self.isDestroyed then
		return
	end

	self.isDestroyed = true
	cancelAnimations(self)
	self.maid:DoCleaning()
	if self.label and self.originalPosition then
		self.label.Position = self.originalPosition
		self.label.Rotation = self.originalRotation
	end
	self.label = nil
end

return WinStreakUI
