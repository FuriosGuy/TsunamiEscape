--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TweenService = game:GetService("TweenService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig_Client)
local PlayerHandler = require(ReplicatedStorage.Modules.PlayerHandler)
local SpinWheelConfig = require(ReplicatedStorage.Modules.Config.SpinWheelConfig)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)

local MODULE_NAME = "BloodMoonProgressUI"
local BLOODMOON_EVENT_ID = "Bloodmoon"
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

type BloodMoonProgressUIObject = {
	screenGui: ScreenGui,
	root: Frame?,
	currentWinsLabel: TextLabel?,
	currentStageLabel: TextLabel?,
	nextUnlockLabel: TextLabel?,
	trackFrame: Frame?,
	progressFrame: Frame?,
	markersFrame: Frame?,
	markerTemplate: GuiObject?,
	stageProgressFrame: GuiObject?,
	progressHeightScale: number,
	progressHeightOffset: number,
	maxWins: number,
	unlockDefinitions: { UnlockDefinition },
	originalRootVisible: boolean?,
	stageProgressVisibleBeforeBloodmoon: boolean?,
	stateFolder: Folder?,
	maid: MaidLike,
	stateMaid: MaidLike,
	progressTween: Tween?,
	initialized: boolean,
	bloodmoonActive: boolean,
}

local BloodMoonProgressUI = {}
BloodMoonProgressUI.__index = BloodMoonProgressUI

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

local function loadUnlockDefinitions(): ({ UnlockDefinition }, number)
	local rawConfig = CoreConfig.bloodmoonProgress
	if typeof(rawConfig) ~= "table" or rawConfig.enabled == false then
		return {}, DEFAULT_MAX_WINS
	end

	local maxWins = if isFiniteNumber(rawConfig.maxWins)
		then math.max(1, math.floor(rawConfig.maxWins))
		else DEFAULT_MAX_WINS
	local unlockDefinitions: { UnlockDefinition } = {}
	local rawUnlocks = rawConfig.unlocks
	if typeof(rawUnlocks) ~= "table" then
		return unlockDefinitions, maxWins
	end

	for _, rawUnlock in ipairs(rawUnlocks) do
		if typeof(rawUnlock) == "table"
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
				imageAssetId = if typeof(rawUnlock.imageAssetId) == "string"
					and rawUnlock.imageAssetId ~= ""
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

	return unlockDefinitions, maxWins
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

	local rewardId: SpinWheelConfig.RewardId = if unlockDefinition.kind == "Trail"
		then "FlameTrail"
		else "FlameKart"
	local reward = SpinWheelConfig.GetReward(rewardId)
	return if reward then reward.imageAssetId else ""
end

local function getBloodmoonActive(stateFolder: Folder): boolean
	local activeEventIds = stateFolder:GetAttribute("ActiveEventIds")
	if typeof(activeEventIds) == "string" then
		for eventId in string.gmatch(activeEventIds, "[^,]+") do
			if eventId == BLOODMOON_EVENT_ID then
				return true
			end
		end
	end

	return stateFolder:GetAttribute("EnvironmentName") == "Bloodmoon"
end

local function configureMarker(
	marker: GuiObject,
	unlockDefinition: UnlockDefinition
)
	marker.Name = MARKER_PREFIX .. unlockDefinition.id
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Visible = true

	local imageLabel = marker:FindFirstChild("ImageLabel", true)
	if imageLabel and imageLabel:IsA("ImageLabel") then
		imageLabel.Image = getMarkerImage(unlockDefinition)
		local imageScale = if unlockDefinition.kind == "Kart"
			then KART_MARKER_IMAGE_SCALE
			else TRAIL_MARKER_IMAGE_SCALE
		imageLabel.Size = UDim2.fromScale(imageScale, imageScale)
	end

	local winRequiredLabel = marker:FindFirstChild("WinRequired", true)
	if winRequiredLabel and winRequiredLabel:IsA("TextLabel") then
		winRequiredLabel.Text = string.format("%d Wins", unlockDefinition.winsRequired)
	end
