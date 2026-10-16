--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local DebugModule = require(ReplicatedStorage.Modules.DebugModule)
local Maid = require(ReplicatedStorage.Modules.Maid)
local HalloweenEventConfig = require(ReplicatedStorage.Modules.Config.HalloweenEventConfig)
local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local ProductService = require(ServerScriptService.Modules.Shared.ProductService_Server)
local PlayerHandler = require(ServerScriptService.Modules.Shared.PlayerHandler_Server)
local CreatorPurchaseService = require(ServerScriptService.Modules.CreatorPurchaseService)
local ProductServerService = require(ServerScriptService.Modules.ProductServerService)
local PetLuckyBlockBillboardService = require(ServerScriptService.Modules.PetLuckyBlockBillboardService)
local PetInventoryService = require(ServerScriptService.Modules.PetInventoryService)
local PetPaidRandomItemPolicyService = require(ServerScriptService.Modules.PetPaidRandomItemPolicyService)
local HalloweenCandyService = require(ServerScriptService.Modules.HalloweenCandyService)
local LiveEventService = require(ServerScriptService.Modules.LiveEventService)
local ValidationService = require(ServerScriptService.Modules:WaitForChild("ValidationService"))

type LuckyBlockGroup = "Tier1" | "Tier2" | "Tier3" | "Premium" | PetConfig.EventId
type RollCount = number
type ReceiptRollResult = {
	userId: number,
	group: LuckyBlockGroup,
	petIds: { string },
	overflowCount: number,
}

local PetLuckyBlockPurchaseService = {}
local MODULE_NAME = "PetLuckyBlockPurchaseService"
local REMOTE_COOLDOWN_SECONDS = 0.5
local FAST_OPEN_PREFERENCE_COOLDOWN_SECONDS = 0.25
local MAX_INTERACTION_DISTANCE = 18
local LAST_REQUEST_AT: { [Player]: number } = {}
local FAST_OPEN_PREFERENCE_REQUEST_AT: { [Player]: number } = {}
local RECEIPT_ROLL_RESULTS: { [string]: ReceiptRollResult } = {}
local MODEL_PROMPT_MAIDS: { [Model]: any } = {}
local MODEL_PARTICLE_EMITTER_STATES: { [Model]: { [ParticleEmitter]: boolean } } = {}
local BOUND_OPEN_PROMPTS: { [ProximityPrompt]: boolean } = {}
local SERVICE_MAID = Maid.new()
local INITIALIZED = false
local ROLL_RANDOM = Random.new()
local liveEventStateFolder: Folder? = nil
local INACTIVE_EVENT_HIGHLIGHT_NAME = "LuckyBlockInactiveEventHighlight"

local BLOCK_GROUPS: { LuckyBlockGroup } = {
	"Tier1",
	"Tier2",
	"Tier3",
	"Premium",
	"BloodMoon",
	"NeonRush",
	"FrostbiteRally",
	"Halloween",
}
local EVENT_GROUPS: { [string]: boolean } = {
	BloodMoon = true,
	NeonRush = true,
	FrostbiteRally = true,
	Halloween = true,
}
local ROLL_EVENT_GATED_GROUPS: { [string]: boolean } = {
	NeonRush = true,
	FrostbiteRally = true,
	Halloween = true,
}
local ACTIVE_EVENT_IDS: { [string]: string } = {
	BloodMoon = "Bloodmoon",
	NeonRush = "NeonRush",
	FrostbiteRally = "FrostbiteRally",
}
local PROMPT_LOCKED_EVENT_GROUPS: { [string]: boolean } = {
	NeonRush = true,
	FrostbiteRally = true,
	Halloween = true,
}
local BLOCK_DISPLAY_NAMES: { [string]: string } = {
	Tier1 = "Tier 1 Lucky Block",
	Tier2 = "Tier 2 Lucky Block",
	Tier3 = "Tier 3 Lucky Block",
	Premium = "Premium Lucky Block",
	BloodMoon = "Blood Moon Lucky Block",
	NeonRush = "Neon Rush Lucky Block",
	FrostbiteRally = "Frostbite Rally Lucky Block",
	Halloween = "Halloween Lucky Block",
}
local MODEL_GROUP_ALIASES: { [string]: LuckyBlockGroup } = {
	bloodmoonluckyblock = "BloodMoon",
	robuxluckyblock = "Premium",
	neonluckyblock = "NeonRush",
	frostbiteluckyblock = "FrostbiteRally",
	halloweenluckyblock = "Halloween",
}
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local function getOrCreateRemote(name: string): RemoteEvent?
	local existing = Remotes:FindFirstChild(name)
	if existing then
		if existing:IsA("RemoteEvent") then
			return existing
		end
		DebugModule.debugWarn("Remote name is occupied by wrong class | remote=" .. name, MODULE_NAME)
		return nil
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = Remotes
	return remote
