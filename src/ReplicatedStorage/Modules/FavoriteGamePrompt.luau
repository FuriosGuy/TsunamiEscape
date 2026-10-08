--!strict

local AvatarEditorService = game:GetService("AvatarEditorService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local FavoriteGamePromptAttempted = ReplicatedStorage.Remotes:WaitForChild("FavoriteGamePromptAttempted") :: RemoteEvent

local FavoriteGamePrompt = {}

local FAVORITE_ITEM_TYPE = Enum.AvatarItemType.Asset

type CleanupFunction = () -> ()

function FavoriteGamePrompt.PromptAfterLoadingIfEligible(player: Player): boolean
	if player:GetAttribute("FavoriteGamePromptAttempted") == true then
		DebugModule.debugInfo("Favorite prompt skipped; attempt already recorded", "FavoriteGamePrompt")
		return false
	end

	local placeId = game.PlaceId
	if placeId <= 0 then
		return false
	end

	local persistSuccess, persistError = pcall(function()
		FavoriteGamePromptAttempted:FireServer()
	end)
	if not persistSuccess then
		DebugModule.debugWarn(
			"Failed to record favorite prompt attempt: " .. tostring(persistError),
			"FavoriteGamePrompt"
		)
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

	local function cleanup()
		if not alive then
			return
		end

		alive = false
		if completionConnection then
			completionConnection:Disconnect()
			completionConnection = nil
		end
	end

	local function canContinue(): boolean
		return alive
			and player.Parent ~= nil
			and (isAlive == nil or isAlive())
			and player:GetAttribute("Data_Loaded") == true
	end

	local function tryPrompt()
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

	return cleanup
end

return FavoriteGamePrompt
