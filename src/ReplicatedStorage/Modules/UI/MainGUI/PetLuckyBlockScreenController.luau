--!strict

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local NumberFormatting = require(ReplicatedStorage.Modules.Shared.NumberFormatting)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local ProductService = require(ReplicatedStorage.Modules.Shared.ProductService_Client)
local PetLuckyBlockUIController = require(ReplicatedStorage.Modules.UI.MainGUI.PetLuckyBlockUIController)
local PetLuckyBlockPurchaseController = require(ReplicatedStorage.Modules.UI.MainGUI.PetLuckyBlockPurchaseController)
local PetLuckyBlockCutsceneController = require(ReplicatedStorage.Modules.UI.MainGUI.PetLuckyBlockCutsceneController)
local ModalGuiVisibilityController = require(ReplicatedStorage.Modules.UI.MainGUI.ModalGuiVisibilityController)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

type LuckyBlockGroup = "Tier1" | "Tier2" | "Tier3" | "Premium" | PetConfig.EventId
type PurchaseKind = "Wins" | "Robux"
type RollSource = "Modal" | "Shop"
type HumanoidStateSnapshot = {
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	jumpingEnabled: boolean,
}
type PriceRequestState = {
	threads: { thread },
}
type Controller = {
	player: Player,
	mainGui: ScreenGui,
	openFrame: GuiObject,
	mainFrame: GuiObject,
	exitButton: GuiButton?,
	panelTransitionId: number,
	panelTransitionConnection: RBXScriptConnection?,
	maid: any,
	characterMaid: any,
	petUIController: any,
	purchaseController: any,
	cutsceneController: any,
	cutsceneGeneration: number,
	modalVisibilityController: any,
	openRemote: RemoteEvent?,
	alive: boolean,
	isOpen: boolean,
	activeGroup: LuckyBlockGroup?,
	activeRollSource: RollSource?,
	previousMainFrameInteractable: boolean?,
	lockedHumanoids: { [Humanoid]: HumanoidStateSnapshot },
	blurEffect: BlurEffect?,
	blurTween: Tween?,
	priceRequestStates: { [Frame]: PriceRequestState },
	_stopBlurTween: (self: Controller) -> (),
	_playBlurTween: (self: Controller, targetSize: number, destroyOnComplete: boolean) -> (),
	_beginBlur: (self: Controller) -> (),
	_lockHumanoid: (self: Controller, humanoid: Humanoid) -> (),
	_lockMovement: (self: Controller) -> (),
	_restoreMovement: (self: Controller) -> (),
	_cancelPriceRequests: (self: Controller, targetFrame: GuiObject?) -> (),
	_animatePanelOpen: (self: Controller) -> (),
	_animatePanelClose: (self: Controller, onComplete: () -> ()) -> (),
	_updatePrices: (self: Controller, group: LuckyBlockGroup, targetFrame: GuiObject?) -> (),
	_bindExitButton: (self: Controller) -> (),
	_canOpen: (self: Controller) -> boolean,
	Init: (self: Controller) -> (),
	Open: (self: Controller, group: LuckyBlockGroup) -> (),
	Close: (self: Controller) -> (),
	RequestRoll: (
		self: Controller,
		group: LuckyBlockGroup,
		rollCount: number,
		purchaseKind: PurchaseKind,
		source: RollSource
	) -> boolean,
	UpdatePrices: (self: Controller, group: LuckyBlockGroup, targetFrame: GuiObject?) -> (),
	CancelPriceUpdates: (self: Controller, targetFrame: GuiObject?) -> (),
	Destroy: (self: Controller) -> (),
}

local PetLuckyBlockScreenController = {}
PetLuckyBlockScreenController.__index = PetLuckyBlockScreenController

local MODULE_NAME = "PetLuckyBlockScreenController"
local MOVEMENT_ACTION = "PetLuckyBlockModalMovementLock"
local CLOSE_ACTION = "PetLuckyBlockModalClose"
local MODAL_OWNER = "LuckyBlock"
local BLUR_SIZE = 18
local POLICY_DISABLED_COLOR_MULTIPLIER = 0.75
local ROLL_COUNTS = { 1, 3, 5 }
local GROUP_NAMES: { [string]: string } = {
	Tier1 = "Tier 1 Lucky Block",
	Tier2 = "Tier 2 Lucky Block",
	Tier3 = "Tier 3 Lucky Block",
	Premium = "Premium Lucky Block",
	BloodMoon = "Blood Moon Lucky Block",
	NeonRush = "Neon Rush Lucky Block",
	FrostbiteRally = "Frostbite Rally Lucky Block",
}

