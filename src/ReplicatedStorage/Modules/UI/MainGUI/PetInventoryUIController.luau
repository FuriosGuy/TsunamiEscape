--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local PetRarityConfig = require(ReplicatedStorage.Modules.Config.PetRarityConfig)
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)
local PetViewportRenderer = require(ReplicatedStorage.Modules.UI.PetViewportRenderer)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)

type PetRecord = {
	uid: string,
	petId: string,
	stars: number,
	equipped: boolean,
}

type PetDefinition = PetConfig.PetDefinition
type StrokeStyle = {
	color: Color3,
	thickness: number,
}
type ColorTarget = {
	instance: Instance,
	property: string,
	baseColor: Color3,
	targetColor: Color3?,
	tween: Tween?,
}
type TransparencyTarget = {
	instance: Instance,
	property: string,
	originalTransparency: number,
}
type CardPressState = {
	uiScale: UIScale,
	baseScale: number,
	colorTargets: { ColorTarget },
	scaleTween: Tween?,
	isPressed: boolean,
}

type PetInventoryUIControllerObject = {
	player: Player,
	viewportAnimator: PetViewportRenderer.Animator,
	petFrame: Frame,
	list: ScrollingFrame,
	template: GuiObject,
	selectedFrame: Frame,
	confirmationFrame: Frame,
	cards: { [string]: GuiObject },
	cardConnections: { [string]: RBXScriptConnection },
	cardPressStates: { [string]: CardPressState },
	strokeTweens: { [UIStroke]: Tween },
	strokeTargets: { [UIStroke]: StrokeStyle },
	originalStrokeStyles: { [UIStroke]: StrokeStyle },
	connections: { RBXScriptConnection },
	selectedVisibility: { [GuiObject]: boolean },
	selectionScale: UIScale?,
	selectionTweens: { Tween },
	selectionTransparencyTargets: { TransparencyTarget },
	confirmationScale: UIScale?,
	confirmationTweens: { Tween },
	confirmationTransparencyTargets: { TransparencyTarget },
	confirmationTextTweens: { [TextLabel]: Tween },
	confirmationTextTransparencies: { [TextLabel]: { text: number, stroke: number } },
	confirmationStrokeTweens: { [UIStroke]: Tween },
	confirmationStrokeTransparencies: { [UIStroke]: number },
	confirmationStrokeOwners: { [UIStroke]: TextLabel },
	confirmationTextTokens: { [TextLabel]: number },
	panelTransitionToken: number,
	panelTransitioning: boolean,
	selectionPanelOpening: boolean,
	lastSelectedAnimationUid: string?,
	selectedUid: string?,
	deleteMode: boolean,
	deleteIds: { [string]: boolean },
	deleteSelectedColorTween: Tween?,
	confirmAction: string?,
	confirmIds: { string },
	alive: boolean,
	Refresh: (self: PetInventoryUIControllerObject) -> (),
	Destroy: (self: PetInventoryUIControllerObject) -> (),
}

local PetInventoryUIController = {}
PetInventoryUIController.__index = PetInventoryUIController

local MODULE_NAME = "PetInventoryUIController"
local INVENTORY_ATTRIBUTE = "Pet_Inventory"
local STAR_IMAGE = "rbxassetid://123202050585503"
local EMPTY_STAR_IMAGE = "rbxassetid://80679691355494"
local SELECTED_STROKE_THICKNESS = 6
local EMPHASIZED_STROKE_THICKNESS = 5
local PRESSED_SCALE = 0.95
local PRESSED_COLOR_MULTIPLIER = 0.75
local STROKE_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local DYNAMIC_VISUAL_ATTRIBUTE = "DynamicVisualState"
local petDefinitions: { [string]: PetDefinition } = {}
local petIsPaid: { [string]: boolean } = {}
for _, luckyBlockId in ipairs({ "Tier1", "Tier2", "Tier3", "Premium", "Event" }) do
	local luckyBlock = PetConfig.LuckyBlocks[luckyBlockId :: PetConfig.LuckyBlockId]
	if luckyBlock then
		local paid = luckyBlock.rollCurrency == "Robux"
		for _, pet in ipairs(luckyBlock.pets or {}) do
			petDefinitions[pet.id] = pet
			petIsPaid[pet.id] = paid
		end
		for _, eventPool in pairs(luckyBlock.eventPools or {}) do
			for _, pet in ipairs(eventPool.pets) do
				petDefinitions[pet.id] = pet
				petIsPaid[pet.id] = paid
			end
		end
	end
end

local function findGuiObject(parent: Instance?, name: string): GuiObject?
	local child = if parent then parent:FindFirstChild(name) else nil
	return if child and child:IsA("GuiObject") then child else nil
end

local function findTextLabel(parent: Instance?, name: string): TextLabel?
	local child = if parent then parent:FindFirstChild(name, true) else nil
	return if child and child:IsA("TextLabel") then child else nil
end

local function findButton(parent: Instance?): GuiButton?
	if not parent then
		return nil
	end
	if parent:IsA("GuiButton") then
		return parent
	end
	return parent:FindFirstChildWhichIsA("GuiButton", true)
end

local function readInventory(player: Player): { PetRecord }
	local encoded = player:GetAttribute(INVENTORY_ATTRIBUTE)
	if typeof(encoded) ~= "string" or encoded == "" then
		return {}
	end

	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not ok or typeof(decoded) ~= "table" then
		DebugModule.debugWarn("Could not decode replicated pet inventory", MODULE_NAME)
		return {}
	end

	local pets: { PetRecord } = {}
	for _, value in ipairs(decoded) do
		if typeof(value) == "table"
			and typeof(value.uid) == "string"
			and typeof(value.petId) == "string"
			and petDefinitions[value.petId] ~= nil
			and typeof(value.stars) == "number"
			and typeof(value.equipped) == "boolean"
		then
			table.insert(pets, {
				uid = value.uid,
				petId = value.petId,
				stars = math.clamp(math.floor(value.stars), 1, PetConfig.StarUpgrades.maxStars),
				equipped = value.equipped,
			})
		end
	end
	return pets
end

local function setGradient(guiObject: Instance?, color: ColorSequence)
	local gradient = if guiObject then guiObject:FindFirstChildOfClass("UIGradient") else nil
	if gradient then
		gradient.Color = color
	end
end

