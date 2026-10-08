local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxSoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local NotificationLayoutController = require(ReplicatedStorage.Modules.UI.MainGUI.NotificationLayoutController)

local MinigameUI = {}
MinigameUI.__index = MinigameUI

type ProgressFrameVisibilityControllerLike = {
	SetRaceParticipant: (self: ProgressFrameVisibilityControllerLike, isParticipant: boolean) -> (),
}

type MinigameUIObject = {
	screenGui: ScreenGui,
	root: GuiObject?,
	requiredPlayersLabel: TextLabel?,
	requiredPlayersOriginalVisible: boolean?,
	startingLabel: TextLabel?,
	messageLabel: TextLabel?,
	joinFrame: GuiObject?,
	joinButton: TextButton?,
	stageProgressFrame: GuiObject?,
	startingLabelOriginalVisible: boolean?,
	messageLabelOriginalVisible: boolean?,
	startSurfaceGui: SurfaceGui?,
	countdownSurfaceGui: SurfaceGui?,
	countdownSurfaceLabel: TextLabel?,
	startSurfaceGuiOriginalEnabled: boolean?,
	countdownSurfaceGuiOriginalEnabled: boolean?,
	countdownSurfaceLabelOriginalText: string?,
	countdownSound: Sound?,
	preloadThread: thread?,
	countdownSoundPlayed: boolean,
	world: Instance?,
	joinRequest: RemoteEvent?,
	joinResult: RemoteEvent?,
	raceNotification: RemoteEvent?,
	maid: any,
	runtimeMaid: any,
	originalRootVisible: boolean?,
	originalJoinVisible: boolean?,
	countdownThread: thread?,
	messageThread: thread?,
	messageToken: number,
	visibilityController: ProgressFrameVisibilityControllerLike?,
	runtimeBound: boolean,
	joinPending: boolean,
	joinAttemptToken: number,
	lastParticipant: boolean,
	initialized: boolean,
}

local LOCAL_PLAYER = Players.LocalPlayer
local MODULE_NAME = "MinigameUI"
local MINIMUM_RACE_LEVEL = 50
local COUNTDOWN_SOUND_ID = "rbxassetid://100324658979992"
local ACTIVE_STATES: { [string]: boolean } = {
	Open = true,
	Grace = true,
	Starting = true,
	Countdown = true,
	Racing = true,
}

local function isLevelEligible(): boolean
	local currentLevel = LOCAL_PLAYER:GetAttribute("CurrentLevel")
	return typeof(currentLevel) == "number" and currentLevel >= MINIMUM_RACE_LEVEL
end

local function findMinigameWorld(): Instance?
	local worldsFolder = Workspace:FindFirstChild("Worlds")
	return worldsFolder and worldsFolder:FindFirstChild("Minigame")
end

function MinigameUI.new(
	screenGui: ScreenGui,
	visibilityController: ProgressFrameVisibilityControllerLike?
): MinigameUIObject
	local root = screenGui:FindFirstChild("MinigameNotificationFrame")
	local rootFrame = if root and root:IsA("GuiObject") then root else nil
	local requiredPlayers = rootFrame and rootFrame:FindFirstChild("RequiredPlayers")
	local startingLabel = rootFrame and rootFrame:FindFirstChild("StartingLabel")
	local messageLabel = rootFrame and rootFrame:FindFirstChild("TextLabel")
	local joinFrame = rootFrame and rootFrame:FindFirstChild("JoinButtonFrame")
	local joinButton = joinFrame and joinFrame:FindFirstChild("TextButton")
	local stageProgressFrame = screenGui:FindFirstChild("StageProgressFrame")
	local countdownSound = Instance.new("Sound")
	countdownSound.Name = "MinigameCountdownLocal"
	countdownSound.SoundId = COUNTDOWN_SOUND_ID
	countdownSound.Volume = 1
	countdownSound.Looped = false
	countdownSound.Parent = RobloxSoundService

	return setmetatable({
		screenGui = screenGui,
		root = rootFrame,
		requiredPlayersLabel = if requiredPlayers and requiredPlayers:IsA("TextLabel") then requiredPlayers else nil,
		requiredPlayersOriginalVisible = if requiredPlayers and requiredPlayers:IsA("GuiObject")
			then requiredPlayers.Visible
			else nil,
		startingLabel = if startingLabel and startingLabel:IsA("TextLabel") then startingLabel else nil,
		messageLabel = if messageLabel and messageLabel:IsA("TextLabel") then messageLabel else nil,
		joinFrame = if joinFrame and joinFrame:IsA("GuiObject") then joinFrame else nil,
		joinButton = if joinButton and joinButton:IsA("TextButton") then joinButton else nil,
		stageProgressFrame = if stageProgressFrame and stageProgressFrame:IsA("GuiObject")
			then stageProgressFrame
			else nil,
		startingLabelOriginalVisible = if startingLabel and startingLabel:IsA("GuiObject")
			then startingLabel.Visible
			else nil,
		messageLabelOriginalVisible = if messageLabel and messageLabel:IsA("GuiObject")
			then messageLabel.Visible
			else nil,
		startSurfaceGui = nil,
		countdownSurfaceGui = nil,
		countdownSurfaceLabel = nil,
		startSurfaceGuiOriginalEnabled = nil,
		countdownSurfaceGuiOriginalEnabled = nil,
		countdownSurfaceLabelOriginalText = nil,
		countdownSound = countdownSound,
		preloadThread = nil,
		countdownSoundPlayed = false,
		world = nil,
		joinRequest = nil,
		joinResult = nil,
		raceNotification = nil,
		maid = Maid.new(),
		runtimeMaid = Maid.new(),
		originalRootVisible = if rootFrame then rootFrame.Visible else nil,
		originalJoinVisible = if joinFrame and joinFrame:IsA("GuiObject") then joinFrame.Visible else nil,
		countdownThread = nil,
		messageThread = nil,
		messageToken = 0,
		visibilityController = visibilityController,
		runtimeBound = false,
		joinPending = false,
		joinAttemptToken = 0,
		lastParticipant = false,
		initialized = false,
	}, MinigameUI)