end

local RollRequest = getOrCreateRemote("PetLuckyBlockRollRequest")
local RollResult = getOrCreateRemote("PetLuckyBlockRollResult")
local OpenScreen = getOrCreateRemote("PetLuckyBlockOpen")
local DailyRewardReveal = getOrCreateRemote("DailyLuckyBlockReveal")
local FastOpenPreference = getOrCreateRemote("PetLuckyBlockFastOpenPreference")
local PurchasePrompt = Remotes:WaitForChild("PurchasePrompt", 10)
local ShowNotification = Remotes:FindFirstChild("ShowNotification")

local function sendResult(player: Player, status: string, value: unknown?): ()
	if player.Parent == Players and RollResult then
		RollResult:FireClient(player, status, value)
	end
end

local function isFastOpenEnabled(player: Player): boolean
	local fasterOpenId = ProductService.Gamepasses.PetLuckyBlockFasterOpen
	local ownsFastOpen = typeof(fasterOpenId) == "number"
		and fasterOpenId > 0
		and ProductService.userOwnsGamePass(player, fasterOpenId)
	return ownsFastOpen and player:GetAttribute("Pet_LuckyBlockFastOpenEnabled") ~= false
end

local function createRollResult(player: Player, petIds: { string }): { petIds: { string }, fasterOpen: boolean }
	return {
		petIds = petIds,
		fasterOpen = isFastOpenEnabled(player),
	}
end

local function processFastOpenPreference(player: Player, enabled: any): ()
	local currentValue = player:GetAttribute("Pet_LuckyBlockFastOpenEnabled")
	local currentEnabled = currentValue ~= false
	local now = os.clock()
	local previousRequest = FAST_OPEN_PREFERENCE_REQUEST_AT[player]
	if previousRequest and now - previousRequest < FAST_OPEN_PREFERENCE_COOLDOWN_SECONDS then
		if FastOpenPreference then
			FastOpenPreference:FireClient(player, currentEnabled)
		end
		return
	end
	FAST_OPEN_PREFERENCE_REQUEST_AT[player] = now

	local gamePassId = ProductService.Gamepasses.PetLuckyBlockFasterOpen
	if player:GetAttribute("Data_Loaded") == true
		and typeof(enabled) == "boolean"
		and typeof(gamePassId) == "number"
		and gamePassId > 0
		and ProductService.userOwnsGamePass(player, gamePassId)
	then
		player:SetAttribute("Pet_LuckyBlockFastOpenEnabled", enabled)
		currentEnabled = enabled
	end

	if FastOpenPreference and player.Parent == Players then
		FastOpenPreference:FireClient(player, currentEnabled)
	end
end

local function notify(player: Player, message: string, color: string): ()
	if player.Parent == Players and ShowNotification and ShowNotification:IsA("RemoteEvent") then
		ShowNotification:FireClient(player, message, color)
	end
end

local function readLuckMultiplier(player: Player): number
	local value = player:GetAttribute("Pet_LuckMultiplier")
	if typeof(value) ~= "number" or value ~= value or value < 1 or value == math.huge then
		value = PetConfig.Upgrades.luckMultiplier.startingMultiplier
	end
	return PetConfig.GetEffectiveLuckMultiplier(value, PlayerHandler.GetLiveEventLuckMultiplier(player))
end

local function rollPetIds(player: Player, group: LuckyBlockGroup, rollCount: RollCount): { string }?
	local pets = PetConfig.GetPetsForLuckyBlock(group)
	if not pets or #pets == 0 then
		return nil
	end

	local totalWeight = 0
	local fallbackPet: PetConfig.PetDefinition? = nil
	for _, pet in ipairs(pets) do
		local weight = PetConfig.GetLuckAdjustedWeight(pet, readLuckMultiplier(player))
		if weight == weight and weight > 0 and weight < math.huge then
			totalWeight += weight
			fallbackPet = fallbackPet or pet
		end
	end
	if totalWeight <= 0 or not fallbackPet then
		return nil
	end

	local petIds: { string } = {}
	for _ = 1, rollCount do
		local selection = ROLL_RANDOM:NextNumber(0, totalWeight)
		local cumulativeWeight = 0
		local selectedPet = fallbackPet
		for _, pet in ipairs(pets) do
			local weight = PetConfig.GetLuckAdjustedWeight(pet, readLuckMultiplier(player))
			if weight == weight and weight > 0 and weight < math.huge then
				cumulativeWeight += weight
				if selection <= cumulativeWeight then
					selectedPet = pet
					break
				end
			end
		end
		table.insert(petIds, selectedPet.id)
	end
	return petIds
