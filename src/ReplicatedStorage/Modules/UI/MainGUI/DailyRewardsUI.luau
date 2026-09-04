--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Maid = require(Modules:WaitForChild("Maid"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local ProductService = require(Modules:WaitForChild("ProductService"))
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local FunnelAnalytics = require(Modules:WaitForChild("FunnelAnalytics"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))
local UIFolder = Modules:WaitForChild("UI")
local VisualFunctions = require(UIFolder:WaitForChild("VisualFunctions"))
local DailyRewardsConfig = require(script.Parent:WaitForChild("DailyRewardsConfig"))

local DailyRewardsUI = {}
DailyRewardsUI.__index = DailyRewardsUI

local MODULE_NAME = "DailyRewardsUI"
local COUNTDOWN_UPDATE_INTERVAL = 0.2
local DISABLED_CARD_MULTIPLIER = 0.5
local CLAIMABLE_CARD_SCALE = 1.075
local CURRENT_DAY_ATTRIBUTE = DailyRewardsConfig.CURRENT_DAY_ATTRIBUTE
local NEXT_CLAIM_ATTRIBUTE = DailyRewardsConfig.NEXT_CLAIM_ATTRIBUTE
local CYCLE_COUNT_ATTRIBUTE = DailyRewardsConfig.CYCLE_COUNT_ATTRIBUTE
local CLAIM_ALL_PRODUCT_ID = ProductService.DevProducts["ClaimAllDaily"]
local dailyRewardsConfig = if CoreConfig.server and CoreConfig.server.dailyRewards
	then CoreConfig.server.dailyRewards
	else nil
local DEBUG_SEQUENTIAL_CLAIM_MODE = RunService:IsStudio()
	and dailyRewardsConfig
	and typeof(dailyRewardsConfig.debugSequentialClaimMode) == "boolean"
	and dailyRewardsConfig.debugSequentialClaimMode == true

type DailyRewardDefinition = DailyRewardsConfig.DailyRewardDefinition

type ControllerOptions = {
	player: Player,
	root: Instance,
	onClaimableChanged: ((boolean) -> ())?,
}

type RewardEntry = {
	day: number,
	root: Frame,
	rewardAmountLabel: TextLabel,
	rewardTypeImage: ImageLabel,
	dayCounterLabel: TextLabel?,
	gradient: UIGradient,
	uiscale: UIScale,
	lastStyleKey: string?,
}

local function cacheOriginalColorAttributes(target: Instance)
	local targetProps = {}

	if target:IsA("Frame") or target:IsA("ScrollingFrame") then
		table.insert(targetProps, "BackgroundColor3")
	elseif target:IsA("TextLabel") then
		table.insert(targetProps, "TextColor3")
		table.insert(targetProps, "BackgroundColor3")
	elseif target:IsA("TextButton") or target:IsA("TextBox") then
		table.insert(targetProps, "BackgroundColor3")
		table.insert(targetProps, "TextColor3")
	elseif target:IsA("ImageLabel") then
		table.insert(targetProps, "ImageColor3")
		table.insert(targetProps, "BackgroundColor3")
	elseif target:IsA("ImageButton") then
		table.insert(targetProps, "BackgroundColor3")
		table.insert(targetProps, "ImageColor3")
	elseif target:IsA("UIStroke") then
		table.insert(targetProps, "Color")
	end

	for _, targetProp in ipairs(targetProps) do
		local attributeName = "OriginalColor_" .. targetProp
		if target:GetAttribute(attributeName) == nil then
			target:SetAttribute(attributeName, (target :: any)[targetProp])
		end
	end
end

local function cacheEntryOriginalColors(root: Frame)
	if root:GetAttribute("OriginalDisabledBaseColor") == nil then
		root:SetAttribute("OriginalDisabledBaseColor", root.BackgroundColor3)
	end

	cacheOriginalColorAttributes(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		cacheOriginalColorAttributes(descendant)
	end
end

local function formatRewardNumber(value: number): string
	return VisualFunctions.FormatNumber(value)
end

local function formatClockDuration(totalSeconds: number): string
	local clamped = math.max(0, math.floor(totalSeconds))
	local hours = math.floor(clamped / 3600)
	local minutes = math.floor((clamped % 3600) / 60)
	local seconds = clamped % 60
	return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function sanitizeCurrentDay(rawValue: any): number
	if typeof(rawValue) ~= "number" then
		return 1
	end

	return math.clamp(math.floor(rawValue), 1, DailyRewardsConfig.DAY_COUNT)
end

local function sanitizeCycleCount(rawValue: any): number
	if typeof(rawValue) ~= "number" then
		return 0
	end

	return math.max(0, math.floor(rawValue))
end

local function sanitizeNextClaimUnix(rawValue: any): number
	if typeof(rawValue) ~= "number" then
		return 0
	end

	return math.max(0, math.floor(rawValue))
end

local function getRewardPreviewAmount(player: Player, reward: DailyRewardDefinition, cycleCount: number): number
	local scaledAmount = DailyRewardsConfig.GetScaledAmount(reward, cycleCount)

	if reward.kind == "XPSpeed" then
		return math.round(PlayerHandler.CalculateRewardXPSpeed(player, scaledAmount))
	end

	if reward.kind == "Wins" then
		return PlayerHandler.CalculateDailyWinsAward(player, scaledAmount)
	end

	return scaledAmount
end

local function getRewardAmountText(player: Player, reward: DailyRewardDefinition, cycleCount: number): string
	local previewAmount = getRewardPreviewAmount(player, reward, cycleCount)
	return string.format(
		"%s %s",
		formatRewardNumber(previewAmount),
		DailyRewardsConfig.GetRewardLabel(reward.kind, previewAmount)
	)
end

local function getIconLabel(dayFrame: Frame): ImageLabel?
	local rewardType = dayFrame:FindFirstChild("RewardType")
	if rewardType and rewardType:IsA("ImageLabel") then
		return rewardType
	end

	local kartType = dayFrame:FindFirstChild("KartType")
	if kartType and kartType:IsA("ImageLabel") then
		return kartType
	end

	return dayFrame:FindFirstChildWhichIsA("ImageLabel")
end

local function getOrCreateGradient(dayFrame: Frame): UIGradient
	local existingGradient = dayFrame:FindFirstChildOfClass("UIGradient")
	if existingGradient then
		return existingGradient
	end

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = dayFrame
	return gradient
end

local function getOrCreateUIScale(dayFrame: Frame): UIScale
	local existingScale = dayFrame:FindFirstChildOfClass("UIScale")
	if existingScale then
		return existingScale
	end

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = 1
	uiScale.Parent = dayFrame
	return uiScale
end

function DailyRewardsUI.new(options: ControllerOptions)
	local self = setmetatable({}, DailyRewardsUI)

	self.player = options.player
	self.root = options.root
	self.maid = Maid.new()
	self.buttonMaid = Maid.new()
	self.entries = {} :: { [number]: RewardEntry }
	self.destroyed = false
	self.updateAccumulator = 0
	self.lastClaimButtonClaimable = nil :: boolean?
	self.lastClaimableState = nil :: boolean?
	self.onClaimableChanged = if typeof(options.onClaimableChanged) == "function"
		then options.onClaimableChanged
		else nil
	self.dailyRewardAction = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DailyRewardAction") :: RemoteEvent
	self.frame = nil :: Frame?
	self.claimDailyButton = nil :: TextButton?
	self.claimDailyButtonFrame = nil :: Frame?
	self.claimAllButton = nil :: TextButton?
	self.claimAllButtonFrame = nil :: Frame?
	self.claimAllPriceLabel = nil :: TextLabel?
	self.dailyCountdownLabel = nil :: TextLabel?

	self:Rebuild()
	self:Bind()
	self:Refresh()

	return self
end

function DailyRewardsUI:FindDailyRewardFrame(): Frame?
	local frame = self.root:FindFirstChild("DailyRewardFrame", true)
	if frame and frame:IsA("Frame") then
		return frame
	end

	return nil
end

function DailyRewardsUI:Rebuild()
	table.clear(self.entries)
	self.buttonMaid:DoCleaning()

	self.frame = self:FindDailyRewardFrame()
	if not self.frame then
		return
	end

	local bodyFrame = self.frame:FindFirstChild("BodyFrame")
	if not bodyFrame or not bodyFrame:IsA("Frame") then
		return
	end

	self.dailyCountdownLabel = bodyFrame:FindFirstChild("DailyCountdown") :: TextLabel?
	self.claimDailyButtonFrame = self.frame:FindFirstChild("ClaimDailyButton") :: Frame?
	self.claimAllButtonFrame = self.frame:FindFirstChild("ClaimAllDailyButton") :: Frame?
	self.claimDailyButton = self.claimDailyButtonFrame
			and self.claimDailyButtonFrame:FindFirstChildWhichIsA("TextButton", true)
		or nil
	self.claimAllButton = self.claimAllButtonFrame
			and self.claimAllButtonFrame:FindFirstChildWhichIsA("TextButton", true)
		or nil
	self.claimAllPriceLabel = self.claimAllButtonFrame
			and self.claimAllButtonFrame:FindFirstChild("PriceLabel", true) :: TextLabel?
		or nil

	if self.claimDailyButtonFrame then
		cacheEntryOriginalColors(self.claimDailyButtonFrame)
	end
	if self.claimAllButtonFrame then
		cacheEntryOriginalColors(self.claimAllButtonFrame)
	end

	for day = 1, DailyRewardsConfig.DAY_COUNT do
		local dayFrame = bodyFrame:FindFirstChild(string.format("Day%dInfo", day))
		if not dayFrame or not dayFrame:IsA("Frame") then
			continue
		end

		local rewardAmountLabel = dayFrame:FindFirstChild("RewardAmount") :: TextLabel?
		local rewardTypeImage = getIconLabel(dayFrame)
		if not rewardAmountLabel or not rewardTypeImage then
			DebugModule.debugWarn(
				string.format(
					"Daily reward entry missing UI refs for day %d | amount=%s icon=%s",
					day,
					tostring(rewardAmountLabel ~= nil),
					tostring(rewardTypeImage ~= nil)
				),
				MODULE_NAME
			)
			continue
		end

		local dayCounterLabel = dayFrame:FindFirstChild("DayCounter") :: TextLabel?
		local gradient = getOrCreateGradient(dayFrame)
		local uiScale = getOrCreateUIScale(dayFrame)
		gradient.Rotation = 90
		cacheEntryOriginalColors(dayFrame)

		self.entries[day] = {
			day = day,
			root = dayFrame,
			rewardAmountLabel = rewardAmountLabel,
			rewardTypeImage = rewardTypeImage,
			dayCounterLabel = dayCounterLabel,
			gradient = gradient,
			uiscale = uiScale,
			lastStyleKey = nil,
		}
	end

	if self.claimAllPriceLabel and CLAIM_ALL_PRODUCT_ID then
		task.defer(function()
			if self.destroyed then
				return
			end

			local ok, productInfo = pcall(function()
				return MarketplaceService:GetProductInfo(CLAIM_ALL_PRODUCT_ID, Enum.InfoType.Product)
			end)
			if ok and typeof(productInfo) == "table" and self.claimAllPriceLabel and self.claimAllPriceLabel.Parent then
				self.claimAllPriceLabel.Text = tostring(productInfo.PriceInRobux or 0)
			end
		end)
	end

	if self.claimDailyButton then
		self.buttonMaid:GiveTask(self.claimDailyButton.MouseButton1Click:Connect(function()
			if self.destroyed then
				return
			end

			local nextClaimUnix = sanitizeNextClaimUnix(self.player:GetAttribute(NEXT_CLAIM_ATTRIBUTE))
			local isClaimable = if DEBUG_SEQUENTIAL_CLAIM_MODE then true else os.time() >= nextClaimUnix
			if not isClaimable then
				return
			end

			self.dailyRewardAction:FireServer("ClaimCurrent")
		end))
	end

	if self.claimAllButton and CLAIM_ALL_PRODUCT_ID then
		self.buttonMaid:GiveTask(self.claimAllButton.MouseButton1Click:Connect(function()
			if self.destroyed then
				return
			end

			FunnelAnalytics.FireClientAction("DailyRewardClaimAllPromptOpened", {
				source = "DailyRewardsUI",
			})
			ProductService.promptProductPurchase(self.player, CLAIM_ALL_PRODUCT_ID)
		end))
	end
end

function DailyRewardsUI:ApplyFrameStyle(
	entry: RewardEntry,
	isClaimed: boolean,
	isCurrentDay: boolean,
	isClaimable: boolean
)
	local styleKey = table.concat({
		tostring(isClaimed),
		tostring(isCurrentDay),
		tostring(isClaimable),
	}, ":")
	if entry.lastStyleKey == styleKey then
		return
	end
	entry.lastStyleKey = styleKey

	local reward = DailyRewardsConfig.GetReward(entry.day)
	if not reward then
		return
	end

	local topColor = reward.topColor
	local bottomColor = reward.bottomColor
	local shouldDisable = isClaimed or not isCurrentDay
	local targetScale = if isCurrentDay then CLAIMABLE_CARD_SCALE else 1

	entry.root.BackgroundColor3 = topColor
	entry.root:SetAttribute("OriginalDisabledBaseColor", topColor)
	entry.root:SetAttribute("OriginalColor_BackgroundColor3", topColor)
	entry.gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, topColor),
		ColorSequenceKeypoint.new(1, bottomColor),
	})
	VisualFunctions.SetFrameDisabledState(entry.root, shouldDisable, DISABLED_CARD_MULTIPLIER)
	TweenService:Create(
		entry.uiscale,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Scale = targetScale }
	):Play()
