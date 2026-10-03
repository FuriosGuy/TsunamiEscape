--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

type Controller = {
	alive: boolean,
	policyPlayer: Player?,
	maid: any?,
	folderMaid: any?,
	blocksFolder: Folder?,
	modelMaids: { [Model]: any },
	_bindBlocksFolder: (self: Controller, folder: Folder) -> (),
	_bindModel: (self: Controller, model: Model) -> (),
	_clearModelBindings: (self: Controller) -> (),
	Init: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

local PetLuckyBlockBillboardVisualController = {}
PetLuckyBlockBillboardVisualController.__index = PetLuckyBlockBillboardVisualController

local MODULE_NAME = "PetLuckyBlockBillboardVisualController"
local BILLBOARD_NAME = "LuckyBlockBillboard"
local LOCK_BILLBOARD_NAME = "LockBillboard"
local POLICY_LOCK_BILLBOARD_NAME = "PolicyLockBillboard"
local POLICY_HIGHLIGHT_NAME = "LuckyBlockPolicyRestrictedHighlight"
local EVENT_LOCK_HIGHLIGHT_NAME = "LuckyBlockInactiveEventHighlight"
local EVENT_AVAILABILITY_ATTRIBUTE = "LuckyBlockEventAvailable"
local POLICY_RESTRICTED_ATTRIBUTE = "Pet_PaidRandomItemsRestricted"
local POLICY_LOADED_ATTRIBUTE = "Pet_RandomItemPolicyLoaded"
local DISABLED_COLOR_MULTIPLIER = 0.55
local DISABLED_HIGHLIGHT_TRANSPARENCY = 0.55
local warnedMissingLockTemplate = false

local function getLuckyBlocksFolder(instance: Instance): Folder?
	if not instance:IsA("Folder") or instance.Name ~= "LuckyBlocks" then
		return nil
	end

	local world = instance.Parent
	local worlds = if world then world.Parent else nil
	if not world or world.Name ~= "World1" or not worlds or worlds.Name ~= "Worlds" then
		return nil
	end

	return instance
end

local function arePaidRandomItemsAllowed(player: Player?): boolean
	return player ~= nil
		and player:GetAttribute(POLICY_LOADED_ATTRIBUTE) == true
		and player:GetAttribute(POLICY_RESTRICTED_ATTRIBUTE) == false
end

local function hasActiveEventLockHighlight(model: Model): boolean
	local highlight = model:FindFirstChild(EVENT_LOCK_HIGHLIGHT_NAME)
	return highlight ~= nil and highlight:IsA("Highlight") and highlight.Enabled
end

function PetLuckyBlockBillboardVisualController.new(): Controller
	return setmetatable({
		alive = false,
		policyPlayer = Players.LocalPlayer,
		maid = nil,
		folderMaid = nil,
		blocksFolder = nil,
		modelMaids = {},
	}, PetLuckyBlockBillboardVisualController) :: Controller
end

function PetLuckyBlockBillboardVisualController._clearModelBindings(self: Controller): ()
	for model, modelMaid in pairs(table.clone(self.modelMaids)) do
		self.modelMaids[model] = nil
		modelMaid:DoCleaning()
	end
end

function PetLuckyBlockBillboardVisualController._bindModel(self: Controller, model: Model): ()
	if not self.alive or model.Parent ~= self.blocksFolder or self.modelMaids[model] then
		return
	end

	local modelMaid = Maid.new()
	self.modelMaids[model] = modelMaid
	local billboardMaid: any = nil
	local boundBillboard: BillboardGui? = nil
	local policyEmitterStates: { [ParticleEmitter]: boolean } = {}
	local policyEmitterConnections: { [ParticleEmitter]: RBXScriptConnection } = {}
	local changingEmitterState: { [ParticleEmitter]: boolean } = {}
	local boundEventHighlights: { [Highlight]: boolean } = {}

	local function setEmitterEnabled(emitter: ParticleEmitter, enabled: boolean): ()
		if emitter.Enabled == enabled then
			return
		end
		changingEmitterState[emitter] = enabled
		emitter.Enabled = enabled
	end

	local function trackPolicyEmitter(emitter: ParticleEmitter, eventUnavailable: boolean): ()
		if policyEmitterStates[emitter] == nil then
			policyEmitterStates[emitter] = if eventUnavailable then false else emitter.Enabled
			policyEmitterConnections[emitter] = emitter:GetPropertyChangedSignal("Enabled"):Connect(function()
				local expectedLocalState = changingEmitterState[emitter]
				if expectedLocalState ~= nil and emitter.Enabled == expectedLocalState then
					changingEmitterState[emitter] = nil
					return
				end
				changingEmitterState[emitter] = nil

				local isEventUnavailable = model:GetAttribute(EVENT_AVAILABILITY_ATTRIBUTE) == false
				policyEmitterStates[emitter] = if isEventUnavailable then false else emitter.Enabled
				if not isEventUnavailable and not arePaidRandomItemsAllowed(self.policyPlayer) and emitter.Enabled then
					setEmitterEnabled(emitter, false)
				end
			end)
		elseif eventUnavailable then
			policyEmitterStates[emitter] = false
		end
	end

	local function refreshPolicyEmitters(): ()
		local policyRestricted = not arePaidRandomItemsAllowed(self.policyPlayer)
		local eventUnavailable = model:GetAttribute(EVENT_AVAILABILITY_ATTRIBUTE) == false
		if policyRestricted then
			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("ParticleEmitter") then
					trackPolicyEmitter(descendant, eventUnavailable)
					setEmitterEnabled(descendant, false)
				end
			end
			return
		end

		for emitter, wasEnabled in pairs(table.clone(policyEmitterStates)) do
			local connection = policyEmitterConnections[emitter]
			if connection then
				connection:Disconnect()
				policyEmitterConnections[emitter] = nil
			end
			policyEmitterStates[emitter] = nil
			if emitter.Parent then
				changingEmitterState[emitter] = nil
				emitter.Enabled = wasEnabled
			end
		end
	end

	local function refreshPolicyLock(): ()
		local mainPart = model:FindFirstChild("MainPart")
		if not mainPart or not mainPart:IsA("BasePart") then
			return
		end

		local policyAllowsPaidRandomItems = arePaidRandomItemsAllowed(self.policyPlayer)
		local eventUnavailable = model:GetAttribute(EVENT_AVAILABILITY_ATTRIBUTE) == false
		local policyRestricted = not policyAllowsPaidRandomItems and not hasActiveEventLockHighlight(model)
		refreshPolicyEmitters()
		local policyLock = mainPart:FindFirstChild(POLICY_LOCK_BILLBOARD_NAME)
		if policyLock and not policyLock:IsA("BillboardGui") then
			return
		end

		local policyHighlight = model:FindFirstChild(POLICY_HIGHLIGHT_NAME)
		if policyHighlight and not policyHighlight:IsA("Highlight") then
			return
		end
		if policyRestricted then
			local highlight = if policyHighlight then policyHighlight :: Highlight else Instance.new("Highlight")
			highlight.Name = POLICY_HIGHLIGHT_NAME
			highlight.Adornee = model
			highlight.FillColor = Color3.new(0, 0, 0)
			highlight.FillTransparency = DISABLED_HIGHLIGHT_TRANSPARENCY
			highlight.OutlineTransparency = 1
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Enabled = true
			if highlight.Parent ~= model then
				highlight.Parent = model
			end
		elseif policyHighlight then
			policyHighlight:Destroy()
		end

		if policyRestricted then
			if not policyLock then
				local userInterface = ReplicatedStorage:FindFirstChild("UserInterface")
				local template = userInterface and userInterface:FindFirstChild(LOCK_BILLBOARD_NAME)
				if template and template:IsA("BillboardGui") then
					local clone = template:Clone()
					clone.Name = POLICY_LOCK_BILLBOARD_NAME
					clone.Adornee = mainPart
					clone.Enabled = true
					clone.Parent = mainPart
				else
					if not warnedMissingLockTemplate then
						warnedMissingLockTemplate = true
						DebugModule.debugWarn(
							"ReplicatedStorage.UserInterface.LockBillboard is missing or has wrong class",
							MODULE_NAME
						)
					end
				end
			end
		elseif policyLock then
			policyLock:Destroy()
		end

		local prompt = mainPart:FindFirstChild("LuckyBlockOpenPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = policyAllowsPaidRandomItems and not eventUnavailable
		end
	end

	local function bindEventHighlight(instance: Instance): ()
		if not instance:IsA("Highlight") or instance.Name ~= EVENT_LOCK_HIGHLIGHT_NAME or boundEventHighlights[instance] then
			return
		end
		boundEventHighlights[instance] = true
		modelMaid:GiveTask(instance:GetPropertyChangedSignal("Enabled"):Connect(refreshPolicyLock))
	end

	local function clearBillboardBinding(): ()
		if billboardMaid then
			billboardMaid:DoCleaning()
			billboardMaid = nil
		end
		boundBillboard = nil
	end

	local function bindBillboard(instance: Instance): ()
		if not instance:IsA("BillboardGui") or instance.Name ~= BILLBOARD_NAME or boundBillboard == instance then
			return
		end

		clearBillboardBinding()
		boundBillboard = instance
		local currentMaid = Maid.new()
		billboardMaid = currentMaid

		local function applyLabel(label: TextLabel): ()
			local isDisabled = model:GetAttribute(EVENT_AVAILABILITY_ATTRIBUTE) == false
				or not arePaidRandomItemsAllowed(self.policyPlayer)
			VisualFunctions.SetTextLabelDisabledState(label, isDisabled, DISABLED_COLOR_MULTIPLIER)
		end

		local function refreshLabels(): ()
			if not instance.Parent then
				return
			end

			for _, descendant in ipairs(instance:GetDescendants()) do
				if descendant:IsA("TextLabel") then
					applyLabel(descendant)
				end
			end
		end

		currentMaid:GiveTask(model:GetAttributeChangedSignal(EVENT_AVAILABILITY_ATTRIBUTE):Connect(refreshLabels))
		local policyPlayer = self.policyPlayer
		if policyPlayer then
			currentMaid:GiveTask(policyPlayer:GetAttributeChangedSignal(POLICY_RESTRICTED_ATTRIBUTE):Connect(refreshLabels))
			currentMaid:GiveTask(policyPlayer:GetAttributeChangedSignal(POLICY_LOADED_ATTRIBUTE):Connect(refreshLabels))
		end
		currentMaid:GiveTask(instance.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("TextLabel") then
				applyLabel(descendant)
			end
		end))
		currentMaid:GiveTask(instance.Destroying:Connect(function()
			if boundBillboard == instance then
				clearBillboardBinding()
			end
		end))
		refreshLabels()
	end

	modelMaid:GiveTask(model.DescendantAdded:Connect(bindBillboard))
	modelMaid:GiveTask(model.DescendantAdded:Connect(function(instance: Instance)
		if instance.Name == "MainPart" or instance.Name == "LuckyBlockOpenPrompt" then
			refreshPolicyLock()
		elseif instance:IsA("ParticleEmitter") then
			refreshPolicyEmitters()
		elseif instance.Name == EVENT_LOCK_HIGHLIGHT_NAME then
			bindEventHighlight(instance)
			refreshPolicyLock()
		end
	end))
	modelMaid:GiveTask(model:GetAttributeChangedSignal(EVENT_AVAILABILITY_ATTRIBUTE):Connect(refreshPolicyLock))
	local policyPlayer = self.policyPlayer
	if policyPlayer then
		modelMaid:GiveTask(policyPlayer:GetAttributeChangedSignal(POLICY_RESTRICTED_ATTRIBUTE):Connect(refreshPolicyLock))
		modelMaid:GiveTask(policyPlayer:GetAttributeChangedSignal(POLICY_LOADED_ATTRIBUTE):Connect(refreshPolicyLock))
	end
	modelMaid:GiveTask(function()
		clearBillboardBinding()
		for emitter, wasEnabled in pairs(table.clone(policyEmitterStates)) do
			local connection = policyEmitterConnections[emitter]
			if connection then
				connection:Disconnect()
				policyEmitterConnections[emitter] = nil
			end
			policyEmitterStates[emitter] = nil
			if emitter.Parent then
				changingEmitterState[emitter] = nil
				emitter.Enabled = wasEnabled
			end
		end
		local mainPart = model:FindFirstChild("MainPart")
		local policyLock = mainPart and mainPart:FindFirstChild(POLICY_LOCK_BILLBOARD_NAME)
		if policyLock then
			policyLock:Destroy()
		end
		local policyHighlight = model:FindFirstChild(POLICY_HIGHLIGHT_NAME)
		if policyHighlight then
			policyHighlight:Destroy()
		end
	end)
	for _, descendant in ipairs(model:GetDescendants()) do
		bindBillboard(descendant)
		bindEventHighlight(descendant)
	end
	refreshPolicyLock()
end

function PetLuckyBlockBillboardVisualController._bindBlocksFolder(self: Controller, folder: Folder): ()
	if not self.alive or self.blocksFolder == folder then
		return
	end

	if self.folderMaid then
		self.folderMaid:DoCleaning()
		self.folderMaid = nil
	end
	self:_clearModelBindings()
	self.blocksFolder = folder

	local folderMaid = Maid.new()
	self.folderMaid = folderMaid
	folderMaid:GiveTask(folder.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Model") then
			self:_bindModel(child)
		end
	end))
	folderMaid:GiveTask(folder.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Model") then
			local modelMaid = self.modelMaids[child]
			self.modelMaids[child] = nil
			if modelMaid then
				modelMaid:DoCleaning()
			end
		end
	end))
	folderMaid:GiveTask(folder.AncestryChanged:Connect(function(_: Instance, parent: Instance?)
		if parent == nil and self.blocksFolder == folder then
			self.blocksFolder = nil
			self:_clearModelBindings()
			if self.folderMaid == folderMaid then
				self.folderMaid = nil
			end
			folderMaid:DoCleaning()
		end
	end))

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			self:_bindModel(child)
		end
	end
