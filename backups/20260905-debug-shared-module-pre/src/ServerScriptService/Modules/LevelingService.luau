--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local DebugModule = require(game:GetService("ServerScriptService").Modules:WaitForChild("DebugModule_Server"))
local SystemChatService = require(game:GetService("ServerScriptService").Modules:WaitForChild("SystemChatService_Server"))
local VerifyRewardCalculator = require(game:GetService("ServerScriptService").Modules:WaitForChild("VerifyRewardCalculator_Server"))
local FunnelAnalytics = require(game:GetService("ServerScriptService").Modules:WaitForChild("FunnelAnalytics_Server"))
local Maid = require(Modules:WaitForChild("Maid"))
local ValidationService = require(script.Parent:WaitForChild("ValidationService_Server"))
local ConfigFolder = game:GetService("ServerScriptService").Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig_Server"))
local EconomyAnalytics = require(script.Parent:WaitForChild("EconomyAnalytics"))

local LevelingService = {}

-- CONFIG
local MODULE_NAME = "LevelingService"
local isInitialized = false
local serviceMaid = Maid.new()
local levelingConfig = CoreConfig.leveling
local verifyRewardConfig = VerifyRewardCalculator.GetConfig(CoreConfig)
local VERIFY_GROUP_ID = if CoreConfig.social and typeof(CoreConfig.social.verifyGroupId) == "number"
	then CoreConfig.social.verifyGroupId
	else 13706307
local VERIFY_REWARD_COOLDOWN_SECONDS = if levelingConfig
		and typeof(levelingConfig.verifyRewardCooldownSeconds) == "number"
	then math.max(0, levelingConfig.verifyRewardCooldownSeconds)
	else 24 * 60 * 60
local VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE = "VerifyRewardNextClaimUnix"
local VERIFY_DEBUG_IGNORE_COOLDOWN_IN_STUDIO = RunService:IsStudio()
	and levelingConfig
	and levelingConfig.debugVerifyIgnoreCooldownInStudio == true
local REBIRTH_CONFETTI_COLORS = if levelingConfig
		and typeof(levelingConfig.rebirthConfettiColors) == "table"
		and #levelingConfig.rebirthConfettiColors > 0
	then levelingConfig.rebirthConfettiColors
	else {
		Color3.fromRGB(255, 215, 0),
		Color3.fromRGB(255, 43, 43),
		Color3.fromRGB(0, 200, 255),
		Color3.fromRGB(57, 255, 20),
		Color3.fromRGB(170, 0, 255),
	}
local REBIRTH_CONFETTI_DURATION = if levelingConfig
		and typeof(levelingConfig.rebirthConfettiDuration) == "number"
	then levelingConfig.rebirthConfettiDuration
	else 1.5
local REBIRTH_CONFETTI_COUNT = if levelingConfig and typeof(levelingConfig.rebirthConfettiCount) == "number"
	then math.max(1, math.floor(levelingConfig.rebirthConfettiCount))
	else 70
local analyticsConfig = if CoreConfig.analytics then CoreConfig.analytics else nil
local analyticsFunnels = if analyticsConfig and typeof(analyticsConfig.funnels) == "table"
	then analyticsConfig.funnels
	else nil
local VERIFY_REWARD_FUNNEL_NAME = if analyticsFunnels and typeof(analyticsFunnels.verifyReward) == "string"
	then analyticsFunnels.verifyReward
	else "VerifyRewardClaim"
local REBIRTH_FUNNEL_NAME = if analyticsFunnels and typeof(analyticsFunnels.rebirth) == "string"
	then analyticsFunnels.rebirth
	else "RebirthFlow"

-- REMOTES
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MovementAction = Remotes:WaitForChild("MovementAction") :: RemoteEvent
local RebirthAction = Remotes:WaitForChild("RebirthAction") :: RemoteEvent
local XPGainAwarded = Remotes:WaitForChild("XPGainAwarded") :: RemoteEvent
local VerifyRewardRequest = Remotes:WaitForChild("VerifyRewardRequest") :: RemoteEvent
local VerifyRewardResult = Remotes:WaitForChild("VerifyRewardResult") :: RemoteEvent
local PlayConfettiBurst = Remotes:WaitForChild("PlayConfettiBurst") :: RemoteEvent
local RebirthResult = Remotes:WaitForChild("RebirthResult") :: RemoteEvent
local ShowNotification = Remotes:WaitForChild("ShowNotification") :: RemoteEvent

