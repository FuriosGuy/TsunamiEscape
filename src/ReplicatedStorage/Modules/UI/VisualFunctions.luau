local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local FramerateManager = require(ReplicatedStorage.Modules.FramerateManager)
local NumberFormatting = require(ReplicatedStorage.Modules.Shared:WaitForChild("NumberFormatting"))
local NotificationLayoutController = require(ReplicatedStorage.Modules.UI.MainGUI.NotificationLayoutController)

local VisualFunctions = {}

type NotificationRequest = {
	message: string,
	textColor: Color3?,
	gradientBottomColor: Color3?,
	notificationKey: string?,
	style: "Standard" | "QuickFade",
}

-- Table to store references to specific UI frames
VisualFunctions.ActiveFrameGroup = {
	RebirthFrame = nil :: GuiObject?,
	RebirthConfirmFrame = nil :: GuiObject?,
	TrailFrame = nil :: GuiObject?,
	KartFrame = nil :: GuiObject?,
	ShopFrame = nil :: GuiObject?,
	VerifyFrame = nil :: GuiObject?,
	TrollFrame = nil :: GuiObject?,
	DailyRewardFrame = nil :: GuiObject?,
	RewardsFrame = nil :: GuiObject?,
	SpinWheelFrame = nil :: GuiObject?,
	PetFrame = nil :: GuiObject?,
}

VisualFunctions.HUD = {
	LevelsBarFrame = nil :: Frame?,
	SpeedMultiFrame = nil :: Frame?,
	BottomRightGridFrame = nil :: GuiObject?,
	SpeedBuyFrame = nil :: Frame?,
	RightSideButtonsFrame = nil :: Frame?,
	XPProgressFrame = nil :: Frame?,
	LevelProgressFrame = nil :: Frame?,
	LevelUpFrame = nil :: Frame?,
	NotificationFrame = nil :: GuiObject?,
	CustomSpeedFrame = nil :: Frame?,
	CustomSpeedTextBox = nil :: TextBox?,

	-- Floating System Templates
	FloatingFrame = nil :: Frame?,
	Float_CurrentSpeedFrame = nil :: Frame?,
	Float_CurrentBloodMoonWinFrame = nil :: Frame?,
	EventCurrentWinsTarget = nil :: GuiObject?,
	DisableWaveButtonFrame = nil :: Frame?,
	DisableWavePriceLabel = nil :: TextLabel?,
	DisableWaveCountdownLabel = nil :: TextLabel?,
	ReturnToStageFrame = nil :: GuiObject?,
	ReturnToStagePriceLabel = nil :: TextLabel?,
	ReturnToStageCountdownLabel = nil :: TextLabel?,

	-- Multiplier Shop
	MultiplierSpeedProductFrame_Parent = nil :: Frame?,
	MultiplierSpeedPriceLabel = nil :: TextLabel?,
	MultiplierSpeedPromptButton = nil :: GuiButton?,

	-- Win System Templates
	WinCountFrame = nil :: Frame?,
	Float_CurrentWinFrame = nil :: Frame?,
}

VisualFunctions.Labels = {
	XPSpeedLabel = nil :: TextLabel?,
	CurrentLevelLabel = nil :: TextLabel?,
	RebirthMultiLabel = nil :: TextLabel?,
	TrailMultiplierLabel = nil :: TextLabel?,
	FriendMultiplierLabel = nil :: TextLabel?,
	XPAllSpeedLabel = nil :: TextLabel?,
	LevelNeededLabel = nil :: TextLabel?,

	-- Rebirth Preview Labels
	BeforeMultiplierLabel = nil :: TextLabel?,
	BeforeMaxLevelLabel = nil :: TextLabel?,
	AfterMultiplierLabel = nil :: TextLabel?,
	AfterMaxLevelLabel = nil :: TextLabel?,

	-- Level Up Visuals
	LevelBeforeLabel = nil :: TextLabel?,
	LevelAfterLabel = nil :: TextLabel?,
	WalkspeedBeforeLabel = nil :: TextLabel?,
	WalkspeedAfterLabel = nil :: TextLabel?,
	NotificationTextLabel = nil :: TextLabel?,

	-- Custom Speed Visuals
	MaxSpeedLabel = nil :: TextLabel?,

	-- Win System Labels
	WinsLabel = nil :: TextLabel?,

	-- XP Product Labels
	Xp100KValueLabel = nil :: GuiObject?,
	Xp1MValueLabel = nil :: GuiObject?,
	Xp10MValueLabel = nil :: GuiObject?,
}

local COMPACT_NUMBER_THRESHOLD_LENGTH = 20
local XP_LABEL_COMPACT_DIGITS_THRESHOLD = 9

local function formatWithCommasOrCompact(value: number): string
	local commaText = NumberFormatting.FormatWithCommas(value)
	if string.len(commaText) > COMPACT_NUMBER_THRESHOLD_LENGTH then
		return NumberFormatting.FormatNumber(value)
	end

	return commaText
end

local function formatXPLabelValue(value: number): string
	local rounded = math.round(math.abs(value))
	if rounded >= (10 ^ (XP_LABEL_COMPACT_DIGITS_THRESHOLD - 1)) then
		return NumberFormatting.FormatNumber(value)
	end

	return NumberFormatting.FormatWithCommas(value)
end

local function formatPreciseNumber(value: number): string
	if math.abs(value) >= 1000 then
		return NumberFormatting.FormatNumber(value)
	end

	local rounded = math.round(value * 100) / 100
	if rounded == math.round(rounded) then
		return NumberFormatting.FormatWithCommas(rounded)
	end

	local text = string.format("%.2f", rounded)
	text = text:gsub("%.00$", "")
	text = text:gsub("(%..-)0$", "%1")
	return text
end

local function distributeValue(totalValue: number, splitCount: number): { number }
	local distributed = {}
	local roundedTotal = math.round(totalValue)

	if math.abs(totalValue - roundedTotal) < 0.001 then
		local baseAmount = math.floor(roundedTotal / splitCount)
		local remainder = roundedTotal % splitCount

		for i = 1, splitCount do
			local amount = baseAmount
			if i > splitCount - remainder then
				amount += 1
			end
			table.insert(distributed, amount)
		end

		return distributed
	end

	local currentSum = 0
	for i = 1, splitCount do
		local nextSum = totalValue * (i / splitCount)
		table.insert(distributed, nextSum - currentSum)
		currentSum = nextSum
	end

	return distributed
end

function VisualFunctions.FormatNumber(val: number): string
	return NumberFormatting.FormatNumber(val)
end

-- Internal state to track hover status and parameters for click return logic
local HoverStates: {
	[GuiObject]: {
		isHovering: boolean,
		hoverSize: UDim2,
		hoverColor: Color3,
		colorMultiplier: number?,
		rotateImage: GuiObject?,
		targetRotation: number,
		originalSize: UDim2,
		originalColor: Color3,
		hoverScale: number,
	},
} = setmetatable(
	{},
	{ __mode = "k" }
) :: {
	[GuiObject]: {
		isHovering: boolean,
		hoverSize: UDim2,
		hoverColor: Color3,
		colorMultiplier: number?,
		rotateImage: GuiObject?,
		targetRotation: number,
		originalSize: UDim2,
		originalColor: Color3,
		hoverScale: number,
	},
}
local RainbowGradientMaids: { [UIGradient]: Maid } = {}
local RainbowGradientStates: { [UIGradient]: { colors: { Color3 }, speed: number } } = setmetatable(
	{},
	{ __mode = "k" }
) :: {
	[UIGradient]: { colors: { Color3 }, speed: number },
}
local HoverSetupBindings: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: { [GuiObject]: boolean }
local ClickSetupBindings: { [GuiObject]: boolean } = setmetatable({}, { __mode = "k" }) :: { [GuiObject]: boolean }
local ClickPulseActions: { [GuiObject]: () -> () } = setmetatable({}, { __mode = "k" }) :: { [GuiObject]: () -> () }
local ClickPulseThreads: { [GuiObject]: thread } = setmetatable({}, { __mode = "k" }) :: { [GuiObject]: thread }
local AnimationMaids: { [Instance]: Maid } = setmetatable({}, { __mode = "k" }) :: { [Instance]: Maid }
local FrameShadowColorMaids: { [CanvasGroup]: Maid } = setmetatable({}, { __mode = "k" }) :: { [CanvasGroup]: Maid }
local FrameShadowColorUpdates: { [CanvasGroup]: () -> () } = setmetatable({}, { __mode = "k" }) :: {
	[CanvasGroup]: () -> (),
}
local InteractionMaids: { [GuiObject]: Maid } = setmetatable({}, { __mode = "k" }) :: { [GuiObject]: Maid }
local activeNotificationKey: string? = nil
local currentNotificationRequest: NotificationRequest? = nil
local notificationSuppressionRoot: Instance? = nil
local notificationSuppressionConnection: RBXScriptConnection? = nil
local notificationSuppressed = false
local LUCKY_BLOCK_CUTSCENE_ACTIVE_ATTRIBUTE = "LuckyBlockCutsceneActive"
local RAINBOW_GRADIENT_UPDATE_INTERVAL = 1 / 30
local rainbowGradientUpdaterBound = false
local rainbowGradientUpdateAccumulator = 0

local function clearReferenceTable(map: { [any]: any })
	for key in pairs(map) do
		map[key] = nil
	end
end

