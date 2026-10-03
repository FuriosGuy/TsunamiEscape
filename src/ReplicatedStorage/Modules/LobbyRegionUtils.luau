local Workspace = game:GetService("Workspace")

local LobbyRegionUtils = {}

function LobbyRegionUtils.IsPointInsidePart(part: BasePart, point: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5

	return math.abs(localPoint.X) <= halfSize.X
		and math.abs(localPoint.Y) <= halfSize.Y
		and math.abs(localPoint.Z) <= halfSize.Z
end

function LobbyRegionUtils.GetWorldFolder(worldName: string?): Instance?
	if typeof(worldName) ~= "string" or worldName == "" then
		return nil
	end

	local worldsFolder = Workspace:FindFirstChild("Worlds")
	return worldsFolder and worldsFolder:FindFirstChild(worldName) or nil
end

function LobbyRegionUtils.FindLobbyRegionPart(world: Instance?): BasePart?
	if not world then
		return nil
	end

	local lobbyRegionContainer = world:FindFirstChild("LobbyRegion_Model")
	if not lobbyRegionContainer then
		return nil
	end

	local nestedLobbyRegion = lobbyRegionContainer:FindFirstChild("LobbyRegion", true)
	if nestedLobbyRegion and nestedLobbyRegion:IsA("BasePart") then
		return nestedLobbyRegion
	end

	return nil
end

function LobbyRegionUtils.IsCharacterInsideLobbyRegion(character: Model?, worldName: string?): boolean
	if not character then
		return false
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local world = LobbyRegionUtils.GetWorldFolder(worldName)
	local lobbyRegion = LobbyRegionUtils.FindLobbyRegionPart(world)
	if not lobbyRegion then
		return false
	end

	return LobbyRegionUtils.IsPointInsidePart(lobbyRegion, rootPart.Position)
end

function LobbyRegionUtils.IsPlayerInsideCurrentWorldLobby(player: Player): boolean
	local currentWorld = player:GetAttribute("Current_World")
	if typeof(currentWorld) ~= "string" then
		return false
	end

	return LobbyRegionUtils.IsCharacterInsideLobbyRegion(player.Character, currentWorld)
end

return LobbyRegionUtils
