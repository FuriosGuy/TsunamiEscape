--!strict

local Config = {}

export type Product = {
	key: string,
	productKey: string,
	displayName: string,
	kind: "Kart" | "Trail" | "CandyBoost",
	ownedName: string,
	candyPrice: number,
	candyPurchasable: boolean?,
	kartModelName: string?,
	description: string?,
}

Config.CandyBoost = table.freeze({
	productKey = "HalloweenCandyBoost",
	endAttributeName = "HalloweenCandyBoostEndUnix",
	multiplier = 2,
	durationSeconds = 30 * 60,
})

Config.Products = table.freeze({
	{
		key = "HalloweenCandyBoost",
		productKey = Config.CandyBoost.productKey,
		displayName = "2x Candy",
		kind = "CandyBoost",
		ownedName = "",
		candyPrice = 0,
		candyPurchasable = false,
		description = "2x Candy Boost",
	},
	{
		key = "PumpkinKart",
		productKey = "PumpkinKart",
		displayName = "Pumpkin Kart",
		kind = "Kart",
		ownedName = "1_PumpkinKart",
		kartModelName = "1_PumpkinKart",
		candyPrice = 200,
	},
	{
		key = "CoffinKart",
		productKey = "CoffinKart",
		displayName = "Coffin Kart",
		kind = "Kart",
		ownedName = "2_CoffinKart",
		kartModelName = "2_CoffinKart",
		candyPrice = 350,
	},
	{
		key = "WitchBroom",
		productKey = "WitchBroom",
		displayName = "Witch Broom",
		kind = "Kart",
		ownedName = "3_WitchBroom",
		kartModelName = "3_WitchBroom",
		candyPrice = 500,
	},
	{
		key = "HearseKart",
		productKey = "HearseKart",
		displayName = "Hearse",
		kind = "Kart",
		ownedName = "4_HearseKart",
		kartModelName = "4_HearseKart",
		candyPrice = 700,
	},
	{
		key = "HalloweenTrail",
		productKey = "HalloweenTrail",
		displayName = "Halloween Trail",
		kind = "Trail",
		ownedName = "HalloweenTrail",
		candyPrice = 750,
		description = "8x Speed Boost",
	},
	{
		key = "HorsemanKart",
		productKey = "HorsemanKart",
		displayName = "Horseman Kart",
		kind = "Kart",
		ownedName = "5_HorsemanKart",
		kartModelName = "5_HorsemanKart",
		candyPrice = 900,
	},
} :: { Product })

return table.freeze(Config)
