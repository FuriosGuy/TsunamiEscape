--!strict

local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

if not plugin then
	return
end

local MODULE_NAME = "AnchorPointPlugin"
local DEFAULT_MODE = "ChangePos"
local HOVER_COLOR_MULTIPLIER = 1.2
local SELECTED_COLOR_MULTIPLIER = HOVER_COLOR_MULTIPLIER
local POSITION_MODE_SETTING_KEY = "PositionMode"
local GAP_SETTING_KEY = "GapToEdge"
local CHECK_OTHER_FRAMES_SETTING_KEY = "CheckOtherFrames"
local SELECTED_ANCHOR_SETTING_KEY = "SelectedAnchor"

type PositionMode = "ChangePos" | "ChangePos1" | "StayInPos"

local function createHoverTweenInfo(): TweenInfo
	return TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

local ANCHOR_POINTS: { [string]: Vector2 } = table.freeze({
	TopLeft = Vector2.new(0, 0),
	TopCenter = Vector2.new(0.5, 0),
	TopRight = Vector2.new(1, 0),
	CenterLeft = Vector2.new(0, 0.5),
	Center = Vector2.new(0.5, 0.5),
	CenterRight = Vector2.new(1, 0.5),
	BottomLeft = Vector2.new(0, 1),
	BottomCenter = Vector2.new(0.5, 1),
	BottomRight = Vector2.new(1, 1),
})

local function readPluginSetting(key: string): string?
	local success, value = pcall(function()
		return plugin:GetSetting(key)
	end)

	if success and type(value) == "string" then
		return value
	end
	if not success then
		warn(string.format("[%s] Could not read plugin setting %s: %s", MODULE_NAME, key, tostring(value)))
	end

	return nil
end

local function readPluginBooleanSetting(key: string): boolean?
	local success, value = pcall(function()
		return plugin:GetSetting(key)
	end)

	if success and type(value) == "boolean" then
		return value
	end
	if not success then
		warn(string.format("[%s] Could not read plugin setting %s: %s", MODULE_NAME, key, tostring(value)))
	end

	return nil
end

local function savePluginSetting(key: string, value: string | boolean)
	local success, failure = pcall(function()
		plugin:SetSetting(key, value)
	end)
	if not success then
		warn(string.format("[%s] Could not save plugin setting %s: %s", MODULE_NAME, key, tostring(failure)))
	end
end

local function getSavedPositionMode(): PositionMode
	local savedMode = readPluginSetting(POSITION_MODE_SETTING_KEY)
	if savedMode == "ChangePos" or savedMode == "ChangePos1" or savedMode == "StayInPos" then
		return savedMode
	end

	return DEFAULT_MODE
end

local connections: { RBXScriptConnection } = {}
local activeTweens: { [GuiObject]: Tween } = {}
local anchorCellColors: { [string]: { cell: GuiObject, baseColor: Color3 } } = {}
local savedAnchorName = readPluginSetting(SELECTED_ANCHOR_SETTING_KEY)
local selectedAnchorName: string? = if savedAnchorName and ANCHOR_POINTS[savedAnchorName]
	then savedAnchorName
	else nil
local hoveredAnchorName: string? = nil
local checkOtherFramesEnabled = readPluginBooleanSetting(CHECK_OTHER_FRAMES_SETTING_KEY) or false

local toolbar = plugin:CreateToolbar("Anchor Point")
local toolbarButton = toolbar:CreateButton(
	"Anchor Point",
	"Change anchor points on selected GUI objects",
	""
)
toolbarButton.ClickableWhenViewportHidden = true

local widgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false,
	false,
	300,
	500,
	240,
	300
)
local widget = plugin:CreateDockWidgetPluginGuiAsync("AnchorPointPickerWidget", widgetInfo)
widget.Title = "Anchor Point"

local guiTemplate = script:FindFirstChild("AnchorPointGUI")
local templateSource = if guiTemplate then guiTemplate:FindFirstChild("Frame") else nil

if not templateSource or not templateSource:IsA("GuiObject") then
	warn(string.format("[%s] Could not find AnchorPointGUI.Frame under plugin script", MODULE_NAME))
	return
end