end

local function getGroupFromModel(model: Model): LuckyBlockGroup?
	local blockId = model:GetAttribute("LuckyBlockId")
	local eventId = model:GetAttribute("LuckyBlockEventId")
	if blockId == "Event" then
		if typeof(eventId) == "string" then
			local normalizedEventId = string.lower(string.gsub(eventId, "[^%w]", ""))
			for _, group in ipairs(BLOCK_GROUPS) do
				if EVENT_GROUPS[group] and normalizedEventId == string.lower(group) then
					return group
				end
			end
		end
		return nil
	end
	if typeof(blockId) == "string" then
		local normalizedBlockId = string.lower(string.gsub(blockId, "[^%w]", ""))
		for _, group in ipairs(BLOCK_GROUPS) do
			if normalizedBlockId == string.lower(group) then
				return group
			end
		end
	end
	local normalizedName = string.lower(string.gsub(model.Name, "[^%w]", ""))
	local aliasedGroup = MODEL_GROUP_ALIASES[normalizedName]
	if aliasedGroup then
		return aliasedGroup
	end
	for _, group in ipairs(BLOCK_GROUPS) do
		if normalizedName == string.lower(group .. "LuckyBlock") then
			return group
		end
	end
	return nil
end

local function isLiveEventActive(eventId: string): boolean
	if eventId == "Halloween" then
		return liveEventStateFolder ~= nil and liveEventStateFolder:GetAttribute("HalloweenPartTwoActive") == true
	end
	local liveEventId = ACTIVE_EVENT_IDS[eventId] or eventId
	return LiveEventService.IsEventActive(liveEventId)
end

local function isLuckyBlockEventUnavailable(group: LuckyBlockGroup): boolean
	return PROMPT_LOCKED_EVENT_GROUPS[group] == true and not isLiveEventActive(group)
end

local function findNearbyLuckyBlock(player: Player, group: LuckyBlockGroup): boolean
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local worlds = Workspace:FindFirstChild("Worlds")
	local world = worlds and worlds:FindFirstChild("World1")
	local blocks = world and world:FindFirstChild("LuckyBlocks")
	if not root or not root:IsA("BasePart") or not blocks then
		return false
	end

	for _, child in ipairs(blocks:GetChildren()) do
		if child:IsA("Model") and getGroupFromModel(child) == group then
			local target = child:FindFirstChild("MainPart")
			if
				target
				and target:IsA("BasePart")
				and (target.Position - root.Position).Magnitude <= MAX_INTERACTION_DISTANCE
			then
				return true
			end
		end
	end
	return false
end

local function canInteractWithLuckyBlock(player: Player, group: LuckyBlockGroup): boolean
	return not isLuckyBlockEventUnavailable(group)
		and ValidationService.IsPlayerAlive(player)
		and ValidationService.ValidateRewardEligibility(player, "LuckyBlockInteraction")
		and findNearbyLuckyBlock(player, group)
end

local function setEventBlockParticleEmitters(model: Model, unavailable: boolean): ()
	local originalStates = MODEL_PARTICLE_EMITTER_STATES[model]
	if unavailable then
		if not originalStates then
			originalStates = {}
			MODEL_PARTICLE_EMITTER_STATES[model] = originalStates
		end

		for _, descendant in model:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				if originalStates[descendant] == nil then
					originalStates[descendant] = descendant.Enabled
				end
				descendant.Enabled = false
			end
		end
		return
	end

	if not originalStates then
		return
	end

	for emitter, wasEnabled in pairs(originalStates) do
		if emitter.Parent then
			emitter.Enabled = wasEnabled
		end
	end
	MODEL_PARTICLE_EMITTER_STATES[model] = nil
end

