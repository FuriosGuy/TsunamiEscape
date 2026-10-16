local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local NotificationLayoutController = require(ReplicatedStorage.Modules.UI.MainGUI.NotificationLayoutController)

local DebugModule = require(ReplicatedStorage.Modules:WaitForChild("DebugModule"))
local Maid = require(ReplicatedStorage.Modules.Maid)
local SoundService = require(ReplicatedStorage.Modules.SoundService)

type EventDisplayData = {
	id: string,
	displayText: string,
	displayColor: string,
	startText: string,
	startSound: string,
	showCountdown: boolean,
	environmentName: string,
	effects: {
		xpMultiplier: number,
		winButtonMultiplier: number,
		walkSpeedMultiplier: number,
		luckMultiplier: number,
	},
	endsAtUnix: number,
	startsAtUnix: number,
}

local LiveEventBannerUI = {}
LiveEventBannerUI.__index = LiveEventBannerUI
local localPlayer = Players.LocalPlayer

type LiveEventBannerUIObject = {
	container: GuiObject?,
	template: Frame?,
	stateFolder: Folder?,
	cards: { [string]: Frame },
	cardEventData: { [string]: EventDisplayData },
	cardEndsAt: { [string]: number },
	cardStartsAt: { [string]: number },
	cardModes: { [string]: "live" | "starting" | "ending" | "upcoming" },
	cardUpcomingPrefixes: { [string]: string },
	cardEnvironmentNames: { [string]: string },
	originalContainerSize: UDim2?,
	originalCountdownLabel1TextColor: Color3?,
	originalContainerVisible: boolean?,
	originalTemplateVisible: boolean?,
	maid: any,
	initialized: boolean,
	refreshAccumulator: number,
	eventStartSoundArmed: boolean,
}

local MODULE_NAME = "LiveEventBannerUI"

local function formatMultiplier(multiplier: number): string
	local roundedMultiplier = math.round(multiplier)
	if math.abs(multiplier - roundedMultiplier) < 0.001 then
		return string.format("%dx", roundedMultiplier)
	end
	return string.format("%.2fx", multiplier)
end

local function getEventTooltipDescription(eventData: EventDisplayData): string
	if eventData.id == "HalloweenSeason" then
		return "Halloween is live! Collect candies, open Halloween Lucky Blocks, and visit the Candy Shop."
	end

	local bonusDescriptions: { string } = {}
	local effects = eventData.effects
	if math.abs(effects.xpMultiplier - 1) > 0.001 then
		table.insert(bonusDescriptions, formatMultiplier(effects.xpMultiplier) .. " XP Speed")
	end
	if math.abs(effects.winButtonMultiplier - 1) > 0.001 then
		table.insert(bonusDescriptions, formatMultiplier(effects.winButtonMultiplier) .. " Wins")
	end
	if math.abs(effects.luckMultiplier - 1) > 0.001 then
		table.insert(bonusDescriptions, formatMultiplier(effects.luckMultiplier) .. " Lucky Block Luck")
	end

	local description = ""
	if #bonusDescriptions > 0 then
		description = "Race through it with " .. table.concat(bonusDescriptions, " and ") .. "!"
	end

	if effects.walkSpeedMultiplier < 0.999 then
		local movementDescription = string.format(
			"but move %d%% slower",
			math.round((1 - effects.walkSpeedMultiplier) * 100)
		)
		description = if description == ""
			then "Race carefully: " .. movementDescription .. "!"
			else string.gsub(description, "!$", function()
				return ", " .. movementDescription .. "!"
			end)
	elseif effects.walkSpeedMultiplier > 1.001 then
		local movementDescription = string.format(
			"move %d%% faster",
			math.round((effects.walkSpeedMultiplier - 1) * 100)
		)
		description = if description == ""
			then "Race fast: " .. movementDescription .. "!"
			else string.gsub(description, "!$", function()
				return " and " .. movementDescription .. "!"
			end)
	end
	if eventData.environmentName ~= "" then
		description = if description == ""
			then "Race to earn event Wins for cool event rewards!"
			else string.gsub(description, "!$", " and earn event Wins too!")
	end
	if description == "" then
		return "Race in this limited-time event and grab the rewards!"
	end

	return description
end

local function setEventLabelInteraction(eventLabel: TextLabel?, isLive: boolean)
	if not eventLabel then
		return
	end

	eventLabel.Active = isLive
	eventLabel.Interactable = isLive
	eventLabel:SetAttribute("EventTooltipEnabled", isLive)
	eventLabel:SetAttribute("UiDisabled", not isLive)
end

local function escapeRichText(value: string): string
	local escaped = string.gsub(value, "&", "&amp;")
	escaped = string.gsub(escaped, "<", "&lt;")
	escaped = string.gsub(escaped, ">", "&gt;")
	return escaped
end

local function parseHexColor(value: string): Color3?
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