local function buildRainbowColorSequence(colors: { Color3 }, speed: number): ColorSequence
	local colorCount = #colors
	if colorCount == 0 then
		return ColorSequence.new(Color3.new(1, 1, 1))
	elseif colorCount == 1 then
		return ColorSequence.new(colors[1])
	end

	local currentTime = tick()
	local offset = (currentTime * speed) % 1
	local keypoints = table.create(colorCount)

	for i = 1, colorCount do
		local ratio = (i - 1) / (colorCount - 1)
		local shiftedRatio = (ratio + offset) % 1
		keypoints[i] = { time = shiftedRatio, color = colors[i] }
	end

	table.sort(keypoints, function(a, b)
		return a.time < b.time
	end)

	if keypoints[1].time > 0 then
		local first = keypoints[1]
		local last = keypoints[#keypoints]
		local lerpFactor = (0 - last.time + 1) / (first.time - last.time + 1)
		local color = last.color:Lerp(first.color, lerpFactor)
		table.insert(keypoints, 1, { time = 0, color = color })
	end
	if keypoints[#keypoints].time < 1 then
		local first = keypoints[1]
		local last = keypoints[#keypoints]
		local lerpFactor = (1 - last.time) / (first.time + 1 - last.time)
		local color = last.color:Lerp(first.color, lerpFactor)
		table.insert(keypoints, { time = 1, color = color })
	end

	local finalKeypoints = table.create(#keypoints)
	for index, keypoint in ipairs(keypoints) do
		finalKeypoints[index] = ColorSequenceKeypoint.new(keypoint.time, keypoint.color)
	end

	return ColorSequence.new(finalKeypoints)
end

local function stopRainbowGradientUpdater()
	if not rainbowGradientUpdaterBound then
		return
	end

	rainbowGradientUpdaterBound = false
	FramerateManager:UnbindFromUpdate(VisualFunctions._UpdateRainbowGradients)
end

local function isGradientVisible(gradient: UIGradient): boolean
	local current: Instance? = gradient
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end

	return true
end

function VisualFunctions._UpdateRainbowGradients(deltaTime: number)
	rainbowGradientUpdateAccumulator += deltaTime
	if rainbowGradientUpdateAccumulator < RAINBOW_GRADIENT_UPDATE_INTERVAL then
		return
	end
	rainbowGradientUpdateAccumulator = 0

	local activeCount = 0
	local staleGradients = {}

	for gradient, state in pairs(RainbowGradientStates) do
		if gradient.Parent == nil or RainbowGradientMaids[gradient] == nil then
			table.insert(staleGradients, gradient)
		else
			activeCount += 1
			if isGradientVisible(gradient) then
				gradient.Color = buildRainbowColorSequence(state.colors, state.speed)
			end
		end
	end

	for _, gradient in ipairs(staleGradients) do
		local gradientMaid = RainbowGradientMaids[gradient]
		RainbowGradientStates[gradient] = nil
		RainbowGradientMaids[gradient] = nil
		if gradientMaid then
			gradientMaid:DoCleaning()
		end
	end

	if activeCount == 0 then
		stopRainbowGradientUpdater()
	end
end

local function ensureRainbowGradientUpdater()
	if rainbowGradientUpdaterBound then
		return
	end

	if not FramerateManager:IsRunning() then
		FramerateManager:Start()
	end

	rainbowGradientUpdateAccumulator = 0
	rainbowGradientUpdaterBound = true
	FramerateManager:BindToUpdate(VisualFunctions._UpdateRainbowGradients)
end

local function replaceAnimationMaid(instance: Instance): Maid
	local existingMaid = AnimationMaids[instance]
	if existingMaid then
		existingMaid:DoCleaning()
		AnimationMaids[instance] = nil
	end

	local animationMaid = Maid.new()
	AnimationMaids[instance] = animationMaid
	local cleaned = false

	local function cleanupAnimation()
		if cleaned then
			return
		end

		cleaned = true
		if AnimationMaids[instance] == animationMaid then
			AnimationMaids[instance] = nil
		end
		animationMaid:DoCleaning()
	end

	animationMaid:GiveTask(instance.Destroying:Connect(cleanupAnimation))
	animationMaid:GiveTask(instance.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupAnimation()
		end
	end))

	return animationMaid
end

local function clearAnimationMaid(instance: Instance)
	local animationMaid = AnimationMaids[instance]
	if not animationMaid then
		return
	end

	AnimationMaids[instance] = nil
	animationMaid:DoCleaning()
end

local function getInteractionMaid(frame: GuiObject): Maid
	local existingMaid = InteractionMaids[frame]
	if existingMaid then
		return existingMaid
	end

	local interactionMaid = Maid.new()
	InteractionMaids[frame] = interactionMaid
	local cleaned = false

	local function cleanupInteraction()
		if cleaned then
			return
		end

		cleaned = true
		if InteractionMaids[frame] == interactionMaid then
			InteractionMaids[frame] = nil
		end
		HoverStates[frame] = nil
		HoverSetupBindings[frame] = nil
		ClickSetupBindings[frame] = nil
		ClickPulseActions[frame] = nil
		local pulseThread = ClickPulseThreads[frame]
		ClickPulseThreads[frame] = nil
		if pulseThread and coroutine.status(pulseThread) ~= "dead" then
			pcall(task.cancel, pulseThread)
		end
		interactionMaid:DoCleaning()
	end

	interactionMaid:GiveTask(frame.Destroying:Connect(cleanupInteraction))
	interactionMaid:GiveTask(frame.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupInteraction()
		end
	end))

	return interactionMaid
end

VisualFunctions.NotificationThemes = ColorConfig.UI.NotificationThemes

local function lightenColor(color: Color3, multiplier: number): Color3
	return Color3.new(
		math.clamp(color.R * multiplier, 0, 1),
		math.clamp(color.G * multiplier, 0, 1),
		math.clamp(color.B * multiplier, 0, 1)
	)
end

local function applyColorToDescendants(root: Instance, multiplier: number, isReset: boolean)
	local function applyColor(target: Instance)
		if target:GetAttribute("DynamicVisualState") == true then
			return
		end
		if target:IsA("UIGradient") then
			-- Parent color already tints the gradient output; tinting both compounds darkening.
			return
		end

		local targetProps = {}
		if target:IsA("Frame") or target:IsA("ScrollingFrame") or target:IsA("CanvasGroup") then
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

		if #targetProps == 0 then
			return
		end

		local tweenGoals = {}
		for _, targetProp in ipairs(targetProps) do
			local attributeName = "OriginalColor_" .. targetProp
			local originalColor = target:GetAttribute(attributeName) :: Color3?
			if not originalColor then
				originalColor = (target :: any)[targetProp]
				target:SetAttribute(attributeName, originalColor)
			end

			tweenGoals[targetProp] = if isReset
				then originalColor
				else lightenColor(originalColor or Color3.new(1, 1, 1), multiplier)
		end

		TweenService:Create(target, TweenConfig.HoverColor, tweenGoals):Play()
	end

	applyColor(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		applyColor(descendant)
	end
end

local function getTransparencyProperty(obj: Instance): string?
	if obj:IsA("CanvasGroup") then
		return "GroupTransparency"
	elseif obj:IsA("Frame") or obj:IsA("ScrollingFrame") then
		return "BackgroundTransparency"
	elseif obj:IsA("ViewportFrame") then
		return "ImageTransparency"
	elseif obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		return "TextTransparency"
	elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
		return "ImageTransparency"
	elseif obj:IsA("UIStroke") then
		return "Transparency"
	end
	return nil
end

local function setTransparencyRecursive(root: Instance, alpha: number)
	local function apply(obj: Instance)
		local prop = getTransparencyProperty(obj)
		if not prop then
			return
		end

		local originalAttribute = if obj:IsA("CanvasGroup") then "OriginalGroupTransparency" else "OriginalTransparency"
		local original = obj:GetAttribute(originalAttribute) :: number?
		if original == nil then
			original = (obj :: any)[prop]
			obj:SetAttribute(originalAttribute, original)
		end

		local baseAlpha = original or 0
		if baseAlpha >= 1 then
			return
		end

		local target = baseAlpha + (1 - baseAlpha) * alpha
		local objAny = obj :: any
		objAny[prop] = target

		if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
			local bgOriginal = obj:GetAttribute("OriginalBackgroundTransparency") :: number?
			if bgOriginal == nil then
				bgOriginal = (obj :: any).BackgroundTransparency
				obj:SetAttribute("OriginalBackgroundTransparency", bgOriginal)
			end
			local baseBgAlpha = bgOriginal or 0
			if baseBgAlpha < 1 then
				(obj :: any).BackgroundTransparency = baseBgAlpha + (1 - baseBgAlpha) * alpha
			end
		end
		if obj:IsA("ScrollingFrame") then
			local scrollbarOriginal = obj:GetAttribute("OriginalScrollBarImageTransparency") :: number?
			if scrollbarOriginal == nil then
				scrollbarOriginal = obj.ScrollBarImageTransparency
				obj:SetAttribute("OriginalScrollBarImageTransparency", scrollbarOriginal)
			end
			obj.ScrollBarImageTransparency = scrollbarOriginal + (1 - scrollbarOriginal) * alpha
		end
	end

	apply(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if not descendant:FindFirstAncestorWhichIsA("CanvasGroup") then
			apply(descendant)
		end
	end
end

function VisualFunctions.BindFrameShadowColorSync(canvasGroup: CanvasGroup, sessionMaid: any): ()
	if canvasGroup:GetAttribute("CreateFrameShadow") ~= true then
		return
	end
	local existingMaid = FrameShadowColorMaids[canvasGroup]
	if existingMaid then
		local updateShadowColor = FrameShadowColorUpdates[canvasGroup]
		if updateShadowColor then
			updateShadowColor()
		end
		return
	end

	local main = canvasGroup:FindFirstChild("Main")
	local shadow = canvasGroup:FindFirstChild("Shadow")
	if not main or not main:IsA("GuiObject") or not shadow or not shadow:IsA("GuiObject") then
		return
	end
	local innerStrokes: { UIStroke } = {}
	local isLuckyBlockTierHeader = canvasGroup.Name == "TopFrame"
		and (canvasGroup:FindFirstAncestor("OpenLuckyBlockFrame") ~= nil
			or canvasGroup:FindFirstAncestor("LuckyBlocks") ~= nil)
	if isLuckyBlockTierHeader then
		for _, descendant in ipairs(main:GetDescendants()) do
			if descendant:IsA("UIStroke") and string.find(string.lower(descendant.Name), "inner", 1, true) then
				table.insert(innerStrokes, descendant)
			end
		end
	end

	local syncMaid = Maid.new()
	FrameShadowColorMaids[canvasGroup] = syncMaid
	sessionMaid:GiveTask(syncMaid)
	syncMaid:GiveTask(function()
		if FrameShadowColorMaids[canvasGroup] == syncMaid then
			FrameShadowColorMaids[canvasGroup] = nil
			FrameShadowColorUpdates[canvasGroup] = nil
		end
	end)

	local function updateShadowColor(): ()
		local darkenFactor = canvasGroup:GetAttribute("ShadowDarkenFactor")
		if typeof(darkenFactor) ~= "number" then
			darkenFactor = 0.75
		end
		local backgroundColor = main.BackgroundColor3
		shadow.BackgroundColor3 = backgroundColor:Lerp(Color3.new(0, 0, 0), math.clamp(darkenFactor, 0, 1))
		local luminance = backgroundColor.R * 0.2126 + backgroundColor.G * 0.7152 + backgroundColor.B * 0.0722
		local strokeTransparency = 0.7 + (1 - luminance) * 0.2
		for _, innerStroke in ipairs(innerStrokes) do
			if innerStroke.Parent then
				innerStroke.Transparency = strokeTransparency
			end
		end
	end

	FrameShadowColorUpdates[canvasGroup] = updateShadowColor
	syncMaid:GiveTask(main:GetPropertyChangedSignal("BackgroundColor3"):Connect(updateShadowColor))
	updateShadowColor()
end

local function isRotateTextLabel(instance: Instance): boolean
	return instance:IsA("TextLabel") and string.find(string.lower(instance.Name), "rotate", 1, true) ~= nil
end

local function findRotatingTarget(frame: GuiObject): GuiObject?
	if isRotateTextLabel(frame) then
		return frame
	end

	if
		(frame:IsA("ImageLabel") or frame:IsA("ImageButton"))
		and (frame:GetAttribute("isRotate") ~= nil or frame.Name == "RotateImage")
	then
		return frame
	end

	local directRotateImage = frame:FindFirstChild("RotateImage")
	if directRotateImage and (directRotateImage:IsA("ImageLabel") or directRotateImage:IsA("ImageButton")) then
		return directRotateImage
	end

	for _, descendant in ipairs(frame:GetDescendants()) do
		if
			(descendant:IsA("ImageLabel") or descendant:IsA("ImageButton"))
			and descendant:GetAttribute("isRotate") ~= nil
		then
			return descendant
		end
		if isRotateTextLabel(descendant) then
			return descendant :: TextLabel
		end
	end

	return nil
end

local function toNotificationDisplayText(message: string): string
	return string.upper(message)
end

local function findInteractionUIScale(target: GuiObject): UIScale?
	for _, child in ipairs(target:GetChildren()) do
		if child:IsA("UIScale") and child:GetAttribute("IgnoreInteractionScale") ~= true then
			return child
		end
	end

	return nil
end

function VisualFunctions.SetupFrameHover(
	frame: GuiObject,
	scale: number?,
	rotateScale: number?,
	colorMultiplier: number?
)
	if HoverSetupBindings[frame] == true then
		return
	end
	HoverSetupBindings[frame] = true
	local interactionMaid = getInteractionMaid(frame)

	local target = frame
	if frame.Parent and frame.Parent:IsA("GuiObject") and string.find(frame.Parent.Name, "_Parent") then
		target = frame.Parent :: GuiObject
	end

	local originalSize = target.Size
	local hoverScale = scale or 1.05
	local tweenInfo = TweenConfig.Hover

	if not tweenInfo then
		DebugModule.debugError("TweenConfig.Hover is missing!", nil, "VisualFunctions")
		return
	end

	local hoverSize = UDim2.new(
		originalSize.X.Scale * hoverScale,
		originalSize.X.Offset,
		originalSize.Y.Scale * hoverScale,
		originalSize.Y.Offset
	)

	local rotateImage = findRotatingTarget(frame)
	local targetRotation = rotateScale or 35

	local originalColor = frame.BackgroundColor3
	local mult = colorMultiplier or 1.2
	local hoverColor = lightenColor(originalColor, mult)

	-- Store parameters for click return logic
	HoverStates[frame] = {
		isHovering = false,
		hoverSize = hoverSize,
		hoverColor = hoverColor,
		colorMultiplier = colorMultiplier,
		rotateImage = rotateImage,
		targetRotation = targetRotation,
		originalSize = originalSize,
		originalColor = originalColor,
		hoverScale = hoverScale, -- Store for click return
	}

	local function onHoverEnter()
		if target:GetAttribute("UiDisabled") == true then
			return
		end

		local hoverState = HoverStates[frame]
		if not hoverState then
			return
		end

		if hoverState.isHovering then
			return
		end

		hoverState.isHovering = true
		SoundService.PlayGuiSound("Hover")

		local uiScale = findInteractionUIScale(target)
		if uiScale then
			TweenService:Create(uiScale, tweenInfo, { Scale = hoverScale }):Play()
		else
			TweenService:Create(target, tweenInfo, { Size = hoverSize }):Play()
		end

		if rotateImage then
			TweenService:Create(rotateImage, TweenConfig.Rotate, { Rotation = targetRotation }):Play()
		end
		if colorMultiplier then
			if frame:GetAttribute("DynamicVisualState") ~= true then
				TweenService:Create(frame, TweenConfig.HoverColor, { BackgroundColor3 = hoverState.hoverColor }):Play()
			end
			applyColorToDescendants(target, mult, false)
		end
	end

	local function onHoverLeave()
		if target:GetAttribute("UiDisabled") == true then
			return
		end

		local hoverState = HoverStates[frame]
		if not hoverState then
			return
		end

		hoverState.isHovering = false

		local uiScale = findInteractionUIScale(target)
		if uiScale then
			TweenService:Create(uiScale, tweenInfo, { Scale = 1 }):Play()
		else
			TweenService:Create(target, tweenInfo, { Size = originalSize }):Play()
		end

		if rotateImage then
			TweenService:Create(rotateImage, TweenConfig.Rotate, { Rotation = 0 }):Play()
		end
		if colorMultiplier then
			if frame:GetAttribute("DynamicVisualState") ~= true then
				TweenService:Create(frame, TweenConfig.HoverColor, { BackgroundColor3 = hoverState.originalColor }):Play()
			end
			applyColorToDescendants(target, mult, true)
		end
	end

	local function setupGuiObject(child: Instance)
		if child:IsA("GuiObject") then
			interactionMaid:GiveTask(child.MouseEnter:Connect(onHoverEnter))
			interactionMaid:GiveTask(child.MouseLeave:Connect(onHoverLeave))
		end
	end

	setupGuiObject(frame)
	for _, child in ipairs(frame:GetChildren()) do
		setupGuiObject(child)
	end

	interactionMaid:GiveTask(frame.ChildAdded:Connect(setupGuiObject))
end

function VisualFunctions.SetupFrameClick(
	frame: GuiObject,
	scale: number?,
	rotateScale: number?,
	colorMultiplier: number?
)
	if ClickSetupBindings[frame] == true then
		return
	end
	ClickSetupBindings[frame] = true
	local interactionMaid = getInteractionMaid(frame)

	local target = frame
	if frame.Parent and frame.Parent:IsA("GuiObject") and string.find(frame.Parent.Name, "_Parent") then
		target = frame.Parent :: GuiObject
	end

	local originalSize = target.Size
	local originalColor = frame.BackgroundColor3
	local cScale = scale or 0.9
	local cRotate = rotateScale or -15
	local cColorMult = colorMultiplier or 0.8

	local clickSize = UDim2.new(
		originalSize.X.Scale * cScale,
		originalSize.X.Offset,
		originalSize.Y.Scale * cScale,
		originalSize.Y.Offset
	)

	local function getBaseColor(): Color3
		local state = HoverStates[frame]
		return if state then state.originalColor else originalColor
	end

	local function onMouseDown()
		if target:GetAttribute("UiDisabled") == true then
			return
		end

		local uiScale = findInteractionUIScale(target)
		if uiScale then
			TweenService:Create(uiScale, TweenConfig.Click, { Scale = cScale }):Play()
		else
			TweenService:Create(target, TweenConfig.Click, { Size = clickSize }):Play()
		end

		if colorMultiplier then
			local clickColor = lightenColor(getBaseColor(), cColorMult)
			if frame:GetAttribute("DynamicVisualState") ~= true then
				TweenService:Create(frame, TweenConfig.Click, { BackgroundColor3 = clickColor }):Play()
			end
			applyColorToDescendants(target, cColorMult, false)
		end

		local state = HoverStates[frame]
		if state and state.rotateImage then
			TweenService:Create(state.rotateImage, TweenConfig.Click, { Rotation = cRotate }):Play()
		end
	end

	local function onMouseUp()
		if target:GetAttribute("UiDisabled") == true then
			return
		end

		local state = HoverStates[frame]
		local uiScale = findInteractionUIScale(target)

		if state and state.isHovering then
			if uiScale then
				TweenService:Create(uiScale, TweenConfig.Hover, { Scale = state.hoverScale or 1.05 }):Play()
			else
				TweenService:Create(target, TweenConfig.Hover, { Size = state.hoverSize }):Play()
			end

			if state.colorMultiplier then
				if frame:GetAttribute("DynamicVisualState") ~= true then
					TweenService:Create(frame, TweenConfig.HoverColor, { BackgroundColor3 = state.hoverColor }):Play()
				end
				applyColorToDescendants(target, state.colorMultiplier or 1.2, false)
			end
			if state.rotateImage then
				TweenService:Create(state.rotateImage, TweenConfig.Rotate, { Rotation = state.targetRotation }):Play()
			end
		else
			if uiScale then
				TweenService:Create(uiScale, TweenConfig.Click, { Scale = 1 }):Play()
			else
				TweenService:Create(target, TweenConfig.Click, { Size = originalSize }):Play()
			end

			if colorMultiplier then
				if frame:GetAttribute("DynamicVisualState") ~= true then
					TweenService:Create(frame, TweenConfig.Click, { BackgroundColor3 = getBaseColor() }):Play()
				end
				applyColorToDescendants(target, 1, true)
			end
			if state and state.rotateImage then
				TweenService:Create(state.rotateImage, TweenConfig.Rotate, { Rotation = 0 }):Play()
			end
		end
	end

	ClickPulseActions[frame] = function()
		if not frame.Parent or target:GetAttribute("UiDisabled") == true then
			return
		end

		local currentThread = ClickPulseThreads[frame]
		if currentThread and coroutine.status(currentThread) ~= "dead" then
			pcall(task.cancel, currentThread)
		end

		onMouseDown()
		local releaseThread: thread
		releaseThread = task.delay(0.12, function()
			if ClickPulseThreads[frame] ~= releaseThread then
				return
			end
			ClickPulseThreads[frame] = nil
			if frame.Parent then
				onMouseUp()
			end
		end)
		ClickPulseThreads[frame] = releaseThread
	end

	local function setupButton(child: Instance)
		if child:IsA("GuiButton") then
			interactionMaid:GiveTask(child.MouseButton1Down:Connect(onMouseDown))
			interactionMaid:GiveTask(child.MouseButton1Up:Connect(onMouseUp))
			interactionMaid:GiveTask(child.InputBegan:Connect(function(input)
				local isTouch = input.UserInputType == Enum.UserInputType.Touch
				local isGamepadConfirm = input.UserInputType.Name:find("Gamepad") ~= nil
					and input.KeyCode == Enum.KeyCode.ButtonA
				if isTouch or isGamepadConfirm then
					onMouseDown()
				end
			end))
			interactionMaid:GiveTask(child.InputEnded:Connect(function(input)
				local isTouch = input.UserInputType == Enum.UserInputType.Touch
				local isGamepadConfirm = input.UserInputType.Name:find("Gamepad") ~= nil
					and input.KeyCode == Enum.KeyCode.ButtonA
				if isTouch or isGamepadConfirm then
					onMouseUp()
				end
			end))

			interactionMaid:GiveTask(child.MouseLeave:Connect(function()
				onMouseUp()
			end))
		end
	end

	setupButton(frame)
	for _, child in ipairs(frame:GetChildren()) do
		setupButton(child)
	end

	interactionMaid:GiveTask(frame.ChildAdded:Connect(setupButton))
end

function VisualFunctions.PlayFrameClick(frame: GuiObject)
	local clickPulseAction = ClickPulseActions[frame]
	if clickPulseAction then
		clickPulseAction()
	end
end

type NotificationBadgePulseStep = {
	scale: number,
	rotationOffset: number,
	xOffset: number,
	duration: number,
}

local NOTIFICATION_BADGE_PULSE_COOLDOWN = 2.4
local NOTIFICATION_BADGE_SHAKE_OFFSET = 3
local NOTIFICATION_BADGE_PULSE_STEPS: { NotificationBadgePulseStep } = {
	{ scale = 1.24, rotationOffset = 0, xOffset = 0, duration = 0.18 },
	{ scale = 1.1, rotationOffset = -10, xOffset = -NOTIFICATION_BADGE_SHAKE_OFFSET, duration = 0.1 },
	{ scale = 1.18, rotationOffset = 10, xOffset = NOTIFICATION_BADGE_SHAKE_OFFSET, duration = 0.1 },
	{ scale = 1, rotationOffset = 0, xOffset = 0, duration = 0.12 },
}

function VisualFunctions.StartNotificationBadgeAnimation(badge: GuiObject): () -> ()
	local scaleInstance = badge:FindFirstChild("NotificationBadgePulseScale")
	if not scaleInstance or not scaleInstance:IsA("UIScale") then
		local pulseScale = Instance.new("UIScale")
		pulseScale.Name = "NotificationBadgePulseScale"
		pulseScale.Scale = 1
		pulseScale.Parent = badge
		scaleInstance = pulseScale
	end

	local badgeScale = scaleInstance :: UIScale
	local originalPosition = badge.Position
	local originalRotation = badge.Rotation
	local activeTweens: { Tween } = {}
	local animationThread: thread? = nil
	local isAlive = true

	local function playStep(step: NotificationBadgePulseStep): boolean
		if not isAlive or badge.Parent == nil then
			return false
		end

		local tweenInfo = TweenInfo.new(step.duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local scaleTween = TweenService:Create(badgeScale, tweenInfo, { Scale = step.scale })
		local movementTween = TweenService:Create(badge, tweenInfo, {
			Position = originalPosition + UDim2.fromOffset(step.xOffset, 0),
			Rotation = originalRotation + step.rotationOffset,
		})
		activeTweens = { scaleTween, movementTween }
		scaleTween:Play()
		movementTween:Play()

		local playbackState = scaleTween.Completed:Wait()
		if activeTweens[1] == scaleTween then
			table.clear(activeTweens)
		end
		return playbackState == Enum.PlaybackState.Completed and isAlive and badge.Parent ~= nil
	end

	animationThread = task.spawn(function()
		local firstPulse = true
		while isAlive and badge.Parent do
			if firstPulse then
				badgeScale.Scale = 0.72
				firstPulse = false
			end

			for _, step in ipairs(NOTIFICATION_BADGE_PULSE_STEPS) do
				if not playStep(step) then
					break
				end
			end

			if isAlive and badge.Parent then
				task.wait(NOTIFICATION_BADGE_PULSE_COOLDOWN)
			end
		end

		if animationThread == coroutine.running() then
			animationThread = nil
		end
	end)

	return function(): ()
		if not isAlive then
			return
		end
		isAlive = false
		for _, tween in ipairs(activeTweens) do
			tween:Cancel()
		end
		table.clear(activeTweens)

		local threadToCancel = animationThread
		animationThread = nil
		if threadToCancel and threadToCancel ~= coroutine.running() and coroutine.status(threadToCancel) ~= "dead" then
			pcall(task.cancel, threadToCancel)
		end

		if badgeScale.Parent then
			badgeScale.Scale = 1
		end
		if badge.Parent then
			badge.Position = originalPosition
			badge.Rotation = originalRotation
		end
	end
end

local function resetHoverAndClickVisualState(root: Instance)
	for trackedFrame, state in pairs(HoverStates) do
		if trackedFrame == root or trackedFrame:IsDescendantOf(root) then
			state.isHovering = false

			local target = trackedFrame
			if
				trackedFrame.Parent
				and trackedFrame.Parent:IsA("GuiObject")
				and string.find(trackedFrame.Parent.Name, "_Parent")
			then
				target = trackedFrame.Parent :: GuiObject
			end

			local uiScale = findInteractionUIScale(target)
			if uiScale then
				uiScale.Scale = 1
			else
				target.Size = state.originalSize
			end

			trackedFrame.BackgroundColor3 = state.originalColor
			if state.rotateImage then
				state.rotateImage.Rotation = 0
			end
		end
	end
end

function VisualFunctions.SetFrameDisabledState(frame: GuiObject?, isDisabled: boolean, colorMultiplier: number?)
	if not frame then
		return
	end

	if isDisabled then
		-- Force-reset hover/click visuals so disabled darkening wins even if cursor is still over the frame.
		resetHoverAndClickVisualState(frame)
	end

	local mult = colorMultiplier or 0.75
	local originalColor = frame:GetAttribute("OriginalDisabledBaseColor") :: Color3?
	if not originalColor then
		originalColor = frame:GetAttribute("OriginalColor_BackgroundColor3") :: Color3?
	end
	if not originalColor then
		originalColor = frame.BackgroundColor3
	end
	frame:SetAttribute("OriginalDisabledBaseColor", originalColor)
	frame:SetAttribute("OriginalColor_BackgroundColor3", originalColor)

	frame.Interactable = not isDisabled
	frame:SetAttribute("UiDisabled", isDisabled)
	if frame:GetAttribute("DynamicVisualState") == true then
		frame.BackgroundColor3 = if isDisabled then lightenColor(originalColor, mult) else originalColor
	end
	applyColorToDescendants(frame, if isDisabled then mult else 1, not isDisabled)

	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			descendant.Interactable = not isDisabled
			descendant.Active = not isDisabled
			descendant.AutoButtonColor = not isDisabled
			descendant.Selectable = not isDisabled
		end
	end
end

function VisualFunctions.SetTextLabelDisabledState(label: TextLabel?, isDisabled: boolean, colorMultiplier: number?)
	if not label then
		return
	end

	applyColorToDescendants(label, if isDisabled then colorMultiplier or 0.75 else 1, not isDisabled)
end

function VisualFunctions.SetFrameInteractableState(frame: GuiObject?, isInteractable: boolean)
	if not frame then
		return
	end

	if not isInteractable then
		resetHoverAndClickVisualState(frame)
	end

	frame.Interactable = isInteractable
	frame:SetAttribute("UiDisabled", not isInteractable)

	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			descendant.Interactable = isInteractable
			descendant.Active = isInteractable
			descendant.AutoButtonColor = isInteractable
			descendant.Selectable = isInteractable
		end
	end
end

function VisualFunctions.RefreshFrameInteractionColors(frame: GuiObject?)
	if not frame then
		return
	end

	local state = HoverStates[frame]
	if not state then
		return
	end

	local currentColor = frame.BackgroundColor3
	state.originalColor = currentColor
	state.hoverColor = lightenColor(currentColor, state.colorMultiplier or 1.2)
	frame:SetAttribute("OriginalDisabledBaseColor", currentColor)
	frame:SetAttribute("OriginalColor_BackgroundColor3", currentColor)
	if state.isHovering and state.colorMultiplier then
		frame.BackgroundColor3 = state.hoverColor
	end
end

function VisualFunctions.OpenWindow(frame: GuiObject)
	local originalSize = frame:GetAttribute("OriginalSize") :: UDim2? or frame.Size
	local originalPos = frame:GetAttribute("OriginalPosition") :: UDim2? or frame.Position

	if not frame:GetAttribute("OriginalSize") then
		frame:SetAttribute("OriginalSize", originalSize)
		frame:SetAttribute("OriginalPosition", originalPos)
	end

	-- Start scaled down, slightly below
	frame.Size =
		UDim2.new(originalSize.X.Scale * 0.5, originalSize.X.Offset, originalSize.Y.Scale * 0.5, originalSize.Y.Offset)
	frame.Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset, 1, 0)
	setTransparencyRecursive(frame, 1)
	frame.Visible = true
	frame.Interactable = false
	local animationMaid = replaceAnimationMaid(frame)

	local sizeTween = TweenService:Create(frame, TweenConfig.WindowOpen, {
		Size = originalSize,
		Position = originalPos,
	})

	-- Animate transparency back to original
	local t = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		if frame.Parent == nil then
			connection:Disconnect()
			return
		end

		t = math.min(1, t + dt / 0.4)
		setTransparencyRecursive(frame, 1 - t)
		if t >= 1 then
			connection:Disconnect()
			frame.Interactable = true
		end
	end)
	animationMaid:GiveTask(connection)
	animationMaid:GiveTask(sizeTween)

	sizeTween:Play()
end

function VisualFunctions.CloseWindow(frame: GuiObject)
	local originalSize = frame:GetAttribute("OriginalSize") :: UDim2? or frame.Size
	local originalPos = frame:GetAttribute("OriginalPosition") :: UDim2? or frame.Position
	local closeSize =
		UDim2.new(originalSize.X.Scale * 1.2, originalSize.X.Offset, originalSize.Y.Scale * 1.2, originalSize.Y.Offset)

	frame.Interactable = false
	local animationMaid = replaceAnimationMaid(frame)

	local sizeTween = TweenService:Create(frame, TweenConfig.WindowClose, {
		Size = closeSize,
		Position = UDim2.new(originalPos.X.Scale, originalPos.X.Offset, 0.35, 0),
	})

	-- Animate transparency to 1
	local t = 0
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		if frame.Parent == nil then
			connection:Disconnect()
			return
		end

		t = math.min(1, t + dt / 0.3)
		setTransparencyRecursive(frame, t)
		if t >= 1 then
			connection:Disconnect()
			frame.Visible = false
			-- Restore original state for next open
			frame.Size = originalSize
			frame.Position = originalPos
			setTransparencyRecursive(frame, 0)
		end
	end)
	animationMaid:GiveTask(connection)
	animationMaid:GiveTask(sizeTween)

	sizeTween:Play()

	return sizeTween.Completed
end

function VisualFunctions.SetupLightRay(image: ImageLabel)
	local tweenInfo = TweenConfig.LinearLoop
	if not tweenInfo then
		DebugModule.debugError("TweenConfig.LinearLoop is missing!", nil, "VisualFunctions")
		return
	end

	image.Rotation = 0
	local tween = TweenService:Create(image, tweenInfo, { Rotation = 360 })
	tween:Play()
end

function VisualFunctions.SetupPulsate(guiObject: GuiObject, scale: number?)
	local targetScale = scale or 1.1
	local tweenInfo = TweenConfig.Pulsate

	if not tweenInfo then
		DebugModule.debugError("TweenConfig.Pulsate is missing!", nil, "VisualFunctions")
		return
	end

	local originalSize = guiObject.Size
	local pulsateSize = UDim2.new(
		originalSize.X.Scale * targetScale,
		originalSize.X.Offset,
		originalSize.Y.Scale * targetScale,
		originalSize.Y.Offset
	)

	local tween = TweenService:Create(guiObject, tweenInfo, { Size = pulsateSize })
	tween:Play()
end

function VisualFunctions.SetupLuckyBlockBackgroundMotion(
	image: ImageLabel | ImageButton,
	maid: any,
	isAlive: () -> boolean
): ()
	local originalRotation = image.Rotation
	local scale = image:FindFirstChild("LuckyBlockBackgroundMotionScale")
	local createdScale = scale == nil
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "LuckyBlockBackgroundMotionScale"
		scale.Parent = image
	end
	if not scale:IsA("UIScale") then
		return
	end
	local originalScale = scale.Scale
	local activeTween: Tween? = nil
	local rotations = { -9, 9, -6, 6, 0 }

	maid:GiveTask(function()
		if activeTween then
			activeTween:Cancel()
			activeTween:Destroy()
			activeTween = nil
		end
		if image.Parent then
			image.Rotation = originalRotation
		end
		if scale.Parent then
			if createdScale then
				scale:Destroy()
			else
				scale.Scale = originalScale
			end
		end
	end)

	maid:GiveSpawnTask(task.spawn(function()
		local function isVisible(): boolean
			local current: Instance? = image
			while current do
				if current:IsA("GuiObject") and not current.Visible then
					return false
				elseif current:IsA("ScreenGui") and not current.Enabled then
					return false
				end
				current = current.Parent
			end
			return true
		end

		local function tweenTo(instance: Instance, tweenInfo: TweenInfo, goal: { [string]: any }): boolean
			local tween = TweenService:Create(instance, tweenInfo, goal)
			activeTween = tween
			tween:Play()
			local playbackState = tween.Completed:Wait()
			tween:Destroy()
			if activeTween == tween then
				activeTween = nil
			end
			return playbackState == Enum.PlaybackState.Completed
		end

		while isAlive() and image.Parent do
			if not isVisible() then
				task.wait(0.1)
				continue
			end

			for _, rotationOffset in ipairs(rotations) do
				if not isAlive() or not image.Parent or not isVisible() then
					break
				end
				if not tweenTo(
					image,
					TweenInfo.new(0.065, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Rotation = originalRotation + rotationOffset }
				) then
					break
				end
			end

			if isAlive() and image.Parent and isVisible() then
				tweenTo(scale, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
					Scale = originalScale * 1.04,
				})
				tweenTo(scale, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
					Scale = originalScale,
				})
			end
			task.wait(2.6)
		end
	end))
