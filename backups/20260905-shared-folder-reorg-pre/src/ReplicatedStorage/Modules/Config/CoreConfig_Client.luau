--!strict

-- CoreConfig_Client.luau

local CoreConfig = {}

-- Debug system configuration (universal across all modules)
CoreConfig.debugSystem = {
	enabled = true, -- Enable diagnostics for the current feature investigation.
	showPrints = true, -- Show targeted feature diagnostics.
	showWarns = true, -- Show targeted feature warnings.
	validationWarns = true, -- Validation warnings may be emitted in live servers; independent of studioOnly.
	showErrors = true, -- Show debug error messages
	timestamp = true, -- Include timestamps in debug messages
	studioOnly = true, -- Keep ordinary diagnostics out of published servers; validationWarn bypasses this gate.

	-- Temporary analysis scope: soft teleport/reward validation only.
	enabledModules = {
		"ValidationService_Server",
	},
	disabledModules = {},
	moduleOverrides = {}, -- Highest-priority per-module override
}

-- Performance configuration (universal)
CoreConfig.performance = {
	maxFrameTime = 1 / 60, -- Target frame time (60 FPS)
}

-- Platform Experience Notification configuration.
-- Message IDs are Creator Dashboard notification-string IDs, not secrets.
CoreConfig.experienceNotifications = {
	enabled = true,
	studioEnabled = false, -- Open Cloud delivery requires a published experience.
	promptOnJoin = true,
	studioPromptEnabled = false,
	promptDelaySeconds = 5,
	maxSendsPerPlayerSession = 1,
	messageIds = {
		DailyRewardReady = "87f29950-6a58-f344-b2c3-aa40304b9db3",
		SpinWheelReady = "21b959a7-1739-664c-b901-83461d6dbe3f",
		GroupRewardReady = "63eeae6c-1497-4a41-8716-c9ef1e470670",
		BloodMoonLive = "0fc76257-0e28-2342-868f-edcd87b84c2e",
		AdminAbuseLive = "e91bce0e-bd27-304c-b072-5ec583871cb0",
		TwoXWeekendLive = "f40cdd3a-7f48-ce4c-8b15-a52570213ac0",
	},
	categories = {
		DailyRewardReady = "DailyReward",
		SpinWheelReady = "SpinWheel",
		GroupRewardReady = "GroupReward",
		BloodMoonLive = "BloodMoon",
		AdminAbuseLive = "AdminAbuse",
		TwoXWeekendLive = "TwoXWeekend",
	},
}

-- Client graphics overrides
CoreConfig.clientGraphics = {
	disableGlobalShadowsOnMobile = true, -- Disables Lighting.GlobalShadows for mobile clients to reduce render/shadowmap cost.
}

-- Client Bloodmoon ground visual that follows only grounded characters.
CoreConfig.bloodmoonParticle = {
	enabled = true, -- Shows the local BloodmoonParticle while the Bloodmoon environment is fully active.
	size = 512, -- Width and depth of the ground particle in studs.
	verticalOffset = -5, -- Ground probe depth below the player's root part before the floor lock is applied.
	positionUpdateFps = 15, -- Limits ground-following raycasts and CFrame writes.
	positionMovementThreshold = 2, -- Minimum grounded movement in studs before another position update.
	rotationThresholdDegrees = 20, -- Minimum grounded rotation before another orientation update.
	groundRaycastInterval = 0.25, -- Minimum time between ground raycasts while the player is moving.
}

-- Client environment transition settings.
CoreConfig.environment = {
	transitionDurationSeconds = 6, -- Duration for each supported environment tween.
	atmosphereLeadSeconds = 0.5, -- Starts atmosphere before ambient and remaining environment values.
}

