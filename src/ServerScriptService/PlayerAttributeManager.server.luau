local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TutorialProgress = Remotes:WaitForChild("TutorialProgress") :: RemoteEvent
local ShowNotification = Remotes:WaitForChild("ShowNotification") :: RemoteEvent
local SoundPreferenceChanged = Remotes:WaitForChild("SoundPreferenceChanged") :: RemoteEvent

local function getOrCreateRemoteEvent(name: string): RemoteEvent
	local existing = Remotes:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), name .. " must be a RemoteEvent")
		return existing
	end

	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = name
	remoteEvent.Parent = Remotes
	return remoteEvent
end

local HapticPreferenceChanged = getOrCreateRemoteEvent("HapticPreferenceChanged")

local ReplicatedModules = ReplicatedStorage:WaitForChild("Modules")
local ServerModules = game.ServerScriptService:WaitForChild("Modules")
local Maid = require(ReplicatedModules:WaitForChild("Maid"))
local NumberFormatting = require(ReplicatedModules.Shared:WaitForChild("NumberFormatting"))
local PlayerHandler = require(ServerModules.Shared:WaitForChild("PlayerHandler_Server"))
local DebugModule = require(game:GetService("ReplicatedStorage").Modules:WaitForChild("DebugModule"))
local FunnelAnalytics =
	require(game:GetService("ServerScriptService").Modules.Shared:WaitForChild("FunnelAnalytics_Server"))
local ProductService = require(ServerModules.Shared:WaitForChild("ProductService_Server"))
local SharedFolder = ServerModules:WaitForChild("Shared")
local CoreConfig = require(SharedFolder:WaitForChild("CoreConfig_Server"))

-- Services
local ServerModules = script.Parent.Modules
local ProductServerService = require(ServerModules.ProductServerService)
local DataRecoveryService = require(ServerModules.DataRecoveryService)
local CreatorPurchaseService = require(ServerModules.CreatorPurchaseService)
local TrollService = require(ServerModules.TrollService)
local ReturnToStageService = require(ServerModules.ReturnToStageService)
local LevelingService = require(ServerModules.LevelingService)
local EconomyService = require(ServerModules.EconomyService)
local TsunamiSystem = require(ServerModules.TsunamiSystem)
local PlaytimeRewardsService = require(ServerModules.PlaytimeRewardsService)
local DailyRewardsService = require(ServerModules.DailyRewardsService)
local ReferralService = require(ServerModules.ReferralService)
local EconomyAnalytics = require(ServerModules.EconomyAnalytics)
local SpinWheelService = require(ServerModules.SpinWheelService)
local TemporaryBoostService = require(ServerModules.TemporaryBoostService)
local CompensationService = require(ServerModules.CompensationService)
local RewardedVideoService = require(ServerModules.RewardedVideoService)
local BadgeAwardService = require(ServerModules.BadgeAwardService)
local WinStreakService = require(ServerModules:WaitForChild("WinStreakService"))
local PetUpgradeService = require(ServerModules:WaitForChild("PetUpgradeService"))
local PetInventoryService = require(ServerModules:WaitForChild("PetInventoryService"))
local PetLuckyBlockPurchaseService = require(ServerModules:WaitForChild("PetLuckyBlockPurchaseService"))
local PetPaidRandomItemPolicyService = require(ServerModules:WaitForChild("PetPaidRandomItemPolicyService"))

local MODULE_NAME = "PlayerAttributeManager"
local DEFAULT_PLAYER_SPEED = if typeof(PlayerHandler.DEFAULT_ATTRIBUTES.Player_Speed) == "number"
	then PlayerHandler.DEFAULT_ATTRIBUTES.Player_Speed
	else 16
local pamConfig = if CoreConfig.server and CoreConfig.server.playerAttributeManager
	then CoreConfig.server.playerAttributeManager
	else nil
local AUTOSAVE_INTERVAL = if pamConfig and typeof(pamConfig.autosaveInterval) == "number"
	then math.max(1, pamConfig.autosaveInterval)
	else 300
local SHUTDOWN_SAVE_TIMEOUT_SECONDS = if pamConfig and typeof(pamConfig.shutdownSaveTimeoutSeconds) == "number"
	then math.max(5, math.floor(pamConfig.shutdownSaveTimeoutSeconds))
	else 25
local DISABLE_WAVES_DURATION = if pamConfig and typeof(pamConfig.disableWavesDuration) == "number"
	then math.max(1, math.floor(pamConfig.disableWavesDuration))
	else 15
local badgeConfig = if typeof(CoreConfig.badges) == "table" then CoreConfig.badges :: { [any]: any } else {}

local function getBadgeId(name: string): number
	local badgeId = badgeConfig[name]
	if typeof(badgeId) == "number" and badgeId > 0 then
		return math.floor(badgeId)
	end
	return 0
end

local function getPlaytimeBadgeId(seconds: number): number
	local playtimeBadges = badgeConfig.playtime
	if typeof(playtimeBadges) ~= "table" then
		return 0
	end

	local badgeId = playtimeBadges[seconds]
	if typeof(badgeId) == "number" and badgeId > 0 then
		return math.floor(badgeId)
	end
	return 0
end

local function getEventBadgeId(eventKey: string, winsRequired: number): number
	local eventBadges = badgeConfig[eventKey]
	if typeof(eventBadges) ~= "table" then
		return 0
	end

	local badgeId = eventBadges[winsRequired]
	if typeof(badgeId) == "number" and badgeId > 0 then
		return math.floor(badgeId)
	end
	return 0
end

local WELCOME_BADGE_ID = getBadgeId("welcome")
local REBIRTH_ONCE_BADGE_ID = getBadgeId("rebirthOnce")
local RACE_CHAMPION_BADGE_ID = getBadgeId("raceChampion")
local PODIUM_FINISH_BADGE_ID = getBadgeId("podiumFinish")
local RACING_LEGEND_BADGE_ID = getBadgeId("racingLegend")

type ThresholdBadge = {
	seconds: number,
	badgeId: number,
	label: string,
}