end

local function formatSeconds(seconds: number): number
	return math.max(0, math.ceil(seconds))
end

function MinigameUI:cancelCountdown()
	if self.countdownThread then
		task.cancel(self.countdownThread)
		self.countdownThread = nil
	end
end

function MinigameUI:cancelMessage()
	self.messageToken += 1
	if self.messageThread then
		task.cancel(self.messageThread)
		self.messageThread = nil
	end
end

function MinigameUI:bindRaceSurfaceObjects(): boolean
	if not self.world then
		return false
	end

	local cooldownStart = self.world:FindFirstChild("CooldownStart")
	if not cooldownStart then
		return false
	end

	if self.startSurfaceGui and not self.startSurfaceGui:IsDescendantOf(cooldownStart) then
		self.startSurfaceGui = nil
		self.startSurfaceGuiOriginalEnabled = nil
	end
	if self.countdownSurfaceGui and not self.countdownSurfaceGui:IsDescendantOf(cooldownStart) then
		self.countdownSurfaceGui = nil
		self.countdownSurfaceGuiOriginalEnabled = nil
	end
	if self.countdownSurfaceLabel and not self.countdownSurfaceLabel:IsDescendantOf(cooldownStart) then
		self.countdownSurfaceLabel = nil
		self.countdownSurfaceLabelOriginalText = nil
	end

	local startSurfaceGui = cooldownStart:FindFirstChild("SurfaceGui1")
	if not self.startSurfaceGui and startSurfaceGui and startSurfaceGui:IsA("SurfaceGui") then
		self.startSurfaceGui = startSurfaceGui
		self.startSurfaceGuiOriginalEnabled = startSurfaceGui.Enabled
	end

	local countdownSurfaceGui = cooldownStart:FindFirstChild("SurfaceGui2")
	if not self.countdownSurfaceGui and countdownSurfaceGui and countdownSurfaceGui:IsA("SurfaceGui") then
		self.countdownSurfaceGui = countdownSurfaceGui
		self.countdownSurfaceGuiOriginalEnabled = countdownSurfaceGui.Enabled
	end

	local countdownFrame = self.countdownSurfaceGui and self.countdownSurfaceGui:FindFirstChild("Frame")
	local countdownSurfaceLabel = countdownFrame and countdownFrame:FindFirstChild("CountdownLabel")
	if not self.countdownSurfaceLabel and countdownSurfaceLabel and countdownSurfaceLabel:IsA("TextLabel") then
		self.countdownSurfaceLabel = countdownSurfaceLabel
		self.countdownSurfaceLabelOriginalText = countdownSurfaceLabel.Text
	end

	return self.countdownSurfaceLabel ~= nil
end