end

function PetLuckyBlockBillboardVisualController.Init(self: Controller): ()
	if self.alive then
		return
	end
	self.alive = true
	self.policyPlayer = Players.LocalPlayer
	self.maid = Maid.new()

	local function tryBindFolder(instance: Instance): ()
		local folder = getLuckyBlocksFolder(instance)
		if folder then
			self:_bindBlocksFolder(folder)
		end
	end

	self.maid:GiveTask(Workspace.DescendantAdded:Connect(tryBindFolder))
	local worlds = Workspace:FindFirstChild("Worlds")
	local world = worlds and worlds:FindFirstChild("World1")
	local existingFolder = world and world:FindFirstChild("LuckyBlocks")
	if existingFolder then
		tryBindFolder(existingFolder)
	else
		DebugModule.debugInfo("Waiting for Workspace.Worlds.World1.LuckyBlocks", MODULE_NAME)
	end
end

function PetLuckyBlockBillboardVisualController.Destroy(self: Controller): ()
	if not self.alive then
		return
	end
	self.alive = false
	if self.maid then
		self.maid:DoCleaning()
		self.maid = nil
	end
	if self.folderMaid then
		self.folderMaid:DoCleaning()
		self.folderMaid = nil
	end
	self:_clearModelBindings()
	self.blocksFolder = nil
	self.policyPlayer = nil
end

return PetLuckyBlockBillboardVisualController
