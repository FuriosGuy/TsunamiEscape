--!strict
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local ConfigFolder = ReplicatedStorage.Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local TsunamiSystem = {}

export type TsunamiConfig = {
	Chance: number,
	Speed: number,
	ModelName: string?,
}

TsunamiSystem.TsunamiConfigs = {
	["Very Slow"] = {
		Chance = 25,
		Speed = 65,
	},
	["Slow"] = {
		Chance = 40,
		Speed = 80,
	},
	["Medium"] = {
		Chance = 60,
		Speed = 140,
	},
	["Fast"] = {
		Chance = 25,
		Speed = 225,
	},
	["Very Fast"] = {
		Chance = 15,
		Speed = 275,
	},
	["Extremely Fast"] = {
		Chance = 5,
		Speed = 325,
	},
}

local tsunamiRollOrder = {
	"Extremely Fast",
	"Very Fast",
	"Fast",
	"Medium",
	"Slow",
	"Very Slow",
}

local activeTweens: { [Instance]: Tween } = {}
local activeSounds: { [Instance]: Sound } = {}
local activeTouchConnections: { [Instance]: RBXScriptConnection } = {}
local disabledWorlds: { [string]: number } = {}
local recoveryBatchTokens: { [string]: number } = {}
local recoveryBatchKickoffThreads: { [string]: thread } = {}
local recoveryBatchThreads: { [string]: thread } = {}
local tsunamiTemplatesFolder = ReplicatedStorage:WaitForChild("Tsunamis")
local tsunamiSystemConfig = if CoreConfig.server and CoreConfig.server.tsunamiSystem
	then CoreConfig.server.tsunamiSystem
	else nil
local MIN_RANDOM_PATH_DISTANCE = if tsunamiSystemConfig and typeof(tsunamiSystemConfig.minRandomPathDistance) == "number"
	then math.max(0, tsunamiSystemConfig.minRandomPathDistance)
	else 200
local DISABLE_WAVES_RECOVERY_BATCH_COUNT = if tsunamiSystemConfig
		and typeof(tsunamiSystemConfig.disableWavesRecoveryBatchCount) == "number"
	then
		math.max(1, math.floor(tsunamiSystemConfig.disableWavesRecoveryBatchCount))
	else
		20
local DISABLE_WAVES_RECOVERY_BATCH_INTERVAL = if tsunamiSystemConfig
		and typeof(tsunamiSystemConfig.disableWavesRecoveryBatchInterval) == "number"
	then
		math.max(0, tsunamiSystemConfig.disableWavesRecoveryBatchInterval)
	else
		5
local DISABLE_WAVES_RECOVERY_TSUNAMIS = if tsunamiSystemConfig
		and typeof(tsunamiSystemConfig.disableWavesRecoveryTsunamis) == "table"
		and #tsunamiSystemConfig.disableWavesRecoveryTsunamis > 0
	then
		tsunamiSystemConfig.disableWavesRecoveryTsunamis
	else
		{ "Medium", "Fast", "Very Fast", "Extremely Fast" }

local function getWorld(worldName: string): Instance?
	local worldsFolder = Workspace:FindFirstChild("Worlds")
	if not worldsFolder then
		DebugModule.debugWarn("Workspace.Worlds folder not found", "TsunamiSystem")
		return nil
	end

	return worldsFolder:FindFirstChild(worldName)
end

local function getTsunamiFolder(worldName: string): Instance?
	local world = getWorld(worldName)
	if not world then
		DebugModule.debugWarn("World " .. worldName .. " not found", "TsunamiSystem")
		return nil
	end

	local tsunamiFolder = world:FindFirstChild("Tsunamis")
	if not tsunamiFolder then
		DebugModule.debugWarn("Tsunamis folder missing for " .. worldName, "TsunamiSystem")
		return nil
	end

	return tsunamiFolder
end

local function getPointsFolder(worldName: string, pointsFolderName: string?): Instance?
	local tsunamiFolder = getTsunamiFolder(worldName)
	if not tsunamiFolder then
		return nil
	end

	local resolvedFolderName = pointsFolderName or "Points"
	local pointsFolder = tsunamiFolder:FindFirstChild(resolvedFolderName)
	if not pointsFolder then
		DebugModule.debugWarn(resolvedFolderName .. " folder missing for " .. worldName, "TsunamiSystem")
		return nil
	end

	return pointsFolder
end