local function getPetMultiplier(definition: PetDefinition, stars: number): number
	return PetConfig.GetPetMultiplier(definition.multiplier, definition.rarity, petIsPaid[definition.id] == true, stars)
end

local function setMultiplierTextStyle(label: TextLabel, rarity: PetConfig.Rarity, stars: number): Color3
	local style = ColorConfig.Pets.GetStarMultiplierTextStyle(rarity, stars)
	label.TextColor3 = style.TextColor
	local gradient = label:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = style.Gradient
	end
	return style.TextColor
end

local function findOuterStroke(guiObject: Instance?): UIStroke?
	local stroke = if guiObject then guiObject:FindFirstChild("UIStroke") else nil
	return if stroke and stroke:IsA("UIStroke") then stroke else nil
end

local function collectCardColorTargets(card: GuiObject): { ColorTarget }
	local targets: { ColorTarget } = {}
	local function capture(instance: Instance, property: string)
		local color = (instance :: any)[property]
		if typeof(color) == "Color3" then
			table.insert(targets, {
				instance = instance,
				property = property,
				baseColor = color,
				targetColor = nil,
				tween = nil,
			})
		end
	end

	local function inspect(instance: Instance)
		if instance:IsA("Frame") or instance:IsA("ScrollingFrame") or instance:IsA("ViewportFrame") then
			capture(instance, "BackgroundColor3")
		elseif instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			capture(instance, "BackgroundColor3")
			capture(instance, "TextColor3")
		elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			capture(instance, "BackgroundColor3")
			capture(instance, "ImageColor3")
		end
	end

	inspect(card)
	for _, descendant in ipairs(card:GetDescendants()) do
		inspect(descendant)
	end
	return targets
end

