--!strict

export type ColorStyle = {
	Color: Color3,
	Gradient: ColorSequence,
}

export type GradientStyle = {
	BackgroundColor: Color3,
	Gradient: ColorSequence,
	GradientBottomColor: Color3,
}

export type KartFrameStyle = GradientStyle
export type Rarity = "Common" | "Rare" | "Epic" | "Legendary" | "Mythic"
type StarMultiplierTextStyle = { TextColor: Color3, Gradient: ColorSequence }
type NotificationTheme = { textColor: Color3, gradientBottomColor: Color3 }
type LuckyBlockTopFrameStyle = { BackgroundColor: Color3, Gradient: ColorSequence, Label: string }
type StageProgressWorldStyle = { backgroundColor: Color3 }

local Colors: { [string]: ColorStyle } = table.freeze({
	White = table.freeze({
		Color = Color3.fromRGB(255, 255, 255),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
	}),
	Black = table.freeze({
		Color = Color3.fromRGB(0, 0, 0),
		Gradient = ColorSequence.new(Color3.fromRGB(0, 0, 0)),
	}),
	Gray = table.freeze({
		Color = Color3.fromRGB(239, 239, 239),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(122, 122, 122)),
	}),
	Purple = table.freeze({
		Color = Color3.fromRGB(227, 74, 255),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(74, 3, 255)),
	}),
	Gold = table.freeze({
		Color = Color3.fromRGB(254, 200, 42),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 85, 0)),
	}),
	WheelGold = table.freeze({
		Color = Color3.fromRGB(254, 199, 41),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 85, 0)),
	}),
	Blue = table.freeze({
		Color = Color3.fromRGB(88, 216, 255),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(0, 81, 255)),
	}),
	Green = table.freeze({
		Color = Color3.fromRGB(0, 255, 0),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(0, 130, 15)),
	}),
	Red = table.freeze({
		Color = Color3.fromRGB(255, 78, 78),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(206, 0, 3)),
	}),
	Legendary = table.freeze({
		Color = Color3.fromRGB(255, 255, 0),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 128, 0)),
	}),
	Mythic = table.freeze({
		Color = Color3.fromRGB(255, 0, 0),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(206, 0, 3)),
	}),
	Frostbite = table.freeze({
		Color = Color3.fromRGB(204, 238, 255),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(115, 173, 255)),
	}),
	AdvancedTank = table.freeze({
		Color = Color3.new(0, 1, 1),
		Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0, 0.3843, 1)),
	}),
	ShoppingKart = table.freeze({
		Color = Color3.new(0.6745, 0.6471, 0.6667),
		Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.302, 0.302, 0.302)),
	}),
	FormulaCar = table.freeze({
		Color = Color3.new(1, 0.3059, 0.3059),
		Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.8078, 0, 0.0118)),
	}),
	BloodMoonKart = table.freeze({
		Color = Color3.new(1, 0, 0),
		Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.5098, 0, 0)),
	}),
	InviteFriend = table.freeze({
		Color = Color3.new(1, 1, 0),
		Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 0.502, 0)),
	}),
	PetsButton = table.freeze({
		Color = Color3.new(0.8196, 0.5255, 0.2941),
		Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.8667, 0.3333, 0.2275)),
	}),
	PetLuck = table.freeze({
		Color = Color3.new(0.4471, 0.8706, 0.2941),
		Gradient = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.1059, 0.4431, 0.2353)),
	}),
	UnreadBadge = table.freeze({
		Color = Color3.fromRGB(255, 79, 79),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 79, 79)),
	}),
	World1Progress = table.freeze({
		Color = Color3.fromRGB(85, 255, 0),
		Gradient = ColorSequence.new(Color3.fromRGB(85, 255, 0)),
	}),
	SpinConfettiCream = table.freeze({
		Color = Color3.fromRGB(255, 240, 166),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 240, 166)),
	}),
	SpinConfettiYellow = table.freeze({
		Color = Color3.fromRGB(255, 215, 64),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 215, 64)),
	}),
	SpinConfettiOrange = table.freeze({
		Color = Color3.fromRGB(255, 181, 46),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 181, 46)),
	}),
	SpinConfettiDeepOrange = table.freeze({
		Color = Color3.fromRGB(242, 140, 40),
		Gradient = ColorSequence.new(Color3.fromRGB(242, 140, 40)),
	}),
	LuckyBlockTier1 = table.freeze({
		Color = Color3.fromRGB(254, 200, 42),
		Gradient = ColorSequence.new(Color3.fromRGB(254, 200, 42), Color3.fromRGB(255, 85, 0)),
	}),
	LuckyBlockTier2 = table.freeze({
		Color = Color3.fromRGB(88, 216, 255),
		Gradient = ColorSequence.new(Color3.fromRGB(88, 216, 255), Color3.fromRGB(0, 81, 255)),
	}),
	LuckyBlockTier3 = table.freeze({
		Color = Color3.fromRGB(227, 74, 255),
		Gradient = ColorSequence.new(Color3.fromRGB(227, 74, 255), Color3.fromRGB(74, 3, 255)),
	}),
	LuckyBlockPremium = table.freeze({
		Color = Color3.fromRGB(0, 255, 0),
		Gradient = ColorSequence.new(Color3.fromRGB(0, 255, 0), Color3.fromRGB(0, 130, 15)),
	}),
	LuckyBlockBloodMoon = table.freeze({
		Color = Color3.fromRGB(255, 0, 0),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 0, 0)),
	}),
	LuckyBlockNeonRush = table.freeze({
		Color = Color3.fromRGB(88, 216, 255),
		Gradient = ColorSequence.new(Color3.fromRGB(88, 216, 255), Color3.fromRGB(0, 81, 255)),
	}),
	LuckyBlockFrostbiteRally = table.freeze({
		Color = Color3.fromRGB(204, 238, 255),
		Gradient = ColorSequence.new(Color3.fromRGB(204, 238, 255), Color3.fromRGB(115, 173, 255)),
	}),
	LuckyBlockHalloween = table.freeze({
		Color = Color3.fromRGB(255, 128, 0),
		Gradient = ColorSequence.new(Color3.fromRGB(255, 128, 0), Color3.fromRGB(128, 40, 0)),
	}),
})

