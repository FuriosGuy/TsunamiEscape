--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

type LuckyBlockGroup = "Tier1" | "Tier2" | "Tier3" | "Premium" | "BloodMoon" | "NeonRush" | "FrostbiteRally" | "Halloween"
type PolicyParticleState = {
	originalEnabled: boolean,
	connection: RBXScriptConnection,
}

type Controller = {
	alive: boolean,
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
local EVENT_HIGHLIGHT_NAME = "LuckyBlockInactiveEventHighlight"
local EVENT_AVAILABILITY_ATTRIBUTE = "LuckyBlockEventAvailable"
local POLICY_RESTRICTED_ATTRIBUTE = "Pet_PaidRandomItemsRestricted"
local POLICY_LOADED_ATTRIBUTE = "Pet_RandomItemPolicyLoaded"
local DISABLED_COLOR_MULTIPLIER = 0.55
local DISABLED_HIGHLIGHT_TRANSPARENCY = 0.55
local localPlayer = Players.LocalPlayer
local warnedMissingLockTemplate = false

local MODEL_GROUP_ALIASES: { [string]: LuckyBlockGroup } = {
	tier1luckyblock = "Tier1",
	tier2luckyblock = "Tier2",
	tier3luckyblock = "Tier3",
	premiumluckyblock = "Premium",
	robuxluckyblock = "Premium",
	bloodmoonluckyblock = "BloodMoon",
	neonluckyblock = "NeonRush",
	frostbiteluckyblock = "FrostbiteRally",
	halloweenluckyblock = "Halloween",
}

local function getLuckyBlockGroup(model: Model): LuckyBlockGroup?
	local blockId = model:GetAttribute("LuckyBlockId")
	local eventId = model:GetAttribute("LuckyBlockEventId")
	if blockId == "Event" and typeof(eventId) == "string" then
		if eventId == "BloodMoon" or eventId == "NeonRush" or eventId == "FrostbiteRally" or eventId == "Halloween" then
			return eventId
		end
	end
	if blockId == "Tier1" or blockId == "Tier2" or blockId == "Tier3" or blockId == "Premium" then
		return blockId
	end

	local normalizedName = string.lower(string.gsub(model.Name, "[^%w]", ""))
	return MODEL_GROUP_ALIASES[normalizedName]
end

local function arePaidRandomItemsAllowed(): boolean
	return localPlayer:GetAttribute(POLICY_LOADED_ATTRIBUTE) == true
		and localPlayer:GetAttribute(POLICY_RESTRICTED_ATTRIBUTE) == false
end

local function isPolicyRestrictedBlock(model: Model): boolean
	if arePaidRandomItemsAllowed() then
		return false
	end

	local group = getLuckyBlockGroup(model)
	if not group or group == "Tier1" or group == "Tier2" or group == "Tier3" then
		return false
	end
	if group == "Premium" then
		return PetConfig.LuckyBlocks.Premium.rollCurrency == "Robux"
	end

	local candyPrices = PetConfig.LuckyBlocks.Event.eventCandyPricePerRoll
	if candyPrices and typeof(candyPrices[group]) == "number" and candyPrices[group] > 0 then
		return false
	end
	local robuxPrices = PetConfig.LuckyBlocks.Event.eventRobuxPricePerRoll
	return PetConfig.LuckyBlocks.Event.rollCurrency == "Robux"
		and robuxPrices ~= nil
		and typeof(robuxPrices[group]) == "number"
		and robuxPrices[group] > 0
end

local function hasActiveEventHighlight(model: Model): boolean
	local highlight = model:FindFirstChild(EVENT_HIGHLIGHT_NAME)
	return highlight ~= nil and highlight:IsA("Highlight") and highlight.Enabled
end

local function setPolicyHighlight(model: Model, enabled: boolean): ()
	local existing = model:FindFirstChild(POLICY_HIGHLIGHT_NAME)
	if existing and not existing:IsA("Highlight") then
		DebugModule.debugWarn("Policy highlight name is occupied by wrong class | model=" .. model:GetFullName(), MODULE_NAME)
		return
	end

	local highlight = existing :: Highlight?
	if enabled and not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = POLICY_HIGHLIGHT_NAME
		highlight.Parent = model
	elseif not enabled and highlight then
		highlight:Destroy()
		return
	end

	if highlight then
		highlight.Adornee = model
		highlight.FillColor = Color3.new(0, 0, 0)
		highlight.FillTransparency = DISABLED_HIGHLIGHT_TRANSPARENCY
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Enabled = enabled
	end
end

local function setPolicyLockBillboard(mainPart: BasePart, enabled: boolean): ()
	local existing = mainPart:FindFirstChild(POLICY_LOCK_BILLBOARD_NAME)
	if existing and not existing:IsA("BillboardGui") then
		DebugModule.debugWarn("Policy lock name is occupied by wrong class | part=" .. mainPart:GetFullName(), MODULE_NAME)
		return
	end

	local lockBillboard = existing :: BillboardGui?
	if enabled and not lockBillboard then
		local interface = ReplicatedStorage:FindFirstChild("UserInterface")
		local template = interface and interface:FindFirstChild(LOCK_BILLBOARD_NAME)
		if not template or not template:IsA("BillboardGui") then
			if not warnedMissingLockTemplate then
				warnedMissingLockTemplate = true
				DebugModule.debugWarn("ReplicatedStorage.UserInterface.LockBillboard is missing or wrong class", MODULE_NAME)
			end
			return
		end

		lockBillboard = template:Clone()
		lockBillboard.Name = POLICY_LOCK_BILLBOARD_NAME
		lockBillboard.Adornee = mainPart
		lockBillboard.Enabled = true
		lockBillboard.Parent = mainPart
	elseif not enabled and lockBillboard then
		lockBillboard:Destroy()
	end
end

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

function PetLuckyBlockBillboardVisualController.new(): Controller
	return setmetatable({
		alive = false,
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
	local policyParticlesDisabled = false
	local policyParticleStates: { [ParticleEmitter]: PolicyParticleState } = {}
	local function setPolicyParticlesDisabled(disabled: boolean): ()
		policyParticlesDisabled = disabled
		if disabled then
			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("ParticleEmitter") and not policyParticleStates[descendant] then
					local emitter = descendant
					local state: PolicyParticleState = {
						originalEnabled = emitter.Enabled,
						connection = emitter:GetPropertyChangedSignal("Enabled"):Connect(function()
							if policyParticlesDisabled and emitter.Enabled then
								emitter.Enabled = false
							end
						end),
					}
					policyParticleStates[emitter] = state
					emitter.Enabled = false
				end
			end
			return
		end

		for emitter, state in pairs(policyParticleStates) do
			state.connection:Disconnect()
			if emitter.Parent then
				emitter.Enabled = state.originalEnabled
			end
			policyParticleStates[emitter] = nil
		end
	end
	local function disableAddedPolicyEmitter(instance: Instance): ()
		if policyParticlesDisabled and instance:IsA("ParticleEmitter") then
			setPolicyParticlesDisabled(true)
		end
	end
	local function refreshAvailability(): ()
		local mainPart = model:FindFirstChild("MainPart")
		if not mainPart or not mainPart:IsA("BasePart") then
			return
		end

		local eventUnavailable = model:GetAttribute(EVENT_AVAILABILITY_ATTRIBUTE) == false
		local policyRestricted = isPolicyRestrictedBlock(model) and not eventUnavailable and not hasActiveEventHighlight(model)
		setPolicyParticlesDisabled(policyRestricted)
		setPolicyLockBillboard(mainPart, policyRestricted)
		setPolicyHighlight(model, policyRestricted)

		local prompt = mainPart:FindFirstChild("LuckyBlockOpenPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = not eventUnavailable and not policyRestricted
		end
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
				or isPolicyRestrictedBlock(model)
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
		currentMaid:GiveTask(localPlayer:GetAttributeChangedSignal(POLICY_RESTRICTED_ATTRIBUTE):Connect(refreshLabels))
		currentMaid:GiveTask(localPlayer:GetAttributeChangedSignal(POLICY_LOADED_ATTRIBUTE):Connect(refreshLabels))
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

	modelMaid:GiveTask(model.DescendantAdded:Connect(function(instance: Instance)
		bindBillboard(instance)
		disableAddedPolicyEmitter(instance)
	end))
	modelMaid:GiveTask(model.DescendantAdded:Connect(function(instance: Instance)
		if instance.Name == "MainPart" or instance.Name == "LuckyBlockOpenPrompt" or instance.Name == EVENT_HIGHLIGHT_NAME then
			refreshAvailability()
		end
	end))
	modelMaid:GiveTask(model:GetAttributeChangedSignal(EVENT_AVAILABILITY_ATTRIBUTE):Connect(refreshAvailability))
	modelMaid:GiveTask(localPlayer:GetAttributeChangedSignal(POLICY_RESTRICTED_ATTRIBUTE):Connect(refreshAvailability))
	modelMaid:GiveTask(localPlayer:GetAttributeChangedSignal(POLICY_LOADED_ATTRIBUTE):Connect(refreshAvailability))
	modelMaid:GiveTask(function()
		clearBillboardBinding()
		setPolicyParticlesDisabled(false)
		setPolicyHighlight(model, false)
		local mainPart = model:FindFirstChild("MainPart")
		if mainPart and mainPart:IsA("BasePart") then
			setPolicyLockBillboard(mainPart, false)
			local prompt = mainPart:FindFirstChild("LuckyBlockOpenPrompt")
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = model:GetAttribute(EVENT_AVAILABILITY_ATTRIBUTE) ~= false
			end
		end
	end)
	for _, descendant in ipairs(model:GetDescendants()) do
		bindBillboard(descendant)
	end
	refreshAvailability()
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
end

return PetLuckyBlockBillboardVisualController