local function getPointCFrame(worldName: string, pointName: string, pointsFolderName: string?): CFrame?
	local pointsFolder = getPointsFolder(worldName, pointsFolderName)
	if not pointsFolder then
		return nil
	end

	local point = pointsFolder:FindFirstChild(pointName)
	if not point then
		DebugModule.debugWarn(pointName .. " point missing for " .. worldName, "TsunamiSystem")
		return nil
	end

	if point:IsA("BasePart") then
		return point.CFrame
	elseif point:IsA("Model") then
		return point:GetPivot()
	end

	DebugModule.debugWarn(pointName .. " point must be a BasePart or Model in " .. worldName, "TsunamiSystem")
	return nil
end

local function getTemplatePart(tsunamiName: string, config: TsunamiConfig): BasePart?
	local modelName = config.ModelName or tsunamiName
	local template = tsunamiTemplatesFolder:FindFirstChild(modelName)
	if not template then
		DebugModule.debugWarn(
			"Tsunami template " .. modelName .. " missing in ReplicatedStorage.Tsunamis",
			"TsunamiSystem"
		)
		return nil
	end

	if not template:IsA("BasePart") then
		DebugModule.debugWarn("Tsunami template " .. modelName .. " must be a BasePart", "TsunamiSystem")
		return nil
	end

	return template
end

local function cleanupTsunami(tsunamiPart: BasePart)
	local tween = activeTweens[tsunamiPart]
	if tween then
		tween:Cancel()
		activeTweens[tsunamiPart] = nil
	end

	local touchConnection = activeTouchConnections[tsunamiPart]
	if touchConnection then
		touchConnection:Disconnect()
		activeTouchConnections[tsunamiPart] = nil
	end

	local sound = activeSounds[tsunamiPart]
	if sound then
		activeSounds[tsunamiPart] = nil
		if sound.Parent then
			sound:Destroy()
		end
	end

	if tsunamiPart.Parent then
		tsunamiPart:Destroy()
	end
end

local function findHumanoidFromHit(hit: BasePart): Humanoid?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function getRandomSpawnCFrame(startCFrame: CFrame, endCFrame: CFrame): CFrame
	local baseStartPosition = startCFrame.Position
	local baseEndPosition = endCFrame.Position
	local pathVector = baseEndPosition - baseStartPosition
	local pathDistance = pathVector.Magnitude

	if pathDistance <= MIN_RANDOM_PATH_DISTANCE then
		return startCFrame
	end

	local direction = pathVector.Unit
	local maxStartAlpha = math.max(0, (pathDistance - MIN_RANDOM_PATH_DISTANCE) / pathDistance)
	local startAlpha = math.random() * maxStartAlpha

	local randomStartPosition = baseStartPosition + (direction * (pathDistance * startAlpha))
	return CFrame.new(randomStartPosition)
end

function TsunamiSystem.ResolveTsunamiName(tsunamiName: string): string?
	if TsunamiSystem.TsunamiConfigs[tsunamiName] then
		return tsunamiName
	end

	local normalizedName = string.lower(string.gsub(tsunamiName, "[%s_]+", ""))
	for configuredName, _ in pairs(TsunamiSystem.TsunamiConfigs) do
		local normalizedConfiguredName = string.lower(string.gsub(configuredName, "[%s_]+", ""))
		if normalizedConfiguredName == normalizedName then
			return configuredName
		end
	end

	return nil
end

function TsunamiSystem.GetTsunamiConfig(tsunamiName: string): TsunamiConfig?
	local resolvedName = TsunamiSystem.ResolveTsunamiName(tsunamiName)
	if not resolvedName then
		DebugModule.debugWarn("Missing tsunami config for " .. tsunamiName, "TsunamiSystem")
		return nil
	end

	return TsunamiSystem.TsunamiConfigs[resolvedName]
end

function TsunamiSystem.GetDebugPointsFolders(worldName: string): { Instance }
	local tsunamiFolder = getTsunamiFolder(worldName)
	if not tsunamiFolder then
		return {}
	end

	local debugFolders = {}
	for _, child in ipairs(tsunamiFolder:GetChildren()) do
		if string.find(child.Name, "PointsDebug_", 1, true) == 1 then
			table.insert(debugFolders, child)
		end
	end

	table.sort(debugFolders, function(a, b)
		return a.Name < b.Name
	end)

	return debugFolders
end

function TsunamiSystem.IsWorldDisabled(worldName: string): boolean
	local disabledUntil = disabledWorlds[worldName]
	if not disabledUntil then
		return false
	end

	if tick() >= disabledUntil then
		disabledWorlds[worldName] = nil
		return false
	end

	return true
end

