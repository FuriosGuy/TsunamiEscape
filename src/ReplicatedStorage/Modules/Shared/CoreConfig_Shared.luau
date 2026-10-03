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
	},
	disabledModules = {
		"EventBoard",
	},
	moduleOverrides = {},
}

CoreConfig.social = {
	verifyGroupId = 13706307,
	friendInviteMultiplierStep = 0.1,
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
	freeSpinPlaytimeSeconds = 15 * 60, -- Active in-game time between free spins.
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

CoreConfig.disableWaves = {
	durationSeconds = 15,
}

CoreConfig.premium = {
	debugPromptOwnedMembershipInStudio = true,
}

function CoreConfig.canShowPremiumPrompt(membershipType, isStudio: boolean): boolean
	if membershipType ~= Enum.MembershipType.Premium then
		return true
	end

	return isStudio and CoreConfig.premium.debugPromptOwnedMembershipInStudio == true
end

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
	winStageRewards = {
		{ minimumStage = 16, amount = 1 },
		{ minimumStage = 18, amount = 2 },
		{ minimumStage = 20, amount = 3 },
	},
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
