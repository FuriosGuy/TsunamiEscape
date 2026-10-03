--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Maid = require(ReplicatedStorage.Modules.Maid)

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)

local HapticButtonController = {}
HapticButtonController.__index = HapticButtonController

type ButtonHapticState = {
	originalPress: HapticEffect?,
	originalHover: HapticEffect?,
}

type HapticButtonControllerObject = {
	root: Instance,
	player: Player,
	maid: any,
	effect: HapticEffect?,
	buttonStates: { [GuiButton]: ButtonHapticState },
	initialized: boolean,
	alive: boolean,
	warnedAboutApi: boolean,
	refresh: (self: HapticButtonControllerObject) -> (),
	Init: (self: HapticButtonControllerObject) -> (),
	Destroy: (self: HapticButtonControllerObject) -> (),
}

local MODULE_NAME = "HapticButtonController"

local function createClickEffect(): HapticEffect?
	local success, effectOrError = pcall(function()
		local effect = Instance.new("HapticEffect")
		effect.Name = "MainGUIUIClickHaptic"
		effect.Type = Enum.HapticEffectType.UIClick
		effect.Looped = false
		effect.Parent = Workspace
		return effect
	end)

	if not success then
		DebugModule.debugWarn("Could not create UIClick haptic effect: " .. tostring(effectOrError), MODULE_NAME)
		return nil
	end

	return effectOrError :: HapticEffect
end

local function syncButton(controller: HapticButtonControllerObject, button: GuiButton): ()
	if not controller.alive or not button:IsDescendantOf(controller.root) then
		return
	end

	local success, syncError = pcall(function()
		local state = controller.buttonStates[button]
		if not state then
			state = {
				originalPress = button.PressHapticEffect,
				originalHover = button.HoverHapticEffect,
			}
			controller.buttonStates[button] = state
		end

		if controller.player:GetAttribute("HapticsEnabled") == false then
			button.PressHapticEffect = nil
			button.HoverHapticEffect = nil
			return
		end

		button.PressHapticEffect = state.originalPress or controller.effect
		button.HoverHapticEffect = state.originalHover
	end)

	if not success then
		if not controller.warnedAboutApi then
			controller.warnedAboutApi = true
			DebugModule.debugWarn("Could not sync GuiButton haptic effects: " .. tostring(syncError), MODULE_NAME)
		end
	end
end

function HapticButtonController.new(root: ScreenGui): HapticButtonControllerObject
	return setmetatable({
		root = root,
		player = assert(Players.LocalPlayer, "HapticButtonController requires a local player"),
		maid = Maid.new(),
		effect = nil,
		buttonStates = setmetatable({}, { __mode = "k" }) :: { [GuiButton]: ButtonHapticState },
		initialized = false,
		alive = true,
		warnedAboutApi = false,
	}, HapticButtonController) :: HapticButtonControllerObject
end

function HapticButtonController.refresh(self: HapticButtonControllerObject): ()
	if not self.alive then
		return
	end

	if self.player:GetAttribute("HapticsEnabled") ~= false and not self.effect then
		self.effect = createClickEffect()
	end

	for button in pairs(self.buttonStates) do
		syncButton(self, button)
	end
end

function HapticButtonController.Init(self: HapticButtonControllerObject): ()
	if self.initialized or not self.alive then
		return
	end
	self.initialized = true

	self.maid:GiveTask(self.root.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("GuiButton") then
			syncButton(self, descendant)
		end
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("HapticsEnabled"):Connect(function()
		self:refresh()
	end))

	for _, descendant in ipairs(self.root:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			syncButton(self, descendant)
		end
	end
	self:refresh()
end

function HapticButtonController.Destroy(self: HapticButtonControllerObject): ()
	if not self.alive then
		return
	end
	self.alive = false
	self.maid:DoCleaning()

	local effect = self.effect
	for button, state in pairs(self.buttonStates) do
		local success, restoreError = pcall(function()
			button.PressHapticEffect = state.originalPress
			button.HoverHapticEffect = state.originalHover
		end)
		if not success and not self.warnedAboutApi then
			self.warnedAboutApi = true
			DebugModule.debugWarn(
				"Could not restore GuiButton haptic effects: " .. tostring(restoreError),
				MODULE_NAME
			)
		end
	end

	if effect then
		effect:Destroy()
		self.effect = nil
	end
	table.clear(self.buttonStates)
end

return HapticButtonController
