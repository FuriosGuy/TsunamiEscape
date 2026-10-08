local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local TweenService = game:GetService("TweenService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local PlayerHandler = require(ReplicatedStorage.Modules.Shared:WaitForChild("PlayerHandler_Client"))
local SpinWheelConfig = require(ReplicatedStorage.Modules.Config.SpinWheelConfig)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)
local NotificationLayoutController = require(ReplicatedStorage.Modules.UI.MainGUI.NotificationLayoutController)

local MODULE_NAME = "EventProgressUI"
local DEFAULT_MAX_WINS = 100
local MARKER_PREFIX = "BloodmoonUnlock_"
local TRAIL_MARKER_IMAGE_SCALE = 1.25
local KART_MARKER_IMAGE_SCALE = 2.5
local FINAL_MARKER_END_INSET_SCALE = 0.02

type UnlockKind = "Trail" | "Kart"

type UnlockDefinition = {
	id: string,
	displayName: string,
	winsRequired: number,
	kind: UnlockKind,
	imageAssetId: string?,
}

type MaidLike = {
	GiveTask: (self: MaidLike, task: any) -> number,
	DoCleaning: (self: MaidLike) -> (),
}

type ProgressFrameVisibilityControllerLike = {
	SetEventActive: (self: ProgressFrameVisibilityControllerLike, isActive: boolean) -> (),
}

type EventProgressTheme = {
	id: string,
	backgroundColor: Color3,
	gradientColor: Color3,
	infoText: string,
	winsAttribute: string,
	maxWins: number,
	showUnlocks: boolean,
	unlockDefinitions: { UnlockDefinition },
}

type EventProgressUIObject = {
	screenGui: ScreenGui,
	root: GuiObject?,
	currentWinsLabel: TextLabel?,
	currentStageLabel: TextLabel?,
	nextUnlockLabel: TextLabel?,
	infoLabel: TextLabel?,
	trackFrame: Frame?,
	progressFrame: Frame?,
	markersFrame: Frame?,
	markerTemplate: GuiObject?,
	stageProgressFrame: GuiObject?,
	progressHeightScale: number,
	progressHeightOffset: number,
	maxWins: number,
	defaultUnlockDefinitions: { UnlockDefinition },
	unlockDefinitions: { UnlockDefinition },
	originalRootVisible: boolean?,
	visibilityController: ProgressFrameVisibilityControllerLike?,
	stateFolder: Folder?,
	maid: MaidLike,
	stateMaid: MaidLike,
	progressTween: Tween?,
	initialized: boolean,
	eventActive: boolean,
	activeTheme: EventProgressTheme?,
	activeWinsAttribute: string,
	activeMaxWins: number,
	showUnlocks: boolean,
	themeMaid: MaidLike,
}

local EventProgressUI = {}
EventProgressUI.__index = EventProgressUI

local function isFiniteNumber(value: unknown): boolean
	return typeof(value) == "number" and value == value and value < math.huge and value > -math.huge
end

local function getTextLabel(parent: Instance?, name: string): TextLabel?
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(name)
	return if child and child:IsA("TextLabel") then child else nil
end

local function getGuiObject(parent: Instance?, name: string): GuiObject?
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(name)
	return if child and child:IsA("GuiObject") then child else nil
end