end

function DailyRewardsUI:ApplyClaimButtonState(isClaimable: boolean)
	if self.lastClaimButtonClaimable == isClaimable then
		return
	end
	self.lastClaimButtonClaimable = isClaimable

	local button = self.claimDailyButton
	local buttonFrame = self.claimDailyButtonFrame

	if buttonFrame then
		VisualFunctions.SetFrameDisabledState(buttonFrame, not isClaimable, 0.65)
	end

	if not button then
		return
	end

	button.AutoButtonColor = false
	button.Active = isClaimable
	button.Selectable = isClaimable
	button.Text = "CLAIM"
end

function DailyRewardsUI:NotifyClaimableChanged(isClaimable: boolean)
	if self.lastClaimableState == isClaimable then
		return
	end
	self.lastClaimableState = isClaimable

	local callback = self.onClaimableChanged
	if not callback then
		return
	end

	local ok, err = pcall(callback, isClaimable)
	if not ok then
		DebugModule.debugWarn(string.format("onClaimableChanged callback failed: %s", tostring(err)), MODULE_NAME)
	end
end

function DailyRewardsUI:Refresh()
	if self.destroyed then
		return
	end

	if next(self.entries) == nil then
		self:Rebuild()
	end

	local currentDay = sanitizeCurrentDay(self.player:GetAttribute(CURRENT_DAY_ATTRIBUTE))
	local cycleCount = sanitizeCycleCount(self.player:GetAttribute(CYCLE_COUNT_ATTRIBUTE))
	local nextClaimUnix = sanitizeNextClaimUnix(self.player:GetAttribute(NEXT_CLAIM_ATTRIBUTE))
	local nowUnix = os.time()
	local claimable = if DEBUG_SEQUENTIAL_CLAIM_MODE then true else nowUnix >= nextClaimUnix
	local remainingSeconds = math.max(0, nextClaimUnix - nowUnix)

	for day, entry in pairs(self.entries) do
		local reward = DailyRewardsConfig.GetReward(day)
		if not reward then
			continue
		end

		entry.rewardAmountLabel.Text = getRewardAmountText(self.player, reward, cycleCount)
		entry.rewardTypeImage.Image = reward.image
		if entry.dayCounterLabel then
			entry.dayCounterLabel.Text = string.format("DAY %d", day)
		end

		local isClaimed = day < currentDay
		self:ApplyFrameStyle(entry, isClaimed, day == currentDay, claimable)
	end

	if self.dailyCountdownLabel then
		self.dailyCountdownLabel.Visible = true
		self.dailyCountdownLabel.Text = if claimable
			then "REWARD READY!"
			else string.format("DAY %d REWARD AVAILABLE IN %s", currentDay, formatClockDuration(remainingSeconds))
	end

	self:ApplyClaimButtonState(claimable)
	self:NotifyClaimableChanged(claimable)
