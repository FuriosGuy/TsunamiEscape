--!strict

local CoreConfig = require(script.Parent:WaitForChild("CoreConfig_Shared"))
local PetConfig = require(game:GetService("ReplicatedStorage").Modules.Config.PetConfig)
local spinWheelConfig = CoreConfig.spinWheel or {}
local rewardedAdMaxSpins = if typeof(spinWheelConfig.rewardedAdMaxSpins) == "number"
	then math.max(1, math.floor(spinWheelConfig.rewardedAdMaxSpins))
	else 5

local PlayerDataConfig: { [string]: any } = {}

PlayerDataConfig.DEFAULT_ATTRIBUTES = {
	Rebirths = 0,
	Rebirth_XPMultiplier = 1,
	DevProduct_XPSpeedMultiplier = 1,
	Misc_XPSpeedMultiplier = 1,
	Friend_XPMultiplier = 1,
	FriendInviteCount = 0,

	Player_Speed = 16,
	Max_Player_Speed = 16,
	Trail_Equipped = "None",
	OwnedTrails = "",
	OwnedKarts = "1_Default",
	Kart_Equipped = "1_Default",
	Current_World = "World1",
	MusicEnabled = true,
	HapticsEnabled = true,
	CurrentStage = 0,
	MinigameRaceWins = 0,
	BloodmoonWins = 0,
	BloodmoonWinsCycleUnix = 0,
	NeonRushWins = 0,
	NeonRushWinsCycleUnix = 0,
	FrostbiteRallyWins = 0,
	FrostbiteRallyWinsCycleUnix = 0,
	Pet_EquipSlotCapacity = PetConfig.Equip.startingSlots,
	Pet_BackpackCapacity = PetConfig.Storage.startingCapacity,
	Pet_LuckMultiplier = PetConfig.Upgrades.luckMultiplier.startingMultiplier,
	Pet_LuckyBlockFastOpenEnabled = true,
	Pet_Inventory = "[]",
	Pet_OverflowClaims = "[]",
	Pet_PaidRandomItemsRestricted = true,
	Pet_RandomItemPolicyLoaded = false,

	WinCount = 0,
	WinMultiplier = 1,
	WinStreakCount = 0,
	HasVIPPass = false,
	VerifyRewardClaimed = false,
	VerifyRewardNextClaimUnix = 0,
	VerifyRewardClaimCount = 0,
	StarterPackRewardClaimed = false,
	FreeTreadmillClaimed = false,
	TutorialSeen = false,
	TutorialCompleted = false,
	FavoriteGamePromptAttempted = false,
	Data_Loaded = false,
	PlaytimeRewardElapsed = 0,
	TotalPlaytimeSeconds = 0,
	PlaytimeRewardsClaimed = "",
	DailyRewardCurrentDay = 1,
	DailyRewardNextClaimUnix = 0,
	DailyRewardCycleCount = 0,
	DailyRewardLastClaimDayKey = 0,
	DailyRewardTimezoneOffsetMinutes = 0,
	DailyRewardTimezoneInitialized = false,
	SpinWheelSpins = 0,
	SpinWheelNextFreeSpinUnix = 0, -- Legacy cooldown field; migrated and cleared on join.
	SpinWheelNextFreeSpinPlaytimeSeconds = 0,
	SpinWheelFreeSpinInitialized = false,
	SpinWheelProcessedReceiptIds = "",
	SpinWheelRewardedAdSpinsRemaining = rewardedAdMaxSpins,
	SpinWheelRewardedAdNextAvailableUnix = 0,
	SpinWheelRewardedAdResetUnix = 0,
	TemporarySpeedBoostEndUnix = 0,
	TemporaryWinBoostEndUnix = 0,
	CompensationClaimedCampaigns = "",

	CurrentLevel = 1,
	MaxLevel = 25,
	AllXPSpeed = 0,
	CurrentXPSpeed = 0,
	MaxXPSpeed = 25,

	Treadmill_XPMultiplier = 1,
	Treadmill_Active = false,
	Movement_XPGainRate = 10,
	Movement_XPGainInterval = 0.25,
}

PlayerDataConfig.PREMIUM_MULTIPLIER = 1.25

local socialConfig = CoreConfig.social
PlayerDataConfig.FRIEND_INVITE_MULTIPLIER_STEP = if socialConfig
		and typeof(socialConfig.friendInviteMultiplierStep) == "number"
	then math.max(0, socialConfig.friendInviteMultiplierStep)
	else 0.1

