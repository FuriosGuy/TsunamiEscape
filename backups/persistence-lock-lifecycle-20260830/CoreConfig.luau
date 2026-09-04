-- CoreConfig.luau

local CoreConfig = {}

-- Debug system configuration (universal across all modules)
CoreConfig.debugSystem = {
	enabled = true, -- Enable diagnostics for the current datastore investigation.
	showPrints = true, -- Show datastore and leaderboard diagnostics.
	showWarns = true, -- Show datastore and leaderboard warnings.
	showErrors = true, -- Show debug error messages
	timestamp = true, -- Include timestamps in debug messages
	studioOnly = false, -- Keep targeted persistence warnings available in published servers during this investigation.

	-- Temporary analysis scope: profile lifecycle and cross-server update diagnostics.
	enabledModules = {
		"ProductServerService",
		"PlayerAttributeManager",
		"ReferralService",
	},
	disabledModules = {}, -- Example: { "WorldManager" }
	moduleOverrides = { -- Highest-priority per-module override
		-- PlayerAttributeManager = true,
		-- WorldManager = false,
	},
}

-- Performance configuration (universal)
CoreConfig.performance = {
	maxFrameTime = 1 / 60, -- Target frame time (60 FPS)
}

-- Funnel analytics configuration (server-side Roblox AnalyticsService events)
CoreConfig.analytics = {
	enabled = true, -- Master toggle for funnel analytics helpers.
	economyEventsEnabled = true, -- Tracks authoritative currency sources/sinks in Roblox economy analytics.
	liveServerOnly = true, -- Funnel events only send from published live servers, never Studio/client.
	tutorialKartPrefix = "2_", -- Kart-name prefix used to detect the tutorial's second kart unlock.
	funnels = {
		verifyReward = "VerifyRewardClaim", -- Daily verify reward claim conversion funnel.
		rebirth = "RebirthFlow", -- Rebirth progression funnel across normal/purchased rebirths.
		playtimeReward = "PlaytimeRewardClaim", -- Playtime gift claim funnel.
		dailyReward = "DailyRewardClaim", -- Daily login reward claim funnel.
		dailyRewardClaimAll = "DailyRewardClaimAll", -- Claim-all daily reward purchase funnel.
		referral = "FriendInviteConversion", -- Invite/referral reward conversion funnel.
		friendInvitePrompt = "FriendInvitePrompt", -- Client invite-prompt engagement funnel.
		starterPack = "StarterPackFlow", -- Starter pack purchase/reward funnel.
		kartProgression = "KartProgressionFlow", -- Kart purchase/equip progression funnel.
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
}

-- One-time progression and race badges awarded by the server.
CoreConfig.badges = {
	experienceId = 9824719186, -- Main experience that owns and awards these badges.
	skipInStudio = true, -- Studio cannot persist real badge awards; test live in the published experience.
	successRefreshSeconds = 300, -- Avoid repeating ownership requests while nothing changed.
	initialRetrySeconds = 30, -- Retry transient Roblox badge-service failures after this delay.
	maxRetrySeconds = 600, -- Cap retries so service outages cannot spam requests.
	welcome = 3273304151493169,
	rebirthOnce = 1450520018893580,
	raceChampion = 3647670825159407,
	podiumFinish = 1168875109174939,
	racingLegend = 4258086265318362,
	playtime = {
		[5 * 60] = 60755709719278,
		[10 * 60] = 2819309255867369,
		[20 * 60] = 313561735586430,
		[30 * 60] = 750417595844198,
		[60 * 60] = 1667014806481744,
	},
	bloodmoon = {
		[5] = 891322904894608,
		[20] = 3951271662721938,
		[50] = 2305419625716178,
		[100] = 607482057912483,
	},
}

-- System chat promotional loop tuning/content
CoreConfig.systemChat = {
	promoMinDelay = 60, -- Minimum seconds between promo broadcasts.
	promoMaxDelay = 120, -- Maximum seconds between promo broadcasts.
	likeFavoriteEmojis = { -- Emoji pool for Like/Favorite promotional messages.
		"👍",
		"⭐",
		"🔥",
		"🎉",
		"💛",
		"💬",
		"📌",
		"🌟",
	},
	groupEmojis = { -- Emoji pool for group-join promotional messages.
		"👥",
		"🎁",
		"✨",
		"🚀",
		"🏆",
		"🤝",
		"📣",
		"🎊",
	},
	shopEmojis = { -- Emoji pool for dev product/gamepass promotional messages.
		"🛒",
		"💎",
		"⚡",
		"🚗",
		"🔥",
		"🧪",
		"💥",
		"🎯",
	},
	likeFavoritePromotionalMessages = { -- Rotating social prompts for like/favorite actions.
		"Favorite the game and leave a Like for more updates!",
		"Enjoying the game? Favorite it and drop a Like!",
		"Like + Favorite the game to support future content!",
		"Show some support by Liking and Favoriting the game!",
		"Like and Favorite the game if you want more awesome updates!",
	},
	groupPromotionalMessages = { -- Rotating social prompts for group joins.
		"Join our group for exclusive rewards!",
		"Join our group to claim exclusive rewards!",
		"Group members get exclusive rewards, join us now!",
		"Join our group and grab your exclusive rewards!",
		"Want exclusive rewards? Join our group today!",
	},
	shopPromotionalTemplates = { -- Use "{ITEM}" placeholder for random catalog picks.
		"Boost your run with {ITEM}!",
		"Try {ITEM} from the shop!",
		"Power up now with {ITEM}!",
		"Upgrade your progress using {ITEM}!",
		"Check out {ITEM} in the shop!",
	},
	shopPromotionOfferKeys = { -- Keys resolved from ProductService.Gamepasses/DevProducts.
		"VIP",
		"2xWins",
		"3xTreadmill",
		"15xTreadmill",
		"35xTreadmill",
		"100xTreadmill",
		"AdvancedTank",
		"ShoppingKart",
		"FormulaCar",
		"+1000",
		"+5000",
		"+10000",
		"+100K",
		"+1M",
		"+10M",
		"2x",
		"4x",
		"8x",
		"16x",
		"32x",
		"64x",
		"100x",
	},
}

-- Timed purchase prompt configuration. Product IDs remain in ProductService.
CoreConfig.promptBuy = {
	minDeaths = 3,
	maxDeaths = 5,
	minMinutes = 3,
	maxMinutes = 5,
	displayDurationSeconds = 15,
	temporaryBoostSelectionWeight = 4, -- Makes temporary boosts more likely in timed product prompts.
	bloodmoonKartSelectionWeight = 3, -- Blood Moon karts are strongly biased during the event.
	studioAlwaysShow = true, -- Studio-only prompt test; live servers still use death/time triggers.
	studioShowOwnedProducts = true, -- Studio-only preview: include already-owned permanent offers in the prompt.
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

-- Save system timing
CoreConfig.persistence = {
	saveDebounceSeconds = 10, -- Delay before regular save after recent write.
	finalSaveDebounceSeconds = 2, -- Minimum spacing for forced/final saves.
	finalSaveRetryAttempts = 3, -- Bounded retries for a forced leave/shutdown save.
	finalSaveRetryDelaySeconds = 1, -- Backoff base between forced save retries.
	loadRetryAttempts = 3, -- Maximum bounded retries for transient load failures.
	loadRetryDelaySeconds = 1, -- Backoff base between load attempts.
	grantedReceiptCacheLimit = 256, -- Maximum local receipt cache entries per server.
	durableReceiptHistoryLimit = 128, -- Receipt IDs retained in profile data to make reward retries idempotent.
	sessionLockLeaseSeconds = 180, -- A loaded profile lease refreshed by successful saves.
	sessionLockAcquireTimeoutSeconds = 20, -- Maximum wait for previous server to release a profile.
	sessionLockRetryDelaySeconds = 1, -- Delay between session-lock acquisition attempts.
	debugVerbose = false, -- Set true only when detailed load/save success logs are needed.
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

-- Return-to-stage offer settings
CoreConfig.returnToStage = {
	enabled = true, -- Master toggle for return-to-stage feature.
	duration = 10, -- Seconds the return-to-stage offer remains available.
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

-- Reusable live bonuses. Schedules use one global server time, never player locale.
CoreConfig.liveEvents = {
	refreshIntervalSeconds = 1, -- Keeps global schedule transitions live within one second in already-running servers.
	events = {
		{
			id = "Weekend2x",
			enabled = true,
			priority = 100,
			displayText = "2X WEEKEND!",
			displayColor = Color3.fromRGB(255, 199, 41),
			showCountdown = false, -- Keep the weekend card compact instead of showing a long multi-hour timer.
			preEventCountdownSeconds = 12 * 60 * 60, -- Show CountdownLabel1 during twelve hours before weekend starts.
			schedule = { kind = "WeekendTokyoToPacific" }, -- Saturday 00:00 JST through Sunday end in Pacific Time.
			effects = {
				xpMultiplier = 2, -- Applies only to normal treadmill/movement XP.
				winButtonMultiplier = 2, -- Applies only to normal WinButton rewards.
			},
		},
		{
			id = "Bloodmoon",
			enabled = true,
			priority = 200,
			displayText = "BLOOD MOON",
			displayColor = Color3.fromRGB(255, 0, 0),
			environmentName = "Bloodmoon",
			preEventCountdownSeconds = 24 * 60 * 60, -- Show CountdownLabel1 during twenty-four hours before the event starts.
			effects = {
				xpMultiplier = 1.5, -- Applies only to normal movement and treadmill XP.
				walkSpeedMultiplier = 0.75, -- Temporarily reduces effective player speed by 25% while live.
			},
			debugStudioEnabled = true, -- Studio-only test switch; production schedule remains authoritative when disabled.
			debugStudioStartAfterSeconds = 0, -- Studio test starts live immediately to verify instant JIP environment application.
			debugStudioDurationSeconds = 5 * 60, -- Studio test stays live for one hour so progression can be tested.
			debugStudioGraceDurationSeconds = 2 * 10, -- Studio test uses a twenty-second grace phase, representing two days.
			schedule = {
				kind = "RecurringWindow",
				cycleStartUnix = 0, -- First active Bloodmoon start in UTC Unix time; zero keeps production inactive.
				firstCycleStartsActive = true, -- First cycle starts live; later cycles automatically enter the grace period.
				activeDurationSeconds = 3 * 24 * 60 * 60,
				graceDurationSeconds = 3 * 24 * 60 * 60,
			},
		},
	},
}

-- Bloodmoon progression display. Unlock IDs match authored trail and kart assets.
CoreConfig.bloodmoonProgress = {
	enabled = true,
	maxWins = 100,
	debugStudioWinAmount = 10, -- Studio-only Bloodmoon win amount; published servers always use base amount 1.
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

-- Server gameplay/system tuning
CoreConfig.server = {
	playerAttributeManager = {
		autosaveInterval = 90, -- Refresh profile session locks and reduce crash-loss window.
		disableWavesDuration = 15, -- Seconds the Disable Waves product cooldown/effect lasts.
		playerCollisionGroup = "PlayersNoCollide", -- CollisionGroup assigned to player character parts.
	},
	tsunamiManager = {
		debugStudioDisableWaves = true, -- Temporarily suppresses all tsunami spawning in Studio; published servers are unchanged.
		startupSpawnCount = 25, -- Startup burst wave count before normal spawn loop.
		startupSpawnInterval = 0, -- Delay between startup burst spawns (seconds).
		minSpawnDelay = 8, -- Minimum random delay for normal spawn loop (seconds).
		maxSpawnDelay = 15, -- Maximum random delay for normal spawn loop (seconds).
	},
	worldManager = {
		debounceTime = 1.0, -- Touch/button debounce window (seconds).
		gamepassKartShowcaseTiltDegrees = 25, -- Fixed upward showcase tilt for gamepass karts.
		activeTreadmillUpdateInterval = 0.1, -- Tick rate for active treadmill reward updates (seconds).
		treadmillScanInterval = 0.1, -- Tick rate for treadmill touch scanning (seconds).
		kartHolderName = "EquippedKarts", -- Workspace folder used to hold kart runtime models.
		debugDisableKartEquipping = false, -- Disable kart attach flow for debugging.
		debugDisableKartSounds = false, -- Disable kart engine sound setup for debugging.
		debugDisableKartMotors = false, -- Disable kart motor creation for debugging.
		debugDisableKartWelds = false, -- Disable kart weld creation for debugging.
		invisEndTeleportCooldown = 1, -- Per-player server touch cooldown for the end barriers.
	},
	trollService = {
		actionTimeout = 60, -- Seconds a troll action stays pending before expiring.
		slowDuration = 10, -- Seconds the Slow troll effect lasts.
		freezeDuration = 10, -- Seconds the Freeze troll effect lasts.
		defaultSlowSpeed = 16, -- WalkSpeed applied during Slow effect.
		notificationStyle = "Default", -- "Default" uses full notification; "QuickFade" uses fast fade variant.
		notificationTickInterval = 1, -- Seconds between timed troll countdown notification updates.
	},
	playtimeRewards = {
		debugSequentialClaimMode = true, -- Studio-only debug: Gift01 ignores timer; each claim unlocks the next gift immediately.
	},
	dailyRewards = {
		debugSequentialClaimMode = true, -- Studio-only debug: each daily claim unlocks the next day immediately with no cooldown wait.
	},
	tsunamiSystem = {
		minRandomPathDistance = 1000, -- Minimum path distance required before randomizing spawn offset.
		hitEvaluationInterval = 0.05, -- Server overlap check interval while at least one wave is active.
		hitPadding = 2, -- Small server hitbox margin matching the old Touched behavior.
		disableWavesRecoveryBatchCount = 20, -- Number of recovery batches after disable-waves expires.
		disableWavesRecoveryBatchInterval = 10, -- Seconds between recovery batches.
		disableWavesRecoveryTsunamis = { -- Tsunami sets re-enabled during recovery.
			"Medium",
			"Fast",
			"Very Fast",
			"Extremely Fast",
		},
	},
	minigame = {
		requiredPlayers = 5, -- Minimum players needed before a race can start.
		maxPlayers = 20, -- Maximum racers accepted for one race.
		gracePeriodSeconds = 30, -- Join window before the race validates its player count.
		preCountdownGraceSeconds = 3, -- Short transition before the audible race countdown.
		countdownFallbackSeconds = 4, -- Total countdown duration: 3, 2, 1, then START.
		raceTimeoutSeconds = 180, -- Maximum time allowed for racers to reach the finish line.
		cooldownSeconds = 5 * 60, -- Delay before another race can open.
		returnFreezeSeconds = 1, -- Freeze returned racers briefly at the World 1 spawn.
		countdownSoundId = 100324658979992, -- Countdown audio that releases both starting barriers.
		debugAllowSinglePlayerInStudio = true, -- Studio-only: allow one player to start a race.
		debugSkipCooldownInStudio = false, -- Studio-only: reopen race immediately after it ends or is cancelled.
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