local function parseUnlockDefinitions(rawUnlocks: unknown, maxWins: number): { UnlockDefinition }
	local unlockDefinitions: { UnlockDefinition } = {}
	if typeof(rawUnlocks) ~= "table" then
		return unlockDefinitions
	end

	for _, rawUnlock in ipairs(rawUnlocks) do
		if
			typeof(rawUnlock) == "table"
			and typeof(rawUnlock.id) == "string"
			and typeof(rawUnlock.displayName) == "string"
			and isFiniteNumber(rawUnlock.winsRequired)
			and (rawUnlock.kind == "Trail" or rawUnlock.kind == "Kart")
		then
			local winsRequired = math.clamp(math.floor(rawUnlock.winsRequired), 1, maxWins)
			table.insert(unlockDefinitions, {
				id = rawUnlock.id,
				displayName = rawUnlock.displayName,
				winsRequired = winsRequired,
				kind = rawUnlock.kind,
				imageAssetId = if typeof(rawUnlock.imageAssetId) == "string" and rawUnlock.imageAssetId ~= ""
					then rawUnlock.imageAssetId
					else nil,
			})
		end
	end

	table.sort(unlockDefinitions, function(left: UnlockDefinition, right: UnlockDefinition): boolean
		if left.winsRequired == right.winsRequired then
			return left.id < right.id
		end
		return left.winsRequired < right.winsRequired
	end)

	return unlockDefinitions
end

local function loadUnlockDefinitions(): ({ UnlockDefinition }, number)
	local rawConfig = CoreConfig.bloodmoonProgress
	if typeof(rawConfig) ~= "table" or rawConfig.enabled == false then
		return {}, DEFAULT_MAX_WINS
	end

	local maxWins = if isFiniteNumber(rawConfig.maxWins)
		then math.max(1, math.floor(rawConfig.maxWins))
		else DEFAULT_MAX_WINS
	return parseUnlockDefinitions(rawConfig.unlocks, maxWins), maxWins
end

local function getMarkerImage(unlockDefinition: UnlockDefinition): string
	if typeof(unlockDefinition.imageAssetId) == "string" and unlockDefinition.imageAssetId ~= "" then
		return unlockDefinition.imageAssetId
	end

	if unlockDefinition.kind == "Trail" then
		local trailConfig = PlayerHandler.GetTrailConfig(unlockDefinition.id)
		local trailImage = trailConfig and trailConfig.ImageAssetId
		if typeof(trailImage) == "string" and trailImage ~= "" then
			return trailImage
		end
	end

	local rewardId: SpinWheelConfig.RewardId = if unlockDefinition.kind == "Trail" then "FlameTrail" else "FlameKart"
	local reward = SpinWheelConfig.GetReward(rewardId)
	return if reward then reward.imageAssetId else ""
end

local function parseHexColor(value: unknown): Color3?
	if typeof(value) ~= "string" then
		return nil
	end

	local redHex, greenHex, blueHex = string.match(value, "^#?(%x%x)(%x%x)(%x%x)$")
	if not redHex or not greenHex or not blueHex then
		return nil
	end

	local red = tonumber(redHex, 16)
	local green = tonumber(greenHex, 16)
	local blue = tonumber(blueHex, 16)
	if red == nil or green == nil or blue == nil then
		return nil
	end

	return Color3.fromRGB(red, green, blue)
end

local function formatStageWinAwards(rawAwards: unknown): string?
	if typeof(rawAwards) ~= "table" then
		return nil
	end

	local awards: { { stage: number, amount: number } } = {}
	for _, rawAward in ipairs(rawAwards) do
		if
			type(rawAward) == "table"
			and isFiniteNumber(rawAward.minimumStage)
			and isFiniteNumber(rawAward.amount)
			and rawAward.minimumStage >= 0
			and rawAward.amount > 0
		then
			table.insert(awards, {
				stage = math.floor(rawAward.minimumStage),
				amount = math.floor(rawAward.amount),
			})
		end
	end

	if #awards == 0 then
		return nil
	end

	table.sort(awards, function(left, right)
		return left.stage < right.stage
	end)

	local phrases: { string } = {}
	for _, award in ipairs(awards) do
		local winWord = if award.amount == 1 then "WIN" else "WINS"
		table.insert(phrases, string.format("STAGE %d: %d %s", award.stage, award.amount, winWord))
	end

	return table.concat(phrases, " | ") .. "!"
end

