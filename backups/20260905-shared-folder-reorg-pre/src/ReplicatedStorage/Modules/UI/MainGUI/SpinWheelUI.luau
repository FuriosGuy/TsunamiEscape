--!strict

local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig_Client"))
local SpinWheelConfig = require(ConfigFolder:WaitForChild("SpinWheelConfig"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local Maid = require(Modules:WaitForChild("Maid"))
local ProductService = require(Modules:WaitForChild("ProductService"))
local RewardedVideoClient = require(Modules:WaitForChild("RewardedVideoClient"))
local VisualFunctions = require(Modules:WaitForChild("UI"):WaitForChild("VisualFunctions"))
local SoundService = require(Modules:WaitForChild("SoundService"))

local SpinWheelUI = {}
SpinWheelUI.__index = SpinWheelUI

local MODULE_NAME = "SpinWheelUI"
local SPINS_ATTRIBUTE = "SpinWheelSpins"
local NEXT_FREE_SPIN_ATTRIBUTE = "SpinWheelNextFreeSpinUnix"
local FREE_SPIN_COOLDOWN_SECONDS = 24 * 60 * 60
local REWARDED_AD_REMAINING_ATTRIBUTE = "SpinWheelRewardedAdSpinsRemaining"
local REWARDED_AD_NEXT_AVAILABLE_ATTRIBUTE = "SpinWheelRewardedAdNextAvailableUnix"
local REWARDED_AD_RESET_ATTRIBUTE = "SpinWheelRewardedAdResetUnix"
local BLUR_SIZE = 24
local BADGE_NAME = "SpinWheelClaimableNotification"
local MOVEMENT_LOCK_ACTION = "SpinWheelMovementLock"
local MOVEMENT_LOCK_KEYS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Space,
}

type VisibilityState = {
	visible: boolean,
	interactable: boolean,
}

type Controller = {
	root: Instance,
	player: Player,
	maid: any,
	frame: Frame?,
	mainFrame: Frame?,
	notificationFrame: Frame?,
	notificationFrameDefaultZIndex: number?,
	arrow: GuiObject?,
	spinWheelButtonFrame: GuiObject?,
	spinButtonFrame: Frame?,
	spinButton: TextButton?,
	nextSpinLabel: TextLabel?,
	nextSpinLabel1: TextLabel?,
	watchAdButtonFrame: Frame?,
	watchAdButton: TextButton?,
	exitButton: GuiButton?,
	rewardFrames: { [SpinWheelConfig.RewardId]: GuiObject },
	visibilitySnapshot: { [GuiObject]: VisibilityState },
	badge: GuiObject?,
	blurEffect: BlurEffect?,
	createdBlur: boolean,
	isOpen: boolean,
	alive: boolean,
	spinInFlight: boolean,
	rewardedAdInFlight: boolean,
	rewardedAdCooldownVisible: boolean,
	rewardedAdRemainingOverride: number?,
	rewardedAdNextAvailableOverride: number?,
	rewardedAdResetOverride: number?,
	watchAdDisabled: boolean?,
	spinButtonDisabled: boolean?,
	spinToken: number,
	idleThread: thread?,
	countdownThread: thread?,
	availabilityThread: thread?,
	spinThread: thread?,
	spinTickThread: thread?,
	grantThread: thread?,
	activeTween: Tween?,
	lastBadgeText: string?,
	pendingServerToken: string?,
	movementLockedHumanoid: Humanoid?,
	movementWalkSpeed: number?,
	movementJumpHeight: number?,
	movementJumpPower: number?,
	movementAutoRotate: boolean?,
	movementInputBound: boolean,
}

local function findGuiButton(instance: Instance?): GuiButton?
	if not instance then
		return nil
	end
	if instance:IsA("GuiButton") then
		return instance
	end
	return instance:FindFirstChildWhichIsA("GuiButton", true)
end

local function findTextLabel(instance: Instance?, name: string): TextLabel?
	if not instance then
		return nil
	end
	local child = instance:FindFirstChild(name, true)
	return if child and child:IsA("TextLabel") then child else nil
end

local function getNumberAttribute(player: Player, name: string, defaultValue: number): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else defaultValue
end

local function formatDuration(seconds: number): string
	local remaining = math.max(0, math.floor(seconds))
	local hours = math.floor(remaining / 3600)
	local minutes = math.floor((remaining % 3600) / 60)
	local remainder = remaining % 60
	return string.format("%02d:%02d:%02d", hours, minutes, remainder)
end

local function normalizePositiveAngle(angle: number): number
	local normalized = angle % 360
	return if normalized < 0 then normalized + 360 else normalized
end

local function normalizeSignedAngle(angle: number): number
	local normalized = normalizePositiveAngle(angle)
	return if normalized > 180 then normalized - 360 else normalized
end

local function getCenter(guiObject: GuiObject): Vector2
	return guiObject.AbsolutePosition + (guiObject.AbsoluteSize * 0.5)
end

local function getAngleBetween(origin: Vector2, target: Vector2): number
	local delta = target - origin
	return math.deg(math.atan2(delta.Y, delta.X))
end

local function getRewardName(rewardId: SpinWheelConfig.RewardId): string
	local reward = SpinWheelConfig.GetReward(rewardId)
	return if reward then reward.displayName else string.upper(rewardId)
end

function SpinWheelUI.new(root: Instance): Controller
	local self = setmetatable({
		root = root,
		player = game:GetService("Players").LocalPlayer,
		maid = Maid.new(),
		frame = nil,
		mainFrame = nil,
		notificationFrame = nil,
		notificationFrameDefaultZIndex = nil,
		arrow = nil,
		spinWheelButtonFrame = nil,
		spinButtonFrame = nil,
		spinButton = nil,
		nextSpinLabel = nil,
		nextSpinLabel1 = nil,
		watchAdButtonFrame = nil,
		watchAdButton = nil,
		exitButton = nil,
		rewardFrames = {},
		visibilitySnapshot = {},
		badge = nil,
		blurEffect = nil,
		createdBlur = false,
		isOpen = false,
		alive = true,
		spinInFlight = false,
		rewardedAdInFlight = false,
		rewardedAdCooldownVisible = false,
		rewardedAdRemainingOverride = nil,
		rewardedAdNextAvailableOverride = nil,
		rewardedAdResetOverride = nil,
		watchAdDisabled = nil,
		spinButtonDisabled = nil,
		spinToken = 0,
		idleThread = nil,
		countdownThread = nil,
		availabilityThread = nil,
		spinThread = nil,
		spinTickThread = nil,
		grantThread = nil,
		activeTween = nil,
		lastBadgeText = nil,
		pendingServerToken = nil,
		movementLockedHumanoid = nil,
		movementWalkSpeed = nil,
		movementJumpHeight = nil,
		movementJumpPower = nil,
		movementAutoRotate = nil,
		movementInputBound = false,
	}, SpinWheelUI) :: Controller
	return self
end

function SpinWheelUI:findReferences()
	local frameInstance = self.root:FindFirstChild("SpinWheelFrame", true)
	local buttonFrame = self.root:FindFirstChild("SpinWheelButtonFrame", true)
	if not frameInstance or not frameInstance:IsA("Frame") then
		DebugModule.debugWarn("SpinWheelFrame missing", MODULE_NAME)
		return false
	end
	if not buttonFrame or not buttonFrame:IsA("GuiObject") then
		DebugModule.debugWarn("SpinWheelButtonFrame missing", MODULE_NAME)
		return false
	end

	self.frame = frameInstance
	self.mainFrame = frameInstance:FindFirstChild("MainFrame") :: Frame?
	local notificationFrame = self.root:FindFirstChild("NotificationFrame", true)
	self.notificationFrame = if notificationFrame and notificationFrame:IsA("Frame")
		then notificationFrame
		else nil
	if self.notificationFrame then
		self.notificationFrameDefaultZIndex = self.notificationFrame.ZIndex
	end
	self.arrow = frameInstance:FindFirstChild("Arrow") :: GuiObject?
	self.spinWheelButtonFrame = buttonFrame
	self.spinButtonFrame = frameInstance:FindFirstChild("SpinButton") :: Frame?
	local spinButton = findGuiButton(self.spinButtonFrame)
	self.spinButton = if spinButton and spinButton:IsA("TextButton") then spinButton else nil
	self.nextSpinLabel = findTextLabel(frameInstance, "NextSpinLabel")
	self.nextSpinLabel1 = findTextLabel(frameInstance, "NextSpinLabel1")
	local watchAdButtonFrame = frameInstance:FindFirstChild("WatchAdButton")
	self.watchAdButtonFrame = if watchAdButtonFrame and watchAdButtonFrame:IsA("Frame")
		then watchAdButtonFrame
		else nil
	local watchAdButton = findGuiButton(watchAdButtonFrame)
	self.watchAdButton = if watchAdButton and watchAdButton:IsA("TextButton") then watchAdButton else nil
	self.exitButton = findGuiButton(frameInstance:FindFirstChild("ExitButton"))

	if not self.mainFrame or not self.arrow or not self.spinButtonFrame or not self.spinButton or not self.exitButton then
		DebugModule.debugWarn("Spin wheel UI references incomplete", MODULE_NAME)
		return false
	end

	for _, reward in ipairs(SpinWheelConfig.Rewards) do
		local rewardFrame = self.mainFrame:FindFirstChild(reward.frameName)
		if rewardFrame and rewardFrame:IsA("GuiObject") then
			self.rewardFrames[reward.id] = rewardFrame
		end
	end

	return true
end

function SpinWheelUI:setNotificationLayerForWheel(isWheelOpen: boolean)
	local notificationFrame = self.notificationFrame
	if not notificationFrame then
		return
	end

	if isWheelOpen then
		local wheelZIndex = if self.frame then self.frame.ZIndex else notificationFrame.ZIndex
		notificationFrame.ZIndex = math.max(notificationFrame.ZIndex, wheelZIndex + 1)
		return
	end

	local defaultZIndex = self.notificationFrameDefaultZIndex
	if defaultZIndex ~= nil then
		notificationFrame.ZIndex = defaultZIndex
	end
end

function SpinWheelUI:setButtonEnabled(button: GuiButton, isEnabled: boolean)
	button.Active = isEnabled
	button.AutoButtonColor = isEnabled
	button.Selectable = isEnabled
	if button.Parent and button.Parent:IsA("Frame") then
		button.Parent.Interactable = isEnabled
	end
end

function SpinWheelUI:getFreeSpinCooldownSeconds(): number
	local config = CoreConfig.spinWheel
	return if config and typeof(config.freeSpinCooldownSeconds) == "number"
		then math.max(1, math.floor(config.freeSpinCooldownSeconds))
		else FREE_SPIN_COOLDOWN_SECONDS
end

function SpinWheelUI:getRewardedAdMaxSpins(): number
	local config = CoreConfig.spinWheel
	return if config and typeof(config.rewardedAdMaxSpins) == "number"
		then math.max(1, math.floor(config.rewardedAdMaxSpins))
		else 5
end

local function formatMinutesSeconds(seconds: number): string
	local remaining = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(remaining / 60), remaining % 60)
