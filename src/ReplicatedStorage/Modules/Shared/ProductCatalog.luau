--!strict

-- Public product metadata shared by client presentation and server authority.
local ProductCatalog: { [string]: any } = {}

ProductCatalog.Gamepasses = {
	["2xWins"] = 1760592086,
	["VIP"] = 1761600143,
	["3xTreadmill"] = 1767574117,
	["15xTreadmill"] = 1766286297,
	["35xTreadmill"] = 1767831974,
	["100xTreadmill"] = 1768431922,
	["AdvancedTank"] = 1791998927,
	["ShoppingKart"] = 1790815513,
	["FormulaCar"] = 1792060852,
	["StarterPack"] = 1832483110,
}

ProductCatalog.DevProducts = {
	["SkipRebirth"] = 3559805591,
	["DisableWaves"] = 3559813364,
	["ReturnToStage"] = 3564307894,
	["TrollPlayer"] = 3573199025,
	["+100K"] = 3559807390,
	["+1M"] = 3559807486,
	["+10M"] = 3559807556,
	["+1000"] = 3573866224,
	["+5000"] = 3573865316,
	["+10000"] = 3573900618,
	["2x"] = 3560793026,
	["4x"] = 3560793704,
	["8x"] = 3560793814,
	["16x"] = 3560795074,
	["32x"] = 3560795353,
	["64x"] = 3560795487,
	["100x"] = 3560795766,
	["GalaxyTrail"] = 3572176684,
	["DemonTrail"] = 3572176018,
	["GoldTrail"] = 3572176138,
	["PurpleTrail"] = 3572175420,
	["BlueTrail"] = 3572175233,
	["GreenTrail"] = 3572175108,
	["ClaimAllDaily"] = 3589872144,
	["Spin1"] = 3612605889,
	["Spin3"] = 3612605970,
	["Spin5"] = 3612606198,
	["Spin10"] = 3612606233,
	["TempSpeedBoost"] = 3707042010,
	["TempWinBoost"] = 3707052002,
	["CrimsonCell"] = 3710412649,
	["BloodDragon"] = 3710413009,
	["SiegeTank"] = 3710413231,
}

ProductCatalog.BloodmoonKartProducts = {
	CrimsonCell = {
		KartName = "4_CrimsonCell",
		EventName = "Bloodmoon",
	},
	BloodDragon = {
		KartName = "5_BloodDragon",
		EventName = "Bloodmoon",
	},
	SiegeTank = {
		KartName = "6_SiegeTank",
		EventName = "Bloodmoon",
	},
}

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
