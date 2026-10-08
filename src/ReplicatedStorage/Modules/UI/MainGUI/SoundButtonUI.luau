--!strict

local PreferenceToggleUI = require(script.Parent.PreferenceToggleUI)

type PreferenceToggleConfig = PreferenceToggleUI.PreferenceToggleConfig
type PreferenceToggleUIObject = PreferenceToggleUI.PreferenceToggleUIObject

local SoundButtonUI = {}

local MUSIC_CONFIG: PreferenceToggleConfig = table.freeze({
	frameName = "SoundButtonFrame",
	attributeName = "MusicEnabled",
	remoteName = "SoundPreferenceChanged",
	enabledImage = "rbxassetid://130154476215017",
	disabledImage = "rbxassetid://96167397555969",
	debugName = "SoundButtonUI",
})

function SoundButtonUI.new(screenGui: ScreenGui): PreferenceToggleUIObject
	return PreferenceToggleUI.new(screenGui, MUSIC_CONFIG)
end

return SoundButtonUI
