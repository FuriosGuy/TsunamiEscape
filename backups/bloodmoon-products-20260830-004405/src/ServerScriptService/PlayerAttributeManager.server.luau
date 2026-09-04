--!strict
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TutorialProgress = Remotes:WaitForChild("TutorialProgress") :: RemoteEvent

local ReplicatedModules = ReplicatedStorage:WaitForChild("Modules")
local Maid = require(ReplicatedModules:WaitForChild("Maid"))
local PlayerHandler = require(ReplicatedModules:WaitForChild("PlayerHandler"))
local DebugModule = require(ReplicatedModules:WaitForChild("DebugModule"))
local FunnelAnalytics = require(ReplicatedModules:WaitForChild("FunnelAnalytics"))
local ProductService = require(ReplicatedModules:WaitForChild("ProductService"))
local ConfigFolder = ReplicatedModules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

-- Services
local ServerModules = script.Parent.Modules
local ProductServerService = require(ServerModules.ProductServerService)
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
local RewardedVideoService = require(ServerModules.RewardedVideoService)
local BadgeAwardService = require(ServerModules.BadgeAwardService)

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

local WELCOME_BADGE_ID = getBadgeId("welcome")
local REBIRTH_ONCE_BADGE_ID = getBadgeId("rebirthOnce")
local RACE_CHAMPION_BADGE_ID = getBadgeId("raceChampion")
local PODIUM_FINISH_BADGE_ID = getBadgeId("podiumFinish")
local RACING_LEGEND_BADGE_ID = getBadgeId("racingLegend")

type PlaytimeBadge = {
	seconds: number,
	badgeId: number,
	label: string,
}

local PLAYTIME_BADGES: { PlaytimeBadge } = {
	{ seconds = 5 * 60, badgeId = getPlaytimeBadgeId(5 * 60), label = "Playtime5Minutes" },
	{ seconds = 10 * 60, badgeId = getPlaytimeBadgeId(10 * 60), label = "Playtime10Minutes" },
	{ seconds = 20 * 60, badgeId = getPlaytimeBadgeId(20 * 60), label = "Playtime20Minutes" },
	{ seconds = 30 * 60, badgeId = getPlaytimeBadgeId(30 * 60), label = "Playtime30Minutes" },
	{ seconds = 60 * 60, badgeId = getPlaytimeBadgeId(60 * 60), label = "Playtime60Minutes" },
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

local playerMaids: { [Player]: any } = {}
local activeMaid = Maid.new()
local scriptAlive = true
local cleanupStarted = false
local badgeAwardService = BadgeAwardService.new()

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

local function syncLeaderstatValue(player: Player, valueObject: NumberValue, attributeName: string)
	local attributeValue = player:GetAttribute(attributeName)
	if typeof(attributeValue) ~= "number" then
		attributeValue = 0
	end
	valueObject.Value = math.round(attributeValue)
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

local function logOnboardingProgress(player: Player)
	FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_PLAYER_JOINED, "Player Joined", {
		customField01 = tostring(player:GetAttribute("Current_World") or "World1"),
	})

	if player:GetAttribute("TutorialSeen") == true then
		FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_TUTORIAL_SEEN, "Tutorial Seen")
	end

	local currentLevel = player:GetAttribute("CurrentLevel")
	if typeof(currentLevel) == "number" and currentLevel >= 3 then
		FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_LEVEL_THREE, "Reached Level 3")
	end

	local currentWins = player:GetAttribute("WinCount")
	if typeof(currentWins) == "number" and currentWins >= 1 then
		FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_FIRST_WIN, "Earned First Win")
	end

	if playerOwnsTutorialKart(player) then
		FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_TUTORIAL_KART_OWNED, "Owned Tutorial Kart")
	end

	if player:GetAttribute("TutorialCompleted") == true then
		FunnelAnalytics.LogOnboardingStep(player, ONBOARDING_STEP_TUTORIAL_COMPLETED, "Tutorial Completed")
	end
end