end

function SpinWheelUI:getRewardedAdState(): (number, number, number)
	local maxSpins = self:getRewardedAdMaxSpins()
	local remaining = self.rewardedAdRemainingOverride
		or getNumberAttribute(self.player, REWARDED_AD_REMAINING_ATTRIBUTE, maxSpins)
	local nextAvailableUnix = self.rewardedAdNextAvailableOverride
		or getNumberAttribute(self.player, REWARDED_AD_NEXT_AVAILABLE_ATTRIBUTE, 0)
	local resetUnix = self.rewardedAdResetOverride
		or getNumberAttribute(self.player, REWARDED_AD_RESET_ATTRIBUTE, 0)
	local safeRemaining = math.clamp(math.floor(remaining), 0, maxSpins)
	local safeNextAvailableUnix = math.max(0, math.floor(nextAvailableUnix))
	local safeResetUnix = math.max(0, math.floor(resetUnix))
	if safeResetUnix > 0 and safeResetUnix <= os.time() then
		-- The server applies the authoritative reset when the next ad is requested.
		return maxSpins, 0, 0
	end
	return safeRemaining, safeNextAvailableUnix, safeResetUnix
end

local function formatRewardedAdCountdown(seconds: number): string
	local remaining = math.max(0, math.floor(seconds))
	if remaining >= 60 * 60 then
		return formatDuration(remaining)
	end
	return formatMinutesSeconds(remaining)
