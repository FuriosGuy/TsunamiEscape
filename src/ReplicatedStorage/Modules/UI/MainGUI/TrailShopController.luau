--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Modules:WaitForChild("Maid"))
local VisualFunctions = require(ReplicatedStorage.Modules.UI:WaitForChild("VisualFunctions"))
local SoundService = require(ReplicatedStorage.Modules:WaitForChild("SoundService"))
local PlayerHandler = require(ReplicatedStorage.Modules.Shared:WaitForChild("PlayerHandler_Client"))
local ProductService = require(ReplicatedStorage.Modules.Shared:WaitForChild("ProductService_Client"))
local SpinWheelConfig = require(ReplicatedStorage.Modules.Config:WaitForChild("SpinWheelConfig"))
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)

local TrailShopController = {}

type TrailConfig = { [string]: any }

type TrailEntry = {
	frame: Frame,
	buyButton: GuiObject?,
	robuxBuyButton: GuiObject?,
	equipButton: GuiObject?,
	robuxOriginalPosition: UDim2?,
	robuxOriginalSize: UDim2?,
}

type Options = {
	player: Player,
	openSpinWheelFromShop: (player: Player) -> (),
	applyWheelStyle: (frame: GuiObject) -> (),
	applyEquipStyle: (frame: GuiObject) -> (),
	canBuyEventProduct: (config: TrailConfig, isOwned: boolean) -> boolean,
	formatTrailMultiplier: (multiplier: number) -> string,
	getOrCreateEquipButton: (entryFrame: Frame) -> GuiObject?,
}

