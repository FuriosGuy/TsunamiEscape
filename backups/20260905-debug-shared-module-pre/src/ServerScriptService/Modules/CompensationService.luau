--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CoreConfig = require(game:GetService("ServerScriptService").Modules.Config:WaitForChild("CoreConfig_Server"))
local DebugModule = require(game:GetService("ServerScriptService").Modules:WaitForChild("DebugModule_Server"))
local ProductServerService = require(script.Parent:WaitForChild("ProductServerService"))
local TemporaryBoostService = require(script.Parent:WaitForChild("TemporaryBoostService"))

local CompensationService = {}

local MODULE_NAME = "CompensationService"
local CLAIMS_ATTRIBUTE = "CompensationClaimedCampaigns"
local SPEED_END_ATTRIBUTE = "TemporarySpeedBoostEndUnix"
local WIN_END_ATTRIBUTE = "TemporaryWinBoostEndUnix"

type CompensationDefinition = {
	enabled: boolean?,
	campaignId: string?,
	startUnix: number?,
	endUnix: number?,
	speedBoostSeconds: number?,
	winBoostSeconds: number?,
}

local claimedThisSession: { [Player]: boolean } = {}

local function getDefinition(): CompensationDefinition
	local configured = CoreConfig.compensation
	return if typeof(configured) == "table" then configured :: CompensationDefinition else {}
end

local function hasClaimedCampaign(claimedCampaigns: any, campaignId: string): boolean
	if typeof(claimedCampaigns) ~= "string" or claimedCampaigns == "" then
		return false
	end

	for storedCampaignId in string.gmatch(claimedCampaigns, "[^|]+") do
		if storedCampaignId == campaignId then
			return true
		end
	end

	return false
end

local function appendCampaign(claimedCampaigns: any, campaignId: string): string
	if typeof(claimedCampaigns) ~= "string" or claimedCampaigns == "" then
		return campaignId
	end
	return claimedCampaigns .. "|" .. campaignId
end

local function getPositiveDuration(value: number?, fallback: number): number
	return if typeof(value) == "number" and value > 0 then math.floor(value) else fallback
end

function CompensationService.Init()
	local definition = getDefinition()
	if definition.enabled ~= true then
		DebugModule.debugInfo("Compensation campaign disabled", MODULE_NAME)
		return
	end

	DebugModule.debugInfo(
		string.format(
			"Compensation campaign ready | id=%s | startUnix=%s | endUnix=%s | speedSeconds=%d | winSeconds=%d",
			tostring(definition.campaignId),
			tostring(definition.startUnix),
			tostring(definition.endUnix),
			getPositiveDuration(definition.speedBoostSeconds, 30 * 60),
			getPositiveDuration(definition.winBoostSeconds, 30 * 60)
		),
		MODULE_NAME
	)
end

function CompensationService.TryGrant(player: Player): boolean
	if player:GetAttribute("Data_Loaded") ~= true or claimedThisSession[player] then
		return false
	end

	local definition = getDefinition()
	local campaignId = definition.campaignId
	local startUnix = definition.startUnix
	local endUnix = definition.endUnix
	local nowUnix = os.time()
	if
		definition.enabled ~= true
		or typeof(campaignId) ~= "string"
		or campaignId == ""
		or typeof(startUnix) ~= "number"
		or typeof(endUnix) ~= "number"
		or nowUnix < startUnix
		or nowUnix >= endUnix
	then
		return false
	end

	local previousClaims = player:GetAttribute(CLAIMS_ATTRIBUTE)
	if hasClaimedCampaign(previousClaims, campaignId) then
		return false
	end

	claimedThisSession[player] = true
	local previousSpeedEnd = player:GetAttribute(SPEED_END_ATTRIBUTE)
	local previousWinEnd = player:GetAttribute(WIN_END_ATTRIBUTE)
	local updatedClaims = appendCampaign(previousClaims, campaignId)
	player:SetAttribute(CLAIMS_ATTRIBUTE, updatedClaims)
	TemporaryBoostService.GrantSpeedBoost(player, getPositiveDuration(definition.speedBoostSeconds, 30 * 60))
	TemporaryBoostService.GrantWinBoost(player, getPositiveDuration(definition.winBoostSeconds, 30 * 60))

	if not ProductServerService.SavePlayerData(player, true) then
		player:SetAttribute(CLAIMS_ATTRIBUTE, previousClaims)
		player:SetAttribute(SPEED_END_ATTRIBUTE, previousSpeedEnd)
		player:SetAttribute(WIN_END_ATTRIBUTE, previousWinEnd)
		claimedThisSession[player] = nil
		DebugModule.debugWarn(
			"Compensation claim rolled back because save failed | player=" .. player.Name .. " | campaign=" .. campaignId,
			MODULE_NAME
		)
		return false
	end

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local showNotification = remotes and remotes:FindFirstChild("ShowNotification")
	if showNotification and showNotification:IsA("RemoteEvent") and player.Parent then
		showNotification:FireClient(player, "COMPENSATION CLAIMED! +30 MIN 2X SPEED AND 2X WINS!", "Green")
	end

	DebugModule.debugInfo(
		"Compensation claimed | player=" .. player.Name .. " | campaign=" .. campaignId,
		MODULE_NAME
	)
	return true
end

function CompensationService.CleanupPlayer(player: Player)
	claimedThisSession[player] = nil
end

return CompensationService
