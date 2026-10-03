--!strict

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Maid = require(ReplicatedStorage.Modules.Maid)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)

local NotificationLayoutController = {}
NotificationLayoutController.__index = NotificationLayoutController

local DEFAULT_TOP_SCALE = 0.077
local LAYOUT_GAP_PIXELS = 12
local DEFAULT_END_POSITION = UDim2.new(0.214, 0, DEFAULT_TOP_SCALE, 0)
local LAYOUT_TWEEN_INFO = TweenConfig.NotificationLayout
local POST_LAYOUT_REFRESH_FRAMES = 5

local NOTIFICATION_FRAME_NAMES = {
	"MinigameNotificationFrame",
	"NotificationFrame",
	"LevelUpFrame",
}

local RESERVED_FRAME_NAMES = {
	"EventFrameList",
	"EventProgress",
	"StageProgressFrame",
}

local TOP_ANCHOR_FRAME_NAMES = {
	"EventProgress",
	"StageProgressFrame",
}

type LayoutControllerObject = {
	screenGui: ScreenGui,
	frames: { [string]: GuiObject? },
	reservedFrames: { [string]: GuiObject? },
	originalPositions: { [GuiObject]: UDim2 },
	positionTweens: { [GuiObject]: Tween },
	visibilityStates: { [GuiObject]: boolean },
	pendingAnimationFrames: { [GuiObject]: boolean },
	maid: any,
	referenceMaid: any,
	initialized: boolean,
	postLayoutRefreshQueued: boolean,
	lastReferenceSignature: string?,
	lastTargetSignature: string?,
}

type LayoutControllerType = LayoutControllerObject

local activeController: LayoutControllerType? = nil

local function collectGuiObjects(screenGui: ScreenGui, name: string): { GuiObject }
	local matches: { GuiObject } = {}
	local seen: { [GuiObject]: boolean } = {}

	local function collectFrom(root: Instance)
		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant.Name == name and descendant:IsA("GuiObject") and not seen[descendant] then
				seen[descendant] = true
				table.insert(matches, descendant)
			end
		end
	end

	collectFrom(screenGui)

	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		for _, child in ipairs(playerGui:GetChildren()) do
			if child:IsA("ScreenGui") and child ~= screenGui then
				collectFrom(child)
			end
		end
	end

	return matches
end

local function getViewportHeight(): number
	local camera = Workspace.CurrentCamera
	if not camera then
		return 1
	end
	return math.max(1, camera.ViewportSize.Y)
end

local function getHeightScale(frame: GuiObject, viewportHeight: number): number
	local absoluteHeight = frame.AbsoluteSize.Y
	if absoluteHeight > 0 then
		return absoluteHeight / viewportHeight
	end

	return math.max(0, (frame.Size.Y.Scale * viewportHeight + frame.Size.Y.Offset) / viewportHeight)
end

local function getOwningScreenGui(frame: GuiObject, fallback: ScreenGui): ScreenGui
	local ancestor = frame:FindFirstAncestorOfClass("ScreenGui")
	return if ancestor then ancestor else fallback
end

local function isEffectivelyVisible(frame: GuiObject, fallbackScreenGui: ScreenGui): boolean
	local current: Instance? = frame
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("ScreenGui") then
			return current.Enabled
		end
		current = current.Parent
	end

	return frame:IsDescendantOf(fallbackScreenGui)
end

local function findGuiObject(screenGui: ScreenGui, name: string): GuiObject?
	local matches = collectGuiObjects(screenGui, name)
	if #matches == 0 then
		return nil
	end

	-- Studio can retain a hidden copy after a GUI is moved or changed class.
	-- Use the active visible copy so layout follows what the player sees.
	for _, match in ipairs(matches) do
		if isEffectivelyVisible(match, screenGui) then
			return match
		end
	end

	return matches[1]
end

