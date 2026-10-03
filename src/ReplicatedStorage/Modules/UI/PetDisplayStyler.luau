--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ColorConfig = require(ReplicatedStorage.Modules.Config.ColorConfig)

local PetDisplayStyler = {}

function PetDisplayStyler.Apply(
	petNameLabel: TextLabel,
	rarityLabel: TextLabel,
	petName: string,
	rarity: ColorConfig.Rarity
): ()
	local rarityStyle = ColorConfig.Pets.GetDisplayRarityStyle(rarity)
	petNameLabel.Text = petName
	petNameLabel.TextColor3 = ColorConfig.Colors.White.Color
	local nameGradient = petNameLabel:FindFirstChildOfClass("UIGradient")
	if nameGradient then
		nameGradient.Color = ColorSequence.new(ColorConfig.Colors.White.Color)
	end

	rarityLabel.Text = string.upper(rarity)
	rarityLabel.TextColor3 = rarityStyle.BackgroundColor
	local rarityGradient = rarityLabel:FindFirstChildOfClass("UIGradient")
	if rarityGradient then
		rarityGradient.Color = rarityStyle.Gradient
		rarityGradient.Rotation = 90
	end
end

return table.freeze(PetDisplayStyler)
