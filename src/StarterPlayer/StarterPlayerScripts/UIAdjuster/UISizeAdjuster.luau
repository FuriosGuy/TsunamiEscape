local AUDIT_INTERVAL_SECONDS = 10
local SUMMARY_INTERVAL_SECONDS = 5
local MODULE_NAME = "UISizeAdjuster"

local SCREEN_GUI_TAG = "ScreenGui"
local SCREEN_STROKE_TAG = "ScreenStroke"
local TEXT_TAG = "Text"
local TILE_TAG = "Tile"
local TEXT_CONSTRAINT_TAG = "TextConstraint"
local PADDING_TAG = "Padding"
local SIZE_CONSTRAINT_TAG = "SizeConstraint"
local CORNER_TAG = "Corner"

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 100)

local Maid = require(ReplicatedStorage.Modules.Maid)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)

type TextObject = TextLabel | TextButton | TextBox
type TileObject = ImageLabel | ImageButton

type CoverageCounters = {
	eligibleTotal: number,
	taggedTotal: number,
	scaledTotal: number,
	skippedTotal: number,
	skipByReason: { [string]: number },
}

local uiStrokeAdjusterMaid = Maid.new()
local cameraViewportConnection: RBXScriptConnection? = nil
local scriptAlive = true
local screenGuiMaids: { [ScreenGui]: any } = {}

local screenStrokes: { [UIStroke]: number } = {}
local screenTexts: { [TextObject]: number } = {}
local screenTiles: { [TileObject]: UDim2 } = {}
local screenTextConstraints: { [UITextSizeConstraint]: { minTextSize: number, maxTextSize: number } } = {}
local screenPaddings: { [UIPadding]: { left: UDim, right: UDim, top: UDim, bottom: UDim } } = {}
local screenSizeConstraints: { [UISizeConstraint]: { minSize: Vector2, maxSize: Vector2 } } = {}
local screenCorners: { [UICorner]: UDim } = {}
local coverageCounters: CoverageCounters = {
	eligibleTotal = 0,
	taggedTotal = 0,
	scaledTotal = 0,
	skippedTotal = 0,
	skipByReason = {},
}

local function clearTrackedInstance(instance: Instance)
	if instance:IsA("UIStroke") then
		screenStrokes[instance] = nil
	elseif instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		screenTexts[instance] = nil
	elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		screenTiles[instance] = nil
	elseif instance:IsA("UITextSizeConstraint") then
		screenTextConstraints[instance] = nil
	elseif instance:IsA("UIPadding") then
		screenPaddings[instance] = nil
	elseif instance:IsA("UISizeConstraint") then
		screenSizeConstraints[instance] = nil
	elseif instance:IsA("UICorner") then
		screenCorners[instance] = nil
	end
end

local function clearTrackedDescendants(root: Instance)
	for _, descendant in root:GetDescendants() do
		clearTrackedInstance(descendant)
	end
end

local uiAdjusterConfig = CoreConfig.uiAdjuster or {}
local REFERENCE_VIEWPORT = if typeof(uiAdjusterConfig.referenceViewport) == "Vector2"
	then uiAdjusterConfig.referenceViewport
	else Vector2.new(1920, 1080)
local MIN_SCALE_RATIO = if typeof(uiAdjusterConfig.minScaleRatio) == "number"
	then math.max(0.1, uiAdjusterConfig.minScaleRatio)
	else 0.45
local MAX_SCALE_RATIO = if typeof(uiAdjusterConfig.maxScaleRatio) == "number"
	then math.max(MIN_SCALE_RATIO, uiAdjusterConfig.maxScaleRatio)
	else 1.35
local MIN_TEXT_SIZE = if typeof(uiAdjusterConfig.minTextSize) == "number"
	then math.max(1, uiAdjusterConfig.minTextSize)
	else 8
local MIN_TILE_OFFSET = if typeof(uiAdjusterConfig.minTileOffset) == "number"
	then math.max(1, math.floor(uiAdjusterConfig.minTileOffset))
	else 1
local NO_UPSCALE_ON_MOBILE = if typeof(uiAdjusterConfig.noUpscaleOnMobile) == "boolean"
	then uiAdjusterConfig.noUpscaleOnMobile
	else true
