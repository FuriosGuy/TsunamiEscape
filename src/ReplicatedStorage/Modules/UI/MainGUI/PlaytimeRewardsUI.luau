local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Maid = require(Modules:WaitForChild("Maid"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local PlayerHandler = require(Modules:WaitForChild("Shared"):WaitForChild("PlayerHandler_Client"))
local UIFolder = Modules:WaitForChild("UI")
local VisualFunctions = require(UIFolder:WaitForChild("VisualFunctions"))
local SharedFolder = Modules:WaitForChild("Shared")
local NumberFormatting = require(SharedFolder:WaitForChild("NumberFormatting"))
local CoreConfig = require(SharedFolder:WaitForChild("CoreConfig_Client"))
local CoreConfigShared = require(SharedFolder:WaitForChild("CoreConfig_Shared"))
local PlaytimeRewardsConfig = require(Modules:WaitForChild("Shared"):WaitForChild("PlaytimeRewardsConfig"))
local ColorConfig = require(Modules:WaitForChild("Config"):WaitForChild("ColorConfig"))

local PlaytimeRewardsUI = {}
PlaytimeRewardsUI.__index = PlaytimeRewardsUI

local MODULE_NAME = "PlaytimeRewardsUI"
local PLAYTIME_ELAPSED_ATTRIBUTE = "PlaytimeRewardElapsed"
local PLAYTIME_CLAIMED_ATTRIBUTE = "PlaytimeRewardsClaimed"
local FREE_TREADMILL_CLAIMED_ATTRIBUTE = if RunService:IsStudio()
	then "FreeTreadmillStudioClaimed"
	else "FreeTreadmillClaimed"
local FREE_TREADMILL_REMAINING_ATTRIBUTE = "FreeTreadmillClaimRemainingSeconds"
local FREE_TREADMILL_CLAIM_ID = "FreeTreadmill"
local COUNTDOWN_UPDATE_INTERVAL = 0.2
local COMPACT_NUMBER_THRESHOLD_LENGTH = 20
local READY_TEXT_STYLE = ColorConfig.UI.PlaytimeRewards.ReadyTextStyle
local treadmillConfig = CoreConfigShared.treadmills
assert(typeof(treadmillConfig) == "table", "CoreConfigShared.treadmills is required")
local freeTreadmillClaimSessionSeconds = treadmillConfig.freeTreadmillClaimSessionSeconds
local studioFreeTreadmillClaimSessionSeconds = treadmillConfig.studioFreeTreadmillClaimSessionSeconds
assert(
	typeof(freeTreadmillClaimSessionSeconds) == "number" and freeTreadmillClaimSessionSeconds >= 0,
	"CoreConfigShared.treadmills.freeTreadmillClaimSessionSeconds must be non-negative"
)
assert(
	typeof(studioFreeTreadmillClaimSessionSeconds) == "number" and studioFreeTreadmillClaimSessionSeconds >= 0,
	"CoreConfigShared.treadmills.studioFreeTreadmillClaimSessionSeconds must be non-negative"
)
local FREE_TREADMILL_SESSION_SECONDS = math.floor(
	if RunService:IsStudio() then studioFreeTreadmillClaimSessionSeconds else freeTreadmillClaimSessionSeconds
)
local playtimeConfig = if CoreConfig.clientDebug and CoreConfig.clientDebug.playtimeRewards
	then CoreConfig.clientDebug.playtimeRewards
	else nil
local DEBUG_SEQUENTIAL_CLAIM_MODE = if playtimeConfig
		and typeof(playtimeConfig.debugSequentialClaimMode) == "boolean"
	then RunService:IsStudio() and playtimeConfig.debugSequentialClaimMode
	else false

type RewardTier = PlaytimeRewardsConfig.RewardTier

type RewardEntry = {
	tier: RewardTier,
	tierIndex: number,
	root: Frame,
	claimButton: TextButton,
	countdownLabel: TextLabel,
	rewardLabel: TextLabel,
	rotateImage: ImageLabel,
	textGradient: UIGradient?,
	iconGradient: UIGradient?,
	iconGradientAnimated: boolean,
	baseBackgroundColor: Color3,
	claimedBackgroundColor: Color3,
	inFlight: boolean,
	isClaimed: boolean,
}

type ControllerOptions = {
	player: Player,
	root: Instance,
	onClaimableCountChanged: ((number) -> ())?,
}

local function formatWithCommasOnly(value: number): string
	return NumberFormatting.FormatWithCommas(value)
end

local function formatCompactNumber(value: number): string
	return NumberFormatting.FormatCompactNumber(value)
end

local function formatNumber(value: number): string
	local formatted = formatWithCommasOnly(value)
	if string.len(formatted) > COMPACT_NUMBER_THRESHOLD_LENGTH then
		return formatCompactNumber(value)
	end

	return formatted
end

local function formatCountdown(remainingSeconds: number): string
	local clamped = math.max(0, math.ceil(remainingSeconds))
	local minutes = math.floor(clamped / 60)
	local seconds = clamped % 60
	return string.format("%02d:%02d", minutes, seconds)
end

local function parseClaimedTiers(value: any): { [string]: boolean }
	local claimed: { [string]: boolean } = {}
	if typeof(value) ~= "string" or value == "" then
		return claimed
	end

	for token in string.gmatch(value, "([^,]+)") do
		if token ~= "" then
			claimed[token] = true
		end
	end

	return claimed
end

local function getNumericAttribute(player: Player, attributeName: string, defaultValue: number): number
	local value = player:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	return defaultValue
end

local function formatRewardText(tier: RewardTier, player: Player): string
	local parts = {}
	for _, reward in ipairs(tier.rewards) do
		if reward.kind == "XPSpeed" then
			local rebirthMultiplier = getNumericAttribute(player, "Rebirth_XPMultiplier", 1)
			local devMultiplier = getNumericAttribute(player, "DevProduct_XPSpeedMultiplier", 1)
			local miscMultiplier = getNumericAttribute(player, "Misc_XPSpeedMultiplier", 1)
			local friendMultiplier = getNumericAttribute(player, "Friend_XPMultiplier", 1)
			local treadmillMultiplier = getNumericAttribute(player, "Treadmill_XPMultiplier", 1)
			local effectiveXP = reward.amount
				* rebirthMultiplier
				* devMultiplier
				* miscMultiplier
				* friendMultiplier
				* treadmillMultiplier
			local amount = formatCompactNumber(effectiveXP)
			table.insert(parts, "+" .. amount .. " XP")
		elseif reward.kind == "Wins" then
			local effectiveWins = PlayerHandler.CalculatePlaytimeWinsAward(player, reward.amount)
			local amount = formatNumber(effectiveWins)
			table.insert(parts, "+" .. amount .. " Wins")
		elseif reward.kind == "Level" then
			local amount = formatNumber(reward.amount)
			local suffix = if reward.amount == 1 then "Level" else "Levels"
			table.insert(parts, "+" .. amount .. " " .. suffix)
		elseif reward.kind == "Rebirth" then
			local amount = formatNumber(reward.amount)
			local suffix = if reward.amount == 1 then "Rebirth" else "Rebirths"
			table.insert(parts, "+" .. amount .. " " .. suffix)
		else
			local amount = formatNumber(reward.amount)
			table.insert(parts, "+" .. amount)
		end
	end

	return table.concat(parts, " ")
end

local function getFirstUnclaimedTierIndex(claimed: { [string]: boolean }): number?
	for index, tier in ipairs(PlaytimeRewardsConfig.TIERS) do
		if claimed[tier.id] ~= true then
			return index
		end
	end
	return nil
end

local function getTierIconImage(tier: RewardTier): string
	local primaryReward = tier.rewards[1]
	if primaryReward and primaryReward.kind then
		return PlaytimeRewardsConfig.GetIconForTier(tier.id, primaryReward.kind)
	end
	return PlaytimeRewardsConfig.PLACEHOLDER_ICON_IMAGE
end

local function getTierClaimedIconImage(tier: RewardTier): string
	local primaryReward = tier.rewards[1]
	if primaryReward and primaryReward.kind then
		return PlaytimeRewardsConfig.GetClaimedIconForTier(tier.id, primaryReward.kind)
	end
	return PlaytimeRewardsConfig.PLACEHOLDER_ICON_IMAGE
end

local function toClaimedBackgroundColor(color: Color3): Color3
	local factor = 0.45
	return Color3.new(color.R * factor, color.G * factor, color.B * factor)
end

local function getExistingClaimButton(root: Frame): TextButton?
	local claimButton = root:FindFirstChild("TextButton")
	if claimButton and claimButton:IsA("TextButton") then
		return claimButton
	end

	local legacyClaimButton = root:FindFirstChild("ClaimButton")
	if legacyClaimButton and legacyClaimButton:IsA("TextButton") then
		return legacyClaimButton
	end

	return nil
end

local function getExistingCountdownLabel(root: Frame): (TextLabel?, UIGradient?)
	local existing = root:FindFirstChild("TimerLabel")
	local label: TextLabel?
	if existing and existing:IsA("TextLabel") then
		label = existing
	else
		local fallbackExisting = root:FindFirstChild("CountdownLabel")
		if fallbackExisting and fallbackExisting:IsA("TextLabel") then
			label = fallbackExisting
		end
	end
	if not label then
		return nil, nil
	end

	local gradient = label:FindFirstChild("TextGradient")
	local textGradient = if gradient and gradient:IsA("UIGradient") then gradient else nil

	return label, textGradient
end

local function getExistingRotateImage(root: Frame): ImageLabel?
	local existing = root:FindFirstChild("RotateImage")
	if existing and existing:IsA("ImageLabel") then
		return existing
	end

	return nil
end

local function getExistingIconGradient(rotateImage: ImageLabel): UIGradient?
	local existingGradient = rotateImage:FindFirstChild("PlaytimeIconGradient")
	if existingGradient and existingGradient:IsA("UIGradient") then
		return existingGradient
	end

	local fallbackGradient = rotateImage:FindFirstChildOfClass("UIGradient")
	if fallbackGradient then
		fallbackGradient.Name = "PlaytimeIconGradient"
		return fallbackGradient
	end

	return nil
end

local function getOrCreateIconGradient(rotateImage: ImageLabel): UIGradient
	local gradient = getExistingIconGradient(rotateImage)
	if gradient then
		return gradient
	end

	local newGradient = Instance.new("UIGradient")
	newGradient.Name = "PlaytimeIconGradient"
	newGradient.Enabled = false
	newGradient.Parent = rotateImage
	return newGradient
end

local function getExistingRewardLabel(root: Frame): TextLabel?
	local existing = root:FindFirstChild("RewardLabel")
	if existing and existing:IsA("TextLabel") then
		return existing
	end

	return nil
end

function PlaytimeRewardsUI.new(options: ControllerOptions)
	local self = setmetatable({}, PlaytimeRewardsUI)

	self.player = options.player
	self.root = options.root
	self.maid = Maid.new()
	self.entryMaid = Maid.new()
	self.entries = {} :: { [string]: RewardEntry }
	self.updateAccumulator = 0
	self.destroyed = false
	self.onClaimableCountChanged = if typeof(options.onClaimableCountChanged) == "function"
		then options.onClaimableCountChanged
		else nil
	self.lastClaimableCount = -1
	self.freeTreadmillButtonFrame = nil
	self.freeTreadmillClaimButton = nil
	self.freeTreadmillCountdownLabel = nil
	self.freeTreadmillClaimLabel = nil
	self.freeTreadmillClaimLabelDefaultText = nil
	self.freeTreadmillClaimPending = false
	self.freeTreadmillClaimPendingUntil = 0

	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local remote = remotes:FindFirstChild("PlaytimeRewardAction")
	self.playtimeRewardAction = if remote and remote:IsA("RemoteEvent") then remote else nil
	if not self.playtimeRewardAction then
		DebugModule.debugWarn("PlaytimeRewardAction remote missing", MODULE_NAME)
	end

	self.maid:GiveTask(function()
		self.entryMaid:DoCleaning()
	end)

	self:Rebuild()
	self:Bind()
	self:BindFreeTreadmillButton()
	self:Refresh()

	return self
end

function PlaytimeRewardsUI:NotifyClaimableCount(claimableCount: number)
	if self.lastClaimableCount == claimableCount then
		return
	end
	self.lastClaimableCount = claimableCount

	local callback = self.onClaimableCountChanged
	if not callback then
		return
	end

	local ok, err = pcall(callback, claimableCount)
	if not ok then
		DebugModule.debugWarn(string.format("onClaimableCountChanged callback failed: %s", tostring(err)), MODULE_NAME)
	end
end

function PlaytimeRewardsUI:GetRewardListAndTemplate(): (GuiObject?, Frame?)
	local rewardsFrame = self.root:FindFirstChild("RewardsFrame", true)
	if not rewardsFrame or not rewardsFrame:IsA("GuiObject") then
		return nil, nil
	end

	local bodyFrame = rewardsFrame:FindFirstChild("BodyFrame")
	if not bodyFrame or not bodyFrame:IsA("GuiObject") then
		return nil, nil
	end

	local list = bodyFrame:FindFirstChild("List")
	if not list or not list:IsA("GuiObject") then
		return nil, nil
	end

	local template = list:FindFirstChild("PlaytimeRewardButton_Template")
	if not template or not template:IsA("Frame") then
		return list, nil
	end

	return list, template
end

function PlaytimeRewardsUI:ClearEntries()
	for _, entry in pairs(self.entries) do
		if entry.root.Parent then
			entry.root:Destroy()
		end
	end
	table.clear(self.entries)
end

function PlaytimeRewardsUI:Rebuild()
	self.entryMaid:DoCleaning()
	self:ClearEntries()

	local list, template = self:GetRewardListAndTemplate()
	if not list or not template then
		return
	end

	template.Visible = false
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") and child:GetAttribute("PlaytimeRewardEntry") == true then
			child:Destroy()
		end
	end

	for index, tier in ipairs(PlaytimeRewardsConfig.TIERS) do
		local entryFrame = template:Clone()
		entryFrame.Name = "PlaytimeRewardButton_" .. tier.id
		entryFrame.LayoutOrder = index
		entryFrame.Visible = true
		-- Opt out of global hover/click visual hooks for this runtime card.
		entryFrame:SetAttribute("isHover", nil)
		entryFrame:SetAttribute("isShine", nil)
		entryFrame:SetAttribute("PlaytimeRewardEntry", true)
		local claimButton = getExistingClaimButton(entryFrame)
		local countdownLabel, textGradient = getExistingCountdownLabel(entryFrame)
		local rotateImage = getExistingRotateImage(entryFrame)
		local iconGradient = if rotateImage then getExistingIconGradient(rotateImage) else nil
		local rewardLabel = getExistingRewardLabel(entryFrame)
		if not claimButton or not countdownLabel or not rotateImage or not rewardLabel then
			DebugModule.debugWarn(
				string.format(
					"Playtime template entry missing required child for %s | button=%s timer=%s icon=%s reward=%s",
					tier.id,
					tostring(claimButton ~= nil),
					tostring(countdownLabel ~= nil),
					tostring(rotateImage ~= nil),
					tostring(rewardLabel ~= nil)
				),
				MODULE_NAME
			)
			entryFrame:Destroy()
			continue
		end
		claimButton.AutoButtonColor = false

		rotateImage.Image = getTierIconImage(tier)
		rewardLabel.Text = formatRewardText(tier, self.player)
		if textGradient then
			textGradient.Enabled = false
		end
		if iconGradient then
			iconGradient.Enabled = false
		end

		entryFrame.Parent = list
		VisualFunctions.SetupFrameHover(entryFrame, 1.1, 15, 1.5)
		VisualFunctions.SetupFrameClick(entryFrame, 0.95, -15, 0.75)

		local entry: RewardEntry = {
			tier = tier,
			tierIndex = index,
			root = entryFrame,
			claimButton = claimButton,
			countdownLabel = countdownLabel,
			rewardLabel = rewardLabel,
			rotateImage = rotateImage,
			textGradient = textGradient,
			iconGradient = iconGradient,
			iconGradientAnimated = false,
			baseBackgroundColor = entryFrame.BackgroundColor3,
			claimedBackgroundColor = toClaimedBackgroundColor(entryFrame.BackgroundColor3),
			inFlight = false,
			isClaimed = false,
		}
		self.entries[tier.id] = entry

		self.entryMaid:GiveTask(claimButton.Activated:Connect(function()
			if entry.isClaimed or entry.inFlight then
				return
			end

			if DEBUG_SEQUENTIAL_CLAIM_MODE then
				local claimedSet = parseClaimedTiers(self.player:GetAttribute(PLAYTIME_CLAIMED_ATTRIBUTE))
				local expectedTierIndex = getFirstUnclaimedTierIndex(claimedSet)
				if not expectedTierIndex or entry.tierIndex ~= expectedTierIndex then
					return
				end
			else
				local elapsed = self.player:GetAttribute(PLAYTIME_ELAPSED_ATTRIBUTE)
				local elapsedSeconds = if typeof(elapsed) == "number" then elapsed else 0
				if elapsedSeconds < tier.unlockSeconds then
					return
				end
			end

			if self.playtimeRewardAction then
				entry.inFlight = true
				self:ApplyClaimingState(entry)
				self.playtimeRewardAction:FireServer("Claim", tier.id)
				self.entryMaid:GiveTask(task.delay(2, function()
					if self.destroyed then
						return
					end
					if not entry.isClaimed then
						entry.inFlight = false
					end
				end))
			end
		end))
	end
end

function PlaytimeRewardsUI:ApplyLockedState(entry: RewardEntry, remainingSeconds: number)
	entry.root.BackgroundColor3 = entry.baseBackgroundColor
	entry.root.Interactable = false
	if DEBUG_SEQUENTIAL_CLAIM_MODE then
		entry.countdownLabel.Text = "LOCKED"
	else
		entry.countdownLabel.Text = formatCountdown(remainingSeconds)
	end
	entry.countdownLabel.TextColor3 = ColorConfig.Colors.White.Color
	if entry.textGradient then
		entry.textGradient.Enabled = false
	end
	entry.rewardLabel.Visible = false
	entry.rotateImage.Image = getTierIconImage(entry.tier)
	entry.rotateImage.Visible = true
	if entry.iconGradient then
		entry.iconGradient.Enabled = false
	end
	entry.iconGradientAnimated = false
	entry.claimButton.Active = false
	entry.claimButton.Interactable = false
	entry.claimButton.Selectable = false
end

function PlaytimeRewardsUI:ApplyReadyState(entry: RewardEntry)
	entry.root.BackgroundColor3 = entry.baseBackgroundColor
	entry.root.Interactable = true
	entry.countdownLabel.Text = "CLAIM"
	entry.countdownLabel.TextColor3 = READY_TEXT_STYLE.TextColor
	if entry.textGradient then
		entry.textGradient.Enabled = true
		entry.textGradient.Rotation = 90
		entry.textGradient.Color = READY_TEXT_STYLE.Gradient
	end
	entry.rewardLabel.Visible = false
	entry.rotateImage.Image = getTierIconImage(entry.tier)
	entry.rotateImage.Visible = true
	if entry.iconGradient then
		entry.iconGradient.Enabled = false
	end
	entry.iconGradientAnimated = false
	entry.claimButton.Active = true
	entry.claimButton.Interactable = true
	entry.claimButton.Selectable = true
end

function PlaytimeRewardsUI:ApplyClaimingState(entry: RewardEntry)
	entry.root.BackgroundColor3 = entry.baseBackgroundColor
	entry.root.Interactable = false
	entry.countdownLabel.Text = "CLAIMING..."
	entry.countdownLabel.TextColor3 = READY_TEXT_STYLE.TextColor
	if entry.textGradient then
		entry.textGradient.Enabled = true
		entry.textGradient.Rotation = 90
		entry.textGradient.Color = READY_TEXT_STYLE.Gradient
	end
	entry.rewardLabel.Visible = false
	entry.rotateImage.Image = getTierIconImage(entry.tier)
	entry.rotateImage.Visible = true
	if entry.iconGradient then
		entry.iconGradient.Enabled = false
	end
	entry.iconGradientAnimated = false
	entry.claimButton.Active = false
	entry.claimButton.Interactable = false
	entry.claimButton.Selectable = false
end

function PlaytimeRewardsUI:ApplyClaimedState(entry: RewardEntry)
	entry.root.BackgroundColor3 = entry.claimedBackgroundColor
	entry.root.Interactable = false
	entry.countdownLabel.Text = "CLAIMED"
	entry.countdownLabel.TextColor3 = ColorConfig.Colors.White.Color
	if entry.textGradient then
		entry.textGradient.Enabled = false
	end
	entry.rewardLabel.Visible = true
	entry.rotateImage.Image = getTierClaimedIconImage(entry.tier)
	entry.rotateImage.Visible = true
	if entry.tier.id == "Gift12" then
		local iconGradient = entry.iconGradient or getOrCreateIconGradient(entry.rotateImage)
		entry.iconGradient = iconGradient
		iconGradient.Enabled = true
		if not entry.iconGradientAnimated then
			VisualFunctions.SetupRotatingGradient(iconGradient)
			entry.iconGradientAnimated = true
		end
	else
		local iconGradient = entry.iconGradient
		if iconGradient then
			iconGradient.Enabled = false
		end
		entry.iconGradientAnimated = false
	end
	entry.claimButton.Active = false
	entry.claimButton.Interactable = false
	entry.claimButton.Selectable = false
	entry.inFlight = false
	entry.isClaimed = true
end

function PlaytimeRewardsUI:BindFreeTreadmillButton()
	local candidate = self.root:FindFirstChild("FreeTreadmillButtonFrame", true)
	local frame = if candidate and candidate:IsA("GuiObject") then candidate else nil
	if not frame then
		return
	end

	if self.freeTreadmillButtonFrame ~= frame then
		self.maid.FreeTreadmillButtonConnection = nil
		self.maid.FreeTreadmillDescendantAdded = nil
		self.freeTreadmillButtonFrame = frame
		self.freeTreadmillClaimButton = nil
		self.freeTreadmillCountdownLabel = nil
		self.freeTreadmillClaimLabel = nil
		self.freeTreadmillClaimLabelDefaultText = nil
		self.freeTreadmillClaimPending = false
		self.freeTreadmillClaimPendingUntil = 0
		self.maid.FreeTreadmillDescendantAdded = frame.DescendantAdded:Connect(function(descendant)
			if
				descendant.Name == "TextButton"
				or descendant.Name == "CountdownLabel"
				or descendant.Name == "ClaimLabel"
			then
				self:BindFreeTreadmillButton()
			end
		end)
	end

	local buttonCandidate = frame:FindFirstChild("TextButton", true)
	local claimButton = if buttonCandidate and buttonCandidate:IsA("GuiButton") then buttonCandidate else nil
	if claimButton ~= self.freeTreadmillClaimButton then
		self.maid.FreeTreadmillButtonConnection = nil
		self.freeTreadmillClaimButton = claimButton
		if claimButton then
			self.maid.FreeTreadmillButtonConnection = claimButton.Activated:Connect(function()
				if
					self.destroyed
					or self.freeTreadmillClaimPending
					or self.player:GetAttribute(FREE_TREADMILL_CLAIMED_ATTRIBUTE) == true
					or self.player:GetAttribute("Data_Loaded") ~= true
				then
					return
				end

				local remaining = self.player:GetAttribute(FREE_TREADMILL_REMAINING_ATTRIBUTE)
				local remainingSeconds = if typeof(remaining) == "number"
					then math.max(0, math.floor(remaining))
					else FREE_TREADMILL_SESSION_SECONDS
				if remainingSeconds > 0 or not self.playtimeRewardAction then
					return
				end

				self.freeTreadmillClaimPending = true
				self.freeTreadmillClaimPendingUntil = os.clock() + 4
				self:RefreshFreeTreadmillButton()
				local fired, fireError = pcall(
					self.playtimeRewardAction.FireServer,
					self.playtimeRewardAction,
					"Claim",
					FREE_TREADMILL_CLAIM_ID
				)
				if not fired then
					self.freeTreadmillClaimPending = false
					self.freeTreadmillClaimPendingUntil = 0
					DebugModule.debugWarn(
						string.format("Free treadmill claim request failed: %s", tostring(fireError)),
						MODULE_NAME
					)
					self:RefreshFreeTreadmillButton()
				end
			end)
		end
	end

	local countdownCandidate = frame:FindFirstChild("CountdownLabel", true)
	self.freeTreadmillCountdownLabel = if countdownCandidate and countdownCandidate:IsA("TextLabel")
		then countdownCandidate
		else nil
	local claimLabelCandidate = frame:FindFirstChild("ClaimLabel", true)
	local claimLabel = if claimLabelCandidate and claimLabelCandidate:IsA("TextLabel")
		then claimLabelCandidate
		else nil
	if claimLabel ~= self.freeTreadmillClaimLabel then
		self.freeTreadmillClaimLabel = claimLabel
		self.freeTreadmillClaimLabelDefaultText = if claimLabel then claimLabel.Text else nil
	end

	self:RefreshFreeTreadmillButton()
end

function PlaytimeRewardsUI:RefreshFreeTreadmillButton()
	local frame = self.freeTreadmillButtonFrame
	if not frame or frame.Parent == nil then
		return
	end

	local claimed = self.player:GetAttribute(FREE_TREADMILL_CLAIMED_ATTRIBUTE) == true
	frame.Visible = not claimed
	local button = self.freeTreadmillClaimButton
	if claimed then
		self.freeTreadmillClaimPending = false
		if button then
			button.Active = false
			button.Interactable = false
			button.Selectable = false
		end
		return
	end

	if self.freeTreadmillClaimPending and os.clock() >= self.freeTreadmillClaimPendingUntil then
		self.freeTreadmillClaimPending = false
		self.freeTreadmillClaimPendingUntil = 0
	end

	local remainingAttribute = self.player:GetAttribute(FREE_TREADMILL_REMAINING_ATTRIBUTE)
	local remainingSeconds = if typeof(remainingAttribute) == "number"
		then math.max(0, math.floor(remainingAttribute))
		else FREE_TREADMILL_SESSION_SECONDS
	local isReady = remainingSeconds <= 0
	local canClaim = isReady and self.player:GetAttribute("Data_Loaded") == true
		and not self.freeTreadmillClaimPending

	if self.freeTreadmillCountdownLabel then
		self.freeTreadmillCountdownLabel.Text = formatCountdown(remainingSeconds)
		self.freeTreadmillCountdownLabel.Visible = not isReady
	end
	if self.freeTreadmillClaimLabel then
		if self.freeTreadmillClaimPending then
			self.freeTreadmillClaimLabel.Text = "CLAIMING..."
		elseif isReady then
			self.freeTreadmillClaimLabel.Text = "CLAIM"
		else
			self.freeTreadmillClaimLabel.Text = self.freeTreadmillClaimLabelDefaultText or "FREE 2X TREADMILL"
		end
	end

	if button then
		button.Active = canClaim
		button.Interactable = canClaim
		button.Selectable = canClaim
	end
end

function PlaytimeRewardsUI:Refresh()
	if self.destroyed then
		return
	end
	self:RefreshFreeTreadmillButton()

	if next(self.entries) == nil then
		self:Rebuild()
	end

	local elapsedAttribute = self.player:GetAttribute(PLAYTIME_ELAPSED_ATTRIBUTE)
	local elapsedSeconds = if typeof(elapsedAttribute) == "number" then elapsedAttribute else 0
	local claimedSet = parseClaimedTiers(self.player:GetAttribute(PLAYTIME_CLAIMED_ATTRIBUTE))
	local isFreshCycle = next(claimedSet) == nil and elapsedSeconds <= 0
	if isFreshCycle then
		-- The server clears both attributes after the final cycle claim. Clear
		-- any local pending state immediately so the new cycle is responsive.
		for _, entry in pairs(self.entries) do
			entry.inFlight = false
		end
	end
	local expectedTierIndex = if DEBUG_SEQUENTIAL_CLAIM_MODE then getFirstUnclaimedTierIndex(claimedSet) else nil
	local claimableCount = 0

	for tierId, entry in pairs(self.entries) do
		local tier = entry.tier
		entry.rewardLabel.Text = formatRewardText(tier, self.player)
		local isClaimed = claimedSet[tierId] == true
		if isClaimed then
			self:ApplyClaimedState(entry)
		else
			entry.isClaimed = false
			if entry.inFlight then
				self:ApplyClaimingState(entry)
				continue
			end

			if DEBUG_SEQUENTIAL_CLAIM_MODE then
				if expectedTierIndex and entry.tierIndex == expectedTierIndex then
					self:ApplyReadyState(entry)
					claimableCount += 1
				else
					self:ApplyLockedState(entry, 0)
				end
			else
				local remaining = tier.unlockSeconds - elapsedSeconds
				if remaining <= 0 then
					self:ApplyReadyState(entry)
					claimableCount += 1
				else
					self:ApplyLockedState(entry, remaining)
				end
			end
		end
	end

	self:NotifyClaimableCount(claimableCount)
end

function PlaytimeRewardsUI:Bind()
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(PLAYTIME_ELAPSED_ATTRIBUTE):Connect(function()
		self:Refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(PLAYTIME_CLAIMED_ATTRIBUTE):Connect(function()
		self:Refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(FREE_TREADMILL_REMAINING_ATTRIBUTE):Connect(function()
		self:RefreshFreeTreadmillButton()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(FREE_TREADMILL_CLAIMED_ATTRIBUTE):Connect(function()
		self:RefreshFreeTreadmillButton()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
		self:RefreshFreeTreadmillButton()
	end))

	self.maid:GiveTask(self.root.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "FreeTreadmillButtonFrame" then
			self:BindFreeTreadmillButton()
		end
		if descendant.Name == "RewardsFrame" or descendant.Name == "PlaytimeRewardButton_Template" then
			task.defer(function()
				if self.destroyed then
					return
				end
				self:Rebuild()
				self:Refresh()
			end)
		end
	end))
	self.maid:GiveTask(self.root.DescendantRemoving:Connect(function(descendant)
		if descendant == self.freeTreadmillButtonFrame then
			self.maid.FreeTreadmillButtonConnection = nil
			self.maid.FreeTreadmillDescendantAdded = nil
			self.freeTreadmillButtonFrame = nil
			self.freeTreadmillClaimButton = nil
			self.freeTreadmillCountdownLabel = nil
			self.freeTreadmillClaimLabel = nil
			self.freeTreadmillClaimLabelDefaultText = nil
		elseif
			descendant == self.freeTreadmillClaimButton
			or descendant == self.freeTreadmillCountdownLabel
			or descendant == self.freeTreadmillClaimLabel
		then
			task.defer(function()
				if not self.destroyed then
					self:BindFreeTreadmillButton()
				end
			end)
		end
	end))

	self.maid:GiveTask(RunService.Heartbeat:Connect(function(dt)
		self.updateAccumulator += dt
		if self.updateAccumulator < COUNTDOWN_UPDATE_INTERVAL then
			return
		end
		self.updateAccumulator = 0

		self:Refresh()
	end))
end

function PlaytimeRewardsUI:Destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self:NotifyClaimableCount(0)
	self.maid:DoCleaning()
	self.entryMaid:DoCleaning()
	self:ClearEntries()
end

return PlaytimeRewardsUI
