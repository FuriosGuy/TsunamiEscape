--!strict

local RunService = game:GetService("RunService")

local FIRST_UNLOCK_UNIX_TIMESTAMP = DateTime.fromUniversalTime(2026, 10, 17, 0, 0, 0).UnixTimestamp
local STUDIO_PART_TWO_BYPASS_ENABLED = true

local function IsDateAvailable(nowUnixTimestamp: number?): boolean
	if RunService:IsStudio() and STUDIO_PART_TWO_BYPASS_ENABLED then
		return true
	end

	local timestamp = nowUnixTimestamp or os.time()
	if timestamp < FIRST_UNLOCK_UNIX_TIMESTAMP then
		return false
	end

	local utcDate = DateTime.fromUnixTimestamp(timestamp):ToUniversalTime()
	return utcDate.Month == 10
end

local function IsAvailable(environmentName: string?, nowUnixTimestamp: number?): boolean
	return environmentName == "Halloween" and IsDateAvailable(nowUnixTimestamp)
end

local function GetNextUnlockUnixTimestamp(nowUnixTimestamp: number?): number?
	if RunService:IsStudio() and STUDIO_PART_TWO_BYPASS_ENABLED then
		return nil
	end

	local timestamp = nowUnixTimestamp or os.time()
	return if timestamp < FIRST_UNLOCK_UNIX_TIMESTAMP then FIRST_UNLOCK_UNIX_TIMESTAMP else nil
end

return table.freeze({
	FirstUnlockUnixTimestamp = FIRST_UNLOCK_UNIX_TIMESTAMP,
	StudioPartTwoBypassEnabled = STUDIO_PART_TWO_BYPASS_ENABLED,
	IsDateAvailable = IsDateAvailable,
	IsAvailable = IsAvailable,
	GetNextUnlockUnixTimestamp = GetNextUnlockUnixTimestamp,
})
