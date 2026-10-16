local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("DebugModule"))
local TsunamiTrajectory = require(ReplicatedStorage.Modules.TsunamiTrajectory)
local SharedFolder = game:GetService("ServerScriptService").Modules:WaitForChild("Shared")
local CoreConfig = require(SharedFolder:WaitForChild("CoreConfig_Server"))

local TsunamiSystem = {}

export type TsunamiConfig = {
	Chance: number,
	Speed: number,
	ModelName: string?,
}

type ActiveTsunamiState = {
	instance: Folder,
	worldName: string,
	startCFrame: CFrame,
	targetCFrame: CFrame,
	startServerTime: number,
	duration: number,
	hitHalfExtents: Vector3,
	previousWaveCFrame: CFrame?,
	previousPlayerPositions: { [Player]: Vector3 },
}

TsunamiSystem.TsunamiConfigs = {
	["Very Slow"] = {
		Chance = 25,
		Speed = 40,
	},
	["Slow"] = {
		Chance = 40,
		Speed = 70,
	},
	["Medium"] = {
		Chance = 60,
		Speed = 100,
	},
	["Fast"] = {
		Chance = 25,
		Speed = 175,
	},
	["Very Fast"] = {
		Chance = 15,
		Speed = 250,
	},
	["Extremely Fast"] = {
		Chance = 5,
		Speed = 300,
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

local activeStates: { [Folder]: ActiveTsunamiState } = {}
local disabledWorlds: { [string]: number } = {}
local disableExpiryThreads: { [string]: thread } = {}
local disableGenerations: { [string]: number } = {}
local hitEvaluationConnection: RBXScriptConnection? = nil
local hitEvaluationAccumulator = 0
local nextWaveId = 0
local recoverySerial = 0
local tsunamiTemplatesFolder = ReplicatedStorage:WaitForChild("Tsunamis")
local tsunamiSystemConfig = if CoreConfig.server and CoreConfig.server.tsunamiSystem
	then CoreConfig.server.tsunamiSystem
	else nil
local MIN_RANDOM_PATH_DISTANCE = if tsunamiSystemConfig
		and typeof(tsunamiSystemConfig.minRandomPathDistance) == "number"
	then math.max(0, tsunamiSystemConfig.minRandomPathDistance)
	else 200
local HIT_EVALUATION_INTERVAL = if tsunamiSystemConfig
		and typeof(tsunamiSystemConfig.hitEvaluationInterval) == "number"
	then math.clamp(tsunamiSystemConfig.hitEvaluationInterval, 0.025, 0.25)
	else 0.05
local HIT_PADDING = if tsunamiSystemConfig and typeof(tsunamiSystemConfig.hitPadding) == "number"
	then math.max(0, tsunamiSystemConfig.hitPadding)
	else 2

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
		local templateNames = {}
		for _, child in ipairs(tsunamiTemplatesFolder:GetChildren()) do
			table.insert(templateNames, child.Name .. ":" .. child.ClassName)
		end
		table.sort(templateNames)
		local templateParent = tsunamiTemplatesFolder.Parent
		DebugModule.debugWarn(
			string.format(
				"Template lookup failed | requested=%s | folder=%s | parent=%s | children=%s | serverTime=%.3f",
				modelName,
				tsunamiTemplatesFolder:GetFullName(),
				if templateParent then templateParent:GetFullName() else "nil",
				if #templateNames > 0 then table.concat(templateNames, ",") else "none",
				Workspace:GetServerTimeNow()
			),
			"TsunamiSystem"
		)
		return nil
	end

	if not template:IsA("BasePart") then
		DebugModule.debugWarn(
			string.format(
				"Template lookup failed | requested=%s | class=%s | path=%s | expected=BasePart",
				modelName,
				template.ClassName,
				template:GetFullName()
			),
			"TsunamiSystem"
		)
		return nil
	end

	return template
end

local function getOrCreateActiveStatesFolder(tsunamiFolder: Instance): Folder?
	local existingFolder = tsunamiFolder:FindFirstChild("ActiveStates")
	if existingFolder then
		if existingFolder:IsA("Folder") then
			return existingFolder
		end

		DebugModule.debugWarn("Tsunamis.ActiveStates must be a Folder", "TsunamiSystem")
		return nil
	end

	local activeStatesFolder = Instance.new("Folder")
	activeStatesFolder.Name = "ActiveStates"
	activeStatesFolder.Parent = tsunamiFolder
	return activeStatesFolder
end

local function stopHitEvaluator()
	if hitEvaluationConnection then
		hitEvaluationConnection:Disconnect()
		hitEvaluationConnection = nil
	end

	hitEvaluationAccumulator = 0
end

local function cleanupActiveState(state: Folder, reason: string)
	local activeState = activeStates[state]
	local elapsed = if activeState then math.max(0, Workspace:GetServerTimeNow() - activeState.startServerTime) else -1
	DebugModule.debugInfo(
		string.format(
			"Cleanup state | waveId=%s | reason=%s | elapsed=%.2fs | duration=%.2fs | parent=%s",
			tostring(state:GetAttribute("WaveId") or state.Name),
			reason,
			elapsed,
			if activeState then activeState.duration else -1,
			if state.Parent then state.Parent:GetFullName() else "nil"
		),
		"TsunamiSystem"
	)
	activeStates[state] = nil
	if state.Parent then
		state:Destroy()
	end
end

local function getLivingRootPosition(player: Player): (Humanoid?, Vector3?)
	local character = player.Character
	if not character then
		return nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart or not rootPart:IsA("BasePart") then
		return nil, nil
	end

	return humanoid, rootPart.Position
end

local function isPointInsideAxisAlignedBox(point: Vector3, halfExtents: Vector3): boolean
	return math.abs(point.X) <= halfExtents.X
		and math.abs(point.Y) <= halfExtents.Y
		and math.abs(point.Z) <= halfExtents.Z
end

local function isSegmentInsideAxisAlignedBox(startPoint: Vector3, endPoint: Vector3, halfExtents: Vector3): boolean
	if isPointInsideAxisAlignedBox(startPoint, halfExtents) or isPointInsideAxisAlignedBox(endPoint, halfExtents) then
		return true
	end

	local tMin = 0
	local tMax = 1

	local deltaX = endPoint.X - startPoint.X
	if math.abs(deltaX) < 0.000001 then
		if startPoint.X < -halfExtents.X or startPoint.X > halfExtents.X then
			return false
		end
	else
		local inverseDelta = 1 / deltaX
		local first = (-halfExtents.X - startPoint.X) * inverseDelta
		local second = (halfExtents.X - startPoint.X) * inverseDelta
		if first > second then
			first, second = second, first
		end
		tMin = math.max(tMin, first)
		tMax = math.min(tMax, second)
		if tMin > tMax then
			return false
		end
	end

	local deltaY = endPoint.Y - startPoint.Y
	if math.abs(deltaY) < 0.000001 then
		if startPoint.Y < -halfExtents.Y or startPoint.Y > halfExtents.Y then
			return false
		end
	else
		local inverseDelta = 1 / deltaY
		local first = (-halfExtents.Y - startPoint.Y) * inverseDelta
		local second = (halfExtents.Y - startPoint.Y) * inverseDelta
		if first > second then
			first, second = second, first
		end
		tMin = math.max(tMin, first)
		tMax = math.min(tMax, second)
		if tMin > tMax then
			return false
		end
	end

	local deltaZ = endPoint.Z - startPoint.Z
	if math.abs(deltaZ) < 0.000001 then
		return startPoint.Z >= -halfExtents.Z and startPoint.Z <= halfExtents.Z
	end

	local inverseDelta = 1 / deltaZ
	local first = (-halfExtents.Z - startPoint.Z) * inverseDelta
	local second = (halfExtents.Z - startPoint.Z) * inverseDelta
	if first > second then
		first, second = second, first
	end
	tMin = math.max(tMin, first)
	tMax = math.min(tMax, second)
	return tMin <= tMax
end

local function evaluateActiveStates()
	local now = Workspace:GetServerTimeNow()
	local players = Players:GetPlayers()

	for state, activeState in pairs(activeStates) do
		if not state.Parent then
			activeStates[state] = nil
			continue
		end

		local waveCFrame, hasExpired = TsunamiTrajectory.Sample(
			activeState.startCFrame,
			activeState.targetCFrame,
			activeState.startServerTime,
			activeState.duration,
			now
		)
		local previousWaveCFrame = activeState.previousWaveCFrame or waveCFrame
		for _, player in ipairs(players) do
			local humanoid, currentPosition = getLivingRootPosition(player)
			if humanoid and currentPosition and player:GetAttribute("Current_World") == activeState.worldName then
				local immunityUntil = player:GetAttribute("TsunamiImmunityUntil")
				if typeof(immunityUntil) == "number" and immunityUntil > now then
					activeState.previousPlayerPositions[player] = currentPosition
					continue
				elseif typeof(immunityUntil) == "number" and immunityUntil > 0 then
					player:SetAttribute("TsunamiImmunityUntil", 0)
				end

				local currentLocalPosition = waveCFrame:PointToObjectSpace(currentPosition)
				local previousPosition = activeState.previousPlayerPositions[player] or currentPosition
				local previousLocalPosition = previousWaveCFrame:PointToObjectSpace(previousPosition)
				local isInside = isSegmentInsideAxisAlignedBox(
					previousLocalPosition,
					currentLocalPosition,
					activeState.hitHalfExtents
				)

				if isInside and humanoid.Health > 0 then
					humanoid.Health = 0
				end

				activeState.previousPlayerPositions[player] = currentPosition
			else
				activeState.previousPlayerPositions[player] = nil
			end
		end
		activeState.previousWaveCFrame = waveCFrame

		if hasExpired then
			cleanupActiveState(state, "duration.expired")
		end
	end

	if next(activeStates) == nil then
		stopHitEvaluator()
	end
end

local function startHitEvaluator()
	if hitEvaluationConnection then
		return
	end

	hitEvaluationAccumulator = 0
	hitEvaluationConnection = RunService.Heartbeat:Connect(function(deltaTime)
		hitEvaluationAccumulator += deltaTime
		if hitEvaluationAccumulator < HIT_EVALUATION_INTERVAL then
			return
		end

		hitEvaluationAccumulator = 0
		evaluateActiveStates()
	end)
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

	if os.clock() >= disabledUntil then
		-- Keep expired disable state until recovery consumes it. This prevents
		-- the normal scheduler from racing the immediate recovery wave.
		return true
	end

	return true
end

function TsunamiSystem.SpawnRecoveryTsunami(worldName: string): Folder?
	local disabledUntil = disabledWorlds[worldName]
	if not disabledUntil or os.clock() < disabledUntil then
		return nil
	end

	disabledWorlds[worldName] = nil
	disableExpiryThreads[worldName] = nil
	disableGenerations[worldName] = nil
	recoverySerial += 1

	local world = getWorld(worldName)
	local canSpawn = world ~= nil and (worldName ~= "Minigame" or world:GetAttribute("RaceState") == "Racing")
	if not canSpawn then
		return nil
	end

	return TsunamiSystem.SpawnCycleForWorld(worldName)
end

function TsunamiSystem.GetRecoverySerial(): number
	return recoverySerial
end

function TsunamiSystem.DisableWorldTsunamis(worldName: string, duration: number)
	local durationSeconds = math.max(0, duration)
	local previousExpiryThread = disableExpiryThreads[worldName]
	if previousExpiryThread then
		pcall(task.cancel, previousExpiryThread)
		disableExpiryThreads[worldName] = nil
	end

	local generation = (disableGenerations[worldName] or 0) + 1
	disableGenerations[worldName] = generation
	local disabledUntil = os.clock() + durationSeconds
	disabledWorlds[worldName] = disabledUntil

	DebugModule.debugPrint(
		string.format("Disabled tsunami spawning in %s for %.1f seconds", worldName, duration),
		"TsunamiSystem"
	)

	if durationSeconds <= 0 then
		disabledWorlds[worldName] = nil
		disableGenerations[worldName] = nil
		return
	end

	disableExpiryThreads[worldName] = task.delay(durationSeconds, function()
		if disableGenerations[worldName] ~= generation then
			return
		end

		local currentDisabledUntil = disabledWorlds[worldName]
		if currentDisabledUntil ~= disabledUntil then
			return
		end

		local recoveryWave = TsunamiSystem.SpawnRecoveryTsunami(worldName)
		if recoveryWave then
			DebugModule.debugPrint(
				"Spawned recovery tsunami after disable-waves cooldown | world=" .. worldName,
				"TsunamiSystem"
			)
		end
	end)
end

function TsunamiSystem.ClearWorldTsunamis(worldName: string)
	local tsunamiFolder = getTsunamiFolder(worldName)
	if not tsunamiFolder then
		return
	end

	for state, activeState in pairs(activeStates) do
		if activeState.worldName == worldName then
			cleanupActiveState(state, "world.clear")
		end
	end

	for _, child in ipairs(tsunamiFolder:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= "Start" and child.Name ~= "End" then
			child:Destroy()
		elseif child:IsA("Folder") and child.Name == "ActiveStates" then
			for _, state in ipairs(child:GetChildren()) do
				state:Destroy()
			end
		end
	end

	if next(activeStates) == nil then
		stopHitEvaluator()
	end
	DebugModule.debugPrint("Cleared active tsunamis in " .. worldName, "TsunamiSystem")
end

function TsunamiSystem.Destroy()
	stopHitEvaluator()
	for state in pairs(activeStates) do
		cleanupActiveState(state, "system.destroy")
	end

	table.clear(activeStates)
	table.clear(disabledWorlds)
	recoverySerial = 0
	for worldName, expiryThread in pairs(disableExpiryThreads) do
		pcall(task.cancel, expiryThread)
		disableExpiryThreads[worldName] = nil
		disableGenerations[worldName] = nil
	end
	DebugModule.debugPrint("TsunamiSystem destroyed active runtime state", "TsunamiSystem")
end

function TsunamiSystem.SpawnCycleForWorld(worldName: string, useStartupPath: boolean?): Folder?
	if TsunamiSystem.IsWorldDisabled(worldName) then
		return nil
	end

	local debugFolders = TsunamiSystem.GetDebugPointsFolders(worldName)
	if #debugFolders > 0 then
		local lastSpawnedTsunami: Folder? = nil

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
): Folder?
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
	local endCFrame = getPointCFrame(worldName, "End", pointsFolderName)
	local template = getTemplatePart(resolvedTsunamiName, tsunamiConfig)
	local tsunamiFolder = getTsunamiFolder(worldName)

	if not startCFrame or not endCFrame or not template or not tsunamiFolder then
		return nil
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
		return nil
	end

	local direction = pathVector.Unit
	local startPivot = CFrame.lookAt(startPosition, startPosition + direction) * CFrame.Angles(0, math.rad(-90), 0)
	local targetPivot = CFrame.lookAt(endPosition, endPosition + direction) * CFrame.Angles(0, math.rad(-90), 0)
	local pivotToPartOffset = template:GetPivot():ToObjectSpace(template.CFrame)
	local startPartCFrame = startPivot * pivotToPartOffset
	local targetPartCFrame = targetPivot * pivotToPartOffset
	local activeStatesFolder = getOrCreateActiveStatesFolder(tsunamiFolder)
	if not activeStatesFolder then
		return nil
	end

	nextWaveId += 1
	local startServerTime = Workspace:GetServerTimeNow()
	local state = Instance.new("Folder")
	state.Name = string.format("Wave_%d", nextWaveId)
	state:SetAttribute("WaveId", nextWaveId)
	state:SetAttribute("WorldName", worldName)
	state:SetAttribute("TsunamiName", resolvedTsunamiName)
	state:SetAttribute("TemplateName", tsunamiConfig.ModelName or resolvedTsunamiName)
	state:SetAttribute("StartCFrame", startPartCFrame)
	state:SetAttribute("TargetCFrame", targetPartCFrame)
	state:SetAttribute("StartServerTime", startServerTime)
	state:SetAttribute("Duration", duration)
	state:SetAttribute("VisualSize", template.Size)
	state.Parent = activeStatesFolder

	activeStates[state] = {
		instance = state,
		worldName = worldName,
		startCFrame = startPartCFrame,
		targetCFrame = targetPartCFrame,
		startServerTime = state:GetAttribute("StartServerTime") :: number,
		duration = duration,
		hitHalfExtents = (template.Size * 0.5) + Vector3.new(HIT_PADDING, HIT_PADDING, HIT_PADDING),
		previousWaveCFrame = nil,
		previousPlayerPositions = {},
	}
	startHitEvaluator()

	DebugModule.debugPrint(
		string.format(
			"Spawned tsunami state | waveId=%d | name=%s | world=%s | template=%s | points=%s | start=(%.1f,%.1f,%.1f) | target=(%.1f,%.1f,%.1f) | duration=%.2fs | serverTime=%.3f | stateParent=%s | activeStateCount=%d",
			nextWaveId,
			resolvedTsunamiName,
			worldName,
			tsunamiConfig.ModelName or resolvedTsunamiName,
			pointsFolderName or "Points",
			startPartCFrame.Position.X,
			startPartCFrame.Position.Y,
			startPartCFrame.Position.Z,
			targetPartCFrame.Position.X,
			targetPartCFrame.Position.Y,
			targetPartCFrame.Position.Z,
			duration,
			startServerTime,
			activeStatesFolder:GetFullName(),
			#activeStatesFolder:GetChildren()
		),
		"TsunamiSystem"
	)

	return state
end

function TsunamiSystem.SpawnRandomTsunami(
	worldName: string,
	pointsFolderName: string?,
	useStartupPath: boolean?
): Folder?
	local tsunamiName = TsunamiSystem.RollTsunamiType(worldName)
	if not tsunamiName then
		return nil
	end

	return TsunamiSystem.SpawnTsunami(worldName, tsunamiName, pointsFolderName, useStartupPath)
end

return TsunamiSystem
