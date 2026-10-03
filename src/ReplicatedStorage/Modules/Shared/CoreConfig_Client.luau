-- CoreConfig_Client.luau

local CoreConfig = require(script.Parent:WaitForChild("CoreConfig_Shared"))

-- Performance configuration (universal)
CoreConfig.performance = {
	maxFrameTime = 1 / 60, -- Target frame time (60 FPS)
}

-- Client graphics overrides
CoreConfig.clientGraphics = {
	disableGlobalShadowsOnMobile = true, -- Disables Lighting.GlobalShadows for mobile clients to reduce render/shadowmap cost.
}

-- Client Bloodmoon ground visual that follows only grounded characters.
CoreConfig.bloodmoonParticle = {
	enabled = true, -- Shows the local BloodmoonParticle while the Bloodmoon environment is fully active.
	size = 512, -- Width and depth of the ground particle in studs.
	verticalOffset = -5, -- Ground probe depth below the player's root part before the floor lock is applied.
	positionUpdateFps = 15, -- Limits ground-following raycasts and CFrame writes.
	positionMovementThreshold = 2, -- Minimum grounded movement in studs before another position update.
	rotationThresholdDegrees = 20, -- Minimum grounded rotation before another orientation update.
	groundRaycastInterval = 0.25, -- Minimum time between ground raycasts while the player is moving.
	mobileRateMultiplier = 0.55, -- Stronger local event-particle reduction on Phone and Tablet clients.
}

-- Client environment transition settings.
CoreConfig.environment = {
	transitionDurationSeconds = 6, -- Duration for each supported environment tween.
	atmosphereLeadSeconds = 0.5, -- Starts atmosphere before ambient and remaining environment values.
}

-- World geometry tint overrides for active live events.
CoreConfig.eventWorldVisuals = {
	frostbiteRally = {
		enabled = true,
		eventId = "FrostbiteRally",
		targetColor = Color3.fromRGB(202, 203, 209),
	},
}

-- Client-side distance culling for non-gameplay visuals.
CoreConfig.clientCulling = {
	enabled = true, -- Master toggle for CollectionService-based client visual culling.
	updateInterval = 0.25, -- Seconds between culling visibility passes.
	mobileDistanceMultiplier = 0.65, -- Scales culling distances down on Phone and Tablet clients.
	mobileParticleDistanceMultiplier = 0.5, -- Tighter particle-only distance scale on Phone and Tablet clients.
	mobileParticleReducedRateMultiplier = 0.4, -- Lower reduced-rate particle budget on Phone and Tablet clients.
	autoTagBillboards = true, -- Automatically tags BillboardGuis so lobby labels can be culled by distance.
	autoTagSurfaceGuis = true, -- Automatically tags SurfaceGuis in Workspace so world panels can be culled by distance.
	autoTagDecorativeEffects = true, -- Automatically tags safe Workspace particles/lights/beams/trails for distance culling.
	billboardDistance = 450, -- BillboardGui distance before it is disabled.
	surfaceGuiDistance = 450, -- SurfaceGui distance before it is disabled.
	particleDistance = 260, -- ParticleEmitter distance before tagged emitters are disabled.
	particleReducedDistance = 140, -- ParticleEmitter distance before tagged emitters use reduced rate.
	particleReducedRateMultiplier = 0.55, -- Reduced-rate particle budget before full particle disable.
	cullHysteresisDistance = 24, -- Prevents visual pop-in when an object hovers near a cull boundary.
	lightDistance = 320, -- Light distance before tagged lights are disabled.
	beamDistance = 360, -- Beam distance before tagged beams are disabled.
	trailDistance = 300, -- Trail distance before tagged trails are disabled.
	autoTagDecorativeTextures = true, -- Culls only decorative Terrain, Decorations, and VIPRooms textures/decals.
	textureDistance = 600, -- Decorative Texture/Decal distance before local transparency is applied.
	autoCullDecorativeShadows = true, -- Culls CastShadow only on distant decorative Terrain, Decorations, and VIPRooms parts.
	shadowDistance = 400, -- Decorative part distance before local CastShadow is disabled.
	remoteTrailEnabled = true, -- Enables client-only quality budgeting for observed player trails.
	remoteTrailUpdateInterval = 0.25, -- Seconds between observed remote trail quality passes.
	remoteTrailMobileDistanceMultiplier = 0.65, -- Scales remote trail distances on Phone and Tablet clients.
	remoteTrailFullDistance = 120, -- Nearby remote trails retain full effect quality.
	remoteTrailDisableDistance = 360, -- Remote trails beyond this hard radius are disabled; mid-range trails are reduced.
	remoteTrailReducedRateMultiplier = 0.5, -- Rate applied to mid-range remote trail emitters.
	remoteTrailMaxVisiblePlayers = 6, -- Safety cap for active remote trail owners.
}