end

function VisualFunctions.SetupRainbowGradient(gradient: UIGradient)
	local existingMaid = RainbowGradientMaids[gradient]
	if existingMaid then
		existingMaid:DoCleaning()
		RainbowGradientMaids[gradient] = nil
		RainbowGradientStates[gradient] = nil
	end

	local gradientMaid = Maid.new()
	RainbowGradientMaids[gradient] = gradientMaid
	local cleaned = false

	local function cleanupGradient()
		if cleaned then
			return
		end

		cleaned = true
		if RainbowGradientMaids[gradient] == gradientMaid then
			RainbowGradientMaids[gradient] = nil
		end
		RainbowGradientStates[gradient] = nil
		gradientMaid:DoCleaning()

		if next(RainbowGradientStates) == nil then
			stopRainbowGradientUpdater()
		end
	end

	local colors = {
		Color3.fromHex("#FF0000"),
		Color3.fromHex("#FFFF00"),
		Color3.fromHex("#00FF00"),
		Color3.fromHex("#00FFFF"),
		Color3.fromHex("#0000FF"),
		Color3.fromHex("#FF00FF"),
		Color3.fromHex("#FF0000"),
	}

	local speed = 0.5
	RainbowGradientStates[gradient] = {
		colors = colors,
		speed = speed,
	}
	gradient.Color = buildRainbowColorSequence(colors, speed)
	ensureRainbowGradientUpdater()

	gradientMaid:GiveTask(gradient.Destroying:Connect(cleanupGradient))
	gradientMaid:GiveTask(gradient.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupGradient()
		end
	end))
