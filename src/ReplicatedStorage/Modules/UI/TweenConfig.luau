--!strict

local TweenConfig = {
	Hover = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	HoverColor = TweenInfo.new(0.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
	Click = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
	Rotate = TweenInfo.new(0.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
	LinearLoop = TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
	Pulsate = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	WindowOpen = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	WindowClose = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	RotatingGradient = TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
	ProgressBar = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	MenuOpen = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	MenuClose = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	LoadingProgress = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	LoadingLabelFade = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	DataRecoveryPop = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	LoadingLogoBounce = TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	LoadingLogoSettle = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	NotificationLayout = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	DailyRewardCard = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	SpinWheelShine = TweenInfo.new(2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
	SpinWheelRotation = TweenInfo.new(0, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	RewardPulse = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	ProductPrompt = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	RemoteEffectAppear = TweenInfo.new(0, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	RemoteEffectMove = TweenInfo.new(0, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
	RemoteEffectCollect = TweenInfo.new(0, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	RemoteEffectDisappear = TweenInfo.new(0, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	MusicFade = TweenInfo.new(0),
	CameraFov = TweenInfo.new(0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	TsunamiVisual = TweenInfo.new(0, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
	EnvironmentTransition = TweenInfo.new(0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	EnvironmentLinear = TweenInfo.new(0, Enum.EasingStyle.Linear),
	DropdownOpen = TweenInfo.new(0, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
	TopbarCaptionIn = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	TopbarCaptionOut = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	TooltipOpen = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	TooltipClose = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	WinStreakHoverSwing = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	WinStreakHoverScale = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	WinStreakReset = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	WinStreakFinishShake = TweenInfo.new(0.05, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	WinStreakFinishScaleUp = TweenInfo.new(0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
	WinStreakFinishScaleDown = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
	Instant = TweenInfo.new(0),
}

function TweenConfig.WithDuration(duration: number, template: TweenInfo): TweenInfo
	return TweenInfo.new(
		duration,
		template.EasingStyle,
		template.EasingDirection,
		template.RepeatCount,
		template.Reverses,
		template.DelayTime
	)
end

function TweenConfig.FromParameters(
	duration: number,
	easingStyle: EnumItem,
	easingDirection: EnumItem,
	repeatCount: number?,
	reverses: boolean?,
	delayTime: number?
): TweenInfo
	return TweenInfo.new(
		duration,
		easingStyle,
		easingDirection,
		repeatCount or 0,
		reverses or false,
		delayTime or 0
	)
end

export type TweenConfig = typeof(TweenConfig)

return TweenConfig
