--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PetRarityConfig = require(ReplicatedStorage.Modules.Config.PetRarityConfig)

export type Rarity = PetRarityConfig.Rarity
export type LuckyBlockId = "Tier1" | "Tier2" | "Tier3" | "Premium" | "Event"
export type LuckyBlockKind = "Wins" | "Premium" | "Event"
export type RollCurrency = "Wins" | "Robux"
export type EventId = "BloodMoon" | "NeonRush" | "FrostbiteRally"
export type LuckyBlockGroup = "Tier1" | "Tier2" | "Tier3" | "Premium" | EventId

export type PetDefinition = {
	id: string,
	name: string,
	modelPath: string,
	rarity: Rarity,
	chanceWeight: number,
	multiplier: number,
}

export type EventPetPool = {
	pets: { PetDefinition },
}

export type LuckyBlockDefinition = {
	id: LuckyBlockId,
	displayName: string,
	kind: LuckyBlockKind,
	rollCurrency: RollCurrency,
	winCostPerRoll: number?,
	robuxPricePerRoll: number?,
	eventRobuxPricePerRoll: { [EventId]: number }?,
	pets: { PetDefinition }?,
	eventPools: { [EventId]: EventPetPool }?,
}

export type StarUpgradeRule = {
	copiesToTwoStars: number,
	copiesToThreeStars: number,
	bonusAtTwoStars: number,
	bonusAtThreeStars: number,
}

type StarUpgradeBonus = {
	bonusAtTwoStars: number,
	bonusAtThreeStars: number,
}

type OddsRemainder = {
	petId: string,
	units: number,
	remainder: number,
}

local function createPet(id: string, name: string, modelPath: string, rarity: Rarity, multiplier: number): PetDefinition
	return table.freeze({
		id = id,
		name = name,
		modelPath = modelPath,
		rarity = rarity,
		chanceWeight = PetRarityConfig.ChanceWeights[rarity],
		multiplier = multiplier,
	})
end

local function createStarUpgradeRule(
	copiesToTwoStars: number,
	copiesToThreeStars: number,
	bonusAtTwoStars: number,
	bonusAtThreeStars: number
): StarUpgradeRule
	return table.freeze({
		copiesToTwoStars = copiesToTwoStars,
		copiesToThreeStars = copiesToThreeStars,
		bonusAtTwoStars = bonusAtTwoStars,
		bonusAtThreeStars = bonusAtThreeStars,
	})
end