end

function VisualFunctions.SetupRotatingGradient(gradient: UIGradient)
	local sequence = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, Color3.fromHex("#FF0000")),
		ColorSequenceKeypoint.new(0.17, Color3.fromHex("#FFFF00")),
		ColorSequenceKeypoint.new(0.33, Color3.fromHex("#00FF00")),
		ColorSequenceKeypoint.new(0.50, Color3.fromHex("#00FFFF")),
		ColorSequenceKeypoint.new(0.66, Color3.fromHex("#0000FF")),
		ColorSequenceKeypoint.new(0.83, Color3.fromHex("#FF00FF")),
		ColorSequenceKeypoint.new(1.00, Color3.fromHex("#FF0000")),
	})

	gradient.Color = sequence

	local tweenInfo = TweenConfig.RotatingGradient
	local tween = TweenService:Create(gradient, tweenInfo, { Rotation = 360 })

	tween:Play()
end

function VisualFunctions.UpdateXPLabel(current: number, max: number)
	local label = VisualFunctions.Labels.XPSpeedLabel
	if label then
		label.Text = string.format("%s/%s", formatXPLabelValue(current), formatXPLabelValue(max))
	end
end

function VisualFunctions.UpdateLevelLabel(level: number, maxLevel: number)
	local label = VisualFunctions.Labels.CurrentLevelLabel
	if label then
		if level >= maxLevel then
			label.Text = string.format("Level %d (MAX)", level)
		else
			label.Text = "Level " .. tostring(level)
		end
	end