local PLAYTIME_BADGES: { ThresholdBadge } = {
	{ seconds = 5 * 60, badgeId = getPlaytimeBadgeId(5 * 60), label = "Playtime5Minutes" },
	{ seconds = 10 * 60, badgeId = getPlaytimeBadgeId(10 * 60), label = "Playtime10Minutes" },
	{ seconds = 20 * 60, badgeId = getPlaytimeBadgeId(20 * 60), label = "Playtime20Minutes" },
	{ seconds = 30 * 60, badgeId = getPlaytimeBadgeId(30 * 60), label = "Playtime30Minutes" },
	{ seconds = 60 * 60, badgeId = getPlaytimeBadgeId(60 * 60), label = "Playtime60Minutes" },
}

local BLOODMOON_BADGES: { ThresholdBadge } = {
	{ seconds = 5, badgeId = getEventBadgeId("bloodmoon", 5), label = "Bloodmoon5Wins" },
	{ seconds = 20, badgeId = getEventBadgeId("bloodmoon", 20), label = "Bloodmoon20Wins" },
	{ seconds = 50, badgeId = getEventBadgeId("bloodmoon", 50), label = "Bloodmoon50Wins" },
	{ seconds = 100, badgeId = getEventBadgeId("bloodmoon", 100), label = "Bloodmoon100Wins" },
}

local NEON_RUSH_BADGES: { ThresholdBadge } = {
	{ seconds = 20, badgeId = getEventBadgeId("neonRush", 20), label = "NeonRush20Wins" },
	{ seconds = 50, badgeId = getEventBadgeId("neonRush", 50), label = "NeonRush50Wins" },
}

local FROSTBITE_RALLY_BADGES: { ThresholdBadge } = {
	{ seconds = 10, badgeId = getEventBadgeId("frostbiteRally", 10), label = "FrostbiteRally10Wins" },
	{ seconds = 40, badgeId = getEventBadgeId("frostbiteRally", 40), label = "FrostbiteRally40Wins" },
}

type EventBadgeSet = {
	attributeName: string,
	badges: { ThresholdBadge },
}

local EVENT_WIN_BADGE_SETS: { EventBadgeSet } = {
	{ attributeName = "BloodmoonWins", badges = BLOODMOON_BADGES },
	{ attributeName = "NeonRushWins", badges = NEON_RUSH_BADGES },
	{ attributeName = "FrostbiteRallyWins", badges = FROSTBITE_RALLY_BADGES },
}
local PLAYER_COLLISION_GROUP = if pamConfig and typeof(pamConfig.playerCollisionGroup) == "string"
	then pamConfig.playerCollisionGroup
	else "PlayersNoCollide"
local analyticsConfig = if CoreConfig.analytics then CoreConfig.analytics else nil
local TUTORIAL_KART_PREFIX = if analyticsConfig and typeof(analyticsConfig.tutorialKartPrefix) == "string"
	then analyticsConfig.tutorialKartPrefix
	else "2_"
local ONBOARDING_STEP_PLAYER_JOINED = 1
local ONBOARDING_STEP_TUTORIAL_SEEN = 2
local ONBOARDING_STEP_LEVEL_THREE = 3
local ONBOARDING_STEP_FIRST_WIN = 4
local ONBOARDING_STEP_TUTORIAL_KART_OWNED = 5
local ONBOARDING_STEP_TUTORIAL_COMPLETED = 6
local ONBOARDING_SESSION_FUNNEL_NAME = "OnboardingSession"
local ONBOARDING_SESSION_STEP_TUTORIAL_SEEN = 2
local ONBOARDING_SESSION_STEP_FIRST_MOVEMENT = 3
local ONBOARDING_SESSION_STEP_LEVEL_THREE = 4
local ONBOARDING_SESSION_STEP_FIRST_WIN = 5
local ONBOARDING_SESSION_STEP_FIRST_DEATH = 6
local ONBOARDING_SESSION_STEP_TUTORIAL_KART_OWNED = 7
local ONBOARDING_SESSION_STEP_TUTORIAL_COMPLETED = 8
local ONBOARDING_SESSION_STEP_SESSION_ENDED = 9

type AnalyticsScalarValue = string | number | boolean
type AnalyticsCustomFields = {
	customField01: AnalyticsScalarValue?,
	customField02: AnalyticsScalarValue?,
	customField03: AnalyticsScalarValue?,
}

local playerMaids: { [Player]: any } = {}
local preferenceRequestTimes: { [Player]: { [string]: number } } = {}
local onboardingSessionIds: { [Player]: string } = {}
local onboardingSessionStartedAt: { [Player]: number } = {}
local cleanupInFlightPlayers: { [Player]: boolean } = {}
local runtimeInitializationInFlight: { [Player]: boolean } = {}
local runtimeInitialized: { [Player]: boolean } = {}
local cleanupInFlightCount = 0
local activeMaid = Maid.new()
local scriptAlive = true
local cleanupStarted = false
local badgeAwardService = BadgeAwardService.new()
local unregisterWinStreakReturnListener: (() -> ())? = ReturnToStageService.RegisterSuccessfulReturn(function(
	player: Player
)
	WinStreakService.RestoreAfterReturn(player)
end)

type LeaderstatBinding = {
	leaderstatName: string,
	attributeName: string,
}

local LEADERSTAT_BINDINGS: { LeaderstatBinding } = {
	{
		leaderstatName = "Rebirths",
		attributeName = "Rebirths",
	},
	{
		leaderstatName = "Wins",
		attributeName = "WinCount",
	},
	{
		leaderstatName = "Speed",
		attributeName = "AllXPSpeed", -- Total XP Speed
	},
}

-- Initialize Collision Groups
pcall(function()
	PhysicsService:RegisterCollisionGroup(PLAYER_COLLISION_GROUP)
end)
PhysicsService:CollisionGroupSetCollidable(PLAYER_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)

local function getPlayerMaid(player: Player): any
	if playerMaids[player] then
		return playerMaids[player]
	end
	local maid = Maid.new()
	playerMaids[player] = maid
	return maid
end

local function getOrCreateLeaderstatsFolder(player: Player): Folder
	local existingFolder = player:FindFirstChild("leaderstats")
	if existingFolder and existingFolder:IsA("Folder") then
		return existingFolder
	end

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	return leaderstats
end

local function syncLeaderstatValue(player: Player, valueObject: StringValue, attributeName: string)
	local attributeValue = player:GetAttribute(attributeName)
	if typeof(attributeValue) ~= "number" then
		attributeValue = 0
	end
	valueObject.Value = NumberFormatting.FormatNumber(attributeValue)
end