local MOBILE_MAX_SCALE_RATIO = if typeof(uiAdjusterConfig.mobileMaxScaleRatio) == "number"
	then math.max(MIN_SCALE_RATIO, uiAdjusterConfig.mobileMaxScaleRatio)
	else 1.0
local ORIGINAL_TEXT_SIZE_ATTR = "UIAdjusterOriginalTextSize"
local ORIGINAL_TILE_X_SCALE_ATTR = "UIAdjusterOriginalTileXScale"
local ORIGINAL_TILE_X_OFFSET_ATTR = "UIAdjusterOriginalTileXOffset"
local ORIGINAL_TILE_Y_SCALE_ATTR = "UIAdjusterOriginalTileYScale"
local ORIGINAL_TILE_Y_OFFSET_ATTR = "UIAdjusterOriginalTileYOffset"

local function isMobileClient(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

local function addSkip(reason: string)
	coverageCounters.skippedTotal += 1
	coverageCounters.skipByReason[reason] = (coverageCounters.skipByReason[reason] or 0) + 1
end

local function addScaled()
	coverageCounters.scaledTotal += 1
end

local function getCurrentCamera(): Camera?
	return workspace.CurrentCamera
end

local function getBox(vector: Vector2): number
	return math.min(vector.X, vector.Y)
end

local function getScreenRatio(): number
	local currentCamera = getCurrentCamera()
	if currentCamera == nil then
		addSkip("missing_camera")
		return 1
	end

	local reference = getBox(REFERENCE_VIEWPORT)
	if reference <= 0 then
		addSkip("invalid_reference_viewport")
		return 1
	end

	local rawRatio = getBox(currentCamera.ViewportSize) / reference
	local maxRatio = MAX_SCALE_RATIO
	if NO_UPSCALE_ON_MOBILE and isMobileClient() then
		maxRatio = math.min(maxRatio, MOBILE_MAX_SCALE_RATIO)
	end

	return math.clamp(rawRatio, MIN_SCALE_RATIO, maxRatio)
end

local function makeTileSizeSafe(baseTileSize: UDim2, ratio: number): UDim2
	local xScale = baseTileSize.X.Scale
	local yScale = baseTileSize.Y.Scale
	local xOffset = baseTileSize.X.Offset * ratio
	local yOffset = baseTileSize.Y.Offset * ratio

	-- TileSize cannot be zero on either axis.
	if xScale == 0 and xOffset <= 0 then
		xOffset = MIN_TILE_OFFSET
	end
	if yScale == 0 and yOffset <= 0 then
		yOffset = MIN_TILE_OFFSET
	end

	return UDim2.new(xScale, xOffset, yScale, yOffset)
end

local function getOriginalTextSize(instance: TextObject): number
	local storedSize = instance:GetAttribute(ORIGINAL_TEXT_SIZE_ATTR)
	if typeof(storedSize) == "number" and storedSize > 0 then
		return storedSize
	end

	local currentSize = instance.TextSize
	instance:SetAttribute(ORIGINAL_TEXT_SIZE_ATTR, currentSize)
	return currentSize
end

local function getOriginalTileSize(instance: TileObject): UDim2
	local xScale = instance:GetAttribute(ORIGINAL_TILE_X_SCALE_ATTR)
	local xOffset = instance:GetAttribute(ORIGINAL_TILE_X_OFFSET_ATTR)
	local yScale = instance:GetAttribute(ORIGINAL_TILE_Y_SCALE_ATTR)
	local yOffset = instance:GetAttribute(ORIGINAL_TILE_Y_OFFSET_ATTR)

	if
		typeof(xScale) == "number"
		and typeof(xOffset) == "number"
		and typeof(yScale) == "number"
		and typeof(yOffset) == "number"
	then
		return UDim2.new(xScale, xOffset, yScale, yOffset)
	end

	local currentSize = instance.TileSize
	instance:SetAttribute(ORIGINAL_TILE_X_SCALE_ATTR, currentSize.X.Scale)
	instance:SetAttribute(ORIGINAL_TILE_X_OFFSET_ATTR, currentSize.X.Offset)
	instance:SetAttribute(ORIGINAL_TILE_Y_SCALE_ATTR, currentSize.Y.Scale)
	instance:SetAttribute(ORIGINAL_TILE_Y_OFFSET_ATTR, currentSize.Y.Offset)
	return currentSize
end

local function addTagOnce(instance: Instance, tag: string): boolean
	if CollectionService:HasTag(instance, tag) then
		return false
	end

	CollectionService:AddTag(instance, tag)
	coverageCounters.taggedTotal += 1
	return true
end

local function tryTagEligible(instance: Instance)
	if instance:IsA("UIStroke") then
		coverageCounters.eligibleTotal += 1
		addTagOnce(instance, SCREEN_STROKE_TAG)
		return
	end

	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		coverageCounters.eligibleTotal += 1
		addTagOnce(instance, TEXT_TAG)
		return
	end

	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		coverageCounters.eligibleTotal += 1
		addTagOnce(instance, TILE_TAG)
		return
	end

	if instance:IsA("UITextSizeConstraint") then
		coverageCounters.eligibleTotal += 1
		addTagOnce(instance, TEXT_CONSTRAINT_TAG)
		return
	end

	if instance:IsA("UIPadding") then
		coverageCounters.eligibleTotal += 1
		addTagOnce(instance, PADDING_TAG)
		return
	end

	if instance:IsA("UISizeConstraint") then
		coverageCounters.eligibleTotal += 1
		addTagOnce(instance, SIZE_CONSTRAINT_TAG)
		return
	end

	if instance:IsA("UICorner") then
		coverageCounters.eligibleTotal += 1
		addTagOnce(instance, CORNER_TAG)
	end
end

local function tagScreenGuiTree(screenGui: ScreenGui)
	local existingMaid = screenGuiMaids[screenGui]
	if existingMaid then
		existingMaid:DoCleaning()
		screenGuiMaids[screenGui] = nil
	end

	local screenGuiMaid = Maid.new()
	screenGuiMaids[screenGui] = screenGuiMaid

	tryTagEligible(screenGui)
	for _, descendant in screenGui:GetDescendants() do
		tryTagEligible(descendant)
	end

	screenGuiMaid:GiveTask(screenGui.DescendantAdded:Connect(function(descendant)
		tryTagEligible(descendant)
	end))
	screenGuiMaid:GiveTask(screenGui.DescendantRemoving:Connect(function(descendant)
		clearTrackedInstance(descendant)
	end))
	screenGuiMaid:GiveTask(screenGui.Destroying:Connect(function()
		clearTrackedDescendants(screenGui)
		local maid = screenGuiMaids[screenGui]
		if maid then
			maid:DoCleaning()
			screenGuiMaids[screenGui] = nil
		end
	end))
	screenGuiMaid:GiveTask(screenGui.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil then
			return
		end

		clearTrackedDescendants(screenGui)
		local maid = screenGuiMaids[screenGui]
		if maid then
			maid:DoCleaning()
			screenGuiMaids[screenGui] = nil
		end
	end))
