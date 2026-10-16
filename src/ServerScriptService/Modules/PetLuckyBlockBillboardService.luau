--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local NumberFormatting = require(ReplicatedStorage.Modules.Shared.NumberFormatting)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)
local ProductService = require(ServerScriptService.Modules.Shared.ProductService_Server)

type LuckyBlockGroup = "Tier1" | "Tier2" | "Tier3" | "Premium" | PetConfig.EventId

local PetLuckyBlockBillboardService = {}
local MODULE_NAME = "PetLuckyBlockBillboardService"
local TEMPLATE_NAME = "BillboardBlock"
local BILLBOARD_NAME = "LuckyBlockBillboard"
local LOCK_BILLBOARD_NAME = "LockBillboard"
local EVENT_AVAILABILITY_ATTRIBUTE = "LuckyBlockEventAvailable"
local PRODUCT_INFO_CACHE: { [number]: number } = {}
local WHITE = ColorConfig.Colors.White.Color

local function getTextLabel(billboard: BillboardGui, name: string): TextLabel?
	local instance = billboard:FindFirstChild(name)
	if instance and instance:IsA("TextLabel") then
		return instance
	end

	DebugModule.debugWarn("Billboard template is missing TextLabel " .. name, MODULE_NAME)
	return nil
end

local function setTextStyle(label: TextLabel, gradientSequence: ColorSequence): ()
	local gradientInstance = label:FindFirstChildOfClass("UIGradient")
	if not gradientInstance then
		local newGradient = Instance.new("UIGradient")
		newGradient.Name = "UIGradient"
		newGradient.Parent = label
		gradientInstance = newGradient
	end

	label.TextColor3 = WHITE
	gradientInstance.Color = gradientSequence
	gradientInstance.Rotation = 90
end

local function getPriceText(group: LuckyBlockGroup): string?
	if group == "Tier1" or group == "Tier2" or group == "Tier3" then
		local winCost = PetConfig.LuckyBlocks[group].winCostPerRoll
		if typeof(winCost) == "number" and winCost > 0 then
			return NumberFormatting.FormatNumber(winCost) .. " Wins"
		end
		return nil
	end

	local robuxPrice: number?
	if group == "Premium" then
		robuxPrice = PetConfig.LuckyBlocks.Premium.robuxPricePerRoll
	else
		robuxPrice = PetConfig.LuckyBlocks.Event.eventRobuxPricePerRoll
			and PetConfig.LuckyBlocks.Event.eventRobuxPricePerRoll[group]
	end
	if typeof(robuxPrice) ~= "number" or robuxPrice <= 0 then
		return nil
	end

	return utf8.char(0xE002) .. " " .. NumberFormatting.FormatNumber(robuxPrice)
end

local function getRollOneProductId(group: LuckyBlockGroup): number?
	local prefix = if group == "Premium" then "PetPremium" else "Pet" .. group
	local productId = ProductService.DevProducts[prefix .. "LuckyBlockRoll1"]
	return if typeof(productId) == "number" and productId > 0 then productId else nil
end

local function updateRobuxPriceFromProduct(billboard: BillboardGui, label: TextLabel, group: LuckyBlockGroup): ()
	local productId = getRollOneProductId(group)
	if not productId then
		DebugModule.debugWarn("Missing 1x developer product ID | group=" .. group, MODULE_NAME)
		return
	end

	local cachedPrice = PRODUCT_INFO_CACHE[productId]
	if cachedPrice then
		label.Text = utf8.char(0xE002) .. " " .. NumberFormatting.FormatNumber(cachedPrice)
		return
	end

	task.spawn(function()
		local success, productInfo = pcall(function()
			return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
		end)
		if not billboard.Parent or not label.Parent then
			return
		end

		local price = if success and typeof(productInfo) == "table" then productInfo.PriceInRobux else nil
		if typeof(price) ~= "number" or price < 0 then
			DebugModule.debugWarn(
				"Developer product price lookup failed | group=" .. group .. " | productId=" .. tostring(productId),
				MODULE_NAME
			)
			return
		end

		local roundedPrice = math.round(price)
		PRODUCT_INFO_CACHE[productId] = roundedPrice
		label.Text = utf8.char(0xE002) .. " " .. NumberFormatting.FormatNumber(roundedPrice)
	end)
end

local function updateBlockName(billboard: BillboardGui, group: LuckyBlockGroup): boolean
	local label = getTextLabel(billboard, "BlockName")
	local style = ColorConfig.LuckyBlocks.TopFrameStyles[group]
	if not label or not style then
		return false
	end

	label.Text = style.Label
	setTextStyle(label, style.Gradient)
	return true
end

