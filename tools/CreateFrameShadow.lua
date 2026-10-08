--!strict
-- Paste into Roblox Studio's Command Bar with one statically sized Frame selected.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local MAIN_NAME = "Main"
local SHADOW_NAME = "Shadow"
local MAIN_LIGHTEN_FACTOR = 0.1
local SHADOW_OFFSET_Y_SCALE = 0.075
local SHADOW_DARKEN_FACTOR = 0.75

local function transformGradient(gradient: UIGradient, color: Color3, factor: number): ()
	local keypoints: { ColorSequenceKeypoint } = {}
	for _, keypoint in ipairs(gradient.Color.Keypoints) do
		table.insert(
			keypoints,
			ColorSequenceKeypoint.new(keypoint.Time, keypoint.Value:Lerp(color, factor))
		)
	end
	gradient.Color = ColorSequence.new(keypoints)
end

local function isInnerStroke(instance: Instance): boolean
	return instance:IsA("UIStroke")
		and string.find(string.lower(instance.Name), "inner", 1, true) ~= nil
end

local function isLayout(instance: Instance): boolean
	return instance:IsA("UIListLayout")
		or instance:IsA("UIGridLayout")
		or instance:IsA("UIPageLayout")
		or instance:IsA("UITableLayout")
end

local function fitGuiObjectToMainBounds(guiObject: GuiObject, mainHeightScale: number): ()
	local position = guiObject.Position
	local size = guiObject.Size
	guiObject.Position = UDim2.new(
		position.X.Scale,
		position.X.Offset,
		position.Y.Scale * mainHeightScale,
		position.Y.Offset
	)
	guiObject.Size = UDim2.new(
		size.X.Scale,
		size.X.Offset,
		size.Y.Scale * mainHeightScale,
		size.Y.Offset
	)
end

local function isImage(guiObject: GuiObject): boolean
	return guiObject:IsA("ImageLabel") or guiObject:IsA("ImageButton")
end

local function isTextContent(guiObject: GuiObject): boolean
	return guiObject:IsA("TextLabel") or guiObject:IsA("TextButton") or guiObject:IsA("TextBox")
end

local function isTextureImage(guiObject: GuiObject): boolean
	return isImage(guiObject) and string.find(string.lower(guiObject.Name), "texture", 1, true) ~= nil
end

local selectedInstance = Selection:Get()[1]
assert(selectedInstance and selectedInstance:IsA("Frame"), "Select one Frame first.")

local main = selectedInstance :: Frame
local originalParent = main.Parent
assert(originalParent ~= nil, "Selected Frame must have a parent.")
assert(main.AutomaticSize == Enum.AutomaticSize.None, "Selected Frame must have AutomaticSize set to None.")
assert(main.ZIndex > 1, "Set selected Frame ZIndex to at least 2 so Shadow can render behind Main.")
for _, child in ipairs(main:GetChildren()) do
	assert(not isLayout(child), "Remove direct UI layout objects before converting this Frame.")
end

local originalName = main.Name
local originalColor = main.BackgroundColor3
local originalSize = main.Size
local originalPosition = main.Position
local originalAnchorPoint = main.AnchorPoint
local originalZIndex = main.ZIndex
local originalLayoutOrder = main.LayoutOrder
local originalVisible = main.Visible
local originalRotation = main.Rotation
local originalAttributes = main:GetAttributes()

local beforeWaypointSucceeded, beforeWaypointFailure = pcall(function()
	ChangeHistoryService:SetWaypoint("Before Create Frame Shadow")
end)
if not beforeWaypointSucceeded then
	warn("[CreateFrameShadow] Could not create undo waypoint; no changes made: " .. tostring(beforeWaypointFailure))
	return
end

