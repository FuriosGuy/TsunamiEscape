--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RobloxSoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local PetDisplayStyler = require(ReplicatedStorage.Modules.UI.PetDisplayStyler)
local PetViewportRenderer = require(ReplicatedStorage.Modules.UI.PetViewportRenderer)

type LuckyBlockGroup = PetConfig.LuckyBlockGroup
type PetDefinition = PetConfig.PetDefinition
type CleanupTask = Instance | RBXScriptConnection | Tween | thread
type PlayRouletteTick = (number) -> ()
type CleanupMaid = {
	GiveTask: (self: CleanupMaid, task: CleanupTask) -> number,
}

type PetDisplayState = {
	billboard: BillboardGui,
	adorneeAttachment: Attachment?,
	petName: TextLabel,
	rarityType: TextLabel,
	targetSize: UDim2,
	targetOffset: Vector3,
}

type RevealSlot = {
	definition: PetDefinition,
	count: number,
	winnerModel: Model,
	activeModel: Model,
	petDisplay: PetDisplayState?,
	petDisplayWarningLogged: boolean,
	highlight: Highlight,
	originalTransparency: { [BasePart]: number },
	winnerHidden: boolean,
	finalScale: number,
	baseWidth: number,
	baseHeight: number,
	baseDepth: number,
	facingRotation: CFrame,
	layoutCenter: Vector3,
	startFrame: CFrame,
	targetFrame: CFrame,
}

type RevealLayout = {
	slots: { RevealSlot },
	cameraFrame: CFrame,
}

type ConsolidationPlan = {
	representatives: { RevealSlot },
	duplicates: { RevealSlot },
	representativeByPetId: { [string]: RevealSlot },
}

type GridLayout = {
	rowWidths: { number },
	rowHeights: { number },
	rowGaps: { { number } },
	maxRowWidth: number,
	totalLayoutHeight: number,
	maxPetHeight: number,
	maxPetDepth: number,
	verticalGap: number,
}

local PetLuckyBlockRevealController = {}
local MODULE_NAME = "PetLuckyBlockRevealController"
local START_SCALE = 0.06
local LAUNCH_DURATION = 0.9
local FAST_LAUNCH_DURATION = 0.65
local ROULETTE_SWITCH_COUNT = 15
local ROULETTE_INITIAL_INTERVAL = 0.065
local ROULETTE_FINAL_INTERVAL = 0.48
local HIGHLIGHT_FLASH_DURATION = 0.2
local HIGHLIGHT_FADE_DURATION = 0.38
local HIGHLIGHT_HOLD_DURATION = 0.12
local PET_DISPLAY_POP_DURATION = 0.45
local PET_DISPLAY_HOLD_DURATION = 1.5
local DUPLICATE_RESULT_HOLD_DURATION = 0.3
local DUPLICATE_CONSOLIDATION_DURATION = 0.55
local FINAL_GRID_REFLOW_DURATION = 0.35
local CONSOLIDATION_PULSE_DURATION = 0.3
local CONSOLIDATION_PULSE_SCALE = 1.2
local CONSOLIDATION_END_HOLD_DURATION = 0.35
local PET_DISPLAY_START_SCALE = 0.65
local PET_DISPLAY_TOP_PADDING = 0.1
local PET_DISPLAY_POP_OFFSET = 0.2
local PET_DISPLAY_MIN_FORWARD_OFFSET = 0.25
local PET_DISPLAY_FORWARD_DEPTH_FACTOR = 0.12
local MIN_REVEAL_CAMERA_DISTANCE = 6
local HORIZONTAL_DIRECTION_EPSILON = 0.001
local MAX_CAMERA_FACING_PITCH = math.rad(60)
local HORIZONTAL_SCREEN_FRACTION = 0.88
local VERTICAL_SCREEN_FRACTION = 0.78
local CAMERA_FIT_PADDING = 1.25
local BLOCK_CLEARANCE_MINIMUM = 8
local MIN_HORIZONTAL_GAP = 3
local HORIZONTAL_GAP_WIDTH_FACTOR = 0.18
local HORIZONTAL_GAP_HEIGHT_FACTOR = 0.16
local MIN_VERTICAL_GAP = 3
local VERTICAL_GAP_HEIGHT_FACTOR = 0.28
local PET_DISPLAY_HEADROOM_MINIMUM = 2
local PET_DISPLAY_HEADROOM_HEIGHT_FACTOR = 0.35
local BLACK = ColorConfig.Colors.Black.Color
local WHITE = ColorConfig.Colors.White.Color
local ROULETTE_RANDOM = Random.new()

local function getExtentAlong(frame: CFrame, size: Vector3, axis: Vector3): number
	return math.abs(frame.RightVector:Dot(axis)) * size.X
		+ math.abs(frame.UpVector:Dot(axis)) * size.Y
		+ math.abs(frame.LookVector:Dot(axis)) * size.Z
end

local function getCameraHorizontalFacing(camera: Camera): Vector3
	local facing = -camera.CFrame.LookVector
	facing = Vector3.new(facing.X, 0, facing.Z)
	if facing.Magnitude <= HORIZONTAL_DIRECTION_EPSILON then
		local right = camera.CFrame.RightVector
		facing = Vector3.new(right.X, 0, right.Z):Cross(Vector3.yAxis)
	end
	if facing.Magnitude <= HORIZONTAL_DIRECTION_EPSILON then
		return Vector3.zAxis
	end
	return facing.Unit
end

local function getCameraFacingDirection(camera: Camera): Vector3
	local facing = -camera.CFrame.LookVector
	local horizontalFacing = Vector3.new(facing.X, 0, facing.Z)
	if horizontalFacing.Magnitude <= HORIZONTAL_DIRECTION_EPSILON then
		horizontalFacing = getCameraHorizontalFacing(camera)
	else
		horizontalFacing = horizontalFacing.Unit
	end

	local pitch = math.asin(math.clamp(facing.Y, -1, 1))
	pitch = math.clamp(pitch, -MAX_CAMERA_FACING_PITCH, MAX_CAMERA_FACING_PITCH)
	return (horizontalFacing * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)).Unit
end

