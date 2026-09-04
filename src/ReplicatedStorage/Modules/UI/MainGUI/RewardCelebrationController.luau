--!strict

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfettiBurstPlayer = require(ReplicatedStorage.Modules.UI:WaitForChild("ConfettiBurstPlayer"))

local RewardCelebrationController = {}
RewardCelebrationController.__index = RewardCelebrationController

type ControllerOptions = {
	root: Instance,
	soundService: any,
	coreConfig: any,
}

function RewardCelebrationController.new(options: ControllerOptions)
	local self = setmetatable({}, RewardCelebrationController)

	local confettiHost = options.root:FindFirstChild("ConfettiFrame", true)
	self.confettiPlayer = if confettiHost and confettiHost:IsA("GuiObject")
		then ConfettiBurstPlayer.GetOrCreateSingleton(confettiHost)
		else nil
	self.soundService = options.soundService
	self.rewardCelebrationCount = if options.coreConfig.leveling
			and typeof(options.coreConfig.leveling.rewardCelebrationConfettiCount) == "number"
		then math.max(1, math.floor(options.coreConfig.leveling.rewardCelebrationConfettiCount))
		else 45
	self.rewardCelebrationColors = if options.coreConfig.leveling
			and typeof(options.coreConfig.leveling.rebirthConfettiColors) == "table"
			and #options.coreConfig.leveling.rebirthConfettiColors > 0
		then options.coreConfig.leveling.rebirthConfettiColors
		else nil
	self.rewardCelebrationDuration = if options.coreConfig.leveling
			and typeof(options.coreConfig.leveling.rebirthConfettiDuration) == "number"
		then options.coreConfig.leveling.rebirthConfettiDuration
		else 1.5
	self.pulseToken = 0
	self.isPulsing = false
	self.activeTween = nil :: Tween?
	self.pulseButtonFrame = nil :: GuiObject?

	return self
end

function RewardCelebrationController:PlayRewardCelebration(playHorn: boolean?)
	if playHorn ~= false then
		self.soundService.PlayGuiSound("Confetti")
	end

	if self.confettiPlayer then
		self.confettiPlayer:PlayBurst(
			self.rewardCelebrationColors,
			self.rewardCelebrationDuration,
			self.rewardCelebrationCount
		)
	end
end

function RewardCelebrationController:GetOrCreateButtonScale(buttonFrame: GuiObject): UIScale
	local existingScale = buttonFrame:FindFirstChild("RebirthPulseScale")
	if existingScale and existingScale:IsA("UIScale") then
		return existingScale
	end

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "RebirthPulseScale"
	uiScale.Scale = 1
	uiScale:SetAttribute("IgnoreInteractionScale", true)
	uiScale.Parent = buttonFrame
	return uiScale
end

function RewardCelebrationController:StopRebirthButtonPulse()
	local buttonFrame = self.pulseButtonFrame
	self.pulseToken += 1
	self.isPulsing = false
	self.pulseButtonFrame = nil

	if self.activeTween then
		self.activeTween:Cancel()
		self.activeTween = nil
	end

	if buttonFrame then
		self:GetOrCreateButtonScale(buttonFrame).Scale = 1
	end
end

function RewardCelebrationController:StartRebirthButtonPulse(buttonFrame: GuiObject?)
	if not buttonFrame then
		return
	end

	if self.isPulsing and self.pulseButtonFrame == buttonFrame then
		return
	end
	if self.isPulsing then
		self:StopRebirthButtonPulse()
	end

	self.pulseToken += 1
	self.isPulsing = true
	self.pulseButtonFrame = buttonFrame
	local pulseToken = self.pulseToken
	local uiScale = self:GetOrCreateButtonScale(buttonFrame)
	uiScale.Scale = 1

	local function playPulse(targetScale: number)
		if pulseToken ~= self.pulseToken or not self.isPulsing then
			return
		end
		if buttonFrame.Parent == nil then
			self:StopRebirthButtonPulse()
			return
		end

		local tween = TweenService:Create(
			uiScale,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Scale = targetScale }
		)
		self.activeTween = tween
		tween.Completed:Once(function(playbackState)
			if pulseToken ~= self.pulseToken then
				return
			end
			if playbackState ~= Enum.PlaybackState.Completed then
				return
			end

			playPulse(if targetScale > 1 then 1 else 1.06)
		end)
		tween:Play()
	end

	playPulse(1.06)
end

function RewardCelebrationController:UpdateRebirthReady(isReady: boolean, buttonFrame: GuiObject?)
	if isReady then
		self:StartRebirthButtonPulse(buttonFrame)
	else
		self:StopRebirthButtonPulse()
	end
end

function RewardCelebrationController:Destroy()
	self:StopRebirthButtonPulse()
end

return RewardCelebrationController
