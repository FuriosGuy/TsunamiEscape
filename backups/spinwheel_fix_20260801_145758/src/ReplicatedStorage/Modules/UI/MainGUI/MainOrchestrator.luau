--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)
local SoundService = require(ReplicatedStorage.Modules.SoundService)
local Players = game:GetService("Players")
local PlayerHandler = require(ReplicatedStorage.Modules.PlayerHandler)
local ProductService = require(ReplicatedStorage.Modules.ProductService)
local VerifyRewardCalculator = require(ReplicatedStorage.Modules.VerifyRewardCalculator)
local MainFunctions = require(ReplicatedStorage.Modules.UI.MainFunctions)
local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig)
local FavoriteGamePrompt = require(ReplicatedStorage.Modules.FavoriteGamePrompt)
local TutorialNotificationSystem = require(script.Parent:WaitForChild("TutorialNotificationSystem"))
local PlaytimeRewardsUI = require(script.Parent:WaitForChild("PlaytimeRewardsUI"))
local DailyRewardsUI = require(script.Parent:WaitForChild("DailyRewardsUI"))
local DailyRewardPromptController = require(script.Parent:WaitForChild("DailyRewardPromptController"))
local RewardCelebrationController = require(script.Parent:WaitForChild("RewardCelebrationController"))
local StageProgressBindings = require(script.Parent:WaitForChild("StageProgressBindings"))
local RemoteBindings = require(script.Parent:WaitForChild("RemoteBindings"))
local DEFAULT_PLAYER_SPEED = if typeof(PlayerHandler.DEFAULT_ATTRIBUTES.Player_Speed) == "number"
	then PlayerHandler.DEFAULT_ATTRIBUTES.Player_Speed
	else 16
local DEFAULT_MAX_PLAYER_SPEED = if typeof(PlayerHandler.DEFAULT_ATTRIBUTES.Max_Player_Speed) == "number"
	then PlayerHandler.DEFAULT_ATTRIBUTES.Max_Player_Speed
	else 16

local MainOrchestrator = {}
local DEBUG_TROLL_FRAME_ONLY_FOR_ME = false -- Enabled to allow self-testing as requested
local DEBUG_LOADING_DETAILS = false
local hasCompletedStartupLoading = false
local VERIFY_GROUP_ID = if CoreConfig.social and typeof(CoreConfig.social.verifyGroupId) == "number"
	then CoreConfig.social.verifyGroupId
	else 13706307
local verifyRewardConfig = VerifyRewardCalculator.GetConfig(CoreConfig)
local VERIFY_REWARD_CLAIM_COUNT_ATTRIBUTE = verifyRewardConfig.claimCountAttribute
local VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE = "VerifyRewardNextClaimUnix"
local VERIFY_REWARD_COUNTDOWN_UPDATE_INTERVAL = 1

