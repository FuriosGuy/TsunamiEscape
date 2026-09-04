--!strict
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local ConfigFolder = ReplicatedStorage.Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))
local TsunamiSystem = require(script.Parent.Modules.TsunamiSystem)

local MODULE_NAME = "TsunamiManager"
local tsunamiManagerConfig = if CoreConfig.server and CoreConfig.server.tsunamiManager
	then CoreConfig.server.tsunamiManager
	else nil
local STARTUP_SPAWN_COUNT = if tsunamiManagerConfig and typeof(tsunamiManagerConfig.startupSpawnCount) == "number"
	then math.max(1, math.floor(tsunamiManagerConfig.startupSpawnCount))
	else 70
local STARTUP_SPAWN_INTERVAL = if tsunamiManagerConfig and typeof(tsunamiManagerConfig.startupSpawnInterval) == "number"
	then math.max(0, tsunamiManagerConfig.startupSpawnInterval)
	else 0
local MIN_SPAWN_DELAY = if tsunamiManagerConfig and typeof(tsunamiManagerConfig.minSpawnDelay) == "number"
	then math.max(0, tsunamiManagerConfig.minSpawnDelay)
	else 10
local MAX_SPAWN_DELAY = if tsunamiManagerConfig and typeof(tsunamiManagerConfig.maxSpawnDelay) == "number"
	then math.max(MIN_SPAWN_DELAY, tsunamiManagerConfig.maxSpawnDelay)
	else 15
local isRunning = true
local tsunamiLoopThread: thread? = nil

local function getWorldsFolder(): Instance?
	local worldsFolder = Workspace:FindFirstChild("Worlds")
	if not worldsFolder then
		DebugModule.debugWarn("Workspace.Worlds folder not found", MODULE_NAME)
		return nil
	end

	return worldsFolder
end

local function spawnForWorld(worldName: string, useStartupPath: boolean?)
	TsunamiSystem.SpawnCycleForWorld(worldName, useStartupPath)
end

local function spawnForAllWorlds(useStartupPath: boolean?)
	local worldsFolder = getWorldsFolder()
	if not worldsFolder then
		return
	end

	for _, world in ipairs(worldsFolder:GetChildren()) do
		spawnForWorld(world.Name, useStartupPath)
	end
end

local function shutdownManager()
	if not isRunning then
		return
	end

	isRunning = false
	if tsunamiLoopThread then
		task.cancel(tsunamiLoopThread)
		tsunamiLoopThread = nil
	end
end

script.Destroying:Connect(shutdownManager)
game:BindToClose(shutdownManager)

tsunamiLoopThread = task.spawn(function()
	for spawnIndex = 1, STARTUP_SPAWN_COUNT do
		if not isRunning then
			return
		end

		spawnForAllWorlds(true)

		if spawnIndex < STARTUP_SPAWN_COUNT then
			task.wait(STARTUP_SPAWN_INTERVAL)
		end
	end

	if not isRunning then
		return
	end

	DebugModule.debugPrint(
		"All startup tsunami waves completed spawning, returning to normal behavior",
		MODULE_NAME
	)
	spawnForAllWorlds(false)

	while isRunning do
		local delayTime = math.random(MIN_SPAWN_DELAY, MAX_SPAWN_DELAY)
		task.wait(delayTime)
		if not isRunning then
			break
		end
		spawnForAllWorlds(false)
	end
end)

DebugModule.debugPrint(
	string.format(
		"TsunamiManager initialized with %d startup spawns every %d seconds, then delay range %d-%d seconds",
		STARTUP_SPAWN_COUNT,
		STARTUP_SPAWN_INTERVAL,
		MIN_SPAWN_DELAY,
		MAX_SPAWN_DELAY
	),
	MODULE_NAME
)
