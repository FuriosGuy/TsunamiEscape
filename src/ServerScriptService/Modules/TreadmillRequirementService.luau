--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreConfigShared = require(ReplicatedStorage.Modules.Shared:WaitForChild("CoreConfig_Shared"))
local ShowNotification = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShowNotification") :: RemoteEvent

local TreadmillRequirementService = {}
local FREE_TREADMILL_CLAIMED_ATTRIBUTE = if RunService:IsStudio()
	then "FreeTreadmillStudioClaimed"
	else "FreeTreadmillClaimed"
local treadmillConfig = CoreConfigShared.treadmills
assert(typeof(treadmillConfig) == "table", "CoreConfigShared.treadmills is required")

local rebirthRequiredValue = treadmillConfig.rebirthTreadmillRequiredRebirths
local freeTreadmillSessionSecondsValue = treadmillConfig.freeTreadmillClaimSessionSeconds
local blockedNoticeCooldownValue = treadmillConfig.blockedNoticeCooldownSeconds
assert(
	typeof(rebirthRequiredValue) == "number" and rebirthRequiredValue >= 0,
	"CoreConfigShared.treadmills.rebirthTreadmillRequiredRebirths must be non-negative"
)
assert(
	typeof(freeTreadmillSessionSecondsValue) == "number" and freeTreadmillSessionSecondsValue >= 0,
	"CoreConfigShared.treadmills.freeTreadmillClaimSessionSeconds must be non-negative"
)
assert(
	typeof(blockedNoticeCooldownValue) == "number" and blockedNoticeCooldownValue > 0,
	"CoreConfigShared.treadmills.blockedNoticeCooldownSeconds must be positive"
)

local REBIRTH_REQUIRED = math.floor(rebirthRequiredValue)
local FREE_TREADMILL_SESSION_SECONDS = math.floor(freeTreadmillSessionSecondsValue)
local BLOCKED_NOTICE_COOLDOWN_SECONDS = blockedNoticeCooldownValue
type BlockedNoticeState = {
	state: string,
	lastSentAt: number,
}
local blockedNoticeStates: { [Player]: { [string]: BlockedNoticeState } } = {}

local function readNonNegativeNumberAttribute(player: Player, attributeName: string): number
	local value = player:GetAttribute(attributeName)
	if typeof(value) ~= "number" then
		return 0
	end

	return math.max(0, math.floor(value))
end

function TreadmillRequirementService.Meets(player: Player, treadmillName: string): boolean
	if treadmillName == "RebirthTreadmill" then
		return readNonNegativeNumberAttribute(player, "Rebirths") >= REBIRTH_REQUIRED
	end

	if treadmillName == "2xTreadmill" then
		return player:GetAttribute(FREE_TREADMILL_CLAIMED_ATTRIBUTE) == true
	end

	return true
end

function TreadmillRequirementService.NotifyBlocked(player: Player, treadmillName: string): ()
	local noticeState: string
	local message: string
	if treadmillName == "RebirthTreadmill" then
		local rebirths = readNonNegativeNumberAttribute(player, "Rebirths")
		local remainingRebirths = math.max(0, REBIRTH_REQUIRED - rebirths)
		if remainingRebirths == 0 then
			return
		end

		local rebirthText = if remainingRebirths == 1 then "REBIRTH" else "REBIRTHS"
		if rebirths == 0 then
			message = string.format("REACH %d %s TO USE!", remainingRebirths, rebirthText)
		else
			message = string.format("REACH %d MORE %s TO USE!", remainingRebirths, rebirthText)
		end
		noticeState = "rebirths:" .. tostring(remainingRebirths)
	elseif treadmillName == "2xTreadmill" then
		if player:GetAttribute(FREE_TREADMILL_CLAIMED_ATTRIBUTE) == true then
			return
		end

		local remainingValue = player:GetAttribute("FreeTreadmillClaimRemainingSeconds")
		local remainingSeconds = if typeof(remainingValue) == "number"
			then math.max(0, math.floor(remainingValue))
			else FREE_TREADMILL_SESSION_SECONDS
		if remainingSeconds <= 0 then
			message = "CLAIM YOUR FREE 2X TREADMILL TO USE IT!"
			noticeState = "claim"
		else
			local remainingMinutes = math.max(1, math.ceil(remainingSeconds / 60))
			local minuteText = if remainingMinutes == 1 then "MIN" else "MINS"
			message = string.format(
				"PLAY %d MORE %s TO CLAIM 2X!",
				remainingMinutes,
				minuteText
			)
			noticeState = "session"
		end
	else
		return
	end

	local playerStates = blockedNoticeStates[player]
	if not playerStates then
		playerStates = {}
		blockedNoticeStates[player] = playerStates
	end
	local now = os.clock()
	local previousNotice = playerStates[treadmillName]
	if
		previousNotice
		and previousNotice.state == noticeState
		and now - previousNotice.lastSentAt < BLOCKED_NOTICE_COOLDOWN_SECONDS
	then
		return
	end

	playerStates[treadmillName] = {
		state = noticeState,
		lastSentAt = now,
	}
	if player.Parent then
		ShowNotification:FireClient(player, message, "Red")
	end
end

function TreadmillRequirementService.CleanupPlayer(player: Player): ()
	blockedNoticeStates[player] = nil
end

function TreadmillRequirementService.Cleanup(): ()
	table.clear(blockedNoticeStates)
end

return TreadmillRequirementService