-- Client-side distance culling for non-gameplay visuals.
CoreConfig.clientCulling = {
	enabled = true, -- Master toggle for CollectionService-based client visual culling.
	updateInterval = 0.25, -- Seconds between culling visibility passes.
	mobileDistanceMultiplier = 0.65, -- Scales culling distances down on touch-only mobile clients.
	autoTagBillboards = true, -- Automatically tags BillboardGuis so lobby labels can be culled by distance.
	autoTagSurfaceGuis = true, -- Automatically tags SurfaceGuis in Workspace so world panels can be culled by distance.
	autoTagDecorativeEffects = true, -- Automatically tags safe Workspace particles/lights/beams/trails for distance culling.
	billboardDistance = 450, -- BillboardGui distance before it is disabled.
	surfaceGuiDistance = 450, -- SurfaceGui distance before it is disabled.
	particleDistance = 260, -- ParticleEmitter distance before tagged emitters are disabled.
	lightDistance = 320, -- Light distance before tagged lights are disabled.
	beamDistance = 360, -- Beam distance before tagged beams are disabled.
	trailDistance = 300, -- Trail distance before tagged trails are disabled.
}

-- Client-owned tsunami visuals; server replicates state only, not moving geometry.
CoreConfig.clientTsunamiVisuals = {
	enabled = true, -- Master toggle for local tsunami visual reconstruction.
	billboardMaxDistance = 450, -- Maximum distance for tsunami labels.
	disableShadows = true, -- Avoid shadowmap work for cosmetic wave copies.
	soundGraceSeconds = 1.5, -- Late joins do not replay an old wave crash sound.
}

-- UI scaling safeguards (client)
CoreConfig.uiAdjuster = {
	referenceViewport = Vector2.new(1920, 1080), -- Baseline viewport used to compute UI scale ratio.
	minScaleRatio = 0.45, -- Prevents ultra-small scaling on narrow/tall device viewports.
	maxScaleRatio = 1.35, -- Prevents oversized scaling on large viewport extremes.
	noUpscaleOnMobile = true, -- Prevents mobile clients from scaling above baseline text/tile sizes.
	mobileMaxScaleRatio = 1.0, -- Effective max ratio when noUpscaleOnMobile is enabled.
	minTextSize = 2, -- Absolute floor for TextSize/UITextSizeConstraint calculations.
	minTileOffset = 1, -- TileSize offset floor to satisfy non-zero tile requirements.
}

-- Client-only debug toggles. Server authority remains in CoreConfig_Server.
CoreConfig.clientDebug = {
	dailyRewards = {
		debugSequentialClaimMode = true,
	},
	playtimeRewards = {
		debugSequentialClaimMode = true,
	},
}
-- Social configuration (shared by client/server systems)
CoreConfig.social = {
	verifyGroupId = 13706307, -- Group ID used for verify reward checks/prompts.
	friendInviteMultiplierStep = 0.1, -- Permanent XP multiplier increase granted per unique referred player.
	friendInviteTopbarIconImage = "rbxassetid://112009101194397", -- Topbar icon image used for the invite-friends button.
	friendInviteTopbarLabel = "Invite Friends!", -- Short label shown beside the topbar invite icon.
	friendInvitePromptMessage = "Invite friends to join and earn +0.10x multiplier per unique friend!", -- Prompt text shown in Roblox's invite modal.
}

-- Event board fallback for an event that is already active when a player joins.
CoreConfig.eventBoard = {
	activeEventId = "", -- Optional single-experience fallback when no universe-specific ID is configured.
	activeEventIdsByUniverse = {
		[9799168239] = "1575542102719333001", -- Active event fallback for +1 Speed DEV.
		[9824719186] = "3893769414042059370", -- Active event fallback for +1 Speed live.
	},
	eventThumbnailIdsByEvent = {
		-- SocialService can omit event thumbnail metadata at runtime, so keep a narrow fallback per event.
		["1575542102719333001"] = 104775788509568, -- +1 Speed DEV event thumbnail.
		["6019459865490096779"] = 137113910559154, -- +1 Speed live event thumbnail.
		["3893769414042059370"] = 95114581728373, -- ADMIN ABUSE live event thumbnail.
	},
	secondaryEventTitles = {
		-- EventBoard shows these only when no major event is active or upcoming.
		"2X WEEKEND",
	},
}

