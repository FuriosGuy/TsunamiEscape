-- DebugModule.luau

local DebugModule = {}
local runtimeModuleOverrides: { [string]: boolean } = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CoreConfig = require(ReplicatedStorage.Modules.Config.CoreConfig)
local DEFAULT_DEBUG_SETTINGS = {
	enabled = true,
	showPrints = true,
	showWarns = true,
	validationWarns = false,
	showErrors = true,
	timestamp = true,
	-- Fail closed if the shared config is missing or incomplete.
	studioOnly = true,
}

local function getDebugSettings()
	return CoreConfig.debugSystem or DEFAULT_DEBUG_SETTINGS
end

local function normalizeModuleName(moduleName: string?): string?
	if typeof(moduleName) ~= "string" or moduleName == "" then
		return nil
	end

	return moduleName
end

local function listContainsModule(moduleList: { any }?, moduleName: string): boolean
	if typeof(moduleList) ~= "table" then
		return false
	end

	for _, entry in ipairs(moduleList) do
		if entry == moduleName then
			return true
		end
	end

	return false
end

local function shouldLogModule(settings: any, moduleName: string?, bypassStudioOnly: boolean?): boolean
	if not bypassStudioOnly and settings.studioOnly == true and not RunService:IsStudio() then
		return false
	end

	local normalizedModuleName = normalizeModuleName(moduleName)
	if not normalizedModuleName then
		return true
	end

	local runtimeOverride = runtimeModuleOverrides[normalizedModuleName]
	if runtimeOverride ~= nil then
		return runtimeOverride
	end

	if settings.moduleOverrides and typeof(settings.moduleOverrides) == "table" then
		local configuredOverride = settings.moduleOverrides[normalizedModuleName]
		if typeof(configuredOverride) == "boolean" then
			return configuredOverride
		end
	end

	if listContainsModule(settings.disabledModules, normalizedModuleName) then
		return false
	end

	local hasTargetedModules = typeof(settings.enabledModules) == "table" and #settings.enabledModules > 0
	if hasTargetedModules then
		return listContainsModule(settings.enabledModules, normalizedModuleName)
	end

	return true
end

-- Format timestamp for debug messages
local function getTimestamp()
	if not getDebugSettings().timestamp then
		return ""
	end

	local time = os.date("*t")
	local formatted = string.format("%02d:%02d:%02d", time.hour, time.min, time.sec)
	return formatted .. "   ▶ "
end

-- Debug print function
function DebugModule.debugPrint(message, moduleName)
	local settings = getDebugSettings()
	if not settings.enabled or not settings.showPrints or not shouldLogModule(settings, moduleName) then
		return
	end

	local prefix = moduleName and "[" .. moduleName .. "] " or "[Debug] "
	print(getTimestamp() .. prefix .. tostring(message))
end

-- Debug warn function
function DebugModule.debugWarn(message, moduleName)
	local settings = getDebugSettings()
	if not settings.enabled or not settings.showWarns or not shouldLogModule(settings, moduleName) then
		return
	end

	local prefix = moduleName and "[" .. moduleName .. "] " or "[Debug] "
	warn(getTimestamp() .. prefix .. tostring(message))
end

-- Validation warnings have a separate gate because server-side validation may
-- need to be observed in live servers even when ordinary debug output is Studio-only.
function DebugModule.validationWarn(message, moduleName)
	local settings = getDebugSettings()
	if
		not settings.enabled
		or settings.validationWarns ~= true
		or not settings.showWarns
		or not shouldLogModule(settings, moduleName, true)
	then
		return
	end

	local prefix = moduleName and "[Validation:" .. moduleName .. "] " or "[Validation] "
	warn(getTimestamp() .. prefix .. tostring(message))
end

-- Debug error function
function DebugModule.debugError(message, errorDetails, moduleName)
	local settings = getDebugSettings()
	if not settings.enabled or not settings.showErrors or not shouldLogModule(settings, moduleName) then
		return
	end

	local prefix = moduleName and "[" .. moduleName .. "] " or "[Debug] "
	local fullMessage = prefix .. tostring(message)
	if errorDetails then
		fullMessage = fullMessage .. " - Details: " .. tostring(errorDetails)
	end

	error(getTimestamp() .. fullMessage)
end

-- Debug info function (alias for debugPrint)
function DebugModule.debugInfo(message, moduleName)
	DebugModule.debugPrint(message, moduleName)
end

-- Debug trace function for detailed debugging
function DebugModule.debugTrace(message, data, moduleName)
	local settings = getDebugSettings()
	if not settings.enabled or not settings.showPrints or not shouldLogModule(settings, moduleName) then
		return
	end

	local prefix = moduleName and "[" .. moduleName .. "] " or "[Debug] "
	local traceMessage = getTimestamp() .. prefix .. "TRACE: " .. tostring(message)

	if data then
		if typeof(data) == "table" then
			traceMessage = traceMessage .. " | Data: " .. game:GetService("HttpService"):JSONEncode(data)
		else
			traceMessage = traceMessage .. " | Data: " .. tostring(data)
		end
	end

	print(traceMessage)
end

-- Check if debug is enabled
function DebugModule.isEnabled()
	local settings = getDebugSettings()
	if settings.studioOnly == true and not RunService:IsStudio() then
		return false
	end
	return settings.enabled
end

-- Get current debug settings
function DebugModule.getSettings()
	return getDebugSettings()
end

function DebugModule.setModuleEnabled(moduleName: string, isEnabled: boolean)
	local normalizedModuleName = normalizeModuleName(moduleName)
	if not normalizedModuleName then
		return
	end

	runtimeModuleOverrides[normalizedModuleName] = isEnabled
end

function DebugModule.clearModuleOverride(moduleName: string)
	local normalizedModuleName = normalizeModuleName(moduleName)
	if not normalizedModuleName then
		return
	end

	runtimeModuleOverrides[normalizedModuleName] = nil
end

function DebugModule.clearAllModuleOverrides()
	table.clear(runtimeModuleOverrides)
end

function DebugModule.getModuleOverrides(): { [string]: boolean }
	return table.clone(runtimeModuleOverrides)
end

return DebugModule
