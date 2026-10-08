--!strict

local WinDisplayController = {}
WinDisplayController.__index = WinDisplayController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugModule = require(ReplicatedStorage.Modules.DebugModule_Client)

type ControllerOptions = {
	player: Player,
	visualFunctions: any,
	spawnSessionTask: (callback: () -> ()) -> thread,
	playRewardCelebration: (playHorn: boolean?) -> (),
	playWinSound: () -> (),
	refreshTrailShop: () -> (),
	refreshAffordableTrailBadge: () -> (),
	onTutorialProgressChanged: () -> (),
}

type Controller = {
	player: Player,
	visualFunctions: any,
	spawnSessionTask: (callback: () -> ()) -> thread,
	playRewardCelebration: (playHorn: boolean?) -> (),
	playWinSound: () -> (),
	refreshTrailShop: () -> (),
	refreshAffordableTrailBadge: () -> (),
	onTutorialProgressChanged: () -> (),
	displayedWinCount: number,
	winAnimationSession: number,
	pendingWinCount: number?,
	bloodmoonMappingWarningShown: boolean,
	alive: boolean,
}

local function distributeValue(totalValue: number, count: number): { number }
	local distributed = {}
	local currentSum = 0
	for i = 1, count do
		local nextSum = math.round(totalValue * (i / count))
		table.insert(distributed, nextSum - currentSum)
		currentSum = nextSum
	end

	return distributed
end

function WinDisplayController.new(options: ControllerOptions): Controller
	return setmetatable({
		player = options.player,
		visualFunctions = options.visualFunctions,
		spawnSessionTask = options.spawnSessionTask,
		playRewardCelebration = options.playRewardCelebration,
		playWinSound = options.playWinSound,
		refreshTrailShop = options.refreshTrailShop,
		refreshAffordableTrailBadge = options.refreshAffordableTrailBadge,
		onTutorialProgressChanged = options.onTutorialProgressChanged,
		displayedWinCount = options.player:GetAttribute("WinCount") or 0,
		winAnimationSession = 0,
		pendingWinCount = nil,
		bloodmoonMappingWarningShown = false,
		alive = true,
	}, WinDisplayController) :: Controller
end

function WinDisplayController:SetDisplayedWinCount(value: number)
	self.displayedWinCount = value
	self.visualFunctions.UpdateWinLabel(value)
end

function WinDisplayController:UpdateWinDisplay()
	local currentWins = self.player:GetAttribute("WinCount") or 0
	if self.winAnimationSession > 0 then
		self.pendingWinCount = currentWins
	else
		self:SetDisplayedWinCount(currentWins)
	end

	self.refreshTrailShop()
	self.refreshAffordableTrailBadge()
	self.onTutorialProgressChanged()
end

function WinDisplayController:OnBloodmoonWinAwarded(amount: number)
	if amount <= 0 then
		return
	end

	local hud = self.visualFunctions.HUD
	local template = hud.Float_CurrentBloodMoonWinFrame
	local target = hud.BloodMoonCurrentWinsTarget
	if not template or not target then
		if not self.bloodmoonMappingWarningShown then
			self.bloodmoonMappingWarningShown = true
			DebugModule.debugWarn(
				string.format(
					"Bloodmoon popup mapping incomplete | template=%s | target=%s",
					tostring(template ~= nil),
					tostring(target ~= nil)
				),
				"WinDisplayController"
			)
		end
		return
	end

	self.visualFunctions.CreateFloatingText(template, amount, 1, {
		TargetFrame = target,
		IntegerOnly = true,
		PlayPopSound = false,
	})
end

function WinDisplayController:OnWinAwarded(amount: number, source: string?)
	if source == "BloodmoonWin" then
		self:OnBloodmoonWinAwarded(amount)
		return
	end

	local splitCount = 1
	local absoluteAmount = math.abs(math.floor(amount))
	if amount > 0 then
		self.playRewardCelebration(false)
		if source == "WinButton" then
			self.playWinSound()
		end
	end

	if absoluteAmount >= 10000 then
		splitCount = 5
	elseif absoluteAmount >= 100 then
		splitCount = 3
	end

	local attributeWinCount = self.player:GetAttribute("WinCount")
	local targetWins = if typeof(attributeWinCount) == "number"
		then attributeWinCount
		else self.displayedWinCount + amount
	local startWins = targetWins - amount
	local distributed = distributeValue(amount, splitCount)
	local lifetime = 2

	self.winAnimationSession += 1
	local currentSession = self.winAnimationSession
	self.pendingWinCount = targetWins
	self:SetDisplayedWinCount(startWins)

	self.visualFunctions.CreateFloatingText(self.visualFunctions.HUD.Float_CurrentWinFrame, amount, splitCount, {
		Lifetime = lifetime,
		TargetFrame = self.visualFunctions.HUD.WinCountFrame,
	})

	self.spawnSessionTask(function()
		local runningTotal = startWins
		task.wait(lifetime * 0.6)

		for i, value in ipairs(distributed) do
			if not self.alive or currentSession ~= self.winAnimationSession then
				return
			end

			runningTotal += value
			self:SetDisplayedWinCount(runningTotal)

			if i < #distributed then
				task.wait(0.05)
			end
		end

		if self.alive and currentSession == self.winAnimationSession then
			self.winAnimationSession = 0
			self:SetDisplayedWinCount(self.pendingWinCount or runningTotal)
			self.pendingWinCount = nil
		end
	end)
end

function WinDisplayController:GetUpdateHandler(): () -> ()
	return function()
		self:UpdateWinDisplay()
	end
end

function WinDisplayController:GetWinAwardedHandler(): (number, string?) -> ()
	return function(amount: number, source: string?)
		self:OnWinAwarded(amount, source)
	end
end

function WinDisplayController:Destroy()
	if not self.alive then
		return
	end

	self.alive = false
	self.winAnimationSession += 1
	self.pendingWinCount = nil
end

return WinDisplayController