local function getVisibleBounds(
	frame: GuiObject,
	screenGui: ScreenGui,
	viewportHeight: number
): (number, number)
	if not isEffectivelyVisible(frame, screenGui) then
		return 0, 0
	end

	local absoluteTop = frame.AbsolutePosition.Y
	local absoluteBottom = absoluteTop + frame.AbsoluteSize.Y
	local visibleTop = math.clamp(absoluteTop, 0, viewportHeight)
	local visibleBottom = math.clamp(absoluteBottom, 0, viewportHeight)
	if visibleBottom < visibleTop then
		visibleBottom = visibleTop
	end

	if frame:IsA("ScrollingFrame") and not frame.ClipsDescendants then
		local canvasBottom = frame.AbsolutePosition.Y
			- frame.CanvasPosition.Y
			+ frame.AbsoluteCanvasSize.Y
		visibleBottom = math.max(visibleBottom, math.min(canvasBottom, viewportHeight))
	end

	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("GuiObject") and isEffectivelyVisible(descendant, screenGui) then
			local descendantTop = descendant.AbsolutePosition.Y
			local descendantBottom = descendantTop + descendant.AbsoluteSize.Y
			local ancestor: Instance? = descendant.Parent
			while ancestor and ancestor ~= screenGui do
				if ancestor:IsA("GuiObject") and ancestor.ClipsDescendants then
					local ancestorTop = ancestor.AbsolutePosition.Y
					local ancestorBottom = ancestorTop + ancestor.AbsoluteSize.Y
					descendantTop = math.max(descendantTop, ancestorTop)
					descendantBottom = math.min(descendantBottom, ancestorBottom)
				end
				ancestor = ancestor.Parent
			end

			descendantTop = math.max(descendantTop, 0)
			descendantBottom = math.min(descendantBottom, viewportHeight)
			if descendantBottom > descendantTop then
				visibleTop = math.min(visibleTop, descendantTop)
				visibleBottom = math.max(visibleBottom, descendantBottom)
			end
		end
	end

	if visibleBottom <= visibleTop then
		return 0, 0
	end

	return visibleTop / viewportHeight, math.max(0, visibleBottom / viewportHeight)
end

local function getVisibleBottomScale(frame: GuiObject, screenGui: ScreenGui, viewportHeight: number): number
	local _, bottomScale = getVisibleBounds(frame, screenGui, viewportHeight)
	return bottomScale
end

local function getLayoutRootBottomScale(
	frame: GuiObject,
	screenGui: ScreenGui,
	viewportHeight: number
): number
	if not isEffectivelyVisible(frame, screenGui) then
		return 0
	end

	local parentTop = 0
	local parentHeight = viewportHeight
	local parent = frame.Parent
	if parent and parent:IsA("GuiObject") then
		parentTop = parent.AbsolutePosition.Y
		parentHeight = math.max(1, parent.AbsoluteSize.Y)
	end

	local localTop = frame.Position.Y.Scale * parentHeight + frame.Position.Y.Offset
	local localHeight = frame.Size.Y.Scale * parentHeight + frame.Size.Y.Offset
	local bottom = parentTop + localTop + (1 - frame.AnchorPoint.Y) * localHeight
	return math.clamp(bottom / viewportHeight, 0, 1)
end

local function getReservedBottomScale(
	reservedName: string,
	frame: GuiObject,
	screenGui: ScreenGui,
	viewportHeight: number
): number
	if reservedName == "EventProgress" or reservedName == "StageProgressFrame" then
		return getLayoutRootBottomScale(frame, screenGui, viewportHeight)
	end

	return getVisibleBottomScale(frame, screenGui, viewportHeight)
end

local function getVisibleHeightScale(frame: GuiObject, screenGui: ScreenGui, viewportHeight: number): number
	local topScale, bottomScale = getVisibleBounds(frame, screenGui, viewportHeight)
	if bottomScale <= topScale then
		return getHeightScale(frame, viewportHeight)
	end

	return bottomScale - topScale
end

local function getTopProtrusionScale(
	frame: GuiObject,
	screenGui: ScreenGui,
	viewportHeight: number
): number
	local contentTopScale, contentBottomScale = getVisibleBounds(frame, screenGui, viewportHeight)
	if contentBottomScale <= contentTopScale then
		return 0
	end

	local rootTopScale = math.clamp(frame.AbsolutePosition.Y, 0, viewportHeight) / viewportHeight
	return math.max(0, rootTopScale - contentTopScale)
end

