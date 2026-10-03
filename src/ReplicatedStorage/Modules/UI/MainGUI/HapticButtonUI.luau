--!strict

local PreferenceToggleUI = require(script.Parent.PreferenceToggleUI)

type PreferenceToggleConfig = PreferenceToggleUI.PreferenceToggleConfig
type PreferenceToggleUIObject = PreferenceToggleUI.PreferenceToggleUIObject

local HapticButtonUI = {}

local HAPTIC_CONFIG: PreferenceToggleConfig = table.freeze({
	frameName = "HapticButtonFrame",
	attributeName = "HapticsEnabled",
	remoteName = "HapticPreferenceChanged",
	enabledImage = "rbxassetid://138611960784953",
	disabledImage = "rbxassetid://114347081530443",
	debugName = "HapticButtonUI",
	labelText = "HAPTIC",
})

function HapticButtonUI.new(screenGui: ScreenGui): PreferenceToggleUIObject
	return PreferenceToggleUI.new(screenGui, HAPTIC_CONFIG)
end

return HapticButtonUI
