--!strict

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)

local MouseTooltipController = {}
MouseTooltipController.__index = MouseTooltipController

type TooltipDefinition = {
	description: string | (() -> string),
	isEnabled: ((target: GuiObject) -> boolean)?,
	descriptionForTarget: ((target: GuiObject) -> string)?,
}

type TooltipVisualState = {
	textTransparency: number?,
	imageTransparency: number?,
	backgroundTransparency: number?,
	strokeTransparency: number?,
}

type TooltipPositionCandidate = {
	anchorPoint: Vector2,
	screenPosition: Vector2,
}

type MouseTooltipControllerObject = {
	screenGui: ScreenGui,
	playerGui: PlayerGui?,
	maid: any,
	tooltip: GuiObject?,
	bodyFrame: GuiObject?,
	descriptionLabel: TextLabel?,
	baseTooltipYScale: number,
	baseTooltipYOffset: number,
	baseDisplayOrder: number,
	visualStates: { [Instance]: TooltipVisualState },
	animationTweens: { [Instance]: Tween },
	lastMousePosition: Vector2?,
	boundTargets: { [GuiObject]: TooltipDefinition },
	activeTarget: GuiObject?,
	initialized: boolean,
	alive: boolean,
	tooltipLayerActive: boolean,
}

local MODULE_NAME = "MouseTooltipController"
local SCREEN_PADDING = 6
local DESCRIPTION_VERTICAL_PADDING = 8
local BASE_TOOLTIP_SIZE = UDim2.new(0.13, 0, 0.038, 0)
local REFERENCE_VIEWPORT_SIZE = Vector2.new(1920, 1080)
local TOOLTIP_FADE_ALPHA = 0.82
local MAX_DESCRIPTION_LENGTH =
	#"Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."

local FRIEND_MULTIPLIER_TOOLTIP: TooltipDefinition = {
	description = "Invite a friend! When they join through your invite, you both get a permanent +0.10x Friends Multiplier!",
}

local TOOLTIP_DEFINITIONS: { [string]: TooltipDefinition } = table.freeze({
	FriendMultiplier = FRIEND_MULTIPLIER_TOOLTIP,
	FriendMultiplierFrame = FRIEND_MULTIPLIER_TOOLTIP,
	InviteFriendButtonFrame = FRIEND_MULTIPLIER_TOOLTIP,
	SoundButtonFrame = {
		description = "Toggle music on or off.",
	},
	HapticButtonFrame = {
		description = "Toggle haptic feedback on or off.",
	},
	KartButtonFrame = {
		description = "Browse event karts and paid rides, then buy or equip your favorite!",
	},
	PlaytimeButtonFrame = {
		description = "Play to unlock 12 gifts across an hour! Claim XP Speed, Wins, Levels, and a bonus bundle.",
	},
	RebirthButtonFrame = {
		description = "Reach max level to rebirth! Your Speed resets, but you gain +0.5x permanent XP multiplier. Wins stay!",
	},
	ShopButtonFrame = {
		description = "Browse new karts, Win boosts, and XP treadmills to power up your runs!",
	},
	TrailButtonFrame = {
		description = "Choose a trail to show off and boost your XP Speed! Unlock trails with Wins, spins, or event rewards.",
	},
	PetsButtonFrame = {
		description = "Open your pet inventory to equip, merge, or delete pets.",
	},
	DeleteSelectedButton = {
		description = "Select pets for batch deletion. You will confirm before they are removed.",
	},
	MergeButton = {
		description = "Merge matching unequipped pets into higher-star pets.",
	},
	EquipBestButton = {
		description = "Equip your strongest pets, replacing your current equipped set.",
	},
	UnequipAllButton = {
		description = "Unequip all pets. They stay safely in your inventory.",
	},
	PetMultiplierFrame = {
		description = "Shows the combined XP bonus from your equipped pets.",
	},
	LuckMultiplierFrame = {
		description = "Upgrade pet luck to improve your odds of rarer Lucky Block pets.",
	},
	TrollButtonFrame = {
		description = "Watch another runner, then prank them with paid actions like Freeze, Slow, or Jumpscare!",
	},
	VerifyButtonFrame = {
		description = "Join our Roblox group for free Speed and Wins, then swing back every 4 hours to claim again!",
	},
	PremiumMultiplierFrame = {
		description = function(): string
			local localPlayer = Players.LocalPlayer
			if localPlayer and localPlayer.MembershipType == Enum.MembershipType.Premium then
				return "Premium gives you a permanent 1.25x XP Speed and Wins boost!"
			end
			return "Go Premium and enjoy a permanent 1.25x boost to XP Speed and Wins!"
		end,
	},
	TempSpeedBoostBuyFrame = {
		description = "Double your XP Speed for a while and level up faster!",
	},
	TempWinBoostBuyFrame = {
		description = "Double your Wins for a while and stack up rewards!",
	},
	SpinWheelButtonFrame = {
		description = "Spin the wheel for free turns and surprise rewards!",
	},
	DailyRewardButtonFrame = {
		description = "Come back each day to grab your next reward!",
	},
	DisableWaveButtonFrame = {
		description = function(): string
			local disableWavesConfig = CoreConfig.disableWaves
			local configuredDuration = if typeof(disableWavesConfig) == "table"
					and typeof(disableWavesConfig.durationSeconds) == "number"
				then disableWavesConfig.durationSeconds
				else 15
			local durationSeconds = math.max(1, math.floor(configuredDuration))
			return ("Take a wave break: waves stay off for %d seconds!"):format(durationSeconds)
		end,
	},
	StarterPackButtonFrame = {
		description = "Start strong with 10,000 XP Speed and 250 Wins!",
	},
	WinStreak = {
		description = "Reach stage 20 to grow your streak by +0.2x! Dying resets it.",
	},
	EventLabel = {
		description = "Check the event details and see what you can win!",
		isEnabled = function(target: GuiObject): boolean
			return target:GetAttribute("EventTooltipEnabled") == true
		end,
		descriptionForTarget = function(target: GuiObject): string
			local card = target:FindFirstAncestorWhichIsA("Frame")
			local description = card and card:GetAttribute("EventTooltipDescription")
			return if typeof(description) == "string" and description ~= ""
				then description
				else "Check the event details and see what you can win!"
		end,
	},
})

