--!strict

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClientCullingService = require(ReplicatedStorage.Modules.ClientCullingService)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local PetRarityConfig = require(ReplicatedStorage.Modules.Config.PetRarityConfig)
local PetDisplayStyler = require(ReplicatedStorage.Modules.UI.PetDisplayStyler)
local PetViewportRenderer = require(ReplicatedStorage.Modules.UI.PetViewportRenderer)

type PetDefinition = PetConfig.PetDefinition
type EquippedPet = {
	visualKey: string,
	petId: string,
	definition: PetDefinition,
	stars: number,
	multiplier: number,
}
type CleanupTask = Instance | RBXScriptConnection | thread | (() -> ())
type MaidLike = {
	GiveTask: (self: MaidLike, task: CleanupTask) -> number,
	DoCleaning: (self: MaidLike) -> (),
}
type Follower = {
	visualKey: string,
	petId: string,
	model: Model,
	depth: number,
	groundOffset: number,
	phase: number,
}
type PlayerState = {
	player: Player,
	maid: MaidLike,
	characterMaid: MaidLike?,
	character: Model?,
	root: BasePart?,
	humanoid: Humanoid?,
	kart: Model?,
	kartRearExtent: number?,
	groundRaycastParams: RaycastParams,
	groundY: number?,
	groundProbePosition: Vector3?,
	groundProbeAt: number,
	followerFolder: Folder?,
	followers: { [string]: Follower },
	followerOrder: { Follower },
	desired: { EquippedPet },
	inRenderRange: boolean,
	active: boolean,
	invalidInventoryLogged: boolean,
}
type KartTrackingState = {
	maid: MaidLike,
	ownerState: PlayerState?,
}

local PetFollowerController = {}
local MODULE_NAME = "PetFollowerController"
local INVENTORY_ATTRIBUTE = "Pet_Inventory"
local PET_DISPLAY_NAME = "PetDisplay"
local PET_DISPLAY_ATTACHMENT_NAME = "PetFollowerDisplayAttachment"
local EQUIPPED_KART_MODEL_TAG = "SB_EquippedKartModel"
local PET_GROUPS: { PetConfig.LuckyBlockGroup } = {
	"Tier1",
	"Tier2",
	"Tier3",
	"Premium",
	"BloodMoon",
	"NeonRush",
	"FrostbiteRally",
}

local playerStates: { [Player]: PlayerState } = {}
local trackedKartModels: { [Model]: KartTrackingState } = {}
local petDefinitionsById: { [string]: PetDefinition } = {}
local petIsPaidById: { [string]: boolean } = {}
local localPlayer: Player? = Players.LocalPlayer
local followerRootFolder: Folder? = nil
local ownsFollowerRootFolder = false
local randomGenerator = Random.new()
local initialized = false
local renderConnection: RBXScriptConnection? = nil
local playerAddedConnection: RBXScriptConnection? = nil
local playerRemovingConnection: RBXScriptConnection? = nil
local kartAddedConnection: RBXScriptConnection? = nil
local kartRemovedConnection: RBXScriptConnection? = nil
local warnedMissingDisplay = false

local function createMaid(): MaidLike
	return Maid.new() :: MaidLike
end

local function createGroundRaycastParams(): RaycastParams
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true
	raycastParams.RespectCanCollide = true
	return raycastParams
end

local function refreshGroundRaycastFilter(state: PlayerState): ()
	local excludedInstances: { Instance } = {}
	if state.character then
		table.insert(excludedInstances, state.character)
	end
	if state.kart then
		table.insert(excludedInstances, state.kart)
	end
	if followerRootFolder then
		table.insert(excludedInstances, followerRootFolder)
	end
	state.groundRaycastParams.FilterDescendantsInstances = excludedInstances
	state.groundY = nil
	state.groundProbePosition = nil
	state.groundProbeAt = 0
end

