--!strict
-- Read-only by default. Run in Studio Command Bar with API Services enabled.
-- Close every live server and make sure these players are not connected before applying.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local PLAYER_STORE_NAME = "PlayerStats_v1"
local BACKUP_STORE_NAME = "PlayerStatsManualBackups_v1"
local WIN_LEADERBOARD_NAME = "WinLeaderboard_v1"
local SPEED_LEADERBOARD_NAME = "SpeedLeaderboard_v1"
local LEADERBOARD_SCAN_LIMIT = 10 -- The supplied screenshots show the top six rows.

-- Safety switches. Leave false until the dry-run output is confirmed.
local APPLY_CHANGES = false
local CONFIRM_TEXT = ""
local REQUIRED_CONFIRM_TEXT = "RESET ABNORMAL LEADERBOARD DATA"

-- Names read from the supplied leaderboard screenshots.
-- If a name was changed, use the numeric ID printed by the leaderboard scan below.
local WIN_TARGET_NAMES = {
	"M4rx_2w3",
	"datpc66353",
	"Hammymix",
}

local SPEED_TARGET_NAMES = {
	"roblox_user_83835021",
	"datpc66353",
	"M4rx_2w3",
	"Hammymix",
	"CheeseJai_99",
	"SRPJR1",
}

-- Add IDs here when the scan shows a renamed/deleted account.
local WIN_TARGET_IDS: { number } = {}
local SPEED_TARGET_IDS: { number } = {}

type ChangeSet = { [string]: number }

local playerStore = DataStoreService:GetDataStore(PLAYER_STORE_NAME)
local backupStore = DataStoreService:GetDataStore(BACKUP_STORE_NAME)
local winLeaderboard = DataStoreService:GetOrderedDataStore(WIN_LEADERBOARD_NAME)
local speedLeaderboard = DataStoreService:GetOrderedDataStore(SPEED_LEADERBOARD_NAME)
local usernameCache: { [number]: string } = {}

local function addId(targets: { [number]: boolean }, userId: any)
	if typeof(userId) == "number" and userId > 0 and userId % 1 == 0 then
		targets[userId] = true
	end
end

local function addIds(targets: { [number]: boolean }, ids: { number })
	for _, userId in ipairs(ids) do
		addId(targets, userId)
	end
end

local function resolveName(name: string): number?
	local moderatedIdText = string.match(string.lower(name), "^roblox_user_(%d+)$")
	if moderatedIdText then
		local moderatedUserId = tonumber(moderatedIdText)
		if moderatedUserId then
			print("Resolved moderated username:", name, "->", moderatedUserId)
			return moderatedUserId
		end
	end

	local success, userId = pcall(function()
		return Players:GetUserIdFromNameAsync(name)
	end)
	if not success or typeof(userId) ~= "number" then
		warn("Could not resolve username:", name, userId)
		return nil
	end

	print("Resolved username:", name, "->", userId)
	return userId
end

local function collectTargets(names: { string }, ids: { number }): { [number]: boolean }
	local targets: { [number]: boolean } = {}
	addIds(targets, ids)

	for _, name in ipairs(names) do
		local userId = resolveName(name)
		if userId then
			addId(targets, userId)
		end
	end

	return targets
end

local function getUsername(userId: number): string
	local cachedUsername = usernameCache[userId]
	if cachedUsername then
		return cachedUsername
	end

	local success, username = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolvedUsername = if success and typeof(username) == "string" then username else "<name unavailable>"
	usernameCache[userId] = resolvedUsername
	return resolvedUsername
end

local function scanLeaderboard(storeName: string, store: OrderedDataStore)
	print("========== " .. storeName .. " TOP " .. tostring(LEADERBOARD_SCAN_LIMIT) .. " ==========")

	local success, pagesOrError = pcall(function()
		return store:GetSortedAsync(false, LEADERBOARD_SCAN_LIMIT)
	end)
	if not success then
		warn("Leaderboard scan failed:", storeName, pagesOrError)
		return
	end

	local pages = pagesOrError
	for rank, entry in ipairs(pages:GetCurrentPage()) do
		local userId = tonumber(entry.key)
		local username = if userId then getUsername(userId) else "<invalid user ID>"
		print(string.format("%d | %s | userId=%s | value=%s", rank, username, entry.key, tostring(entry.value)))
	end

	print("========== END " .. storeName .. " ==========")
end

local function sortedIds(targets: { [number]: boolean }): { number }
	local ids = {}
	for userId in pairs(targets) do
		table.insert(ids, userId)
	end
	table.sort(ids)
	return ids
end

local function printTargets(label: string, targets: { [number]: boolean }, changes: ChangeSet)
	print("========== " .. label .. " TARGETS ==========")
	for _, userId in ipairs(sortedIds(targets)) do
		local changeParts = {}
		for attribute, value in pairs(changes) do
			table.insert(changeParts, attribute .. "=" .. tostring(value))
		end
		table.sort(changeParts)
		print(
			string.format("userId=%d | username=%s | %s", userId, getUsername(userId), table.concat(changeParts, ", "))
		)
	end
	if next(targets) == nil then
		print("No targets resolved.")
	end