local function cancelRecoveryBatchKickoffThread(worldName: string)
	local kickoffThread = recoveryBatchKickoffThreads[worldName]
	if kickoffThread then
		task.cancel(kickoffThread)
		recoveryBatchKickoffThreads[worldName] = nil
	end
end

local function cancelRecoveryBatchThread(worldName: string)
	local batchThread = recoveryBatchThreads[worldName]
	if batchThread then
		task.cancel(batchThread)
		recoveryBatchThreads[worldName] = nil
	end
end

function TsunamiSystem.DisableWorldTsunamis(worldName: string, duration: number)
	local durationSeconds = math.max(0, duration)
	recoveryBatchTokens[worldName] = (recoveryBatchTokens[worldName] or 0) + 1
	local disableToken = recoveryBatchTokens[worldName]

	cancelRecoveryBatchKickoffThread(worldName)
	cancelRecoveryBatchThread(worldName)

	disabledWorlds[worldName] = tick() + durationSeconds
	DebugModule.debugPrint(
		string.format("Disabled tsunami spawning in %s for %.1f seconds", worldName, duration),
		"TsunamiSystem"
	)

	if DISABLE_WAVES_RECOVERY_BATCH_COUNT <= 0 then
		return
	end

	if durationSeconds <= 0 then
		TsunamiSystem.StartDisableWavesRecoveryBatch(worldName)
		return
	end

	recoveryBatchKickoffThreads[worldName] = task.spawn(function()
		task.wait(durationSeconds)
		recoveryBatchKickoffThreads[worldName] = nil

		if recoveryBatchTokens[worldName] ~= disableToken then
			return
		end

		TsunamiSystem.StartDisableWavesRecoveryBatch(worldName)
	end)
end

