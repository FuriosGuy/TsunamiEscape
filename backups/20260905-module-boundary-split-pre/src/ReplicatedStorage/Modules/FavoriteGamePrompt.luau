--!strict

local AvatarEditorService = game:GetService("AvatarEditorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local LobbyRegionUtils = require(ReplicatedStorage.Modules.LobbyRegionUtils)

local FavoriteGamePrompt = {}

local FAVORITE_ITEM_TYPE = Enum.AvatarItemType.Asset

function FavoriteGamePrompt.PromptAfterLoadingIfEligible(player: Player): boolean
	if not LobbyRegionUtils.IsPlayerInsideCurrentWorldLobby(player) then
		return false
	end

	local placeId = game.PlaceId
	if placeId <= 0 then
		return false
	end

	local successPrompt, promptError = pcall(function()
		AvatarEditorService:PromptSetFavorite(placeId, FAVORITE_ITEM_TYPE, true)
	end)
	if not successPrompt then
		DebugModule.debugWarn(
			string.format("Failed PromptSetFavorite for placeId %d: %s", placeId, tostring(promptError)),
			"FavoriteGamePrompt"
		)
		return false
	end

	return true
end

return FavoriteGamePrompt
