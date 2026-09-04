--!strict

local RunService = game:GetService("RunService")
local SoundService = require(game:GetService("ReplicatedStorage").Modules.SoundService)
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig)

type VisualConfig = {
	enabled: boolean,
	billboardMaxDistance: number,
	disableShadows: boolean,
	soundGraceSeconds: number,
}

type StateBinding = {
	state: Folder,
	maid: any,
	visualMaid: any?,
	visual: BasePart?,
	templateName: string?,
	startCFrame: CFrame?,
	targetCFrame: CFrame?,
	startServerTime: number?,
	duration: number?,
}

type StateData = {
	templateName: string,
	startCFrame: CFrame,
	targetCFrame: CFrame,
	startServerTime: number,
	duration: number,
	visualSize: Vector3,
}

type WorldBinding = {
	world: Instance,
	maid: any,
	tsunamiMaid: any?,
	activeStatesMaid: any?,
	states: { [Folder]: StateBinding },
	visualFolder: Folder?,
	activeStatesFolder: Folder?,
	tsunamiFolder: Instance?,
}

type ServiceState = {
	maid: any,
	worldBindings: { [Instance]: WorldBinding },
	worldsFolder: Instance?,
	worldsMaid: any?,
	isRunning: boolean,
}

local TsunamiVisualService = {}
local serviceState: ServiceState? = nil
local tsunamiTemplatesFolder = ReplicatedStorage:WaitForChild("Tsunamis")

local DEFAULT_CONFIG: VisualConfig = {
	enabled = true,
	billboardMaxDistance = 450,
	disableShadows = true,
	soundGraceSeconds = 1.5,
}

local function getConfig(): VisualConfig
	local rawConfig = CoreConfig.clientTsunamiVisuals
	if typeof(rawConfig) ~= "table" then
		return table.clone(DEFAULT_CONFIG)
	end

	local billboardMaxDistance = if typeof(rawConfig.billboardMaxDistance) == "number"
		then math.max(0, rawConfig.billboardMaxDistance)
		else DEFAULT_CONFIG.billboardMaxDistance
	local soundGraceSeconds = if typeof(rawConfig.soundGraceSeconds) == "number"
		then math.max(0, rawConfig.soundGraceSeconds)
		else DEFAULT_CONFIG.soundGraceSeconds

	return {
		enabled = rawConfig.enabled ~= false,
		billboardMaxDistance = billboardMaxDistance,
		disableShadows = rawConfig.disableShadows ~= false,
		soundGraceSeconds = soundGraceSeconds,
	}
end

local function cleanupVisual(binding: StateBinding)
	if binding.visualMaid then
		binding.visualMaid:DoCleaning()
		binding.visualMaid = nil
	end

	binding.visual = nil
end

local function getVisualFolder(binding: WorldBinding): Folder?
	local existingFolder = binding.world:FindFirstChild("ClientTsunamiVisuals")
	if existingFolder then
		if existingFolder:IsA("Folder") then
			binding.visualFolder = existingFolder
			return existingFolder
		end

		DebugModule.debugWarn(
			"ClientTsunamiVisuals exists but is not a Folder in " .. binding.world:GetFullName(),
			"TsunamiVisualService"
		)
		return nil
	end

	local visualFolder = Instance.new("Folder")
	visualFolder.Name = "ClientTsunamiVisuals"
	visualFolder:SetAttribute("DisableClientCulling", true)
	visualFolder.Parent = binding.world
	binding.visualFolder = visualFolder
	return visualFolder
end

local function configureVisual(visual: BasePart, config: VisualConfig)
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanTouch = false
	visual.CanQuery = false
	if config.disableShadows then
		visual.CastShadow = false
	end

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			if config.disableShadows then
				descendant.CastShadow = false
			end
		elseif descendant:IsA("BillboardGui") then
			descendant.MaxDistance = config.billboardMaxDistance
		end
	end
end

local function readStateAttributes(state: Folder): StateData?
	local templateName = state:GetAttribute("TemplateName")
	local startCFrame = state:GetAttribute("StartCFrame")
	local targetCFrame = state:GetAttribute("TargetCFrame")
	local startServerTime = state:GetAttribute("StartServerTime")
	local duration = state:GetAttribute("Duration")
	local visualSize = state:GetAttribute("VisualSize")

	if typeof(templateName) ~= "string"
		or typeof(startCFrame) ~= "CFrame"
		or typeof(targetCFrame) ~= "CFrame"
		or typeof(startServerTime) ~= "number"
		or typeof(duration) ~= "number"
		or typeof(visualSize) ~= "Vector3"
		or duration <= 0
	then
		return nil
	end

	return {
		templateName = templateName,
		startCFrame = startCFrame,
		targetCFrame = targetCFrame,
		startServerTime = startServerTime,
		duration = duration,
		visualSize = visualSize,
	}