local HIDDEN_TOOLTIP_CHILDREN = table.freeze({
	"Image",
	"ProductImage",
	"PriceLabel",
	"CountdownLabel",
	"BuyButton",
	"WatchAdButton",
	"ExitButton",
})

for targetName, definition in pairs(TOOLTIP_DEFINITIONS) do
	local description = if typeof(definition.description) == "function"
		then definition.description()
		else definition.description
	assert(#description <= MAX_DESCRIPTION_LENGTH, ("Tooltip description exceeds length limit: %s"):format(targetName))
end

local function findGuiObject(root: Instance, name: string): GuiObject?
	local instance = root:FindFirstChild(name, true)
	if instance and instance:IsA("GuiObject") then
		return instance
	end

	return nil
end

local function findTextLabel(root: Instance, name: string): TextLabel?
	local instance = root:FindFirstChild(name, true)
	if instance and instance:IsA("TextLabel") then
		return instance
	end

	return nil
end

function MouseTooltipController.new(screenGui: ScreenGui): MouseTooltipControllerObject
	assert(screenGui:IsA("ScreenGui"), "MouseTooltipController requires a ScreenGui root")

	return setmetatable({
		screenGui = screenGui,
		playerGui = screenGui:FindFirstAncestorOfClass("PlayerGui") :: PlayerGui?,
		maid = Maid.new(),
		tooltip = nil,
		bodyFrame = nil,
		descriptionLabel = nil,
		baseTooltipYScale = 0,
		baseTooltipYOffset = 0,
		baseDisplayOrder = screenGui.DisplayOrder,
		visualStates = {},
		animationTweens = {},
		lastMousePosition = nil,
		boundTargets = {},
		activeTarget = nil,
		initialized = false,
		alive = true,
		tooltipLayerActive = false,
	}, MouseTooltipController) :: MouseTooltipControllerObject
end

function MouseTooltipController._getScreenBounds(self: MouseTooltipControllerObject): (Vector2, Vector2, Vector2)
	local screenGuiPosition = self.screenGui.AbsolutePosition
	local screenGuiSize = self.screenGui.AbsoluteSize
	if screenGuiSize.X > 0 and screenGuiSize.Y > 0 then
		return screenGuiPosition, screenGuiSize, screenGuiPosition
	end

	local camera = Workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then
		return Vector2.zero, camera.ViewportSize, screenGuiPosition
	end

	return screenGuiPosition, self.screenGui.AbsoluteSize, screenGuiPosition
end

function MouseTooltipController._resizeToDescription(self: MouseTooltipControllerObject, screenSize: Vector2)
	local tooltip = self.tooltip
	local descriptionLabel = self.descriptionLabel
	if not tooltip or not descriptionLabel or descriptionLabel.Text == "" then
		return
	end
	local labelWidth = descriptionLabel.AbsoluteSize.X
	if labelWidth <= 0 then
		return
	end

	local viewportTextScale = math.min(
		screenSize.X / REFERENCE_VIEWPORT_SIZE.X,
		screenSize.Y / REFERENCE_VIEWPORT_SIZE.Y,
		1
	)
	local measurementTextSize = math.max(1, math.floor(descriptionLabel.TextSize * viewportTextScale + 0.5))
	local measuredText = TextService:GetTextSize(
		descriptionLabel.Text,
		measurementTextSize,
		descriptionLabel.Font,
		Vector2.new(labelWidth, math.huge)
	)
	local singleLineText = TextService:GetTextSize(
		"Ag",
		measurementTextSize,
		descriptionLabel.Font,
		Vector2.new(labelWidth, math.huge)
	)
	local labelHeightScale = math.max(descriptionLabel.Size.Y.Scale, 0.01)
	local baseHeight = self.baseTooltipYScale * screenSize.Y + self.baseTooltipYOffset
	local requiredHeight = math.ceil(measuredText.Y / labelHeightScale)
	if measuredText.Y > singleLineText.Y then
		requiredHeight += DESCRIPTION_VERTICAL_PADDING
	end
	local maximumHeight = math.max(baseHeight, screenSize.Y - (SCREEN_PADDING * 2))
	local targetHeight = math.clamp(math.max(baseHeight, requiredHeight), baseHeight, maximumHeight)
	local targetYScale = targetHeight / screenSize.Y

	local currentSize = tooltip.Size
	if math.abs(currentSize.Y.Scale - targetYScale) > 0.001 or currentSize.Y.Offset ~= 0 then
		tooltip.Size = UDim2.new(currentSize.X.Scale, currentSize.X.Offset, targetYScale, 0)
	end
end

function MouseTooltipController._updatePosition(self: MouseTooltipControllerObject)
	if not self.alive or not self.tooltip or not self.tooltip.Visible then
		return
	end

	local _, screenSize = self:_getScreenBounds()
	if screenSize.X <= 0 or screenSize.Y <= 0 then
		return
	end

	self:_resizeToDescription(screenSize)
	local mouseScreenPosition = UserInputService:GetMouseLocation()
	if mouseScreenPosition == Vector2.zero and self.lastMousePosition then
		mouseScreenPosition = self.lastMousePosition
	end
	local tooltipSize = self.tooltip.AbsoluteSize
	if tooltipSize.X <= 0 or tooltipSize.Y <= 0 then
		return
	end

	local topLeft: TooltipPositionCandidate = {
		anchorPoint = Vector2.new(1, 1),
		screenPosition = mouseScreenPosition,
	}
	local topRight: TooltipPositionCandidate = {
		anchorPoint = Vector2.new(0, 1),
		screenPosition = mouseScreenPosition,
	}
	local bottomLeft: TooltipPositionCandidate = {
		anchorPoint = Vector2.new(1, 0),
		screenPosition = mouseScreenPosition,
	}
	local bottomRight: TooltipPositionCandidate = {
		anchorPoint = Vector2.new(0, 0),
		screenPosition = mouseScreenPosition,
	}

	local isNearRightEdge = mouseScreenPosition.X > screenSize.X * 0.5
	local isNearBottomEdge = mouseScreenPosition.Y > screenSize.Y * 0.5
	local candidates: { TooltipPositionCandidate } = if isNearBottomEdge
		then if isNearRightEdge
			then { topLeft, topRight, bottomLeft, bottomRight }
			else { topRight, topLeft, bottomRight, bottomLeft }
		else if isNearRightEdge
			then { bottomLeft, bottomRight, topLeft, topRight }
			else { bottomRight, bottomLeft, topRight, topLeft }

	local function getAnchorOffset(anchorPoint: Vector2): Vector2
		return Vector2.new(tooltipSize.X * anchorPoint.X, tooltipSize.Y * anchorPoint.Y)
	end

	local function fits(candidate: TooltipPositionCandidate): boolean
		local topLeftPosition = candidate.screenPosition - getAnchorOffset(candidate.anchorPoint)
		local bottomRightPosition = topLeftPosition + tooltipSize
		return topLeftPosition.X >= SCREEN_PADDING
			and topLeftPosition.Y >= SCREEN_PADDING
			and bottomRightPosition.X <= screenSize.X - SCREEN_PADDING
			and bottomRightPosition.Y <= screenSize.Y - SCREEN_PADDING
	end

	local function clippingScore(candidate: TooltipPositionCandidate): number
		local topLeftPosition = candidate.screenPosition - getAnchorOffset(candidate.anchorPoint)
		local bottomRightPosition = topLeftPosition + tooltipSize
		return math.max(0, SCREEN_PADDING - topLeftPosition.X)
			+ math.max(0, SCREEN_PADDING - topLeftPosition.Y)
			+ math.max(0, bottomRightPosition.X - (screenSize.X - SCREEN_PADDING))
			+ math.max(0, bottomRightPosition.Y - (screenSize.Y - SCREEN_PADDING))
	end

	local chosenCandidate: TooltipPositionCandidate? = nil
	local leastClippedCandidate = candidates[1]
	local leastClippedScore = clippingScore(leastClippedCandidate)
	for _, candidate in ipairs(candidates) do
		if fits(candidate) then
			chosenCandidate = candidate
			break
		end

		local score = clippingScore(candidate)
		if score < leastClippedScore then
			leastClippedCandidate = candidate
			leastClippedScore = score
		end
	end

	local resolvedCandidate = chosenCandidate or leastClippedCandidate
	self.tooltip.AnchorPoint = resolvedCandidate.anchorPoint
	self.tooltip.Position = UDim2.fromOffset(resolvedCandidate.screenPosition.X, resolvedCandidate.screenPosition.Y)
end

function MouseTooltipController._cancelTooltipAnimations(self: MouseTooltipControllerObject)
	local activeTweens = table.clone(self.animationTweens)
	table.clear(self.animationTweens)
	for _, tween in pairs(activeTweens) do
		tween:Cancel()
	end
end

function MouseTooltipController._getFadedTransparency(original: number, alpha: number): number
	return math.clamp(original + ((1 - original) * alpha), 0, 1)
end

function MouseTooltipController._setTooltipVisualTransparency(self: MouseTooltipControllerObject, alpha: number)
	for instance, visualState in pairs(self.visualStates) do
		if not instance.Parent then
			continue
		end

		if
			visualState.textTransparency ~= nil
			and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
		then
			instance.TextTransparency = self._getFadedTransparency(visualState.textTransparency, alpha)
		end
		if visualState.imageTransparency ~= nil and (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
			instance.ImageTransparency = self._getFadedTransparency(visualState.imageTransparency, alpha)
		end
		if visualState.backgroundTransparency ~= nil and instance:IsA("GuiObject") then
			instance.BackgroundTransparency = self._getFadedTransparency(visualState.backgroundTransparency, alpha)
		end
		if visualState.strokeTransparency ~= nil and instance:IsA("UIStroke") then
			instance.Transparency = self._getFadedTransparency(visualState.strokeTransparency, alpha)
		end
	end
end

function MouseTooltipController._getTooltipVisualGoals(
	self: MouseTooltipControllerObject,
	visualState: TooltipVisualState,
	alpha: number
): { [string]: any }
	local goals: { [string]: any } = {}
	if visualState.textTransparency ~= nil then
		goals.TextTransparency = self._getFadedTransparency(visualState.textTransparency, alpha)
	end
	if visualState.imageTransparency ~= nil then
		goals.ImageTransparency = self._getFadedTransparency(visualState.imageTransparency, alpha)
	end
	if visualState.backgroundTransparency ~= nil then
		goals.BackgroundTransparency = self._getFadedTransparency(visualState.backgroundTransparency, alpha)
	end
	if visualState.strokeTransparency ~= nil then
		goals.Transparency = self._getFadedTransparency(visualState.strokeTransparency, alpha)
	end
	return goals
end

function MouseTooltipController._playTooltipTween(
	self: MouseTooltipControllerObject,
	instance: Instance,
	tweenInfo: TweenInfo,
	goals: { [string]: any }
): Tween
	local previousTween = self.animationTweens[instance]
	if previousTween then
		previousTween:Cancel()
	end

	local tween = TweenService:Create(instance, tweenInfo, goals)
	self.animationTweens[instance] = tween
	local completedConnection: RBXScriptConnection?
	completedConnection = tween.Completed:Connect(function()
		if completedConnection then
			completedConnection:Disconnect()
			completedConnection = nil
		end
		if self.animationTweens[instance] == tween then
			self.animationTweens[instance] = nil
		end
	end)
	tween:Play()
	return tween
end

function MouseTooltipController._restoreTooltipLayer(self: MouseTooltipControllerObject)
	if self.tooltipLayerActive then
		self.screenGui.DisplayOrder = self.baseDisplayOrder
		self.tooltipLayerActive = false
	end
end

function MouseTooltipController._hide(self: MouseTooltipControllerObject, target: GuiObject?)
	if not self.alive or self.activeTarget ~= target then
		return
	end

	self.activeTarget = nil
	local tooltip = self.tooltip
	if not tooltip then
		self:_restoreTooltipLayer()
		return
	end

	self:_cancelTooltipAnimations()
	if not tooltip.Visible then
		self:_restoreTooltipLayer()
		return
	end

	local descriptionLabel = self.descriptionLabel
	local descriptionVisualState = if descriptionLabel then self.visualStates[descriptionLabel] else nil
	if not descriptionLabel or not descriptionVisualState then
		tooltip.Visible = false
		self:_setTooltipVisualTransparency(0)
		self:_restoreTooltipLayer()
		return
	end

	local closeGoals = self:_getTooltipVisualGoals(descriptionVisualState, TOOLTIP_FADE_ALPHA)
	local closeTween = self:_playTooltipTween(descriptionLabel, TweenConfig.TooltipClose, closeGoals)
	local completedConnection: RBXScriptConnection?
	completedConnection = closeTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if completedConnection then
			completedConnection:Disconnect()
			completedConnection = nil
		end
		if
			playbackState ~= Enum.PlaybackState.Completed
			or not self.alive
			or self.activeTarget ~= nil
			or self.tooltip ~= tooltip
		then
			return
		end
		tooltip.Visible = false
		self:_setTooltipVisualTransparency(0)
		self:_restoreTooltipLayer()
	end)

	for instance, visualState in pairs(self.visualStates) do
		if instance == descriptionLabel then
			continue
		end
		local goals = self:_getTooltipVisualGoals(visualState, TOOLTIP_FADE_ALPHA)
		if next(goals) then
			self:_playTooltipTween(instance, TweenConfig.TooltipClose, goals)
		end
	end
end

function MouseTooltipController._raiseTooltipLayer(self: MouseTooltipControllerObject)
	if self.tooltipLayerActive then
		return
	end

	local highestDisplayOrder = self.baseDisplayOrder
	local playerGui = self.playerGui
	if playerGui then
		for _, child in ipairs(playerGui:GetChildren()) do
			if child:IsA("ScreenGui") and child ~= self.screenGui then
				highestDisplayOrder = math.max(highestDisplayOrder, child.DisplayOrder)
			end
		end
	end

	self.screenGui.DisplayOrder = highestDisplayOrder + 1
	self.tooltipLayerActive = true
end

function MouseTooltipController._animateTooltipSwitch(
	self: MouseTooltipControllerObject,
	target: GuiObject,
	description: string
)
	local tooltip = self.tooltip
	local descriptionLabel = self.descriptionLabel
	if not tooltip or not descriptionLabel then
		return
	end

	self:_updatePosition()
	local descriptionVisualState = self.visualStates[descriptionLabel]
	if not descriptionVisualState then
		return
	end
	local closeGoals = self:_getTooltipVisualGoals(descriptionVisualState, TOOLTIP_FADE_ALPHA)
	local closeTween = self:_playTooltipTween(descriptionLabel, TweenConfig.TooltipClose, closeGoals)
	local completedConnection: RBXScriptConnection?
	completedConnection = closeTween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if completedConnection then
			completedConnection:Disconnect()
			completedConnection = nil
		end
		if
			playbackState ~= Enum.PlaybackState.Completed
			or not self.alive
			or self.activeTarget ~= target
			or self.tooltip ~= tooltip
		then
			return
		end

		descriptionLabel.Text = description
		self:_updatePosition()
		self:_setTooltipVisualTransparency(TOOLTIP_FADE_ALPHA)
		for instance, visualState in pairs(self.visualStates) do
			local goals = self:_getTooltipVisualGoals(visualState, 0)
			if next(goals) then
				self:_playTooltipTween(instance, TweenConfig.TooltipOpen, goals)
			end
		end
	end)

	for instance, visualState in pairs(self.visualStates) do
		if instance == descriptionLabel then
			continue
		end
		local goals = self:_getTooltipVisualGoals(visualState, TOOLTIP_FADE_ALPHA)
		if next(goals) then
			self:_playTooltipTween(instance, TweenConfig.TooltipClose, goals)
		end
	end