local function getRootTopScaleForPosition(
	frame: GuiObject,
	position: UDim2,
	viewportHeight: number
): number
	return position.Y.Scale
		- frame.AnchorPoint.Y * getHeightScale(frame, viewportHeight)
		+ position.Y.Offset / viewportHeight
end

local function describeGuiObject(
	frame: GuiObject?,
	fallbackScreenGui: ScreenGui,
	rootOnly: boolean?
): string
	if not frame or not frame.Parent then
		return "missing"
	end
	local viewportHeight = getViewportHeight()
	local rootBottom = (frame.AbsolutePosition.Y + frame.AbsoluteSize.Y) / viewportHeight
	local contentBottom = if rootOnly == true
		then getLayoutRootBottomScale(frame, fallbackScreenGui, viewportHeight)
		else getVisibleBottomScale(frame, fallbackScreenGui, viewportHeight)

	return string.format(
		"%s|class=%s|visible=%s|rootBottom=%.3f|contentBottom=%.3f",
		frame:GetFullName(),
		frame.ClassName,
		tostring(isEffectivelyVisible(frame, fallbackScreenGui)),
		rootBottom,
		contentBottom
	)
end

local function connectAncestorVisibilitySignals(
	screenGui: ScreenGui,
	frame: GuiObject,
	callback: () -> (),
	maid: any
)
	local current: Instance? = frame
	while current and current ~= screenGui do
		if current:IsA("GuiObject") then
			maid:GiveTask(current:GetPropertyChangedSignal("Visible"):Connect(callback))
		end
		current = current.Parent
	end
end

local function connectGuiBoundsSignals(
	frame: GuiObject,
	callback: () -> (),
	maid: any,
	trackAbsolutePosition: boolean?
)
	if trackAbsolutePosition ~= false then
		maid:GiveTask(frame:GetPropertyChangedSignal("AbsolutePosition"):Connect(callback))
	end
	maid:GiveTask(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(callback))
	maid:GiveTask(frame:GetPropertyChangedSignal("Visible"):Connect(callback))
	if frame:IsA("ScrollingFrame") then
		maid:GiveTask(frame:GetPropertyChangedSignal("CanvasPosition"):Connect(callback))
		maid:GiveTask(frame:GetPropertyChangedSignal("CanvasSize"):Connect(callback))
		maid:GiveTask(frame:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(callback))
	end

	for _, descendant in ipairs(frame:GetDescendants()) do
		if descendant:IsA("UIListLayout") then
			maid:GiveTask(descendant:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(callback))
		end
		if descendant:IsA("GuiObject") then
			if trackAbsolutePosition ~= false then
				maid:GiveTask(descendant:GetPropertyChangedSignal("AbsolutePosition"):Connect(callback))
			end
			maid:GiveTask(descendant:GetPropertyChangedSignal("AbsoluteSize"):Connect(callback))
			maid:GiveTask(descendant:GetPropertyChangedSignal("Visible"):Connect(callback))
		end
	end
end

local function getPositionForTop(frame: GuiObject, topScale: number, viewportHeight: number): UDim2
	local currentPosition = frame.Position
	local frameHeightScale = getHeightScale(frame, viewportHeight)
	local yOffset = currentPosition.Y.Offset
	local yScale = topScale + frame.AnchorPoint.Y * frameHeightScale - yOffset / viewportHeight

	return UDim2.new(currentPosition.X.Scale, currentPosition.X.Offset, yScale, yOffset)
end

local function isTrackedFrameName(name: string): boolean
	for _, trackedName in ipairs(NOTIFICATION_FRAME_NAMES) do
		if trackedName == name then
			return true
		end
	end
	return false
end

local function isReservedFrameName(name: string): boolean
	for _, reservedName in ipairs(RESERVED_FRAME_NAMES) do
		if reservedName == name then
			return true
		end
	end
	return false
end

function NotificationLayoutController.new(screenGui: ScreenGui): LayoutControllerType
	return setmetatable({
		screenGui = screenGui,
		frames = {},
		reservedFrames = {},
		originalPositions = {},
		positionTweens = {},
		visibilityStates = {},
		pendingAnimationFrames = {},
		maid = Maid.new(),
		referenceMaid = Maid.new(),
		initialized = false,
		postLayoutRefreshQueued = false,
		lastReferenceSignature = nil,
		lastTargetSignature = nil,
	}, NotificationLayoutController)