end

function VisualFunctions.UpdateRebirthMultiLabel(multi: number)
	local label = VisualFunctions.Labels.RebirthMultiLabel
	if label then
		label.Text = string.format("%.2fx Multiplier (Rebirth)", multi)
	end
end

function VisualFunctions.UpdateTrailMultiplierLabel(
	trailName: string?,
	multi: number?,
	textColor: Color3?,
	gradientBottomColor: Color3?
)
	local label = VisualFunctions.Labels.TrailMultiplierLabel
	local frame = VisualFunctions.HUD.SpeedMultiFrame
	if not label or not frame then
		return
	end

	if not trailName or not multi or trailName == "" or trailName == "None" then
		label.Visible = false
		return
	end

	label.Visible = true
	label.Text = string.format("%.2fx Multiplier (Trail)", multi)
	if textColor then
		label.TextColor3 = textColor
	end

	local labelGradient = label:FindFirstChildOfClass("UIGradient")
	if labelGradient and gradientBottomColor then
		labelGradient.Rotation = 90
		labelGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, gradientBottomColor),
		})
	end
end

function VisualFunctions.UpdateFriendMultiplierLabel(multiplier: number)
	local label = VisualFunctions.Labels.FriendMultiplierLabel
	if label then
		label.Visible = true
		label.Text = string.format("%.2fx", multiplier)
	end
