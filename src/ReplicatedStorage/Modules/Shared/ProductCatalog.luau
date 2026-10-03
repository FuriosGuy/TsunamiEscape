--!strict

-- Public product metadata shared by client presentation and server authority.
local ProductCatalog: { [string]: any } = {}

-- Gamepasses: treadmill progression, XP multipliers, and kart unlocks.
ProductCatalog.Gamepasses = {
	-- Treadmill progression, ordered by multiplier.
	["3xTreadmill"] = 1767574117,
	["15xTreadmill"] = 1766286297,
	["35xTreadmill"] = 1767831974,
	["100xTreadmill"] = 1768431922,

	-- Permanent XP and pet presentation upgrades.
	["2xWins"] = 1760592086,
	["PetLuckyBlockFasterOpen"] = 2001128747,

	-- Permanent kart unlocks.
	["AdvancedTank"] = 1791998927,
	["FormulaCar"] = 1792060852,
	["ShoppingKart"] = 1790815513,

	-- General access and bundles.
	["StarterPack"] = 1832483110,
	["VIP"] = 1761600143,
}

-- Developer products: keys sorted by functional group; each group ordered consistently.
ProductCatalog.DevProducts = {
	-- Currency packs, ordered by amount.
	["+1000"] = 3573866224,
	["+5000"] = 3573865316,
	["+10000"] = 3573900618,
	["+100K"] = 3559807390,
	["+1M"] = 3559807486,
	["+10M"] = 3559807556,

	-- Event kart purchases.
	["BloodDragon"] = 3710413009,
	["CrimsonCell"] = 3710412649,
	["IglooKart"] = 3712635767,
	["SiegeTank"] = 3710413231,
	["VoltVIper"] = 3712635731,

	-- General progression and gameplay products.
	["ClaimAllDaily"] = 3589872144,
	["DisableWaves"] = 3559813364,
	["ReturnToStage"] = 3564307894,
	["SkipRebirth"] = 3559805591,
	["TrollPlayer"] = 3573199025,

	-- Pet capacity upgrades.
	["PetBackpackSlotPlusFifteen"] = 3715602343,
	["PetEquipSlotPlusThree"] = 3715602410,

	-- Tier 1 Lucky Block roll bundles, ordered by roll count.
	["PetTier1LuckyBlockRoll1"] = 3715760243,
	["PetTier1LuckyBlockRoll3"] = 3715760248,
	["PetTier1LuckyBlockRoll5"] = 3715760253,

	-- Tier 2 Lucky Block roll bundles, ordered by roll count.
	["PetTier2LuckyBlockRoll1"] = 3715760259,
	["PetTier2LuckyBlockRoll3"] = 3715760262,
	["PetTier2LuckyBlockRoll5"] = 3715760266,

	-- Tier 3 Lucky Block roll bundles, ordered by roll count.
	["PetTier3LuckyBlockRoll1"] = 3715760273,
	["PetTier3LuckyBlockRoll3"] = 3715760279,
	["PetTier3LuckyBlockRoll5"] = 3715760284,

	-- Premium Lucky Block roll bundles, ordered by roll count.
	["PetPremiumLuckyBlockRoll1"] = 3715655207,
	["PetPremiumLuckyBlockRoll3"] = 3715655210,
	["PetPremiumLuckyBlockRoll5"] = 3715655217,

	-- Blood Moon Event Lucky Block roll bundles, ordered by roll count.
	["PetBloodMoonLuckyBlockRoll1"] = 3715655264,
	["PetBloodMoonLuckyBlockRoll3"] = 3715655274,
	["PetBloodMoonLuckyBlockRoll5"] = 3715655280,

	-- Frostbite Rally Event Lucky Block roll bundles, ordered by roll count.
	["PetFrostbiteRallyLuckyBlockRoll1"] = 3715655244,
	["PetFrostbiteRallyLuckyBlockRoll3"] = 3715655249,
	["PetFrostbiteRallyLuckyBlockRoll5"] = 3715655257,

	-- Neon Rush Event Lucky Block roll bundles, ordered by roll count.
	["PetNeonRushLuckyBlockRoll1"] = 3715655223,
	["PetNeonRushLuckyBlockRoll3"] = 3715655228,
	["PetNeonRushLuckyBlockRoll5"] = 3715655238,

	-- Permanent pet luck tiers, ordered from lowest to highest.
	["PetLuck2x"] = 3715602556,
	["PetLuck4x"] = 3715602620,
	["PetLuck6x"] = 3715602659,
	["PetLuck8x"] = 3715602690,
	["PetLuck10x"] = 3715602734,

	-- Existing XP-speed multipliers, ordered by multiplier.
	["2x"] = 3560793026,
	["4x"] = 3560793704,
	["8x"] = 3560793814,
	["16x"] = 3560795074,
	["32x"] = 3560795353,
	["64x"] = 3560795487,
	["100x"] = 3560795766,

	-- Spin-wheel bundles, ordered by spin count.
	["Spin1"] = 3612605889,
	["Spin3"] = 3612605970,
	["Spin5"] = 3612606198,
	["Spin10"] = 3612606233,

	-- Temporary boosts.
	["TempSpeedBoost"] = 3707042010,
	["TempWinBoost"] = 3707052002,

	-- Trail unlocks, alphabetically ordered.
	["BlueTrail"] = 3572175233,
	["DemonTrail"] = 3572176018,
	["GalaxyTrail"] = 3572176684,
	["GoldTrail"] = 3572176138,
	["GreenTrail"] = 3572175108,
	["PurpleTrail"] = 3572175420,
}

-- Blood Moon developer products mapped to permanent kart ownership.
ProductCatalog.BloodmoonKartProducts = {
	BloodDragon = {
		KartName = "5_BloodDragon",
		EventName = "Bloodmoon",
	},
	CrimsonCell = {
		KartName = "4_CrimsonCell",
		EventName = "Bloodmoon",
	},
	SiegeTank = {
		KartName = "6_SiegeTank",
		EventName = "Bloodmoon",
	},
}

-- Event-specific kart product groups.
ProductCatalog.EventKartProducts = {
	Bloodmoon = ProductCatalog.BloodmoonKartProducts,
	FrostbiteRally = {
		IglooKart = {
			KartName = "3_IglooKart",
			EventName = "FrostbiteRally",
		},
	},
	NeonRush = {
		VoltVIper = {
			KartName = "3_VoltVIper",
			EventName = "NeonRush",
		},
	},
}

-- Existing XP multiplier rung to developer-product key mapping.
ProductCatalog.MULTIPLIER_TO_PRODUCT = {
	[1] = "2x",
	[2] = "4x",
	[4] = "8x",
	[8] = "16x",
	[16] = "32x",
	[32] = "64x",
	[64] = "100x",
}

return ProductCatalog