end

function SpinWheelUI:updateWatchAdButton()
	local button = self.watchAdButton
	local frame = self.watchAdButtonFrame
	local cooldownLabel = self.nextSpinLabel1
	if not button or not frame then
		return
	end

	local maxSpins = self:getRewardedAdMaxSpins()
	local remaining, nextAvailableUnix, resetUnix = self:getRewardedAdState()
	local cooldownRemaining = math.max(0, nextAvailableUnix - os.time())
	local dailyResetRemaining = if remaining <= 0 then math.max(0, resetUnix - os.time()) else 0
	local countdownRemaining = math.max(cooldownRemaining, dailyResetRemaining)
	local disabled = self.rewardedAdInFlight or remaining <= 0 or cooldownRemaining > 0
	if countdownRemaining <= 0 then
		self.rewardedAdCooldownVisible = false
	end

	button.Text = string.format("WATCH AD TO SPIN (%d/%d)", remaining, maxSpins)
	if cooldownLabel then
		cooldownLabel.Text = formatRewardedAdCountdown(countdownRemaining)
		cooldownLabel.Visible = self.rewardedAdCooldownVisible and countdownRemaining > 0 and disabled
	end
	self:setButtonEnabled(button, not disabled)
	if self.watchAdDisabled ~= disabled then
		VisualFunctions.SetFrameDisabledState(frame, disabled, 0.75)
		self.watchAdDisabled = disabled
	end
end

function SpinWheelUI:hasSpinAvailable(): boolean
	if getNumberAttribute(self.player, SPINS_ATTRIBUTE, 0) > 0 then
		return true
	end

	local nextFreeSpinUnix = getNumberAttribute(self.player, NEXT_FREE_SPIN_ATTRIBUTE, 0)
	return nextFreeSpinUnix <= os.time()
end

function SpinWheelUI:updateAvailabilityBadge()
	local shouldShow = self:hasSpinAvailable()
	if not shouldShow then
		if self.badge then
			self.badge:Destroy()
			self.badge = nil
		end
		self.lastBadgeText = nil
		return
	end

	local buttonFrame = self.spinWheelButtonFrame
	if not buttonFrame or buttonFrame.Parent == nil then
		return
	end

	local count = math.max(1, math.floor(getNumberAttribute(self.player, SPINS_ATTRIBUTE, 0)))
	local countText = tostring(count)
	if self.badge == nil or self.badge.Parent == nil then
		local template = self.root:FindFirstChild("NotifShow_Template", true)
		if template and template:IsA("GuiObject") then
			self.badge = template:Clone()
			self.badge.Name = BADGE_NAME
			self.badge.Visible = true
			self.badge.Parent = buttonFrame
		end
	end

	if self.badge then
		self.badge.Visible = true
		if self.lastBadgeText == countText then
			return
		end
		self.lastBadgeText = countText
		local numberLabel = self.badge:FindFirstChild("NumberLabel", true)
		if numberLabel and (numberLabel:IsA("TextLabel") or numberLabel:IsA("TextButton")) then
			(numberLabel :: TextLabel).Text = countText
		end
	end
end

function SpinWheelUI:updateCountdownLabel()
	local label = self.nextSpinLabel
	if not label then
		return
	end

	if self:hasSpinAvailable() then
		label.Text = "NEXT SPIN READY!"
		return
	end

	local nextFreeSpinUnix = getNumberAttribute(self.player, NEXT_FREE_SPIN_ATTRIBUTE, 0)
	local remaining = math.max(0, nextFreeSpinUnix - os.time())
	label.Text = "NEXT SPIN IN " .. formatDuration(remaining)
end

function SpinWheelUI:updateSpinButton()
	local button = self.spinButton
	if not button then
		return
	end

	local spinCount = math.max(0, math.floor(getNumberAttribute(self.player, SPINS_ATTRIBUTE, 0)))
	local hasSpinAvailable = self:hasSpinAvailable()
	local shouldDarken = not hasSpinAvailable
	button.Text = if spinCount <= 1 then "SPIN" else "SPIN (" .. tostring(spinCount) .. ")"
	self:setButtonEnabled(button, not self.spinInFlight and hasSpinAvailable)
	if self.spinButtonFrame and self.spinButtonDisabled ~= shouldDarken then
		VisualFunctions.SetFrameDisabledState(self.spinButtonFrame, shouldDarken, 0.75)
		self.spinButtonDisabled = shouldDarken
	end
	if self.exitButton then
		self:setButtonEnabled(self.exitButton, not self.spinInFlight)
	end
	self:updateAvailabilityBadge()
	self:updateCountdownLabel()
	self:updateWatchAdButton()
end