local function isLuckyBlockGroup(value: unknown): boolean
	return typeof(value) == "string" and GROUP_NAMES[value] ~= nil
end

local function isWinsGroup(group: LuckyBlockGroup): boolean
	return group == "Tier1" or group == "Tier2" or group == "Tier3"
end

local function getProductKey(group: LuckyBlockGroup, rollCount: number): string
	local prefix = if group == "Premium" then "PetPremium" else "Pet" .. group
	return prefix .. "LuckyBlockRoll" .. tostring(rollCount)
end

local function getRollPricePrefix(rollCount: number): string
	return if rollCount == 1 then "OPEN" else "OPEN " .. tostring(rollCount) .. "X"
end

local function findGuiButton(root: Instance): GuiButton?
	if root:IsA("GuiButton") then
		return root
	end
	local button = root:FindFirstChildWhichIsA("GuiButton", true)
	return if button and button:IsA("GuiButton") then button else nil
end

local function findTextLabel(root: Instance, names: { string }): TextLabel?
	for _, name in ipairs(names) do
		local instance = root:FindFirstChild(name, true)
		if instance and instance:IsA("TextLabel") then
			return instance
		end
	end
	return nil
end

local function showPolicyRestrictionNotification(): ()
	local theme = VisualFunctions.NotificationThemes.Red or VisualFunctions.NotificationThemes.Default
	VisualFunctions.ShowNotification(
		"LUCKY BLOCKS ARE UNAVAILABLE FOR YOUR ACCOUNT!",
		theme.textColor,
		theme.gradientBottomColor
	)
end

function PetLuckyBlockScreenController.new(mainGui: ScreenGui): Controller?
	local openFrameInstance = mainGui:WaitForChild("OpenLuckyBlockFrame", 10)
	if not openFrameInstance or not openFrameInstance:IsA("GuiObject") then
		DebugModule.debugWarn("MainGUI.OpenLuckyBlockFrame is missing", MODULE_NAME)
		return nil
	end
	local mainFrameInstance = openFrameInstance:WaitForChild("MainFrame", 10)
	if not mainFrameInstance or not mainFrameInstance:IsA("GuiObject") then
		DebugModule.debugWarn("MainGUI.OpenLuckyBlockFrame.MainFrame is missing", MODULE_NAME)
		return nil
	end
	local openFrame = openFrameInstance
	local mainFrame = mainFrameInstance
	local self = setmetatable({
		player = Players.LocalPlayer,
		mainGui = mainGui,
		openFrame = openFrame,
		mainFrame = mainFrame,
		exitButton = nil,
		panelTransitionId = 0,
		panelTransitionConnection = nil,
		maid = Maid.new(),
		characterMaid = Maid.new(),
		petUIController = nil,
		purchaseController = nil,
		cutsceneController = PetLuckyBlockCutsceneController.new(mainGui),
		cutsceneGeneration = 0,
		modalVisibilityController = ModalGuiVisibilityController.new(mainGui),
		openRemote = nil,
		alive = true,
		isOpen = false,
		activeGroup = nil,
		activeRollSource = nil,
		previousMainFrameInteractable = nil,
		lockedHumanoids = {},
		blurEffect = nil,
		blurTween = nil,
		priceRequestStates = {},
	}, PetLuckyBlockScreenController) :: Controller

	self.purchaseController = PetLuckyBlockPurchaseController.new(
		function(group: LuckyBlockGroup, petIds: { string }, fasterOpen: boolean)
			local cutsceneController = self.cutsceneController
			if not self.alive or not cutsceneController then
				return
			end
			local rollSource = self.activeRollSource
			self.activeRollSource = nil
			local restoreModal = rollSource == "Modal" and self.isOpen
			if restoreModal then
				self.activeGroup = group
			end
			self.cutsceneGeneration += 1
			local generation = self.cutsceneGeneration
			cutsceneController:Stop()
			if restoreModal then
				self:_playBlurTween(0, false)
			end
			local started = cutsceneController:Play(group, petIds, fasterOpen, function()
				if generation ~= self.cutsceneGeneration or not self.alive or not restoreModal or not self.isOpen then
					return
				end
				self.openFrame.Visible = true
				self.mainFrame.Visible = true
				self:_beginBlur()
			end)
			if not started and restoreModal then
				self.openFrame.Visible = true
				self.mainFrame.Visible = true
				self:_beginBlur()
			end
		end
	)
	self.petUIController = PetLuckyBlockUIController.new(
		mainFrame,
		"Tier1",
		function(rollCount: number, purchaseKind: PurchaseKind)
			local activeGroup = self.activeGroup
			local purchaseController = self.purchaseController
			if not self.isOpen or not activeGroup or not purchaseController then
				return
			end
			self:RequestRoll(activeGroup, rollCount, purchaseKind, "Modal")
		end
	)
	return self