local frame = templateSource:Clone()
frame.Name = "AnchorPointFrame"
frame.AnchorPoint = Vector2.zero
frame.Position = UDim2.fromScale(0, 0)
frame.Size = UDim2.fromScale(1, 1)
frame.Visible = true
frame.Parent = widget

local positionMode: PositionMode = getSavedPositionMode()
local listFrame = frame:FindFirstChild("List")
if not listFrame then
	warn(string.format("[%s] AnchorPointGUI.Frame.List was not found", MODULE_NAME))
	return
end

local gapToEdgeInput = listFrame:FindFirstChild("GapToEdge")

local function normalizeGapInput(): number
	if not gapToEdgeInput or not gapToEdgeInput:IsA("TextBox") then
		return 0
	end

	local gap = tonumber(gapToEdgeInput.Text)
	if not gap or gap ~= gap or gap < 0 or gap > 0.5 or gap == math.huge then
		warn(string.format("[%s] GapToEdge must be a number from 0 to 0.5; using zero", MODULE_NAME))
		gap = 0
	end

	local normalizedGap = string.format("%.15g", gap)
	gapToEdgeInput.Text = normalizedGap
	savePluginSetting(GAP_SETTING_KEY, normalizedGap)
	return gap
end

if gapToEdgeInput and gapToEdgeInput:IsA("TextBox") then
	local savedGap = readPluginSetting(GAP_SETTING_KEY)
	if savedGap then
		gapToEdgeInput.Text = savedGap
	elseif gapToEdgeInput.Text == "" then
		gapToEdgeInput.Text = "0"
	end
	table.insert(connections, gapToEdgeInput.FocusLost:Connect(function()
		normalizeGapInput()
	end))
else
	warn(string.format("[%s] List.GapToEdge TextBox was not found; using zero gap", MODULE_NAME))
	gapToEdgeInput = nil
end
normalizeGapInput()

local checkOtherFramesContainer = listFrame:FindFirstChild("CheckOtherFrames")
local checkOtherFramesCenter = if checkOtherFramesContainer
	then checkOtherFramesContainer:FindFirstChild("Center")
	else nil
local checkOtherFramesButton = if checkOtherFramesCenter
	then checkOtherFramesCenter:FindFirstChild("Button")
	else nil

local function refreshCheckOtherFramesButton()
	if checkOtherFramesButton and checkOtherFramesButton:IsA("GuiButton") then
		checkOtherFramesButton.Active = true
		checkOtherFramesButton.Visible = true
		checkOtherFramesButton.BackgroundTransparency = if checkOtherFramesEnabled then 0 else 1
	end
end

if checkOtherFramesButton and checkOtherFramesButton:IsA("GuiButton") then
	refreshCheckOtherFramesButton()
	table.insert(connections, checkOtherFramesButton.Activated:Connect(function()
		checkOtherFramesEnabled = not checkOtherFramesEnabled
		savePluginSetting(CHECK_OTHER_FRAMES_SETTING_KEY, checkOtherFramesEnabled)
		refreshCheckOtherFramesButton()
	end))
else
	warn(string.format("[%s] List.CheckOtherFrames.Center.Button was not found", MODULE_NAME))
end

local function getModeButton(modeName: PositionMode): TextButton?
	local modeContainer = listFrame:FindFirstChild(modeName)
	local center = if modeContainer then modeContainer:FindFirstChild("Center") else nil
	local button = if center then center:FindFirstChild("Button") else nil

	if button and button:IsA("TextButton") then
		return button
	end

	return nil
end

local changePosButton = getModeButton("ChangePos")
local changePosOnlyButton = getModeButton("ChangePos1")
local stayInPosButton = getModeButton("StayInPos")

local function refreshModeButtons()
	if changePosButton then
		changePosButton.Active = true
		changePosButton.Visible = true
		changePosButton.BackgroundTransparency = if positionMode == "ChangePos" then 0 else 1
	end
	if changePosOnlyButton then
		changePosOnlyButton.Active = true
		changePosOnlyButton.Visible = true
		changePosOnlyButton.BackgroundTransparency = if positionMode == "ChangePos1" then 0 else 1
	end
	if stayInPosButton then
		stayInPosButton.Active = true
		stayInPosButton.Visible = true
		stayInPosButton.BackgroundTransparency = if positionMode == "StayInPos" then 0 else 1
	end