local function collectTransparencyTargets(root: Instance): { TransparencyTarget }
	local targets: { TransparencyTarget } = {}
	local function capture(instance: Instance, property: string)
		local transparency = (instance :: any)[property]
		if typeof(transparency) == "number" then
			table.insert(targets, {
				instance = instance,
				property = property,
				originalTransparency = transparency,
			})
		end
	end

	local function inspect(instance: Instance)
		if instance:IsA("GuiObject") then
			capture(instance, "BackgroundTransparency")
		end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			capture(instance, "TextTransparency")
		end
		if instance:IsA("ImageLabel") or instance:IsA("ImageButton") or instance:IsA("ViewportFrame") then
			capture(instance, "ImageTransparency")
		end
		if instance:IsA("ScrollingFrame") then
			capture(instance, "ScrollBarImageTransparency")
		end
		if instance:IsA("CanvasGroup") then
			capture(instance, "GroupTransparency")
		end
		if instance:IsA("UIStroke") then
			capture(instance, "Transparency")
		end
	end

	inspect(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		inspect(descendant)
	end
	return targets
end

local function cancelPanelTweens(tweens: { Tween })
	local activeTweens = table.clone(tweens)
	table.clear(tweens)
	for _, tween in ipairs(activeTweens) do
		tween:Cancel()
	end
end

local function playTrackedTween(tween: Tween, tweens: { Tween })
	table.insert(tweens, tween)
	tween.Completed:Connect(function()
		local index = table.find(tweens, tween)
		if index then
			table.remove(tweens, index)
		end
	end)
	tween:Play()
end

local function playPanelAnimation(
	scale: UIScale?,
	targets: { TransparencyTarget },
	tweens: { Tween },
	onCompleted: (() -> ())?
)
	if not scale then
		return
	end
	cancelPanelTweens(tweens)
	scale.Scale = 0.86
	for _, target in ipairs(targets) do
		if target.instance.Parent then
			(target.instance :: any)[target.property] = 1
			local goal = { [target.property] = target.originalTransparency }
			playTrackedTween(TweenService:Create(target.instance, TweenConfig.MenuOpen, goal), tweens)
		end
	end
	local scaleTween = TweenService:Create(scale, TweenConfig.WindowOpen, { Scale = 1 })
	if onCompleted then
		scaleTween.Completed:Connect(function(playbackState)
			if playbackState == Enum.PlaybackState.Completed then
				onCompleted()
			end
		end)
	end
	playTrackedTween(scaleTween, tweens)
end

local function restorePanelPresentation(frame: Frame, scale: UIScale?, targets: { TransparencyTarget }, tweens: { Tween })
	cancelPanelTweens(tweens)
	if scale then
		scale.Scale = 1
	end
	for _, target in ipairs(targets) do
		if target.instance:IsDescendantOf(frame) then
			(target.instance :: any)[target.property] = target.originalTransparency
		end
	end
end

local function playPanelClose(
	frame: Frame,
	scale: UIScale?,
	targets: { TransparencyTarget },
	tweens: { Tween },
	onCompleted: () -> ()
)
	if not scale then
		onCompleted()
		return
	end
	cancelPanelTweens(tweens)
	for _, target in ipairs(targets) do
		if target.instance:IsDescendantOf(frame) then
			playTrackedTween(TweenService:Create(target.instance, TweenConfig.WindowClose, {
				[target.property] = 1,
			}), tweens)
		end
	end
	local scaleTween = TweenService:Create(scale, TweenConfig.WindowClose, { Scale = 0.86 })
	table.insert(tweens, scaleTween)
	scaleTween.Completed:Connect(function(playbackState)
		local tweenIndex = table.find(tweens, scaleTween)
		if tweenIndex then
			table.remove(tweens, tweenIndex)
		end
		if playbackState == Enum.PlaybackState.Completed then
			onCompleted()
		end
	end)
	scaleTween:Play()
end

local function tweenConfirmationText(self: PetInventoryUIControllerObject, label: TextLabel?, text: string)
	if not label or label.Text == text then
		return
	end
	if not label:IsDescendantOf(self.confirmationFrame) then
		DebugModule.debugWarn("Skipped stale confirmation label reference | label=" .. label:GetFullName(), MODULE_NAME)
		return
	end

	for index = #self.confirmationTransparencyTargets, 1, -1 do
		local target = self.confirmationTransparencyTargets[index]
		if not target.instance:IsDescendantOf(self.confirmationFrame) then
			if target.instance:IsA("UIStroke") then
				local stroke = target.instance
				local strokeTween = self.confirmationStrokeTweens[stroke]
				if strokeTween then
					strokeTween:Cancel()
				end
				stroke.Transparency = target.originalTransparency
				self.confirmationStrokeTweens[stroke] = nil
				self.confirmationStrokeTransparencies[stroke] = nil
				self.confirmationStrokeOwners[stroke] = nil
			end
			DebugModule.debugWarn(
				"Removed stale confirmation transparency cache | instance=" .. target.instance.Name,
				MODULE_NAME
			)
			table.remove(self.confirmationTransparencyTargets, index)
		end
	end

	for cachedLabel in pairs(self.confirmationTextTransparencies) do
		if not cachedLabel:IsDescendantOf(self.confirmationFrame) then
			local staleTween = self.confirmationTextTweens[cachedLabel]
			if staleTween then
				staleTween:Cancel()
			end
			self.confirmationTextTweens[cachedLabel] = nil
			self.confirmationTextTransparencies[cachedLabel] = nil
			self.confirmationTextTokens[cachedLabel] = nil
			DebugModule.debugWarn("Removed stale confirmation text cache | label=" .. cachedLabel.Name, MODULE_NAME)
		end
	end
	local originalTransparency = self.confirmationTextTransparencies[label]
	if not originalTransparency then
		originalTransparency = {
			text = label.TextTransparency,
			stroke = label.TextStrokeTransparency,
		}
		self.confirmationTextTransparencies[label] = originalTransparency
	end
	local strokeTargets: { { stroke: UIStroke, transparency: number } } = {}
	for _, descendant in ipairs(label:GetDescendants()) do
		if descendant:IsA("UIStroke") and descendant:IsDescendantOf(self.confirmationFrame) then
			local originalStrokeTransparency = self.confirmationStrokeTransparencies[descendant]
			if originalStrokeTransparency == nil then
				for _, cachedTarget in ipairs(self.confirmationTransparencyTargets) do
					if cachedTarget.instance == descendant and cachedTarget.property == "Transparency" then
						originalStrokeTransparency = cachedTarget.originalTransparency
						break
					end
				end
				originalStrokeTransparency = originalStrokeTransparency or descendant.Transparency
				self.confirmationStrokeTransparencies[descendant] = originalStrokeTransparency
				table.insert(self.confirmationTransparencyTargets, {
					instance = descendant,
					property = "Transparency",
					originalTransparency = originalStrokeTransparency,
				})
			end
			table.insert(strokeTargets, {
				stroke = descendant,
				transparency = originalStrokeTransparency,
			})
		end
	end
	local textToken = (self.confirmationTextTokens[label] or 0) + 1
	self.confirmationTextTokens[label] = textToken
	local previousTween = self.confirmationTextTweens[label]
	if previousTween then
		previousTween:Cancel()
	end
	for stroke, owner in pairs(self.confirmationStrokeOwners) do
		if owner == label then
			local strokeTween = self.confirmationStrokeTweens[stroke]
			if strokeTween then
				strokeTween:Cancel()
				self.confirmationStrokeTweens[stroke] = nil
			end
			self.confirmationStrokeOwners[stroke] = nil
		end
	end
	local function beginFadeIn()
		if self.confirmationTextTokens[label] ~= textToken or not self.alive or not label:IsDescendantOf(self.confirmationFrame) then
			return
		end
		label.Text = text
		local fadeIn = TweenService:Create(label, TweenConfig.MenuOpen, {
			TextTransparency = originalTransparency.text,
			TextStrokeTransparency = originalTransparency.stroke,
		})
		self.confirmationTextTweens[label] = fadeIn
		fadeIn.Completed:Connect(function()
			if self.confirmationTextTweens[label] == fadeIn then
				self.confirmationTextTweens[label] = nil
			end
		end)
		fadeIn:Play()
		for _, target in ipairs(strokeTargets) do
			if not target.stroke:IsDescendantOf(self.confirmationFrame) then
				continue
			end
			local strokeTween = TweenService:Create(target.stroke, TweenConfig.MenuOpen, {
				Transparency = target.transparency,
			})
			self.confirmationStrokeTweens[target.stroke] = strokeTween
			self.confirmationStrokeOwners[target.stroke] = label
			strokeTween.Completed:Connect(function()
				if self.confirmationStrokeTweens[target.stroke] == strokeTween then
					self.confirmationStrokeTweens[target.stroke] = nil
					self.confirmationStrokeOwners[target.stroke] = nil
				end
			end)
			strokeTween:Play()
		end
	end
	local function onLabelFadeOutCompleted(playbackState: Enum.PlaybackState)
		if playbackState ~= Enum.PlaybackState.Completed or self.confirmationTextTokens[label] ~= textToken then
			return
		end
		beginFadeIn()
	end
	local fadeOut = TweenService:Create(label, TweenConfig.MenuClose, {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	self.confirmationTextTweens[label] = fadeOut
	fadeOut.Completed:Connect(onLabelFadeOutCompleted)
	fadeOut:Play()
	for _, target in ipairs(strokeTargets) do
		local previousStrokeTween = self.confirmationStrokeTweens[target.stroke]
		if previousStrokeTween then
			previousStrokeTween:Cancel()
		end
		local strokeTween = TweenService:Create(target.stroke, TweenConfig.MenuClose, { Transparency = 1 })
		self.confirmationStrokeTweens[target.stroke] = strokeTween
		self.confirmationStrokeOwners[target.stroke] = label
		strokeTween.Completed:Connect(function()
			if self.confirmationStrokeTweens[target.stroke] == strokeTween
				and strokeTween.PlaybackState ~= Enum.PlaybackState.Playing
			then
				self.confirmationStrokeTweens[target.stroke] = nil
				self.confirmationStrokeOwners[target.stroke] = nil
			end
		end)
		strokeTween:Play()
	end
end

local function resetConfirmationTextTransitions(self: PetInventoryUIControllerObject)
	for label, tween in pairs(table.clone(self.confirmationTextTweens)) do
		tween:Cancel()
		self.confirmationTextTweens[label] = nil
		self.confirmationTextTokens[label] = (self.confirmationTextTokens[label] or 0) + 1
		local originalTransparency = self.confirmationTextTransparencies[label]
		if originalTransparency and label:IsDescendantOf(self.confirmationFrame) then
			label.TextTransparency = originalTransparency.text
			label.TextStrokeTransparency = originalTransparency.stroke
		end
	end
	for stroke, tween in pairs(table.clone(self.confirmationStrokeTweens)) do
		tween:Cancel()
		self.confirmationStrokeTweens[stroke] = nil
		self.confirmationStrokeOwners[stroke] = nil
		local originalTransparency = self.confirmationStrokeTransparencies[stroke]
		if originalTransparency and stroke:IsDescendantOf(self.confirmationFrame) then
			stroke.Transparency = originalTransparency
		end
	end
end

local function ensureAnimationScale(frame: GuiObject, name: string): UIScale
	local scale = frame:FindFirstChild(name)
	if not scale or not scale:IsA("UIScale") then
		if scale then
			scale:Destroy()
		end
		local createdScale = Instance.new("UIScale")
		createdScale.Name = name
		createdScale.Scale = 1
		scale = createdScale
	end
	if scale.Parent == nil then
		scale.Parent = frame
	end
	return scale :: UIScale
end

local function cancelCardPressTweens(state: CardPressState)
	if state.scaleTween then
		state.scaleTween:Cancel()
		state.scaleTween = nil
	end
	for _, target in ipairs(state.colorTargets) do
		if target.tween then
			target.tween:Cancel()
			target.tween = nil
		end
	end
end

local function clearCardPressState(self: PetInventoryUIControllerObject, uid: string)
	local state = self.cardPressStates[uid]
	if state then
		cancelCardPressTweens(state)
		self.cardPressStates[uid] = nil
	end
end

local function clearCardStrokeTween(self: PetInventoryUIControllerObject, card: GuiObject)
	local stroke = findOuterStroke(findGuiObject(card, "Background"))
	if not stroke then
		return
	end
	local tween = self.strokeTweens[stroke]
	if tween then
		tween:Cancel()
		self.strokeTweens[stroke] = nil
	end
	self.strokeTargets[stroke] = nil
	self.originalStrokeStyles[stroke] = nil
end

local function tweenStrokeTo(self: PetInventoryUIControllerObject, stroke: UIStroke, targetStyle: StrokeStyle)
	stroke:SetAttribute(DYNAMIC_VISUAL_ATTRIBUTE, true)
	local previousTarget = self.strokeTargets[stroke]
	local previousTween = self.strokeTweens[stroke]
	if previousTarget
		and previousTarget.color == targetStyle.color
		and previousTarget.thickness == targetStyle.thickness
	then
		if previousTween and previousTween.PlaybackState == Enum.PlaybackState.Playing then
			return
		end
		if stroke.Color == targetStyle.color and stroke.Thickness == targetStyle.thickness then
			return
		end
	end

	if previousTween then
		previousTween:Cancel()
	end
	self.strokeTargets[stroke] = targetStyle
	local tween = TweenService:Create(stroke, STROKE_TWEEN_INFO, {
		Color = targetStyle.color,
		Thickness = targetStyle.thickness,
	})
	self.strokeTweens[stroke] = tween
	tween:Play()
end

local function setPetStars(parent: Instance?, stars: number)
	local starsFrame = findGuiObject(parent, "Stars")
	if not starsFrame then
		return
	end
	for starIndex = 1, 3 do
		local star = starsFrame:FindFirstChild("Star" .. tostring(starIndex))
		if star and star:IsA("ImageLabel") then
			star.Image = if starIndex <= stars then STAR_IMAGE else EMPTY_STAR_IMAGE
			star.Visible = true
		end
	end
end

local function cardOrder(left: GuiObject, right: GuiObject): boolean
	local leftEquipped = left:GetAttribute("PetEquipped") == true
	local rightEquipped = right:GetAttribute("PetEquipped") == true
	if leftEquipped ~= rightEquipped then
		return leftEquipped
	end
	local leftRarity = PetRarityConfig.RarityOrder[tostring(left:GetAttribute("PetRarity"))] or 0
	local rightRarity = PetRarityConfig.RarityOrder[tostring(right:GetAttribute("PetRarity"))] or 0
	if leftRarity ~= rightRarity then
		return leftRarity > rightRarity
	end
	local leftStars = tonumber(left:GetAttribute("PetStars")) or 0
	local rightStars = tonumber(right:GetAttribute("PetStars")) or 0
	if leftStars ~= rightStars then
		return leftStars > rightStars
	end
	local leftMultiplier = tonumber(left:GetAttribute("PetMultiplier")) or 0
	local rightMultiplier = tonumber(right:GetAttribute("PetMultiplier")) or 0
	if leftMultiplier ~= rightMultiplier then
		return leftMultiplier > rightMultiplier
	end
	return tostring(left:GetAttribute("PetDisplayName")) < tostring(right:GetAttribute("PetDisplayName"))
end

function PetInventoryUIController.new(screenGui: ScreenGui): PetInventoryUIControllerObject?
	local player = Players.LocalPlayer
	local petFrame = findGuiObject(screenGui, "PetFrame")
	local petList = findGuiObject(petFrame, "PetList")
	local scrollingFrame = findGuiObject(petList, "ScrollingFrame")
	local template = findGuiObject(scrollingFrame, "PetShowcaseTemplate")
	local leftFrame = findGuiObject(petFrame, "LeftFrame")
	local selectedFrame = findGuiObject(leftFrame, "SelectedFrame")
	local confirmationFrame = findGuiObject(leftFrame, "ConfirmationFrame")
	local deleteSelectedButton = findGuiObject(petFrame, "DeleteSelectedButton")
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local actionRemote = remotes and remotes:FindFirstChild("PetInventoryAction")
	if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") or not template
		or not selectedFrame or not selectedFrame:IsA("Frame")
		or not confirmationFrame or not confirmationFrame:IsA("Frame")
		or not petFrame or not petFrame:IsA("Frame")
		or not actionRemote or not actionRemote:IsA("RemoteEvent")
	then
		DebugModule.debugWarn("Pet inventory UI hierarchy or action remote missing", MODULE_NAME)
		return nil
	end

	local self = setmetatable({
		player = player,
		viewportAnimator = PetViewportRenderer.CreateAnimator(),
		petFrame = petFrame,
		list = scrollingFrame,
		template = template,
		selectedFrame = selectedFrame,
		confirmationFrame = confirmationFrame,
		cards = {},
		cardConnections = {},
		cardPressStates = {},
		strokeTweens = {},
		strokeTargets = {},
		originalStrokeStyles = {},
		connections = {},
		selectedVisibility = {},
		selectionScale = nil,
		selectionTweens = {},
		selectionTransparencyTargets = {},
		confirmationScale = nil,
		confirmationTweens = {},
		confirmationTransparencyTargets = {},
		confirmationTextTweens = {},
		confirmationTextTransparencies = {},
		confirmationStrokeTweens = {},
		confirmationStrokeTransparencies = {},
		confirmationStrokeOwners = {},
		confirmationTextTokens = {},
		panelTransitionToken = 0,
		panelTransitioning = false,
		selectionPanelOpening = false,
		lastSelectedAnimationUid = nil,
		selectedUid = nil,
		deleteMode = false,
		deleteIds = {},
		deleteSelectedColorTween = nil,
		confirmAction = nil,
		confirmIds = {},
		alive = true,
	}, PetInventoryUIController) :: PetInventoryUIControllerObject
	local deleteSelectedOriginalColor = if deleteSelectedButton
		then deleteSelectedButton.BackgroundColor3
		else nil
	if deleteSelectedButton then
		deleteSelectedButton:SetAttribute(DYNAMIC_VISUAL_ATTRIBUTE, true)
		for _, descendant in ipairs(deleteSelectedButton:GetDescendants()) do
			if descendant:IsA("UIStroke") then
				descendant:SetAttribute(DYNAMIC_VISUAL_ATTRIBUTE, true)
			end
		end
	end
	local function setDeleteMode(enabled: boolean)
		local modeChanged = self.deleteMode ~= enabled
		self.deleteMode = enabled
		table.clear(self.deleteIds)
		if deleteSelectedButton and deleteSelectedOriginalColor then
			local targetColor = if enabled
				then ColorConfig.UI.NotificationThemes.Red.textColor
				else deleteSelectedOriginalColor
			if self.deleteSelectedColorTween then
				self.deleteSelectedColorTween:Cancel()
				self.deleteSelectedColorTween = nil
			end
			if deleteSelectedButton.BackgroundColor3 ~= targetColor then
				local colorTween = TweenService:Create(deleteSelectedButton, TweenConfig.Click, {
					BackgroundColor3 = targetColor,
				})
				self.deleteSelectedColorTween = colorTween
				colorTween.Completed:Connect(function()
					if self.deleteSelectedColorTween == colorTween then
						self.deleteSelectedColorTween = nil
					end
				end)
				colorTween:Play()
			end
		end
		if modeChanged then
			DebugModule.debugInfo("Delete selection mode changed | enabled=" .. tostring(enabled), MODULE_NAME)
		end
	end
	self.selectionScale = ensureAnimationScale(selectedFrame, "PetSelectionAnimationScale")
	self.selectionTransparencyTargets = collectTransparencyTargets(selectedFrame)
	self.confirmationScale = ensureAnimationScale(confirmationFrame, "PetConfirmationAnimationScale")
	self.confirmationTransparencyTargets = collectTransparencyTargets(confirmationFrame)
	for _, labelName in ipairs({ "TitleLabel", "WarningLabel" }) do
		local label = findTextLabel(confirmationFrame, labelName)
		if label then
			self.confirmationTextTransparencies[label] = {
				text = label.TextTransparency,
				stroke = label.TextStrokeTransparency,
			}
		end
	end
	template.Visible = false
	selectedFrame.Visible = true
	confirmationFrame.Visible = false
	for _, descendant in ipairs(selectedFrame:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			self.selectedVisibility[descendant] = descendant.Visible
		end
	end

	local function sendAction(action: string, payload: any?)
		if self.alive and player:GetAttribute("Data_Loaded") == true then
			(actionRemote :: RemoteEvent):FireServer(action, payload)
		end
	end

	local function setConfirmation(action: string?, title: string?, description: string?)
		local wasConfirmationVisible = confirmationFrame.Visible
		self.confirmAction = action
		self.confirmIds = {}
		if action ~= nil then
			self.lastSelectedAnimationUid = nil
		end
		if action == "DeleteMany" then
			for uid in pairs(self.deleteIds) do
				table.insert(self.confirmIds, uid)
			end
		end
		local titleLabel = findTextLabel(confirmationFrame, "TitleLabel")
		local warningLabel = findTextLabel(confirmationFrame, "WarningLabel")
		if titleLabel and title then
			local nextTitle = string.upper(title)
			if wasConfirmationVisible then
				tweenConfirmationText(self, titleLabel, nextTitle)
			else
				titleLabel.Text = nextTitle
			end
		end
		if warningLabel and description then
			if wasConfirmationVisible then
				tweenConfirmationText(self, warningLabel, description)
			else
				warningLabel.Text = description
			end
		end
		local nextFrame = if action ~= nil then confirmationFrame else selectedFrame
		local currentFrame = if confirmationFrame.Visible
			then confirmationFrame
			elseif selectedFrame.Visible
			then selectedFrame
			else nil
		self.panelTransitionToken += 1
		local transitionToken = self.panelTransitionToken
		if self.panelTransitioning and currentFrame then
			local currentScale = if currentFrame == confirmationFrame then self.confirmationScale else self.selectionScale
			local currentTargets = if currentFrame == confirmationFrame
				then self.confirmationTransparencyTargets
				else self.selectionTransparencyTargets
			local currentTweens = if currentFrame == confirmationFrame then self.confirmationTweens else self.selectionTweens
			restorePanelPresentation(currentFrame, currentScale, currentTargets, currentTweens)
			self.panelTransitioning = false
			self.selectionPanelOpening = false
		end
		if currentFrame == nextFrame then
			return
		end

		local function showNextFrame()
			if not self.alive or self.panelTransitionToken ~= transitionToken then
				return
		end
			self.panelTransitioning = false
			if currentFrame then
				currentFrame.Visible = false
			end
			nextFrame.Visible = true
			local nextScale = if nextFrame == confirmationFrame then self.confirmationScale else self.selectionScale
			local nextTargets = if nextFrame == confirmationFrame
				then self.confirmationTransparencyTargets
				else self.selectionTransparencyTargets
			local nextTweens = if nextFrame == confirmationFrame then self.confirmationTweens else self.selectionTweens
			local onPanelOpened: (() -> ())? = nil
			if nextFrame == selectedFrame then
				self.selectionPanelOpening = true
				onPanelOpened = function()
					if self.panelTransitionToken == transitionToken then
						self.selectionPanelOpening = false
					end
				end
			end
			playPanelAnimation(nextScale, nextTargets, nextTweens, onPanelOpened)
		end

		if currentFrame then
			self.panelTransitioning = true
			if currentFrame == selectedFrame then
				self.selectionPanelOpening = false
			elseif nextFrame ~= confirmationFrame then
				resetConfirmationTextTransitions(self)
			end
			local currentScale = if currentFrame == confirmationFrame then self.confirmationScale else self.selectionScale
			local currentTargets = if currentFrame == confirmationFrame
				then self.confirmationTransparencyTargets
				else self.selectionTransparencyTargets
			local currentTweens = if currentFrame == confirmationFrame then self.confirmationTweens else self.selectionTweens
			playPanelClose(currentFrame, currentScale, currentTargets, currentTweens, showNextFrame)
		else
			showNextFrame()
		end
	end

	local function updateDeleteConfirmation()
		local count = 0
		for _ in pairs(self.deleteIds) do
			count += 1
		end
		local warningLabel = findTextLabel(confirmationFrame, "WarningLabel")
		if warningLabel and self.confirmAction == "DeleteMany" then
			tweenConfirmationText(self, warningLabel, if count == 0
				then "Select pets to delete, then confirm. Equipped pets cannot be deleted."
				else string.format("Delete %d selected pet%s? Equipped pets cannot be deleted.", count, if count == 1 then "" else "s"))
		end
		self.confirmIds = {}
		for uid in pairs(self.deleteIds) do
			table.insert(self.confirmIds, uid)
		end
	end

	local function updateCardVisual(card: GuiObject)
		local uid = card:GetAttribute("PetUid")
		local selected = not self.deleteMode and uid == self.selectedUid
		local deleteMarked = typeof(uid) == "string" and self.deleteIds[uid] == true
		local equipped = card:GetAttribute("PetEquipped") == true
		local themeName = if selected then "Blue" elseif deleteMarked then "Red" elseif equipped then "Green" else nil
		local pressState = if typeof(uid) == "string" then self.cardPressStates[uid] else nil
		local isPressed = selected or deleteMarked
		if pressState then
			if pressState.isPressed ~= isPressed then
				pressState.isPressed = isPressed
				if pressState.scaleTween then
					pressState.scaleTween:Cancel()
				end
				pressState.scaleTween = TweenService:Create(pressState.uiScale, TweenConfig.Click, {
					Scale = pressState.baseScale * (if isPressed then PRESSED_SCALE else 1),
				})
				pressState.scaleTween:Play()
			end
			for _, target in ipairs(pressState.colorTargets) do
				local multiplier = if isPressed then PRESSED_COLOR_MULTIPLIER else 1
				local targetColor = Color3.new(
					target.baseColor.R * multiplier,
					target.baseColor.G * multiplier,
					target.baseColor.B * multiplier
				)
				local currentColor = (target.instance :: any)[target.property]
				local tweenIsPlaying = target.tween ~= nil
					and target.tween.PlaybackState == Enum.PlaybackState.Playing
				if target.targetColor ~= targetColor or (currentColor ~= targetColor and not tweenIsPlaying) then
					if target.tween then
						target.tween:Cancel()
					end
					target.targetColor = targetColor
					local tween = TweenService:Create(target.instance, TweenConfig.Click, {
						[target.property] = targetColor,
					})
					target.tween = tween
					tween.Completed:Connect(function()
						if target.tween == tween then
							target.tween = nil
						end
					end)
					tween:Play()
				end
			end
		end
		local background = findGuiObject(card, "Background")
		local stroke = findOuterStroke(background)
		if not stroke then
			return
		end
		local originalStyle = self.originalStrokeStyles[stroke]
		if not originalStyle then
			originalStyle = {
				color = stroke.Color,
				thickness = stroke.Thickness,
			}
			self.originalStrokeStyles[stroke] = originalStyle
		end

		local theme = if themeName then ColorConfig.UI.NotificationThemes[themeName] else nil
		local targetStyle: StrokeStyle = {
			color = if theme then theme.textColor else originalStyle.color,
			thickness = if selected
				then SELECTED_STROKE_THICKNESS
				elseif deleteMarked or equipped
				then EMPHASIZED_STROKE_THICKNESS
				else originalStyle.thickness,
		}
		local strokeGradient = stroke:FindFirstChildOfClass("UIGradient")
		if strokeGradient then
			local gradientBottomColor = if theme then theme.gradientBottomColor else originalStyle.color
			strokeGradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, ColorConfig.Colors.White.Color),
				ColorSequenceKeypoint.new(1, gradientBottomColor),
			})
		end
		tweenStrokeTo(self, stroke, targetStyle)
	end

	local function openSingleDelete(uid: string)
		setDeleteMode(false)
		setConfirmation("Delete", "DELETE PET", "Are you sure you want to delete this pet? This cannot be undone.")
		self.confirmIds = { uid }
	end

	local function connectCard(card: GuiObject, uid: string)
		if self.cardConnections[uid] then
			return
		end
		local button = findButton(card)
		if not button then
			DebugModule.debugWarn("Pet card activation button missing | uid=" .. uid, MODULE_NAME)
			return
		end
		button.Active = true
		button.Interactable = true
		self.cardConnections[uid] = button.Activated:Connect(function()
			if not self.alive then
				return
			end
			local currentCard = self.cards[uid]
			if not currentCard then
				return
			end
			if self.deleteMode then
				if currentCard:GetAttribute("PetEquipped") == true then
					local warningLabel = findTextLabel(confirmationFrame, "WarningLabel")
					if warningLabel then
						tweenConfirmationText(self, warningLabel, "Equipped pets cannot be deleted. Unequip pet first.")
					end
					return
				end
				self.deleteIds[uid] = if self.deleteIds[uid] then nil else true
				updateDeleteConfirmation()
				self:Refresh()
			else
				self.selectedUid = uid
				self:Refresh()
			end
		end)
	end

	local function populateCard(card: GuiObject, pet: PetRecord, definition: PetDefinition)
		card.Name = pet.uid
		card.LayoutOrder = 0
		card:SetAttribute("PetUid", pet.uid)
		card:SetAttribute("PetEquipped", pet.equipped)
		card:SetAttribute("PetRarity", definition.rarity)
		card:SetAttribute("PetStars", pet.stars)
		card:SetAttribute("PetDisplayName", definition.name)
		local effectiveMultiplier = getPetMultiplier(definition, pet.stars)
		card:SetAttribute("PetMultiplier", effectiveMultiplier)

		local nameLabel = findTextLabel(card, "PetName")
		local multiplierLabel = findTextLabel(card, "Multiplier")
		local background = findGuiObject(card, "Background")
		local style = ColorConfig.Pets.GetDisplayRarityStyle(definition.rarity)
		if nameLabel then
			nameLabel.Text = definition.name
		end
		if multiplierLabel then
			multiplierLabel.Text = string.format("%.2fx", effectiveMultiplier)
			local multiplierColor = setMultiplierTextStyle(multiplierLabel, definition.rarity, pet.stars)
			local pressState = self.cardPressStates[pet.uid]
			if pressState then
				for _, target in ipairs(pressState.colorTargets) do
					if target.instance == multiplierLabel and target.property == "TextColor3" then
						target.baseColor = multiplierColor
						break
					end
				end
			end
		end
		if background and style then
			setGradient(background, style.Gradient)
		end
		local viewport = findGuiObject(card, "Viewport")
		if viewport and viewport:IsA("ViewportFrame") then
			PetViewportRenderer.Render(viewport, definition.modelPath, self.viewportAnimator)
		end
		setPetStars(card, pet.stars)
		card.Visible = true
		connectCard(card, pet.uid)
	end

	local function createCard(pet: PetRecord, definition: PetDefinition): GuiObject
		local card = self.template:Clone()
		local uiScale = card:FindFirstChild("PetSelectionScale")
		if not uiScale or not uiScale:IsA("UIScale") then
			if uiScale then
				uiScale:Destroy()
			end
			local createdScale = Instance.new("UIScale")
			createdScale.Name = "PetSelectionScale"
			createdScale.Scale = 1
			uiScale = createdScale
		end
		local typedScale = uiScale :: UIScale
		if typedScale.Parent == nil then
			typedScale.Parent = card
		end
		self.cardPressStates[pet.uid] = {
			uiScale = typedScale,
			baseScale = typedScale.Scale,
			colorTargets = collectCardColorTargets(card),
			scaleTween = nil,
			isPressed = false,
		}
		populateCard(card, pet, definition)
		card.Parent = self.list
		return card
	end

	local function updateSelectedDetails(pet: PetRecord?, definition: PetDefinition?)
		if not pet or not definition then
			local viewport = findGuiObject(selectedFrame, "Viewport")
			if viewport and viewport:IsA("ViewportFrame") then
				PetViewportRenderer.Clear(viewport, self.viewportAnimator)
			end
			for descendant in pairs(self.selectedVisibility) do
				if descendant.Parent then
					descendant.Visible = false
				end
			end
			return
		end

		for descendant, wasVisible in pairs(self.selectedVisibility) do
			if descendant.Parent then
				descendant.Visible = wasVisible
			end
		end
		local selectedWasVisible = selectedFrame.Visible
		local shouldAnimateSelection = self.confirmAction == nil
			and selectedFrame.Visible
			and not self.selectionPanelOpening
			and (not selectedWasVisible or self.lastSelectedAnimationUid ~= pet.uid)
		local nameLabel = findTextLabel(selectedFrame, "PetName")
		local multiplierLabel = findTextLabel(selectedFrame, "Multiplier")
		local rarityLabel = findTextLabel(selectedFrame, "RarityType")
		local style = ColorConfig.Pets.GetDisplayRarityStyle(definition.rarity)
		local viewport = findGuiObject(selectedFrame, "Viewport")
		if viewport and viewport:IsA("ViewportFrame") then
			PetViewportRenderer.Render(viewport, definition.modelPath, self.viewportAnimator)
		end
		if nameLabel then
			nameLabel.Text = definition.name
		end
		if multiplierLabel then
			multiplierLabel.Text = string.format("%.2fx", getPetMultiplier(definition, pet.stars))
			setMultiplierTextStyle(multiplierLabel, definition.rarity, pet.stars)
		end
		if rarityLabel and style then
			rarityLabel.Text = string.upper(definition.rarity)
			rarityLabel.TextColor3 = style.BackgroundColor
			setGradient(rarityLabel, style.Gradient)
		end
		local background = findGuiObject(selectedFrame, "Background")
		if background and style then
			setGradient(background, style.Gradient)
		end
		setPetStars(selectedFrame, pet.stars)
		local equipContainer = findGuiObject(selectedFrame, "EquipButton")
		local equipButton = findButton(equipContainer)
		if equipButton and equipButton:IsA("TextButton") then
			equipButton.Text = if pet.equipped then "UNEQUIP" else "EQUIP"
		end
		if equipContainer then
			equipContainer:SetAttribute(DYNAMIC_VISUAL_ATTRIBUTE, true)
			for _, descendant in ipairs(equipContainer:GetDescendants()) do
				if descendant:IsA("UIStroke") then
					descendant:SetAttribute(DYNAMIC_VISUAL_ATTRIBUTE, true)
				end
			end
		end
		if shouldAnimateSelection then
			playPanelAnimation(self.selectionScale, self.selectionTransparencyTargets, self.selectionTweens)
		end
		self.lastSelectedAnimationUid = pet.uid
	end

	local function activateConfirmation()
		local action = self.confirmAction
		local selectedUid = self.confirmIds[1]
		if action == "Delete" and selectedUid then
			sendAction("Delete", selectedUid)
		elseif action == "DeleteMany" then
			sendAction("DeleteMany", self.confirmIds)
		elseif action == "MergeAll" then
			sendAction("MergeAll")
		end
		setDeleteMode(false)
		setConfirmation(nil, nil, nil)
		self:Refresh()
	end

	local function bindButton(parent: Instance?, callback: () -> ())
		local button = findButton(parent)
		if button then
			table.insert(self.connections, button.Activated:Connect(callback))
		else
			DebugModule.debugWarn("Pet inventory button missing | parent=" .. (if parent then parent.Name else "nil"), MODULE_NAME)
		end
	end

	bindButton(findGuiObject(selectedFrame, "EquipButton"), function()
		if self.selectedUid then
			sendAction("Equip", self.selectedUid)
		end
	end)
	bindButton(findGuiObject(petFrame, "EquipBestButton"), function()
		setDeleteMode(false)
		setConfirmation(nil, nil, nil)
		sendAction("EquipBest")
	end)
	bindButton(findGuiObject(petFrame, "UnequipAllButton"), function()
		setDeleteMode(false)
		setConfirmation(nil, nil, nil)
		sendAction("UnequipAll")
	end)
	bindButton(findGuiObject(selectedFrame, "DeleteButton"), function()
		if self.selectedUid then
			openSingleDelete(self.selectedUid)
		end
	end)
	bindButton(findGuiObject(petFrame, "DeleteSelectedButton"), function()
		if self.deleteMode then
			setDeleteMode(false)
			setConfirmation(nil, nil, nil)
			self:Refresh()
			return
		end
		setDeleteMode(true)
		setConfirmation("DeleteMany", "DELETE SELECTED", "Select pets to delete, then confirm. Equipped pets cannot be deleted.")
		updateDeleteConfirmation()
		self:Refresh()
	end)
	bindButton(findGuiObject(petFrame, "MergeButton"), function()
		setDeleteMode(false)
		setConfirmation("MergeAll", "MERGE PETS", "Merge all eligible unequipped duplicate pets? This cannot be undone.")
	end)
	bindButton(findGuiObject(confirmationFrame, "ConfirmButton"), activateConfirmation)
	bindButton(findGuiObject(confirmationFrame, "CancelButton"), function()
		setDeleteMode(false)
		setConfirmation(nil, nil, nil)
		self:Refresh()
	end)

	local testRarities = {
		AddCommonPet = "Common",
		AddRarePet = "Rare",
		AddEpicPet = "Epic",
		AddLegendaryPet = "Legendary",
		AddMythicalPet = "Mythic",
	}
	for buttonName, rarity in pairs(testRarities) do
		local testButton = findGuiObject(petFrame, buttonName)
		if testButton then
			testButton.Visible = RunService:IsStudio()
			local button = findButton(testButton)
			if button then
				table.insert(self.connections, button.Activated:Connect(function()
					sendAction("AddRandom", rarity)
				end))
			end
		end
	end

	local function refresh()
		if not self.alive then
			return
		end
		local inventory = readInventory(player)
		local present: { [string]: boolean } = {}
		local recordsByUid: { [string]: PetRecord } = {}
		for _, pet in ipairs(inventory) do
			present[pet.uid] = true
			recordsByUid[pet.uid] = pet
			local definition = petDefinitions[pet.petId]
			if definition then
				local card = self.cards[pet.uid]
				if not card then
					card = createCard(pet, definition)
					self.cards[pet.uid] = card
				else
					populateCard(card, pet, definition)
				end
			end
		end
		for uid, card in pairs(self.cards) do
			if not present[uid] then
				local connection = self.cardConnections[uid]
				if connection then
					connection:Disconnect()
					self.cardConnections[uid] = nil
				end
			clearCardPressState(self, uid)
				clearCardStrokeTween(self, card)
				card:Destroy()
				self.cards[uid] = nil
				self.deleteIds[uid] = nil
			end
		end

		local sortedCards: { GuiObject } = {}
		for _, pet in ipairs(inventory) do
			local card = self.cards[pet.uid]
			if card then
				table.insert(sortedCards, card)
			end
		end
		table.sort(sortedCards, cardOrder)
		for order, card in ipairs(sortedCards) do
			card.LayoutOrder = order
		end

		if #inventory == 0 then
			self.selectedUid = nil
			updateSelectedDetails(nil, nil)
			return
		end
		if not self.selectedUid or not recordsByUid[self.selectedUid] then
			local firstCard = sortedCards[1]
			self.selectedUid = if firstCard then firstCard:GetAttribute("PetUid") :: string else inventory[1].uid
		end
		for _, card in ipairs(sortedCards) do
			updateCardVisual(card)
		end
		local selectedPet = recordsByUid[self.selectedUid]
		local selectedDefinition = if selectedPet then petDefinitions[selectedPet.petId] else nil
		updateSelectedDetails(selectedPet, selectedDefinition)
	end
	self.Refresh = function(_controller: PetInventoryUIControllerObject)
		refresh()
	end

	table.insert(self.connections, player:GetAttributeChangedSignal(INVENTORY_ATTRIBUTE):Connect(function()
		self:Refresh()
	end))
	table.insert(self.connections, player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
		self:Refresh()
	end))
	self:Refresh()
	return self