-- STATE
local lastMovementTime: { [Player]: number } = {}
local trackedHumanoids: { [Player]: Humanoid } = {}
local verifyRewardInFlight: { [Player]: boolean } = {}
local studioVerifyDataLoadedConnections: { [Player]: RBXScriptConnection } = {}
local verifyRewardFunnelSessions: { [Player]: string } = {}
local rebirthFunnelSessions: { [Player]: string } = {}

local function startVerifyRewardFunnel(player: Player): string?
	local nextClaimCount = player:GetAttribute("VerifyRewardClaimCount")
	if typeof(nextClaimCount) ~= "number" then
		nextClaimCount = 0
	end

	local sessionId = FunnelAnalytics.OpenRecurringFunnel(player, VERIFY_REWARD_FUNNEL_NAME, "Verify Reward Requested", {
		customField01 = tostring(nextClaimCount + 1),
	})
	verifyRewardFunnelSessions[player] = sessionId or ""
	return sessionId
end

local function getOrStartRebirthFunnelSession(player: Player, isPurchase: boolean): string?
	local existingSessionId = rebirthFunnelSessions[player]
	if typeof(existingSessionId) == "string" and existingSessionId ~= "" then
		return existingSessionId
	end

	local nextRebirthCount = player:GetAttribute("Rebirths")
	if typeof(nextRebirthCount) ~= "number" then
		nextRebirthCount = 0
	end

	local sessionId = FunnelAnalytics.OpenRecurringFunnel(player, REBIRTH_FUNNEL_NAME, "Rebirth Started", {
		customField01 = tostring(nextRebirthCount + 1),
		customField02 = if isPurchase then "Purchased" else "Normal",
	})
	if sessionId then
		rebirthFunnelSessions[player] = sessionId
	end

	return sessionId
end

local function getVerifyRewardNextClaimUnix(player: Player): number
	local rawValue = player:GetAttribute(VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE)
	if typeof(rawValue) ~= "number" then
		return 0
	end

	local nextClaimUnix = math.max(0, math.floor(rawValue))
	if nextClaimUnix <= 0 then
		return 0
	end

	if VERIFY_DEBUG_IGNORE_COOLDOWN_IN_STUDIO then
		player:SetAttribute(VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE, 0)
		return 0
	end

	local maxNextClaimUnix = os.time() + VERIFY_REWARD_COOLDOWN_SECONDS
	if VERIFY_REWARD_COOLDOWN_SECONDS >= 0 and nextClaimUnix > maxNextClaimUnix then
		player:SetAttribute(VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE, maxNextClaimUnix)
		return maxNextClaimUnix
	end

	return nextClaimUnix
end

local function clearVerifyCooldownForStudioDebug(player: Player)
	if not VERIFY_DEBUG_IGNORE_COOLDOWN_IN_STUDIO then
		return
	end

	local currentNextClaim = getVerifyRewardNextClaimUnix(player)
	if currentNextClaim ~= 0 then
		player:SetAttribute(VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE, 0)
	end
end

local function bindStudioVerifyCooldownReset(player: Player)
	if not VERIFY_DEBUG_IGNORE_COOLDOWN_IN_STUDIO then
		return
	end

	local existingConnection = studioVerifyDataLoadedConnections[player]
	if existingConnection then
		existingConnection:Disconnect()
		studioVerifyDataLoadedConnections[player] = nil
	end

	local function tryResetCooldown()
		if player:GetAttribute("Data_Loaded") == true then
			clearVerifyCooldownForStudioDebug(player)
		end
	end

	tryResetCooldown()
	local dataLoadedConnection = player:GetAttributeChangedSignal("Data_Loaded"):Connect(tryResetCooldown)
	studioVerifyDataLoadedConnections[player] = dataLoadedConnection
end

local function playRebirthConfetti(player: Player)
	PlayConfettiBurst:FireClient(player, REBIRTH_CONFETTI_COLORS, REBIRTH_CONFETTI_DURATION, REBIRTH_CONFETTI_COUNT)
end

