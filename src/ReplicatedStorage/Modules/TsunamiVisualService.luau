local RunService = game:GetService("RunService")
local SoundService = require(game:GetService("ReplicatedStorage").Modules.SoundService)
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local TsunamiTrajectory = require(ReplicatedStorage.Modules.TsunamiTrajectory)

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
	lastInvalidAttributes: string?,
	expiredLogged: boolean,
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
	liveEventState: Folder?,
	liveEventStateMaid: any?,
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

local function getAttributeTypeSummary(state: Folder): string
	return string.format(
		"TemplateName=%s,StartCFrame=%s,TargetCFrame=%s,StartServerTime=%s,Duration=%s,VisualSize=%s",
		typeof(state:GetAttribute("TemplateName")),
		typeof(state:GetAttribute("StartCFrame")),
		typeof(state:GetAttribute("TargetCFrame")),
		typeof(state:GetAttribute("StartServerTime")),
		typeof(state:GetAttribute("Duration")),
		typeof(state:GetAttribute("VisualSize"))
	)
end

local function getTemplateFolderSummary(): string
	local templateNames = {}
	for _, child in ipairs(tsunamiTemplatesFolder:GetChildren()) do
		table.insert(templateNames, child.Name .. ":" .. child.ClassName)
	end
	table.sort(templateNames)
	return if #templateNames > 0 then table.concat(templateNames, ",") else "none"
end

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

local function isBloodmoonActive(): boolean
	local liveEventState = ReplicatedStorage:FindFirstChild("LiveEventState")
	if not liveEventState or not liveEventState:IsA("Folder") then
		return false
	end

	local activeEventIds = liveEventState:GetAttribute("ActiveEventIds")
	return typeof(activeEventIds) == "string"
		and string.find("," .. activeEventIds .. ",", ",Bloodmoon,", 1, true) ~= nil
end

local function getTemplate(templateName: string): BasePart?
	local template = tsunamiTemplatesFolder:FindFirstChild(templateName)
	return if template and template:IsA("BasePart") then template else nil
end

local function applyBillboardTextColor(visual: BasePart, sourceTemplate: BasePart, colorTemplate: BasePart)
	local visualBillboard = visual:FindFirstChild("BillboardGui", true)
	local sourceBillboard = sourceTemplate:FindFirstChild("BillboardGui", true)
	local colorBillboard = colorTemplate:FindFirstChild("BillboardGui", true)
	if not visualBillboard or not sourceBillboard or not colorBillboard then
		return
	end

	for _, sourceDescendant in ipairs(sourceBillboard:GetDescendants()) do
		if not sourceDescendant:IsA("TextLabel") and not sourceDescendant:IsA("TextButton") then
			continue
		end

		local visualText = visualBillboard:FindFirstChild(sourceDescendant.Name, true)
		local colorText = colorBillboard:FindFirstChild(sourceDescendant.Name, true)
		if not visualText or not colorText then
			continue
		end
		if not visualText:IsA("TextLabel") and not visualText:IsA("TextButton") then
			continue
		end
		if not colorText:IsA("TextLabel") and not colorText:IsA("TextButton") then
			continue
		end

		visualText.TextColor3 = colorText.TextColor3
		local sourceGradient = sourceDescendant:FindFirstChildOfClass("UIGradient")
		local colorGradient = colorText:FindFirstChildOfClass("UIGradient")
		local visualGradient = visualText:FindFirstChildOfClass("UIGradient")
		if sourceGradient and colorGradient and visualGradient then
			visualGradient.Color = colorGradient.Color
			visualGradient.Rotation = colorGradient.Rotation
		end
	end
end

local function applyVisualColor(visual: BasePart, templateName: string)
	local sourceTemplate = getTemplate(templateName)
	local colorTemplate = if isBloodmoonActive() then getTemplate("Extremely Fast") else sourceTemplate
	if colorTemplate then
		visual.Color = colorTemplate.Color
		if sourceTemplate then
			applyBillboardTextColor(visual, sourceTemplate, colorTemplate)
		end
	end
end

local function cleanupVisual(binding: StateBinding, reason: string)
	if binding.visualMaid then
		local visual = binding.visual
		DebugModule.debugInfo(
			string.format(
				"Cleanup visual | waveId=%s | reason=%s | visualParent=%s | position=%s",
				tostring(binding.state:GetAttribute("WaveId") or binding.state.Name),
				reason,
				if visual and visual.Parent then visual.Parent:GetFullName() else "nil",
				if visual then tostring(visual.Position) else "nil"
			),
			"TsunamiVisualService"
		)
		binding.visualMaid:DoCleaning()
		binding.visualMaid = nil
	end

	binding.visual = nil
end