-- Client-owned tsunami visuals; server replicates state only, not moving geometry.
CoreConfig.clientTsunamiVisuals = {
	enabled = true, -- Master toggle for local tsunami visual reconstruction.
	billboardMaxDistance = 450, -- Maximum distance for tsunami labels.
	disableShadows = true, -- Avoid shadowmap work for cosmetic wave copies.
	soundGraceSeconds = 1.5, -- Late joins do not replay an old wave crash sound.
}

-- UI scaling safeguards (client)
CoreConfig.uiAdjuster = {
	referenceViewport = Vector2.new(1920, 1080), -- Baseline viewport used to compute UI scale ratio.
	minScaleRatio = 0.45, -- Prevents ultra-small scaling on narrow/tall device viewports.
	maxScaleRatio = 1.35, -- Prevents oversized scaling on large viewport extremes.
	noUpscaleOnMobile = true, -- Prevents mobile clients from scaling above baseline text/tile sizes.
	mobileMaxScaleRatio = 1.0, -- Effective max ratio when noUpscaleOnMobile is enabled.
	minTextSize = 2, -- Absolute floor for TextSize/UITextSizeConstraint calculations.
	minTileOffset = 1, -- TileSize offset floor to satisfy non-zero tile requirements.
}

-- Client-only debug toggles. Server authority remains in CoreConfig_Server.
CoreConfig.clientDebug = {
	dailyRewards = {
		debugSequentialClaimMode = true,
	},
	playtimeRewards = {
		debugSequentialClaimMode = true,
	},
}
-- Event board fallback for an event that is already active when a player joins.
CoreConfig.eventBoard = {
	activeEventId = "", -- Optional single-experience fallback when no universe-specific ID is configured.
	activeEventIdsByUniverse = {
		[9799168239] = "1575542102719333001", -- Active event fallback for +1 Speed DEV.
		[9824719186] = "3893769414042059370", -- Active event fallback for +1 Speed live.
	},
	eventThumbnailIdsByEvent = {
		-- SocialService can omit event thumbnail metadata at runtime, so keep a narrow fallback per event.
		["1575542102719333001"] = 104775788509568, -- +1 Speed DEV event thumbnail.
		["6019459865490096779"] = 137113910559154, -- +1 Speed live event thumbnail.
		["3893769414042059370"] = 95114581728373, -- ADMIN ABUSE live event thumbnail.
	},
	secondaryEventTitles = {
		-- EventBoard shows these only when no major event is active or upcoming.
		"2X WEEKEND",
	},
}