end

function MouseTooltipController._show(self: MouseTooltipControllerObject, target: GuiObject)
	if not self.alive or self.screenGui:GetAttribute("PostLoadingStartupComplete") ~= true then
		return
	end

	local definition = self.boundTargets[target]
	if not definition or not self.tooltip or not self.descriptionLabel then
		return
	end
	if definition.isEnabled and not definition.isEnabled(target) then
		return
	end

	local description = if definition.descriptionForTarget
		then definition.descriptionForTarget(target)
		elseif typeof(definition.description) == "function" then definition.description()
		else definition.description
	local wasVisible = self.tooltip.Visible
	self:_cancelTooltipAnimations()
	self.activeTarget = target
	self:_raiseTooltipLayer()
	self.tooltip.Visible = true
	if wasVisible then
		self:_animateTooltipSwitch(target, description)
		return
	else
		self.descriptionLabel.Text = description
		self:_setTooltipVisualTransparency(TOOLTIP_FADE_ALPHA)
		for instance, visualState in pairs(self.visualStates) do
			local goals: { [string]: any } = {}
			if visualState.textTransparency ~= nil then
				goals.TextTransparency = visualState.textTransparency
			end
			if visualState.imageTransparency ~= nil then
				goals.ImageTransparency = visualState.imageTransparency
			end
			if visualState.backgroundTransparency ~= nil then
				goals.BackgroundTransparency = visualState.backgroundTransparency
			end
			if visualState.strokeTransparency ~= nil then
				goals.Transparency = visualState.strokeTransparency
			end
			if next(goals) then
				self:_playTooltipTween(instance, TweenConfig.TooltipOpen, goals)
			end
		end
	end
	self:_updatePosition()