end

local function resolveReservedFrame(
	screenGui: ScreenGui,
	reservedFrames: { [string]: GuiObject? },
	reservedName: string
): GuiObject?
	local currentFrame = reservedFrames[reservedName]
	if currentFrame and currentFrame.Parent and isEffectivelyVisible(currentFrame, screenGui) then
		return currentFrame
	end

	local visibleFrame = findGuiObject(screenGui, reservedName)
	return if visibleFrame then visibleFrame else currentFrame
end

local function calculateTargets(
	screenGui: ScreenGui,
	frames: { [string]: GuiObject? },
	reservedFrames: { [string]: GuiObject? },
	includedFrame: GuiObject?,
	originalPositions: { [GuiObject]: UDim2 }
): { [GuiObject]: UDim2 }
	local viewportHeight = getViewportHeight()
	local topAnchorBottomScale = 0

	for _, reservedName in ipairs(TOP_ANCHOR_FRAME_NAMES) do
		local reservedFrame = resolveReservedFrame(screenGui, reservedFrames, reservedName)
		if reservedFrames[reservedName] ~= reservedFrame then
			reservedFrames[reservedName] = reservedFrame
		end
		if reservedFrame and reservedFrame.Parent then
			local reservedBottomScale = getReservedBottomScale(
				reservedName,
				reservedFrame,
				screenGui,
				viewportHeight
			)
			if reservedBottomScale > 0 then
				topAnchorBottomScale = math.max(topAnchorBottomScale, reservedBottomScale)
			end
		end
	end

	local nextTopScale = if topAnchorBottomScale > 0
		then topAnchorBottomScale + LAYOUT_GAP_PIXELS / viewportHeight
		else DEFAULT_TOP_SCALE

	local targets: { [GuiObject]: UDim2 } = {}
	local eventFrame = resolveReservedFrame(screenGui, reservedFrames, "EventFrameList")
	if eventFrame and eventFrame.Parent and isEffectivelyVisible(eventFrame, screenGui) then
		local topProtrusionScale = getTopProtrusionScale(eventFrame, screenGui, viewportHeight)
		local eventRootTopScale: number
		local eventContentTopScale: number
		if topAnchorBottomScale > 0 then
			eventContentTopScale = nextTopScale
			eventRootTopScale = eventContentTopScale + topProtrusionScale
		else
			local originalPosition = originalPositions[eventFrame] or eventFrame.Position
			eventRootTopScale = getRootTopScaleForPosition(eventFrame, originalPosition, viewportHeight)
			eventContentTopScale = eventRootTopScale - topProtrusionScale
		end

		targets[eventFrame] = getPositionForTop(eventFrame, eventRootTopScale, viewportHeight)
		local eventTopScale, eventBottomScale = getVisibleBounds(eventFrame, screenGui, viewportHeight)
		local eventHeightScale = eventBottomScale - eventTopScale
		if eventHeightScale <= 0 then
			eventHeightScale = getHeightScale(eventFrame, viewportHeight)
		end
		nextTopScale = eventContentTopScale
			+ eventHeightScale
			+ LAYOUT_GAP_PIXELS / viewportHeight
	end

	for _, frameName in ipairs(NOTIFICATION_FRAME_NAMES) do
		local frame = frames[frameName]
		if
			frame
			and frame.Parent
			and (isEffectivelyVisible(frame, screenGui) or frame == includedFrame)
		then
			local frameTopProtrusionScale = getTopProtrusionScale(frame, screenGui, viewportHeight)
			local frameContentTopScale = nextTopScale
			targets[frame] = getPositionForTop(
				frame,
				frameContentTopScale + frameTopProtrusionScale,
				viewportHeight
			)
			nextTopScale = frameContentTopScale
				+ getVisibleHeightScale(frame, screenGui, viewportHeight)
				+ LAYOUT_GAP_PIXELS / viewportHeight
		end
	end

	return targets
end

function NotificationLayoutController._calculateTargets(
	self: LayoutControllerType,
	includedFrame: GuiObject?
): { [GuiObject]: UDim2 }
	return calculateTargets(self.screenGui, self.frames, self.reservedFrames, includedFrame, self.originalPositions)