local function disableAddedEventBlockEmitter(model: Model, emitter: ParticleEmitter, group: LuckyBlockGroup): ()
	if not PROMPT_LOCKED_EVENT_GROUPS[group] or not isLuckyBlockEventUnavailable(group) then
		return
	end

	local originalStates = MODEL_PARTICLE_EMITTER_STATES[model]
	if not originalStates then
		originalStates = {}
		MODEL_PARTICLE_EMITTER_STATES[model] = originalStates
	end
	if originalStates[emitter] == nil then
		originalStates[emitter] = emitter.Enabled
	end
	emitter.Enabled = false
end

local function clearModelPromptBindings(model: Model): ()
	setEventBlockParticleEmitters(model, false)
	local modelMaid = MODEL_PROMPT_MAIDS[model]
	if modelMaid then
		MODEL_PROMPT_MAIDS[model] = nil
		modelMaid:DoCleaning()
	end
end

local function getPromptPart(model: Model): BasePart?
	local mainPart = model:FindFirstChild("MainPart")
	return if mainPart and mainPart:IsA("BasePart") then mainPart else nil
end

local function updateEventBlockPresentation(model: Model, modelMaid: any, group: LuckyBlockGroup): ()
	local unavailable = isLuckyBlockEventUnavailable(group)
	if PROMPT_LOCKED_EVENT_GROUPS[group] then
		PetLuckyBlockBillboardService.SetEventAvailability(model, not unavailable)
		setEventBlockParticleEmitters(model, unavailable)
	end
	local promptPart = getPromptPart(model)
	local promptInstance = promptPart and promptPart:FindFirstChild("LuckyBlockOpenPrompt")
	if promptInstance and promptInstance:IsA("ProximityPrompt") then
		promptInstance.Enabled = not unavailable
	end
	DebugModule.debugInfo(
		"Event block state applied | group="
			.. group
			.. " | active="
			.. tostring(not unavailable)
			.. " | promptEnabled="
			.. tostring(promptInstance ~= nil and promptInstance:IsA("ProximityPrompt") and promptInstance.Enabled),
		MODULE_NAME
	)

	local highlightInstance = model:FindFirstChild(INACTIVE_EVENT_HIGHLIGHT_NAME)
	if highlightInstance and not highlightInstance:IsA("Highlight") then
		DebugModule.debugWarn(
			"Inactive event highlight name is occupied by wrong class | model=" .. model:GetFullName(),
			MODULE_NAME
		)
		return
	end

	local highlight = highlightInstance :: Highlight?
	if not highlight and unavailable then
		highlight = Instance.new("Highlight")
		highlight.Name = INACTIVE_EVENT_HIGHLIGHT_NAME
		highlight.Parent = model
		modelMaid:GiveTask(highlight)
	end
	if highlight then
		highlight.Adornee = model
		highlight.FillColor = Color3.new(0, 0, 0)
		highlight.FillTransparency = 0.55
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Enabled = unavailable
	end
end

local function addOpenPrompt(model: Model, modelMaid: any, group: LuckyBlockGroup): ()
	if model.Parent == nil then
		return
	end
	local promptPart = getPromptPart(model)
	if not promptPart then
		return
	end
	local billboardCleanup = PetLuckyBlockBillboardService.Attach(model, promptPart, group)
	if billboardCleanup then
		modelMaid:GiveTask(billboardCleanup)
	end

	local promptInstance = promptPart:FindFirstChild("LuckyBlockOpenPrompt")
	local prompt: ProximityPrompt
	local createdPrompt = false
	if promptInstance then
		if not promptInstance:IsA("ProximityPrompt") then
			DebugModule.debugWarn(
				"LuckyBlockOpenPrompt name is occupied by wrong class | model=" .. model:GetFullName(),
				MODULE_NAME
			)
			return
		end
		prompt = promptInstance
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "LuckyBlockOpenPrompt"
		prompt.ActionText = "Open"
		prompt.ObjectText = BLOCK_DISPLAY_NAMES[group] or "Lucky Block"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = MAX_INTERACTION_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
		prompt.Enabled = true
		prompt.Parent = promptPart
		createdPrompt = true
	end

	if BOUND_OPEN_PROMPTS[prompt] then
		return
	end
	BOUND_OPEN_PROMPTS[prompt] = true
	local groupDisplayName = BLOCK_DISPLAY_NAMES[group]
	if groupDisplayName then
		prompt.ObjectText = groupDisplayName
	end
	prompt.ActionText = "Open"
	prompt.MaxActivationDistance = MAX_INTERACTION_DISTANCE
	prompt.RequiresLineOfSight = false
	updateEventBlockPresentation(model, modelMaid, group)

	modelMaid:GiveTask(prompt.Triggered:Connect(function(player: Player)
		if player.Parent ~= Players or model.Parent == nil or getGroupFromModel(model) ~= group then
			return
		end
		if player:GetAttribute("Data_Loaded") ~= true then
			DebugModule.debugWarn(
				"Lucky Block prompt rejected; player data not loaded | player=" .. player.Name,
				MODULE_NAME
			)
			return
		end
		if not canInteractWithLuckyBlock(player, group) then
			return
		end
		if OpenScreen and OpenScreen:IsA("RemoteEvent") then
			OpenScreen:FireClient(player, group)
		end
	end))
	modelMaid:GiveTask(function()
		BOUND_OPEN_PROMPTS[prompt] = nil
	end)
	if createdPrompt then
		modelMaid:GiveTask(function()
			if prompt.Parent then
				prompt:Destroy()
			end
		end)
	end