local success, failure = pcall(function()
	local groupHeightScale = 1 + SHADOW_OFFSET_Y_SCALE
	local mainHeightScale = 1 / groupHeightScale
	local shadowPositionYScale = 1 - mainHeightScale
	local contentZIndex = math.max(5, math.min(originalZIndex, 10))
	local mainZIndex = contentZIndex - 3
	local textureZIndex = mainZIndex + 1
	local imageZIndex = mainZIndex + 2
	local shadowZIndex = math.max(1, mainZIndex - 1)

	local function setDescendantZIndices(guiObject: GuiObject): ()
		for _, descendant in ipairs(guiObject:GetDescendants()) do
			if not descendant:IsA("GuiObject") then
				continue
			end

			if isTextureImage(descendant) then
				descendant.ZIndex = textureZIndex
			elseif isImage(descendant) then
				descendant.ZIndex = imageZIndex
			elseif isTextContent(descendant) or descendant:IsA("GuiButton") then
				descendant.ZIndex = contentZIndex
			else
				descendant.ZIndex = mainZIndex
			end
		end
	end

	local canvasGroup: CanvasGroup = Instance.new("CanvasGroup")
	canvasGroup.Name = originalName
	canvasGroup.AnchorPoint = originalAnchorPoint
	canvasGroup.Position = UDim2.new(
		originalPosition.X.Scale,
		originalPosition.X.Offset,
		originalPosition.Y.Scale + originalSize.Y.Scale * SHADOW_OFFSET_Y_SCALE * originalAnchorPoint.Y,
		originalPosition.Y.Offset + originalSize.Y.Offset * SHADOW_OFFSET_Y_SCALE * originalAnchorPoint.Y
	)
	canvasGroup.Size = UDim2.new(
		originalSize.X.Scale,
		originalSize.X.Offset,
		originalSize.Y.Scale * groupHeightScale,
		originalSize.Y.Offset * groupHeightScale
	)
	canvasGroup.Rotation = originalRotation
	canvasGroup.ZIndex = originalZIndex
	canvasGroup.LayoutOrder = originalLayoutOrder
	canvasGroup.Visible = originalVisible
	canvasGroup.BackgroundTransparency = 1
	canvasGroup.BorderSizePixel = 0
	canvasGroup.GroupColor3 = Color3.new(1, 1, 1)
	canvasGroup.GroupTransparency = 0
	canvasGroup.Active = false
	canvasGroup.Selectable = false

	local shadow: Frame = Instance.new("Frame")
	shadow.Name = SHADOW_NAME
	shadow.AnchorPoint = Vector2.zero
	shadow.Position = UDim2.fromScale(0, shadowPositionYScale)
	shadow.Size = UDim2.fromScale(1, mainHeightScale)
	shadow.BackgroundColor3 = originalColor:Lerp(Color3.new(0, 0, 0), SHADOW_DARKEN_FACTOR)
	shadow.BackgroundTransparency = 0
	shadow.BorderSizePixel = 0
	shadow.ClipsDescendants = false
	shadow.ZIndex = shadowZIndex
	shadow.Active = false
	shadow.Selectable = false

	local mainCornerClones: { UICorner } = {}
	local originalChildren = main:GetChildren()
	for _, child in ipairs(originalChildren) do
		if child:IsA("UICorner") then
			table.insert(mainCornerClones, child:Clone() :: UICorner)
		end
	end

	main.Name = MAIN_NAME
	main.AnchorPoint = Vector2.zero
	main.Position = UDim2.fromScale(0, 0)
	main.Size = UDim2.fromScale(1, mainHeightScale)
	main.Rotation = 0
	main.Visible = true
	main.ClipsDescendants = true
	main.BackgroundColor3 = originalColor:Lerp(Color3.new(1, 1, 1), MAIN_LIGHTEN_FACTOR)
	main.ZIndex = mainZIndex

	main.Parent = canvasGroup
	for _, child in ipairs(originalChildren) do
		if isInnerStroke(child) then
			continue
		end

		if child:IsA("UISizeConstraint") then
			continue
		end
		if child:IsA("UIAspectRatioConstraint") then
			child.AspectRatio /= groupHeightScale
			child.Parent = canvasGroup
			continue
		end

		if child:IsA("UIGradient") then
			transformGradient(child, Color3.new(1, 1, 1), MAIN_LIGHTEN_FACTOR)
			continue
		end

		if child:IsA("GuiObject") then
			if isImage(child) and not isTextureImage(child) then
				fitGuiObjectToMainBounds(child, mainHeightScale)
				child.ZIndex = imageZIndex
				setDescendantZIndices(child)
				child.Parent = canvasGroup
				continue
			end

			fitGuiObjectToMainBounds(child, mainHeightScale)
			if isTextureImage(child) then
				child.ZIndex = textureZIndex
			elseif isTextContent(child) then
				child.ZIndex = contentZIndex
			else
				child.ZIndex = mainZIndex
			end

			setDescendantZIndices(child)
		end
		child.Parent = canvasGroup
	end

	for _, corner in ipairs(mainCornerClones) do
		corner.Parent = main
	end
	shadow.Parent = canvasGroup
	for attributeName, attributeValue in pairs(originalAttributes) do
		canvasGroup:SetAttribute(attributeName, attributeValue)
		main:SetAttribute(attributeName, nil)
	end
	canvasGroup:SetAttribute("CreateFrameShadow", true)
	canvasGroup:SetAttribute("ShadowDarkenFactor", SHADOW_DARKEN_FACTOR)
	canvasGroup.Parent = originalParent
	Selection:Set({ canvasGroup })
end)

local afterWaypointSucceeded, afterWaypointFailure = pcall(function()
	ChangeHistoryService:SetWaypoint("Create Frame Shadow")
end)

if success then
	if afterWaypointSucceeded then
		print("[CreateFrameShadow] Converted. Press Ctrl+Z once to undo.")
	else
		warn("[CreateFrameShadow] Converted, but could not create the final undo waypoint: " .. tostring(afterWaypointFailure))
	end
	return
end

warn("[CreateFrameShadow] Conversion failed: " .. tostring(failure))
if afterWaypointSucceeded then
	warn("[CreateFrameShadow] Partial changes recorded; press Ctrl+Z once to undo them.")
	Selection:Set({ main })
	return
end

warn("[CreateFrameShadow] Could not record partial changes for undo: " .. tostring(afterWaypointFailure))
Selection:Set({ main })
