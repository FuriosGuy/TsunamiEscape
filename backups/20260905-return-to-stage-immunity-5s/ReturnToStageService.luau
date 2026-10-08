--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Maid = require(Modules:WaitForChild("Maid"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local ProductService = require(Modules:WaitForChild("ProductService"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local ReturnToStageService = {}

-- CONFIG
local returnToStageConfig = CoreConfig.returnToStage
local RETURN_TO_STAGE_DURATION = if returnToStageConfig and typeof(returnToStageConfig.duration) == "number"
	then math.max(1, returnToStageConfig.duration)
	else 10
local RETURN_TO_STAGE_ENABLED = if returnToStageConfig and typeof(returnToStageConfig.enabled) == "boolean"
	then returnToStageConfig.enabled
	else true
local RETURN_TO_STAGE_IMMUNITY_DURATION = 5
local MODULE_NAME = "ReturnToStageService"
local isInitialized = false
local serviceMaid = Maid.new()

-- REMOTES
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ReturnToStageOffer = Remotes:WaitForChild("ReturnToStageOffer") :: RemoteEvent
local ReturnToStageDeclined = Remotes:WaitForChild("ReturnToStageDeclined") :: RemoteEvent
local ReturnToStagePromptOpened = Remotes:WaitForChild("ReturnToStagePromptOpened") :: RemoteEvent
local RequestReturnToStageOffer = Remotes:WaitForChild("RequestReturnToStageOffer") :: RemoteEvent

-- STATE
local pendingReturnToStage: {
	[Player]: {
		stage: number,
		worldName: string,
		expiresAt: number,
		promptLocked: boolean?,
		maid: any, -- Rule #3.10: Handle expiration thread
	},
} =
	{}

local pendingReturnOfferRequest: { [Player]: boolean } = {}

local function findNearestTsunamiCover(world: Instance, origin: Vector3): BasePart?
	local roadsFolder = world:FindFirstChild("Roads")
	if not roadsFolder then
		return nil
	end

	local nearestCover: BasePart? = nil
	local nearestDistance = math.huge
	for _, descendant in ipairs(roadsFolder:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "TsunamiCover" then
			local distance = (descendant.Position - origin).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestCover = descendant
			end
		end
	end

	return nearestCover
end

local function findReturnStageDestination(worldName: string, stageNumber: number): BasePart?
	local worldsFolder = workspace:FindFirstChild("Worlds")
	local world = worldsFolder and worldsFolder:FindFirstChild(worldName)
	if not world then
		return nil
	end

	local stagesFolder = world:FindFirstChild("Stages")
	local stageInstance = stagesFolder and stagesFolder:FindFirstChild("Stage_" .. tostring(stageNumber))
	if not stageInstance then
		return nil
	end

	local stagePart = if stageInstance:IsA("BasePart")
		then stageInstance
		else stageInstance:FindFirstChildWhichIsA("BasePart", true)
	if not stagePart then
		return nil
	end

	return findNearestTsunamiCover(world, stagePart.Position)
end

-- Shared server-side stage destination lookup for safe world redirects.
function ReturnToStageService.GetStageDestination(worldName: string, stageNumber: number): BasePart?
	if worldName == "" or stageNumber < 0 then
		return nil
	end

	return findReturnStageDestination(worldName, math.floor(stageNumber))
end

-- Finds safe return cover relative to a specific world barrier.
function ReturnToStageService.GetNearestTsunamiCover(worldName: string, origin: Vector3): BasePart?
	if worldName == "" then
		return nil
	end

	local worldsFolder = workspace:FindFirstChild("Worlds")
	local world = worldsFolder and worldsFolder:FindFirstChild(worldName)
	if not world then
		return nil
	end

	return findNearestTsunamiCover(world, origin)
end

function ReturnToStageService.OfferReturnToStage(player: Player)
	if not RETURN_TO_STAGE_ENABLED then
		pendingReturnToStage[player] = nil
		ReturnToStageOffer:FireClient(player, false)
		return
	end

	local state = pendingReturnToStage[player]
	if not state or state.stage <= 0 or state.worldName == "" then
		pendingReturnToStage[player] = nil
		ReturnToStageOffer:FireClient(player, false)
		return
	end

	local expiresAt = os.clock() + RETURN_TO_STAGE_DURATION
	state.expiresAt = expiresAt

	-- Rule #3.10: Resource bounding/cleanup
	if not state.maid then
		state.maid = Maid.new()
	end
	state.maid.ExpireThread = nil

	ReturnToStageOffer:FireClient(player, true, state.stage, RETURN_TO_STAGE_DURATION)

	state.maid.ExpireThread = task.spawn(function()
		task.wait(RETURN_TO_STAGE_DURATION)
		local currentState = pendingReturnToStage[player]
		if not player.Parent or not currentState then
			return
		end

		if currentState.expiresAt == expiresAt and os.clock() >= currentState.expiresAt then
			if currentState.promptLocked == true then
				return
			end

			DebugModule.debugPrint(string.format("ReturnToStage offer expired for %s", player.Name), MODULE_NAME)
			pendingReturnToStage[player] = nil
			player:SetAttribute("CurrentStage", 0)
			ReturnToStageOffer:FireClient(player, false)
		end
	end)
end

function ReturnToStageService.HandlePurchase(player: Player, productId: number, isPurchased: boolean): (boolean, string)
	if productId ~= ProductService.DevProducts.ReturnToStage then
		return false, "InvalidProduct"
	end
	if not isPurchased then
		return false, "NotPurchased"
	end
	if not RETURN_TO_STAGE_ENABLED then
		pendingReturnToStage[player] = nil
		ReturnToStageOffer:FireClient(player, false)
		return false, "Disabled"
	end

	local state = pendingReturnToStage[player]
	if not state or (os.clock() > state.expiresAt and state.promptLocked ~= true) then
		pendingReturnToStage[player] = nil
		return false, "OfferUnavailable"
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local destination = findReturnStageDestination(state.worldName, state.stage)

	if
		not character
		or not humanoid
		or humanoid.Health <= 0
		or not rootPart
		or not rootPart:IsA("BasePart")
		or not destination
	then
		pendingReturnToStage[player] = nil
		return false, "CharacterUnavailable"
	end

	character:PivotTo(destination.CFrame * CFrame.new(0, 3, 0))
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	player:SetAttribute(
		"TsunamiImmunityUntil",
		Workspace:GetServerTimeNow() + RETURN_TO_STAGE_IMMUNITY_DURATION
	)
	DebugModule.debugInfo(
		string.format(
			"ReturnToStage completed | player=%s | stage=%d | immunitySeconds=%d",
			player.Name,
			state.stage,
			RETURN_TO_STAGE_IMMUNITY_DURATION
		),
		MODULE_NAME
	)
	ReturnToStageService.CleanupPlayer(player) -- Full cleanup after success
	ReturnToStageOffer:FireClient(player, false)
	return true, "Granted"
end

function ReturnToStageService.HandleCreatorPurchase(player: Player, productId: number): (boolean, string)
	if productId ~= ProductService.DevProducts.ReturnToStage then
		return false, "InvalidProduct"
	end

	local state = pendingReturnToStage[player]
	if not state or state.promptLocked ~= true then
		DebugModule.debugWarn(
			"Creator ReturnToStage rejected because strict offer is not locked | player=" .. player.Name,
			MODULE_NAME
		)
		return false, "OfferNotLocked"
	end

	return ReturnToStageService.HandlePurchase(player, productId, true)
end

function ReturnToStageService.OnDeclined(player: Player)
	local state = pendingReturnToStage[player]
	if not state then
		return
	end

	ReturnToStageService.CleanupPlayer(player)
	player:SetAttribute("CurrentStage", 0)
	ReturnToStageOffer:FireClient(player, false)
end

function ReturnToStageService.OnPromptOpened(player: Player)
	ReturnToStageService.PrepareRewardedReturn(player)
end

function ReturnToStageService.PrepareRewardedReturn(player: Player): boolean
	local state = pendingReturnToStage[player]
	if not state then
		return false
	end

	if state.expiresAt > 0 and os.clock() > state.expiresAt then
		return false
	end

	state.promptLocked = true
	return true
end

function ReturnToStageService.CancelRewardedReturn(player: Player)
	local state = pendingReturnToStage[player]
	if not state then
		return
	end

	state.promptLocked = false
	if state.expiresAt > 0 and os.clock() >= state.expiresAt then
		ReturnToStageService.CleanupPlayer(player)
		player:SetAttribute("CurrentStage", 0)
		ReturnToStageOffer:FireClient(player, false)
	end
end

function ReturnToStageService.OnRequestOffer(player: Player)
	if not RETURN_TO_STAGE_ENABLED then
		return
	end

	if player:GetAttribute("Data_Loaded") ~= true then
		pendingReturnOfferRequest[player] = true
		return
	end

	local stage = player:GetAttribute("CurrentStage")
	local worldName = player:GetAttribute("Current_World")

	if typeof(stage) == "number" and stage > 0 and typeof(worldName) == "string" and worldName ~= "" then
		if not pendingReturnToStage[player] then
			pendingReturnToStage[player] = {
				stage = stage,
				worldName = worldName,
				expiresAt = 0,
				promptLocked = false,
				maid = Maid.new(),
			}
		end
		ReturnToStageService.OfferReturnToStage(player)
	else
		pendingReturnToStage[player] = nil
		ReturnToStageOffer:FireClient(player, false)
	end
end

function ReturnToStageService.SetPendingState(player: Player, stage: number, worldName: string)
	if not RETURN_TO_STAGE_ENABLED then
		return
	end
	pendingReturnToStage[player] = {
		stage = stage,
		worldName = worldName,
		expiresAt = 0,
		promptLocked = false,
		maid = Maid.new(),
	}
end

function ReturnToStageService.CheckQueuedRequest(player: Player)
	if pendingReturnOfferRequest[player] then
		pendingReturnOfferRequest[player] = nil
		ReturnToStageService.OnRequestOffer(player)
	end
end

function ReturnToStageService.CleanupPlayer(player: Player)
	local state = pendingReturnToStage[player]
	if state and state.maid then
		state.maid:DoCleaning()
	end
	pendingReturnToStage[player] = nil
	pendingReturnOfferRequest[player] = nil
end

function ReturnToStageService.Init()
	if isInitialized then
		return
	end
	isInitialized = true
	serviceMaid.ReturnToStageDeclined = ReturnToStageDeclined.OnServerEvent:Connect(ReturnToStageService.OnDeclined)
	serviceMaid.ReturnToStagePromptOpened =
		ReturnToStagePromptOpened.OnServerEvent:Connect(ReturnToStageService.OnPromptOpened)
	serviceMaid.RequestReturnToStageOffer =
		RequestReturnToStageOffer.OnServerEvent:Connect(ReturnToStageService.OnRequestOffer)
	DebugModule.debugInfo("ReturnToStageService Initialized", MODULE_NAME)
end

function ReturnToStageService.Shutdown()
	for player in pairs(table.clone(pendingReturnToStage)) do
		ReturnToStageService.CleanupPlayer(player)
	end
	serviceMaid:DoCleaning()
	table.clear(pendingReturnOfferRequest)
	isInitialized = false
end

return ReturnToStageService