end

local function registerLuckyBlockModel(blocksFolder: Instance, instance: Instance): ()
	if not instance:IsA("Model") or instance.Parent ~= blocksFolder or MODEL_PROMPT_MAIDS[instance] then
		return
	end
	local group = getGroupFromModel(instance)
	if not group then
		return
	end

	local model = instance
	local modelMaid = Maid.new()
	MODEL_PROMPT_MAIDS[model] = modelMaid
	local function tryAddPrompt(): ()
		addOpenPrompt(model, modelMaid, group)
	end
	tryAddPrompt()
	modelMaid:GiveTask(model.ChildAdded:Connect(tryAddPrompt))
	modelMaid:GiveTask(model.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("ParticleEmitter") then
			disableAddedEventBlockEmitter(model, descendant, group)
		end
	end))
	modelMaid:GiveTask(model.AncestryChanged:Connect(function()
		if model.Parent ~= blocksFolder then
			clearModelPromptBindings(model)
		end
	end))
end

local function refreshEventBlockPresentations(): ()
	for model, modelMaid in pairs(MODEL_PROMPT_MAIDS) do
		if model.Parent then
			local group = getGroupFromModel(model)
			if group and PROMPT_LOCKED_EVENT_GROUPS[group] then
				updateEventBlockPresentation(model, modelMaid, group)
			end
		end
	end
end

local function bindLiveEventState(candidate: Instance): ()
	if not candidate:IsA("Folder") or liveEventStateFolder == candidate then
		return
	end
	liveEventStateFolder = candidate
	SERVICE_MAID.LuckyBlockActiveEventIdsChanged =
		candidate:GetAttributeChangedSignal("ActiveEventIds"):Connect(refreshEventBlockPresentations)
	SERVICE_MAID.LuckyBlockEnvironmentNameChanged =
		candidate:GetAttributeChangedSignal("EnvironmentName"):Connect(function()
			refreshEventBlockPresentations()
		end)
	local nextUnlockTimestamp = HalloweenEventConfig.GetNextUnlockUnixTimestamp(os.time())
	if nextUnlockTimestamp then
		SERVICE_MAID.LuckyBlockHalloweenGateThread = task.delay(
			math.max(nextUnlockTimestamp - os.time(), 0),
			refreshEventBlockPresentations
		)
	end
	SERVICE_MAID.LuckyBlockEventStateAncestryChanged = candidate.AncestryChanged:Connect(
		function(_: Instance, parent: Instance?)
			if parent == nil and liveEventStateFolder == candidate then
				liveEventStateFolder = nil
				SERVICE_MAID.LuckyBlockActiveEventIdsChanged = nil
				SERVICE_MAID.LuckyBlockEnvironmentNameChanged = nil
				SERVICE_MAID.LuckyBlockEventStateAncestryChanged = nil
				refreshEventBlockPresentations()
			end
		end
	)
	refreshEventBlockPresentations()
end

local function watchLiveEventState(): ()
	SERVICE_MAID.LuckyBlockEventStateAdded = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
		if child.Name == "LiveEventState" then
			bindLiveEventState(child)
		end
	end)
	local existingState = ReplicatedStorage:FindFirstChild("LiveEventState")
	if existingState then
		bindLiveEventState(existingState)
	end
end