PlayerDataConfig.DEFAULT_PLAYER_SPEED = if typeof(PlayerDataConfig.DEFAULT_ATTRIBUTES.Player_Speed) == "number"
	then PlayerDataConfig.DEFAULT_ATTRIBUTES.Player_Speed
	else 16
PlayerDataConfig.DEFAULT_MAX_PLAYER_SPEED = if typeof(PlayerDataConfig.DEFAULT_ATTRIBUTES.Max_Player_Speed)
		== "number"
	then PlayerDataConfig.DEFAULT_ATTRIBUTES.Max_Player_Speed
	else 16

PlayerDataConfig.TRAIL_ORDER = {
	"GalaxyTrail",
	"DemonTrail",
	"EclipseTrail",
	"FlameTrail",
	"GreenTrail",
	"BlueTrail",
	"PurpleTrail",
	"GoldTrail",
}

PlayerDataConfig.TRAIL_CONFIGS = {
	GalaxyTrail = {
		DisplayName = "Galaxy Trail",
		XPMultiplier = 15,
		CanBuyWithWins = false,
		WinsRequired = 0,
		BackgroundColor = Color3.fromRGB(84, 0, 255),
		GradientBottomColor = Color3.fromRGB(100, 100, 100),
		ProductKey = "GalaxyTrail",
	},
	DemonTrail = {
		DisplayName = "Demon Trail",
		XPMultiplier = 7.5,
		CanBuyWithWins = false,
		WinsRequired = 0,
		BackgroundColor = Color3.fromRGB(255, 0, 0),
		GradientBottomColor = Color3.fromRGB(0, 0, 0),
		ProductKey = "DemonTrail",
	},
	EclipseTrail = {
		DisplayName = "Eclipse Trail",
		XPMultiplier = 7,
		CanBuyWithWins = false,
		WinsRequired = 5,
		BackgroundColor = Color3.fromRGB(255, 79, 79),
		GradientBottomColor = Color3.fromRGB(206, 0, 3),
		ImageAssetId = "rbxassetid://107479098911247",
		EventOnly = true,
		EventName = "Bloodmoon",
	},
	GreenTrail = {
		DisplayName = "Green Trail",
		XPMultiplier = 1.5,
		CanBuyWithWins = true,
		WinsRequired = 250,
		BackgroundColor = Color3.fromRGB(0, 255, 0),
		GradientBottomColor = Color3.fromRGB(0, 130, 15),
		ProductKey = "GreenTrail",
	},
	BlueTrail = {
		DisplayName = "Blue Trail",
		XPMultiplier = 2,
		CanBuyWithWins = true,
		WinsRequired = 750,
		BackgroundColor = Color3.fromRGB(88, 216, 255),
		GradientBottomColor = Color3.fromRGB(0, 81, 255),
		ProductKey = "BlueTrail",
	},
	PurpleTrail = {
		DisplayName = "Purple Trail",
		XPMultiplier = 3,
		CanBuyWithWins = true,
		WinsRequired = 2500,
		BackgroundColor = Color3.fromRGB(228, 75, 255),
		GradientBottomColor = Color3.fromRGB(74, 3, 255),
		ProductKey = "PurpleTrail",
	},
	GoldTrail = {
		DisplayName = "Gold Trail",
		XPMultiplier = 4.5,
		CanBuyWithWins = true,
		WinsRequired = 7500,
		BackgroundColor = Color3.fromRGB(255, 255, 0),
		GradientBottomColor = Color3.fromRGB(255, 183, 0),
		ProductKey = "GoldTrail",
	},
	FlameTrail = {
		DisplayName = "Flame Trail",
		XPMultiplier = 6,
		CanBuyWithWins = false,
		WinsRequired = 0,
		BackgroundColor = Color3.fromRGB(254, 199, 41),
		GradientBottomColor = Color3.fromRGB(255, 85, 0),
		RewardSource = "SpinWheel",
	},
}

PlayerDataConfig.MOVEMENT_CONFIG = {
	XP_GAIN_RATE = 100,
	XP_GAIN_INTERVAL = 0.5,
	XP_GAIN_TOLERANCE = 0.05,
	PLAYER_SPEED_PER_LEVEL = 4,
	LEVEL_MULTIPLIERS = {
		{ MaxLevel = 200, Multiplier = 1.125 },
		{ MaxLevel = 400, Multiplier = 1.15 },
	},
	REBIRTH_CONFIG = {
		MAX_LEVEL_INCREMENT = 25,
		MULTIPLIER_INCREMENT = 0.5,
	},
}

return PlayerDataConfig