function SpinWheelUI:refreshRewardPreviews()
	local maxXPSpeed = getNumberAttribute(self.player, "MaxXPSpeed", 1)
	local smallSpeed = SpinWheelConfig.GetSmallSpeedBase(maxXPSpeed)
	local totalWins = getNumberAttribute(self.player, "WinCount", 0)
	local wheelWins = SpinWheelConfig.GetWheelWinsBase(totalWins)
	local largeSpeed = SpinWheelConfig.GetLargeSpeedBase(maxXPSpeed)

	local previewText: { [SpinWheelConfig.RewardId]: string } = {
		SpeedSmall = "+" .. VisualFunctions.FormatNumber(smallSpeed) .. " SPEED",
		SpeedLarge = "+" .. VisualFunctions.FormatNumber(largeSpeed) .. " SPEED",
		Wins = "+" .. VisualFunctions.FormatNumber(wheelWins) .. " WINS",
		Rebirth = "+1 REBIRTH",
		FlameTrail = "FLAME TRAIL",
		FlameKart = "FLAME KART",
	}

	for rewardId, rewardFrame in pairs(self.rewardFrames) do
		local rewardName = findTextLabel(rewardFrame, "RewardName")
		if rewardName then
			rewardName.Text = previewText[rewardId]
		end
		local chance = findTextLabel(rewardFrame, "Chance")
		local reward = SpinWheelConfig.GetReward(rewardId)
		if chance and reward then
			chance.Text = tostring(reward.chance) .. "%"
		end
	end
end

function SpinWheelUI:loadPrices()
	for _, pack in ipairs(SpinWheelConfig.PurchasePacks) do
		local packFrame = self.frame and self.frame:FindFirstChild(pack.buttonName, true)
		local priceLabel = findTextLabel(packFrame, "PriceLabel")
		local productId = tonumber(ProductService.DevProducts[pack.productKey])
		if priceLabel then
			priceLabel.Text = "..."
		end
		if not packFrame then
			DebugModule.debugWarn("Purchase frame missing: " .. pack.buttonName, MODULE_NAME)
		elseif not productId or productId <= 0 then
			DebugModule.debugWarn("Purchase product ID missing: " .. pack.productKey, MODULE_NAME)
		elseif not priceLabel then
			DebugModule.debugWarn("PriceLabel missing: " .. pack.buttonName, MODULE_NAME)
		else
			local thread = task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
				end)
				if not self.alive or priceLabel.Parent == nil then
					return
				end
				if ok and typeof(info) == "table" then
					local price = (info :: any).PriceInRobux
					if typeof(price) == "number" then
						priceLabel.Text = tostring(math.max(0, math.floor(price)))
					else
						priceLabel.Text = "0"
						DebugModule.debugWarn("Product has no Robux price: " .. pack.productKey, MODULE_NAME)
					end
				else
					priceLabel.Text = "0"
					DebugModule.debugWarn("Failed price lookup for " .. pack.productKey .. " (" .. tostring(info) .. ")", MODULE_NAME)
				end
			end)
			self.maid:GiveSpawnTask(thread)
		end
	end
end

function SpinWheelUI:stopIdleRotation()
	if self.idleThread then
		task.cancel(self.idleThread)
		self.idleThread = nil
	end
end

function SpinWheelUI:startIdleRotation()
	self:stopIdleRotation()
	local mainFrame = self.mainFrame
	if not mainFrame then
		return
	end

	local config = CoreConfig.spinWheel
	local degreesPerSecond = if config and typeof(config.idleRotationDegreesPerSecond) == "number"
		then config.idleRotationDegreesPerSecond
		else 8
	self.idleThread = task.spawn(function()
		while self.alive and self.isOpen and mainFrame.Parent ~= nil do
			local dt = RunService.RenderStepped:Wait()
			if not self.spinInFlight then
				mainFrame.Rotation += dt * degreesPerSecond
			end
		end
	end)
end

function SpinWheelUI:stopCountdown()
	if self.countdownThread then
		task.cancel(self.countdownThread)
		self.countdownThread = nil
	end
end

function SpinWheelUI:startCountdown()
	self:stopCountdown()
	self.countdownThread = task.spawn(function()
		while self.alive and self.isOpen and self.frame and self.frame.Parent ~= nil do
			self:updateSpinButton()
			task.wait(1)
		end
	end)
end

function SpinWheelUI:startAvailabilityWatcher()
	if self.availabilityThread then
		task.cancel(self.availabilityThread)
		self.availabilityThread = nil
	end
	self.availabilityThread = task.spawn(function()
		while self.alive and self.root.Parent ~= nil do
			self:updateSpinButton()
			task.wait(1)
		end
	end)
end

function SpinWheelUI:stopAvailabilityWatcher()
	if self.availabilityThread then
		task.cancel(self.availabilityThread)
		self.availabilityThread = nil
	end
end

function SpinWheelUI:stopSpinTween()
	self.spinToken += 1
	if self.spinTickThread then
		task.cancel(self.spinTickThread)
		self.spinTickThread = nil
	end
	if self.activeTween then
		self.activeTween:Cancel()
		self.activeTween = nil
	end
	if self.spinThread then
		task.cancel(self.spinThread)
		self.spinThread = nil
	end
	self.spinInFlight = false
end

function SpinWheelUI:resetCompletedSpinState()
	if self.spinInFlight then
		return
	end

	if self.activeTween then
		self.activeTween:Cancel()
		self.activeTween = nil
	end
	if self.spinThread then
		task.cancel(self.spinThread)
		self.spinThread = nil
	end
	if self.spinTickThread then
		task.cancel(self.spinTickThread)
		self.spinTickThread = nil
	end
	self:stopGrantThread()
	self.pendingServerToken = nil
	self.spinToken += 1
end