local function bindLuckyBlockOpenPrompts(): ()
	local worlds = Workspace:WaitForChild("Worlds", 30)
	local world = worlds and worlds:WaitForChild("World1", 30)
	local blocksFolder = world and world:WaitForChild("LuckyBlocks", 30)
	if not blocksFolder then
		DebugModule.debugWarn("Workspace.Worlds.World1.LuckyBlocks did not load within 30 seconds", MODULE_NAME)
		return
	end

	SERVICE_MAID:GiveTask(blocksFolder.ChildAdded:Connect(function(child: Instance)
		registerLuckyBlockModel(blocksFolder, child)
	end))
	SERVICE_MAID:GiveTask(blocksFolder.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Model") then
			clearModelPromptBindings(child)
		end
	end))
	for _, child in ipairs(blocksFolder:GetChildren()) do
		registerLuckyBlockModel(blocksFolder, child)
	end
end

local function getPaidRollProductId(group: LuckyBlockGroup, rollCount: RollCount): number?
	local prefix = if group == "Premium" then "PetPremium" else "Pet" .. group
	local productId = ProductService.DevProducts[prefix .. "LuckyBlockRoll" .. tostring(rollCount)]
	return if typeof(productId) == "number" and productId > 0 then productId else nil
end

local function processRequest(
	player: Player,
	rawGroup: any,
	rawRollCount: any,
	rawPurchaseKind: any,
	rawSource: any
): ()
	if player.Parent ~= Players then
		return
	end
	local now = os.clock()
	local previous = LAST_REQUEST_AT[player] or 0
	if now - previous < REMOTE_COOLDOWN_SECONDS then
		sendResult(player, "RateLimited")
		return
	end
	LAST_REQUEST_AT[player] = now

	if typeof(rawGroup) ~= "string" or not table.find(BLOCK_GROUPS, rawGroup) then
		sendResult(player, "InvalidRequest")
		return
	end
	if rawRollCount ~= 1 and rawRollCount ~= 3 and rawRollCount ~= 5 then
		sendResult(player, "InvalidRequest")
		return
	end
	if rawPurchaseKind ~= "Wins" and rawPurchaseKind ~= "Candy" and rawPurchaseKind ~= "Robux" then
		sendResult(player, "InvalidRequest")
		return
	end
	if rawSource ~= "World" and rawSource ~= "Shop" then
		sendResult(player, "InvalidRequest")
		return
	end
	local group = rawGroup :: LuckyBlockGroup
	local rollCount = rawRollCount :: RollCount
	local purchaseKind = rawPurchaseKind :: "Wins" | "Candy" | "Robux"
	local source = rawSource :: "World" | "Shop"
	if player:GetAttribute("Data_Loaded") ~= true then
		sendResult(player, "DataNotLoaded")
		return
	end
	if purchaseKind == "Robux" then
		if player:GetAttribute("Pet_RandomItemPolicyLoaded") ~= true then
			sendResult(player, "PolicyLoading")
			return
		end
		if not PetPaidRandomItemPolicyService.CanUsePaidRandomItems(player) then
			sendResult(player, "PaidRandomItemsRestricted")
			return
		end
	end
	local canUseLuckyBlock = if source == "World"
		then canInteractWithLuckyBlock(player, group)
		else ValidationService.IsPlayerAlive(player)
			and ValidationService.ValidateRewardEligibility(player, "LuckyBlockInteraction")
	if not canUseLuckyBlock then
		sendResult(player, "InvalidRequest")
		return
	end
	if ROLL_EVENT_GATED_GROUPS[group] and not isLiveEventActive(group) then
		sendResult(player, "EventInactive")
		return
	end

	if not PetConfig.GetPetsForLuckyBlock(group) then
		sendResult(player, "ProductUnavailable")
		return
	end

	if purchaseKind == "Wins" or purchaseKind == "Candy" then
		if purchaseKind == "Wins" and group ~= "Tier1" and group ~= "Tier2" and group ~= "Tier3" then
			sendResult(player, "InvalidRequest")
			return
		end
		if purchaseKind == "Candy" and group ~= "Halloween" then
			sendResult(player, "InvalidRequest")
			return
		end
		local definition = PetConfig.LuckyBlocks[group]
		local candyPrices = PetConfig.LuckyBlocks.Event.eventCandyPricePerRoll
		local costPerRoll: number? = nil
		if purchaseKind == "Candy" then
			costPerRoll = candyPrices and candyPrices[group]
		elseif definition then
			costPerRoll = definition.winCostPerRoll
		end
		if typeof(costPerRoll) ~= "number" or costPerRoll <= 0 then
			sendResult(player, "ProductUnavailable")
			return
		end
		if PetInventoryService.GetAvailableCapacity(player) < rollCount then
			sendResult(player, "InventoryFull")
			return
		end
		local petIds = rollPetIds(player, group, rollCount)
		if not petIds then
			sendResult(player, "ProductUnavailable")
			return
		end
		local totalCost = costPerRoll * rollCount
		local previousWins: number? = nil
		if purchaseKind == "Wins" then
			local winCount = player:GetAttribute("WinCount")
			if
				typeof(winCount) ~= "number"
				or winCount ~= winCount
				or winCount == math.huge
				or winCount < totalCost
			then
				sendResult(player, "NotEnoughWins")
				return
			end
			previousWins = winCount
			if not PlayerHandler.SpendWins(player, totalCost) then
				sendResult(player, "NotEnoughWins")
				return
			end
		elseif not HalloweenCandyService.TrySpendCandy(player, totalCost) then
			sendResult(player, "NotEnoughCandy")
			return
		end
		local granted = PetInventoryService.GrantLuckyBlockPets(player, group, petIds)
		if not granted then
			if purchaseKind == "Wins" and previousWins then
				player:SetAttribute("WinCount", previousWins)
			elseif purchaseKind == "Candy" and not HalloweenCandyService.RefundCandy(player, totalCost) then
				DebugModule.debugWarn("Candy refund failed after Lucky Block grant failure | player=" .. player.Name, MODULE_NAME)
			end
			sendResult(player, "GrantFailed")
			return
		end
		sendResult(player, "RollResolved", createRollResult(player, petIds))
		DebugModule.debugInfo(
			string.format(
				"Lucky Block %s roll granted | player=%s | group=%s | count=%d | cost=%d",
				purchaseKind,
				player.Name,
				group,
				rollCount,
				totalCost
			),
			MODULE_NAME
		)
		return
	end

	local productId = getPaidRollProductId(group, rollCount)
	if not productId then
		sendResult(player, "ProductUnavailable")
		return
	end
	if not PurchasePrompt or not PurchasePrompt:IsA("RemoteEvent") then
		DebugModule.debugWarn("PurchasePrompt remote unavailable", MODULE_NAME)
		sendResult(player, "ProductUnavailable")
		return
	end
	(PurchasePrompt :: RemoteEvent):FireClient(player, "Product", productId)
	sendResult(player, "ProductPrompted", productId)