local LuckyBlocks: { [LuckyBlockId]: LuckyBlockDefinition } = table.freeze({
	Tier1 = table.freeze({
		id = "Tier1",
		displayName = "Tier 1 Lucky Block",
		kind = "Wins",
		rollCurrency = "Wins",
		winCostPerRoll = 100,
		robuxPricePerRoll = 19,
		pets = table.freeze({
			createPet("Tier1_TralaleroTralala", "Tralalero Tralala", "Tier1/04_Tralalero", "Common", 1.25),
			createPet("Tier1_BombardiroCrocodilo", "Bombardiro Crocodilo", "Tier1/02_Bombardiro", "Common", 1.25),
			createPet("Tier1_TungSahur", "Tung Tung Tung Sahur", "Tier1/06_Tung", "Common", 1.25),
			createPet("Tier1_BallerinaCappuccina", "Ballerina Cappuccina", "Tier1/01_Ballerina", "Common", 1.25),
			createPet("Tier1_ChimpanziniBananini", "Chimpanzini Bananini", "Tier1/03_Chimpanzini", "Common", 1.25),
			createPet("Tier1_TrippiTroppi", "Trippi Troppi", "Tier1/05_Trippi", "Common", 1.25),
			createPet("Tier1_LiriliLarila", "Lirili Larila", "Tier1/10_Lirili", "Rare", 1.55),
			createPet("Tier1_BrrBrrPatapim", "Brr Brr Patapim", "Tier1/07_Brr", "Rare", 1.55),
			createPet("Tier1_CappuccinoAssassino", "Cappuccino Assassino", "Tier1/08_Cappuccino", "Rare", 1.55),
			createPet("Tier1_CocofantoElefanto", "Cocofanto Elefanto", "Tier1/09_Cocofanto", "Rare", 1.55),
		}),
	}),
	Tier2 = table.freeze({
		id = "Tier2",
		displayName = "Tier 2 Lucky Block",
		kind = "Wins",
		rollCurrency = "Wins",
		winCostPerRoll = 5_000,
		robuxPricePerRoll = 39,
		pets = table.freeze({
			createPet("Tier2_LaGrandeCombinasion", "Gold La Grande Combinasion", "Tier2/01_LaGrande", "Common", 1.5),
			createPet("Tier2_Meowl", "Meowl", "Tier2/02_Meowl", "Common", 1.5),
			createPet("Tier2_CactoHipopotamo", "Cacto Hipopotamo", "Tier2/03_Cacto", "Common", 1.5),
			createPet("Tier2_BombombiniGusini", "Bombombini Gusini", "Tier2/04_Bombombini", "Rare", 2),
			createPet("Tier2_LiriliLarila", "Gold Lirili Larila", "Tier2/05_Lirili", "Rare", 2),
			createPet("Tier2_TralaleroTralala", "Gold Tralalero Tralala", "Tier2/06_Tralalero", "Rare", 2),
			createPet("Tier2_TungSahur", "Diamond Tung Sahur", "Tier2/07_Tung", "Epic", 2.75),
			createPet("Tier2_BallerinaCappuccina", "Diamond Ballerina Cappuccina", "Tier2/08_Ballerina", "Epic", 2.75),
			createPet("Tier2_TrippiTroppi", "Galaxy Trippi Troppi", "Tier2/09_Trippi", "Legendary", 4.25),
			createPet(
				"Tier2_CactoHipopotamoGalaxy",
				"Galaxy Cacto Hipopotamo",
				"Tier2/10_GalaxyCacto",
				"Legendary",
				4.25
			),
		}),
	}),
	Tier3 = table.freeze({
		id = "Tier3",
		displayName = "Tier 3 Lucky Block",
		kind = "Wins",
		rollCurrency = "Wins",
		winCostPerRoll = 50_000,
		robuxPricePerRoll = 59,
		pets = table.freeze({
			createPet("Tier3_StrawberryElephant", "Strawberry Elephant", "Tier3/02_Strawberry", "Legendary", 4.75),
			createPet("Tier3_OneByOneByOneByOne", "1x1x1x1", "Tier3/06_1x1x1x1", "Epic", 3.5),
			createPet("Tier3_SixSeven", "Six Seven", "Tier3/01_SixSeven", "Common", 1.75),
			createPet("Tier3_TungSahur", "Gold Tung Sahur", "Tier3/05_Tung", "Rare", 2.5),
			createPet("Tier3_TrippiTroppi", "Gold Trippi Troppi", "Tier3/04_Trippi", "Rare", 2.5),
			createPet("Tier3_BallerinaCappuccina", "Gold Ballerina Cappuccina", "Tier3/03_Ballerina", "Rare", 2.5),
			createPet("Tier3_TralaleroTralala", "Diamond Tralalero Tralala", "Tier3/08_Tralalero", "Epic", 3.5),
			createPet("Tier3_BombardiroCrocodilo", "Diamond Bombardiro Crocodilo", "Tier3/07_Bombardiro", "Epic", 3.5),
			createPet("Tier3_LiriliLarila", "Galaxy Lirili Larila", "Tier3/10_Lirili", "Epic", 3.5),
			createPet(
				"Tier3_ChimpanziniBananini",
				"Galaxy Chimpanzini Bananini",
				"Tier3/09_Chimpanzini",
				"Legendary",
				4.75
			),
		}),
	}),
	Premium = table.freeze({
		id = "Premium",
		displayName = "Premium Lucky Block",
		kind = "Premium",
		rollCurrency = "Robux",
		robuxPricePerRoll = 99,
		pets = table.freeze({
			createPet("Premium_ChimpanziniBananini", "Gold Chimpanzini Bananini", "Robux/01_Chimpanzini", "Epic", 4.5),
			createPet(
				"Premium_CappuccinoAssassino",
				"Diamond Cappuccino Assassino",
				"Robux/02_Cappuccino",
				"Epic",
				4.5
			),
			createPet("Premium_TralaleroTralala", "Galaxy Tralalero Tralala", "Robux/04_Tralalero", "Epic", 4.5),
			createPet("Premium_BombardiroCrocodilo", "Galaxy Bombardiro Crocodilo", "Robux/03_Bombardiro", "Epic", 4.5),
			createPet("Premium_Meowl", "Gold Meowl", "Robux/05_Meowl", "Legendary", 5.5),
			createPet(
				"Premium_LaGrandeCombinasion",
				"Galaxy La Grande Combinasion",
				"Robux/06_LaGrande",
				"Legendary",
				5.5
			),
			createPet(
				"Premium_StrawberryElephant",
				"Galaxy Strawberry Elephant",
				"Robux/07_Strawberry",
				"Legendary",
				5.5
			),
			createPet("Premium_OneByOneByOneByOne", "Hacker 1x1x1x1", "Robux/08_1x1x1x1", "Mythic", 13.5),
		}),
	}),
	Event = table.freeze({
		id = "Event",
		displayName = "Event Lucky Block",
		kind = "Event",
		rollCurrency = "Robux",
		eventRobuxPricePerRoll = table.freeze({
			BloodMoon = 129,
			NeonRush = 99,
			FrostbiteRally = 99,
		}),
		eventPools = table.freeze({
			BloodMoon = table.freeze({
				pets = table.freeze({
					createPet(
						"BloodMoon_BombardiroCrocodilo",
						"Bloodmoon Bombardiro Crocodilo",
						"BloodMoon/02_Bombardiro",
						"Epic",
						5.5
					),
					createPet(
						"BloodMoon_BallerinaCappuccina",
						"Bloodmoon Ballerina Cappuccina",
						"BloodMoon/01_Ballerina",
						"Epic",
						5.5
					),
					createPet(
						"BloodMoon_TralaleroTralala",
						"Bloodmoon Tralalero Tralala",
						"BloodMoon/04_Tralalero",
						"Legendary",
						7.5
					),
					createPet(
						"BloodMoon_CappuccinoAssassino",
						"Bloodmoon Cappuccino Assassino",
						"BloodMoon/03_Cappuccino",
						"Legendary",
						7.5
					),
				createPet("BloodMoon_TungSahur", "Bloodmoon Tung Sahur", "BloodMoon/05_Tung", "Mythic", 16),
				}),
			}),
			NeonRush = table.freeze({
				pets = table.freeze({
					createPet(
						"NeonRush_TralaleroTralala",
						"Neon Tralalero Tralala",
						"NeonRush/02_Neon_Tralalero",
						"Epic",
						4.5
					),
					createPet(
						"NeonRush_CappuccinoAssassino",
						"Neon Cappuccino Assassino",
						"NeonRush/01_Neon_Cappuccino",
						"Epic",
						4.5
					),
					createPet(
						"NeonRush_ChimpanziniBananini",
						"Neon Chimpanzini Bananini",
						"NeonRush/03_Neon_Chimpanzini",
						"Legendary",
						5.5
					),
					createPet(
						"NeonRush_LaGrandeCombinasion",
						"Neon La Grande Combinasion",
						"NeonRush/04_Neon_Combinasion",
						"Legendary",
						5.5
					),
					createPet("NeonRush_TungSahur", "Neon Tung Sahur", "NeonRush/05_Neon_Tung", "Mythic", 13.5),
				}),
			}),
			FrostbiteRally = table.freeze({
				pets = table.freeze({
					createPet(
						"FrostbiteRally_LiriliLarila",
						"Diamond Lirili Larila",
						"FrostbiteRally/01_Lirili",
						"Epic",
						4.5
					),
					createPet("FrostbiteRally_Meowl", "Diamond Meowl", "FrostbiteRally/02_Meowl", "Epic", 4.5),
					createPet(
						"FrostbiteRally_BlueberrinniOctopusini",
						"Diamond Blueberrinni Octopusini",
						"FrostbiteRally/03_Blueberrinni",
						"Legendary",
						5.5
					),
					createPet(
						"FrostbiteRally_CactoHipopotamo",
						"Diamond Cacto Hipopotamo",
						"FrostbiteRally/04_Cacto",
						"Legendary",
						5.5
					),
					createPet(
						"FrostbiteRally_DragonCannelloni",
						"Diamond Dragon Cannelloni",
						"FrostbiteRally/05_Dragon",
						"Mythic",
						13.5
					),
				}),
			}),
		}),
	}),
})

