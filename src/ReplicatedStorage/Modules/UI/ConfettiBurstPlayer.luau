--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfettiController = require(ReplicatedStorage.Modules.UI:WaitForChild("ConfettiController"))

export type ConfettiBurstPlayer = {
	PlayBurst: (
		self: ConfettiBurstPlayer,
		colors: { Color3 }?,
		duration: number?,
		totalCount: number?,
		batchSize: number?,
		batchDelay: number?
	) -> (),
	Reset: (self: ConfettiBurstPlayer) -> (),
	Destroy: (self: ConfettiBurstPlayer) -> (),
}

type ConfettiBurstPlayerInternal = ConfettiBurstPlayer & {
	_container: GuiObject,
	_emitter: any,
	_renderConnection: RBXScriptConnection?,
	_destroyed: boolean,
}

local ConfettiBurstPlayer = {}
ConfettiBurstPlayer.__index = ConfettiBurstPlayer

local singleton: ConfettiBurstPlayerInternal? = nil

local function startLoop(self: ConfettiBurstPlayerInternal)
	if self._renderConnection then
		return
	end

	self._renderConnection = RunService.RenderStepped:Connect(function(deltaTime)
		self._emitter:Update(deltaTime)
		if not self._emitter:IsActive() and self._renderConnection then
			self._renderConnection:Disconnect()
			self._renderConnection = nil
		end
	end)
end

function ConfettiBurstPlayer.new(container: GuiObject): ConfettiBurstPlayer
	local self = setmetatable({
		_container = container,
		_emitter = ConfettiController.new(container, 40),
		_renderConnection = nil,
		_destroyed = false,
	}, ConfettiBurstPlayer) :: ConfettiBurstPlayerInternal

	return self
end

function ConfettiBurstPlayer.GetOrCreateSingleton(container: GuiObject?): ConfettiBurstPlayer?
	if not container then
		return nil
	end

	if singleton and singleton._destroyed then
		singleton = nil
	end

	if singleton and singleton._container == container and container.Parent ~= nil then
		return singleton
	end

	if singleton then
		singleton:Destroy()
		singleton = nil
	end

	singleton = ConfettiBurstPlayer.new(container) :: ConfettiBurstPlayerInternal
	return singleton
end

function ConfettiBurstPlayer:PlayBurst(
	colors: { Color3 }?,
	duration: number?,
	totalCount: number?,
	batchSize: number?,
	batchDelay: number?
)
	local selfInternal = self :: ConfettiBurstPlayerInternal
	if selfInternal._destroyed then
		return
	end

	selfInternal._emitter:Reset()
	selfInternal._emitter:PlayBurst(colors, duration, totalCount, batchSize, batchDelay)
	startLoop(selfInternal)
end

function ConfettiBurstPlayer:Reset()
	local selfInternal = self :: ConfettiBurstPlayerInternal
	if selfInternal._destroyed then
		return
	end

	selfInternal._emitter:Reset()
	if selfInternal._renderConnection then
		selfInternal._renderConnection:Disconnect()
		selfInternal._renderConnection = nil
	end
end

function ConfettiBurstPlayer:Destroy()
	local selfInternal = self :: ConfettiBurstPlayerInternal
	if selfInternal._destroyed then
		return
	end

	selfInternal._destroyed = true

	if selfInternal._renderConnection then
		selfInternal._renderConnection:Disconnect()
		selfInternal._renderConnection = nil
	end

	selfInternal._emitter:Destroy()

	if singleton == selfInternal then
		singleton = nil
	end
end

return ConfettiBurstPlayer
