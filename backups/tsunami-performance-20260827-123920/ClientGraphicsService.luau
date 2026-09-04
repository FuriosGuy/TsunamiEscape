--!strict

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local ClientCullingService = require(ReplicatedStorage.Modules.ClientCullingService)

local ClientGraphicsService = {}
local isInitialized = false
local originalGlobalShadows: boolean? = nil

local function isMobileClient(): boolean
	-- Mobile heuristic: touch-first devices without keyboard/mouse availability.
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

function ClientGraphicsService.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	if not RunService:IsClient() then
		return
	end

	local config = CoreConfig.clientGraphics
	if typeof(config) ~= "table" then
		return
	end

	if config.disableGlobalShadowsOnMobile == true and isMobileClient() then
		if originalGlobalShadows == nil then
			originalGlobalShadows = Lighting.GlobalShadows
		end
		Lighting.GlobalShadows = false
		DebugModule.debugInfo("Applied mobile graphics override: GlobalShadows=false", "ClientGraphicsService")
	end

	ClientCullingService.Start()
end

function ClientGraphicsService.Shutdown()
	if not isInitialized then
		return
	end

	ClientCullingService.Stop()
	if originalGlobalShadows ~= nil then
		Lighting.GlobalShadows = originalGlobalShadows
		originalGlobalShadows = nil
	end
	isInitialized = false
end

return ClientGraphicsService