end

function PetLuckyBlockPurchaseService.GrantDailyRewardRoll(
	player: Player,
	group: "Premium" | "Tier3"
): (boolean, string?, number)
	if player:GetAttribute("Data_Loaded") ~= true then
		return false, nil, 0
	end

	local petIds = rollPetIds(player, group, 1)
	if not petIds or #petIds ~= 1 then
		DebugModule.debugWarn("Daily Lucky Block roll returned no pet | group=" .. group, MODULE_NAME)
		return false, nil, 0
	end

	local petId = petIds[1]
	if not petId then
		DebugModule.debugWarn("Daily Lucky Block roll returned no pet | group=" .. group, MODULE_NAME)
		return false, nil, 0
	end

	local granted, overflowCount = PetInventoryService.GrantLuckyBlockPets(player, group, petIds)
	if not granted then
		DebugModule.debugWarn("Daily Lucky Block pet grant failed | group=" .. group, MODULE_NAME)
		return false, nil, 0
	end

	DebugModule.debugInfo(
		string.format("Daily Lucky Block roll granted | player=%s | group=%s", player.Name, group),
		MODULE_NAME
	)
	if DailyRewardReveal then
		DailyRewardReveal:FireClient(player, {
			group = group,
			petIds = petIds,
			fasterOpen = isFastOpenEnabled(player),
		})
	end
	return true, petId, overflowCount
end

