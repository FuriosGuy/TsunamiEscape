local WinDisplayController = {}
WinDisplayController.__index = WinDisplayController

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)

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
	eventMappingWarningShown: boolean,
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
		eventMappingWarningShown = false,
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

local function parseHexColor(value: unknown): Color3?
	if typeof(value) ~= "string" then
		return nil
	end

	local redHex, greenHex, blueHex = string.match(value, "^#?(%x%x)(%x%x)(%x%x)$")
	if not redHex or not greenHex or not blueHex then
		return nil
	end

	local red = tonumber(redHex, 16)
	local green = tonumber(greenHex, 16)
	local blue = tonumber(blueHex, 16)
	if red == nil or green == nil or blue == nil then
		return nil
	end

	return Color3.fromRGB(red, green, blue)
end

local function getEventVisuals(eventName: string): (Color3?, Color3?, string?)
	local stateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
	if not stateFolder or not stateFolder:IsA("Folder") then
		return nil, nil, nil
	end

	local encodedEvents = stateFolder:GetAttribute("ActiveEvents")
	if typeof(encodedEvents) ~= "string" then
		return nil, nil, nil
	end

	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, encodedEvents)
	if not ok or typeof(decoded) ~= "table" then
		return nil, nil, nil
	end

	for _, eventEntry in ipairs(decoded) do
		if typeof(eventEntry) == "table" and eventEntry.id == eventName then
			local displayColor = parseHexColor(eventEntry.displayColor)
			local progressUi = eventEntry.progressUi
			local gradientColor = if typeof(progressUi) == "table"
				then parseHexColor(progressUi.gradientColor)
				else nil
			local imageAssetId = if typeof(eventEntry.winPopupImageAssetId) == "string"
				and eventEntry.winPopupImageAssetId ~= ""
				then eventEntry.winPopupImageAssetId
				else nil
			return displayColor, gradientColor, imageAssetId
		end
	end

	return nil, nil, nil
end

function WinDisplayController:OnEventWinAwarded(eventName: string, amount: number)
	if amount <= 0 then
		return
	end

	local hud = self.visualFunctions.HUD
	local template = hud.Float_CurrentBloodMoonWinFrame
	local target = hud.EventCurrentWinsTarget
	if not template or not target then
		if not self.eventMappingWarningShown then
			self.eventMappingWarningShown = true
			DebugModule.debugWarn(
				string.format(
					"Event win popup mapping incomplete | event=%s | template=%s | target=%s",
					eventName,
					tostring(template ~= nil),
					tostring(target ~= nil)
				),
				"WinDisplayController"
			)
		end
		return
	end

	local eventColor, gradientColor, imageAssetId = getEventVisuals(eventName)
	self.visualFunctions.CreateFloatingText(template, amount, 1, {
		TargetFrame = target,
		IntegerOnly = true,
		PlayPopSound = false,
		TextColor = eventColor,
		GradientBottomColor = gradientColor,
		ImageColor = eventColor,
		ImageAssetId = imageAssetId,
	})
end

function WinDisplayController:OnWinAwarded(amount: number, source: string?)
	local splitCount = 1
	local absoluteAmount = math.abs(math.floor(amount))
	if amount > 0 then
		self.playRewardCelebration(false)
		if source == "WinButton" or source == "MinigameRace" then
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

function WinDisplayController:GetEventWinAwardedHandler(): (string, number) -> ()
	return function(eventName: string, amount: number)
		self:OnEventWinAwarded(eventName, amount)
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