end

local function updateScreenGuiStrokesAndTextSize()
	local ratio = getScreenRatio()

	for uiStroke, originalThickness in screenStrokes do
		if uiStroke.Parent == nil then
			screenStrokes[uiStroke] = nil
			addSkip("destroyed_before_scale")
		elseif uiStroke.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize then
			screenStrokes[uiStroke] = nil
			addSkip("stroke_already_scaled")
		else
			uiStroke.Thickness = originalThickness * ratio
		end
	end

	for textObject, originalSize in screenTexts do
		if textObject.Parent == nil then
			screenTexts[textObject] = nil
			addSkip("destroyed_before_scale")
		else
			textObject.TextSize = math.max(MIN_TEXT_SIZE, originalSize * ratio)
		end
	end

	for imageLabel, originalTileSize in screenTiles do
		if imageLabel.Parent == nil then
			screenTiles[imageLabel] = nil
			addSkip("destroyed_before_scale")
		else
			imageLabel.TileSize = makeTileSizeSafe(originalTileSize, ratio)
		end
	end

	for textConstraint, originalValues in screenTextConstraints do
		if textConstraint.Parent == nil then
			screenTextConstraints[textConstraint] = nil
			addSkip("destroyed_before_scale")
		else
			local scaledMin = math.max(MIN_TEXT_SIZE, originalValues.minTextSize * ratio)
			local scaledMax = math.max(scaledMin, originalValues.maxTextSize * ratio)
			textConstraint.MinTextSize = scaledMin
			textConstraint.MaxTextSize = scaledMax
		end
	end

	for padding, originalValues in screenPaddings do
		if padding.Parent == nil then
			screenPaddings[padding] = nil
			addSkip("destroyed_before_scale")
		else
			padding.PaddingLeft = UDim.new(originalValues.left.Scale, originalValues.left.Offset * ratio)
			padding.PaddingRight = UDim.new(originalValues.right.Scale, originalValues.right.Offset * ratio)
			padding.PaddingTop = UDim.new(originalValues.top.Scale, originalValues.top.Offset * ratio)
			padding.PaddingBottom = UDim.new(originalValues.bottom.Scale, originalValues.bottom.Offset * ratio)
		end
	end

	for sizeConstraint, originalValues in screenSizeConstraints do
		if sizeConstraint.Parent == nil then
			screenSizeConstraints[sizeConstraint] = nil
			addSkip("destroyed_before_scale")
		else
			sizeConstraint.MinSize = Vector2.new(originalValues.minSize.X * ratio, originalValues.minSize.Y * ratio)
			sizeConstraint.MaxSize = Vector2.new(originalValues.maxSize.X * ratio, originalValues.maxSize.Y * ratio)
		end
	end

	for corner, originalCornerRadius in screenCorners do
		if corner.Parent == nil then
			screenCorners[corner] = nil
			addSkip("destroyed_before_scale")
		else
			corner.CornerRadius = UDim.new(originalCornerRadius.Scale, originalCornerRadius.Offset * ratio)
		end
	end