local function playerOwnsTutorialKart(player: Player): boolean
	local ownedKarts = PlayerHandler.GetOwnedKarts(player)
	for kartName, isOwned in pairs(ownedKarts) do
		if isOwned and string.match(kartName, "^" .. TUTORIAL_KART_PREFIX) then
			return true
		end
	end

	return false
end

local function logOnboardingSessionStep(
	player: Player,
	step: number,
	stepName: string,
	customFields: AnalyticsCustomFields?
)
	local sessionId = onboardingSessionIds[player]
	if sessionId then
		FunnelAnalytics.LogRecurringStep(player, ONBOARDING_SESSION_FUNNEL_NAME, sessionId, step, stepName, customFields)
	end
end

local function logOnboardingProgress(player: Player)
	FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_PLAYER_JOINED, "Player Joined", {
		customField01 = tostring(player:GetAttribute("Current_World") or "World1"),
	})

	if player:GetAttribute("TutorialSeen") == true then
		FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_TUTORIAL_SEEN, "Tutorial Seen")
		logOnboardingSessionStep(player, ONBOARDING_SESSION_STEP_TUTORIAL_SEEN, "Tutorial Seen")
	end

	local currentLevel = player:GetAttribute("CurrentLevel")
	if typeof(currentLevel) == "number" and currentLevel >= 3 then
		FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_LEVEL_THREE, "Reached Level 3")
		logOnboardingSessionStep(player, ONBOARDING_SESSION_STEP_LEVEL_THREE, "Reached Level 3")
	end

	local currentWins = player:GetAttribute("WinCount")
	if typeof(currentWins) == "number" and currentWins >= 1 then
		FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_FIRST_WIN, "Earned First Win")
		logOnboardingSessionStep(player, ONBOARDING_SESSION_STEP_FIRST_WIN, "Earned First Win")
	end

	if playerOwnsTutorialKart(player) then
		FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_TUTORIAL_KART_OWNED, "Owned Tutorial Kart")
		logOnboardingSessionStep(player, ONBOARDING_SESSION_STEP_TUTORIAL_KART_OWNED, "Owned Tutorial Kart")
	end

	if player:GetAttribute("TutorialCompleted") == true then
		FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_TUTORIAL_COMPLETED, "Tutorial Completed")
		logOnboardingSessionStep(player, ONBOARDING_SESSION_STEP_TUTORIAL_COMPLETED, "Tutorial Completed")
	end
end

local function getSessionDurationBucket(durationSeconds: number): string
	if durationSeconds < 30 then
		return "Under30Seconds"
	elseif durationSeconds < 120 then
		return "30To119Seconds"
	elseif durationSeconds < 300 then
		return "2To4Minutes"
	elseif durationSeconds < 600 then
		return "5To9Minutes"
	end

	return "10PlusMinutes"
end

local function startOnboardingSession(player: Player)
	if onboardingSessionIds[player] then
		return
	end

	local sessionId = FunnelAnalytics.OpenRecurringFunnel(player, ONBOARDING_SESSION_FUNNEL_NAME, "Session Started")
	if sessionId then
		onboardingSessionIds[player] = sessionId
		onboardingSessionStartedAt[player] = os.clock()
	end
end

local function finishOnboardingSession(player: Player)
	local sessionId = onboardingSessionIds[player]
	if sessionId then
		local startedAt = onboardingSessionStartedAt[player] or os.clock()
		local durationSeconds = math.max(0, os.clock() - startedAt)
		logOnboardingSessionStep(player, ONBOARDING_SESSION_STEP_SESSION_ENDED, "Session Ended", {
			customField01 = getSessionDurationBucket(durationSeconds),
			customField02 = player:GetAttribute("WinCount") or 0,
			customField03 = player:GetAttribute("TutorialCompleted") == true,
		})
	end

	onboardingSessionIds[player] = nil
	onboardingSessionStartedAt[player] = nil
end

local function setupLeaderstatsSync(player: Player, playerMaid: any)
	local leaderstats = getOrCreateLeaderstatsFolder(player)

	for _, config in ipairs(LEADERSTAT_BINDINGS) do
		local leaderstatName = config.leaderstatName
		local existingValue = leaderstats:FindFirstChild(leaderstatName)
		local valueObject: StringValue

		if existingValue and existingValue:IsA("StringValue") then
			valueObject = existingValue
		else
			if existingValue then
				existingValue:Destroy()
			end

			valueObject = Instance.new("StringValue")
			valueObject.Name = leaderstatName
			valueObject.Parent = leaderstats
		end

		syncLeaderstatValue(player, valueObject, config.attributeName)
		playerMaid["LeaderstatSync_" .. leaderstatName] = player
			:GetAttributeChangedSignal(config.attributeName)
			:Connect(function()
				syncLeaderstatValue(player, valueObject, config.attributeName)
			end)
	end
end

local function applyCharacterNoCollision(character: Model, characterMaid: any)
	character.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = PLAYER_COLLISION_GROUP
		end
	end
	characterMaid:GiveTask(character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = PLAYER_COLLISION_GROUP
		end
	end))
end