end

function NotificationLayoutController._queuePostLayoutRefresh(self: LayoutControllerType)
	if self.postLayoutRefreshQueued then
		return
	end

	self.postLayoutRefreshQueued = true
	task.defer(function()
		if not self.initialized then
			self.postLayoutRefreshQueued = false
			return
		end

		local remainingPasses = POST_LAYOUT_REFRESH_FRAMES
		local connection: RBXScriptConnection? = nil
		connection = RunService.RenderStepped:Connect(function()
			remainingPasses -= 1
			if remainingPasses > 0 then
				return
			end
			if connection then
				connection:Disconnect()
				connection = nil
			end
			self.postLayoutRefreshQueued = false
			if self.initialized then
				self:_applyTargets(nil)
			end
		end)
		self.maid:GiveTask(connection)
	end)
end

function NotificationLayoutController.refresh(self: LayoutControllerType)
	self:_applyTargets(nil)
	self:_queuePostLayoutRefresh()
end

function NotificationLayoutController._stopPositionTween(self: LayoutControllerType, frame: GuiObject)
	local tween = self.positionTweens[frame]
	if tween then
		tween:Cancel()
		tween:Destroy()
		self.positionTweens[frame] = nil
	end
end

function NotificationLayoutController._applyTargets(
	self: LayoutControllerType,
	skipTweenFrame: GuiObject?,
	preserveFrame: GuiObject?
)
	if not self.initialized then
		return
	end

	local targets = self:_calculateTargets(nil)
	local targetParts: { string } = {}
	local reservedParts: { string } = {}
	local viewportHeight = getViewportHeight()
	for _, reservedName in ipairs(RESERVED_FRAME_NAMES) do
		local reservedFrame = self.reservedFrames[reservedName]
		local bottomScale = if reservedFrame
			then getReservedBottomScale(reservedName, reservedFrame, self.screenGui, viewportHeight)
			else 0
		table.insert(reservedParts, string.format("%s=%.3f", reservedName, bottomScale))
	end
	table.insert(targetParts, "reserved=" .. table.concat(reservedParts, ","))
	local eventFrame = self.reservedFrames.EventFrameList
	local eventTargetPosition = if eventFrame then targets[eventFrame] else nil
	if eventFrame and eventTargetPosition then
		table.insert(
			targetParts,
			string.format(
				"EventFrameListTarget=%.3f+%d",
				eventTargetPosition.Y.Scale,
				eventTargetPosition.Y.Offset
			)
		)
	end
	for _, frameName in ipairs(NOTIFICATION_FRAME_NAMES) do
		local frame = self.frames[frameName]
		local targetPosition = if frame then targets[frame] else nil
		if frame and targetPosition then
			table.insert(
				targetParts,
				string.format(
					"%s=%.3f+%d|visible=%s",
					frameName,
					targetPosition.Y.Scale,
					targetPosition.Y.Offset,
					tostring(isEffectivelyVisible(frame, self.screenGui))
				)
			)
		end
	end
	local targetSignature = table.concat(targetParts, ";")
	if targetSignature ~= self.lastTargetSignature then
		self.lastTargetSignature = targetSignature
		DebugModule.debugPrint("Notification targets recalculated | " .. targetSignature, "NotificationLayoutController")
	end

	for frame, _ in pairs(self.positionTweens) do
		if not targets[frame] then
			self:_stopPositionTween(frame)
		end
	end

	for frame, targetPosition in pairs(targets) do
		if frame == preserveFrame then
			self:_stopPositionTween(frame)
		elseif frame == skipTweenFrame then
			self:_stopPositionTween(frame)
			frame.Position = targetPosition
		elseif frame.Position ~= targetPosition then
			self:_stopPositionTween(frame)
			local tween = TweenService:Create(frame, LAYOUT_TWEEN_INFO, {
				Position = targetPosition,
			})
			self.positionTweens[frame] = tween
			tween.Completed:Once(function()
				if self.positionTweens[frame] == tween then
					self.positionTweens[frame] = nil
				end
				tween:Destroy()
			end)
			tween:Play()
		end
	end
end

