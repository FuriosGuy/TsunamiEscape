--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)

local PreferenceToggleUI = {}
PreferenceToggleUI.__index = PreferenceToggleUI

export type PreferenceToggleConfig = {
	frameName: string,
	attributeName: string,
	remoteName: string,
	enabledImage: string,
	disabledImage: string,
	debugName: string,
	labelText: string?,
}

export type PreferenceToggleUIObject = {
	screenGui: ScreenGui,
	player: Player,
	config: PreferenceToggleConfig,
	maid: any,
	frame: GuiObject?,
	button: GuiButton?,
	icon: ImageLabel?,
	initialized: boolean,
	alive: boolean,
	lastToggleAt: number,
	refresh: (self: PreferenceToggleUIObject) -> (),
	Init: (self: PreferenceToggleUIObject) -> (),
	Destroy: (self: PreferenceToggleUIObject) -> (),
}

local TOGGLE_DEBOUNCE_SECONDS = 0.25

function PreferenceToggleUI.new(
	screenGui: ScreenGui,
	config: PreferenceToggleConfig
): PreferenceToggleUIObject
	local player = assert(Players.LocalPlayer, "PreferenceToggleUI requires a local player")
	return setmetatable({
		screenGui = screenGui,
		player = player,
		config = config,
		maid = Maid.new(),
		frame = nil,
		button = nil,
		icon = nil,
		initialized = false,
		alive = true,
		lastToggleAt = -math.huge,
	}, PreferenceToggleUI) :: PreferenceToggleUIObject
end

function PreferenceToggleUI.refresh(self: PreferenceToggleUIObject): ()
	local icon = self.icon
	local button = self.button
	if not self.alive or not icon or not button then
		return
	end

	local enabled = self.player:GetAttribute(self.config.attributeName) ~= false
	icon.Image = if enabled then self.config.enabledImage else self.config.disabledImage
	local dataLoaded = self.player:GetAttribute("Data_Loaded") == true
	button.Active = dataLoaded
	button.AutoButtonColor = dataLoaded
end

function PreferenceToggleUI.Init(self: PreferenceToggleUIObject): ()
	if self.initialized or not self.alive then
		return
	end
	self.initialized = true

	local config = self.config
	local frameInstance = self.screenGui:FindFirstChild(config.frameName, true)
	if not frameInstance or not frameInstance:IsA("GuiObject") then
		DebugModule.debugWarn(config.frameName .. " was not found", config.debugName)
		return
	end
	local buttonInstance = frameInstance:FindFirstChild("TextButton", true)
	local iconInstance = frameInstance:FindFirstChild("Image", true)
	if not buttonInstance or not buttonInstance:IsA("GuiButton") then
		DebugModule.debugWarn(config.frameName .. " TextButton was not found", config.debugName)
		return
	end
	if not iconInstance or not iconInstance:IsA("ImageLabel") then
		DebugModule.debugWarn(config.frameName .. " Image was not found", config.debugName)
		return
	end

	local labelInstance = frameInstance:FindFirstChild("TextLabel", true)
	if config.labelText and labelInstance and labelInstance:IsA("TextLabel") then
		labelInstance.Text = config.labelText
	end

	self.frame = frameInstance
	self.button = buttonInstance
	self.icon = iconInstance
	self:refresh()
	buttonInstance.Active = false
	buttonInstance.AutoButtonColor = false

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local remoteInstance = if remotes then remotes:WaitForChild(config.remoteName, 10) else nil
	if not remoteInstance or not remoteInstance:IsA("RemoteEvent") then
		DebugModule.debugWarn(config.remoteName .. " RemoteEvent was not found", config.debugName)
		return
	end

	self:refresh()

	self.maid:GiveTask(buttonInstance.Activated:Connect(function()
		local now = os.clock()
		if not self.alive
			or self.player:GetAttribute("Data_Loaded") ~= true
			or now - self.lastToggleAt < TOGGLE_DEBOUNCE_SECONDS
		then
			return
		end
		self.lastToggleAt = now

		local attributeName = config.attributeName
		local nextEnabled = self.player:GetAttribute(attributeName) == false
		self.player:SetAttribute(attributeName, nextEnabled)
		self:refresh()

		local success, err = pcall(function()
			(remoteInstance :: RemoteEvent):FireServer(nextEnabled)
		end)
		if not success then
			self.player:SetAttribute(attributeName, not nextEnabled)
			self:refresh()
			DebugModule.debugWarn(
				config.debugName .. " preference request failed: " .. tostring(err),
				config.debugName
			)
		end
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal(config.attributeName):Connect(function()
		self:refresh()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
		self:refresh()
	end))
end

function PreferenceToggleUI.Destroy(self: PreferenceToggleUIObject): ()
	if not self.alive then
		return
	end
	self.alive = false
	self.maid:DoCleaning()
	self.frame = nil
	self.button = nil
	self.icon = nil
end

return PreferenceToggleUI