end

local function setPositionMode(mode: PositionMode)
	positionMode = mode
	savePluginSetting(POSITION_MODE_SETTING_KEY, mode)
	refreshModeButtons()
end

if changePosButton then
	table.insert(connections, changePosButton.Activated:Connect(function()
		setPositionMode("ChangePos")
	end))
else
	warn(string.format("[%s] List.ChangePos.Center.Button was not found", MODULE_NAME))
end

if changePosOnlyButton then
	table.insert(connections, changePosOnlyButton.Activated:Connect(function()
		setPositionMode("ChangePos1")
	end))
else
	warn(string.format("[%s] List.ChangePos1.Center.Button was not found", MODULE_NAME))
end

if stayInPosButton then
	table.insert(connections, stayInPosButton.Activated:Connect(function()
		setPositionMode("StayInPos")
	end))
else
	warn(string.format("[%s] List.StayInPos.Center.Button was not found", MODULE_NAME))
end

refreshModeButtons()

local function getGapToEdge(): number
	return normalizeGapInput()
end

local function applyGapToAnchorPosition(anchorPoint: Vector2, gap: number): Vector2
	local x = anchorPoint.X
	local y = anchorPoint.Y

	if x == 0 then
		x = gap
	elseif x == 1 then
		x = 1 - gap
	end

	if y == 0 then
		y = gap
	elseif y == 1 then
		y = 1 - gap
	end

	return Vector2.new(x, y)
end

local function getParentBounds(parent: Instance): (Vector2?, Vector2?)
	if parent:IsA("GuiObject") then
		return parent.AbsolutePosition, parent.AbsoluteSize
	end
	if parent:IsA("ScreenGui") then
		local camera = Workspace.CurrentCamera
		if not camera then
			return nil, nil
		end
		local viewportSize = camera.ViewportSize
		if parent.IgnoreGuiInset then
			return Vector2.zero, viewportSize
		end
		local topLeftInset, bottomRightInset = GuiService:GetGuiInset()
		return topLeftInset, Vector2.new(
			viewportSize.X - topLeftInset.X - bottomRightInset.X,
			viewportSize.Y - topLeftInset.Y - bottomRightInset.Y
		)
	end
	return nil, nil
end

local function overlapsVerticallyWithGap(
	object: GuiObject,
	sibling: GuiObject,
	gapPixels: number,
	anchorPoint: Vector2
): number?
	local objectPosition = object.AbsolutePosition
	local objectSize = object.AbsoluteSize
	local siblingPosition = sibling.AbsolutePosition
	local siblingSize = sibling.AbsoluteSize
	local horizontalOverlap = objectPosition.X < siblingPosition.X + siblingSize.X
		and objectPosition.X + objectSize.X > siblingPosition.X
	local verticalOverlap = objectPosition.Y < siblingPosition.Y + siblingSize.Y + gapPixels
		and objectPosition.Y + objectSize.Y + gapPixels > siblingPosition.Y

	if not horizontalOverlap or not verticalOverlap then
		return nil
	end

	if anchorPoint.Y >= 0.5 then
		return siblingPosition.Y - gapPixels - (objectPosition.Y + objectSize.Y)
	end
	return siblingPosition.Y + siblingSize.Y + gapPixels - objectPosition.Y
end