local function getGradientBottom(style: ColorStyle): Color3
	return style.Gradient.Keypoints[2].Value
end

local function createGradientStyle(style: ColorStyle): GradientStyle
	return table.freeze({
		BackgroundColor = style.Color,
		Gradient = style.Gradient,
		GradientBottomColor = getGradientBottom(style),
	})
end

local function createNotificationTheme(style: ColorStyle)
	return table.freeze({
		textColor = style.Color,
		gradientBottomColor = getGradientBottom(style),
	})
end

local NotificationThemes: { [string]: NotificationTheme } = table.freeze({
	Default = createNotificationTheme(Colors.Gray),
	Green = createNotificationTheme(Colors.Green),
	Red = createNotificationTheme(Colors.Red),
	Purple = createNotificationTheme(Colors.Purple),
	Gold = createNotificationTheme(Colors.Gold),
	Blue = createNotificationTheme(Colors.Blue),
})

local rarityStyles = table.freeze({
	Common = createGradientStyle(Colors.Green),
	Rare = createGradientStyle(Colors.Blue),
	Epic = createGradientStyle(Colors.Purple),
	Legendary = createGradientStyle(Colors.Legendary),
	Mythic = createGradientStyle(Colors.Mythic),
})

local commonPetDisplayStyle = createGradientStyle(Colors.Gray)

local function getPetDisplayRarityStyle(rarity: Rarity): GradientStyle
	return if rarity == "Common" then commonPetDisplayStyle else rarityStyles[rarity]
end

local function createStarMultiplierTextStyle(textStyle: ColorStyle): StarMultiplierTextStyle
	return table.freeze({
		TextColor = textStyle.Color,
		Gradient = textStyle.Gradient,
	})
end

local starMultiplierStyles: { [string]: { [number]: StarMultiplierTextStyle } } = table.freeze({
	CommonRare = table.freeze({
		[1] = createStarMultiplierTextStyle(Colors.White),
		[2] = createStarMultiplierTextStyle(Colors.Green),
		[3] = createStarMultiplierTextStyle(Colors.Blue),
	}),
	EpicMythic = table.freeze({
		[1] = createStarMultiplierTextStyle(Colors.Purple),
		[2] = createStarMultiplierTextStyle(Colors.Gold),
		[3] = createStarMultiplierTextStyle(Colors.Red),
	}),
})

local function getStarMultiplierTextStyle(rarity: Rarity, stars: number)
	local styles = if rarity == "Common" or rarity == "Rare"
		then starMultiplierStyles.CommonRare
		else starMultiplierStyles.EpicMythic
	local starCount = math.clamp(math.floor(stars), 1, 3)
	if starCount == 1 then
		return styles[1]
	elseif starCount == 2 then
		return styles[2]
	end
	return styles[3]
end