local function updateBoundVisuals(state: ServiceState)
	local serverTime = Workspace:GetServerTimeNow()
	for _, worldBinding in pairs(state.worldBindings) do
		for _, binding in pairs(worldBinding.states) do
			local visual = binding.visual
			local startCFrame = binding.startCFrame
			local targetCFrame = binding.targetCFrame
			local startServerTime = binding.startServerTime
			local duration = binding.duration
			if
				not visual
				or not visual.Parent
				or not startCFrame
				or not targetCFrame
				or not startServerTime
				or not duration
			then
				continue
			end

			local visualCFrame, isComplete = TsunamiTrajectory.Sample(
				startCFrame,
				targetCFrame,
				startServerTime,
				duration,
				serverTime
			)
			if isComplete then
				cleanupVisual(binding, "duration.expired")
				continue
			end

			visual.CFrame = visualCFrame
		end
	end
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

local function readStateAttributes(state: Folder): (StateData?, string?)
	local templateName = state:GetAttribute("TemplateName")
	local startCFrame = state:GetAttribute("StartCFrame")
	local targetCFrame = state:GetAttribute("TargetCFrame")
	local startServerTime = state:GetAttribute("StartServerTime")
	local duration = state:GetAttribute("Duration")
	local visualSize = state:GetAttribute("VisualSize")

	if
		typeof(templateName) ~= "string"
		or typeof(startCFrame) ~= "CFrame"
		or typeof(targetCFrame) ~= "CFrame"
		or typeof(startServerTime) ~= "number"
		or typeof(duration) ~= "number"
		or typeof(visualSize) ~= "Vector3"
		or duration <= 0
	then
		return nil, getAttributeTypeSummary(state)
	end

	return {
		templateName = templateName,
		startCFrame = startCFrame,
		targetCFrame = targetCFrame,
		startServerTime = startServerTime,
		duration = duration,
		visualSize = visualSize,
	},
		nil
end