local function avoidVisibleSiblingFrames(object: GuiObject, selectedObjects: { [GuiObject]: boolean }, anchorPoint: Vector2, edgeGap: number)
	local parent = object.Parent
	if not parent then
		return
	end
	local parentPosition, parentSize = getParentBounds(parent)
	if not parentPosition or not parentSize or parentSize.Y <= 0 then
		warn(string.format("[%s] Cannot check sibling frames for %s: parent bounds unavailable", MODULE_NAME, object:GetFullName()))
		return
	end

	local edgeGapPixels = edgeGap * parentSize.Y
	if object.AbsoluteSize.Y + edgeGapPixels * 2 > parentSize.Y then
		warn(string.format("[%s] Cannot keep %s inside parent while honoring GapToEdge", MODULE_NAME, object:GetFullName()))
		return
	end
	if parent:IsA("GuiObject")
		and (parent:FindFirstChildWhichIsA("UIListLayout") or parent:FindFirstChildWhichIsA("UIGridLayout"))
	then
		warn(string.format("[%s] Cannot reposition %s: parent layout controls child positions", MODULE_NAME, object:GetFullName()))
		return
	end

	local siblings: { GuiObject } = {}
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and child ~= object and child.Visible and not selectedObjects[child] then
			table.insert(siblings, child)
		end
	end

	local moved = false
	for _ = 1, 32 do
		local shiftY = 0
		for _, sibling in siblings do
			local requiredShift = overlapsVerticallyWithGap(object, sibling, edgeGapPixels, anchorPoint)
			if requiredShift then
				shiftY = if anchorPoint.Y >= 0.5
					then math.min(shiftY, requiredShift)
					else math.max(shiftY, requiredShift)
			end
		end
		if shiftY == 0 then
			break
		end

		local currentPosition = object.AbsolutePosition
		local objectSize = object.AbsoluteSize
		local minimumY = parentPosition.Y + edgeGapPixels
		local maximumY = parentPosition.Y + parentSize.Y - edgeGapPixels - objectSize.Y
		local destinationY = math.clamp(currentPosition.Y + shiftY, minimumY, maximumY)
		local appliedShift = destinationY - currentPosition.Y
		if appliedShift == 0 then
			break
		end

		local position = object.Position
		object.Position = UDim2.new(
			position.X.Scale,
			position.X.Offset,
			position.Y.Scale,
			position.Y.Offset + appliedShift
		)
		moved = true
	end

	if moved then
		local stillOverlaps = false
		for _, sibling in siblings do
			if overlapsVerticallyWithGap(object, sibling, edgeGapPixels, anchorPoint) then
				stillOverlaps = true
				break
			end
		end
		if stillOverlaps then
			warn(string.format("[%s] Could not fully avoid sibling frame overlap for %s", MODULE_NAME, object:GetFullName()))
		end
	end
end

local function applyAnchorPointToObject(object: GuiObject, anchorPoint: Vector2, edgeGap: number)
	local anchorDelta = anchorPoint - object.AnchorPoint

	if positionMode == "StayInPos" then
		local position = object.Position
		local size = object.Size
		object.Position = UDim2.new(
			position.X.Scale + anchorDelta.X * size.X.Scale,
			position.X.Offset + anchorDelta.X * size.X.Offset,
			position.Y.Scale + anchorDelta.Y * size.Y.Scale,
			position.Y.Offset + anchorDelta.Y * size.Y.Offset
		)
	else
		local adjustedPosition = applyGapToAnchorPosition(anchorPoint, edgeGap)
		object.Position = UDim2.fromScale(adjustedPosition.X, adjustedPosition.Y)
		if positionMode == "ChangePos" then
			object.AnchorPoint = anchorPoint
		end
	end

	if positionMode == "StayInPos" then
		object.AnchorPoint = anchorPoint
	end
end

local function applyAnchorPoint(anchorName: string, anchorPoint: Vector2)
	local selectedGuiObjects: { GuiObject } = {}
	for _, selectedObject in Selection:Get() do
		if selectedObject:IsA("GuiObject") then
			table.insert(selectedGuiObjects, selectedObject)
		end
	end

	if #selectedGuiObjects == 0 then
		warn(string.format("[%s] Select one or more GUI objects first", MODULE_NAME))
		return
	end

	local recording = ChangeHistoryService:TryBeginRecording("SetGuiAnchorPoint")
	if not recording then
		warn(string.format("[%s] Could not begin undo recording", MODULE_NAME))
		return
	end
	local edgeGap = if positionMode == "StayInPos" then 0 else getGapToEdge()
	local selectedSet: { [GuiObject]: boolean } = {}
	for _, object in selectedGuiObjects do
		selectedSet[object] = true
	end

	local success, failure = pcall(function()
		for _, object in selectedGuiObjects do
			applyAnchorPointToObject(object, anchorPoint, edgeGap)
			if checkOtherFramesEnabled and positionMode ~= "StayInPos" then
				avoidVisibleSiblingFrames(object, selectedSet, anchorPoint, edgeGap)
			end
		end
	end)

	if success then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	else
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Cancel)
		warn(string.format("[%s] Failed setting %s anchor point: %s", MODULE_NAME, anchorName, tostring(failure)))
	end