local StarUpgradeRules = table.freeze({
	maxStars = 3,
	byRarity = table.freeze({
		Common = createStarUpgradeRule(5, 5, 0.5, 1),
		Rare = createStarUpgradeRule(4, 4, 0.75, 1.5),
		Epic = createStarUpgradeRule(3, 3, 1.25, 2.5),
		Legendary = createStarUpgradeRule(3, 3, 1.5, 3),
		Mythic = createStarUpgradeRule(3, 3, 5, 10),
	}),
})

local PaidStarBonuses: { [Rarity]: StarUpgradeBonus } = table.freeze({
	Epic = table.freeze({ bonusAtTwoStars = 1.75, bonusAtThreeStars = 3.5 }),
	Legendary = table.freeze({ bonusAtTwoStars = 3.5, bonusAtThreeStars = 7 }),
	Mythic = table.freeze({ bonusAtTwoStars = 6, bonusAtThreeStars = 12 }),
})

local LuckRarityWeightBonus: { [Rarity]: number } = table.freeze({
	Common = 0,
	Rare = 0.15,
	Epic = 0.35,
	Legendary = 0.7,
	Mythic = 3,
})

local function GetPetsForLuckyBlock(group: LuckyBlockGroup): { PetDefinition }?
	if group == "Tier1" or group == "Tier2" or group == "Tier3" or group == "Premium" then
		return LuckyBlocks[group].pets
	end
	local eventPools = LuckyBlocks.Event.eventPools
	local eventPool = if eventPools then eventPools[group] else nil
	return if eventPool then eventPool.pets else nil
