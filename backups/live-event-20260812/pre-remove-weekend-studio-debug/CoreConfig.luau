-- CoreConfig.luau

local CoreConfig = {}

-- Debug system configuration (universal across all modules)
CoreConfig.debugSystem = {
	enabled = true, -- Temporary debug toggle for targeted EventBoard diagnostics.
	showPrints = true, -- Temporary badge verification output.
	showWarns = true, -- Temporary badge verification warnings.
	showErrors = true, -- Show debug error messages
	timestamp = true, -- Include timestamps in debug messages

	-- Temporary analysis scope: only badge-related server modules are shown.
	enabledModules = { "EventBoard" },
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
}

-- Spin wheel timing and local testing switches.
CoreConfig.spinWheel = {
	freeSpinCooldownSeconds = 24 * 60 * 60, -- One free spin becomes available each day.
	debugFreeSpinReadyInStudio = true, -- Studio-only: make another free spin ready after testing a spin.
	idleRotationDegreesPerSecond = 8, -- Slow wheel rotation while the modal is idle.
	spinRotationDuration = 4, -- Seconds used for an active wheel spin.
	spinFullTurns = 6, -- Full rotations before the selected reward settles.
	wheelTickVolume = 0.25, -- Volume of each reward-segment tick during an active spin.
	wheelTickMinPlaybackSpeed = 1, -- Lowest tick pitch; keep the ending from sounding lowered.
	wheelTickMaxPlaybackSpeed = 1.6, -- Highest tick pitch while the wheel is moving quickly.
	wheelTickReferenceDegreesPerSecond = 720, -- Angular speed that maps to the maximum tick pitch.
}

-- Return-to-stage offer settings
CoreConfig.returnToStage = {
	enabled = true, -- Master toggle for return-to-stage feature.
	duration = 10, -- Seconds the return-to-stage offer remains available.
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
			debugStudioForceActiveAfterSeconds = 60, -- Studio-only: stay off for one minute, then activate live for testing.
			schedule = { kind = "WeekendTokyoToPacific" }, -- Saturday 00:00 JST through Sunday end in Pacific Time.
			effects = {
				xpMultiplier = 2, -- Applies only to normal treadmill/movement XP.
				winButtonMultiplier = 2, -- Applies only to normal WinButton rewards.
			},
		},
	},
}

-- Server gameplay/system tuning
CoreConfig.server = {
	playerAttributeManager = {
		autosaveInterval = 300, -- Seconds between autosave passes.
		disableWavesDuration = 30, -- Seconds the Disable Waves product cooldown/effect lasts.
		playerCollisionGroup = "PlayersNoCollide", -- CollisionGroup assigned to player character parts.
	},
	tsunamiManager = {
		startupSpawnCount = 25, -- Startup burst wave count before normal spawn loop.
		startupSpawnInterval = 0, -- Delay between startup burst spawns (seconds).
		minSpawnDelay = 10, -- Minimum random delay for normal spawn loop (seconds).
		maxSpawnDelay = 20, -- Maximum random delay for normal spawn loop (seconds).
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
		debugSkipCooldownInStudio = true, -- Studio-only: reopen race immediately after it ends or is cancelled.
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
