--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CoreConfig = require(Modules:WaitForChild("Config"):WaitForChild("CoreConfig"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local Maid = require(Modules:WaitForChild("Maid"))
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local SoundService = require(Modules:WaitForChild("SoundService"))
local ValidationService = require(Modules:WaitForChild("ValidationService"))
local EconomyAnalytics = require(script.Parent:WaitForChild("EconomyAnalytics"))
local LevelingService = require(script.Parent:WaitForChild("LevelingService"))

local MinigameService = {}

type RaceState = "Open" | "Grace" | "Starting" | "Countdown" | "Racing" | "Cooldown"

type ParticipantState = {
	order: number,
	finished: boolean,
	maid: any,
}

type ReturnFreezeState = {
	character: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
	rootAnchored: boolean,
	thread: thread?,
}

local MODULE_NAME = "MinigameService"
local DEFAULT_REQUIRED_PLAYERS = 5
local DEFAULT_MAX_PLAYERS = 20
local DEFAULT_GRACE_SECONDS = 30
local DEFAULT_PRE_COUNTDOWN_GRACE_SECONDS = 3
local DEFAULT_COUNTDOWN_FALLBACK_SECONDS = 3
local DEFAULT_RACE_TIMEOUT_SECONDS = 180
local DEFAULT_COOLDOWN_SECONDS = 5 * 60
local DEFAULT_RETURN_FREEZE_SECONDS = 1
local DEFAULT_COUNTDOWN_SOUND_ID = 100324658979992
local RACE_VOID_NOTIFICATION = "NOT ENOUGH PLAYERS TO START RACE!"

local serverConfig = CoreConfig.server
local minigameConfig = if serverConfig and typeof(serverConfig.minigame) == "table"
	then serverConfig.minigame
	else nil

local function readNumber(name: string, fallback: number, minimum: number): number
	local value = minigameConfig and minigameConfig[name]
	if typeof(value) ~= "number" then
		return fallback
	end

	return math.max(minimum, value)
end

local REQUIRED_PLAYERS = math.floor(readNumber("requiredPlayers", DEFAULT_REQUIRED_PLAYERS, 1))
local MAX_PLAYERS = math.floor(readNumber("maxPlayers", DEFAULT_MAX_PLAYERS, REQUIRED_PLAYERS))
local GRACE_SECONDS = readNumber("gracePeriodSeconds", DEFAULT_GRACE_SECONDS, 1)
local PRE_COUNTDOWN_GRACE_SECONDS = readNumber(
	"preCountdownGraceSeconds",
	DEFAULT_PRE_COUNTDOWN_GRACE_SECONDS,
	0
)
local COUNTDOWN_FALLBACK_SECONDS = readNumber(
	"countdownFallbackSeconds",
	DEFAULT_COUNTDOWN_FALLBACK_SECONDS,
	1
)
local RACE_TIMEOUT_SECONDS = readNumber("raceTimeoutSeconds", DEFAULT_RACE_TIMEOUT_SECONDS, 1)
local COOLDOWN_SECONDS = readNumber("cooldownSeconds", DEFAULT_COOLDOWN_SECONDS, 0)
local RETURN_FREEZE_SECONDS = readNumber("returnFreezeSeconds", DEFAULT_RETURN_FREEZE_SECONDS, 0)
local COUNTDOWN_SOUND_ID = if minigameConfig and typeof(minigameConfig.countdownSoundId) == "number"
	then minigameConfig.countdownSoundId
	else DEFAULT_COUNTDOWN_SOUND_ID
local DEBUG_ALLOW_SINGLE_PLAYER = RunService:IsStudio()
	and minigameConfig ~= nil
	and minigameConfig.debugAllowSinglePlayerInStudio == true
local DEBUG_SKIP_COOLDOWN = RunService:IsStudio()
	and minigameConfig ~= nil
	and minigameConfig.debugSkipCooldownInStudio == true

local worldsFolder = Workspace:FindFirstChild("Worlds")
local minigameWorld = worldsFolder and worldsFolder:FindFirstChild("Minigame")
assert(minigameWorld, "Workspace.Worlds.Minigame is required")

local cooldownStart = minigameWorld:FindFirstChild("CooldownStart")
local cooldownStartSecond = minigameWorld:FindFirstChild("CooldownStart_2nd")
local finishLine = minigameWorld:FindFirstChild("FinishLine")
local teleportZone = minigameWorld:FindFirstChild("TeleportZone")
assert(cooldownStart and cooldownStart:IsA("BasePart"), "Minigame.CooldownStart must be a BasePart")
assert(
	cooldownStartSecond and cooldownStartSecond:IsA("BasePart"),
	"Minigame.CooldownStart_2nd must be a BasePart"
)
assert(finishLine and finishLine:IsA("BasePart"), "Minigame.FinishLine must be a BasePart")
assert(teleportZone and teleportZone:IsA("BasePart"), "Minigame.TeleportZone must be a BasePart")

local startSurfaceGui = cooldownStart:FindFirstChild("SurfaceGui1")
local countdownSurfaceGui = cooldownStart:FindFirstChild("SurfaceGui2")
local countdownFrame = countdownSurfaceGui and countdownSurfaceGui:FindFirstChild("Frame")
local countdownLabel = countdownFrame and countdownFrame:FindFirstChild("CountdownLabel")
assert(startSurfaceGui and startSurfaceGui:IsA("SurfaceGui"), "Minigame SurfaceGui1 is required")
assert(countdownSurfaceGui and countdownSurfaceGui:IsA("SurfaceGui"), "Minigame SurfaceGui2 is required")
assert(countdownLabel and countdownLabel:IsA("TextLabel"), "Minigame CountdownLabel is required")

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local function getOrCreateRemote(name: string): RemoteEvent
	local existing = remotes:FindFirstChild(name)
	if existing then
		assert(existing:IsA("RemoteEvent"), name .. " must be a RemoteEvent")
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remotes
	return remote
end

local joinRequest = getOrCreateRemote("MinigameJoinRequest")
local raceNotification = getOrCreateRemote("MinigameRaceNotification")
local showNotification = getOrCreateRemote("ShowNotification")
local winButtonPressed = getOrCreateRemote("WinButtonPressed")
local xpGainAwarded = getOrCreateRemote("XPGainAwarded")

SoundService.RegisterSound("MinigameCountdown", {
	SoundId = COUNTDOWN_SOUND_ID,
	Volume = 0,
	PlaybackSpeed = 1,
	Looped = false,
	AllowOverlap = false,
})

local serviceMaid = Maid.new()
local participants: { [Player]: ParticipantState } = {}
local joinRequestLastAt: { [Player]: number } = {}
local raceState: RaceState = "Open"
local phaseThread: thread? = nil
local phaseToken = 0
local joinOrder = 0
local finishCount = 0
local activeCountdownSound: Sound? = nil
local returnFreezeStates: { [Player]: ReturnFreezeState } = {}
local initialized = false

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function setWorldAttribute(name: string, value: any)
	minigameWorld:SetAttribute(name, value)
end

local function setPlayerState(player: Player, participant: boolean, state: string, placement: number?)
	player:SetAttribute("MinigameParticipant", participant)
	player:SetAttribute("MinigameState", state)
	player:SetAttribute("MinigamePlacement", placement)
end

local function getParticipantCount(): number
	local count = 0
	for _ in pairs(participants) do
		count += 1
	end
	return count
end

local function updatePlayerCount()
	setWorldAttribute("RacePlayerCount", getParticipantCount())
	setWorldAttribute("RaceRequiredPlayers", REQUIRED_PLAYERS)
end

local function hasEnoughParticipants(): boolean
	local participantCount = getParticipantCount()
	return participantCount >= REQUIRED_PLAYERS or (DEBUG_ALLOW_SINGLE_PLAYER and participantCount >= 1)
end

local function setRaceSurfaceGuisVisible(visible: boolean)
	startSurfaceGui.Enabled = visible
	countdownSurfaceGui.Enabled = visible
end

local function setRaceState(nextState: RaceState)
	raceState = nextState
	setRaceSurfaceGuisVisible(nextState ~= "Racing")
	setWorldAttribute("RaceState", nextState)
	updatePlayerCount()
end

local function setBarriers(canCollide: boolean)
	cooldownStart.CanCollide = canCollide
	cooldownStartSecond.CanCollide = canCollide
end

local function resetRacePhaseState()
	countdownLabel.Text = ""
	setWorldAttribute("GraceEndsAt", 0)
	setWorldAttribute("CountdownEndsAt", 0)
	setWorldAttribute("RaceEndsAt", 0)
end

local function clearFinishedPlayerStates()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("MinigameParticipant") ~= true then
			setPlayerState(player, false, "None", nil)
		end
	end
end

local function cancelPhaseThread()
	phaseToken += 1
	local runningThread = coroutine.running()
	if phaseThread and phaseThread ~= runningThread then
		task.cancel(phaseThread)
	end
	phaseThread = nil
end

local function stopCountdownSound()
	local sound = activeCountdownSound
	activeCountdownSound = nil
	if sound and sound.Parent then
		sound:Stop()
		sound:Destroy()
	end
end

local function notify(
	player: Player,
	eventName: string,
	placement: number?,
	awardedWins: number?,
	awardedLevels: number?,
	message: string?
)
	raceNotification:FireClient(player, eventName, placement, awardedWins, awardedLevels, message)
end

local function getRaceSpawnCFrame(order: number): CFrame
	local columns = 5
	local columnIndex = (order - 1) % columns
	local rowIndex = math.floor((order - 1) / columns)
	local xOffset = (columnIndex - 2) * 8
	local zOffset = math.min(18, rowIndex * 8)
	local safeHeight = teleportZone.Size.Y * 0.5 + 3

	return teleportZone.CFrame * CFrame.new(xOffset, safeHeight, zOffset)
end

local function restoreReturnFreeze(player: Player, state: ReturnFreezeState)
	if player.Character ~= state.character
		or not state.character.Parent
		or not state.humanoid.Parent
		or not state.rootPart.Parent
	then
		return
	end

	state.humanoid.WalkSpeed = state.walkSpeed
	state.humanoid.JumpPower = state.jumpPower
	state.humanoid.JumpHeight = state.jumpHeight
	state.humanoid.AutoRotate = state.autoRotate
	state.rootPart.AssemblyLinearVelocity = Vector3.zero
	state.rootPart.AssemblyAngularVelocity = Vector3.zero
	state.rootPart.Anchored = state.rootAnchored
	state.rootPart.AssemblyLinearVelocity = Vector3.zero
	state.rootPart.AssemblyAngularVelocity = Vector3.zero
end

local function cancelReturnFreeze(player: Player)
	local state = returnFreezeStates[player]
	if not state then
		return
	end

	returnFreezeStates[player] = nil
	if state.thread and state.thread ~= coroutine.running() then
		task.cancel(state.thread)
	end
	restoreReturnFreeze(player, state)
end

local function freezePlayerAfterReturn(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not rootPart or not rootPart:IsA("BasePart") or humanoid.Health <= 0 then
		return
	end

	local state = returnFreezeStates[player]
	if not state or state.character ~= character or state.humanoid ~= humanoid or state.rootPart ~= rootPart then
		if state then
			cancelReturnFreeze(player)
		end
		state = {
			character = character,
			humanoid = humanoid,
			rootPart = rootPart,
			walkSpeed = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			jumpHeight = humanoid.JumpHeight,
			autoRotate = humanoid.AutoRotate,
			rootAnchored = rootPart.Anchored,
			thread = nil,
		}
		returnFreezeStates[player] = state
	elseif state.thread then
		task.cancel(state.thread)
	end

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid.Jump = false
	rootPart.Anchored = true
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	state.thread = task.spawn(function()
		task.wait(RETURN_FREEZE_SECONDS)
		if returnFreezeStates[player] ~= state then
			return
		end

		returnFreezeStates[player] = nil
		state.thread = nil
		restoreReturnFreeze(player, state)
	end)
end

local function returnPlayerToWorld1(player: Player)
	if ValidationService.IsPlayerAlive(player) then
		LevelingService.SendPlayerToWorld1Spawn(player)
		freezePlayerAfterReturn(player)
	end
end

local function getPlayerFromRaceTouch(hit: BasePart): Player?
	local characterPlayer = ValidationService.GetAlivePlayerFromTouch(hit)
	if characterPlayer then
		return characterPlayer
	end

	local kartModel = hit:FindFirstAncestor("EquippedKart")
	if not kartModel or not kartModel:IsA("Model") then
		return nil
	end

	local ownerUserId = kartModel:GetAttribute("KartOwnerUserId")
	if typeof(ownerUserId) ~= "number" then
		return nil
	end

	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner or not ValidationService.IsPlayerAlive(owner) then
		return nil
	end

	return owner
end

local removeParticipant: (player: Player, reason: string, returnPlayer: boolean) -> ()
local startCooldown: (reason: string, notificationMessage: string?) -> ()
local finishRace: (reason: string) -> ()
local beginGrace: () -> ()

local function bindParticipantCharacter(player: Player, participant: ParticipantState)
	local function bindHumanoid(character: Model)
		participant.maid.HumanoidDied = nil
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		participant.maid.HumanoidDied = humanoid.Died:Connect(function()
			removeParticipant(player, "Died", false)
		end)
	end

	local character = player.Character
	if character then
		bindHumanoid(character)
	end
	participant.maid.CharacterAdded = player.CharacterAdded:Connect(bindHumanoid)
	participant.maid.WorldChanged = player:GetAttributeChangedSignal("Current_World"):Connect(function()
		if player:GetAttribute("Current_World") ~= "World1" then
			removeParticipant(player, "WorldChanged", true)
		end
	end)
end

local function clearParticipant(player: Player, participant: ParticipantState, returnPlayer: boolean, state: string)
	if returnPlayer then
		returnPlayerToWorld1(player)
	end

	participant.maid:DoCleaning()
	participants[player] = nil
	setPlayerState(player, false, state, player:GetAttribute("MinigamePlacement") :: number?)
	updatePlayerCount()
end

local function snapshotParticipants(): { Player }
	local snapshot = {}
	for player in pairs(participants) do
		table.insert(snapshot, player)
	end
	return snapshot
end

local function clearAllParticipants(notificationMessage: string?, returnPlayer: boolean)
	for _, player in ipairs(snapshotParticipants()) do
		local participant = participants[player]
		if participant then
			if notificationMessage then
				notify(player, "RaceEnded", nil, nil, nil, notificationMessage)
			end
			clearParticipant(player, participant, returnPlayer, "Finished")
		end
	end
end

local function calculateBaseWins(player: Player, placement: number): number
	local currentWins = player:GetAttribute("WinCount")
	if typeof(currentWins) ~= "number" then
		currentWins = 0
	end

	local rate = if placement == 1 then 0.4 elseif placement == 2 then 0.2 elseif placement == 3 then 0.05 else 0.01
	local rounded = math.floor(math.max(0, currentWins) * rate / 10) * 10
	return math.max(100, rounded)
end

local function getLevelReward(placement: number): number
	return if placement == 1 then 5 elseif placement == 2 then 2 else 0
end

local function formatPlacement(placement: number): string
	local lastTwoDigits = placement % 100
	local suffix = if lastTwoDigits >= 11 and lastTwoDigits <= 13
		then "TH"
		elseif placement % 10 == 1
		then "ST"
		elseif placement % 10 == 2
		then "ND"
		elseif placement % 10 == 3
		then "RD"
		else "TH"
	return tostring(placement) .. suffix
end

local function awardPlacement(player: Player, placement: number)
	local participant = participants[player]
	if not participant or participant.finished or raceState ~= "Racing" then
		return
	end

	participant.finished = true
	finishCount += 1
	participant.maid:DoCleaning()

	local baseWins = calculateBaseWins(player, placement)
	local beforeAllXPSpeed = player:GetAttribute("AllXPSpeed")
	if typeof(beforeAllXPSpeed) ~= "number" then
		beforeAllXPSpeed = 0
	end

	local awardedWins = PlayerHandler.AddWins(player, baseWins)
	local awardedLevels = PlayerHandler.AddLevels(player, getLevelReward(placement))
	if placement == 1 then
		local currentRaceWins = player:GetAttribute("MinigameRaceWins")
		if typeof(currentRaceWins) ~= "number" then
			currentRaceWins = 0
		end
		PlayerHandler.SetAttribute(player, "MinigameRaceWins", math.max(0, math.floor(currentRaceWins)) + 1)
	end
	local afterAllXPSpeed = player:GetAttribute("AllXPSpeed")
	if typeof(afterAllXPSpeed) ~= "number" then
		afterAllXPSpeed = beforeAllXPSpeed
	end
	local awardedXPSpeed = math.max(0, afterAllXPSpeed - beforeAllXPSpeed)
	if awardedWins > 0 then
		winButtonPressed:FireClient(player, awardedWins, "MinigameRace")
	end
	if awardedXPSpeed > 0 then
		xpGainAwarded:FireClient(player, awardedXPSpeed)
	end

	EconomyAnalytics.LogSource(
		player,
		"Wins",
		awardedWins,
		Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
		"MinigameRace",
		{ customField01 = tostring(placement), customField02 = "Placement" }
	)
	if awardedXPSpeed > 0 then
		EconomyAnalytics.LogSource(
			player,
			"XPSpeed",
			awardedXPSpeed,
			Enum.AnalyticsEconomyTransactionType.Gameplay.Name,
			"MinigameRaceLevelReward",
			{ customField01 = tostring(placement), customField02 = tostring(awardedLevels) }
		)
	end

	setPlayerState(player, false, "Finished", placement)
	returnPlayerToWorld1(player)
	showNotification:FireClient(
		player,
		"CONGRATULATIONS! YOU GOT " .. formatPlacement(placement) .. " PLACE!",
		"Gold"
	)
	participants[player] = nil
	updatePlayerCount()

	if getParticipantCount() <= 0 then
		finishRace("All racers finished")
	end
end

removeParticipant = function(player: Player, reason: string, returnPlayer: boolean)
	local participant = participants[player]
	if not participant then
		return
	end

	clearParticipant(player, participant, returnPlayer, "Finished")
	DebugModule.debugInfo(
		string.format("Removed %s from race (%s)", player.Name, reason),
		MODULE_NAME
	)

	if (raceState == "Starting" or raceState == "Countdown") and not hasEnoughParticipants() then
		startCooldown("Pre-race player requirement lost", RACE_VOID_NOTIFICATION)
	elseif raceState == "Racing" and getParticipantCount() <= 0 then
		finishRace("No racers remaining")
	end
end

local function setOpenState()
	resetRacePhaseState()
	setWorldAttribute("CooldownEndsAt", 0)
end

local function runCooldown(token: number)
	local cooldownSeconds = if DEBUG_SKIP_COOLDOWN then 0 else COOLDOWN_SECONDS
	local deadline = serverNow() + cooldownSeconds
	resetRacePhaseState()
	setWorldAttribute("CooldownEndsAt", deadline)

	phaseThread = task.spawn(function()
		local remaining = math.max(0, deadline - serverNow())
		if remaining > 0 then
			task.wait(remaining)
		end
		if token ~= phaseToken or raceState ~= "Cooldown" then
			return
		end

		setOpenState()
		setRaceState("Open")
		phaseThread = nil
		-- Every completed cooldown opens a synchronized join window. Studio only
		-- changes the cooldown duration; it does not change the race flow.
		beginGrace()
	end)
end

startCooldown = function(reason: string, notificationMessage: string?)
	cancelPhaseThread()
	stopCountdownSound()
	resetRacePhaseState()
	setBarriers(true)
	local isRaceVoid = notificationMessage == RACE_VOID_NOTIFICATION
	if isRaceVoid then
		for _, player in ipairs(snapshotParticipants()) do
			showNotification:FireClient(player, RACE_VOID_NOTIFICATION, "Red")
		end
	end
	clearAllParticipants(if isRaceVoid then nil else notificationMessage, true)
	clearFinishedPlayerStates()
	finishCount = 0
	joinOrder = 0
	setRaceState("Cooldown")
	DebugModule.debugInfo(string.format("Race entered cooldown (%s)", reason), MODULE_NAME)
	runCooldown(phaseToken)
end

finishRace = function(reason: string)
	if raceState ~= "Racing" then
		return
	end

	startCooldown(reason, "RACE COMPLETE!")
end

local function voidRace(reason: string)
	if raceState ~= "Grace" then
		return
	end

	startCooldown(reason, RACE_VOID_NOTIFICATION)
end

local function startRace(token: number)
	if token ~= phaseToken or raceState ~= "Countdown" then
		return
	end
	if not hasEnoughParticipants() then
		startCooldown("Countdown ended below required players", RACE_VOID_NOTIFICATION)
		return
	end

	setBarriers(false)
	setWorldAttribute("CountdownEndsAt", 0)
	setWorldAttribute("RaceEndsAt", serverNow() + RACE_TIMEOUT_SECONDS)
	setRaceState("Racing")
	for player in pairs(participants) do
		setPlayerState(player, true, "Racing", nil)
	end

	phaseThread = task.spawn(function()
		local deadline = serverNow() + RACE_TIMEOUT_SECONDS
		while token == phaseToken and raceState == "Racing" and serverNow() < deadline do
			task.wait(0.25)
		end

		if token == phaseToken and raceState == "Racing" then
			finishRace("Race timeout")
		end
	end)
end

local function startActualCountdown(token: number)
	if token ~= phaseToken or raceState ~= "Starting" then
		return
	end
	if not hasEnoughParticipants() then
		startCooldown("Starting phase ended below required players", RACE_VOID_NOTIFICATION)
		return
	end

	activeCountdownSound = SoundService.PlayWorkspaceSound("MinigameCountdown", cooldownStart)
	local countdownDeadline = serverNow() + COUNTDOWN_FALLBACK_SECONDS

	countdownLabel.Text = "3"
	setWorldAttribute("CountdownEndsAt", countdownDeadline)
	setBarriers(true)
	setRaceSurfaceGuisVisible(true)
	setRaceState("Countdown")

	phaseThread = task.spawn(function()
		while token == phaseToken and raceState == "Countdown" and serverNow() < countdownDeadline do
			task.wait(0.1)
		end

		if token ~= phaseToken or raceState ~= "Countdown" then
			return
		end

		stopCountdownSound()
		countdownLabel.Text = "START!"
		task.wait(0.2)
		if token == phaseToken and raceState == "Countdown" then
			startRace(token)
		end
	end)
end

local function beginCountdown()
	cancelPhaseThread()
	setWorldAttribute("GraceEndsAt", 0)
	setWorldAttribute("CountdownEndsAt", 0)
	setRaceState("Starting")
	setBarriers(true)
	setRaceSurfaceGuisVisible(true)
	countdownLabel.Text = "STARTING"

	local token = phaseToken
	phaseThread = task.spawn(function()
		local deadline = serverNow() + PRE_COUNTDOWN_GRACE_SECONDS
		while token == phaseToken and raceState == "Starting" and serverNow() < deadline do
			task.wait(0.1)
		end

		if token == phaseToken and raceState == "Starting" then
			startActualCountdown(token)
		end
	end)
end

beginGrace = function()
	cancelPhaseThread()
	stopCountdownSound()
	resetRacePhaseState()
	setWorldAttribute("CooldownEndsAt", 0)
	finishCount = 0
	joinOrder = 0
	local token = phaseToken
	local deadline = serverNow() + GRACE_SECONDS
	setWorldAttribute("GraceEndsAt", deadline)
	setWorldAttribute("CountdownEndsAt", 0)
	setBarriers(true)
	setRaceSurfaceGuisVisible(true)
	setRaceState("Grace")

	phaseThread = task.spawn(function()
		while token == phaseToken and raceState == "Grace" and serverNow() < deadline do
			task.wait(0.25)
		end

		if token ~= phaseToken or raceState ~= "Grace" then
			return
		end

		if hasEnoughParticipants() then
			beginCountdown()
		else
			voidRace("Grace period ended below required players")
		end
	end)
end

local function canJoin(player: Player): boolean
	if raceState ~= "Open" and raceState ~= "Grace" then
		return false
	end
	if participants[player] then
		return false
	end
	if getParticipantCount() >= MAX_PLAYERS then
		return false
	end
	if player:GetAttribute("Current_World") ~= "World1" then
		return false
	end
	if not ValidationService.IsPlayerAlive(player) then
		return false
	end
	if not LevelingService.IsPlayerInsideWorld1Lobby(player) then
		return false
	end

	local now = os.clock()
	local lastRequest = joinRequestLastAt[player] or 0
	if now - lastRequest < 1 then
		return false
	end
	joinRequestLastAt[player] = now
	return true
end

local function joinPlayer(player: Player)
	if not canJoin(player) then
		return
	end

	joinOrder += 1
	local participant: ParticipantState = {
		order = joinOrder,
		finished = false,
		maid = Maid.new(),
	}
	participants[player] = participant
	setPlayerState(player, true, "Queued", nil)
	player:SetAttribute("Treadmill_Active", false)
	bindParticipantCharacter(player, participant)
	if player.Character then
		player.Character:PivotTo(getRaceSpawnCFrame(participant.order))
	end
	updatePlayerCount()

	if raceState == "Open" then
		beginGrace()
	end
end

local function initializePlayer(player: Player)
	if player:GetAttribute("MinigameParticipant") ~= true then
		setPlayerState(player, false, "None", nil)
	end
end

function MinigameService.Init()
	if initialized then
		return
	end
	initialized = true

	raceState = "Open"
	finishCount = 0
	joinOrder = 0
	setBarriers(true)
	setRaceSurfaceGuisVisible(true)
	resetRacePhaseState()
	setWorldAttribute("RaceState", "Open")
	setWorldAttribute("RacePlayerCount", 0)
	setWorldAttribute("RaceRequiredPlayers", REQUIRED_PLAYERS)
	setWorldAttribute("CooldownEndsAt", 0)

	serviceMaid.JoinRequest = joinRequest.OnServerEvent:Connect(function(player: Player)
		joinPlayer(player)
	end)
	serviceMaid.FinishLine = finishLine.Touched:Connect(function(hit: BasePart)
		if raceState ~= "Racing" then
			return
		end

		local player = getPlayerFromRaceTouch(hit)
		local participant = player and participants[player]
		if not player or not participant or participant.finished then
			return
		end

		awardPlacement(player, finishCount + 1)
	end)
	serviceMaid.PlayerAdded = Players.PlayerAdded:Connect(initializePlayer)
	serviceMaid.PlayerRemoving = Players.PlayerRemoving:Connect(function(player: Player)
		joinRequestLastAt[player] = nil
		cancelReturnFreeze(player)
		removeParticipant(player, "PlayerRemoving", false)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayer(player)
	end

	-- Start the first synchronized join window immediately so players see the
	-- real server countdown as soon as the minigame UI appears.
	beginGrace()

	serviceMaid.Cleanup = function()
		cancelPhaseThread()
		stopCountdownSound()
		setBarriers(true)
		setRaceSurfaceGuisVisible(true)
		for player in pairs(returnFreezeStates) do
			cancelReturnFreeze(player)
		end
		for _, player in ipairs(snapshotParticipants()) do
			local participant = participants[player]
			if participant then
				clearParticipant(player, participant, true, "None")
			end
		end
		participants = {}
		joinRequestLastAt = {}
	end

	DebugModule.debugPrint(
		string.format("MinigameService initialized | required=%d | max=%d", REQUIRED_PLAYERS, MAX_PLAYERS),
		MODULE_NAME
	)
end

function MinigameService.Destroy()
	if not initialized then
		return
	end

	initialized = false
	serviceMaid:DoCleaning()
	raceState = "Open"
	finishCount = 0
	joinOrder = 0
	resetRacePhaseState()
	setWorldAttribute("CooldownEndsAt", 0)
	clearFinishedPlayerStates()
	setBarriers(true)
	setRaceState("Open")
end

function MinigameService.IsRaceRunning(): boolean
	return raceState == "Racing"
end

return MinigameService