end

function PetInventoryUIController.Destroy(self: PetInventoryUIControllerObject)
	if not self.alive then
		return
	end
	self.alive = false
	self.viewportAnimator:Destroy()
	if self.deleteSelectedColorTween then
		self.deleteSelectedColorTween:Cancel()
		self.deleteSelectedColorTween = nil
	end
	cancelPanelTweens(self.selectionTweens)
	cancelPanelTweens(self.confirmationTweens)
	for _, tween in pairs(self.confirmationTextTweens) do
		tween:Cancel()
	end
	for _, tween in pairs(self.confirmationStrokeTweens) do
		tween:Cancel()
	end
	table.clear(self.confirmationTextTweens)
	table.clear(self.confirmationTextTransparencies)
	table.clear(self.confirmationStrokeTweens)
	table.clear(self.confirmationStrokeTransparencies)
	table.clear(self.confirmationStrokeOwners)
	table.clear(self.confirmationTextTokens)
	for _, target in ipairs(self.selectionTransparencyTargets) do
		if target.instance.Parent then
			(target.instance :: any)[target.property] = target.originalTransparency
		end
	end
	for _, target in ipairs(self.confirmationTransparencyTargets) do
		if target.instance:IsDescendantOf(self.confirmationFrame) then
			(target.instance :: any)[target.property] = target.originalTransparency
		end
	end
	if self.selectionScale then
		self.selectionScale.Scale = 1
	end
	if self.confirmationScale then
		self.confirmationScale.Scale = 1
	end
	table.clear(self.selectionTransparencyTargets)
	table.clear(self.confirmationTransparencyTargets)
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	for uid, connection in pairs(self.cardConnections) do
		connection:Disconnect()
		self.cardConnections[uid] = nil
	end
	for uid, card in pairs(self.cards) do
		clearCardPressState(self, uid)
		clearCardStrokeTween(self, card)
		card:Destroy()
		self.cards[uid] = nil
	end
	for _, tween in pairs(self.strokeTweens) do
		tween:Cancel()
	end
	table.clear(self.strokeTweens)
	table.clear(self.strokeTargets)
	table.clear(self.originalStrokeStyles)
	table.clear(self.selectedVisibility)
	table.clear(self.deleteIds)
	table.clear(self.confirmIds)
	self.selectedUid = nil
end

return PetInventoryUIController