end

local function getMarkerPosition(
	trackFrame: Frame,
	markersFrame: Frame,
	progress: number
): UDim2
	local trackSize = trackFrame.AbsoluteSize
	local markersSize = markersFrame.AbsoluteSize
	if trackSize.X <= 0 or trackSize.Y <= 0 or markersSize.X <= 0 or markersSize.Y <= 0 then
		return UDim2.new(progress, 0, 0.5, 0)
	end

	local trackPoint = trackFrame.AbsolutePosition + Vector2.new(
		trackSize.X * progress,
		trackSize.Y * 0.5
	)
	local markersPoint = trackPoint - markersFrame.AbsolutePosition
	return UDim2.fromOffset(markersPoint.X, markersPoint.Y)
end

function BloodMoonProgressUI.new(screenGui: ScreenGui): BloodMoonProgressUIObject
	local rootInstance = screenGui:FindFirstChild("BloodMoonProgress")
	local root = if rootInstance and rootInstance:IsA("Frame") then rootInstance else nil
	local currentWinsLabel = getTextLabel(root, "CurrentWins")
	local currentStageLabel = getTextLabel(root, "CurrentStage")
	local nextUnlockLabel = getTextLabel(root, "NextUnlock")
	local trackFrameInstance = getGuiObject(root, "TrackFrame")
	local trackFrame = if trackFrameInstance and trackFrameInstance:IsA("Frame") then trackFrameInstance else nil
	local progressFrameInstance = getGuiObject(trackFrame, "ProgressFrame")
	local progressFrame = if progressFrameInstance and progressFrameInstance:IsA("Frame") then progressFrameInstance else nil
	local markersFrameInstance = getGuiObject(trackFrame, "Markers")
	local markersFrame = if markersFrameInstance and markersFrameInstance:IsA("Frame") then markersFrameInstance else nil
	local markerTemplate = getGuiObject(trackFrame, "StageMarkerTemplate")
	local stageProgressFrame = getGuiObject(screenGui, "StageProgressFrame")
	local unlockDefinitions, maxWins = loadUnlockDefinitions()

	return setmetatable({
		screenGui = screenGui,
		root = root,
		currentWinsLabel = currentWinsLabel,
		currentStageLabel = currentStageLabel,
		nextUnlockLabel = nextUnlockLabel,
		trackFrame = trackFrame,
		progressFrame = progressFrame,
		markersFrame = markersFrame,
		markerTemplate = markerTemplate,
		stageProgressFrame = stageProgressFrame,
		progressHeightScale = if progressFrame then progressFrame.Size.Y.Scale else 1,
		progressHeightOffset = if progressFrame then progressFrame.Size.Y.Offset else 0,
		maxWins = maxWins,
		unlockDefinitions = unlockDefinitions,
		originalRootVisible = if root then root.Visible else nil,
		stageProgressVisibleBeforeBloodmoon = nil,
		stateFolder = nil,
		maid = Maid.new() :: MaidLike,
		stateMaid = Maid.new() :: MaidLike,
		progressTween = nil,
		initialized = false,
		bloodmoonActive = false,
	}, BloodMoonProgressUI)
end

function BloodMoonProgressUI:refreshProgress()
	local currentStage = 0
	local currentWins = 0
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		local stageAttribute = localPlayer:GetAttribute("CurrentStage")
		if isFiniteNumber(stageAttribute) then
			currentStage = math.max(0, math.floor(stageAttribute))
		end

		local bloodmoonWins = localPlayer:GetAttribute("BloodmoonWins")
		if isFiniteNumber(bloodmoonWins) then
			currentWins = math.max(0, math.floor(bloodmoonWins))
		end
	end

	if self.currentStageLabel then
		self.currentStageLabel.Text = string.format("STAGE %d", currentStage)
	end

	if self.currentWinsLabel then
		self.currentWinsLabel.Text = string.format("%d Wins", currentWins)
	end

	if self.progressFrame then
		local progress = math.clamp(currentWins / self.maxWins, 0, 1)
		local targetSize = UDim2.new(
			progress,
			0,
			self.progressHeightScale,
			self.progressHeightOffset
		)
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