end

function VisualFunctions.UpdateAllXPLabel(total: number)
	local label = VisualFunctions.Labels.XPAllSpeedLabel
	if label then
		label.Text = string.format("%s Speed", formatWithCommasOrCompact(total))
	end
end

function VisualFunctions.UpdateXPProgressBar(current: number, max: number)
	local progressFrame = VisualFunctions.HUD.XPProgressFrame
	if not progressFrame then
		return
	end

	local ratio = math.clamp(current / max, 0, 1)
	local targetSize = UDim2.new(ratio, 0, 1, 0)

	TweenService:Create(progressFrame, TweenConfig.ProgressBar, {
		Size = targetSize,
	}):Play()
end

function VisualFunctions.UpdateLevelProgressBar(current: number, max: number)
	local progressFrame = VisualFunctions.HUD.LevelProgressFrame
	if not progressFrame then
		return
	end

	local ratio = math.clamp(current / max, 0, 1)
	local targetSize = UDim2.new(ratio, 0, 1, 0)

	TweenService:Create(progressFrame, TweenConfig.ProgressBar, {
		Size = targetSize,
	}):Play()
end

function VisualFunctions.UpdateLevelNeededLabel(current: number, max: number)
	local label = VisualFunctions.Labels.LevelNeededLabel
	if label then
		label.Text = string.format("%d/%d", current, max)
	end
end

function VisualFunctions.UpdateRebirthPreview(
	currentMult: number,
	nextMult: number,
	currentMaxLvl: number,
	nextMaxLvl: number
)
	local labels = VisualFunctions.Labels

	if labels.BeforeMultiplierLabel then
		labels.BeforeMultiplierLabel.Text = string.format("%.2fx", currentMult)
	end
	if labels.AfterMultiplierLabel then
		labels.AfterMultiplierLabel.Text = string.format("%.2fx", nextMult)
	end
	if labels.BeforeMaxLevelLabel then
		labels.BeforeMaxLevelLabel.Text = string.format("Lvl %d", currentMaxLvl)
	end
	if labels.AfterMaxLevelLabel then
		labels.AfterMaxLevelLabel.Text = string.format("Lvl %d", nextMaxLvl)
	end
end

function VisualFunctions.UpdateMaxSpeedLabel(max: number)
	local label = VisualFunctions.Labels.MaxSpeedLabel
	if label then
		label.Text = string.format("MAX: %d", max)
	end
end

function VisualFunctions.UpdateWinLabel(total: number)
	local label = VisualFunctions.Labels.WinsLabel
	if label then
		label.Text = formatWithCommasOrCompact(total)
	end
end

--[[
	Displays floating "+value" text that spreads outward from a center point.
    Supports value splitting and random directional movement.
]]
function VisualFunctions.CreateFloatingText(
	template: Frame?,
	totalValue: number,
	splitCount: number,
	config: {
		AngleStep: number?,
		SpawnPos: UDim2?,
		Bounds: { Min: number, Max: number }?,
		Lifetime: number?,
		TargetFrame: GuiObject?,
		IntegerOnly: boolean?,
		PlayPopSound: boolean?,
		TextColor: Color3?,
		GradientBottomColor: Color3?,
		ImageColor: Color3?,
		ImageAssetId: string?,
	}?
)
	local container = VisualFunctions.HUD.FloatingFrame
	if not template or not container then
		return
	end

	local angleStep = config and config.AngleStep or 5
	local spawnPos = config and config.SpawnPos or UDim2.fromScale(0.5, 0.5)
	local bounds = config and config.Bounds or { Min = 0.45, Max = 0.5 } -- Min/Max distance from center
	local lifetime = config and config.Lifetime or 0.8
	local targetFrame = config and config.TargetFrame or nil
	local integerOnly = config and config.IntegerOnly == true or false

	local function getTargetPos(): UDim2?
		if not targetFrame then
			return nil
		end

		local containerSize = container.AbsoluteSize
		if containerSize.X <= 0 or containerSize.Y <= 0 then
			return nil
		end

		local frameCenter = targetFrame.AbsolutePosition + (targetFrame.AbsoluteSize / 2)
		local containerOrigin = container.AbsolutePosition
		local relativeCenter = frameCenter - containerOrigin

		return UDim2.fromScale(relativeCenter.X / containerSize.X, relativeCenter.Y / containerSize.Y)
	end

	local distributed = distributeValue(if integerOnly then math.round(totalValue) else totalValue, splitCount)
	local splitStagger = if targetFrame then 0.18 else 0.05

	for i, rewardAmount in ipairs(distributed) do
		local popupMaid = Maid.new()
		local popupThread = task.spawn(function()
			local amount = rewardAmount
			if integerOnly then
				amount = math.round(amount)
			end
			if amount <= 0 then
				return
			end

			local clone = template:Clone()
			clone.Name = "FloatingPopup"
			clone.Position = spawnPos
			clone.AnchorPoint = Vector2.new(0.5, 0.5)
			clone.Visible = true
			for _, descendant in ipairs(clone:GetDescendants()) do
				if descendant:IsA("GuiObject") then
					descendant.Visible = true
				end
			end
			popupMaid:GiveTask(clone.Destroying:Connect(function()
				popupMaid:DoCleaning()
			end))

			local label = clone:FindFirstChildWhichIsA("TextLabel", true)
			if label then
				if integerOnly then
					label.Text = "+" .. formatWithCommasOrCompact(amount)
				else
					label.Text = "+" .. formatPreciseNumber(amount)
				end
				if config and config.TextColor then
					label.TextColor3 = config.TextColor
				end
				if config and config.GradientBottomColor then
					local gradient = label:FindFirstChildWhichIsA("UIGradient", true)
					if gradient then
						local keypoints = gradient.Color.Keypoints
						if #keypoints > 0 then
							local updatedKeypoints = table.clone(keypoints)
							local lastKeypoint = updatedKeypoints[#updatedKeypoints]
							updatedKeypoints[#updatedKeypoints] = ColorSequenceKeypoint.new(
								lastKeypoint.Time,
								config.GradientBottomColor
							)
							gradient.Color = ColorSequence.new(updatedKeypoints)
						end
					end
				end
			end

			local image = clone:FindFirstChildWhichIsA("ImageLabel", true)
			if image then
				image.Visible = true
				if config and config.ImageAssetId then
					image.Image = config.ImageAssetId
				end
				if config and config.ImageColor then
					image.ImageColor3 = config.ImageColor
				end
			end

			clone.Parent = container

			-- Calculate balanced target using Polar Coordinates (Angle + Distance)
			local randomAngle = math.rad(math.random(0, math.floor(360 / angleStep)) * angleStep)
			local distance = math.random(math.floor(bounds.Min * 1000), math.floor(bounds.Max * 1000)) / 1000

			local targetX = spawnPos.X.Scale + math.cos(randomAngle) * distance
			local targetY = spawnPos.Y.Scale + math.sin(randomAngle) * distance

			local targetPos = UDim2.fromScale(targetX, targetY)
			local finalTargetPos = getTargetPos()

			-- Initial State
			local canvasGroup = clone:IsA("CanvasGroup")
			if canvasGroup then
				(clone :: CanvasGroup).GroupTransparency = 1
			else
				setTransparencyRecursive(clone, 1)
			end
			clone.Size = UDim2.fromScale(0.3, 0.3)

			-- Appear Tween
			local appearInfo = TweenConfig.WithDuration(lifetime * 0.3, TweenConfig.RemoteEffectAppear)
			local moveInfo = TweenConfig.WithDuration(lifetime, TweenConfig.RemoteEffectMove)

			local appearGoals = {
				Size = template.Size,
			}
			if canvasGroup then
				(appearGoals :: any).GroupTransparency = 0
			end
			TweenService:Create(clone, appearInfo, appearGoals):Play()

			if not canvasGroup then
				for _, desc in ipairs(clone:GetDescendants()) do
					local prop = getTransparencyProperty(desc)
					if prop then
						TweenService:Create(desc, appearInfo, { [prop] = 0 }):Play()
					end
				end
			end

			local spreadDuration = lifetime * 0.6
			local collectDuration = if finalTargetPos then lifetime * 0.25 else 0
			local disappearDuration = if finalTargetPos then lifetime * 0.15 else lifetime * 0.4

			TweenService:Create(clone, moveInfo, { Position = targetPos }):Play()
			task.wait(spreadDuration)

			if finalTargetPos then
				local collectInfo = TweenConfig.WithDuration(collectDuration, TweenConfig.RemoteEffectCollect)
				local collectGoals = {
					Position = finalTargetPos,
				}
				if canvasGroup then
					(collectGoals :: any).GroupTransparency = 1
				end

				local collectTween = TweenService:Create(clone, collectInfo, collectGoals)
				collectTween:Play()

				replaceAnimationMaid(clone)
				if not config or config.PlayPopSound ~= false then
					local popThread = task.delay(math.max(collectDuration * 0.85, 0.01), function()
						if clone.Parent then
							SoundService.PlayGuiSound("Pop")
						end
					end)
					popupMaid:GiveTask(popThread)
				end

				if not canvasGroup then
					for _, desc in ipairs(clone:GetDescendants()) do
						local prop = getTransparencyProperty(desc)
						if prop then
							TweenService:Create(desc, collectInfo, { [prop] = 1 }):Play()
						end
					end
				end

				task.wait(collectDuration)
			end

			-- Disappear Tween
			local disappearInfo = TweenConfig.WithDuration(disappearDuration, TweenConfig.RemoteEffectDisappear)
			local disappearGoals = {}
			if canvasGroup then
				(disappearGoals :: any).GroupTransparency = 1
			end
			TweenService:Create(clone, disappearInfo, disappearGoals):Play()

			if not canvasGroup then
				for _, desc in ipairs(clone:GetDescendants()) do
					local prop = getTransparencyProperty(desc)
					if prop then
						TweenService:Create(desc, disappearInfo, { [prop] = 1 }):Play()
					end
				end
			end

			task.wait(disappearDuration)
			clone:Destroy()
		end)
		popupMaid:GiveTask(popupThread)

		if splitCount > 1 then
			task.wait(splitStagger)
		end
	end
end

function VisualFunctions.ShowLevelUpNotification(oldLvl: number, newLvl: number, oldSpeed: number, newSpeed: number)
	local frame = VisualFunctions.HUD.LevelUpFrame
	if not frame then
		return
	end
	local animationMaid = replaceAnimationMaid(frame)

	local labels = VisualFunctions.Labels
	if labels.LevelBeforeLabel then
		labels.LevelBeforeLabel.Text = "Lvl " .. tostring(oldLvl)
	end
	if labels.LevelAfterLabel then
		labels.LevelAfterLabel.Text = "Lvl " .. tostring(newLvl)
	end
	if labels.WalkspeedBeforeLabel then
		labels.WalkspeedBeforeLabel.Text = "Walkspeed " .. tostring(oldSpeed)
	end
	if labels.WalkspeedAfterLabel then
		labels.WalkspeedAfterLabel.Text = "Walkspeed " .. tostring(newSpeed)
	end

	local startPos, endPos = NotificationLayoutController.GetAnimationPositions(frame)

	if not frame.Visible then
		setTransparencyRecursive(frame, 1)
		frame.Visible = true
		frame.Position = startPos
	end
	-- Recalculate after visibility changes so newly active event/progress UI is included.
	endPos = NotificationLayoutController.GetVisiblePosition(frame, true)
	DebugModule.debugPrint(
		string.format("Level-up notification target | yScale=%.3f | yOffset=%d", endPos.Y.Scale, endPos.Y.Offset),
		"VisualFunctions"
	)

	TweenService:Create(frame, TweenConfig.WindowOpen, {
		Position = endPos,
	}):Play()

	local t = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		t = math.min(1, t + dt / 0.4)
		setTransparencyRecursive(frame, 1 - t)
		if t >= 1 then
			connection:Disconnect()
		end
	end)
	animationMaid:GiveTask(connection)

	animationMaid:GiveTask(task.delay(3, function()
		if AnimationMaids[frame] ~= animationMaid then
			return
		end

		local closeTween = TweenService:Create(frame, TweenConfig.WindowClose, {
			Position = startPos,
		})
		SoundService.PlayGuiSound("Swish")
		closeTween:Play()

		local ft = 0
		local fConnection
		fConnection = RunService.RenderStepped:Connect(function(dt)
			if AnimationMaids[frame] ~= animationMaid then
				fConnection:Disconnect()
				return
			end

			ft = math.min(1, ft + dt / 0.3)
			setTransparencyRecursive(frame, ft)
			if ft >= 1 then
				fConnection:Disconnect()
				if AnimationMaids[frame] == animationMaid then
					frame.Visible = false
				end
			end
		end)
		animationMaid:GiveTask(fConnection)
	end))