local function refreshStateVisual(binding: StateBinding, worldBinding: WorldBinding)
	local config = getConfig()
	if not config.enabled then
		cleanupVisual(binding, "config.disabled")
		return
	end
	if not binding.state.Parent then
		return
	end

	local stateData, invalidAttributes = readStateAttributes(binding.state)
	if not stateData then
		if binding.lastInvalidAttributes ~= invalidAttributes then
			binding.lastInvalidAttributes = invalidAttributes
			DebugModule.debugWarn(
				string.format(
					"State attributes incomplete | waveId=%s | path=%s | fields=%s | stateParent=%s",
					tostring(binding.state:GetAttribute("WaveId") or binding.state.Name),
					binding.state:GetFullName(),
					invalidAttributes or "unknown",
					if binding.state.Parent then binding.state.Parent:GetFullName() else "nil"
				),
				"TsunamiVisualService"
			)
		end
		return
	end
	if binding.lastInvalidAttributes then
		DebugModule.debugInfo(
			string.format(
				"State attributes recovered | waveId=%s | fields=%s",
				tostring(binding.state:GetAttribute("WaveId") or binding.state.Name),
				binding.lastInvalidAttributes
			),
			"TsunamiVisualService"
		)
		binding.lastInvalidAttributes = nil
	end
	binding.expiredLogged = false

	local templateName = stateData.templateName
	local startCFrame = stateData.startCFrame
	local targetCFrame = stateData.targetCFrame
	local startServerTime = stateData.startServerTime
	local duration = stateData.duration
	local visualSize = stateData.visualSize

	if
		binding.visual
		and binding.visual.Parent
		and binding.templateName == templateName
		and binding.startCFrame == startCFrame
		and binding.targetCFrame == targetCFrame
		and binding.startServerTime == startServerTime
		and binding.duration == duration
	then
		return
	end

	cleanupVisual(binding, "state.changed")

	local now = Workspace:GetServerTimeNow()
	local elapsed = now - startServerTime
	if elapsed >= duration then
		if not binding.expiredLogged then
			binding.expiredLogged = true
			DebugModule.debugWarn(
				string.format(
					"State arrived too late for visual | waveId=%s | template=%s | age=%.2fs | duration=%.2fs | lateBy=%.2fs | stateParent=%s",
					tostring(binding.state:GetAttribute("WaveId") or binding.state.Name),
					templateName,
					elapsed,
					duration,
					elapsed - duration,
					if binding.state.Parent then binding.state.Parent:GetFullName() else "nil"
				),
				"TsunamiVisualService"
			)
		end
		return
	end

	local template = tsunamiTemplatesFolder:FindFirstChild(templateName)
	if not template or not template:IsA("BasePart") then
		DebugModule.debugWarn(
			string.format(
				"Client template lookup failed | waveId=%s | requested=%s | folder=%s | children=%s | state=%s",
				tostring(binding.state:GetAttribute("WaveId") or binding.state.Name),
				templateName,
				tsunamiTemplatesFolder:GetFullName(),
				getTemplateFolderSummary(),
				binding.state:GetFullName()
			),
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
	applyVisualColor(visual, templateName)

	local initialServerTime = Workspace:GetServerTimeNow()
	local visualCFrame, isComplete = TsunamiTrajectory.Sample(
		startCFrame,
		targetCFrame,
		startServerTime,
		duration,
		initialServerTime
	)
	if isComplete then
		visual:Destroy()
		return
	end

	visual.CFrame = visualCFrame
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

	local clampedElapsed = math.max(0, initialServerTime - startServerTime)
	local remaining = duration - clampedElapsed

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
	DebugModule.debugInfo(
		string.format(
			"Visual created | waveId=%s | template=%s | age=%.2fs | remaining=%.2fs | start=%s | target=%s | current=%s | parent=%s | transparency=%.2f | localTransparency=%.2f | anchored=%s | canQuery=%s | canTouch=%s | canCollide=%s",
			tostring(binding.state:GetAttribute("WaveId") or binding.state.Name),
			templateName,
			clampedElapsed,
			remaining,
			tostring(startCFrame.Position),
			tostring(targetCFrame.Position),
			tostring(visual.Position),
			if visual.Parent then visual.Parent:GetFullName() else "nil",
			visual.Transparency,
			visual.LocalTransparencyModifier,
			tostring(visual.Anchored),
			tostring(visual.CanQuery),
			tostring(visual.CanTouch),
			tostring(visual.CanCollide)
		),
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

	DebugModule.debugInfo(
		string.format(
			"State removed | waveId=%s | stateParent=%s | visualParent=%s",
			tostring(state:GetAttribute("WaveId") or state.Name),
			if state.Parent then state.Parent:GetFullName() else "nil",
			if binding.visual and binding.visual.Parent then binding.visual.Parent:GetFullName() else "nil"
		),
		"TsunamiVisualService"
	)
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
		lastInvalidAttributes = nil,
		expiredLogged = false,
	}
	worldBinding.states[state] = stateBinding
	stateBinding.maid:GiveTask(function()
		cleanupVisual(stateBinding, "state.cleanup")
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

	DebugModule.debugInfo(
		string.format(
			"State arrived | waveId=%s | path=%s | stateParent=%s | serverAge=%s | attributes=%s | activeStateCount=%d",
			tostring(state:GetAttribute("WaveId") or state.Name),
			state:GetFullName(),
			if state.Parent then state.Parent:GetFullName() else "nil",
			if typeof(state:GetAttribute("StartServerTime")) == "number"
				then string.format(
					"%.2fs",
					Workspace:GetServerTimeNow() - (state:GetAttribute("StartServerTime") :: number)
				)
				else "unknown",
			getAttributeTypeSummary(state),
			if worldBinding.activeStatesFolder then #worldBinding.activeStatesFolder:GetChildren() else 0
		),
		"TsunamiVisualService"
	)

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

local function refreshAllVisualColors()
	local state = serviceState
	if not state or not state.isRunning then
		return
	end

	for _, worldBinding in pairs(state.worldBindings) do
		for _, stateBinding in pairs(worldBinding.states) do
			if stateBinding.visual and stateBinding.visual.Parent and stateBinding.templateName then
				applyVisualColor(stateBinding.visual, stateBinding.templateName)
			end
		end
	end
end

local function bindLiveEventState(state: ServiceState, liveEventState: Instance)
	if not liveEventState:IsA("Folder") or state.liveEventState == liveEventState then
		return
	end

	if state.liveEventStateMaid then
		state.liveEventStateMaid:DoCleaning()
	end

	state.liveEventState = liveEventState
	local liveEventStateMaid = Maid.new()
	state.liveEventStateMaid = liveEventStateMaid
	liveEventStateMaid:GiveTask(liveEventState:GetAttributeChangedSignal("ActiveEventIds"):Connect(function()
		refreshAllVisualColors()
		DebugModule.debugInfo(
			"Bloodmoon tsunami color mode updated | active=" .. tostring(isBloodmoonActive()),
			"TsunamiVisualService"
		)
	end))

	refreshAllVisualColors()
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
		liveEventState = nil,
		liveEventStateMaid = nil,
		isRunning = true,
	}
	serviceState = state

	local config = getConfig()
	if not config.enabled then
		DebugModule.debugInfo("Tsunami visual service disabled by config", "TsunamiVisualService")
		return
	end

	local existingLiveEventState = ReplicatedStorage:FindFirstChild("LiveEventState")
	if existingLiveEventState then
		bindLiveEventState(state, existingLiveEventState)
	end
	state.maid:GiveTask(ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "LiveEventState" then
			bindLiveEventState(state, child)
		end
	end))
	state.maid:GiveTask(ReplicatedStorage.ChildRemoved:Connect(function(child)
		if child ~= state.liveEventState then
			return
		end

		if state.liveEventStateMaid then
			state.liveEventStateMaid:DoCleaning()
			state.liveEventStateMaid = nil
		end
		state.liveEventState = nil
		refreshAllVisualColors()
	end))

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
		if state.liveEventStateMaid then
			state.liveEventStateMaid:DoCleaning()
			state.liveEventStateMaid = nil
		end
		state.liveEventState = nil
	end)
	state.maid:GiveTask(RunService.PreRender:Connect(function()
		if state.isRunning then
			updateBoundVisuals(state)
		end
	end))

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