local topFrameStyles: { [string]: LuckyBlockTopFrameStyle } = table.freeze({
	Tier1 = table.freeze({
		BackgroundColor = Colors.LuckyBlockTier1.Color,
		Gradient = Colors.LuckyBlockTier1.Gradient,
		Label = "Tier 1 Lucky Block",
	}),
	Tier2 = table.freeze({
		BackgroundColor = Colors.LuckyBlockTier2.Color,
		Gradient = Colors.LuckyBlockTier2.Gradient,
		Label = "Tier 2 Lucky Block",
	}),
	Tier3 = table.freeze({
		BackgroundColor = Colors.LuckyBlockTier3.Color,
		Gradient = Colors.LuckyBlockTier3.Gradient,
		Label = "Tier 3 Lucky Block",
	}),
	Premium = table.freeze({
		BackgroundColor = Colors.LuckyBlockPremium.Color,
		Gradient = Colors.LuckyBlockPremium.Gradient,
		Label = "Premium Lucky Block",
	}),
	BloodMoon = table.freeze({
		BackgroundColor = Colors.LuckyBlockBloodMoon.Color,
		Gradient = Colors.LuckyBlockBloodMoon.Gradient,
		Label = "Blood Moon Lucky Block",
	}),
	NeonRush = table.freeze({
		BackgroundColor = Colors.LuckyBlockNeonRush.Color,
		Gradient = Colors.LuckyBlockNeonRush.Gradient,
		Label = "Neon Rush Lucky Block",
	}),
	FrostbiteRally = table.freeze({
		BackgroundColor = Colors.LuckyBlockFrostbiteRally.Color,
		Gradient = Colors.LuckyBlockFrostbiteRally.Gradient,
		Label = "Frostbite Rally Lucky Block",
	}),
	Halloween = table.freeze({
		BackgroundColor = Colors.LuckyBlockHalloween.Color,
		Gradient = Colors.LuckyBlockHalloween.Gradient,
		Label = "Halloween Lucky Block",
	}),
})

local kartFrameStyles: { [string]: KartFrameStyle } = table.freeze({
	AdvancedTank = createGradientStyle(Colors.AdvancedTank),
	ShoppingKart = createGradientStyle(Colors.ShoppingKart),
	FormulaCar = createGradientStyle(Colors.FormulaCar),
	BloodMoon = createGradientStyle(Colors.BloodMoonKart),
	NeonRush = createGradientStyle(Colors.Blue),
	FrostbiteRally = createGradientStyle(Colors.Frostbite),
	Halloween = createGradientStyle(Colors.LuckyBlockHalloween),
})

local buttonStyles = table.freeze({
	Wheel = createGradientStyle(Colors.WheelGold),
	Equip = createGradientStyle(Colors.Green),
})

local hudButtonStyles: { [string]: GradientStyle } = table.freeze({
	PetsButtonFrame = createGradientStyle(Colors.PetsButton),
	LuckMultiplier = createGradientStyle(Colors.PetLuck),
})

local stageProgressWorlds: { [string]: StageProgressWorldStyle } = table.freeze({
	World1 = table.freeze({ backgroundColor = Colors.World1Progress.Color }),
	Fallback = table.freeze({ backgroundColor = Colors.World1Progress.Color }),
})

local UI = table.freeze({
	NotificationThemes = NotificationThemes,
	ButtonStyles = buttonStyles,
	HudButtonStyles = hudButtonStyles,
	StageProgressWorlds = stageProgressWorlds,
	SpinWheel = table.freeze({
		LabelTextColor = Colors.Gold.Color,
		LabelGradientBottomColor = Colors.Gold.Gradient.Keypoints[2].Value,
		LabelShineColor = Colors.White.Color,
		RewardConfettiColors = table.freeze({
			Colors.SpinConfettiCream.Color,
			Colors.SpinConfettiYellow.Color,
			Colors.SpinConfettiOrange.Color,
			Colors.SpinConfettiDeepOrange.Color,
		}),
	}),
	PlaytimeRewards = table.freeze({
		ReadyTextStyle = table.freeze({
			TextColor = Colors.Green.Color,
			Gradient = Colors.Green.Gradient,
		}),
	}),
})

local Pets = table.freeze({
	Rarities = rarityStyles,
	GetDisplayRarityStyle = getPetDisplayRarityStyle,
	GetStarMultiplierTextStyle = getStarMultiplierTextStyle,
})

local LuckyBlocks = table.freeze({
	TopFrameStyles = topFrameStyles,
})

local Karts = table.freeze({
	FrameStyles = kartFrameStyles,
})

return table.freeze({
	Colors = Colors,
	Pets = Pets,
	LuckyBlocks = LuckyBlocks,
	Karts = Karts,
	UI = UI,
})
