local NumberFormatting = {}

local SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qd",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Od",
	"Nd",
	"Vg",
}

-- Continue short-scale abbreviations through centillion. For example,
-- unvigintillion becomes Uvg and quadragintillion becomes Qag.
local UNIT_PREFIXES = {
	[1] = "U",
	[2] = "D",
	[3] = "T",
	[4] = "Qa",
	[5] = "Qi",
	[6] = "Sx",
	[7] = "Sp",
	[8] = "O",
	[9] = "N",
}
local TENS_SUFFIXES = {
	[2] = "Vg",
	[3] = "Tg",
	[4] = "Qag",
	[5] = "Qig",
	[6] = "Sxg",
	[7] = "Spg",
	[8] = "Og",
	[9] = "Ng",
}

for numberName = 21, 99 do
	local tens = math.floor(numberName / 10)
	local units = numberName % 10
	local tensSuffix = TENS_SUFFIXES[tens]
	if units == 0 then
		SUFFIXES[numberName + 2] = tensSuffix
	else
		SUFFIXES[numberName + 2] = UNIT_PREFIXES[units] .. tensSuffix
	end
end

SUFFIXES[102] = "Ce"

local function trimDecimalText(text: string): string
	text = text:gsub("%.00$", "")
	return text:gsub("(%..-)0$", "%1")
end

function NumberFormatting.FormatWithCommas(value: number): string
	local rounded = math.round(value)
	local formatted = string.format("%.0f", rounded)

	local count = 0
	repeat
		local updated
		updated, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = updated
	until count == 0

	return formatted
end

function NumberFormatting.FormatNumber(value: number): string
	local magnitude = math.abs(value)
	if magnitude < 1000 then
		return NumberFormatting.FormatWithCommas(value)
	end

	local index = math.floor(math.log10(magnitude) / 3)
	index = math.clamp(index, 0, #SUFFIXES - 1)
	local suffix = SUFFIXES[index + 1]
	local shortValue = value / (10 ^ (index * 3))
	local text = trimDecimalText(string.format("%.2f", shortValue))

	return text .. suffix
end

function NumberFormatting.FormatCompactNumber(value: number): string
	local magnitude = math.abs(value)
	local suffixIndex = 1
	local compactValue = value

	while math.abs(compactValue) >= 1000 and suffixIndex < #SUFFIXES do
		compactValue /= 1000
		suffixIndex += 1
	end

	if suffixIndex == 1 then
		return NumberFormatting.FormatWithCommas(value)
	end

	local suffix = SUFFIXES[suffixIndex]
	if magnitude >= 1000 then
		if math.abs(compactValue) >= 100 then
			return string.format("%.0f%s", compactValue, suffix)
		elseif math.abs(compactValue) >= 10 then
			return trimDecimalText(string.format("%.1f%s", compactValue, suffix))
		end
		return trimDecimalText(string.format("%.2f%s", compactValue, suffix))
	end

	return NumberFormatting.FormatWithCommas(value)
end

return NumberFormatting
