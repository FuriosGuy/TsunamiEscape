--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))
local Maid = require(ReplicatedStorage.Modules.Maid)
local SoundService = require(ReplicatedStorage.Modules.SoundService)

type EventDisplayData = {
	id: string,
	displayText: string,
	displayColor: string,
	showCountdown: boolean,
	environmentName: string,
	endsAtUnix: number,
	startsAtUnix: number,
}

local LiveEventBannerUI = {}
LiveEventBannerUI.__index = LiveEventBannerUI

type LiveEventBannerUIObject = {
	container: Frame?,
	template: Frame?,
	stateFolder: Folder?,
	cards: { [string]: Frame },
	cardEventData: { [string]: EventDisplayData },
	cardEndsAt: { [string]: number },
	cardStartsAt: { [string]: number },
	cardModes: { [string]: "live" | "starting" | "ending" | "upcoming" },
	cardUpcomingPrefixes: { [string]: string },
	cardEnvironmentNames: { [string]: string },
	originalCountdownLabel1TextColor: Color3?,
	originalContainerVisible: boolean?,
	originalTemplateVisible: boolean?,
	maid: any,
	initialized: boolean,
	refreshAccumulator: number,
	bloodmoonSoundArmed: boolean,
}

local MODULE_NAME = "LiveEventBannerUI"
local BLOODMOON_EVENT_ID = "Bloodmoon"
local BLOODMOON_START_TEXT = "THE BLOOD MOON RISES..."
local BLOODMOON_START_COLOR = Color3.fromRGB(255, 0, 0)

local function escapeRichText(value: string): string
	local escaped = string.gsub(value, "&", "&amp;")
	escaped = string.gsub(escaped, "<", "&lt;")
	escaped = string.gsub(escaped, ">", "&gt;")
	return escaped
end

local function formatRemainingTime(
	deadlineUnix: number,
	prefix: string,
	finishedText: string?,
	expiredText: string?
): string
	if deadlineUnix <= 0 then
		return finishedText or prefix .. " 00"
	end

	local remaining = math.max(0, deadlineUnix - DateTime.now().UnixTimestamp)
	if remaining <= 0 then
		return expiredText or prefix .. " 00"
	end
	local seconds = remaining % 60
	if remaining >= 3600 then
		local hours = math.floor(remaining / 3600)
		local minutes = math.floor((remaining % 3600) / 60)
		return string.format("%s %02d:%02d:%02d", prefix, hours, minutes, seconds)
	end
	if remaining >= 60 then
		local minutes = math.floor(remaining / 60)
		return string.format("%s %02d:%02d", prefix, minutes, seconds)
	end

	return string.format("%s %02d", prefix, seconds)
end

local function getColoredEventText(eventData: EventDisplayData): string
	local displayText = escapeRichText(string.upper(eventData.displayText))
	if eventData.displayColor == "" then
		return displayText
	end

	return string.format('<font color="%s">%s</font>', eventData.displayColor, displayText)
end

local function getLiveEventLabelText(eventData: EventDisplayData, endsAtUnix: number): string
	local eventText = getColoredEventText(eventData)
	if not eventData.showCountdown then
		return eventText
	end

	return eventText .. " " .. formatRemainingTime(endsAtUnix, "ENDS IN:", "LIVE")
end

local function decodeEventData(value: any): { EventDisplayData }
	if typeof(value) ~= "string" or value == "" then
		return {}
	end

	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, value)
	if not ok or typeof(decoded) ~= "table" then
		return {}
	end

	local events: { EventDisplayData } = {}
	for _, entry in ipairs(decoded :: { any }) do
		if typeof(entry) == "table"
			and typeof(entry.id) == "string"
			and typeof(entry.displayText) == "string"
			and (typeof(entry.endsAtUnix) == "number" or typeof(entry.startsAtUnix) == "number")
		then
			table.insert(events, {
				id = entry.id,
				displayText = entry.displayText,
				displayColor = if typeof(entry.displayColor) == "string" then entry.displayColor else "",
				showCountdown = entry.showCountdown ~= false,
				environmentName = if typeof(entry.environmentName) == "string" then entry.environmentName else "",
				endsAtUnix = if typeof(entry.endsAtUnix) == "number" then entry.endsAtUnix else 0,
				startsAtUnix = if typeof(entry.startsAtUnix) == "number" then entry.startsAtUnix else 0,
			})
		end
	end

	return events
end

local function getCardKey(eventData: EventDisplayData, mode: "live" | "upcoming"): string
	return mode .. "#" .. eventData.id
end

local function isBloodmoonCardKey(key: string): boolean
	return key == "live#" .. BLOODMOON_EVENT_ID
end

local function setCountdownLabel1Color(label: TextLabel, color: Color3?, originalColor: Color3?)
	if color then
		label.TextColor3 = color
	elseif originalColor then
		label.TextColor3 = originalColor
	end
