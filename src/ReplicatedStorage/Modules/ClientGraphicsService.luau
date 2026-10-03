local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Shared.CoreConfig_Client)
local ClientDeviceProfile = require(ReplicatedStorage.Modules.ClientDeviceProfile)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local ClientCullingService = require(ReplicatedStorage.Modules.ClientCullingService)
local EnvironmentService = require(ReplicatedStorage.Modules.EnvironmentService)
local LiveEventWorldVisualService = require(ReplicatedStorage.Modules.LiveEventWorldVisualService)
local TsunamiVisualService = require(ReplicatedStorage.Modules.TsunamiVisualService)

local ClientGraphicsService = {}
local isInitialized = false
local originalGlobalShadows: boolean? = nil

function ClientGraphicsService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	if not RunService:IsClient() then
		return
	end

	EnvironmentService.Start()
	LiveEventWorldVisualService.Start()

	local config = CoreConfig.clientGraphics
	if typeof(config) ~= "table" then
		return
	end

	if config.disableGlobalShadowsOnMobile == true and ClientDeviceProfile.IsMobile() then
		if originalGlobalShadows == nil then
			originalGlobalShadows = Lighting.GlobalShadows
		end
		Lighting.GlobalShadows = false
		EnvironmentService.SetGlobalShadowsOverride(false)
		DebugModule.debugInfo("Applied mobile graphics override: GlobalShadows=false", "ClientGraphicsService")
	end

	ClientCullingService.Start()
	TsunamiVisualService.Start()
end

function ClientGraphicsService.Shutdown()
	if not isInitialized then
		return
	end

	ClientCullingService.Stop()
	TsunamiVisualService.Stop()
	LiveEventWorldVisualService.Stop()
	EnvironmentService.SetGlobalShadowsOverride(nil)
	EnvironmentService.Stop()
	if originalGlobalShadows ~= nil then
		Lighting.GlobalShadows = originalGlobalShadows
		originalGlobalShadows = nil
	end
	isInitialized = false
end

return ClientGraphicsService