local function getActiveEventTheme(stateFolder: Folder): EventProgressTheme?
	local activeEvents = stateFolder:GetAttribute("ActiveEvents")
	if typeof(activeEvents) ~= "string" or activeEvents == "" then
		return nil
	end

	local ok, decoded = pcall(function()
		return HttpService:JSONDecode(activeEvents)
	end)
	if not ok or typeof(decoded) ~= "table" then
		return nil
	end

	for _, eventEntry in ipairs(decoded) do
		if typeof(eventEntry) == "table" and typeof(eventEntry.id) == "string" then
			local progressUi = eventEntry.progressUi
			if typeof(progressUi) == "table" then
				local backgroundColor = parseHexColor(progressUi.backgroundColor)
				local gradientColor = parseHexColor(progressUi.gradientColor)
				local infoText = if typeof(progressUi.infoText) == "string" and progressUi.infoText ~= ""
					then progressUi.infoText
					else formatStageWinAwards(eventEntry.stageWinAwards)
				if
					backgroundColor
					and gradientColor
					and typeof(infoText) == "string"
					and infoText ~= ""
				then
					local winsAttribute = if typeof(progressUi.winsAttribute) == "string"
						and progressUi.winsAttribute ~= ""
						then progressUi.winsAttribute
						elseif typeof(eventEntry.kartWinsAttribute) == "string"
						and eventEntry.kartWinsAttribute ~= ""
						then eventEntry.kartWinsAttribute
						else "BloodmoonWins"
					local maxWins = if isFiniteNumber(progressUi.maxWins)
						then math.max(1, math.floor(progressUi.maxWins))
						else DEFAULT_MAX_WINS
					local unlockDefinitions = parseUnlockDefinitions(progressUi.unlocks, maxWins)
					return {
						id = eventEntry.id,
						backgroundColor = backgroundColor,
						gradientColor = gradientColor,
						infoText = string.upper(infoText),
						winsAttribute = winsAttribute,
						maxWins = maxWins,
						showUnlocks = progressUi.showUnlocks ~= false,
						unlockDefinitions = unlockDefinitions,
					}
				end
			end
		end
	end

	return nil
end

