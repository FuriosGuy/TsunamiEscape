--!strict

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local NumberFormatting = require(ReplicatedStorage.Modules.Shared.NumberFormatting)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local PetLuckyBlockUIController = require(ReplicatedStorage.Modules.UI.MainGUI.PetLuckyBlockUIController)
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

type LuckyBlockGroup = "Tier1" | "Tier2" | "Tier3" | "Premium" | PetConfig.EventId
type PurchaseKind = "Wins" | "Robux"
type PriceBridge = {
	RequestRoll: (
		self: any,
		group: LuckyBlockGroup,
		rollCount: number,
		purchaseKind: PurchaseKind,
		source: "Shop"
	) -> boolean,
	UpdatePrices: (self: any, group: LuckyBlockGroup, targetFrame: GuiObject?) -> (),
	CancelPriceUpdates: (self: any, targetFrame: GuiObject?) -> (),
}
type CardState = {
	group: LuckyBlockGroup,
	frame: Frame,
	button: GuiButton,
	activatedConnection: RBXScriptConnection,
}
type Controller = {
	mainGui: ScreenGui,
	shopFrame: GuiObject,
	sectionFrame: GuiObject,
	mainFrame: GuiObject,
	listFrame: GuiObject,
	list: ScrollingFrame,
	template: Frame,
	priceBridge: PriceBridge,
	petUIController: any,
	maid: any,
	cards: { CardState },
	selectedGroup: LuckyBlockGroup,
	policyDisabled: boolean?,
	alive: boolean,
	_selectGroup: (self: Controller, group: LuckyBlockGroup) -> (),
	_updatePolicyState: (self: Controller) -> (),
	_updatePurchaseButtonState: (self: Controller, canPurchase: boolean) -> (),
	_updateVisibility: (self: Controller) -> (),
	_updateCards: (self: Controller) -> (),
	_buildCards: (self: Controller) -> (),
	Init: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

local PetLuckyBlockShopController = {}
PetLuckyBlockShopController.__index = PetLuckyBlockShopController

local MODULE_NAME = "PetLuckyBlockShopController"
local CARD_ATTRIBUTE = "PetLuckyBlockShopCard"
local ROBUX_ICON = utf8.char(0xE002)
local POLICY_DARKEN_MULTIPLIER = 0.75
local EVENT_IDS: { [PetConfig.EventId]: string } = {
	NeonRush = "NeonRush",
	FrostbiteRally = "FrostbiteRally",
}
local GROUP_ORDER: { LuckyBlockGroup } = {
	"BloodMoon",
	"Premium",
	"NeonRush",
	"FrostbiteRally",
	"Tier3",
	"Tier2",
	"Tier1",
}
local GROUP_PRIORITY: { [LuckyBlockGroup]: number } = {}
for order, group in ipairs(GROUP_ORDER) do
	GROUP_PRIORITY[group] = order
end
local ROLL_COUNTS = { 1, 3, 5 }

local function findButton(root: Instance): GuiButton?
	if root:IsA("GuiButton") then
		return root
	end
	return root:FindFirstChildWhichIsA("GuiButton", true)
end

local function getRobuxPrice(group: LuckyBlockGroup): number
	if group == "Tier1" or group == "Tier2" or group == "Tier3" or group == "Premium" then
		return PetConfig.LuckyBlocks[group].robuxPricePerRoll or 0
	end
	local eventPrices = PetConfig.LuckyBlocks.Event.eventRobuxPricePerRoll
	return if eventPrices then eventPrices[group] or 0 else 0
end

local function isEventAvailable(group: LuckyBlockGroup): boolean
	local eventId = EVENT_IDS[group :: PetConfig.EventId]
	if not eventId then
		return true
	end

	local state = ReplicatedStorage:FindFirstChild("LiveEventState")
	local activeIds = if state then state:GetAttribute("ActiveEventIds") else nil
	return typeof(activeIds) == "string" and string.find("," .. activeIds .. ",", "," .. eventId .. ",", 1, true) ~= nil
end

local function setCardText(card: CardState): ()
	local style = ColorConfig.LuckyBlocks.TopFrameStyles[card.group]
	local price = NumberFormatting.FormatNumber(getRobuxPrice(card.group))
	if card.button:IsA("TextButton") then
		card.button.Text = string.upper(style.Label) .. "\n" .. ROBUX_ICON .. " " .. price
	end
end

local function clearDisabledColorCache(root: Instance): ()
	local function clearInstance(instance: Instance): ()
		for attributeName in pairs(instance:GetAttributes()) do
			if attributeName == "OriginalDisabledBaseColor" or string.sub(attributeName, 1, 14) == "OriginalColor_" then
				instance:SetAttribute(attributeName, nil)
			end
		end
	end

	clearInstance(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		clearInstance(descendant)
	end
end

local function createCard(self: Controller, group: LuckyBlockGroup, order: number): CardState?
	local style = ColorConfig.LuckyBlocks.TopFrameStyles[group]
	local clone = self.template:Clone()
	clone.Name = group .. "LuckyBlockButton"
	clone.LayoutOrder = order
	clone:SetAttribute(CARD_ATTRIBUTE, true)
	clone.BackgroundColor3 = style.BackgroundColor
	clone:SetAttribute("OriginalDisabledBaseColor", nil)
	clone:SetAttribute("OriginalColor_BackgroundColor3", nil)
	clone:SetAttribute("UiDisabled", nil)
	local gradient = clone:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = style.Gradient
		gradient.Rotation = 90
	end
	local image = clone:FindFirstChild("Image")
	local imageGradient = image and image:FindFirstChildOfClass("UIGradient")
	if imageGradient then
		imageGradient.Color = style.Gradient
		imageGradient.Rotation = 90
	end
	local outerStroke = clone:FindFirstChild("UIStroke")
	if outerStroke and outerStroke:IsA("UIStroke") then
		outerStroke.Color = Color3.new(0, 0, 0)
	end
	local button = findButton(clone)
	if not button then
		clone:Destroy()
		DebugModule.debugWarn("Lucky Block list template has no GuiButton", MODULE_NAME)
		return nil
	end
	clone.Active = true
	button.Active = true
	button.Selectable = true
	button.SelectionOrder = order
	local card: CardState = {
		group = group,
		frame = clone,
		button = button,
		activatedConnection = button.Activated:Connect(function()
			if not self.alive then
				return
			end
			VisualFunctions.PlayFrameClick(clone)
			SoundService.PlayGuiSound("Click")
			self:_selectGroup(group)
		end),
	}
	setCardText(card)
	VisualFunctions.SetupFrameHover(clone, 1.05, 12)
	VisualFunctions.SetupFrameClick(clone, 0.94, -8)
	clone.Visible = true
	clone.Parent = self.list
	return card
end

function PetLuckyBlockShopController.new(mainGui: ScreenGui, priceBridge: PriceBridge): Controller?
	local shopInstance = mainGui:WaitForChild("ShopFrame", 10)
	local scrollBackground = shopInstance and shopInstance:FindFirstChild("ScrollBackground")
	local shopScrollingFrame = scrollBackground and scrollBackground:FindFirstChild("ScrollingFrame")
	local sectionInstance = shopScrollingFrame and shopScrollingFrame:FindFirstChild("LuckyBlocks")
	local mainFrameInstance = sectionInstance and sectionInstance:FindFirstChild("MainFrame")
	local listFrameInstance = sectionInstance and sectionInstance:FindFirstChild("LuckyblockList")
	local listInstance = listFrameInstance and listFrameInstance:FindFirstChild("ScrollingFrame")
	local templateInstance = listInstance and listInstance:FindFirstChild("LuckyBlockButtonTemplate")
	if
		not shopInstance
		or not shopInstance:IsA("GuiObject")
		or not sectionInstance
		or not sectionInstance:IsA("GuiObject")
		or not mainFrameInstance
		or not mainFrameInstance:IsA("GuiObject")
		or not listFrameInstance
		or not listFrameInstance:IsA("GuiObject")
		or not listInstance
		or not listInstance:IsA("ScrollingFrame")
		or not templateInstance
		or not templateInstance:IsA("Frame")
	then
		DebugModule.debugWarn("ShopFrame LuckyBlocks hierarchy is incomplete", MODULE_NAME)
		return nil
	end

	local self = setmetatable({
		mainGui = mainGui,
		shopFrame = shopInstance,
		sectionFrame = sectionInstance,
		mainFrame = mainFrameInstance,
		listFrame = listFrameInstance,
		list = listInstance,
		template = templateInstance,
		priceBridge = priceBridge,
		petUIController = nil,
		maid = Maid.new(),
		cards = {},
		selectedGroup = "BloodMoon",
		policyDisabled = nil,
		alive = true,
	}, PetLuckyBlockShopController) :: Controller

	self.petUIController = PetLuckyBlockUIController.new(
		self.mainFrame,
		"BloodMoon",
		function(rollCount: number, purchaseKind: PurchaseKind)
			if not self.alive then
				return
			end
			if EVENT_IDS[self.selectedGroup :: PetConfig.EventId] and not isEventAvailable(self.selectedGroup) then
				return
			end
			self.priceBridge:RequestRoll(self.selectedGroup, rollCount, purchaseKind, "Shop")
		end
	)
	return self
end

function PetLuckyBlockShopController._selectGroup(self: Controller, group: LuckyBlockGroup): ()
	if not self.alive then
		return
	end
	self.selectedGroup = group

	local petUIController = self.petUIController :: any
	petUIController:SetPreviewGroup(group)
	self.priceBridge:UpdatePrices(group, self.mainFrame)
	self:_updatePolicyState()
	self:_updateCards()
end

function PetLuckyBlockShopController._updatePurchaseButtonState(self: Controller, canPurchase: boolean): ()
	local supportsWins = self.selectedGroup == "Tier1" or self.selectedGroup == "Tier2" or self.selectedGroup == "Tier3"

	for _, rollCount in ipairs(ROLL_COUNTS) do
		local winsFrame = self.mainFrame:FindFirstChild("BuyButton_" .. tostring(rollCount) .. "x", true)
		if winsFrame and winsFrame:IsA("GuiObject") then
			winsFrame.Visible = supportsWins
			VisualFunctions.SetFrameInteractableState(winsFrame, canPurchase and supportsWins)
		end

		local robuxFrame = self.mainFrame:FindFirstChild("RobuxBuyButton_" .. tostring(rollCount) .. "x", true)
		if robuxFrame and robuxFrame:IsA("GuiObject") then
			robuxFrame.Visible = true
			VisualFunctions.SetFrameInteractableState(robuxFrame, canPurchase)
		end
	end
end

function PetLuckyBlockShopController._updatePolicyState(self: Controller): ()
	local player = Players.LocalPlayer
	local policyAllowsPaidRandomItems = player:GetAttribute("Pet_RandomItemPolicyLoaded") == true
		and player:GetAttribute("Pet_PaidRandomItemsRestricted") == false
	local isDisabled = not policyAllowsPaidRandomItems
	if self.policyDisabled ~= isDisabled then
		local selectedObject = GuiService.SelectedObject
		if isDisabled and selectedObject and selectedObject:IsDescendantOf(self.sectionFrame) then
			GuiService.SelectedObject = nil
		end
		self.policyDisabled = isDisabled
		VisualFunctions.SetFrameDisabledState(self.sectionFrame, isDisabled, POLICY_DARKEN_MULTIPLIER)
		if isDisabled then
			-- Keep hidden template colors clean so newly cloned cards do not inherit dimmed visuals.
			VisualFunctions.SetFrameDisabledState(self.template, false, POLICY_DARKEN_MULTIPLIER)
		end
	end
	self:_updatePurchaseButtonState(policyAllowsPaidRandomItems)
end

function PetLuckyBlockShopController._updateCards(self: Controller): ()
	for _, card in ipairs(self.cards) do
		setCardText(card)
	end
end

function PetLuckyBlockShopController._updateVisibility(self: Controller): ()
	local isVisible = self.mainGui.Enabled and self.shopFrame.Visible and self.sectionFrame.Visible
	local petUIController = self.petUIController :: any
	petUIController:SetPreviewVisible(isVisible)
	if isVisible then
		self.priceBridge:UpdatePrices(self.selectedGroup, self.mainFrame)
		self:_updateCards()
	else
		self.priceBridge:CancelPriceUpdates(self.mainFrame)
	end
	self:_updatePolicyState()
end

function PetLuckyBlockShopController.Init(self: Controller): ()
	if not self.alive then
		return
	end
	self.template.Visible = false
	local petUIController = self.petUIController :: any
	petUIController:Init()
	self:_buildCards()
	petUIController:SetPreviewVisible(false)
	self.maid:GiveTask(self.shopFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		self:_updateVisibility()
	end))
	self.maid:GiveTask(self.sectionFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		self:_updateVisibility()
	end))
	self.maid:GiveTask(self.mainGui:GetPropertyChangedSignal("Enabled"):Connect(function()
		self:_updateVisibility()
	end))
	local player = Players.LocalPlayer
	self.maid:GiveTask(player:GetAttributeChangedSignal("Pet_RandomItemPolicyLoaded"):Connect(function()
		self.priceBridge:UpdatePrices(self.selectedGroup, self.mainFrame)
		self:_updatePolicyState()
		self:_updateCards()
	end))
	self.maid:GiveTask(player:GetAttributeChangedSignal("Pet_PaidRandomItemsRestricted"):Connect(function()
		self.priceBridge:UpdatePrices(self.selectedGroup, self.mainFrame)
		self:_updatePolicyState()
		self:_updateCards()
	end))
	local liveEventState = ReplicatedStorage:FindFirstChild("LiveEventState")
		or ReplicatedStorage:WaitForChild("LiveEventState", 10)
	if liveEventState then
		self.maid:GiveTask(liveEventState:GetAttributeChangedSignal("ActiveEventIds"):Connect(function()
			self:_buildCards()
		end))
	end
	self.maid:GiveTask(self.template.Destroying:Connect(function()
		self:Destroy()
	end))
	self:_updateVisibility()
