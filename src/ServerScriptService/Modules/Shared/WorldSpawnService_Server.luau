--!strict

local Workspace = game:GetService("Workspace")

local WorldSpawnService = {}

export type SpawnLocation = Model | BasePart

local function isSpawnLocation(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("Model") or instance:IsA("BasePart"))
end

local function findNestedSpawnLocation(container: Instance): SpawnLocation?
	local nestedSpawnLocation = container:FindFirstChild("SpawnLocation", true)
	if isSpawnLocation(nestedSpawnLocation) then
		return nestedSpawnLocation :: SpawnLocation
	end

	return nil
end

function WorldSpawnService.Get(worldName: string): SpawnLocation?
	local worldsFolder = Workspace:FindFirstChild("Worlds")
	local worldFolder = worldsFolder and worldsFolder:FindFirstChild(worldName)
	if not worldFolder then
		return nil
	end

	local spawnContainer = worldFolder:FindFirstChild("SpawnLocation")
	if spawnContainer and spawnContainer:IsA("Model") then
		return findNestedSpawnLocation(spawnContainer) or spawnContainer
	end
	if isSpawnLocation(spawnContainer) then
		return spawnContainer :: SpawnLocation
	end

	return findNestedSpawnLocation(worldFolder)
end

return WorldSpawnService
