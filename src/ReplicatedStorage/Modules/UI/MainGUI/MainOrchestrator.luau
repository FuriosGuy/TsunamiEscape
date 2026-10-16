local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local Players = game:GetService("Players")
local PlayerHandler = require(ReplicatedStorage.Modules.Shared:WaitForChild("PlayerHandler_Client"))
local ProductService = require(ReplicatedStorage.Modules.Shared:WaitForChild("ProductService_Client"))
local KartCatalog = require(ReplicatedStorage.Modules.KartCatalog)
local VerifyRewardCalculator = require(ReplicatedStorage.Modules.Shared.VerifyRewardCalculator)
local MainFunctions = require(ReplicatedStorage.Modules.UI.MainFunctions)
local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local SpinWheelConfig = require(ReplicatedStorage.Modules.Config.SpinWheelConfig)
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local HalloweenCandyShopConfig = require(ReplicatedStorage.Modules.Shared.HalloweenCandyShopConfig)
local FavoriteGamePrompt = require(ReplicatedStorage.Modules.FavoriteGamePrompt)
local TutorialNotificationSystem = require(script.Parent:WaitForChild("TutorialNotificationSystem"))
local PlaytimeRewardsUI = require(script.Parent:WaitForChild("PlaytimeRewardsUI"))
local DailyRewardsUI = require(script.Parent:WaitForChild("DailyRewardsUI"))
local DailyRewardPromptController = require(script.Parent:WaitForChild("DailyRewardPromptController"))
local VerifyGroupController = require(script.Parent:WaitForChild("VerifyGroupController"))
local RewardCelebrationController = require(script.Parent:WaitForChild("RewardCelebrationController"))
local WinDisplayController = require(script.Parent:WaitForChild("WinDisplayController"))
local LevelDisplayController = require(script.Parent:WaitForChild("LevelDisplayController"))
local HudDisplayController = require(script.Parent:WaitForChild("HudDisplayController"))
local TrailDisplayController = require(script.Parent:WaitForChild("TrailDisplayController"))
local TrailShopController = require(script.Parent:WaitForChild("TrailShopController"))
local PlayerAttributeBindings = require(script.Parent:WaitForChild("PlayerAttributeBindings"))
local StageProgressBindings = require(script.Parent:WaitForChild("StageProgressBindings"))
local RemoteBindings = require(script.Parent:WaitForChild("RemoteBindings"))
local DisplayRefreshBindings = require(script.Parent:WaitForChild("DisplayRefreshBindings"))
local KartShopController = require(script.Parent:WaitForChild("KartShopController"))
local RewardedVideoClient = require(ReplicatedStorage.Modules.RewardedVideoClient)
local MenuOpenController = require(script.Parent:WaitForChild("MenuOpenController"))
local WinStreakUI = require(script.Parent:WaitForChild("WinStreakUI"))
local WinCountShopShortcut = require(script.Parent:WaitForChild("WinCountShopShortcut"))
local DEFAULT_PLAYER_SPEED = if typeof(PlayerHandler.DEFAULT_ATTRIBUTES.Player_Speed) == "number"
	then PlayerHandler.DEFAULT_ATTRIBUTES.Player_Speed
	else 16
local DEFAULT_MAX_PLAYER_SPEED = if typeof(PlayerHandler.DEFAULT_ATTRIBUTES.Max_Player_Speed) == "number"
	then PlayerHandler.DEFAULT_ATTRIBUTES.Max_Player_Speed
	else 16

local MainOrchestrator = {}
local DEBUG_TROLL_FRAME_ONLY_FOR_ME = false -- Enabled to allow self-testing as requested
local DEBUG_LOADING_DETAILS = false
local STARTUP_LOADING_ENABLED = true
local hasCompletedStartupLoading = false
local verifyRewardConfig = VerifyRewardCalculator.GetConfig(CoreConfig)
local VERIFY_REWARD_CLAIM_COUNT_ATTRIBUTE = verifyRewardConfig.claimCountAttribute
local VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE = "VerifyRewardNextClaimUnix"
local VERIFY_REWARD_COUNTDOWN_UPDATE_INTERVAL = 1
local RETURN_TO_STAGE_BUTTON_SPLIT_POSITION = UDim2.new(0.261, 0, 0.484, 0)
local RETURN_TO_STAGE_BUTTON_CENTER_POSITION = UDim2.new(0.5, 0, 0.484, 0)
local WHEEL_STYLE = ColorConfig.UI.ButtonStyles.Wheel
local EQUIP_STYLE = ColorConfig.UI.ButtonStyles.Equip
local DISABLE_WAVE_PURCHASE_WATCHDOG_SECONDS = 30
local DISABLE_WAVE_NOTIFICATION_KEY = "DisableWavesCooldown"
local DISABLE_WAVE_NOTIFICATION_MESSAGE = "WAVES DISABLED!"
local PET_INTERACTION_FRAME_NAMES: { [string]: boolean } = table.freeze({
	AddButton = true,
	DeleteButton = true,
	DeleteSelectedButton = true,
	EquipButton = true,
	EquipBestButton = true,
	UnequipAllButton = true,
	MergeButton = true,
	ConfirmButton = true,
	CancelButton = true,
})
local function stopNotificationBadgeAnimation(badgeState: any)
	local stopAnimation = badgeState.animationCleanup
	badgeState.animationCleanup = nil
	if typeof(stopAnimation) == "function" then
		stopAnimation()
	end
end

local function ensureNotificationBadgeAnimation(badgeState: any, badge: GuiObject)
	if typeof(badgeState.animationCleanup) ~= "function" then
		badgeState.animationCleanup = VisualFunctions.StartNotificationBadgeAnimation(badge)
	end
end

local function applyReturnToStageAdLayout(frame: GuiObject, adAvailable: boolean)
	local paidButton = frame:FindFirstChild("ReturnToStageButton", true)
	if paidButton and paidButton:IsA("GuiObject") then
		paidButton.Position = if adAvailable
			then RETURN_TO_STAGE_BUTTON_SPLIT_POSITION
			else RETURN_TO_STAGE_BUTTON_CENTER_POSITION
	end

	local watchAdFrame = frame:FindFirstChild("WatchAdButton", true)
	if watchAdFrame and watchAdFrame:IsA("GuiObject") then
		watchAdFrame.Visible = adAvailable
	end

	local orLabel = frame:FindFirstChild("TextLabel")
	if orLabel and orLabel:IsA("TextLabel") then
		orLabel.Visible = adAvailable
	end
end

local function isLiveEventActive(eventId: string?): boolean
	if typeof(eventId) ~= "string" or eventId == "" then
		return false
	end

	local liveEventState = ReplicatedStorage:FindFirstChild("LiveEventState")
	if not liveEventState or not liveEventState:IsA("Folder") then
		return false
	end
	if eventId == "Halloween" then
		return liveEventState:GetAttribute("EnvironmentName") == "Halloween"
	end

	local activeEventIds = liveEventState:GetAttribute("ActiveEventIds")
	return typeof(activeEventIds) == "string"
		and string.find("," .. activeEventIds .. ",", "," .. eventId .. ",", 1, true) ~= nil
end

local function getKartEventId(config: { [string]: any }): string?
	local eventId = config.eventId
	if typeof(eventId) ~= "string" or eventId == "" then
		eventId = config.sourceSubfolder
	end
	return if typeof(eventId) == "string" and eventId ~= "" then eventId else nil
end

local function isEventKartConfig(config: { [string]: any }): boolean
	return getKartEventId(config) ~= nil
end

local function canBuyEventProduct(config: { [string]: any }, isOwned: boolean): boolean
	local eventId = getKartEventId(config)
	local productKey = config.productKey or config.ProductKey
	return not isOwned
		and eventId ~= nil
		and typeof(productKey) == "string"
		and isLiveEventActive(eventId)
end

local function formatTrailMultiplier(multiplier: number): string
	local text = string.format("%.2f", multiplier)
	text = text:gsub("%.00$", "")
	text = text:gsub("(%..-)0$", "%1")
	return text
end

local function getOrCreateEquipButton(entryFrame: Frame): GuiObject?
	local existing = entryFrame:FindFirstChild("EquipButton")
	if existing and existing:IsA("GuiObject") then
		return existing
	end

	local buyButton = entryFrame:FindFirstChild("BuyButton")
	if not buyButton or not buyButton:IsA("GuiObject") then
		return nil
	end

	local equipButton = buyButton:Clone()
	equipButton.Name = "EquipButton"
	equipButton.Parent = entryFrame

	local textButton = equipButton:FindFirstChild("TextButton", true)
	if textButton and textButton:IsA("TextButton") then
		textButton.Text = "EQUIP"
	end

	return equipButton
end

local function applyGradientStyle(frame: GuiObject, style: ColorConfig.GradientStyle)
	local styleTarget = frame
	if frame:IsA("CanvasGroup") then
		local main = frame:FindFirstChild("Main")
		if main and main:IsA("GuiObject") then
			styleTarget = main
		end
	end
	styleTarget.BackgroundColor3 = style.BackgroundColor
	local gradient = styleTarget:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = styleTarget
	end
	gradient.Rotation = 90
	gradient.Color = style.Gradient
	VisualFunctions.RefreshFrameInteractionColors(styleTarget)
end

local function applyWheelStyle(frame: GuiObject)
	frame:SetAttribute("OriginalDisabledBaseColor", nil)
	applyGradientStyle(frame, WHEEL_STYLE)
end

local function applyEquipStyle(frame: GuiObject)
	applyGradientStyle(frame, EQUIP_STYLE)
end

local function openSpinWheelFromShop(player: Player)
	MainFunctions.SetFrameVisibleSimple("TrailFrame", false)
	MainFunctions.SetFrameVisibleSimple("KartFrame", false)
	local requestId = player:GetAttribute("SpinWheelOpenRequested")
	local nextRequestId = if typeof(requestId) == "number" then requestId + 1 else 1
	player:SetAttribute("SpinWheelOpenRequested", nextRequestId)
end

local function bindPetInventoryNotifications(
	root: Instance,
	player: Player,
	updateBadge: (any, boolean, string, string) -> ()
): () -> ()
	local maid = Maid.new()
	local badgeState = {
		buttonFrame = nil :: GuiObject?,
		template = nil :: GuiObject?,
		badge = nil :: GuiObject?,
		refresh = nil :: (() -> ())?,
	}
	local petFrame: GuiObject? = nil
	local baselineReady = false
	local knownPetUids: { [string]: boolean } = {}
	local unreadPetUids: { [string]: boolean } = {}

	local function refreshBadge(): ()
		local unreadCount = 0
		for _ in pairs(unreadPetUids) do
			unreadCount += 1
		end
		updateBadge(badgeState, unreadCount > 0, "NewPetsNotification", tostring(unreadCount))
	end

	local function readPetUids(): { [string]: boolean }?
		local encodedInventory = player:GetAttribute("Pet_Inventory")
		if typeof(encodedInventory) ~= "string" then
			return nil
		end

		local ok, decodedInventory = pcall(HttpService.JSONDecode, HttpService, encodedInventory)
		if not ok or typeof(decodedInventory) ~= "table" then
			return nil
		end

		local petUids: { [string]: boolean } = {}
		for _, petRecord in ipairs(decodedInventory) do
			if typeof(petRecord) == "table" and typeof(petRecord.uid) == "string" then
				petUids[petRecord.uid] = true
			end
		end
		return petUids
	end

	local function updateFromAttribute(): ()
		if player:GetAttribute("Data_Loaded") ~= true then
			return
		end

		local currentPetUids = readPetUids()
		if not currentPetUids then
			return
		end

		if not baselineReady then
			knownPetUids = currentPetUids
			baselineReady = true
			refreshBadge()
			return
		end

		local inventoryOpen = petFrame ~= nil and petFrame.Visible
		for petUid in pairs(currentPetUids) do
			if not knownPetUids[petUid] and not inventoryOpen then
				unreadPetUids[petUid] = true
			end
		end

		for petUid in pairs(unreadPetUids) do
			if not currentPetUids[petUid] then
				unreadPetUids[petUid] = nil
			end
		end

		knownPetUids = currentPetUids
		refreshBadge()
	end

	local function bindInstance(instance: Instance): ()
		if not instance:IsA("GuiObject") then
			return
		end

		if instance.Name == "NotifShow_Template" then
			badgeState.template = instance
			refreshBadge()
		elseif instance.Name == "PetsButtonFrame" then
			badgeState.buttonFrame = instance
			refreshBadge()
		elseif instance.Name == "PetFrame" and instance:IsA("GuiObject") then
			petFrame = instance
			maid:GiveTask(instance:GetPropertyChangedSignal("Visible"):Connect(function()
				if petFrame == instance and instance.Visible then
					table.clear(unreadPetUids)
					refreshBadge()
				end
			end))
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		bindInstance(descendant)
	end
	maid:GiveTask(root.DescendantAdded:Connect(bindInstance))
	maid:GiveTask(player:GetAttributeChangedSignal("Pet_Inventory"):Connect(updateFromAttribute))
	maid:GiveTask(player:GetAttributeChangedSignal("Data_Loaded"):Connect(updateFromAttribute))
	updateFromAttribute()
	refreshBadge()

	return function(): ()
		maid:DoCleaning()
		table.clear(knownPetUids)
		table.clear(unreadPetUids)
		petFrame = nil
		updateBadge(badgeState, false, "NewPetsNotification", "0")
	end
end

