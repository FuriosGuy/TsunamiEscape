--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Maid = require(Modules:WaitForChild("Maid"))
local DebugModule = require(Modules:WaitForChild("DebugModule"))
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
local MODULE_NAME = "ReturnToStageService"

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

	local nearestCover: BasePart? = nil
	local nearestDistance = math.huge
	local roadsFolder = world:FindFirstChild("Roads")
	if not roadsFolder then
		return nil
	end

	for _, descendant in ipairs(roadsFolder:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "TsunamiCover" then
			local distance = (descendant.Position - stagePart.Position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestCover = descendant
			end
		end
	end

	return nearestCover
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

function ReturnToStageService.HandlePurchase(player: Player, productId: number, isPurchased: boolean)
	if not isPurchased then
		return
	end
	if not RETURN_TO_STAGE_ENABLED then
		pendingReturnToStage[player] = nil
		ReturnToStageOffer:FireClient(player, false)
		return
	end

	local state = pendingReturnToStage[player]
	if not state or (os.clock() > state.expiresAt and state.promptLocked ~= true) then
		pendingReturnToStage[player] = nil
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local destination = findReturnStageDestination(state.worldName, state.stage)

	if not character or not humanoid or humanoid.Health <= 0 or not destination then
		pendingReturnToStage[player] = nil
		return
	end

	character:PivotTo(destination.CFrame * CFrame.new(0, 3, 0))
	ReturnToStageService.CleanupPlayer(player) -- Full cleanup after success
	ReturnToStageOffer:FireClient(player, false)
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
	local state = pendingReturnToStage[player]
	if not state then
		return
	end

	if state.expiresAt > 0 and os.clock() > state.expiresAt then
		return
	end

	state.promptLocked = true
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
	ReturnToStageDeclined.OnServerEvent:Connect(ReturnToStageService.OnDeclined)
	ReturnToStagePromptOpened.OnServerEvent:Connect(ReturnToStageService.OnPromptOpened)
	RequestReturnToStageOffer.OnServerEvent:Connect(ReturnToStageService.OnRequestOffer)
	DebugModule.debugInfo("ReturnToStageService Initialized", MODULE_NAME)
end

return ReturnToStageService
