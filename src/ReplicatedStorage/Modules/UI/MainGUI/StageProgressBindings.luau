local StageProgressBindings = {}

type BindOptions = {
	sessionMaid: any,
	playersService: Players,
	workspace: Workspace,
	player: Player,
	connectTrackedPlayer: (Player) -> (),
	disconnectTrackedPlayer: (Player) -> (),
	updateStageProgressPlayerMarkers: () -> (),
	tryRefreshStageProgress: () -> (),
}

function StageProgressBindings.Bind(options: BindOptions)
	for _, trackedPlayer in ipairs(options.playersService:GetPlayers()) do
		options.connectTrackedPlayer(trackedPlayer)
	end

	options.sessionMaid:GiveTask(options.playersService.PlayerAdded:Connect(function(addedPlayer)
		options.connectTrackedPlayer(addedPlayer)
		task.defer(options.updateStageProgressPlayerMarkers)
	end))

	options.sessionMaid:GiveTask(options.playersService.PlayerRemoving:Connect(function(removingPlayer)
		options.disconnectTrackedPlayer(removingPlayer)
		task.defer(options.updateStageProgressPlayerMarkers)
	end))

	options.sessionMaid:GiveTask(options.workspace.DescendantAdded:Connect(function(descendant)
		local currentWorld = options.player:GetAttribute("Current_World")
		if typeof(currentWorld) ~= "string" or currentWorld == "" then
			return
		end

		local worldsFolder = options.workspace:FindFirstChild("Worlds")
		local world = worldsFolder and worldsFolder:FindFirstChild(currentWorld)
		if not world or not descendant:IsDescendantOf(world) then
			return
		end

		if descendant.Name == "LobbyRegion" or descendant.Name == "StageEnd" or descendant.Name == "InvisEnd" then
			task.defer(options.tryRefreshStageProgress)
			return
		end

		local stageAncestor = descendant:FindFirstAncestor("Stages")
		if stageAncestor == world:FindFirstChild("Stages") then
			task.defer(options.tryRefreshStageProgress)
		end
	end))
end

return StageProgressBindings
