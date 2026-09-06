local NumberFormatting = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qd", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function NumberFormatting.FormatWithCommas(value: number): string
	local rounded = math.round(value)
	local formatted = tostring(rounded)

	local count = 0
	repeat
		local updated
		updated, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = updated
	until count == 0

	return formatted
end

function NumberFormatting.FormatNumber(value: number): string
	if value < 1000 then
		return NumberFormatting.FormatWithCommas(value)
	end

	local index = math.floor(math.log10(value) / 3)
	index = math.clamp(index, 0, #SUFFIXES - 1)
	local suffix = SUFFIXES[index + 1]
	local shortValue = value / (10 ^ (index * 3))
	local text = string.format("%.2f", shortValue)
	text = text:gsub("%.00$", "")
	text = text:gsub("(%..-)0$", "%1")

	return text .. suffix
end

return NumberFormatting
