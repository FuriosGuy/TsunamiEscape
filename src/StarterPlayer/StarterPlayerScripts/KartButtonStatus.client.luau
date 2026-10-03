--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerHandler = require(ReplicatedStorage.Modules.Shared:WaitForChild("PlayerHandler_Client"))

local localPlayer = Players.LocalPlayer

local EQUIPPED_COLOR = Color3.fromRGB(0, 255, 0)
local AVAILABLE_COLOR = Color3.fromRGB(213, 115, 61)
local LOCKED_COLOR = Color3.fromRGB(196, 40, 28)

local EVENT_WINS_ATTRIBUTES: { [string]: string } = {
	Bloodmoon = "BloodmoonWins",
	NeonRush = "NeonRushWins",
	FrostbiteRally = "FrostbiteRallyWins",
}

local trackedButtonParts: { [BasePart]: boolean } = {}
local liveEventState: Folder? = nil
local liveEventStateConnection: RBXScriptConnection? = nil

local function getStringAttribute(instance: Instance, attributeName: string): string?
	local value = instance:GetAttribute(attributeName)
	return if typeof(value) == "string" and value ~= "" then value else nil
end

local function getNumberAttribute(instance: Instance, attributeName: string): number?
	local value = instance:GetAttribute(attributeName)
	if typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end

	return nil
end

local function getEventName(kartButton: Model): string?
	local directEventName = getStringAttribute(kartButton, "EventName")
	if directEventName then
		return directEventName
	end

	local eventButtonsFolder = kartButton:FindFirstAncestor("EventKartButtons")
	if not eventButtonsFolder then
		return nil
	end

	local ancestor: Instance? = kartButton
	while ancestor and ancestor.Parent ~= eventButtonsFolder do
		ancestor = ancestor.Parent
	end

	return if ancestor and ancestor.Parent == eventButtonsFolder then ancestor.Name else nil
end

local function getWorldKartName(kartButton: Model): string?
	local configuredKartName = getStringAttribute(kartButton, "KartName")
	if configuredKartName then
		return configuredKartName
	end

	local gamepassKartName = string.match(kartButton.Name, "^KartButton_(.+)$")
	if gamepassKartName and tonumber(gamepassKartName) == nil then
		return gamepassKartName
	end

	local kartNumber = getNumberAttribute(kartButton, "KartNumber")
	if not kartNumber then
		return nil
	end

	local world = kartButton:FindFirstAncestorWhichIsA("Folder")
	while world and world.Parent and world.Parent.Name ~= "Worlds" do
		world = world.Parent :: Folder
	end
	if not world then
		return nil
	end

	local kartModels = ReplicatedStorage:FindFirstChild("KartModels")
	local worldModels = kartModels and kartModels:FindFirstChild(world.Name)
	if not worldModels then
		return nil
	end

	local prefix = tostring(math.floor(kartNumber)) .. "_"
	for _, child in ipairs(worldModels:GetChildren()) do
		if child:IsA("Model") and string.sub(child.Name, 1, #prefix) == prefix then
			return child.Name
		end
	end

	return nil
end

local function isLiveEventActive(eventName: string): boolean
	local stateFolder = liveEventState
	if not stateFolder then
		return false
	end

	local activeEventIds = stateFolder:GetAttribute("ActiveEventIds")
	if typeof(activeEventIds) ~= "string" then
		return false
	end

	for activeEventId in string.gmatch(activeEventIds, "[^,]+") do
		if string.lower(activeEventId) == string.lower(eventName) then
			return true
		end
	end

	return false
end

local function getKartButton(buttonPart: BasePart): Model?
	local kartButton = buttonPart.Parent
	if not kartButton or not kartButton:IsA("Model") or kartButton:FindFirstChild("Button") ~= buttonPart then
		return nil
	end

	if not kartButton:FindFirstAncestor("KartButtons") and not kartButton:FindFirstAncestor("EventKartButtons") then
		return nil
	end

	return kartButton
end

local function isPaidKart(kartButton: Model): boolean
	if getStringAttribute(kartButton, "ProductKey") ~= nil then
		return true
	end

	local nameSuffix = string.match(kartButton.Name, "^GamepassKartButton_(.+)$")
		or string.match(kartButton.Name, "^KartButton_(.+)$")
	return nameSuffix ~= nil and tonumber(nameSuffix) == nil
end

local function getCurrentWins(eventName: string?): number
	local attributeName: string? = nil
	if eventName then
		for configuredEventName, configuredAttributeName in pairs(EVENT_WINS_ATTRIBUTES) do
			if string.lower(configuredEventName) == string.lower(eventName) then
				attributeName = configuredAttributeName
				break
			end
		end
	else
		attributeName = "WinCount"
	end

	local wins = attributeName and getNumberAttribute(localPlayer, attributeName)
	return wins or 0
end

local function updateButtonStatus(buttonPart: BasePart)
	local kartButton = getKartButton(buttonPart)
	if not kartButton then
		trackedButtonParts[buttonPart] = nil
		return
	end

	local kartName = getWorldKartName(kartButton)
	local eventName = getEventName(kartButton)
	if not kartName then
		return
	end
	if isPaidKart(kartButton) then
		return
	end

	if localPlayer:GetAttribute("Kart_Equipped") == kartName then
		buttonPart.Color = EQUIPPED_COLOR
		return
	end

	if eventName and not isLiveEventActive(eventName) then
		buttonPart.Color = LOCKED_COLOR
		return
	end

	local winsRequired = getNumberAttribute(kartButton, "WinsRequired")
	local hasEnoughWins = winsRequired ~= nil and getCurrentWins(eventName) >= winsRequired
	local ownsKart = PlayerHandler.OwnsKart(localPlayer, kartName)
	buttonPart.Color = if ownsKart or hasEnoughWins then AVAILABLE_COLOR else LOCKED_COLOR
end

local function refreshTrackedButtons()
	for buttonPart in pairs(trackedButtonParts) do
		if buttonPart.Parent then
			updateButtonStatus(buttonPart)
		else
			trackedButtonParts[buttonPart] = nil
		end
	end
end

local function registerButtonPart(instance: Instance)
	if not instance:IsA("BasePart") or instance.Name ~= "Button" then
		return
	end

	local kartButton = getKartButton(instance)
	if not kartButton then
		return
	end

	trackedButtonParts[instance] = true
	updateButtonStatus(instance)
end

local function bindLiveEventState(candidate: Instance)
	if not candidate:IsA("Folder") or liveEventState == candidate then
		return
	end

	if liveEventStateConnection then
		liveEventStateConnection:Disconnect()
		liveEventStateConnection = nil
	end

	liveEventState = candidate
	liveEventStateConnection = candidate:GetAttributeChangedSignal("ActiveEventIds"):Connect(refreshTrackedButtons)
	refreshTrackedButtons()
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
	registerButtonPart(descendant)
end

Workspace.DescendantAdded:Connect(registerButtonPart)
Workspace.DescendantRemoving:Connect(function(instance)
	if instance:IsA("BasePart") then
		trackedButtonParts[instance] = nil
	end
end)

for _, attributeName in ipairs({
	"WinCount",
	"BloodmoonWins",
	"NeonRushWins",
	"FrostbiteRallyWins",
	"Kart_Equipped",
	"OwnedKarts",
}) do
	localPlayer:GetAttributeChangedSignal(attributeName):Connect(refreshTrackedButtons)
end

local existingState = ReplicatedStorage:FindFirstChild("LiveEventState")
if existingState then
	bindLiveEventState(existingState)
end

ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "LiveEventState" then
		bindLiveEventState(child)
	end
end)
