--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local HalloweenCandyShopConfig = require(ReplicatedStorage.Modules.Shared.HalloweenCandyShopConfig)
local KartCatalog = require(ReplicatedStorage.Modules.KartCatalog)
local Maid = require(ReplicatedStorage.Modules.Maid)
local MainFunctions = require(ReplicatedStorage.Modules.UI.MainFunctions)
local PlayerHandler = require(ReplicatedStorage.Modules.Shared.PlayerHandler_Client)
local ProductService = require(ReplicatedStorage.Modules.Shared.ProductService_Client)
local ProductCatalog = require(ReplicatedStorage.Modules.Shared.ProductCatalog)
local PetLuckyBlockUIController = require(ReplicatedStorage.Modules.UI.MainGUI.PetLuckyBlockUIController)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

type Product = HalloweenCandyShopConfig.Product
type CardState = {
	product: Product,
	frame: Frame,
	candyFrame: GuiObject,
	candyButton: GuiButton,
	robuxFrame: GuiObject,
	robuxButton: GuiButton,
}
type LuckyBlockPriceBridge = {
	RequestRoll: (self: any, group: string, rollCount: number, purchaseKind: string, source: string) -> boolean,
	UpdatePrices: (self: any, group: string, targetFrame: GuiObject?) -> (),
	CancelPriceUpdates: (self: any, targetFrame: GuiObject?) -> (),
}
type Controller = {
	root: ScreenGui,
	frame: GuiObject,
	openButton: ImageButton,
	template: Frame,
	grid: GuiObject,
	maid: any,
	cards: { CardState },
	previewController: any,
	priceBridge: LuckyBlockPriceBridge,
	imageTasks: { [thread]: boolean },
	physicalShop: Model?,
	physicalShopMaid: any?,
	physicalTouching: boolean,
	alive: boolean,
	_buildCards: (self: Controller) -> (),
	_updateCards: (self: Controller) -> (),
	_updateVisibility: (self: Controller) -> (),
	_onFrameVisibilityChanged: (self: Controller) -> (),
	_getDescription: (self: Controller, product: Product) -> string,
	_loadProductImage: (self: Controller, card: CardState) -> (),
	_bindPhysicalShop: (self: Controller, shop: Model) -> (),
	_clearPhysicalShop: (self: Controller) -> (),
	Init: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

local HalloweenCandyShopUIController = {}
HalloweenCandyShopUIController.__index = HalloweenCandyShopUIController

local MODULE_NAME = "HalloweenCandyShopUIController"
local ROBUX_ICON = utf8.char(0xE002)
local OWNED_DARKEN_MULTIPLIER = 0.6
local PHYSICAL_SHOP_NAME = "PhysicalCandyShop"
local PHYSICAL_TOUCH_PART_NAME = "TouchPart"
local GHOST_MODEL_NAME = "Ghost"
local GHOST_BOB_HEIGHT = 0.45
local GHOST_BOB_CYCLE_SECONDS = 2.4
local GHOST_BOB_UPDATE_INTERVAL = 1 / 30

local function findButton(root: Instance): GuiButton?
	if root:IsA("GuiButton") then
		return root
	end
	return root:FindFirstChildWhichIsA("GuiButton", true)
end

local function getPartTwoState(): boolean
	local state = ReplicatedStorage:FindFirstChild("LiveEventState")
	if not state then
		return false
	end
	return state:GetAttribute("HalloweenPartTwoActive") == true
end

local function findPhysicalCandyShop(): Model?
	local worlds = Workspace:FindFirstChild("Worlds")
	local world = worlds and worlds:FindFirstChild("World1")
	local decorations = world and world:FindFirstChild("Decorations")
	local shop = decorations and decorations:FindFirstChild(PHYSICAL_SHOP_NAME)
	return if shop and shop:IsA("Model") then shop else nil
end

local function ownsProduct(player: Player, product: Product): boolean
	if product.kind == "Kart" then
		return PlayerHandler.OwnsKart(player, product.ownedName)
	end
	if product.kind == "Trail" then
		return PlayerHandler.OwnsTrail(player, product.ownedName)
	end
	return false
end

function HalloweenCandyShopUIController.new(root: ScreenGui, priceBridge: LuckyBlockPriceBridge): Controller?
	local frameInstance = root:WaitForChild("CandyShopFrame", 10)
	local counter = root:WaitForChild("CandyCountFrame", 10)
	local buttonInstance = counter and counter:FindFirstChild("RotateImage", true)
	local scrollingFrame = frameInstance
		and frameInstance:FindFirstChild("ScrollBackground")
		and frameInstance.ScrollBackground:FindFirstChild("ScrollingFrame")
	local productList = scrollingFrame and scrollingFrame:FindFirstChild("ProductList")
	local gridInstance = productList and productList:FindFirstChild("GridList")
	local templateInstance = gridInstance and gridInstance:FindFirstChild("CardTemplate")
	if
		not frameInstance
		or not frameInstance:IsA("GuiObject")
		or not buttonInstance
		or not buttonInstance:IsA("ImageButton")
		or not gridInstance
		or not gridInstance:IsA("GuiObject")
		or not templateInstance
		or not templateInstance:IsA("Frame")
	then
		DebugModule.debugWarn("Candy shop UI hierarchy incomplete", MODULE_NAME)
		return nil
	end

	local luckyBlock = scrollingFrame:FindFirstChild("LuckyBlock")
	local luckyBlockMain = luckyBlock and luckyBlock:FindFirstChild("MainFrame")
	if not luckyBlockMain or not luckyBlockMain:IsA("GuiObject") then
		DebugModule.debugWarn("Candy shop LuckyBlock.MainFrame missing", MODULE_NAME)
		return nil
	end

	local self = setmetatable({
		root = root,
		frame = frameInstance,
		openButton = buttonInstance,
		template = templateInstance,
		grid = gridInstance,
		maid = Maid.new(),
		cards = {},
		previewController = nil,
		priceBridge = priceBridge,
		imageTasks = {},
		physicalShop = nil,
		physicalShopMaid = nil,
		physicalTouching = false,
		alive = true,
	}, HalloweenCandyShopUIController) :: Controller

	self.previewController = PetLuckyBlockUIController.new(
		luckyBlockMain,
		"Halloween",
		function(rollCount: number, purchaseKind: string)
			if self.alive then
				self.priceBridge:RequestRoll("Halloween", rollCount, purchaseKind, "Shop")
			end
		end
	)
	return self
end

function HalloweenCandyShopUIController._getDescription(self: Controller, product: Product): string
	if product.description then
		return product.description
	end
	if product.kind == "Trail" then
		local trailConfig = PlayerHandler.GetTrailConfig(product.ownedName)
		local multiplier = if trailConfig then trailConfig.XPMultiplier else nil
		return if typeof(multiplier) == "number" then tostring(multiplier) .. "x Speed Boost" else "Speed Boost"
	end
	local model = if product.kartModelName
		then KartCatalog.FindModel(product.kartModelName, "Specials", "Halloween")
		else nil
	local xpGain = model and model:GetAttribute("XP_Gain")
	local numericGain = if typeof(xpGain) == "number" then xpGain else if typeof(xpGain) == "string" then tonumber(xpGain) else nil
	return if numericGain then string.format("+%d/Steps", math.round(numericGain)) else "+0/Steps"
end

function HalloweenCandyShopUIController._loadProductImage(self: Controller, card: CardState): ()
	local image = card.frame:FindFirstChild("ProductImage", true)
	local productId = ProductCatalog.DevProducts[card.product.productKey]
	if not image or not image:IsA("ImageLabel") or typeof(productId) ~= "number" then
		return
	end
	local imageLabel = image
	local thread: thread
	thread = task.spawn(function()
		local success, info = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		self.imageTasks[thread] = nil
		if not self.alive or not imageLabel.Parent or not success or typeof(info) ~= "table" then
			return
		end
		local iconId = tonumber((info :: any).IconImageAssetId)
		if iconId and iconId > 0 then
			imageLabel.Image = "rbxassetid://" .. tostring(iconId)
		end
	end)
	self.imageTasks[thread] = true
end

function HalloweenCandyShopUIController._buildCards(self: Controller): ()
	self.template.Visible = false
	for _, child in ipairs(self.grid:GetChildren()) do
		if child:GetAttribute("HalloweenCandyProductCard") == true then
			child:Destroy()
		end
	end
	table.clear(self.cards)
	for order, product in ipairs(HalloweenCandyShopConfig.Products) do
		local cardInstance = self.template:Clone()
		cardInstance.Name = product.key .. "Card"
		cardInstance.LayoutOrder = order
		cardInstance:SetAttribute("HalloweenCandyProductCard", true)
		cardInstance.Visible = true
		local nameLabel = cardInstance:FindFirstChild("ProductName", true)
		if nameLabel and nameLabel:IsA("TextLabel") then
			nameLabel.Text = product.displayName
		end
		local description = self:_getDescription(product)
		for _, labelName in ipairs({ "ProductDescription", "ProductName1" }) do
			local label = cardInstance:FindFirstChild(labelName, true)
			if label and label:IsA("TextLabel") then
				label.Text = description
			end
		end
		local candyFrame = cardInstance:FindFirstChild("CandyBuy")
		local candyButton = candyFrame and findButton(candyFrame)
		local robuxFrame = cardInstance:FindFirstChild("RobuxBuy")
		local robuxButton = robuxFrame and findButton(robuxFrame)
		if
			not candyFrame or not candyFrame:IsA("GuiObject") or not candyButton
			or not robuxFrame or not robuxFrame:IsA("GuiObject") or not robuxButton
		then
			cardInstance:Destroy()
			DebugModule.debugWarn("Candy product card missing buy buttons | product=" .. product.key, MODULE_NAME)
			continue
		end
		local candyText = candyButton:FindFirstChildWhichIsA("TextLabel")
		if candyButton:IsA("TextButton") then
			candyButton.Text = tostring(product.candyPrice)
		elseif candyText then
			candyText.Text = tostring(product.candyPrice)
		end
		if robuxButton:IsA("TextButton") then
			robuxButton.Text = ROBUX_ICON
		end
		local card: CardState = {
			product = product,
			frame = cardInstance,
			candyFrame = candyFrame,
			candyButton = candyButton,
			robuxFrame = robuxFrame,
			robuxButton = robuxButton,
		}
		if product.candyPurchasable == false then
			candyFrame.Visible = false
			candyButton.Active = false
			candyButton.Interactable = false
		end
		table.insert(self.cards, card)
		self.maid:GiveTask(candyButton.Activated:Connect(function()
			local player = Players.LocalPlayer
			if not self.alive or product.candyPurchasable == false or ownsProduct(player, product) then
				return
			end
			local remotes = ReplicatedStorage:FindFirstChild("Remotes")
			local purchaseRemote = remotes and remotes:FindFirstChild("HalloweenCandyShopPurchase")
			if purchaseRemote and purchaseRemote:IsA("RemoteEvent") then
				purchaseRemote:FireServer("Purchase", product.productKey)
			end
		end))
		self.maid:GiveTask(robuxButton.Activated:Connect(function()
			local player = Players.LocalPlayer
			if not self.alive or ownsProduct(player, product) then
				return
			end
			local productId = ProductCatalog.DevProducts[product.productKey]
			if typeof(productId) == "number" then
				ProductService.promptProductPurchase(player, productId)
			end
		end))
		self:_loadProductImage(card)
		cardInstance.Parent = self.grid
	end
	self:_updateCards()
end

function HalloweenCandyShopUIController._updateCards(self: Controller): ()
	local player = Players.LocalPlayer
	local balanceValue = player:GetAttribute("HalloweenCandyCount")
	local balance = if typeof(balanceValue) == "number" then math.max(0, math.floor(balanceValue)) else 0
	for _, card in ipairs(self.cards) do
		local owned = ownsProduct(player, card.product)
		VisualFunctions.SetFrameDisabledState(card.frame, owned, OWNED_DARKEN_MULTIPLIER)
		VisualFunctions.SetFrameDisabledState(
			card.candyFrame,
			owned or card.product.candyPurchasable == false or balance < card.product.candyPrice,
			OWNED_DARKEN_MULTIPLIER
		)
		card.candyFrame.Visible = card.product.candyPurchasable ~= false
		VisualFunctions.SetFrameDisabledState(card.robuxFrame, owned, OWNED_DARKEN_MULTIPLIER)
		card.candyButton.Active = not owned and balance >= card.product.candyPrice
		card.candyButton.Interactable = not owned and balance >= card.product.candyPrice
		card.robuxButton.Active = not owned
		card.robuxButton.Interactable = not owned
	end
end

function HalloweenCandyShopUIController._clearPhysicalShop(self: Controller): ()
	local shopMaid = self.physicalShopMaid
	self.physicalShopMaid = nil
	self.physicalShop = nil
	self.physicalTouching = false
	if shopMaid then
		shopMaid:DoCleaning()
	end
	if self.frame.Visible then
		MainFunctions.ToggleFrame("CandyShopFrame")
	end
end

function HalloweenCandyShopUIController._bindPhysicalShop(self: Controller, shop: Model): ()
	if not self.alive or findPhysicalCandyShop() ~= shop or self.physicalShop == shop then
		return
	end

	self:_clearPhysicalShop()
	self.physicalShop = shop
	local shopMaid = Maid.new()
	self.physicalShopMaid = shopMaid
	local touchPartInstance = shop:FindFirstChild(PHYSICAL_TOUCH_PART_NAME, true)
	local ghostInstance = shop:FindFirstChild(GHOST_MODEL_NAME, true)

	if not touchPartInstance or not touchPartInstance:IsA("BasePart") then
		DebugModule.debugWarn("PhysicalCandyShop.TouchPart is missing", MODULE_NAME)
	else
		local touchPart = touchPartInstance
		local touchingCharacterParts: { [BasePart]: boolean } = {}
		local function openShop(): ()
			if not self.alive or not getPartTwoState() then
				return
			end
			self.physicalTouching = true
			if not self.frame.Visible then
				MainFunctions.ToggleFrame("CandyShopFrame")
			end
		end
		local function closeShop(): ()
			self.physicalTouching = false
			if self.frame.Visible then
				MainFunctions.ToggleFrame("CandyShopFrame")
			end
		end

		shopMaid:GiveTask(touchPart.Touched:Connect(function(hit: BasePart)
			local character = Players.LocalPlayer.Character
			if character and hit:IsDescendantOf(character) then
				touchingCharacterParts[hit] = true
				openShop()
			end
		end))
		shopMaid:GiveTask(touchPart.TouchEnded:Connect(function(hit: BasePart)
			local character = Players.LocalPlayer.Character
			if character and hit:IsDescendantOf(character) then
				touchingCharacterParts[hit] = nil
				if next(touchingCharacterParts) == nil then
					closeShop()
				end
			end
		end))
		shopMaid:GiveTask(Players.LocalPlayer.CharacterRemoving:Connect(function()
			table.clear(touchingCharacterParts)
			closeShop()
		end))
	end

	if ghostInstance and ghostInstance:IsA("Model") then
		local ghost = ghostInstance
		local basePivot = ghost:GetPivot()
		local startTime = Workspace:GetServerTimeNow()
		local updateAccumulator = 0
		shopMaid:GiveTask(RunService.Heartbeat:Connect(function(deltaTime: number)
			if not self.alive or not ghost:IsDescendantOf(shop) then
				return
			end

			updateAccumulator += deltaTime
			if updateAccumulator < GHOST_BOB_UPDATE_INTERVAL then
				return
			end
			updateAccumulator %= GHOST_BOB_UPDATE_INTERVAL

			local elapsed = Workspace:GetServerTimeNow() - startTime
			local bobOffset = math.sin((elapsed * math.pi * 2) / GHOST_BOB_CYCLE_SECONDS) * GHOST_BOB_HEIGHT
			ghost:PivotTo(basePivot * CFrame.new(0, bobOffset, 0))
		end))
	else
		DebugModule.debugWarn("PhysicalCandyShop.Ghost model is missing", MODULE_NAME)
	end

	shopMaid:GiveTask(shop.Destroying:Connect(function()
		if self.physicalShop == shop then
			self:_clearPhysicalShop()
		end
	end))
end

function HalloweenCandyShopUIController._onFrameVisibilityChanged(self: Controller): ()
	if not self.alive then
		return
	end
	local available = getPartTwoState()
	local shouldPreview = self.frame.Visible and available
	if self.previewController then
		self.previewController:SetPreviewVisible(shouldPreview)
	end
	local scrollBackground = self.frame:FindFirstChild("ScrollBackground")
	local scrollingFrame = scrollBackground and scrollBackground:FindFirstChild("ScrollingFrame")
	local luckyBlock = scrollingFrame and scrollingFrame:FindFirstChild("LuckyBlock")
	local luckyMain = luckyBlock and luckyBlock:FindFirstChild("MainFrame")
	if luckyMain and luckyMain:IsA("GuiObject") then
		if shouldPreview then
			self.priceBridge:UpdatePrices("Halloween", luckyMain)
		else
			self.priceBridge:CancelPriceUpdates(luckyMain)
		end
	end
	self:_updateCards()
	if self.frame.Visible and not available then
		MainFunctions.ToggleFrame("CandyShopFrame")
	end
	if not available then
		self.physicalTouching = false
	end
end

function HalloweenCandyShopUIController._updateVisibility(self: Controller): ()
	local available = getPartTwoState()
	self.openButton.Interactable = available
	self.openButton.Active = available
	if not available then
		self:_onFrameVisibilityChanged()
	elseif self.physicalTouching and not self.frame.Visible then
		MainFunctions.ToggleFrame("CandyShopFrame")
	end
end

function HalloweenCandyShopUIController.Init(self: Controller): ()
	if not self.alive then
		return
	end
	self.frame.Visible = false
	self:_buildCards()
	self.previewController:Init()
	self.previewController:SetPreviewGroup("Halloween")
	self.previewController:SetPreviewVisible(false)
	local existingPhysicalShop = findPhysicalCandyShop()
	if existingPhysicalShop then
		self:_bindPhysicalShop(existingPhysicalShop)
	end
	self.maid.PhysicalCandyShopAdded = Workspace.DescendantAdded:Connect(function(instance: Instance)
		if instance.Name == PHYSICAL_SHOP_NAME and instance:IsA("Model") then
			self:_bindPhysicalShop(instance)
		end
	end)
	self.maid.PhysicalCandyShopRemoved = Workspace.DescendantRemoving:Connect(function(instance: Instance)
		if instance == self.physicalShop then
			self:_clearPhysicalShop()
		end
	end)
	self.maid:GiveTask(self.frame:GetPropertyChangedSignal("Visible"):Connect(function()
		self:_onFrameVisibilityChanged()
	end))
	local player = Players.LocalPlayer
	self.maid:GiveTask(player:GetAttributeChangedSignal("HalloweenCandyCount"):Connect(function()
		self:_updateCards()
	end))
	self.maid:GiveTask(player:GetAttributeChangedSignal("OwnedKarts"):Connect(function()
		self:_updateCards()
	end))
	self.maid:GiveTask(player:GetAttributeChangedSignal("OwnedTrails"):Connect(function()
		self:_updateCards()
	end))
	local state = ReplicatedStorage:WaitForChild("LiveEventState", 10)
	if state then
		self.maid:GiveTask(state:GetAttributeChangedSignal("HalloweenPartTwoActive"):Connect(function()
			self:_updateVisibility()
		end))
		self.maid:GiveTask(state:GetAttributeChangedSignal("EnvironmentName"):Connect(function()
			self:_updateVisibility()
		end))
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local purchaseRemote = remotes and remotes:WaitForChild("HalloweenCandyShopPurchase", 10)
	if purchaseRemote and purchaseRemote:IsA("RemoteEvent") then
		self.maid:GiveTask(purchaseRemote.OnClientEvent:Connect(function(action: unknown, productKey: unknown, succeeded: unknown, reason: unknown)
			if action ~= "Result" or typeof(productKey) ~= "string" or typeof(succeeded) ~= "boolean" then
				return
			end
			if succeeded then
				self:_updateCards()
			elseif reason == "NotEnoughCandy" then
				VisualFunctions.ShowNotification("NOT ENOUGH CANDY!", Color3.fromRGB(255, 90, 90), Color3.fromRGB(140, 0, 0))
			end
		end))
	end
	self:_updateVisibility()
	self:_onFrameVisibilityChanged()
	self.maid:GiveTask(self.frame.Destroying:Connect(function()
		self:Destroy()
	end))
end

function HalloweenCandyShopUIController.Destroy(self: Controller): ()
	if not self.alive then
		return
	end
	self:_clearPhysicalShop()
	self.alive = false
	self.frame.Visible = false
	for thread in pairs(self.imageTasks) do
		pcall(task.cancel, thread)
		self.imageTasks[thread] = nil
	end
	self.maid:DoCleaning()
	if self.previewController then
		self.previewController:Destroy()
		self.previewController = nil
	end
	self.priceBridge:CancelPriceUpdates(nil)
end

return HalloweenCandyShopUIController
