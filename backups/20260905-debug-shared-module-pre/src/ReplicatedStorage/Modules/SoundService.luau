--!strict
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxSoundService = game:GetService("SoundService")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule_Client)

local SoundService = {}
local guiSoundFolder = Instance.new("Folder")
guiSoundFolder.Name = "GuiSounds"
guiSoundFolder.Parent = RobloxSoundService

SoundService.WorldMusicPlaylists = {
	Fallback = {
		LobbyMusicList = { 138197655562277 },
		ActionMusicList = { 72666159391603 },
	},
}

export type SoundSettings = {
	SoundId: string | number,
	Volume: number?,
	Pitch: number?,
	PlaybackSpeed: number?,
	Looped: boolean?,
	AllowOverlap: boolean?,
	RollOffMode: Enum.RollOffMode?,
	RollOffMinDistance: number?,
	RollOffMaxDistance: number?,
	TimePosition: number?,
}

SoundService.Sounds = {
	["Click"] = {
		SoundId = 124637583082916,
		Volume = 0.4,
		Pitch = 1,
		PlaybackSpeed = 1,
		Looped = false,
		AllowOverlap = false,
	},
	["Pop"] = {
		SoundId = 109359226723492,
		Volume = 0.8,
		Pitch = 1,
		PlaybackSpeed = 1,
		Looped = false,
		AllowOverlap = true,
	},
	["Close"] = {
		SoundId = 92389629512441,
		Volume = 0.4,
		Pitch = 1,
		PlaybackSpeed = 0.75,
		Looped = false,
		AllowOverlap = false,
	},
	["BellRing"] = {
		SoundId = 128714357287984,
		Volume = 0.4,
		Pitch = 1,
		PlaybackSpeed = 0.75,
		Looped = false,
		AllowOverlap = false,
	},
	["Success"] = {
		SoundId = 128044073486125,
		Volume = 0.4,
		Pitch = 1,
		PlaybackSpeed = 0.75,
		Looped = false,
		AllowOverlap = false,
	},
	["Hover"] = {
		SoundId = 139800881181209,
		Volume = 0.3,
		Pitch = 1,
		PlaybackSpeed = 1.5,
		Looped = false,
		AllowOverlap = false,
	},
	["LevelUp"] = {
		SoundId = 3120909354,
		Volume = 0.7,
		Pitch = 1,
		PlaybackSpeed = 1,
		Looped = false,
		AllowOverlap = true,
	},
	["Rebirth"] = {
		SoundId = 100288208393628,
		Volume = 0.7,
		Pitch = 1,
		PlaybackSpeed = 1,
		Looped = false,
		AllowOverlap = true,
	},
	["WinReward"] = {
		SoundId = 136993031050456,
		Volume = 1,
		Pitch = 1,
		PlaybackSpeed = 1,
		Looped = false,
		AllowOverlap = true,
	},
	["BloodmoonRise"] = {
		SoundId = 89079094196786,
		Volume = 1,
		Pitch = 1,
		PlaybackSpeed = 1,
		Looped = false,
		AllowOverlap = false,
	},
	["Confetti"] = {
		SoundId = 1631688574,
		Volume = 1,
		Pitch = 1,
		PlaybackSpeed = 1,
		Looped = false,
		AllowOverlap = true,
	},
	["Swish"] = {
		SoundId = 91252825775281,
		Volume = 1,
		Pitch = 1,
		PlaybackSpeed = 1,
		Looped = false,
		AllowOverlap = true,
	},
	["AmbientLoop"] = {
		SoundId = 0,
		Volume = 0.35,
		Pitch = 1,
		PlaybackSpeed = 1,
		Looped = true,
		RollOffMode = Enum.RollOffMode.InverseTapered,
		RollOffMinDistance = 10,
		RollOffMaxDistance = 80,
	},
	["Wave Crash"] = {
		SoundId = 79068891226084,
		Volume = 1,
		Pitch = 1,
		PlaybackSpeed = 1,
		Looped = true,
		RollOffMode = Enum.RollOffMode.InverseTapered,
		RollOffMinDistance = 64,
		RollOffMaxDistance = 256,
	},
	["KartEngine"] = {
		SoundId = 9112787430,
		Volume = 2,
		Pitch = 1,
		PlaybackSpeed = 0.5,
		Looped = true,
		RollOffMode = Enum.RollOffMode.InverseTapered,
		RollOffMinDistance = 32,
		RollOffMaxDistance = 96,
	},
}

