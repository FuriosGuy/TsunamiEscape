--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerAttributeBindings = {}

type Callback = () -> ()

type MaidLike = {
	GiveTask: (self: MaidLike, task: any) -> any,
}

type Options = {
	player: Player,
	sessionMaid: MaidLike,
	onAllXPSpeedChanged: Callback,
	onCurrentXPSpeedChanged: Callback,
	onMaxXPSpeedChanged: Callback,
	onCurrentLevelChanged: Callback,
	onMaxPlayerSpeedChanged: Callback,
	onOwnedTrailsChanged: Callback,
	onOwnedKartsChanged: Callback,
	onTrailEquippedChanged: Callback,
	onKartEquippedChanged: Callback,
	onWinCountChanged: Callback,
	onDataLoadedChanged: Callback,
	onGamePassOwnershipSyncChanged: Callback,
	onTutorialCompletedChanged: Callback,
	verifyRewardNextClaimAttribute: string,
	verifyRewardClaimCountAttribute: string,
	onVerifyRewardNextClaimChanged: Callback,
	onVerifyRewardClaimCountChanged: Callback,
	onTreadmillActiveChanged: Callback,
	onTreadmillMultiplierChanged: Callback,
	onDisableWavesOnCooldownChanged: Callback,
	onDisableWavesCooldownEndChanged: Callback,
	onHasVIPPassChanged: Callback,
	onStarterPackRewardClaimedChanged: Callback,
	onCurrentWorldChanged: Callback,
	onCurrentStageChanged: Callback,
}

local function bindAttribute(player: Player, sessionMaid: MaidLike, attributeName: string, callback: Callback)
	sessionMaid:GiveTask(player:GetAttributeChangedSignal(attributeName):Connect(callback))
end

function PlayerAttributeBindings.Bind(options: Options)
	local player = options.player
	local sessionMaid = options.sessionMaid

	bindAttribute(player, sessionMaid, "AllXPSpeed", options.onAllXPSpeedChanged)
	bindAttribute(player, sessionMaid, "CurrentXPSpeed", options.onCurrentXPSpeedChanged)
	bindAttribute(player, sessionMaid, "MaxXPSpeed", options.onMaxXPSpeedChanged)
	bindAttribute(player, sessionMaid, "CurrentLevel", options.onCurrentLevelChanged)
	bindAttribute(player, sessionMaid, "Max_Player_Speed", options.onMaxPlayerSpeedChanged)
	bindAttribute(player, sessionMaid, "OwnedTrails", options.onOwnedTrailsChanged)
	bindAttribute(player, sessionMaid, "OwnedKarts", options.onOwnedKartsChanged)
	bindAttribute(player, sessionMaid, "Trail_Equipped", options.onTrailEquippedChanged)
	bindAttribute(player, sessionMaid, "Kart_Equipped", options.onKartEquippedChanged)
	bindAttribute(player, sessionMaid, "WinCount", options.onWinCountChanged)
	bindAttribute(player, sessionMaid, "Data_Loaded", options.onDataLoadedChanged)
	bindAttribute(player, sessionMaid, "GamePassOwnershipSyncComplete", options.onGamePassOwnershipSyncChanged)
	bindAttribute(player, sessionMaid, "TutorialCompleted", options.onTutorialCompletedChanged)
	bindAttribute(player, sessionMaid, options.verifyRewardNextClaimAttribute, options.onVerifyRewardNextClaimChanged)
	bindAttribute(player, sessionMaid, options.verifyRewardClaimCountAttribute, options.onVerifyRewardClaimCountChanged)
	bindAttribute(player, sessionMaid, "Treadmill_Active", options.onTreadmillActiveChanged)
	bindAttribute(player, sessionMaid, "Treadmill_XPMultiplier", options.onTreadmillMultiplierChanged)
	bindAttribute(player, sessionMaid, "DisableWavesOnCooldown", options.onDisableWavesOnCooldownChanged)
	bindAttribute(player, sessionMaid, "DisableWavesCooldownEnd", options.onDisableWavesCooldownEndChanged)
	bindAttribute(player, sessionMaid, "HasVIPPass", options.onHasVIPPassChanged)
	bindAttribute(player, sessionMaid, "StarterPackRewardClaimed", options.onStarterPackRewardClaimedChanged)
	bindAttribute(player, sessionMaid, "Current_World", options.onCurrentWorldChanged)
	bindAttribute(player, sessionMaid, "CurrentStage", options.onCurrentStageChanged)
end

return PlayerAttributeBindings
