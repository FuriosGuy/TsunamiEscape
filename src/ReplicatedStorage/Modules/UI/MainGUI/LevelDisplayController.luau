local LevelDisplayController = {}
LevelDisplayController.__index = LevelDisplayController

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LEVEL_UP_PARTICLES = ReplicatedStorage:WaitForChild("Particles"):WaitForChild("LevelUp")
local LEVEL_UP_PARTICLE_SIZE_SCALE = 2

type ControllerOptions = {
	player: Player,
	visualFunctions: any,
	playerHandler: any,
	soundService: any,
	refreshRebirthReadyState: () -> (),
	tutorialSystem: any?,
	defaultMaxPlayerSpeed: number,
}

type Controller = {
	player: Player,
	visualFunctions: any,
	playerHandler: any,
	soundService: any,
	refreshRebirthReadyState: () -> (),
	tutorialSystem: any?,
	defaultMaxPlayerSpeed: number,
	lastLevel: number,
	lastMaxSpeed: number,
	hasSuppressedInitialLoadedLevel: boolean,
	alive: boolean,
}

local function getNumberAttribute(player: Player, attributeName: string, fallback: number): number
	local value = player:GetAttribute(attributeName)
	return if typeof(value) == "number" then value else fallback
end

local function emitLevelUpParticles(character: Model?): ()
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "LevelUpParticles"
	attachment.Position = Vector3.zero
	local emittersToFire: { { emitter: ParticleEmitter, count: number } } = {}
	local maximumLifetime = 0

	for _, descendant in LEVEL_UP_PARTICLES:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local emitter = descendant:Clone()
			local emitCount = emitter:GetAttribute("EmitCount")
			emitter.Enabled = false
			local sizeKeypoints = table.create(#emitter.Size.Keypoints)
			for _, keypoint in emitter.Size.Keypoints do
				table.insert(
					sizeKeypoints,
					NumberSequenceKeypoint.new(
						keypoint.Time,
						keypoint.Value * LEVEL_UP_PARTICLE_SIZE_SCALE,
						keypoint.Envelope * LEVEL_UP_PARTICLE_SIZE_SCALE
					)
				)
			end
			emitter.Size = NumberSequence.new(sizeKeypoints)
			emitter.Parent = attachment

			if typeof(emitCount) == "number" and emitCount >= 1 then
				table.insert(emittersToFire, {
					emitter = emitter,
					count = math.floor(emitCount),
				})
				maximumLifetime = math.max(maximumLifetime, emitter.Lifetime.Max)
			end
		end
	end

	if #emittersToFire == 0 then
		attachment:Destroy()
		return
	end

	attachment.Parent = rootPart
	for _, entry in emittersToFire do
		entry.emitter:Emit(entry.count)
	end
	Debris:AddItem(attachment, math.max(maximumLifetime + 0.5, 0.5))
end

function LevelDisplayController.new(options: ControllerOptions): Controller
	local player = options.player
	return setmetatable({
		player = player,
		visualFunctions = options.visualFunctions,
		playerHandler = options.playerHandler,
		soundService = options.soundService,
		refreshRebirthReadyState = options.refreshRebirthReadyState,
		tutorialSystem = options.tutorialSystem,
		defaultMaxPlayerSpeed = options.defaultMaxPlayerSpeed,
		lastLevel = getNumberAttribute(player, "CurrentLevel", 1),
		lastMaxSpeed = getNumberAttribute(player, "Max_Player_Speed", options.defaultMaxPlayerSpeed),
		hasSuppressedInitialLoadedLevel = false,
		alive = true,
	}, LevelDisplayController) :: Controller
end

function LevelDisplayController:SyncState(level: number, maxSpeed: number)
	if not self.alive then
		return
	end

	self.lastLevel = level
	self.lastMaxSpeed = maxSpeed
end

function LevelDisplayController:UpdateLevelDisplay()
	if not self.alive then
		return
	end

	local level = getNumberAttribute(self.player, "CurrentLevel", 1)
	local maxLevel = getNumberAttribute(self.player, "MaxLevel", 25)
	local rebirthMultiplier = getNumberAttribute(self.player, "Rebirth_XPMultiplier", 1)
	local maxSpeed = self.playerHandler.GetEffectiveMaxPlayerSpeed(self.player)

	self.visualFunctions.UpdateLevelLabel(level, maxLevel)
	self.visualFunctions.UpdateLevelProgressBar(level, maxLevel)
	self.visualFunctions.UpdateLevelNeededLabel(level, maxLevel)

	local isInitialLoadedJump = not self.hasSuppressedInitialLoadedLevel and level > self.lastLevel + 1
	if isInitialLoadedJump then
		self.hasSuppressedInitialLoadedLevel = true
	elseif level > self.lastLevel then
		self.soundService.PlayGuiSound("LevelUp")
		self.visualFunctions.ShowLevelUpNotification(self.lastLevel, level, self.lastMaxSpeed, maxSpeed)
		emitLevelUpParticles(self.player.Character)
	end

	self.lastLevel = level
	self.lastMaxSpeed = maxSpeed
	local nextStats = self.playerHandler.GetNextRebirthStats(self.player)
	self.visualFunctions.UpdateRebirthPreview(
		rebirthMultiplier,
		nextStats.NextMultiplier,
		maxLevel,
		nextStats.NextMaxLevel
	)
	self.refreshRebirthReadyState()

	if self.tutorialSystem then
		self.tutorialSystem:OnProgressChanged()
	end
end

function LevelDisplayController:UpdateMaxSpeedDisplay()
	if not self.alive then
		return
	end

	local maxSpeed = self.playerHandler.GetEffectiveMaxPlayerSpeed(self.player)
	self.visualFunctions.UpdateMaxSpeedLabel(maxSpeed)
	self.lastMaxSpeed = maxSpeed
end

function LevelDisplayController:GetLevelUpdateHandler(): () -> ()
	return function()
		self:UpdateLevelDisplay()
	end
end

function LevelDisplayController:GetMaxSpeedUpdateHandler(): () -> ()
	return function()
		self:UpdateMaxSpeedDisplay()
	end
end

function LevelDisplayController:Destroy()
	if not self.alive then
		return
	end

	self.alive = false
	self.tutorialSystem = nil
	self.refreshRebirthReadyState = function() end
end

return LevelDisplayController