local function updatePrice(billboard: BillboardGui, group: LuckyBlockGroup): boolean
	local label = getTextLabel(billboard, "PriceLabel")
	local priceText = getPriceText(group)
	if not label or not priceText then
		DebugModule.debugWarn("No base price configured for Lucky Block " .. group, MODULE_NAME)
		return false
	end

	label.Text = priceText
	setTextStyle(label, ColorSequence.new(ColorConfig.Colors.White.Color))
	if group ~= "Tier1" and group ~= "Tier2" and group ~= "Tier3" then
		updateRobuxPriceFromProduct(billboard, label, group)
	end
	return true
end

local function updateDescription(billboard: BillboardGui, group: LuckyBlockGroup): boolean
	local label = getTextLabel(billboard, "DescLabel")
	if not label then
		return false
	end

	local themeName: string?
	if group == "Premium" then
		label.Text = "OP!"
		themeName = "Purple"
	elseif group == "BloodMoon" or group == "NeonRush" or group == "FrostbiteRally" or group == "Halloween" then
		label.Text = "LIMITED!"
		themeName = "Gold"
	else
		label.Visible = false
		return true
	end

	local theme = ColorConfig.UI.NotificationThemes[themeName]
	if not theme then
		DebugModule.debugWarn("Missing description theme " .. themeName, MODULE_NAME)
		return false
	end

	label.Visible = true
	setTextStyle(label, ColorSequence.new(theme.textColor, theme.gradientBottomColor))
	return true
end

local function configureBillboard(billboard: BillboardGui, group: LuckyBlockGroup): boolean
	local valid = updateBlockName(billboard, group)
	valid = updatePrice(billboard, group) and valid
	valid = updateDescription(billboard, group) and valid
	return valid
end

function PetLuckyBlockBillboardService.SetEventAvailability(model: Model, isAvailable: boolean): ()
	if model:GetAttribute(EVENT_AVAILABILITY_ATTRIBUTE) ~= isAvailable then
		model:SetAttribute(EVENT_AVAILABILITY_ATTRIBUTE, isAvailable)
	end

	local mainPart = model:FindFirstChild("MainPart")
	if not mainPart or not mainPart:IsA("BasePart") then
		DebugModule.debugWarn("Cannot update lock billboard; MainPart missing | model=" .. model:GetFullName(), MODULE_NAME)
		return
	end

	local lockBillboard = mainPart:FindFirstChild(LOCK_BILLBOARD_NAME)
	if lockBillboard and not lockBillboard:IsA("BillboardGui") then
		DebugModule.debugWarn("LockBillboard name is occupied by wrong class | model=" .. model:GetFullName(), MODULE_NAME)
		return
	end

	if not lockBillboard and not isAvailable then
		local userInterface = ReplicatedStorage:FindFirstChild("UserInterface")
		local template = userInterface and userInterface:FindFirstChild(LOCK_BILLBOARD_NAME)
		if not template or not template:IsA("BillboardGui") then
			DebugModule.debugWarn("ReplicatedStorage.UserInterface.LockBillboard is missing or has wrong class", MODULE_NAME)
			return
		end

		local clone = template:Clone()
		clone.Name = LOCK_BILLBOARD_NAME
		clone.Adornee = mainPart
		clone.Enabled = true
		clone.Parent = mainPart
		return
	end

	if lockBillboard and lockBillboard:IsA("BillboardGui") then
		lockBillboard.Adornee = mainPart
		lockBillboard.Enabled = not isAvailable
	end
end

function PetLuckyBlockBillboardService.Attach(
	model: Model,
	mainPart: BasePart,
	group: LuckyBlockGroup
): (() -> ())?
	if model.Parent == nil or mainPart.Parent ~= model then
		return nil
	end

	local existing = mainPart:FindFirstChild(BILLBOARD_NAME)
	if existing then
		if not existing:IsA("BillboardGui") then
			DebugModule.debugWarn("LuckyBlockBillboard name is occupied by a non-BillboardGui | model=" .. model:GetFullName(), MODULE_NAME)
			return nil
		end
		existing.Adornee = mainPart
		existing.Enabled = true
		configureBillboard(existing, group)
		return nil
	end

	local userInterface = ReplicatedStorage:FindFirstChild("UserInterface")
	local template = userInterface and userInterface:FindFirstChild(TEMPLATE_NAME)
	if not template or not template:IsA("BillboardGui") then
		DebugModule.debugWarn("ReplicatedStorage.UserInterface.BillboardBlock is missing or has wrong class", MODULE_NAME)
		return nil
	end

	local billboard = template:Clone()
	billboard.Name = BILLBOARD_NAME
	billboard.Adornee = mainPart
	billboard.Enabled = true
	if not configureBillboard(billboard, group) then
		billboard:Destroy()
		return nil
	end
	billboard.Parent = mainPart

	return function(): ()
		if billboard.Parent then
			billboard:Destroy()
		end
	end
end

return PetLuckyBlockBillboardService
