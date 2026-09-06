local CoreConfig = {}

CoreConfig.debugSystem = {
	enabled = true,
	showPrints = true,
	showWarns = true,
	validationWarns = false,
	showErrors = true,
	timestamp = true,
	studioOnly = true,
	enabledModules = {
		"ValidationService"
	},
	disabledModules = {
		"EventBoard"
	},
	moduleOverrides = {},
}

CoreConfig.experienceNotifications = {
	enabled = true,
	studioEnabled = false,
	allowedUniverseIds = {
		[9824719186] = true,
	},
	promptOnJoin = true,
	studioPromptEnabled = false,
	promptDelaySeconds = 5,
	-- 0 means there is no in-session budget; Roblox's per-user daily limit still applies.
	maxSendsPerPlayerSession = 0,
	-- Roblox limits delivery to one notification per user per experience per UTC day.
	maxNotificationsPerPlayerPerUtcDay = 1,
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

CoreConfig.social = {
	verifyGroupId = 13706307,
	friendInviteMultiplierStep = 0.1,
	friendInviteTopbarIconImage = "rbxassetid://112009101194397",
	friendInviteTopbarLabel = "Invite Friends!",
	friendInvitePromptMessage = "Invite friends to join and earn +0.10x multiplier per unique friend!",
}

CoreConfig.leveling = {
	verifyRewardXP = 5000,
	verifyRewardWins = 50,
	verifyRewardDailyGrowthMultiplier = 1.1,
	verifyRewardRoundStep = 5,
	verifyRewardClaimCountAttribute = "VerifyRewardClaimCount",
	verifyRewardCooldownSeconds = 4 * 60 * 60,
	debugVerifyIgnoreCooldownInStudio = true,
	rebirthConfettiColors = {
		Color3.fromRGB(255, 215, 0),
		Color3.fromRGB(255, 43, 43),
		Color3.fromRGB(0, 200, 255),
		Color3.fromRGB(57, 255, 20),
		Color3.fromRGB(170, 0, 255),
	},
	rebirthConfettiDuration = 1.5,
	rebirthConfettiCount = 70,
	rewardCelebrationConfettiCount = 45,
}

CoreConfig.spinWheel = {
	freeSpinCooldownSeconds = 24 * 60 * 60,
	debugFreeSpinReadyInStudio = true,
	rewardedAdMaxSpins = 5,
	rewardedAdResetSeconds = 24 * 60 * 60,
	rewardedAdCooldownSeconds = 5 * 60,
	idleRotationDegreesPerSecond = 8,
	spinRotationDuration = 4,
	spinFullTurns = 6,
	wheelTickVolume = 0.25,
	wheelTickMinPlaybackSpeed = 1,
	wheelTickMaxPlaybackSpeed = 1.6,
	wheelTickReferenceDegreesPerSecond = 720,
}

CoreConfig.temporaryBoosts = {
	purchaseDurationSeconds = 10 * 60,
	rewardedAdDurationSeconds = 5 * 60,
}

CoreConfig.rewardedVideo = {
	enabled = true,
	requestCooldownSeconds = 3,
	placements = {
		PromptTempSpeedBoost = 618250252180809,
		PromptTempWinBoost = 511368025590066,
		ReturnToStage = 854035274061902,
		SpinWheel = 798599652050120,
	},
}

CoreConfig.bloodmoonProgress = {
	enabled = true,
	maxWins = 100,
	debugStudioWinAmount = 1,
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

return CoreConfig