function NotificationLayoutController._refreshReferences(self: LayoutControllerType)
	self.referenceMaid:DoCleaning()

	for _, frameName in ipairs(NOTIFICATION_FRAME_NAMES) do
		local frame = findGuiObject(self.screenGui, frameName)
		self.frames[frameName] = frame
		if frame and self.originalPositions[frame] == nil then
			self.originalPositions[frame] = frame.Position
		end
		if frame then
			self.visibilityStates[frame] = isEffectivelyVisible(frame, self.screenGui)
			local function refreshFrameVisibility()
				local wasVisible = self.visibilityStates[frame] == true
				local preserveFrame = self.pendingAnimationFrames[frame] == true
				self.pendingAnimationFrames[frame] = nil
				local isVisible = isEffectivelyVisible(frame, self.screenGui)
				self.visibilityStates[frame] = isVisible
				self:_applyTargets(
					if isVisible and not wasVisible and not preserveFrame then frame else nil,
					if preserveFrame then frame else nil
				)
			end
			connectAncestorVisibilitySignals(
				getOwningScreenGui(frame, self.screenGui),
				frame,
				refreshFrameVisibility,
				self.referenceMaid
			)
			self.referenceMaid:GiveTask(frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				self:refresh()
			end))
		end
	end

	for _, reservedName in ipairs(RESERVED_FRAME_NAMES) do
		local candidates = collectGuiObjects(self.screenGui, reservedName)
		local frame = findGuiObject(self.screenGui, reservedName)
		self.reservedFrames[reservedName] = frame
		if frame and self.originalPositions[frame] == nil then
			self.originalPositions[frame] = frame.Position
		end
		for _, candidate in ipairs(candidates) do
			connectAncestorVisibilitySignals(
				getOwningScreenGui(candidate, self.screenGui),
				candidate,
				function()
					-- A hidden template can become the live copy after initialization.
					-- Re-select the visible copy before measuring its bounds.
					self:_refreshReferences()
				end,
				self.referenceMaid
			)
			connectGuiBoundsSignals(
				candidate,
				function()
					self:refresh()
				end,
				self.referenceMaid,
				reservedName ~= "EventFrameList"
			)
			self.referenceMaid:GiveTask(candidate.DescendantAdded:Connect(function()
				-- Dynamic cards and progress markers must be included in bounds tracking.
				self:_refreshReferences()
			end))
			self.referenceMaid:GiveTask(candidate.DescendantRemoving:Connect(function()
				self:refresh()
			end))
		end
	end

	local referenceSignature = table.concat({
		"Notification=" .. describeGuiObject(self.frames.NotificationFrame, self.screenGui),
		"Minigame=" .. describeGuiObject(self.frames.MinigameNotificationFrame, self.screenGui),
		"LevelUp=" .. describeGuiObject(self.frames.LevelUpFrame, self.screenGui),
		"Event=" .. describeGuiObject(self.reservedFrames.EventFrameList, self.screenGui),
		"EventProgress=" .. describeGuiObject(self.reservedFrames.EventProgress, self.screenGui, true),
		"Stage=" .. describeGuiObject(self.reservedFrames.StageProgressFrame, self.screenGui, true),
	}, " || ")
	if referenceSignature ~= self.lastReferenceSignature then
		self.lastReferenceSignature = referenceSignature
		DebugModule.debugPrint("Layout references refreshed | " .. referenceSignature, "NotificationLayoutController")
	end

	self:refresh()
end

function NotificationLayoutController:_getVisiblePosition(frame: GuiObject, includeFrame: boolean?): UDim2
	local targets = self:_calculateTargets(if includeFrame == true then frame else nil)
	return targets[frame] or frame.Position
end

function NotificationLayoutController:_getAnimationPositions(frame: GuiObject): (UDim2, UDim2)
	self:_stopPositionTween(frame)
	if not frame.Visible then
		self.pendingAnimationFrames[frame] = true
	end
	local endPosition = self:_getVisiblePosition(frame, true)
	local viewportHeight = getViewportHeight()
	local slideDistance = math.max(0.08, getHeightScale(frame, viewportHeight) + 0.015)
	local startPosition = UDim2.new(
		endPosition.X.Scale,
		endPosition.X.Offset,
		endPosition.Y.Scale + slideDistance,
		endPosition.Y.Offset
	)
	return startPosition, endPosition