-- Timed purchase prompt configuration. Product IDs remain in ProductService.
CoreConfig.promptBuy = {
	minDeaths = 3,
	maxDeaths = 5,
	minMinutes = 2,
	maxMinutes = 5,
	shortIntervalSelectionWeight = 2, -- Makes 2-3 minute rolls twice as likely as longer rolls.
	displayDurationSeconds = 15,
	temporaryBoostSelectionWeight = 4, -- Makes temporary boosts more likely in timed product prompts.
	bloodmoonKartSelectionWeight = 3, -- Blood Moon karts are strongly biased during the event.
	studioAlwaysShow = false, -- Studio-only prompt test; live servers still use death/time triggers.
	studioShowOwnedProducts = false, -- Studio-only preview: include already-owned permanent offers in the prompt.
	visiblePosition = UDim2.new(0.873, 0, 0.874, 0),
	hiddenPosition = UDim2.new(2, 0, 0.874, 0),
	excludedDevProductKeys = {
		ReturnToStage = true, -- Return-to-stage uses its own strict offer flow.
		TrollPlayer = true, -- Requires a selected target from TrollFrame.
	},
	permanentDevProductKeys = {
		GalaxyTrail = "Trail",
		DemonTrail = "Trail",
		GoldTrail = "Trail",
		PurpleTrail = "Trail",
		BlueTrail = "Trail",
		GreenTrail = "Trail",
	},
	descriptionPools = {
		Default = {
			"Power up your run and progress faster!",
			"Grab this boost and make your next run count!",
			"Upgrade your adventure with this special offer!",
		},
		Speed = {
			"Gain extra XP Speed and level up faster!",
			"Power up your speed progress with this offer!",
			"Reach higher levels faster with extra XP Speed!",
		},
		Wins = {
			"Get more wins and unlock better rewards faster!",
			"Add wins to your run and reach new karts sooner!",
			"Build your win count with this instant reward!",
		},
		Trail = {
			"Equip this trail for a permanent multiplier boost!",
			"Leave a brighter trail behind while powering up!",
			"Add this trail to your collection and progress faster!",
		},
		Treadmill = {
			"Power up treadmill gains with this permanent gamepass!",
			"Earn speed faster while using treadmills!",
			"Turn every treadmill run into faster progress!",
		},
		Kart = {
			"Unlock this kart and race with a bigger speed boost!",
			"Upgrade your ride and push toward faster progress!",
			"Add this kart to your collection and hit the track!",
		},
		TemporaryBoost = {
			"Activate 2x gains for 10 minutes and speed up your run!",
			"Temporarily double your progress and push ahead faster!",
			"Get 10 minutes of 2x power for your next run!",
		},
		Spin = {
			"Add spins and try your luck on the reward wheel!",
			"Get more wheel spins and chase exclusive rewards!",
			"Spin for a chance at powerful rewards and rare items!",
		},
		Utility = {
			"Use this boost to make your next run easier!",
			"Get a helpful advantage for your next challenge!",
			"Make faster progress with this useful upgrade!",
		},
	},
}

-- Leaderboard debug controls
CoreConfig.leaderboard = {
	debugUseFakeData = false, -- Replace datastore entries with fake rows for UI/dev testing.
	debugAppendFakeData = false, -- Append fake rows after real entries for mixed testing.
}

-- Leveling/reward tuning
CoreConfig.leveling = {
	verifyRewardXP = 5000, -- XP granted after successful group verification.
	verifyRewardWins = 50, -- Wins granted after successful group verification.
	verifyRewardDailyGrowthMultiplier = 1.1, -- Multiplier applied per successful group reward claim (compounding).
	verifyRewardRoundStep = 5, -- Rewards round up to the next multiple of this value.
	verifyRewardClaimCountAttribute = "VerifyRewardClaimCount", -- Attribute tracking successful verify-claim count.
	verifyRewardCooldownSeconds = 4 * 60 * 60, -- Cooldown between group verify reward claims (4h).
	debugVerifyIgnoreCooldownInStudio = true, -- Studio-only debug: verify reward is always claimable (cooldown ignored/reset).
	rebirthConfettiColors = { -- Gradient palette used by rebirth confetti burst.
		Color3.fromRGB(255, 215, 0),
		Color3.fromRGB(255, 43, 43),
		Color3.fromRGB(0, 200, 255),
		Color3.fromRGB(57, 255, 20),
		Color3.fromRGB(170, 0, 255),
	},
	rebirthConfettiDuration = 1.5, -- Seconds for rebirth confetti effect.
	rebirthConfettiCount = 70, -- Total confetti particles for rebirth celebrations.
	rewardCelebrationConfettiCount = 45, -- Total confetti particles for win/tutorial-complete celebrations.
}