function MinigameUI:setMessage(message: string, duration: number)
	if not self.messageLabel then
		return
	end

	self:cancelMessage()
	self.messageLabel.Text = message
	local token = self.messageToken
	self.messageThread = task.spawn(function()
		task.wait(duration)
		if token ~= self.messageToken or not self.initialized then
			return
		end
		self.messageThread = nil
		self:refresh()
	end)
	-- Reconcile parent and child visibility after message state becomes active.
	self:refresh(false)
end

function MinigameUI:updateCountdownLoop()
	self:cancelCountdown()
	if not self.world then
		return
	end

	local state = self.world:GetAttribute("RaceState")
	if state ~= "Grace" and state ~= "Countdown" then
		return
	end

	self.countdownThread = task.spawn(function()
		while
			self.initialized
			and self.world
			and (self.world:GetAttribute("RaceState") == "Grace" or self.world:GetAttribute("RaceState") == "Countdown")
		do
			local state = self.world:GetAttribute("RaceState")
			local deadlineAttribute = if state == "Grace"
				then self.world:GetAttribute("GraceEndsAt")
				else self.world:GetAttribute("CountdownEndsAt")
			local deadline = if typeof(deadlineAttribute) == "number" then deadlineAttribute else 0
			local remaining = deadline - Workspace:GetServerTimeNow()

			local startingText: string
			local surfaceText = ""
			if state == "Countdown" then
				local countdownNumber = if remaining > 3
					then 3
					elseif remaining > 2 then 2
					elseif remaining > 1 then 1
					else 0
				startingText = if countdownNumber > 0
					then "STARTING IN " .. tostring(countdownNumber) .. " SECONDS"
					else "START!"
				surfaceText = if countdownNumber > 0 then tostring(countdownNumber) else "START!"
			else
				local seconds = formatSeconds(remaining)
				startingText = if seconds > 0 then "STARTING IN " .. tostring(seconds) .. " SECONDS" else "STARTING!"
			end

			if self.startingLabel then
				self.startingLabel.Text = startingText
			end
			if self.countdownSurfaceLabel then
				self.countdownSurfaceLabel.Text = surfaceText
			end
			task.wait(0.1)
		end
		self.countdownThread = nil
	end)
end

function MinigameUI:refresh(restartCountdown: boolean?, departingPlayer: Player?)
	local root = self.root
	local world = self.world
	if not root then
		if self.visibilityController then
			self.visibilityController:SetRaceParticipant(false)
		end
		return
	end
	if not world or not self.runtimeBound then
		if self.visibilityController then
			self.visibilityController:SetRaceParticipant(false)
		end
		root.Visible = false
		if self.joinFrame then
			self.joinFrame.Visible = false
		end
		NotificationLayoutController.Refresh()
		return
	end
	self:bindRaceSurfaceObjects()

	local stateValue = world:GetAttribute("RaceState")
	local state = if typeof(stateValue) == "string" then stateValue else "Cooldown"
	local inWorld1 = LOCAL_PLAYER:GetAttribute("Current_World") == "World1"
	local participant = LOCAL_PLAYER:GetAttribute("MinigameParticipant") == true
	local raceEligible = isLevelEligible() or participant
	local hasTemporaryMessage = self.messageThread ~= nil
	local requiredPlayersValue = world:GetAttribute("RaceRequiredPlayers")
	local requiredPlayers = if typeof(requiredPlayersValue) == "number"
		then math.max(1, math.floor(requiredPlayersValue))
		else nil
	local serverPlayerCount = #Players:GetPlayers()
	if departingPlayer and departingPlayer.Parent == Players then
		serverPlayerCount = math.max(0, serverPlayerCount - 1)
	end
	local meetsMinimumServerPopulation = requiredPlayers ~= nil and serverPlayerCount >= requiredPlayers
	local surfaceGuisVisible = raceEligible and state ~= "Racing" and meetsMinimumServerPopulation
	if self.startSurfaceGui then
		self.startSurfaceGui.Enabled = surfaceGuisVisible
	end
	if self.countdownSurfaceGui then
		self.countdownSurfaceGui.Enabled = surfaceGuisVisible
	end
	local visible = raceEligible
		and inWorld1
		and meetsMinimumServerPopulation
		and (
			(not participant and (state == "Open" or state == "Grace"))
			or (participant and ACTIVE_STATES[state] == true)
			or hasTemporaryMessage
		)
	root.Visible = visible

	if self.requiredPlayersLabel then
		local playerCountValue = world:GetAttribute("RacePlayerCount")
		local playerCount = if typeof(playerCountValue) == "number"
			then math.max(0, math.floor(playerCountValue))
			else 0
		local raceLabelState = state == "Grace" or state == "Starting" or state == "Countdown" or state == "Racing"
		self.requiredPlayersLabel.Text = if state == "Racing"
			then "RACE TO THE FINISH!"
			else string.format("REQUIRED PLAYERS: %d/%d", playerCount, requiredPlayers or 5)
		self.requiredPlayersLabel.Visible = visible and raceLabelState
	end

	if self.visibilityController then
		self.visibilityController:SetRaceParticipant(participant)
	elseif self.stageProgressFrame then
		self.stageProgressFrame.Visible = not participant
	end
	if self.joinButton then
		local joinable = visible and (state == "Open" or state == "Grace") and not participant and not self.joinPending
		self.joinButton.Active = joinable
		self.joinButton.AutoButtonColor = self.joinButton.Active
		self.joinButton.Text = if self.joinPending
			then "JOINING..."
			elseif participant then "JOINED"
			elseif state == "Racing" then "RACING"
			else "JOIN"
		if self.joinFrame then
			self.joinFrame.Visible = joinable
		end
	end

	local startingLabelVisible = visible and (state == "Grace" or state == "Starting" or state == "Countdown")
	local raceLabelsVisible = visible and state ~= "Racing"
	if self.startingLabel then
		self.startingLabel.Visible = startingLabelVisible
	end
	if self.messageLabel then
		self.messageLabel.Visible = visible
			and (hasTemporaryMessage or (raceLabelsVisible and self.messageLabelOriginalVisible ~= false))
	end

	if self.startingLabel then
		if state == "Starting" then
			self.startingLabel.Text = "STARTING..."
		elseif state ~= "Grace" and state ~= "Countdown" then
			self.startingLabel.Text = ""
		end
	end
	if self.messageLabel and self.messageThread == nil then
		self.messageLabel.Text = if state == "Racing" then "" else "JOIN THE RACE!"
	end

	if state == "Countdown" and not self.countdownSoundPlayed and self.countdownSound then
		self.countdownSound.TimePosition = 0
		self.countdownSound:Play()
		self.countdownSoundPlayed = true
	elseif state ~= "Countdown" then
		if self.countdownSound then
			self.countdownSound:Stop()
		end
		self.countdownSoundPlayed = false
	end

	if restartCountdown ~= false then
		self:updateCountdownLoop()
	end

	NotificationLayoutController.Refresh()
