--!strict
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local PlayerHandler = require(ReplicatedStorage.Modules.PlayerHandler)

local ValidationService = {}

local function resetPlayerToWorldSpawn(player: Player)
	local currentWorld = player:GetAttribute("Current_World")
	if typeof(currentWorld) ~= "string" or currentWorld == "" then
		currentWorld = "World1"
	end

	player:SetAttribute("CurrentStage", 0)

	local character = player.Character
	if not character then
		return
	end

	local worldsFolder = Workspace:FindFirstChild("Worlds")
	local worldFolder = worldsFolder and worldsFolder:FindFirstChild(currentWorld)
	local spawnLocation = worldFolder and worldFolder:FindFirstChild("SpawnLocation")
	if spawnLocation and spawnLocation:IsA("BasePart") then
		character:PivotTo(spawnLocation:GetPivot() * CFrame.new(0, 3, 0))
	end
end

function ValidationService.GetAliveHumanoid(character: Model?): Humanoid?
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return humanoid
end

function ValidationService.IsCharacterAlive(character: Model?): boolean
	return ValidationService.GetAliveHumanoid(character) ~= nil
end

function ValidationService.IsPlayerAlive(player: Player?): boolean
	if not player then
		return false
	end

	return ValidationService.IsCharacterAlive(player.Character)
end

function ValidationService.GetAlivePlayerFromTouch(hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player or not ValidationService.IsPlayerAlive(player) then
		return nil
	end

	return player
end

--[[
    Verifies if a player is authorized to be in a specific world.
    Kicks player if mismatch is detected.
]]
function ValidationService.ValidateWorldAccess(player: Player, expectedWorld: string): boolean
	local currentWorld = player:GetAttribute("Current_World")

	if currentWorld ~= expectedWorld then
		DebugModule.debugWarn(
			string.format(
				"Player %s attempted to interact with %s but is in %s",
				player.Name,
				expectedWorld,
				tostring(currentWorld)
			),
			"ValidationService"
		)
		player:Kick("Invalid world interaction detected")
		return false
	end

	return true
end

--[[
    Centralized check for suspicious movement speed.
]]
function ValidationService.ValidateSpeed(player: Player, reportedSpeed: number): boolean
	local maxAllowed = PlayerHandler.GetEffectiveMaxPlayerSpeed(player)
	local buffer = 5 -- Allow for slight network/physics variation

	if reportedSpeed > (maxAllowed + buffer) then
		DebugModule.debugWarn(
			string.format("Player %s reported speed %d (Max allowed: %d)", player.Name, reportedSpeed, maxAllowed),
			"ValidationService"
		)
		player:Kick("Speed modification detected")
		return false
	end

	return true
end

function ValidationService.ValidateWinButtonStage(player: Player, requiredStage: number): boolean
	local currentStage = player:GetAttribute("CurrentStage")
	if typeof(currentStage) ~= "number" then
		currentStage = 0
	end

	if requiredStage > currentStage then
		DebugModule.debugWarn(
			string.format(
				"Player %s tried to skip ahead to WinButton stage %d while on stage %d",
				player.Name,
				requiredStage,
				currentStage
			),
			"ValidationService"
		)
		resetPlayerToWorldSpawn(player)
		return false
	end

	return true
end

return ValidationService
