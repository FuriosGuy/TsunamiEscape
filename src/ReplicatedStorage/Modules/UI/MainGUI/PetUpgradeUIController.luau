--!strict

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)
local NumberFormatting = require(ReplicatedStorage.Modules.Shared.NumberFormatting)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local ProductService = require(ReplicatedStorage.Modules.Shared:WaitForChild("ProductService_Client"))
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

type PetUpgradeUIControllerObject = {
	player: Player,
	connections: { RBXScriptConnection },
	pendingProductIds: { [number]: boolean },
	pendingGamePassIds: { [number]: boolean },
	priceThreads: { thread },
	priceRequestKeys: { [TextLabel]: string },
	fastOpenTweens: { [GuiButton]: Tween },
	creatorPurchaseDisconnect: (() -> ())?,
	alive: boolean,
	Destroy: (self: PetUpgradeUIControllerObject) -> (),
}

local PetUpgradeUIController = {}
PetUpgradeUIController.__index = PetUpgradeUIController

local MODULE_NAME = "PetUpgradeUIController"
local EQUIP_CAPACITY_ATTRIBUTE = "Pet_EquipSlotCapacity"
local BACKPACK_CAPACITY_ATTRIBUTE = "Pet_BackpackCapacity"
local LUCK_MULTIPLIER_ATTRIBUTE = "Pet_LuckMultiplier"
local FAST_OPEN_ENABLED_ATTRIBUTE = "Pet_LuckyBlockFastOpenEnabled"
local FASTER_OPEN_GAMEPASS_KEY = "PetLuckyBlockFasterOpen"
local LUCK_TIERS = PetConfig.Upgrades.luckMultiplier.tiers
local MAX_LUCK_MULTIPLIER = LUCK_TIERS[#LUCK_TIERS].multiplier
local ROBUX_ICON = utf8.char(0xE002)

local function findGuiObject(parent: Instance?, name: string): GuiObject?
	local child = if parent then parent:FindFirstChild(name) else nil
	return if child and child:IsA("GuiObject") then child else nil
end

local function findTextLabel(parent: Instance?, name: string): TextLabel?
	local child = if parent then parent:FindFirstChild(name, true) else nil
	return if child and child:IsA("TextLabel") then child else nil
end

local function findButton(parent: Instance?): GuiButton?
	if not parent then
		return nil
	end
	if parent:IsA("GuiButton") then
		return parent
	end
	return parent:FindFirstChildWhichIsA("GuiButton", true)
end

local function getNextLuckProductKey(multiplier: number): string?
	for _, tier in ipairs(LUCK_TIERS) do
		if tier.multiplier > multiplier then
			return tier.productKey
		end
	end
	return nil
end

local function readCapacity(player: Player, attributeName: string, defaultValue: number): number
	local value = player:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return defaultValue
	end
	return math.floor(value)
end

local function readLuckMultiplier(player: Player): number
	local value = player:GetAttribute(LUCK_MULTIPLIER_ATTRIBUTE)
	local defaultValue = PetConfig.Upgrades.luckMultiplier.startingMultiplier
	if typeof(value) ~= "number" or value ~= value or value < defaultValue then
		return defaultValue
	end
	return math.min(value, MAX_LUCK_MULTIPLIER)
end

function PetUpgradeUIController.new(screenGui: ScreenGui): PetUpgradeUIControllerObject
	local player = Players.LocalPlayer
	local self = setmetatable({
		player = player,
		connections = {},
		pendingProductIds = {},
		pendingGamePassIds = {},
		priceThreads = {},
		priceRequestKeys = {},
		fastOpenTweens = {},
		creatorPurchaseDisconnect = nil,
		alive = true,
	}, PetUpgradeUIController) :: PetUpgradeUIControllerObject

	local petFrame = findGuiObject(screenGui, "PetFrame")
	local petSlots = findGuiObject(petFrame, "PetSlots")
	local backpackSlots = findGuiObject(petFrame, "BackpackSlots")
	local petLuckFrame = findGuiObject(petFrame, "LuckMultiplier")
	local petLuckAddButton = findGuiObject(petLuckFrame, "AddButton")
	local bottomRightFrame = findGuiObject(screenGui, "BottomRightGridFrame")
	local hudLuckFrame = findGuiObject(bottomRightFrame, "LuckMultiplierFrame")
	local hudPromptButton = findGuiObject(hudLuckFrame, "PromptButton")
	local hudPlusLabel = findTextLabel(hudLuckFrame, "TextLabel")
	local petLuckAmount = findTextLabel(petLuckFrame, "Amount")
	local hudLuckMultiplier = findTextLabel(hudLuckFrame, "Multiplier")
	local openLuckyBlockFrame = findGuiObject(screenGui, "OpenLuckyBlockFrame")
	local openLuckyBlockMainFrame = findGuiObject(openLuckyBlockFrame, "MainFrame")
	local luckyBlockLuckButtonFrame = findGuiObject(openLuckyBlockMainFrame, "LuckButtonFrame")
	local luckyBlockLuckPromptButton = findButton(luckyBlockLuckButtonFrame)
	local fasterOpenButtonFrame = findGuiObject(openLuckyBlockMainFrame, "InstantHatchButtonFrame")
	local fastOpenLabel = findGuiObject(openLuckyBlockMainFrame, "FastOpen")
	local shopFrame = findGuiObject(screenGui, "ShopFrame")
	local shopScrollBackground = findGuiObject(shopFrame, "ScrollBackground")
	local shopScrollingFrame = findGuiObject(shopScrollBackground, "ScrollingFrame")
	local shopLuckyBlocks = findGuiObject(shopScrollingFrame, "LuckyBlocks")
	local shopLuckyBlocksMainFrame = findGuiObject(shopLuckyBlocks, "MainFrame")
	local shopFastOpenLabel = findGuiObject(shopLuckyBlocksMainFrame, "FastOpen")
	type FastOpenToggle = { label: GuiObject, container: CanvasGroup, button: GuiButton }
	local fastOpenToggles: { FastOpenToggle } = {}
	local fastOpenLabels: { GuiObject } = {}
	if fastOpenLabel then
		table.insert(fastOpenLabels, fastOpenLabel)
	end
	if shopFastOpenLabel then
		table.insert(fastOpenLabels, shopFastOpenLabel)
	end
	for _, label in ipairs(fastOpenLabels) do
		if label then
			label.Visible = false
			local canvasGroup = label:FindFirstChildWhichIsA("CanvasGroup")
			local button = findButton(canvasGroup)
			if canvasGroup and button then
				table.insert(fastOpenToggles, {
					label = label,
					container = canvasGroup,
					button = button,
				})
			end
		end
	end
	local fastOpenRemoteInstance = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PetLuckyBlockFastOpenPreference", 10)
	local fastOpenRemote = if fastOpenRemoteInstance and fastOpenRemoteInstance:IsA("RemoteEvent")
		then fastOpenRemoteInstance
		else nil
	local gamePassId = ProductService.Gamepasses[FASTER_OPEN_GAMEPASS_KEY]
	local fasterOpenOwned = false
	local fasterOpenOwnershipResolved = false
	local fastOpenEnabled = player:GetAttribute(FAST_OPEN_ENABLED_ATTRIBUTE) ~= false
	local fastOpenPending = false

	local function setFasterOpenDisabledState(): ()
		if fasterOpenButtonFrame and fasterOpenButtonFrame:IsA("GuiObject") then
			if fasterOpenOwnershipResolved then
				VisualFunctions.SetFrameDisabledState(fasterOpenButtonFrame, fasterOpenOwned, 0.5)
			else
				VisualFunctions.SetFrameInteractableState(fasterOpenButtonFrame, false)
			end
		end
	end

	local function updateFastOpenVisibility(): ()
		local isVisible = fasterOpenOwnershipResolved
			and fasterOpenOwned
			and player:GetAttribute("Data_Loaded") == true
		for _, toggle in ipairs(fastOpenToggles) do
			toggle.label.Visible = isVisible
		end
	end

	local function updateFastOpenVisual(): ()
		for _, toggle in ipairs(fastOpenToggles) do
			local gradient = toggle.button:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Color = if fastOpenEnabled then ColorConfig.Colors.Green.Gradient else ColorConfig.Colors.Gray.Gradient
			end

			local previousTween = self.fastOpenTweens[toggle.button]
			if previousTween then
				previousTween:Cancel()
			end
			local tween = TweenService:Create(
				toggle.button,
				TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ BackgroundTransparency = if fastOpenEnabled then 0 else 1 }
			)
			self.fastOpenTweens[toggle.button] = tween
			tween:Play()
		end
	end

	local function requestPrice(priceLabel: TextLabel?, itemId: number?, infoType: Enum.InfoType): ()
		if not priceLabel then
			return
		end
		if typeof(itemId) ~= "number" or itemId <= 0 then
			priceLabel.Text = "PRICE UNAVAILABLE"
			return
		end

		local requestKey = infoType.Name .. ":" .. tostring(itemId)
		if self.priceRequestKeys[priceLabel] == requestKey then
			return
		end
		self.priceRequestKeys[priceLabel] = requestKey
		priceLabel.Text = "ONLY " .. ROBUX_ICON .. " ...!"

		local requestThread = task.spawn(function()
			local success, productInfo = pcall(function()
				return MarketplaceService:GetProductInfo(itemId, infoType)
			end)
			if not self.alive or not priceLabel.Parent or self.priceRequestKeys[priceLabel] ~= requestKey then
				return
			end

			local price = if success and typeof(productInfo) == "table" then productInfo.PriceInRobux else nil
			if typeof(price) ~= "number" or price < 0 then
				self.priceRequestKeys[priceLabel] = nil
				priceLabel.Text = "PRICE UNAVAILABLE"
				DebugModule.debugWarn("Lucky Block upgrade price lookup failed | itemId=" .. tostring(itemId), MODULE_NAME)
				return
			end

			priceLabel.Text = "ONLY " .. ROBUX_ICON .. " " .. NumberFormatting.FormatNumber(math.round(price)) .. "!"
		end)
		table.insert(self.priceThreads, requestThread)
	end

	local function promptProduct(productKey: string)
		if not self.alive or player:GetAttribute("Data_Loaded") ~= true then
			return
		end
		if string.match(productKey, "^PetLuck")
			and (player:GetAttribute("Pet_RandomItemPolicyLoaded") ~= true
				or player:GetAttribute("Pet_PaidRandomItemsRestricted") == true)
		then
			return
		end

		local productId = ProductService.DevProducts[productKey]
		if typeof(productId) ~= "number" or productId <= 0 or self.pendingProductIds[productId] then
			return
		end

		if ProductService.promptProductPurchase(player, productId) then
			self.pendingProductIds[productId] = true
		end
	end

	local function connectAction(container: Instance?, onActivated: () -> ())
		if not container or not container:IsA("GuiObject") then
			DebugModule.debugWarn("Pet upgrade action frame missing or is not a GuiObject", MODULE_NAME)
			return
		end

		VisualFunctions.SetupFrameHover(container, 1.1, 15, 1.5)
		VisualFunctions.SetupFrameClick(container, 0.95, -15, 0.75)
		local button = findButton(container)
		if button then
			button.Active = true
			button.Interactable = true
			table.insert(self.connections, button.Activated:Connect(onActivated))
			return
		end

		container.Active = true
		container.Interactable = true
		table.insert(self.connections, container.InputBegan:Connect(function(input: InputObject)
			local isMouseClick = input.UserInputType == Enum.UserInputType.MouseButton1
			local isTouch = input.UserInputType == Enum.UserInputType.Touch
			if (isMouseClick or isTouch) and container:GetAttribute("UiDisabled") ~= true then
				VisualFunctions.PlayFrameClick(container)
				onActivated()
			end
		end))
	end

	local function connectPurchaseButton(container: Instance?, productKeyProvider: () -> string?)
		connectAction(container, function()
			local productKey = productKeyProvider()
			if productKey then
				promptProduct(productKey)
			end
		end)
	end

	connectPurchaseButton(findGuiObject(petSlots, "AddButton"), function()
		return "PetEquipSlotPlusThree"
	end)
	connectPurchaseButton(findGuiObject(backpackSlots, "AddButton"), function()
		return "PetBackpackSlotPlusFifteen"
	end)
	connectPurchaseButton(petLuckAddButton, function()
		for _, tier in ipairs(LUCK_TIERS) do
			if tier.multiplier > readLuckMultiplier(player) then
				return tier.productKey
			end
		end
		return nil
	end)
	connectPurchaseButton(hudPromptButton, function()
		return getNextLuckProductKey(readLuckMultiplier(player))
	end)
	connectPurchaseButton(luckyBlockLuckButtonFrame, function()
		return getNextLuckProductKey(readLuckMultiplier(player))
	end)
	connectAction(fasterOpenButtonFrame, function()
		if
			type(gamePassId) == "number"
			and gamePassId > 0
			and fasterOpenOwnershipResolved
			and not fasterOpenOwned
			and not self.pendingGamePassIds[gamePassId]
		then
			self.pendingGamePassIds[gamePassId] = true
			ProductService.promptGamePassPurchase(player, gamePassId)
		end
	end)
	if #fastOpenToggles > 0 then
		for _, toggle in ipairs(fastOpenToggles) do
			connectAction(toggle.container, function()
				if not fasterOpenOwned or not fasterOpenOwnershipResolved or player:GetAttribute("Data_Loaded") ~= true then
					return
				end
				if fastOpenPending or not fastOpenRemote then
					return
				end

				fastOpenPending = true
				fastOpenEnabled = not fastOpenEnabled
				updateFastOpenVisual()
				fastOpenRemote:FireServer(fastOpenEnabled)
			end)
		end
		if fastOpenRemote then
			table.insert(self.connections, fastOpenRemote.OnClientEvent:Connect(function(serverEnabled: any)
				if typeof(serverEnabled) ~= "boolean" then
					return
				end
				fastOpenPending = false
				fastOpenEnabled = serverEnabled
				updateFastOpenVisual()
			end))
		else
			DebugModule.debugWarn("Fast Open preference remote is missing or invalid", MODULE_NAME)
		end
	else
		DebugModule.debugWarn("OpenLuckyBlockFrame.MainFrame.FastOpen toggle hierarchy is missing", MODULE_NAME)
	end

	local fasterOpenPriceLabel = findTextLabel(fasterOpenButtonFrame, "PriceLabel")
	local luckyBlockLuckPriceLabel = findTextLabel(luckyBlockLuckButtonFrame, "PriceLabel")
	if fasterOpenButtonFrame and not fasterOpenPriceLabel then
		DebugModule.debugWarn("OpenLuckyBlockFrame.MainFrame Faster Open PriceLabel is missing", MODULE_NAME)
	end
	if luckyBlockLuckButtonFrame and not luckyBlockLuckPriceLabel then
		DebugModule.debugWarn("OpenLuckyBlockFrame.MainFrame.LuckButtonFrame.PriceLabel is missing", MODULE_NAME)
	end
	if fasterOpenPriceLabel and typeof(gamePassId) == "number" then
		requestPrice(fasterOpenPriceLabel, gamePassId, Enum.InfoType.GamePass)
	end

	local function refresh()
		if not self.alive then
			return
		end

		local equipCapacity = readCapacity(player, EQUIP_CAPACITY_ATTRIBUTE, PetConfig.Equip.startingSlots)
		local backpackCapacity = readCapacity(player, BACKPACK_CAPACITY_ATTRIBUTE, PetConfig.Storage.startingCapacity)
		local luckMultiplier = readLuckMultiplier(player)
		local equippedCount = 0
		local petCount = 0
		local inventoryData = player:GetAttribute("Pet_Inventory")
		if typeof(inventoryData) == "string" then
			local ok, inventory = pcall(HttpService.JSONDecode, HttpService, inventoryData)
			if ok and typeof(inventory) == "table" then
				for _, pet in ipairs(inventory) do
					if typeof(pet) == "table" then
						petCount += 1
						if pet.equipped == true then
							equippedCount += 1
						end
					end
				end
			end
		end
		local equipAmount = findTextLabel(petSlots, "Amount")
		local backpackAmount = findTextLabel(backpackSlots, "Amount")
		if equipAmount then
			equipAmount.Text = string.format("%d/%d", equippedCount, equipCapacity)
		end
		if backpackAmount then
			backpackAmount.Text = string.format("%d/%d", petCount, backpackCapacity)
		end

		local multiplierText = string.format("%.2fx", luckMultiplier)
		if petLuckAmount then
			petLuckAmount.Text = multiplierText
		end
		if hudLuckMultiplier then
			hudLuckMultiplier.Text = multiplierText
		end

		local nextTierAvailable = luckMultiplier < MAX_LUCK_MULTIPLIER
		local nextLuckMultiplier = MAX_LUCK_MULTIPLIER
		for _, tier in ipairs(LUCK_TIERS) do
			if tier.multiplier > luckMultiplier then
				nextLuckMultiplier = tier.multiplier
				break
			end
		end
		if luckyBlockLuckPromptButton and luckyBlockLuckPromptButton:IsA("TextButton") then
			luckyBlockLuckPromptButton.Text = if nextTierAvailable
				then string.format("%dx Luck", nextLuckMultiplier)
				else "MAXED"
		end
		local luckPurchasesAllowed = player:GetAttribute("Pet_RandomItemPolicyLoaded") == true
			and player:GetAttribute("Pet_PaidRandomItemsRestricted") ~= true
		if petLuckAddButton then
			petLuckAddButton.Visible = nextTierAvailable and luckPurchasesAllowed
		end
		if hudPromptButton then
			hudPromptButton.Visible = nextTierAvailable and luckPurchasesAllowed
		end
		if hudPlusLabel then
			hudPlusLabel.Visible = nextTierAvailable and luckPurchasesAllowed
		end

		if luckyBlockLuckButtonFrame and luckyBlockLuckButtonFrame:IsA("GuiObject") then
			luckyBlockLuckButtonFrame.Visible = true
			VisualFunctions.SetFrameDisabledState(
				luckyBlockLuckButtonFrame,
				not nextTierAvailable or not luckPurchasesAllowed,
				0.5
			)
		end
		if luckyBlockLuckPriceLabel then
			local nextProductKey = getNextLuckProductKey(luckMultiplier)
			local productId = if nextProductKey then ProductService.DevProducts[nextProductKey] else nil
			if nextProductKey and typeof(productId) == "number" and productId > 0 then
				requestPrice(luckyBlockLuckPriceLabel, productId, Enum.InfoType.Product)
			else
				self.priceRequestKeys[luckyBlockLuckPriceLabel] = nil
				luckyBlockLuckPriceLabel.Text = "MAXED"
			end
		end
	end

	table.insert(self.connections, player:GetAttributeChangedSignal(EQUIP_CAPACITY_ATTRIBUTE):Connect(refresh))
	table.insert(self.connections, player:GetAttributeChangedSignal(BACKPACK_CAPACITY_ATTRIBUTE):Connect(refresh))
	table.insert(self.connections, player:GetAttributeChangedSignal(LUCK_MULTIPLIER_ATTRIBUTE):Connect(refresh))
	table.insert(self.connections, player:GetAttributeChangedSignal("Pet_Inventory"):Connect(refresh))
	table.insert(self.connections, player:GetAttributeChangedSignal("Data_Loaded"):Connect(refresh))
	table.insert(self.connections, player:GetAttributeChangedSignal("Data_Loaded"):Connect(updateFastOpenVisibility))
	table.insert(self.connections, player:GetAttributeChangedSignal(FAST_OPEN_ENABLED_ATTRIBUTE):Connect(function()
		fastOpenEnabled = player:GetAttribute(FAST_OPEN_ENABLED_ATTRIBUTE) ~= false
		fastOpenPending = false
		updateFastOpenVisual()
	end))
	table.insert(self.connections, player:GetAttributeChangedSignal("Pet_RandomItemPolicyLoaded"):Connect(refresh))
	table.insert(self.connections, player:GetAttributeChangedSignal("Pet_PaidRandomItemsRestricted"):Connect(refresh))
	table.insert(self.connections, MarketplaceService.PromptProductPurchaseFinished:Connect(function(finishedPlayer, productId)
		if finishedPlayer == player then
			self.pendingProductIds[productId] = nil
		end
	end))
	table.insert(self.connections, MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(
		finishedPlayer: Player,
		finishedGamePassId: number,
		wasPurchased: boolean
	)
		if finishedPlayer ~= player then
			return
		end
		self.pendingGamePassIds[finishedGamePassId] = nil
		if finishedGamePassId == gamePassId and wasPurchased then
			ProductService.SetGamePassOwnershipCache(player, finishedGamePassId, true)
			fasterOpenOwned = true
			fasterOpenOwnershipResolved = true
			setFasterOpenDisabledState()
			updateFastOpenVisibility()
		end
	end))
	self.creatorPurchaseDisconnect = ProductService.ConnectCreatorPurchaseFinished(function(kind, productId)
		if kind == "Product" then
			self.pendingProductIds[productId] = nil
		end
	end)

	refresh()
	setFasterOpenDisabledState()
	updateFastOpenVisibility()
	updateFastOpenVisual()
	if typeof(gamePassId) == "number" and gamePassId > 0 then
		local ownershipThread = task.spawn(function()
			local success, ownsPass = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
			end)
			if not self.alive then
				return
			end

			fasterOpenOwnershipResolved = true
			if success and typeof(ownsPass) == "boolean" then
				fasterOpenOwned = ownsPass
				ProductService.SetGamePassOwnershipCache(player, gamePassId, ownsPass)
			else
				DebugModule.debugWarn("Faster Open game pass ownership check failed", MODULE_NAME)
			end
			setFasterOpenDisabledState()
			updateFastOpenVisibility()
		end)
		table.insert(self.priceThreads, ownershipThread)
	elseif fasterOpenButtonFrame then
		DebugModule.debugWarn("Faster Open game pass ID is missing", MODULE_NAME)
	end
	return self
end

function PetUpgradeUIController:Destroy()
	if not self.alive then
		return
	end
	self.alive = false
	for button, tween in pairs(self.fastOpenTweens) do
		tween:Cancel()
		self.fastOpenTweens[button] = nil
	end
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	if self.creatorPurchaseDisconnect then
		self.creatorPurchaseDisconnect()
		self.creatorPurchaseDisconnect = nil
	end
	for _, thread in ipairs(self.priceThreads) do
		if coroutine.status(thread) ~= "dead" then
			pcall(task.cancel, thread)
		end
	end
	table.clear(self.priceThreads)
	table.clear(self.priceRequestKeys)
	table.clear(self.pendingProductIds)
	table.clear(self.pendingGamePassIds)
end

return PetUpgradeUIController