end

function NotificationLayoutController:Init()
	if self.initialized then
		return
	end

	self.initialized = true
	activeController = self
	self:_refreshReferences()

	self.maid:GiveTask(self.screenGui.DescendantAdded:Connect(function(descendant: Instance)
		if isTrackedFrameName(descendant.Name) or isReservedFrameName(descendant.Name) then
			self:_refreshReferences()
		end
	end))
	self.maid:GiveTask(self.screenGui.DescendantRemoving:Connect(function(descendant: Instance)
		if isTrackedFrameName(descendant.Name) or isReservedFrameName(descendant.Name) then
			self:_refreshReferences()
		end
	end))

	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui then
		self.maid:GiveTask(playerGui.DescendantAdded:Connect(function(descendant: Instance)
			if isReservedFrameName(descendant.Name) then
				self:_refreshReferences()
			end
		end))
		self.maid:GiveTask(playerGui.DescendantRemoving:Connect(function(descendant: Instance)
			if isReservedFrameName(descendant.Name) then
				self:_refreshReferences()
			end
		end))
	end

	local boundCamera: Camera? = nil
	local function refreshCameraBinding()
		local camera = Workspace.CurrentCamera
		if camera ~= boundCamera then
			boundCamera = camera
			self.maid.ViewportChanged = if camera
				then camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
					self:refresh()
				end)
				else nil
		end
		self:refresh()
	end

	self.maid.CurrentCameraChanged = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refreshCameraBinding)
	refreshCameraBinding()
end

function NotificationLayoutController:Destroy()
	if not self.initialized then
		return
	end

	self.initialized = false
	self.referenceMaid:DoCleaning()
	self.maid:DoCleaning()
	for frame, _ in pairs(self.positionTweens) do
		self:_stopPositionTween(frame)
	end
	for frame, originalPosition in pairs(self.originalPositions) do
		if frame.Parent then
			frame.Position = originalPosition
		end
	end
	self.originalPositions = {}
	self.positionTweens = {}
	self.visibilityStates = {}
	self.pendingAnimationFrames = {}
	self.postLayoutRefreshQueued = false
	self.lastReferenceSignature = nil
	self.lastTargetSignature = nil
	self.frames = {}
	self.reservedFrames = {}
	if activeController == self then
		activeController = nil
	end
end

function NotificationLayoutController.GetVisiblePosition(frame: GuiObject, includeFrame: boolean?): UDim2
	local controller = activeController
	if controller then
		return controller:_getVisiblePosition(frame, includeFrame)
	end

	local screenGui = frame:FindFirstAncestorOfClass("ScreenGui")
	if not screenGui then
		return DEFAULT_END_POSITION
	end

	local frames: { [string]: GuiObject? } = {}
	local reservedFrames: { [string]: GuiObject? } = {}
	for _, frameName in ipairs(NOTIFICATION_FRAME_NAMES) do
		frames[frameName] = findGuiObject(screenGui, frameName)
	end
	for _, reservedName in ipairs(RESERVED_FRAME_NAMES) do
		reservedFrames[reservedName] = findGuiObject(screenGui, reservedName)
	end

	local targets = calculateTargets(screenGui, frames, reservedFrames, if includeFrame then frame else nil, {})
	return targets[frame] or getPositionForTop(frame, DEFAULT_TOP_SCALE, getViewportHeight())
end

function NotificationLayoutController.GetAnimationPositions(frame: GuiObject): (UDim2, UDim2)
	local controller = activeController
	if controller then
		return controller:_getAnimationPositions(frame)
	end

	local endPosition = NotificationLayoutController.GetVisiblePosition(frame, true)
	local viewportHeight = getViewportHeight()
	local slideDistance = math.max(0.08, getHeightScale(frame, viewportHeight) + 0.015)
	local startPosition = UDim2.new(
		endPosition.X.Scale,
		endPosition.X.Offset,
		endPosition.Y.Scale + slideDistance,
		endPosition.Y.Offset
	)
	return startPosition, endPosition
end

function NotificationLayoutController.Refresh()
	local controller = activeController
	if controller then
		controller:refresh()
	end
end

return NotificationLayoutController