end

function PetLuckyBlockScreenController._stopBlurTween(self: Controller): ()
	if self.blurTween then
		self.blurTween:Cancel()
		self.blurTween = nil
	end
end

function PetLuckyBlockScreenController._playBlurTween(
	self: Controller,
	targetSize: number,
	destroyOnComplete: boolean
): ()
	self:_stopBlurTween()
	local blur = self.blurEffect
	if not blur then
		return
	end
	local tween = TweenService:Create(blur, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = targetSize,
	})
	self.blurTween = tween
	if destroyOnComplete then
		local completedConnection: RBXScriptConnection? = nil
		completedConnection = tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			if completedConnection then
				completedConnection:Disconnect()
				completedConnection = nil
			end
			if playbackState == Enum.PlaybackState.Completed and not self.isOpen and self.blurEffect == blur then
				self.blurEffect = nil
				blur:Destroy()
			end
		end)
	end
	tween:Play()
end

function PetLuckyBlockScreenController._beginBlur(self: Controller): ()
	local blur = self.blurEffect
	if not blur or not blur.Parent then
		blur = Instance.new("BlurEffect")
		blur.Name = "LuckyBlockModalBlur"
		blur.Size = 0
		blur.Enabled = true
		blur.Parent = Lighting
		self.blurEffect = blur
	end
	blur.Enabled = true
	self:_playBlurTween(BLUR_SIZE, false)
end

function PetLuckyBlockScreenController._lockHumanoid(self: Controller, humanoid: Humanoid): ()
	if self.lockedHumanoids[humanoid] then
		return
	end
	self.lockedHumanoids[humanoid] = {
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
		jumpingEnabled = humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid:Move(Vector3.zero, true)
end

function PetLuckyBlockScreenController._lockMovement(self: Controller): ()
	ContextActionService:BindActionAtPriority(
		MOVEMENT_ACTION,
		function(): Enum.ContextActionResult
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight,
		Enum.PlayerActions.CharacterJump
	)
	local character = self.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		self:_lockHumanoid(humanoid)
	end
end

function PetLuckyBlockScreenController._restoreMovement(self: Controller): ()
	ContextActionService:UnbindAction(MOVEMENT_ACTION)
	for humanoid, state in pairs(self.lockedHumanoids) do
		if humanoid.Parent then
			humanoid.WalkSpeed = state.walkSpeed
			humanoid.JumpPower = state.jumpPower
			humanoid.JumpHeight = state.jumpHeight
			humanoid.AutoRotate = state.autoRotate
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, state.jumpingEnabled)
		end
		self.lockedHumanoids[humanoid] = nil
	end
end

local function bindCharacterDeath(self: Controller, character: Model): ()
	self.characterMaid:DoCleaning()
	local humanoidBound = false
	local function bindHumanoid(humanoid: Humanoid): ()
		if humanoidBound then
			return
		end
		humanoidBound = true
		local camera = Workspace.CurrentCamera
		local cameraSubject = if camera then camera.CameraSubject else nil
		if
			camera
			and humanoid.Health > 0
			and cameraSubject
			and cameraSubject:IsA("Humanoid")
			and cameraSubject.Health <= 0
		then
			camera.CameraSubject = humanoid
		end
		self.characterMaid:GiveTask(humanoid.Died:Connect(function()
			if self.isOpen then
				self:Close()
			end
		end))
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:IsA("Humanoid") then
		bindHumanoid(humanoid)
	end
	self.characterMaid:GiveTask(character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Humanoid") then
			bindHumanoid(child)
		end
	end))
end

function PetLuckyBlockScreenController._cancelPriceRequests(self: Controller, targetFrame: GuiObject?): ()
	for frame, state in pairs(table.clone(self.priceRequestStates)) do
		if targetFrame == nil or frame == targetFrame then
			for _, thread in ipairs(state.threads) do
				if coroutine.status(thread) ~= "dead" then
					pcall(task.cancel, thread)
				end
			end
			self.priceRequestStates[frame] = nil
		end
	end
