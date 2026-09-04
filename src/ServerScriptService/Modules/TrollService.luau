--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Maid = require(Modules:WaitForChild("Maid"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local PlayerHandler = require(Modules:WaitForChild("PlayerHandler"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local TrollService = {}

-- CONFIG
local trollConfig = if CoreConfig.server and CoreConfig.server.trollService then CoreConfig.server.trollService else nil
local TROLL_ACTION_TIMEOUT = if trollConfig and typeof(trollConfig.actionTimeout) == "number"
	then math.max(1, trollConfig.actionTimeout)
	else 60
local TROLL_SLOW_DURATION = if trollConfig and typeof(trollConfig.slowDuration) == "number"
	then math.max(0.1, trollConfig.slowDuration)
	else 10
local TROLL_FREEZE_DURATION = if trollConfig and typeof(trollConfig.freezeDuration) == "number"
	then math.max(0.1, trollConfig.freezeDuration)
	else 10
local DEFAULT_TROLL_SLOW_SPEED = if trollConfig and typeof(trollConfig.defaultSlowSpeed) == "number"
	then math.max(0, trollConfig.defaultSlowSpeed)
	else (if typeof(PlayerHandler.DEFAULT_ATTRIBUTES.Player_Speed) == "number"
		then PlayerHandler.DEFAULT_ATTRIBUTES.Player_Speed
		else 16)
local TROLL_NOTIFICATION_STYLE = if trollConfig and trollConfig.notificationStyle == "QuickFade"
	then "QuickFade"
	else nil
local TROLL_NOTIFICATION_TICK_INTERVAL = if trollConfig
		and typeof(trollConfig.notificationTickInterval) == "number"
	then math.max(0.25, trollConfig.notificationTickInterval)
	else 1
local MODULE_NAME = "TrollService"
local isInitialized = false
local serviceMaid = Maid.new()

-- REMOTES
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TrollActionRequest = Remotes:WaitForChild("TrollActionRequest") :: RemoteEvent
local TriggerJumpscare = Remotes:WaitForChild("TriggerJumpscare") :: RemoteEvent
local ShowNotification = Remotes:WaitForChild("ShowNotification") :: RemoteEvent

-- STATE (Managed per lifetime)
local pendingTrollActions: {
	[Player]: {
		actionName: string,
		targetUserId: number,
		expiresAt: number,
	},
} = {}

local activeTrollEffects: {
	[Player]: {
		slowUntil: number?,
		freezeUntil: number?,
		maid: any, -- Maid to handle thread cleanup
	},
} =
	{}

local function getEffectMaid(player: Player): any
	local state = activeTrollEffects[player]
	if not state then
		state = { maid = Maid.new() }
		activeTrollEffects[player] = state
	end
	return state.maid
end

local function isEffectActive(untilTime: number?): boolean
	return typeof(untilTime) == "number" and untilTime > os.clock()
end

local function showTimedNotification(player: Player, prefix: string, duration: number, themeName: string)
	local startedAt = os.clock()
	local maid = getEffectMaid(player)

	-- Rule #3.10: Clean up previous notification thread
	maid.TimedNotification = nil

	maid.TimedNotification = task.spawn(function()
		while player.Parent do
			local remaining = math.max(0, math.ceil(duration - (os.clock() - startedAt)))
			ShowNotification:FireClient(
				player,
				string.format("%s %ds", prefix, remaining),
				themeName,
				TROLL_NOTIFICATION_STYLE
			)
			if remaining <= 0 then
				break
			end
			task.wait(TROLL_NOTIFICATION_TICK_INTERVAL)
		end
	end)
end

function TrollService.GetEffectiveWalkSpeed(player: Player): number?
	local state = activeTrollEffects[player]
	if not state then
		return nil
	end

	if isEffectActive(state.freezeUntil) then
		return 0
	end

	if isEffectActive(state.slowUntil) then
		return DEFAULT_TROLL_SLOW_SPEED * PlayerHandler.GetLiveEventWalkSpeedMultiplier(player)
	end

	return nil
end

function TrollService.UpdatePlayerSpeed(player: Player)
	local targetSpeed = TrollService.GetEffectiveWalkSpeed(player)
	if targetSpeed == nil then
		-- Restore the event-adjusted speed after a troll effect ends.
		targetSpeed = PlayerHandler.GetEffectiveWalkSpeed(player)
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = targetSpeed
	end
end

function TrollService.HandleTrollPurchase(player: Player, productId: number, isPurchased: boolean)
	if not isPurchased then
		return
	end

	local pendingAction = pendingTrollActions[player]
	pendingTrollActions[player] = nil

	if not pendingAction or os.clock() > pendingAction.expiresAt then
		return
	end

	local targetPlayer = Players:GetPlayerByUserId(pendingAction.targetUserId)
	if not targetPlayer then
		return
	end

	local maid = getEffectMaid(targetPlayer)
	local state = activeTrollEffects[targetPlayer]

	if pendingAction.actionName == "Kill" then
		local character = targetPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			ShowNotification:FireClient(targetPlayer, "YOU WERE KILLED!", "Red", TROLL_NOTIFICATION_STYLE)
			humanoid.Health = 0
		end
	elseif pendingAction.actionName == "Slow" then
		state.slowUntil = os.clock() + TROLL_SLOW_DURATION
		state.freezeUntil = nil
		TrollService.UpdatePlayerSpeed(targetPlayer)
		showTimedNotification(targetPlayer, "SLOWED FOR", TROLL_SLOW_DURATION, "Blue")

		maid.SlowExpire = task.spawn(function()
			task.wait(TROLL_SLOW_DURATION)
			state.slowUntil = nil
			TrollService.UpdatePlayerSpeed(targetPlayer)
		end)
	elseif pendingAction.actionName == "Freeze" then
		state.freezeUntil = os.clock() + TROLL_FREEZE_DURATION
		state.slowUntil = nil
		TrollService.UpdatePlayerSpeed(targetPlayer)
		showTimedNotification(targetPlayer, "FROZEN FOR", TROLL_FREEZE_DURATION, "Red")

		maid.FreezeExpire = task.spawn(function()
			task.wait(TROLL_FREEZE_DURATION)
			state.freezeUntil = nil
			TrollService.UpdatePlayerSpeed(targetPlayer)
		end)
	elseif pendingAction.actionName == "Jumpscare" then
		TriggerJumpscare:FireClient(targetPlayer)
	end
end

function TrollService.OnTrollRequest(player: Player, actionName: string, targetUserId: number)
	-- Rule #3.12: Basic validation and rate limiting could be added here
	if typeof(actionName) ~= "string" or typeof(targetUserId) ~= "number" then
		return
	end

	local validActions = { Kill = true, Slow = true, Freeze = true, Jumpscare = true }
	if not validActions[actionName] then
		return
	end

	local targetPlayer = Players:GetPlayerByUserId(targetUserId)
	if not targetPlayer then
		return
	end

	pendingTrollActions[player] = {
		actionName = actionName,
		targetUserId = targetUserId,
		expiresAt = os.clock() + TROLL_ACTION_TIMEOUT,
	}
end

function TrollService.CleanupPlayer(player: Player)
	pendingTrollActions[player] = nil
	local state = activeTrollEffects[player]
	if state then
		-- Rule #3.10 & #3.21: Explicit cleanup of all effect threads
		state.maid:DoCleaning()
		activeTrollEffects[player] = nil
	end
end

function TrollService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	serviceMaid.TrollActionRequest = TrollActionRequest.OnServerEvent:Connect(TrollService.OnTrollRequest)
	DebugModule.debugInfo("TrollService Initialized", MODULE_NAME)
end

function TrollService.Shutdown()
	for player in pairs(table.clone(pendingTrollActions)) do
		TrollService.CleanupPlayer(player)
	end
	for player in pairs(table.clone(activeTrollEffects)) do
		TrollService.CleanupPlayer(player)
	end
	serviceMaid:DoCleaning()
	isInitialized = false
end

return TrollService