function BloodMoonProgressUI:buildMarkers()
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

function BloodMoonProgressUI:positionMarkers()
	if not self.trackFrame or not self.markersFrame then
		return
	end

	for _, unlockDefinition in ipairs(self.unlockDefinitions) do
		local marker = self.markersFrame:FindFirstChild(MARKER_PREFIX .. unlockDefinition.id)
		if marker and marker:IsA("GuiObject") then
			local progress = unlockDefinition.winsRequired / self.maxWins
			if unlockDefinition.winsRequired >= self.maxWins then
				progress = math.max(0, progress - FINAL_MARKER_END_INSET_SCALE)
			end
			marker.Position = getMarkerPosition(
				self.trackFrame,
				self.markersFrame,
				progress
			)
		end
	end
end

function BloodMoonProgressUI:setBloodmoonActive(isActive: boolean)
	if self.bloodmoonActive == isActive then
		if isActive then
			self:refreshProgress()
		end
		return
	end

	self.bloodmoonActive = isActive
	if isActive then
		if self.stageProgressFrame and self.stageProgressVisibleBeforeBloodmoon == nil then
			self.stageProgressVisibleBeforeBloodmoon = self.stageProgressFrame.Visible
		end
		if self.stageProgressFrame then
			self.stageProgressFrame.Visible = false
		end
		if self.root then
			self.root.Visible = true
		end
		self:refreshProgress()
		return
	end

	if self.root then
		self.root.Visible = false
	end
	if self.stageProgressFrame and self.stageProgressVisibleBeforeBloodmoon ~= nil then
		self.stageProgressFrame.Visible = self.stageProgressVisibleBeforeBloodmoon
	end
	self.stageProgressVisibleBeforeBloodmoon = nil
end

function BloodMoonProgressUI:bindStateFolder(stateFolder: Folder)
	self.stateMaid:DoCleaning()
	self.stateMaid = Maid.new() :: MaidLike
	self.stateFolder = stateFolder
	self.stateMaid:GiveTask(stateFolder:GetAttributeChangedSignal("ActiveEventIds"):Connect(function()
		self:setBloodmoonActive(getBloodmoonActive(stateFolder))
	end))
	self.stateMaid:GiveTask(stateFolder:GetAttributeChangedSignal("EnvironmentName"):Connect(function()
		self:setBloodmoonActive(getBloodmoonActive(stateFolder))
	end))
	self.stateMaid:GiveTask(stateFolder.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent == nil and self.stateFolder == stateFolder then
			self.stateFolder = nil
			self:setBloodmoonActive(false)
		end
	end))
	self:setBloodmoonActive(getBloodmoonActive(stateFolder))
end

function BloodMoonProgressUI:Init()
	if self.initialized then
		return
	end
	self.initialized = true

	if not self.root or not self.trackFrame or not self.progressFrame or not self.markersFrame or not self.markerTemplate then
		DebugModule.debugWarn("BloodMoonProgress UI hierarchy is incomplete", MODULE_NAME)
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
	self.maid:GiveTask(Players.LocalPlayer:GetAttributeChangedSignal("BloodmoonWins"):Connect(function()
		if self.bloodmoonActive then
			self:refreshProgress()
		end
	end))
	self.maid:GiveTask(Players.LocalPlayer:GetAttributeChangedSignal("CurrentStage"):Connect(function()
		if self.bloodmoonActive then
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
	end
end

function BloodMoonProgressUI:Destroy()
	if not self.initialized then
		return
	end
	self.initialized = false
	self.stateMaid:DoCleaning()
	self.maid:DoCleaning()
	if self.progressTween then
		self.progressTween:Cancel()
		self.progressTween:Destroy()
		self.progressTween = nil
	end
	self.stateFolder = nil
	self:setBloodmoonActive(false)
	if self.root and self.originalRootVisible ~= nil then
		self.root.Visible = self.originalRootVisible
	end
end

return BloodMoonProgressUI