local function setGradientEndColor(parent: GuiObject?, color: Color3)
	if not parent then
		return
	end

	local gradient = parent:FindFirstChildWhichIsA("UIGradient", true)
	if not gradient then
		return
	end

	local keypoints = gradient.Color.Keypoints
	if #keypoints == 0 then
		return
	end

	local updatedKeypoints = table.clone(keypoints)
	local finalKeypoint = updatedKeypoints[#updatedKeypoints]
	updatedKeypoints[#updatedKeypoints] = ColorSequenceKeypoint.new(finalKeypoint.Time, color)
	gradient.Color = ColorSequence.new(updatedKeypoints)
end

local function applyEventTheme(object: EventProgressUIObject, theme: EventProgressTheme)
	if object.progressFrame then
		object.progressFrame.BackgroundColor3 = theme.backgroundColor
		setGradientEndColor(object.progressFrame, theme.gradientColor)
	end
	if object.infoLabel then
		object.infoLabel.Text = theme.infoText
		object.infoLabel.TextColor3 = theme.backgroundColor
		setGradientEndColor(object.infoLabel, theme.gradientColor)
	end
end

local function configureMarker(marker: GuiObject, unlockDefinition: UnlockDefinition)
	marker.Name = MARKER_PREFIX .. unlockDefinition.id
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Visible = true

	local imageLabel = marker:FindFirstChild("ImageLabel", true)
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.Image = getMarkerImage(unlockDefinition)
		local imageScale = if unlockDefinition.kind == "Kart" then KART_MARKER_IMAGE_SCALE else TRAIL_MARKER_IMAGE_SCALE
		imageLabel.Size = UDim2.fromScale(imageScale, imageScale)
	end

	local winRequiredLabel = marker:FindFirstChild("WinRequired", true)
	if winRequiredLabel and winRequiredLabel:IsA("TextLabel") then
		winRequiredLabel.Text = string.format("%d Wins", unlockDefinition.winsRequired)
	end
end

local function getMarkerPosition(trackFrame: Frame, markersFrame: Frame, progress: number): UDim2
	local trackSize = trackFrame.AbsoluteSize
	local markersSize = markersFrame.AbsoluteSize
	if trackSize.X <= 0 or trackSize.Y <= 0 or markersSize.X <= 0 or markersSize.Y <= 0 then
		return UDim2.new(progress, 0, 0.5, 0)
	end

	local trackPoint = trackFrame.AbsolutePosition + Vector2.new(trackSize.X * progress, trackSize.Y * 0.5)
	local markersPoint = trackPoint - markersFrame.AbsolutePosition
	return UDim2.fromOffset(markersPoint.X, markersPoint.Y)
end

function EventProgressUI.new(
	screenGui: ScreenGui,
	visibilityController: ProgressFrameVisibilityControllerLike?
): EventProgressUIObject
	local rootInstance = screenGui:FindFirstChild("EventProgress")
	local root = if rootInstance and rootInstance:IsA("GuiObject") then rootInstance else nil
	local currentWinsLabel = getTextLabel(root, "CurrentWins")
	local currentStageLabel = getTextLabel(root, "CurrentStage")
	local nextUnlockLabel = getTextLabel(root, "NextUnlock")
	local infoLabel = getTextLabel(root, "Info")
	local trackFrameInstance = getGuiObject(root, "TrackFrame")
	local trackFrame = if trackFrameInstance and trackFrameInstance:IsA("Frame") then trackFrameInstance else nil
	local progressFrameInstance = getGuiObject(trackFrame, "ProgressFrame")
	local progressFrame = if progressFrameInstance and progressFrameInstance:IsA("Frame")
		then progressFrameInstance
		else nil
	local markersFrameInstance = getGuiObject(trackFrame, "Markers")
	local markersFrame = if markersFrameInstance and markersFrameInstance:IsA("Frame")
		then markersFrameInstance
		else nil
	local markerTemplate = getGuiObject(trackFrame, "StageMarkerTemplate")
	local stageProgressFrame = getGuiObject(screenGui, "StageProgressFrame")
	local unlockDefinitions, maxWins = loadUnlockDefinitions()

	return setmetatable({
		screenGui = screenGui,
		root = root,
		currentWinsLabel = currentWinsLabel,
		currentStageLabel = currentStageLabel,
		nextUnlockLabel = nextUnlockLabel,
		infoLabel = infoLabel,
		trackFrame = trackFrame,
		progressFrame = progressFrame,
		markersFrame = markersFrame,
		markerTemplate = markerTemplate,
		stageProgressFrame = stageProgressFrame,
		progressHeightScale = if progressFrame then progressFrame.Size.Y.Scale else 1,
		progressHeightOffset = if progressFrame then progressFrame.Size.Y.Offset else 0,
		maxWins = maxWins,
		defaultUnlockDefinitions = unlockDefinitions,
		unlockDefinitions = unlockDefinitions,
		originalRootVisible = if root then root.Visible else nil,
		visibilityController = visibilityController,
		stateFolder = nil,
		maid = Maid.new() :: MaidLike,
		stateMaid = Maid.new() :: MaidLike,
		progressTween = nil,
		initialized = false,
		eventActive = false,
		activeTheme = nil,
		activeWinsAttribute = "BloodmoonWins",
		activeMaxWins = maxWins,
		showUnlocks = true,
		themeMaid = Maid.new() :: MaidLike,
	}, EventProgressUI)
end

function EventProgressUI:refreshProgress()
	local currentStage = 0
	local currentWins = 0
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		local stageAttribute = localPlayer:GetAttribute("CurrentStage")
		if isFiniteNumber(stageAttribute) then
			currentStage = math.max(0, math.floor(stageAttribute))
		end

		local eventWins = localPlayer:GetAttribute(self.activeWinsAttribute)
		if isFiniteNumber(eventWins) then
			currentWins = math.max(0, math.floor(eventWins))
		end
	end

	if self.currentStageLabel then
		self.currentStageLabel.Text = string.format("STAGE %d", currentStage)
	end

	if self.currentWinsLabel then
		self.currentWinsLabel.Text = string.format("%d Wins", currentWins)
	end

	if self.progressFrame then
		local progress = math.clamp(currentWins / self.activeMaxWins, 0, 1)
		local targetSize = UDim2.new(progress, 0, self.progressHeightScale, self.progressHeightOffset)
		if self.progressTween then
			self.progressTween:Cancel()
			self.progressTween:Destroy()
			self.progressTween = nil
		end

		if currentWins <= 0 then
			self.progressFrame.Visible = false
			self.progressFrame.Size = targetSize
		else
			self.progressFrame.Visible = true
			self.progressTween = TweenService:Create(self.progressFrame, TweenConfig.ProgressBar, {
				Size = targetSize,
			})
			self.progressTween:Play()
		end
	end

	if self.nextUnlockLabel then
		if not self.showUnlocks then
			self.nextUnlockLabel.Text = ""
			return
		end

		local nextUnlock: UnlockDefinition? = nil
		for _, unlockDefinition in ipairs(self.unlockDefinitions) do
			if unlockDefinition.winsRequired > currentWins then
				nextUnlock = unlockDefinition
				break
			end
		end
		self.nextUnlockLabel.Text = if nextUnlock then nextUnlock.displayName else "ALL REWARDS UNLOCKED"
	end
end

function EventProgressUI:buildMarkers()
	if not self.markersFrame or not self.markerTemplate then
		return
	end

	self.markersFrame.ClipsDescendants = false
	local desiredNames: { [string]: boolean } = {}
	for _, unlockDefinition in ipairs(self.unlockDefinitions) do
		local markerName = MARKER_PREFIX .. unlockDefinition.id
		desiredNames[markerName] = true
		local markerInstance = self.markersFrame:FindFirstChild(markerName)
		local marker = if markerInstance and markerInstance:IsA("GuiObject")
			then markerInstance
			else self.markerTemplate:Clone()

		configureMarker(marker, unlockDefinition)
		if marker.Parent ~= self.markersFrame then
			marker.Parent = self.markersFrame
		end
	end

	for _, child in ipairs(self.markersFrame:GetChildren()) do
		if string.sub(child.Name, 1, #MARKER_PREFIX) == MARKER_PREFIX and not desiredNames[child.Name] then
			child:Destroy()
		end
	end
	self.markerTemplate.Visible = false
	self:positionMarkers()
end

function EventProgressUI:positionMarkers()
	if not self.trackFrame or not self.markersFrame then
		return
	end

	for _, unlockDefinition in ipairs(self.unlockDefinitions) do
		local marker = self.markersFrame:FindFirstChild(MARKER_PREFIX .. unlockDefinition.id)
		if marker and marker:IsA("GuiObject") then
			local progress = unlockDefinition.winsRequired / self.activeMaxWins
			if unlockDefinition.winsRequired >= self.activeMaxWins then
				progress = math.max(0, progress - FINAL_MARKER_END_INSET_SCALE)
			end
			marker.Position = getMarkerPosition(self.trackFrame, self.markersFrame, progress)
		end
	end
end

function EventProgressUI:setEventTheme(theme: EventProgressTheme?)
	self.themeMaid:DoCleaning()
	self.themeMaid = Maid.new() :: MaidLike
	self.activeWinsAttribute = if theme then theme.winsAttribute else "BloodmoonWins"
	self.activeMaxWins = if theme then theme.maxWins else self.maxWins
	self.unlockDefinitions = if theme then theme.unlockDefinitions else self.defaultUnlockDefinitions
	self.showUnlocks = if theme then theme.showUnlocks else true
	if self.markersFrame then
		self.markersFrame.Visible = self.showUnlocks
	end
	if self.nextUnlockLabel then
		self.nextUnlockLabel.Visible = theme ~= nil and self.showUnlocks
	end
	if theme then
		self.themeMaid:GiveTask(
			Players.LocalPlayer:GetAttributeChangedSignal(self.activeWinsAttribute):Connect(function()
				if self.eventActive then
					self:refreshProgress()
				end
			end)
		)
	end

	local isActive = theme ~= nil
	local previousEventId = if self.activeTheme then self.activeTheme.id else nil
	local currentEventId = if theme then theme.id else nil
	local eventChanged = self.eventActive ~= isActive or previousEventId ~= currentEventId
	self.eventActive = isActive
	self.activeTheme = theme

	if eventChanged then
		self:buildMarkers()
	end

	if self.visibilityController then
		self.visibilityController:SetEventActive(isActive)
	elseif self.root then
		self.root.Visible = isActive
		if self.stageProgressFrame then
			self.stageProgressFrame.Visible = not isActive
		end
	end

	if theme then
		applyEventTheme(self, theme)
		self:refreshProgress()
	end

	if eventChanged then
		DebugModule.debugInfo(
			"Event progress layout state changed | active="
				.. tostring(isActive)
				.. " | event="
				.. tostring(currentEventId or "none"),
			MODULE_NAME
		)
		NotificationLayoutController.Refresh()
	end
end

function EventProgressUI:bindStateFolder(stateFolder: Folder)
	self.stateMaid:DoCleaning()
	self.stateMaid = Maid.new() :: MaidLike
	self.stateFolder = stateFolder
	self.stateMaid:GiveTask(stateFolder:GetAttributeChangedSignal("ActiveEvents"):Connect(function()
		self:setEventTheme(getActiveEventTheme(stateFolder))
	end))
	self.stateMaid:GiveTask(stateFolder.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent == nil and self.stateFolder == stateFolder then
			self.stateFolder = nil
			self:setEventTheme(nil)
		end
	end))
	self:setEventTheme(getActiveEventTheme(stateFolder))
end

function EventProgressUI:Init()
	if self.initialized then
		return
	end
	self.initialized = true

	if
		not self.root
		or not self.trackFrame
		or not self.progressFrame
		or not self.markersFrame
		or not self.markerTemplate
	then
		if self.visibilityController then
			self.visibilityController:SetEventActive(false)
		end
		DebugModule.debugWarn("EventProgress UI hierarchy is incomplete", MODULE_NAME)
		return
	end

	self.root.Visible = false
	self:buildMarkers()
	self.maid:GiveTask(self.trackFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		self:positionMarkers()
	end))
	self.maid:GiveTask(self.trackFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:positionMarkers()
	end))
	self.maid:GiveTask(self.markersFrame:GetPropertyChangedSignal("AbsolutePosition"):Connect(function()
		self:positionMarkers()
	end))
	self.maid:GiveTask(self.markersFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:positionMarkers()
	end))
	self.maid:GiveTask(Players.LocalPlayer:GetAttributeChangedSignal("CurrentStage"):Connect(function()
		if self.eventActive then
			self:refreshProgress()
		end
	end))
	self.maid:GiveTask(ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == "LiveEventState" and child:IsA("Folder") then
			self:bindStateFolder(child)
		end
	end))

	local stateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
	if stateFolder and stateFolder:IsA("Folder") then
		self:bindStateFolder(stateFolder)
	else
		self:setEventTheme(nil)
	end
end

function EventProgressUI:Destroy()
	if not self.initialized then
		return
	end
	self.initialized = false
	self.stateMaid:DoCleaning()
	self.maid:DoCleaning()
	self.themeMaid:DoCleaning()
	if self.progressTween then
		self.progressTween:Cancel()
		self.progressTween:Destroy()
		self.progressTween = nil
	end
	self.stateFolder = nil
	self:setEventTheme(nil)
	if self.root and self.originalRootVisible ~= nil then
		self.root.Visible = self.originalRootVisible
	end
end

return EventProgressUI