local function getCachedGroundY(state: PlayerState, now: number): number?
	local root = state.root
	if not root or not root.Parent then
		return nil
	end

	local probePosition = Vector3.new(root.Position.X, 0, root.Position.Z)
	local previousPosition = state.groundProbePosition
	local moved = not previousPosition
		or (probePosition - previousPosition).Magnitude >= PetConfig.Followers.groundRaycastMoveThreshold
	local timeSinceProbe = now - state.groundProbeAt
	local movementRefreshDue = moved and timeSinceProbe >= PetConfig.Followers.groundRaycastMoveCooldown
	local intervalRefreshDue = timeSinceProbe >= PetConfig.Followers.groundRaycastInterval
	if not movementRefreshDue and not intervalRefreshDue then
		return state.groundY
	end

	state.groundProbePosition = probePosition
	state.groundProbeAt = now
	local rayOrigin = root.Position + Vector3.yAxis * PetConfig.Followers.groundRaycastUpOffset
	local rayDirection = -Vector3.yAxis * PetConfig.Followers.groundRaycastDownDistance
	local result = Workspace:Raycast(rayOrigin, rayDirection, state.groundRaycastParams)
	state.groundY = if result then result.Position.Y else nil
	return state.groundY
end

local function getPlayerFollowerFolder(player: Player): Folder?
	local rootFolder = followerRootFolder
	if not rootFolder or not rootFolder.Parent then
		local existingRoot = Workspace:FindFirstChild("PetFollower")
		if existingRoot then
			if not existingRoot:IsA("Folder") then
				DebugModule.debugWarn("Workspace.PetFollower exists but is not a Folder", MODULE_NAME)
				return nil
			end
			rootFolder = existingRoot
		else
			rootFolder = Instance.new("Folder")
			rootFolder.Name = "PetFollower"
			rootFolder.Parent = Workspace
			ownsFollowerRootFolder = true
		end
		followerRootFolder = rootFolder
	end

	for _, child in ipairs(rootFolder:GetChildren()) do
		if child:IsA("Folder") and child:GetAttribute("PetFollowerUserId") == player.UserId then
			child.Name = string.format("%s_%d", player.Name, player.UserId)
			return child
		end
	end

	local folderName = string.format("%s_%d", player.Name, player.UserId)
	local existingFolder = rootFolder:FindFirstChild(folderName)
	if existingFolder then
		if not existingFolder:IsA("Folder") then
			DebugModule.debugWarn(
				string.format("Player follower folder is not a Folder | player=%s", player.Name),
				MODULE_NAME
			)
			return nil
		end
		existingFolder:SetAttribute("PetFollowerUserId", player.UserId)
		return existingFolder
	end

	local folder = Instance.new("Folder")
	folder.Name = folderName
	folder:SetAttribute("PetFollowerUserId", player.UserId)
	folder.Parent = rootFolder
	return folder
end

local function getLuckyBlockForGroup(group: PetConfig.LuckyBlockGroup): PetConfig.LuckyBlockDefinition
	if group == "Tier1" or group == "Tier2" or group == "Tier3" or group == "Premium" then
		return PetConfig.LuckyBlocks[group]
	end
	return PetConfig.LuckyBlocks.Event
end

for _, group in ipairs(PET_GROUPS) do
	local pets = PetConfig.GetPetsForLuckyBlock(group)
	if pets then
		local isPaid = getLuckyBlockForGroup(group).rollCurrency == "Robux"
		for _, definition in ipairs(pets) do
			petDefinitionsById[definition.id] = definition
			petIsPaidById[definition.id] = isPaid
		end
	end
end

local function getEffectiveMultiplier(definition: PetDefinition, stars: number): number
	return PetConfig.GetPetMultiplier(
		definition.multiplier,
		definition.rarity,
		petIsPaidById[definition.id] == true,
		stars
	)
end

local function clearFollowers(state: PlayerState): ()
	for visualKey, follower in pairs(state.followers) do
		follower.model:Destroy()
		state.followers[visualKey] = nil
	end
	table.clear(state.followerOrder)
end

local function removeOrphanedFollowerModels(state: PlayerState): ()
	local trackedModels: { [Model]: boolean } = {}
	for _, follower in pairs(state.followers) do
		trackedModels[follower.model] = true
	end

	local removedCount = 0
	local folder = state.followerFolder
	if folder and folder.Parent then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") and not trackedModels[child] then
				child:Destroy()
				removedCount += 1
			end
		end
	end

	-- Remove legacy clones left directly under Workspace by older controller versions.
	local legacyModelName = string.format("PetFollower_%d", state.player.UserId)
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and child.Name == legacyModelName and not trackedModels[child] then
			child:Destroy()
			removedCount += 1
		end
	end

	if removedCount > 0 then
		DebugModule.debugWarn(
			string.format("Removed stale follower clones | player=%s | count=%d", state.player.Name, removedCount),
			MODULE_NAME
		)
	end
end

