--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)

local MODULE_NAME = "PetViewportRenderer"
local PET_MODELS_FOLDER = "BrainrotPets"
local VIEWPORT_MODEL_NAME = "PetViewportModel"
local VIEWPORT_WORLD_NAME = "PetViewportWorld"
local VIEWPORT_CAMERA_NAME = "PetViewportCamera"
local CAMERA_FIELD_OF_VIEW = 15
local CAMERA_FILL_RATIO = 0.9
local CAMERA_PADDING = 1.03
local ROTATION_PERIOD_SECONDS = 10
local BOB_PERIOD_SECONDS = 2.8
local BOB_AMPLITUDE_STUDS = 0.5
local PRELOAD_BATCH_SIZE = 4

local PetViewportRenderer = {}

type AnimationEntry = {
	model: Model,
	basePivot: CFrame,
	startedAt: number,
	originalTransparency: { [BasePart]: number },
	hiddenForPreload: boolean,
}

type PreloadStatus = "Loaded" | "Failed"

local preloadStatuses: { [string]: PreloadStatus } = {}
local preloadQueue: { string } = {}
local queuedModelPaths: { [string]: boolean } = {}
local warnedModelPaths: { [string]: boolean } = {}
local preloadWorkerActive = false

export type Animator = {
	entries: { [ViewportFrame]: AnimationEntry },
	connection: RBXScriptConnection?,
	alive: boolean,
	Register: (self: Animator, viewport: ViewportFrame) -> (),
	Unregister: (self: Animator, viewport: ViewportFrame) -> (),
	Destroy: (self: Animator) -> (),
}

local ViewportAnimator = {}
ViewportAnimator.__index = ViewportAnimator

local function removeRenderedModel(viewport: ViewportFrame): ()
	viewport.CurrentCamera = nil
	for _, child in ipairs(viewport:GetChildren()) do
		if child.Name == VIEWPORT_MODEL_NAME
			or child.Name == VIEWPORT_WORLD_NAME
			or child.Name == VIEWPORT_CAMERA_NAME
		then
			child:Destroy()
		end
	end
	viewport:SetAttribute("PetModelPath", nil)
end

local function findModelTemplate(modelPath: string): Model?
	local current: Instance? = ReplicatedStorage:FindFirstChild(PET_MODELS_FOLDER)
	if not current then
		return nil
	end

	for _, segment in ipairs(string.split(modelPath, "/")) do
		if segment == "" or segment == "." or segment == ".." then
			return nil
		end
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end

	return if current and current:IsA("Model") then current else nil
end