end

local function IsLuckyBlockPaid(group: LuckyBlockId | LuckyBlockGroup): boolean
	if group == "Tier1" or group == "Tier2" or group == "Tier3" or group == "Premium" then
		return LuckyBlocks[group].rollCurrency == "Robux"
	elseif group == "Event" then
		return LuckyBlocks.Event.rollCurrency == "Robux"
	end

	local eventPools = LuckyBlocks.Event.eventPools
	return LuckyBlocks.Event.rollCurrency == "Robux" and eventPools ~= nil and eventPools[group] ~= nil
end

local function GetLuckAdjustedWeight(pet: PetDefinition, luckMultiplier: number): number
	local luck = luckMultiplier
	if luck ~= luck or luck == math.huge or luck < 1 then
		luck = 1
	end
	luck = math.min(luck, 10)

	local luckProgress = math.log(luck) / math.log(10)
	local rarityBonus = LuckRarityWeightBonus[pet.rarity] or 0
	return pet.chanceWeight * (1 + luckProgress * rarityBonus)
end

local function GetLuckyBlockOdds(group: LuckyBlockGroup, luckMultiplier: number): { [string]: number }?
	local pets = GetPetsForLuckyBlock(group)
	if not pets or #pets == 0 then
		return nil
	end

	local totalWeight = 0
	local weightedPets: { { petId: string, weight: number } } = {}
	for _, pet in ipairs(pets) do
		local weight = GetLuckAdjustedWeight(pet, luckMultiplier)
		if weight == weight and weight > 0 and weight < math.huge then
			totalWeight += weight
			table.insert(weightedPets, { petId = pet.id, weight = weight })
		end
	end
	if totalWeight <= 0 or #weightedPets == 0 then
		return nil
	end

	-- Largest-remainder rounding keeps four-decimal displayed odds summing to exactly 100%.
	local totalUnits = 1_000_000
	local assignedUnits = 0
	local remainders: { OddsRemainder } = {}
	for _, entry in ipairs(weightedPets) do
		local exactUnits = entry.weight / totalWeight * totalUnits
		local units = math.floor(exactUnits)
		assignedUnits += units
		table.insert(remainders, {
			petId = entry.petId,
			units = units,
			remainder = exactUnits - units,
		})
	end
	table.sort(remainders, function(left: OddsRemainder, right: OddsRemainder): boolean
		if left.remainder == right.remainder then
			return left.petId < right.petId
		end
		return left.remainder > right.remainder
	end)
	local unassignedUnits = totalUnits - assignedUnits
	for index = 1, unassignedUnits do
		local entry = remainders[((index - 1) % #remainders) + 1]
		entry.units += 1
	end

	local oddsByPetId: { [string]: number } = {}
	for _, entry in ipairs(remainders) do
		oddsByPetId[entry.petId] = entry.units / 10_000
	end
	return oddsByPetId
end

local function GetPetMultiplier(baseMultiplier: number, rarity: Rarity, paid: boolean, stars: number): number
	local rule = StarUpgradeRules.byRarity[rarity]
	local starCount = math.clamp(math.floor(stars), 1, StarUpgradeRules.maxStars)
	if not rule or starCount == 1 then
		return baseMultiplier
	end
	local bonus = if paid then PaidStarBonuses[rarity] or rule else rule
	if starCount == 2 then
		return baseMultiplier + bonus.bonusAtTwoStars
	end
	return baseMultiplier + bonus.bonusAtThreeStars
end

return table.freeze({
	LuckyBlocks = LuckyBlocks,
	Multiplier = table.freeze({
		emptyPetContribution = 1,
		stackingRule = "AdditiveOverOne",
	}),
	Equip = table.freeze({
		startingSlots = 3,
	}),
	Followers = table.freeze({
		maxBounds = Vector3.new(4, 4, 4),
		maxVisualPets = 9,
		maxColumns = 3,
		spacing = 4.75,
		followDistance = 5.25,
		kartRearClearance = 2.5,
		groundClearance = 0.04,
		groundRaycastInterval = 0.5,
		groundRaycastMoveThreshold = 2.5,
		groundRaycastMoveCooldown = 0.25,
		groundRaycastUpOffset = 2.5,
		groundRaycastDownDistance = 256,
		followResponsiveness = 12,
		bobAmplitude = 0.18,
		bobFrequency = 2.2,
		swayAngle = math.rad(3),
		movementTiltAngle = math.rad(10),
		movementTiltThreshold = 0.75,
		movementTiltFullSpeed = 12,
		renderDistance = 180,
		renderCullHysteresis = 20,
		billboardSize = UDim2.new(7, 0, 1.4, 0),
		billboardMaxDistance = 130,
		billboardTopPadding = 0.15,
	}),
	Storage = table.freeze({
		startingCapacity = 25,
	}),
	Upgrades = table.freeze({
		equipSlotsPerPurchase = 3,
		backpackSlotsPerPurchase = 15,
		luckMultiplier = table.freeze({
			startingMultiplier = 1,
			rarityWeightBonus = LuckRarityWeightBonus,
			tiers = table.freeze({
				table.freeze({ multiplier = 2, productKey = "PetLuck2x" }),
				table.freeze({ multiplier = 4, productKey = "PetLuck4x" }),
				table.freeze({ multiplier = 6, productKey = "PetLuck6x" }),
				table.freeze({ multiplier = 8, productKey = "PetLuck8x" }),
				table.freeze({ multiplier = 10, productKey = "PetLuck10x" }),
			}),
		}),
	}),
	StarUpgrades = StarUpgradeRules,
	GetPetMultiplier = GetPetMultiplier,
	GetLuckAdjustedWeight = GetLuckAdjustedWeight,
	GetLuckyBlockOdds = GetLuckyBlockOdds,
	GetPetsForLuckyBlock = GetPetsForLuckyBlock,
	IsLuckyBlockPaid = IsLuckyBlockPaid,
})
