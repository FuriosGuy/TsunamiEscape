--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MainOrchestrator = require(ReplicatedStorage.Modules.UI.MainGUI.MainOrchestrator)
local SpinWheelUI = require(ReplicatedStorage.Modules.UI.MainGUI.SpinWheelUI)
local MinigameUI = require(ReplicatedStorage.Modules.UI.MainGUI.MinigameUI)
local LiveEventBannerUI = require(ReplicatedStorage.Modules.UI.MainGUI.LiveEventBannerUI)
local BloodMoonProgressUI = require(ReplicatedStorage.Modules.UI.MainGUI.BloodMoonProgressUI)
local TemporaryBoostUI = require(ReplicatedStorage.Modules.UI.MainGUI.TemporaryBoostUI)
local PromptBuyProductsUI = require(ReplicatedStorage.Modules.UI.MainGUI.PromptBuyProductsUI)
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

-- Initialize the orchestrator with the current ScreenGui as the root
MainOrchestrator.Init(script.Parent)

local spinWheelUI = SpinWheelUI.new(script.Parent)
spinWheelUI:Init()

local minigameUI = MinigameUI.new(script.Parent)
minigameUI:Init()

local liveEventBannerUI = LiveEventBannerUI.new(script.Parent)
liveEventBannerUI:Init()

local bloodMoonProgressUI = BloodMoonProgressUI.new(script.Parent)
bloodMoonProgressUI:Init()

local temporaryBoostUI = TemporaryBoostUI.new(script.Parent)
temporaryBoostUI:Init()

local promptBuyProductsUI = PromptBuyProductsUI.new(script.Parent)
promptBuyProductsUI:Init()

DebugModule.debugPrint("GuiHandler initialized.", "GuiHandler")

local function cleanupGuiHandlerSingleton()
	spinWheelUI:Destroy()
	minigameUI:Destroy()
	liveEventBannerUI:Destroy()
	bloodMoonProgressUI:Destroy()
	temporaryBoostUI:Destroy()
	promptBuyProductsUI:Destroy()
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
