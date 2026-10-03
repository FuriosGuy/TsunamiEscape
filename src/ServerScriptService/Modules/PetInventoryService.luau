--!strict

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PetConfig = require(ReplicatedStorage.Modules.Config.PetConfig)
local DebugModule = require(ReplicatedStorage.Modules.DebugModule)

type PetRecord = {
	uid: string,
	petId: string,
	stars: number,
	equipped: boolean,
}

type PetEntry = {
	definition: PetConfig.PetDefinition,
	paid: boolean,
}

type RankedPet = {
	record: PetRecord,
	multiplier: number,
}

local PetInventoryService = {}
local MODULE_NAME = "PetInventoryService"
local INVENTORY_ATTRIBUTE = "Pet_Inventory"
local EQUIPPED_MULTIPLIER_ATTRIBUTE = "Pet_EquippedMultiplier"
local EQUIPPED_MULTIPLIER_FALLBACK = PetConfig.Multiplier.emptyPetContribution
local BACKPACK_CAPACITY_ATTRIBUTE = "Pet_BackpackCapacity"
local EQUIP_CAPACITY_ATTRIBUTE = "Pet_EquipSlotCapacity"
local OVERFLOW_ATTRIBUTE = "Pet_OverflowClaims"
local MAX_DELETE_REQUEST_IDS = 500
local REMOTE_COOLDOWN_SECONDS = 0.15

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ActionRemote = Remotes:WaitForChild("PetInventoryAction") :: RemoteEvent
local ShowNotification = Remotes:WaitForChild("ShowNotification") :: RemoteEvent
local randomGenerator = Random.new()
local lastActionAt: { [Player]: number } = {}
local equippedMultipliers: { [Player]: number } = {}
local inventoryChangedConnections: { [Player]: RBXScriptConnection } = {}
local capacityChangedConnections: { [Player]: RBXScriptConnection } = {}
local overflowChangedConnections: { [Player]: RBXScriptConnection } = {}
local dataLoadedConnections: { [Player]: RBXScriptConnection } = {}
local petEntries: { [string]: PetEntry } = {}
local rarityPets: { [string]: { string } } = {
	Common = {},
	Rare = {},
	Epic = {},
	Legendary = {},
	Mythic = {},
}
local initialized = false
local remoteConnection: RBXScriptConnection? = nil
local playerRemovingConnection: RBXScriptConnection? = nil
local playerAddedConnection: RBXScriptConnection? = nil

local function registerLuckyBlockPets(luckyBlock: PetConfig.LuckyBlockDefinition, paid: boolean)
	local function register(pet: PetConfig.PetDefinition)
		petEntries[pet.id] = { definition = pet, paid = paid }
		local rarityList = rarityPets[pet.rarity]
		if rarityList then
			table.insert(rarityList, pet.id)
		end
	end

	for _, pet in ipairs(luckyBlock.pets or {}) do
		register(pet)
	end
	for _, eventPool in pairs(luckyBlock.eventPools or {}) do
		for _, pet in ipairs(eventPool.pets) do
			register(pet)
		end
	end
end

for _, luckyBlockId in ipairs({ "Tier1", "Tier2", "Tier3", "Premium", "Event" }) do
	local luckyBlock = PetConfig.LuckyBlocks[luckyBlockId :: PetConfig.LuckyBlockId]
	if luckyBlock then
		registerLuckyBlockPets(luckyBlock, luckyBlock.rollCurrency == "Robux")
	end
end

local function notify(player: Player, message: string, color: string)
	ShowNotification:FireClient(player, message, color)
end

