--!strict
local TweenConfig = {
	Hover = TweenInfo.new(0.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
	Click = TweenInfo.new(0.1, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
	Rotate = TweenInfo.new(0.2, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut),
	LinearLoop = TweenInfo.new(5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
	Pulsate = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	WindowOpen = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
	WindowClose = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
	RotatingGradient = TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
	ProgressBar = TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
}

export type TweenConfig = typeof(TweenConfig)

return TweenConfig