end

local function refreshStateVisual(binding: StateBinding, worldBinding: WorldBinding)
	local config = getConfig()
	if not config.enabled then
		cleanupVisual(binding)
		return
	end
	if not binding.state.Parent then
		return
	end

	local stateData = readStateAttributes(binding.state)
	if not stateData then
		return
	end

	local templateName = stateData.templateName
	local startCFrame = stateData.startCFrame
	local targetCFrame = stateData.targetCFrame
	local startServerTime = stateData.startServerTime
	local duration = stateData.duration
	local visualSize = stateData.visualSize

	if binding.visual and binding.visual.Parent
		and binding.templateName == templateName
		and binding.startCFrame == startCFrame
		and binding.targetCFrame == targetCFrame
		and binding.startServerTime == startServerTime
		and binding.duration == duration
	then
		return
	end

	cleanupVisual(binding)

	local now = Workspace:GetServerTimeNow()
	local elapsed = now - startServerTime
	if elapsed >= duration then
		return
	end

	local template = tsunamiTemplatesFolder:FindFirstChild(templateName)
	if not template or not template:IsA("BasePart") then
		DebugModule.debugWarn(
			"Missing client tsunami template " .. templateName .. " for " .. binding.state:GetFullName(),
			"TsunamiVisualService"
		)
		return
	end

	local visualFolder = getVisualFolder(worldBinding)
	if not visualFolder then
		return
	end

	local visual = template:Clone()
	visual.Name = "ClientTsunami_" .. tostring(binding.state:GetAttribute("WaveId") or binding.state.Name)
	visual:SetAttribute("DisableClientCulling", true)
	configureVisual(visual, config)

	local clampedElapsed = math.max(0, elapsed)
	local alpha = math.clamp(clampedElapsed / duration, 0, 1)
	visual.CFrame = startCFrame:Lerp(targetCFrame, alpha)
	visual.Parent = visualFolder

	local visualMaid = Maid.new()
	visualMaid:GiveTask(visual)
	binding.visualMaid = visualMaid
	binding.visual = visual
	binding.templateName = templateName
	binding.startCFrame = startCFrame
	binding.targetCFrame = targetCFrame
	binding.startServerTime = startServerTime
	binding.duration = duration

	local remaining = duration - clampedElapsed
	local tween = TweenService:Create(visual, TweenInfo.new(remaining, Enum.EasingStyle.Linear), {
		CFrame = targetCFrame,
	})
	visualMaid:GiveTask(tween)
	tween:Play()

	if clampedElapsed <= config.soundGraceSeconds then
		local sound = SoundService.PlayWorkspaceSound("Wave Crash", visual)
		if sound then
			visualMaid:GiveTask(sound)
		end
	end

	DebugModule.debugInfo(
		string.format("Bound %s tsunami visual; remaining=%.2fs", templateName, remaining),
		"TsunamiVisualService"
	)

	-- The size attribute is read to validate the replicated state contract.
	if visual.Size ~= visualSize then
		DebugModule.debugWarn(
			"Client tsunami template size differs from server state for " .. templateName,
			"TsunamiVisualService"
		)
	end
end

local function cleanupState(worldBinding: WorldBinding, state: Folder)
	local binding = worldBinding.states[state]
	if not binding then
		return
	end

	worldBinding.states[state] = nil
	binding.maid:DoCleaning()
end

local function bindState(worldBinding: WorldBinding, state: Instance)
	if not state:IsA("Folder") or worldBinding.states[state] then
		return
	end

	local stateBinding: StateBinding = {
		state = state,
		maid = Maid.new(),
		visualMaid = nil,
		visual = nil,
		templateName = nil,
		startCFrame = nil,
		targetCFrame = nil,
		startServerTime = nil,
		duration = nil,
	}
	worldBinding.states[state] = stateBinding
	stateBinding.maid:GiveTask(function()
		cleanupVisual(stateBinding)
	end)

	stateBinding.maid:GiveTask(state.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupState(worldBinding, state)
		end
	end))
	for _, attributeName in ipairs({
		"TemplateName",
		"StartCFrame",
		"TargetCFrame",
		"StartServerTime",
		"Duration",
		"VisualSize",
	}) do
		stateBinding.maid:GiveTask(state:GetAttributeChangedSignal(attributeName):Connect(function()
			refreshStateVisual(stateBinding, worldBinding)
		end))
	end

	refreshStateVisual(stateBinding, worldBinding)