end

local anchorSelection = listFrame:FindFirstChild("AnchorSelection")
if not anchorSelection then
	warn(string.format("[%s] List.AnchorSelection frame was not found", MODULE_NAME))
	return
end

local function tweenAnchorCell(anchorName: string)
	local cellState = anchorCellColors[anchorName]
	if not cellState then
		return
	end

	local colorMultiplier = if selectedAnchorName == anchorName then SELECTED_COLOR_MULTIPLIER else 1
	if hoveredAnchorName == anchorName then
		colorMultiplier = HOVER_COLOR_MULTIPLIER
	end
	local targetColor = Color3.new(
		math.clamp(cellState.baseColor.R * colorMultiplier, 0, 1),
		math.clamp(cellState.baseColor.G * colorMultiplier, 0, 1),
		math.clamp(cellState.baseColor.B * colorMultiplier, 0, 1)
	)

	local activeTween = activeTweens[cellState.cell]
	if activeTween then
		activeTween:Cancel()
	end

	local tween = TweenService:Create(cellState.cell, createHoverTweenInfo(), {
		BackgroundColor3 = targetColor,
	})
	activeTweens[cellState.cell] = tween
	tween:Play()
end

local function refreshGridFromSelection()
	local nextAnchorName: string? = nil
	for _, selectedObject in Selection:Get() do
		if selectedObject:IsA("GuiObject") then
			for anchorName, anchorPoint in ANCHOR_POINTS do
				if selectedObject.AnchorPoint == anchorPoint then
					nextAnchorName = anchorName
					break
				end
			end
			break
		end
	end

	selectedAnchorName = nextAnchorName
	for cellName in anchorCellColors do
		tweenAnchorCell(cellName)
	end
end

table.insert(connections, Selection.SelectionChanged:Connect(refreshGridFromSelection))

for anchorName, anchorPoint in ANCHOR_POINTS do
	local anchorCell = anchorSelection:FindFirstChild(anchorName)
	local anchorButton = if anchorCell then anchorCell:FindFirstChild("ImageButton") else nil

	if anchorCell and anchorCell:IsA("GuiObject") and anchorButton and anchorButton:IsA("ImageButton") then
		anchorCellColors[anchorName] = {
			cell = anchorCell,
			baseColor = anchorCell.BackgroundColor3,
		}
		anchorButton.Active = true
		anchorButton.Visible = true
		if selectedAnchorName == anchorName then
			tweenAnchorCell(anchorName)
		end
		table.insert(connections, anchorButton.MouseEnter:Connect(function()
			hoveredAnchorName = anchorName
			tweenAnchorCell(anchorName)
		end))
		table.insert(connections, anchorButton.MouseLeave:Connect(function()
			if hoveredAnchorName == anchorName then
				hoveredAnchorName = nil
			end
			tweenAnchorCell(anchorName)
		end))
		table.insert(connections, anchorButton.Activated:Connect(function()
			selectedAnchorName = anchorName
			savePluginSetting(SELECTED_ANCHOR_SETTING_KEY, anchorName)
			for cellName in anchorCellColors do
				tweenAnchorCell(cellName)
			end
			applyAnchorPoint(anchorName, anchorPoint)
		end))
	else
		warn(string.format("[%s] List.AnchorSelection.%s.ImageButton was not found", MODULE_NAME, anchorName))
	end
end

refreshGridFromSelection()

table.insert(connections, toolbarButton.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	toolbarButton:SetActive(widget.Enabled)
end))

plugin.Unloading:Connect(function()
	if gapToEdgeInput and gapToEdgeInput:IsA("TextBox") then
		savePluginSetting(GAP_SETTING_KEY, gapToEdgeInput.Text)
	end
	savePluginSetting(CHECK_OTHER_FRAMES_SETTING_KEY, checkOtherFramesEnabled)
	savePluginSetting(POSITION_MODE_SETTING_KEY, positionMode)
	if selectedAnchorName then
		savePluginSetting(SELECTED_ANCHOR_SETTING_KEY, selectedAnchorName)
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	for _, tween in activeTweens do
		tween:Cancel()
	end
	table.clear(activeTweens)
	table.clear(anchorCellColors)
end)
