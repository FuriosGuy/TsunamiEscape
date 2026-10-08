local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = table.clone(require(ReplicatedStorage.Modules.Shared:WaitForChild("CoreConfig_Shared")))

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
	bloodmoonSelectionWeight = 4, -- Blood Moon messages are four times as likely while the event is active.
	normalSelectionWeight = 1, -- Normal tips/promotions remain possible during Blood Moon at reduced weight.
	bloodmoonColor = Color3.fromRGB(255, 65, 65), -- Blood Moon system chat color.
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
	bloodmoonRewardTemplates = {
		"🌑 Earn {WINS} Blood Moon Wins to unlock {REWARD}!",
	},
	bloodmoonPromotionalTemplates = {
		"🌑 BLOOD MOON IS LIVE! Chase {REWARD} before the event ends!",
		"⚡ Want to earn Blood Moon Wins faster? Try {BOOST} or unlock 2X Wins!",
		"🚗 {KART} is permanent after purchase, but paid Blood Moon karts are only available while the event is live!",
		"🔥 Keep pushing toward {REWARD} and collect exclusive Blood Moon gear!",
		"🎯 Check out {KART} in the Blood Moon shop while the event is active!",
	},
	bloodmoonTipMessages = {
		"🌑 Reach the final stage and touch the Win button to earn a Blood Moon Win!",
		"🔴 The waves glow red while Blood Moon is active!",
		"🎯 Stay alert and time your movement carefully!",
		"🏁 Finish your run and touch the Win button before leaving the course!",
		"🏆 Blood Moon Wins reset when the next event begins, but unlocked rewards stay yours permanently!",
	},
}

-- Server leaderboard debug controls.
CoreConfig.leaderboard = {
	debugUseFakeData = false,
	debugAppendFakeData = false,
}

-- Save system timing
CoreConfig.persistence = {
	saveDebounceSeconds = 10, -- Delay before regular save after recent write.
	finalSaveDebounceSeconds = 2, -- Minimum spacing for forced/final saves.
	finalSaveRetryAttempts = 3, -- Bounded retries for a forced leave/shutdown save.
	finalSaveRetryDelaySeconds = 1, -- Backoff base between forced save retries.
	loadRetryAttempts = 3, -- Maximum bounded retries for transient load failures.
	loadRetryDelaySeconds = 1, -- Backoff base between load attempts.
	regularSaveRetryInitialSeconds = 2, -- Backoff base for transient regular-save failures.
	regularSaveRetryAttempts = 6, -- Bounded regular-save attempts before final-save protection takes over.
	regularSaveRetryMaxSeconds = 30, -- Cap for regular-save retry backoff.
	datastoreBudgetWaitSeconds = 5, -- Maximum time to wait for a shared request budget slot.
	grantedReceiptCacheLimit = 256, -- Maximum local receipt cache entries per server.
	durableReceiptHistoryLimit = 128, -- Receipt IDs retained in profile data to make reward retries idempotent.
	sessionLockRecoverySeconds = 60, -- Emergency recovery only when a server crashes without releasing its lock.
	sessionLockRetryDelaySeconds = 1, -- Initial exponential-backoff delay for a locked key.
	sessionLockRetryMaxDelaySeconds = 5, -- Caps locked-key retry backoff to avoid request spam.
	sessionLockWaitGraceSeconds = 10, -- Extra bounded time for the expiry-crossing UpdateAsync request.
	sessionLockHeartbeatSeconds = 15, -- Refresh active locks well before emergency recovery.
	debugVerbose = true, -- Temporary full persistence trace for load/save-loss investigation.
}

-- One-time global compensation campaign. Unix values use Asia/Manila (UTC+8).
CoreConfig.compensation = {
	enabled = true,
	campaignId = "DataRecoveryCompensation_20260830",
	startUnix = 1788019200, -- 2026-08-30 00:00 PHT.
	endUnix = 1788624000, -- 2026-09-06 00:00 PHT; seven-day claim window.
	speedBoostSeconds = 30 * 60,
	winBoostSeconds = 30 * 60,
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
			debugStudioEnabled = false, -- Use the real Unix schedule in Studio and published servers.
			debugStudioStartAfterSeconds = 0, -- Studio test starts live immediately to verify instant JIP environment application.
			debugStudioDurationSeconds = 5 * 60, -- Studio test stays live for one hour so progression can be tested.
			debugStudioGraceDurationSeconds = 2 * 10, -- Studio test uses a twenty-second grace phase, representing two days.
			schedule = {
				kind = "RecurringWindow",
				cycleStartUnix = 1788562800, -- 2026-09-04 23:00 UTC / 2026-09-05 07:00 PHT; first active Bloodmoon start.
				firstCyclePreEventCountdownStartUnix = 1788019200, -- 2026-08-30 00:00 PHT; only the first event countdown starts early.
				firstCycleStartsActive = true, -- First cycle starts live; later cycles automatically enter the grace period.
				activeDurationSeconds = 3 * 24 * 60 * 60,
				graceDurationSeconds = 3 * 24 * 60 * 60,
			},
		},
	},
}

-- Server gameplay/system tuning
CoreConfig.server = {
	playerAttributeManager = {
		autosaveInterval = 90, -- Refresh profile session locks and reduce crash-loss window.
		shutdownSaveTimeoutSeconds = 25, -- Keep final saves inside Roblox's BindToClose window.
		disableWavesDuration = 15, -- Seconds the Disable Waves product cooldown/effect lasts.
		playerCollisionGroup = "PlayersNoCollide", -- CollisionGroup assigned to player character parts.
	},
	tsunamiManager = {
		debugStudioDisableWaves = false, -- Temporarily suppresses all tsunami spawning in Studio; published servers are unchanged.
		startupSpawnCount = 25, -- Startup burst wave count before normal spawn loop.
		startupSpawnInterval = 0, -- Delay between startup burst spawns (seconds).
		minSpawnDelay = 10, -- Minimum random delay for normal spawn loop (seconds).
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

return CoreConfig