local function readCapacity(player: Player, attributeName: string, defaultValue: number): number
	local value = player:GetAttribute(attributeName)
	if typeof(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return defaultValue
	end
	return math.floor(value)
end

local function readInventory(player: Player): { PetRecord }
	local encoded = player:GetAttribute(INVENTORY_ATTRIBUTE)
	if typeof(encoded) ~= "string" or encoded == "" then
		return {}
	end

	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not ok or typeof(decoded) ~= "table" then
		DebugModule.debugWarn("Invalid saved inventory JSON | player=" .. player.Name, MODULE_NAME)
		return {}
	end

	local inventory: { PetRecord } = {}
	for _, value in ipairs(decoded) do
		if typeof(value) == "table"
			and typeof(value.uid) == "string"
			and typeof(value.petId) == "string"
			and petEntries[value.petId] ~= nil
			and typeof(value.stars) == "number"
			and value.stars >= 1
			and value.stars <= PetConfig.StarUpgrades.maxStars
			and typeof(value.equipped) == "boolean"
		then
			table.insert(inventory, {
				uid = value.uid,
				petId = value.petId,
				stars = math.floor(value.stars),
				equipped = value.equipped,
			})
		end
	end
	return inventory
end

local function updateEquippedMultiplier(player: Player): ()
	local totalMultiplier = EQUIPPED_MULTIPLIER_FALLBACK
	local equippedCount = 0
	for _, pet in ipairs(readInventory(player)) do
		if pet.equipped then
			local entry = petEntries[pet.petId]
			if entry then
				local petMultiplier = PetConfig.GetPetMultiplier(
					entry.definition.multiplier,
					entry.definition.rarity,
					entry.paid,
					pet.stars
				)
				totalMultiplier += math.max(0, petMultiplier - EQUIPPED_MULTIPLIER_FALLBACK)
				equippedCount += 1
			end
		end
	end
	local resolvedMultiplier = if equippedCount > 0 then totalMultiplier else EQUIPPED_MULTIPLIER_FALLBACK
	local previousMultiplier = equippedMultipliers[player]
	equippedMultipliers[player] = resolvedMultiplier
	if player:GetAttribute(EQUIPPED_MULTIPLIER_ATTRIBUTE) ~= resolvedMultiplier then
		player:SetAttribute(EQUIPPED_MULTIPLIER_ATTRIBUTE, resolvedMultiplier)
	end
	if previousMultiplier ~= resolvedMultiplier then
		DebugModule.debugInfo(
			string.format(
				"Equipped pet multiplier updated | player=%s | count=%d | multiplier=%.2fx",
				player.Name,
				equippedCount,
				resolvedMultiplier
			),
			MODULE_NAME
		)
	end
end

local claimOverflow: (player: Player) -> ()

local function bindPlayerInventory(player: Player): ()
	local previousConnection = inventoryChangedConnections[player]
	if previousConnection then
		previousConnection:Disconnect()
	end
	inventoryChangedConnections[player] = player:GetAttributeChangedSignal(INVENTORY_ATTRIBUTE):Connect(function()
		updateEquippedMultiplier(player)
	end)
	local previousCapacityConnection = capacityChangedConnections[player]
	if previousCapacityConnection then
		previousCapacityConnection:Disconnect()
	end
	capacityChangedConnections[player] = player:GetAttributeChangedSignal(BACKPACK_CAPACITY_ATTRIBUTE):Connect(function()
		claimOverflow(player)
	end)
	local previousOverflowConnection = overflowChangedConnections[player]
	if previousOverflowConnection then
		previousOverflowConnection:Disconnect()
	end
	overflowChangedConnections[player] = player:GetAttributeChangedSignal(OVERFLOW_ATTRIBUTE):Connect(function()
		claimOverflow(player)
	end)
	local previousDataLoadedConnection = dataLoadedConnections[player]
	if previousDataLoadedConnection then
		previousDataLoadedConnection:Disconnect()
	end
	dataLoadedConnections[player] = player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
		if player:GetAttribute("Data_Loaded") == true then
			claimOverflow(player)
		end
	end)
	updateEquippedMultiplier(player)
	if player:GetAttribute("Data_Loaded") == true then
		claimOverflow(player)
	end
end

local function writeInventory(player: Player, inventory: { PetRecord })
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, inventory)
	if not ok then
		DebugModule.debugError(
			"Inventory encode failed | player=" .. player.Name,
			encoded,
			MODULE_NAME
		)
		return false
	end
	player:SetAttribute(INVENTORY_ATTRIBUTE, encoded)
	updateEquippedMultiplier(player)
	return true
