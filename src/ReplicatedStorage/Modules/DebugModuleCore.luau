local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

type SettingsProvider = () -> any

local DebugModuleCore = {}

function DebugModuleCore.new(getSettings: SettingsProvider): { [string]: any }
	local DebugModule: { [string]: any } = {}
	local runtimeModuleOverrides: { [string]: boolean } = {}
	local defaultSettings = {
		enabled = true,
		showPrints = true,
		showWarns = true,
		validationWarns = false,
		showErrors = true,
		timestamp = true,
		studioOnly = true,
	}

	local function resolveSettings(): any
		local settings = getSettings()
		return if typeof(settings) == "table" then settings else defaultSettings
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

		if typeof(settings.moduleOverrides) == "table" then
			local configuredOverride = settings.moduleOverrides[normalizedModuleName]
			if typeof(configuredOverride) == "boolean" then
				return configuredOverride
			end
		end

		if listContainsModule(settings.disabledModules, normalizedModuleName) then
			return false
		end

		local hasTargetedModules = typeof(settings.enabledModules) == "table" and #settings.enabledModules > 0
		return if hasTargetedModules then listContainsModule(settings.enabledModules, normalizedModuleName) else true
	end

	local function getTimestamp(): string
		if resolveSettings().timestamp ~= true then
			return ""
		end

		local time = os.date("*t")
		return string.format("%02d:%02d:%02d   ▶ ", time.hour, time.min, time.sec)
	end

	local function getPrefix(moduleName: string?): string
		return if moduleName then "[" .. moduleName .. "] " else "[Debug] "
	end

	function DebugModule.debugPrint(message: any, moduleName: string?)
		local settings = resolveSettings()
		if not settings.enabled or not settings.showPrints or not shouldLogModule(settings, moduleName) then
			return
		end
		print(getTimestamp() .. getPrefix(moduleName) .. tostring(message))
	end

	function DebugModule.debugWarn(message: any, moduleName: string?)
		local settings = resolveSettings()
		if not settings.enabled or not settings.showWarns or not shouldLogModule(settings, moduleName) then
			return
		end
		warn(getTimestamp() .. getPrefix(moduleName) .. tostring(message))
	end

	function DebugModule.validationWarn(message: any, moduleName: string?)
		local settings = resolveSettings()
		if
			not settings.enabled
			or settings.validationWarns ~= true
			or not settings.showWarns
			or not shouldLogModule(settings, moduleName, true)
		then
			return
		end

		local prefix = if moduleName then "[Validation:" .. moduleName .. "] " else "[Validation] "
		warn(getTimestamp() .. prefix .. tostring(message))
	end

	function DebugModule.debugError(message: any, errorDetails: any, moduleName: string?)
		local settings = resolveSettings()
		if not settings.enabled or not settings.showErrors or not shouldLogModule(settings, moduleName) then
			return
		end

		local fullMessage = getPrefix(moduleName) .. tostring(message)
		if errorDetails ~= nil then
			fullMessage ..= " - Details: " .. tostring(errorDetails)
		end
		-- Keep diagnostics from aborting the gameplay path that reported them.
		warn(getTimestamp() .. "[Error] " .. fullMessage)
	end

	function DebugModule.debugInfo(message: any, moduleName: string?)
		DebugModule.debugPrint(message, moduleName)
	end

	function DebugModule.debugTrace(message: any, data: any, moduleName: string?)
		local settings = resolveSettings()
		if not settings.enabled or not settings.showPrints or not shouldLogModule(settings, moduleName) then
			return
		end

		local traceMessage = getTimestamp() .. getPrefix(moduleName) .. "TRACE: " .. tostring(message)
		if data ~= nil then
			local serialized = if typeof(data) == "table" then HttpService:JSONEncode(data) else tostring(data)
			traceMessage ..= " | Data: " .. serialized
		end
		print(traceMessage)
	end

	function DebugModule.isEnabled(): boolean
		local settings = resolveSettings()
		return settings.enabled == true and (settings.studioOnly ~= true or RunService:IsStudio())
	end

	function DebugModule.getSettings(): any
		return resolveSettings()
	end

	function DebugModule.setModuleEnabled(moduleName: string, isEnabled: boolean)
		local normalizedModuleName = normalizeModuleName(moduleName)
		if normalizedModuleName then
			runtimeModuleOverrides[normalizedModuleName] = isEnabled
		end
	end

	function DebugModule.clearModuleOverride(moduleName: string)
		runtimeModuleOverrides[normalizeModuleName(moduleName) or ""] = nil
	end

	function DebugModule.clearAllModuleOverrides()
		table.clear(runtimeModuleOverrides)
	end

	function DebugModule.getModuleOverrides(): { [string]: boolean }
		return table.clone(runtimeModuleOverrides)
	end

	return DebugModule
end

return DebugModuleCore