local function isPointInsidePart(part: BasePart, point: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5
	return math.abs(localPoint.X) <= halfSize.X
		and math.abs(localPoint.Y) <= halfSize.Y
		and math.abs(localPoint.Z) <= halfSize.Z
end

local function findLobbyRegionPart(world: Instance?): BasePart?
	if not world then
		return nil
	end
	local lobbyRegionContainer = world:FindFirstChild("LobbyRegion_Model")
	if lobbyRegionContainer then
		local nestedLobbyRegion = lobbyRegionContainer:FindFirstChild("LobbyRegion", true)
		if nestedLobbyRegion and nestedLobbyRegion:IsA("BasePart") then
			return nestedLobbyRegion
		end
	end
	return nil
end

local function isPlayerInsideWorld1Lobby(player: Player): boolean
	if player:GetAttribute("Current_World") ~= "World1" then
		return false
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local worldsFolder = workspace:FindFirstChild("Worlds")
	local world1 = worldsFolder and worldsFolder:FindFirstChild("World1")
	local lobbyRegion = findLobbyRegionPart(world1)
	if not lobbyRegion then
		return false
	end

	return isPointInsidePart(lobbyRegion, rootPart.Position)
end

local function sendPlayerToWorld1Spawn(player: Player)
	player:SetAttribute("Current_World", "World1")
	player:SetAttribute("CurrentStage", 0)
	player:SetAttribute("Treadmill_Active", false)

	local character = player.Character
	if not character then
		return
	end

	local worldsFolder = workspace:FindFirstChild("Worlds")
	local world1 = worldsFolder and worldsFolder:FindFirstChild("World1")
	local spawnLocation = world1 and world1:FindFirstChild("SpawnLocation")
	if spawnLocation and spawnLocation:IsA("BasePart") then
		character:PivotTo(spawnLocation:GetPivot() * CFrame.new(0, 3, 0))
		ValidationService.MarkServerTeleport(player)
	end
end

function LevelingService.IsPlayerInsideWorld1Lobby(player: Player): boolean
	return isPlayerInsideWorld1Lobby(player)
end

function LevelingService.SendPlayerToWorld1Spawn(player: Player)
	sendPlayerToWorld1Spawn(player)
end

function LevelingService.OnMovementAction(player: Player)
	local humanoid = trackedHumanoids[player]
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	if player:GetAttribute("Treadmill_Active") == true then
		return
	end
	if not ValidationService.ValidateRewardEligibility(player, "MovementXP") then
		return
	end

	local now = os.clock()
	local lastTime = lastMovementTime[player] or 0
	local interval = PlayerHandler.GetMovementInterval(player)
	local tolerance = PlayerHandler.MOVEMENT_CONFIG.XP_GAIN_TOLERANCE

	if now >= lastTime + interval - tolerance then
		lastMovementTime[player] = math.max(now, lastTime + interval)
		local awardedAmount = PlayerHandler.AddXPSpeed(player, PlayerHandler.GetMovementGain(player))
		XPGainAwarded:FireClient(player, awardedAmount)
	end
end

function LevelingService.PerformRebirth(player: Player, isPurchase: boolean)
	local success = PlayerHandler.PerformRebirth(player, isPurchase)
	if success then
		local rebirthSessionId = getOrStartRebirthFunnelSession(player, isPurchase)
		if not isPlayerInsideWorld1Lobby(player) then
			sendPlayerToWorld1Spawn(player)
		end

		local rebirths = player:GetAttribute("Rebirths") or 0
		RebirthResult:FireClient(player)
		playRebirthConfetti(player)
		SystemChatService.BroadcastLocalRebirth(player, rebirths)
		if rebirthSessionId then
			FunnelAnalytics.LogRecurringStep(
				player,
				REBIRTH_FUNNEL_NAME,
				rebirthSessionId,
				2,
				"Rebirth Completed",
				{
					customField01 = tostring(rebirths),
					customField02 = if isPurchase then "Purchased" else "Normal",
				}
			)
			rebirthFunnelSessions[player] = nil
		end
		DebugModule.debugInfo(
			string.format("Player %s rebirthed (Purchase: %s)", player.Name, tostring(isPurchase)),
			MODULE_NAME
		)
		return true
	end

	rebirthFunnelSessions[player] = nil
	if not isPurchase then
		ShowNotification:FireClient(player, "MAX LEVEL REQUIRED!", "Red")
	end
	return false
end

function LevelingService.OnRebirthRequest(player: Player)
	local currentLevel = player:GetAttribute("CurrentLevel") or 1
	local maxLevel = player:GetAttribute("MaxLevel") or 25

	if currentLevel >= maxLevel then
		getOrStartRebirthFunnelSession(player, false)
		LevelingService.PerformRebirth(player, false)
	else
		ShowNotification:FireClient(player, "MAX LEVEL REQUIRED!", "Red")
	end
end

function LevelingService.OnVerifyRewardRequest(player: Player)
	if verifyRewardInFlight[player] == true then
		DebugModule.debugInfo("Verify reward request ignored (in flight) for " .. player.Name, MODULE_NAME)
		return
	end

	if player:GetAttribute("Data_Loaded") ~= true then
		local verifyRewardSessionId = startVerifyRewardFunnel(player)
		if verifyRewardSessionId then
			FunnelAnalytics.LogRecurringStep(
				player,
				VERIFY_REWARD_FUNNEL_NAME,
				verifyRewardSessionId,
				2,
				"Verify Data Not Loaded"
			)
			verifyRewardFunnelSessions[player] = nil
		end
		VerifyRewardResult:FireClient(player, false, getVerifyRewardNextClaimUnix(player))
		return
	end

	if not ValidationService.ValidateRewardEligibility(player, "VerifyReward") then
		VerifyRewardResult:FireClient(player, false, getVerifyRewardNextClaimUnix(player))
		return
	end

	if VERIFY_DEBUG_IGNORE_COOLDOWN_IN_STUDIO then
		clearVerifyCooldownForStudioDebug(player)
	else
		local requestUnix = os.time()
		local requestNextClaimUnix = getVerifyRewardNextClaimUnix(player)
		if requestNextClaimUnix > requestUnix then
			local verifyRewardSessionId = startVerifyRewardFunnel(player)
			if verifyRewardSessionId then
				FunnelAnalytics.LogRecurringStep(
					player,
					VERIFY_REWARD_FUNNEL_NAME,
					verifyRewardSessionId,
					2,
					"Verify Reward Cooldown"
				)
				verifyRewardFunnelSessions[player] = nil
			end
			VerifyRewardResult:FireClient(player, false, requestNextClaimUnix)
			return
		end
	end

	verifyRewardInFlight[player] = true
	local verifyRewardSessionId = startVerifyRewardFunnel(player)

	local function releaseVerifyRewardLock()
		verifyRewardInFlight[player] = nil
	end

	local success, inGroup = pcall(function()
		return player:IsInGroup(VERIFY_GROUP_ID)
	end)

	if not success or not inGroup then
		if verifyRewardSessionId then
			FunnelAnalytics.LogRecurringStep(
				player,
				VERIFY_REWARD_FUNNEL_NAME,
				verifyRewardSessionId,
				2,
				"Verify Group Missing"
			)
		end
		verifyRewardFunnelSessions[player] = nil
		releaseVerifyRewardLock()
		VerifyRewardResult:FireClient(player, false, getVerifyRewardNextClaimUnix(player))
		return
	end

	if verifyRewardSessionId then
		FunnelAnalytics.LogRecurringStep(
			player,
			VERIFY_REWARD_FUNNEL_NAME,
			verifyRewardSessionId,
			2,
			"Verify Group Membership"
		)
	end

	local nowUnix = os.time()
	if not VERIFY_DEBUG_IGNORE_COOLDOWN_IN_STUDIO then
		local nextClaimUnix = getVerifyRewardNextClaimUnix(player)
		if nextClaimUnix > nowUnix then
			if verifyRewardSessionId then
				FunnelAnalytics.LogRecurringStep(
					player,
					VERIFY_REWARD_FUNNEL_NAME,
					verifyRewardSessionId,
					3,
					"Verify Reward Cooldown"
				)
			end
			verifyRewardFunnelSessions[player] = nil
			releaseVerifyRewardLock()
			VerifyRewardResult:FireClient(player, false, nextClaimUnix)
			return
		end
	end

	local awardedXP = 0
	local awardedWins = 0
	local grantSuccess, grantErr = pcall(function()
		local rewardPreview = VerifyRewardCalculator.ComputeRewardsForNextClaim(player, verifyRewardConfig)
		awardedXP = PlayerHandler.AddExactXPSpeed(player, rewardPreview.xpAward)

		local currentWins = player:GetAttribute("WinCount") or 0
		PlayerHandler.SetAttribute(player, "WinCount", currentWins + rewardPreview.winsAward)
		awardedWins = rewardPreview.winsAward
	end)
	if not grantSuccess then
		if verifyRewardSessionId then
			FunnelAnalytics.LogRecurringStep(
				player,
				VERIFY_REWARD_FUNNEL_NAME,
				verifyRewardSessionId,
				3,
				"Verify Reward Grant Failed"
			)
		end
		verifyRewardFunnelSessions[player] = nil
		releaseVerifyRewardLock()
		DebugModule.debugWarn(
			"Verify reward grant failed for " .. player.Name .. ": " .. tostring(grantErr),
			MODULE_NAME
		)
		VerifyRewardResult:FireClient(player, false, getVerifyRewardNextClaimUnix(player))
		return
	end

	local updatedNextClaimUnix = if VERIFY_DEBUG_IGNORE_COOLDOWN_IN_STUDIO
		then 0
		else nowUnix + VERIFY_REWARD_COOLDOWN_SECONDS
	player:SetAttribute("VerifyRewardClaimed", true)
	player:SetAttribute(VERIFY_REWARD_NEXT_CLAIM_ATTRIBUTE, updatedNextClaimUnix)
	VerifyRewardCalculator.AdvanceClaimCount(player, verifyRewardConfig)

	XPGainAwarded:FireClient(player, awardedXP)
	EconomyAnalytics.LogSource(
		player,
		"XPSpeed",
		awardedXP,
		Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
		"VerifyReward",
		{ customField01 = tostring(player:GetAttribute("VerifyRewardClaimCount") or 0) }
	)
	EconomyAnalytics.LogSource(
		player,
		"Wins",
		awardedWins,
		Enum.AnalyticsEconomyTransactionType.TimedReward.Name,
		"VerifyReward",
		{ customField01 = tostring(player:GetAttribute("VerifyRewardClaimCount") or 0) }
	)
	local winRemote = Remotes:FindFirstChild("WinButtonPressed")
	if winRemote and winRemote:IsA("RemoteEvent") then
		winRemote:FireClient(player, awardedWins, "VerifyReward")
	end

	if verifyRewardSessionId then
		FunnelAnalytics.LogRecurringStep(
			player,
			VERIFY_REWARD_FUNNEL_NAME,
			verifyRewardSessionId,
			3,
			"Verify Reward Granted",
			{
				customField01 = tostring(player:GetAttribute("VerifyRewardClaimCount") or 0),
			}
		)
	end

	releaseVerifyRewardLock()
	verifyRewardFunnelSessions[player] = nil
	VerifyRewardResult:FireClient(player, true, updatedNextClaimUnix)
end

function LevelingService.TrackHumanoid(player: Player, humanoid: Humanoid?)
	trackedHumanoids[player] = humanoid
	if not humanoid then
		lastMovementTime[player] = 0
	end
end

function LevelingService.OnPlayerAdded(player: Player)
	getVerifyRewardNextClaimUnix(player)
end

function LevelingService.CleanupPlayer(player: Player)
	lastMovementTime[player] = nil
	trackedHumanoids[player] = nil
	verifyRewardInFlight[player] = nil
	verifyRewardFunnelSessions[player] = nil
	rebirthFunnelSessions[player] = nil
	local dataLoadedConnection = studioVerifyDataLoadedConnections[player]
	if dataLoadedConnection then
		dataLoadedConnection:Disconnect()
		studioVerifyDataLoadedConnections[player] = nil
	end
end

function LevelingService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	serviceMaid.MovementAction = MovementAction.OnServerEvent:Connect(LevelingService.OnMovementAction)
	serviceMaid.RebirthAction = RebirthAction.OnServerEvent:Connect(LevelingService.OnRebirthRequest)
	serviceMaid.VerifyRewardRequest = VerifyRewardRequest.OnServerEvent:Connect(LevelingService.OnVerifyRewardRequest)
	if VERIFY_DEBUG_IGNORE_COOLDOWN_IN_STUDIO then
		for _, player in ipairs(Players:GetPlayers()) do
			bindStudioVerifyCooldownReset(player)
		end
		serviceMaid.PlayerAdded = Players.PlayerAdded:Connect(bindStudioVerifyCooldownReset)
	end
	DebugModule.debugInfo("LevelingService Initialized", MODULE_NAME)
end

function LevelingService.Shutdown()
	for player, connection in pairs(table.clone(studioVerifyDataLoadedConnections)) do
		connection:Disconnect()
		studioVerifyDataLoadedConnections[player] = nil
	end
	serviceMaid:DoCleaning()
	isInitialized = false
end

return LevelingService