-- Timed purchase prompt configuration. Product IDs remain in ProductCatalog.
CoreConfig.promptBuy = {
	minDeaths = 3,
	maxDeaths = 5,
	minMinutes = 2,
	maxMinutes = 5,
	shortIntervalSelectionWeight = 2, -- Makes 2-3 minute rolls twice as likely as longer rolls.
	displayDurationSeconds = 10,
	temporaryBoostSelectionWeight = 4, -- Makes temporary boosts more likely in timed product prompts.
	bloodmoonKartSelectionWeight = 3, -- Blood Moon karts are strongly biased during the event.
	premiumPromptSelectionWeight = 1, -- Include Roblox Plus as a low-frequency random prompt offer.
	studioAlwaysShow = false, -- Studio-only prompt test; live servers still use death/time triggers.
	studioShowOwnedProducts = false, -- Studio-only preview: include already-owned permanent offers in the prompt.
	visiblePosition = UDim2.new(0.897, 0, 0.21, 0),
	hiddenPosition = UDim2.new(2, 0, 0.21, 0),
	premiumPrompt = {
		productImage = "rbxassetid://106963890821116",
		title = "ROBLOX PLUS",
		description = "Get permanent 1.25x XP Speed and Wins multipliers with Roblox Plus.",
	},
	excludedDevProductKeys = {
		ReturnToStage = true, -- Return-to-stage uses its own strict offer flow.
		TrollPlayer = true, -- Requires a selected target from TrollFrame.
		PetLuck2x = true, -- Cumulative luck tiers must only appear in the dedicated next-tier purchase flow.
		PetLuck4x = true,
		PetLuck6x = true,
		PetLuck8x = true,
		PetLuck10x = true,
	},
	-- Only Neon/Frostbite pet Lucky Block products require their event to be active; Blood Moon stays available.
		gatedDevProductKeyPrefixes = {
			PetNeonRushLuckyBlockRoll = "NeonRush",
			PetFrostbiteRallyLuckyBlockRoll = "FrostbiteRally",
	},
	permanentDevProductKeys = {
		GalaxyTrail = "Trail",
		DemonTrail = "Trail",
		GoldTrail = "Trail",
		PurpleTrail = "Trail",
		BlueTrail = "Trail",
		GreenTrail = "Trail",
	},
	descriptionPools = {
		Default = {
			"Power up your run and progress faster!",
			"Grab this boost and make your next run count!",
			"Upgrade your adventure with this special offer!",
		},
		Speed = {
			"Gain extra XP Speed and level up faster!",
			"Power up your speed progress with this offer!",
			"Reach higher levels faster with extra XP Speed!",
		},
		Wins = {
			"Get more wins and unlock better rewards faster!",
			"Add wins to your run and reach new karts sooner!",
			"Build your win count with this instant reward!",
		},
		Trail = {
			"Equip this trail for a permanent multiplier boost!",
			"Leave a brighter trail behind while powering up!",
			"Add this trail to your collection and progress faster!",
		},
		Treadmill = {
			"Power up treadmill gains with this permanent gamepass!",
			"Earn speed faster while using treadmills!",
			"Turn every treadmill run into faster progress!",
		},
		Kart = {
			"Unlock this kart and race with a bigger speed boost!",
			"Upgrade your ride and push toward faster progress!",
			"Add this kart to your collection and hit the track!",
		},
		TemporaryBoost = {
			"Activate 2x gains for 10 minutes and speed up your run!",
			"Temporarily double your progress and push ahead faster!",
			"Get 10 minutes of 2x power for your next run!",
		},
		Spin = {
			"Add spins and try your luck on the reward wheel!",
			"Get more wheel spins and chase exclusive rewards!",
			"Spin for a chance at powerful rewards and rare items!",
		},
		Utility = {
			"Use this boost to make your next run easier!",
			"Get a helpful advantage for your next challenge!",
			"Make faster progress with this useful upgrade!",
		},
	},
}

-- Get debug settings (for backward compatibility)
function CoreConfig.getDebugSettings()
	return CoreConfig.debugSystem
end

-- Check if debug is enabled
function CoreConfig.isDebugEnabled()
	return CoreConfig.debugSystem.enabled
end

-- Update debug settings at runtime
function CoreConfig.setDebugSettings(settings)
	for key, value in pairs(settings) do
		if CoreConfig.debugSystem[key] ~= nil then
			CoreConfig.debugSystem[key] = value
		end
	end
end

-- Get performance settings
function CoreConfig.getPerformanceSettings()
	return CoreConfig.performance
end

return CoreConfig
