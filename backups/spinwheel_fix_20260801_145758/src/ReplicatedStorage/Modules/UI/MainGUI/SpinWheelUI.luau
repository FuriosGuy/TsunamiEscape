--!strict

local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))
local SpinWheelConfig = require(ConfigFolder:WaitForChild("SpinWheelConfig"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local Maid = require(Modules:WaitForChild("Maid"))
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local ProductService = require(Modules:WaitForChild("ProductService"))
local VisualFunctions = require(Modules:WaitForChild("UI"):WaitForChild("VisualFunctions"))
local SoundService = require(Modules:WaitForChild("SoundService"))

local SpinWheelUI = {}
SpinWheelUI.__index = SpinWheelUI

local MODULE_NAME = "SpinWheelUI"
local SPINS_ATTRIBUTE = "SpinWheelSpins"
local NEXT_FREE_SPIN_ATTRIBUTE = "SpinWheelNextFreeSpinUnix"
local FREE_SPIN_COOLDOWN_SECONDS = 24 * 60 * 60
local BLUR_SIZE = 24
local BADGE_NAME = "SpinWheelClaimableNotification"

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
	arrow: GuiObject?,
	spinWheelButtonFrame: GuiObject?,
	spinButtonFrame: Frame?,
	spinButton: TextButton?,
	nextSpinLabel: TextLabel?,
	exitButton: GuiButton?,
	rewardFrames: { [SpinWheelConfig.RewardId]: GuiObject },
	visibilitySnapshot: { [GuiObject]: VisibilityState },
	badge: GuiObject?,
	blurEffect: BlurEffect?,
	createdBlur: boolean,
	isOpen: boolean,
	alive: boolean,
	spinInFlight: boolean,
	spinToken: number,
	idleThread: thread?,
	countdownThread: thread?,
	availabilityThread: thread?,
	spinThread: thread?,
	activeTween: Tween?,
	lastBadgeText: string?,
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
		arrow = nil,
		spinWheelButtonFrame = nil,
		spinButtonFrame = nil,
		spinButton = nil,
		nextSpinLabel = nil,
		exitButton = nil,
		rewardFrames = {},
		visibilitySnapshot = {},
		badge = nil,
		blurEffect = nil,
		createdBlur = false,
		isOpen = false,
		alive = true,
		spinInFlight = false,
		spinToken = 0,
		idleThread = nil,
		countdownThread = nil,
		availabilityThread = nil,
		spinThread = nil,
		activeTween = nil,
		lastBadgeText = nil,
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
	self.arrow = frameInstance:FindFirstChild("Arrow") :: GuiObject?
	self.spinWheelButtonFrame = buttonFrame
	self.spinButtonFrame = frameInstance:FindFirstChild("SpinButton") :: Frame?
	local spinButton = findGuiButton(self.spinButtonFrame)
	self.spinButton = if spinButton and spinButton:IsA("TextButton") then spinButton else nil
	self.nextSpinLabel = findTextLabel(frameInstance, "NextSpinLabel")
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
	button.Text = if spinCount <= 1 then "SPIN" else "SPIN (" .. tostring(spinCount) .. ")"
	self:setButtonEnabled(button, not self.spinInFlight and self:hasSpinAvailable())
	self:updateAvailabilityBadge()
	self:updateCountdownLabel()
end

function SpinWheelUI:refreshRewardPreviews()
	local currentXPSpeed = getNumberAttribute(self.player, "CurrentXPSpeed", 0)
	local maxXPSpeed = getNumberAttribute(self.player, "MaxXPSpeed", 1)
	local smallSpeed = SpinWheelConfig.GetSmallSpeedBase(currentXPSpeed, maxXPSpeed)
	local totalWins = getNumberAttribute(self.player, "WinCount", 0)
	local wheelWins = SpinWheelConfig.GetWheelWinsBase(totalWins)
	local finalSmallSpeed = PlayerHandler.CalculateAwardedXPSpeed(self.player, smallSpeed)
	local finalLargeSpeed = PlayerHandler.CalculateAwardedXPSpeed(self.player, smallSpeed * 3)
	local winMultiplier = getNumberAttribute(self.player, "WinMultiplier", 1)
	local finalWins = math.max(0, math.round(wheelWins * winMultiplier))

	local previewText: { [SpinWheelConfig.RewardId]: string } = {
		SpeedSmall = "+" .. VisualFunctions.FormatNumber(finalSmallSpeed) .. " SPEED",
		SpeedLarge = "+" .. VisualFunctions.FormatNumber(finalLargeSpeed) .. " SPEED",
		Wins = "+" .. VisualFunctions.FormatNumber(finalWins) .. " WINS",
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
		local packFrame = self.frame and self.frame:FindFirstChild(pack.buttonName)
		local priceLabel = findTextLabel(packFrame, "PriceLabel")
		local productId = ProductService.DevProducts[pack.productKey]
		if priceLabel and productId then
			local thread = task.spawn(function()
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
				end)
				if not self.alive or priceLabel.Parent == nil then
					return
				end
				if ok and typeof(info) == "table" then
					local price = (info :: any).PriceInRobux
					priceLabel.Text = if typeof(price) == "number" then tostring(price) else "0"
				else
					DebugModule.debugWarn("Failed price lookup for " .. pack.productKey, MODULE_NAME)
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

	local theme = VisualFunctions.NotificationThemes.Default
	if rewardId == "Wins" then
		theme = VisualFunctions.NotificationThemes.Gold
	elseif rewardId == "Rebirth" then
		theme = VisualFunctions.NotificationThemes.Purple
	elseif rewardId == "SpeedSmall" or rewardId == "SpeedLarge" then
		theme = VisualFunctions.NotificationThemes.Blue
	elseif rewardId == "FlameTrail" or rewardId == "FlameKart" then
		theme = VisualFunctions.NotificationThemes.Red
	end

	VisualFunctions.ShowNotification("YOU WIN " .. getRewardName(rewardId :: SpinWheelConfig.RewardId) .. "!", theme.textColor, theme.gradientBottomColor)
end

function SpinWheelUI:spin(result: { [string]: any })
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
		tween.Completed:Wait()
		if not self.alive or not self.isOpen or token ~= self.spinToken then
			return
		end
		RunService.RenderStepped:Wait()
		self:correctRewardAlignment(typedRewardId)
		self.activeTween = nil
		self.spinThread = nil
		self.spinInFlight = false
		self:showResult(result)
		self:updateSpinButton()
		self:startIdleRotation()
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

function SpinWheelUI:open()
	if self.isOpen or not self.frame then
		return
	end
	self:captureVisibility()
	self.isOpen = true
	self.player:SetAttribute("SpinWheelModalOpen", true)
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
	self.isOpen = false
	self.player:SetAttribute("SpinWheelModalOpen", false)
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
			SoundService.PlayGuiSound("Close")
			self:close()
		end))
	end

	if self.spinButton then
		self.maid:GiveTask(self.spinButton.Activated:Connect(function()
			if self.spinInFlight or not self:hasSpinAvailable() then
				return
			end
			self.spinInFlight = true
			self:updateSpinButton()
			local remotes = ReplicatedStorage:WaitForChild("Remotes")
			local remote = remotes:FindFirstChild("SpinWheelRequest")
			if not remote or not remote:IsA("RemoteEvent") then
				self.spinInFlight = false
				self:updateSpinButton()
				return
			end
			remote:FireServer()
		end))
	end

	for _, pack in ipairs(SpinWheelConfig.PurchasePacks) do
		local packFrame = self.frame and self.frame:FindFirstChild(pack.buttonName)
		local buyButton = findGuiButton(packFrame and packFrame:FindFirstChild("BuyButton", true))
		if buyButton then
			self.maid:GiveTask(buyButton.Activated:Connect(function()
				local productId = ProductService.DevProducts[pack.productKey]
				if productId then
					SoundService.PlayGuiSound("Click")
					ProductService.promptProductPurchase(self.player, productId)
				end
			end))
		end
	end

	self.maid:GiveTask(self.player:GetAttributeChangedSignal(SPINS_ATTRIBUTE):Connect(function()
		self:updateSpinButton()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(NEXT_FREE_SPIN_ATTRIBUTE):Connect(function()
		self:updateSpinButton()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("SpinWheelOpenRequested"):Connect(function()
		self:open()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("CurrentXPSpeed"):Connect(function()
		self:refreshRewardPreviews()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("MaxXPSpeed"):Connect(function()
		self:refreshRewardPreviews()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("WinCount"):Connect(function()
		self:refreshRewardPreviews()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("WinMultiplier"):Connect(function()
		self:refreshRewardPreviews()
	end))

	local resultRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("SpinWheelResult")
	if resultRemote and resultRemote:IsA("RemoteEvent") then
		self.maid:GiveTask(resultRemote.OnClientEvent:Connect(function(result: { [string]: any })
			if self.isOpen then
				self:spin(result)
			else
				self.spinInFlight = false
				self:updateSpinButton()
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
	self:updateSpinButton()
	self.frame.Visible = false
	self.frame.Interactable = false
end

function SpinWheelUI:Destroy()
	if not self.alive then
		return
	end
	self.alive = false
	if self.isOpen then
		self:close()
	end
	self:stopIdleRotation()
	self:stopCountdown()
	self:stopAvailabilityWatcher()
	self:stopSpinTween()
	if self.badge then
		self.badge:Destroy()
		self.badge = nil
	end
	self.player:SetAttribute("SpinWheelModalOpen", false)
	self.maid:DoCleaning()
end

return SpinWheelUI
