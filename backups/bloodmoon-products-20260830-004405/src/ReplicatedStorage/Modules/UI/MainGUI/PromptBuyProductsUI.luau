--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = Modules:WaitForChild("Config")
local UI = Modules:WaitForChild("UI")

local CoreConfig = require(Config:WaitForChild("CoreConfig"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local Maid = require(Modules:WaitForChild("Maid"))
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local ProductService = require(Modules:WaitForChild("ProductService"))
local RewardedVideoClient = require(Modules:WaitForChild("RewardedVideoClient"))
local VisualFunctions = require(UI:WaitForChild("VisualFunctions"))

local PromptBuyProductsUI = {}
PromptBuyProductsUI.__index = PromptBuyProductsUI

local MODULE_NAME = "PromptBuyProductsUI"
local DEFAULT_VISIBLE_POSITION = UDim2.new(0.873, 0, 0.874, 0)
local DEFAULT_HIDDEN_POSITION = UDim2.new(2, 0, 0.874, 0)
local DEFAULT_PROMPT_DURATION_SECONDS = 15
local PROMPT_BLOCKING_FRAMES = {
	"SpinWheelFrame",
	"DailyRewardFrame",
	"RebirthFrame",
	"ShopFrame",
	"TrailFrame",
	"KartFrame",
	"TrollFrame",
}

type ProductKind = "DevProduct" | "GamePass"

type ProductInfo = {
	[string]: any,
}

type ProductCandidate = {
	key: string,
	id: number,
	kind: ProductKind,
	infoType: any,
	category: string,
	info: ProductInfo,
}

type PromptBuyProductsUIObject = {
	screenGui: ScreenGui,
	player: Player,
	frame: Frame,
	productImage: ImageLabel?,
	countdownLabel: TextLabel,
	priceLabel: TextLabel,
	productTitleLabel: TextLabel,
	productDescriptionLabel: TextLabel,
	buyFrame: GuiObject,
	buyButton: GuiButton,
	watchAdFrame: GuiObject,
	watchAdButton: GuiButton,
	exitFrame: GuiObject,
	exitButton: GuiButton,
	maid: any,
	characterMaid: any,
	alive: boolean,
	promptVisible: boolean,
	selectionInFlight: boolean,
	promptToken: number,
	deathsSincePrompt: number,
	deathTarget: number,
	deathTriggerReady: boolean,
	timeTriggerReady: boolean,
	nextTimeTriggerAt: number,
	currentProduct: ProductCandidate?,
	rewardedVideoInFlight: boolean,
	activeTween: Tween?,
	studioPromptReady: boolean,
	random: Random,
	marketplaceInfoCache: { [string]: ProductInfo },
}

type PromptBuyProductsUIType = PromptBuyProductsUIObject

local promptConfig: any = CoreConfig.promptBuy or {}
local STUDIO_ALWAYS_SHOW = RunService:IsStudio() and promptConfig.studioAlwaysShow == true
local MIN_DEATHS = math.max(1, math.floor(tonumber(promptConfig.minDeaths) or 3))
local MAX_DEATHS = math.max(MIN_DEATHS, math.floor(tonumber(promptConfig.maxDeaths) or 5))
local MIN_MINUTES = math.max(1, math.floor(tonumber(promptConfig.minMinutes) or 3))
local MAX_MINUTES = math.max(MIN_MINUTES, math.floor(tonumber(promptConfig.maxMinutes) or 10))
local TEMPORARY_BOOST_SELECTION_WEIGHT = math.max(
	1,
	tonumber(promptConfig.temporaryBoostSelectionWeight) or 3
)
local PROMPT_DURATION_SECONDS = math.max(
	1,
	math.floor(tonumber(promptConfig.displayDurationSeconds) or DEFAULT_PROMPT_DURATION_SECONDS)
)
local VISIBLE_POSITION = if typeof(promptConfig.visiblePosition) == "UDim2"
	then promptConfig.visiblePosition
	else DEFAULT_VISIBLE_POSITION
local HIDDEN_POSITION = if typeof(promptConfig.hiddenPosition) == "UDim2"
	then promptConfig.hiddenPosition
	else DEFAULT_HIDDEN_POSITION

local function findRequiredChild(root: Instance, name: string, className: string): Instance
	local child = root:FindFirstChild(name, true)
	assert(child and child.ClassName == className, string.format("%s.%s must be a %s", root:GetFullName(), name, className))
	return child
end

local function getRandomInteger(random: Random, minimum: number, maximum: number): number
	return random:NextInteger(minimum, maximum)
end

local function formatCountdown(seconds: number): string
	local remaining = math.max(0, math.ceil(seconds))
	return string.format("%ds", remaining)
end

local function getRewardedVideoPlacement(productKey: string): string?
	if productKey == "TempSpeedBoost" then
		return "PromptTempSpeedBoost"
	elseif productKey == "TempWinBoost" then
		return "PromptTempWinBoost"
	end
	return nil
end

local function toAssetId(value: any): string?
	if typeof(value) ~= "number" or value <= 0 then
		return nil
	end

	return "rbxassetid://" .. tostring(math.floor(value))
end

local function getCategory(productKey: string): string
	if string.find(productKey, "Trail", 1, true) then
		return "Trail"
	elseif string.find(productKey, "Kart", 1, true)
		or productKey == "AdvancedTank"
		or productKey == "ShoppingKart"
		or productKey == "FormulaCar" then
		return "Kart"
	elseif productKey == "StarterPack" then
		return "Utility"
	elseif productKey == "TempSpeedBoost" or productKey == "TempWinBoost" then
		return "TemporaryBoost"
	elseif string.sub(productKey, 1, 4) == "Spin" then
		return "Spin"
	elseif string.find(productKey, "Treadmill", 1, true) then
		return "Treadmill"
	elseif productKey == "+100K" or productKey == "+1M" or productKey == "+10M" then
		return "Speed"
	elseif productKey == "+1000" or productKey == "+5000" or productKey == "+10000" then
		return "Wins"
	elseif string.find(productKey, "Wins", 1, true)
		or string.find(productKey, "Win", 1, true) then
		return "Wins"
	elseif string.find(productKey, "Speed", 1, true)
		or string.find(productKey, "x", 1, true) then
		return "Speed"
	end

	return "Utility"
end

local function getDescription(random: Random, category: string): string
	local pools = promptConfig.descriptionPools
	local pool = if typeof(pools) == "table" then pools[category] else nil
	if typeof(pool) ~= "table" or #pool == 0 then
		pool = if typeof(pools) == "table" then pools.Default else nil
	end
	if typeof(pool) ~= "table" or #pool == 0 then
		return "Power up your run and progress faster!"
	end

	local description = tostring(pool[getRandomInteger(random, 1, #pool)])
	return string.sub(description, 1, 130)
end

local function isExcludedDevProduct(productKey: string): boolean
	-- Keep this safety check local to the selector so config drift cannot expose
	-- the strict ReturnToStage offer through the generic purchase prompt.
	if productKey == "ReturnToStage" or productKey == "Teleport" then
		return true
	end

	local excludedKeys = promptConfig.excludedDevProductKeys
	if typeof(excludedKeys) == "table" and excludedKeys[productKey] == true then
		return true
	end

	for _, multiplierProductKey in pairs(ProductService.MULTIPLIER_TO_PRODUCT) do
		if multiplierProductKey == productKey then
			return true
		end
	end

	return false
end

function PromptBuyProductsUI.new(screenGui: Instance): PromptBuyProductsUIType
	assert(screenGui:IsA("ScreenGui"), "PromptBuyProductsUI requires a ScreenGui root")

	local frame = findRequiredChild(screenGui, "PromptBuyProductsFrame", "Frame") :: Frame
	local bodyFrame = findRequiredChild(frame, "BodyFrame", "Frame") :: Frame
	local buyFrame = findRequiredChild(frame, "BuyButton", "Frame") :: GuiObject
	local watchAdFrame = findRequiredChild(frame, "WatchAdButton", "Frame") :: GuiObject
	local exitFrame = findRequiredChild(frame, "ExitButton", "Frame") :: GuiObject

	local self = setmetatable({
		screenGui = screenGui :: ScreenGui,
		player = Players.LocalPlayer,
		frame = frame,
		productImage = bodyFrame:FindFirstChild("ProductImage", true) :: ImageLabel?,
		countdownLabel = findRequiredChild(frame, "CountdownLabel", "TextLabel") :: TextLabel,
		priceLabel = findRequiredChild(frame, "PriceLabel", "TextLabel") :: TextLabel,
		productTitleLabel = findRequiredChild(frame, "ProductTitleLabel", "TextLabel") :: TextLabel,
		productDescriptionLabel = findRequiredChild(frame, "ProductDescriptionLabel", "TextLabel") :: TextLabel,
		buyFrame = buyFrame,
		buyButton = findRequiredChild(buyFrame, "TextButton", "TextButton") :: GuiButton,
		watchAdFrame = watchAdFrame,
		watchAdButton = findRequiredChild(watchAdFrame, "TextButton", "TextButton") :: GuiButton,
		exitFrame = exitFrame,
		exitButton = findRequiredChild(exitFrame, "TextButton", "TextButton") :: GuiButton,
		maid = Maid.new(),
		characterMaid = Maid.new(),
		alive = true,
		promptVisible = false,
		selectionInFlight = false,
		promptToken = 0,
		deathsSincePrompt = 0,
		deathTarget = MIN_DEATHS,
		deathTriggerReady = false,
		timeTriggerReady = false,
		nextTimeTriggerAt = 0,
		currentProduct = nil,
		rewardedVideoInFlight = false,
		activeTween = nil,
		studioPromptReady = true,
		random = Random.new(),
		marketplaceInfoCache = {},
	}, PromptBuyProductsUI)

	self.frame.Position = HIDDEN_POSITION
	self.frame.Visible = true
	self:_enableInteraction()
	self.watchAdFrame.Visible = false
	self.countdownLabel.Text = formatCountdown(0)

	return self
end

function PromptBuyProductsUI._getMarketplaceInfo(
	self: PromptBuyProductsUIType,
	productId: number,
	infoType: any
): ProductInfo?
	local cacheKey = tostring(infoType) .. ":" .. tostring(productId)
	local cached = self.marketplaceInfoCache[cacheKey]
	if cached then
		return cached
	end

	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(productId, infoType)
	end)
	if not success or typeof(info) ~= "table" then
		DebugModule.debugWarn(
			string.format("Product metadata unavailable | productId=%d | infoType=%s", productId, tostring(infoType)),
			MODULE_NAME
		)
		return nil
	end

	local typedInfo = info :: ProductInfo
	self.marketplaceInfoCache[cacheKey] = typedInfo
	return typedInfo
end

function PromptBuyProductsUI._isPermanentProductOwned(
	self: PromptBuyProductsUIType,
	productKey: string,
	productKind: ProductKind,
	productId: number
): boolean
	if productKind == "GamePass" then
		return ProductService.userOwnsGamePass(self.player, productId)
	end

	local permanentProductKeys = promptConfig.permanentDevProductKeys
	local ownershipType = if typeof(permanentProductKeys) == "table" then permanentProductKeys[productKey] else nil
	if ownershipType == "Trail" then
		return PlayerHandler.OwnsTrail(self.player, productKey)
	elseif ownershipType == "Kart" then
		return PlayerHandler.OwnsKart(self.player, productKey)
	end

	return false
end

function PromptBuyProductsUI._collectEligibleProducts(self: PromptBuyProductsUIType): { ProductCandidate }
	local candidates: { ProductCandidate } = {}

	for productKey, rawId in pairs(ProductService.DevProducts) do
		if typeof(productKey) == "string" and typeof(rawId) == "number" and not isExcludedDevProduct(productKey) then
			local productInfo = self:_getMarketplaceInfo(rawId, Enum.InfoType.Product)
			if productInfo then
				table.insert(candidates, {
					key = productKey,
					id = rawId,
					kind = "DevProduct",
					infoType = Enum.InfoType.Product,
					category = getCategory(productKey),
					info = productInfo,
				})
			end
		end
	end

	for productKey, rawId in pairs(ProductService.Gamepasses) do
		if typeof(productKey) == "string" and typeof(rawId) == "number" then
			if not self:_isPermanentProductOwned(productKey, "GamePass", rawId) then
				local productInfo = self:_getMarketplaceInfo(rawId, Enum.InfoType.GamePass)
				if productInfo then
					table.insert(candidates, {
						key = productKey,
						id = rawId,
						kind = "GamePass",
						infoType = Enum.InfoType.GamePass,
						category = getCategory(productKey),
						info = productInfo,
					})
				end
			end
		end
	end

	return candidates
end

function PromptBuyProductsUI._selectProduct(self: PromptBuyProductsUIType): ProductCandidate?
	local candidates = self:_collectEligibleProducts()
	if #candidates == 0 then
		DebugModule.debugWarn("No eligible products available for generic prompt", MODULE_NAME)
		return nil
	end

	local totalWeight = 0
	for _, candidate in ipairs(candidates) do
		totalWeight += if candidate.category == "TemporaryBoost"
			then TEMPORARY_BOOST_SELECTION_WEIGHT
			else 1
	end

	local selection = self.random:NextNumber(0, totalWeight)
	local accumulatedWeight = 0
	for _, candidate in ipairs(candidates) do
		accumulatedWeight += if candidate.category == "TemporaryBoost"
			then TEMPORARY_BOOST_SELECTION_WEIGHT
			else 1
		if selection <= accumulatedWeight then
			return candidate
		end
	end

	return candidates[#candidates]
end

function PromptBuyProductsUI._isBlockedByOtherUI(self: PromptBuyProductsUIType): boolean
	for _, frameName in ipairs(PROMPT_BLOCKING_FRAMES) do
		local otherFrame = self.screenGui:FindFirstChild(frameName, true)
		if otherFrame and otherFrame:IsA("GuiObject") and otherFrame.Visible then
			return true
		end
	end

	return false
end

function PromptBuyProductsUI._stopActiveTween(self: PromptBuyProductsUIType)
	if self.activeTween then
		self.activeTween:Cancel()
		self.activeTween:Destroy()
		self.activeTween = nil
	end
end

function PromptBuyProductsUI._tweenTo(self: PromptBuyProductsUIType, position: UDim2)
	self:_stopActiveTween()
	local tween = TweenService:Create(
		self.frame,
		TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = position }
	)
	self.activeTween = tween
	tween:Play()
	tween.Completed:Once(function()
		if self.activeTween == tween then
			self.activeTween = nil
		end
		tween:Destroy()
	end)
end

function PromptBuyProductsUI._resetTriggers(self: PromptBuyProductsUIType)
	self.deathsSincePrompt = 0
	self.deathTarget = getRandomInteger(self.random, MIN_DEATHS, MAX_DEATHS)
	self.deathTriggerReady = false
	self.timeTriggerReady = false
	local minutes = getRandomInteger(self.random, MIN_MINUTES, MAX_MINUTES)
	self.nextTimeTriggerAt = os.clock() + minutes * 60
end

function PromptBuyProductsUI._enableInteraction(self: PromptBuyProductsUIType)
	self.frame.Active = true
	self.frame.Interactable = true
	self.buyFrame.Active = true
	self.buyFrame.Interactable = true
	self.exitFrame.Active = true
	self.exitFrame.Interactable = true
	self.buyButton.Active = true
	self.buyButton.Interactable = true
	self.buyButton.Selectable = true
	self.exitButton.Active = true
	self.exitButton.Interactable = true
	self.exitButton.Selectable = true
	self.watchAdFrame.Active = true
	self.watchAdFrame.Interactable = true
	self.watchAdButton.Active = true
	self.watchAdButton.Interactable = true
	self.watchAdButton.Selectable = true
end

function PromptBuyProductsUI._showProduct(self: PromptBuyProductsUIType, product: ProductCandidate)
	self.promptToken += 1
	local token = self.promptToken
	self.currentProduct = product
	self.rewardedVideoInFlight = false
	self.promptVisible = true
	self:_enableInteraction()
	if STUDIO_ALWAYS_SHOW then
		self.studioPromptReady = false
	end
	self.countdownLabel.Text = formatCountdown(PROMPT_DURATION_SECONDS)
	self.priceLabel.Text = tostring(math.max(0, math.floor(tonumber(product.info.PriceInRobux) or 0)))
	self.productTitleLabel.Text = string.upper(tostring(product.info.Name or product.key))
	self.productDescriptionLabel.Text = getDescription(self.random, product.category)
	self.watchAdFrame.Visible = product.category == "TemporaryBoost" and RewardedVideoClient.IsAvailable()

	local imageId = toAssetId(product.info.IconImageAssetId)
	if self.productImage and imageId then
		self.productImage.Image = imageId
	end

	self.frame.Visible = true
	self:_tweenTo(VISIBLE_POSITION)

	task.spawn(function()
		local expiresAt = os.clock() + PROMPT_DURATION_SECONDS
		while self.alive and self.promptVisible and self.promptToken == token do
			local remaining = expiresAt - os.clock()
			self.countdownLabel.Text = formatCountdown(remaining)
			if remaining <= 0 then
				self:_hidePrompt(token)
				break
			end
			task.wait(0.1)
		end
	end)
end

function PromptBuyProductsUI._hidePrompt(self: PromptBuyProductsUIType, expectedToken: number?)
	if expectedToken and expectedToken ~= self.promptToken then
		return
	end

	self.promptToken += 1
	self.promptVisible = false
	self.currentProduct = nil
	self.rewardedVideoInFlight = false
	self.watchAdFrame.Visible = false
	if STUDIO_ALWAYS_SHOW then
		self.studioPromptReady = true
	end
	self.countdownLabel.Text = formatCountdown(0)
	self:_tweenTo(HIDDEN_POSITION)
end

function PromptBuyProductsUI._handlePurchaseFinished(
	self: PromptBuyProductsUIType,
	productId: number,
	wasPurchased: boolean
)
	local product = self.currentProduct
	if not self.alive or not self.promptVisible or not wasPurchased or not product then
		return
	end

	if product.id ~= productId then
		return
	end

	DebugModule.debugInfo(
		string.format("Prompt purchase succeeded; hiding product prompt | productId=%d", productId),
		MODULE_NAME
	)
	self:_hidePrompt()
end

function PromptBuyProductsUI._tryShowPrompt(self: PromptBuyProductsUIType)
	if not self.alive
		or self.promptVisible
		or self.selectionInFlight
		or STUDIO_ALWAYS_SHOW and not self.studioPromptReady
		or self:_isBlockedByOtherUI() then
		return
	end

	if not STUDIO_ALWAYS_SHOW
		and (self.player:GetAttribute("TutorialCompleted") ~= true
			or not self.deathTriggerReady and not self.timeTriggerReady) then
		return
	end

	self.selectionInFlight = true
	local product = self:_selectProduct()
	self.selectionInFlight = false
	if not self.alive or not product then
		self:_resetTriggers()
		return
	end

	self:_resetTriggers()
	self:_showProduct(product)
end

function PromptBuyProductsUI._recordDeath(self: PromptBuyProductsUIType)
	if not self.alive then
		return
	end

	self.deathsSincePrompt += 1
	if self.deathsSincePrompt >= self.deathTarget then
		self.deathTriggerReady = true
	end
	self:_tryShowPrompt()
end

function PromptBuyProductsUI._bindCharacter(self: PromptBuyProductsUIType, character: Model)
	self.characterMaid:DoCleaning()

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		local humanoidInstance = character:WaitForChild("Humanoid", 5)
		if humanoidInstance and humanoidInstance:IsA("Humanoid") then
			humanoid = humanoidInstance
		end
	end
	if not humanoid then
		DebugModule.debugWarn("Prompt Buy could not bind Humanoid death signal", MODULE_NAME)
		return
	end

	self.characterMaid:GiveTask(humanoid.Died:Connect(function()
		self:_recordDeath()
	end))
end

function PromptBuyProductsUI.Init(self: PromptBuyProductsUIType)
	self:_resetTriggers()

	VisualFunctions.SetupFrameHover(self.buyFrame, 1.05, 35, 1.2)
	VisualFunctions.SetupFrameClick(self.buyFrame, 0.9, -15, 0.8)
	VisualFunctions.SetupFrameHover(self.exitFrame, 1.05, 35, 1.2)
	VisualFunctions.SetupFrameClick(self.exitFrame, 0.9, -15, 0.8)
	VisualFunctions.SetupFrameHover(self.watchAdFrame, 1.05, 35, 1.2)
	VisualFunctions.SetupFrameClick(self.watchAdFrame, 0.9, -15, 0.8)

	self.maid:GiveTask(self.buyButton.Activated:Connect(function()
		local product = self.currentProduct
		if not self.alive or not self.promptVisible or not product then
			return
		end

		if product.kind == "GamePass" then
			ProductService.promptGamePassPurchase(self.player, product.id)
		else
			ProductService.promptProductPurchase(self.player, product.id)
		end
	end))

	self.maid:GiveTask(self.exitButton.Activated:Connect(function()
		self:_hidePrompt()
	end))

	self.maid:GiveTask(self.watchAdButton.Activated:Connect(function()
		local product = self.currentProduct
		if
			not self.alive
			or not self.promptVisible
			or self.rewardedVideoInFlight
			or not product
			or product.category ~= "TemporaryBoost"
		then
			return
		end

		local placementName = getRewardedVideoPlacement(product.key)
		if not placementName or not RewardedVideoClient.Request(placementName) then
			self.watchAdFrame.Visible = false
			return
		end

		self.rewardedVideoInFlight = true
		self.watchAdFrame.Active = false
		self.watchAdFrame.Interactable = false
		self.watchAdButton.Active = false
		self.watchAdButton.Interactable = false
	end))

	self.maid:GiveTask(RewardedVideoClient.ConnectResult(function(
		placementName: string,
		completed: boolean,
		_resultName: string
	)
		local product = self.currentProduct
		if not product or getRewardedVideoPlacement(product.key) ~= placementName then
			return
		end

		self.rewardedVideoInFlight = false
		if completed then
			self:_hidePrompt()
		else
			self:_enableInteraction()
			self.watchAdFrame.Visible = RewardedVideoClient.IsAvailable()
		end
	end))

	self.maid:GiveTask(MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(
		player,
		productId,
		wasPurchased
	)
		if player == self.player then
			self:_handlePurchaseFinished(productId, wasPurchased)
		end
	end))

	self.maid:GiveTask(MarketplaceService.PromptProductPurchaseFinished:Connect(function(
		userId,
		productId,
		wasPurchased
	)
		if userId == self.player.UserId then
			self:_handlePurchaseFinished(productId, wasPurchased)
		end
	end))

	self.maid:GiveTask(self.player.CharacterAdded:Connect(function(character)
		self:_bindCharacter(character)
	end))
	if self.player.Character then
		self:_bindCharacter(self.player.Character)
	end
	if STUDIO_ALWAYS_SHOW then
		self:_tryShowPrompt()
	end

	self.maid:GiveTask(self.player:GetAttributeChangedSignal("TutorialCompleted"):Connect(function()
		self:_tryShowPrompt()
	end))

	task.spawn(function()
		while self.alive and self.screenGui.Parent do
			if os.clock() >= self.nextTimeTriggerAt then
				self.timeTriggerReady = true
			end
			self:_tryShowPrompt()
			task.wait(1)
		end
	end)

	DebugModule.debugInfo("Prompt Buy Products UI initialized", MODULE_NAME)
end

function PromptBuyProductsUI.Destroy(self: PromptBuyProductsUIType)
	if not self.alive then
		return
	end

	self.alive = false
	self.promptToken += 1
	self.promptVisible = false
	self.currentProduct = nil
	self.rewardedVideoInFlight = false
	self.watchAdFrame.Visible = false
	self:_stopActiveTween()
	self.characterMaid:DoCleaning()
	self.maid:DoCleaning()
	self.frame.Position = HIDDEN_POSITION
	self.frame.Visible = true
end

return PromptBuyProductsUI