local function prepareModel(model: Model, preserveVisualEffects: boolean): boolean
	local basePartCount = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			basePartCount += 1
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		elseif descendant:IsA("ParticleEmitter")
			or descendant:IsA("Beam")
			or descendant:IsA("Trail")
			or descendant:IsA("Smoke")
			or descendant:IsA("Fire")
			or descendant:IsA("Sparkles")
		then
			if not preserveVisualEffects then
				descendant:Destroy()
			end
		elseif descendant:IsA("BaseScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		end
	end
	return basePartCount > 0
end

local function isViewportVisible(viewport: ViewportFrame): boolean
	local viewportPosition = viewport.AbsolutePosition
	local viewportSize = viewport.AbsoluteSize
	local viewportRight = viewportPosition.X + viewportSize.X
	local viewportBottom = viewportPosition.Y + viewportSize.Y
	local current: Instance? = viewport

	while current do
		if current:IsA("GuiObject") then
			if not current.Visible then
				return false
			end
			if current.ClipsDescendants then
				local clipPosition = current.AbsolutePosition
				local clipSize = current.AbsoluteSize
				if viewportRight <= clipPosition.X
					or viewportPosition.X >= clipPosition.X + clipSize.X
					or viewportBottom <= clipPosition.Y
					or viewportPosition.Y >= clipPosition.Y + clipSize.Y
				then
					return false
				end
			end
		elseif current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end

	return viewportSize.X > 0 and viewportSize.Y > 0
end

local function getAnimatedModel(viewport: ViewportFrame): Model?
	local worldModel = viewport:FindFirstChild(VIEWPORT_WORLD_NAME)
	local model = worldModel and worldModel:FindFirstChild(VIEWPORT_MODEL_NAME)
	return if model and model:IsA("Model") then model else nil
end

local function setModelHiddenForPreload(entry: AnimationEntry, hidden: boolean): ()
	if entry.hiddenForPreload == hidden then
		return
	end
	entry.hiddenForPreload = hidden

	for _, descendant in ipairs(entry.model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if hidden then
				entry.originalTransparency[descendant] = descendant.LocalTransparencyModifier
				descendant.LocalTransparencyModifier = 1
			else
				local originalTransparency = entry.originalTransparency[descendant]
				if originalTransparency ~= nil then
					descendant.LocalTransparencyModifier = originalTransparency
				end
			end
		end
	end
	if not hidden then
		table.clear(entry.originalTransparency)
	end
end

local function preloadBatch(modelPaths: { string }): ()
	local templates: { Model } = {}
	local validPaths: { string } = {}
	for _, modelPath in ipairs(modelPaths) do
		local template = findModelTemplate(modelPath)
		if template then
			table.insert(templates, template)
			table.insert(validPaths, modelPath)
		else
			preloadStatuses[modelPath] = "Failed"
			DebugModule.debugWarn(
				string.format("Pet model missing during texture preload | path=%s", modelPath),
				MODULE_NAME
			)
		end
	end
	if #templates == 0 then
		return
	end

	local failedAssetIds: { string } = {}
	local succeeded, errorMessage = pcall(function()
		ContentProvider:PreloadAsync(templates, function(assetId: string, status: Enum.AssetFetchStatus)
			if status ~= Enum.AssetFetchStatus.Success and #failedAssetIds < 4 then
				table.insert(failedAssetIds, assetId)
			end
		end)
	end)
	local status: PreloadStatus = if succeeded and #failedAssetIds == 0 then "Loaded" else "Failed"
	for _, modelPath in ipairs(validPaths) do
		preloadStatuses[modelPath] = status
	end
	if status == "Failed" then
		local failureDetails = if not succeeded then tostring(errorMessage) else table.concat(failedAssetIds, ",")
		DebugModule.debugWarn(
			string.format(
				"Pet texture preload failed | models=%s | assets=%s",
				table.concat(validPaths, ","),
				failureDetails
			),
			MODULE_NAME
		)
	end
end

local function processPreloadQueue(): ()
	while #preloadQueue > 0 do
		local batch: { string } = {}
		while #preloadQueue > 0 and #batch < PRELOAD_BATCH_SIZE do
			local modelPath = table.remove(preloadQueue, 1)
			if modelPath then
				table.insert(batch, modelPath)
			end
		end
		preloadBatch(batch)
		for _, modelPath in ipairs(batch) do
			queuedModelPaths[modelPath] = nil
		end
	end
	preloadWorkerActive = false
end

local function queueModelPreload(modelPath: string): ()
	if preloadStatuses[modelPath] or queuedModelPaths[modelPath] then
		return
	end
	queuedModelPaths[modelPath] = true
	table.insert(preloadQueue, modelPath)
	if not preloadWorkerActive then
		preloadWorkerActive = true
		task.defer(processPreloadQueue)
	end
end

local function updateAnimator(self: Animator): ()
	local now = os.clock()
	for viewport, entry in pairs(self.entries) do
		if not viewport:IsDescendantOf(game) or not entry.model:IsDescendantOf(viewport) then
			if entry.model:IsDescendantOf(viewport) then
				setModelHiddenForPreload(entry, false)
				entry.model:PivotTo(entry.basePivot)
			end
			self.entries[viewport] = nil
		elseif isViewportVisible(viewport) then
			local modelPath = viewport:GetAttribute("PetModelPath")
			if typeof(modelPath) == "string" then
				queueModelPreload(modelPath)
				setModelHiddenForPreload(entry, preloadStatuses[modelPath] == nil)
			end
			local elapsed = now - entry.startedAt
			local rotation = (elapsed % ROTATION_PERIOD_SECONDS) / ROTATION_PERIOD_SECONDS * math.pi * 2
			local bob = math.sin(elapsed / BOB_PERIOD_SECONDS * math.pi * 2) * BOB_AMPLITUDE_STUDS
			entry.model:PivotTo(
				CFrame.new(0, bob, 0)
					* CFrame.Angles(0, rotation, 0)
					* entry.basePivot
			)
		end
	end

	if next(self.entries) == nil and self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
end

function ViewportAnimator.Register(self: Animator, viewport: ViewportFrame): ()
	if not self.alive then
		return
	end
	local model = getAnimatedModel(viewport)
	if not model then
		return
	end
	local existing = self.entries[viewport]
	if not existing or existing.model ~= model then
		self.entries[viewport] = {
			model = model,
			basePivot = model:GetPivot(),
			startedAt = os.clock(),
			originalTransparency = {},
			hiddenForPreload = false,
		}
	end
	if not self.connection then
		self.connection = RunService.RenderStepped:Connect(function()
			updateAnimator(self)
		end)
	end
end

function ViewportAnimator.Unregister(self: Animator, viewport: ViewportFrame): ()
	local entry = self.entries[viewport]
	if not entry then
		return
	end
	if entry.model:IsDescendantOf(viewport) then
		setModelHiddenForPreload(entry, false)
		entry.model:PivotTo(entry.basePivot)
	end
	self.entries[viewport] = nil
	if next(self.entries) == nil and self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
end

function ViewportAnimator.Destroy(self: Animator): ()
	if not self.alive then
		return
	end
	self.alive = false
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	for _, entry in pairs(self.entries) do
		if entry.model.Parent then
			setModelHiddenForPreload(entry, false)
			entry.model:PivotTo(entry.basePivot)
		end
	end
	table.clear(self.entries)
end

function PetViewportRenderer.CreateAnimator(): Animator
	return setmetatable({
		entries = {},
		connection = nil,
		alive = true,
	}, ViewportAnimator) :: Animator
end

local function getFramingDistance(
	viewport: ViewportFrame,
	boundingBoxCFrame: CFrame,
	boundingBoxSize: Vector3,
	camera: Camera
): number
	local aspectRatio = if viewport.AbsoluteSize.Y > 0
		then viewport.AbsoluteSize.X / viewport.AbsoluteSize.Y
		else 1
	local tangentVertical = math.tan(math.rad(camera.FieldOfView * 0.5))
	local tangentHorizontal = tangentVertical * aspectRatio
	local cameraDirection = Vector3.new(0.2, 0.08, -1).Unit
	local cameraOrientation = CFrame.lookAt(cameraDirection, Vector3.zero)
	local distance = 0

	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local corner = boundingBoxCFrame:PointToWorldSpace(Vector3.new(
					boundingBoxSize.X * x * 0.5,
					boundingBoxSize.Y * y * 0.5,
					boundingBoxSize.Z * z * 0.5
				))
				local depth = corner:Dot(cameraDirection)
				local horizontal = math.abs(corner:Dot(cameraOrientation.RightVector))
				local vertical = math.abs(corner:Dot(cameraOrientation.UpVector))
				distance = math.max(
					distance,
					depth + horizontal / (tangentHorizontal * CAMERA_FILL_RATIO),
					depth + vertical / (tangentVertical * CAMERA_FILL_RATIO)
				)
			end
		end
	end

	return distance * CAMERA_PADDING
end

function PetViewportRenderer.Clear(viewport: ViewportFrame, animator: Animator?): ()
	if animator then
		animator:Unregister(viewport)
	end
	removeRenderedModel(viewport)
end

function PetViewportRenderer.CloneModel(modelPath: string, preserveVisualEffects: boolean?): Model?
	queueModelPreload(modelPath)
	local template = findModelTemplate(modelPath)
	if not template then
		DebugModule.debugWarn(
			string.format("Brainrot model missing | path=%s", modelPath),
			MODULE_NAME
		)
		return nil
	end

	local model = template:Clone()
	model.Name = VIEWPORT_MODEL_NAME
	if not prepareModel(model, preserveVisualEffects == true) then
		model:Destroy()
		DebugModule.debugWarn(
			string.format("Brainrot model has no BaseParts | path=%s", modelPath),
			MODULE_NAME
		)
		return nil
	end

	local boundingBoxCFrame, boundingBoxSize = model:GetBoundingBox()
	if boundingBoxSize.Magnitude <= 0 then
		model:Destroy()
		DebugModule.debugWarn(
			string.format("Brainrot model has invalid bounds | path=%s", modelPath),
			MODULE_NAME
		)
		return nil
	end
	model:PivotTo(CFrame.new(-boundingBoxCFrame.Position) * model:GetPivot())
	return model
end

function PetViewportRenderer.Render(viewport: ViewportFrame, modelPath: string, animator: Animator?): boolean
	if viewport:GetAttribute("PetModelPath") == modelPath
		and viewport:FindFirstChild(VIEWPORT_WORLD_NAME)
		and viewport:FindFirstChild(VIEWPORT_MODEL_NAME, true)
		and viewport.CurrentCamera
	then
		if animator then
			animator:Register(viewport)
		end
		return true
	end

	if animator then
		animator:Unregister(viewport)
	end
	removeRenderedModel(viewport)
	local model = PetViewportRenderer.CloneModel(modelPath)
	if not model then
		return false
	end

	local boundingBoxCFrame, boundingBoxSize = model:GetBoundingBox()

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = VIEWPORT_WORLD_NAME
	local camera = Instance.new("Camera")
	camera.Name = VIEWPORT_CAMERA_NAME
	camera.FieldOfView = CAMERA_FIELD_OF_VIEW

	local cameraDirection = Vector3.new(0.2, 0.08, -1).Unit
	local distance = getFramingDistance(viewport, boundingBoxCFrame, boundingBoxSize, camera)
	local cameraPosition = cameraDirection * distance
	camera.CFrame = CFrame.lookAt(cameraPosition, Vector3.zero)

	viewport.Ambient = Color3.fromRGB(190, 190, 190)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -1).Unit

	worldModel.Parent = viewport
	model.Parent = worldModel
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport:SetAttribute("PetModelPath", modelPath)
	if animator then
		animator:Register(viewport)
	end
	return true
end

return table.freeze(PetViewportRenderer)
