--!strict
--[=[
	Enhanced Frame Rate Manager Module
	Provides dual-mode frame rate management for optimal game performance.

	This module offers:
	- FixedStep: Consistent 60 FPS game logic updates
	- RealTime: Frame-rate independent input processing
	- Hybrid: Systems can use both for optimal performance

	Usage:
	```lua
	local FrameRateManager = require(path.to.FrameRateManager)
	FrameRateManager:Start()

	-- Fixed-step game logic (60 FPS)
	FrameRateManager:BindToUpdate(function(deltaTime)
		-- Your 60 FPS game logic here
	end)

	-- Real-time input processing (actual FPS)
	FrameRateManager:BindToRealTimeInput(function(deltaTime, fpsMultiplier)
		-- Your frame-rate independent input processing here
	end)
	```
	@class FrameRateManager
]=]

local FrameRateManager = {}

-- Dependencies
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreConfig = require(script.Parent.Config.CoreConfig)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)

-- Module state
local isRunning = false
local fixedStepConnection: RBXScriptConnection?
local realTimeConnection: RBXScriptConnection?
local fixedStepCallbacks: { (deltaTime: number) -> () } = {}
local realTimeInputCallbacks: { (deltaTime: number, fpsMultiplier: number) -> () } = {}
local lastUpdateTime = 0
local accumulatedTime = 0
local targetFPS = 60
local targetFrameTime = 1 / targetFPS
local lastRealTimeUpdate = 0
local DEFAULT_TARGET_FRAME_TIME = 1 / 60
local MAX_FIXED_STEPS_PER_HEARTBEAT = 4

--[=[
	Starts the enhanced frame rate manager with dual-mode processing.
	This creates both fixed-step and real-time update loops.

	@return ()
]=]
function FrameRateManager:Start()
	if isRunning then
		DebugModule.debugPrint("Already running", "FrameRateManager")
		return
	end

	local configuredFrameTime = CoreConfig.performance.maxFrameTime
	targetFrameTime = if typeof(configuredFrameTime) == "number" and configuredFrameTime > 0
		then configuredFrameTime
		else DEFAULT_TARGET_FRAME_TIME
	targetFPS = 1 / targetFrameTime

	-- Fixed-step update loop (60 FPS game logic)
	fixedStepConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		-- Drop stale time after a stall instead of replaying unlimited updates in one frame.
		local maxCatchUpTime = targetFrameTime * MAX_FIXED_STEPS_PER_HEARTBEAT
		local safeDeltaTime = math.clamp(deltaTime, 0, maxCatchUpTime)
		accumulatedTime = math.min(accumulatedTime + safeDeltaTime, maxCatchUpTime)

		local fixedStepCount = 0
		while accumulatedTime >= targetFrameTime and fixedStepCount < MAX_FIXED_STEPS_PER_HEARTBEAT do
			accumulatedTime -= targetFrameTime
			fixedStepCount += 1

			-- Call all fixed-step update functions
			for _, callback in ipairs(fixedStepCallbacks) do
				callback(targetFrameTime)
			end
		end

		if fixedStepCount >= MAX_FIXED_STEPS_PER_HEARTBEAT then
			accumulatedTime = 0
		end
	end)

	-- Real-time input processing loop (actual FPS) - Only on client
	if RunService:IsClient() then
		realTimeConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
			local currentTime = os.clock()
			local realDeltaTime = currentTime - lastRealTimeUpdate
			lastRealTimeUpdate = currentTime

			-- Calculate FPS multiplier for frame-rate independent processing
			local actualFPS = 1 / math.max(realDeltaTime, 0.001)
			local fpsMultiplier = actualFPS / targetFPS

			-- Call all real-time input functions
			for _, callback in ipairs(realTimeInputCallbacks) do
				callback(realDeltaTime, fpsMultiplier)
			end
		end)
	end

	isRunning = true
	lastUpdateTime = os.clock()
	lastRealTimeUpdate = os.clock()
end

