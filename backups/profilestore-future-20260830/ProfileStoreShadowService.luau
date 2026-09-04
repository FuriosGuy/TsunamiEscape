--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ReplicatedModules = ReplicatedStorage:WaitForChild("Modules")
local ProductService = require(ReplicatedModules:WaitForChild("ProductService"))
local DebugModule = require(ReplicatedModules:WaitForChild("DebugModule"))
local CoreConfig = require(ReplicatedModules:WaitForChild("Config"):WaitForChild("CoreConfig"))
local ProfileStore = require(script.Parent:WaitForChild("ProfileStore"))
local ProductServerService = require(script.Parent:WaitForChild("ProductServerService"))

local ProfileStoreShadowService = {}

local MODULE_NAME = "ProfileStoreShadowService"
local PROFILE_STORE_MODULE_NAME = "ProfileStore"

ProfileStore.SetDebugLogger(
	function(message: string)
		DebugModule.debugPrint(message, PROFILE_STORE_MODULE_NAME)
	end,
	function(message: string)
		DebugModule.debugWarn(message, PROFILE_STORE_MODULE_NAME)
	end
)

local persistenceConfig = CoreConfig.persistence
local ENABLED = persistenceConfig ~= nil and persistenceConfig.profileStoreShadowEnabled == true
local STORE_NAME = if persistenceConfig ~= nil
	and typeof(persistenceConfig.profileStoreShadowStoreName) == "string"
	and persistenceConfig.profileStoreShadowStoreName ~= ""
	then persistenceConfig.profileStoreShadowStoreName
	else "PlayerProfiles_v2"
local USE_MOCK_IN_STUDIO = persistenceConfig ~= nil
	and persistenceConfig.profileStoreShadowUseMockInStudio == true

type ProfileData = { [string]: any }
type SessionConnection = {
	Disconnect: (self: SessionConnection) -> (),
}
type SessionSignal = {
	Connect: (self: SessionSignal, listener: () -> ()) -> SessionConnection,
}
type ShadowProfile = {
	Data: ProfileData,
	IsActive: (self: ShadowProfile) -> boolean,
	AddUserId: (self: ShadowProfile, userId: number) -> (),
	Reconcile: (self: ShadowProfile) -> (),
	Save: (self: ShadowProfile) -> (),
	EndSession: (self: ShadowProfile) -> (),
	OnSessionEnd: SessionSignal,
}

local profileStore: any = nil
local profiles: { [number]: ShadowProfile } = {}
local sessionConnections: { [number]: SessionConnection } = {}
local profileStoreConnections: { [number]: SessionConnection } = {}
local sessionTokens: { [number]: number } = {}
local initialized = false
local shuttingDown = false
local shutdownReady = false
local SHUTDOWN_BARRIER_TIMEOUT_SECONDS = 25

ProfileStore.SetBeforeCloseHandler(function()
	local deadline = os.clock() + SHUTDOWN_BARRIER_TIMEOUT_SECONDS
	while not shutdownReady and os.clock() < deadline do
		task.wait()
	end
	if not shutdownReady then
		DebugModule.debugWarn(
			"ProfileStore shutdown barrier timed out before authoritative cleanup completed",
			MODULE_NAME
		)
	end
end)

local function getToken(userId: number): number
	local nextToken = (sessionTokens[userId] or 0) + 1
	sessionTokens[userId] = nextToken
	return nextToken
end

local function isCurrent(player: Player, token: number): boolean
	return not shuttingDown
		and initialized
		and player.Parent == Players
		and sessionTokens[player.UserId] == token
end

local function disconnectSessionConnection(userId: number)
	local connection = sessionConnections[userId]
	sessionConnections[userId] = nil
	if connection ~= nil then
		local ok, err = pcall(connection.Disconnect, connection)
		if not ok then
			DebugModule.debugWarn(
				"ProfileStore session connection cleanup failed | userId="
					.. tostring(userId)
					.. " | err="
					.. tostring(err),
				MODULE_NAME
			)
		end
	end
end

local function disconnectProfileStoreConnections()
	for index, connection in pairs(profileStoreConnections) do
		local ok, err = pcall(connection.Disconnect, connection)
		if not ok then
			DebugModule.debugWarn(
				"ProfileStore diagnostic connection cleanup failed | index="
					.. tostring(index)
					.. " | err="
					.. tostring(err),
				MODULE_NAME
			)
		end
	end
	table.clear(profileStoreConnections)
end

local function buildProfileTemplate(): ProfileData
	local template: ProfileData = {}
	for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
		template[entry.name] = entry.default
	end
	template.DataRevision = 0
	return template
end

local function copyPlayerDataToProfile(player: Player, profile: ShadowProfile)
	for _, entry in ipairs(ProductService.SAVED_ATTRIBUTES) do
		local value = player:GetAttribute(entry.name)
		profile.Data[entry.name] = if value ~= nil then value else entry.default
	end
	local currentRevision = profile.Data.DataRevision
	profile.Data.DataRevision = if typeof(currentRevision) == "number"
		then math.max(0, math.floor(currentRevision)) + 1
		else 1
end