end

local function decodePetRecords(player: Player, attributeName: string): ({ PetRecord }?, boolean)
	local encoded = player:GetAttribute(attributeName)
	if typeof(encoded) ~= "string" or encoded == "" then
		return {}, true
	end

	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, encoded)
	if not ok or typeof(decoded) ~= "table" then
		DebugModule.debugWarn(
			"Invalid pet storage JSON | player=" .. player.Name .. " | attribute=" .. attributeName,
			MODULE_NAME
		)
		return nil, false
	end

	local records: { PetRecord } = {}
	for _, value in ipairs(decoded) do
		if typeof(value) ~= "table"
			or typeof(value.uid) ~= "string"
			or typeof(value.petId) ~= "string"
			or petEntries[value.petId] == nil
			or typeof(value.stars) ~= "number"
			or value.stars < 1
			or value.stars > PetConfig.StarUpgrades.maxStars
			or typeof(value.equipped) ~= "boolean"
		then
			DebugModule.debugWarn(
				"Invalid pet storage record | player=" .. player.Name .. " | attribute=" .. attributeName,
				MODULE_NAME
			)
			return nil, false
		end
		table.insert(records, {
			uid = value.uid,
			petId = value.petId,
			stars = math.floor(value.stars),
			equipped = value.equipped,
		})
	end
	return records, true
end

local function writePetStorage(player: Player, inventory: { PetRecord }, overflow: { PetRecord }): boolean
	local inventoryOk, encodedInventory = pcall(HttpService.JSONEncode, HttpService, inventory)
	local overflowOk, encodedOverflow = pcall(HttpService.JSONEncode, HttpService, overflow)
	if not inventoryOk or not overflowOk then
		DebugModule.debugError(
			"Pet storage encode failed | player=" .. player.Name,
			if not inventoryOk then encodedInventory else encodedOverflow,
			MODULE_NAME
		)
		return false
	end

	player:SetAttribute(INVENTORY_ATTRIBUTE, encodedInventory)
	player:SetAttribute(OVERFLOW_ATTRIBUTE, encodedOverflow)
	updateEquippedMultiplier(player)
	return true
end

local function isPetInGroup(petId: string, group: PetConfig.LuckyBlockGroup): boolean
	local pets = PetConfig.GetPetsForLuckyBlock(group)
	if not pets then
		return false
	end
	for _, pet in ipairs(pets) do
		if pet.id == petId then
			return true
		end
	end
	return false
end

