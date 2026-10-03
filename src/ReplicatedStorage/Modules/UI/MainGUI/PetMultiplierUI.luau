--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)

type PetMultiplierUIObject = {
	screenGui: ScreenGui,
	player: Player,
	frame: GuiObject?,
	multiplierLabel: TextLabel?,
	connections: { RBXScriptConnection },
	initialized: boolean,
	alive: boolean,
	Init: (self: PetMultiplierUIObject) -> (),
	Destroy: (self: PetMultiplierUIObject) -> (),
}

local PetMultiplierUI = {}
PetMultiplierUI.__index = PetMultiplierUI

local MODULE_NAME = "PetMultiplierUI"
local MULTIPLIER_ATTRIBUTE = "Pet_EquippedMultiplier"
local DEFAULT_MULTIPLIER = 1

function PetMultiplierUI.new(screenGui: ScreenGui): PetMultiplierUIObject?
	local player = Players.LocalPlayer
	if not player then
		DebugModule.debugWarn("Cannot initialize pet multiplier UI without local player", MODULE_NAME)
		return nil
	end

	return setmetatable({
		screenGui = screenGui,
		player = player,
		frame = nil,
		multiplierLabel = nil,
		connections = {},
		initialized = false,
		alive = true,
	}, PetMultiplierUI) :: PetMultiplierUIObject
end

function PetMultiplierUI.Init(self: PetMultiplierUIObject)
	if self.initialized or not self.alive then
		return
	end
	self.initialized = true

	local frame = self.screenGui:FindFirstChild("PetMultiplierFrame", true)
	local multiplierLabel = frame and frame:FindFirstChild("Multiplier", true)
	if not frame or not frame:IsA("GuiObject") then
		DebugModule.debugWarn("PetMultiplierFrame was not found", MODULE_NAME)
		return
	end
	if not multiplierLabel or not multiplierLabel:IsA("TextLabel") then
		DebugModule.debugWarn("PetMultiplierFrame Multiplier label was not found", MODULE_NAME)
		return
	end

	self.frame = frame
	self.multiplierLabel = multiplierLabel
	local attributeConnection: RBXScriptConnection? = nil
	local function refresh()
		if not self.alive then
			return
		end
		if not multiplierLabel:IsDescendantOf(self.screenGui) then
			DebugModule.debugWarn("Skipped stale pet multiplier label reference", MODULE_NAME)
			if attributeConnection then
				attributeConnection:Disconnect()
				attributeConnection = nil
			end
			self.multiplierLabel = nil
			self.frame = nil
			return
		end
		local multiplier = self.player:GetAttribute(MULTIPLIER_ATTRIBUTE)
		if typeof(multiplier) ~= "number"
			or multiplier ~= multiplier
			or multiplier == math.huge
			or multiplier == -math.huge
			or multiplier < DEFAULT_MULTIPLIER
		then
			multiplier = DEFAULT_MULTIPLIER
		end
		multiplierLabel.Text = string.format("%.2fx", multiplier)
	end

	refresh()
	if self.multiplierLabel ~= multiplierLabel then
		return
	end
	attributeConnection = self.player:GetAttributeChangedSignal(MULTIPLIER_ATTRIBUTE):Connect(refresh)
	table.insert(self.connections, attributeConnection)
	DebugModule.debugInfo("Pet multiplier display initialized", MODULE_NAME)
end

function PetMultiplierUI.Destroy(self: PetMultiplierUIObject)
	if not self.alive then
		return
	end
	self.alive = false
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.multiplierLabel = nil
	self.frame = nil
end

return PetMultiplierUI