local function readEquippedPets(state: PlayerState): { EquippedPet }?
	local encoded = state.player:GetAttribute(INVENTORY_ATTRIBUTE)
	if typeof(encoded) ~= "string" or encoded == "" then
		state.invalidInventoryLogged = false
		return {}
	end

	local success, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not success or typeof(decoded) ~= "table" then
		if not state.invalidInventoryLogged then
			state.invalidInventoryLogged = true
			DebugModule.debugWarn(
				"Could not decode replicated pet inventory | player=" .. state.player.Name,
				MODULE_NAME
			)
		end
		return nil
	end
	state.invalidInventoryLogged = false

	local equippedPets: { EquippedPet } = {}
	local seenUids: { [string]: boolean } = {}
	for _, value in ipairs(decoded) do
		if typeof(value) == "table" then
			local record = value :: { [string]: any }
			local uid = record.uid
			local petId = record.petId
			local definition = if typeof(petId) == "string" then petDefinitionsById[petId] else nil
			if typeof(uid) == "string"
				and #uid > 0
				and #uid <= 128
				and not seenUids[uid]
				and record.equipped == true
				and typeof(record.stars) == "number"
				and record.stars >= 1
				and record.stars <= PetConfig.StarUpgrades.maxStars
				and definition
			then
				seenUids[uid] = true
				local stars = math.floor(record.stars)
				table.insert(equippedPets, {
					visualKey = uid,
					petId = petId,
					definition = definition,
					stars = stars,
					multiplier = getEffectiveMultiplier(definition, stars),
				})
			end
		end
	end
	table.sort(equippedPets, function(left: EquippedPet, right: EquippedPet): boolean
		local leftRarity = PetRarityConfig.RarityOrder[left.definition.rarity] or 0
		local rightRarity = PetRarityConfig.RarityOrder[right.definition.rarity] or 0
		if leftRarity ~= rightRarity then
			return leftRarity > rightRarity
		end
		if left.stars ~= right.stars then
			return left.stars > right.stars
		end
		if left.multiplier ~= right.multiplier then
			return left.multiplier > right.multiplier
		end
		return left.visualKey < right.visualKey
	end)
	while #equippedPets > PetConfig.Followers.maxVisualPets do
		table.remove(equippedPets)
	end
	return equippedPets
end

local function findAdorneePart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local part = model:FindFirstChildWhichIsA("BasePart", true)
	return if part and part:IsA("BasePart") then part else nil
end

local function createPetBillboard(
	model: Model,
	definition: PetDefinition
): ()
	local userInterface = ReplicatedStorage:FindFirstChild("UserInterface")
	local template = userInterface and userInterface:FindFirstChild(PET_DISPLAY_NAME)
	if not template or not template:IsA("BillboardGui") then
		if not warnedMissingDisplay then
			warnedMissingDisplay = true
			DebugModule.debugWarn("UserInterface.PetDisplay BillboardGui missing", MODULE_NAME)
		end
		return
	end

	local adorneePart = findAdorneePart(model)
	if not adorneePart then
		DebugModule.debugWarn("Follower pet has no BasePart | pet=" .. definition.id, MODULE_NAME)
		return
	end

	local boundsFrame, boundsSize = model:GetBoundingBox()
	local attachment = Instance.new("Attachment")
	attachment.Name = PET_DISPLAY_ATTACHMENT_NAME
	attachment.Position = adorneePart.CFrame:PointToObjectSpace(
		boundsFrame.Position + Vector3.yAxis * (boundsSize.Y * 0.5 + PetConfig.Followers.billboardTopPadding)
	)
	attachment.Parent = adorneePart

	local display = template:Clone()
	local petName = display:FindFirstChild("PetName", true)
	local rarityType = display:FindFirstChild("RarityType", true)
	if not petName or not petName:IsA("TextLabel") or not rarityType or not rarityType:IsA("TextLabel") then
		display:Destroy()
		attachment:Destroy()
		DebugModule.debugWarn("PetDisplay missing PetName or RarityType TextLabel", MODULE_NAME)
		return
	end

	PetDisplayStyler.Apply(petName, rarityType, definition.name, definition.rarity)
	display.Name = "PetFollowerDisplay"
	display.Size = PetConfig.Followers.billboardSize
	display.MaxDistance = PetConfig.Followers.billboardMaxDistance
	display.ExtentsOffsetWorldSpace = Vector3.zero
	display.Adornee = attachment
	display.Enabled = true
	display.Parent = model
	CollectionService:AddTag(display, ClientCullingService.Tags.Billboard)