end

function DailyRewardsUI:Bind()
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(CURRENT_DAY_ATTRIBUTE):Connect(function()
		self:Refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(NEXT_CLAIM_ATTRIBUTE):Connect(function()
		self:Refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(CYCLE_COUNT_ATTRIBUTE):Connect(function()
		self:Refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("Rebirth_XPMultiplier"):Connect(function()
		self:Refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("DevProduct_XPSpeedMultiplier"):Connect(function()
		self:Refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("Misc_XPSpeedMultiplier"):Connect(function()
		self:Refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("Friend_XPMultiplier"):Connect(function()
		self:Refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("Treadmill_XPMultiplier"):Connect(function()
		self:Refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("WinMultiplier"):Connect(function()
		self:Refresh()
	end))

	self.maid:GiveTask(self.root.DescendantAdded:Connect(function(descendant)
		if
			descendant.Name == "DailyRewardFrame"
			or descendant.Name == "ClaimDailyButton"
			or descendant.Name == "ClaimAllDailyButton"
			or string.match(descendant.Name, "^Day%dInfo$")
		then
			task.defer(function()
				if self.destroyed then
					return
				end
				self:Rebuild()
				self:Refresh()
			end)
		end
	end))

	self.maid:GiveTask(RunService.Heartbeat:Connect(function(dt)
		self.updateAccumulator += dt
		if self.updateAccumulator < COUNTDOWN_UPDATE_INTERVAL then
			return
		end
		self.updateAccumulator = 0
		self:Refresh()
	end))
end

function DailyRewardsUI:Destroy()
	if self.destroyed then
		return
	end

	self.destroyed = true
	self:NotifyClaimableChanged(false)
	self.maid:DoCleaning()
	self.buttonMaid:DoCleaning()
	table.clear(self.entries)
end

return DailyRewardsUI