end

local function getTemplateCountdownLabel1Color(template: Frame?): Color3?
	if not template then
		return nil
	end

	local countdownLabel1 = template:FindFirstChild("CountdownLabel1")
	if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
		return countdownLabel1.TextColor3
	end

	return nil
end

local function hasBloodmoonEvent(events: { EventDisplayData }): boolean
	for _, eventData in ipairs(events) do
		if eventData.id == BLOODMOON_EVENT_ID then
			return true
		end
	end

	return false
end

function LiveEventBannerUI.new(screenGui: ScreenGui): LiveEventBannerUIObject
	local containerInstance = screenGui:FindFirstChild("EventFrameList")
	local container = if containerInstance and containerInstance:IsA("Frame") then containerInstance else nil
	local templateInstance = container and container:FindFirstChild("EventFrameTemplate")
	local template = if templateInstance and templateInstance:IsA("Frame") then templateInstance else nil

	return setmetatable({
		container = container,
		template = template,
		stateFolder = nil,
		cards = {},
		cardEventData = {},
		cardEndsAt = {},
		cardStartsAt = {},
		cardModes = {},
		cardUpcomingPrefixes = {},
		cardEnvironmentNames = {},
		originalCountdownLabel1TextColor = getTemplateCountdownLabel1Color(template),
		originalContainerVisible = if container then container.Visible else nil,
		originalTemplateVisible = if template then template.Visible else nil,
		maid = Maid.new(),
		initialized = false,
		refreshAccumulator = 1,
		bloodmoonSoundArmed = false,
	}, LiveEventBannerUI)
end

function LiveEventBannerUI:refreshCountdowns()
	for key, card in pairs(self.cards) do
		local mode = self.cardModes[key]
		if mode == "upcoming" then
			local countdownLabel1 = card:FindFirstChild("CountdownLabel1")
			if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
				setCountdownLabel1Color(countdownLabel1, nil, self.originalCountdownLabel1TextColor)
				countdownLabel1.Text = (self.cardUpcomingPrefixes[key] or "")
					.. " "
					.. formatRemainingTime(
						self.cardStartsAt[key] or 0,
						"LIVE IN:",
						"LIVE IN: 00"
					)
			end
		elseif mode == "starting" or mode == "ending" then
			local countdownLabel1 = card:FindFirstChild("CountdownLabel1")
			if mode == "starting" then
				if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
					setCountdownLabel1Color(
						countdownLabel1,
						if isBloodmoonCardKey(key) then BLOODMOON_START_COLOR else nil,
						self.originalCountdownLabel1TextColor
					)
					countdownLabel1.Text = if isBloodmoonCardKey(key) then BLOODMOON_START_TEXT else "STARTING..."
				end
			elseif countdownLabel1 and countdownLabel1:IsA("TextLabel") then
				setCountdownLabel1Color(countdownLabel1, nil, self.originalCountdownLabel1TextColor)
				countdownLabel1.Text = "ENDING..."
			end
		else
			local eventLabel = card:FindFirstChild("EventLabel")
			local endsAtUnix = self.cardEndsAt[key] or 0
			if endsAtUnix > 0 and endsAtUnix <= DateTime.now().UnixTimestamp then
				self.cardModes[key] = "ending"
				local countdownLabel1 = card:FindFirstChild("CountdownLabel1")
				if eventLabel and eventLabel:IsA("TextLabel") then
					eventLabel.Visible = false
				end
				if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
					countdownLabel1.Visible = true
					countdownLabel1.RichText = false
					setCountdownLabel1Color(countdownLabel1, nil, self.originalCountdownLabel1TextColor)
					countdownLabel1.Text = "ENDING..."
				end
			elseif eventLabel and eventLabel:IsA("TextLabel") then
				local eventData = self.cardEventData[key]
				if eventData then
					eventLabel.Text = getLiveEventLabelText(eventData, endsAtUnix)
				end
			end
		end
	end
end