local function getFacingFrame(position: Vector3, cameraPosition: Vector3, camera: Camera): CFrame
	local direction = (cameraPosition - position).Unit
	local upDirection = Vector3.yAxis
	if math.abs(direction:Dot(upDirection)) > 0.995 then
		upDirection = camera.CFrame.UpVector
	end
	if math.abs(direction:Dot(upDirection)) > 0.995 then
		upDirection = Vector3.zAxis
	end
	return CFrame.lookAt(position, cameraPosition, upDirection)
end

local function orientModelToCamera(model: Model, camera: Camera?): Vector3?
	local activeCamera = camera or Workspace.CurrentCamera
	if not activeCamera then
		return nil
	end

	local modelPivot = model:GetPivot()
	local facingDirection = getCameraFacingDirection(activeCamera)
	local facingRotation = CFrame.lookAt(Vector3.zero, facingDirection, Vector3.yAxis).Rotation
	model:PivotTo(CFrame.new(modelPivot.Position) * facingRotation)
	local boundsFrame, boundsSize = model:GetBoundingBox()
	model:PivotTo(CFrame.new(-boundsFrame.Position) * model:GetPivot())
	boundsFrame, boundsSize = model:GetBoundingBox()
	return Vector3.new(
		getExtentAlong(boundsFrame, boundsSize, activeCamera.CFrame.RightVector),
		getExtentAlong(boundsFrame, boundsSize, activeCamera.CFrame.UpVector),
		getExtentAlong(boundsFrame, boundsSize, activeCamera.CFrame.LookVector)
	)
end

local function setPetVisible(model: Model, originalTransparency: { [BasePart]: number }, visible: boolean): ()
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if visible then
				local transparency = originalTransparency[descendant]
				if transparency ~= nil then
					descendant.LocalTransparencyModifier = transparency
				end
			else
				originalTransparency[descendant] = descendant.LocalTransparencyModifier
				descendant.LocalTransparencyModifier = 1
			end
		end
	end
	if visible then
		table.clear(originalTransparency)
	end
end

local function makeRows(petCount: number): { { number } }
	if petCount == 5 then
		return { { 1, 2, 3 }, { 4, 5 } }
	elseif petCount == 4 then
		return { { 1, 2 }, { 3, 4 } }
	end
	local row: { number } = {}
	for index = 1, petCount do
		table.insert(row, index)
	end
	return { row }
end

