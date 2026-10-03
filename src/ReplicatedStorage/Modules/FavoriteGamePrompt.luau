--!strict

local AvatarEditorService = game:GetService("AvatarEditorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local LobbyRegionUtils = require(ReplicatedStorage.Modules.LobbyRegionUtils)

local FavoriteGamePrompt = {}

local FAVORITE_ITEM_TYPE = Enum.AvatarItemType.Asset
local DEFERRED_PROMPT_DELAY_SECONDS = 90

type CleanupFunction = () -> ()

local function cancelThread(threadValue: thread?)
	if threadValue and threadValue ~= coroutine.running() and coroutine.status(threadValue) ~= "dead" then
		pcall(task.cancel, threadValue)
	end
end

function FavoriteGamePrompt.PromptAfterLoadingIfEligible(player: Player): boolean
	if not LobbyRegionUtils.IsPlayerInsideCurrentWorldLobby(player) then
		return false
	end

	local placeId = game.PlaceId
	if placeId <= 0 then
		return false
	end

	local favoriteCheckSucceeded, isFavorite = pcall(function(): boolean
		return AvatarEditorService:GetFavoriteAsync(placeId, FAVORITE_ITEM_TYPE)
	end)
	if not favoriteCheckSucceeded or typeof(isFavorite) ~= "boolean" then
		DebugModule.debugWarn(
			string.format(
				"Failed favorite status check for placeId %d: %s",
				placeId,
				tostring(isFavorite)
			),
			"FavoriteGamePrompt"
		)
		return false
	end

	if isFavorite then
		DebugModule.debugInfo(
			string.format("Favorite prompt skipped; player already favorited placeId %d", placeId),
			"FavoriteGamePrompt"
		)
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

function FavoriteGamePrompt.StartDeferredPrompt(player: Player, isAlive: (() -> boolean)?): CleanupFunction
	local alive = true
	local didAttempt = false
	local completionConnection: RBXScriptConnection? = nil
	local delayThread: thread? = nil

	local function cleanup()
		if not alive then
			return
		end

		alive = false
		if completionConnection then
			completionConnection:Disconnect()
			completionConnection = nil
		end
		cancelThread(delayThread)
		delayThread = nil
	end

	local function canContinue(): boolean
		return alive
			and player.Parent ~= nil
			and (isAlive == nil or isAlive())
			and player:GetAttribute("Data_Loaded") == true
	end

	local function tryPrompt()
		if delayThread == coroutine.running() then
			delayThread = nil
		end

		if didAttempt or not canContinue() then
			return
		end

		-- Wait until action tutorial ends so native prompt cannot interrupt it.
		if player:GetAttribute("TutorialCompleted") ~= true then
			return
		end

		didAttempt = true
		cleanup()
		FavoriteGamePrompt.PromptAfterLoadingIfEligible(player)
	end

	completionConnection = player:GetAttributeChangedSignal("TutorialCompleted"):Connect(tryPrompt)
	delayThread = task.delay(DEFERRED_PROMPT_DELAY_SECONDS, tryPrompt)

	return cleanup
end

return FavoriteGamePrompt