end

local function createFollower(equippedPet: EquippedPet): Follower?
	local definition = equippedPet.definition
	local model = PetViewportRenderer.CloneModel(definition.modelPath)
	if not model then
		return nil
	end

	local boundsFrame, boundsSize = model:GetBoundingBox()
	local limits = PetConfig.Followers.maxBounds
	if boundsSize.X <= 0 or boundsSize.Y <= 0 or boundsSize.Z <= 0 then
		model:Destroy()
		DebugModule.debugWarn("Invalid pet follower bounds | pet=" .. definition.id, MODULE_NAME)
		return nil
	end
	local fitScale = math.min(limits.X / boundsSize.X, limits.Y / boundsSize.Y, limits.Z / boundsSize.Z)
	if fitScale ~= fitScale or fitScale <= 0 or fitScale == math.huge then
		model:Destroy()
		DebugModule.debugWarn("Invalid pet follower scale | pet=" .. definition.id, MODULE_NAME)
		return nil
	end
	model:ScaleTo(model:GetScale() * fitScale)
	local fittedBoundsFrame, fittedBounds = model:GetBoundingBox()
	local verticalExtent = (
		math.abs(fittedBoundsFrame.RightVector.Y) * fittedBounds.X
		+ math.abs(fittedBoundsFrame.UpVector.Y) * fittedBounds.Y
		+ math.abs(fittedBoundsFrame.LookVector.Y) * fittedBounds.Z
	) * 0.5
	local groundOffset = model:GetPivot().Position.Y
		- (fittedBoundsFrame.Position.Y - verticalExtent)
		+ PetConfig.Followers.groundClearance
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CastShadow = false
		end
	end
	createPetBillboard(model, definition)

	return {
		visualKey = equippedPet.visualKey,
		petId = definition.id,
		model = model,
		depth = fittedBounds.Z,
		groundOffset = groundOffset,
		phase = randomGenerator:NextNumber(0, math.pi * 2),
	}
end

local function getRootFacing(root: BasePart): CFrame
	local lookVector = root.CFrame.LookVector
	local horizontalLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if horizontalLook.Magnitude <= 0.001 then
		horizontalLook = Vector3.new(0, 0, -1)
	else
		horizontalLook = horizontalLook.Unit
	end
	return CFrame.lookAt(root.Position, root.Position + horizontalLook, Vector3.yAxis)
end

local function getKartRearExtent(state: PlayerState, kart: Model): number?
	local root = state.root
	if not root or not root.Parent or not kart.Parent then
		return nil
	end
	local boundsFrame, boundsSize = kart:GetBoundingBox()
	local rearDirection = -getRootFacing(root).LookVector
	local centerOffset = (boundsFrame.Position - root.Position):Dot(rearDirection)
	local halfExtent = (
		math.abs(boundsFrame.RightVector:Dot(rearDirection)) * boundsSize.X
		+ math.abs(boundsFrame.UpVector:Dot(rearDirection)) * boundsSize.Y
		+ math.abs(boundsFrame.LookVector:Dot(rearDirection)) * boundsSize.Z
	) * 0.5
	return math.max(root.Size.Z * 0.5, centerOffset + halfExtent)
end

local function setKartForPlayerState(state: PlayerState, kart: Model?): ()
	state.kart = kart
	state.kartRearExtent = if kart then getKartRearExtent(state, kart) else nil
	refreshGroundRaycastFilter(state)
end

local function refreshKartOwner(kart: Model): ()
	local trackingState = trackedKartModels[kart]
	if not trackingState then
		return
	end

	local ownerUserId = kart:GetAttribute("KartOwnerUserId")
	if typeof(ownerUserId) ~= "number" then
		ownerUserId = kart:GetAttribute("OwnerUserId")
	end
	local owner = if typeof(ownerUserId) == "number" then Players:GetPlayerByUserId(ownerUserId) else nil
	local nextOwnerState = if owner then playerStates[owner] else nil
	if trackingState.ownerState and trackingState.ownerState ~= nextOwnerState
		and trackingState.ownerState.kart == kart
	then
		setKartForPlayerState(trackingState.ownerState, nil)
	end
	trackingState.ownerState = nextOwnerState
	if nextOwnerState and nextOwnerState.kart ~= kart then
		setKartForPlayerState(nextOwnerState, kart)
	elseif nextOwnerState then
		nextOwnerState.kartRearExtent = getKartRearExtent(nextOwnerState, kart)
	end
