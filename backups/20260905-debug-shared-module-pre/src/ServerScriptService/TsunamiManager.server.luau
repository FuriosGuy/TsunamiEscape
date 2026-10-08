--!strict
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(game:GetService("ServerScriptService").Modules:WaitForChild("DebugModule_Server"))
local ConfigFolder = game:GetService("ServerScriptService").Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig_Server"))
local TsunamiSystem = require(script.Parent.Modules.TsunamiSystem)

local MODULE_NAME = "TsunamiManager"
local tsunamiManagerConfig = if CoreConfig.server and CoreConfig.server.tsunamiManager
	then CoreConfig.server.tsunamiManager
	else nil
local STARTUP_SPAWN_COUNT = if tsunamiManagerConfig
		and typeof(tsunamiManagerConfig.startupSpawnCount) == "number"
	then math.max(1, math.floor(tsunamiManagerConfig.startupSpawnCount))
	else 70
local STARTUP_SPAWN_INTERVAL = if tsunamiManagerConfig
		and typeof(tsunamiManagerConfig.startupSpawnInterval) == "number"
	then math.max(0, tsunamiManagerConfig.startupSpawnInterval)
	else 0
local MIN_SPAWN_DELAY = if tsunamiManagerConfig and typeof(tsunamiManagerConfig.minSpawnDelay) == "number"
	then math.max(0, tsunamiManagerConfig.minSpawnDelay)
	else 10
local MAX_SPAWN_DELAY = if tsunamiManagerConfig and typeof(tsunamiManagerConfig.maxSpawnDelay) == "number"
	then math.max(MIN_SPAWN_DELAY, tsunamiManagerConfig.maxSpawnDelay)
	else 15
local DISABLE_WAVES_IN_STUDIO = RunService:IsStudio()
	and tsunamiManagerConfig ~= nil
	and tsunamiManagerConfig.debugStudioDisableWaves == true
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

local function canSpawnForWorld(world: Instance): boolean
	if world.Name == "Minigame" then
		return world:GetAttribute("RaceState") == "Racing"
	end

	return true
end

local function spawnForAllWorlds(useStartupPath: boolean?)
	local worldsFolder = getWorldsFolder()
	if not worldsFolder then
		return
	end

	for _, world in ipairs(worldsFolder:GetChildren()) do
		if canSpawnForWorld(world) then
			spawnForWorld(world.Name, useStartupPath)
		end
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
	TsunamiSystem.Destroy()
end

script.Destroying:Connect(shutdownManager)
script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		shutdownManager()
	end
end)
game:BindToClose(shutdownManager)

if not DISABLE_WAVES_IN_STUDIO then
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
else
	DebugModule.debugPrint("Studio wave spawning disabled by CoreConfig", MODULE_NAME)
end

DebugModule.debugPrint(
	string.format(
		"TsunamiManager initialized | studioWavesDisabled=%s | startupSpawns=%d | startupInterval=%d | delayRange=%d-%d seconds",
		tostring(DISABLE_WAVES_IN_STUDIO),
		STARTUP_SPAWN_COUNT,
		STARTUP_SPAWN_INTERVAL,
		MIN_SPAWN_DELAY,
		MAX_SPAWN_DELAY
	),
	MODULE_NAME
)