end

local function clearTutorialOnlyNotificationControls(frame: GuiObject)
	local tutorialLabel = frame:FindFirstChild("TutorialLabel", true)
	if tutorialLabel then
		if tutorialLabel:IsA("TextLabel") then
			tutorialLabel.Text = ""
		end
		if tutorialLabel:IsA("GuiObject") then
			tutorialLabel.Visible = false
		end
	end

	local skipButtonFrame = frame:FindFirstChild("SkipButtonFrame", true)
	if skipButtonFrame and skipButtonFrame:IsA("GuiObject") then
		skipButtonFrame.Visible = false

		local skipButton = skipButtonFrame:FindFirstChildWhichIsA("GuiButton", true)
		if skipButton and skipButton:IsA("GuiButton") then
			skipButton.Active = false
			skipButton.Selectable = false
			skipButton.AutoButtonColor = false
		end
	end
end

local function hideNotificationFrame(frame: GuiObject, label: TextLabel?)
	clearAnimationMaid(frame)
	activeNotificationKey = nil
	currentNotificationRequest = nil
	frame.Visible = false
	if label then
		label.Text = ""
	end
	setTransparencyRecursive(frame, 0)
	clearTutorialOnlyNotificationControls(frame)
end

local function hasNotificationText(message: string): boolean
	return typeof(message) == "string" and string.match(message, "%S") ~= nil
end

local function findNotificationRoot(frame: GuiObject): Instance?
	local current: Instance? = frame
	while current do
		if current.Name == "MainGUI" then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getVisibleNotificationRequest(frame: GuiObject, label: TextLabel?): NotificationRequest?
	if not frame.Visible or not label or not hasNotificationText(label.Text) then
		return nil
	end

	local gradientBottomColor: Color3? = nil
	local gradient = frame:FindFirstChildOfClass("UIGradient") or label:FindFirstChildOfClass("UIGradient")
	if gradient then
		local keypoints = gradient.Color.Keypoints
		if #keypoints > 0 then
			gradientBottomColor = keypoints[#keypoints].Value
		end
	end

	return {
		message = label.Text,
		textColor = label.TextColor3,
		gradientBottomColor = gradientBottomColor,
		notificationKey = activeNotificationKey,
		style = "Standard",
	}
end

local function setNotificationSuppressed(isSuppressed: boolean, frame: GuiObject?): ()
	if notificationSuppressed == isSuppressed then
		return
	end

	notificationSuppressed = isSuppressed
	local notificationFrame = frame or VisualFunctions.HUD.NotificationFrame
	local label = VisualFunctions.Labels.NotificationTextLabel
	if isSuppressed then
		if notificationFrame and not currentNotificationRequest then
			currentNotificationRequest = getVisibleNotificationRequest(notificationFrame, label)
		end
		if not currentNotificationRequest then
			activeNotificationKey = nil
		end
		if notificationFrame then
			clearAnimationMaid(notificationFrame)
			notificationFrame.Visible = false
			if label then
				label.Text = ""
			end
			setTransparencyRecursive(notificationFrame, 0)
			clearTutorialOnlyNotificationControls(notificationFrame)
		end
		return
	end

	local request = currentNotificationRequest
	currentNotificationRequest = nil
	if not request then
		activeNotificationKey = nil
		if notificationFrame then
			hideNotificationFrame(notificationFrame, label)
		end
		return
	end

	if request.style == "QuickFade" then
		VisualFunctions.ShowQuickFadeNotification(request.message, request.textColor, request.gradientBottomColor)
	else
		VisualFunctions.ShowNotification(
			request.message,
			request.textColor,
			request.gradientBottomColor,
			request.notificationKey
		)
	end
end

local function syncNotificationSuppression(frame: GuiObject?): ()
	local root = if frame then findNotificationRoot(frame) else notificationSuppressionRoot
	if root then
		setNotificationSuppressed(root:GetAttribute(LUCKY_BLOCK_CUTSCENE_ACTIVE_ATTRIBUTE) == true, frame)
	end
end

local function playNotificationCloseAnimation(
	frame: GuiObject,
	animationMaid: Maid,
	startPos: UDim2,
	label: TextLabel?
)
	if AnimationMaids[frame] ~= animationMaid then
		return
	end

	local closeTween = TweenService:Create(frame, TweenConfig.WindowClose, {
		Position = startPos,
	})
	SoundService.PlayGuiSound("Swish")
	closeTween:Play()

	local ft = 0
	local fConnection
	fConnection = RunService.RenderStepped:Connect(function(dt)
		if AnimationMaids[frame] ~= animationMaid then
			fConnection:Disconnect()
			return
		end

		ft = math.min(1, ft + dt / 0.3)
		setTransparencyRecursive(frame, ft)
		if ft >= 1 then
			fConnection:Disconnect()
			if AnimationMaids[frame] == animationMaid then
				frame.Visible = false
				if label then
					label.Text = ""
				end
				setTransparencyRecursive(frame, 0)
			end
		end
	end)
	animationMaid:GiveTask(fConnection)
end

function VisualFunctions.BindNotificationVisibilityGuard(frame: GuiObject, cleanupMaid: any)
	local root = findNotificationRoot(frame)
	if root and notificationSuppressionRoot ~= root then
		if notificationSuppressionConnection then
			notificationSuppressionConnection:Disconnect()
		end
		notificationSuppressionRoot = root
		notificationSuppressionConnection = root:GetAttributeChangedSignal(
			LUCKY_BLOCK_CUTSCENE_ACTIVE_ATTRIBUTE
		):Connect(function()
			syncNotificationSuppression(frame)
		end)
		cleanupMaid:GiveTask(notificationSuppressionConnection)
	end
	syncNotificationSuppression(frame)

	local function validateVisibleNotification()
		if not frame.Visible then
			return
		end

		local label = frame:FindFirstChild("TextLabel")
		if label and label:IsA("TextLabel") and hasNotificationText(label.Text) then
			return
		end

		hideNotificationFrame(frame, if label and label:IsA("TextLabel") then label else nil)
		DebugModule.debugWarn("NotificationFrame was shown without message text", "VisualFunctions")
	end

	cleanupMaid:GiveTask(frame:GetPropertyChangedSignal("Visible"):Connect(validateVisibleNotification))
	validateVisibleNotification()
end

function VisualFunctions.SetNotificationSuppressed(isSuppressed: boolean): ()
	setNotificationSuppressed(isSuppressed, VisualFunctions.HUD.NotificationFrame)
end

function VisualFunctions.ShowNotification(
	message: string,
	textColor: Color3?,
	gradientBottomColor: Color3?,
	notificationKey: string?
)
	local frame = VisualFunctions.HUD.NotificationFrame
	local label = VisualFunctions.Labels.NotificationTextLabel
	syncNotificationSuppression(frame)
	if not hasNotificationText(message) then
		if activeNotificationKey ~= nil then
			return
		end
		if frame then
			hideNotificationFrame(frame, label)
		end
		DebugModule.debugWarn("Ignored blank notification payload", "VisualFunctions")
		return
	end
	if not frame or not label then
		return
	end
	if frame.Parent == nil or label.Parent == nil or not label:IsDescendantOf(frame) then
		DebugModule.debugWarn("Notification mapping is stale; notification was ignored", "VisualFunctions")
		return
	end
	if activeNotificationKey ~= nil and activeNotificationKey ~= notificationKey then
		return
	end
	activeNotificationKey = notificationKey
	local request: NotificationRequest = {
		message = message,
		textColor = textColor,
		gradientBottomColor = gradientBottomColor,
		notificationKey = notificationKey,
		style = "Standard",
	}
	currentNotificationRequest = request
	if notificationSuppressed then
		return
	end

	local animationMaid = replaceAnimationMaid(frame)
	clearTutorialOnlyNotificationControls(frame)

	label.Text = toNotificationDisplayText(message)
	label.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)

	local bottomColor = gradientBottomColor or Color3.fromRGB(255, 255, 255)
	local frameGradient = frame:FindFirstChildOfClass("UIGradient")
	if frameGradient then
		frameGradient.Enabled = true
		frameGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, bottomColor),
		})
	end

	local labelGradient = label:FindFirstChildOfClass("UIGradient")
	if labelGradient then
		labelGradient.Enabled = true
		labelGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, bottomColor),
		})
		labelGradient.Rotation = 90
	end

	local startPos, endPos = NotificationLayoutController.GetAnimationPositions(frame)

	if not frame.Visible then
		setTransparencyRecursive(frame, 1)
		frame.Visible = true
		frame.Position = startPos
	end
	endPos = NotificationLayoutController.GetVisiblePosition(frame, true)
	DebugModule.debugPrint(
		string.format(
			"Notification target | message=%s | yScale=%.3f | yOffset=%d",
			label.Text,
			endPos.Y.Scale,
			endPos.Y.Offset
		),
		"VisualFunctions"
	)

	TweenService:Create(frame, TweenConfig.WindowOpen, {
		Position = endPos,
	}):Play()

	local t = 0
	local connection
	connection = RunService.RenderStepped:Connect(function(dt)
		t = math.min(1, t + dt / 0.4)
		setTransparencyRecursive(frame, 1 - t)
		if t >= 1 then
			connection:Disconnect()
		end
	end)
	animationMaid:GiveTask(connection)

	if notificationKey == nil then
		animationMaid:GiveTask(task.delay(2.5, function()
			if currentNotificationRequest ~= request then
				return
			end
			currentNotificationRequest = nil
			playNotificationCloseAnimation(frame, animationMaid, startPos, nil)
		end))
	end