--[=[
	Stops the frame rate manager, halting all updates.

	@return ()
]=]
function FrameRateManager:Stop()
	if not isRunning then
		DebugModule.debugPrint("Not currently running", "FrameRateManager")
		return
	end

	if fixedStepConnection then
		fixedStepConnection:Disconnect()
		fixedStepConnection = nil
	end

	if realTimeConnection then
		realTimeConnection:Disconnect()
		realTimeConnection = nil
	end

	isRunning = false
	accumulatedTime = 0
	fixedStepCallbacks = {}
	realTimeInputCallbacks = {}
end

--[=[
	Binds a callback function to be called at 60 FPS intervals.
	The callback will receive the fixed delta time (1/60 seconds).

	@param callback (deltaTime: number) -> () -- The function to call on each update
	@return ()
]=]
function FrameRateManager:BindToUpdate(callback: (deltaTime: number) -> ())
	if typeof(callback) ~= "function" then
		DebugModule.debugWarn("Callback must be a function", "FrameRateManager")
		return
	end

	table.insert(fixedStepCallbacks, callback)
end

--[=[
	Unbinds a specific callback function from updates.

	@param callback (deltaTime: number) -> () -- The function to remove
	@return ()
]=]
function FrameRateManager:UnbindFromUpdate(callback: (deltaTime: number) -> ())
	for i, boundCallback in ipairs(fixedStepCallbacks) do
		if boundCallback == callback then
			table.remove(fixedStepCallbacks, i)
			break
		end
	end
end

--[=[
	Binds a callback function for real-time input processing at actual frame rate.
	The callback receives real delta time and FPS multiplier for frame-rate independent processing.

	@param callback (deltaTime: number, fpsMultiplier: number) -> () -- The function to call on each frame
	@return ()
]=]
function FrameRateManager:BindToRealTimeInput(callback: (deltaTime: number, fpsMultiplier: number) -> ())
	if typeof(callback) ~= "function" then
		DebugModule.debugWarn("Real-time callback must be a function", "FrameRateManager")
		return
	end

	table.insert(realTimeInputCallbacks, callback)
end

--[=[
	Unbinds a specific real-time input callback function.

	@param callback (deltaTime: number, fpsMultiplier: number) -> () -- The function to remove
	@return ()
]=]
function FrameRateManager:UnbindFromRealTimeInput(callback: (deltaTime: number, fpsMultiplier: number) -> ())
	for i, boundCallback in ipairs(realTimeInputCallbacks) do
		if boundCallback == callback then
			table.remove(realTimeInputCallbacks, i)
			break
		end
	end
end

--[=[
	Returns whether the frame rate manager is currently running.

	@return boolean -- True if manager is active, false otherwise
]=]
function FrameRateManager:IsRunning(): boolean
	return isRunning
end

--[=[
	Gets the current target frame time from CoreConfig.

	@return number -- The target frame time in seconds (1/60 for 60 FPS)
]=]
function FrameRateManager:GetTargetFrameTime(): number
	return targetFrameTime
end

--[=[
	Gets the current target FPS based on CoreConfig settings.

	@return number -- The target FPS (60)
]=]
function FrameRateManager:GetTargetFPS(): number
	return targetFPS
end

--[=[
	Gets the number of currently bound update callbacks.

	@return number -- Number of bound callbacks
]=]
function FrameRateManager:GetCallbackCount(): number
	return #fixedStepCallbacks
end

--[=[
	Gets the number of currently bound real-time input callbacks.

	@return number -- Number of real-time callbacks
]=]
function FrameRateManager:GetRealTimeCallbackCount(): number
	return #realTimeInputCallbacks
end

--[=[
	Gets the current FPS multiplier for frame-rate compensation.

	@return number -- FPS multiplier (actual FPS / target FPS)
]=]
function FrameRateManager:GetCurrentFPSMultiplier(): number
	local currentTime = os.clock()
	local deltaTime = currentTime - lastRealTimeUpdate
	local actualFPS = 1 / math.max(deltaTime, 0.001)
	return actualFPS / targetFPS
end

return FrameRateManager