function SpinWheelUI:startSpinTickSound(tween: Tween, token: number)
	if self.spinTickThread then
		task.cancel(self.spinTickThread)
		self.spinTickThread = nil
	end

	local mainFrame = self.mainFrame
	if not mainFrame then
		return
	end

	local rewardCount = 0
	for _ in pairs(self.rewardFrames) do
		rewardCount += 1
	end
	if rewardCount <= 0 then
		return
	end

	local segmentAngle = 360 / rewardCount
	local config = CoreConfig.spinWheel
	local volume = if config and typeof(config.wheelTickVolume) == "number"
		then math.max(0, config.wheelTickVolume)
		else 0.25
	local minPlaybackSpeed = if config and typeof(config.wheelTickMinPlaybackSpeed) == "number"
		then math.max(1, config.wheelTickMinPlaybackSpeed)
		else 1
	local maxPlaybackSpeed = if config and typeof(config.wheelTickMaxPlaybackSpeed) == "number"
		then math.max(minPlaybackSpeed, config.wheelTickMaxPlaybackSpeed)
		else 1.6
	local referenceDegreesPerSecond = if config and typeof(config.wheelTickReferenceDegreesPerSecond) == "number"
		then math.max(1, config.wheelTickReferenceDegreesPerSecond)
		else 720

	self.spinTickThread = task.spawn(function()
		local previousRotation = mainFrame.Rotation
		while self.alive and self.isOpen and token == self.spinToken and mainFrame.Parent ~= nil do
			if tween.PlaybackState ~= Enum.PlaybackState.Playing then
				break
			end

			local deltaTime = RunService.RenderStepped:Wait()
			local currentRotation = mainFrame.Rotation
			local previousSegment = math.floor(previousRotation / segmentAngle)
			local currentSegment = math.floor(currentRotation / segmentAngle)
			local crossedSegments = math.abs(currentSegment - previousSegment)

			if crossedSegments > 0 then
				local degreesPerSecond = if deltaTime > 0
					then math.abs(currentRotation - previousRotation) / deltaTime
					else 0
				local speedAlpha = math.clamp(degreesPerSecond / referenceDegreesPerSecond, 0, 1)
				local playbackSpeed = minPlaybackSpeed
					+ ((maxPlaybackSpeed - minPlaybackSpeed) * speedAlpha)
				local tickCount = math.min(crossedSegments, 4)

				for _ = 1, tickCount do
					SoundService.PlayGuiSound("Click", nil, {
						Volume = volume,
						PlaybackSpeed = playbackSpeed,
						AllowOverlap = true,
					})
				end
			end

			previousRotation = currentRotation
		end

		if self.spinTickThread == coroutine.running() then
			self.spinTickThread = nil
		end
	end)
end

function SpinWheelUI:getRotationForReward(rewardId: SpinWheelConfig.RewardId): number?
	local mainFrame = self.mainFrame
	local arrow = self.arrow
	local rewardFrame = self.rewardFrames[rewardId]
	if not mainFrame or not arrow or not rewardFrame then
		return nil
	end

	local wheelCenter = getCenter(mainFrame)
	local arrowAngle = getAngleBetween(wheelCenter, getCenter(arrow))
	local rewardAngle = getAngleBetween(wheelCenter, getCenter(rewardFrame))
	local requiredDelta = normalizePositiveAngle(arrowAngle - rewardAngle)
	local config = CoreConfig.spinWheel
	local fullTurns = if config and typeof(config.spinFullTurns) == "number"
		then math.max(1, math.floor(config.spinFullTurns))
		else 6
	return mainFrame.Rotation + (fullTurns * 360) + requiredDelta
end

function SpinWheelUI:correctRewardAlignment(rewardId: SpinWheelConfig.RewardId)
	local mainFrame = self.mainFrame
	local arrow = self.arrow
	local rewardFrame = self.rewardFrames[rewardId]
	if not mainFrame or not arrow or not rewardFrame then
		return
	end

	local wheelCenter = getCenter(mainFrame)
	local arrowAngle = getAngleBetween(wheelCenter, getCenter(arrow))
	local rewardAngle = getAngleBetween(wheelCenter, getCenter(rewardFrame))
	mainFrame.Rotation += normalizeSignedAngle(arrowAngle - rewardAngle)
end

function SpinWheelUI:showResult(result: { [string]: any })
	local rewardId = result.rewardId
	if typeof(rewardId) ~= "string" then
		return
	end
	local reward = SpinWheelConfig.GetReward(rewardId)
	if not reward then
		return
	end

	local theme = VisualFunctions.NotificationThemes.Gold

	local rewardTerms = {}
	local awardedSpeed = tonumber(result.awardedSpeed) or 0
	local awardedWins = tonumber(result.awardedWins) or 0
	local awardedRebirth = tonumber(result.awardedRebirth) or 0
	if awardedSpeed > 0 then
		table.insert(rewardTerms, "+" .. VisualFunctions.FormatNumber(awardedSpeed) .. " SPEED")
	end
	if awardedWins > 0 then
		table.insert(rewardTerms, "+" .. VisualFunctions.FormatNumber(awardedWins) .. " WINS")
	end
	if awardedRebirth > 0 then
		table.insert(rewardTerms, "+" .. tostring(awardedRebirth) .. " REBIRTH")
	end
	local rewardText = if #rewardTerms > 0
		then table.concat(rewardTerms, " ")
		else getRewardName(rewardId :: SpinWheelConfig.RewardId)

	SoundService.PlayGuiSound("WinReward")
	VisualFunctions.ShowNotification("YOU WIN " .. rewardText .. "!", theme.textColor, theme.gradientBottomColor)
end

function SpinWheelUI:stopGrantThread()
	if self.grantThread then
		task.cancel(self.grantThread)
		self.grantThread = nil
	end
end