local function getEventStartText(eventData: EventDisplayData): string
	if eventData.startText ~= "" then
		return eventData.startText
	end
	return string.upper(eventData.displayText) .. " STARTS..."
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
		if
			typeof(entry) == "table"
			and typeof(entry.id) == "string"
			and typeof(entry.displayText) == "string"
			and (typeof(entry.endsAtUnix) == "number" or typeof(entry.startsAtUnix) == "number")
		then
			local rawEffects = if typeof(entry.effects) == "table" then entry.effects else {}
			table.insert(events, {
				id = entry.id,
				displayText = entry.displayText,
				displayColor = if typeof(entry.displayColor) == "string" then entry.displayColor else "",
				startText = if typeof(entry.startText) == "string" then entry.startText else "",
				startSound = if typeof(entry.startSound) == "string" then entry.startSound else "",
				showCountdown = entry.showCountdown ~= false,
				environmentName = if typeof(entry.environmentName) == "string" then entry.environmentName else "",
				effects = {
					xpMultiplier = if typeof(rawEffects.xpMultiplier) == "number" then rawEffects.xpMultiplier else 1,
					winButtonMultiplier = if typeof(rawEffects.winButtonMultiplier) == "number"
						then rawEffects.winButtonMultiplier
						else 1,
					walkSpeedMultiplier = if typeof(rawEffects.walkSpeedMultiplier) == "number"
						then rawEffects.walkSpeedMultiplier
						else 1,
					luckMultiplier = if typeof(rawEffects.luckMultiplier) == "number"
						then rawEffects.luckMultiplier
						else 1,
				},
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

local function getStartSoundEvent(events: { EventDisplayData }): EventDisplayData?
	for _, eventData in ipairs(events) do
		if eventData.startSound ~= "" then
			return eventData
		end
	end

	return nil
end

function LiveEventBannerUI.new(screenGui: ScreenGui): LiveEventBannerUIObject
	local containerInstance = screenGui:FindFirstChild("EventFrameList", true)
	local container = if containerInstance and containerInstance:IsA("GuiObject") then containerInstance else nil
	local templateInstance = container and container:FindFirstChild("EventFrameTemplate", true)
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
		originalContainerSize = if container then container.Size else nil,
		originalCountdownLabel1TextColor = getTemplateCountdownLabel1Color(template),
		originalContainerVisible = if container then container.Visible else nil,
		originalTemplateVisible = if template then template.Visible else nil,
		maid = Maid.new(),
		initialized = false,
		refreshAccumulator = 1,
		eventStartSoundArmed = false,
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
					.. formatRemainingTime(self.cardStartsAt[key] or 0, "LIVE IN:", "LIVE IN: 00")
			end
		elseif mode == "starting" or mode == "ending" then
			local countdownLabel1 = card:FindFirstChild("CountdownLabel1")
			if mode == "starting" then
				local eventData = self.cardEventData[key]
				if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
					setCountdownLabel1Color(
						countdownLabel1,
						if eventData then parseHexColor(eventData.displayColor) else nil,
						self.originalCountdownLabel1TextColor
					)
					countdownLabel1.Text = if eventData then getEventStartText(eventData) else "STARTING..."
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
	if self.stateFolder:GetAttribute("EnvironmentName") == "Halloween" then
		table.insert(activeEventData, {
			id = "HalloweenSeason",
			displayText = "HALLOWEEN!",
			displayColor = "#FF7A00",
			startText = "",
			startSound = "",
			showCountdown = false,
			environmentName = "",
			effects = {
				xpMultiplier = 1,
				winButtonMultiplier = 1,
				walkSpeedMultiplier = 1,
				luckMultiplier = 1,
			},
			endsAtUnix = 0,
			startsAtUnix = 0,
		})
	end
	local transitionComplete = self.stateFolder:GetAttribute("EnvironmentTransitionComplete") == true
	local startSoundEvent = getStartSoundEvent(activeEventData)
	local isEventEnvironmentEnabled = localPlayer == nil
		or localPlayer:GetAttribute("EventEnvironmentEnabled") ~= false
	if not startSoundEvent then
		self.eventStartSoundArmed = false
	elseif not isEventEnvironmentEnabled then
		self.eventStartSoundArmed = false
	elseif transitionComplete and self.eventStartSoundArmed then
		self.eventStartSoundArmed = false
		SoundService.PlayGuiSound(startSoundEvent.startSound)
	end
	local endingCardCount = 0
	if not transitionComplete then
		for key, _ in pairs(self.cards) do
			if
				(self.cardModes[key] == "live" or self.cardModes[key] == "ending")
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
	local visibleEventCount = math.max(1, totalEventCount)
	local desiredCards: { [string]: boolean } = {}
	local cardHeightScale = 1 / visibleEventCount
	local originalContainerSize = self.originalContainerSize
	if originalContainerSize then
		self.container.Size = UDim2.new(
			originalContainerSize.X.Scale,
			originalContainerSize.X.Offset,
			originalContainerSize.Y.Scale * visibleEventCount,
			originalContainerSize.Y.Offset * visibleEventCount
		)
	end
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
		card:SetAttribute("EventId", eventEntry.id)
		local halloweenPartTwoActive = self.stateFolder:GetAttribute("HalloweenPartTwoActive") == true
		card:SetAttribute(
			"EventTooltipDescription",
			if eventEntry.id == "HalloweenSeason" and not halloweenPartTwoActive
				then nil
				else getEventTooltipDescription(eventEntry)
		)
		if isStarting then
			if eventLabel and eventLabel:IsA("TextLabel") then
				setEventLabelInteraction(eventLabel, false)
				eventLabel.Visible = false
			end
			if countdownLabel1 and countdownLabel1:IsA("TextLabel") then
				countdownLabel1.Visible = true
				countdownLabel1.RichText = false
				setCountdownLabel1Color(
					countdownLabel1,
					parseHexColor(eventEntry.displayColor),
					self.originalCountdownLabel1TextColor
				)
				countdownLabel1.Text = getEventStartText(eventEntry)
			end
			self.cardModes[key] = "starting"
		else
			if eventLabel and eventLabel:IsA("TextLabel") then
				setEventLabelInteraction(
					eventLabel,
					eventEntry.id ~= "HalloweenSeason" or halloweenPartTwoActive
				)
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
				setEventLabelInteraction(eventLabel, false)
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
		card:SetAttribute("EventId", eventEntry.id)
		card:SetAttribute("EventTooltipDescription", getEventTooltipDescription(eventEntry))
		if eventLabel and eventLabel:IsA("TextLabel") then
			setEventLabelInteraction(eventLabel, false)
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
			if
				not desiredCards[key]
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
					setEventLabelInteraction(eventLabel, false)
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

	self.container.Visible = totalEventCount > 0 and isEventEnvironmentEnabled
	self.template.Visible = false
	local templateEventLabel = self.template:FindFirstChild("EventLabel")
	if templateEventLabel and templateEventLabel:IsA("TextLabel") then
		setEventLabelInteraction(templateEventLabel, false)
	end
	self:refreshCountdowns()
	DebugModule.debugInfo(
		string.format(
			"Event layout refresh | active=%d | upcoming=%d | visible=%s | class=%s | bottom=%.3f",
			#activeEventData,
			#upcomingEventData,
			tostring(self.container.Visible),
			self.container.ClassName,
			(self.container.AbsolutePosition.Y + self.container.AbsoluteSize.Y)
				/ math.max(1, Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.Y or 1)
		),
		MODULE_NAME
	)
	NotificationLayoutController.Refresh()
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
	if localPlayer then
		self.maid.EventEnvironmentEnabled = localPlayer:GetAttributeChangedSignal("EventEnvironmentEnabled"):Connect(function()
			if localPlayer:GetAttribute("EventEnvironmentEnabled") == false then
				local activeEvents = decodeEventData(
					if self.stateFolder then self.stateFolder:GetAttribute("ActiveEvents") else nil
				)
				for _, eventData in ipairs(activeEvents) do
					if eventData.startSound ~= "" then
						SoundService.StopGuiSound(eventData.startSound)
					end
				end
				self.eventStartSoundArmed = false
			end
			self:refresh()
		end)
	end

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
				self.maid.EnvironmentName = child:GetAttributeChangedSignal("EnvironmentName"):Connect(function()
					self:refresh()
				end)
				self.maid.HalloweenPartTwo = child:GetAttributeChangedSignal("HalloweenPartTwoActive"):Connect(function()
					self:refresh()
				end)
				self.maid.EnvironmentTransition = child
					:GetAttributeChangedSignal("EnvironmentTransitionComplete")
					:Connect(function()
						if child:GetAttribute("EnvironmentTransitionComplete") ~= true then
					self.eventStartSoundArmed = true
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
	self.maid.EnvironmentName = stateFolder:GetAttributeChangedSignal("EnvironmentName"):Connect(function()
		self:refresh()
	end)
	self.maid.HalloweenPartTwo = stateFolder:GetAttributeChangedSignal("HalloweenPartTwoActive"):Connect(function()
		self:refresh()
	end)
	self.maid.EnvironmentTransition = stateFolder
		:GetAttributeChangedSignal("EnvironmentTransitionComplete")
		:Connect(function()
			if stateFolder:GetAttribute("EnvironmentTransitionComplete") ~= true then
				self.eventStartSoundArmed = true
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
	if self.container and self.originalContainerSize then
		self.container.Size = self.originalContainerSize
	end
	if self.template and self.originalTemplateVisible ~= nil then
		self.template.Visible = self.originalTemplateVisible
	end
	self.stateFolder = nil
end

return LiveEventBannerUI