local function setupLeaderstatsSync(player: Player, playerMaid: any)
	local leaderstats = getOrCreateLeaderstatsFolder(player)

	for _, config in ipairs(LEADERSTAT_BINDINGS) do
		local leaderstatName = config.leaderstatName
		local existingValue = leaderstats:FindFirstChild(leaderstatName)
		local valueObject: NumberValue

		if existingValue and existingValue:IsA("NumberValue") then
			valueObject = existingValue
		else
			if existingValue then
				existingValue:Destroy()
			end

			valueObject = Instance.new("NumberValue")
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

	charMaid:GiveTask(humanoid.Died:Connect(function()
		LevelingService.TrackHumanoid(player, nil)
		TrollService.CleanupPlayer(player)

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

	playerMaid.DisableWavesCooldownTask = task.spawn(function()
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

	return requests
end

local function syncPlayerBadges(player: Player)
	badgeAwardService:SyncPlayer(player, getEligibleBadgeRequests(player))
end

local function onPlayerAdded(player: Player)
	local playerMaid = getPlayerMaid(player)

	-- Initialization Guard (Rule #3.24)
	if player:GetAttribute("PAM_Initialized") == true then
		-- If already initialized and we're here, it's a script reload.
		-- Rebind runtime systems without resetting player state.
		if player.Character then
			setupCharacter(player, player.Character)
		end
		SpinWheelService.OnPlayerAdded(player)
		PlaytimeRewardsService.OnPlayerAdded(player)
		DailyRewardsService.OnPlayerAdded(player)
		syncPlayerBadges(player)
		return
	end
	player:SetAttribute("PAM_Initialized", true)

	PlayerHandler.InitializePlayer(player)
	player:SetAttribute("Data_Loaded", false)
	player:SetAttribute("DisableWavesOnCooldown", false)
	player:SetAttribute("DisableWavesCooldownEnd", 0)

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

	-- Load Data. Never expose or save default state after a failed load.
	local loadStatus = ProductServerService.LoadPlayerData(player)
	if loadStatus == "Failed" then
		DebugModule.debugWarn(
			"Player initialization stopped because data load failed | player=" .. player.Name,
			MODULE_NAME
		)
		player:Kick("Your data could not be loaded. Please rejoin.")
		return
	elseif loadStatus == "RecoveryRequired" then
		DebugModule.debugWarn(
			"Player initialization stopped because saved data is missing but profile is registered | player="
				.. player.Name,
			MODULE_NAME
		)
		player:Kick("Your saved data needs recovery. Please contact the game developers.")
		return
	end
	SpinWheelService.OnPlayerAdded(player)
	LevelingService.OnPlayerAdded(player)

	-- Attributes Setup
	player:SetAttribute("Treadmill_Active", false)
	player:SetAttribute("Treadmill_XPMultiplier", 1)
	player:SetAttribute("Movement_XPGainInterval", PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_INTERVAL)

	EconomyService.SyncTrailState(player)
	EconomyService.SyncGamePassAttributes(player)
	PlayerHandler.ApplyFriendInviteMultiplier(player)
	logOnboardingProgress(player)

	PlaytimeRewardsService.OnPlayerAdded(player)
	DailyRewardsService.OnPlayerAdded(player)
	player:SetAttribute("Data_Loaded", true)
	ReferralService.OnPlayerAdded(player)
	ReturnToStageService.CheckQueuedRequest(player)
	PlayerHandler.SyncBloodmoonUnlocks(player)

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
end

local function cleanupPlayer(player: Player)
	local maid = playerMaids[player]
	if maid then
		maid:DoCleaning()
		playerMaids[player] = nil
	end
	badgeAwardService:CleanupPlayer(player)

	TrollService.CleanupPlayer(player)
	ReturnToStageService.CleanupPlayer(player)
	LevelingService.CleanupPlayer(player)
	PlaytimeRewardsService.CleanupPlayer(player)
	DailyRewardsService.CleanupPlayer(player)
	SpinWheelService.CleanupPlayer(player)

	ProductServerService.SavePlayerData(player, true) -- Force save on leave
	ProductServerService.CleanupPlayerState(player)
end

-- PRODUCT CALLBACKS (Rule #3.20: Contracts)
local function registerCallbacks()
	ProductServerService.SetProductCallback(ProductService.DevProducts.SkipRebirth, function(p, id, bought)
		LevelingService.PerformRebirth(p, true)
	end)

	ProductServerService.SetProductCallback(ProductService.DevProducts.DisableWaves, function(p, id, bought)
		local world = p:GetAttribute("Current_World")
		if typeof(world) == "string" then
			applyDisableWavesCooldown(p, DISABLE_WAVES_DURATION)
			TsunamiSystem.DisableWorldTsunamis(world, DISABLE_WAVES_DURATION)
			TsunamiSystem.ClearWorldTsunamis(world)
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
			ProductServerService.SetProductCallback(id, function(p)
				local awardedWins = PlayerHandler.AddWins(p, data.amount)
				EconomyAnalytics.LogSource(
					p,
					"Wins",
					awardedWins,
					Enum.AnalyticsEconomyTransactionType.IAP.Name,
					"DevProduct_" .. data.name,
					{ customField01 = data.name }
				)
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
			ProductServerService.SetProductCallback(id, function(p)
				local awardedAmount = PlayerHandler.AddXPSpeedProduct(p, data.amount)
				EconomyAnalytics.LogSource(
					p,
					"XPSpeed",
					awardedAmount,
					Enum.AnalyticsEconomyTransactionType.IAP.Name,
					"DevProduct_" .. data.name,
					{ customField01 = data.name }
				)
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
end

-- INITIALIZATION
ProductServerService.Init()
TemporaryBoostService.Init()
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

activeMaid.PlayerAdded = Players.PlayerAdded:Connect(onPlayerAdded)
activeMaid.PlayerRemoving = Players.PlayerRemoving:Connect(cleanupPlayer)
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
	activeMaid:DoCleaning()
	for _, player in ipairs(Players:GetPlayers()) do
		cleanupPlayer(player)
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
	ProductServerService.Shutdown()
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