function PetLuckyBlockPurchaseService.Init(): ()
	if INITIALIZED then
		return
	end
	if not RollRequest or not RollResult then
		DebugModule.debugWarn("Lucky Block purchase remotes unavailable; service not initialized", MODULE_NAME)
		return
	end
	INITIALIZED = true
	SERVICE_MAID:GiveTask(RollRequest.OnServerEvent:Connect(processRequest))
	if FastOpenPreference then
		SERVICE_MAID:GiveTask(FastOpenPreference.OnServerEvent:Connect(processFastOpenPreference))
	else
		DebugModule.debugWarn("Fast Open preference remote unavailable", MODULE_NAME)
	end
	SERVICE_MAID:GiveTask(Players.PlayerRemoving:Connect(function(player: Player)
		LAST_REQUEST_AT[player] = nil
		FAST_OPEN_PREFERENCE_REQUEST_AT[player] = nil
		for receiptId, result in pairs(RECEIPT_ROLL_RESULTS) do
			if result.userId == player.UserId then
				RECEIPT_ROLL_RESULTS[receiptId] = nil
			end
		end
	end))
	watchLiveEventState()
	local promptBindingThread = task.spawn(bindLuckyBlockOpenPrompts)
	SERVICE_MAID:GiveTask(promptBindingThread)

	for _, group in ipairs(BLOCK_GROUPS) do
		for _, rollCount in ipairs({ 1, 3, 5 }) do
			local typedGroup = group :: LuckyBlockGroup
			local typedCount = rollCount :: RollCount
			local productId = getPaidRollProductId(typedGroup, typedCount)
			if productId then
				ProductServerService.SetProductCallback(
					productId,
					function(
						player: Player,
						callbackProductId: number,
						_bought: boolean,
						receiptId: string?,
						_purchaseChannel: EnumItem?,
						grantSource: string?
					): (boolean, string)
						if callbackProductId ~= productId then
							return false, "LuckyBlockProductIdMismatch"
						end
						if player:GetAttribute("Data_Loaded") ~= true then
							return false, "PlayerDataNotLoaded"
						end
						if not PetPaidRandomItemPolicyService.CanUsePaidRandomItems(player) then
							return false, "PaidRandomItemsRestricted"
						end
						if grantSource == "CreatorGrant" and not CreatorPurchaseService.IsExperienceCreator(player) then
							return false, "CreatorGrantNotAuthorized"
						end
						if grantSource ~= "CreatorGrant" and (typeof(receiptId) ~= "string" or receiptId == "") then
							return false, "ReceiptIdMissing"
						end

						local petIds = rollPetIds(player, typedGroup, typedCount)
						if not petIds then
							return false, "LuckyBlockPoolUnavailable"
						end
						local granted, overflowCount =
							PetInventoryService.GrantLuckyBlockPets(player, typedGroup, petIds)
						if not granted then
							return false, "LuckyBlockPetGrantFailed"
						end

						if grantSource == "CreatorGrant" then
							sendResult(player, "RollResolved", createRollResult(player, petIds))
							return true, "CreatorTestConsumed"
						end

						RECEIPT_ROLL_RESULTS[receiptId :: string] = {
							userId = player.UserId,
							group = typedGroup,
							petIds = petIds,
							overflowCount = overflowCount,
						}
						return true, "LuckyBlockPetsGranted"
					end
				)
				ProductServerService.SetProductGrantedCallback(
					productId,
					function(player: Player, _callbackProductId: number, receiptId: string): ()
						local result = RECEIPT_ROLL_RESULTS[receiptId]
						if not result or result.userId ~= player.UserId then
							return
						end
						RECEIPT_ROLL_RESULTS[receiptId] = nil
						sendResult(player, "RollResolved", createRollResult(player, result.petIds))
						if result.overflowCount > 0 then
							notify(
								player,
								"BACKPACK FULL! "
									.. tostring(result.overflowCount)
									.. " PET(S) STORED UNTIL SPACE OPENS.",
								"Gold"
							)
						end
					end
				)
			else
				DebugModule.debugWarn(
					"Lucky Block product callback skipped; catalog ID missing | group="
						.. group
						.. " | count="
						.. tostring(rollCount),
					MODULE_NAME
				)
			end
		end
	end
	DebugModule.debugInfo("Lucky Block rolls initialized with receipt-safe inventory grants", MODULE_NAME)
end

function PetLuckyBlockPurchaseService.Destroy(): ()
	if not INITIALIZED then
		return
	end
	INITIALIZED = false
	SERVICE_MAID:DoCleaning()
	liveEventStateFolder = nil
	for model in pairs(table.clone(MODEL_PROMPT_MAIDS)) do
		clearModelPromptBindings(model)
	end
	for player in pairs(table.clone(LAST_REQUEST_AT)) do
		LAST_REQUEST_AT[player] = nil
	end
	table.clear(FAST_OPEN_PREFERENCE_REQUEST_AT)
	table.clear(RECEIPT_ROLL_RESULTS)
end

return PetLuckyBlockPurchaseService