local function updateWalkSpeed(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local trollSpeed = TrollService.GetEffectiveWalkSpeed(player)
	local speed = if typeof(trollSpeed) == "number" then trollSpeed else PlayerHandler.GetEffectiveWalkSpeed(player)
	humanoid.WalkSpeed = speed
end

local function setupCharacter(player: Player, character: Model)
	if character:GetAttribute("PAM_SetupComplete") == true then
		return
	end
	character:SetAttribute("PAM_SetupComplete", true)

	local playerMaid = getPlayerMaid(player)
	local charMaid = Maid.new()
	playerMaid.CharacterMaid = charMaid -- Rule #3.14: Proper cleanup bound to character lifecycle

	applyCharacterNoCollision(character, charMaid)
	updateWalkSpeed(player, character)

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	LevelingService.TrackHumanoid(player, humanoid)

	charMaid:GiveTask(humanoid.Running:Connect(function(speed: number)
		if speed > 0.5 then
			logOnboardingSessionStep(player, ONBOARDING_SESSION_STEP_FIRST_MOVEMENT, "First Movement")
		end
	end))

	charMaid:GiveTask(humanoid.Died:Connect(function()
		logOnboardingSessionStep(player, ONBOARDING_SESSION_STEP_FIRST_DEATH, "First Death")
		LevelingService.TrackHumanoid(player, nil)
		TrollService.CleanupPlayer(player)
		WinStreakService.ResetForDeath(player)

		local stage = player:GetAttribute("CurrentStage")
		local world = player:GetAttribute("Current_World")
		if typeof(stage) == "number" and stage > 0 and typeof(world) == "string" then
			ReturnToStageService.SetPendingState(player, stage, world)
		end
	end))

	-- Offer return to stage on spawn
	charMaid.ReturnOffer = task.defer(function()
		ReturnToStageService.OfferReturnToStage(player)
	end)
end

local function applyDisableWavesCooldown(player: Player, durationSeconds: number)
	local playerMaid = getPlayerMaid(player)
	local duration = math.max(0, math.floor(durationSeconds))
	if duration <= 0 then
		player:SetAttribute("DisableWavesOnCooldown", false)
		player:SetAttribute("DisableWavesCooldownEnd", 0)
		playerMaid.DisableWavesCooldownTask = nil
		return
	end

	local cooldownEnd = os.time() + duration
	player:SetAttribute("DisableWavesOnCooldown", true)
	player:SetAttribute("DisableWavesCooldownEnd", cooldownEnd)

	local cooldownThread = task.spawn(function()
		local remaining = cooldownEnd - os.time()
		if remaining > 0 then
			task.wait(remaining)
		end

		if not player.Parent then
			return
		end

		local currentCooldownEnd = player:GetAttribute("DisableWavesCooldownEnd")
		if typeof(currentCooldownEnd) == "number" and currentCooldownEnd == cooldownEnd then
			player:SetAttribute("DisableWavesOnCooldown", false)
			player:SetAttribute("DisableWavesCooldownEnd", 0)
		end
	end)
	playerMaid.DisableWavesCooldownTask = function()
		if coroutine.status(cooldownThread) ~= "dead" then
			pcall(task.cancel, cooldownThread)
		end
	end
end

type BadgeRequest = {
	badgeId: number,
	label: string,
}

local function getEligibleBadgeRequests(player: Player): { BadgeRequest }
	local requests: { BadgeRequest } = {}
	local added: { [number]: boolean } = {}

	local function addBadge(badgeId: number, label: string)
		if badgeId > 0 and not added[badgeId] then
			added[badgeId] = true
			table.insert(requests, { badgeId = badgeId, label = label })
		end
	end

	addBadge(WELCOME_BADGE_ID, "Welcome")

	local rebirths = player:GetAttribute("Rebirths")
	if typeof(rebirths) == "number" and rebirths >= 1 then
		addBadge(REBIRTH_ONCE_BADGE_ID, "RebirthOnce")
	end

	local placement = player:GetAttribute("MinigamePlacement")
	if typeof(placement) == "number" then
		if placement == 1 then
			addBadge(RACE_CHAMPION_BADGE_ID, "RaceChampion")
		end
		if placement >= 1 and placement <= 3 then
			addBadge(PODIUM_FINISH_BADGE_ID, "PodiumFinish")
		end
	end

	local raceWins = player:GetAttribute("MinigameRaceWins")
	if typeof(raceWins) == "number" and raceWins >= 10 then
		addBadge(RACING_LEGEND_BADGE_ID, "RacingLegend")
	end

	local totalPlaytimeSeconds = player:GetAttribute("TotalPlaytimeSeconds")
	if typeof(totalPlaytimeSeconds) == "number" then
		for _, badge in ipairs(PLAYTIME_BADGES) do
			if totalPlaytimeSeconds >= badge.seconds then
				addBadge(badge.badgeId, badge.label)
			end
		end
	end

	for _, eventBadgeSet in ipairs(EVENT_WIN_BADGE_SETS) do
		local eventWins = player:GetAttribute(eventBadgeSet.attributeName)
		if typeof(eventWins) == "number" then
			for _, badge in ipairs(eventBadgeSet.badges) do
				if eventWins >= badge.seconds then
					addBadge(badge.badgeId, badge.label)
				end
			end
		end
	end

	return requests
end

local function syncPlayerBadges(player: Player)
	badgeAwardService:SyncPlayer(player, getEligibleBadgeRequests(player))
end

local function completePlayerInitialization(player: Player, loadStatus: string): boolean
	if player.Parent == nil then
		return false
	end
	if runtimeInitialized[player] then
		return true
	end
	if runtimeInitializationInFlight[player] then
		return false
	end
	runtimeInitializationInFlight[player] = true

	local playerMaid = getPlayerMaid(player)
	setupLeaderstatsSync(player, playerMaid)

	playerMaid.CharacterAdded = player.CharacterAdded:Connect(function(char)
		setupCharacter(player, char)
	end)
	playerMaid.CharacterRemoving = player.CharacterRemoving:Connect(function()
		playerMaid.CharacterMaid = nil -- Rule #3.21: Explicit cleanup
	end)

	if player.Character then
		setupCharacter(player, player.Character)
	end

	SpinWheelService.OnPlayerAdded(player)
	LevelingService.OnPlayerAdded(player)

	-- Attributes Setup
	player:SetAttribute("Treadmill_Active", false)
	player:SetAttribute("Treadmill_XPMultiplier", 1)
	player:SetAttribute("Movement_XPGainInterval", PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_INTERVAL)

	EconomyService.SyncTrailState(player)
	PlayerHandler.ApplyFriendInviteMultiplier(player)
	logOnboardingProgress(player)

	PlaytimeRewardsService.OnPlayerAdded(player)
	DailyRewardsService.OnPlayerAdded(player)
	if loadStatus == "New" then
		player:SetAttribute("Data_LoadState", "Saving")
		-- A genuinely new profile has no durable source yet, so keep it
		-- unavailable until its first authoritative snapshot is written.
		if not ProductServerService.SavePlayerData(player, true) then
			player:SetAttribute("Data_Loaded", false)
			player:SetAttribute("Data_LoadState", "Unavailable")
			ProductServerService.ReleaseSessionLock(player, "InitialProfileSaveFailed")
			runtimeInitializationInFlight[player] = nil
			DebugModule.debugWarn(
				"Initial profile persistence failed; stopping initialization | player=" .. player.Name,
				MODULE_NAME
			)
			return false
		end
		DebugModule.debugInfo(
			"Initial profile persisted | player=" .. player.Name .. " | status=" .. loadStatus,
			MODULE_NAME
		)
	end
	player:SetAttribute("Data_Loaded", true)
	player:SetAttribute("Data_LoadState", "Loaded")
	WinStreakService.InitializePlayer(player)
	if loadStatus == "LegacyMigration" then
		-- Legacy data is already durable. Do not block join on the metadata
		-- upgrade; the normal save queue will migrate it in the background.
		if ProductServerService.SavePlayerData(player) then
			DebugModule.debugInfo("Legacy profile migration scheduled | player=" .. player.Name, MODULE_NAME)
		else
			DebugModule.debugWarn(
				"Legacy profile migration could not be scheduled; later saves will retry | player=" .. player.Name,
				MODULE_NAME
			)
		end
	end
	playerMaid.GamePassSyncTask = task.spawn(function()
		if player.Parent == nil or player:GetAttribute("Data_Loaded") ~= true then
			return
		end

		EconomyService.SyncGamePassAttributes(player)
		if player.Parent ~= nil and player:GetAttribute("Data_Loaded") == true then
			ProductServerService.SavePlayerData(player)
		end
	end)
	CompensationService.TryGrant(player)
	ReferralService.OnPlayerAdded(player)
	ReturnToStageService.CheckQueuedRequest(player)
	PlayerHandler.SyncConfiguredEventUnlocks(player)

	-- Dynamic Attribute Sync (Strictly Keyed to avoid Rule #3.10 duplication)
	playerMaid.SpeedSync = player:GetAttributeChangedSignal("Player_Speed"):Connect(function()
		if player.Character then
			updateWalkSpeed(player, player.Character)
		end
	end)
	playerMaid.LiveEventWalkSpeedSync = player
		:GetAttributeChangedSignal("LiveEvent_WalkSpeedMultiplier")
		:Connect(function()
			if player.Character then
				updateWalkSpeed(player, player.Character)
			end
		end)
	if player.Character then
		updateWalkSpeed(player, player.Character)
	end
	playerMaid.TrailSync = player:GetAttributeChangedSignal("Trail_Equipped"):Connect(function()
		EconomyService.SyncTrailState(player)
	end)
	playerMaid.TutorialSeenAnalytics = player:GetAttributeChangedSignal("TutorialSeen"):Connect(function()
		logOnboardingProgress(player)
	end)
	playerMaid.TutorialCompletedAnalytics = player:GetAttributeChangedSignal("TutorialCompleted"):Connect(function()
		logOnboardingProgress(player)
	end)
	playerMaid.LevelAnalytics = player:GetAttributeChangedSignal("CurrentLevel"):Connect(function()
		logOnboardingProgress(player)
	end)
	playerMaid.WinAnalytics = player:GetAttributeChangedSignal("WinCount"):Connect(function()
		logOnboardingProgress(player)
	end)
	playerMaid.OwnedKartsAnalytics = player:GetAttributeChangedSignal("OwnedKarts"):Connect(function()
		logOnboardingProgress(player)
	end)
	playerMaid.FriendInviteSync = player:GetAttributeChangedSignal("FriendInviteCount"):Connect(function()
		PlayerHandler.ApplyFriendInviteMultiplier(player)
	end)
	playerMaid.RebirthBadgeSync = player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		syncPlayerBadges(player)
	end)
	playerMaid.RacePlacementBadgeSync = player:GetAttributeChangedSignal("MinigamePlacement"):Connect(function()
		syncPlayerBadges(player)
	end)
	playerMaid.RaceWinsBadgeSync = player:GetAttributeChangedSignal("MinigameRaceWins"):Connect(function()
		syncPlayerBadges(player)
	end)
	playerMaid.PlaytimeBadgeSync = player:GetAttributeChangedSignal("TotalPlaytimeSeconds"):Connect(function()
		syncPlayerBadges(player)
	end)
	for _, eventBadgeSet in ipairs(EVENT_WIN_BADGE_SETS) do
		local attributeName = eventBadgeSet.attributeName
		playerMaid[attributeName .. "BadgeSync"] = player:GetAttributeChangedSignal(attributeName):Connect(function()
			syncPlayerBadges(player)
		end)
	end

	-- Rule #3.10: Bound GamePass periodic sync
	playerMaid.GPSyncThread = task.spawn(function()
		while player.Parent and player:GetAttribute("PAM_Initialized") == true do
			task.wait(60)
			EconomyService.SyncGamePassAttributes(player)
		end
	end)

	playerMaid.WelcomeBadgeTask = task.defer(function()
		syncPlayerBadges(player)
	end)
	runtimeInitializationInFlight[player] = nil
	runtimeInitialized[player] = true
	return true
end

local function retryPlayerDataLoad(player: Player): (boolean, string?)
	if player.Parent == nil then
		return false, "Player left before the retry could finish."
	end
	if runtimeInitialized[player] then
		return true, nil
	end
	if runtimeInitializationInFlight[player] then
		return false, "A data load is already in progress."
	end

	player:SetAttribute("Data_Loaded", false)
	player:SetAttribute("Data_LoadState", "Loading")
	local loadStatus = ProductServerService.LoadPlayerData(player)
	if loadStatus == "Failed" or loadStatus == "RecoveryRequired" then
		player:SetAttribute("Data_Loaded", false)
		player:SetAttribute("Data_LoadState", "RecoveryRequired")
		return false, "Retry failed safely. Your data was not changed."
	end

	if not completePlayerInitialization(player, loadStatus) then
		player:SetAttribute("Data_Loaded", false)
		player:SetAttribute("Data_LoadState", "RecoveryRequired")
		return false, "Data loaded, but startup could not finish safely."
	end
	return true, nil
end

local function onPlayerAdded(player: Player)
	startOnboardingSession(player)

	-- Initialization Guard (Rule #3.24)
	if player:GetAttribute("PAM_Initialized") == true then
		-- If already initialized and we're here, it's a script reload.
		-- Rebind runtime systems without resetting player state.
		if player.Character then
			setupCharacter(player, player.Character)
		end
		SpinWheelService.OnPlayerAdded(player)
		CompensationService.TryGrant(player)
		PlaytimeRewardsService.OnPlayerAdded(player)
		DailyRewardsService.OnPlayerAdded(player)
		syncPlayerBadges(player)
		return
	end
	player:SetAttribute("PAM_Initialized", true)

	PlayerHandler.InitializePlayer(player)
	player:SetAttribute("Data_Loaded", false)
	player:SetAttribute("Data_LoadState", "Loading")
	player:SetAttribute("GamePassOwnershipSyncComplete", false)
	player:SetAttribute("DisableWavesOnCooldown", false)
	player:SetAttribute("DisableWavesCooldownEnd", 0)

	-- Start the authoritative profile request before optional player setup work.
	-- This keeps leaderstats and character wiring from delaying the datastore.
	local loadStatus = ProductServerService.LoadPlayerData(player)
	if loadStatus == "Failed" or loadStatus == "RecoveryRequired" then
		player:SetAttribute(
			"Data_LoadState",
			if loadStatus == "RecoveryRequired" then "RecoveryRequired" else "Unavailable"
		)
		if loadStatus == "RecoveryRequired" then
			DataRecoveryService.RecordInitialRecoveryAttempt(player)
		end
		DebugModule.debugWarn(
			"Player initialization stopped because data load was not safe | player="
				.. player.Name
				.. " | status="
				.. tostring(loadStatus),
			MODULE_NAME
		)
		-- Keep empty or malformed profiles connected only so the recovery prompt can
		-- offer a server-validated retry or reset. Network/load failures remain rejoin-only.
		if loadStatus == "Failed" and player.Parent ~= nil then
			player:Kick("Your data could not be loaded safely. Please rejoin.")
		end
		return
	end

	completePlayerInitialization(player, loadStatus)
end

local function cleanupPlayerInternal(player: Player)
	finishOnboardingSession(player)
	preferenceRequestTimes[player] = nil
	local maid = playerMaids[player]
	playerMaids[player] = nil
	runtimeInitializationInFlight[player] = nil
	runtimeInitialized[player] = nil
	local runtimeCleanupOk, runtimeCleanupError = pcall(function()
		if maid then
			maid:DoCleaning()
		end
		badgeAwardService:CleanupPlayer(player)

		TrollService.CleanupPlayer(player)
		ReturnToStageService.CleanupPlayer(player)
		LevelingService.CleanupPlayer(player)
		PlaytimeRewardsService.CleanupPlayer(player)
		DailyRewardsService.CleanupPlayer(player)
		SpinWheelService.CleanupPlayer(player)
		CompensationService.CleanupPlayer(player)
		CreatorPurchaseService.CleanupPlayer(player)
		WinStreakService.CleanupPlayer(player)
	end)
	if not runtimeCleanupOk then
		DebugModule.debugWarn(
			"Runtime cleanup failed before final save | player="
				.. player.Name
				.. " | err="
				.. tostring(runtimeCleanupError),
			MODULE_NAME
		)
	end

	if player:GetAttribute("Data_Loaded") == true then
		DebugModule.debugInfo(
			"Final player save starting | player="
				.. player.Name
				.. " | level="
				.. tostring(player:GetAttribute("CurrentLevel")),
			MODULE_NAME
		)
		local saveCallOk, saved = pcall(ProductServerService.SavePlayerData, player, true, true)
		if not saveCallOk or not saved then
			DebugModule.debugWarn(
				"Final player save failed | player="
					.. player.Name
					.. " | err="
					.. tostring(if saveCallOk then "save returned false" else saved),
				MODULE_NAME
			)
			ProductServerService.ReleaseSessionLock(player, "FinalSaveFailed")
		else
			DebugModule.debugInfo(
				"Final player save completed | player="
					.. player.Name
					.. " | level="
					.. tostring(player:GetAttribute("CurrentLevel")),
				MODULE_NAME
			)
		end
	else
		DebugModule.debugWarn(
			"Final player save skipped because data never loaded | player=" .. player.Name,
			MODULE_NAME
		)
		-- A player that leaves during loading has no safe snapshot to save.
		-- Release only the lock acquired by this server; never write defaults.
		ProductServerService.ReleaseSessionLock(player, "CleanupBeforeDataLoad")
	end
	local stateCleanupOk, stateCleanupError = pcall(ProductServerService.CleanupPlayerState, player)
	if not stateCleanupOk then
		DebugModule.debugWarn(
			"Persistence state cleanup failed | player=" .. player.Name .. " | err=" .. tostring(stateCleanupError),
			MODULE_NAME
		)
	end
end

local function cleanupPlayer(player: Player)
	if cleanupInFlightPlayers[player] then
		DebugModule.debugInfo("Player cleanup already in flight | player=" .. player.Name, MODULE_NAME)
		return
	end

	cleanupInFlightPlayers[player] = true
	cleanupInFlightCount += 1
	DebugModule.debugInfo(
		"Player cleanup started | player=" .. player.Name .. " | inFlight=" .. tostring(cleanupInFlightCount),
		MODULE_NAME
	)
	local ok, err = pcall(cleanupPlayerInternal, player)
	cleanupInFlightPlayers[player] = nil
	cleanupInFlightCount = math.max(0, cleanupInFlightCount - 1)
	if not ok then
		DebugModule.debugWarn(
			"Player cleanup crashed | player=" .. player.Name .. " | err=" .. tostring(err),
			MODULE_NAME
		)
	end
	DebugModule.debugInfo(
		"Player cleanup finished | player="
			.. player.Name
			.. " | success="
			.. tostring(ok)
			.. " | inFlight="
			.. tostring(cleanupInFlightCount),
		MODULE_NAME
	)
end

-- PRODUCT CALLBACKS (Rule #3.20: Contracts)
local function registerCallbacks()
	PetUpgradeService.RegisterCallbacks()

	ProductServerService.SetProductCallback(ProductService.DevProducts.SkipRebirth, function(p, id, bought)
		LevelingService.PerformRebirth(p, true)
	end)

	ProductServerService.SetProductCallback(ProductService.DevProducts.DisableWaves, function(p, id, bought)
		local world = p:GetAttribute("Current_World")
		if typeof(world) == "string" then
			applyDisableWavesCooldown(p, DISABLE_WAVES_DURATION)
			TsunamiSystem.DisableWorldTsunamis(world, DISABLE_WAVES_DURATION)
			TsunamiSystem.ClearWorldTsunamis(world)
			ShowNotification:FireAllClients(
				"WAVES DISABLED!",
				"Red",
				"DisableWaves",
				os.time() + DISABLE_WAVES_DURATION
			)
		end
	end)

	ProductServerService.SetProductCallback(
		ProductService.DevProducts.ReturnToStage,
		ReturnToStageService.HandlePurchase
	)
	ProductServerService.SetProductCallback(ProductService.DevProducts.TrollPlayer, TrollService.HandleTrollPurchase)
	ProductServerService.SetProductCallback(ProductService.DevProducts.ClaimAllDaily, function(p)
		DailyRewardsService.ClaimAllRemaining(p)
	end)

	-- Multipliers and Trails
	for mult, productName in pairs(ProductService.MULTIPLIER_TO_PRODUCT) do
		local id = ProductService.DevProducts[productName]
		if id then
			ProductServerService.SetProductCallback(id, function(p)
				local target = tonumber(string.match(productName, "(%d+)x")) or 1
				p:SetAttribute("DevProduct_XPSpeedMultiplier", target)
			end)
		end
	end

	-- GamePasses
	ProductServerService.SetGamePassCallback(ProductService.Gamepasses["2xWins"], function(p)
		EconomyService.SyncGamePassAttributes(p)
	end)

	ProductServerService.SetGamePassCallback(ProductService.Gamepasses["VIP"], function(p)
		EconomyService.SyncGamePassAttributes(p)
	end)

	ProductServerService.SetGamePassCallback(ProductService.Gamepasses["StarterPack"], function(p)
		EconomyService.SyncGamePassAttributes(p)
	end)

	local kartPasses = { "AdvancedTank", "ShoppingKart", "FormulaCar" }
	for _, kartName in ipairs(kartPasses) do
		local id = ProductService.Gamepasses[kartName]
		if id then
			ProductServerService.SetGamePassCallback(id, function(p)
				EconomyService.SyncGamePassAttributes(p)
			end)
		end
	end

	local treadmillPasses = { "3xTreadmill", "15xTreadmill", "35xTreadmill", "100xTreadmill" }
	for _, passName in ipairs(treadmillPasses) do
		local id = ProductService.Gamepasses[passName]
		if id then
			ProductServerService.SetGamePassCallback(id, function(p)
				EconomyService.SyncGamePassAttributes(p)
			end)
		end
	end

	-- Wins DevProducts
	local winsProducts = {
		{ name = "+1000", amount = 1000 },
		{ name = "+5000", amount = 5000 },
		{ name = "+10000", amount = 10000 },
	}

	for _, data in ipairs(winsProducts) do
		local id = ProductService.DevProducts[data.name]
		if id then
			ProductServerService.SetProductCallback(id, function(p, _, _, _, _, grantSource)
				local awardedWins = PlayerHandler.AddWins(p, data.amount)
				if grantSource ~= "CreatorGrant" then
					EconomyAnalytics.LogSource(
						p,
						"Wins",
						awardedWins,
						Enum.AnalyticsEconomyTransactionType.IAP.Name,
						"DevProduct_" .. data.name,
						{ customField01 = data.name }
					)
				end
				local winRemote = ReplicatedStorage.Remotes:FindFirstChild("WinButtonPressed")
				if winRemote and winRemote:IsA("RemoteEvent") then
					winRemote:FireClient(p, awardedWins)
				end
			end)
		end
	end

	-- XP Speed Products
	local xpSpeedProducts = {
		{ name = "+100K", amount = 100000 },
		{ name = "+1M", amount = 1000000 },
		{ name = "+10M", amount = 10000000 },
	}
	for _, data in ipairs(xpSpeedProducts) do
		local id = ProductService.DevProducts[data.name]
		if id then
			ProductServerService.SetProductCallback(id, function(p, _, _, _, _, grantSource)
				local awardedAmount = PlayerHandler.AddXPSpeedProduct(p, data.amount)
				if grantSource ~= "CreatorGrant" then
					EconomyAnalytics.LogSource(
						p,
						"XPSpeed",
						awardedAmount,
						Enum.AnalyticsEconomyTransactionType.IAP.Name,
						"DevProduct_" .. data.name,
						{ customField01 = data.name }
					)
				end
				local xpRemote = ReplicatedStorage.Remotes:FindFirstChild("XPGainAwarded")
				if xpRemote and xpRemote:IsA("RemoteEvent") then
					xpRemote:FireClient(p, awardedAmount)
				end
			end)
		end
	end

	-- Trail DevProducts
	local trailProducts = { "GalaxyTrail", "DemonTrail", "GoldTrail", "PurpleTrail", "BlueTrail", "GreenTrail" }
	for _, trailName in ipairs(trailProducts) do
		local id = ProductService.DevProducts[trailName]
		if id then
			ProductServerService.SetProductCallback(id, function(p)
				PlayerHandler.AddOwnedTrail(p, trailName)
			end)
		end
	end

	-- Event kart Developer Products. ProductServerService owns receipt
	-- reservation and saves after this callback returns successfully.
	for eventName, eventProducts in pairs(ProductService.EventKartProducts) do
		if typeof(eventProducts) == "table" then
			for productKey, productConfig in pairs(eventProducts) do
				local productId = ProductService.DevProducts[productKey]
				if typeof(productId) == "number" and typeof(productConfig) == "table" then
					local kartName = productConfig.KartName
					if typeof(kartName) == "string" and kartName ~= "" then
						local registeredEventName = tostring(eventName)
						local registeredProductKey = productKey
						local registeredKartName = kartName
						ProductServerService.SetProductCallback(productId, function(p, _, _, _, _, grantSource)
							PlayerHandler.AddOwnedKart(p, registeredKartName)
							-- ProductServerService owns the receipt transaction and performs the
							-- durable save after this callback returns. Avoid a nested save here:
							-- it can race the receipt save and incorrectly fail the callback.
							DebugModule.debugInfo(
								string.format(
									"Granted permanent event kart product | player=%s | event=%s | product=%s | kart=%s",
									p.Name,
									registeredEventName,
									registeredProductKey,
									registeredKartName
								),
								MODULE_NAME
							)
						end)
					end
				else
					DebugModule.debugWarn(
						"Event kart product registration skipped | event="
							.. tostring(eventName)
							.. " | product="
							.. tostring(productKey),
						MODULE_NAME
					)
				end
			end
		end
	end
end

-- INITIALIZATION
ProductServerService.Init()
PetPaidRandomItemPolicyService.Init()
activeMaid.PetPaidRandomItemPolicyServiceCleanup = script.Destroying:Connect(function()
	PetPaidRandomItemPolicyService.Destroy()
end)
PetInventoryService.Init()
DataRecoveryService.SetRetryHandler(retryPlayerDataLoad)
DataRecoveryService.Init()
TemporaryBoostService.Init()
CompensationService.Init()
RewardedVideoService.Init()
SpinWheelService.Init()
ReturnToStageService.Init()
TrollService.Init()
LevelingService.Init()
EconomyService.Init()
PlaytimeRewardsService.Init()
DailyRewardsService.Init()
ReferralService.Init()
registerCallbacks()
CreatorPurchaseService.Init()
PetLuckyBlockPurchaseService.Init()
activeMaid.PetLuckyBlockPurchaseServiceCleanup = script.Destroying:Connect(function()
	PetLuckyBlockPurchaseService.Destroy()
end)

activeMaid.PlayerAdded = Players.PlayerAdded:Connect(onPlayerAdded)
activeMaid.PlayerRemoving = Players.PlayerRemoving:Connect(cleanupPlayer)
local function bindBooleanPreferenceRemote(remoteEvent: RemoteEvent, attributeName: string): RBXScriptConnection
	return remoteEvent.OnServerEvent:Connect(function(player: Player, enabled: any)
		if player.Parent ~= Players or typeof(enabled) ~= "boolean" then
			return
		end
		if player:GetAttribute("Data_Loaded") ~= true then
			return
		end

		local playerRequestTimes = preferenceRequestTimes[player]
		if not playerRequestTimes then
			playerRequestTimes = {}
			preferenceRequestTimes[player] = playerRequestTimes
		end
		local now = os.clock()
		if now - (playerRequestTimes[attributeName] or -math.huge) < 0.25 then
			return
		end
		playerRequestTimes[attributeName] = now
		PlayerHandler.SetAttribute(player, attributeName, enabled)
	end)
end

activeMaid.SoundPreferenceChanged = bindBooleanPreferenceRemote(SoundPreferenceChanged, "MusicEnabled")
activeMaid.HapticPreferenceChanged = bindBooleanPreferenceRemote(HapticPreferenceChanged, "HapticsEnabled")
activeMaid.TutorialProgress = TutorialProgress.OnServerEvent:Connect(function(player: Player, state: string)
	if player:GetAttribute("Data_Loaded") ~= true then
		return
	end
	if typeof(state) ~= "string" then
		return
	end

	local didChange = false
	if state == "Seen" then
		if player:GetAttribute("TutorialSeen") ~= true then
			player:SetAttribute("TutorialSeen", true)
			didChange = true
		end
	elseif state == "Completed" then
		if player:GetAttribute("TutorialSeen") ~= true then
			player:SetAttribute("TutorialSeen", true)
			didChange = true
		end
		if player:GetAttribute("TutorialCompleted") ~= true then
			player:SetAttribute("TutorialCompleted", true)
			didChange = true
		end
	end

	if didChange then
		ProductServerService.SavePlayerData(player)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Autosave Loop (Rule #3.10)
activeMaid.Autosave = task.spawn(function()
	while scriptAlive do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			ProductServerService.SavePlayerData(player)
		end
	end
end)

-- Cleanup on script removal (Rule #3.21). AncestryChanged covers reloads where
-- Destroying is not delivered reliably.
local function shutdownPlayerAttributeManager()
	if cleanupStarted then
		return
	end

	cleanupStarted = true
	scriptAlive = false
	DebugModule.debugInfo("PlayerAttributeManager shutdown started", MODULE_NAME)
	PetInventoryService.Shutdown()
	ProductServerService.PrepareForShutdown()
	activeMaid:DoCleaning()

	local cleanupSet: { [Player]: boolean } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		cleanupSet[player] = true
	end
	for player in pairs(playerMaids) do
		cleanupSet[player] = true
	end
	local playersToCleanup: { Player } = {}
	for player in pairs(cleanupSet) do
		table.insert(playersToCleanup, player)
	end
	DebugModule.debugInfo(
		"Shutdown cleanup snapshot | players="
			.. tostring(#playersToCleanup)
			.. " | alreadyInFlight="
			.. tostring(cleanupInFlightCount),
		MODULE_NAME
	)
	local completedCleanupCount = 0
	for _, player in ipairs(playersToCleanup) do
		task.spawn(function()
			local ok, err = pcall(cleanupPlayer, player)
			if not ok then
				DebugModule.debugError("Shutdown player cleanup failed | player=" .. player.Name, err, MODULE_NAME)
			end
			completedCleanupCount += 1
		end)
	end

	local shutdownDeadline = os.clock() + SHUTDOWN_SAVE_TIMEOUT_SECONDS
	while (completedCleanupCount < #playersToCleanup or cleanupInFlightCount > 0) and os.clock() < shutdownDeadline do
		task.wait(0.1)
	end
	if completedCleanupCount < #playersToCleanup or cleanupInFlightCount > 0 then
		DebugModule.debugWarn(
			"Shutdown save window expired | completed="
				.. tostring(completedCleanupCount)
				.. "/"
				.. tostring(#playersToCleanup)
				.. " | inFlight="
				.. tostring(cleanupInFlightCount)
				.. " | timeout="
				.. tostring(SHUTDOWN_SAVE_TIMEOUT_SECONDS),
			MODULE_NAME
		)
	else
		DebugModule.debugInfo(
			"Shutdown player saves completed | players=" .. tostring(completedCleanupCount),
			MODULE_NAME
		)
	end
	TrollService.Shutdown()
	ReturnToStageService.Shutdown()
	LevelingService.Shutdown()
	EconomyService.Shutdown()
	PlaytimeRewardsService.Shutdown()
	DailyRewardsService.Shutdown()
	SpinWheelService.Shutdown()
	RewardedVideoService.Shutdown()
	badgeAwardService:Shutdown()
	if unregisterWinStreakReturnListener then
		unregisterWinStreakReturnListener()
		unregisterWinStreakReturnListener = nil
	end
	CreatorPurchaseService.Shutdown()
	DataRecoveryService.Shutdown()
	ProductServerService.Shutdown()
	DebugModule.debugInfo("PlayerAttributeManager shutdown completed", MODULE_NAME)
end

script.Destroying:Connect(shutdownPlayerAttributeManager)
script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		shutdownPlayerAttributeManager()
	end
end)

game:BindToClose(function()
	shutdownPlayerAttributeManager()
	task.wait(1)
end)

DebugModule.debugInfo("LifecycleManager Initialized", MODULE_NAME)
