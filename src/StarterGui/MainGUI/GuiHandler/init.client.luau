local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NotificationLayoutController = require(ReplicatedStorage.Modules.UI.MainGUI.NotificationLayoutController)
local HapticButtonController = require(ReplicatedStorage.Modules.UI.MainGUI.HapticButtonController)
local MainOrchestrator = require(ReplicatedStorage.Modules.UI.MainGUI.MainOrchestrator)
local SpinWheelUI = require(ReplicatedStorage.Modules.UI.MainGUI.SpinWheelUI)
local MinigameUI = require(ReplicatedStorage.Modules.UI.MainGUI.MinigameUI)
local LiveEventBannerUI = require(ReplicatedStorage.Modules.UI.MainGUI.LiveEventBannerUI)
local EventProgressUI = require(ReplicatedStorage.Modules.UI.MainGUI.EventProgressUI)
local ProgressFrameVisibilityController = require(ReplicatedStorage.Modules.UI.MainGUI.ProgressFrameVisibilityController)
local PremiumUI = require(ReplicatedStorage.Modules.UI.MainGUI.PremiumUI)
local FriendMultiplierUI = require(ReplicatedStorage.Modules.UI.MainGUI.FriendMultiplierUI)
local SoundButtonUI = require(ReplicatedStorage.Modules.UI.MainGUI.SoundButtonUI)
local HapticButtonUI = require(ReplicatedStorage.Modules.UI.MainGUI.HapticButtonUI)
local TemporaryBoostUI = require(ReplicatedStorage.Modules.UI.MainGUI.TemporaryBoostUI)
local PromptBuyProductsUI = require(ReplicatedStorage.Modules.UI.MainGUI.PromptBuyProductsUI)
local MouseTooltipController = require(ReplicatedStorage.Modules.UI.MainGUI.MouseTooltipController)
local PetUpgradeUIController = require(ReplicatedStorage.Modules.UI.MainGUI.PetUpgradeUIController)
local PetInventoryUIController = require(ReplicatedStorage.Modules.UI.MainGUI.PetInventoryUIController)
local PetMultiplierUI = require(ReplicatedStorage.Modules.UI.MainGUI.PetMultiplierUI)
local PetLuckyBlockScreenController = require(ReplicatedStorage.Modules.UI.MainGUI.PetLuckyBlockScreenController)
local PetLuckyBlockBillboardVisualController =
	require(ReplicatedStorage.Modules.UI.MainGUI.PetLuckyBlockBillboardVisualController)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local GUI_HANDLER_SINGLETON_KEY = "__SpeedBrainrotMainGuiHandler"

local existingHandler = shared[GUI_HANDLER_SINGLETON_KEY]
if existingHandler ~= nil and existingHandler ~= script then
	DebugModule.debugWarn("Duplicate GuiHandler detected, destroying new instance", "GuiHandler")
	script:Destroy()
	return
end

shared[GUI_HANDLER_SINGLETON_KEY] = script

-- Wait for the ScreenGui to be fully loaded
if not script.Parent:IsA("ScreenGui") then
	DebugModule.debugWarn("GuiHandler is not a child of a ScreenGui!", "GuiHandler")
end

local hapticButtonController = if script.Parent:IsA("ScreenGui")
	then HapticButtonController.new(script.Parent :: ScreenGui)
	else nil
if hapticButtonController then
	hapticButtonController:Init()
end

-- Initialize the orchestrator with the current ScreenGui as the root
-- Build reserved top-of-screen UI first so the first notification uses the
-- final event/progress layout instead of the initial hidden-template state.
local progressFrameVisibilityController = ProgressFrameVisibilityController.new(script.Parent)

local liveEventBannerUI = LiveEventBannerUI.new(script.Parent)
liveEventBannerUI:Init()

local eventProgressUI = EventProgressUI.new(script.Parent, progressFrameVisibilityController)
eventProgressUI:Init()

local notificationLayoutController = NotificationLayoutController.new(script.Parent)
notificationLayoutController:Init()

MainOrchestrator.Init(script.Parent)

local spinWheelUI = SpinWheelUI.new(script.Parent)
spinWheelUI:Init()

local petLuckyBlockScreenController = PetLuckyBlockScreenController.new(script.Parent :: ScreenGui)
if petLuckyBlockScreenController then
	petLuckyBlockScreenController:Init()
end

local petLuckyBlockBillboardVisualController = PetLuckyBlockBillboardVisualController.new()
petLuckyBlockBillboardVisualController:Init()

local minigameUI = MinigameUI.new(script.Parent, progressFrameVisibilityController)
minigameUI:Init()

local temporaryBoostUI = TemporaryBoostUI.new(script.Parent)
temporaryBoostUI:Init()

local premiumUI = PremiumUI.new(script.Parent)
premiumUI:Init()

local friendMultiplierUI = FriendMultiplierUI.new(script.Parent)
friendMultiplierUI:Init()

local soundButtonUI = SoundButtonUI.new(script.Parent)
soundButtonUI:Init()

local hapticButtonUI = HapticButtonUI.new(script.Parent)
hapticButtonUI:Init()

local promptBuyProductsUI = PromptBuyProductsUI.new(script.Parent)
promptBuyProductsUI:Init()

local mouseTooltipController = MouseTooltipController.new(script.Parent)
mouseTooltipController:Init()

local petUpgradeUIController = PetUpgradeUIController.new(script.Parent :: ScreenGui)
local petInventoryUIController = PetInventoryUIController.new(script.Parent :: ScreenGui)
local petMultiplierUI = PetMultiplierUI.new(script.Parent :: ScreenGui)
if petMultiplierUI then
	petMultiplierUI:Init()
end

NotificationLayoutController.Refresh()
DebugModule.debugPrint(
	"GuiHandler initialized | notification layout active | root=" .. script.Parent:GetFullName(),
	"GuiHandler"
)

local function cleanupGuiHandlerSingleton()
	notificationLayoutController:Destroy()
	spinWheelUI:Destroy()
	if petLuckyBlockScreenController then
		petLuckyBlockScreenController:Destroy()
	end
	petLuckyBlockBillboardVisualController:Destroy()
	minigameUI:Destroy()
	liveEventBannerUI:Destroy()
	eventProgressUI:Destroy()
	temporaryBoostUI:Destroy()
	premiumUI:Destroy()
	friendMultiplierUI:Destroy()
	soundButtonUI:Destroy()
	hapticButtonUI:Destroy()
	promptBuyProductsUI:Destroy()
	mouseTooltipController:Destroy()
	petUpgradeUIController:Destroy()
	if petInventoryUIController then
		petInventoryUIController:Destroy()
	end
	if petMultiplierUI then
		petMultiplierUI:Destroy()
	end
	if hapticButtonController then
		hapticButtonController:Destroy()
	end
	progressFrameVisibilityController:Destroy()
	if shared[GUI_HANDLER_SINGLETON_KEY] == script then
		shared[GUI_HANDLER_SINGLETON_KEY] = nil
	end
end

script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanupGuiHandlerSingleton()
	end
end)
script.Destroying:Connect(cleanupGuiHandlerSingleton)