end

function MinigameUI:onRaceNotification(
	eventName: string,
	placement: number?,
	awardedWins: number?,
	awardedLevels: number?,
	message: string?
)
	if eventName == "RaceEnded" and typeof(message) == "string" then
		self:setMessage(message, 4)
	end
end

local function getJoinFailureMessage(reason: string): string
	if reason == "LevelRequired" then
		return "REACH LEVEL 50 TO RACE!"
	end
	if reason == "RaceFull" then
		return "RACE IS FULL!"
	end
	if reason == "RaceClosed" then
		return "RACE IS NOT OPEN!"
	end
	if reason == "WrongWorld" then
		return "RETURN TO WORLD 1 TO JOIN!"
	end
	if reason == "CharacterUnavailable" then
		return "RESPAWN BEFORE JOINING!"
	end
	if reason == "RateLimited" then
		return "PLEASE WAIT A MOMENT!"
	end
	return "COULD NOT JOIN RACE!"
end

function MinigameUI:tryBindRuntime(): boolean
	if
		self.runtimeBound
		and self.world
		and self.world.Parent
		and self.joinRequest
		and self.joinResult
		and self.raceNotification
	then
		return true
	end

	local world = findMinigameWorld()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local joinRequest = remotes and remotes:FindFirstChild("MinigameJoinRequest")
	local joinResult = remotes and remotes:FindFirstChild("MinigameJoinResult")
	local raceNotification = remotes and remotes:FindFirstChild("MinigameRaceNotification")
	if
		not self.root
		or not world
		or not joinRequest
		or not joinRequest:IsA("RemoteEvent")
		or not joinResult
		or not joinResult:IsA("RemoteEvent")
		or not raceNotification
		or not raceNotification:IsA("RemoteEvent")
	then
		self.runtimeBound = false
		self.world = nil
		self.joinRequest = nil
		self.joinResult = nil
		self.raceNotification = nil
		self:refresh(false)
		return false
	end

	self.runtimeMaid:DoCleaning()
	self.runtimeMaid = Maid.new()
	self.maid.RuntimeMaid = self.runtimeMaid
	self.world = world
	self.joinRequest = joinRequest
	self.joinResult = joinResult
	self.raceNotification = raceNotification
	self.runtimeBound = true
	self.joinPending = false
	self:bindRaceSurfaceObjects()

	self.runtimeMaid.JoinButton = if self.joinButton
		then self.joinButton.Activated:Connect(function()
			if not self.joinRequest or not self.joinButton or not self.joinButton.Active or self.joinPending then
				return
			end

			self.joinPending = true
			self.joinAttemptToken += 1
			local token = self.joinAttemptToken
			self:refresh(false)
			self.joinRequest:FireServer()
			local timeoutThread = task.delay(3, function()
				if self.initialized and self.joinPending and token == self.joinAttemptToken then
					self.joinPending = false
					self:setMessage("JOIN REQUEST TIMED OUT!", 3)
					self:refresh(false)
				end
			end)
			self.runtimeMaid.JoinTimeout = function()
				pcall(task.cancel, timeoutThread)
			end
		end)
		else nil
	self.runtimeMaid.JoinResult = joinResult.OnClientEvent:Connect(function(success: boolean, reason: string)
		self.joinPending = false
		self.joinAttemptToken += 1
		self.runtimeMaid.JoinTimeout = nil
		if success ~= true then
			self:setMessage(getJoinFailureMessage(reason), 3)
		end
		self:refresh()
	end)
	self.runtimeMaid.RaceNotification = raceNotification.OnClientEvent:Connect(function(...)
		self:onRaceNotification(...)
	end)
	self.runtimeMaid.RaceState = world:GetAttributeChangedSignal("RaceState"):Connect(function()
		self:refresh()
	end)
	self.runtimeMaid.RacePlayerCount = world:GetAttributeChangedSignal("RacePlayerCount"):Connect(function()
		self:refresh(false)
	end)
	self.runtimeMaid.RaceRequiredPlayers = world:GetAttributeChangedSignal("RaceRequiredPlayers"):Connect(function()
		self:refresh(false)
	end)
	self.runtimeMaid.RaceDeadline = world:GetAttributeChangedSignal("GraceEndsAt"):Connect(function()
		self:updateCountdownLoop()
	end)
	self.runtimeMaid.CountdownDeadline = world:GetAttributeChangedSignal("CountdownEndsAt"):Connect(function()
		self:updateCountdownLoop()
	end)
	self.runtimeMaid.SurfaceDescendantAdded = world.DescendantAdded:Connect(function(descendant: Instance)
		if
			descendant.Name == "CooldownStart"
			or descendant.Name == "SurfaceGui1"
			or descendant.Name == "SurfaceGui2"
			or descendant.Name == "Frame"
			or descendant.Name == "CountdownLabel"
		then
			if self:bindRaceSurfaceObjects() then
				self:refresh(false)
			end
		end
	end)
	self.runtimeMaid.WorldAncestry = world.AncestryChanged:Connect(function(_, parent)
		if parent == nil and self.world == world then
			self.runtimeBound = false
			self.world = nil
			self:cancelCountdown()
			self:refresh(false)
		end
	end)
	self:refresh()
	return true
