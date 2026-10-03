--!strict

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local PetRarityConfig = require(ReplicatedStorage.Modules.Config.PetRarityConfig)
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)
local PetViewportRenderer = require(ReplicatedStorage.Modules.UI.PetViewportRenderer)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

type LuckyBlockGroup = "Tier1" | "Tier2" | "Tier3" | "Premium" | PetConfig.EventId
type PurchaseKind = "Wins" | "Robux"
type RollCallback = (rollCount: number, purchaseKind: PurchaseKind) -> ()

type RollButtonState = {
	frame: GuiObject,
	button: GuiButton,
	rollCount: number,
	purchaseKind: PurchaseKind,
}

type TopFrameState = {
	backgroundColor: Color3,
	gradientColor: ColorSequence?,
	gradientRotation: number?,
	labelText: string?,
}

type Controller = {
	root: Instance,
	previewGroup: LuckyBlockGroup,
	rendered: boolean,
	onRollRequested: RollCallback,
	viewportAnimator: PetViewportRenderer.Animator,
	maid: any,
	alive: boolean,
	buttonStates: { [GuiObject]: RollButtonState },
	boundButtons: { [GuiButton]: boolean },
	previewInstances: { Frame },
	previewContainer: ScrollingFrame?,
	previewContainerWasVisible: boolean?,
	previewScrollBarTransparency: number?,
	viewportVisibility: { [ViewportFrame]: boolean },
	canvasConnection: RBXScriptConnection?,
	template: Frame?,
	templateWasVisible: boolean?,
	topFrame: Frame?,
	topFrameState: TopFrameState?,
	previousGamepadSelection: GuiObject?,
	_registerButton: (self: Controller, instance: Instance) -> (),
	_bindButtons: (self: Controller) -> (),
	_renderShowcase: (self: Controller) -> (),
	Init: (self: Controller) -> (),
	SetPreviewGroup: (self: Controller, group: LuckyBlockGroup) -> (),
	SetPreviewVisible: (self: Controller, isVisible: boolean) -> (),
	FocusForGamepad: (self: Controller) -> (),
	RestoreGamepadFocus: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

local PetLuckyBlockUIController = {}
PetLuckyBlockUIController.__index = PetLuckyBlockUIController

local MODULE_NAME = "PetLuckyBlockUIController"
local PREVIEW_ATTRIBUTE = "TemporaryPetShowcasePreview"

local function getRollButtonInfo(name: string): (number?, PurchaseKind?)
	local winsCount = string.match(name, "^BuyButton_([135])x$")
	if winsCount then
		return tonumber(winsCount), "Wins"
	end

	local robuxCount = string.match(name, "^RobuxBuyButton_([135])x$")
	if robuxCount then
		return tonumber(robuxCount), "Robux"
	end
	return nil, nil
end

local function isValidSelectionTarget(target: GuiObject?, requiredAncestor: Instance?): boolean
	if not target or not target.Parent or not target.Selectable then
		return false
	end

	local foundRequiredAncestor = requiredAncestor == nil
	local foundEnabledScreenGui = false
	local current: Instance? = target
	while current do
		if current:IsA("GuiObject") then
			if not current.Visible or not current.Interactable then
				return false
			end
		elseif current:IsA("ScreenGui") then
			if not current.Enabled then
				return false
			end
			foundEnabledScreenGui = true
		end

		if current == requiredAncestor then
			foundRequiredAncestor = true
		end
		current = current.Parent
	end

	return foundRequiredAncestor and foundEnabledScreenGui
end

local function getPetPool(group: LuckyBlockGroup): { PetConfig.PetDefinition }?
	return PetConfig.GetPetsForLuckyBlock(group)
end

local function getWeightText(percentage: number): string
	return string.format("%.2f%%", percentage)
end

local function previewOrder(left: PetConfig.PetDefinition, right: PetConfig.PetDefinition): boolean
	local leftRarity = PetRarityConfig.RarityOrder[left.rarity] or 0
	local rightRarity = PetRarityConfig.RarityOrder[right.rarity] or 0
	if leftRarity ~= rightRarity then
		return leftRarity > rightRarity
	end
	if left.chanceWeight ~= right.chanceWeight then
		return left.chanceWeight > right.chanceWeight
	end
	return left.name < right.name
end

local function findButton(frame: GuiObject): GuiButton?
	if frame:IsA("GuiButton") then
		return frame
	end
	local button = frame:FindFirstChildWhichIsA("GuiButton", true)
	return if button and button:IsA("GuiButton") then button else nil
end

local function hasShowcaseHierarchy(root: Instance): boolean
	local petList = root:FindFirstChild("PetList", true)
	local scrollingFrame = petList and petList:FindFirstChildWhichIsA("ScrollingFrame", true)
	local template = scrollingFrame and scrollingFrame:FindFirstChild("PetShowcaseTemplate")
	local topFrame = root:FindFirstChild("TopFrame", true)
	return scrollingFrame ~= nil
		and template ~= nil
		and template:IsA("Frame")
		and topFrame ~= nil
		and topFrame:IsA("Frame")
end

local function registerButtonAncestors(self: Controller, instance: Instance): ()
	local current: Instance? = instance
	while current do
		if current:IsA("GuiObject") then
			self:_registerButton(current)
		end
		if current == self.root then
			break
		end
		current = current.Parent
	end
end

local function createPreviewCard(
	template: Frame,
	definition: PetConfig.PetDefinition,
	weightText: string,
	layoutOrder: number,
	viewportAnimator: PetViewportRenderer.Animator
): Frame?
	local clone = template:Clone()
	if not clone:IsA("Frame") then
		clone:Destroy()
		DebugModule.debugWarn("Pet showcase template clone was not a Frame", MODULE_NAME)
		return nil
	end

	clone.Name = definition.id .. "Preview"
	clone.LayoutOrder = layoutOrder
	clone.Visible = true
	clone:SetAttribute(PREVIEW_ATTRIBUTE, true)

	local rarityStyle = ColorConfig.Pets.GetDisplayRarityStyle(definition.rarity)
	local background = clone:FindFirstChild("Background")
	if background and background:IsA("Frame") then
		background.BackgroundColor3 = ColorConfig.Colors.White.Color
		background.BackgroundTransparency = 0
		local gradient = background:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = rarityStyle.Gradient
			gradient.Rotation = 90
		end
	end

	local rollWeight = clone:FindFirstChild("RollWeight")
	if rollWeight and rollWeight:IsA("TextLabel") then
		rollWeight.Text = weightText
	end

	local rarityType = clone:FindFirstChild("RarityType")
	if rarityType and rarityType:IsA("TextLabel") then
		rarityType.Text = string.upper(definition.rarity)
		rarityType.TextColor3 = rarityStyle.BackgroundColor
		local gradient = rarityType:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = rarityStyle.Gradient
			gradient.Rotation = 90
		end
	end

	local petName = clone:FindFirstChild("PetName")
	if petName and petName:IsA("TextLabel") then
		petName.Text = definition.name
	end

	local viewport = clone:FindFirstChild("Viewport")
	if viewport and viewport:IsA("ViewportFrame") then
		PetViewportRenderer.Render(viewport, definition.modelPath, viewportAnimator)
	end
	return clone
end

function PetLuckyBlockUIController.new(
	root: Instance,
	initialGroup: LuckyBlockGroup,
	onRollRequested: RollCallback
): Controller
	return setmetatable({
		root = root,
		previewGroup = initialGroup,
		rendered = false,
		onRollRequested = onRollRequested,
		viewportAnimator = PetViewportRenderer.CreateAnimator(),
		maid = Maid.new(),
		alive = true,
		buttonStates = setmetatable({}, { __mode = "k" }) :: { [GuiObject]: RollButtonState },
		boundButtons = setmetatable({}, { __mode = "k" }) :: { [GuiButton]: boolean },
		previewInstances = {},
		previewContainer = nil,
		previewContainerWasVisible = nil,
		previewScrollBarTransparency = nil,
		viewportVisibility = setmetatable({}, { __mode = "k" }) :: { [ViewportFrame]: boolean },
		canvasConnection = nil,
		template = nil,
		templateWasVisible = nil,
		topFrame = nil,
		topFrameState = nil,
		previousGamepadSelection = nil,
	}, PetLuckyBlockUIController) :: Controller
end

function PetLuckyBlockUIController.FocusForGamepad(self: Controller): ()
	if not string.find(UserInputService:GetLastInputType().Name, "Gamepad", 1, true) then
		return
	end

	local selectedObject = GuiService.SelectedObject
	if selectedObject
		and selectedObject:IsDescendantOf(self.root)
		and isValidSelectionTarget(selectedObject, self.root)
	then
		return
	end

	local first: RollButtonState? = nil
	for _, state in pairs(self.buttonStates) do
		if isValidSelectionTarget(state.button, self.root)
			and (not first or state.button.SelectionOrder < first.button.SelectionOrder)
		then
			first = state
		end
	end
	if first then
		if self.previousGamepadSelection == nil
			and selectedObject
			and selectedObject:IsA("GuiButton")
			and isValidSelectionTarget(selectedObject, nil)
		then
			self.previousGamepadSelection = selectedObject
		end
		GuiService.SelectedObject = first.button
	elseif selectedObject and selectedObject:IsDescendantOf(self.root) then
		GuiService.SelectedObject = nil
	end
end

function PetLuckyBlockUIController.RestoreGamepadFocus(self: Controller): ()
	local selectedObject = GuiService.SelectedObject
	if selectedObject and selectedObject:IsDescendantOf(self.root) then
		local previous = self.previousGamepadSelection
		GuiService.SelectedObject = if previous
			and previous:IsA("GuiButton")
			and isValidSelectionTarget(previous, nil)
			then previous
			else nil
	end
	self.previousGamepadSelection = nil
end

function PetLuckyBlockUIController._registerButton(self: Controller, instance: Instance): ()
	if not instance:IsA("GuiObject") or self.buttonStates[instance] then
		return
	end
	local rollCount, purchaseKind = getRollButtonInfo(instance.Name)
	local button = findButton(instance)
	if not rollCount or not purchaseKind or not button or self.boundButtons[button] then
		return
	end

	instance.Active = true
	button.Active = true
	button.Selectable = true
	button.SelectionOrder = rollCount * 2 + (if purchaseKind == "Robux" then 1 else 0)
	VisualFunctions.SetupFrameHover(instance, 1.05, 12, 1.15)
	VisualFunctions.SetupFrameClick(instance, 0.94, -8, 0.8)

	local state: RollButtonState = {
		frame = instance,
		button = button,
		rollCount = rollCount,
		purchaseKind = purchaseKind,
	}
	self.buttonStates[instance] = state
	self.boundButtons[button] = true
	self.maid:GiveTask(button.Activated:Connect(function()
		if not self.alive then
			return
		end
		VisualFunctions.PlayFrameClick(instance)
		self.onRollRequested(rollCount, purchaseKind)
	end))
end

function PetLuckyBlockUIController._bindButtons(self: Controller): ()
	self:_registerButton(self.root)
	for _, descendant in ipairs(self.root:GetDescendants()) do
		registerButtonAncestors(self, descendant)
	end
	self.maid:GiveTask(self.root.DescendantAdded:Connect(function(descendant: Instance)
		registerButtonAncestors(self, descendant)
		if not self.rendered and hasShowcaseHierarchy(self.root) then
			self:_renderShowcase()
		end
	end))

	local states: { RollButtonState } = {}
	for _, state in pairs(self.buttonStates) do
		table.insert(states, state)
	end
	table.sort(states, function(left: RollButtonState, right: RollButtonState): boolean
		return left.button.SelectionOrder < right.button.SelectionOrder
	end)
	for _, state in ipairs(states) do
		local sameRollAlternative: RollButtonState? = nil
		local leftRoll: RollButtonState? = nil
		local rightRoll: RollButtonState? = nil
		for _, candidate in ipairs(states) do
			if candidate.rollCount == state.rollCount and candidate.purchaseKind ~= state.purchaseKind then
				sameRollAlternative = candidate
			elseif candidate.purchaseKind == state.purchaseKind and candidate.rollCount < state.rollCount then
				leftRoll = candidate
			elseif candidate.purchaseKind == state.purchaseKind and candidate.rollCount > state.rollCount then
				rightRoll = candidate
			end
		end
		state.button.NextSelectionLeft = if leftRoll then leftRoll.button else state.button
		state.button.NextSelectionRight = if rightRoll then rightRoll.button else state.button
		state.button.NextSelectionUp = if sameRollAlternative then sameRollAlternative.button else state.button
		state.button.NextSelectionDown = if sameRollAlternative then sameRollAlternative.button else state.button
	end

	self.maid:GiveTask(UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		if string.find(inputType.Name, "Gamepad", 1, true) then
			self:FocusForGamepad()
		end
	end))
