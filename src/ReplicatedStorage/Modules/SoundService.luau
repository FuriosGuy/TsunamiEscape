local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RobloxSoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local TweenConfig = require(ReplicatedStorage.Modules.UI.TweenConfig)

local SoundService = {}
local guiSoundFolder: Folder? = nil
type SoundPreloadState = "loading" | "loaded" | "failed"
local preloadStates: { [string]: SoundPreloadState } = {}
if RunService:IsClient() then
	guiSoundFolder = Instance.new("Folder")
	guiSoundFolder.Name = "GuiSounds"
	guiSoundFolder.Parent = RobloxSoundService
end

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

export type SoundOverrides = {
	SoundId: (string | number)?,
	Volume: number?,
	Pitch: number?,
	PlaybackSpeed: number?,
	Looped: boolean?,
	RollOffMode: Enum.RollOffMode?,
	RollOffMinDistance: number?,
	RollOffMaxDistance: number?,
	TimePosition: number?,
}

-- SoundId and playback defaults live on ReplicatedStorage.Sounds templates.
SoundService.Sounds = {
	Click = { AllowOverlap = false },
	Pop = { AllowOverlap = true },
	Close = { AllowOverlap = false },
	BellRing = { AllowOverlap = false },
	Success = { AllowOverlap = false },
	Hover = { AllowOverlap = false },
	LevelUp = { AllowOverlap = true },
	Rebirth = { AllowOverlap = true },
	WinReward = { AllowOverlap = true },
	BloodmoonRise = { AllowOverlap = false },
	NeonRushRise = { AllowOverlap = false },
	Confetti = { AllowOverlap = true },
	Swish = { AllowOverlap = true },
	LuckyBlockFallWhoosh = { AllowOverlap = false },
	LuckyBlockImpact = { AllowOverlap = false },
	LuckyBlockThump = { AllowOverlap = false },
	LuckyBlockReward = { AllowOverlap = true },
	AmbientLoop = { AllowOverlap = false },
	["Wave Crash"] = { AllowOverlap = false },
	KartEngine = { AllowOverlap = false },
}

local registeredConfigs: { [string]: SoundSettings } = {}

local function normalizeSoundId(soundId: string | number): string
	if typeof(soundId) == "number" then
		return "rbxassetid://" .. tostring(soundId)
	end

	if string.find(soundId, "rbxassetid://") == 1 then
		return soundId
	end

	return "rbxassetid://" .. soundId
end

local function getSoundAssetKey(soundId: string | number): string
	local normalizedId = normalizeSoundId(soundId)
	return string.gsub(normalizedId, "^rbxassetid://", "")
end

local function getSoundTemplate(soundName: string): Sound?
	local folder = ReplicatedStorage:FindFirstChild("Sounds")
	local template = folder and folder:FindFirstChild(soundName)
	if template and template:IsA("Sound") then
		return template
	end
	return nil
end

local function applyProperties(sound: Sound, soundName: string, config: SoundSettings)
	sound.SoundId = normalizeSoundId(config.SoundId)
	sound.Volume = if config.Volume ~= nil then config.Volume else 1
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

local function applyOverrides(sound: Sound, overrides: SoundOverrides): ()
	if overrides.SoundId ~= nil then
		sound.SoundId = normalizeSoundId(overrides.SoundId)
	end
	if overrides.Volume ~= nil then
		sound.Volume = overrides.Volume
	end
	local playbackSpeed = overrides.PlaybackSpeed or overrides.Pitch
	if playbackSpeed ~= nil then
		sound.PlaybackSpeed = playbackSpeed
	end
	if overrides.Looped ~= nil then
		sound.Looped = overrides.Looped
	end
	if overrides.TimePosition ~= nil then
		sound.TimePosition = overrides.TimePosition
	end
	if overrides.RollOffMode ~= nil then
		sound.RollOffMode = overrides.RollOffMode
	end
	if overrides.RollOffMinDistance ~= nil then
		sound.RollOffMinDistance = overrides.RollOffMinDistance
	end
	if overrides.RollOffMaxDistance ~= nil then
		sound.RollOffMaxDistance = overrides.RollOffMaxDistance
	end
end

local function createSound(parent: Instance, soundName: string, overrideSettings: SoundOverrides?): Sound?
	local registeredConfig = registeredConfigs[soundName]
	local template = getSoundTemplate(soundName)
	if not registeredConfig and not template then
		DebugModule.debugWarn("Missing sound template/config for " .. soundName, "SoundService")
		return nil
	end

	local sound: Sound
	if registeredConfig then
		sound = Instance.new("Sound")
		applyProperties(sound, soundName, registeredConfig)
	else
		sound = (template :: Sound):Clone()
		sound.Name = soundName
	end
	if overrideSettings then
		applyOverrides(sound, overrideSettings)
	end
	sound.Parent = parent

	return sound
end

local function getOrCreateCachedGuiSound(soundName: string): Sound?
	if not guiSoundFolder then
		return nil
	end

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