end

function MinigameUI:bindDiscoveryListeners()
	local worldsFolder = Workspace:FindFirstChild("Worlds")
	if worldsFolder then
		self.maid.MinigameAdded = worldsFolder.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Minigame" then
				self:tryBindRuntime()
			end
		end)
	end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes then
		self.maid.MinigameRemoteAdded = remotes.ChildAdded:Connect(function(child: Instance)
			if
				child.Name == "MinigameJoinRequest"
				or child.Name == "MinigameJoinResult"
				or child.Name == "MinigameRaceNotification"
			then
				self:tryBindRuntime()
			end
		end)
	end
end

function MinigameUI:Init()
	if self.initialized then
		return
	end
	self.initialized = true
	self.lastParticipant = LOCAL_PLAYER:GetAttribute("MinigameParticipant") == true
	self.preloadThread = task.spawn(function()
		local success, errorMessage = pcall(function()
			if self.countdownSound then
				ContentProvider:PreloadAsync({ self.countdownSound })
			end
		end)
		if not success then
			DebugModule.debugWarn("Countdown sound preload failed: " .. tostring(errorMessage), MODULE_NAME)
		end
	end)

	if self.requiredPlayersLabel then
		self.maid.RequiredPlayersVisibility = self.requiredPlayersLabel
			:GetPropertyChangedSignal("Visible")
			:Connect(function()
				if self.initialized then
					self:refresh(false)
				end
			end)
	end
	if self.startingLabel then
		self.maid.StartingLabelVisibility = self.startingLabel:GetPropertyChangedSignal("Visible"):Connect(function()
			if self.initialized then
				self:refresh(false)
			end
		end)
	end
	self.maid.WorldChanged = LOCAL_PLAYER:GetAttributeChangedSignal("Current_World"):Connect(function()
		self:refresh()
	end)
	self.maid.LevelChanged = LOCAL_PLAYER:GetAttributeChangedSignal("CurrentLevel"):Connect(function()
		self:refresh()
	end)
	self.maid.ServerPlayerAdded = Players.PlayerAdded:Connect(function()
		self:refresh(false)
	end)
	self.maid.ServerPlayerRemoving = Players.PlayerRemoving:Connect(function(player: Player)
		self:refresh(false, player)
	end)
	self.maid.ParticipantChanged = LOCAL_PLAYER:GetAttributeChangedSignal("MinigameParticipant"):Connect(function()
		local isParticipant = LOCAL_PLAYER:GetAttribute("MinigameParticipant") == true
		local leftRace = self.lastParticipant and not isParticipant
		self.lastParticipant = isParticipant
		if not isParticipant then
			self:cancelMessage()
		end
		self.joinPending = false
		self:refresh()

		local raceState = self.world and self.world:GetAttribute("RaceState")
		if leftRace and (raceState == "Open" or raceState == "Grace") then
			self:setMessage("JOIN THE RACE!", 3)
		end
	end)
	self.maid.WorkspaceChildAdded = Workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Worlds" then
			self:bindDiscoveryListeners()
			self:tryBindRuntime()
		end
	end)
	self.maid.ReplicatedStorageChildAdded = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Remotes" then
			self:bindDiscoveryListeners()
			self:tryBindRuntime()
		end
	end)
	self:bindDiscoveryListeners()
	if not self:tryBindRuntime() then
		DebugModule.debugInfo("Minigame UI waiting for streamed runtime objects", MODULE_NAME)
	end