end

function PetLuckyBlockUIController._renderShowcase(self: Controller): ()
	local petList = self.root:FindFirstChild("PetList", true)
	local scrollingFrame = petList and petList:FindFirstChildWhichIsA("ScrollingFrame", true)
	local templateInstance = scrollingFrame and scrollingFrame:FindFirstChild("PetShowcaseTemplate")
	local topFrameInstance = self.root:FindFirstChild("TopFrame", true)
	if not scrollingFrame
		or not templateInstance
		or not templateInstance:IsA("Frame")
		or not topFrameInstance
		or not topFrameInstance:IsA("Frame")
	then
		self.rendered = false
		DebugModule.debugWarn("Lucky Block preview hierarchy is still loading", MODULE_NAME)
		return
	end
	local template = templateInstance
	local topFrame = topFrameInstance
	self.previewContainer = scrollingFrame
	if self.previewContainerWasVisible == nil then
		self.previewContainerWasVisible = scrollingFrame.Visible
		self.previewScrollBarTransparency = scrollingFrame.ScrollBarImageTransparency
	end
	self.template = template
	self.templateWasVisible = template.Visible
	template.Visible = false

	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:GetAttribute(PREVIEW_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
	table.clear(self.previewInstances)

	local petPool = getPetPool(self.previewGroup)
	if not petPool then
		self.rendered = false
		DebugModule.debugWarn("Pet pool missing for preview group " .. self.previewGroup, MODULE_NAME)
		return
	end

	local style = ColorConfig.LuckyBlocks.TopFrameStyles[self.previewGroup]
	local gradient = topFrame:FindFirstChildOfClass("UIGradient")
	local label = topFrame:FindFirstChild("LuckyBlockTier")
	self.topFrame = topFrame
	if not self.topFrameState then
		self.topFrameState = {
			backgroundColor = topFrame.BackgroundColor3,
			gradientColor = if gradient then gradient.Color else nil,
			gradientRotation = if gradient then gradient.Rotation else nil,
			labelText = if label and label:IsA("TextLabel") then label.Text else nil,
		}
	end
	topFrame.BackgroundColor3 = style.BackgroundColor
	if gradient then
		gradient.Color = style.Gradient
		gradient.Rotation = 90
	end
	if label and label:IsA("TextLabel") then
		label.Text = style.Label
	end

	local player = Players.LocalPlayer
	local luckMultiplier = if player then player:GetAttribute("Pet_LuckMultiplier") else nil
	local oddsByPetId = PetConfig.GetLuckyBlockOdds(
		self.previewGroup,
		if typeof(luckMultiplier) == "number" then luckMultiplier else PetConfig.Upgrades.luckMultiplier.startingMultiplier
	)
	if not oddsByPetId then
		self.rendered = false
		DebugModule.debugWarn("Could not calculate Lucky Block odds | group=" .. self.previewGroup, MODULE_NAME)
		return
	end
	local sortedPets = table.clone(petPool)
	table.sort(sortedPets, previewOrder)
	for order, pet in ipairs(sortedPets) do
		local preview = createPreviewCard(
			template,
			pet,
			getWeightText(oddsByPetId[pet.id] or 0),
			order,
			self.viewportAnimator
		)
		if preview then
			for _, descendant in ipairs(preview:GetDescendants()) do
				if descendant:IsA("ViewportFrame") then
					self.viewportVisibility[descendant] = descendant.Visible
				end
			end
			table.insert(self.previewInstances, preview)
			preview.Parent = scrollingFrame
		end
	end

	local gridLayout = scrollingFrame:FindFirstChildOfClass("UIGridLayout")
	if gridLayout then
		if self.canvasConnection then
			self.canvasConnection:Disconnect()
			self.canvasConnection = nil
		end
		local function updateCanvasSize(): ()
			if scrollingFrame.Parent then
				scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, gridLayout.AbsoluteContentSize.Y)
			end
		end
		updateCanvasSize()
		self.canvasConnection = gridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
	end
	self.rendered = true