local function grantLuckyBlockPets(
	player: Player,
	group: PetConfig.LuckyBlockGroup,
	petIds: { string }
): (boolean, number)
	if player:GetAttribute("Data_Loaded") ~= true or (#petIds ~= 1 and #petIds ~= 3 and #petIds ~= 5) then
		return false, 0
	end

	local inventory, inventoryValid = decodePetRecords(player, INVENTORY_ATTRIBUTE)
	local overflow, overflowValid = decodePetRecords(player, OVERFLOW_ATTRIBUTE)
	if not inventoryValid or not overflowValid or not inventory or not overflow then
		return false, 0
	end

	for _, petId in ipairs(petIds) do
		if typeof(petId) ~= "string" or not isPetInGroup(petId, group) then
			DebugModule.debugWarn("Rejected invalid Lucky Block pet grant | group=" .. group, MODULE_NAME)
			return false, 0
		end
	end

	local capacity = readCapacity(player, BACKPACK_CAPACITY_ATTRIBUTE, PetConfig.Storage.startingCapacity)
	local availableSlots = math.max(capacity - #inventory, 0)
	local overflowCount = 0
	for index, petId in ipairs(petIds) do
		local record: PetRecord = {
			uid = HttpService:GenerateGUID(false),
			petId = petId,
			stars = 1,
			equipped = false,
		}
		if index <= availableSlots then
			table.insert(inventory, record)
		else
			table.insert(overflow, record)
			overflowCount += 1
		end
	end

	return writePetStorage(player, inventory, overflow), overflowCount
end

local function getAvailableCapacity(player: Player): number
	local inventory, valid = decodePetRecords(player, INVENTORY_ATTRIBUTE)
	if not valid or not inventory then
		return 0
	end
	local capacity = readCapacity(player, BACKPACK_CAPACITY_ATTRIBUTE, PetConfig.Storage.startingCapacity)
	return math.max(capacity - #inventory, 0)
end

claimOverflow = function(player: Player): ()
	local inventory, inventoryValid = decodePetRecords(player, INVENTORY_ATTRIBUTE)
	local overflow, overflowValid = decodePetRecords(player, OVERFLOW_ATTRIBUTE)
	if not inventoryValid or not overflowValid or not inventory or not overflow or #overflow == 0 then
		return
	end

	local capacity = readCapacity(player, BACKPACK_CAPACITY_ATTRIBUTE, PetConfig.Storage.startingCapacity)
	local claimCount = math.min(math.max(capacity - #inventory, 0), #overflow)
	if claimCount <= 0 then
		return
	end

	for index = 1, claimCount do
		table.insert(inventory, overflow[index])
	end
	local remainingOverflow: { PetRecord } = {}
	for index = claimCount + 1, #overflow do
		table.insert(remainingOverflow, overflow[index])
	end
	if writePetStorage(player, inventory, remainingOverflow) then
		notify(player, "CLAIMED " .. tostring(claimCount) .. " STORED PET(S)!", "Green")
	end
end

local function countEquipped(inventory: { PetRecord }): number
	local count = 0
	for _, pet in ipairs(inventory) do
		if pet.equipped then
			count += 1
		end
	end
	return count
end

local function findPetIndex(inventory: { PetRecord }, uid: string): number?
	for index, pet in ipairs(inventory) do
		if pet.uid == uid then
			return index
		end
	end
	return nil
end

local function addRandomPet(player: Player, rarity: string)
	if not RunService:IsStudio() then
		return
	end
	local petIds = rarityPets[rarity]
	if not petIds or #petIds == 0 then
		return
	end

	local inventory = readInventory(player)
	if #inventory >= readCapacity(player, BACKPACK_CAPACITY_ATTRIBUTE, PetConfig.Storage.startingCapacity) then
		notify(player, "BACKPACK FULL!", "Red")
		return
	end

	local petId = petIds[randomGenerator:NextInteger(1, #petIds)]
	table.insert(inventory, {
		uid = HttpService:GenerateGUID(false),
		petId = petId,
		stars = 1,
		equipped = false,
	})
	writeInventory(player, inventory)
end

local function setEquipped(player: Player, uid: string)
	local inventory = readInventory(player)
	local index = findPetIndex(inventory, uid)
	if not index then
		return
	end

	local pet = inventory[index]
	if pet.equipped then
		pet.equipped = false
	else
		if countEquipped(inventory) >= readCapacity(player, EQUIP_CAPACITY_ATTRIBUTE, PetConfig.Equip.startingSlots) then
			notify(player, "ALL PET SLOTS EQUIPPED!", "Red")
			return
		end
		pet.equipped = true
	end
	writeInventory(player, inventory)
end

local function equipBest(player: Player): ()
	local inventory = readInventory(player)
	if #inventory == 0 then
		notify(player, "NO PETS TO EQUIP!", "Red")
		return
	end

	local rankedPets: { RankedPet } = {}
	for _, pet in ipairs(inventory) do
		local entry = petEntries[pet.petId]
		if entry then
			table.insert(rankedPets, {
				record = pet,
				multiplier = PetConfig.GetPetMultiplier(
					entry.definition.multiplier,
					entry.definition.rarity,
					entry.paid,
					pet.stars
				),
			})
		end
	end

	table.sort(rankedPets, function(left: RankedPet, right: RankedPet): boolean
		if left.multiplier ~= right.multiplier then
			return left.multiplier > right.multiplier
		end
		if left.record.stars ~= right.record.stars then
			return left.record.stars > right.record.stars
		end
		if left.record.petId ~= right.record.petId then
			return left.record.petId < right.record.petId
		end
		return left.record.uid < right.record.uid
	end)

	local equipCapacity = readCapacity(player, EQUIP_CAPACITY_ATTRIBUTE, PetConfig.Equip.startingSlots)
	local selectedUids: { [string]: boolean } = {}
	local targetCount = math.min(equipCapacity, #rankedPets)
	for index = 1, targetCount do
		selectedUids[rankedPets[index].record.uid] = true
	end

	local changed = false
	for _, pet in ipairs(inventory) do
		local shouldEquip = selectedUids[pet.uid] == true
		if pet.equipped ~= shouldEquip then
			pet.equipped = shouldEquip
			changed = true
		end
	end

	if targetCount == 0 then
		if changed then
			writeInventory(player, inventory)
		end
		notify(player, "NO EQUIP SLOTS AVAILABLE!", "Red")
		return
	end

	if changed then
		if writeInventory(player, inventory) then
			notify(player, "EQUIPPED BEST PETS!", "Green")
		end
	else
		notify(player, "BEST PETS ALREADY EQUIPPED!", "Green")
	end
end

local function unequipAll(player: Player): ()
	local inventory = readInventory(player)
	local changed = false
	for _, pet in ipairs(inventory) do
		if pet.equipped then
			pet.equipped = false
			changed = true
		end
	end

	if changed and writeInventory(player, inventory) then
		notify(player, "ALL PETS UNEQUIPPED!", "Green")
	end
end

local function deletePets(player: Player, ids: { string })
	local inventory = readInventory(player)
	local requested: { [string]: boolean } = {}
	for _, uid in ipairs(ids) do
		if typeof(uid) == "string" then
			requested[uid] = true
		end
	end
	if next(requested) == nil then
		notify(player, "SELECT PETS TO DELETE!", "Red")
		return
	end

	local kept: { PetRecord } = {}
	local removed = 0
	for _, pet in ipairs(inventory) do
		if requested[pet.uid] then
			if pet.equipped then
				notify(player, "UNEQUIP PETS BEFORE DELETING!", "Red")
				return
			end
			removed += 1
		else
			table.insert(kept, pet)
		end
	end
	if removed == 0 then
		notify(player, "NO PETS SELECTED!", "Red")
		return
	end
	if writeInventory(player, kept) then
		claimOverflow(player)
	end
end

local function mergeAll(player: Player)
	local inventory = readInventory(player)
	local mergedCount = 0
	for petId, entry in pairs(petEntries) do
		local rule = PetConfig.StarUpgrades.byRarity[entry.definition.rarity]
		if rule then
			for stars = 1, PetConfig.StarUpgrades.maxStars - 1 do
				local required = if stars == 1 then rule.copiesToTwoStars else rule.copiesToThreeStars
				local eligible: { PetRecord } = {}
				for _, pet in ipairs(inventory) do
					if pet.petId == petId and pet.stars == stars and not pet.equipped then
						table.insert(eligible, pet)
					end
				end
				while #eligible >= required do
					local consumed: { [string]: boolean } = {}
					for index = 1, required do
						consumed[eligible[index].uid] = true
					end
					local remaining: { PetRecord } = {}
					for _, pet in ipairs(inventory) do
						if not consumed[pet.uid] then
							table.insert(remaining, pet)
						end
					end
					table.insert(remaining, {
						uid = HttpService:GenerateGUID(false),
						petId = petId,
						stars = stars + 1,
						equipped = false,
					})
					inventory = remaining
					mergedCount += 1
					table.clear(eligible)
					for _, pet in ipairs(inventory) do
						if pet.petId == petId and pet.stars == stars and not pet.equipped then
							table.insert(eligible, pet)
						end
					end
				end
			end
		end
	end

	if mergedCount == 0 then
		notify(player, "NO PETS READY TO MERGE!", "Red")
		return
	end
	if writeInventory(player, inventory) then
		claimOverflow(player)
		notify(player, "MERGED " .. tostring(mergedCount) .. " PET(S)!", "Green")
	end
end

local function processAction(player: Player, action: string, payload: any)
	if player:GetAttribute("Data_Loaded") ~= true then
		return
	end
	if action == "AddRandom" then
		if typeof(payload) == "string" then
			addRandomPet(player, payload)
		end
	elseif action == "Equip" then
		if typeof(payload) == "string" then
			setEquipped(player, payload)
		end
	elseif action == "EquipBest" and payload == nil then
		equipBest(player)
	elseif action == "UnequipAll" and payload == nil then
		unequipAll(player)
	elseif action == "Delete" then
		if typeof(payload) == "string" and #payload <= 64 then
			deletePets(player, { payload })
		end
	elseif action == "DeleteMany" then
		if typeof(payload) == "table" then
			local validIds: { string } = {}
			local validPayload = true
			for index, uid in pairs(payload) do
				if typeof(index) ~= "number" or index % 1 ~= 0 or typeof(uid) ~= "string" or #uid > 64 then
					validPayload = false
					break
				end
				table.insert(validIds, uid)
				if #validIds > MAX_DELETE_REQUEST_IDS then
					validPayload = false
					break
				end
			end
			if validPayload then
				deletePets(player, validIds)
			end
		end
	elseif action == "MergeAll" and payload == nil then
		mergeAll(player)
	end
end

function PetInventoryService.Init()
	if initialized then
		return
	end
	initialized = true
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayerInventory(player)
	end
	playerAddedConnection = Players.PlayerAdded:Connect(bindPlayerInventory)
	remoteConnection = ActionRemote.OnServerEvent:Connect(function(player: Player, action: any, payload: any)
		if typeof(action) ~= "string" or #action > 24 then
			return
		end
		local now = os.clock()
		local previous = lastActionAt[player] or 0
		if now - previous < REMOTE_COOLDOWN_SECONDS then
			return
		end
		lastActionAt[player] = now
		processAction(player, action, payload)
	end)
	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player: Player)
		lastActionAt[player] = nil
		equippedMultipliers[player] = nil
		local inventoryConnection = inventoryChangedConnections[player]
		if inventoryConnection then
			inventoryConnection:Disconnect()
			inventoryChangedConnections[player] = nil
		end
		local capacityConnection = capacityChangedConnections[player]
		if capacityConnection then
			capacityConnection:Disconnect()
			capacityChangedConnections[player] = nil
		end
		local overflowConnection = overflowChangedConnections[player]
		if overflowConnection then
			overflowConnection:Disconnect()
			overflowChangedConnections[player] = nil
		end
		local dataLoadedConnection = dataLoadedConnections[player]
		if dataLoadedConnection then
			dataLoadedConnection:Disconnect()
			dataLoadedConnections[player] = nil
		end
	end)
end

function PetInventoryService.GetEquippedMultiplier(player: Player): number
	return equippedMultipliers[player] or EQUIPPED_MULTIPLIER_FALLBACK
end

function PetInventoryService.GetAvailableCapacity(player: Player): number
	return getAvailableCapacity(player)
end

function PetInventoryService.GrantLuckyBlockPets(
	player: Player,
	group: PetConfig.LuckyBlockGroup,
	petIds: { string }
): (boolean, number)
	return grantLuckyBlockPets(player, group, petIds)
end

function PetInventoryService.Shutdown()
	if remoteConnection then
		remoteConnection:Disconnect()
		remoteConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	if playerAddedConnection then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end
	for player, connection in pairs(inventoryChangedConnections) do
		connection:Disconnect()
		inventoryChangedConnections[player] = nil
		equippedMultipliers[player] = nil
	end
	for player, connection in pairs(capacityChangedConnections) do
		connection:Disconnect()
		capacityChangedConnections[player] = nil
	end
	for player, connection in pairs(overflowChangedConnections) do
		connection:Disconnect()
		overflowChangedConnections[player] = nil
	end
	for player, connection in pairs(dataLoadedConnections) do
		connection:Disconnect()
		dataLoadedConnections[player] = nil
	end
	table.clear(lastActionAt)
	initialized = false
end

return PetInventoryService