end

local function bindToCameraViewport(camera: Camera)
	if cameraViewportConnection then
		cameraViewportConnection:Disconnect()
		cameraViewportConnection = nil
	end

	cameraViewportConnection =
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScreenGuiStrokesAndTextSize)
	uiStrokeAdjusterMaid:GiveTask(cameraViewportConnection)
end

local function refreshCameraBinding()
	local currentCamera = getCurrentCamera()
	if currentCamera then
		bindToCameraViewport(currentCamera)
	end

	updateScreenGuiStrokesAndTextSize()
end

local function summarizeCounters()
	if not DebugModule.isEnabled() then
		return
	end

	DebugModule.debugInfo(
		string.format(
			"Coverage summary | eligible=%d tagged=%d scaled=%d skipped=%d reasons=%s",
			coverageCounters.eligibleTotal,
			coverageCounters.taggedTotal,
			coverageCounters.scaledTotal,
			coverageCounters.skippedTotal,
			HttpService:JSONEncode(coverageCounters.skipByReason)
		),
		MODULE_NAME
	)
end

local function runGlobalAudit()
	if not DebugModule.isEnabled() then
		return
	end

	local textTotal = 0
	local textTagged = 0
	local tileTotal = 0
	local tileTagged = 0
	local tileSkippedNonTile = 0
	local strokeTotal = 0
	local strokeTagged = 0
	local textConstraintTotal = 0
	local textConstraintTagged = 0
	local paddingTotal = 0
	local paddingTagged = 0
	local sizeConstraintTotal = 0
	local sizeConstraintTagged = 0
	local cornerTotal = 0
	local cornerTagged = 0

	for _, descendant in playerGui:GetDescendants() do
		if descendant:IsA("UIStroke") then
			strokeTotal += 1
			if CollectionService:HasTag(descendant, SCREEN_STROKE_TAG) then
				strokeTagged += 1
			end
		elseif descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			textTotal += 1
			if CollectionService:HasTag(descendant, TEXT_TAG) then
				textTagged += 1
			end
		elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			tileTotal += 1
			if CollectionService:HasTag(descendant, TILE_TAG) then
				tileTagged += 1
				if descendant.ScaleType ~= Enum.ScaleType.Tile then
					tileSkippedNonTile += 1
				end
			end
		elseif descendant:IsA("UITextSizeConstraint") then
			textConstraintTotal += 1
			if CollectionService:HasTag(descendant, TEXT_CONSTRAINT_TAG) then
				textConstraintTagged += 1
			end
		elseif descendant:IsA("UIPadding") then
			paddingTotal += 1
			if CollectionService:HasTag(descendant, PADDING_TAG) then
				paddingTagged += 1
			end
		elseif descendant:IsA("UISizeConstraint") then
			sizeConstraintTotal += 1
			if CollectionService:HasTag(descendant, SIZE_CONSTRAINT_TAG) then
				sizeConstraintTagged += 1
			end
		elseif descendant:IsA("UICorner") then
			cornerTotal += 1
			if CollectionService:HasTag(descendant, CORNER_TAG) then
				cornerTagged += 1
			end
		end
	end

	DebugModule.debugInfo(
		string.format(
			"Audit | text=%d/%d strokes=%d/%d images=%d/%d nonTileTagged=%d textConstraints=%d/%d paddings=%d/%d sizeConstraints=%d/%d corners=%d/%d",
			textTagged,
			textTotal,
			strokeTagged,
			strokeTotal,
			tileTagged,
			tileTotal,
			tileSkippedNonTile,
			textConstraintTagged,
			textConstraintTotal,
			paddingTagged,
			paddingTotal,
			sizeConstraintTagged,
			sizeConstraintTotal,
			cornerTagged,
			cornerTotal
		),
		MODULE_NAME
	)