function LiveEventBannerUI:rebuild()
	if not self.container or not self.template or not self.stateFolder then
		return
	end

	local activeEventData = decodeEventData(self.stateFolder:GetAttribute("ActiveEvents"))
	local upcomingEventData = decodeEventData(self.stateFolder:GetAttribute("UpcomingEvents"))
	local transitionComplete = self.stateFolder:GetAttribute("EnvironmentTransitionComplete") == true
	local bloodmoonActive = hasBloodmoonEvent(activeEventData)
	if not bloodmoonActive then
		self.bloodmoonSoundArmed = false
	elseif transitionComplete and self.bloodmoonSoundArmed then
		self.bloodmoonSoundArmed = false
		SoundService.PlayGuiSound("BloodmoonRise")
	end
	local endingCardCount = 0
	if not transitionComplete then
		for key, _ in pairs(self.cards) do
			if (self.cardModes[key] == "live" or self.cardModes[key] == "ending")
				and (self.cardEnvironmentNames[key] or "") ~= ""
			then
				local stillActive = false
				for _, eventEntry in ipairs(activeEventData) do
					if getCardKey(eventEntry, "live") == key then
						stillActive = true
						break
					end
				end
				if not stillActive then
					endingCardCount += 1
				end
			end
		end
	end
	local totalEventCount = #activeEventData + #upcomingEventData + endingCardCount
	local desiredCards: { [string]: boolean } = {}
	local cardHeightScale = if totalEventCount > 0 then 1 / totalEventCount else 1
	local cardIndex = 0
	for _, eventEntry in ipairs(activeEventData) do
		cardIndex += 1
		local key = getCardKey(eventEntry, "live")
		desiredCards[key] = true
		local card = self.cards[key]
		if not card then
			card = self.template:Clone()
			card.Name = "EventFrame_" .. eventEntry.id
			self.cards[key] = card
		end

		card.LayoutOrder = cardIndex
		card.Size = UDim2.new(1, 0, cardHeightScale, 0)
		card.Visible = true
		local eventLabel = card:FindFirstChild("EventLabel")
		local countdownLabel1 = card:FindFirstChild("CountdownLabel1")
		local isStarting = eventEntry.environmentName ~= "" and not transitionComplete
		if isStarting then
			if eventLabel and eventLabel:IsA("TextLabel") then
				eventLabel.Visible = false
			end
			if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
				countdownLabel1.Visible = true
				countdownLabel1.RichText = false
				setCountdownLabel1Color(
					countdownLabel1,
					if eventEntry.id == BLOODMOON_EVENT_ID then BLOODMOON_START_COLOR else nil,
					self.originalCountdownLabel1TextColor
				)
				countdownLabel1.Text = if eventEntry.id == BLOODMOON_EVENT_ID
					then BLOODMOON_START_TEXT
					else "STARTING..."
			end
			self.cardModes[key] = "starting"
		else
			if eventLabel and eventLabel:IsA("TextLabel") then
				eventLabel.Visible = true
				eventLabel.RichText = true
				eventLabel.Text = getLiveEventLabelText(eventEntry, eventEntry.endsAtUnix)
			end
			if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
				countdownLabel1.Visible = false
			end
			self.cardModes[key] = "live"
		end
		self.cardStartsAt[key] = 0
		self.cardEventData[key] = eventEntry
		self.cardEndsAt[key] = eventEntry.endsAtUnix
		self.cardEnvironmentNames[key] = eventEntry.environmentName
		if eventEntry.endsAtUnix > 0 and eventEntry.endsAtUnix <= DateTime.now().UnixTimestamp then
			if eventLabel and eventLabel:IsA("TextLabel") then
				eventLabel.Visible = false
			end
			if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
				countdownLabel1.Visible = true
				countdownLabel1.RichText = false
				setCountdownLabel1Color(countdownLabel1, nil, self.originalCountdownLabel1TextColor)
				countdownLabel1.Text = "ENDING..."
			end
			self.cardModes[key] = "ending"
		end
		if card.Parent ~= self.container then
			card.Parent = self.container
		end
	end

	for _, eventEntry in ipairs(upcomingEventData) do
		cardIndex += 1
		local key = getCardKey(eventEntry, "upcoming")
		desiredCards[key] = true
		local card = self.cards[key]
		if not card then
			card = self.template:Clone()
			card.Name = "EventFrame_" .. eventEntry.id .. "_Upcoming"
			self.cards[key] = card
		end

		card.LayoutOrder = cardIndex
		card.Size = UDim2.new(1, 0, cardHeightScale, 0)
		card.Visible = true
		local eventLabel = card:FindFirstChild("EventLabel")
		local countdownLabel1 = card:FindFirstChild("CountdownLabel1")
		if eventLabel and eventLabel:IsA("TextLabel") then
			eventLabel.Visible = false
		end
		if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
			countdownLabel1.Visible = true
			countdownLabel1.RichText = true
			setCountdownLabel1Color(countdownLabel1, nil, self.originalCountdownLabel1TextColor)
		end
		self.cardModes[key] = "upcoming"
		self.cardEventData[key] = eventEntry
		self.cardEndsAt[key] = 0
		self.cardStartsAt[key] = eventEntry.startsAtUnix
		self.cardUpcomingPrefixes[key] = getColoredEventText(eventEntry)
		self.cardEnvironmentNames[key] = ""
		if card.Parent ~= self.container then
			card.Parent = self.container
		end
	end

	if not transitionComplete then
		for key, card in pairs(self.cards) do
			if not desiredCards[key]
				and (self.cardModes[key] == "live" or self.cardModes[key] == "ending")
				and (self.cardEnvironmentNames[key] or "") ~= ""
			then
				cardIndex += 1
				desiredCards[key] = true
				card.LayoutOrder = cardIndex
				card.Size = UDim2.new(1, 0, cardHeightScale, 0)
				card.Visible = true

				local eventLabel = card:FindFirstChild("EventLabel")
				local countdownLabel1 = card:FindFirstChild("CountdownLabel1")
				if eventLabel and eventLabel:IsA("TextLabel") then
					eventLabel.Visible = false
				end
				if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
					countdownLabel1.Visible = true
					countdownLabel1.RichText = false
					setCountdownLabel1Color(countdownLabel1, nil, self.originalCountdownLabel1TextColor)
					countdownLabel1.Text = "ENDING..."
				end
				self.cardModes[key] = "ending"
			end
		end
	end

	for key, card in pairs(self.cards) do
		if not desiredCards[key] then
			card:Destroy()
			self.cards[key] = nil
			self.cardEventData[key] = nil
			self.cardEndsAt[key] = nil
			self.cardStartsAt[key] = nil
			self.cardModes[key] = nil
			self.cardUpcomingPrefixes[key] = nil
			self.cardEnvironmentNames[key] = nil
		end
	end

	self.container.Visible = totalEventCount > 0
	self.template.Visible = false
	self:refreshCountdowns()