-- Spin wheel timing and local testing switches.
CoreConfig.spinWheel = {
	freeSpinCooldownSeconds = 24 * 60 * 60, -- One free spin becomes available each day.
	debugFreeSpinReadyInStudio = true, -- Studio-only: make another free spin ready after testing a spin.
	rewardedAdMaxSpins = 5, -- Maximum rewarded-ad spin opportunities in one reset window.
	rewardedAdResetSeconds = 24 * 60 * 60, -- Reset the rewarded-ad quota after a full day.
	rewardedAdCooldownSeconds = 5 * 60, -- Delay between completed rewarded-ad spin opportunities.
	idleRotationDegreesPerSecond = 8, -- Slow wheel rotation while the modal is idle.
	spinRotationDuration = 4, -- Seconds used for an active wheel spin.
	spinFullTurns = 6, -- Full rotations before the selected reward settles.
	wheelTickVolume = 0.25, -- Volume of each reward-segment tick during an active spin.
	wheelTickMinPlaybackSpeed = 1, -- Lowest tick pitch; keep the ending from sounding lowered.
	wheelTickMaxPlaybackSpeed = 1.6, -- Highest tick pitch while the wheel is moving quickly.
	wheelTickReferenceDegreesPerSecond = 720, -- Angular speed that maps to the maximum tick pitch.
}

-- Temporary boost durations. Ad rewards are shorter than direct purchases.
CoreConfig.temporaryBoosts = {
	purchaseDurationSeconds = 10 * 60, -- Duration granted by a Robux purchase.
	rewardedAdDurationSeconds = 5 * 60, -- Duration granted by a rewarded ad.
}

-- Rewarded-video ad placements and their analytics identifiers.
CoreConfig.rewardedVideo = {
	enabled = true, -- Master toggle; Creator Hub eligibility still controls ad availability.
	requestCooldownSeconds = 3, -- Server cooldown between ad requests from one player.
	placements = {
		PromptTempSpeedBoost = 618250252180809, -- Temporary speed boost ad placement.
		PromptTempWinBoost = 511368025590066, -- Temporary win boost ad placement.
		ReturnToStage = 854035274061902, -- Return-to-stage ad placement.
		SpinWheel = 798599652050120, -- Uses Roblox's default rewarded-video placement until a dedicated ID is assigned.
	},
}

-- Bloodmoon progression display. Unlock IDs match authored trail and kart assets.
CoreConfig.bloodmoonProgress = {
	enabled = true,
	maxWins = 100,
	debugStudioWinAmount = 1, -- Studio-only Bloodmoon win amount; published servers always use base amount 1.
	unlocks = {
		{ id = "EclipseTrail", displayName = "Eclipse Trail", winsRequired = 5, kind = "Trail" },
		{
			id = "1_CrimsonRunner",
			displayName = "Crimson Runner",
			winsRequired = 20,
			kind = "Kart",
			imageAssetId = "rbxassetid://140523900133990",
		},
		{
			id = "2_NightGlider",
			displayName = "Night Glider",
			winsRequired = 50,
			kind = "Kart",
			imageAssetId = "rbxassetid://104926778382950",
			legacyIds = { "NightGlider" },
		},
		{
			id = "3_Moonfang",
			displayName = "Moonfang",
			winsRequired = 100,
			kind = "Kart",
			imageAssetId = "rbxassetid://120790041354948",
			legacyIds = { "Moonfang" },
		},
	},
}

-- Get debug settings (for backward compatibility)
function CoreConfig.getDebugSettings()
	return CoreConfig.debugSystem
end

-- Check if debug is enabled
function CoreConfig.isDebugEnabled()
	return CoreConfig.debugSystem.enabled
end

-- Update debug settings at runtime
function CoreConfig.setDebugSettings(settings)
	for key, value in pairs(settings) do
		if CoreConfig.debugSystem[key] ~= nil then
			CoreConfig.debugSystem[key] = value
		end
	end
end

-- Get performance settings
function CoreConfig.getPerformanceSettings()
	return CoreConfig.performance
end

return CoreConfig