end

function MouseTooltipController._bindTarget(
	self: MouseTooltipControllerObject,
	target: GuiObject,
	definition: TooltipDefinition
)
	if self.boundTargets[target] then
		return
	end

	self.boundTargets[target] = definition
	self.maid:GiveTask(target.MouseEnter:Connect(function(x: number, y: number)
		self.lastMousePosition = Vector2.new(x, y)
		self:_show(target)
	end))
	self.maid:GiveTask(target.MouseLeave:Connect(function()
		self.lastMousePosition = nil
		self:_hide(target)
	end))
	self.maid:GiveTask(target.MouseMoved:Connect(function(x: number, y: number)
		self.lastMousePosition = Vector2.new(x, y)
		if self.activeTarget == target then
			self:_updatePosition()
		end
	end))
	self.maid:GiveTask(target.Destroying:Connect(function()
		self.boundTargets[target] = nil
		self:_hide(target)
	end))
	if definition.isEnabled then
		self.maid:GiveTask(target:GetAttributeChangedSignal("EventTooltipEnabled"):Connect(function()
			if self.activeTarget == target and not definition.isEnabled(target) then
				self:_hide(target)
			end
		end))
	end
end

function MouseTooltipController._bindMainGuiTarget(self: MouseTooltipControllerObject, target: GuiObject)
	local definition = TOOLTIP_DEFINITIONS[target.Name]
	if definition then
		self:_bindTarget(target, definition)
	end