end

function PetLuckyBlockUIController.SetPreviewGroup(self: Controller, group: LuckyBlockGroup): ()
	if not self.alive then
		return
	end
	local groupChanged = self.previewGroup ~= group
	self.previewGroup = group
	if not groupChanged and self.rendered then
		return
	end
	self:_renderShowcase()
end

function PetLuckyBlockUIController.SetPreviewVisible(self: Controller, isVisible: boolean): ()
	local scrollingFrame = self.previewContainer
	if scrollingFrame and scrollingFrame.Parent then
		if isVisible then
			scrollingFrame.Visible = self.previewContainerWasVisible ~= false
			scrollingFrame.ScrollBarImageTransparency = self.previewScrollBarTransparency or 0
		else
			scrollingFrame.Visible = false
			scrollingFrame.ScrollBarImageTransparency = 1
		end
	end

	for viewport, wasVisible in pairs(self.viewportVisibility) do
		if viewport.Parent then
			viewport.Visible = if isVisible then wasVisible else false
		end
	end
end

function PetLuckyBlockUIController.Init(self: Controller): ()
	if not self.alive then
		return
	end
	self.maid:GiveTask(self.root.Destroying:Connect(function()
		self:Destroy()
	end))
	local player = Players.LocalPlayer
	if player then
		self.maid:GiveTask(player:GetAttributeChangedSignal("Pet_LuckMultiplier"):Connect(function()
			if self.alive then
				self.rendered = false
				self:_renderShowcase()
			end
		end))
	end
	self:_bindButtons()