end

function VisualFunctions.UpdateNotification(message: string, notificationKey: string): boolean
	local frame = VisualFunctions.HUD.NotificationFrame
	syncNotificationSuppression(frame)
	if activeNotificationKey ~= notificationKey then
		return false
	end
	local request = currentNotificationRequest
	if request and request.notificationKey == notificationKey then
		request.message = message
	end
	if notificationSuppressed then
		if request and request.notificationKey == notificationKey then
			return true
		end
		return false
	end

	local label = VisualFunctions.Labels.NotificationTextLabel
	if not frame or not label or not frame.Visible or frame.Parent == nil or label.Parent == nil then
		return false
	end

	label.Text = toNotificationDisplayText(message)
	return true
end

function VisualFunctions.HideNotification(notificationKey: string): boolean
	local frame = VisualFunctions.HUD.NotificationFrame
	syncNotificationSuppression(frame)
	if activeNotificationKey ~= notificationKey then
		return false
	end

	local label = VisualFunctions.Labels.NotificationTextLabel
	currentNotificationRequest = nil
	activeNotificationKey = nil
	if notificationSuppressed then
		if frame then
			hideNotificationFrame(frame, label)
		end
		return true
	end
	if not frame then
		return false
	end

	local animationMaid = AnimationMaids[frame]
	if not animationMaid or not frame.Visible then
		hideNotificationFrame(frame, label)
		return true
	end

	playNotificationCloseAnimation(
		frame,
		animationMaid,
		NotificationLayoutController.GetAnimationPositions(frame),
		label
	)
	return true
end

function VisualFunctions.ShowQuickFadeNotification(message: string, textColor: Color3?, gradientBottomColor: Color3?)
	local frame = VisualFunctions.HUD.NotificationFrame
	local label = VisualFunctions.Labels.NotificationTextLabel
	syncNotificationSuppression(frame)
	if not hasNotificationText(message) then
		if activeNotificationKey ~= nil then
			return
		end
		if frame then
			hideNotificationFrame(frame, label)
		end
		DebugModule.debugWarn("Ignored blank quick-fade notification payload", "VisualFunctions")
		return
	end
	if not frame or not label then
		return
	end
	if frame.Parent == nil or label.Parent == nil or not label:IsDescendantOf(frame) then
		DebugModule.debugWarn("Quick-fade notification mapping is stale; notification was ignored", "VisualFunctions")
		return
	end
	if activeNotificationKey ~= nil then
		return
	end
	activeNotificationKey = nil
	local request: NotificationRequest = {
		message = message,
		textColor = textColor,
		gradientBottomColor = gradientBottomColor,
		notificationKey = nil,
		style = "QuickFade",
	}
	currentNotificationRequest = request
	if notificationSuppressed then
		return
	end

	local animationMaid = replaceAnimationMaid(frame)
	clearTutorialOnlyNotificationControls(frame)
	label.Text = toNotificationDisplayText(message)
	label.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)

	local bottomColor = gradientBottomColor or Color3.fromRGB(255, 255, 255)
	local frameGradient = frame:FindFirstChildOfClass("UIGradient")
	if frameGradient then
		frameGradient.Enabled = true
		frameGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, bottomColor),
		})
	end

	local labelGradient = label:FindFirstChildOfClass("UIGradient")
	if labelGradient then
		labelGradient.Enabled = true
		labelGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, bottomColor),
		})
		labelGradient.Rotation = 90
	end

	frame.Visible = true
	frame.Position = NotificationLayoutController.GetVisiblePosition(frame, true)
	DebugModule.debugPrint(
		string.format(
			"Quick-fade notification target | message=%s | yScale=%.3f | yOffset=%d",
			label.Text,
			frame.Position.Y.Scale,
			frame.Position.Y.Offset
		),
		"VisualFunctions"
	)
	setTransparencyRecursive(frame, 1)

	local fadeIn = 0
	local fadeInConnection
	fadeInConnection = RunService.RenderStepped:Connect(function(dt)
		fadeIn = math.min(1, fadeIn + dt / 0.12)
		setTransparencyRecursive(frame, 1 - fadeIn)
		if fadeIn >= 1 then
			fadeInConnection:Disconnect()
		end
	end)
	animationMaid:GiveTask(fadeInConnection)

	animationMaid:GiveTask(task.delay(0.85, function()
		if AnimationMaids[frame] ~= animationMaid then
			return
		end

		local fadeOut = 0
		local fadeOutConnection
		fadeOutConnection = RunService.RenderStepped:Connect(function(dt)
			if AnimationMaids[frame] ~= animationMaid then
				fadeOutConnection:Disconnect()
				return
			end

			fadeOut = math.min(1, fadeOut + dt / 0.16)
			setTransparencyRecursive(frame, fadeOut)
			if fadeOut >= 1 then
				fadeOutConnection:Disconnect()
				if AnimationMaids[frame] == animationMaid then
					frame.Visible = false
					setTransparencyRecursive(frame, 0)
					if currentNotificationRequest == request then
						currentNotificationRequest = nil
					end
				end
			end
		end)
		animationMaid:GiveTask(fadeOutConnection)
	end))
end

function VisualFunctions.ResetRuntimeState()
	for gradient, gradientMaid in pairs(RainbowGradientMaids) do
		RainbowGradientMaids[gradient] = nil
		RainbowGradientStates[gradient] = nil
		gradientMaid:DoCleaning()
	end
	stopRainbowGradientUpdater()
	activeNotificationKey = nil
	currentNotificationRequest = nil
	notificationSuppressed = false
	notificationSuppressionRoot = nil
	if notificationSuppressionConnection then
		notificationSuppressionConnection:Disconnect()
		notificationSuppressionConnection = nil
	end

	for instance, animationMaid in pairs(AnimationMaids) do
		AnimationMaids[instance] = nil
		animationMaid:DoCleaning()
	end

	for guiObject, interactionMaid in pairs(InteractionMaids) do
		InteractionMaids[guiObject] = nil
		interactionMaid:DoCleaning()
	end
	for guiObject, pulseThread in pairs(ClickPulseThreads) do
		ClickPulseThreads[guiObject] = nil
		if coroutine.status(pulseThread) ~= "dead" then
			pcall(task.cancel, pulseThread)
		end
	end

	clearReferenceTable(HoverStates :: any)
	clearReferenceTable(HoverSetupBindings :: any)
	clearReferenceTable(ClickSetupBindings :: any)
	clearReferenceTable(ClickPulseActions :: any)
	clearReferenceTable(VisualFunctions.ActiveFrameGroup :: any)
	clearReferenceTable(VisualFunctions.HUD :: any)
	clearReferenceTable(VisualFunctions.Labels :: any)
end

return VisualFunctions