end

function PetLuckyBlockScreenController._animatePanelOpen(self: Controller): ()
	self.panelTransitionId += 1
	if self.panelTransitionConnection then
		self.panelTransitionConnection:Disconnect()
		self.panelTransitionConnection = nil
	end
	SoundService.PlayGuiSound("Click")
	VisualFunctions.OpenWindow(self.mainFrame)
end

function PetLuckyBlockScreenController._animatePanelClose(self: Controller, onComplete: () -> ()): ()
	self.panelTransitionId += 1
	local transitionId = self.panelTransitionId
	if self.panelTransitionConnection then
		self.panelTransitionConnection:Disconnect()
		self.panelTransitionConnection = nil
	end
	SoundService.PlayGuiSound("Close")
	local closeCompleted = VisualFunctions.CloseWindow(self.mainFrame)
	self.panelTransitionConnection = closeCompleted:Connect(function(playbackState: Enum.PlaybackState)
		if self.panelTransitionConnection then
			self.panelTransitionConnection:Disconnect()
			self.panelTransitionConnection = nil
		end
		if playbackState == Enum.PlaybackState.Completed and transitionId == self.panelTransitionId then
			onComplete()
		end
	end)
end

function PetLuckyBlockScreenController._updatePrices(self: Controller, group: LuckyBlockGroup, targetFrame: GuiObject?): ()
	local priceFrame = targetFrame or self.mainFrame
	if not priceFrame.Parent then
		return
	end
	self:_cancelPriceRequests(priceFrame)
	local requestState: PriceRequestState = {
		threads = {},
	}
	self.priceRequestStates[priceFrame] = requestState
	local policyReady = self.player:GetAttribute("Pet_RandomItemPolicyLoaded") == true
	local paidRandomItemsAllowed = policyReady and self.player:GetAttribute("Pet_PaidRandomItemsRestricted") ~= true
	local policyControlsThisFrame = priceFrame == self.mainFrame
	local showWins = isWinsGroup(group)
	for _, rollCount in ipairs(ROLL_COUNTS) do
		local winsFrame = priceFrame:FindFirstChild("BuyButton_" .. tostring(rollCount) .. "x", true)
		local robuxFrame = priceFrame:FindFirstChild("RobuxBuyButton_" .. tostring(rollCount) .. "x", true)
		if winsFrame and winsFrame:IsA("GuiObject") then
			winsFrame.Visible = showWins
			if policyControlsThisFrame and winsFrame:IsA("GuiObject") then
				VisualFunctions.SetFrameDisabledState(
					winsFrame,
					not paidRandomItemsAllowed,
					POLICY_DISABLED_COLOR_MULTIPLIER
				)
			end
			if showWins then
				local costPerRoll = if group == "Tier1"
						or group == "Tier2"
						or group == "Tier3"
					then PetConfig.LuckyBlocks[group].winCostPerRoll
					else nil
				local priceLabel = findTextLabel(winsFrame, { "PriceLabel", "AmountLabel", "CostLabel" })
				local button = findGuiButton(winsFrame)
				if typeof(costPerRoll) == "number" and costPerRoll > 0 then
					local amount = costPerRoll * rollCount
					local priceText = getRollPricePrefix(rollCount)
						.. " FOR "
						.. NumberFormatting.FormatNumber(amount)
						.. " WINS"
					if priceLabel then
						priceLabel.Text = priceText
					elseif button and button:IsA("TextButton") then
						button.Text = priceText
					end
				elseif button and button:IsA("TextButton") then
					button.Text = "PRICE UNAVAILABLE"
					DebugModule.debugWarn("Missing Wins cost | group=" .. group, MODULE_NAME)
				end
			end
		end
		if robuxFrame and robuxFrame:IsA("GuiObject") then
			robuxFrame.Visible = true
			if policyControlsThisFrame and robuxFrame:IsA("GuiObject") then
				VisualFunctions.SetFrameDisabledState(
					robuxFrame,
					not paidRandomItemsAllowed,
					POLICY_DISABLED_COLOR_MULTIPLIER
				)
			end
			local productId = ProductService.DevProducts[getProductKey(group, rollCount)]
			local priceLabel = findTextLabel(robuxFrame, { "PriceLabel" })
			local button = findGuiButton(robuxFrame)
			if priceLabel then
				priceLabel.Text = getRollPricePrefix(rollCount) .. " FOR ..."
				if typeof(productId) ~= "number" or productId <= 0 then
					priceLabel.Text = getRollPricePrefix(rollCount) .. " FOR UNAVAILABLE"
					DebugModule.debugWarn(
						"Missing Robux product ID | group=" .. group .. " | rolls=" .. tostring(rollCount),
						MODULE_NAME
					)
				else
					local thread = task.spawn(function()
						local success, productInfo = pcall(function()
							return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
						end)
						if
							not self.alive
							or not priceLabel.Parent
							or not priceLabel:IsDescendantOf(priceFrame)
							or self.priceRequestStates[priceFrame] ~= requestState
						then
							return
						end
						local price = if success and typeof(productInfo) == "table"
							then productInfo.PriceInRobux
							else nil
						if typeof(price) == "number" and price >= 0 then
							priceLabel.Text = getRollPricePrefix(rollCount)
								.. " FOR "
								.. utf8.char(0xE002)
								.. " "
								.. NumberFormatting.FormatNumber(price)
						else
							priceLabel.Text = getRollPricePrefix(rollCount) .. " FOR UNAVAILABLE"
							DebugModule.debugWarn(
								"Robux price lookup failed | group="
									.. group
									.. " | rolls="
									.. tostring(rollCount)
									.. " | productId="
									.. tostring(productId),
								MODULE_NAME
							)
						end
					end)
					table.insert(requestState.threads, thread)
				end
			elseif button and button:IsA("TextButton") then
				button.Text = getRollPricePrefix(rollCount) .. " FOR UNAVAILABLE"
			end
		end
	end
