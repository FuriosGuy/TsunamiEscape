-- Paste this entire file into the Roblox Studio Command Bar.
-- Server mode replicates the environment; edit/client mode applies it locally.

local TARGET_ENVIRONMENT = "Bloodmoon" -- "Default" or "Bloodmoon". Neon Rush also uses "Bloodmoon" visuals.
local HOLD_MANUAL_ENVIRONMENT = true -- Stops the live event scheduler from replacing this test value.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local environments = ReplicatedStorage:FindFirstChild("Environments")
if not environments or not environments:IsA("Folder") then
	warn("[EnvironmentChanger] ReplicatedStorage.Environments is missing.")
	return
end

local profile = environments:FindFirstChild(TARGET_ENVIRONMENT)
if not profile or not profile:IsA("Folder") then
	warn("[EnvironmentChanger] Environment profile does not exist: " .. TARGET_ENVIRONMENT)
	return
end

if RunService:IsServer() then
	local stateFolder = ReplicatedStorage:FindFirstChild("LiveEventState")
	if not stateFolder or not stateFolder:IsA("Folder") then
		warn("[EnvironmentChanger] LiveEventState is missing. Start a play session first.")
		return
	end

	if HOLD_MANUAL_ENVIRONMENT then
		local serverScriptService = game:GetService("ServerScriptService")
		local modules = serverScriptService:FindFirstChild("Modules")
		local liveEventModule = modules and modules:FindFirstChild("LiveEventService")
		if liveEventModule and liveEventModule:IsA("ModuleScript") then
			local success, liveEventService = pcall(require, liveEventModule)
			if success and type(liveEventService) == "table" and type(liveEventService.Destroy) == "function" then
				liveEventService.Destroy()
			else
				warn("[EnvironmentChanger] Could not stop LiveEventService; the scheduler may overwrite the test.")
			end
		end
	end

	stateFolder:SetAttribute("EnvironmentName", TARGET_ENVIRONMENT)
	print(
		"[EnvironmentChanger] Applied replicated environment: "
			.. TARGET_ENVIRONMENT
			.. " | manual hold="
			.. tostring(HOLD_MANUAL_ENVIRONMENT)
	)
	return
end

local environmentServiceModule = ReplicatedStorage.Modules:FindFirstChild("EnvironmentService")
if not environmentServiceModule or not environmentServiceModule:IsA("ModuleScript") then
	warn("[EnvironmentChanger] ReplicatedStorage.Modules.EnvironmentService is missing.")
	return
end

local success, environmentService = pcall(require, environmentServiceModule)
if not success or type(environmentService) ~= "table" or type(environmentService.ApplyForStudio) ~= "function" then
	warn("[EnvironmentChanger] EnvironmentService manual API is unavailable. Resync the latest project first.")
	return
end

environmentService.ApplyForStudio(TARGET_ENVIRONMENT)
print("[EnvironmentChanger] Applied local environment: " .. TARGET_ENVIRONMENT)
