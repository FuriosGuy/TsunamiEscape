--!strict

local UserInputService = game:GetService("UserInputService")

type DeviceKind = "Phone" | "Tablet" | "Desktop" | "Console" | "VR"

local ClientDeviceProfile = {}
local cachedDeviceKind: DeviceKind? = nil

local function getStudioDeviceKind(): DeviceKind?
	local serviceOk, service = pcall(function()
		return game:GetService("StudioDeviceSimulatorService")
	end)
	if not serviceOk then
		return nil
	end

	local deviceOk, deviceId = pcall(function()
		return (service :: any):GetDeviceAsync()
	end)
	if not deviceOk or typeof(deviceId) ~= "string" or deviceId == "default" then
		return nil
	end

	local infoOk, info = pcall(function()
		return (service :: any):GetDeviceInfoAsync(deviceId)
	end)
	if not infoOk or typeof(info) ~= "table" then
		return nil
	end

	local deviceForm = (info :: any).DeviceForm
	if deviceForm == Enum.DeviceForm.Phone then
		return "Phone"
	elseif deviceForm == Enum.DeviceForm.Tablet then
		return "Tablet"
	elseif deviceForm == Enum.DeviceForm.Console then
		return "Console"
	elseif deviceForm == Enum.DeviceForm.VR then
		return "VR"
	end

	return "Desktop"
end

local function resolveDeviceKind(): DeviceKind
	local studioDeviceKind = getStudioDeviceKind()
	if studioDeviceKind then
		return studioDeviceKind
	end

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled then
		return "Phone"
	end

	return "Desktop"
end

function ClientDeviceProfile.GetKind(): DeviceKind
	if cachedDeviceKind == nil then
		cachedDeviceKind = resolveDeviceKind()
	end

	return cachedDeviceKind
end

function ClientDeviceProfile.IsMobile(): boolean
	local deviceKind = ClientDeviceProfile.GetKind()
	return deviceKind == "Phone" or deviceKind == "Tablet"
end

return ClientDeviceProfile