end

local function bindActiveStatesFolder(worldBinding: WorldBinding, activeStatesFolder: Instance)
	if not activeStatesFolder:IsA("Folder") then
		DebugModule.debugWarn(
			"ActiveStates is not a Folder in " .. worldBinding.world:GetFullName(),
			"TsunamiVisualService"
		)
		return
	end

	if worldBinding.activeStatesFolder == activeStatesFolder then
		return
	end

	if worldBinding.activeStatesMaid then
		worldBinding.activeStatesMaid:DoCleaning()
		worldBinding.activeStatesMaid = nil
	end
	for state in pairs(worldBinding.states) do
		cleanupState(worldBinding, state)
	end

	worldBinding.activeStatesFolder = activeStatesFolder
	local activeStatesMaid = Maid.new()
	worldBinding.activeStatesMaid = activeStatesMaid
	activeStatesMaid:GiveTask(activeStatesFolder.ChildAdded:Connect(function(child)
		bindState(worldBinding, child)
	end))
	activeStatesMaid:GiveTask(activeStatesFolder.ChildRemoved:Connect(function(child)
		if child:IsA("Folder") then
			cleanupState(worldBinding, child)
		end
	end))

	for _, state in ipairs(activeStatesFolder:GetChildren()) do
		bindState(worldBinding, state)
	end
end

local function bindTsunamiFolder(worldBinding: WorldBinding, tsunamiFolder: Instance)
	if worldBinding.tsunamiFolder == tsunamiFolder then
		return
	end

	if worldBinding.tsunamiMaid then
		worldBinding.tsunamiMaid:DoCleaning()
		worldBinding.tsunamiMaid = nil
	end
	if worldBinding.activeStatesMaid then
		worldBinding.activeStatesMaid:DoCleaning()
		worldBinding.activeStatesMaid = nil
	end
	for state in pairs(worldBinding.states) do
		cleanupState(worldBinding, state)
	end

	worldBinding.tsunamiFolder = tsunamiFolder
	local tsunamiMaid = Maid.new()
	worldBinding.tsunamiMaid = tsunamiMaid
	local activeStatesFolder = tsunamiFolder:FindFirstChild("ActiveStates")
	if activeStatesFolder then
		bindActiveStatesFolder(worldBinding, activeStatesFolder)
	end

	tsunamiMaid:GiveTask(tsunamiFolder.ChildAdded:Connect(function(child)
		if child.Name == "ActiveStates" then
			bindActiveStatesFolder(worldBinding, child)
		end
	end))
	tsunamiMaid:GiveTask(tsunamiFolder.ChildRemoved:Connect(function(child)
		if child == worldBinding.activeStatesFolder then
			for state in pairs(worldBinding.states) do
				cleanupState(worldBinding, state)
			end
			if worldBinding.activeStatesMaid then
				worldBinding.activeStatesMaid:DoCleaning()
				worldBinding.activeStatesMaid = nil
			end
			worldBinding.activeStatesFolder = nil
		end
	end))
end

local function refreshWorldVisuals(worldBinding: WorldBinding)
	for _, stateBinding in pairs(worldBinding.states) do
		refreshStateVisual(stateBinding, worldBinding)
	end
end

local function cleanupWorld(state: ServiceState, world: Instance)
	local worldBinding = state.worldBindings[world]
	if not worldBinding then
		return
	end

	state.worldBindings[world] = nil
	for stateFolder in pairs(worldBinding.states) do
		cleanupState(worldBinding, stateFolder)
	end
	if worldBinding.tsunamiMaid then
		worldBinding.tsunamiMaid:DoCleaning()
		worldBinding.tsunamiMaid = nil
	end
	if worldBinding.activeStatesMaid then
		worldBinding.activeStatesMaid:DoCleaning()
		worldBinding.activeStatesMaid = nil
	end
	worldBinding.maid:DoCleaning()
	if worldBinding.visualFolder and worldBinding.visualFolder.Parent then
		worldBinding.visualFolder:Destroy()
	end
end