function SpinWheelUI:scheduleGrant(token: string)
	self:stopGrantThread()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local grantRemote = remotes:FindFirstChild("SpinWheelGrant")
	if not grantRemote or not grantRemote:IsA("RemoteEvent") then
		DebugModule.debugWarn("SpinWheelGrant remote missing", MODULE_NAME)
		return
	end

	self.grantThread = task.delay(0.75, function()
		self.grantThread = nil
		if self.alive and self.pendingServerToken == token then
			grantRemote:FireServer(token)
		end
	end)
end

function SpinWheelUI:spin(result: { [string]: any })
	if self.activeTween or self.spinThread or self.spinTickThread then
		DebugModule.debugWarn("Ignoring duplicate spin start while a spin is active", MODULE_NAME)
		return
	end
	local rewardId = result.rewardId
	if typeof(rewardId) ~= "string" or not self.mainFrame then
		self.spinInFlight = false
		self:updateSpinButton()
		return
	end

	local typedRewardId = rewardId :: SpinWheelConfig.RewardId
	local targetRotation = self:getRotationForReward(typedRewardId)
	if not targetRotation then
		self.spinInFlight = false
		self:updateSpinButton()
		return
	end

	self.spinToken += 1
	local token = self.spinToken
	self:stopIdleRotation()
	if self.spinTickThread then
		task.cancel(self.spinTickThread)
		self.spinTickThread = nil
	end
	local config = CoreConfig.spinWheel
	local duration = if config and typeof(config.spinRotationDuration) == "number"
		then math.max(0.5, config.spinRotationDuration)
		else 4
	local tween = TweenService:Create(
		self.mainFrame,
		TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Rotation = targetRotation }
	)
	self.activeTween = tween

	self.spinThread = task.spawn(function()
		tween:Play()
		self:startSpinTickSound(tween, token)
		tween.Completed:Wait()
		if self.spinTickThread then
			task.cancel(self.spinTickThread)
			self.spinTickThread = nil
		end
		if not self.alive or not self.isOpen or token ~= self.spinToken then
			return
		end
		RunService.RenderStepped:Wait()
		self:correctRewardAlignment(typedRewardId)
		local tickVolume = if config and typeof(config.wheelTickVolume) == "number"
			then math.max(0, config.wheelTickVolume)
			else 0.25
		SoundService.PlayGuiSound("Click", nil, {
			Volume = tickVolume,
			PlaybackSpeed = 1,
			AllowOverlap = true,
		})
		self.activeTween = nil
		self.spinThread = nil
		local serverToken = result.token
		if typeof(serverToken) ~= "string" then
			self.spinInFlight = false
			self:updateSpinButton()
			self:startIdleRotation()
			return
		end
		self.pendingServerToken = serverToken
		local remotes = ReplicatedStorage:WaitForChild("Remotes")
		local claimRemote = remotes:FindFirstChild("SpinWheelClaim")
		if claimRemote and claimRemote:IsA("RemoteEvent") then
			claimRemote:FireServer(serverToken)
		else
			DebugModule.debugWarn("SpinWheelClaim remote missing", MODULE_NAME)
			self.spinInFlight = false
			self:updateSpinButton()
			self:startIdleRotation()
		end
	end)
end

function SpinWheelUI:captureVisibility()
	table.clear(self.visibilitySnapshot)
	for _, child in ipairs(self.root:GetChildren()) do
		if child:IsA("GuiObject") then
			self.visibilitySnapshot[child] = {
				visible = child.Visible,
				interactable = child.Interactable,
			}
			if child ~= self.frame then
				child.Visible = false
			end
		end
	end
end

function SpinWheelUI:restoreVisibility()
	for guiObject, state in pairs(self.visibilitySnapshot) do
		if guiObject.Parent then
			guiObject.Visible = state.visible
			guiObject.Interactable = state.interactable
		end
	end
	table.clear(self.visibilitySnapshot)
end

function SpinWheelUI:enableBlur()
	local existing = Lighting:FindFirstChild("SpinWheelBlur")
	if existing and existing:IsA("BlurEffect") then
		self.blurEffect = existing
		self.createdBlur = false
	else
		local blur = Instance.new("BlurEffect")
		blur.Name = "SpinWheelBlur"
		blur.Size = BLUR_SIZE
		blur.Enabled = true
		blur.Parent = Lighting
		self.blurEffect = blur
		self.createdBlur = true
	end
	if self.blurEffect then
		self.blurEffect.Size = BLUR_SIZE
		self.blurEffect.Enabled = true
	end
end

function SpinWheelUI:disableBlur()
	if self.blurEffect then
		if self.createdBlur then
			self.blurEffect:Destroy()
		else
			self.blurEffect.Enabled = false
		end
	end
	self.blurEffect = nil
	self.createdBlur = false
end

function SpinWheelUI:bindMovementInputLock()
	if self.movementInputBound then
		return
	end

	ContextActionService:BindActionAtPriority(
		MOVEMENT_LOCK_ACTION,
		function()
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		table.unpack(MOVEMENT_LOCK_KEYS)
	)
	self.movementInputBound = true
end

function SpinWheelUI:unbindMovementInputLock()
	if not self.movementInputBound then
		return
	end

	ContextActionService:UnbindAction(MOVEMENT_LOCK_ACTION)
	self.movementInputBound = false
end

function SpinWheelUI:unlockPlayerMovement()
	local humanoid = self.movementLockedHumanoid
	if humanoid and humanoid.Parent then
		if typeof(self.movementWalkSpeed) == "number" then
			humanoid.WalkSpeed = self.movementWalkSpeed
		end
		if typeof(self.movementJumpHeight) == "number" then
			humanoid.JumpHeight = self.movementJumpHeight
		end
		if typeof(self.movementJumpPower) == "number" then
			humanoid.JumpPower = self.movementJumpPower
		end
		if typeof(self.movementAutoRotate) == "boolean" then
			humanoid.AutoRotate = self.movementAutoRotate
		end
	end

	self.movementLockedHumanoid = nil
	self.movementWalkSpeed = nil
	self.movementJumpHeight = nil
	self.movementJumpPower = nil
	self.movementAutoRotate = nil
	self:unbindMovementInputLock()
