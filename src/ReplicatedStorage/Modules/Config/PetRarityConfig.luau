--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)

export type Rarity = ColorConfig.Rarity

local ChanceWeights: { [Rarity]: number } = table.freeze({
	Common = 100,
	Rare = 60,
	Epic = 35,
	Legendary = 12,
	Mythic = 1,
})

local RarityOrder: { [string]: number } = table.freeze({
	Common = 1,
	Rare = 2,
	Epic = 3,
	Legendary = 4,
	Mythic = 5,
})

return table.freeze({
	ChanceWeights = ChanceWeights,
	RarityOrder = RarityOrder,
})