end

uiStrokeAdjusterMaid:GiveTask(
	CollectionService:GetInstanceAddedSignal(SCREEN_GUI_TAG):Connect(function(screenGui: ScreenGui)
		tagScreenGuiTree(screenGui)
	end)
)

uiStrokeAdjusterMaid:GiveTask(
	CollectionService:GetInstanceAddedSignal(SCREEN_STROKE_TAG):Connect(function(uiStroke: UIStroke)
		if uiStroke.StrokeSizingMode == Enum.StrokeSizingMode.ScaledSize then
			addSkip("stroke_already_scaled")
			return
		end

		screenStrokes[uiStroke] = uiStroke.Thickness
		uiStroke.Thickness *= getScreenRatio()
		addScaled()
	end)
)

uiStrokeAdjusterMaid:GiveTask(CollectionService:GetInstanceAddedSignal(TEXT_TAG):Connect(function(instance: Instance)
	if not (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
		addSkip("text_wrong_class")
		return
	end

	local textObject: TextObject = instance
	if textObject.TextScaled then
		addSkip("text_scaled_true")
		return
	end

	local originalTextSize = getOriginalTextSize(textObject)
	screenTexts[textObject] = originalTextSize
	textObject.TextSize = math.max(MIN_TEXT_SIZE, originalTextSize * getScreenRatio())
	addScaled()
end))

uiStrokeAdjusterMaid:GiveTask(CollectionService:GetInstanceAddedSignal(TILE_TAG):Connect(function(instance: Instance)
	if not (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
		addSkip("tile_wrong_class")
		return
	end

	local imageObject: TileObject = instance
	if imageObject.ScaleType ~= Enum.ScaleType.Tile then
		addSkip("image_not_tile")
		return
	end

	local originalTileSize = getOriginalTileSize(imageObject)
	screenTiles[imageObject] = originalTileSize
	imageObject.TileSize = makeTileSizeSafe(originalTileSize, getScreenRatio())
	addScaled()
end))

uiStrokeAdjusterMaid:GiveTask(
	CollectionService:GetInstanceAddedSignal(TEXT_CONSTRAINT_TAG):Connect(function(instance: Instance)
		if not instance:IsA("UITextSizeConstraint") then
			addSkip("text_constraint_wrong_class")
			return
		end

		screenTextConstraints[instance] = {
			minTextSize = instance.MinTextSize,
			maxTextSize = instance.MaxTextSize,
		}
		local ratio = getScreenRatio()
		local scaledMin = math.max(MIN_TEXT_SIZE, instance.MinTextSize * ratio)
		local scaledMax = math.max(scaledMin, instance.MaxTextSize * ratio)
		instance.MinTextSize = scaledMin
		instance.MaxTextSize = scaledMax
		addScaled()
	end)
)

uiStrokeAdjusterMaid:GiveTask(CollectionService:GetInstanceAddedSignal(PADDING_TAG):Connect(function(instance: Instance)
	if not instance:IsA("UIPadding") then
		addSkip("padding_wrong_class")
		return
	end

	screenPaddings[instance] = {
		left = instance.PaddingLeft,
		right = instance.PaddingRight,
		top = instance.PaddingTop,
		bottom = instance.PaddingBottom,
	}
	local ratio = getScreenRatio()
	instance.PaddingLeft = UDim.new(instance.PaddingLeft.Scale, instance.PaddingLeft.Offset * ratio)
	instance.PaddingRight = UDim.new(instance.PaddingRight.Scale, instance.PaddingRight.Offset * ratio)
	instance.PaddingTop = UDim.new(instance.PaddingTop.Scale, instance.PaddingTop.Offset * ratio)
	instance.PaddingBottom = UDim.new(instance.PaddingBottom.Scale, instance.PaddingBottom.Offset * ratio)
	addScaled()
end))

uiStrokeAdjusterMaid:GiveTask(
	CollectionService:GetInstanceAddedSignal(SIZE_CONSTRAINT_TAG):Connect(function(instance: Instance)
		if not instance:IsA("UISizeConstraint") then
			addSkip("size_constraint_wrong_class")
			return
		end

		screenSizeConstraints[instance] = {
			minSize = instance.MinSize,
			maxSize = instance.MaxSize,
		}
		local ratio = getScreenRatio()
		instance.MinSize = Vector2.new(instance.MinSize.X * ratio, instance.MinSize.Y * ratio)
		instance.MaxSize = Vector2.new(instance.MaxSize.X * ratio, instance.MaxSize.Y * ratio)
		addScaled()
	end)
)

uiStrokeAdjusterMaid:GiveTask(CollectionService:GetInstanceAddedSignal(CORNER_TAG):Connect(function(instance: Instance)
	if not instance:IsA("UICorner") then
		addSkip("corner_wrong_class")
		return
	end

	screenCorners[instance] = instance.CornerRadius
	local cornerRadius = instance.CornerRadius
	instance.CornerRadius = UDim.new(cornerRadius.Scale, cornerRadius.Offset * getScreenRatio())
	addScaled()
end))

uiStrokeAdjusterMaid:GiveTask(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refreshCameraBinding))
refreshCameraBinding()

uiStrokeAdjusterMaid:GiveTask(task.spawn(function()
	local summaryAccumulator = 0
	local auditAccumulator = 0

	while scriptAlive do
		local dt = RunService.Heartbeat:Wait()
		summaryAccumulator += dt
		auditAccumulator += dt

		if summaryAccumulator >= SUMMARY_INTERVAL_SECONDS then
			summaryAccumulator = 0
			summarizeCounters()
		end

		if auditAccumulator >= AUDIT_INTERVAL_SECONDS then
			auditAccumulator = 0
			runGlobalAudit()
		end
	end
end))

local function cleanupAdjuster()
	if not scriptAlive then
		return
	end

	scriptAlive = false
	for screenGui, screenGuiMaid in pairs(screenGuiMaids) do
		clearTrackedDescendants(screenGui)
		screenGuiMaid:DoCleaning()
		screenGuiMaids[screenGui] = nil
	end
	table.clear(screenStrokes)
	table.clear(screenTexts)
	table.clear(screenTiles)
	table.clear(screenTextConstraints)
	table.clear(screenPaddings)
	table.clear(screenSizeConstraints)
	table.clear(screenCorners)
	uiStrokeAdjusterMaid:DoCleaning()
end

uiStrokeAdjusterMaid:GiveTask(script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanupAdjuster()
	end
end))
uiStrokeAdjusterMaid:GiveTask(script.Destroying:Connect(cleanupAdjuster))

local UIStrokeAdjuster = {}

function UIStrokeAdjuster:TagScreenGui(screenGui: ScreenGui)
	if screenGui:IsA("ScreenGui") then
		addTagOnce(screenGui, SCREEN_GUI_TAG)
	end
end

function UIStrokeAdjuster:TagBillboardGui(billboardGui: BillboardGui)
	if billboardGui:IsA("BillboardGui") then
		return
	end
end

return UIStrokeAdjuster