end

function SpinWheelUI:lockPlayerMovement()
	self:bindMovementInputLock()

	local character = self.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if self.movementLockedHumanoid ~= humanoid then
		self:unlockPlayerMovement()
		self:bindMovementInputLock()
		self.movementLockedHumanoid = humanoid
		self.movementWalkSpeed = humanoid.WalkSpeed
		self.movementJumpHeight = humanoid.JumpHeight
		self.movementJumpPower = humanoid.JumpPower
		self.movementAutoRotate = humanoid.AutoRotate
	end

	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero, true)
end

function SpinWheelUI:open()
	if self.isOpen or not self.frame then
		return
	end
	self:captureVisibility()
	self.isOpen = true
	self:setNotificationLayerForWheel(true)
	self.player:SetAttribute("SpinWheelModalOpen", true)
	self:lockPlayerMovement()
	self.frame.Visible = true
	self.frame.Interactable = true
	self:enableBlur()
	self:refreshRewardPreviews()
	self:updateSpinButton()
	self:startIdleRotation()
	self:startCountdown()
end

function SpinWheelUI:close()
	if not self.isOpen then
		return
	end
	if self.spinInFlight then
		return
	end
	self.isOpen = false
	self:setNotificationLayerForWheel(false)
	self.player:SetAttribute("SpinWheelModalOpen", false)
	self:unlockPlayerMovement()
	self:stopIdleRotation()
	self:stopCountdown()
	self:stopSpinTween()
	if self.frame then
		self.frame.Visible = false
		self.frame.Interactable = false
	end
	self:disableBlur()
	self:restoreVisibility()
	self:updateAvailabilityBadge()
end

function SpinWheelUI:requestSpin(ignoreLocalAvailability: boolean?): boolean
	if self.spinInFlight or (not ignoreLocalAvailability and not self:hasSpinAvailable()) then
		return false
	end

	self:resetCompletedSpinState()
	self.spinInFlight = true
	self:updateSpinButton()

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:FindFirstChild("SpinWheelRequest")
	if not remote or not remote:IsA("RemoteEvent") then
		self.spinInFlight = false
		self:updateSpinButton()
		DebugModule.debugWarn("SpinWheelRequest remote missing", MODULE_NAME)
		return false
	end

	remote:FireServer()
	return true
end

