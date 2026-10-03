--!strict

local TsunamiTrajectory = {}

function TsunamiTrajectory.Sample(
	startCFrame: CFrame,
	targetCFrame: CFrame,
	startServerTime: number,
	duration: number,
	serverTime: number
): (CFrame, boolean)
	assert(duration > 0, "Tsunami trajectory duration must be positive")

	local elapsed = serverTime - startServerTime
	local alpha = math.clamp(elapsed / duration, 0, 1)
	local isComplete = elapsed >= duration

	return startCFrame:Lerp(targetCFrame, alpha), isComplete
end

return TsunamiTrajectory