type Controller = {
	Build: (self: Controller) -> (),
	Update: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

local WHEEL_STYLE = ColorConfig.UI.ButtonStyles.Wheel

function TrailShopController.new(options: Options): Controller
	local player = options.player
	local shopMaid = Maid.new()
	local entryFrames: { [string]: TrailEntry } = {}
	local productCache: { [number]: any } = {}
	local destroyed = false
	local controller: Controller = {} :: Controller

	local function spawnShopTask(callback: () -> ())
		local thread = task.spawn(function()
			if destroyed then
				return
			end
			callback()
		end)
		shopMaid:GiveTask(thread)
		return thread
	end

	local function updateTrailEntryPrice(trailName: string, config: TrailConfig)
		local entry = entryFrames[trailName]
		if not entry or not entry.robuxBuyButton then
			return
		end
		if config.RewardSource == "SpinWheel" or config.EventOnly == true then
			entry.robuxBuyButton.Visible = false
			return
		end

		local priceLabel = entry.robuxBuyButton:FindFirstChild("PriceLabel", true)
		local trailTypeImage = entry.frame:FindFirstChild("TrailType", true)
		local productKey = config.ProductKey
		local productId = if typeof(productKey) == "string" then ProductService.DevProducts[productKey] else nil
		if typeof(productId) ~= "number" then
			if priceLabel and priceLabel:IsA("TextLabel") then
				priceLabel.Text = "---"
			end
			return
		end

		spawnShopTask(function()
			local info = productCache[productId]
			if not info then
				local success, result = pcall(function()
					return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
				end)
				if success then
					info = result
					productCache[productId] = result
				end
			end

			if info and not destroyed then
				if priceLabel and priceLabel:IsA("TextLabel") and priceLabel.Parent then
					priceLabel.Text = tostring(info.PriceInRobux or 0)
				end

				if trailTypeImage and trailTypeImage:IsA("ImageLabel") and trailTypeImage.Parent then
					local iconId = tonumber(info.IconImageAssetId)
					if iconId and iconId > 0 then
						trailTypeImage.Image = "rbxassetid://" .. tostring(iconId)
					end
				end
			end
		end)
	end

	local function updateTrailShop()
		for trailName, entry in pairs(entryFrames) do
			local config = PlayerHandler.GetTrailConfig(trailName)
			if not config then
				continue
			end

			local isOwned = PlayerHandler.OwnsTrail(player, trailName)
			local eventId = config.eventId
			local isEventProduct = typeof(eventId) == "string" and eventId ~= ""
			local eventProductAvailable = options.canBuyEventProduct(config, isOwned)
			entry.frame.Visible = not isEventProduct or isOwned or eventProductAvailable
			local isEquipped = player:GetAttribute("Trail_Equipped") == trailName
			local currentWins = player:GetAttribute("WinCount") or 0
			local isWheelOnly = config.RewardSource == "SpinWheel"
			local isEventLocked = config.EventOnly == true and not isOwned

			entry.frame.BackgroundColor3 = if isWheelOnly then WHEEL_STYLE.BackgroundColor else config.BackgroundColor
			local frameGradient = entry.frame:FindFirstChildOfClass("UIGradient")
			if not frameGradient then
				frameGradient = Instance.new("UIGradient")
				frameGradient.Parent = entry.frame
			end
			frameGradient.Rotation = 90
			frameGradient.Color = if isWheelOnly
				then WHEEL_STYLE.Gradient
				else config.Gradient or ColorSequence.new(ColorConfig.Colors.White.Color, config.GradientBottomColor)
			VisualFunctions.RefreshFrameInteractionColors(entry.frame)

			local trailImage = entry.frame:FindFirstChild("Image", true)
			if
				trailImage
				and (trailImage:IsA("ImageLabel") or trailImage:IsA("ImageButton"))
				and typeof(config.ImageAssetId) == "string"
			then
				trailImage.Image = config.ImageAssetId
			end

			local trailNameLabel = entry.frame:FindFirstChild("TrailName", true)
			if trailNameLabel and trailNameLabel:IsA("TextLabel") then
				trailNameLabel.Text = string.upper(config.DisplayName)
			end

			local speedAmountLabel = entry.frame:FindFirstChild("SpeedAmount", true)
			if speedAmountLabel and speedAmountLabel:IsA("TextLabel") then
				speedAmountLabel.Text = string.format("%sx Speed Boost", options.formatTrailMultiplier(config.XPMultiplier))
			end

			local trailTypeLabel = entry.frame:FindFirstChild("TrailType", true)
			if trailTypeLabel and trailTypeLabel:IsA("TextLabel") then
				trailTypeLabel.Text = if isEventLocked
					then "EVENT"
					else if isWheelOnly and not isOwned
						then "SPIN"
						else if config.CanBuyWithWins then "WINS / ROBUX" else "ROBUX ONLY"
			elseif
				trailTypeLabel
				and (trailTypeLabel:IsA("ImageLabel") or trailTypeLabel:IsA("ImageButton"))
				and (isWheelOnly or config.EventOnly == true)
			then
				if isWheelOnly then
					local wheelReward = SpinWheelConfig.GetReward("FlameTrail")
					if wheelReward then
						trailTypeLabel.Image = wheelReward.imageAssetId
					end
				elseif config.EventOnly == true and typeof(config.ImageAssetId) == "string" then
					trailTypeLabel.Image = config.ImageAssetId
				end
			end

			local buyTextButton = entry.buyButton and entry.buyButton:FindFirstChild("TextButton", true)
			if buyTextButton and buyTextButton:IsA("TextButton") then
				buyTextButton.Text = string
					.format("%d", math.round(config.WinsRequired))
					:reverse()
					:gsub("(%d%d%d)", "%1,")
					:reverse()
					:gsub("^,", "")
			end

			local equipTextButton = entry.equipButton and entry.equipButton:FindFirstChild("TextButton", true)
			if equipTextButton and equipTextButton:IsA("TextButton") then
				equipTextButton.Text = if isEventLocked
					then "EVENT"
					else if isWheelOnly and not isOwned
						then "SPIN"
						else if isEquipped then "UNEQUIP" else "EQUIP"
			end

			if entry.buyButton then
				entry.buyButton.Visible = not isWheelOnly and not isOwned and config.CanBuyWithWins
				VisualFunctions.SetFrameInteractableState(
					entry.buyButton,
					not isWheelOnly and currentWins >= config.WinsRequired
				)
			end

			if entry.robuxBuyButton then
				entry.robuxBuyButton.Visible = not isWheelOnly
					and config.EventOnly ~= true
					and not isOwned
					and (not isEventProduct or eventProductAvailable)
				if not config.CanBuyWithWins then
					if entry.buyButton then
						entry.robuxBuyButton.Position = entry.buyButton.Position
						entry.robuxBuyButton.Size = entry.buyButton.Size
					end
				else
					if entry.robuxOriginalPosition then
						entry.robuxBuyButton.Position = entry.robuxOriginalPosition
					end
					if entry.robuxOriginalSize then
						entry.robuxBuyButton.Size = entry.robuxOriginalSize
					end
				end
			end

			if entry.equipButton then
				entry.equipButton.Visible = isWheelOnly
					or config.EventOnly == true
					or isOwned
					or (eventProductAvailable and not isEventProduct)
				VisualFunctions.SetFrameInteractableState(
					entry.equipButton,
					if isEventLocked then false elseif isWheelOnly and not isOwned then true else isOwned
				)
				if isEventLocked then
					options.applyEquipStyle(entry.equipButton)
					entry.equipButton.BackgroundColor3 = config.BackgroundColor
					local eventGradient = entry.equipButton:FindFirstChildOfClass("UIGradient")
					if eventGradient then
						eventGradient.Rotation = 90
						eventGradient.Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, ColorConfig.Colors.White.Color),
							ColorSequenceKeypoint.new(1, config.GradientBottomColor),
						})
					end
					VisualFunctions.RefreshFrameInteractionColors(entry.equipButton)
				elseif isWheelOnly and not isOwned then
					options.applyWheelStyle(entry.equipButton)
				else
					options.applyEquipStyle(entry.equipButton)
				end
			end

			updateTrailEntryPrice(trailName, config)
		end
	end

	function controller:Build()
		shopMaid:DoCleaning()
		local trailFrame = VisualFunctions.ActiveFrameGroup.TrailFrame
		local scrollBackground = trailFrame and trailFrame:FindFirstChild("ScrollBackground")
		local scrollingFrame = scrollBackground and scrollBackground:FindFirstChild("ScrollingFrame")
		if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") then
			return
		end

		local template = scrollingFrame:FindFirstChild("SpeedTrailTemplate")
		if not template or not template:IsA("Frame") then
			return
		end

		for _, child in ipairs(scrollingFrame:GetChildren()) do
			if child ~= template and child:IsA("Frame") then
				child:Destroy()
			end
		end
		table.clear(entryFrames)
		template.Visible = false

		for index, trailName in ipairs(PlayerHandler.TRAIL_ORDER) do
			local config = PlayerHandler.GetTrailConfig(trailName)
			if not config then
				continue
			end

			local clone = template:Clone()
			clone.Name = trailName .. "Template"
			clone.LayoutOrder = index
			clone.Visible = true
			clone.Parent = scrollingFrame

			local buyButton = clone:FindFirstChild("BuyButton")
			local robuxBuyButton = clone:FindFirstChild("RobuxBuyButton")
			local equipButton = options.getOrCreateEquipButton(clone)

			if buyButton and buyButton:IsA("GuiObject") then
				local textButton = buyButton:FindFirstChild("TextButton", true)
				if textButton and textButton:IsA("TextButton") then
					shopMaid:GiveTask(textButton.Activated:Connect(function()
						SoundService.PlayGuiSound("Click")
						if config.EventOnly == true and not PlayerHandler.OwnsTrail(player, trailName) then
							return
						end
						if config.RewardSource == "SpinWheel" and not PlayerHandler.OwnsTrail(player, trailName) then
							options.openSpinWheelFromShop(player)
							return
						end
						local trailRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("TrailAction")
						if trailRemote and trailRemote:IsA("RemoteEvent") then
							trailRemote:FireServer("BuyWithWins", trailName)
						end
					end))
				end
			end

			if robuxBuyButton and robuxBuyButton:IsA("GuiObject") then
				local textButton = robuxBuyButton:FindFirstChild("TextButton", true)
				if textButton and textButton:IsA("TextButton") then
					shopMaid:GiveTask(textButton.Activated:Connect(function()
						SoundService.PlayGuiSound("Click")
						if typeof(config.eventId) == "string" and not options.canBuyEventProduct(config, false) then
							return
						end
						local productKey = config.ProductKey
						local productId = if typeof(productKey) == "string" then ProductService.DevProducts[productKey] else nil
						if typeof(productId) == "number" and productId ~= 0 then
							ProductService.promptProductPurchase(player, productId)
						end
					end))
				end
			end

			if equipButton then
				local textButton = equipButton:FindFirstChild("TextButton", true)
				if textButton and textButton:IsA("TextButton") then
					shopMaid:GiveTask(textButton.Activated:Connect(function()
						SoundService.PlayGuiSound("Click")
						if config.EventOnly == true and not PlayerHandler.OwnsTrail(player, trailName) then
							return
						end
						if config.RewardSource == "SpinWheel" and not PlayerHandler.OwnsTrail(player, trailName) then
							options.openSpinWheelFromShop(player)
							return
						end
						local trailRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("TrailAction")
						if trailRemote and trailRemote:IsA("RemoteEvent") then
							trailRemote:FireServer("Equip", trailName)
						end
					end))
				end
			end

			entryFrames[trailName] = {
				frame = clone,
				buyButton = if buyButton and buyButton:IsA("GuiObject") then buyButton else nil,
				robuxBuyButton = if robuxBuyButton and robuxBuyButton:IsA("GuiObject") then robuxBuyButton else nil,
				equipButton = equipButton,
				robuxOriginalPosition = if robuxBuyButton and robuxBuyButton:IsA("GuiObject")
					then robuxBuyButton.Position
					else nil,
				robuxOriginalSize = if robuxBuyButton and robuxBuyButton:IsA("GuiObject")
					then robuxBuyButton.Size
					else nil,
			}
		end

		updateTrailShop()
	end

	function controller:Update()
		updateTrailShop()
	end

	function controller:Destroy()
		destroyed = true
		shopMaid:DoCleaning()
		table.clear(entryFrames)
		table.clear(productCache)
	end

	return controller
end

return TrailShopController