end

function MinigameUI:Destroy()
	if not self.initialized then
		return
	end

	self.initialized = false
	self:cancelCountdown()
	self:cancelMessage()
	if self.preloadThread then
		task.cancel(self.preloadThread)
		self.preloadThread = nil
	end
	if self.countdownSound then
		self.countdownSound:Stop()
		self.countdownSound:Destroy()
		self.countdownSound = nil
	end
	self.maid:DoCleaning()
	local raceEligible = isLevelEligible() or LOCAL_PLAYER:GetAttribute("MinigameParticipant") == true
	if self.requiredPlayersLabel and self.requiredPlayersOriginalVisible ~= nil then
		self.requiredPlayersLabel.Visible = if raceEligible then self.requiredPlayersOriginalVisible else false
	end
	if self.startingLabel and self.startingLabelOriginalVisible ~= nil then
		self.startingLabel.Visible = if raceEligible then self.startingLabelOriginalVisible else false
	end
	if self.messageLabel and self.messageLabelOriginalVisible ~= nil then
		self.messageLabel.Visible = if raceEligible then self.messageLabelOriginalVisible else false
	end
	if self.startSurfaceGui and self.startSurfaceGuiOriginalEnabled ~= nil then
		self.startSurfaceGui.Enabled = if raceEligible then self.startSurfaceGuiOriginalEnabled else false
	end
	if self.countdownSurfaceGui and self.countdownSurfaceGuiOriginalEnabled ~= nil then
		self.countdownSurfaceGui.Enabled = if raceEligible then self.countdownSurfaceGuiOriginalEnabled else false
	end
	if self.countdownSurfaceLabel and self.countdownSurfaceLabelOriginalText ~= nil then
		self.countdownSurfaceLabel.Text = self.countdownSurfaceLabelOriginalText
	end
	if self.visibilityController then
		self.visibilityController:SetRaceParticipant(false)
	elseif self.stageProgressFrame then
		self.stageProgressFrame.Visible = true
	end
	if self.root and self.originalRootVisible ~= nil then
		self.root.Visible = if raceEligible then self.originalRootVisible else false
	end
	if self.joinFrame and self.originalJoinVisible ~= nil then
		self.joinFrame.Visible = if raceEligible then self.originalJoinVisible else false
	end
	self.runtimeBound = false
	self.joinPending = false
	self.world = nil
	self.joinRequest = nil
	self.joinResult = nil
	self.raceNotification = nil
end

return MinigameUI