function TsunamiSystem.StartDisableWavesRecoveryBatch(worldName: string, count: number?, interval: number?)
	local batchCount = math.max(0, math.floor(count or DISABLE_WAVES_RECOVERY_BATCH_COUNT))
	local batchInterval = math.max(0, interval or DISABLE_WAVES_RECOVERY_BATCH_INTERVAL)
	if batchCount <= 0 then
		return
	end

	local token = (recoveryBatchTokens[worldName] or 0) + 1
	recoveryBatchTokens[worldName] = token
	disabledWorlds[worldName] = tick() + (batchCount * batchInterval) + 0.25

	cancelRecoveryBatchKickoffThread(worldName)
	cancelRecoveryBatchThread(worldName)

	recoveryBatchThreads[worldName] = task.spawn(function()
		for spawnIndex = 1, batchCount do
			if recoveryBatchTokens[worldName] ~= token then
				if recoveryBatchThreads[worldName] == coroutine.running() then
					recoveryBatchThreads[worldName] = nil
				end
				return
			end

			local tsunamiName = DISABLE_WAVES_RECOVERY_TSUNAMIS[math.random(1, #DISABLE_WAVES_RECOVERY_TSUNAMIS)]
			TsunamiSystem.SpawnTsunami(worldName, tsunamiName)

			if spawnIndex < batchCount then
				task.wait(batchInterval)
			end
		end

		if recoveryBatchTokens[worldName] ~= token then
			if recoveryBatchThreads[worldName] == coroutine.running() then
				recoveryBatchThreads[worldName] = nil
			end
			return
		end

		recoveryBatchTokens[worldName] = nil
		disabledWorlds[worldName] = nil
		if recoveryBatchThreads[worldName] == coroutine.running() then
			recoveryBatchThreads[worldName] = nil
		end
		DebugModule.debugPrint(
			string.format(
				"Disable waves recovery batch finished in %s after %d spawns",
				worldName,
				batchCount
			),
			"TsunamiSystem"
		)
	end)
end

function TsunamiSystem.ClearWorldTsunamis(worldName: string)
	local tsunamiFolder = getTsunamiFolder(worldName)
	if not tsunamiFolder then
		return
	end

	for _, child in ipairs(tsunamiFolder:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "Start" and child.Name ~= "End" then
			cleanupTsunami(child)
		end
	end

	DebugModule.debugPrint("Cleared active tsunamis in " .. worldName, "TsunamiSystem")
end

function TsunamiSystem.SpawnCycleForWorld(worldName: string, useStartupPath: boolean?): BasePart?
	if TsunamiSystem.IsWorldDisabled(worldName) then
		return nil
	end

	local debugFolders = TsunamiSystem.GetDebugPointsFolders(worldName)
	if #debugFolders > 0 then
		local lastSpawnedTsunami: BasePart? = nil

		for _, debugFolder in ipairs(debugFolders) do
			local tsunamiName = string.gsub(debugFolder.Name, "^PointsDebug_", "")
			local spawnedTsunami = TsunamiSystem.SpawnTsunami(worldName, tsunamiName, debugFolder.Name, useStartupPath)
			if spawnedTsunami then
				lastSpawnedTsunami = spawnedTsunami
			end
		end

		return lastSpawnedTsunami
	end

	return TsunamiSystem.SpawnRandomTsunami(worldName, nil, useStartupPath)
end

function TsunamiSystem.RollTsunamiType(worldName: string): string?
	if not getWorld(worldName) then
		return nil
	end

	local successfulRolls = {}

	for _, tsunamiName in ipairs(tsunamiRollOrder) do
		local config = TsunamiSystem.TsunamiConfigs[tsunamiName]
		if config and math.random(1, 100) <= config.Chance then
			table.insert(successfulRolls, tsunamiName)
		end
	end

	if #successfulRolls > 0 then
		return successfulRolls[math.random(1, #successfulRolls)]
	end

	return "Medium"
end

function TsunamiSystem.SpawnTsunami(
	worldName: string,
	tsunamiName: string,
	pointsFolderName: string?,
	useStartupPath: boolean?
): BasePart?
	local resolvedTsunamiName = TsunamiSystem.ResolveTsunamiName(tsunamiName)
	if not resolvedTsunamiName then
		DebugModule.debugWarn("Missing tsunami config for " .. tsunamiName, "TsunamiSystem")
		return nil
	end

	local tsunamiConfig = TsunamiSystem.TsunamiConfigs[resolvedTsunamiName]
	if not tsunamiConfig then
		return nil
	end

	local startCFrame = getPointCFrame(worldName, "Start", pointsFolderName)
	local endPointName = "End"
	local endCFrame = getPointCFrame(worldName, endPointName, pointsFolderName)
	local template = getTemplatePart(resolvedTsunamiName, tsunamiConfig)
	local tsunamiFolder = getTsunamiFolder(worldName)

	if not startCFrame or not endCFrame or not template or not tsunamiFolder then
		return nil
	end

	local tsunamiPart = template:Clone()
	tsunamiPart.Parent = tsunamiFolder
	tsunamiPart:PivotTo(startCFrame)

	activeTouchConnections[tsunamiPart] = tsunamiPart.Touched:Connect(function(hit)
		local humanoid = findHumanoidFromHit(hit)
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = 0
		end
	end)

	local tsunamiSound = SoundService.PlayWorkspaceSound("Wave Crash", tsunamiPart)
	if tsunamiSound then
		activeSounds[tsunamiPart] = tsunamiSound
	end

	if useStartupPath == true then
		startCFrame = getRandomSpawnCFrame(startCFrame, endCFrame)
	end

	local startPosition = startCFrame.Position
	local endPosition = endCFrame.Position
	local pathVector = endPosition - startPosition
	local pathDistance = pathVector.Magnitude
	local duration = if tsunamiConfig.Speed > 0 then pathDistance / tsunamiConfig.Speed else 0

	if duration <= 0 or pathDistance <= 0 then
		tsunamiPart:PivotTo(endCFrame)
		cleanupTsunami(tsunamiPart)
		return nil
	end

	local direction = pathVector.Unit
	local startPivot = CFrame.lookAt(startPosition, startPosition + direction) * CFrame.Angles(0, math.rad(-90), 0)
	local targetPivot = CFrame.lookAt(endPosition, endPosition + direction) * CFrame.Angles(0, math.rad(-90), 0)
	local pivotToPartOffset = tsunamiPart:GetPivot():ToObjectSpace(tsunamiPart.CFrame)
	tsunamiPart:PivotTo(startPivot)

	local tween = TweenService:Create(tsunamiPart, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		CFrame = targetPivot * pivotToPartOffset,
	})
	activeTweens[tsunamiPart] = tween

	tween.Completed:Connect(function()
		cleanupTsunami(tsunamiPart)
	end)

	tween:Play()

	DebugModule.debugPrint(
		string.format("Spawned %s tsunami in %s using %s", resolvedTsunamiName, worldName, pointsFolderName or "Points"),
		"TsunamiSystem"
	)

	return tsunamiPart
end

function TsunamiSystem.SpawnRandomTsunami(
	worldName: string,
	pointsFolderName: string?,
	useStartupPath: boolean?
): BasePart?
	local tsunamiName = TsunamiSystem.RollTsunamiType(worldName)
	if not tsunamiName then
		return nil
	end

	return TsunamiSystem.SpawnTsunami(worldName, tsunamiName, pointsFolderName, useStartupPath)
end

return TsunamiSystem
