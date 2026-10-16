--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maid = require(ReplicatedStorage.Modules:WaitForChild("Maid"))
local VisualFunctions = require(ReplicatedStorage.Modules.UI:WaitForChild("VisualFunctions"))
local SoundService = require(ReplicatedStorage.Modules:WaitForChild("SoundService"))
local PlayerHandler = require(ReplicatedStorage.Modules.Shared:WaitForChild("PlayerHandler_Client"))
local ProductService = require(ReplicatedStorage.Modules.Shared:WaitForChild("ProductService_Client"))
local KartCatalog = require(ReplicatedStorage.Modules:WaitForChild("KartCatalog"))
local SpinWheelConfig = require(ReplicatedStorage.Modules.Config:WaitForChild("SpinWheelConfig"))
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)

local KartShopController = {}

local WHEEL_STYLE = ColorConfig.UI.ButtonStyles.Wheel

type KartConfig = {
	kartName: string,
	displayName: string,
	sourceFolder: string?,
	sourceSubfolder: string?,
	eventId: string?,
	bloodmoonKart: boolean?,
	gamePassId: number?,
	productKey: string?,
	wheelOnly: boolean?,
	wheelImage: string?,
	showOnlyWhenOwned: boolean?,
	imageAssetId: string?,
	style: ColorConfig.KartFrameStyle,
}

type KartEntry = {
	frame: Frame,
	equipButton: GuiObject?,
}

type MarketplaceInfoGetter = (itemId: number, infoType: Enum.InfoType) -> any

type Options = {
	player: Player,
	kartActionRemote: RemoteEvent,
	getMarketplaceInfoCached: MarketplaceInfoGetter,
	isLiveEventActive: (eventId: string?) -> boolean,
	openSpinWheelFromShop: (player: Player) -> (),
	applyWheelStyle: (frame: GuiObject) -> (),
	applyEquipStyle: (frame: GuiObject) -> (),
}