end

local function unregisterKartModel(kart: Model): ()
	local trackingState = trackedKartModels[kart]
	if not trackingState then
		return
	end
	trackedKartModels[kart] = nil
	if trackingState.ownerState and trackingState.ownerState.kart == kart then
		setKartForPlayerState(trackingState.ownerState, nil)
	end
	trackingState.maid:DoCleaning()
end

local function registerKartModel(instance: Instance): ()
	if not instance:IsA("Model") then
		return
	end
	local kart = instance
	if trackedKartModels[kart] then
		refreshKartOwner(kart)
		return
	end

	local trackingState: KartTrackingState = {
		maid = createMaid(),
		ownerState = nil,
	}
	trackedKartModels[kart] = trackingState
	trackingState.maid:GiveTask(kart:GetAttributeChangedSignal("KartOwnerUserId"):Connect(function()
		refreshKartOwner(kart)
	end))
	trackingState.maid:GiveTask(kart:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
		refreshKartOwner(kart)
	end))
	trackingState.maid:GiveTask(kart.AncestryChanged:Connect(function(_, parent: Instance?)
		if parent then
			refreshKartOwner(kart)
		else
			unregisterKartModel(kart)
		end
	end))
	refreshKartOwner(kart)
end

local function getTargetFrame(
	state: PlayerState,
	follower: Follower,
	index: number,
	count: number,
	now: number,
	groundY: number?
): CFrame?
	local root = state.root
	local humanoid = state.humanoid
	if not root or not root.Parent or not humanoid or humanoid.Health <= 0 then
		return nil
	end

	local columns = math.clamp(math.floor(PetConfig.Followers.maxColumns), 1, math.max(count, 1))
	local row = math.floor((index - 1) / columns)
	local rowStart = row * columns + 1
	local rowCount = math.min(columns, count - row * columns)
	local column = index - rowStart
	local horizontalOffset = (column - (rowCount - 1) * 0.5) * PetConfig.Followers.spacing
	local bob = (math.sin(now * PetConfig.Followers.bobFrequency + follower.phase) + 1)
		* 0.5
		* PetConfig.Followers.bobAmplitude
	local sway = math.sin(now * PetConfig.Followers.bobFrequency * 0.7 + follower.phase)
		* PetConfig.Followers.swayAngle
	local velocity = root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local tiltThreshold = PetConfig.Followers.movementTiltThreshold
	local fullTiltSpeed = math.max(PetConfig.Followers.movementTiltFullSpeed, tiltThreshold + 0.01)
	local movementAlpha = math.clamp((horizontalSpeed - tiltThreshold) / (fullTiltSpeed - tiltThreshold), 0, 1)
	local movementPitch = -PetConfig.Followers.movementTiltAngle * movementAlpha
	local fallbackGroundY = root.Position.Y - humanoid.HipHeight - root.Size.Y * 0.5
	local verticalOffset = (groundY or fallbackGroundY) + follower.groundOffset + bob - root.Position.Y
	local facing = getRootFacing(root)
	local rearExtent = state.kartRearExtent or root.Size.Z * 0.5
	local rearClearance = if state.kart and state.kart.Parent
		then PetConfig.Followers.kartRearClearance
		else PetConfig.Followers.followDistance
	local depthOffset = rearExtent + rearClearance + follower.depth * 0.5 + row * PetConfig.Followers.spacing
	return facing
		* CFrame.new(horizontalOffset, verticalOffset, depthOffset)
		* CFrame.Angles(
			movementPitch,
			sway,
			math.sin(now * 1.7 + follower.phase) * PetConfig.Followers.swayAngle * 0.5
		)
end