end

function PetLuckyBlockScreenController.UpdatePrices(self: Controller, group: LuckyBlockGroup, targetFrame: GuiObject?): ()
	if self.alive and isLuckyBlockGroup(group) then
		self:_updatePrices(group, targetFrame)
	end
end

function PetLuckyBlockScreenController.CancelPriceUpdates(self: Controller, targetFrame: GuiObject?): ()
	if self.alive then
		self:_cancelPriceRequests(targetFrame)
	end
end

function PetLuckyBlockScreenController.RequestRoll(
	self: Controller,
	group: LuckyBlockGroup,
	rollCount: number,
	purchaseKind: PurchaseKind,
	source: RollSource
): boolean
	local purchaseController = self.purchaseController
	if not self.alive or not purchaseController or not isLuckyBlockGroup(group) then
		return false
	end
	local requestSource = if source == "Shop" then "Shop" else "World"
	local accepted = purchaseController:RequestRoll(group, rollCount, purchaseKind, requestSource)
	if accepted then
		self.activeRollSource = source
	end
	return accepted
end

function PetLuckyBlockScreenController._bindExitButton(self: Controller): ()
	local exitFrame = self.mainFrame:FindFirstChild("ExitButton", true)
	local exitButton = if exitFrame then findGuiButton(exitFrame) else nil
	if not exitFrame or not exitFrame:IsA("GuiObject") or not exitButton or self.exitButton == exitButton then
		return
	end

	self.exitButton = exitButton
	VisualFunctions.SetupFrameHover(exitFrame, 1.05, 12, 1.15)
	VisualFunctions.SetupFrameClick(exitFrame, 0.94, -8, 0.8)
	self.maid:GiveTask(exitButton.Activated:Connect(function()
		if not self.alive then
			return
		end
		VisualFunctions.PlayFrameClick(exitFrame)
		self:Close()
	end))
end

function PetLuckyBlockScreenController._canOpen(self: Controller): boolean
	if not self.alive or self.player:GetAttribute("SpinWheelModalOpen") == true then
		return false
	end
	local modalOwner = self.player:GetAttribute("ModalLockOwner")
	if modalOwner ~= nil and modalOwner ~= MODAL_OWNER then
		return false
	end
	local trollFrame = self.mainGui:FindFirstChild("TrollFrame", true)
	if trollFrame and trollFrame:IsA("GuiObject") and trollFrame.Visible then
		return false
	end
	return self.mainGui.Enabled and self.mainGui:GetAttribute("StartupLoadingComplete") == true
end