end

function PetLuckyBlockShopController._buildCards(self: Controller): ()
	if not self.alive then
		return
	end
	if self.policyDisabled then
		VisualFunctions.SetFrameDisabledState(self.sectionFrame, false, POLICY_DARKEN_MULTIPLIER)
		clearDisabledColorCache(self.sectionFrame)
		self.policyDisabled = nil
	end
	local existingByGroup: { [LuckyBlockGroup]: CardState } = {}
	for _, card in ipairs(self.cards) do
		existingByGroup[card.group] = card
	end
	local sortedGroups = table.clone(GROUP_ORDER)
	table.sort(sortedGroups, function(left: LuckyBlockGroup, right: LuckyBlockGroup): boolean
		local leftPrice = getRobuxPrice(left)
		local rightPrice = getRobuxPrice(right)
		if leftPrice ~= rightPrice then
			return leftPrice > rightPrice
		end
		return GROUP_PRIORITY[left] < GROUP_PRIORITY[right]
	end)

	local nextCards: { CardState } = {}
	local selectedStillListed = false
	for _, group in ipairs(sortedGroups) do
		if EVENT_IDS[group :: PetConfig.EventId] and not isEventAvailable(group) then
			continue
		end
		local card = existingByGroup[group]
		if not card then
			card = createCard(self, group, #nextCards + 1)
		end
		if card then
			card.frame.LayoutOrder = #nextCards + 1
			table.insert(nextCards, card)
			if card.group == self.selectedGroup then
				selectedStillListed = true
			end
			existingByGroup[group] = nil
		end
	end
	for _, card in pairs(existingByGroup) do
		card.activatedConnection:Disconnect()
		if card.frame.Parent then
			card.frame:Destroy()
		end
	end
	self.cards = nextCards
	if not selectedStillListed then
		self.selectedGroup = "BloodMoon"
	end
	self:_selectGroup(self.selectedGroup)
	self:_updatePolicyState()
end

function PetLuckyBlockShopController.Destroy(self: Controller): ()
	if not self.alive then
		return
	end
	self.alive = false
	self.maid:DoCleaning()
	self.priceBridge:CancelPriceUpdates(self.mainFrame)
	local petUIController = self.petUIController :: any
	petUIController:Destroy()
	for _, card in ipairs(self.cards) do
		card.activatedConnection:Disconnect()
		if card.frame.Parent then
			card.frame:Destroy()
		end
	end
	table.clear(self.cards)
end

return PetLuckyBlockShopController
