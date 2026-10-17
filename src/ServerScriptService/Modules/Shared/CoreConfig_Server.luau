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
		referral = "FriendInviteConversion", -- Invite/referral reward conversion funnel.
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
	neonRush = {
		[20] = 1965611997651037,
		[50] = 356327208275738,
	},
	frostbiteRally = {
		[10] = 1950296135504240,
		[40] = 1966822009022446,
	},
	halloweenCandy = {
		[10] = 1352755888106575,
		[100] = 2095447770236893,
		[250] = 3590603505057797,
		[500] = 330910764884357,
		[1000] = 2110030669403670,
	},
}

-- System chat promotional loop tuning/content
CoreConfig.systemChat = {
	promoMinDelay = 60, -- Minimum seconds between promo broadcasts.
	promoMaxDelay = 120, -- Maximum seconds between promo broadcasts.
	bloodmoonSelectionWeight = 4, -- Blood Moon messages are four times as likely while the event is active.
	normalSelectionWeight = 1, -- Normal tips/promotions remain possible during Blood Moon at reduced weight.
	liveEventSelectionWeight = 4, -- Active event messages are favored over normal promotions.
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
		"🌑 Reach stage 16 for 1, stage 18 for 2, or stage 20 for 3 Blood Moon Wins!",
		"🔴 The waves glow red while Blood Moon is active!",
		"🎯 Stay alert and time your movement carefully!",
		"🏁 Finish your run and touch the Win button before leaving the course!",
		"🏆 Blood Moon Wins reset when the next event begins, but unlocked rewards stay yours permanently!",
	},
	weekend2xPromotionalTemplates = {
		"{EVENT} is live! Earn 2x XP Speed and 2x Wins!",
	},
	weekend2xTipMessages = {
		"Race through {EVENT} to level up and earn Wins twice as fast!",
	},
	weekendMultiplierPromotionalTemplates = {
		"{EVENT} is live! Earn boosted XP Speed, Wins, and Lucky Block luck!",
	},
	weekendMultiplierTipMessages = {
		"Use {EVENT} to earn more XP and Wins, and improve your Lucky Block pet odds!",
	},
	millionSpecialPromotionalTemplates = {
		"1 MILLION SPECIAL is live! Enjoy 2x XP Speed and 2x Wins while it lasts!",
	},
	millionSpecialTipMessages = {
		"Celebrate 1 MILLION SPECIAL with 2x XP Speed and 2x Wins!",
	},
	liveEventMessages = {
		"✨ {EVENT} is live! Check the event progress before it ends!",
		"🏆 {EVENT} is live! Earn event wins before it ends!",
	},
}

-- Server leaderboard debug controls.
CoreConfig.leaderboard = {
	debugUseFakeData = false,
	debugAppendFakeData = false,
}