function MainOrchestrator.Init(root: Instance)
	if root:GetAttribute("MainOrchestratorInitialized") == true then
		DebugModule.debugWarn(
			"MainOrchestrator.Init called more than once for " .. root:GetFullName(),
			"MainOrchestrator"
		)
		return
	end

	root:SetAttribute("MainOrchestratorInitialized", true)

	DebugModule.debugPrint("Initializing Main GUI for " .. root.Name, "MainOrchestrator")
	local sessionMaid = Maid.new()
	local stageProgressTrackedPlayerMaids: { [Player]: Maid } = {}
	local isCleanedUp = false
	local startupLoadingTask: thread? = nil
	local disableWaveCountdownTask: thread? = nil

	if VisualFunctions.ResetRuntimeState then
		VisualFunctions.ResetRuntimeState()
	end

	local function cleanupInitSession()
		if isCleanedUp then
			return
		end

		isCleanedUp = true
		root:SetAttribute("MainOrchestratorInitialized", false)
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
	local hideReturnToStageButton: () -> () = function() end
	local localPlayer = Players.LocalPlayer
	local canUseTrollFrame = true
	local allowSelfTargetingInTrollDebug = DEBUG_TROLL_FRAME_ONLY_FOR_ME

	local trollFrame: Frame? = nil
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
	} =
		{
			humanoid = nil,
			walkSpeed = nil,
			jumpHeight = nil,
			autoRotate = nil,
		}
	local loadingFrame: Frame? = nil
	local loadingImage: ImageLabel? = nil
	local loadingGameImage: ImageLabel? = nil
	local loadingLightRay: ImageLabel? = nil
	local loadingLevelsBarFrame: Frame? = nil
	local loadingProgressFrame: Frame? = nil
	local loadingProgressLabel: TextLabel? = nil
	local loadingCurrentLabel: TextLabel? = nil
	local loadingSkipButtonFrame: GuiObject? = nil
	local loadingSkipButton: GuiButton? = nil
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
	local stageProgressFrame: Frame? = nil
	local stageProgressTrackFrame: Frame? = nil
	local stageProgressMarkersFrame: Frame? = nil
	local stageProgressMarkerTemplate: GuiObject? = nil
	local stageProgressAvatarTemplate: ImageLabel? = nil
	local stageProgressCurrentStageLabel: TextLabel? = nil
	local stageProgressCurrentWorldLabel: TextLabel? = nil
	local stageProgressMarkerClones: { GuiObject } = {}
	local stageProgressPlayerMarkers: { [number]: ImageLabel } = {}
	local stageProgressPlayerMarkerMissingUntil: { [number]: number } = {}
	local stageProgressAvatarCache: { [number]: string } = {}
	local stageProgressWorldName: string? = nil
	local stageProgressStartPosition: Vector3? = nil
	local stageProgressEndPosition: Vector3? = nil
	local STAGE_PROGRESS_MARKER_MISSING_GRACE = 2
	local STAGE_PROGRESS_MARKER_UPDATE_INTERVAL = 0.1
	local STAGE_PROGRESS_WORLD_STYLES = {
		World1 = {
			backgroundColor = Color3.fromRGB(85, 255, 0),
		},
		Fallback = {
			backgroundColor = Color3.fromRGB(255, 255, 255),
		},
	}
	local rebirthReadyUIState = {
		buttonFrame = nil :: GuiObject?,
		template = nil :: GuiObject?,
		badge = nil :: GuiObject?,
		refresh = nil :: (() -> ())?,
		wasReady = false,
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
		for trackedPlayer, trackedPlayerMaid in pairs(stageProgressTrackedPlayerMaids) do
			trackedPlayerMaid:DoCleaning()
			stageProgressTrackedPlayerMaids[trackedPlayer] = nil
		end
	end)
	sessionMaid:GiveTask(function()
		if startupLoadingTask then
			task.cancel(startupLoadingTask)
			startupLoadingTask = nil
		end
		if disableWaveCountdownTask then
			task.cancel(disableWaveCountdownTask)
			disableWaveCountdownTask = nil
		end
		verifyGroupCountdownLabel = nil
		verifyRewardWhenLabel = nil
		refreshVerifyCountdownLabel = nil
		verifyRewardXPLabel = nil
		verifyRewardWinsLabel = nil
		refreshVerifyRewardValueLabels = nil
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

	-- State for LevelUp comparisons
	local lastLevel = localPlayer:GetAttribute("CurrentLevel") or 1
	local lastMaxSpeed = localPlayer:GetAttribute("Max_Player_Speed") or DEFAULT_MAX_PLAYER_SPEED
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
				TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
				fadeOutTween.Completed:Connect(function(playbackState)
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
						TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{
							TextTransparency = 0,
						}
					)
					loadingCurrentLabelTween = fadeInTween
					fadeInTween:Play()
				end)
			end
		end
	end

	local function formatLoadingLabel(baseLabel: string, detail: string?): string
		if DEBUG_LOADING_DETAILS and detail and detail ~= "" then
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
		notificationStyle: string?
	)
		if localPlayer:GetAttribute("SpinWheelModalOpen") == true then
			return
		end

		if tutorialSystem then
			tutorialSystem:ShowNonTutorialNotification(message, textColor, gradientBottomColor, notificationStyle)
			return
		end

		if notificationStyle == "QuickFade" then
			VisualFunctions.ShowQuickFadeNotification(message, textColor, gradientBottomColor)
			return
		end
		VisualFunctions.ShowNotification(message, textColor, gradientBottomColor)
	end

	local function updateButtonNotificationBadge(
		badgeState: any,
		shouldShow: boolean,
		badgeName: string,
		countText: string
	)
		local existingBadge = badgeState.badge
		if not shouldShow then
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
				fallback.BackgroundColor3 = Color3.fromRGB(255, 79, 79)
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
				label.TextColor3 = Color3.fromRGB(255, 255, 255)
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
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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
		if instance:IsA("Frame") or instance:IsA("ScrollingFrame") then
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
			local descendantGoals = {}
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
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
				task.defer(syncTrollCamera)
			end)
			trollSelectedCharacterRemovingConnection = trollSelectedPlayer.CharacterRemoving:Connect(function()
				task.defer(syncTrollCamera)
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
				humanoid.WalkSpeed = localPlayer:GetAttribute("Player_Speed") or DEFAULT_PLAYER_SPEED
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
			local loadedWalkSpeed = localPlayer:GetAttribute("Player_Speed")
			if typeof(loadedWalkSpeed) == "number" then
				humanoid.WalkSpeed = loadedWalkSpeed
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

	local function spawnSessionTask(callback: () -> ()): thread
		local thread = task.spawn(function()
			if isCleanedUp then
				return
			end
			callback()
		end)
		sessionMaid:GiveTask(thread)
		return thread
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

	local function runStartupLoading()
		if hasCompletedStartupLoading then
			if loadingFrame then
				loadingFrame.Visible = false
			end
			debugLoading("Startup loading skipped because it has already completed")
			return
		end

		if not loadingFrame then
			debugLoadingWarn("Startup loading skipped: LoadingFrame not found")
			return
		end

		loadingFrame.Visible = true
		lockLocalMovementForLoading()
		fetchLoadingGameIcon()
		debugLoading("Startup loading started")

		startupLoadingTask = spawnSessionTask(function()
			local MIN_SECTION_DISPLAY_TIME = 0.25
			local PRE_HIDE_HOLD_TIME = 0.5
			local STANDARD_FADE_DURATION = 1
			local ATTRIBUTE_WAIT_TIMEOUT = 20
			local CAMERA_WAIT_TIMEOUT = 10
			local preloadTargets: { { instance: Instance, name: string } } = {}
			if loadingImage then
				table.insert(preloadTargets, { instance = loadingImage, name = "Image" })
			end
			if loadingGameImage then
				table.insert(preloadTargets, { instance = loadingGameImage, name = "GameImage" })
			end
			if loadingLightRay then
				table.insert(preloadTargets, { instance = loadingLightRay, name = "LightRay" })
			end
			if jumpscareImage then
				table.insert(preloadTargets, { instance = jumpscareImage, name = "JumpscareImage" })
			end

			local totalSteps = 1
				+ #loadingRemoteNames
				+ math.max(1, #preloadTargets)
				+ 3
				+ 4
				+ #loadingSystemTasks
				+ 1
				+ #loadingRequiredAttributes
			local completedSteps = 0

			local function setLoadingStatus(baseLabel: string, detail: string?)
				local formattedLabel = formatLoadingLabel(baseLabel, detail)
				updateLoadingProgress(completedSteps / totalSteps, formattedLabel)
				debugLoading(string.format("Loading status: %s [%d/%d]", formattedLabel, completedSteps, totalSteps))
			end

			local function markLoadingStep(baseLabel: string, detail: string?)
				completedSteps += 1
				local formattedLabel = formatLoadingLabel(baseLabel, detail)
				updateLoadingProgress(completedSteps / totalSteps, formattedLabel)
				debugLoading(
					string.format("Loading step complete: %s [%d/%d]", formattedLabel, completedSteps, totalSteps)
				)
			end

			local function jumpToDataLoad()
				completedSteps = totalSteps - #loadingRequiredAttributes
				local formattedLabel = formatLoadingLabel("Data Load", "Awaiting Server")
				loadingProgressFloor = math.max(loadingProgressFloor, completedSteps / totalSteps)
				hideLoadingSkipButton()
				updateLoadingProgress(completedSteps / totalSteps, formattedLabel)
				debugLoading(
					string.format(
						"Loading skip requested; jumping to %s [%d/%d]",
						formattedLabel,
						completedSteps,
						totalSteps
					)
				)
			end

			local function finishSection(sectionStartedAt: number)
				local elapsed = os.clock() - sectionStartedAt
				local remaining = MIN_SECTION_DISPLAY_TIME - elapsed
				if remaining > 0 then
					task.wait(remaining)
				end
			end

			local sectionStartedAt = os.clock()
			setLoadingStatus("Loading UI", "MainGUI")
			task.wait()
			markLoadingStep("Loading UI", "MainGUI")
			finishSection(sectionStartedAt)

			if not loadingSkipRequested then
				sectionStartedAt = os.clock()
				for _, remoteName in ipairs(loadingRemoteNames) do
					if loadingSkipRequested then
						break
					end
					setLoadingStatus("Loading Remotes", remoteName)
					remotes:WaitForChild(remoteName)
					if loadingSkipRequested then
						break
					end
					markLoadingStep("Loading Remotes", remoteName)
				end
				finishSection(sectionStartedAt)
			else
				jumpToDataLoad()
			end
			if loadingSkipRequested then
				jumpToDataLoad()
			end

			if not loadingSkipRequested then
				sectionStartedAt = os.clock()
				if #preloadTargets == 0 then
					markLoadingStep("Loading Core Assets", "None")
				else
					for _, preloadTarget in ipairs(preloadTargets) do
						if loadingSkipRequested then
							break
						end
						setLoadingStatus("Loading Core Assets", preloadTarget.name)
						pcall(function()
							ContentProvider:PreloadAsync({ preloadTarget.instance })
						end)
						if loadingSkipRequested then
							break
						end
						markLoadingStep("Loading Core Assets", preloadTarget.name)
					end
				end
				finishSection(sectionStartedAt)
			end
			if loadingSkipRequested then
				jumpToDataLoad()
			end

			if not loadingSkipRequested then
				sectionStartedAt = os.clock()
				setLoadingStatus("Loading World", "Worlds")
				local worldsFolder = workspace:WaitForChild("Worlds")
				markLoadingStep("Loading World", "Worlds")

				local currentWorld = (localPlayer:GetAttribute("Current_World") or "World1") :: string
				setLoadingStatus("Loading World", currentWorld)
				local world = worldsFolder:WaitForChild(currentWorld)
				markLoadingStep("Loading World", currentWorld)

				setLoadingStatus("Loading World", "LobbyRegion")
				local lobbyRegionContainer = world:WaitForChild("LobbyRegion_Model")
				lobbyRegionContainer:WaitForChild("LobbyRegion")
				markLoadingStep("Loading World", "LobbyRegion")
				finishSection(sectionStartedAt)
			end
			if loadingSkipRequested then
				jumpToDataLoad()
			end

			if not loadingSkipRequested then
				sectionStartedAt = os.clock()
				setLoadingStatus("Loading Character", "Character")
				local startupCharacter = localPlayer.Character or localPlayer.CharacterAdded:Wait()
				markLoadingStep("Loading Character", "Character")

				setLoadingStatus("Loading Character", "Humanoid")
				startupCharacter:WaitForChild("Humanoid")
				markLoadingStep("Loading Character", "Humanoid")

				setLoadingStatus("Loading Character", "HumanoidRootPart")
				startupCharacter:WaitForChild("HumanoidRootPart")
				markLoadingStep("Loading Character", "HumanoidRootPart")

				setLoadingStatus("Loading Character", "Camera")
				local cameraWaitStarted = os.clock()
				while workspace.CurrentCamera == nil and not loadingSkipRequested and not isCleanedUp do
					local waitedFor = os.clock() - cameraWaitStarted
					if waitedFor >= CAMERA_WAIT_TIMEOUT then
						debugLoadingWarn(
							string.format(
								"Timed out waiting for CurrentCamera after %.1fs, continuing with fallback",
								waitedFor
							)
						)
						break
					end
					task.wait()
				end
				if workspace.CurrentCamera == nil then
					debugLoadingWarn("CurrentCamera is still nil after timeout; continuing startup flow")
				end
				markLoadingStep("Loading Character", "Camera")
				finishSection(sectionStartedAt)
			end
			if loadingSkipRequested then
				jumpToDataLoad()
			end

			if not loadingSkipRequested then
				sectionStartedAt = os.clock()
				for _, systemTask in ipairs(loadingSystemTasks) do
					if loadingSkipRequested then
						break
					end
					setLoadingStatus("Loading Systems", systemTask)
					task.wait()
					if loadingSkipRequested then
						break
					end
					markLoadingStep("Loading Systems", systemTask)
				end
				finishSection(sectionStartedAt)
			end
			if loadingSkipRequested then
				jumpToDataLoad()
			end

			if not loadingSkipRequested then
				sectionStartedAt = os.clock()
				setLoadingStatus("Loading Cosmetics", "Startup")
				task.wait(0.15)
				markLoadingStep("Loading Cosmetics", "Startup")
				finishSection(sectionStartedAt)
			end
			if loadingSkipRequested then
				jumpToDataLoad()
			end

			sectionStartedAt = os.clock()
			for _, attributeName in ipairs(loadingRequiredAttributes) do
				hideLoadingSkipButton()
				setLoadingStatus("Data Load", attributeName)
				local waitStarted = os.clock()
				local hasWarnedLongWait = false
				local didTimeout = false
				while not loadingSkipRequested and not isCleanedUp do
					local attributeValue = localPlayer:GetAttribute(attributeName)
					if attributeName == "Data_Loaded" then
						if attributeValue == true then
							debugLoading("Data load ready: Data_Loaded=true")
							break
						end
					elseif attributeValue ~= nil then
						debugLoading(string.format("Data load ready: %s=%s", attributeName, tostring(attributeValue)))
						break
					end

					local waitedFor = os.clock() - waitStarted
					if not hasWarnedLongWait and waitedFor >= 3 then
						hasWarnedLongWait = true
						debugLoadingWarn(
							string.format("Still waiting on loading attribute %s after %.1fs", attributeName, waitedFor)
						)
					end

					if waitedFor >= ATTRIBUTE_WAIT_TIMEOUT then
						didTimeout = true
						debugLoadingWarn(
							string.format(
								"Timed out waiting on loading attribute %s after %.1fs, continuing with fallback",
								attributeName,
								waitedFor
							)
						)
						break
					end
					task.wait(0.1)
				end

				if isCleanedUp then
					return
				end

				if loadingSkipRequested and not didTimeout then
					break
				end

				markLoadingStep("Data Load", attributeName)
			end
			finishSection(sectionStartedAt)

			updateLoadingProgress(1, formatLoadingLabel("Data Load", "Complete"))
			debugLoading("Startup loading reached 100%")
			hasCompletedStartupLoading = true
			loadingProgressFloor = 1
			if loadingProgressTween then
				loadingProgressTween.Completed:Wait()
			end

			local fadeDuration = STANDARD_FADE_DURATION
			if loadingLevelsBarFrame then
				tweenGuiFadeOut(loadingLevelsBarFrame, fadeDuration)
			end
			if loadingSkipButtonFrame then
				tweenGuiFadeOut(loadingSkipButtonFrame, fadeDuration)
			end
			if loadingLightRay then
				tweenGuiFadeOut(loadingLightRay, fadeDuration)
			end
			if loadingGameImage then
				tweenGuiFadeOut(loadingGameImage, fadeDuration)
			end

			task.wait(fadeDuration)

			if loadingImage then
				local moveTween = TweenService:Create(
					loadingImage,
					TweenInfo.new(STANDARD_FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{
						Position = UDim2.new(0.5, 0, 0.5, 0),
						Size = UDim2.new(0.5, 0, 0.5, 0),
					}
				)
				moveTween:Play()
				moveTween.Completed:Wait()
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
			unlockLocalMovementForLoading()
			debugLoading("Startup loading finished and frame hidden")
			FavoriteGamePrompt.PromptAfterLoadingIfEligible(localPlayer)
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

		if instance.Name == "NotifShow_Template" then
			rebirthReadyUIState.template = instance
			kartPurchaseUIState.template = instance
			trailAffordableUIState.template = instance
			playtimeClaimableUIState.template = instance
			verifyClaimableUIState.template = instance
		elseif instance.Name == "RebirthButtonFrame" then
			rebirthReadyUIState.buttonFrame = instance
			if rebirthReadyUIState.refresh then
				task.defer(rebirthReadyUIState.refresh)
			end
		elseif instance.Name == "KartButtonFrame" then
			kartPurchaseUIState.buttonFrame = instance
			if kartPurchaseUIState.refresh then
				task.defer(kartPurchaseUIState.refresh)
			end
		elseif instance.Name == "TrailButtonFrame" then
			trailAffordableUIState.buttonFrame = instance
			if trailAffordableUIState.refresh then
				task.defer(trailAffordableUIState.refresh)
			end
		elseif instance.Name == "PlaytimeButtonFrame" then
			playtimeClaimableUIState.buttonFrame = instance
			if playtimeClaimableUIState.refresh then
				task.defer(playtimeClaimableUIState.refresh)
			end
		elseif instance.Name == "VerifyButtonFrame" then
			verifyClaimableUIState.buttonFrame = instance
			if verifyClaimableUIState.refresh then
				task.defer(verifyClaimableUIState.refresh)
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
		elseif instance.Name == "LoadingFrame" and instance:IsA("Frame") then
			loadingFrame = instance
			instance.Visible = not hasCompletedStartupLoading
			loadingImage = instance:FindFirstChild("Image") :: ImageLabel?
			loadingGameImage = instance:FindFirstChild("GameImage", true) :: ImageLabel?
			loadingLightRay = instance:FindFirstChild("LightRay") :: ImageLabel?
			loadingLevelsBarFrame = instance:FindFirstChild("LevelsBarFrame") :: Frame?
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
			loadingSkipButton = loadingSkipButtonFrame
				and loadingSkipButtonFrame:FindFirstChildWhichIsA("GuiButton", true)
			if loadingSkipButton and loadingSkipButton:GetAttribute("LoadingSkipBound") ~= true then
				loadingSkipButton:SetAttribute("LoadingSkipBound", true)
				loadingSkipButton.MouseButton1Click:Connect(function()
					if loadingSkipRequested then
						return
					end
					loadingSkipRequested = true
					hideLoadingSkipButton()
					updateLoadingProgress(0.9, formatLoadingLabel("Data Load", "Awaiting Server"))
				end)
			end
		elseif instance.Name == "ReturnToStageButton" then
			VisualFunctions.HUD.ReturnToStageButton = instance
			VisualFunctions.HUD.ReturnToStagePriceLabel = instance:FindFirstChild("PriceLabel", true) :: TextLabel?
			VisualFunctions.HUD.ReturnToStageCountdownLabel =
				instance:FindFirstChild("CountdownLabel", true) :: TextLabel?
			instance.Visible = false
			VisualFunctions.SetupPulsate(instance, 1.02)
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
			elseif instance.Name == "FriendMultiplier" then
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
					task.defer(refreshVerifyCountdownLabel)
				end
			elseif instance.Name == "WhenRewardLabel" and instance:FindFirstAncestor("VerifyFrame") ~= nil then
				verifyRewardWhenLabel = instance
				if refreshVerifyRewardValueLabels then
					task.defer(refreshVerifyRewardValueLabels)
				end
			elseif
				instance.Name == "XPRewardsLabel"
				and instance:FindFirstAncestor("GroupRewardsClaimableFrame") ~= nil
			then
				verifyRewardXPLabel = instance
				if refreshVerifyRewardValueLabels then
					task.defer(refreshVerifyRewardValueLabels)
				end
			elseif
				instance.Name == "WinRewardsLabel"
				and instance:FindFirstAncestor("GroupRewardsClaimableFrame") ~= nil
			then
				verifyRewardWinsLabel = instance
				if refreshVerifyRewardValueLabels then
					task.defer(refreshVerifyRewardValueLabels)
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
		if instance.Name == "RebirthFrame" and instance:IsA("Frame") then
			VisualFunctions.ActiveFrameGroup.RebirthFrame = instance
			instance.Visible = false
		elseif instance.Name == "TrailFrame" then
			VisualFunctions.ActiveFrameGroup.TrailFrame = instance
			instance.Visible = false
		elseif instance.Name == "KartFrame" then
			VisualFunctions.ActiveFrameGroup.KartFrame = instance
			instance.Visible = false
		elseif instance.Name == "VerifyFrame" then
			VisualFunctions.ActiveFrameGroup.VerifyFrame = instance
			instance.Visible = false
		elseif instance.Name == "TrollFrame" then
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
		elseif instance.Name == "PetsFrame" then
			VisualFunctions.ActiveFrameGroup.PetsFrame = instance
			instance.Visible = false
		elseif instance.Name == "ShopFrame" then
			VisualFunctions.ActiveFrameGroup.ShopFrame = instance
			instance.Visible = false
		elseif instance.Name == "RebirthConfirmFrame" then
			VisualFunctions.ActiveFrameGroup.RebirthConfirmFrame = instance
			instance.Visible = false
		elseif instance.Name == "RewardsFrame" then
			VisualFunctions.ActiveFrameGroup.RewardsFrame = instance
			instance.Visible = false
		elseif instance.Name == "DailyRewardFrame" then
			VisualFunctions.ActiveFrameGroup.DailyRewardFrame = instance
			instance.Visible = false
		elseif instance.Name == "SpinWheelFrame" and instance:IsA("Frame") then
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
		elseif instance.Name == "NotificationFrame" then
			VisualFunctions.HUD.NotificationFrame = instance
			instance.Visible = false
			if tutorialSystem then
				tutorialSystem:RefreshNotificationReferences()
			end
		elseif instance.Name == "StageProgressFrame" and instance:IsA("Frame") then
			stageProgressFrame = instance
			stageProgressTrackFrame = instance:FindFirstChild("TrackFrame", true) :: Frame?
			stageProgressMarkersFrame = stageProgressTrackFrame
				and stageProgressTrackFrame:FindFirstChild("Markers") :: Frame?
			stageProgressCurrentStageLabel = instance:FindFirstChild("CurrentStageLabel", true) :: TextLabel?
			stageProgressCurrentWorldLabel = (
				instance:FindFirstChild("CurrentWorldLabel", true)
				or instance:FindFirstChild("CurrentWORLDLabel", true)
				or instance:FindFirstChild("CurrentWorld", true)
			) :: TextLabel?
			stageProgressMarkerTemplate = stageProgressTrackFrame
				and stageProgressTrackFrame:FindFirstChild("StageMarkerTemplate") :: GuiObject?
			stageProgressAvatarTemplate = stageProgressTrackFrame
				and stageProgressTrackFrame:FindFirstChild("AvatarImageTemplate") :: ImageLabel?
			if stageProgressMarkerTemplate then
				stageProgressMarkerTemplate.Visible = false
			end
			if stageProgressAvatarTemplate then
				stageProgressAvatarTemplate.Visible = false
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
		elseif instance.Name == "SpeedBuyFrame" then
			VisualFunctions.HUD.SpeedBuyFrame = instance
		elseif instance.Name == "RightSideButtonsFrame" then
			VisualFunctions.HUD.RightSideButtonsFrame = instance
		elseif instance.Name == "FloatingFrame" then
			VisualFunctions.HUD.FloatingFrame = instance
		elseif instance.Name == "Float_CurrentSpeedFrame" then
			VisualFunctions.HUD.Float_CurrentSpeedFrame = instance
			instance.Visible = false
		elseif instance.Name == "WinCountFrame" then
			VisualFunctions.HUD.WinCountFrame = instance
		elseif instance.Name == "Float_CurrentWinFrame" then
			VisualFunctions.HUD.Float_CurrentWinFrame = instance
			instance.Visible = false
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
					textBox.Text = tostring(player:GetAttribute("Player_Speed") or DEFAULT_PLAYER_SPEED)
				end
				textBox.FocusLost:Connect(function(enterPressed)
					if not enterPressed then
						textBox.Text = tostring(player:GetAttribute("Player_Speed") or DEFAULT_PLAYER_SPEED)
						return
					end
					local val = tonumber(textBox.Text)
					if val then
						local SpeedAction = ReplicatedStorage.Remotes:FindFirstChild("SpeedAction")
						if SpeedAction and SpeedAction:IsA("RemoteEvent") then
							SpeedAction:FireServer(val)
						end
					end
					task.delay(0.1, function()
						textBox.Text = tostring(player:GetAttribute("Player_Speed") or DEFAULT_PLAYER_SPEED)
					end)
				end)
			end
		end

		-- 4. Hover & Click Interactions
		local hoverAttr = instance:GetAttribute("isHover")
		if hoverAttr ~= nil then
			VisualFunctions.SetupFrameHover(instance, 1.1, 15, 1.5)
			local hasButton = instance:IsA("GuiButton")
			for _, child in ipairs(instance:GetChildren()) do
				if child:IsA("GuiButton") then
					hasButton = true
					break
				end
			end
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
		then
			genericButton.MouseButton1Click:Connect(function()
				SoundService.PlayGuiSound("Click")
			end)
		end

		if targetFrameName then
			local button = if instance:IsA("GuiButton")
				then instance
				else instance:FindFirstChildWhichIsA("GuiButton", true)
			if button then
				button.MouseButton1Click:Connect(function()
					if targetFrameName == "TrollFrame" and not canUseTrollFrame then
						return
					end

					local targetFrame = VisualFunctions.ActiveFrameGroup[targetFrameName]
					if targetFrameName == "TrollFrame" and not (targetFrame and targetFrame.Visible) then
						hideReturnToStageButton()
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
				button.MouseButton1Click:Connect(function()
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
			and instance.Parent:IsA("Frame")
			and instance.Parent.Name ~= "SpinWheelFrame"
		then
			local targetParent = instance.Parent :: Frame
			local button = if instance:IsA("GuiButton")
				then instance
				else instance:FindFirstChildWhichIsA("GuiButton", true)
			if button and button.Parent == instance then
				button.MouseButton1Click:Connect(function()
					SoundService.PlayGuiSound("Close")
					if targetParent.Name == "TrollFrame" then
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
			if button and button:GetAttribute("TrollNavBound") ~= true then
				button:SetAttribute("TrollNavBound", true)
				trollPreviousButton = button
				button.MouseButton1Click:Connect(function()
					SoundService.PlayGuiSound("Click")
					cycleTrollTarget(-1)
				end)
			end
		elseif instance.Name == "NextPlayerButton" then
			local button = instance:FindFirstChildWhichIsA("GuiButton", true)
			if button and button:GetAttribute("TrollNavBound") ~= true then
				button:SetAttribute("TrollNavBound", true)
				trollNextButton = button
				button.MouseButton1Click:Connect(function()
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
			if button and button:GetAttribute("TrollActionBound") ~= true then
				button:SetAttribute("TrollActionBound", true)
				trollActionButtons[instance.Name] = button
				button.MouseButton1Click:Connect(function()
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
					button.MouseButton1Click:Connect(function()
						SoundService.PlayGuiSound("Click")
						local RebirthAction = ReplicatedStorage.Remotes:FindFirstChild("RebirthAction")
						if RebirthAction and RebirthAction:IsA("RemoteEvent") then
							RebirthAction:FireServer()
						end
					end)
				elseif instance.Name == "SkipRebirthButton" then
					button.MouseButton1Click:Connect(function()
						SoundService.PlayGuiSound("Click")
						local skipId = ProductService.DevProducts.SkipRebirth
						if skipId and skipId ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, skipId)
						end
					end)
				elseif instance.Name == "100KBuyButton" then
					button.MouseButton1Click:Connect(function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+100K"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "1MBuyButton" then
					button.MouseButton1Click:Connect(function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+1M"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "10MBuyButton" then
					button.MouseButton1Click:Connect(function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+10M"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "1000WinButton" then
					button.MouseButton1Click:Connect(function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+1000"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "5000WinButton" then
					button.MouseButton1Click:Connect(function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+5000"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "10000WinButton" then
					button.MouseButton1Click:Connect(function()
						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts["+10000"]
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "MultiplierSpeedProductButtonFrame" then
					button.MouseButton1Click:Connect(function()
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
					button.MouseButton1Click:Connect(function()
						if Players.LocalPlayer:GetAttribute("DisableWavesOnCooldown") == true then
							return
						end

						SoundService.PlayGuiSound("Click")
						local id = ProductService.DevProducts.DisableWaves
						if id and id ~= 0 then
							ProductService.promptProductPurchase(Players.LocalPlayer, id)
						end
					end)
				elseif instance.Name == "ReturnToStageButton" then
					button.MouseButton1Click:Connect(function()
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
					button.MouseButton1Click:Connect(function()
						SoundService.PlayGuiSound("Click")
						task.spawn(function()
							local promptOk, promptResult = pcall(function()
								return GroupService:PromptJoinAsync(VERIFY_GROUP_ID)
							end)
							if not promptOk then
								DebugModule.debugWarn(
									"Group prompt failed for VerifyButton: " .. tostring(promptResult),
									"MainOrchestrator"
								)
							else
								local status = promptResult :: Enum.GroupMembershipStatus
								if
									status ~= Enum.GroupMembershipStatus.Joined
									and status ~= Enum.GroupMembershipStatus.AlreadyMember
								then
									if status == Enum.GroupMembershipStatus.JoinRequestPending then
										local theme = VisualFunctions.NotificationThemes.Gold
										showNotificationRespectingTutorial(
											"GROUP REQUEST PENDING",
											theme.textColor,
											theme.gradientBottomColor
										)
									elseif status == Enum.GroupMembershipStatus.None then
										local theme = VisualFunctions.NotificationThemes.Red
										showNotificationRespectingTutorial(
											"GROUP JOIN CANCELED",
											theme.textColor,
											theme.gradientBottomColor
										)
									end
								end
							end

							local verifyRemote = ReplicatedStorage:WaitForChild("Remotes")
								:FindFirstChild("VerifyRewardRequest")
							if verifyRemote and verifyRemote:IsA("RemoteEvent") then
								verifyRemote:FireServer()
							end
						end)
					end)
				elseif SHOP_BUTTON_CONFIGS[instance.Name] then
					local shopConfig = SHOP_BUTTON_CONFIGS[instance.Name]
					button.MouseButton1Click:Connect(function()
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

	local player = localPlayer
	if player then
		local lastAllXP = player:GetAttribute("AllXPSpeed") or 0
		local displayedWinCount = player:GetAttribute("WinCount") or 0
		local winAnimationSession = 0
		local pendingWinCount: number? = nil
		local hasSuppressedInitialLoadedLevel = false
		local pendingPurchasedKarts: { [string]: boolean } = {}
		local previousOwnedKarts: { [string]: boolean } = table.clone(PlayerHandler.GetOwnedKarts(player))
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

			updateRebirthReadyBadgeVisibility(canRebirth)
			if canRebirth and not rebirthReadyUIState.wasReady then
				local theme = VisualFunctions.NotificationThemes.Purple
				showNotificationRespectingTutorial("YOU CAN NOW REBIRTH!", theme.textColor, theme.gradientBottomColor)
			end
			rewardCelebrationController:UpdateRebirthReady(canRebirth, rebirthReadyUIState.buttonFrame)

			rebirthReadyUIState.wasReady = canRebirth
		end
		rebirthReadyUIState.refresh = refreshRebirthReadyState
		sessionMaid:GiveTask(function()
			rebirthReadyUIState.refresh = nil
			rebirthReadyUIState.wasReady = false
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
		local function handleOwnedKartsChangedForBadge()
			local currentOwnedKarts = PlayerHandler.GetOwnedKarts(player)
			if player:GetAttribute("Data_Loaded") ~= true then
				previousOwnedKarts = table.clone(currentOwnedKarts)
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

		local function distributeValue(totalValue: number, count: number): { number }
			local distributed = {}
			local currentSum = 0
			for i = 1, count do
				local nextSum = math.round(totalValue * (i / count))
				table.insert(distributed, nextSum - currentSum)
				currentSum = nextSum
			end

			return distributed
		end

		local function setDisplayedWinCount(value: number)
			displayedWinCount = value
			VisualFunctions.UpdateWinLabel(displayedWinCount)
		end

		local productCache = {}
		local updateStageProgressPlayerMarkers: (() -> ())? = nil
		local stageProgressMarkerUpdateAccumulator = STAGE_PROGRESS_MARKER_UPDATE_INTERVAL
		local verifyRewardCountdownAccumulator = VERIFY_REWARD_COUNTDOWN_UPDATE_INTERVAL
		local characterStateMaid: Maid? = nil
		local kartEntryFrames: {
			[string]: {
				frame: Frame,
				equipButton: Frame?,
			},
		} = {}
		local trailEntryFrames: {
			[string]: {
				frame: Frame,
				buyButton: Frame?,
				robuxBuyButton: Frame?,
				equipButton: Frame?,
				robuxOriginalPosition: UDim2?,
				robuxOriginalSize: UDim2?,
			},
		} =
			{}
		local disableWaveCountdownThread = 0
		local returnToStageOfferThread = 0
		local returnToStageOfferTask: thread? = nil
		local pendingSkipRebirthNotificationUntil = 0
		hideReturnToStageButton = function()
			returnToStageOfferThread += 1
			if returnToStageOfferTask then
				task.cancel(returnToStageOfferTask)
				returnToStageOfferTask = nil
			end

			local frame = VisualFunctions.HUD.ReturnToStageButton
			if frame then
				frame.Visible = false
				for _, descendant in ipairs(frame:GetDescendants()) do
					if descendant:IsA("GuiObject") then
						descendant.Visible = false
					end
				end
			end
		end
		sessionMaid:GiveTask(hideReturnToStageButton)

		local function formatClockDuration(totalSeconds: number): string
			local clamped = math.max(0, math.floor(totalSeconds))
			local hours = math.floor(clamped / 3600)
			local minutes = math.floor((clamped % 3600) / 60)
			local seconds = clamped % 60
			return string.format("%02d:%02d:%02d", hours, minutes, seconds)
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

		local function disconnectStageProgressTrackedPlayer(playerToDisconnect: Player)
			local playerMaid = stageProgressTrackedPlayerMaids[playerToDisconnect]
			if playerMaid then
				playerMaid:DoCleaning()
				stageProgressTrackedPlayerMaids[playerToDisconnect] = nil
			end

			local existingMarker = stageProgressPlayerMarkers[playerToDisconnect.UserId]
			if existingMarker and existingMarker.Parent then
				existingMarker:Destroy()
			end

			stageProgressPlayerMarkers[playerToDisconnect.UserId] = nil
			stageProgressPlayerMarkerMissingUntil[playerToDisconnect.UserId] = nil
			stageProgressAvatarCache[playerToDisconnect.UserId] = nil
		end

		local function connectStageProgressTrackedPlayer(playerToTrack: Player)
			disconnectStageProgressTrackedPlayer(playerToTrack)

			local playerMaid = Maid.new()
			stageProgressTrackedPlayerMaids[playerToTrack] = playerMaid
			playerMaid:GiveTask(playerToTrack.CharacterAdded:Connect(function()
				task.defer(updateStageProgressPlayerMarkers)
			end))
			playerMaid:GiveTask(playerToTrack.CharacterRemoving:Connect(function()
				task.defer(updateStageProgressPlayerMarkers)
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
		})
		tutorialSystem:RefreshNotificationReferences()
		tutorialSystem:Start()
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
			getDailyRewardFrame = function(): Frame?
				return VisualFunctions.ActiveFrameGroup.DailyRewardFrame
			end,
			closeOtherFrames = MainFunctions.CloseOtherFrames,
			openWindow = VisualFunctions.OpenWindow,
		})
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

			local kartModelsFolder = ReplicatedStorage:FindFirstChild("KartModels")
			local sourceFolderName = if typeof(config.sourceFolder) == "string" then config.sourceFolder else "Gamepasses"
			local sourceFolder = kartModelsFolder and kartModelsFolder:FindFirstChild(sourceFolderName)
			local kartModel = sourceFolder and sourceFolder:FindFirstChild(kartModelName)
			local xpGain = getNumericAttribute(kartModel, "XP_Gain")
			if typeof(xpGain) == "number" then
				return string.format("+%s/Steps", tostring(math.round(xpGain)))
			end

			return config.stepsText
		end

		local function getStageProgressWorldData(worldName: string): (Instance?, BasePart?, BasePart?, Instance?)
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

		local function formatCurrentWorldLabel(worldName: string?): string
			if typeof(worldName) ~= "string" or worldName == "" then
				return "World 0"
			end

			local worldNumber = string.match(worldName, "^World(%d+)$")
			if worldNumber then
				return "World " .. worldNumber
			end

			return worldName
		end

		local function updateStageProgressTrackStyle(worldName: string?)
			if not stageProgressTrackFrame then
				return
			end

			local style = if typeof(worldName) == "string" and STAGE_PROGRESS_WORLD_STYLES[worldName]
				then STAGE_PROGRESS_WORLD_STYLES[worldName]
				else STAGE_PROGRESS_WORLD_STYLES.Fallback

			stageProgressTrackFrame.BackgroundColor3 = style.backgroundColor
		end

		local function getClampedTrackAlpha(
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

		local function clearStageProgressMarkers()
			for _, marker in ipairs(stageProgressMarkerClones) do
				marker:Destroy()
			end
			table.clear(stageProgressMarkerClones)
		end

		local function clearStageProgressPlayerMarkers()
			for _, marker in pairs(stageProgressPlayerMarkers) do
				marker:Destroy()
			end
			table.clear(stageProgressPlayerMarkers)
			table.clear(stageProgressPlayerMarkerMissingUntil)
		end

		local function ensureStageProgressAvatarMarker(targetPlayer: Player): ImageLabel?
			if not stageProgressTrackFrame or not stageProgressAvatarTemplate then
				return nil
			end

			local existing = stageProgressPlayerMarkers[targetPlayer.UserId]
			if existing and existing.Parent then
				return existing
			end

			local clone = stageProgressAvatarTemplate:Clone()
			clone.Name = string.format("PlayerMarker_%d", targetPlayer.UserId)
			clone.Visible = true
			clone.Image = ""
			clone.ImageTransparency = 0
			clone.Parent = stageProgressTrackFrame
			clone.ZIndex = if targetPlayer == player then 5 else 3
			local requestId = (clone:GetAttribute("StageProgressAvatarRequestId") or 0) :: number
			requestId += 1
			clone:SetAttribute("StageProgressAvatarRequestId", requestId)
			clone:SetAttribute("StageProgressAvatarUserId", targetPlayer.UserId)
			stageProgressPlayerMarkers[targetPlayer.UserId] = clone

			spawnSessionTask(function()
				local cachedImage = stageProgressAvatarCache[targetPlayer.UserId]
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
						stageProgressAvatarCache[targetPlayer.UserId] = content
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

		local function rebuildStageProgressMarkers()
			clearStageProgressMarkers()

			local currentWorld = player:GetAttribute("Current_World")
			if typeof(currentWorld) ~= "string" or currentWorld == "" then
				stageProgressWorldName = nil
				stageProgressStartPosition = nil
				stageProgressEndPosition = nil
				if stageProgressCurrentWorldLabel then
					stageProgressCurrentWorldLabel.Text = "World 0"
				end
				return
			end

			stageProgressWorldName = currentWorld
			updateStageProgressTrackStyle(currentWorld)
			if stageProgressCurrentWorldLabel then
				stageProgressCurrentWorldLabel.Text = formatCurrentWorldLabel(currentWorld)
			end

			local _, lobbyRegion, stageEnd, stagesFolder = getStageProgressWorldData(currentWorld)
			if
				not lobbyRegion
				or not stagesFolder
				or not stageProgressTrackFrame
				or not stageProgressMarkersFrame
				or not stageProgressMarkerTemplate
			then
				stageProgressStartPosition = nil
				stageProgressEndPosition = nil
				return
			end

			stageProgressStartPosition = lobbyRegion.Position
			stageProgressEndPosition = if stageEnd then stageEnd.Position else nil

			local stageEntries = {}
			for _, child in ipairs(stagesFolder:GetChildren()) do
				local stageNumber = child:GetAttribute("Stage")
				local stagePart = if child:IsA("BasePart")
					then child
					else child:FindFirstChildWhichIsA("BasePart", true)
				if typeof(stageNumber) == "number" and stagePart and stagePart:IsA("BasePart") then
					local alpha =
						getClampedTrackAlpha(stageProgressStartPosition, stageProgressEndPosition, stagePart.Position)
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

			if not stageProgressEndPosition and #stageEntries > 0 then
				stageProgressEndPosition = stageEntries[#stageEntries].position
			end

			if not stageProgressEndPosition then
				stageProgressStartPosition = nil
				return
			end

			local minimumSpacingScale = 0.015
			if stageProgressTrackFrame.AbsoluteSize.X > 0 then
				minimumSpacingScale = math.max(
					minimumSpacingScale,
					stageProgressMarkerTemplate.AbsoluteSize.X / stageProgressTrackFrame.AbsoluteSize.X
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
				local markerClone = stageProgressMarkerTemplate:Clone()
				markerClone.Name = "StageMarker_" .. tostring(stageEntry.stageNumber)
				markerClone.Visible = true
				markerClone.ZIndex = 1
				markerClone.Parent = stageProgressMarkersFrame

				local alpha = math.clamp(adjustedAlphas[index], 0, 1)
				markerClone.Position = UDim2.new(
					alpha,
					stageProgressMarkerTemplate.Position.X.Offset,
					stageProgressMarkerTemplate.Position.Y.Scale,
					stageProgressMarkerTemplate.Position.Y.Offset
				)
				table.insert(stageProgressMarkerClones, markerClone)
			end
		end

		local function tryRefreshStageProgress()
			rebuildStageProgressMarkers()
			if updateStageProgressPlayerMarkers then
				updateStageProgressPlayerMarkers()
			end
		end

		updateStageProgressPlayerMarkers = function()
			if stageProgressFrame and not stageProgressFrame.Visible then
				return
			end

			local currentWorld = player:GetAttribute("Current_World")
			local currentStage = player:GetAttribute("CurrentStage")

			if stageProgressCurrentStageLabel then
				stageProgressCurrentStageLabel.Text =
					string.format("Stage %d", if typeof(currentStage) == "number" then currentStage else 0)
			end

			if typeof(currentWorld) ~= "string" or currentWorld == "" then
				clearStageProgressPlayerMarkers()
				updateStageProgressTrackStyle(nil)
				if stageProgressCurrentWorldLabel then
					stageProgressCurrentWorldLabel.Text = "World 0"
				end
				return
			end

			if stageProgressCurrentWorldLabel then
				stageProgressCurrentWorldLabel.Text = formatCurrentWorldLabel(currentWorld)
			end
			updateStageProgressTrackStyle(currentWorld)

			if
				stageProgressWorldName ~= currentWorld
				or not stageProgressStartPosition
				or not stageProgressEndPosition
			then
				rebuildStageProgressMarkers()
			end

			if not stageProgressStartPosition or not stageProgressEndPosition then
				clearStageProgressPlayerMarkers()
				return
			end

			if not stageProgressTrackFrame or not stageProgressAvatarTemplate then
				return
			end

			local visibleUserIds = {}
			for _, targetPlayer in ipairs(Players:GetPlayers()) do
				if targetPlayer:GetAttribute("Current_World") ~= currentWorld then
					continue
				end

				local character = targetPlayer.Character
				local rootPart = character and character:FindFirstChild("HumanoidRootPart")
				if not rootPart or not rootPart:IsA("BasePart") then
					local existingMarker = stageProgressPlayerMarkers[targetPlayer.UserId]
					local missingUntil = stageProgressPlayerMarkerMissingUntil[targetPlayer.UserId]
					if missingUntil == nil then
						missingUntil = tick() + STAGE_PROGRESS_MARKER_MISSING_GRACE
						stageProgressPlayerMarkerMissingUntil[targetPlayer.UserId] = missingUntil
					end

					if existingMarker and existingMarker.Parent and tick() <= missingUntil then
						existingMarker.Visible = true
						visibleUserIds[targetPlayer.UserId] = true
					end
					continue
				end

				stageProgressPlayerMarkerMissingUntil[targetPlayer.UserId] = nil

				local marker = ensureStageProgressAvatarMarker(targetPlayer)
				if not marker then
					continue
				end

				local alpha =
					getClampedTrackAlpha(stageProgressStartPosition, stageProgressEndPosition, rootPart.Position)
				marker.Position = UDim2.new(
					alpha,
					stageProgressAvatarTemplate.Position.X.Offset,
					stageProgressAvatarTemplate.Position.Y.Scale,
					stageProgressAvatarTemplate.Position.Y.Offset
				)
				marker.Visible = true
				marker.ZIndex = if targetPlayer == player then 5 else 3
				visibleUserIds[targetPlayer.UserId] = true
			end

			for userId, marker in pairs(stageProgressPlayerMarkers) do
				if not visibleUserIds[userId] then
					marker.Visible = false
				end
			end
		end

		local KART_FRAME_CONFIGS = {
			{
				kartName = "AdvancedTank",
				displayName = "Advanced Tank",
				gamePassId = ProductService.Gamepasses["AdvancedTank"],
				backgroundColor = Color3.new(0, 1, 1),
				gradientBottomColor = Color3.new(0, 0.3843, 1),
			},
			{
				kartName = "ShoppingKart",
				displayName = "Shopping Kart",
				gamePassId = ProductService.Gamepasses["ShoppingKart"],
				backgroundColor = Color3.new(0.6745, 0.6471, 0.6667),
				gradientBottomColor = Color3.new(0.302, 0.302, 0.302),
			},
			{
				kartName = "FormulaCar",
				displayName = "Formula Car",
				gamePassId = ProductService.Gamepasses["FormulaCar"],
				backgroundColor = Color3.new(1, 0.3059, 0.3059),
				gradientBottomColor = Color3.new(0.8078, 0, 0.0118),
			},
			{
				kartName = "1_FlameKart",
				displayName = "Flame Kart",
				sourceFolder = "Specials",
				wheelOnly = true,
				backgroundColor = Color3.fromRGB(0, 255, 0),
				gradientBottomColor = Color3.fromRGB(0, 130, 15),
			},
		}

		local function updateShopButtons()
			for frameName, config in pairs(SHOP_BUTTON_CONFIGS) do
				local buttonFrame = root:FindFirstChild(frameName, true)
				if not buttonFrame or not buttonFrame:IsA("Frame") then
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
					if shouldUseMarketplaceImage and passImage and (passImage:IsA("ImageLabel") or passImage:IsA("ImageButton")) then
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

		local function showReturnToStageButton(stage: number, duration: number)
			local frame = VisualFunctions.HUD.ReturnToStageButton
			if not frame then
				DebugModule.debugWarn("ReturnToStage button show failed: HUD frame missing", "MainOrchestrator")
				return
			end

			local trollFrame = VisualFunctions.ActiveFrameGroup.TrollFrame
			if trollFrame and trollFrame.Visible then
				hideReturnToStageButton()
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

			local button = frame:FindFirstChild("TextButton", true)
			if button and button:IsA("TextButton") then
				button.Text = string.format("RETURN TO STAGE %d", stage)
			else
				DebugModule.debugWarn("ReturnToStage TextButton missing", "MainOrchestrator")
			end

			local countdownLabel = VisualFunctions.HUD.ReturnToStageCountdownLabel
			if countdownLabel then
				countdownLabel.Text = string.format("%ds", duration)
			else
				DebugModule.debugWarn("ReturnToStage CountdownLabel missing", "MainOrchestrator")
			end

			updateReturnToStagePrice()

			returnToStageOfferTask = task.spawn(function()
				local startedAt = os.clock()
				while threadId == returnToStageOfferThread do
					local remaining = math.max(0, math.ceil(duration - (os.clock() - startedAt)))
					if countdownLabel then
						countdownLabel.Text = string.format("%ds", remaining)
					end

					if remaining <= 0 then
						break
					end

					task.wait(0.1)
				end

				if threadId == returnToStageOfferThread and frame then
					frame.Visible = false
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

				hideReturnToStageButton()
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

			local isOnCooldown = player:GetAttribute("DisableWavesOnCooldown") == true
			local cooldownEnd = player:GetAttribute("DisableWavesCooldownEnd") or 0
			local countdownLabel = VisualFunctions.HUD.DisableWaveCountdownLabel
			VisualFunctions.SetFrameInteractableState(frame, not isOnCooldown)

			disableWaveCountdownThread += 1
			local threadId = disableWaveCountdownThread

			if not isOnCooldown or typeof(cooldownEnd) ~= "number" or cooldownEnd <= 0 then
				if disableWaveCountdownTask then
					task.cancel(disableWaveCountdownTask)
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
				task.cancel(disableWaveCountdownTask)
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

				if threadId == disableWaveCountdownThread and countdownLabel then
					countdownLabel.Text = "0s"
					countdownLabel.Visible = false
				end

				if disableWaveCountdownTask == coroutine.running() then
					disableWaveCountdownTask = nil
				end
			end)
		end

		local function formatTrailMultiplier(multiplier: number): string
			local text = string.format("%.2f", multiplier)
			text = text:gsub("%.00$", "")
			text = text:gsub("(%..-)0$", "%1")
			return text
		end

		local function getOrCreateEquipButton(entryFrame: Frame): Frame?
			local existing = entryFrame:FindFirstChild("EquipButton")
			if existing and existing:IsA("Frame") then
				return existing
			end

			local buyButton = entryFrame:FindFirstChild("BuyButton")
			if not buyButton or not buyButton:IsA("Frame") then
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

		local function applyWheelStyle(frame: Frame, isLocked: boolean, normalColor: Color3, normalBottomColor: Color3)
			local backgroundColor = if isLocked then Color3.fromRGB(254, 199, 41) else normalColor
			local gradientBottomColor = if isLocked then Color3.fromRGB(255, 85, 0) else normalBottomColor
			frame.BackgroundColor3 = backgroundColor
			frame:SetAttribute("OriginalDisabledBaseColor", nil)
			local gradient = frame:FindFirstChildOfClass("UIGradient")
			if not gradient then
				gradient = Instance.new("UIGradient")
				gradient.Parent = frame
			end
			gradient.Rotation = 90
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(1, gradientBottomColor),
			})
		end

		local function openSpinWheelFromShop()
			MainFunctions.SetFrameVisibleSimple("TrailFrame", false)
			MainFunctions.SetFrameVisibleSimple("KartFrame", false)
			local requestId = player:GetAttribute("SpinWheelOpenRequested")
			local nextRequestId = if typeof(requestId) == "number" then requestId + 1 else 1
			player:SetAttribute("SpinWheelOpenRequested", nextRequestId)
		end

		local function updateTrailEntryPrice(trailName: string, config)
			local entry = trailEntryFrames[trailName]
			if not entry or not entry.robuxBuyButton then
				return
			end
			if config.RewardSource == "SpinWheel" then
				entry.robuxBuyButton.Visible = false
				return
			end

			local priceLabel = entry.robuxBuyButton:FindFirstChild("PriceLabel", true)
			local trailTypeImage = entry.frame:FindFirstChild("TrailType", true)

			local productId = ProductService.DevProducts[config.ProductKey]
			if not productId then
				if priceLabel and priceLabel:IsA("TextLabel") then
					priceLabel.Text = "---"
				end
				return
			end

			spawnSessionTask(function()
				local info = productCache[productId]
				if not info then
					local success, result = pcall(function()
						return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
					end)
					if success then
						info = result
						productCache[productId] = result
					end
				end

				if info then
					if priceLabel and priceLabel:IsA("TextLabel") and priceLabel.Parent then
						priceLabel.Text = tostring(info.PriceInRobux or 0)
					end

					if trailTypeImage and trailTypeImage:IsA("ImageLabel") and trailTypeImage.Parent then
						local iconId = tonumber(info.IconImageAssetId)
						if iconId and iconId > 0 then
							trailTypeImage.Image = "rbxassetid://" .. tostring(iconId)
						end
					end
				end
			end)
		end

		local function updateTrailShop()
			for trailName, entry in pairs(trailEntryFrames) do
				local config = PlayerHandler.GetTrailConfig(trailName)
				if not config then
					continue
				end

				local isOwned = PlayerHandler.OwnsTrail(player, trailName)
				local isEquipped = player:GetAttribute("Trail_Equipped") == trailName
				local currentWins = player:GetAttribute("WinCount") or 0
				local isWheelOnly = config.RewardSource == "SpinWheel"

				entry.frame.BackgroundColor3 = if isWheelOnly and not isOwned
					then Color3.fromRGB(254, 199, 41)
					else config.BackgroundColor
				local frameGradient = entry.frame:FindFirstChildOfClass("UIGradient")
				if not frameGradient then
					frameGradient = Instance.new("UIGradient")
					frameGradient.Parent = entry.frame
				end
				frameGradient.Rotation = 90
				frameGradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
					ColorSequenceKeypoint.new(
						1,
						if isWheelOnly and not isOwned
							then Color3.fromRGB(255, 85, 0)
							else config.GradientBottomColor
					),
				})

				local trailNameLabel = entry.frame:FindFirstChild("TrailName", true)
				if trailNameLabel and trailNameLabel:IsA("TextLabel") then
					trailNameLabel.Text = string.upper(config.DisplayName)
				end

				local speedAmountLabel = entry.frame:FindFirstChild("SpeedAmount", true)
				if speedAmountLabel and speedAmountLabel:IsA("TextLabel") then
					speedAmountLabel.Text = string.format("%sx Speed Boost", formatTrailMultiplier(config.XPMultiplier))
				end

				local trailTypeLabel = entry.frame:FindFirstChild("TrailType", true)
				if trailTypeLabel and trailTypeLabel:IsA("TextLabel") then
					trailTypeLabel.Text = if isWheelOnly and not isOwned
						then "SPIN"
						else if config.CanBuyWithWins then "WINS / ROBUX" else "ROBUX ONLY"
				end

				local buyTextButton = entry.buyButton and entry.buyButton:FindFirstChild("TextButton", true)
				if buyTextButton and buyTextButton:IsA("TextButton") then
					buyTextButton.Text = string
						.format("%d", math.round(config.WinsRequired))
						:reverse()
						:gsub("(%d%d%d)", "%1,")
						:reverse()
						:gsub("^,", "")
				end

				local equipTextButton = entry.equipButton and entry.equipButton:FindFirstChild("TextButton", true)
				if equipTextButton and equipTextButton:IsA("TextButton") then
					equipTextButton.Text = if isWheelOnly and not isOwned
						then "SPIN"
						else if isEquipped then "UNEQUIP" else "EQUIP"
				end

				if entry.buyButton then
					entry.buyButton.Visible = not isWheelOnly and not isOwned and config.CanBuyWithWins
					VisualFunctions.SetFrameInteractableState(
						entry.buyButton,
						not isWheelOnly and currentWins >= config.WinsRequired
					)
				end

				if entry.robuxBuyButton then
					entry.robuxBuyButton.Visible = not isWheelOnly and not isOwned
					if not config.CanBuyWithWins then
						if entry.buyButton then
							entry.robuxBuyButton.Position = entry.buyButton.Position
							entry.robuxBuyButton.Size = entry.buyButton.Size
						end
					else
						if entry.robuxOriginalPosition then
							entry.robuxBuyButton.Position = entry.robuxOriginalPosition
						end
						if entry.robuxOriginalSize then
							entry.robuxBuyButton.Size = entry.robuxOriginalSize
						end
					end
				end

				if entry.equipButton then
					entry.equipButton.Visible = isWheelOnly or isOwned
					if isWheelOnly then
						applyWheelStyle(
							entry.equipButton,
							not isOwned,
							Color3.fromRGB(0, 255, 0),
							Color3.fromRGB(0, 130, 15)
						)
					end
					VisualFunctions.SetFrameInteractableState(
						entry.equipButton,
						if isWheelOnly and not isOwned then true else isOwned and not isEquipped
					)
				end

				updateTrailEntryPrice(trailName, config)
			end
		end

		local function updateKartShop()
			for _, config in ipairs(KART_FRAME_CONFIGS) do
				local entry = kartEntryFrames[config.kartName]
				if not entry then
					continue
				end

				local isOwned = PlayerHandler.OwnsKart(player, config.kartName)
				local isEquipped = player:GetAttribute("Kart_Equipped") == config.kartName
				local isWheelOnly = config.wheelOnly == true

				entry.frame.BackgroundColor3 = if isWheelOnly and not isOwned
					then Color3.fromRGB(254, 199, 41)
					else config.backgroundColor
				local frameGradient = entry.frame:FindFirstChildOfClass("UIGradient")
				if not frameGradient then
					frameGradient = Instance.new("UIGradient")
					frameGradient.Parent = entry.frame
				end
				frameGradient.Rotation = 90
				frameGradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
					ColorSequenceKeypoint.new(
						1,
						if isWheelOnly and not isOwned
							then Color3.fromRGB(255, 85, 0)
							else config.gradientBottomColor
					),
				})

				local kartNameLabel = entry.frame:FindFirstChild("KartName", true)
				if kartNameLabel and kartNameLabel:IsA("TextLabel") then
					kartNameLabel.Text = string.upper(config.displayName)
					kartNameLabel.TextColor3 = config.backgroundColor
				end

				local kartTypeImage = entry.frame:FindFirstChild("KartType", true)
				if
					kartTypeImage
					and (kartTypeImage:IsA("ImageLabel") or kartTypeImage:IsA("ImageButton"))
					and typeof(config.gamePassId) == "number"
				then
					local info = getMarketplaceInfoCached(config.gamePassId, Enum.InfoType.GamePass)
					if info then
						local iconAssetId = tonumber((info :: any).IconImageAssetId)
						if iconAssetId and iconAssetId > 0 then
							kartTypeImage.Image = "rbxassetid://" .. tostring(iconAssetId)
						end
					end
				end

				local speedAmountLabel = entry.frame:FindFirstChild("SpeedAmount", true)
				if speedAmountLabel and speedAmountLabel:IsA("TextLabel") then
					local stepsText = getKartShopStepsText({
						kartModelName = config.kartName,
						stepsText = "+0/Steps",
					})
					speedAmountLabel.Text = stepsText or "+0/Steps"
				end

				if entry.equipButton then
					local textButton = entry.equipButton:FindFirstChild("TextButton", true)
					if textButton and textButton:IsA("TextButton") then
						if isWheelOnly and not isOwned then
							textButton.Text = "SPIN"
						elseif isEquipped then
							textButton.Text = "EQUIPPED"
						elseif isOwned then
							textButton.Text = "EQUIP"
						else
							textButton.Text = "BUY"
						end
					end

					if isWheelOnly then
						applyWheelStyle(
							entry.equipButton,
							not isOwned,
							Color3.fromRGB(0, 255, 0),
							Color3.fromRGB(0, 130, 15)
						)
					end
					VisualFunctions.SetFrameInteractableState(entry.equipButton, isOwned and not isEquipped)
				end
			end
		end

		local function buildKartShop()
			local kartFrame = VisualFunctions.ActiveFrameGroup.KartFrame
			local scrollBackground = kartFrame and kartFrame:FindFirstChild("ScrollBackground")
			local scrollingFrame = scrollBackground and scrollBackground:FindFirstChild("ScrollingFrame")
			if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") then
				return
			end

			local template = scrollingFrame:FindFirstChild("KartTemplate")
			if not template or not template:IsA("Frame") then
				return
			end

			for _, child in ipairs(scrollingFrame:GetChildren()) do
				if child ~= template and child:IsA("Frame") then
					child:Destroy()
				end
			end
			table.clear(kartEntryFrames)
			template.Visible = false

			local sortedKartConfigs = table.clone(KART_FRAME_CONFIGS)
			table.sort(sortedKartConfigs, function(a, b)
				local kartModelsFolder = ReplicatedStorage:FindFirstChild("KartModels")
				local aSourceFolder = kartModelsFolder and kartModelsFolder:FindFirstChild(a.sourceFolder or "Gamepasses")
				local bSourceFolder = kartModelsFolder and kartModelsFolder:FindFirstChild(b.sourceFolder or "Gamepasses")
				local aGain = getNumericAttribute(
					aSourceFolder and aSourceFolder:FindFirstChild(a.kartName),
					"XP_Gain"
				) or 0
				local bGain = getNumericAttribute(
					bSourceFolder and bSourceFolder:FindFirstChild(b.kartName),
					"XP_Gain"
				) or 0

				if aGain == bGain then
					return a.displayName < b.displayName
				end

				return aGain > bGain
			end)

			for index, config in ipairs(sortedKartConfigs) do
				local clone = template:Clone()
				clone.Name = config.kartName .. "Template"
				clone.LayoutOrder = index
				clone.Visible = true
				clone.Parent = scrollingFrame

				local equipButton = clone:FindFirstChild("EquipButton")
				if equipButton and equipButton:IsA("Frame") then
					local textButton = equipButton:FindFirstChild("TextButton", true)
					if textButton and textButton:IsA("TextButton") then
						textButton.MouseButton1Click:Connect(function()
							SoundService.PlayGuiSound("Click")

							local isOwned = PlayerHandler.OwnsKart(player, config.kartName)
							if config.wheelOnly == true and not isOwned then
								openSpinWheelFromShop()
								return
							end

							if not isOwned then
								if typeof(config.gamePassId) == "number" then
									ProductService.promptGamePassPurchase(player, config.gamePassId)
								end
								return
							end

							kartActionRemote:FireServer("Equip", config.kartName)
						end)
					end
				end

				kartEntryFrames[config.kartName] = {
					frame = clone,
					equipButton = if equipButton and equipButton:IsA("Frame") then equipButton else nil,
				}
			end

			updateKartShop()
		end

		local function buildTrailShop()
			local trailFrame = VisualFunctions.ActiveFrameGroup.TrailFrame
			local scrollBackground = trailFrame and trailFrame:FindFirstChild("ScrollBackground")
			local scrollingFrame = scrollBackground and scrollBackground:FindFirstChild("ScrollingFrame")
			if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") then
				return
			end

			local template = scrollingFrame:FindFirstChild("SpeedTrailTemplate")
			if not template or not template:IsA("Frame") then
				return
			end

			for _, child in ipairs(scrollingFrame:GetChildren()) do
				if child ~= template and child:IsA("Frame") then
					child:Destroy()
				end
			end
			table.clear(trailEntryFrames)
			template.Visible = false

			for index, trailName in ipairs(PlayerHandler.TRAIL_ORDER) do
				local config = PlayerHandler.GetTrailConfig(trailName)
				if not config then
					continue
				end

				local clone = template:Clone()
				clone.Name = trailName .. "Template"
				clone.LayoutOrder = index
				clone.Visible = true
				clone.Parent = scrollingFrame

				local buyButton = clone:FindFirstChild("BuyButton")
				local robuxBuyButton = clone:FindFirstChild("RobuxBuyButton")
				local equipButton = getOrCreateEquipButton(clone)

				if buyButton and buyButton:IsA("Frame") then
					local textButton = buyButton:FindFirstChild("TextButton", true)
					if textButton and textButton:IsA("TextButton") then
							textButton.MouseButton1Click:Connect(function()
							SoundService.PlayGuiSound("Click")
							if config.RewardSource == "SpinWheel" and not PlayerHandler.OwnsTrail(player, trailName) then
								openSpinWheelFromShop()
								return
							end
							local trailRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("TrailAction")
							if trailRemote and trailRemote:IsA("RemoteEvent") then
								trailRemote:FireServer("BuyWithWins", trailName)
							end
						end)
					end
				end

				if robuxBuyButton and robuxBuyButton:IsA("Frame") then
					local textButton = robuxBuyButton:FindFirstChild("TextButton", true)
					if textButton and textButton:IsA("TextButton") then
						textButton.MouseButton1Click:Connect(function()
							SoundService.PlayGuiSound("Click")
							local productId = ProductService.DevProducts[config.ProductKey]
							if productId and productId ~= 0 then
								ProductService.promptProductPurchase(Players.LocalPlayer, productId)
							end
						end)
					end
				end

				if equipButton then
					local textButton = equipButton:FindFirstChild("TextButton", true)
					if textButton and textButton:IsA("TextButton") then
						textButton.MouseButton1Click:Connect(function()
							SoundService.PlayGuiSound("Click")
							local trailRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("TrailAction")
							if trailRemote and trailRemote:IsA("RemoteEvent") then
								trailRemote:FireServer("Equip", trailName)
							end
						end)
					end
				end

				trailEntryFrames[trailName] = {
					frame = clone,
					buyButton = if buyButton and buyButton:IsA("Frame") then buyButton else nil,
					robuxBuyButton = if robuxBuyButton and robuxBuyButton:IsA("Frame") then robuxBuyButton else nil,
					equipButton = equipButton,
					robuxOriginalPosition = if robuxBuyButton and robuxBuyButton:IsA("Frame")
						then robuxBuyButton.Position
						else nil,
					robuxOriginalSize = if robuxBuyButton and robuxBuyButton:IsA("Frame")
						then robuxBuyButton.Size
						else nil,
				}
			end

			updateTrailShop()
		end

		if VisualFunctions.HUD.X2WinPromptButton then
			VisualFunctions.HUD.X2WinPromptButton.Activated:Connect(function()
				ProductService.promptGamePassPurchase(player, ProductService.Gamepasses["2xWins"])
			end)
		end

		local function updateXPProductLabels()
			-- XP purchases are ONLY scaled by the DevProduct multiplier.
			-- Rebirth and Misc multipliers are intentionally excluded here
			-- to match what AddXPSpeedProduct does on the server.
			local devMult = player:GetAttribute("DevProduct_XPSpeedMultiplier") or 1

			DebugModule.debugPrint(string.format("updateXPProductLabels - DevMult=%.1f", devMult), "MainOrchestrator")

			local function format(val: number)
				return "+" .. VisualFunctions.FormatNumber(val * devMult)
			end

			local mappings = {
				{ Label = VisualFunctions.Labels.Xp100KValueLabel, Value = 100000, Name = "100K" },
				{ Label = VisualFunctions.Labels.Xp1MValueLabel, Value = 1000000, Name = "1M" },
				{ Label = VisualFunctions.Labels.Xp10MValueLabel, Value = 10000000, Name = "10M" },
			}

			for _, entry in ipairs(mappings) do
				local label = entry.Label
				if label then
					if label:IsA("TextLabel") or label:IsA("TextButton") then
						local old = label.Text
						label.Text = format(entry.Value)
						DebugModule.debugPrint(
							string.format("Updated %s Label: %s -> %s", entry.Name, old, label.Text),
							"MainOrchestrator"
						)
					else
						DebugModule.debugPrint(
							string.format("Label for %s exists but is NOT a TextLabel/TextButton", entry.Name),
							"MainOrchestrator"
						)
					end
				else
					DebugModule.debugPrint(
						string.format("Label for %s is MISSING from mappings", entry.Name),
						"MainOrchestrator"
					)
				end
			end
		end

		local function updateTrailMultiplierDisplay()
			local equippedTrail = player:GetAttribute("Trail_Equipped")
			if typeof(equippedTrail) ~= "string" or equippedTrail == "" or equippedTrail == "None" then
				VisualFunctions.UpdateTrailMultiplierLabel(nil, nil, nil, nil)
				return
			end

			local trailConfig = PlayerHandler.GetTrailConfig(equippedTrail)
			if not trailConfig then
				VisualFunctions.UpdateTrailMultiplierLabel(nil, nil, nil, nil)
				return
			end

			VisualFunctions.UpdateTrailMultiplierLabel(
				equippedTrail,
				trailConfig.XPMultiplier,
				trailConfig.BackgroundColor,
				trailConfig.GradientBottomColor
			)
		end

		local function updateUI()
			local currentXP = player:GetAttribute("CurrentXPSpeed") or 0
			local maxXP = player:GetAttribute("MaxXPSpeed") or 25
			local level = player:GetAttribute("CurrentLevel") or 1
			local maxLevel = player:GetAttribute("MaxLevel") or 25
			local rebirthMulti = player:GetAttribute("Rebirth_XPMultiplier") or 1
			local friendMulti = player:GetAttribute("Friend_XPMultiplier") or 1
			local totalXP = player:GetAttribute("AllXPSpeed") or 0
			local maxSpeed = player:GetAttribute("Max_Player_Speed") or DEFAULT_MAX_PLAYER_SPEED

			lastLevel = level
			lastMaxSpeed = maxSpeed

			VisualFunctions.UpdateXPLabel(currentXP, maxXP)
			VisualFunctions.UpdateXPProgressBar(currentXP, maxXP)
			VisualFunctions.UpdateLevelProgressBar(level, maxLevel)
			VisualFunctions.UpdateLevelNeededLabel(level, maxLevel)
			VisualFunctions.UpdateLevelLabel(level, maxLevel)
			VisualFunctions.UpdateRebirthMultiLabel(rebirthMulti)
			VisualFunctions.UpdateFriendMultiplierLabel(friendMulti)
			updateTrailMultiplierDisplay()
			VisualFunctions.UpdateAllXPLabel(totalXP)
			VisualFunctions.UpdateMaxSpeedLabel(maxSpeed)
			refreshRebirthReadyState()

			if VisualFunctions.HUD.CustomSpeedTextBox then
				VisualFunctions.HUD.CustomSpeedTextBox.Text =
					tostring(player:GetAttribute("Player_Speed") or DEFAULT_PLAYER_SPEED)
			end

			lastAllXP = totalXP
			local nextStats = PlayerHandler.GetNextRebirthStats(player)
			VisualFunctions.UpdateRebirthPreview(
				rebirthMulti,
				nextStats.NextMultiplier,
				maxLevel,
				nextStats.NextMaxLevel
			)
			setDisplayedWinCount(player:GetAttribute("WinCount") or 0)
		end

		local function updateAllXPDisplay()
			local currentTotal = player:GetAttribute("AllXPSpeed") or 0
			lastAllXP = currentTotal
			VisualFunctions.UpdateAllXPLabel(currentTotal)
		end

		local function updateXPDisplay()
			local current = player:GetAttribute("CurrentXPSpeed") or 0
			local max = player:GetAttribute("MaxXPSpeed") or 25
			VisualFunctions.UpdateXPLabel(current, max)
			VisualFunctions.UpdateXPProgressBar(current, max)
		end

		local function updateLevelDisplay()
			local lvl = player:GetAttribute("CurrentLevel") or 1
			local maxL = player:GetAttribute("MaxLevel") or 25
			local multi = player:GetAttribute("Rebirth_XPMultiplier") or 1
			local maxS = player:GetAttribute("Max_Player_Speed") or DEFAULT_MAX_PLAYER_SPEED
			VisualFunctions.UpdateLevelLabel(lvl, maxL)
			VisualFunctions.UpdateLevelProgressBar(lvl, maxL)
			VisualFunctions.UpdateLevelNeededLabel(lvl, maxL)
			local isInitialLoadedJump = not hasSuppressedInitialLoadedLevel and lvl > lastLevel + 1
			if isInitialLoadedJump then
				hasSuppressedInitialLoadedLevel = true
			elseif lvl > lastLevel then
				SoundService.PlayGuiSound("LevelUp")
				VisualFunctions.ShowLevelUpNotification(lastLevel, lvl, lastMaxSpeed, maxS)
			end
			lastLevel = lvl
			lastMaxSpeed = maxS
			local nextStats = PlayerHandler.GetNextRebirthStats(player)
			VisualFunctions.UpdateRebirthPreview(multi, nextStats.NextMultiplier, maxL, nextStats.NextMaxLevel)
			refreshRebirthReadyState()
			if tutorialSystem then
				tutorialSystem:OnProgressChanged()
			end
		end

		local function updateMaxSpeedDisplay()
			local maxS = player:GetAttribute("Max_Player_Speed") or DEFAULT_MAX_PLAYER_SPEED
			VisualFunctions.UpdateMaxSpeedLabel(maxS)
			lastMaxSpeed = maxS
		end

		local function updatePlayerSpeedDisplay()
			if VisualFunctions.HUD.CustomSpeedTextBox then
				VisualFunctions.HUD.CustomSpeedTextBox.Text =
					tostring(player:GetAttribute("Player_Speed") or DEFAULT_PLAYER_SPEED)
			end
		end

		local function updateRebirthAndProductDisplay()
			updateUI()
			updateXPProductLabels()
			updateVerifyRewardValueLabels()
		end

		local function updateDevProductDisplay()
			updateMultiplierShop()
			updateXPProductLabels()
			updateVerifyRewardValueLabels()
		end

		local function updateMiscMultiplierDisplay()
			updateXPProductLabels()
			updateTrailMultiplierDisplay()
			updateVerifyRewardValueLabels()
		end

		local function updateFriendMultiplierDisplay()
			local friendMultiplier = player:GetAttribute("Friend_XPMultiplier") or 1
			VisualFunctions.UpdateFriendMultiplierLabel(friendMultiplier)
			updateVerifyRewardValueLabels()
		end

		local function updateWinMultiplierDisplay()
			updateX2WinShop()
			updateXPProductLabels()
			updateShopButtons()
			updateKartShop()
			updateVerifyRewardValueLabels()
		end

		local function updateWinDisplay()
			local currentWins = player:GetAttribute("WinCount") or 0
			if winAnimationSession > 0 then
				pendingWinCount = currentWins
			else
				setDisplayedWinCount(currentWins)
			end
			updateTrailShop()
			refreshAffordableTrailBadge()
			if tutorialSystem then
				tutorialSystem:OnProgressChanged()
			end
		end
		local function updateOwnedTrailsDisplay()
			updateTrailShop()
			refreshAffordableTrailBadge()
		end
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("AllXPSpeed"):Connect(updateAllXPDisplay))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("CurrentXPSpeed"):Connect(updateXPDisplay))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("MaxXPSpeed"):Connect(updateXPDisplay))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("CurrentLevel"):Connect(updateLevelDisplay))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("Max_Player_Speed"):Connect(updateMaxSpeedDisplay))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("Player_Speed"):Connect(updatePlayerSpeedDisplay))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("MaxLevel"):Connect(updateRebirthAndProductDisplay))
		sessionMaid:GiveTask(
			player:GetAttributeChangedSignal("Rebirth_XPMultiplier"):Connect(updateRebirthAndProductDisplay)
		)
		sessionMaid:GiveTask(
			player:GetAttributeChangedSignal("DevProduct_XPSpeedMultiplier"):Connect(updateDevProductDisplay)
		)
		sessionMaid:GiveTask(
			player:GetAttributeChangedSignal("Misc_XPSpeedMultiplier"):Connect(updateMiscMultiplierDisplay)
		)
		sessionMaid:GiveTask(
			player:GetAttributeChangedSignal("Friend_XPMultiplier"):Connect(updateFriendMultiplierDisplay)
		)
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("WinMultiplier"):Connect(updateWinMultiplierDisplay))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("OwnedTrails"):Connect(updateOwnedTrailsDisplay))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("OwnedKarts"):Connect(function()
			updateKartShop()
			handleOwnedKartsChangedForBadge()
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("Trail_Equipped"):Connect(function()
			updateTrailShop()
			updateTrailMultiplierDisplay()
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("Kart_Equipped"):Connect(function()
			updateKartShop()
			handleKartEquippedChangedForBadge()
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("WinCount"):Connect(updateWinDisplay))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
			refreshAffordableTrailBadge()
			refreshPlaytimeClaimableBadge()
			dailyRewardPromptController:RefreshBadge()
			refreshVerifyClaimableBadge()
			updateVerifyRewardValueLabels()
			updateVerifyGroupCountdown(nil)
			dailyRewardPromptController:TryAutoOpen()
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("TutorialCompleted"):Connect(function()
			dailyRewardPromptController:OnTutorialCompletedChanged()
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal(VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE):Connect(function()
			refreshVerifyClaimableBadge()
			updateVerifyGroupCountdown(nil)
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal(VERIFY_REWARD_CLAIM_COUNT_ATTRIBUTE):Connect(function()
			updateVerifyRewardValueLabels()
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("Treadmill_Active"):Connect(function()
			if tutorialSystem then
				tutorialSystem:OnProgressChanged()
			end
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("Treadmill_XPMultiplier"):Connect(function()
			updateVerifyRewardValueLabels()
		end))
		sessionMaid:GiveTask(
			player:GetAttributeChangedSignal("DisableWavesOnCooldown"):Connect(updateDisableWaveButton)
		)
		sessionMaid:GiveTask(
			player:GetAttributeChangedSignal("DisableWavesCooldownEnd"):Connect(updateDisableWaveButton)
		)
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("HasVIPPass"):Connect(function()
			updateShopButtons()
			updateKartShop()
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("StarterPackRewardClaimed"):Connect(function()
			updateShopButtons()
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("Current_World"):Connect(function()
			updateStageProgressPlayerMarkers()
			if tutorialSystem then
				tutorialSystem:OnProgressChanged()
			end
		end))
		sessionMaid:GiveTask(player:GetAttributeChangedSignal("CurrentStage"):Connect(updateStageProgressPlayerMarkers))
		StageProgressBindings.Bind({
			sessionMaid = sessionMaid,
			playersService = Players,
			workspace = Workspace,
			player = player,
			connectTrackedPlayer = connectStageProgressTrackedPlayer,
			disconnectTrackedPlayer = disconnectStageProgressTrackedPlayer,
			updateStageProgressPlayerMarkers = updateStageProgressPlayerMarkers,
			tryRefreshStageProgress = tryRefreshStageProgress,
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
			onWinAwarded = function(amount: number, source: string?)
				local splitCount = 1
				local absAmount = math.abs(math.floor(amount))
				if amount > 0 then
					rewardCelebrationController:PlayRewardCelebration(source == "WinButton")
				end
				if absAmount >= 10000 then
					splitCount = 5
				elseif absAmount >= 100 then
					splitCount = 3
				end

				local targetWins = player:GetAttribute("WinCount") or (displayedWinCount + amount)
				local startWins = targetWins - amount
				local distributed = distributeValue(amount, splitCount)
				local lifetime = 2

				winAnimationSession += 1
				local currentSession = winAnimationSession
				pendingWinCount = targetWins
				setDisplayedWinCount(startWins)

				VisualFunctions.CreateFloatingText(VisualFunctions.HUD.Float_CurrentWinFrame, amount, splitCount, {
					Lifetime = lifetime,
					TargetFrame = VisualFunctions.HUD.WinCountFrame,
				})

				spawnSessionTask(function()
					local runningTotal = startWins
					task.wait(lifetime * 0.6)

					for i, value in ipairs(distributed) do
						if currentSession ~= winAnimationSession then
							return
						end

						runningTotal += value
						setDisplayedWinCount(runningTotal)

						if i < #distributed then
							task.wait(0.05)
						end
					end

					if currentSession == winAnimationSession then
						winAnimationSession = 0
						setDisplayedWinCount(pendingWinCount or runningTotal)
						pendingWinCount = nil
					end
				end)
			end,
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
					VisualFunctions.ShowNotification("YOU REBIRTHED!!", theme.textColor, theme.gradientBottomColor)
				end

				local rebirthFrame = VisualFunctions.ActiveFrameGroup.RebirthFrame
				if rebirthFrame and rebirthFrame.Visible then
					VisualFunctions.CloseWindow(rebirthFrame)
				end

				if tick() < pendingSkipRebirthNotificationUntil then
					task.delay(1.1, function()
						showRebirthNotification()
					end)
				else
					showRebirthNotification()
				end
			end,
			onShowNotification = function(message: string, themeName: string?, notificationStyle: string?)
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
					showReturnToStageButton(stage, duration)
				else
					hideReturnToStageButton()
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
				if loadingFrame and loadingFrame.Visible and not hasCompletedStartupLoading then
					task.defer(lockLocalMovementForLoading)
				end
				if tutorialSystem then
					task.defer(function()
						tutorialSystem:OnProgressChanged()
					end)
				end
			end,
			onRequestReturnToStageOffer = function()
				local requestRemote = remotes:WaitForChild("RequestReturnToStageOffer")
				if requestRemote:IsA("RemoteEvent") then
					requestRemote:FireServer()
				end
			end,
			onPromptProductPurchaseFinished = function(productId: number, wasPurchased: boolean)
				if productId == ProductService.DevProducts.SkipRebirth and wasPurchased then
					pendingSkipRebirthNotificationUntil = tick() + 1.5
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

		updateUI()
		updateMultiplierShop()
		updateDisableWavePrice()
		updateDisableWaveButton()
		updateReturnToStagePrice()
		updateShopButtons()
		buildKartShop()
		buildTrailShop()
		refreshKartPurchaseBadge()
		refreshAffordableTrailBadge()
		refreshPlaytimeClaimableBadge()
		dailyRewardPromptController:RefreshBadge()
		refreshVerifyClaimableBadge()
		updateVerifyRewardValueLabels()
		updateVerifyGroupCountdown(nil)
		tryRefreshStageProgress()
		dailyRewardPromptController:TryAutoOpen()
		if tutorialSystem then
			tutorialSystem:OnProgressChanged()
		end
		sessionMaid:GiveTask(task.delay(0.5, function()
			updateX2WinShop()
			updateXPProductLabels()
			updateShopButtons()
			updateKartShop()
			refreshKartPurchaseBadge()
			updateTrailShop()
			refreshAffordableTrailBadge()
			refreshPlaytimeClaimableBadge()
			dailyRewardPromptController:RefreshBadge()
			refreshVerifyClaimableBadge()
			updateVerifyRewardValueLabels()
			updateVerifyGroupCountdown(nil)
			tryRefreshStageProgress()
			dailyRewardPromptController:TryAutoOpen()
		end))
		setDisplayedWinCount(player:GetAttribute("WinCount") or 0)
		sessionMaid:GiveTask(RunService.Heartbeat:Connect(function(dt)
			stageProgressMarkerUpdateAccumulator =
				math.min(stageProgressMarkerUpdateAccumulator + dt, STAGE_PROGRESS_MARKER_UPDATE_INTERVAL * 3)
			if stageProgressMarkerUpdateAccumulator >= STAGE_PROGRESS_MARKER_UPDATE_INTERVAL then
				stageProgressMarkerUpdateAccumulator = 0
				if updateStageProgressPlayerMarkers and (not stageProgressFrame or stageProgressFrame.Visible) then
					updateStageProgressPlayerMarkers()
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