local function calculateGridLayout(slots: { RevealSlot }, rows: { { number } }): GridLayout
	local maxPetHeight = 0
	local maxPetDepth = 0
	for _, slot in ipairs(slots) do
		maxPetHeight = math.max(maxPetHeight, slot.baseHeight)
		maxPetDepth = math.max(maxPetDepth, slot.baseDepth)
	end

	local verticalGap = math.max(MIN_VERTICAL_GAP, maxPetHeight * VERTICAL_GAP_HEIGHT_FACTOR)
	local rowWidths: { number } = {}
	local rowHeights: { number } = {}
	local rowGaps: { { number } } = {}
	local maxRowWidth = 0
	local totalLayoutHeight = 0
	for rowIndex, row in ipairs(rows) do
		local rowWidth = 0
		local rowHeight = 0
		local gaps: { number } = {}
		for petIndex, slotIndex in ipairs(row) do
			local slot = slots[slotIndex]
			rowWidth += slot.baseWidth
			rowHeight = math.max(rowHeight, slot.baseHeight)

			local nextSlotIndex = row[petIndex + 1]
			if nextSlotIndex then
				local nextSlot = slots[nextSlotIndex]
				local gap = math.max(
					MIN_HORIZONTAL_GAP,
					math.max(slot.baseWidth, nextSlot.baseWidth) * HORIZONTAL_GAP_WIDTH_FACTOR,
					math.max(slot.baseHeight, nextSlot.baseHeight) * HORIZONTAL_GAP_HEIGHT_FACTOR
				)
				table.insert(gaps, gap)
				rowWidth += gap
			end
		end
		rowGaps[rowIndex] = gaps
		rowWidths[rowIndex] = rowWidth
		rowHeights[rowIndex] = rowHeight
		maxRowWidth = math.max(maxRowWidth, rowWidth)
		totalLayoutHeight += rowHeight
	end
	totalLayoutHeight += verticalGap * math.max(#rows - 1, 0)

	return {
		rowWidths = rowWidths,
		rowHeights = rowHeights,
		rowGaps = rowGaps,
		maxRowWidth = maxRowWidth,
		totalLayoutHeight = totalLayoutHeight,
		maxPetHeight = maxPetHeight,
		maxPetDepth = maxPetDepth,
		verticalGap = verticalGap,
	}
end

local function positionSlotsInGrid(
	slots: { RevealSlot },
	rows: { { number } },
	layout: GridLayout,
	camera: Camera,
	groupCenter: Vector3,
	cameraPosition: Vector3
): ()
	local rowOffsets: { [number]: number } = {}
	local rowCursor = -layout.totalLayoutHeight * 0.5
	for rowIndex, rowHeight in ipairs(layout.rowHeights) do
		rowCursor += rowHeight * 0.5
		rowOffsets[rowIndex] = rowCursor
		rowCursor += rowHeight * 0.5 + layout.verticalGap
	end

	for rowIndex, row in ipairs(rows) do
		local cursor = -layout.rowWidths[rowIndex] * 0.5
		for petIndex, slotIndex in ipairs(row) do
			local slot = slots[slotIndex]
			local xOffset = cursor + slot.baseWidth * 0.5
			cursor += slot.baseWidth
			local gap = layout.rowGaps[rowIndex][petIndex]
			if gap then
				cursor += gap
			end

			local targetPosition = groupCenter
				+ camera.CFrame.RightVector * xOffset
				+ camera.CFrame.UpVector * rowOffsets[rowIndex]
			slot.targetFrame = getFacingFrame(targetPosition, cameraPosition, camera)
			slot.facingRotation = slot.targetFrame.Rotation
		end
	end
end

local function getPetLookup(group: LuckyBlockGroup): ({ PetDefinition }?, { [string]: PetDefinition })
	local pets = PetConfig.GetPetsForLuckyBlock(group)
	local lookup: { [string]: PetDefinition } = {}
	if pets then
		for _, pet in ipairs(pets) do
			lookup[pet.id] = pet
		end
	end
	return pets, lookup
end

local function createSlots(
	petIds: { string },
	petCounts: { [string]: number },
	lookup: { [string]: PetDefinition },
	block: Model,
	camera: Camera,
	folder: Folder,
	maid: CleanupMaid
): RevealLayout?
	local blockFrame, blockSize = block:GetBoundingBox()
	if blockSize.Magnitude <= 0 then
		return nil
	end

	local slots: { RevealSlot } = {}
	for _, petId in ipairs(petIds) do
		local definition = lookup[petId]
		local model = if definition then PetViewportRenderer.CloneModel(definition.modelPath) else nil
		if not definition or not model then
			for _, slot in ipairs(slots) do
				slot.winnerModel:Destroy()
				slot.highlight:Destroy()
			end
			return nil
		end

		local modelBounds = orientModelToCamera(model, camera)
		if not modelBounds or modelBounds.X <= 0 or modelBounds.Y <= 0 then
			DebugModule.debugWarn(
				string.format("Invalid Lucky Block reveal model bounds | pet=%s | path=%s", petId, definition.modelPath),
				MODULE_NAME
			)
			model:Destroy()
			for _, slot in ipairs(slots) do
				slot.winnerModel:Destroy()
				slot.highlight:Destroy()
			end
			return nil
		end

		local highlight = Instance.new("Highlight")
		highlight.Name = "PetRevealHighlight"
		highlight.Adornee = model
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.FillColor = BLACK
		highlight.FillTransparency = 0
		highlight.OutlineColor = WHITE
		highlight.OutlineTransparency = 0
		table.insert(slots, {
			definition = definition,
			count = petCounts[petId] or 1,
			winnerModel = model,
			activeModel = model,
			petDisplay = nil,
			petDisplayWarningLogged = false,
			highlight = highlight,
			originalTransparency = {},
			winnerHidden = false,
			finalScale = model:GetScale(),
			baseWidth = modelBounds.X,
			baseHeight = modelBounds.Y,
			baseDepth = modelBounds.Z,
			facingRotation = model:GetPivot().Rotation,
			layoutCenter = Vector3.zero,
			startFrame = CFrame.identity,
			targetFrame = CFrame.identity,
		})
	end

	local petCount = #slots
	local rows = makeRows(petCount)
	local gridLayout = calculateGridLayout(slots, rows)
	local viewport = camera.ViewportSize
	local aspectRatio = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local blockHalfDepth = getExtentAlong(blockFrame, blockSize, camera.CFrame.LookVector) * 0.5
	local blockHalfHeight = getExtentAlong(blockFrame, blockSize, camera.CFrame.UpVector) * 0.5
	local frontClearance = math.max(
		BLOCK_CLEARANCE_MINIMUM,
		blockSize.Magnitude * 0.25,
		gridLayout.maxPetDepth * 0.25
	)
	local frontDistance = blockHalfDepth + gridLayout.maxPetDepth * 0.5 + frontClearance
	local groupCenter = blockFrame.Position
		+ camera.CFrame.UpVector
			* (blockHalfHeight + gridLayout.totalLayoutHeight * 0.5 + math.max(2, blockSize.Y * 0.2))
		- camera.CFrame.LookVector * frontDistance
	local fovTangent = math.tan(math.rad(camera.FieldOfView * 0.5))
	local horizontalDistance = gridLayout.maxRowWidth
		/ (2 * fovTangent * math.max(aspectRatio, 0.1) * HORIZONTAL_SCREEN_FRACTION)
	local displayHeadroom = math.max(
		PET_DISPLAY_HEADROOM_MINIMUM,
		gridLayout.maxPetHeight * PET_DISPLAY_HEADROOM_HEIGHT_FACTOR
	)
	local verticalDistance = (gridLayout.totalLayoutHeight + displayHeadroom)
		/ (2 * fovTangent * VERTICAL_SCREEN_FRACTION)
	local cameraDistance = math.max(horizontalDistance, verticalDistance, MIN_REVEAL_CAMERA_DISTANCE)
		* CAMERA_FIT_PADDING
		+ gridLayout.maxPetDepth * 0.5
	local cameraPosition = groupCenter - camera.CFrame.LookVector * cameraDistance
	local cameraFrame = CFrame.new(cameraPosition) * camera.CFrame.Rotation
	for _, slot in ipairs(slots) do
		slot.layoutCenter = groupCenter
	end
	positionSlotsInGrid(slots, rows, gridLayout, camera, groupCenter, cameraPosition)

	local startPosition = blockFrame.Position
		- camera.CFrame.LookVector * getExtentAlong(blockFrame, blockSize, camera.CFrame.LookVector) * 0.12
	for _, slot in ipairs(slots) do
		slot.facingRotation = slot.targetFrame.Rotation
		slot.startFrame = CFrame.new(startPosition)
			* slot.targetFrame.Rotation
			* CFrame.Angles(math.rad(-38), 0, math.rad(-24))
		slot.winnerModel:PivotTo(slot.startFrame)
		slot.winnerModel:ScaleTo(slot.finalScale * START_SCALE)
		slot.winnerModel.Parent = folder
		slot.highlight.Parent = folder
		maid:GiveTask(slot.highlight)
	end

	return { slots = slots, cameraFrame = cameraFrame }
end

local setPetDisplay: (RevealSlot, PetDefinition, Model, boolean, boolean, CleanupMaid) -> boolean

local function showWinner(slot: RevealSlot): ()
	if slot.petDisplay then
		slot.petDisplay.billboard.Enabled = false
	end
	if slot.activeModel ~= slot.winnerModel then
		slot.activeModel:Destroy()
	end
	if slot.winnerHidden then
		setPetVisible(slot.winnerModel, slot.originalTransparency, true)
		slot.winnerHidden = false
	end
	slot.winnerModel:PivotTo(slot.targetFrame)
	slot.highlight.Adornee = slot.winnerModel
	slot.activeModel = slot.winnerModel
end

local function showRoulettePet(
	slot: RevealSlot,
	definition: PetDefinition,
	folder: Folder,
	camera: Camera?,
	maid: CleanupMaid
): ()
	if slot.activeModel == slot.winnerModel then
		setPetVisible(slot.winnerModel, slot.originalTransparency, false)
		slot.winnerHidden = true
	else
		slot.activeModel:Destroy()
	end

	local model = PetViewportRenderer.CloneModel(definition.modelPath)
	if not model then
		showWinner(slot)
		return
	end
	local modelBounds = orientModelToCamera(model, camera)
	if not modelBounds or modelBounds.X <= 0 or modelBounds.Y <= 0 then
		model:Destroy()
		showWinner(slot)
		return
	end
	model:PivotTo(slot.targetFrame)
	model.Parent = folder
	slot.activeModel = model
	slot.highlight.Adornee = model
	setPetDisplay(slot, definition, model, false, false, maid)
end

local function warnPetDisplayIssue(slot: RevealSlot, message: string): ()
	if slot.petDisplayWarningLogged then
		return
	end
	slot.petDisplayWarningLogged = true
	DebugModule.debugWarn(message, MODULE_NAME)
end

setPetDisplay = function(
	slot: RevealSlot,
	definition: PetDefinition,
	model: Model,
	showDetails: boolean,
	playPop: boolean,
	maid: CleanupMaid
): boolean
	local state = slot.petDisplay
	if not state then
		local player = Players.LocalPlayer
		local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
		local userInterface = ReplicatedStorage:FindFirstChild("UserInterface")
		local template = userInterface and userInterface:FindFirstChild("PetDisplay")
		if not playerGui or not template or not template:IsA("BillboardGui") then
			warnPetDisplayIssue(slot, "PetDisplay template or LocalPlayer.PlayerGui unavailable")
			return false
		end

		local displayClone = template:Clone()
		if not displayClone:IsA("BillboardGui") then
			displayClone:Destroy()
			warnPetDisplayIssue(slot, "PetDisplay clone is not a BillboardGui")
			return false
		end
		local display = displayClone
		local petName = display:FindFirstChild("PetName", true)
		local rarityType = display:FindFirstChild("RarityType", true)
		if not petName or not petName:IsA("TextLabel") or not rarityType or not rarityType:IsA("TextLabel") then
			display:Destroy()
			warnPetDisplayIssue(slot, "PetDisplay is missing PetName or RarityType TextLabel")
			return false
		end

		state = {
			billboard = display,
			adorneeAttachment = nil,
			petName = petName,
			rarityType = rarityType,
			targetSize = display.Size,
			targetOffset = Vector3.new(0, PET_DISPLAY_TOP_PADDING, 0),
		}
		slot.petDisplay = state
		display.Enabled = false
		maid:GiveTask(display)
		display.Parent = playerGui
	end
	if not state then
		return false
	end

	local adornee = model.PrimaryPart
	if not adornee then
		local firstPart = model:FindFirstChildWhichIsA("BasePart", true)
		if firstPart and firstPart:IsA("BasePart") then
			adornee = firstPart
		end
	end
	if not adornee then
		warnPetDisplayIssue(slot, "Cannot show pet reveal label without a BasePart | pet=" .. definition.id)
		state.billboard.Enabled = false
		return false
	end

	local boundsFrame, boundsSize = model:GetBoundingBox()
	local modelPivot = model:GetPivot()
	local modelHeight = getExtentAlong(boundsFrame, boundsSize, Vector3.yAxis)
	local horizontalForward = Vector3.new(modelPivot.LookVector.X, 0, modelPivot.LookVector.Z)
	local forwardDirection = if horizontalForward.Magnitude > HORIZONTAL_DIRECTION_EPSILON
		then horizontalForward.Unit
		else Vector3.zAxis
	local modelDepth = getExtentAlong(boundsFrame, boundsSize, forwardDirection)
	local forwardOffset = math.max(PET_DISPLAY_MIN_FORWARD_OFFSET, modelDepth * PET_DISPLAY_FORWARD_DEPTH_FACTOR)
	local modelTop = boundsFrame.Position
		+ Vector3.yAxis * modelHeight * 0.5
		+ forwardDirection * forwardOffset
	local attachment = state.adorneeAttachment
	if attachment and attachment.Parent and attachment.Parent ~= adornee then
		attachment:Destroy()
		attachment = nil
	end
	if not attachment or attachment.Parent ~= adornee then
		attachment = Instance.new("Attachment")
		attachment.Name = "LuckyBlockPetDisplayAttachment"
		state.adorneeAttachment = attachment
	end
	attachment.Position = adornee.CFrame:PointToObjectSpace(modelTop)
	attachment.Parent = adornee
	state.billboard.Adornee = attachment
	if showDetails then
		local petName = definition.name .. (if slot.count > 1 then " x" .. tostring(slot.count) else "")
		PetDisplayStyler.Apply(state.petName, state.rarityType, petName, definition.rarity)
	else
		state.petName.Text = "???"
		state.petName.TextColor3 = WHITE
		state.rarityType.Text = "???"
		state.rarityType.TextColor3 = WHITE
		local rarityGradient = state.rarityType:FindFirstChildOfClass("UIGradient")
		if rarityGradient then
			rarityGradient.Color = ColorSequence.new(WHITE, WHITE)
		end
	end
	local billboard = state.billboard
	if playPop then
		local targetOffset = state.targetOffset
		billboard.Size = UDim2.new(
			state.targetSize.X.Scale * PET_DISPLAY_START_SCALE,
			state.targetSize.X.Offset * PET_DISPLAY_START_SCALE,
			state.targetSize.Y.Scale * PET_DISPLAY_START_SCALE,
			state.targetSize.Y.Offset * PET_DISPLAY_START_SCALE
		)
		billboard.ExtentsOffsetWorldSpace = targetOffset - Vector3.yAxis * PET_DISPLAY_POP_OFFSET
		billboard.Enabled = true
		local popTween = TweenService:Create(
			billboard,
			TweenInfo.new(PET_DISPLAY_POP_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{
				Size = state.targetSize,
				ExtentsOffsetWorldSpace = targetOffset,
			}
		)
		maid:GiveTask(popTween)
		popTween:Play()
	else
		billboard.Size = state.targetSize
		billboard.ExtentsOffsetWorldSpace = state.targetOffset
		billboard.Enabled = true
	end
	return true
end

local function chooseRoulettePet(
	pets: { PetDefinition },
	slot: RevealSlot,
	previousId: string?,
	usedIds: { [string]: boolean },
	excludeWinner: boolean,
	excludePrevious: boolean
): PetDefinition?
	local candidates: { PetDefinition } = {}
	for _, pet in ipairs(pets) do
		if not usedIds[pet.id]
			and (not excludeWinner or pet.id ~= slot.definition.id)
			and (not excludePrevious or pet.id ~= previousId)
		then
			table.insert(candidates, pet)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[ROULETTE_RANDOM:NextInteger(1, #candidates)]
end

local function chooseRouletteFrame(
	pets: { PetDefinition },
	slots: { RevealSlot },
	previousIds: { [number]: string }
): { [number]: PetDefinition }
	local frame: { [number]: PetDefinition } = {}
	local usedIds: { [string]: boolean } = {}
	for slotIndex, slot in ipairs(slots) do
		local previousId = previousIds[slotIndex]
		local pet = chooseRoulettePet(pets, slot, previousId, usedIds, true, true)
			or chooseRoulettePet(pets, slot, previousId, usedIds, false, true)
			or chooseRoulettePet(pets, slot, previousId, usedIds, false, false)
		if not pet then
			pet = pets[ROULETTE_RANDOM:NextInteger(1, #pets)]
		end
		frame[slotIndex] = pet
		previousIds[slotIndex] = pet.id
		usedIds[pet.id] = true
	end
	return frame
end

local function buildConsolidationPlan(slots: { RevealSlot }): ConsolidationPlan
	local slotsByPetId: { [string]: { RevealSlot } } = {}
	local petIdOrder: { string } = {}
	for _, slot in ipairs(slots) do
		local matchingSlots = slotsByPetId[slot.definition.id]
		if matchingSlots then
			table.insert(matchingSlots, slot)
		else
			slotsByPetId[slot.definition.id] = { slot }
			table.insert(petIdOrder, slot.definition.id)
		end
	end

	local representatives: { RevealSlot } = {}
	local duplicates: { RevealSlot } = {}
	local representativeByPetId: { [string]: RevealSlot } = {}
	local centerRepresentative: RevealSlot? = nil
	local centerDistance = math.huge
	for _, petId in ipairs(petIdOrder) do
		local matchingSlots = assert(slotsByPetId[petId], "Pet result group missing")
		local representative = matchingSlots[1]
		local nearestDistance = (representative.targetFrame.Position - representative.layoutCenter).Magnitude
		for index = 2, #matchingSlots do
			local candidate = matchingSlots[index]
			local distance = (candidate.targetFrame.Position - candidate.layoutCenter).Magnitude
			if distance < nearestDistance then
				representative = candidate
				nearestDistance = distance
			end
		end

		representativeByPetId[petId] = representative
		table.insert(representatives, representative)
		if #matchingSlots > 1 then
			if nearestDistance < centerDistance then
				centerRepresentative = representative
				centerDistance = nearestDistance
			end
			for _, slot in ipairs(matchingSlots) do
				if slot ~= representative then
					table.insert(duplicates, slot)
				end
			end
		end
	end

	if centerRepresentative then
		for index, slot in ipairs(representatives) do
			if slot == centerRepresentative then
				table.remove(representatives, index)
				break
			end
		end
		local representativeCount = #representatives + 1
		local centerIndex = if representativeCount >= 3 then 2 else 1
		table.insert(representatives, centerIndex, centerRepresentative)
	end

	return {
		representatives = representatives,
		duplicates = duplicates,
		representativeByPetId = representativeByPetId,
	}
end

local function updateConsolidatedPetCount(slot: RevealSlot): ()
	local display = slot.petDisplay
	if display then
		PetDisplayStyler.Apply(
			display.petName,
			display.rarityType,
			slot.definition.name .. " x" .. tostring(slot.count),
			slot.definition.rarity
		)
	end
end

local function pulseConsolidatedPet(
	slot: RevealSlot,
	consolidationCount: number,
	maid: CleanupMaid,
	isCurrentRun: () -> boolean,
	onFinished: () -> ()
): ()
	local model = slot.winnerModel
	local baseScale = model:GetScale()
	local pulseCount = math.max(consolidationCount, 1)
	local progress = Instance.new("NumberValue")
	progress.Value = 0
	maid:GiveTask(progress)
	maid:GiveTask(progress:GetPropertyChangedSignal("Value"):Connect(function()
		if not isCurrentRun() or model.Parent == nil then
			return
		end

		local alpha = progress.Value % 1
		local pulse = 1 + (CONSOLIDATION_PULSE_SCALE - 1) * (1 - math.abs(2 * alpha - 1))
		model:ScaleTo(baseScale * pulse)
	end))

	local pulseTween = TweenService:Create(
		progress,
		TweenInfo.new(
			CONSOLIDATION_PULSE_DURATION * pulseCount,
			Enum.EasingStyle.Linear,
			Enum.EasingDirection.InOut
		),
		{ Value = pulseCount }
	)
	maid:GiveTask(pulseTween)
	maid:GiveTask(pulseTween.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and isCurrentRun() and model.Parent then
			model:ScaleTo(baseScale)
			onFinished()
		end
	end))
	pulseTween:Play()
end

local function consolidateDuplicatesTogether(
	plan: ConsolidationPlan,
	maid: CleanupMaid,
	isCurrentRun: () -> boolean,
	onFinished: () -> ()
): ()
	if not isCurrentRun() then
		return
	end

	local consolidationCounts: { [RevealSlot]: number } = {}
	local pendingMerges = #plan.duplicates

	local function finishMerges(): ()
		local pendingPulses = 0
		for representative in pairs(consolidationCounts) do
			updateConsolidatedPetCount(representative)
			pendingPulses += 1
		end
		if pendingPulses == 0 then
			onFinished()
			return
		end

		for representative, consolidationCount in pairs(consolidationCounts) do
			pulseConsolidatedPet(representative, consolidationCount, maid, isCurrentRun, function()
				pendingPulses -= 1
				if pendingPulses == 0 then
					onFinished()
				end
			end)
		end
	end

	local function completeMerge(representative: RevealSlot?): ()
		if representative then
			representative.count += 1
			consolidationCounts[representative] = (consolidationCounts[representative] or 0) + 1
		end
		pendingMerges -= 1
		if pendingMerges == 0 then
			finishMerges()
		end
	end

	for _, duplicate in ipairs(plan.duplicates) do
		local representative = plan.representativeByPetId[duplicate.definition.id]
		if not representative then
			DebugModule.debugWarn("Duplicate pet has no consolidation target", MODULE_NAME)
			duplicate.winnerModel:Destroy()
			completeMerge(nil)
			continue
		end

		if duplicate.petDisplay then
			duplicate.petDisplay.billboard.Enabled = false
		end

		local model = duplicate.winnerModel
		local startFrame = model:GetPivot()
		local startScale = model:GetScale()
		local progress = Instance.new("NumberValue")
		progress.Value = 0
		maid:GiveTask(progress)
		maid:GiveTask(progress:GetPropertyChangedSignal("Value"):Connect(function()
			if not isCurrentRun() or model.Parent == nil then
				return
			end

			local alpha = math.clamp(progress.Value, 0, 1)
			local position = startFrame.Position:Lerp(representative.targetFrame.Position, alpha)
			local rotation = startFrame.Rotation:Lerp(representative.targetFrame.Rotation, alpha)
			model:PivotTo(CFrame.new(position) * rotation)
			model:ScaleTo(startScale * (1 - alpha * 0.9))
		end))

		local mergeTween = TweenService:Create(
			progress,
			TweenInfo.new(DUPLICATE_CONSOLIDATION_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Value = 1 }
		)
		maid:GiveTask(mergeTween)
		maid:GiveTask(mergeTween.Completed:Connect(function(state: Enum.PlaybackState)
			if state ~= Enum.PlaybackState.Completed or not isCurrentRun() then
				return
			end

			model:Destroy()
			completeMerge(representative)
		end))
		mergeTween:Play()
	end
end

local function pauseBeforeCutsceneEnds(
	maid: CleanupMaid,
	isCurrentRun: () -> boolean,
	onFinished: () -> ()
): ()
	local holdValue = Instance.new("NumberValue")
	holdValue.Value = 0
	maid:GiveTask(holdValue)

	local holdTween = TweenService:Create(
		holdValue,
		TweenInfo.new(CONSOLIDATION_END_HOLD_DURATION, Enum.EasingStyle.Linear),
		{ Value = 1 }
	)
	maid:GiveTask(holdTween)
	maid:GiveTask(holdTween.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and isCurrentRun() then
			onFinished()
		end
	end))
	holdTween:Play()
end

local consolidateDuplicatePets: (
	slots: { RevealSlot },
	maid: CleanupMaid,
	isCurrentRun: () -> boolean,
	onFinished: () -> ()
) -> ()

local function hasDuplicatePetResults(slots: { RevealSlot }): boolean
	local seenPetIds: { [string]: boolean } = {}
	for _, slot in ipairs(slots) do
		local petId = slot.definition.id
		if seenPetIds[petId] then
			return true
		end
		seenPetIds[petId] = true
	end
	return false
end

local function playHighlightReveal(
	slots: { RevealSlot },
	maid: CleanupMaid,
	isCurrentRun: () -> boolean,
	skipConsolidation: boolean,
	onFinished: () -> ()
): ()
	local flashValue = Instance.new("NumberValue")
	flashValue.Value = 0
	maid:GiveTask(flashValue)
	maid:GiveTask(flashValue:GetPropertyChangedSignal("Value"):Connect(function()
		local alpha = math.clamp(flashValue.Value, 0, 1)
		for _, slot in ipairs(slots) do
			if slot.highlight.Parent then
				slot.highlight.FillColor = BLACK:Lerp(WHITE, alpha)
			end
		end
	end))
	local flashTween = TweenService:Create(
		flashValue,
		TweenInfo.new(HIGHLIGHT_FLASH_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Value = 1 }
	)
	maid:GiveTask(flashTween)
	maid:GiveTask(flashTween.Completed:Connect(function(flashState: Enum.PlaybackState)
		if flashState ~= Enum.PlaybackState.Completed or not isCurrentRun() then
			return
		end
		local lastIndex = #slots
		for index, slot in ipairs(slots) do
			local fadeTween = TweenService:Create(
				slot.highlight,
				TweenInfo.new(
					HIGHLIGHT_FADE_DURATION,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out,
					0,
					false,
					HIGHLIGHT_HOLD_DURATION
				),
				{ FillTransparency = 1, OutlineTransparency = 1 }
			)
			maid:GiveTask(fadeTween)
			if index == lastIndex then
				maid:GiveTask(fadeTween.Completed:Connect(function(fadeState: Enum.PlaybackState)
					if fadeState == Enum.PlaybackState.Completed and isCurrentRun() then
						local displayCount = 0
						for _, finalSlot in ipairs(slots) do
							if setPetDisplay(
								finalSlot,
								finalSlot.definition,
								finalSlot.winnerModel,
								true,
								true,
								maid
							) then
								displayCount += 1
							end
						end
						local rewardSound = SoundService.PlayGuiSound("LuckyBlockReward")
						if rewardSound then
							maid:GiveTask(rewardSound)
						end
						if displayCount == 0 then
							if skipConsolidation then
								onFinished()
							else
								consolidateDuplicatePets(slots, maid, isCurrentRun, onFinished)
							end
							return
						end

						local holdValue = Instance.new("NumberValue")
						holdValue.Value = 0
						maid:GiveTask(holdValue)
						local holdDuration = if skipConsolidation or hasDuplicatePetResults(slots)
							then DUPLICATE_RESULT_HOLD_DURATION
							else PET_DISPLAY_HOLD_DURATION
						local holdTween = TweenService:Create(
							holdValue,
							TweenInfo.new(holdDuration, Enum.EasingStyle.Linear),
							{ Value = 1 }
						)
						maid:GiveTask(holdTween)
						maid:GiveTask(holdTween.Completed:Connect(function(holdState: Enum.PlaybackState)
							if holdState == Enum.PlaybackState.Completed and isCurrentRun() then
								if skipConsolidation then
									onFinished()
								else
									consolidateDuplicatePets(slots, maid, isCurrentRun, onFinished)
								end
							end
						end))
						holdTween:Play()
					end
				end))
			end
			fadeTween:Play()
		end
	end))
	flashTween:Play()
end

consolidateDuplicatePets = function(
	slots: { RevealSlot },
	maid: CleanupMaid,
	isCurrentRun: () -> boolean,
	onFinished: () -> ()
): ()
	local plan = buildConsolidationPlan(slots)
	if #plan.duplicates == 0 then
		onFinished()
		return
	end

	local function beginMerging(): ()
		consolidateDuplicatesTogether(plan, maid, isCurrentRun, function()
			pauseBeforeCutsceneEnds(maid, isCurrentRun, onFinished)
		end)
	end

	local activeCamera = Workspace.CurrentCamera
	if not activeCamera or #plan.representatives == 0 then
		beginMerging()
		return
	end

	local rows = makeRows(#plan.representatives)
	local compactLayout = calculateGridLayout(plan.representatives, rows)
	positionSlotsInGrid(
		plan.representatives,
		rows,
		compactLayout,
		activeCamera,
		plan.representatives[1].layoutCenter,
		activeCamera.CFrame.Position
	)

	local starts: { [RevealSlot]: CFrame } = {}
	for _, slot in ipairs(plan.representatives) do
		starts[slot] = slot.winnerModel:GetPivot()
	end
	local reflowProgress = Instance.new("NumberValue")
	reflowProgress.Value = 0
	maid:GiveTask(reflowProgress)
	maid:GiveTask(reflowProgress:GetPropertyChangedSignal("Value"):Connect(function()
		if not isCurrentRun() then
			return
		end

		local alpha = math.clamp(reflowProgress.Value, 0, 1)
		for _, slot in ipairs(plan.representatives) do
			local startFrame = starts[slot]
			local position = startFrame.Position:Lerp(slot.targetFrame.Position, alpha)
			local rotation = startFrame.Rotation:Lerp(slot.targetFrame.Rotation, alpha)
			slot.winnerModel:PivotTo(CFrame.new(position) * rotation)
		end
	end))

	local reflowTween = TweenService:Create(
		reflowProgress,
		TweenInfo.new(FINAL_GRID_REFLOW_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ Value = 1 }
	)
	maid:GiveTask(reflowTween)
	maid:GiveTask(reflowTween.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and isCurrentRun() then
			beginMerging()
		end
	end))
	reflowTween:Play()
end

local function beginRouletteSequence(
	playTick: PlayRouletteTick?,
	slots: { RevealSlot },
	pets: { PetDefinition },
	folder: Folder,
	camera: Camera,
	maid: CleanupMaid,
	isCurrentRun: () -> boolean,
	onFinished: () -> ()
): ()
	if not isCurrentRun() then
		return
	end

	local stepTimes: { number } = {}
	local totalDuration = 0
	for step = 1, ROULETTE_SWITCH_COUNT do
		local progress = (step - 1) / math.max(ROULETTE_SWITCH_COUNT - 1, 1)
		local easedProgress = progress * progress
		local interval = ROULETTE_INITIAL_INTERVAL
			+ (ROULETTE_FINAL_INTERVAL - ROULETTE_INITIAL_INTERVAL) * easedProgress
		totalDuration += interval
		table.insert(stepTimes, totalDuration)
	end

	local rouletteTime = Instance.new("NumberValue")
	rouletteTime.Value = 0
	maid:GiveTask(rouletteTime)
	local currentStep = 0
	local previousIds: { [number]: string } = {}
	maid:GiveTask(rouletteTime:GetPropertyChangedSignal("Value"):Connect(function()
		if not isCurrentRun() then
			return
		end
		local elapsed = rouletteTime.Value
		local nextStep = currentStep
		while nextStep < #stepTimes and elapsed >= stepTimes[nextStep + 1] do
			nextStep += 1
		end
		if nextStep <= currentStep then
			return
		end
		currentStep = nextStep
		if currentStep == ROULETTE_SWITCH_COUNT then
			for _, slot in ipairs(slots) do
				showWinner(slot)
			end
			return
		end
		if playTick then
			local tickProgress = math.clamp((currentStep - 1) / math.max(ROULETTE_SWITCH_COUNT - 2, 1), 0, 1)
			playTick(1.25 - 0.3 * tickProgress)
		end

		local rouletteFrame = chooseRouletteFrame(pets, slots, previousIds)
		for slotIndex, slot in ipairs(slots) do
			if currentStep == ROULETTE_SWITCH_COUNT then
				showWinner(slot)
			else
				showRoulettePet(slot, rouletteFrame[slotIndex], folder, camera, maid)
			end
		end
	end))

	local rouletteTween = TweenService:Create(
		rouletteTime,
		TweenInfo.new(totalDuration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
		{ Value = totalDuration }
	)
	maid:GiveTask(rouletteTween)
	maid:GiveTask(rouletteTween.Completed:Connect(function(rouletteState: Enum.PlaybackState)
		if rouletteState ~= Enum.PlaybackState.Completed or not isCurrentRun() then
			return
		end
		for _, slot in ipairs(slots) do
			showWinner(slot)
		end
		playHighlightReveal(slots, maid, isCurrentRun, false, onFinished)
	end))
	rouletteTween:Play()
end

local function playRoulette(
	slots: { RevealSlot },
	pets: { PetDefinition },
	folder: Folder,
	camera: Camera,
	maid: CleanupMaid,
	isCurrentRun: () -> boolean,
	onFinished: () -> ()
): ()
	local tickSound: Sound? = SoundService.CreateSound(RobloxSoundService, "Pop", { Volume = 0.16 })
	if tickSound then
		maid:GiveTask(tickSound)
	end

	local rouletteStarted = false
	local function playRouletteTick(playbackSpeed: number): ()
		local tickSound = SoundService.PlayGuiSound("Pop", RobloxSoundService, {
			Volume = 0.3,
			PlaybackSpeed = playbackSpeed,
		})
		if tickSound then
			maid:GiveTask(tickSound)
		end
	end

	local function startRoulette(soundLoaded: boolean): ()
		if rouletteStarted or not isCurrentRun() then
			return
		end
		rouletteStarted = true
		if tickSound and tickSound.Parent then
			tickSound:Destroy()
		end
		beginRouletteSequence(
			if soundLoaded then playRouletteTick else nil,
			slots,
			pets,
			folder,
			camera,
			maid,
			isCurrentRun,
			onFinished
		)
	end

	if not tickSound then
		DebugModule.debugWarn("Pop sound template unavailable; roulette has no tick sound", MODULE_NAME)
		startRoulette(false)
	elseif tickSound.IsLoaded then
		startRoulette(true)
	else
		local soundToPreload = tickSound
		local preloadThread = task.spawn(function()
			local soundLoaded = SoundService.PreloadSoundInstance(soundToPreload)
			if not isCurrentRun() or rouletteStarted then
				return
			end
			if soundLoaded and soundToPreload.Parent then
				startRoulette(true)
			else
				DebugModule.debugWarn("Pop failed to load; skipping ticks instead of playing late", MODULE_NAME)
				if soundToPreload.Parent then
					soundToPreload:Destroy()
				end
				startRoulette(false)
			end
		end)
		maid:GiveTask(preloadThread)

		local preloadTimeout = task.delay(3, function()
			if rouletteStarted or not isCurrentRun() then
				return
			end
			pcall(task.cancel, preloadThread)
			DebugModule.debugWarn("Pop load timed out; continuing roulette without delayed ticks", MODULE_NAME)
			if soundToPreload.Parent then
				soundToPreload:Destroy()
			end
			startRoulette(false)
		end)
		maid:GiveTask(preloadTimeout)
	end
end

function PetLuckyBlockRevealController.Play(
	group: LuckyBlockGroup,
	petIds: { string },
	block: Model,
	camera: Camera?,
	maid: CleanupMaid,
	isCurrentRun: () -> boolean,
	onFinished: () -> (),
	fastOpen: boolean
): boolean
	if #petIds ~= 1 and #petIds ~= 3 and #petIds ~= 5 then
		DebugModule.debugWarn("Rejected invalid Lucky Block reveal count", MODULE_NAME)
		return false
	end
	local pets, lookup = getPetLookup(group)
	if not pets or #pets == 0 then
		DebugModule.debugWarn("Lucky Block reveal pool missing | group=" .. group, MODULE_NAME)
		return false
	end
	for _, petId in ipairs(petIds) do
		if not lookup[petId] then
			DebugModule.debugWarn("Server returned pet outside Lucky Block pool | group=" .. group, MODULE_NAME)
			return false
		end
	end
	local activeCamera = if camera and camera.Parent then camera else Workspace.CurrentCamera
	if not activeCamera then
		DebugModule.debugWarn("Cannot start Lucky Block reveal without a current camera", MODULE_NAME)
		return false
	end

	local displayPetIds = petIds
	local petCounts: { [string]: number } = {}
	if fastOpen then
		local uniquePetIds: { string } = {}
		for _, petId in ipairs(petIds) do
			local count = petCounts[petId] or 0
			petCounts[petId] = count + 1
			if count == 0 then
				table.insert(uniquePetIds, petId)
			end
		end
		displayPetIds = uniquePetIds
	end

	local folder = Instance.new("Folder")
	folder.Name = "LuckyBlockPetReveal"
	local layout = createSlots(displayPetIds, petCounts, lookup, block, activeCamera, folder, maid)
	if not layout then
		folder:Destroy()
		DebugModule.debugWarn("Could not create every Lucky Block reveal pet | group=" .. group, MODULE_NAME)
		return false
	end

	local slots = layout.slots
	folder.Parent = activeCamera
	maid:GiveTask(folder)
	local launchDuration = if fastOpen then FAST_LAUNCH_DURATION else LAUNCH_DURATION
	local cameraTween = TweenService:Create(
		activeCamera,
		TweenInfo.new(launchDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = layout.cameraFrame }
	)
	maid:GiveTask(cameraTween)
	cameraTween:Play()
	local launchValue = Instance.new("NumberValue")
	launchValue.Value = 0
	maid:GiveTask(launchValue)
	maid:GiveTask(launchValue:GetPropertyChangedSignal("Value"):Connect(function()
		if not isCurrentRun() then
			return
		end
		local progress = math.clamp(launchValue.Value, 0, 1)
		local turn = 1 - progress
		local spin = CFrame.Angles(math.rad(38 * turn), math.rad(540 * turn), math.rad(24 * turn))
		for _, slot in ipairs(slots) do
			local position = slot.startFrame.Position:Lerp(slot.targetFrame.Position, progress)
			local rotation = slot.startFrame.Rotation:Lerp(slot.targetFrame.Rotation, progress)
			local easedScale = START_SCALE + (1 - START_SCALE) * progress
			slot.winnerModel:ScaleTo(slot.finalScale * easedScale)
			slot.winnerModel:PivotTo(CFrame.new(position) * rotation * spin)
		end
	end))
	local launchTween = TweenService:Create(
		launchValue,
		TweenInfo.new(launchDuration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Value = 1 }
	)
	maid:GiveTask(launchTween)
	maid:GiveTask(launchTween.Completed:Connect(function(launchState: Enum.PlaybackState)
		if launchState == Enum.PlaybackState.Completed and isCurrentRun() then
			if fastOpen then
				for _, slot in ipairs(slots) do
					showWinner(slot)
				end
				playHighlightReveal(slots, maid, isCurrentRun, true, onFinished)
			else
				playRoulette(slots, pets, folder, activeCamera, maid, isCurrentRun, onFinished)
			end
		end
	end))
	launchTween:Play()
	return true
end

return PetLuckyBlockRevealController