end

function MouseTooltipController._configureTooltip(self: MouseTooltipControllerObject): boolean
	local tooltip = findGuiObject(self.screenGui, "MouseTooltip")
	if not tooltip then
		DebugModule.debugWarn("MouseTooltip frame was not found", MODULE_NAME)
		return false
	end

	local bodyFrame = findGuiObject(tooltip, "BodyFrame")
	local descriptionLabel = findTextLabel(tooltip, "DescriptionLabel")
	if not bodyFrame or not descriptionLabel then
		DebugModule.debugWarn("MouseTooltip requires BodyFrame and DescriptionLabel", MODULE_NAME)
		return false
	end

	self.tooltip = tooltip
	self.bodyFrame = bodyFrame
	self.descriptionLabel = descriptionLabel
	self.baseTooltipYScale = BASE_TOOLTIP_SIZE.Y.Scale
	self.baseTooltipYOffset = BASE_TOOLTIP_SIZE.Y.Offset
	local tooltipScale = tooltip:FindFirstChild("TooltipAnimationScale")
	if tooltipScale and tooltipScale:IsA("UIScale") then
		tooltipScale:Destroy()
	end
	table.clear(self.visualStates)
	local function captureVisualState(instance: Instance)
		local visualState: TooltipVisualState = {}
		local hasVisualState = false
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			visualState.textTransparency = instance.TextTransparency
			hasVisualState = true
		end
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			visualState.imageTransparency = instance.ImageTransparency
			hasVisualState = true
		end
		if instance:IsA("GuiObject") then
			visualState.backgroundTransparency = instance.BackgroundTransparency
			hasVisualState = true
		end
		if instance:IsA("UIStroke") then
			visualState.strokeTransparency = instance.Transparency
			hasVisualState = true
		end
		if hasVisualState then
			self.visualStates[instance] = visualState
		end
	end
	captureVisualState(tooltip)
	for _, descendant in ipairs(tooltip:GetDescendants()) do
		captureVisualState(descendant)
	end
	local configuredSize = tooltip.Size
	tooltip.Size = UDim2.new(
		configuredSize.X.Scale,
		configuredSize.X.Offset,
		BASE_TOOLTIP_SIZE.Y.Scale,
		BASE_TOOLTIP_SIZE.Y.Offset
	)

	tooltip.AnchorPoint = Vector2.new(0.5, 0.5)
	tooltip.Active = false
	tooltip.Interactable = false
	tooltip.Visible = false
	tooltip.ZIndex = 100
	bodyFrame.Visible = true
	descriptionLabel.Visible = true
	for _, descendant in ipairs(tooltip:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = 100
		end
	end

	for _, childName in ipairs(HIDDEN_TOOLTIP_CHILDREN) do
		local child = tooltip:FindFirstChild(childName, true)
		if child and child:IsA("GuiObject") then
			child.Visible = false
		end
	end

	return true
end

function MouseTooltipController.Init(self: MouseTooltipControllerObject)
	if self.initialized then
		return
	end
	self.initialized = true

	if UserInputService.TouchEnabled then
		local tooltip = findGuiObject(self.screenGui, "MouseTooltip")
		if tooltip then
			tooltip.Visible = false
		end
		return
	end

	if not self:_configureTooltip() then
		return
	end

	for _, descendant in ipairs(self.screenGui:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			self:_bindMainGuiTarget(descendant)
		end
	end

	self.maid:GiveTask(self.screenGui.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("GuiObject") then
			self:_bindMainGuiTarget(descendant)
		end
	end))
	self.maid:GiveTask(self.screenGui:GetAttributeChangedSignal("PostLoadingStartupComplete"):Connect(function()
		local activeTarget = self.activeTarget
		if self.screenGui:GetAttribute("PostLoadingStartupComplete") ~= true and activeTarget then
			self:_hide(activeTarget)
		end
	end))

	self.maid:GiveTask(UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			self:_updatePosition()
		end
	end))
	self.maid:GiveTask(self.screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updatePosition()
	end))
	self.maid:GiveTask(self.screenGui:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		self:_updatePosition()
	end))
	self.maid:GiveTask(self.tooltip:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_updatePosition()
	end))
	self.maid:GiveTask(self.tooltip:GetPropertyChangedSignal("Size"):Connect(function()
		self:_updatePosition()
	end))

	DebugModule.debugPrint("Mouse tooltip initialized", MODULE_NAME)
end

function MouseTooltipController.Destroy(self: MouseTooltipControllerObject)
	if not self.alive then
		return
	end

	self.alive = false
	self:_cancelTooltipAnimations()
	self.maid:DoCleaning()
	self:_restoreTooltipLayer()
	self.boundTargets = {}
	self.activeTarget = nil
	self.lastMousePosition = nil
	if self.tooltip then
		self:_setTooltipVisualTransparency(0)
		self.tooltip.Visible = false
	end
	self.tooltip = nil
	self.bodyFrame = nil
	self.descriptionLabel = nil
	table.clear(self.visualStates)
	table.clear(self.animationTweens)
end

return MouseTooltipController