local function saveShadowSnapshot(player: Player, reason: string): boolean
	local profile = profiles[player.UserId]
	if profile == nil or not profile:IsActive() then
		return false
	end

	copyPlayerDataToProfile(player, profile)
	profile:Save()
	DebugModule.debugPrint(
		"Mirrored authoritative save into ProfileStore shadow | player="
			.. player.Name
			.. " | store="
			.. STORE_NAME
			.. " | reason="
			.. reason,
		MODULE_NAME
	)
	return true
end

local function startSession(player: Player, token: number)
	local profile = profileStore:StartSessionAsync("player_" .. tostring(player.UserId), {
		Cancel = function()
			return not isCurrent(player, token)
		end,
	}) :: ShadowProfile?
	if profile == nil then
		if isCurrent(player, token) then
			DebugModule.debugWarn(
				"ProfileStore shadow session was not acquired; current persistence remains authoritative | player="
					.. player.Name,
				MODULE_NAME
			)
		end
		return
	end

	if not isCurrent(player, token) then
		profile:EndSession()
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile()
	profiles[player.UserId] = profile

	local sessionConnection: SessionConnection
	sessionConnection = profile.OnSessionEnd:Connect(function()
		if profiles[player.UserId] == profile then
			profiles[player.UserId] = nil
		end
		if sessionConnections[player.UserId] == sessionConnection then
			sessionConnections[player.UserId] = nil
		end
		DebugModule.debugWarn(
			"ProfileStore shadow session ended before normal cleanup | player=" .. player.Name,
			MODULE_NAME
		)
	end)
	sessionConnections[player.UserId] = sessionConnection

	-- Initial mirror creates the new-store record without changing the live source.
	saveShadowSnapshot(player, "InitialMirror")
	DebugModule.debugInfo(
		"ProfileStore shadow session started | player="
			.. player.Name
			.. " | store="
			.. STORE_NAME,
		MODULE_NAME
	)
end

function ProfileStoreShadowService.Init()
	if initialized then
		return
	end
	if not ENABLED then
		shutdownReady = true
		DebugModule.debugInfo("ProfileStore shadow disabled by config", MODULE_NAME)
		return
	end

	shuttingDown = false
	shutdownReady = false
	local template = buildProfileTemplate()
	profileStore = ProfileStore.New(STORE_NAME, template)
	if RunService:IsStudio() and USE_MOCK_IN_STUDIO then
		profileStore = profileStore.Mock
	end
	table.insert(
		profileStoreConnections,
		ProfileStore.OnError:Connect(function(message: string, storeName: string, profileKey: string)
			DebugModule.debugWarn(
				"ProfileStore error | store="
					.. storeName
					.. " | key="
					.. profileKey
					.. " | message="
					.. message,
				MODULE_NAME
			)
		end)
	)
	table.insert(
		profileStoreConnections,
		ProfileStore.OnOverwrite:Connect(function(storeName: string, profileKey: string)
			DebugModule.debugWarn(
				"ProfileStore overwrite detected | store=" .. storeName .. " | key=" .. profileKey,
				MODULE_NAME
			)
		end)
	)
	table.insert(
		profileStoreConnections,
		ProfileStore.OnCriticalToggle:Connect(function(isCritical: boolean)
			local message = "ProfileStore critical state changed | active=" .. tostring(isCritical)
			if isCritical then
				DebugModule.debugWarn(message, MODULE_NAME)
			else
				DebugModule.debugInfo(message, MODULE_NAME)
			end
		end)
	)
	ProductServerService.SetSaveObserver(MODULE_NAME, function(player: Player)
		saveShadowSnapshot(player, "AuthoritativeSave")
	end)
	initialized = true
	DebugModule.debugInfo(
		"ProfileStore shadow initialized | store="
			.. STORE_NAME
			.. " | studioMock="
			.. tostring(RunService:IsStudio() and USE_MOCK_IN_STUDIO),
		MODULE_NAME
	)
end

function ProfileStoreShadowService.StartPlayer(player: Player)
	if not initialized or shuttingDown or player.Parent ~= Players then
		return
	end

	local token = getToken(player.UserId)
	task.spawn(function()
		startSession(player, token)
	end)
end

function ProfileStoreShadowService.EndPlayer(player: Player, authoritativeSaveSucceeded: boolean)
	if not initialized then
		return
	end

	local userId = player.UserId
	getToken(userId)
	local profile = profiles[userId]
	profiles[userId] = nil
	disconnectSessionConnection(userId)

	if profile == nil then
		return
	end
	if authoritativeSaveSucceeded and profile:IsActive() then
		copyPlayerDataToProfile(player, profile)
	end
	if profile:IsActive() then
		profile:EndSession()
	end
	DebugModule.debugInfo(
		"ProfileStore shadow session ended | player="
			.. player.Name
			.. " | authoritativeSave="
			.. tostring(authoritativeSaveSucceeded),
		MODULE_NAME
	)
end

function ProfileStoreShadowService.Shutdown()
	if not initialized then
		shutdownReady = true
		return
	end

	shuttingDown = true
	local activePlayers = {}
	for userId in pairs(profiles) do
		table.insert(activePlayers, userId)
	end
	for _, userId in ipairs(activePlayers) do
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			ProfileStoreShadowService.EndPlayer(player, true)
		end
	end
	initialized = false
	profileStore = nil
	disconnectProfileStoreConnections()
	table.clear(sessionTokens)
	shutdownReady = true
	DebugModule.debugInfo("ProfileStore shadow shutdown", MODULE_NAME)
end

return ProfileStoreShadowService