local function reconcileFollowers(state: PlayerState): ()
	local root = state.root
	local humanoid = state.humanoid
	if not state.active or not state.inRenderRange or not root or not humanoid or humanoid.Health <= 0 then
		clearFollowers(state)
		removeOrphanedFollowerModels(state)
		return
	end
	if not state.followerFolder or not state.followerFolder.Parent then
		if state.followerFolder then
			state.followerFolder:Destroy()
		end
		state.followerFolder = getPlayerFollowerFolder(state.player)
		refreshGroundRaycastFilter(state)
	end
	if not state.followerFolder then
		clearFollowers(state)
		return
	end

	local desiredByUid: { [string]: EquippedPet } = {}
	for _, equippedPet in ipairs(state.desired) do
		desiredByUid[equippedPet.visualKey] = equippedPet
	end
	for uid, follower in pairs(state.followers) do
		local equippedPet = desiredByUid[uid]
		if not equippedPet or equippedPet.petId ~= follower.petId then
			follower.model:Destroy()
			state.followers[uid] = nil
		end
	end

	table.clear(state.followerOrder)
	for _, equippedPet in ipairs(state.desired) do
		local follower = state.followers[equippedPet.visualKey]
		if not follower then
			follower = createFollower(equippedPet)
			if follower then
				state.followers[equippedPet.visualKey] = follower
			end
		end
		if follower then
			table.insert(state.followerOrder, follower)
		end
	end

	local now = os.clock()
	local groundY = if #state.followerOrder > 0 then getCachedGroundY(state, now) else nil
	for index, follower in ipairs(state.followerOrder) do
		local targetFrame = getTargetFrame(state, follower, index, #state.followerOrder, now, groundY)
		if targetFrame then
			follower.model:PivotTo(targetFrame)
			follower.model.Name = string.format("PetFollower_%d", state.player.UserId)
			follower.model.Parent = state.followerFolder
		end
	end
	removeOrphanedFollowerModels(state)
end

local function updateDesiredPets(state: PlayerState): ()
	local desiredPets = readEquippedPets(state)
	if not desiredPets then
		return
	end
	state.desired = desiredPets
	reconcileFollowers(state)
end

local function bindCharacter(state: PlayerState, character: Model): ()
	if state.characterMaid then
		state.characterMaid:DoCleaning()
	end
	clearFollowers(state)
	state.character = character
	state.root = nil
	state.humanoid = nil
	state.kart = nil
	state.kartRearExtent = nil
	refreshGroundRaycastFilter(state)
	state.inRenderRange = false
	local characterMaid: MaidLike = createMaid()
	state.characterMaid = characterMaid
	local boundHumanoid: Humanoid? = nil

	local function resolveCharacterParts(): ()
		if not state.active or state.character ~= character then
			return
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") then
			state.root = root
		end
		if humanoid and boundHumanoid ~= humanoid then
			boundHumanoid = humanoid
			state.humanoid = humanoid
			characterMaid:GiveTask(humanoid.Died:Connect(function()
				clearFollowers(state)
			end))
		end
		if state.root and state.humanoid then
			if state.kart then
				state.kartRearExtent = getKartRearExtent(state, state.kart)
			else
				for kart, trackingState in pairs(trackedKartModels) do
					if trackingState.ownerState == state then
						setKartForPlayerState(state, kart)
						break
					end
				end
			end
			reconcileFollowers(state)
		end
	end

	characterMaid:GiveTask(character.ChildAdded:Connect(resolveCharacterParts))
	resolveCharacterParts()
end

local function cleanupPlayer(state: PlayerState): ()
	if not state.active then
		return
	end
	state.active = false
	if state.characterMaid then
		state.characterMaid:DoCleaning()
		state.characterMaid = nil
	end
	state.maid:DoCleaning()
	clearFollowers(state)
	if state.followerFolder then
		state.followerFolder:Destroy()
		state.followerFolder = nil
	end
	state.character = nil
	state.root = nil
	state.humanoid = nil
	state.kart = nil
	state.kartRearExtent = nil
	for _, trackingState in pairs(trackedKartModels) do
		if trackingState.ownerState == state then
			trackingState.ownerState = nil
		end
	end
	table.clear(state.desired)
end

local function bindPlayer(player: Player): ()
	if playerStates[player] then
		return
	end
	local state: PlayerState = {
		player = player,
		maid = createMaid(),
		characterMaid = nil,
		character = nil,
		root = nil,
		humanoid = nil,
		kart = nil,
		kartRearExtent = nil,
		groundRaycastParams = createGroundRaycastParams(),
		groundY = nil,
		groundProbePosition = nil,
		groundProbeAt = 0,
		followerFolder = getPlayerFollowerFolder(player),
		followers = {},
		followerOrder = {},
		desired = {},
		inRenderRange = false,
		active = true,
		invalidInventoryLogged = false,
	}
	playerStates[player] = state
	refreshGroundRaycastFilter(state)
	for kart in pairs(trackedKartModels) do
		refreshKartOwner(kart)
	end
	state.maid:GiveTask(player:GetAttributeChangedSignal(INVENTORY_ATTRIBUTE):Connect(function()
		updateDesiredPets(state)
	end))
	state.maid:GiveTask(player.CharacterAdded:Connect(function(character: Model)
		bindCharacter(state, character)
	end))
	state.maid:GiveTask(player.CharacterRemoving:Connect(function(character: Model)
		if state.character == character then
			if state.characterMaid then
				state.characterMaid:DoCleaning()
				state.characterMaid = nil
			end
			clearFollowers(state)
			state.character = nil
			state.root = nil
			state.humanoid = nil
			state.kart = nil
			state.kartRearExtent = nil
			refreshGroundRaycastFilter(state)
			state.inRenderRange = false
		end
	end))
	updateDesiredPets(state)
	if player.Character then
		bindCharacter(state, player.Character)
	end
end

local function updateFollowers(deltaTime: number): ()
	if not localPlayer then
		return
	end
	local localState = playerStates[localPlayer]
	local localRoot = if localState then localState.root else nil
	local now = os.clock()
	local alpha = 1 - math.exp(-PetConfig.Followers.followResponsiveness * math.min(deltaTime, 0.1))
	for _, state in pairs(playerStates) do
		local root = state.root
		local humanoid = state.humanoid
		local inRange = false
		if root and root.Parent and humanoid and humanoid.Health > 0 and localRoot and localRoot.Parent then
			local renderDistance = PetConfig.Followers.renderDistance
				+ (if state.inRenderRange then PetConfig.Followers.renderCullHysteresis else 0)
			inRange = (root.Position - localRoot.Position).Magnitude <= renderDistance
		end
		if inRange ~= state.inRenderRange then
			state.inRenderRange = inRange
			if inRange then
				reconcileFollowers(state)
			else
				clearFollowers(state)
			end
		end
		if inRange and #state.followerOrder > 0 then
			local groundY = getCachedGroundY(state, now)
			for index, follower in ipairs(state.followerOrder) do
				local targetFrame = getTargetFrame(state, follower, index, #state.followerOrder, now, groundY)
				if targetFrame and follower.model.Parent then
					follower.model:PivotTo(follower.model:GetPivot():Lerp(targetFrame, alpha))
				end
			end
		end
	end
end

function PetFollowerController.Init(): ()
	if initialized or not RunService:IsClient() then
		return
	end
	localPlayer = Players.LocalPlayer
	if not localPlayer then
		DebugModule.debugWarn("LocalPlayer unavailable; followers not started", MODULE_NAME)
		return
	end
	initialized = true
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
	playerAddedConnection = Players.PlayerAdded:Connect(bindPlayer)
	kartAddedConnection = CollectionService:GetInstanceAddedSignal(EQUIPPED_KART_MODEL_TAG):Connect(registerKartModel)
	kartRemovedConnection = CollectionService:GetInstanceRemovedSignal(EQUIPPED_KART_MODEL_TAG):Connect(function(instance: Instance)
		if instance:IsA("Model") then
			unregisterKartModel(instance)
		end
	end)
	for _, instance in ipairs(CollectionService:GetTagged(EQUIPPED_KART_MODEL_TAG)) do
		registerKartModel(instance)
	end
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		local state = playerStates[player]
		if state then
			playerStates[player] = nil
			cleanupPlayer(state)
		end
	end)
	renderConnection = RunService.RenderStepped:Connect(updateFollowers)
	DebugModule.debugInfo("Equipped pet followers started", MODULE_NAME)
end

function PetFollowerController.Shutdown(): ()
	if not initialized then
		return
	end
	initialized = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	if kartAddedConnection then
		kartAddedConnection:Disconnect()
		kartAddedConnection = nil
	end
	if kartRemovedConnection then
		kartRemovedConnection:Disconnect()
		kartRemovedConnection = nil
	end
	for kart in pairs(trackedKartModels) do
		unregisterKartModel(kart)
	end
	for player, state in pairs(playerStates) do
		playerStates[player] = nil
		cleanupPlayer(state)
	end
	if ownsFollowerRootFolder and followerRootFolder and followerRootFolder.Parent then
		followerRootFolder:Destroy()
	end
	followerRootFolder = nil
	ownsFollowerRootFolder = false
end

return table.freeze(PetFollowerController)