type Controller = {
	Build: (self: Controller) -> (),
	Update: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

local KART_FRAME_CONFIGS: { KartConfig } = {
	{
		kartName = "AdvancedTank",
		displayName = "Advanced Tank",
		gamePassId = ProductService.Gamepasses["AdvancedTank"],
		style = ColorConfig.Karts.FrameStyles.AdvancedTank,
	},
	{
		kartName = "ShoppingKart",
		displayName = "Shopping Kart",
		gamePassId = ProductService.Gamepasses["ShoppingKart"],
		style = ColorConfig.Karts.FrameStyles.ShoppingKart,
	},
	{
		kartName = "FormulaCar",
		displayName = "Formula Car",
		gamePassId = ProductService.Gamepasses["FormulaCar"],
		style = ColorConfig.Karts.FrameStyles.FormulaCar,
	},
	{
		kartName = "1_FlameKart",
		displayName = "Flame Kart",
		sourceFolder = "Specials",
		wheelOnly = true,
		wheelImage = (SpinWheelConfig.GetReward("FlameKart") :: SpinWheelConfig.RewardDefinition).imageAssetId,
		style = WHEEL_STYLE,
	},
	{
		kartName = "1_CrimsonRunner",
		displayName = "Crimson Runner",
		sourceFolder = "Specials",
		sourceSubfolder = "Bloodmoon",
		bloodmoonKart = true,
		showOnlyWhenOwned = true,
		imageAssetId = "rbxassetid://140523900133990",
		style = ColorConfig.Karts.FrameStyles.BloodMoon,
	},
	{
		kartName = "2_NightGlider",
		displayName = "Night Glider",
		sourceFolder = "Specials",
		sourceSubfolder = "Bloodmoon",
		bloodmoonKart = true,
		showOnlyWhenOwned = true,
		imageAssetId = "rbxassetid://104926778382950",
		style = ColorConfig.Karts.FrameStyles.BloodMoon,
	},
	{
		kartName = "3_Moonfang",
		displayName = "Moonfang",
		sourceFolder = "Specials",
		sourceSubfolder = "Bloodmoon",
		bloodmoonKart = true,
		showOnlyWhenOwned = true,
		imageAssetId = "rbxassetid://120790041354948",
		style = ColorConfig.Karts.FrameStyles.BloodMoon,
	},
	{
		kartName = "4_CrimsonCell",
		displayName = "Crimson Cell",
		sourceFolder = "Specials",
		sourceSubfolder = "Bloodmoon",
		productKey = "CrimsonCell",
		bloodmoonKart = true,
		showOnlyWhenOwned = true,
		style = ColorConfig.Karts.FrameStyles.BloodMoon,
	},
	{
		kartName = "5_BloodDragon",
		displayName = "Blood Dragon",
		sourceFolder = "Specials",
		sourceSubfolder = "Bloodmoon",
		productKey = "BloodDragon",
		bloodmoonKart = true,
		showOnlyWhenOwned = true,
		style = ColorConfig.Karts.FrameStyles.BloodMoon,
	},
	{
		kartName = "6_SiegeTank",
		displayName = "Siege Tank",
		sourceFolder = "Specials",
		sourceSubfolder = "Bloodmoon",
		productKey = "SiegeTank",
		bloodmoonKart = true,
		showOnlyWhenOwned = true,
		style = ColorConfig.Karts.FrameStyles.BloodMoon,
	},
	{
		kartName = "1_SparkBuggy",
		displayName = "Spark Buggy",
		sourceFolder = "Specials",
		sourceSubfolder = "NeonRush",
		eventId = "NeonRush",
		showOnlyWhenOwned = true,
		imageAssetId = "rbxassetid://111899124648289",
		style = ColorConfig.Karts.FrameStyles.NeonRush,
	},
	{
		kartName = "2_TurboRunner",
		displayName = "Turbo Runner",
		sourceFolder = "Specials",
		sourceSubfolder = "NeonRush",
		eventId = "NeonRush",
		showOnlyWhenOwned = true,
		imageAssetId = "rbxassetid://119199314964183",
		style = ColorConfig.Karts.FrameStyles.NeonRush,
	},
	{
		kartName = "3_VoltVIper",
		displayName = "Volt Viper",
		sourceFolder = "Specials",
		sourceSubfolder = "NeonRush",
		eventId = "NeonRush",
		productKey = "VoltVIper",
		showOnlyWhenOwned = true,
		imageAssetId = "rbxassetid://114735487114166",
		style = ColorConfig.Karts.FrameStyles.NeonRush,
	},
	{
		kartName = "1_Sled",
		displayName = "Ice Sled",
		sourceFolder = "Specials",
		sourceSubfolder = "FrostbiteRally",
		eventId = "FrostbiteRally",
		showOnlyWhenOwned = true,
		imageAssetId = "rbxassetid://118255357334971",
		style = ColorConfig.Karts.FrameStyles.FrostbiteRally,
	},
	{
		kartName = "2_Snowmobile",
		displayName = "Snowmobile",
		sourceFolder = "Specials",
		sourceSubfolder = "FrostbiteRally",
		eventId = "FrostbiteRally",
		showOnlyWhenOwned = true,
		imageAssetId = "rbxassetid://86298743744530",
		style = ColorConfig.Karts.FrameStyles.FrostbiteRally,
	},
	{
		kartName = "3_IglooKart",
		displayName = "Igloo Kart",
		sourceFolder = "Specials",
		sourceSubfolder = "FrostbiteRally",
		eventId = "FrostbiteRally",
		productKey = "IglooKart",
		showOnlyWhenOwned = true,
		imageAssetId = "rbxassetid://82634533787672",
		style = ColorConfig.Karts.FrameStyles.FrostbiteRally,
	},
	{
		kartName = "1_PumpkinKart",
		displayName = "Pumpkin Kart",
		sourceFolder = "Specials",
		sourceSubfolder = "Halloween",
		eventId = "Halloween",
		productKey = "PumpkinKart",
		showOnlyWhenOwned = true,
		style = ColorConfig.Karts.FrameStyles.Halloween,
	},
	{
		kartName = "2_CoffinKart",
		displayName = "Coffin Kart",
		sourceFolder = "Specials",
		sourceSubfolder = "Halloween",
		eventId = "Halloween",
		productKey = "CoffinKart",
		showOnlyWhenOwned = true,
		style = ColorConfig.Karts.FrameStyles.Halloween,
	},
	{
		kartName = "3_WitchBroom",
		displayName = "Witch Broom",
		sourceFolder = "Specials",
		sourceSubfolder = "Halloween",
		eventId = "Halloween",
		productKey = "WitchBroom",
		showOnlyWhenOwned = true,
		style = ColorConfig.Karts.FrameStyles.Halloween,
	},
	{
		kartName = "4_HearseKart",
		displayName = "Hearse Kart",
		sourceFolder = "Specials",
		sourceSubfolder = "Halloween",
		eventId = "Halloween",
		productKey = "HearseKart",
		showOnlyWhenOwned = true,
		style = ColorConfig.Karts.FrameStyles.Halloween,
	},
	{
		kartName = "5_HorsemanKart",
		displayName = "Horseman Kart",
		sourceFolder = "Specials",
		sourceSubfolder = "Halloween",
		eventId = "Halloween",
		productKey = "HorsemanKart",
		showOnlyWhenOwned = true,
		style = ColorConfig.Karts.FrameStyles.Halloween,
	},
}

local function getKartEventId(config: KartConfig): string?
	local eventId = config.eventId
	if typeof(eventId) ~= "string" or eventId == "" then
		eventId = config.sourceSubfolder
	end
	return if typeof(eventId) == "string" and eventId ~= "" then eventId else nil
end

local function getNumericAttribute(instance: Instance?, attributeName: string): number?
	if not instance then
		return nil
	end

	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end
	if typeof(value) == "string" then
		return tonumber(value)
	end
	return nil
end

function KartShopController.new(options: Options): Controller
	local player = options.player
	local shopMaid = Maid.new()
	local entryFrames: { [string]: KartEntry } = {}
	local controller: Controller = {} :: Controller

	local function getKartShopStepsText(config: KartConfig): string?
		local sourceFolder = config.sourceFolder or "Gamepasses"
		local kartModel = KartCatalog.FindModel(config.kartName, sourceFolder, config.sourceSubfolder)
		local xpGain = getNumericAttribute(kartModel, "XP_Gain")
		if typeof(xpGain) == "number" then
			return string.format("+%s/Steps", tostring(math.round(xpGain)))
		end
		return nil
	end

	local function isEventKartConfig(config: KartConfig): boolean
		return getKartEventId(config) ~= nil
	end

	local function canBuyEventProduct(config: KartConfig, isOwned: boolean): boolean
		local eventId = getKartEventId(config)
		return not isOwned
			and eventId ~= nil
			and typeof(config.productKey) == "string"
			and options.isLiveEventActive(eventId)
	end

	local function updateKartShop()
		local kartFrame = VisualFunctions.ActiveFrameGroup.KartFrame
		local scrollBackground = kartFrame and kartFrame:FindFirstChild("ScrollBackground")
		local scrollingFrame = scrollBackground and scrollBackground:FindFirstChild("ScrollingFrame")
		if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") then
			return
		end

		for _, config in ipairs(KART_FRAME_CONFIGS) do
			local entry = entryFrames[config.kartName]
			if not entry then
				continue
			end

			local isOwned = PlayerHandler.OwnsKart(player, config.kartName)
			local isEquipped = player:GetAttribute("Kart_Equipped") == config.kartName
			local isWheelOnly = config.wheelOnly == true
			local frameStyle = if isWheelOnly then WHEEL_STYLE else config.style
			entry.frame.BackgroundColor3 = frameStyle.BackgroundColor

			local frameGradient = entry.frame:FindFirstChildOfClass("UIGradient")
			if not frameGradient then
				frameGradient = Instance.new("UIGradient")
				frameGradient.Parent = entry.frame
			end
			frameGradient.Rotation = 90
			frameGradient.Color = frameStyle.Gradient
			VisualFunctions.RefreshFrameInteractionColors(entry.frame)

			local kartNameLabel = entry.frame:FindFirstChild("KartName", true)
			if kartNameLabel and kartNameLabel:IsA("TextLabel") then
				kartNameLabel.Text = string.upper(config.displayName)
				kartNameLabel.TextColor3 = config.style.BackgroundColor
			end

			local kartTypeImage = entry.frame:FindFirstChild("KartType", true)
			if kartTypeImage and (kartTypeImage:IsA("ImageLabel") or kartTypeImage:IsA("ImageButton")) then
				if isWheelOnly and typeof(config.wheelImage) == "string" then
					kartTypeImage.Image = config.wheelImage
				elseif typeof(config.imageAssetId) == "string" then
					kartTypeImage.Image = config.imageAssetId
				elseif typeof(config.gamePassId) == "number" then
					local info = options.getMarketplaceInfoCached(config.gamePassId, Enum.InfoType.GamePass)
					if info then
						local iconAssetId = tonumber((info :: any).IconImageAssetId)
						if iconAssetId and iconAssetId > 0 then
							kartTypeImage.Image = "rbxassetid://" .. tostring(iconAssetId)
						end
					end
				elseif typeof(config.productKey) == "string" then
					local productId = ProductService.DevProducts[config.productKey]
					if typeof(productId) == "number" then
						local info = options.getMarketplaceInfoCached(productId, Enum.InfoType.Product)
						if info then
							local iconAssetId = tonumber((info :: any).IconImageAssetId)
							if iconAssetId and iconAssetId > 0 then
								kartTypeImage.Image = "rbxassetid://" .. tostring(iconAssetId)
							end
						end
					end
				end
			end

			local speedAmountLabel = entry.frame:FindFirstChild("SpeedAmount", true)
			if speedAmountLabel and speedAmountLabel:IsA("TextLabel") then
				speedAmountLabel.Text = getKartShopStepsText(config) or "+0/Steps"
			end

			if entry.equipButton then
				local textButton = entry.equipButton:FindFirstChild("TextButton", true)
				if textButton and textButton:IsA("TextButton") then
					if isWheelOnly and not isOwned then
						textButton.Text = "SPIN"
					elseif isEventKartConfig(config) and not isOwned and typeof(config.productKey) ~= "string" then
						textButton.Text = "EVENT"
					elseif isEquipped then
						textButton.Text = "EQUIPPED"
					elseif isOwned then
						textButton.Text = "EQUIP"
					else
						textButton.Text = "BUY"
					end
				end

				VisualFunctions.SetFrameInteractableState(
					entry.equipButton,
					isOwned or (isWheelOnly and not isOwned) or canBuyEventProduct(config, isOwned)
				)
				if isWheelOnly and not isOwned then
					options.applyWheelStyle(entry.equipButton)
				else
					options.applyEquipStyle(entry.equipButton)
				end
			end
		end
	end

	function controller:Build()
		shopMaid:DoCleaning()
		local kartFrame = VisualFunctions.ActiveFrameGroup.KartFrame
		local scrollBackground = kartFrame and kartFrame:FindFirstChild("ScrollBackground")
		local scrollingFrame = scrollBackground and scrollBackground:FindFirstChild("ScrollingFrame")
		if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") then
			return
		end

		local template = scrollingFrame:FindFirstChild("KartTemplate")
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

		local sortedKartConfigs: { KartConfig } = {}
		for _, config in ipairs(KART_FRAME_CONFIGS) do
			local isOwned = PlayerHandler.OwnsKart(player, config.kartName)
			local isHalloweenKart = getKartEventId(config) == "Halloween"
			local shouldShow = if isHalloweenKart
				then isOwned
				else config.showOnlyWhenOwned ~= true
					or isOwned
					or (
						isEventKartConfig(config)
							and typeof(config.productKey) == "string"
							and options.isLiveEventActive(getKartEventId(config))
					)
			if shouldShow then
				table.insert(sortedKartConfigs, config)
			end
		end
		table.sort(sortedKartConfigs, function(a, b)
			local aKartModel = KartCatalog.FindModel(a.kartName, a.sourceFolder, a.sourceSubfolder)
			local bKartModel = KartCatalog.FindModel(b.kartName, b.sourceFolder, b.sourceSubfolder)
			local aGain = getNumericAttribute(aKartModel, "XP_Gain") or 0
			local bGain = getNumericAttribute(bKartModel, "XP_Gain") or 0
			if aGain == bGain then
				return a.displayName < b.displayName
			end
			return aGain > bGain
		end)

		for index, config in ipairs(sortedKartConfigs) do
			local clone = template:Clone()
			clone.Name = config.kartName .. "Template"
			clone.LayoutOrder = index
			clone.Visible = true
			clone.Parent = scrollingFrame

			local equipButton = clone:FindFirstChild("EquipButton")
			if equipButton and equipButton:IsA("GuiObject") then
				local textButton = equipButton:FindFirstChild("TextButton", true)
				if textButton and textButton:IsA("TextButton") then
					shopMaid:GiveTask(textButton.Activated:Connect(function()
						SoundService.PlayGuiSound("Click")
						local isOwned = PlayerHandler.OwnsKart(player, config.kartName)
						if isEventKartConfig(config) and not isOwned and not options.isLiveEventActive(getKartEventId(config)) then
							return
						end
						if config.wheelOnly == true and not isOwned then
							options.openSpinWheelFromShop(player)
							return
						end
						if not isOwned then
							if typeof(config.productKey) == "string" then
								local productId = ProductService.DevProducts[config.productKey]
								if typeof(productId) == "number" then
									ProductService.promptProductPurchase(player, productId)
								end
							elseif typeof(config.gamePassId) == "number" then
								ProductService.promptGamePassPurchase(player, config.gamePassId)
							end
							return
						end
						options.kartActionRemote:FireServer("Equip", config.kartName)
					end))
				end
			end

			entryFrames[config.kartName] = {
				frame = clone,
				equipButton = if equipButton and equipButton:IsA("GuiObject") then equipButton else nil,
			}
		end

		updateKartShop()
	end

	function controller:Update()
		updateKartShop()
	end

	function controller:Destroy()
		shopMaid:DoCleaning()
		table.clear(entryFrames)
	end

	return controller
end

return KartShopController