end

function LiveEventBannerUI:refresh()
	if not self.stateFolder then
		return
	end
	self:rebuild()
end

function LiveEventBannerUI:Init()
	if self.initialized then
		return
	end
	self.initialized = true

	if not self.container or not self.template then
		DebugModule.debugWarn("EventFrameList or EventFrameTemplate is missing", MODULE_NAME)
		return
	end
	if not self.template:FindFirstChild("CountdownLabel1") then
		DebugModule.debugWarn("EventFrameTemplate.CountdownLabel1 is missing", MODULE_NAME)
	end
	self.template.Visible = false
	self.container.Visible = false

	self.maid.Timer = RunService.Heartbeat:Connect(function(deltaTime: number)
		if not self.initialized then
			return
		end
		self.refreshAccumulator += deltaTime
		if self.refreshAccumulator >= 1 then
			self.refreshAccumulator = 0
			self:refreshCountdowns()
		end
	end)

	local stateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
	if not stateFolder or not stateFolder:IsA("Folder") then
		self.maid.StateAdded = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
			if child.Name == "LiveEventState" and child:IsA("Folder") then
				self.stateFolder = child
				self.maid.StateAdded = nil
				self.maid.ActiveEvents = child:GetAttributeChangedSignal("ActiveEvents"):Connect(function()
					self:refresh()
				end)
				self.maid.UpcomingEvents = child:GetAttributeChangedSignal("UpcomingEvents"):Connect(function()
					self:refresh()
				end)
				self.maid.EnvironmentTransition = child:GetAttributeChangedSignal("EnvironmentTransitionComplete"):Connect(function()
					if child:GetAttribute("EnvironmentTransitionComplete") ~= true then
						self.bloodmoonSoundArmed = true
					end
					self:refresh()
				end)
				self:refresh()
			end
		end)
		return
	end

	self.stateFolder = stateFolder
	self.maid.ActiveEvents = stateFolder:GetAttributeChangedSignal("ActiveEvents"):Connect(function()
		self:refresh()
	end)
	self.maid.UpcomingEvents = stateFolder:GetAttributeChangedSignal("UpcomingEvents"):Connect(function()
		self:refresh()
	end)
	self.maid.EnvironmentTransition = stateFolder:GetAttributeChangedSignal("EnvironmentTransitionComplete"):Connect(function()
		if stateFolder:GetAttribute("EnvironmentTransitionComplete") ~= true then
			self.bloodmoonSoundArmed = true
		end
		self:refresh()
	end)
	self:refresh()
end

function LiveEventBannerUI:Destroy()
	if not self.initialized then
		return
	end
	self.initialized = false
	self.maid:DoCleaning()
	for key, card in pairs(self.cards) do
		card:Destroy()
		self.cards[key] = nil
		self.cardEventData[key] = nil
		self.cardEndsAt[key] = nil
		self.cardStartsAt[key] = nil
		self.cardModes[key] = nil
		self.cardUpcomingPrefixes[key] = nil
		self.cardEnvironmentNames[key] = nil
	end
	if self.container and self.originalContainerVisible ~= nil then
		self.container.Visible = self.originalContainerVisible
	end
	if self.template and self.originalTemplateVisible ~= nil then
		self.template.Visible = self.originalTemplateVisible
	end
	self.stateFolder = nil
end

return LiveEventBannerUI