end

function PetLuckyBlockUIController.Destroy(self: Controller): ()
	if not self.alive then
		return
	end
	self.alive = false
	self.viewportAnimator:Destroy()
	self:RestoreGamepadFocus()
	self.maid:DoCleaning()
	if self.canvasConnection then
		self.canvasConnection:Disconnect()
		self.canvasConnection = nil
	end
	for _, preview in ipairs(self.previewInstances) do
		if preview.Parent then
			preview:Destroy()
		end
	end
	table.clear(self.previewInstances)
	table.clear(self.viewportVisibility)
	if self.template and self.template.Parent and self.templateWasVisible ~= nil then
		self.template.Visible = self.templateWasVisible
	end
	local topFrame = self.topFrame
	local state = self.topFrameState
	if topFrame and topFrame.Parent and state then
		topFrame.BackgroundColor3 = state.backgroundColor
		local gradient = topFrame:FindFirstChildOfClass("UIGradient")
		if gradient and state.gradientColor and state.gradientRotation then
			gradient.Color = state.gradientColor
			gradient.Rotation = state.gradientRotation
		end
		local label = topFrame:FindFirstChild("LuckyBlockTier")
		if label and label:IsA("TextLabel") and state.labelText then
			label.Text = state.labelText
		end
	end
	table.clear(self.buttonStates)
	table.clear(self.boundButtons)
end

return PetLuckyBlockUIController