local function bindWorld(state: ServiceState, world: Instance)
	if state.worldBindings[world] then
		return
	end

	local worldBinding: WorldBinding = {
		world = world,
		maid = Maid.new(),
		tsunamiMaid = nil,
		activeStatesMaid = nil,
		states = {},
		visualFolder = nil,
		activeStatesFolder = nil,
		tsunamiFolder = nil,
	}
	state.worldBindings[world] = worldBinding

	worldBinding.maid:GiveTask(world.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupWorld(state, world)
		end
	end))
	worldBinding.maid:GiveTask(world.ChildAdded:Connect(function(child)
		if child.Name == "Tsunamis" then
			bindTsunamiFolder(worldBinding, child)
		elseif child.Name == "ClientTsunamiVisuals" and child:IsA("Folder") then
			worldBinding.visualFolder = child
			refreshWorldVisuals(worldBinding)
		end
	end))
	worldBinding.maid:GiveTask(world.ChildRemoved:Connect(function(child)
		if child == worldBinding.tsunamiFolder then
			for stateFolder in pairs(worldBinding.states) do
				cleanupState(worldBinding, stateFolder)
			end
			if worldBinding.tsunamiMaid then
				worldBinding.tsunamiMaid:DoCleaning()
				worldBinding.tsunamiMaid = nil
			end
			if worldBinding.activeStatesMaid then
				worldBinding.activeStatesMaid:DoCleaning()
				worldBinding.activeStatesMaid = nil
			end
			worldBinding.tsunamiFolder = nil
			worldBinding.activeStatesFolder = nil
		elseif child == worldBinding.visualFolder then
			worldBinding.visualFolder = nil
			refreshWorldVisuals(worldBinding)
		end
	end))

	local tsunamiFolder = world:FindFirstChild("Tsunamis")
	if tsunamiFolder then
		bindTsunamiFolder(worldBinding, tsunamiFolder)
	end
end

local function bindWorldsFolder(state: ServiceState, worldsFolder: Instance)
	if state.worldsFolder == worldsFolder then
		return
	end

	if state.worldsMaid then
		state.worldsMaid:DoCleaning()
		state.worldsMaid = nil
	end
	for world in pairs(state.worldBindings) do
		cleanupWorld(state, world)
	end

	state.worldsFolder = worldsFolder
	local worldsMaid = Maid.new()
	state.worldsMaid = worldsMaid
	worldsMaid:GiveTask(worldsFolder.ChildAdded:Connect(function(world)
		bindWorld(state, world)
	end))
	worldsMaid:GiveTask(worldsFolder.ChildRemoved:Connect(function(world)
		cleanupWorld(state, world)
	end))

	for _, world in ipairs(worldsFolder:GetChildren()) do
		bindWorld(state, world)
	end
end

function TsunamiVisualService.Start()
	if serviceState and serviceState.isRunning then
		return
	end
	if not RunService:IsClient() then
		return
	end

	local state: ServiceState = {
		maid = Maid.new(),
		worldBindings = {},
		worldsFolder = nil,
		worldsMaid = nil,
		isRunning = true,
	}
	serviceState = state

	local config = getConfig()
	if not config.enabled then
		DebugModule.debugInfo("Tsunami visual service disabled by config", "TsunamiVisualService")
		return
	end

	local function onWorldsFolderAdded(child: Instance)
		if child.Name == "Worlds" then
			bindWorldsFolder(state, child)
		end
	end

	state.maid:GiveTask(Workspace.ChildAdded:Connect(onWorldsFolderAdded))
	state.maid:GiveTask(Workspace.ChildRemoved:Connect(function(child)
		if child ~= state.worldsFolder then
			return
		end

		if state.worldsMaid then
			state.worldsMaid:DoCleaning()
			state.worldsMaid = nil
		end
		for world in pairs(state.worldBindings) do
			cleanupWorld(state, world)
		end
		state.worldsFolder = nil
	end))
	local worldsFolder = Workspace:FindFirstChild("Worlds") or Workspace:WaitForChild("Worlds", 15)
	if worldsFolder then
		bindWorldsFolder(state, worldsFolder)
	else
		DebugModule.debugWarn("Workspace.Worlds was not available within 15 seconds", "TsunamiVisualService")
	end

	state.maid:GiveTask(function()
		state.isRunning = false
		if state.worldsMaid then
			state.worldsMaid:DoCleaning()
			state.worldsMaid = nil
		end
		for world in pairs(state.worldBindings) do
			cleanupWorld(state, world)
		end
		table.clear(state.worldBindings)
		state.worldsFolder = nil
	end)

	DebugModule.debugInfo("Tsunami visual service started", "TsunamiVisualService")
end

function TsunamiVisualService.Stop()
	local state = serviceState
	if not state then
		return
	end

	serviceState = nil
	state.isRunning = false
	state.maid:DoCleaning()
	table.clear(state.worldBindings)
	DebugModule.debugInfo("Tsunami visual service stopped", "TsunamiVisualService")
end

return TsunamiVisualService