local function normalizeSoundId(soundId: string | number): string
	if typeof(soundId) == "number" then
		return "rbxassetid://" .. tostring(soundId)
	end

	if string.find(soundId, "rbxassetid://") == 1 then
		return soundId
	end

	return "rbxassetid://" .. soundId
end

local function getConfig(soundName: string): SoundSettings?
	local config = SoundService.Sounds[soundName]
	if not config then
		DebugModule.debugWarn("Missing sound config for " .. soundName, "SoundService")
		return nil
	end

	return config
end

local function applyProperties(sound: Sound, soundName: string, config: SoundSettings)
	sound.SoundId = normalizeSoundId(config.SoundId)
	sound.Volume = config.Volume or 1
	sound.PlaybackSpeed = config.PlaybackSpeed or config.Pitch or 1
	sound.Looped = config.Looped == true
	sound.Name = soundName

	if config.TimePosition then
		sound.TimePosition = config.TimePosition
	end

	if config.RollOffMode then
		sound.RollOffMode = config.RollOffMode
	end

	if config.RollOffMinDistance then
		sound.RollOffMinDistance = config.RollOffMinDistance
	end

	if config.RollOffMaxDistance then
		sound.RollOffMaxDistance = config.RollOffMaxDistance
	end
end

local function createSound(parent: Instance, soundName: string, overrideSettings: SoundSettings?): Sound?
	local baseConfig = getConfig(soundName)
	if not baseConfig then
		return nil
	end

	local mergedConfig = table.clone(baseConfig)
	if overrideSettings then
		for key, value in pairs(overrideSettings) do
			(mergedConfig :: any)[key] = value
		end
	end

	local sound = Instance.new("Sound")
	applyProperties(sound, soundName, mergedConfig)
	sound.Parent = parent

	return sound
end

local function getOrCreateCachedGuiSound(soundName: string): Sound?
	local existing = guiSoundFolder:FindFirstChild(soundName)
	if existing and existing:IsA("Sound") then
		return existing
	end

	local sound = createSound(guiSoundFolder, soundName)
	if not sound then
		return nil
	end

	return sound
end

function SoundService.RegisterSound(soundName: string, config: SoundSettings)
	SoundService.Sounds[soundName] = config
	DebugModule.debugPrint("Registered sound config for " .. soundName, "SoundService")
end

function SoundService.GetWorldMusicPlaylist(worldName: string?, playlistName: string?): { string | number }
	local selectedPlaylistName = playlistName or "LobbyMusicList"
	local worldConfig = if worldName then SoundService.WorldMusicPlaylists[worldName] else nil
	local playlist = worldConfig and worldConfig[selectedPlaylistName]
	if playlist and #playlist > 0 then
		return playlist
	end

	local fallbackConfig = SoundService.WorldMusicPlaylists.Fallback
	local fallbackPlaylist = fallbackConfig and fallbackConfig[selectedPlaylistName]
	if fallbackPlaylist and #fallbackPlaylist > 0 then
		return fallbackPlaylist
	end

	return {}
end

function SoundService.CreateSound(parent: Instance, soundName: string, overrideSettings: SoundSettings?): Sound?
	return createSound(parent, soundName, overrideSettings)
end

function SoundService.PlayGuiSound(soundName: string, parent: Instance?, overrideSettings: SoundSettings?): Sound?
	local baseConfig = getConfig(soundName)
	if not baseConfig then
		return nil
	end

	if parent == nil and overrideSettings == nil and not baseConfig.AllowOverlap then
		local cachedSound = getOrCreateCachedGuiSound(soundName)
		if not cachedSound then
			return nil
		end

		cachedSound:Stop()
		cachedSound.TimePosition = 0
		cachedSound:Play()
		return cachedSound
	end

	local targetParent = parent or RobloxSoundService
	local sound = createSound(targetParent, soundName, overrideSettings)
	if not sound then
		return nil
	end

	sound:Play()
	if not sound.Looped then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end

	return sound
end

function SoundService.PlayWorkspaceSound(soundName: string, parent: Instance, overrideSettings: SoundSettings?): Sound?
	local sound = createSound(parent, soundName, overrideSettings)
	if not sound then
		return nil
	end

	sound:Play()
	if not sound.Looped then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end

	return sound
end

function SoundService.StopSound(sound: Sound)
	sound:Stop()
end

function SoundService.FadeOutAndDestroy(sound: Sound, fadeTime: number)
	local tween = TweenService:Create(sound, TweenInfo.new(fadeTime), { Volume = 0 })
	tween:Play()
	tween.Completed:Once(function()
		sound:Stop()
		sound:Destroy()
	end)
end

return SoundService