end

local function makeBackupKey(userId: number): string
	local suffix = string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 8)
	return string.format("b_%d_%d_%s", userId, os.time(), suffix)
end

local function readProfile(userId: number): { [string]: any }?
	local success, dataOrError = pcall(function()
		return playerStore:GetAsync("player_" .. tostring(userId))
	end)
	if not success then
		warn("Profile read failed:", userId, dataOrError)
		return nil
	end
	if typeof(dataOrError) ~= "table" then
		warn("Profile is not a table; refusing cleanup:", userId, typeof(dataOrError))
		return nil
	end
	return dataOrError
end

local function backupProfile(userId: number, data: { [string]: any }, changes: ChangeSet): boolean
	local backupKey = makeBackupKey(userId)
	local success, errorMessage = pcall(function()
		backupStore:SetAsync(backupKey, {
			SourceStore = PLAYER_STORE_NAME,
			SourceKey = "player_" .. tostring(userId),
			UserId = userId,
			CreatedAtUnix = os.time(),
			Reason = "Abnormal leaderboard data cleanup",
			Changes = changes,
			Data = data,
		})
	end)
	if not success then
		warn("Backup failed; profile will not be changed:", userId, errorMessage)
		return false
	end

	print("Backup created:", backupKey, "for userId", userId)
	return true
end

local function updateProfile(userId: number, changes: ChangeSet): boolean
	local data = readProfile(userId)
	if not data then
		return false
	end

	print("========== BEFORE userId=" .. tostring(userId) .. " ==========")
	for attribute, newValue in pairs(changes) do
		print(attribute, "OLD =", tostring(data[attribute]), "NEW =", tostring(newValue))
	end

	if not backupProfile(userId, data, changes) then
		return false
	end

	local key = "player_" .. tostring(userId)
	local success, result = pcall(function()
		return playerStore:UpdateAsync(key, function(currentData)
			if typeof(currentData) ~= "table" then
				return nil
			end

			for attribute, newValue in pairs(changes) do
				currentData[attribute] = newValue
			end
			return currentData
		end)
	end)
	if not success then
		warn("Profile update failed:", userId, result)
		return false
	end

	local verifyData = readProfile(userId)
	if not verifyData then
		warn("Profile changed but verification read failed:", userId)
		return false
	end
	for attribute, expectedValue in pairs(changes) do
		if verifyData[attribute] ~= expectedValue then
			warn("Verification mismatch:", userId, attribute, verifyData[attribute], expectedValue)
			return false
		end
	end

	print("Profile cleanup verified for userId", userId)
	return true
end

local function removeLeaderboardEntry(storeName: string, store: OrderedDataStore, userId: number): boolean
	local success, errorMessage = pcall(function()
		store:RemoveAsync(tostring(userId))
	end)
	if not success then
		warn("Leaderboard removal failed:", storeName, userId, errorMessage)
		return false
	end

	print("Removed leaderboard entry:", storeName, "userId=" .. tostring(userId))
	return true
end

print("========== ABNORMAL DATA CLEANUP ==========")
print("Apply changes:", APPLY_CHANGES)
print("Player store:", PLAYER_STORE_NAME)
print("Backup store:", BACKUP_STORE_NAME)
print("Run only with live servers closed and API Services enabled.")

-- This gives the numeric IDs even when screenshot names were renamed or mistyped.
scanLeaderboard(WIN_LEADERBOARD_NAME, winLeaderboard)
scanLeaderboard(SPEED_LEADERBOARD_NAME, speedLeaderboard)

local winTargets = collectTargets(WIN_TARGET_NAMES, WIN_TARGET_IDS)
local speedTargets = collectTargets(SPEED_TARGET_NAMES, SPEED_TARGET_IDS)
printTargets("WIN COUNT", winTargets, { WinCount = 0 })
printTargets("ALL XP SPEED", speedTargets, { AllXPSpeed = 0 })

if not APPLY_CHANGES then
	print("DRY RUN ONLY. No profiles or leaderboards were changed.")
else
	if CONFIRM_TEXT ~= REQUIRED_CONFIRM_TEXT then
		warn("Apply blocked. Set CONFIRM_TEXT exactly to:", REQUIRED_CONFIRM_TEXT)
	else
		local allTargets: { [number]: ChangeSet } = {}
		for userId in pairs(winTargets) do
			allTargets[userId] = { WinCount = 0 }
		end
		for userId in pairs(speedTargets) do
			local changes = allTargets[userId] or {}
			changes.AllXPSpeed = 0
			allTargets[userId] = changes
		end

		for _, userId in ipairs(sortedIds(allTargets)) do
			local changes = allTargets[userId]
			if updateProfile(userId, changes) then
				if winTargets[userId] then
					removeLeaderboardEntry(WIN_LEADERBOARD_NAME, winLeaderboard, userId)
				end
				if speedTargets[userId] then
					removeLeaderboardEntry(SPEED_LEADERBOARD_NAME, speedLeaderboard, userId)
				end
			end
		end

		print("========== CLEANUP COMPLETE ==========")
	end
end