-- Save system timing
CoreConfig.persistence = {
	debugAlwaysNewPlayerDataInStudio = true, -- Studio-only: use defaults in memory and never read or write player DataStores.
	debugDisableStarterPackRewardsInStudio = true, -- Studio-only: prevent Starter Pack rewards during tutorial tests.
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
	debugStudioEventId = nil, -- Disabled: Studio follows the normal event schedule.
	rotation = {
		enabled = true, -- Live servers use the deterministic Major/Minor event rotation.
		rotationStartUnix = 1790809200, -- 2026-09-30 23:00 UTC / 2026-10-01 07:00 PHT; preserve the current Blood Moon window.
		randomSeed = 9824719186, -- Same seed produces the same event sequence on every server.
		version = "3", -- Bump when the event pool or rotation rules intentionally change.
		firstEventTier = "Major",
		firstSequenceIndex = 4,
		firstEventActiveDurationSeconds = 3 * 24 * 60 * 60, -- Keep current Blood Moon's full three-day active window.
		firstEventGraceDurationSeconds = 2 * 24 * 60 * 60, -- Apply the new two-day grace after current event ends.
		firstEventUsesFullCountdown = false,
	},
	events = {
		{
			id = "Weekend2x",
			enabled = true,
			priority = 100,
			displayText = "2X WEEKEND!",
			displayColor = Color3.fromRGB(255, 199, 41),
			systemChat = {
				promotionalTemplates = CoreConfig.systemChat.weekend2xPromotionalTemplates,
				tipMessages = CoreConfig.systemChat.weekend2xTipMessages,
			},
			showCountdown = false, -- Keep the weekend card compact instead of showing a long multi-hour timer.
			preEventCountdownSeconds = 12 * 60 * 60, -- Show CountdownLabel1 during twelve hours before weekend starts.
			schedule = {
				kind = "AbsoluteWindow",
				startUnix = 1791558000, -- Preserve current 2X WEEKEND event through its Roblox event window.
				endUnix = 1791788400, -- 2026-10-12 07:00 UTC; do not alter current event before it ends.
			},
			effects = {
				xpMultiplier = 2, -- Applies only to normal treadmill/movement XP.
				winButtonMultiplier = 2, -- Applies only to normal WinButton rewards.
			},
		},
		{
			id = "WeekendMultiplier",
			enabled = true,
			priority = 110,
			displayText = "{MULTIPLIER}X WEEKEND!",
			displayColor = Color3.fromRGB(255, 199, 41),
			multiplierChoices = { 2, 3, 4 },
			multiplierRandomSeed = 749,
			systemChat = {
				promotionalTemplates = CoreConfig.systemChat.weekendMultiplierPromotionalTemplates,
				tipMessages = CoreConfig.systemChat.weekendMultiplierTipMessages,
			},
			showCountdown = false,
			preEventCountdownSeconds = 12 * 60 * 60,
			schedule = {
				kind = "WeekendTokyoToPacific",
				activationAfterUnix = 1791788400, -- Begin at first scheduled weekend after current Roblox event ends.
			},
			effects = {
				xpMultiplier = 1,
				winButtonMultiplier = 1,
				luckMultiplier = 1,
			},
		},
		{
			-- Temporary celebration: remove this entry after the seven-day window ends.
			id = "MillionSpecial",
			enabled = true,
			priority = 150,
			displayText = "1 MILLION SPECIAL",
			displayColor = Color3.fromRGB(255, 215, 0),
			systemChat = {
				promotionalTemplates = CoreConfig.systemChat.millionSpecialPromotionalTemplates,
				tipMessages = CoreConfig.systemChat.millionSpecialTipMessages,
			},
			showCountdown = true,
			schedule = {
				kind = "AbsoluteWindow",
				startUnix = 1789868717, -- 2026-09-20 01:45:17 UTC
				endUnix = 1790207940, -- 2026-09-23 23:59:00 UTC
			},
			effects = {
				xpMultiplier = 2,
				winButtonMultiplier = 2,
			},
		},
		{
			id = "Bloodmoon",
			eventTier = "Major",
			enabled = true,
			priority = 200,
			displayText = "BLOOD MOON",
			displayColor = Color3.fromRGB(255, 0, 0),
			winPopupImageAssetId = "rbxassetid://128959525567285",
			startText = "THE BLOOD MOON RISES...",
			startSound = "BloodmoonRise",
			environmentName = "Bloodmoon",
			progressUi = {
				backgroundColor = Color3.fromRGB(255, 78, 78),
				gradientColor = Color3.fromRGB(206, 0, 3),
				winsAttribute = "BloodmoonWins",
				maxWins = 100,
				showUnlocks = true,
				unlocks = CoreConfig.bloodmoonProgress.unlocks,
			},
			stageWinAwards = {
				{ minimumStage = 16, amount = 1 },
				{ minimumStage = 18, amount = 2 },
				{ minimumStage = 20, amount = 3 },
			},
			eventBlockUi = {
				billboardText = "BLOOD MOON KARTS",
				infoText = "BLOOD MOON WINS REQUIRED",
				textColor = Color3.fromRGB(255, 0, 0),
				gradientColor = Color3.fromRGB(206, 0, 3),
			},
			systemChat = {
				rewardTemplates = CoreConfig.systemChat.bloodmoonRewardTemplates,
				promotionalTemplates = CoreConfig.systemChat.bloodmoonPromotionalTemplates,
				tipMessages = CoreConfig.systemChat.bloodmoonTipMessages,
			},
			kartWinsAttribute = "BloodmoonWins",
			kartRequirementLabel = "BLOOD MOON WINS",
			preEventCountdownSeconds = 24 * 60 * 60, -- Show CountdownLabel1 during twenty-four hours before the event starts.
			eventBlockCountdownSeconds = 2 * 24 * 60 * 60, -- EventBlock shows its start countdown during the two-day grace period.
			effects = {
				xpMultiplier = 1.5, -- Applies only to normal movement and treadmill XP.
				walkSpeedMultiplier = 0.75, -- Temporarily reduces effective player speed by 25% while live.
			},
			debugStudioEnabled = false, -- Disabled: Studio follows the normal Blood Moon schedule.
			debugStudioStartAfterSeconds = 0, -- Studio test starts live immediately to verify instant JIP environment application.
			debugStudioDurationSeconds = 20, -- Studio active duration before the event grace phase.
			debugStudioGraceDurationSeconds = 5, -- Temporary Studio gap before the next event.
			schedule = {
				kind = "RecurringWindow",
				cycleStartUnix = 1790809200, -- 2026-09-30 23:00 UTC / 2026-10-01 07:00 PHT; preserved transition window start.
				firstCyclePreEventCountdownStartUnix = 1790722800, -- 24 hours before the preserved transition window.
				firstCycleStartsActive = true, -- First cycle starts live; later cycles automatically enter the grace period.
				activeDurationSeconds = 2 * 24 * 60 * 60,
				graceDurationSeconds = 2 * 24 * 60 * 60,
			},
		},
		{
			id = "NeonRush",
			eventTier = "Minor",
			enabled = true,
			priority = 80,
			displayText = "NEON RUSH",
			displayColor = Color3.fromRGB(0, 220, 255),
			winPopupImageAssetId = "rbxassetid://76077537030305",
			startText = "NEON RUSH STARTS...",
			startSound = "NeonRushRise",
			environmentName = "NeonRush",
			progressUi = {
				backgroundColor = Color3.fromRGB(88, 216, 255),
				gradientColor = Color3.fromRGB(0, 81, 255),
				winsAttribute = "NeonRushWins",
				maxWins = 50,
				showUnlocks = true,
				unlocks = {
					-- TEMPORARY: replace marker images when Neon Rush kart artwork is ready.
					{
						id = "1_SparkBuggy",
						displayName = "SPARK BUGGY",
						winsRequired = 20,
						kind = "Kart",
						imageAssetId = "rbxassetid://111899124648289",
					},
					{
						id = "2_TurboRunner",
						displayName = "TURBO RUNNER",
						winsRequired = 50,
						kind = "Kart",
						imageAssetId = "rbxassetid://119199314964183",
					},
				},
			},
			stageWinAwards = {
				{ minimumStage = 16, amount = 1 },
				{ minimumStage = 18, amount = 2 },
				{ minimumStage = 20, amount = 3 },
			},
			eventBlockUi = {
				billboardText = "NEON RUSH KARTS",
				infoText = "NEON RUSH WINS REQUIRED",
				textColor = Color3.fromRGB(88, 216, 255),
				gradientColor = Color3.fromRGB(0, 81, 255),
			},
			systemChat = {
				rewardTemplates = {
					"⚡ Earn {WINS} {EVENT} Wins to unlock {REWARD}!",
				},
				promotionalTemplates = {
					"⚡ {EVENT} is live! Chase {REWARD} before the event ends!",
					"🏎️ Keep racing to earn {EVENT} Wins and unlock {REWARD}!",
					"🚗 {KART} is available while {EVENT} is live!",
					"🏆 Reach {WINS} {EVENT} Wins to unlock {REWARD}!",
				},
				tipMessages = {
					"✨ {EVENT} is live! Check the event progress before it ends!",
					"🏁 Reach stage 16 for 1, stage 18 for 2, or stage 20 for 3 {EVENT} Wins!",
					"🎯 Complete your run and touch the Win button to earn {EVENT} Wins!",
					"🏆 {EVENT} Wins reset when the next event begins, but unlocked rewards stay yours permanently!",
				},
			},
			showCountdown = true,
			kartWinsAttribute = "NeonRushWins",
			kartRequirementLabel = "WINS",
			preEventCountdownSeconds = 24 * 60 * 60, -- Show the upcoming rotation card only during the final 24 hours.
			eventBlockCountdownSeconds = 2 * 24 * 60 * 60,
			debugStudioEnabled = false,
			debugStudioStartAfterSeconds = 5,
			debugStudioDurationSeconds = 20,
			debugStudioGraceDurationSeconds = 5,
			schedule = {
				kind = "RecurringWindow",
				firstCycleStartsActive = true,
				activeDurationSeconds = 1 * 24 * 60 * 60,
				graceDurationSeconds = 2 * 24 * 60 * 60,
			},
		},
		{
			id = "FrostbiteRally",
			eventTier = "Minor",
			enabled = true,
			priority = 70,
			displayText = "FROSTBITE RALLY",
			displayColor = Color3.fromRGB(204, 238, 255),
			winPopupImageAssetId = "rbxassetid://91747846214512",
			startText = "FROSTBITE RALLY STARTS...",
			showCountdown = true,
			preEventCountdownSeconds = 24 * 60 * 60, -- Show the upcoming rotation card only during the final 24 hours.
			eventBlockCountdownSeconds = 2 * 24 * 60 * 60,
			environmentName = "FrostbiteRally",
			progressUi = {
				backgroundColor = Color3.fromRGB(204, 238, 255),
				gradientColor = Color3.fromRGB(115, 173, 255),
				winsAttribute = "FrostbiteRallyWins",
				maxWins = 50,
				showUnlocks = true,
				unlocks = {
					{
						id = "1_Sled",
						displayName = "Ice Sled",
						winsRequired = 10,
						kind = "Kart",
						imageAssetId = "rbxassetid://118255357334971",
					},
					{
						id = "2_Snowmobile",
						displayName = "Snowmobile",
						winsRequired = 40,
						kind = "Kart",
						imageAssetId = "rbxassetid://86298743744530",
					},
				},
			},
			eventBlockUi = {
				billboardText = "FROSTBITE RALLY KARTS",
				infoText = "FROSTBITE RALLY WINS REQUIRED",
				textColor = Color3.fromRGB(204, 238, 255),
				gradientColor = Color3.fromRGB(115, 173, 255),
			},
			systemChat = {
				rewardTemplates = {
					"❄️ Earn {WINS} {EVENT} Wins to unlock {REWARD}!",
				},
				promotionalTemplates = {
					"❄️ {EVENT} is live! Chase {REWARD} before the event ends!",
					"🏎️ Brave the frozen course to earn {EVENT} Wins and unlock {REWARD}!",
					"🚗 {KART} is available while {EVENT} is live!",
					"🏆 Reach {WINS} {EVENT} Wins to unlock {REWARD}!",
				},
				tipMessages = {
					"✨ {EVENT} is live! Check the event progress before it ends!",
					"❄️ Earn 10 {EVENT} Wins to unlock the Ice Sled!",
					"🎯 Earn 40 {EVENT} Wins to unlock the Snowmobile!",
					"🏁 Complete your run and touch the Win button to earn {EVENT} Wins!",
					"🏆 {EVENT} Wins reset when the next event begins, but unlocked rewards stay yours permanently!",
				},
			},
			kartWinsAttribute = "FrostbiteRallyWins",
			kartRequirementLabel = "FROSTBITE RALLY WINS",
			stageWinAwards = {
				{ minimumStage = 16, amount = 1 },
				{ minimumStage = 18, amount = 2 },
				{ minimumStage = 20, amount = 3 },
			},
			debugStudioEnabled = false,
			debugStudioStartAfterSeconds = 5,
			debugStudioDurationSeconds = 5 * 60,
			debugStudioGraceDurationSeconds = 5,
			schedule = {
				kind = "RecurringWindow",
				firstCycleStartsActive = true,
				activeDurationSeconds = 1 * 24 * 60 * 60,
				graceDurationSeconds = 2 * 24 * 60 * 60,
			},
		},
	},
}

-- Server gameplay/system tuning
CoreConfig.server = {
	playerAttributeManager = {
		autosaveInterval = 90, -- Refresh profile session locks and reduce crash-loss window.
		shutdownSaveTimeoutSeconds = 25, -- Keep final saves inside Roblox's BindToClose window.
		disableWavesDuration = CoreConfig.disableWaves.durationSeconds, -- Derived from shared config so server effect and client tooltip stay synchronized.
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
		gamepassKartShowcaseRotationDuration = 15, -- Full showcase rotation duration (seconds).
		activeTreadmillUpdateInterval = 0.1, -- Tick rate for active treadmill reward updates (seconds).
		treadmillScanInterval = 0.1, -- Tick rate for treadmill touch scanning (seconds).
		kartHolderName = "EquippedKarts", -- Workspace folder used to hold kart runtime models.
		kartSeatOffsetAdjustments = {
			["2_CoffinKart"] = 0.3, -- Lower kart seat anchor slightly so rider sits higher relative to coffin.
		},
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
	},
	minigame = {
		requiredPlayers = 3, -- Minimum players needed before a race can start.
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