local function preloadSoundInstances(sounds: { Sound })
	local fetchedStates: { [string]: Enum.AssetFetchStatus } = {}
	local succeeded, failureMessage = pcall(function()
		ContentProvider:PreloadAsync(sounds, function(contentId: string, status: Enum.AssetFetchStatus)
			fetchedStates[getSoundAssetKey(contentId)] = status
		end)
	end)
	return fetchedStates, succeeded, failureMessage
end

local function preloadSounds(soundNames: { string }): ()
	if not RunService:IsClient() then
		return
	end

	local soundsByAsset: { [string]: Sound } = {}
	for _, soundName in ipairs(soundNames) do
		local sound = getOrCreateCachedGuiSound(soundName)
		if not sound then
			continue
		end

		local assetKey = getSoundAssetKey(sound.SoundId)
		if assetKey == "0" or preloadStates[assetKey] == "loaded" or preloadStates[assetKey] == "loading" then
			continue
		end
		if sound.IsLoaded then
			preloadStates[assetKey] = "loaded"
			continue
		end

		preloadStates[assetKey] = "loading"
		soundsByAsset[assetKey] = sound
	end

	if next(soundsByAsset) == nil then
		return
	end
	local soundsToPreload: { Sound } = {}
	for _, sound in pairs(soundsByAsset) do
		table.insert(soundsToPreload, sound)
	end

	task.spawn(function()
		local fetchedStates, succeeded, failureMessage = preloadSoundInstances(soundsToPreload)

		local loadedNames: { string } = {}
		for assetKey, sound in pairs(soundsByAsset) do
			local fetchStatus = fetchedStates[assetKey]
			if succeeded and (fetchStatus == Enum.AssetFetchStatus.Success or sound.IsLoaded) then
				preloadStates[assetKey] = "loaded"
				table.insert(loadedNames, sound.Name)
			else
				preloadStates[assetKey] = "failed"
				DebugModule.debugWarn(
					"Sound preload failed | name="
						.. sound.Name
						.. " | SoundId="
						.. sound.SoundId
						.. " | status="
						.. tostring(fetchStatus)
						.. " | error="
						.. tostring(failureMessage),
					"SoundService"
				)
			end
		end
		if #loadedNames > 0 then
			DebugModule.debugPrint(
				"Preloaded " .. tostring(#loadedNames) .. " sounds | names=" .. table.concat(loadedNames, ", "),
				"SoundService"
			)
		end
	end)
end

function SoundService.RegisterSound(soundName: string, config: SoundSettings)
	registeredConfigs[soundName] = config
	SoundService.Sounds[soundName] = { AllowOverlap = config.AllowOverlap }
	local oldCachedSound = if guiSoundFolder then guiSoundFolder:FindFirstChild(soundName) else nil
	if oldCachedSound and oldCachedSound:IsA("Sound") then
		applyProperties(oldCachedSound, soundName, config)
	end
	DebugModule.debugPrint("Registered sound config for " .. soundName, "SoundService")
end

function SoundService.PreloadSounds(soundNames: { string }): ()
	preloadSounds(soundNames)
end

function SoundService.PreloadSoundInstance(sound: Sound): boolean
	if not RunService:IsClient() then
		return false
	end
	if sound.IsLoaded then
		return true
	end

	local assetKey = getSoundAssetKey(sound.SoundId)
	local fetchedStates, succeeded, failureMessage = preloadSoundInstances({ sound })
	local fetchStatus = fetchedStates[assetKey]
	local loaded = succeeded and (fetchStatus == Enum.AssetFetchStatus.Success or sound.IsLoaded)
	if loaded then
		preloadStates[assetKey] = "loaded"
		return true
	end

	preloadStates[assetKey] = "failed"
	DebugModule.debugWarn(
		"Sound preload failed | name="
			.. sound.Name
			.. " | SoundId="
			.. sound.SoundId
			.. " | status="
			.. tostring(fetchStatus)
			.. " | error="
			.. tostring(failureMessage),
		"SoundService"
	)
	return false
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

function SoundService.CreateSound(parent: Instance, soundName: string, overrideSettings: SoundOverrides?): Sound?
	return createSound(parent, soundName, overrideSettings)
end

function SoundService.PlayGuiSound(soundName: string, parent: Instance?, overrideSettings: SoundOverrides?): Sound?
	local soundPolicy = SoundService.Sounds[soundName]
	if parent == nil and overrideSettings == nil and not (soundPolicy and soundPolicy.AllowOverlap) then
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

function SoundService.PlayWorkspaceSound(soundName: string, parent: Instance, overrideSettings: SoundOverrides?): Sound?
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
	local tween = TweenService:Create(sound, TweenConfig.WithDuration(fadeTime, TweenConfig.MusicFade), { Volume = 0 })
	tween:Play()
	tween.Completed:Once(function()
		sound:Stop()
		sound:Destroy()
	end)
end

if RunService:IsClient() then
	SoundService.PreloadSounds({
		"Click",
		"Pop",
		"Close",
		"BellRing",
		"Success",
		"Hover",
		"LevelUp",
		"Rebirth",
		"WinReward",
		"Confetti",
		"Swish",
		"LuckyBlockFallWhoosh",
		"LuckyBlockImpact",
		"LuckyBlockThump",
		"LuckyBlockReward",
	})
end

return SoundService