function SpinWheelUI:bind()
	local spinWheelButtonFrame = self.spinWheelButtonFrame
	local spinWheelButton = findGuiButton(spinWheelButtonFrame)
	if spinWheelButton then
		self.maid:GiveTask(spinWheelButton.Activated:Connect(function()
			SoundService.PlayGuiSound("Click")
			self:open()
		end))
	end

	if self.exitButton then
		self.maid:GiveTask(self.exitButton.Activated:Connect(function()
			if self.spinInFlight then
				return
			end
			SoundService.PlayGuiSound("Close")
			self:close()
		end))
	end

	if self.spinButton then
		self.maid:GiveTask(self.spinButton.Activated:Connect(function()
			self:requestSpin()
		end))
	end

	if self.watchAdButtonFrame and self.watchAdButton then
		VisualFunctions.SetupFrameHover(self.watchAdButtonFrame, 1.05, 35, 1.2)
		VisualFunctions.SetupFrameClick(self.watchAdButtonFrame, 0.9, -15, 0.8)
		self.maid:GiveTask(self.watchAdButton.Activated:Connect(function()
			if self.rewardedAdInFlight then
				return
			end
			local remaining, nextAvailableUnix = self:getRewardedAdState()
			if remaining <= 0 or nextAvailableUnix > os.time() then
				self:updateWatchAdButton()
				return
			end
			SoundService.PlayGuiSound("Click")
			if RewardedVideoClient.Request("SpinWheel") then
				self.rewardedAdInFlight = true
				self:updateWatchAdButton()
			end
		end))
	end

	for _, pack in ipairs(SpinWheelConfig.PurchasePacks) do
		local packFrame = self.frame and self.frame:FindFirstChild(pack.buttonName, true)
		local buyButton = findGuiButton(packFrame and packFrame:FindFirstChild("BuyButton", true))
		if not packFrame then
			DebugModule.debugWarn("Purchase frame missing while binding: " .. pack.buttonName, MODULE_NAME)
		elseif not buyButton then
			DebugModule.debugWarn("BuyButton missing while binding: " .. pack.buttonName, MODULE_NAME)
		else
			self.maid:GiveTask(buyButton.Activated:Connect(function()
				local productId = tonumber(ProductService.DevProducts[pack.productKey])
				if productId and productId > 0 then
					SoundService.PlayGuiSound("Click")
					ProductService.promptProductPurchase(self.player, productId)
				else
					DebugModule.debugWarn("Cannot prompt missing product: " .. pack.productKey, MODULE_NAME)
				end
			end))
		end
	end

	self.maid:GiveTask(self.player:GetAttributeChangedSignal(SPINS_ATTRIBUTE):Connect(function()
		self:updateSpinButton()
	end))
	self.maid:GiveTask(self.player.CharacterAdded:Connect(function()
		if self.isOpen then
			self:lockPlayerMovement()
		end
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(NEXT_FREE_SPIN_ATTRIBUTE):Connect(function()
		self:updateSpinButton()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(REWARDED_AD_REMAINING_ATTRIBUTE):Connect(function()
		self.rewardedAdRemainingOverride = nil
		self:updateWatchAdButton()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(REWARDED_AD_NEXT_AVAILABLE_ATTRIBUTE):Connect(function()
		self.rewardedAdNextAvailableOverride = nil
		self:updateWatchAdButton()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(REWARDED_AD_RESET_ATTRIBUTE):Connect(function()
		self.rewardedAdResetOverride = nil
		self:updateWatchAdButton()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("SpinWheelOpenRequested"):Connect(function()
		self:open()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("MaxXPSpeed"):Connect(function()
		self:refreshRewardPreviews()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("WinCount"):Connect(function()
		self:refreshRewardPreviews()
	end))
	self.maid:GiveTask(RewardedVideoClient.ConnectResult(function(
		placementName: string,
		completed: boolean,
		_resultName: string,
		remainingUses: number?,
		nextAvailableUnix: number?,
		resetUnix: number?
	)
		if placementName ~= "SpinWheel" then
			return
		end
		if typeof(remainingUses) == "number" then
			self.rewardedAdRemainingOverride = remainingUses
		end
		if typeof(nextAvailableUnix) == "number" then
			self.rewardedAdNextAvailableOverride = nextAvailableUnix
		end
		if typeof(resetUnix) == "number" then
			self.rewardedAdResetOverride = resetUnix
		end
		if not completed then
			self.rewardedAdInFlight = false
			self.rewardedAdCooldownVisible = false
			self.rewardedAdRemainingOverride = nil
			self.rewardedAdNextAvailableOverride = nil
			self.rewardedAdResetOverride = nil
			DebugModule.debugInfo("Spin wheel rewarded ad did not complete", MODULE_NAME)
		end
		self:updateWatchAdButton()
	end))

	local spinAdRewardedRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("SpinWheelAdRewarded")
	if spinAdRewardedRemote and spinAdRewardedRemote:IsA("RemoteEvent") then
		self.maid:GiveTask(spinAdRewardedRemote.OnClientEvent:Connect(function(
			spinCount: number?,
			remainingUses: number?,
			nextAvailableUnix: number?,
			resetUnix: number?
		)
			self.rewardedAdInFlight = false
			self.rewardedAdCooldownVisible = (typeof(nextAvailableUnix) == "number"
				and nextAvailableUnix > os.time())
				or (typeof(remainingUses) == "number"
					and remainingUses <= 0
					and typeof(resetUnix) == "number"
					and resetUnix > os.time())
			if typeof(remainingUses) == "number" then
				self.rewardedAdRemainingOverride = remainingUses
			end
			if typeof(nextAvailableUnix) == "number" then
				self.rewardedAdNextAvailableOverride = nextAvailableUnix
			end
			if typeof(resetUnix) == "number" then
				self.rewardedAdResetOverride = resetUnix
			end
			self:updateWatchAdButton()
			DebugModule.debugInfo(
				"Starting wheel spin after rewarded ad | spins=" .. tostring(spinCount),
				MODULE_NAME
			)
			if not self.isOpen then
				self:open()
			end
			self:requestSpin(true)
		end))
	else
		DebugModule.debugWarn("SpinWheelAdRewarded remote missing", MODULE_NAME)
	end

	local resultRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("SpinWheelResult")
	if resultRemote and resultRemote:IsA("RemoteEvent") then
		self.maid:GiveTask(resultRemote.OnClientEvent:Connect(function(result: { [string]: any })
			local phase = result.phase
			if phase == "Started" and self.isOpen then
				self:spin(result)
			elseif phase == "RewardReady" and self.isOpen then
				local token = result.token
				if typeof(token) == "string" and token == self.pendingServerToken then
					self:showResult(result)
					self:scheduleGrant(token)
				end
			elseif phase == "Granted" then
				local token = result.token
				if typeof(token) == "string" and token == self.pendingServerToken then
					self:stopGrantThread()
					self.pendingServerToken = nil
					self.spinInFlight = false
					self.activeTween = nil
					self.spinThread = nil
					self.spinTickThread = nil
					self:updateSpinButton()
					self:refreshRewardPreviews()
					if self.isOpen then
						self:startIdleRotation()
					end
				end
			elseif phase == "Error" then
				local token = result.token
				if typeof(token) ~= "string" or token ~= self.pendingServerToken then
					return
				end
				self:stopGrantThread()
				self.pendingServerToken = nil
				self.spinInFlight = false
				self.activeTween = nil
				self.spinThread = nil
				self.spinTickThread = nil
				self:updateSpinButton()
				if self.isOpen then
					self:startIdleRotation()
				end
			end
		end))
	end

	self.maid:GiveTask(self.root.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			self:Destroy()
		end
	end))
	self.maid:GiveTask(self.root.Destroying:Connect(function()
		self:Destroy()
	end))
end

function SpinWheelUI:Init()
	if not self:findReferences() then
		return
	end
	self:bind()
	self:loadPrices()
	self:startAvailabilityWatcher()
	local remaining, nextAvailableUnix, resetUnix = self:getRewardedAdState()
	self.rewardedAdCooldownVisible = nextAvailableUnix > os.time()
		or (remaining <= 0 and resetUnix > os.time())
	self:updateSpinButton()
	self.frame.Visible = false
	self.frame.Interactable = false
end

function SpinWheelUI:Destroy()
	if not self.alive then
		return
	end
	self.alive = false
	self.isOpen = false
	self:setNotificationLayerForWheel(false)
	self.player:SetAttribute("SpinWheelModalOpen", false)
	self:unlockPlayerMovement()
	self:stopIdleRotation()
	self:stopCountdown()
	self:stopAvailabilityWatcher()
	self:stopSpinTween()
	self:stopGrantThread()
	if self.badge then
		self.badge:Destroy()
		self.badge = nil
	end
	if self.frame then
		self.frame.Visible = false
		self.frame.Interactable = false
	end
	self:disableBlur()
	self:restoreVisibility()
	self.maid:DoCleaning()
end

return SpinWheelUI