function PetLuckyBlockScreenController.Open(self: Controller, group: LuckyBlockGroup): ()
	if not self.alive or not isLuckyBlockGroup(group) then
		return
	end
	if self.isOpen then
		self.activeGroup = group
		local petUIController = self.petUIController :: any
		petUIController:SetPreviewGroup(group)
		self:_updatePrices(group)
		return
	end
	if not self:_canOpen() then
		return
	end

	if self.previousMainFrameInteractable == nil then
		self.previousMainFrameInteractable = self.mainFrame.Interactable
	end
	self.modalVisibilityController:Capture(self.openFrame)
	self.activeGroup = group
	self.isOpen = true
	self.player:SetAttribute("ModalLockOwner", MODAL_OWNER)
	self.player:SetAttribute("LuckyBlockModalOpen", true)
	self:_lockMovement()
	local petUIController = self.petUIController :: any
	ContextActionService:BindActionAtPriority(
		CLOSE_ACTION,
		function(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				self:Close()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Escape
	)
	self.openFrame.Visible = true
	self.mainFrame.Visible = true
	petUIController:SetPreviewGroup(group)
	petUIController:SetPreviewVisible(true)
	self:_updatePrices(group)
	if
		self.player:GetAttribute("Pet_RandomItemPolicyLoaded") == true
		and self.player:GetAttribute("Pet_PaidRandomItemsRestricted") == true
	then
		showPolicyRestrictionNotification()
	end
	self:_animatePanelOpen()
	self.modalVisibilityController:SetNotificationLayer(self.openFrame, true)
	self:_beginBlur()
	petUIController:FocusForGamepad()
end

function PetLuckyBlockScreenController.Close(self: Controller): ()
	if not self.isOpen then
		return
	end
	self.isOpen = false
	self.cutsceneGeneration += 1
	local cutsceneController = self.cutsceneController
	if cutsceneController then
		cutsceneController:Stop()
	end
	self.activeGroup = nil
	self:_cancelPriceRequests(self.mainFrame)
	ContextActionService:UnbindAction(CLOSE_ACTION)
	local petUIController = self.petUIController :: any
	petUIController:RestoreGamepadFocus()
	self:_restoreMovement()

	local modalOwner = self.player:GetAttribute("ModalLockOwner")
	if modalOwner == MODAL_OWNER then
		self.player:SetAttribute("ModalLockOwner", nil)
	end
	self.player:SetAttribute("LuckyBlockModalOpen", false)
	self:_animatePanelClose(function()
		petUIController:SetPreviewVisible(false)
		if self.openFrame.Parent then
			self.openFrame.Visible = false
		end
		if self.previousMainFrameInteractable ~= nil and self.mainFrame.Parent then
			self.mainFrame.Interactable = self.previousMainFrameInteractable
		end
		self.previousMainFrameInteractable = nil
		self.modalVisibilityController:SetNotificationLayer(self.openFrame, false)
		self.modalVisibilityController:Restore()
		self:_playBlurTween(0, true)
	end)
end

function PetLuckyBlockScreenController.Init(self: Controller): ()
	if not self.alive then
		return
	end
	self.openFrame.Visible = false
	local petUIController = self.petUIController :: any
	local purchaseController = self.purchaseController :: any
	petUIController:Init()
	purchaseController:Init()

	local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
	local openRemote = remotes and remotes:WaitForChild("PetLuckyBlockOpen", 10)
	if openRemote and openRemote:IsA("RemoteEvent") then
		self.openRemote = openRemote
		self.maid:GiveTask(openRemote.OnClientEvent:Connect(function(rawGroup: unknown)
			if isLuckyBlockGroup(rawGroup) then
				self:Open(rawGroup :: LuckyBlockGroup)
			else
				DebugModule.debugWarn("Server sent unsupported Lucky Block group", MODULE_NAME)
			end
		end))
	else
		DebugModule.debugWarn("PetLuckyBlockOpen remote did not replicate; UI controls remain bound", MODULE_NAME)
	end
	local dailyRevealRemote = remotes and remotes:WaitForChild("DailyLuckyBlockReveal", 10)
	if dailyRevealRemote and dailyRevealRemote:IsA("RemoteEvent") then
		self.maid:GiveTask(dailyRevealRemote.OnClientEvent:Connect(function(payload: unknown)
			if not self.alive or typeof(payload) ~= "table" then
				return
			end
			local reveal = payload :: { [string]: unknown }
			local group = reveal.group
			local petIds = reveal.petIds
			local fasterOpen = reveal.fasterOpen
			if
				(group ~= "Premium" and group ~= "Tier3")
				or typeof(petIds) ~= "table"
				or #petIds ~= 1
				or typeof((petIds :: { unknown })[1]) ~= "string"
				or typeof(fasterOpen) ~= "boolean"
			then
				DebugModule.debugWarn("Rejected malformed daily Lucky Block reveal", MODULE_NAME)
				return
			end

			local cutsceneController = self.cutsceneController
			if not cutsceneController then
				DebugModule.debugWarn("Daily Lucky Block cutscene controller unavailable", MODULE_NAME)
				return
			end
			self.isOpen = false
			self.openFrame.Visible = false
			self.mainFrame.Visible = false
			self:_playBlurTween(0, false)
			self.cutsceneGeneration += 1
			local generation = self.cutsceneGeneration
			local started = cutsceneController:Play(
				group :: LuckyBlockGroup,
				petIds :: { string },
				fasterOpen,
				function()
					if generation ~= self.cutsceneGeneration or not self.alive then
						return
					end
				end
			)
			if not started then
				DebugModule.debugWarn("Daily Lucky Block cutscene failed to start", MODULE_NAME)
			end
		end))
	else
		DebugModule.debugWarn("DailyLuckyBlockReveal remote missing; daily Lucky Block reveal unavailable", MODULE_NAME)
	end

	self:_bindExitButton()
	local function refreshPolicyAvailability(): ()
		local group = self.activeGroup
		if not self.isOpen or not group then
			return
		end
		self:_updatePrices(group)
		if
			self.player:GetAttribute("Pet_RandomItemPolicyLoaded") == true
			and self.player:GetAttribute("Pet_PaidRandomItemsRestricted") == true
		then
			showPolicyRestrictionNotification()
		end
	end
	self.maid:GiveTask(
		self.player:GetAttributeChangedSignal("Pet_RandomItemPolicyLoaded"):Connect(refreshPolicyAvailability)
	)
	self.maid:GiveTask(
		self.player:GetAttributeChangedSignal("Pet_PaidRandomItemsRestricted"):Connect(refreshPolicyAvailability)
	)
	self.maid:GiveTask(self.mainFrame.DescendantAdded:Connect(function()
		self:_bindExitButton()
	end))

	self.maid:GiveTask(self.player.CharacterAdded:Connect(function(character: Model)
		bindCharacterDeath(self, character)
	end))
	self.maid:GiveTask(self.player.CharacterRemoving:Connect(function()
		self.characterMaid:DoCleaning()
		self:Close()
	end))
	local character = self.player.Character
	if character then
		bindCharacterDeath(self, character)
	end
	self.maid:GiveTask(self.openFrame.Destroying:Connect(function()
		self:Destroy()
	end))
	self.maid:GiveTask(self.mainFrame.Destroying:Connect(function()
		self:Destroy()
	end))
	self.maid:GiveTask(self.mainGui.Destroying:Connect(function()
		self:Close()
	end))
end

function PetLuckyBlockScreenController.Destroy(self: Controller): ()
	if not self.alive then
		return
	end
	self:Close()
	self.alive = false
	self.panelTransitionId += 1
	if self.panelTransitionConnection then
		self.panelTransitionConnection:Disconnect()
		self.panelTransitionConnection = nil
	end
	self.openFrame.Visible = false
	self.mainFrame.Visible = false
	if self.previousMainFrameInteractable ~= nil and self.mainFrame.Parent then
		self.mainFrame.Interactable = self.previousMainFrameInteractable
	end
	self.previousMainFrameInteractable = nil
	self.modalVisibilityController:SetNotificationLayer(self.openFrame, false)
	self.modalVisibilityController:Restore()
	self:_cancelPriceRequests(nil)
	self:_stopBlurTween()
	if self.blurEffect then
		self.blurEffect:Destroy()
		self.blurEffect = nil
	end
	self.maid:DoCleaning()
	self.characterMaid:DoCleaning()
	local petUIController = self.petUIController :: any
	petUIController:SetPreviewVisible(false)
	local purchaseController = self.purchaseController :: any
	local cutsceneController = self.cutsceneController
	local modalVisibilityController = self.modalVisibilityController :: any
	petUIController:Destroy()
	purchaseController:Destroy()
	if cutsceneController then
		cutsceneController:Destroy()
	end
	modalVisibilityController:Destroy()
	self.openRemote = nil
end

return PetLuckyBlockScreenController