function MainOrchestrator.Init(root: Instance)
	if root:GetAttribute("MainOrchestratorInitialized") == true then
		DebugModule.debugWarn(
			"MainOrchestrator.Init called more than once for " .. root:GetFullName(),
			"MainOrchestrator"
		)
		return
	end

	root:SetAttribute("MainOrchestratorInitialized", true)
	root:SetAttribute("StartupLoadingComplete", false)
	root:SetAttribute("PostLoadingStartupComplete", false)
	hasCompletedStartupLoading = false

	DebugModule.debugPrint("Initializing Main GUI for " .. root.Name, "MainOrchestrator")
	local sessionMaid = Maid.new()
	local stageProgressState = {
		trackedPlayerMaids = {} :: { [Player]: Maid },
		trackedRootParts = {} :: { [Player]: BasePart },
		frame = nil :: Frame?,
		trackFrame = nil :: Frame?,
		markersFrame = nil :: Frame?,
		markerTemplate = nil :: GuiObject?,
		avatarTemplate = nil :: ImageLabel?,
		currentStageLabel = nil :: TextLabel?,
		currentWorldLabel = nil :: TextLabel?,
		markerClones = {} :: { GuiObject },
		playerMarkers = {} :: { [number]: ImageLabel },
		playerMarkerMissingUntil = {} :: { [number]: number },
		avatarCache = {} :: { [number]: string },
		worldName = nil :: string?,
		startPosition = nil :: Vector3?,
		endPosition = nil :: Vector3?,
		markerMissingGrace = 2,
		markerUpdateInterval = 0.1,
		worldStyles = ColorConfig.UI.StageProgressWorlds,
		markerUpdateAccumulator = 0.1,
		updatePlayerMarkers = function() end,
	}
	local isCleanedUp = false
	local startupLoadingTask: thread? = nil
	local disableWaveCountdownTask: thread? = nil
	local disableWavePurchaseWatchdogTask: thread? = nil
	local disableWavePurchaseAttempt = 0
	local disableWavePurchaseInFlight = false
	local disableWaveNotificationCooldownEnd = 0
	local disableWaveNotificationTask: thread? = nil
	local spawnSessionTask: (callback: () -> ()) -> thread
	local function cancelThread(thread: thread?)
		if thread and coroutine.status(thread) ~= "dead" then
			pcall(task.cancel, thread)
		end
	end
	local function cancelDisableWavePurchaseWatchdog()
		disableWavePurchaseAttempt += 1
		if disableWavePurchaseWatchdogTask then
			cancelThread(disableWavePurchaseWatchdogTask)
			disableWavePurchaseWatchdogTask = nil
		end
	end
	local function updateDisableWaveButtonInteraction()
		local frame = VisualFunctions.HUD.DisableWaveButtonFrame
		if not frame then
			return
		end

		local rawCooldownEnd = Players.LocalPlayer:GetAttribute("DisableWavesCooldownEnd")
		local cooldownEnd = if typeof(rawCooldownEnd) == "number" then math.floor(rawCooldownEnd) else 0
		local isOnCooldown = cooldownEnd > os.time()
		VisualFunctions.SetFrameInteractableState(frame, not isOnCooldown and not disableWavePurchaseInFlight)
	end

	if VisualFunctions.ResetRuntimeState then
		VisualFunctions.ResetRuntimeState()
	end

	local function cleanupInitSession()
		if isCleanedUp then
			return
		end

		isCleanedUp = true
		root:SetAttribute("MainOrchestratorInitialized", false)
		root:SetAttribute("StartupLoadingComplete", false)
		root:SetAttribute("PostLoadingStartupComplete", false)
		sessionMaid:DoCleaning()
		if VisualFunctions.ResetRuntimeState then
			VisualFunctions.ResetRuntimeState()
		end
	end

	sessionMaid:GiveTask(root.Destroying:Connect(cleanupInitSession))
	sessionMaid:GiveTask(root.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupInitSession()
		end
	end))

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local kartActionRemote = remotes:WaitForChild("KartAction") :: RemoteEvent
	local returnToStagePromptOpenedRemote = remotes:WaitForChild("ReturnToStagePromptOpened") :: RemoteEvent
	local trollActionRequestRemote = remotes:WaitForChild("TrollActionRequest") :: RemoteEvent
	local dataRecoveryRequestRemote = remotes:WaitForChild("DataRecoveryRequest") :: RemoteEvent
	local dataRecoveryResultRemote = remotes:WaitForChild("DataRecoveryResult") :: RemoteEvent
	local hideReturnToStageFrame: () -> () = function() end
	local localPlayer = Players.LocalPlayer
	local hasShownFavoriteGamePrompt = false
	local function promptFavoriteGameIfReady()
		if
			hasShownFavoriteGamePrompt
			or not hasCompletedStartupLoading
			or localPlayer:GetAttribute("Data_Loaded") ~= true
		then
			return
		end

		hasShownFavoriteGamePrompt = true
		sessionMaid:GiveTask(
			FavoriteGamePrompt.StartDeferredPrompt(localPlayer, function(): boolean
				return not isCleanedUp
			end)
		)
	end
	local canUseTrollFrame = true
	local allowSelfTargetingInTrollDebug = RunService:IsStudio() and DEBUG_TROLL_FRAME_ONLY_FOR_ME

	local trollFrame: GuiObject? = nil
	local trollNameLabel: TextLabel? = nil
	local trollPreviousButton: GuiButton? = nil
	local trollNextButton: GuiButton? = nil
	local trollButtonFrame: GuiObject? = nil
	local trollActionButtons: { [string]: GuiButton } = {}
	local syncTrollCamera: () -> ()
	local trollSelectedPlayer: Player? = nil
	local trollSpectateConnection: RBXScriptConnection? = nil
	local trollSelectedCharacterAddedConnection: RBXScriptConnection? = nil
	local trollSelectedCharacterRemovingConnection: RBXScriptConnection? = nil
	local jumpscareImage: ImageLabel? = nil
	local jumpscareHideToken = 0
	local trollMovementLockState: {
		humanoid: Humanoid?,
		walkSpeed: number?,
		jumpHeight: number?,
		autoRotate: boolean?,
	} =
		{
			humanoid = nil,
			walkSpeed = nil,
			jumpHeight = nil,
			autoRotate = nil,
		}
	local loadingMovementLockState: {
		humanoid: Humanoid?,
		walkSpeed: number?,
		jumpHeight: number?,
		autoRotate: boolean?,
		onLoadingComplete: () -> (),
	} =
		{
			humanoid = nil,
			walkSpeed = nil,
			jumpHeight = nil,
			autoRotate = nil,
			onLoadingComplete = function() end,
		}
	local loadingFrame: GuiObject? = nil
	local loadingImage: ImageLabel? = nil
	local loadingGameImage: ImageLabel? = nil
	local loadingLightRay: ImageLabel? = nil
	local loadingLevelsBarFrame: Frame? = nil
	local loadingProgressFrame: Frame? = nil
	local loadingProgressLabel: TextLabel? = nil
	local loadingCurrentLabel: TextLabel? = nil
	local loadingSkipButtonFrame: GuiObject? = nil
	local loadingSkipButton: GuiButton? = nil
	local loadingDataRecoveryFrame: GuiObject? = nil
	local loadingDataRecoveryWarningLabel: TextLabel? = nil
	local loadingDataRecoveryAttemptsLabel: TextLabel? = nil
	local loadingDataRecoveryRetryButton: GuiButton? = nil
	local loadingDataRecoveryResetButton: GuiButton? = nil
	local loadingDataRecoveryPopScale: UIScale? = nil
	local loadingDataRecoveryPopTween: Tween? = nil
	local dataRecoveryRequestInFlight = false
	local runStartupLoading: () -> () = function() end
	local tutorialSystem: any? = nil
	local loadingProgressTween: Tween? = nil
	local loadingCurrentLabelTween: Tween? = nil
	local loadingCurrentLabelText = ""
	local loadingProgressFloor = 0
	local loadingSkipRequested = false
	local verifyGroupCountdownLabel: TextLabel? = nil
	local verifyRewardWhenLabel: TextLabel? = nil
	local refreshVerifyCountdownLabel: (() -> ())? = nil
	local verifyRewardXPLabel: TextLabel? = nil
	local verifyRewardWinsLabel: TextLabel? = nil
	local refreshVerifyRewardValueLabels: (() -> ())? = nil
	local verifyGroupController: any = nil
	local rebirthReadyUIState = {
		buttonFrame = nil :: GuiObject?,
		lightRay = nil :: GuiObject?,
		template = nil :: GuiObject?,
		badge = nil :: GuiObject?,
		refresh = nil :: (() -> ())?,
		wasReady = false,
		notificationPending = false,
		skipNotificationUntil = 0,
	}
	local kartPurchaseUIState = {
		buttonFrame = nil :: GuiObject?,
		template = nil :: GuiObject?,
		badge = nil :: GuiObject?,
		refresh = nil :: (() -> ())?,
	}
	local trailAffordableUIState = {
		buttonFrame = nil :: GuiObject?,
		template = nil :: GuiObject?,
		badge = nil :: GuiObject?,
		refresh = nil :: (() -> ())?,
	}
	local candyShopAffordableUIState = {
		buttonFrame = nil :: GuiObject?,
		template = nil :: GuiObject?,
		badge = nil :: GuiObject?,
		refresh = nil :: (() -> ())?,
	}
	local playtimeClaimableUIState = {
		buttonFrame = nil :: GuiObject?,
		template = nil :: GuiObject?,
		badge = nil :: GuiObject?,
		refresh = nil :: (() -> ())?,
	}
	local verifyClaimableUIState = {
		buttonFrame = nil :: GuiObject?,
		template = nil :: GuiObject?,
		badge = nil :: GuiObject?,
		refresh = nil :: (() -> ())?,
	}
	local loadingRequiredAttributes = {
		"Data_Loaded",
	}
	local loadingRemoteNames = {
		"MovementAction",
		"RebirthAction",
		"SpeedAction",
		"ShowNotification",
		"ReturnToStageOffer",
		"ReturnToStageDeclined",
		"ReturnToStagePromptOpened",
		"RequestReturnToStageOffer",
		"PlayConfettiBurst",
		"RebirthResult",
		"VerifyRewardRequest",
		"VerifyRewardResult",
		"TrailAction",
		"KartAction",
		"TrollActionRequest",
		"TriggerJumpscare",
		"PlaytimeRewardAction",
		"XPGainAwarded",
		"WinButtonPressed",
		"OpenVerifyFrame",
		"DailyRewardAction",
	}

	sessionMaid:GiveTask(function()
		for trackedPlayer, trackedPlayerMaid in pairs(stageProgressState.trackedPlayerMaids) do
			trackedPlayerMaid:DoCleaning()
			stageProgressState.trackedPlayerMaids[trackedPlayer] = nil
		end
	end)
	sessionMaid:GiveTask(function()
		if startupLoadingTask then
			cancelThread(startupLoadingTask)
			startupLoadingTask = nil
		end
		if disableWaveCountdownTask then
			cancelThread(disableWaveCountdownTask)
			disableWaveCountdownTask = nil
		end
		cancelDisableWavePurchaseWatchdog()
		disableWavePurchaseInFlight = false
		verifyGroupCountdownLabel = nil
		verifyRewardWhenLabel = nil
		refreshVerifyCountdownLabel = nil
		verifyRewardXPLabel = nil
		verifyRewardWinsLabel = nil
		refreshVerifyRewardValueLabels = nil
		if verifyGroupController then
			verifyGroupController:Destroy()
			verifyGroupController = nil
		end
		verifyClaimableUIState.refresh = nil
	end)
	local loadingSystemTasks = {
		"VIPDoorCollision",
		"KartButtons",
		"WorldMusic",
		"DynamicFov",
	}
	local SHOP_BUTTON_CONFIGS = {
		AdvancedTankButton = {
			kartModelName = "AdvancedTank",
			itemId = ProductService.Gamepasses["AdvancedTank"],
			infoType = Enum.InfoType.GamePass,
			purchaseType = "gamepass",
			colorPassNameFromBackground = true,
		},
		ShoppingKartButton = {
			kartModelName = "ShoppingKart",
			itemId = ProductService.Gamepasses["ShoppingKart"],
			infoType = Enum.InfoType.GamePass,
			purchaseType = "gamepass",
			colorPassNameFromBackground = true,
		},
		FormulaCarButton = {
			kartModelName = "FormulaCar",
			itemId = ProductService.Gamepasses["FormulaCar"],
			infoType = Enum.InfoType.GamePass,
			purchaseType = "gamepass",
			colorPassNameFromBackground = true,
		},
		["3xTreadmillButton"] = {
			itemId = ProductService.Gamepasses["3xTreadmill"],
			infoType = Enum.InfoType.GamePass,
			purchaseType = "gamepass",
			colorPassNameFromBackground = true,
		},
		["15xTreadmillButton"] = {
			itemId = ProductService.Gamepasses["15xTreadmill"],
			infoType = Enum.InfoType.GamePass,
			purchaseType = "gamepass",
			colorPassNameFromBackground = true,
		},
		["35xTreadmillButton"] = {
			itemId = ProductService.Gamepasses["35xTreadmill"],
			infoType = Enum.InfoType.GamePass,
			purchaseType = "gamepass",
			colorPassNameFromBackground = true,
		},
		["100xTreadmillButton"] = {
			itemId = ProductService.Gamepasses["100xTreadmill"],
			infoType = Enum.InfoType.GamePass,
			purchaseType = "gamepass",
			colorPassNameFromBackground = true,
		},
		["2xWinButton"] = {
			itemId = ProductService.Gamepasses["2xWins"],
			infoType = Enum.InfoType.GamePass,
			purchaseType = "gamepass",
		},
		VIPButton = {
			itemId = ProductService.Gamepasses["VIP"],
			infoType = Enum.InfoType.GamePass,
			purchaseType = "gamepass",
		},
		StarterPackButtonFrame = {
			itemId = ProductService.Gamepasses["StarterPack"],
			infoType = Enum.InfoType.GamePass,
			purchaseType = "gamepass",
			hideWhenOwned = true,
			debugShowWhenOwnedInStudio = true,
			useMarketplaceImage = false,
		},
		["1000WinButton"] = {
			itemId = ProductService.DevProducts["+1000"],
			infoType = Enum.InfoType.Product,
			purchaseType = "product",
		},
		["5000WinButton"] = {
			itemId = ProductService.DevProducts["+5000"],
			infoType = Enum.InfoType.Product,
			purchaseType = "product",
		},
		["10000WinButton"] = {
			itemId = ProductService.DevProducts["+10000"],
			infoType = Enum.InfoType.Product,
			purchaseType = "product",
		},
	}

	local safePlayTween: (Instance, number, { [string]: any }) -> ()
	local tweenGuiTransparencyRecursive: (Instance, number, number) -> ()

	local function setTrollPlayerLabel(text: string)
		if trollNameLabel then
			trollNameLabel.Text = text
		end
	end

	local function updateLoadingProgress(progress: number, labelText: string?)
		local clampedProgress = math.max(math.clamp(progress, 0, 1), loadingProgressFloor)

		if loadingProgressFrame then
			if loadingProgressTween then
				loadingProgressTween:Cancel()
				loadingProgressTween = nil
			end

			loadingProgressTween = TweenService:Create(
				loadingProgressFrame,
				TweenConfig.LoadingProgress,
				{
					Size = UDim2.new(
						clampedProgress,
						0,
						loadingProgressFrame.Size.Y.Scale,
						loadingProgressFrame.Size.Y.Offset
					),
				}
			)
			loadingProgressTween:Play()
		end

		if loadingProgressLabel then
			loadingProgressLabel.Text = string.format("%d%%", math.round(clampedProgress * 100))
		end

		if labelText and loadingCurrentLabel then
			if loadingCurrentLabelText == "" then
				loadingCurrentLabelText = loadingCurrentLabel.Text
			end

			if labelText ~= loadingCurrentLabelText then
				loadingCurrentLabelText = labelText

				if loadingCurrentLabelTween then
					loadingCurrentLabelTween:Cancel()
					loadingCurrentLabelTween = nil
				end

				local fadeOutTween = TweenService:Create(
					loadingCurrentLabel,
					TweenConfig.LoadingLabelFade,
					{
						TextTransparency = 1,
					}
				)
				loadingCurrentLabelTween = fadeOutTween
				for _, descendant in ipairs(loadingCurrentLabel:GetDescendants()) do
					if descendant:IsA("UIStroke") then
						safePlayTween(descendant, 0.15, { Transparency = 1 })
					end
				end
				fadeOutTween:Play()
				sessionMaid:GiveTask(fadeOutTween.Completed:Connect(function(playbackState)
					if playbackState ~= Enum.PlaybackState.Completed then
						return
					end
					if not loadingCurrentLabel then
						return
					end

					loadingCurrentLabel.Text = labelText
					for _, descendant in ipairs(loadingCurrentLabel:GetDescendants()) do
						if descendant:IsA("UIStroke") then
							safePlayTween(descendant, 0.15, { Transparency = 0 })
						end
					end

					local fadeInTween = TweenService:Create(
						loadingCurrentLabel,
						TweenConfig.LoadingLabelFade,
						{
							TextTransparency = 0,
						}
					)
					loadingCurrentLabelTween = fadeInTween
					fadeInTween:Play()
				end))
			end
		end
	end

	local function formatLoadingLabel(baseLabel: string, detail: string?): string
		if RunService:IsStudio() and DEBUG_LOADING_DETAILS and detail and detail ~= "" then
			return string.format("%s (%s)", baseLabel, detail)
		end

		return baseLabel
	end

	local function debugLoading(message: string)
		DebugModule.debugPrint(message, "MainOrchestrator")
	end

	local function debugLoadingWarn(message: string)
		DebugModule.debugWarn(message, "MainOrchestrator")
	end

	local function hideLoadingSkipButton()
		if loadingSkipButton then
			loadingSkipButton.Active = false
			loadingSkipButton.Selectable = false
		end

		if loadingSkipButtonFrame then
			loadingSkipButtonFrame.Visible = false
		end
	end

	local function showNotificationRespectingTutorial(
		message: string,
		textColor: Color3?,
		gradientBottomColor: Color3?,
		notificationStyle: string?,
		notificationKey: string?
	): boolean
		local modalLockOwner = localPlayer:GetAttribute("ModalLockOwner")
		if localPlayer:GetAttribute("SpinWheelModalOpen") == true
			or (modalLockOwner ~= nil and modalLockOwner ~= "LuckyBlock")
		then
			return false
		end
		if not hasCompletedStartupLoading then
			return false
		end

		if tutorialSystem then
			return tutorialSystem:ShowNonTutorialNotification(
				message,
				textColor,
				gradientBottomColor,
				notificationStyle,
				notificationKey
			)
		end

		if notificationStyle == "QuickFade" then
			VisualFunctions.ShowQuickFadeNotification(message, textColor, gradientBottomColor)
			return true
		end
		VisualFunctions.ShowNotification(message, textColor, gradientBottomColor, notificationKey)
		return true
	end

	local function refreshDisableWaveNotification()
		if not hasCompletedStartupLoading then
			return
		end

		local theme = VisualFunctions.NotificationThemes.Red
		local wasUpdated = VisualFunctions.UpdateNotification(
			DISABLE_WAVE_NOTIFICATION_MESSAGE,
			DISABLE_WAVE_NOTIFICATION_KEY
		)
		if not wasUpdated then
			showNotificationRespectingTutorial(
				DISABLE_WAVE_NOTIFICATION_MESSAGE,
				theme.textColor,
				theme.gradientBottomColor,
				nil,
				DISABLE_WAVE_NOTIFICATION_KEY
			)
		end
	end

	local function showDisableWaveNotification(cooldownEnd: number)
		local resolvedCooldownEnd = math.floor(cooldownEnd)
		if resolvedCooldownEnd <= os.time() then
			return
		end

		local shouldRestartTask = disableWaveNotificationCooldownEnd ~= resolvedCooldownEnd
		disableWaveNotificationCooldownEnd = resolvedCooldownEnd
		refreshDisableWaveNotification()

		if not shouldRestartTask then
			return
		end

		if disableWaveNotificationTask then
			cancelThread(disableWaveNotificationTask)
			disableWaveNotificationTask = nil
		end

		local trackedCooldownEnd = resolvedCooldownEnd
		disableWaveNotificationTask = spawnSessionTask(function()
			while disableWaveNotificationCooldownEnd == trackedCooldownEnd do
				local remaining = math.max(0, trackedCooldownEnd - os.time())
				if remaining <= 0 then
					break
				end

				refreshDisableWaveNotification()
				task.wait(1)
			end

			if disableWaveNotificationCooldownEnd == trackedCooldownEnd then
				VisualFunctions.HideNotification(DISABLE_WAVE_NOTIFICATION_KEY)
				disableWaveNotificationCooldownEnd = 0
			end

			if disableWaveNotificationTask == coroutine.running() then
				disableWaveNotificationTask = nil
			end
		end)
	end

	local function updateButtonNotificationBadge(
		badgeState: any,
		shouldShow: boolean,
		badgeName: string,
		countText: string
	)
		local existingBadge = badgeState.badge
		if not shouldShow then
			stopNotificationBadgeAnimation(badgeState)
			if existingBadge then
				existingBadge:Destroy()
				badgeState.badge = nil
			end
			return
		end

		local buttonFrame = badgeState.buttonFrame
		if not buttonFrame or buttonFrame.Parent == nil then
			return
		end

		local badge = existingBadge
		if not badge or badge.Parent == nil then
			stopNotificationBadgeAnimation(badgeState)
			local template = badgeState.template
			if not template or template.Parent == nil then
				local guiHandler = root:FindFirstChild("GuiHandler")
				local guiHandlerTemplate = guiHandler and guiHandler:FindFirstChild("NotifShow_Template")
				if guiHandlerTemplate and guiHandlerTemplate:IsA("GuiObject") then
					template = guiHandlerTemplate
				else
					local fallbackTemplate = root:FindFirstChild("NotifShow_Template", true)
					if fallbackTemplate and fallbackTemplate:IsA("GuiObject") then
						template = fallbackTemplate
					end
				end
				badgeState.template = template
			end

			if template and template:IsA("GuiObject") then
				local clone = template:Clone()
				clone.Name = badgeName
				clone.Visible = true
				clone.Parent = buttonFrame
				badge = clone
			else
				local fallback = Instance.new("Frame")
				fallback.Name = badgeName
				fallback.AnchorPoint = Vector2.new(0.5, 0.5)
				fallback.BackgroundColor3 = ColorConfig.Colors.UnreadBadge.Color
				fallback.BorderSizePixel = 0
				fallback.Position = UDim2.new(0.9924, 0, 0.0152, 0)
				fallback.Size = UDim2.new(0.3316, 0, 0.2779, 0)
				fallback.Visible = true
				fallback.ZIndex = 3

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0.5, 0)
				corner.Parent = fallback

				local label = Instance.new("TextLabel")
				label.Name = "NumberLabel"
				label.BackgroundTransparency = 1
				label.Size = UDim2.fromScale(1, 1)
				label.Text = countText
				label.TextColor3 = ColorConfig.Colors.White.Color
				label.TextScaled = true
				label.Font = Enum.Font.GothamBold
				label.ZIndex = 4
				label.Parent = fallback

				fallback.Parent = buttonFrame
				badge = fallback
			end

			badgeState.badge = badge
		end

		if badge then
			badge.Visible = true

			local numberLabel = badge:FindFirstChild("NumberLabel", true)
			if numberLabel and numberLabel:IsA("TextLabel") then
				numberLabel.Text = countText
			elseif numberLabel and numberLabel:IsA("TextButton") then
				numberLabel.Text = countText
			else
				local firstTextLabel = badge:FindFirstChildWhichIsA("TextLabel", true)
				if firstTextLabel then
					firstTextLabel.Text = countText
				else
					local firstTextButton = badge:FindFirstChildWhichIsA("TextButton", true)
					if firstTextButton then
						firstTextButton.Text = countText
					end
				end
			end

			ensureNotificationBadgeAnimation(badgeState, badge)
		end
	end

	local function updateRebirthReadyBadgeVisibility(shouldShow: boolean)
		updateButtonNotificationBadge(rebirthReadyUIState, shouldShow, "RebirthReadyNotification", "1")
	end

	local function isInsideLoadingFrame(instance: Instance): boolean
		local current = instance.Parent
		while current do
			if current == loadingFrame or current.Name == "LoadingFrame" then
				return true
			end
			current = current.Parent
		end

		return false
	end

	local function isLoadingDataReady(): boolean
		for _, attributeName in ipairs(loadingRequiredAttributes) do
			local attributeValue = localPlayer:GetAttribute(attributeName)
			if attributeName == "Data_Loaded" then
				if attributeValue ~= true then
					return false
				end
			elseif attributeValue == nil then
				return false
			end
		end

		return true
	end

	local function fetchLoadingGameIcon()
		if not loadingGameImage then
			return
		end

		if game.GameId == 0 then
			debugLoadingWarn("Loading game icon skipped: game.GameId is 0")
			return
		end

		loadingGameImage.Image = string.format("rbxthumb://type=GameIcon&id=%d&w=150&h=150", game.GameId)
		debugLoading(string.format("Loading game icon set from GameId=%d", game.GameId))
	end

	function safePlayTween(instance: Instance, duration: number, goals: { [string]: any })
		local success, tweenOrError = pcall(function()
			return TweenService:Create(
				instance,
				TweenConfig.WithDuration(duration, TweenConfig.LoadingLabelFade),
				goals
			)
		end)

		if success and tweenOrError then
			(tweenOrError :: Tween):Play()
		else
			debugLoadingWarn(string.format("Tween skipped for %s: %s", instance:GetFullName(), tostring(tweenOrError)))
		end
	end

	function tweenGuiTransparencyRecursive(instance: Instance, duration: number, transparency: number)
		local tweenGoals = {}
		if instance:IsA("CanvasGroup") then
			tweenGoals.GroupTransparency = transparency
		elseif instance:IsA("Frame") or instance:IsA("ScrollingFrame") then
			tweenGoals.BackgroundTransparency = transparency
		elseif instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			tweenGoals.TextTransparency = transparency
		elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			tweenGoals.ImageTransparency = transparency
			tweenGoals.BackgroundTransparency = transparency
		elseif instance:IsA("UIStroke") then
			tweenGoals.Transparency = transparency
		end

		if next(tweenGoals) ~= nil then
			safePlayTween(instance, duration, tweenGoals)
		end

		for _, descendant in ipairs(instance:GetDescendants()) do
			local insideCanvasGroup = instance:IsA("CanvasGroup")
			local ancestor = descendant.Parent
			while ancestor do
				if ancestor:IsA("CanvasGroup") then
					insideCanvasGroup = true
					break
				end
				if ancestor == instance then
					break
				end
				ancestor = ancestor.Parent
			end
			if insideCanvasGroup then
				continue
			end

			local descendantGoals = {}
			if descendant:IsA("CanvasGroup") then
				descendantGoals.GroupTransparency = transparency
			elseif descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
				descendantGoals.TextTransparency = transparency
			elseif descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
				descendantGoals.ImageTransparency = transparency
				descendantGoals.BackgroundTransparency = transparency
			elseif descendant:IsA("Frame") or descendant:IsA("ScrollingFrame") then
				descendantGoals.BackgroundTransparency = transparency
			elseif descendant:IsA("UIStroke") then
				descendantGoals.Transparency = transparency
			end

			if next(descendantGoals) ~= nil then
				safePlayTween(descendant, duration, descendantGoals)
			end
		end
	end

	local function tweenGuiFadeOut(guiObject: GuiObject, duration: number)
		tweenGuiTransparencyRecursive(guiObject, duration, 1)
	end

	local function tweenGuiFadeIn(guiObject: GuiObject, duration: number)
		tweenGuiTransparencyRecursive(guiObject, duration, 0)
	end

	local function getSpectateCandidates(): { Player }
		if not canUseTrollFrame then
			return {}
		end

		local candidates = {}
		for _, candidate in ipairs(Players:GetPlayers()) do
			if allowSelfTargetingInTrollDebug or candidate ~= localPlayer then
				table.insert(candidates, candidate)
			end
		end

		table.sort(candidates, function(a, b)
			return string.lower(a.Name) < string.lower(b.Name)
		end)

		return candidates
	end

	local function getCameraSubjectForPlayer(player: Player): Instance?
		local character = player.Character
		if not character then
			return nil
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			return humanoid
		end

		if humanoid then
			return nil
		end

		return character:FindFirstChild("HumanoidRootPart")
	end

	local function disconnectTrollSelectedCharacterConnections()
		if trollSelectedCharacterAddedConnection then
			trollSelectedCharacterAddedConnection:Disconnect()
			trollSelectedCharacterAddedConnection = nil
		end

		if trollSelectedCharacterRemovingConnection then
			trollSelectedCharacterRemovingConnection:Disconnect()
			trollSelectedCharacterRemovingConnection = nil
		end
	end

	local function restoreLocalCamera()
		local currentCamera = workspace.CurrentCamera
		if not currentCamera then
			return
		end

		local subject = getCameraSubjectForPlayer(localPlayer)
		if subject then
			currentCamera.CameraType = Enum.CameraType.Custom
			currentCamera.CameraSubject = subject
		end
	end

	local function updateTrollSelection(targetPlayer: Player?)
		trollSelectedPlayer = targetPlayer
		disconnectTrollSelectedCharacterConnections()
		if trollSelectedPlayer then
			trollSelectedCharacterAddedConnection = trollSelectedPlayer.CharacterAdded:Connect(function()
				sessionMaid:GiveTask(task.defer(function()
					if not isCleanedUp then
						syncTrollCamera()
					end
				end))
			end)
			trollSelectedCharacterRemovingConnection = trollSelectedPlayer.CharacterRemoving:Connect(function()
				sessionMaid:GiveTask(task.defer(function()
					if not isCleanedUp then
						syncTrollCamera()
					end
				end))
			end)
		end

		if trollSelectedPlayer then
			setTrollPlayerLabel(trollSelectedPlayer.Name)
		else
			setTrollPlayerLabel("None")
		end
	end

	function syncTrollCamera()
		local currentCamera = workspace.CurrentCamera
		if not currentCamera then
			return
		end

		if not trollFrame or not trollFrame.Visible or not canUseTrollFrame then
			restoreLocalCamera()
			return
		end

		local candidates = getSpectateCandidates()
		if #candidates == 0 then
			updateTrollSelection(nil)
			restoreLocalCamera()
			return
		end

		local selectedStillExists = false
		for _, candidate in ipairs(candidates) do
			if candidate == trollSelectedPlayer then
				selectedStillExists = true
				break
			end
		end

		if not selectedStillExists then
			updateTrollSelection(candidates[1])
		end

		local selectedPlayer = trollSelectedPlayer
		if not selectedPlayer then
			restoreLocalCamera()
			return
		end

		local subject = getCameraSubjectForPlayer(selectedPlayer)
		if not subject then
			restoreLocalCamera()
			return
		end

		currentCamera.CameraType = Enum.CameraType.Custom
		if currentCamera.CameraSubject ~= subject then
			currentCamera.CameraSubject = subject
		end
	end

	local function cycleTrollTarget(direction: number)
		local candidates = getSpectateCandidates()
		if #candidates == 0 then
			updateTrollSelection(nil)
			restoreLocalCamera()
			return
		end

		local currentIndex = 1
		for index, candidate in ipairs(candidates) do
			if candidate == trollSelectedPlayer then
				currentIndex = index
				break
			end
		end

		local nextIndex = ((currentIndex - 1 + direction) % #candidates) + 1
		updateTrollSelection(candidates[nextIndex])
		syncTrollCamera()
	end

	local function startTrollSpectate()
		if not canUseTrollFrame then
			if trollFrame then
				trollFrame.Visible = false
			end
			restoreLocalCamera()
			return
		end

		local candidates = getSpectateCandidates()
		updateTrollSelection(candidates[1])
		syncTrollCamera()

		if not trollSpectateConnection then
			trollSpectateConnection = RunService.RenderStepped:Connect(function()
				syncTrollCamera()
			end)
		end
	end

	local function stopTrollSpectate()
		if trollSpectateConnection then
			trollSpectateConnection:Disconnect()
			trollSpectateConnection = nil
		end
		disconnectTrollSelectedCharacterConnections()
		restoreLocalCamera()
	end

	sessionMaid:GiveTask(function()
		stopTrollSpectate()
	end)

	local function lockLocalMovementForTrollFrame()
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		trollMovementLockState.humanoid = humanoid
		trollMovementLockState.walkSpeed = humanoid.WalkSpeed
		trollMovementLockState.jumpHeight = humanoid.JumpHeight
		trollMovementLockState.autoRotate = humanoid.AutoRotate

		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	end

	local function unlockLocalMovementForTrollFrame()
		local character = localPlayer.Character
		local humanoid = (character and character:FindFirstChildOfClass("Humanoid")) or trollMovementLockState.humanoid

		if humanoid then
			if typeof(trollMovementLockState.walkSpeed) == "number" then
				humanoid.WalkSpeed = math.max(trollMovementLockState.walkSpeed, 1)
			else
				-- Fallback if state was lost or never set (Rule #3.24)
				humanoid.WalkSpeed = PlayerHandler.GetEffectiveWalkSpeed(localPlayer)
			end

			if typeof(trollMovementLockState.jumpHeight) == "number" then
				humanoid.JumpHeight = trollMovementLockState.jumpHeight
			end

			if typeof(trollMovementLockState.autoRotate) == "boolean" then
				humanoid.AutoRotate = trollMovementLockState.autoRotate
			else
				humanoid.AutoRotate = true
			end
		end

		trollMovementLockState.humanoid = nil
		trollMovementLockState.walkSpeed = nil
		trollMovementLockState.jumpHeight = nil
		trollMovementLockState.autoRotate = nil
	end

	local function lockLocalMovementForLoading()
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		if loadingMovementLockState.humanoid == humanoid then
			humanoid.WalkSpeed = 0
			humanoid.JumpHeight = 0
			humanoid.AutoRotate = false
			return
		end

		loadingMovementLockState.humanoid = humanoid
		loadingMovementLockState.walkSpeed = humanoid.WalkSpeed
		loadingMovementLockState.jumpHeight = humanoid.JumpHeight
		loadingMovementLockState.autoRotate = humanoid.AutoRotate

		humanoid.WalkSpeed = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false
	end

	local function unlockLocalMovementForLoading()
		local humanoid = loadingMovementLockState.humanoid
		if humanoid and humanoid.Parent then
			if localPlayer:GetAttribute("Data_Loaded") == true then
				humanoid.WalkSpeed = PlayerHandler.GetEffectiveWalkSpeed(localPlayer)
			elseif typeof(loadingMovementLockState.walkSpeed) == "number" then
				humanoid.WalkSpeed = loadingMovementLockState.walkSpeed
			end
			if typeof(loadingMovementLockState.jumpHeight) == "number" then
				humanoid.JumpHeight = loadingMovementLockState.jumpHeight
			end
			if typeof(loadingMovementLockState.autoRotate) == "boolean" then
				humanoid.AutoRotate = loadingMovementLockState.autoRotate
			end
		end

		loadingMovementLockState.humanoid = nil
		loadingMovementLockState.walkSpeed = nil
		loadingMovementLockState.jumpHeight = nil
		loadingMovementLockState.autoRotate = nil
	end

	spawnSessionTask = function(callback: () -> ()): thread
		local thread = task.spawn(function()
			if isCleanedUp then
				return
			end
			callback()
		end)
		sessionMaid:GiveTask(thread)
		return thread
	end

	local boundGuiSignals: { [Instance]: { [string]: boolean } } = {}

	local function bindGuiSignal(instance: Instance, key: string, connection: RBXScriptConnection)
		local bindings = boundGuiSignals[instance]
		if not bindings then
			bindings = {}
			boundGuiSignals[instance] = bindings
		end

		if bindings[key] then
			connection:Disconnect()
			return
		end

		bindings[key] = true
		sessionMaid:GiveTask(connection)
	end

	local function bindGuiButton(button: GuiButton, key: string, callback: () -> ())
		bindGuiSignal(button, key, button.Activated:Connect(callback))
	end

	local function updateDataRecoveryAttempts()
		if not loadingDataRecoveryAttemptsLabel then
			return
		end

		local attempts = localPlayer:GetAttribute("DataRecoveryAttempts")
		local normalizedAttempts = if typeof(attempts) == "number" then math.max(0, math.floor(attempts)) else 0
		loadingDataRecoveryAttemptsLabel.Text = string.format("ATTEMPTS: %d", normalizedAttempts)
	end

	local function setDataRecoveryFrameVisible(visible: boolean, shouldPop: boolean?)
		if not loadingDataRecoveryFrame then
			return
		end

		if not visible and loadingDataRecoveryPopTween then
			loadingDataRecoveryPopTween:Cancel()
			loadingDataRecoveryPopTween = nil
		end
		loadingDataRecoveryFrame.Visible = visible
		loadingDataRecoveryFrame.Active = visible
		loadingDataRecoveryFrame.Interactable = visible
		if visible then
			updateDataRecoveryAttempts()
			if shouldPop and loadingDataRecoveryPopScale then
				loadingDataRecoveryPopScale.Scale = 0.86
				local popTween = TweenService:Create(
					loadingDataRecoveryPopScale,
					TweenConfig.DataRecoveryPop,
					{ Scale = 1 }
				)
				loadingDataRecoveryPopTween = popTween
				popTween.Completed:Once(function()
					if loadingDataRecoveryPopTween == popTween then
						loadingDataRecoveryPopTween = nil
					end
				end)
				popTween:Play()
			end
		end
	end

	local function bindDataRecoveryFrame(frame: GuiObject?)
		if not frame then
			return
		end

		loadingDataRecoveryFrame = frame
		loadingDataRecoveryFrame.Visible = false
		loadingDataRecoveryFrame.Active = false
		loadingDataRecoveryFrame.Interactable = false
		local existingPopScale = frame:FindFirstChild("DataRecoveryPopScale")
		if existingPopScale and existingPopScale:IsA("UIScale") then
			loadingDataRecoveryPopScale = existingPopScale
		else
			local popScale = Instance.new("UIScale")
			popScale.Name = "DataRecoveryPopScale"
			popScale.Scale = 1
			popScale.Parent = frame
			loadingDataRecoveryPopScale = popScale
		end
		loadingDataRecoveryWarningLabel = frame:FindFirstChild("WarningLabel") :: TextLabel?
		loadingDataRecoveryAttemptsLabel = frame:FindFirstChild("Attempts") :: TextLabel?
		if loadingDataRecoveryAttemptsLabel then
			loadingDataRecoveryAttemptsLabel.Text = "ATTEMPTS: 0"
		end

		local retryButtonFrame = frame:FindFirstChild("RetryButton")
		loadingDataRecoveryRetryButton = retryButtonFrame
			and retryButtonFrame:FindFirstChildWhichIsA("GuiButton", true)
		if loadingDataRecoveryRetryButton then
			bindGuiButton(loadingDataRecoveryRetryButton, "dataRecoveryRetry", function()
				if localPlayer:GetAttribute("Data_LoadState") == "RecoveryRequired" then
					if dataRecoveryRequestInFlight then
						return
					end
					dataRecoveryRequestInFlight = true
					setDataRecoveryFrameVisible(false)
					updateLoadingProgress(loadingProgressFloor, "RETRYING DATA LOAD")
					dataRecoveryRequestRemote:FireServer("Retry")
				end
			end)
		end

		local resetButtonFrame = frame:FindFirstChild("ResetButton")
		loadingDataRecoveryResetButton = resetButtonFrame
			and resetButtonFrame:FindFirstChildWhichIsA("GuiButton", true)
		if loadingDataRecoveryResetButton then
			bindGuiButton(loadingDataRecoveryResetButton, "dataRecoveryReset", function()
				if
					dataRecoveryRequestInFlight
					or localPlayer:GetAttribute("Data_LoadState") ~= "RecoveryRequired"
				then
					return
				end
				dataRecoveryRequestInFlight = true
				dataRecoveryRequestRemote:FireServer("Reset")
			end)
		end

		if loadingFrame and loadingFrame.Visible and localPlayer:GetAttribute("Data_LoadState") == "RecoveryRequired" then
			setDataRecoveryFrameVisible(true, true)
		end
	end

	sessionMaid:GiveTask(localPlayer:GetAttributeChangedSignal("DataRecoveryAttempts"):Connect(updateDataRecoveryAttempts))
	sessionMaid:GiveTask(dataRecoveryResultRemote.OnClientEvent:Connect(function(success: boolean, attempts: number, message: string)
		dataRecoveryRequestInFlight = false
		if typeof(attempts) == "number" and loadingDataRecoveryAttemptsLabel then
			loadingDataRecoveryAttemptsLabel.Text = string.format("ATTEMPTS: %d", math.max(0, math.floor(attempts)))
		end
		if success then
			setDataRecoveryFrameVisible(false)
			if localPlayer:GetAttribute("Data_Loaded") == true then
				runStartupLoading()
			end
			return
		end
		if loadingDataRecoveryWarningLabel and typeof(message) == "string" then
			loadingDataRecoveryWarningLabel.Text = message
		end
		setDataRecoveryFrameVisible(true, true)
	end))

	local function deferSessionCallback(callback: () -> ())
		sessionMaid:GiveTask(task.defer(function()
			if not isCleanedUp then
				callback()
			end
		end))
	end

	local function promptTrollProduct(actionName: string)
		if not canUseTrollFrame or not trollSelectedPlayer then
			return
		end

		trollActionRequestRemote:FireServer(actionName, trollSelectedPlayer.UserId)

		local id = ProductService.DevProducts.TrollPlayer
		if id and id ~= 0 then
			ProductService.promptProductPurchase(localPlayer, id)
		end
	end

	runStartupLoading = function()
		if not STARTUP_LOADING_ENABLED then
			hasCompletedStartupLoading = true
			loadingProgressFloor = 1
			setDataRecoveryFrameVisible(false)
			if loadingFrame then
				loadingFrame.Visible = false
				loadingFrame.Active = false
			end
			startupLoadingTask = nil
			root:SetAttribute("StartupLoadingComplete", true)
			return
		end

		if hasCompletedStartupLoading then
			if loadingFrame then
				loadingFrame.Visible = false
				loadingFrame.Active = false
			end
			setDataRecoveryFrameVisible(false)
			root:SetAttribute("StartupLoadingComplete", true)
			debugLoading("Startup loading skipped because it has already completed")
			return
		end

		if not loadingFrame then
			debugLoadingWarn("Startup loading skipped: LoadingFrame not found")
			return
		end

		loadingFrame.Visible = true
		loadingFrame.Active = true
		setDataRecoveryFrameVisible(false)
		if loadingImage then
			loadingImage.Position = UDim2.new(0.5, 0, 0.5, 0)
			loadingImage.Size = UDim2.new(0, 0, 0, 0)
			loadingImage.ImageTransparency = 0
			loadingImage.Visible = true
		end
		if loadingGameImage then
			loadingGameImage.Visible = false
		end
		if loadingLightRay then
			loadingLightRay.Visible = false
		end
		if loadingLevelsBarFrame then
			loadingLevelsBarFrame.Visible = false
		end
		if loadingSkipButtonFrame then
			loadingSkipButtonFrame.Visible = false
			loadingSkipButtonFrame.Active = false
		end
		lockLocalMovementForLoading()
		debugLoading("Startup loading started; waiting for Data_Loaded")

		startupLoadingTask = spawnSessionTask(function()
			local DATA_WAIT_TIMEOUT = 20
			local PRE_HIDE_HOLD_TIME = 0.5
			local STANDARD_FADE_DURATION = 1
			local waitStarted = os.clock()
			local delayedWarningShown = false
			while
				not isCleanedUp
				and localPlayer.Parent ~= nil
				and localPlayer:GetAttribute("Data_Loaded") ~= true
			do
				local dataLoadState = localPlayer:GetAttribute("Data_LoadState")
				if dataLoadState == "Unavailable" or dataLoadState == "RecoveryRequired" then
					debugLoadingWarn(
						"Data load entered a terminal state: " .. tostring(dataLoadState) .. "; keeping startup blocked"
					)
					if dataLoadState == "RecoveryRequired" then
						setDataRecoveryFrameVisible(true, true)
						updateLoadingProgress(loadingProgressFloor, "DATA RECOVERY REQUIRED")
					else
						setDataRecoveryFrameVisible(false)
						updateLoadingProgress(loadingProgressFloor, "DATA LOAD FAILED - PLEASE REJOIN")
					end
					return
				end

				if not delayedWarningShown and os.clock() - waitStarted >= DATA_WAIT_TIMEOUT then
					delayedWarningShown = true
					debugLoadingWarn(
						string.format("Data load is still pending after %.1fs; keeping startup blocked", os.clock() - waitStarted)
					)
					updateLoadingProgress(loadingProgressFloor, "DATA LOAD DELAYED - KEEPING DATA SAFE")
				end
				task.wait(0.1)
			end

			if isCleanedUp or localPlayer.Parent == nil or localPlayer:GetAttribute("Data_Loaded") ~= true then
				return
			end

			updateLoadingProgress(loadingProgressFloor, "DATA LOAD READY")
			debugLoading("Data load ready; playing final logo reveal")

			if loadingImage then
				local bounceTween = TweenService:Create(
					loadingImage,
					TweenConfig.LoadingLogoBounce,
					{
						Size = UDim2.new(0.54, 0, 0.54, 0),
					}
				)
				bounceTween:Play()
				bounceTween.Completed:Wait()

				local settleTween = TweenService:Create(
					loadingImage,
					TweenConfig.LoadingLogoSettle,
					{
						Size = UDim2.new(0.5, 0, 0.5, 0),
					}
				)
				settleTween:Play()
				settleTween.Completed:Wait()
			end

			task.wait(PRE_HIDE_HOLD_TIME)

			local finalFadeDuration = STANDARD_FADE_DURATION
			if loadingImage then
				tweenGuiFadeOut(loadingImage, finalFadeDuration)
			end
			if loadingFrame then
				tweenGuiFadeOut(loadingFrame, finalFadeDuration)
			end

			task.wait(finalFadeDuration)
			if loadingImage then
				loadingImage.Visible = false
			end
			loadingFrame.Visible = false
			loadingFrame.Active = false
			hasCompletedStartupLoading = true
			root:SetAttribute("StartupLoadingComplete", true)
			unlockLocalMovementForLoading()
			debugLoading("Startup loading finished and frame hidden")
			if startupLoadingTask == coroutine.running() then
				startupLoadingTask = nil
			end
		end)
	end

	local function checkInstance(instance: Instance)
		if instance:IsA("UIGradient") and instance.Name == "RainbowGradient" then
			VisualFunctions.SetupRainbowGradient(instance)
			return
		end

		if not instance:IsA("GuiObject") then
			return
		end
		if
			instance:IsA("CanvasGroup")
			and instance:FindFirstChild("Main")
			and instance:FindFirstChild("Shadow")
		then
			local canvasGroup = instance
			local function bindFrameShadowColorSync()
				VisualFunctions.BindFrameShadowColorSync(canvasGroup, sessionMaid)
			end
			sessionMaid:GiveTask(canvasGroup:GetAttributeChangedSignal("CreateFrameShadow"):Connect(bindFrameShadowColorSync))
			bindFrameShadowColorSync()
		end

		if instance.Name == "NotifShow_Template" then
			rebirthReadyUIState.template = instance
			kartPurchaseUIState.template = instance
			trailAffordableUIState.template = instance
			candyShopAffordableUIState.template = instance
			playtimeClaimableUIState.template = instance
			verifyClaimableUIState.template = instance
		elseif instance.Name == "RotateImage" and instance:FindFirstAncestor("CandyCountFrame") then
			candyShopAffordableUIState.buttonFrame = instance
			if candyShopAffordableUIState.refresh then
				deferSessionCallback(function()
					if candyShopAffordableUIState.refresh then
						candyShopAffordableUIState.refresh()
					end
				end)
			end
		elseif instance.Name == "RebirthButtonFrame" then
			rebirthReadyUIState.buttonFrame = instance
			local lightRay = instance:FindFirstChild("LightRay", true)
			if lightRay and lightRay:IsA("GuiObject") then
				rebirthReadyUIState.lightRay = lightRay
				lightRay.Visible = false
			end
			if rebirthReadyUIState.refresh then
				deferSessionCallback(function()
					if rebirthReadyUIState.refresh then
						rebirthReadyUIState.refresh()
					end
				end)
			end
		elseif instance.Name == "KartButtonFrame" then
			kartPurchaseUIState.buttonFrame = instance
			if kartPurchaseUIState.refresh then
				deferSessionCallback(function()
					if kartPurchaseUIState.refresh then
						kartPurchaseUIState.refresh()
					end
				end)
			end
		elseif instance.Name == "TrailButtonFrame" then
			trailAffordableUIState.buttonFrame = instance
			if trailAffordableUIState.refresh then
				deferSessionCallback(function()
					if trailAffordableUIState.refresh then
						trailAffordableUIState.refresh()
					end
				end)
			end
		elseif instance.Name == "PlaytimeButtonFrame" then
			playtimeClaimableUIState.buttonFrame = instance
			if playtimeClaimableUIState.refresh then
				deferSessionCallback(function()
					if playtimeClaimableUIState.refresh then
						playtimeClaimableUIState.refresh()
					end
				end)
			end
		elseif instance.Name == "VerifyButtonFrame" then
			verifyClaimableUIState.buttonFrame = instance
			if verifyClaimableUIState.refresh then
				deferSessionCallback(function()
					if verifyClaimableUIState.refresh then
						verifyClaimableUIState.refresh()
					end
				end)
			end
		end

		-- 1. Visual Effects & Animations
		if instance.Name == "DisableWaveButtonFrame" then
			VisualFunctions.HUD.DisableWaveButtonFrame = instance
			VisualFunctions.HUD.DisableWavePriceLabel = instance:FindFirstChild("PriceLabel", true) :: TextLabel?
			VisualFunctions.HUD.DisableWaveCountdownLabel =
				instance:FindFirstChild("CountdownLabel", true) :: TextLabel?
			if VisualFunctions.HUD.DisableWaveCountdownLabel then
				VisualFunctions.HUD.DisableWaveCountdownLabel.Visible = false
			end
			VisualFunctions.SetupPulsate(instance, 1.05)
		elseif instance.Name == "LoadingFrame" and instance:IsA("GuiObject") then
			loadingFrame = instance
			instance.Visible = STARTUP_LOADING_ENABLED and not hasCompletedStartupLoading
			instance.Active = STARTUP_LOADING_ENABLED
			loadingImage = instance:FindFirstChild("Image") :: ImageLabel?
			loadingGameImage = instance:FindFirstChild("GameImage", true) :: ImageLabel?
			loadingLightRay = instance:FindFirstChild("LightRay") :: ImageLabel?
			loadingLevelsBarFrame = instance:FindFirstChild("LevelsBarFrame") :: Frame?
			if loadingGameImage then
				loadingGameImage.Visible = false
			end
			if loadingLightRay then
				loadingLightRay.Visible = false
			end
			if loadingLevelsBarFrame then
				loadingLevelsBarFrame.Visible = false
			end
			loadingProgressFrame = loadingLevelsBarFrame
				and loadingLevelsBarFrame:FindFirstChild("ProgressFrame") :: Frame?
			loadingProgressLabel = loadingLevelsBarFrame
				and loadingLevelsBarFrame:FindFirstChild("ProgressLabel", true) :: TextLabel?
			if not loadingProgressLabel and loadingLevelsBarFrame then
				loadingProgressLabel = loadingLevelsBarFrame:FindFirstChild("XPSpeedLabel", true) :: TextLabel?
			end
			loadingCurrentLabel = loadingLevelsBarFrame
				and loadingLevelsBarFrame:FindFirstChild("CurrentLoadingLabel", true) :: TextLabel?
			loadingSkipButtonFrame = instance:FindFirstChild("SkipButton")
			if loadingSkipButtonFrame then
				loadingSkipButtonFrame.Visible = false
				loadingSkipButtonFrame.Active = false
			end
			loadingSkipButton = loadingSkipButtonFrame
				and loadingSkipButtonFrame:FindFirstChildWhichIsA("GuiButton", true)
			if loadingSkipButton then
				bindGuiButton(loadingSkipButton, "loadingSkip", function()
					if loadingSkipRequested then
						return
					end
					loadingSkipRequested = true
					hideLoadingSkipButton()
					updateLoadingProgress(0.9, formatLoadingLabel("Data Load", "Awaiting Server"))
				end)
			end

			local recoveryFrame = instance:FindFirstChild("DataRecoveryFrame")
			bindDataRecoveryFrame(if recoveryFrame and recoveryFrame:IsA("GuiObject") then recoveryFrame else nil)
		elseif instance.Name == "DataRecoveryFrame" and instance:IsA("GuiObject") then
			bindDataRecoveryFrame(instance)
		elseif instance.Name == "ReturnToStageFrame" and instance:IsA("GuiObject") then
			VisualFunctions.HUD.ReturnToStageFrame = instance
			local returnToStageButton = instance:FindFirstChild("ReturnToStageButton", true)
			if returnToStageButton then
				VisualFunctions.HUD.ReturnToStagePriceLabel =
					returnToStageButton:FindFirstChild("PriceLabel", true) :: TextLabel?
			end

			local rootCountdownLabel = instance:FindFirstChild("CountdownLabel")
			VisualFunctions.HUD.ReturnToStageCountdownLabel = if rootCountdownLabel
					and rootCountdownLabel:IsA("TextLabel")
				then rootCountdownLabel
				else instance:FindFirstChild("CountdownLabel", true) :: TextLabel?

			instance.Visible = false
			for _, descendant in ipairs(instance:GetDescendants()) do
				if descendant:IsA("GuiObject") then
					descendant.Visible = false
				end
			end

			if returnToStageButton and returnToStageButton:IsA("GuiObject") then
				VisualFunctions.SetupPulsate(returnToStageButton, 1.02)
			end

			local watchAdFrame = instance:FindFirstChild("WatchAdButton", true)
			local watchAdButton = watchAdFrame and watchAdFrame:FindFirstChildWhichIsA("GuiButton", true)
			if watchAdButton then
				bindGuiButton(watchAdButton, "returnToStageRewardedAd", function()
					if not instance.Visible then
						return
					end

					if RewardedVideoClient.Request("ReturnToStage") then
						watchAdButton.Active = false
						watchAdButton.Interactable = false
					end
				end)

					sessionMaid:GiveTask(
						RewardedVideoClient.ConnectResult(
							function(placementName: string, completed: boolean, resultName: string)
								if placementName ~= "ReturnToStage" then
									return
								end

								if completed then
									hideReturnToStageFrame()
								elseif resultName == "Error" then
									applyReturnToStageAdLayout(instance, false)
								else
									watchAdButton.Active = true
									watchAdButton.Interactable = true
							end
						end
					)
				)

			end

			applyReturnToStageAdLayout(instance, false)
		elseif instance.Name == "StarterPackButtonFrame" then
			local packImage = instance:FindFirstChild("PackImage", true)
			if packImage and packImage:IsA("GuiObject") then
				VisualFunctions.SetupPulsate(packImage, 1.08)
			end
		elseif instance.Name == "MultiplierSpeedProductButtonFrame" then
			local gradient = instance:FindFirstChildOfClass("UIGradient")
			if gradient then
				VisualFunctions.SetupRainbowGradient(gradient)
			end
		elseif instance.Name == "LightRay" then
			VisualFunctions.SetupLightRay(instance)
		elseif instance.Name == "WaveImage" then
			VisualFunctions.SetupPulsate(instance, 1.2)
		elseif instance.Name == "RainbowLightning" then
			local gradient = instance:FindFirstChildOfClass("UIGradient")
			if gradient then
				VisualFunctions.SetupRotatingGradient(gradient)
			end
		end

		-- 2. Specialized Mapping (Prioritize Specific Names/Classes)
		if instance:IsA("TextLabel") then
			if instance.Name == "XPSpeedLabel" and not isInsideLoadingFrame(instance) then
				VisualFunctions.Labels.XPSpeedLabel = instance
			elseif instance.Name == "CurrentLevelLabel" then
				VisualFunctions.Labels.CurrentLevelLabel = instance
			elseif instance.Name == "RebirthMultiLabel" then
				VisualFunctions.Labels.RebirthMultiLabel = instance
			elseif instance.Name == "TrailMultiplier" then
				VisualFunctions.Labels.TrailMultiplierLabel = instance
			elseif instance.Name == "FriendMultiplier"
				or (
					instance.Name == "Multiplier"
					and instance.Parent ~= nil
					and (instance.Parent.Name == "FriendMultiplier" or instance.Parent.Name == "FriendMultiplierFrame")
				)
			then
				VisualFunctions.Labels.FriendMultiplierLabel = instance
			elseif instance.Name == "XPAllSpeedLabel" then
				VisualFunctions.Labels.XPAllSpeedLabel = instance
			elseif instance.Name == "LevelNeededLabel" then
				VisualFunctions.Labels.LevelNeededLabel = instance
			elseif instance.Name == "BeforeMultiplierLabel" then
				VisualFunctions.Labels.BeforeMultiplierLabel = instance
			elseif instance.Name == "BeforeMaxLevelLabel" then
				VisualFunctions.Labels.BeforeMaxLevelLabel = instance
			elseif instance.Name == "AfterMultiplierLabel" then
				VisualFunctions.Labels.AfterMultiplierLabel = instance
			elseif instance.Name == "AfterMaxLevelLabel" then
				VisualFunctions.Labels.AfterMaxLevelLabel = instance
			elseif instance.Name == "LevelBeforeLabel" then
				VisualFunctions.Labels.LevelBeforeLabel = instance
			elseif instance.Name == "LevelAfterLabel" then
				VisualFunctions.Labels.LevelAfterLabel = instance
			elseif instance.Name == "WalkspeedBeforeLabel" then
				VisualFunctions.Labels.WalkspeedBeforeLabel = instance
			elseif instance.Name == "WalkspeedAfterLabel" then
				VisualFunctions.Labels.WalkspeedAfterLabel = instance
			elseif instance.Name == "TextLabel" and instance.Parent and instance.Parent.Name == "NotificationFrame" then
				VisualFunctions.Labels.NotificationTextLabel = instance
				if tutorialSystem then
					tutorialSystem:RefreshNotificationReferences()
				end
			elseif instance.Name == "MaxSpeedLabel" then
				VisualFunctions.Labels.MaxSpeedLabel = instance
			elseif instance.Name == "WinsLabel" then
				VisualFunctions.Labels.WinsLabel = instance
			elseif instance.Name == "GroupCountdownLabel" and instance:FindFirstAncestor("VerifyFrame") ~= nil then
				verifyGroupCountdownLabel = instance
				verifyGroupCountdownLabel.Visible = false
				if refreshVerifyCountdownLabel then
					deferSessionCallback(function()
						if refreshVerifyCountdownLabel then
							refreshVerifyCountdownLabel()
						end
					end)
				end
			elseif instance.Name == "WhenRewardLabel" and instance:FindFirstAncestor("VerifyFrame") ~= nil then
				verifyRewardWhenLabel = instance
				if refreshVerifyRewardValueLabels then
					deferSessionCallback(function()
						if refreshVerifyRewardValueLabels then
							refreshVerifyRewardValueLabels()
						end
					end)
				end
			elseif
				instance.Name == "XPRewardsLabel"
				and instance:FindFirstAncestor("GroupRewardsClaimableFrame") ~= nil
			then
				verifyRewardXPLabel = instance
				if refreshVerifyRewardValueLabels then
					deferSessionCallback(function()
						if refreshVerifyRewardValueLabels then
							refreshVerifyRewardValueLabels()
						end
					end)
				end
			elseif
				instance.Name == "WinRewardsLabel"
				and instance:FindFirstAncestor("GroupRewardsClaimableFrame") ~= nil
			then
				verifyRewardWinsLabel = instance
				if refreshVerifyRewardValueLabels then
					deferSessionCallback(function()
						if refreshVerifyRewardValueLabels then
							refreshVerifyRewardValueLabels()
						end
					end)
				end
			end
		elseif instance:IsA("TextButton") then
			local name = string.lower(instance.Name)
			local parentName = if instance.Parent then string.lower(instance.Parent.Name) else ""

			if name == "100kbuybutton" or parentName == "100kbuybutton" then
				VisualFunctions.Labels.Xp100KValueLabel = instance
				DebugModule.debugPrint("Mapped Xp100KValueLabel: " .. instance:GetFullName(), "MainOrchestrator")
			elseif name == "1mbuybutton" or parentName == "1mbuybutton" then
				VisualFunctions.Labels.Xp1MValueLabel = instance
				DebugModule.debugPrint("Mapped Xp1MValueLabel: " .. instance:GetFullName(), "MainOrchestrator")
			elseif name == "10mbuybutton" or parentName == "10mbuybutton" then
				VisualFunctions.Labels.Xp10MValueLabel = instance
				DebugModule.debugPrint("Mapped Xp10MValueLabel: " .. instance:GetFullName(), "MainOrchestrator")
			end
		end

		-- 3. Frame & HUD References
		if instance.Name == "RebirthFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.RebirthFrame = instance
			instance.Visible = false
		elseif instance.Name == "TrailFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.TrailFrame = instance
			instance.Visible = false
		elseif instance.Name == "KartFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.KartFrame = instance
			instance.Visible = false
		elseif instance.Name == "VerifyFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.VerifyFrame = instance
			instance.Visible = false
		elseif instance.Name == "TrollFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.TrollFrame = instance
			instance.Visible = false
			trollFrame = instance

			-- Rule #3.13: Event-driven visibility handling
			sessionMaid:GiveTask(trollFrame:GetPropertyChangedSignal("Visible"):Connect(function()
				if trollFrame and trollFrame.Visible then
					localPlayer:SetAttribute("Ui_TrollFrameOpen", true)
					lockLocalMovementForTrollFrame()
					startTrollSpectate()
				else
					localPlayer:SetAttribute("Ui_TrollFrameOpen", false)
					stopTrollSpectate()
					unlockLocalMovementForTrollFrame()
				end
			end))

			local playerInfoFrame = instance:FindFirstChild("PlayerInfoFrame", true)
			trollNameLabel = if playerInfoFrame
				then playerInfoFrame:FindFirstChild("TextLabel", true) :: TextLabel?
				else nil
			local previousButtonFrame = instance:FindFirstChild("PreviousPlayerButton", true)
			if previousButtonFrame then
				trollPreviousButton = previousButtonFrame:FindFirstChildWhichIsA("GuiButton", true)
			end
			local nextButtonFrame = instance:FindFirstChild("NextPlayerButton", true)
			if nextButtonFrame then
				trollNextButton = nextButtonFrame:FindFirstChildWhichIsA("GuiButton", true)
			end
			if not canUseTrollFrame then
				instance.Visible = false
			end
		elseif instance.Name == "JumpscareImage" and instance:IsA("ImageLabel") then
			jumpscareImage = instance
			instance.Visible = false
		elseif instance.Name == "PetFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.PetFrame = instance
			instance.Visible = false
		elseif instance.Name == "ShopFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.ShopFrame = instance
			instance.Visible = false
		elseif instance.Name == "CandyShopFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.CandyShopFrame = instance
			instance.Visible = false
		elseif instance.Name == "RebirthConfirmFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.RebirthConfirmFrame = instance
			instance.Visible = false
		elseif instance.Name == "RewardsFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.RewardsFrame = instance
			instance.Visible = false
		elseif instance.Name == "DailyRewardFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.DailyRewardFrame = instance
			instance.Visible = false
		elseif instance.Name == "SpinWheelFrame" and instance:IsA("GuiObject") then
			VisualFunctions.ActiveFrameGroup.SpinWheelFrame = instance
			instance.Visible = false
		elseif instance.Name == "MainHUD" then
			VisualFunctions.HUD.MainHUD = instance
		elseif instance.Name == "X2WinPromptButton" then
			VisualFunctions.HUD.X2WinPromptButton = instance
		elseif instance.Name == "MultiplierSpeedProductFrame_Parent" then
			VisualFunctions.HUD.MultiplierSpeedProductFrame_Parent = instance
			VisualFunctions.HUD.MultiplierSpeedPriceLabel = instance:FindFirstChild("PriceLabel", true) :: TextLabel?

			local btnFrame = instance:FindFirstChild("MultiplierSpeedProductButtonFrame", true)
			if btnFrame then
				VisualFunctions.HUD.MultiplierSpeedPromptButton = btnFrame:FindFirstChildWhichIsA("GuiButton", true)
			end
		elseif instance.Name == "CustomSpeedFrame" then
			VisualFunctions.HUD.CustomSpeedFrame = instance
		elseif instance.Name == "LevelUpFrame" then
			VisualFunctions.HUD.LevelUpFrame = instance
			instance.Visible = false
		elseif instance.Name == "NotificationFrame" and instance:IsA("GuiObject") then
			VisualFunctions.HUD.NotificationFrame = instance
			instance.Visible = false
			VisualFunctions.BindNotificationVisibilityGuard(instance, sessionMaid)
			if tutorialSystem then
				tutorialSystem:RefreshNotificationReferences()
			end
		elseif instance.Name == "StageProgressFrame" and instance:IsA("GuiObject") then
			stageProgressState.frame = instance
			stageProgressState.trackFrame = instance:FindFirstChild("TrackFrame", true) :: Frame?
			stageProgressState.markersFrame = stageProgressState.trackFrame
				and stageProgressState.trackFrame:FindFirstChild("Markers") :: Frame?
			stageProgressState.currentStageLabel = instance:FindFirstChild("CurrentStageLabel", true) :: TextLabel?
			stageProgressState.currentWorldLabel = (
				instance:FindFirstChild("CurrentWorldLabel", true)
				or instance:FindFirstChild("CurrentWORLDLabel", true)
				or instance:FindFirstChild("CurrentWorld", true)
			) :: TextLabel?
			stageProgressState.markerTemplate = stageProgressState.trackFrame
				and stageProgressState.trackFrame:FindFirstChild("StageMarkerTemplate") :: GuiObject?
			stageProgressState.avatarTemplate = stageProgressState.trackFrame
				and stageProgressState.trackFrame:FindFirstChild("AvatarImageTemplate") :: ImageLabel?
			if stageProgressState.markerTemplate then
				stageProgressState.markerTemplate.Visible = false
			end
			if stageProgressState.avatarTemplate then
				stageProgressState.avatarTemplate.Visible = false
			end
		elseif instance.Name == "LevelsBarFrame" and not isInsideLoadingFrame(instance) then
			local pg = instance:FindFirstChild("ProgressFrame", true)
			if pg and pg:IsA("Frame") then
				if instance.Parent and instance.Parent.Name == "RebirthFrame" then
					VisualFunctions.HUD.LevelProgressFrame = pg
				else
					VisualFunctions.HUD.XPProgressFrame = pg
					VisualFunctions.HUD.LevelsBarFrame = instance
				end
			end
		elseif instance.Name == "SpeedMultiFrame" then
			VisualFunctions.HUD.SpeedMultiFrame = instance
		elseif instance.Name == "BottomRightGridFrame" and instance:IsA("GuiObject") then
			VisualFunctions.HUD.BottomRightGridFrame = instance
		elseif instance.Name == "SpeedBuyFrame" then
			VisualFunctions.HUD.SpeedBuyFrame = instance
		elseif instance.Name == "RightSideButtonsFrame" then
			VisualFunctions.HUD.RightSideButtonsFrame = instance
		elseif instance.Name == "FloatingFrame" then
			VisualFunctions.HUD.FloatingFrame = instance
		elseif instance.Name == "Float_CurrentSpeedFrame" then
			VisualFunctions.HUD.Float_CurrentSpeedFrame = instance
			instance.Visible = false
		elseif instance.Name == "Float_CurrentBloodMoonWinFrame" then
			VisualFunctions.HUD.Float_CurrentBloodMoonWinFrame = instance
			instance.Visible = false
		elseif instance.Name == "WinCountFrame" then
			VisualFunctions.HUD.WinCountFrame = instance
		elseif instance.Name == "Float_CurrentWinFrame" then
			VisualFunctions.HUD.Float_CurrentWinFrame = instance
			instance.Visible = false
		elseif instance.Name == "CurrentWins" and instance:IsA("GuiObject") then
			local eventProgress = instance:FindFirstAncestor("EventProgress")
			if eventProgress then
				VisualFunctions.HUD.EventCurrentWinsTarget = instance
			end
		elseif instance.Name == "X2WinProductFrame_Parent" then
			VisualFunctions.HUD.X2WinProductFrame_Parent = instance
			VisualFunctions.HUD.X2WinPriceLabel = instance:FindFirstChild("PriceLabel", true) :: TextLabel?
			VisualFunctions.HUD.X2WinPromptButton = instance:FindFirstChildWhichIsA("GuiButton", true)
		elseif instance.Name == "CustomSpeedTextBoxFrame" then
			local textBox = instance:FindFirstChildOfClass("TextBox")
			if textBox then
				VisualFunctions.HUD.CustomSpeedTextBox = textBox
				local player = Players.LocalPlayer
				if player then
					textBox.PlaceholderText = tostring(PlayerHandler.GetEffectiveMaxPlayerSpeed(player))
					textBox.Text = tostring(PlayerHandler.GetEffectiveWalkSpeed(player))
				end
				bindGuiSignal(
					textBox,
					"customSpeedFocused",
					textBox.Focused:Connect(function()
						textBox.PlaceholderText = tostring(PlayerHandler.GetEffectiveMaxPlayerSpeed(player))
						textBox.Text = tostring(player:GetAttribute("Player_Speed") or DEFAULT_PLAYER_SPEED)
					end)
				)
				bindGuiSignal(
					textBox,
					"customSpeedFocusLost",
					textBox.FocusLost:Connect(function(enterPressed)
						if not enterPressed then
							textBox.PlaceholderText = tostring(PlayerHandler.GetEffectiveMaxPlayerSpeed(player))
							textBox.Text = tostring(PlayerHandler.GetEffectiveWalkSpeed(player))
							return
						end
						local val = tonumber(textBox.Text)
						if val then
							local SpeedAction = ReplicatedStorage.Remotes:FindFirstChild("SpeedAction")
							if SpeedAction and SpeedAction:IsA("RemoteEvent") then
								SpeedAction:FireServer(val)
							end
						end
						sessionMaid:GiveTask(task.delay(0.1, function()
							if not isCleanedUp and textBox.Parent then
								textBox.PlaceholderText = tostring(PlayerHandler.GetEffectiveMaxPlayerSpeed(player))
								textBox.Text = tostring(PlayerHandler.GetEffectiveWalkSpeed(player))
							end
						end))
					end)
				)
			end
		end

		-- 4. Hover & Click Interactions
		local hudButtonStyle = ColorConfig.UI.HudButtonStyles[instance.Name]
		if hudButtonStyle and instance:IsA("GuiObject") then
			applyGradientStyle(instance, hudButtonStyle)
		end

		local hoverAttr = instance:GetAttribute("isHover")
		local isPetInteractionFrame = PET_INTERACTION_FRAME_NAMES[instance.Name] == true
			and instance:FindFirstAncestor("PetFrame") ~= nil
		if
			(hoverAttr ~= nil or isPetInteractionFrame)
			and instance.Name ~= "TempSpeedBoostBuyFrame"
			and instance.Name ~= "TempWinBoostBuyFrame"
			and instance.Name ~= "WinStreak"
		then
			VisualFunctions.SetupFrameHover(instance, 1.1, 15, 1.5)
			local hasButton = instance:IsA("GuiButton")
				or instance:FindFirstChildWhichIsA("GuiButton", true) ~= nil
			if hasButton then
				VisualFunctions.SetupFrameClick(instance, 0.95, -15, 0.75)
			end
		end

		local purchaseButtonNames = {
			RebirthButton = true,
			SkipRebirthButton = true,
			VerifyButton = true,
			["100KBuyButton"] = true,
			["1MBuyButton"] = true,
			["10MBuyButton"] = true,
			MultiplierSpeedProductButtonFrame = true,
			DisableWaveButtonFrame = true,
			ReturnToStageButton = true,
			AdvancedTankButton = true,
			ShoppingKartButton = true,
			FormulaCarButton = true,
			["3xTreadmillButton"] = true,
			["15xTreadmillButton"] = true,
			["35xTreadmillButton"] = true,
			["100xTreadmillButton"] = true,
			["2xWinButton"] = true,
			VIPButton = true,
			StarterPackButtonFrame = true,
			["1000WinButton"] = true,
			["5000WinButton"] = true,
			["10000WinButton"] = true,
			SpinWheelButtonFrame = true,
		}

		-- Toggle Buttons Handling
		local toggleMap = {
			RebirthButtonFrame = "RebirthFrame",
			ShopButtonFrame = "ShopFrame",
			TrailButtonFrame = "TrailFrame",
			KartButtonFrame = "KartFrame",
			VerifyButtonFrame = "VerifyFrame",
			TrollButtonFrame = "TrollFrame",
			PlaytimeButtonFrame = "RewardsFrame",
			DailyRewardButtonFrame = "DailyRewardFrame",
			PetsButtonFrame = "PetFrame",
		}
		if instance.Name == "TrollButtonFrame" then
			trollButtonFrame = instance
			if not canUseTrollFrame then
				instance.Visible = false
				instance.Interactable = false
			end
		end
		local targetFrameName = toggleMap[instance.Name]
		local genericButton = if instance:IsA("GuiButton")
			then instance
			else instance:FindFirstChildWhichIsA("GuiButton", true)
		if
			genericButton
			and not targetFrameName
			and instance.Name ~= "CustomSpeedButtonFrame"
			and instance.Name ~= "ExitButton"
			and not (genericButton.Parent and genericButton.Parent.Name == "ExitButton")
			and not purchaseButtonNames[instance.Name]
			and not instance:FindFirstAncestor("KartFrame")
			and not instance:FindFirstAncestor("TrailFrame")
			and not (instance.Name == "RotateImage" and instance:FindFirstAncestor("CandyCountFrame"))
		then
			bindGuiButton(genericButton, "genericClick", function()
				SoundService.PlayGuiSound("Click")
			end)
		end
		if instance.Name == "RotateImage" and instance:FindFirstAncestor("WinCountFrame") then
			WinCountShopShortcut.Bind(instance, sessionMaid)
		end
		if instance.Name == "RotateImage" and instance:FindFirstAncestor("CandyCountFrame") then
			local button = if instance:IsA("GuiButton")
				then instance
				else instance:FindFirstChildWhichIsA("GuiButton", true)
			if button then
				bindGuiButton(button, "toggle:CandyShopFrame", function()
					local targetFrame = VisualFunctions.ActiveFrameGroup.CandyShopFrame
					local liveEventState = ReplicatedStorage:FindFirstChild("LiveEventState")
					if
						not targetFrame
						or not liveEventState
						or liveEventState:GetAttribute("HalloweenPartTwoActive") ~= true
					then
						return
					end
					SoundService.PlayGuiSound(if targetFrame.Visible then "Close" else "Click")
					MainFunctions.ToggleFrame("CandyShopFrame")
				end)
			end
		end

		if targetFrameName then
			local button = if instance:IsA("GuiButton")
				then instance
				else instance:FindFirstChildWhichIsA("GuiButton", true)
			if button then
				bindGuiButton(button, "toggle:" .. targetFrameName, function()
					if targetFrameName == "TrollFrame" and not canUseTrollFrame then
						return
					end

					local targetFrame = VisualFunctions.ActiveFrameGroup[targetFrameName]
					if targetFrameName == "TrollFrame" and not (targetFrame and targetFrame.Visible) then
						hideReturnToStageFrame()
					end
					local soundName = if targetFrame and targetFrame.Visible then "Close" else "Click"
					SoundService.PlayGuiSound(soundName)
					MainFunctions.ToggleFrame(targetFrameName)
				end)
			end
		end

		if instance.Name == "CustomSpeedButtonFrame" then
			local button = if instance:IsA("GuiButton")
				then instance
				else instance:FindFirstChildWhichIsA("GuiButton", true)
			if button then
				bindGuiButton(button, "customSpeed", function()
					local frame = VisualFunctions.HUD.CustomSpeedFrame
					if frame then
						if frame.Visible then
							SoundService.PlayGuiSound("Close")
							VisualFunctions.CloseWindow(frame)
						else
							SoundService.PlayGuiSound("Click")
							VisualFunctions.OpenWindow(frame)
						end
					end
				end)
			end
		end

		if
			instance.Name == "ExitButton"
			and instance.Parent
			and instance.Parent:IsA("GuiObject")
			and instance.Parent.Name ~= "SpinWheelFrame"
			and instance.Parent.Name ~= "PromptBuyProductsFrame"
			and not instance:FindFirstAncestor("OpenLuckyBlockFrame")
		then
			local targetParent = instance.Parent :: GuiObject
			local button = if instance:IsA("GuiButton")
				then instance
				else instance:FindFirstChildWhichIsA("GuiButton", true)
			if button and button.Parent == instance then
				bindGuiButton(button, "exit", function()
					SoundService.PlayGuiSound("Close")
					if targetParent.Name == "ReturnToStageFrame" then
						hideReturnToStageFrame()
					elseif targetParent.Name == "TrollFrame" then
						MainFunctions.SetFrameVisibleSimple("TrollFrame", false)
						stopTrollSpectate()
					else
						VisualFunctions.CloseWindow(targetParent)
					end
				end)
			end
		end

		if instance.Name == "PreviousPlayerButton" then
			local button = instance:FindFirstChildWhichIsA("GuiButton", true)
			if button then
				trollPreviousButton = button
				bindGuiButton(button, "trollNav", function()
					SoundService.PlayGuiSound("Click")
					cycleTrollTarget(-1)
				end)
			end
		elseif instance.Name == "NextPlayerButton" then
			local button = instance:FindFirstChildWhichIsA("GuiButton", true)
			if button then
				trollNextButton = button
				bindGuiButton(button, "trollNav", function()
					SoundService.PlayGuiSound("Click")
					cycleTrollTarget(1)
				end)
			end
		elseif
			instance.Name == "FreezeButton"
			or instance.Name == "SlowButton"
			or instance.Name == "KillButton"
			or instance.Name == "JumpscareButton"
		then
			local button = instance:FindFirstChildWhichIsA("GuiButton", true)
			if button then
				trollActionButtons[instance.Name] = button
				bindGuiButton(button, "trollAction", function()
					SoundService.PlayGuiSound("Click")
					local actionName = if instance.Name == "FreezeButton"
						then "Freeze"
						elseif instance.Name == "SlowButton" then "Slow"
						elseif instance.Name == "KillButton" then "Kill"
						else "Jumpscare"
					promptTrollProduct(actionName)
				end)
			end
		end

		-- 5. Specialized Interaction Connections (Purchases)
		if purchaseButtonNames[instance.Name] then
			local button: GuiButton? = if instance:IsA("GuiButton")
				then instance
				else instance:FindFirstChildWhichIsA("GuiButton", true)
			if button then
				if instance.Name == "RebirthButton" then
					bindGuiButton(button, "purchase", function()
						SoundService.PlayGuiSound("Click")
						local RebirthAction = ReplicatedStorage.Remotes:FindFirstChild("RebirthAction")
						if RebirthAction and RebirthAction:IsA("RemoteEvent") then
							RebirthAction:FireServer()
						end
					end)
				elseif instance.Name == "SkipRebirthButton" then
					bindGuiButton(button, "purchase", function()
						SoundService.PlayGuiSound("Click")
						local skipId = ProductService.DevProducts.SkipRebirth
						if skipId and skipId ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, skipId)
						end
					end)
				elseif instance.Name == "100KBuyButton" then
					bindGuiButton(button, "purchase", function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+100K"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "1MBuyButton" then
					bindGuiButton(button, "purchase", function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+1M"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "10MBuyButton" then
					bindGuiButton(button, "purchase", function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+10M"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "1000WinButton" then
					bindGuiButton(button, "purchase", function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+1000"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "5000WinButton" then
					bindGuiButton(button, "purchase", function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+5000"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "10000WinButton" then
					bindGuiButton(button, "purchase", function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+10000"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "MultiplierSpeedProductButtonFrame" then
					bindGuiButton(button, "purchase", function()
						SoundService.PlayGuiSound("Click")
						local currentMult = Players.LocalPlayer:GetAttribute("DevProduct_XPSpeedMultiplier") or 1
						local nextMultName = ProductService.MULTIPLIER_TO_PRODUCT[currentMult]
						if nextMultName then
							local id = ProductService.DevProducts[nextMultName]
							if id and id ~= 0 then
								ProductService.promptProductPurchase(Players.LocalPlayer, id)
							end
						end
					end)
				elseif instance.Name == "DisableWaveButtonFrame" then
					bindGuiButton(button, "purchase", function()
						local cooldownEnd = Players.LocalPlayer:GetAttribute("DisableWavesCooldownEnd")
						local isOnCooldown = typeof(cooldownEnd) == "number" and cooldownEnd > os.time()
						if isOnCooldown or disableWavePurchaseInFlight then
							return
						end

						local id = ProductService.DevProducts.DisableWaves
						if id and id ~= 0 then
							SoundService.PlayGuiSound("Click")
							local promptStarted = ProductService.promptProductPurchase(Players.LocalPlayer, id)
							if not promptStarted then
								updateDisableWaveButtonInteraction()
								return
							end

							cancelDisableWavePurchaseWatchdog()
							disableWavePurchaseInFlight = true
							local purchaseAttempt = disableWavePurchaseAttempt
							updateDisableWaveButtonInteraction()
							disableWavePurchaseWatchdogTask = task.spawn(function()
								task.wait(DISABLE_WAVE_PURCHASE_WATCHDOG_SECONDS)
								if isCleanedUp or purchaseAttempt ~= disableWavePurchaseAttempt then
									return
								end

								disableWavePurchaseWatchdogTask = nil
								disableWavePurchaseInFlight = false
								updateDisableWaveButtonInteraction()
							end)
							sessionMaid:GiveTask(disableWavePurchaseWatchdogTask)
						end
					end)
				elseif instance.Name == "ReturnToStageButton" then
					bindGuiButton(button, "purchase", function()
						local character = Players.LocalPlayer.Character
						local humanoid = character and character:FindFirstChildOfClass("Humanoid")
						if not humanoid or humanoid.Health <= 0 then
							return
						end

						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts.ReturnToStage
						if id and id ~= 0 then
							returnToStagePromptOpenedRemote:FireServer()
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "VerifyButton" then
					if verifyGroupController then
						verifyGroupController:BindButton(button)
					end
				elseif SHOP_BUTTON_CONFIGS[instance.Name] then
					local shopConfig = SHOP_BUTTON_CONFIGS[instance.Name]
					bindGuiButton(button, "purchase", function()
						SoundService.PlayGuiSound("Click")
						if shopConfig.purchaseType == "gamepass" then
							ProductService.promptGamePassPurchase(localPlayer, shopConfig.itemId)
						else
							ProductService.promptProductPurchase(localPlayer, shopConfig.itemId)
						end
					end)
				end
			end
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		checkInstance(descendant)
	end
	sessionMaid:GiveTask(root.DescendantAdded:Connect(checkInstance))
	sessionMaid:GiveTask(MenuOpenController.new(root))

	local player = localPlayer
	if player then
		sessionMaid:GiveTask(bindPetInventoryNotifications(root, player, updateButtonNotificationBadge))
		sessionMaid:GiveTask(WinStreakUI.new(root, player))
		verifyGroupController = VerifyGroupController.new({
			player = player,
			groupId = if CoreConfig.social and typeof(CoreConfig.social.verifyGroupId) == "number"
				then CoreConfig.social.verifyGroupId
				else 13706307,
			remotes = remotes,
			sessionMaid = sessionMaid,
			spawnSessionTask = spawnSessionTask,
			showNotification = showNotificationRespectingTutorial,
		})
		verifyGroupController:BindAll(root)

		local pendingPurchasedKarts: { [string]: boolean } = {}
		local previousOwnedKarts: { [string]: boolean } = table.clone(PlayerHandler.GetOwnedKarts(player))
		local winDisplayController: any = nil
		local levelDisplayController: any = nil
		local hudDisplayController: any = nil
		local rewardCelebrationController = RewardCelebrationController.new({
			root = root,
			soundService = SoundService,
			coreConfig = CoreConfig,
		})
		sessionMaid:GiveTask(rewardCelebrationController)

		local function refreshRebirthReadyState()
			local currentLevel = player:GetAttribute("CurrentLevel") or 1
			local maxLevel = player:GetAttribute("MaxLevel") or 25
			local canRebirth = maxLevel > 0 and currentLevel >= maxLevel
			if rebirthReadyUIState.lightRay then
				rebirthReadyUIState.lightRay.Visible = canRebirth
			end

			updateRebirthReadyBadgeVisibility(canRebirth)
			if canRebirth and not rebirthReadyUIState.wasReady then
				local theme = VisualFunctions.NotificationThemes.Purple
				rebirthReadyUIState.notificationPending = not showNotificationRespectingTutorial(
					"YOU CAN NOW REBIRTH!",
					theme.textColor,
					theme.gradientBottomColor
				)
			elseif not canRebirth then
				rebirthReadyUIState.notificationPending = false
			end
			rewardCelebrationController:UpdateRebirthReady(canRebirth, rebirthReadyUIState.buttonFrame)

			rebirthReadyUIState.wasReady = canRebirth
		end
		rebirthReadyUIState.flushPending = function()
			if not rebirthReadyUIState.notificationPending then
				return
			end

			local currentLevel = player:GetAttribute("CurrentLevel") or 1
			local maxLevel = player:GetAttribute("MaxLevel") or 25
			if maxLevel <= 0 or currentLevel < maxLevel then
				rebirthReadyUIState.notificationPending = false
				return
			end

			local theme = VisualFunctions.NotificationThemes.Purple
			if showNotificationRespectingTutorial("YOU CAN NOW REBIRTH!", theme.textColor, theme.gradientBottomColor) then
				rebirthReadyUIState.notificationPending = false
			end
		end
		rebirthReadyUIState.refresh = refreshRebirthReadyState
		sessionMaid:GiveTask(function()
			rebirthReadyUIState.refresh = nil
			rebirthReadyUIState.wasReady = false
			rebirthReadyUIState.notificationPending = false
			rebirthReadyUIState.flushPending = nil
			rewardCelebrationController:UpdateRebirthReady(false, nil)
			updateRebirthReadyBadgeVisibility(false)
		end)
		local function countPendingPurchasedKarts(): number
			local count = 0
			for _ in pairs(pendingPurchasedKarts) do
				count += 1
			end
			return count
		end
		local function refreshKartPurchaseBadge()
			local pendingCount = countPendingPurchasedKarts()
			updateButtonNotificationBadge(
				kartPurchaseUIState,
				pendingCount > 0,
				"KartPurchaseNotification",
				tostring(pendingCount)
			)
		end
		local function resetKartPurchaseBadgeBaseline()
			previousOwnedKarts = table.clone(PlayerHandler.GetOwnedKarts(player))
			table.clear(pendingPurchasedKarts)
			refreshKartPurchaseBadge()
		end
		local function handleOwnedKartsChangedForBadge()
			local currentOwnedKarts = PlayerHandler.GetOwnedKarts(player)
			if
				player:GetAttribute("Data_Loaded") ~= true
				or player:GetAttribute("GamePassOwnershipSyncComplete") ~= true
			then
				previousOwnedKarts = table.clone(currentOwnedKarts)
				table.clear(pendingPurchasedKarts)
				refreshKartPurchaseBadge()
				return
			end
			local equippedKart = player:GetAttribute("Kart_Equipped")
			for kartName in pairs(currentOwnedKarts) do
				if currentOwnedKarts[kartName] == true and previousOwnedKarts[kartName] ~= true then
					if typeof(equippedKart) ~= "string" or equippedKart ~= kartName then
						pendingPurchasedKarts[kartName] = true
					end
				end
			end
			previousOwnedKarts = table.clone(currentOwnedKarts)
			refreshKartPurchaseBadge()
		end
		local function handleKartEquippedChangedForBadge()
			local equippedKart = player:GetAttribute("Kart_Equipped")
			if typeof(equippedKart) == "string" and pendingPurchasedKarts[equippedKart] == true then
				pendingPurchasedKarts[equippedKart] = nil
				refreshKartPurchaseBadge()
			end
		end
		kartPurchaseUIState.refresh = refreshKartPurchaseBadge
		sessionMaid:GiveTask(function()
			kartPurchaseUIState.refresh = nil
			table.clear(pendingPurchasedKarts)
			previousOwnedKarts = {}
			updateButtonNotificationBadge(kartPurchaseUIState, false, "KartPurchaseNotification", "0")
		end)
		local function countAffordableUnownedTrails(currentWins: number): number
			local ownedTrails = PlayerHandler.GetOwnedTrails(player)
			local affordableCount = 0
			for _, trailName in ipairs(PlayerHandler.TRAIL_ORDER) do
				local config = PlayerHandler.GetTrailConfig(trailName)
				if not config then
					continue
				end

				if not config.CanBuyWithWins then
					continue
				end

				local winsRequired = if typeof(config.WinsRequired) == "number" then config.WinsRequired else math.huge
				if ownedTrails[trailName] ~= true and currentWins >= winsRequired then
					affordableCount += 1
				end
			end

			return affordableCount
		end
		local function refreshAffordableTrailBadge()
			if player:GetAttribute("Data_Loaded") ~= true then
				updateButtonNotificationBadge(trailAffordableUIState, false, "TrailAffordableNotification", "0")
				return
			end

			local currentWins = player:GetAttribute("WinCount") or 0
			local affordableCount = countAffordableUnownedTrails(currentWins)
			updateButtonNotificationBadge(
				trailAffordableUIState,
				affordableCount > 0,
				"TrailAffordableNotification",
				tostring(affordableCount)
			)
		end
		trailAffordableUIState.refresh = refreshAffordableTrailBadge
		sessionMaid:GiveTask(function()
			trailAffordableUIState.refresh = nil
			updateButtonNotificationBadge(trailAffordableUIState, false, "TrailAffordableNotification", "0")
		end)
		local function setCandyShopLightRayVisible(isVisible: boolean)
			local buttonFrame = candyShopAffordableUIState.buttonFrame
			local lightRay = buttonFrame and buttonFrame:FindFirstChild("LightRay", true)
			if lightRay and lightRay:IsA("GuiObject") then
				lightRay.Visible = isVisible
			end
		end

		local function refreshAffordableCandyShopBadge()
			local eventState = ReplicatedStorage:FindFirstChild("LiveEventState")
			local eventAvailable = eventState ~= nil
				and eventState:GetAttribute("HalloweenPartTwoActive") == true
			if player:GetAttribute("Data_Loaded") ~= true or not eventAvailable then
				setCandyShopLightRayVisible(false)
				updateButtonNotificationBadge(candyShopAffordableUIState, false, "CandyShopAffordableNotification", "0")
				return
			end

			local candyValue = player:GetAttribute("HalloweenCandyCount")
			local candyCount = if typeof(candyValue) == "number" then math.max(0, math.floor(candyValue)) else 0
			local ownedKarts = PlayerHandler.GetOwnedKarts(player)
			local ownedTrails = PlayerHandler.GetOwnedTrails(player)
			local affordableCount = 0
			for _, product in ipairs(HalloweenCandyShopConfig.Products) do
				if product.candyPurchasable ~= false then
					local owned = if product.kind == "Kart"
						then ownedKarts[product.ownedName] == true
						elseif product.kind == "Trail"
						then ownedTrails[product.ownedName] == true
						else false
					if not owned and candyCount >= product.candyPrice then
						affordableCount += 1
					end
				end
			end
			local candyCostPerRoll = PetConfig.LuckyBlocks.Event.eventCandyPricePerRoll.Halloween
			if typeof(candyCostPerRoll) == "number" and candyCostPerRoll > 0 then
				for _, rollCount in ipairs({ 1, 3, 5 }) do
					if candyCount >= candyCostPerRoll * rollCount then
						affordableCount += 1
					end
				end
			end
			setCandyShopLightRayVisible(affordableCount > 0)
			updateButtonNotificationBadge(
				candyShopAffordableUIState,
				affordableCount > 0,
				"CandyShopAffordableNotification",
				tostring(affordableCount)
			)
		end
		candyShopAffordableUIState.refresh = refreshAffordableCandyShopBadge
		sessionMaid:GiveTask(function()
			candyShopAffordableUIState.refresh = nil
			setCandyShopLightRayVisible(false)
			updateButtonNotificationBadge(candyShopAffordableUIState, false, "CandyShopAffordableNotification", "0")
		end)
		for _, attributeName in ipairs({ "Data_Loaded", "HalloweenCandyCount", "OwnedKarts", "OwnedTrails" }) do
			sessionMaid:GiveTask(player:GetAttributeChangedSignal(attributeName):Connect(refreshAffordableCandyShopBadge))
		end
		local function bindCandyShopEventState(eventState: Instance)
			if not eventState:IsA("Folder") or eventState.Name ~= "LiveEventState" then
				return
			end
			sessionMaid:GiveTask(
				eventState:GetAttributeChangedSignal("HalloweenPartTwoActive"):Connect(refreshAffordableCandyShopBadge)
			)
			sessionMaid:GiveTask(
				eventState:GetAttributeChangedSignal("EnvironmentName"):Connect(refreshAffordableCandyShopBadge)
			)
			refreshAffordableCandyShopBadge()
		end
		local currentEventState = ReplicatedStorage:FindFirstChild("LiveEventState")
		if currentEventState then
			bindCandyShopEventState(currentEventState)
		end
		sessionMaid:GiveTask(ReplicatedStorage.ChildAdded:Connect(bindCandyShopEventState))
		refreshAffordableCandyShopBadge()
		local playtimeClaimableCount = 0
		local function refreshPlaytimeClaimableBadge()
			if player:GetAttribute("Data_Loaded") ~= true then
				updateButtonNotificationBadge(playtimeClaimableUIState, false, "PlaytimeClaimableNotification", "0")
				return
			end

			updateButtonNotificationBadge(
				playtimeClaimableUIState,
				playtimeClaimableCount > 0,
				"PlaytimeClaimableNotification",
				tostring(playtimeClaimableCount)
			)
		end
		local function handlePlaytimeClaimableCountChanged(claimableCount: number)
			playtimeClaimableCount = math.max(0, math.floor(claimableCount))
			refreshPlaytimeClaimableBadge()
		end
		playtimeClaimableUIState.refresh = refreshPlaytimeClaimableBadge
		sessionMaid:GiveTask(function()
			playtimeClaimableUIState.refresh = nil
			playtimeClaimableCount = 0
			updateButtonNotificationBadge(playtimeClaimableUIState, false, "PlaytimeClaimableNotification", "0")
		end)
		local function refreshVerifyClaimableBadge()
			if player:GetAttribute("Data_Loaded") ~= true then
				updateButtonNotificationBadge(verifyClaimableUIState, false, "VerifyClaimableNotification", "0")
				return
			end

			local rawNextClaimUnix = player:GetAttribute(VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE)
			local nextClaimUnix = if typeof(rawNextClaimUnix) == "number"
				then math.max(0, math.floor(rawNextClaimUnix))
				else 0
			local isClaimable = nextClaimUnix <= os.time()

			updateButtonNotificationBadge(
				verifyClaimableUIState,
				isClaimable,
				"VerifyClaimableNotification",
				if isClaimable then "1" else "0"
			)
		end
		verifyClaimableUIState.refresh = refreshVerifyClaimableBadge
		sessionMaid:GiveTask(function()
			verifyClaimableUIState.refresh = nil
			updateButtonNotificationBadge(verifyClaimableUIState, false, "VerifyClaimableNotification", "0")
		end)

		local productCache = {}
		stageProgressState.markerUpdateAccumulator = stageProgressState.markerUpdateInterval
		local verifyRewardCountdownAccumulator = VERIFY_REWARD_COUNTDOWN_UPDATE_INTERVAL
		local characterStateMaid: Maid? = nil
		local disableWaveCountdownThread = 0
		local returnToStageOfferThread = 0
		local returnToStageOfferTask: thread? = nil
		hideReturnToStageFrame = function()
			returnToStageOfferThread += 1
			if returnToStageOfferTask then
				if coroutine.status(returnToStageOfferTask) ~= "dead" then
					pcall(task.cancel, returnToStageOfferTask)
				end
				returnToStageOfferTask = nil
			end

			local frame = VisualFunctions.HUD.ReturnToStageFrame
			if frame then
				frame.Visible = false
				for _, descendant in ipairs(frame:GetDescendants()) do
					if descendant:IsA("GuiObject") then
						descendant.Visible = false
					end
				end

				local watchAdButton = frame:FindFirstChild("WatchAdButton", true)
				local watchAdTextButton = watchAdButton and watchAdButton:FindFirstChildWhichIsA("GuiButton", true)
				if watchAdTextButton then
					watchAdTextButton.Active = true
					watchAdTextButton.Interactable = true
				end
			end
		end
		sessionMaid:GiveTask(hideReturnToStageFrame)

		local function formatClockDuration(totalSeconds: number): string
			local clamped = math.max(0, math.floor(totalSeconds))
			local hours = math.floor(clamped / 3600)
			local minutes = math.floor((clamped % 3600) / 60)
			local seconds = clamped % 60
			return string.format("%02d:%02d:%02d", hours, minutes, seconds)
		end

		local function formatReturnToStageCountdown(totalSeconds: number): string
			local seconds = math.max(0, math.floor(totalSeconds))
			local unit = if seconds == 1 then "SECOND" else "SECONDS"
			return string.format("%d %s", seconds, unit)
		end

		local function getVerifyNextClaimUnixFromAttribute(): number
			local rawValue = player:GetAttribute(VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE)
			if typeof(rawValue) == "number" then
				return math.max(0, math.floor(rawValue))
			end

			return 0
		end

		local function updateVerifyRewardValueLabels()
			local rewardPreview = VerifyRewardCalculator.ComputeRewardsForNextClaim(player, verifyRewardConfig)

			if verifyRewardWhenLabel and verifyRewardWhenLabel.Parent then
				local cooldownSeconds = if CoreConfig.leveling
						and typeof(CoreConfig.leveling.verifyRewardCooldownSeconds) == "number"
					then math.max(1, CoreConfig.leveling.verifyRewardCooldownSeconds)
					else 24 * 60 * 60
				local rewardHours = math.max(1, math.round(cooldownSeconds / 3600))
				verifyRewardWhenLabel.Text = string.format("REWARD EVERY %d HOURS", rewardHours)
			end
			if verifyRewardXPLabel and verifyRewardXPLabel.Parent then
				verifyRewardXPLabel.Text = "+" .. VisualFunctions.FormatNumber(rewardPreview.xpAward) .. " Speed"
			end
			if verifyRewardWinsLabel and verifyRewardWinsLabel.Parent then
				verifyRewardWinsLabel.Text = "+" .. VisualFunctions.FormatNumber(rewardPreview.winsAward) .. " Wins"
			end
		end

		local function updateVerifyGroupCountdown(overrideNextClaimUnix: number?)
			local label = verifyGroupCountdownLabel
			if not label or label.Parent == nil then
				return
			end

			if player:GetAttribute("Data_Loaded") ~= true then
				label.Visible = false
				return
			end

			local nextClaimUnix = if typeof(overrideNextClaimUnix) == "number"
				then math.max(0, math.floor(overrideNextClaimUnix))
				else getVerifyNextClaimUnixFromAttribute()
			local remaining = math.max(0, nextClaimUnix - os.time())
			if remaining <= 0 then
				label.Visible = false
				return
			end

			label.Visible = true
			label.Text = "Available again in: " .. formatClockDuration(remaining)
		end

		refreshVerifyCountdownLabel = function()
			updateVerifyGroupCountdown(nil)
		end
		refreshVerifyRewardValueLabels = updateVerifyRewardValueLabels
		sessionMaid:GiveTask(function()
			refreshVerifyCountdownLabel = nil
			refreshVerifyRewardValueLabels = nil
		end)

		local function updateReturnToStagePrice()
			local priceLabel = VisualFunctions.HUD.ReturnToStagePriceLabel
			local id = ProductService.DevProducts.ReturnToStage
			if not priceLabel or not id or id == 0 then
				DebugModule.debugWarn(
					"ReturnToStage price update skipped: missing label or product id",
					"MainOrchestrator"
				)
				return
			end

			spawnSessionTask(function()
				if ProductService.IsLocalExperienceCreator(Players.LocalPlayer) then
					if VisualFunctions.HUD.ReturnToStagePriceLabel == priceLabel and priceLabel.Parent then
						priceLabel.Text = "FREE"
					end
					return
				end

				local info = productCache[id]
				if not info then
					local success, result = pcall(function()
						return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
					end)
					if success then
						info = result
						productCache[id] = result
					end
				end

				if info and priceLabel then
					if VisualFunctions.HUD.ReturnToStagePriceLabel ~= priceLabel or not priceLabel.Parent then
						return
					end
					priceLabel.Text = tostring(info.PriceInRobux or 0)
				end
			end)
		end

		local function getMarketplaceInfoCached(itemId: number, infoType: Enum.InfoType)
			local cacheKey = string.format("%s:%d", tostring(infoType.Value), itemId)
			local info = productCache[cacheKey]
			if info then
				return info
			end

			local success, result = pcall(function()
				return MarketplaceService:GetProductInfo(itemId, infoType)
			end)
			if success and typeof(result) == "table" then
				productCache[cacheKey] = result
				return result
			end

			DebugModule.debugWarn(
				string.format("Failed marketplace info lookup for %d (%s)", itemId, infoType.Name),
				"MainOrchestrator"
			)
			return nil
		end

		stageProgressState.disconnectTrackedPlayer = function(playerToDisconnect: Player)
			local playerMaid = stageProgressState.trackedPlayerMaids[playerToDisconnect]
			if playerMaid then
				playerMaid:DoCleaning()
				stageProgressState.trackedPlayerMaids[playerToDisconnect] = nil
			end

			local existingMarker = stageProgressState.playerMarkers[playerToDisconnect.UserId]
			if existingMarker and existingMarker.Parent then
				existingMarker:Destroy()
			end

			stageProgressState.playerMarkers[playerToDisconnect.UserId] = nil
			stageProgressState.playerMarkerMissingUntil[playerToDisconnect.UserId] = nil
			stageProgressState.avatarCache[playerToDisconnect.UserId] = nil
			stageProgressState.trackedRootParts[playerToDisconnect] = nil
		end

		stageProgressState.cacheRootPart = function(playerToTrack: Player): BasePart?
			local targetCharacter = playerToTrack.Character
			local rootCandidate = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
			if rootCandidate and rootCandidate:IsA("BasePart") then
				stageProgressState.trackedRootParts[playerToTrack] = rootCandidate
				return rootCandidate
			end

			stageProgressState.trackedRootParts[playerToTrack] = nil
			return nil
		end

		stageProgressState.connectTrackedPlayer = function(playerToTrack: Player)
			stageProgressState.disconnectTrackedPlayer(playerToTrack)

			local playerMaid = Maid.new()
			stageProgressState.trackedPlayerMaids[playerToTrack] = playerMaid
			stageProgressState.cacheRootPart(playerToTrack)
			playerMaid:GiveTask(playerToTrack.CharacterAdded:Connect(function()
				stageProgressState.cacheRootPart(playerToTrack)
				sessionMaid:GiveTask(task.defer(function()
					if not isCleanedUp then
						stageProgressState.updatePlayerMarkers()
					end
				end))
			end))
			playerMaid:GiveTask(playerToTrack.CharacterRemoving:Connect(function()
				stageProgressState.trackedRootParts[playerToTrack] = nil
				sessionMaid:GiveTask(task.defer(function()
					if not isCleanedUp then
						stageProgressState.updatePlayerMarkers()
					end
				end))
			end))
		end

		local function getNumericAttribute(instance: Instance?, attributeName: string): number?
			if not instance then
				return nil
			end

			local value = instance:GetAttribute(attributeName)
			if typeof(value) == "number" then
				return value
			end
			if typeof(value) == "string" then
				local parsed = tonumber(value)
				if parsed ~= nil then
					return parsed
				end
			end

			return nil
		end

		tutorialSystem = TutorialNotificationSystem.new({
			player = player,
			sessionMaid = sessionMaid,
			visualFunctions = VisualFunctions,
			soundService = SoundService,
			debugModule = DebugModule,
			tweenGuiFadeIn = tweenGuiFadeIn,
			tweenGuiFadeOut = tweenGuiFadeOut,
			spawnSessionTask = spawnSessionTask,
			isCleanedUp = function()
				return isCleanedUp
			end,
			getNumericAttribute = getNumericAttribute,
			playRewardCelebration = function()
				rewardCelebrationController:PlayRewardCelebration()
			end,
			onTutorialUnlocked = function()
				refreshRebirthReadyState()
				if rebirthReadyUIState.flushPending then
					rebirthReadyUIState.flushPending()
				end
			end,
		})
		tutorialSystem:RefreshNotificationReferences()
		local dailyClaimableUIState = {
			buttonFrame = root:FindFirstChild("DailyRewardButtonFrame", true) :: GuiObject?,
			template = root:FindFirstChild("NotifShow_Template", true) :: GuiObject?,
			badge = nil :: GuiObject?,
			refresh = nil :: (() -> ())?,
		}
		local dailyRewardPromptController = DailyRewardPromptController.new({
			player = player,
			badgeState = dailyClaimableUIState,
			updateButtonNotificationBadge = updateButtonNotificationBadge,
			getDailyRewardFrame = function(): GuiObject?
				return VisualFunctions.ActiveFrameGroup.DailyRewardFrame
			end,
			closeOtherFrames = MainFunctions.CloseOtherFrames,
			openWindow = VisualFunctions.OpenWindow,
			canAutoOpen = function(): boolean
				return hasCompletedStartupLoading
			end,
		})
		loadingMovementLockState.onLoadingComplete = function()
			if
				root:GetAttribute("PostLoadingStartupComplete") == true
				or isCleanedUp
				or root:GetAttribute("StartupLoadingComplete") ~= true
				or localPlayer:GetAttribute("Data_Loaded") ~= true
			then
				return
			end

			root:SetAttribute("PostLoadingStartupComplete", true)
			promptFavoriteGameIfReady()
			tutorialSystem:Start()
			tutorialSystem:OnProgressChanged()
			refreshAffordableTrailBadge()
			refreshPlaytimeClaimableBadge()
			dailyRewardPromptController:RefreshBadge()
			refreshVerifyClaimableBadge()
			updateVerifyRewardValueLabels()
			updateVerifyGroupCountdown(nil)
			if verifyGroupController then
				verifyGroupController:RefreshMembership()
			end
			dailyRewardPromptController:TryAutoOpen()
		end
		sessionMaid:GiveTask(
			root:GetAttributeChangedSignal("StartupLoadingComplete"):Connect(loadingMovementLockState.onLoadingComplete)
		)
		dailyClaimableUIState.refresh = function()
			dailyRewardPromptController:RefreshBadge()
		end
		sessionMaid:GiveTask(function()
			dailyRewardPromptController:Reset()
		end)
		local playtimeRewardsController = PlaytimeRewardsUI.new({
			player = player,
			root = root,
			onClaimableCountChanged = handlePlaytimeClaimableCountChanged,
		})
		sessionMaid:GiveTask(playtimeRewardsController)
		sessionMaid:GiveTask(DailyRewardsUI.new({
			player = player,
			root = root,
			onClaimableChanged = function(isClaimable: boolean)
				dailyRewardPromptController:HandleClaimableChanged(isClaimable)
			end,
		}))

		local function getKartShopStepsText(config): string?
			local kartModelName = config.kartModelName
			if typeof(kartModelName) ~= "string" or kartModelName == "" then
				return config.stepsText
			end

			local sourceFolderName = if typeof(config.sourceFolder) == "string"
				then config.sourceFolder
				else "Gamepasses"
			local kartModel = KartCatalog.FindModel(kartModelName, sourceFolderName, config.sourceSubfolder)
			local xpGain = getNumericAttribute(kartModel, "XP_Gain")
			if typeof(xpGain) == "number" then
				return string.format("+%s/Steps", tostring(math.round(xpGain)))
			end

			return config.stepsText
		end

		stageProgressState.getWorldData = function(worldName: string): (Instance?, BasePart?, BasePart?, Instance?)
			local worldsFolder = Workspace:FindFirstChild("Worlds")
			local world = worldsFolder and worldsFolder:FindFirstChild(worldName)
			if not world then
				return nil, nil, nil, nil
			end

			local lobbyRegionContainer = world:FindFirstChild("LobbyRegion_Model")
			local lobbyRegion = lobbyRegionContainer and lobbyRegionContainer:FindFirstChild("LobbyRegion", true)
			local terrainFolder = world:FindFirstChild("Terrain")
			local stageEnd = if terrainFolder
				then terrainFolder:FindFirstChild("StageEnd", true) :: BasePart?
				else world:FindFirstChild("StageEnd", true) :: BasePart?
			if not stageEnd and terrainFolder then
				local invisStuff = terrainFolder:FindFirstChild("InvisStuff")
				stageEnd = invisStuff and invisStuff:FindFirstChild("InvisEnd", true) :: BasePart?
			end
			local stagesFolder = world:FindFirstChild("Stages")

			if not lobbyRegion or not lobbyRegion:IsA("BasePart") then
				return world, nil, nil, stagesFolder
			end

			if not stageEnd or not stageEnd:IsA("BasePart") then
				return world, lobbyRegion, nil, stagesFolder
			end

			return world, lobbyRegion, stageEnd, stagesFolder
		end

		stageProgressState.formatWorldLabel = function(worldName: string?): string
			if typeof(worldName) ~= "string" or worldName == "" then
				return "World 0"
			end

			local worldNumber = string.match(worldName, "^World(%d+)$")
			if worldNumber then
				return "World " .. worldNumber
			end

			return worldName
		end

		stageProgressState.updateTrackStyle = function(worldName: string?)
			if not stageProgressState.trackFrame then
				return
			end

			local style = if typeof(worldName) == "string" and stageProgressState.worldStyles[worldName]
				then stageProgressState.worldStyles[worldName]
				else stageProgressState.worldStyles.Fallback

			stageProgressState.trackFrame.BackgroundColor3 = style.backgroundColor
		end

		stageProgressState.getTrackAlpha = function(
			startPosition: Vector3?,
			endPosition: Vector3?,
			worldPosition: Vector3?
		): number
			if
				typeof(startPosition) ~= "Vector3"
				or typeof(endPosition) ~= "Vector3"
				or typeof(worldPosition) ~= "Vector3"
			then
				return 0
			end

			local path = endPosition - startPosition
			local pathLength = path.Magnitude
			if pathLength <= 0.001 then
				return 0
			end

			local projectedDistance = (worldPosition - startPosition):Dot(path.Unit)
			return math.clamp(projectedDistance / pathLength, 0, 1)
		end

		stageProgressState.clearMarkers = function()
			for _, marker in ipairs(stageProgressState.markerClones) do
				marker:Destroy()
			end
			table.clear(stageProgressState.markerClones)
		end

		stageProgressState.clearPlayerMarkers = function()
			for _, marker in pairs(stageProgressState.playerMarkers) do
				marker:Destroy()
			end
			table.clear(stageProgressState.playerMarkers)
			table.clear(stageProgressState.playerMarkerMissingUntil)
		end

		stageProgressState.ensureAvatarMarker = function(targetPlayer: Player): ImageLabel?
			if not stageProgressState.trackFrame or not stageProgressState.avatarTemplate then
				return nil
			end

			local existing = stageProgressState.playerMarkers[targetPlayer.UserId]
			if existing and existing.Parent then
				return existing
			end

			local clone = stageProgressState.avatarTemplate:Clone()
			clone.Name = string.format("PlayerMarker_%d", targetPlayer.UserId)
			clone.Visible = true
			clone.Image = ""
			clone.ImageTransparency = 0
			clone.Parent = stageProgressState.trackFrame
			clone.ZIndex = if targetPlayer == player then 5 else 3
			local requestId = (clone:GetAttribute("StageProgressAvatarRequestId") or 0) :: number
			requestId += 1
			clone:SetAttribute("StageProgressAvatarRequestId", requestId)
			clone:SetAttribute("StageProgressAvatarUserId", targetPlayer.UserId)
			stageProgressState.playerMarkers[targetPlayer.UserId] = clone

			spawnSessionTask(function()
				local cachedImage = stageProgressState.avatarCache[targetPlayer.UserId]
				if not cachedImage then
					local success, content, _ = pcall(function()
						return Players:GetUserThumbnailAsync(
							targetPlayer.UserId,
							Enum.ThumbnailType.HeadShot,
							Enum.ThumbnailSize.Size100x100
						)
					end)
					if success and typeof(content) == "string" then
						cachedImage = content
						stageProgressState.avatarCache[targetPlayer.UserId] = content
					end
				end

				if
					cachedImage
					and clone.Parent
					and clone:GetAttribute("StageProgressAvatarRequestId") == requestId
					and clone:GetAttribute("StageProgressAvatarUserId") == targetPlayer.UserId
				then
					clone.Image = cachedImage
				end
			end)

			return clone
		end

		stageProgressState.rebuildMarkers = function()
			stageProgressState.clearMarkers()

			local currentWorld = player:GetAttribute("Current_World")
			if typeof(currentWorld) ~= "string" or currentWorld == "" then
				stageProgressState.worldName = nil
				stageProgressState.startPosition = nil
				stageProgressState.endPosition = nil
				if stageProgressState.currentWorldLabel then
					stageProgressState.currentWorldLabel.Text = "World 0"
				end
				return
			end

			stageProgressState.worldName = currentWorld
			stageProgressState.updateTrackStyle(currentWorld)
			if stageProgressState.currentWorldLabel then
				stageProgressState.currentWorldLabel.Text = stageProgressState.formatWorldLabel(currentWorld)
			end

			local _, lobbyRegion, stageEnd, stagesFolder = stageProgressState.getWorldData(currentWorld)
			if
				not lobbyRegion
				or not stagesFolder
				or not stageProgressState.trackFrame
				or not stageProgressState.markersFrame
				or not stageProgressState.markerTemplate
			then
				stageProgressState.startPosition = nil
				stageProgressState.endPosition = nil
				return
			end

			stageProgressState.startPosition = lobbyRegion.Position
			stageProgressState.endPosition = if stageEnd then stageEnd.Position else nil

			local stageEntries = {}
			for _, child in ipairs(stagesFolder:GetChildren()) do
				local stageNumber = child:GetAttribute("Stage")
				local stagePart = if child:IsA("BasePart")
					then child
					else child:FindFirstChildWhichIsA("BasePart", true)
				if typeof(stageNumber) == "number" and stagePart and stagePart:IsA("BasePart") then
					local alpha = stageProgressState.getTrackAlpha(
						stageProgressState.startPosition,
						stageProgressState.endPosition,
						stagePart.Position
					)
					table.insert(stageEntries, {
						stageNumber = stageNumber,
						position = stagePart.Position,
						alpha = alpha,
					})
				end
			end

			table.sort(stageEntries, function(a, b)
				return a.stageNumber < b.stageNumber
			end)

			if not stageProgressState.endPosition and #stageEntries > 0 then
				stageProgressState.endPosition = stageEntries[#stageEntries].position
			end

			if not stageProgressState.endPosition then
				stageProgressState.startPosition = nil
				return
			end

			local minimumSpacingScale = 0.015
			if stageProgressState.trackFrame.AbsoluteSize.X > 0 then
				minimumSpacingScale = math.max(
					minimumSpacingScale,
					stageProgressState.markerTemplate.AbsoluteSize.X / stageProgressState.trackFrame.AbsoluteSize.X
				)
			end

			local adjustedAlphas = table.create(#stageEntries)
			for index, stageEntry in ipairs(stageEntries) do
				local alpha = stageEntry.alpha
				if index > 1 then
					alpha = math.max(alpha, adjustedAlphas[index - 1] + minimumSpacingScale)
				end
				adjustedAlphas[index] = alpha
			end

			for index = #stageEntries - 1, 1, -1 do
				adjustedAlphas[index] = math.min(adjustedAlphas[index], adjustedAlphas[index + 1] - minimumSpacingScale)
			end

			for index, stageEntry in ipairs(stageEntries) do
				local markerClone = stageProgressState.markerTemplate:Clone()
				markerClone.Name = "StageMarker_" .. tostring(stageEntry.stageNumber)
				markerClone.Visible = true
				markerClone.ZIndex = 1
				markerClone.Parent = stageProgressState.markersFrame

				local alpha = math.clamp(adjustedAlphas[index], 0, 1)
				markerClone.Position = UDim2.new(
					alpha,
					stageProgressState.markerTemplate.Position.X.Offset,
					stageProgressState.markerTemplate.Position.Y.Scale,
					stageProgressState.markerTemplate.Position.Y.Offset
				)
				table.insert(stageProgressState.markerClones, markerClone)
			end
		end

		stageProgressState.tryRefresh = function()
			stageProgressState.rebuildMarkers()
			stageProgressState.updatePlayerMarkers()
		end

		stageProgressState.updatePlayerMarkers = function()
			if stageProgressState.frame and not stageProgressState.frame.Visible then
				return
			end

			local currentWorld = player:GetAttribute("Current_World")
			local currentStage = player:GetAttribute("CurrentStage")

			if stageProgressState.currentStageLabel then
				stageProgressState.currentStageLabel.Text =
					string.format("Stage %d", if typeof(currentStage) == "number" then currentStage else 0)
			end

			if typeof(currentWorld) ~= "string" or currentWorld == "" then
				stageProgressState.clearPlayerMarkers()
				stageProgressState.updateTrackStyle(nil)
				if stageProgressState.currentWorldLabel then
					stageProgressState.currentWorldLabel.Text = "World 0"
				end
				return
			end

			if stageProgressState.currentWorldLabel then
				stageProgressState.currentWorldLabel.Text = stageProgressState.formatWorldLabel(currentWorld)
			end
			stageProgressState.updateTrackStyle(currentWorld)

			if
				stageProgressState.worldName ~= currentWorld
				or not stageProgressState.startPosition
				or not stageProgressState.endPosition
			then
				stageProgressState.rebuildMarkers()
			end

			if not stageProgressState.startPosition or not stageProgressState.endPosition then
				stageProgressState.clearPlayerMarkers()
				return
			end

			if not stageProgressState.trackFrame or not stageProgressState.avatarTemplate then
				return
			end

			local visibleUserIds = {}
			for targetPlayer in pairs(stageProgressState.trackedPlayerMaids) do
				if targetPlayer:GetAttribute("Current_World") ~= currentWorld then
					continue
				end

				local character = targetPlayer.Character
				local rootPart = stageProgressState.trackedRootParts[targetPlayer]
				if not character or not rootPart or rootPart.Parent ~= character then
					rootPart = stageProgressState.cacheRootPart(targetPlayer)
				end
				if not rootPart or not rootPart:IsA("BasePart") then
					local existingMarker = stageProgressState.playerMarkers[targetPlayer.UserId]
					local missingUntil = stageProgressState.playerMarkerMissingUntil[targetPlayer.UserId]
					if missingUntil == nil then
						missingUntil = tick() + stageProgressState.markerMissingGrace
						stageProgressState.playerMarkerMissingUntil[targetPlayer.UserId] = missingUntil
					end

					if existingMarker and existingMarker.Parent and tick() <= missingUntil then
						existingMarker.Visible = true
						visibleUserIds[targetPlayer.UserId] = true
					end
					continue
				end

				stageProgressState.playerMarkerMissingUntil[targetPlayer.UserId] = nil

				local marker = stageProgressState.ensureAvatarMarker(targetPlayer)
				if not marker then
					continue
				end

				local alpha = stageProgressState.getTrackAlpha(
					stageProgressState.startPosition,
					stageProgressState.endPosition,
					rootPart.Position
				)
				marker.Position = UDim2.new(
					alpha,
					stageProgressState.avatarTemplate.Position.X.Offset,
					stageProgressState.avatarTemplate.Position.Y.Scale,
					stageProgressState.avatarTemplate.Position.Y.Offset
				)
				marker.Visible = true
				marker.ZIndex = if targetPlayer == player then 5 else 3
				visibleUserIds[targetPlayer.UserId] = true
			end

			for userId, marker in pairs(stageProgressState.playerMarkers) do
				if not visibleUserIds[userId] then
					marker.Visible = false
				end
			end
		end

		local function updateShopButtons()
			for frameName, config in pairs(SHOP_BUTTON_CONFIGS) do
				local buttonFrame = root:FindFirstChild(frameName, true)
				if not buttonFrame or not buttonFrame:IsA("GuiObject") then
					DebugModule.debugWarn(
						string.format("Shop button frame not found: %s", frameName),
						"MainOrchestrator"
					)
					continue
				end

				local passNameLabel = buttonFrame:FindFirstChild("PassName", true)
				if not passNameLabel then
					passNameLabel = buttonFrame:FindFirstChild("TextLabel", true)
				end
				local priceLabel = buttonFrame:FindFirstChild("PriceLabel", true)
				local passImage = buttonFrame:FindFirstChild("PassImage", true)
				if not passImage then
					passImage = buttonFrame:FindFirstChild("PackImage", true)
				end
				if not passImage then
					passImage = buttonFrame:FindFirstChild("Image", true)
				end
				local stepsLabel = buttonFrame:FindFirstChild("StepsPerSec", true)
				local itemId = config.itemId
				if typeof(itemId) ~= "number" or itemId == 0 then
					continue
				end

				spawnSessionTask(function()
					local info = getMarketplaceInfoCached(itemId, config.infoType)
					if not info then
						return
					end

					if not buttonFrame.Parent then
						return
					end

					if passNameLabel and passNameLabel:IsA("TextLabel") then
						passNameLabel.Text = string.upper(tostring(info.Name or frameName))
						if config.colorPassNameFromBackground then
							passNameLabel.TextColor3 = buttonFrame.BackgroundColor3
						end
					end

					if priceLabel and priceLabel:IsA("TextLabel") then
						priceLabel.Text = tostring(info.PriceInRobux or 0)
					end

					local shouldUseMarketplaceImage = config.useMarketplaceImage ~= false
					if
						shouldUseMarketplaceImage
						and passImage
						and (passImage:IsA("ImageLabel") or passImage:IsA("ImageButton"))
					then
						local iconAssetId = tonumber((info :: any).IconImageAssetId)
						if iconAssetId and iconAssetId > 0 then
							passImage.Image = "rbxassetid://" .. tostring(iconAssetId)
						end
					end

					if stepsLabel and stepsLabel:IsA("TextLabel") then
						local stepsText = getKartShopStepsText(config)
						if typeof(stepsText) == "string" then
							stepsLabel.Text = stepsText
						end
					end

					if config.purchaseType == "gamepass" then
						local ownsPass = false
						if frameName == "VIPButton" then
							ownsPass = player:GetAttribute("HasVIPPass") == true
						elseif frameName == "2xWinButton" then
							ownsPass = (player:GetAttribute("WinMultiplier") or 1) > 1
						elseif typeof(config.kartModelName) == "string" and config.kartModelName ~= "" then
							ownsPass = PlayerHandler.OwnsKart(player, config.kartModelName)
						else
							ownsPass = ProductService.userOwnsGamePass(player, itemId)
						end

						local shouldHideWhenOwned = config.hideWhenOwned == true
							and not (RunService:IsStudio() and config.debugShowWhenOwnedInStudio == true)
						buttonFrame.Visible = if shouldHideWhenOwned then not ownsPass else true
						VisualFunctions.SetFrameDisabledState(buttonFrame, ownsPass, 0.6)
					else
						buttonFrame.Visible = true
						VisualFunctions.SetFrameDisabledState(buttonFrame, false, 0.6)
					end
				end)
			end
		end

		local function showReturnToStageFrame(stage: number, duration: number)
			local frame = VisualFunctions.HUD.ReturnToStageFrame
			if not frame then
				DebugModule.debugWarn("ReturnToStage button show failed: HUD frame missing", "MainOrchestrator")
				return
			end

			local trollFrame = VisualFunctions.ActiveFrameGroup.TrollFrame
			if trollFrame and trollFrame.Visible then
				hideReturnToStageFrame()
				return
			end

			returnToStageOfferThread += 1
			local threadId = returnToStageOfferThread
			frame.Visible = true
			for _, descendant in ipairs(frame:GetDescendants()) do
				if descendant:IsA("GuiObject") then
					descendant.Visible = true
				end
			end

			local watchAdFrame = frame:FindFirstChild("WatchAdButton", true)
			local watchAdTextButton = watchAdFrame and watchAdFrame:FindFirstChildWhichIsA("GuiButton", true)
			applyReturnToStageAdLayout(frame, RewardedVideoClient.IsAvailable())
			if watchAdTextButton then
				watchAdTextButton.Active = true
				watchAdTextButton.Interactable = true
			end

			local button = frame:FindFirstChild("ReturnToStageButton", true)
			local textButton = button and button:FindFirstChildWhichIsA("TextButton", true)
			if textButton then
				textButton.Text = string.format("RETURN TO STAGE %d", stage)
			else
				DebugModule.debugWarn("ReturnToStage TextButton missing", "MainOrchestrator")
			end

			local countdownLabel = VisualFunctions.HUD.ReturnToStageCountdownLabel
			local nestedButton = frame:FindFirstChild("ReturnToStageButton", true)
			local nestedCountdownLabel = if nestedButton
				then nestedButton:FindFirstChild("CountdownLabel", true)
				else nil
			local function updateReturnToStageCountdown(seconds: number)
				local text = formatReturnToStageCountdown(seconds)
				if countdownLabel then
					countdownLabel.Text = text
				end
				if nestedCountdownLabel and nestedCountdownLabel:IsA("TextLabel") then
					nestedCountdownLabel.Text = text
				end
			end
			if countdownLabel then
				updateReturnToStageCountdown(duration)
			else
				DebugModule.debugWarn("ReturnToStage CountdownLabel missing", "MainOrchestrator")
			end

			updateReturnToStagePrice()

			returnToStageOfferTask = task.spawn(function()
				local startedAt = os.clock()
				while threadId == returnToStageOfferThread do
					local remaining = math.max(0, math.ceil(duration - (os.clock() - startedAt)))
					updateReturnToStageCountdown(remaining)

					if remaining <= 0 then
						break
					end

					task.wait(0.1)
				end

				if threadId == returnToStageOfferThread and frame then
					frame.Visible = false
					for _, descendant in ipairs(frame:GetDescendants()) do
						if descendant:IsA("GuiObject") then
							descendant.Visible = false
						end
					end
				end

				if returnToStageOfferTask == coroutine.running() then
					returnToStageOfferTask = nil
				end
			end)
		end

		local function clearCharacterStateBinding()
			if characterStateMaid then
				characterStateMaid:DoCleaning()
				characterStateMaid = nil
			end
		end

		sessionMaid:GiveTask(clearCharacterStateBinding)

		local function bindCharacterState(character: Model)
			clearCharacterStateBinding()

			local nextCharacterStateMaid = Maid.new()
			characterStateMaid = nextCharacterStateMaid
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end

			nextCharacterStateMaid:GiveTask(character.AncestryChanged:Connect(function(_, parent)
				if parent == nil then
					clearCharacterStateBinding()
				end
			end))

			nextCharacterStateMaid:GiveTask(humanoid.Died:Connect(function()
				local trollFrame = VisualFunctions.ActiveFrameGroup.TrollFrame
				if trollFrame and trollFrame.Visible then
					MainFunctions.SetFrameVisibleSimple("TrollFrame", false)
					stopTrollSpectate()
				end

				hideReturnToStageFrame()
			end))
		end

		if player.Character then
			sessionMaid:GiveTask(task.defer(bindCharacterState, player.Character))
		end
		sessionMaid:GiveTask(player.CharacterAdded:Connect(bindCharacterState))

		local function updateMultiplierShop()
			local currentMult = player:GetAttribute("DevProduct_XPSpeedMultiplier") or 1
			local nextMultName = ProductService.MULTIPLIER_TO_PRODUCT[currentMult]
			local frame = VisualFunctions.HUD.MultiplierSpeedProductFrame_Parent
			if not frame then
				return
			end

			local priceLabel = VisualFunctions.HUD.MultiplierSpeedPriceLabel
			local promptButton = VisualFunctions.HUD.MultiplierSpeedPromptButton

			if not nextMultName then
				if promptButton then
					promptButton.Text = "MAXED"
				end
				if priceLabel then
					priceLabel.Text = "---"
				end
				VisualFunctions.SetFrameDisabledState(frame, true, 0.5)
				return
			end

			VisualFunctions.SetFrameDisabledState(frame, false, 0.5)
			if promptButton then
				promptButton.Text = nextMultName .. " Speed"
			end
			local id = ProductService.DevProducts[nextMultName]
			if id and id ~= 0 then
				spawnSessionTask(function()
					local info = productCache[id]
					if not info then
						local success, result = pcall(function()
							return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
						end)
						if success then
							info = result
							productCache[id] = result
						end
					end

					local latestMultiplier = player:GetAttribute("DevProduct_XPSpeedMultiplier") or 1
					local latestNextMultName = ProductService.MULTIPLIER_TO_PRODUCT[latestMultiplier]
					if latestNextMultName ~= nextMultName then
						return
					end

					if info and priceLabel then
						priceLabel.Text = tostring(info.PriceInRobux) .. "!"
					end
				end)
			end
		end

		local function updateX2WinShop()
			local gamepassId = ProductService.Gamepasses["2xWins"]
			local frame = VisualFunctions.HUD.X2WinProductFrame_Parent
			local priceLabel = VisualFunctions.HUD.X2WinPriceLabel
			local ownsPass = (player:GetAttribute("WinMultiplier") or 1) > 1

			if frame then
				VisualFunctions.SetFrameDisabledState(frame, ownsPass, 0.5)
			end

			if ownsPass then
				if VisualFunctions.HUD.X2WinPromptButton then
					VisualFunctions.HUD.X2WinPromptButton.Text = "OWNED"
				end
				if priceLabel then
					priceLabel.Text = "---"
				end
				return
			end

			if VisualFunctions.HUD.X2WinPromptButton then
				VisualFunctions.HUD.X2WinPromptButton.Text = "2x Wins"
			end
			if not priceLabel then
				return
			end
			spawnSessionTask(function()
				local success, info = pcall(function()
					return MarketplaceService:GetProductInfo(gamepassId, Enum.InfoType.GamePass)
				end)
				local latestOwnsPass = (player:GetAttribute("WinMultiplier") or 1) > 1
				if latestOwnsPass then
					return
				end

				if
					success
					and info
					and info.PriceInRobux
					and VisualFunctions.HUD.X2WinPriceLabel == priceLabel
					and priceLabel.Parent
				then
					priceLabel.Text = tostring(info.PriceInRobux) .. "!"
				end
			end)
		end

		local function updateDisableWavePrice()
			local priceLabel = VisualFunctions.HUD.DisableWavePriceLabel
			local id = ProductService.DevProducts.DisableWaves
			if not priceLabel or not id or id == 0 then
				return
			end

			spawnSessionTask(function()
				local info = productCache[id]
				if not info then
					local success, result = pcall(function()
						return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
					end)
					if success then
						info = result
						productCache[id] = result
					end
				end

				if info and priceLabel then
					if VisualFunctions.HUD.DisableWavePriceLabel ~= priceLabel or not priceLabel.Parent then
						return
					end
					priceLabel.Text = tostring(info.PriceInRobux)
				end
			end)
		end

		local function updateDisableWaveButton()
			local frame = VisualFunctions.HUD.DisableWaveButtonFrame
			if not frame then
				return
			end

			local rawCooldownEnd = player:GetAttribute("DisableWavesCooldownEnd")
			local cooldownEnd = if typeof(rawCooldownEnd) == "number" then math.floor(rawCooldownEnd) else 0
			-- The timestamp is authoritative. A stale replicated boolean must not
			-- permanently disable the purchase button after the cooldown expires.
			local isOnCooldown = cooldownEnd > os.time()
			local countdownLabel = VisualFunctions.HUD.DisableWaveCountdownLabel
			updateDisableWaveButtonInteraction()

			if isOnCooldown and cooldownEnd > 0 then
				showDisableWaveNotification(cooldownEnd)
			end

			disableWaveCountdownThread += 1
			local threadId = disableWaveCountdownThread

			if not isOnCooldown or typeof(cooldownEnd) ~= "number" or cooldownEnd <= 0 then
				if disableWaveCountdownTask then
					cancelThread(disableWaveCountdownTask)
					disableWaveCountdownTask = nil
				end
				if countdownLabel then
					countdownLabel.Visible = false
					countdownLabel.Text = "0s"
				end
				updateDisableWavePrice()
				return
			end

			if countdownLabel then
				countdownLabel.Visible = true
			end

			if disableWaveCountdownTask then
				cancelThread(disableWaveCountdownTask)
				disableWaveCountdownTask = nil
			end

			disableWaveCountdownTask = spawnSessionTask(function()
				while threadId == disableWaveCountdownThread do
					local remaining = math.max(0, cooldownEnd - os.time())
					if countdownLabel then
						countdownLabel.Text = tostring(remaining) .. "s"
					end
					if remaining <= 0 then
						break
					end

					task.wait(1)
				end

				if threadId == disableWaveCountdownThread then
					updateDisableWaveButtonInteraction()
					if countdownLabel then
						countdownLabel.Text = "0s"
						countdownLabel.Visible = false
					end
				end

				if disableWaveCountdownTask == coroutine.running() then
					disableWaveCountdownTask = nil
				end
			end)
		end

		productCache.kartShopController = KartShopController.new({
			player = player,
			kartActionRemote = kartActionRemote,
			getMarketplaceInfoCached = getMarketplaceInfoCached,
			isLiveEventActive = isLiveEventActive,
			openSpinWheelFromShop = openSpinWheelFromShop,
			applyWheelStyle = applyWheelStyle,
			applyEquipStyle = applyEquipStyle,
		})
		sessionMaid:GiveTask(productCache.kartShopController)

		productCache.buildKartShop = function()
			productCache.kartShopController:Build()
		end

		productCache.updateKartShop = function()
			productCache.kartShopController:Update()
		end




		if ReplicatedStorage:FindFirstChild("LiveEventState") and ReplicatedStorage.LiveEventState:IsA("Folder") then
			local liveEventState = ReplicatedStorage.LiveEventState :: Folder
			sessionMaid:GiveTask(
				liveEventState:GetAttributeChangedSignal("ActiveEventIds"):Connect(function()
					productCache.buildKartShop()
					productCache.buildTrailShop()
				end)
			)
			sessionMaid:GiveTask(
				liveEventState:GetAttributeChangedSignal("EnvironmentName"):Connect(function()
					productCache.buildKartShop()
					productCache.buildTrailShop()
				end)
			)
		end
		sessionMaid:GiveTask(ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
			if child.Name == "LiveEventState" and child:IsA("Folder") then
				sessionMaid:GiveTask(
					child:GetAttributeChangedSignal("ActiveEventIds"):Connect(function()
						productCache.buildKartShop()
						productCache.buildTrailShop()
					end)
				)
				sessionMaid:GiveTask(
					child:GetAttributeChangedSignal("EnvironmentName"):Connect(function()
						productCache.buildKartShop()
						productCache.buildTrailShop()
					end)
				)
				productCache.buildKartShop()
				productCache.buildTrailShop()
			end
		end))

		productCache.trailShopController = TrailShopController.new({
			player = player,
			openSpinWheelFromShop = openSpinWheelFromShop,
			applyWheelStyle = applyWheelStyle,
			applyEquipStyle = applyEquipStyle,
			canBuyEventProduct = canBuyEventProduct,
			formatTrailMultiplier = formatTrailMultiplier,
			getOrCreateEquipButton = getOrCreateEquipButton,
		})
		sessionMaid:GiveTask(productCache.trailShopController)
		productCache.buildTrailShop = function()
			productCache.trailShopController:Build()
		end
		productCache.updateTrailShop = function()
			productCache.trailShopController:Update()
		end

		if VisualFunctions.HUD.X2WinPromptButton then
			sessionMaid:GiveTask(VisualFunctions.HUD.X2WinPromptButton.Activated:Connect(function()
				ProductService.promptGamePassPurchase(player, ProductService.Gamepasses["2xWins"])
			end))
		end

		levelDisplayController = LevelDisplayController.new({
			player = player,
			visualFunctions = VisualFunctions,
			playerHandler = PlayerHandler,
			soundService = SoundService,
			refreshRebirthReadyState = refreshRebirthReadyState,
			tutorialSystem = tutorialSystem,
			defaultMaxPlayerSpeed = DEFAULT_MAX_PLAYER_SPEED,
		})
		sessionMaid:GiveTask(function()
			if levelDisplayController then
				levelDisplayController:Destroy()
				levelDisplayController = nil
			end
		end)

		winDisplayController = WinDisplayController.new({
			player = player,
			visualFunctions = VisualFunctions,
			spawnSessionTask = spawnSessionTask,
			playRewardCelebration = function(playHorn: boolean?)
				rewardCelebrationController:PlayRewardCelebration(playHorn)
			end,
			playWinSound = function()
				SoundService.PlayGuiSound("Confetti")
			end,
			playWinCountPop = function()
				SoundService.PlayGuiSound("Pop")
			end,
			refreshTrailShop = productCache.updateTrailShop,
			refreshAffordableTrailBadge = refreshAffordableTrailBadge,
			onTutorialProgressChanged = function()
				if hasCompletedStartupLoading and tutorialSystem then
					tutorialSystem:OnProgressChanged()
				end
			end,
		})
		sessionMaid:GiveTask(function()
			if winDisplayController then
				winDisplayController:Destroy()
				winDisplayController = nil
			end
		end)
		hudDisplayController = HudDisplayController.new({
			player = player,
			visualFunctions = VisualFunctions,
			playerHandler = PlayerHandler,
			levelDisplayController = levelDisplayController,
			winDisplayController = winDisplayController,
			refreshRebirthReadyState = refreshRebirthReadyState,
			defaultPlayerSpeed = DEFAULT_PLAYER_SPEED,
			defaultMaxPlayerSpeed = DEFAULT_MAX_PLAYER_SPEED,
		})
		sessionMaid:GiveTask(function()
			if hudDisplayController then
				hudDisplayController:Destroy()
				hudDisplayController = nil
			end
		end)
		PlayerAttributeBindings.Bind({
			player = player,
			sessionMaid = sessionMaid,
			onAllXPSpeedChanged = hudDisplayController:GetUpdateAllXPHandler(),
			onCurrentXPSpeedChanged = hudDisplayController:GetUpdateXPHandler(),
			onMaxXPSpeedChanged = hudDisplayController:GetUpdateXPHandler(),
			onCurrentLevelChanged = levelDisplayController:GetLevelUpdateHandler(),
			onMaxPlayerSpeedChanged = levelDisplayController:GetMaxSpeedUpdateHandler(),
			onOwnedTrailsChanged = TrailDisplayController.CreateOwnedTrailsRefreshHandler(
				productCache.updateTrailShop,
				refreshAffordableTrailBadge
			),
			onOwnedKartsChanged = function()
				productCache.buildKartShop()
				handleOwnedKartsChangedForBadge()
			end,
			onTrailEquippedChanged = function()
				productCache.updateTrailShop()
				hudDisplayController:UpdateTrailMultiplierDisplay()
			end,
			onKartEquippedChanged = function()
				productCache.updateKartShop()
				handleKartEquippedChangedForBadge()
			end,
			onWinCountChanged = winDisplayController:GetUpdateHandler(),
			onDataLoadedChanged = function()
				loadingMovementLockState.onLoadingComplete()
				if player:GetAttribute("Data_Loaded") == true then
					resetKartPurchaseBadgeBaseline()
				else
					handleOwnedKartsChangedForBadge()
				end
			end,
			onGamePassOwnershipSyncChanged = function()
				if player:GetAttribute("GamePassOwnershipSyncComplete") == true then
					resetKartPurchaseBadgeBaseline()
				else
					handleOwnedKartsChangedForBadge()
				end
			end,
			onTutorialCompletedChanged = function()
				dailyRewardPromptController:OnTutorialCompletedChanged()
			end,
			verifyRewardNextClaimAttribute = VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE,
			verifyRewardClaimCountAttribute = VERIFY_REWARD_CLAIM_COUNT_ATTRIBUTE,
			onVerifyRewardNextClaimChanged = function()
				refreshVerifyClaimableBadge()
				updateVerifyGroupCountdown(nil)
			end,
			onVerifyRewardClaimCountChanged = updateVerifyRewardValueLabels,
			onTreadmillActiveChanged = function()
				if hasCompletedStartupLoading and tutorialSystem then
					tutorialSystem:OnProgressChanged()
				end
			end,
			onTreadmillMultiplierChanged = updateVerifyRewardValueLabels,
			onDisableWavesOnCooldownChanged = updateDisableWaveButton,
			onDisableWavesCooldownEndChanged = updateDisableWaveButton,
			onHasVIPPassChanged = function()
				updateShopButtons()
				productCache.updateKartShop()
			end,
			onStarterPackRewardClaimedChanged = updateShopButtons,
			onCurrentWorldChanged = function()
				stageProgressState.updatePlayerMarkers()
				if hasCompletedStartupLoading and tutorialSystem then
					tutorialSystem:OnProgressChanged()
				end
			end,
			onCurrentStageChanged = stageProgressState.updatePlayerMarkers,
		})
		DisplayRefreshBindings.Bind({
			player = player,
			sessionMaid = sessionMaid,
			updateUI = hudDisplayController:GetUpdateUIHandler(),
			updateXPProductLabels = hudDisplayController:GetUpdateXPProductLabelsHandler(),
			updateVerifyRewardValueLabels = updateVerifyRewardValueLabels,
			updateMultiplierShop = updateMultiplierShop,
			updateX2WinShop = updateX2WinShop,
			updateShopButtons = updateShopButtons,
			updateKartShop = productCache.updateKartShop,
			updateTrailMultiplierDisplay = hudDisplayController:GetUpdateTrailMultiplierHandler(),
		})
		StageProgressBindings.Bind({
			sessionMaid = sessionMaid,
			playersService = Players,
			workspace = Workspace,
			player = player,
			connectTrackedPlayer = stageProgressState.connectTrackedPlayer,
			disconnectTrackedPlayer = stageProgressState.disconnectTrackedPlayer,
			updateStageProgressPlayerMarkers = stageProgressState.updatePlayerMarkers,
			tryRefreshStageProgress = stageProgressState.tryRefresh,
		})

		RemoteBindings.Bind({
			remotes = remotes,
			sessionMaid = sessionMaid,
			localPlayer = localPlayer,
			onXPGainAwarded = function(amount: number)
				if amount <= 0 then
					return
				end

				VisualFunctions.CreateFloatingText(VisualFunctions.HUD.Float_CurrentSpeedFrame, amount, 1)
			end,
			onWinAwarded = winDisplayController:GetWinAwardedHandler(),
			onEventWinAwarded = winDisplayController:GetEventWinAwardedHandler(),
			onVerifyRewardResult = function(success: boolean, nextClaimUnix: number?)
				refreshVerifyClaimableBadge()
				updateVerifyGroupCountdown(nextClaimUnix)
				if success then
					local verifyFrame = VisualFunctions.ActiveFrameGroup.VerifyFrame
					if verifyFrame then
						VisualFunctions.CloseWindow(verifyFrame)
					end

					local theme = VisualFunctions.NotificationThemes.Gold
					showNotificationRespectingTutorial(
						"VERIFY REWARD CLAIMED!",
						theme.textColor,
						theme.gradientBottomColor
					)
				else
					local theme = VisualFunctions.NotificationThemes.Red
					showNotificationRespectingTutorial("VERIFY FAILED!", theme.textColor, theme.gradientBottomColor)
				end
			end,
			onRebirthResult = function()
				local function showRebirthNotification()
					SoundService.PlayGuiSound("Rebirth")
					local theme = VisualFunctions.NotificationThemes.Purple
					showNotificationRespectingTutorial(
						"YOU REBIRTHED!!",
						theme.textColor,
						theme.gradientBottomColor
					)
				end

				local rebirthFrame = VisualFunctions.ActiveFrameGroup.RebirthFrame
				if rebirthFrame and rebirthFrame.Visible then
					VisualFunctions.CloseWindow(rebirthFrame)
				end

				local skipNotificationUntil = if typeof(rebirthReadyUIState.skipNotificationUntil) == "number"
					then rebirthReadyUIState.skipNotificationUntil
					else 0
				if tick() < skipNotificationUntil then
					sessionMaid:GiveTask(task.delay(1.1, function()
						if not isCleanedUp then
							showRebirthNotification()
						end
					end))
				else
					showRebirthNotification()
				end
			end,
			onShowNotification = function(
				message: string,
				themeName: string?,
				notificationStyle: string?,
				notificationCooldownEnd: number?
			)
				if notificationStyle == "DisableWaves" and typeof(notificationCooldownEnd) == "number" then
					showDisableWaveNotification(notificationCooldownEnd)
					return
				end

				local theme = if typeof(themeName) == "string" and VisualFunctions.NotificationThemes[themeName]
					then VisualFunctions.NotificationThemes[themeName]
					else VisualFunctions.NotificationThemes.Default
				showNotificationRespectingTutorial(
					message,
					theme.textColor,
					theme.gradientBottomColor,
					notificationStyle
				)
			end,
			onReturnToStageOffer = function(shouldShow: boolean, stage: number?, duration: number?)
				if shouldShow and typeof(stage) == "number" and typeof(duration) == "number" then
					showReturnToStageFrame(stage, duration)
				else
					hideReturnToStageFrame()
				end
			end,
			onOpenVerifyFrameRequested = function()
				local verifyFrame = VisualFunctions.ActiveFrameGroup.VerifyFrame
				if verifyFrame and not verifyFrame.Visible then
					SoundService.PlayGuiSound("Click")
					MainFunctions.ToggleFrame("VerifyFrame")
				end
			end,
			onTriggerJumpscare = function()
				SoundService.PlayGuiSound("Click", nil, {
					SoundId = 1631688574,
					Volume = 1,
					PlaybackSpeed = 1,
					AllowOverlap = true,
				})

				if not jumpscareImage then
					return
				end

				jumpscareImage.Visible = true
				jumpscareHideToken += 1
				local hideToken = jumpscareHideToken
				spawnSessionTask(function()
					task.wait(2)
					if hideToken ~= jumpscareHideToken then
						return
					end
					if jumpscareImage then
						jumpscareImage.Visible = false
					end
				end)
			end,
			onTrackedPlayerRemoving = function(removingPlayer: Player)
				if removingPlayer == trollSelectedPlayer then
					updateTrollSelection(nil)
					syncTrollCamera()
				end
			end,
			onLocalCharacterAdded = function()
				if STARTUP_LOADING_ENABLED and loadingFrame and loadingFrame.Visible and not hasCompletedStartupLoading then
					sessionMaid:GiveTask(task.defer(function()
						if not isCleanedUp then
							lockLocalMovementForLoading()
						end
					end))
				end
				sessionMaid:GiveTask(task.defer(function()
					if not isCleanedUp and hasCompletedStartupLoading and tutorialSystem then
						tutorialSystem:OnProgressChanged()
					end
				end))
			end,
			onRequestReturnToStageOffer = function()
				local requestRemote = remotes:WaitForChild("RequestReturnToStageOffer")
				if requestRemote:IsA("RemoteEvent") then
					requestRemote:FireServer()
				end
			end,
				onPromptProductPurchaseFinished = function(productId: number, wasPurchased: boolean)
				if productId == ProductService.DevProducts.DisableWaves then
					cancelDisableWavePurchaseWatchdog()
					disableWavePurchaseInFlight = false
					updateDisableWaveButton()
				end

				if productId == ProductService.DevProducts.SkipRebirth and wasPurchased then
					rebirthReadyUIState.skipNotificationUntil = tick() + 1.5
				end

				local theme = if wasPurchased
					then VisualFunctions.NotificationThemes.Green
					else VisualFunctions.NotificationThemes.Red
				local message = if wasPurchased then "PURCHASE SUCCESS!" else "PURCHASE FAILED!"
				showNotificationRespectingTutorial(message, theme.textColor, theme.gradientBottomColor)
			end,
			onPromptReturnToStageDeclined = function(productId: number, wasPurchased: boolean)
				if productId == ProductService.DevProducts.ReturnToStage and not wasPurchased then
					local returnToStageDeclined = remotes:WaitForChild("ReturnToStageDeclined")
					if returnToStageDeclined:IsA("RemoteEvent") then
						returnToStageDeclined:FireServer()
					end
				end
			end,
		})

		hudDisplayController:UpdateUI()
		updateMultiplierShop()
		updateDisableWavePrice()
		updateDisableWaveButton()
		updateReturnToStagePrice()
		updateShopButtons()
		productCache.buildKartShop()
		productCache.buildTrailShop()
		refreshKartPurchaseBadge()
		refreshAffordableTrailBadge()
		refreshPlaytimeClaimableBadge()
		dailyRewardPromptController:RefreshBadge()
		refreshVerifyClaimableBadge()
		updateVerifyRewardValueLabels()
		updateVerifyGroupCountdown(nil)
		if verifyGroupController then
			verifyGroupController:RefreshMembership()
		end
		stageProgressState.tryRefresh()
		sessionMaid:GiveTask(task.delay(0.5, function()
			updateX2WinShop()
			hudDisplayController:UpdateXPProductLabels()
			updateShopButtons()
			productCache.updateKartShop()
			refreshKartPurchaseBadge()
			productCache.updateTrailShop()
			refreshAffordableTrailBadge()
			refreshPlaytimeClaimableBadge()
			dailyRewardPromptController:RefreshBadge()
			refreshVerifyClaimableBadge()
			updateVerifyRewardValueLabels()
			updateVerifyGroupCountdown(nil)
			stageProgressState.tryRefresh()
		end))
		if winDisplayController then
			winDisplayController:SetDisplayedWinCount(player:GetAttribute("WinCount") or 0)
		end
		sessionMaid:GiveTask(RunService.Heartbeat:Connect(function(dt)
			stageProgressState.markerUpdateAccumulator = math.min(
				stageProgressState.markerUpdateAccumulator + dt,
				stageProgressState.markerUpdateInterval * 3
			)
			if stageProgressState.markerUpdateAccumulator >= stageProgressState.markerUpdateInterval then
				stageProgressState.markerUpdateAccumulator = 0
				if not stageProgressState.frame or stageProgressState.frame.Visible then
					stageProgressState.updatePlayerMarkers()
				end
			end

			verifyRewardCountdownAccumulator =
				math.min(verifyRewardCountdownAccumulator + dt, VERIFY_REWARD_COUNTDOWN_UPDATE_INTERVAL * 2)
			if verifyRewardCountdownAccumulator >= VERIFY_REWARD_COUNTDOWN_UPDATE_INTERVAL then
				verifyRewardCountdownAccumulator = 0
				refreshVerifyClaimableBadge()
				updateVerifyGroupCountdown(nil)
			end
		end))
		sessionMaid:GiveTask(task.defer(runStartupLoading))
	end

	DebugModule.debugPrint("Main GUI initialization complete", "MainOrchestrator")
end

return MainOrchestrator
