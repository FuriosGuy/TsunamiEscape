--!strict
-- Paste into Roblox Studio's Command Bar with one or more GUI roots selected.
-- Recolors each selected matching text object's gradient endpoint, creating one if missing.

local Selection = game:GetService("Selection")

local TARGET_GRADIENT_COLOR_HEX = "#FF0000" -- Gradient color at time 1.
local TEXT_COLOR_TO_MATCH_HEX = "#FFFFFF" -- TextColor3 to search for.
local TEXT_COLOR_REPLACEMENT_HEX = "#F0F8FF" -- TextColor3 to apply after a match.

local function colorFromHex(hex: string): Color3
	local normalized = string.gsub(hex, "^#", "")
	assert(
		#normalized == 6 and string.match(normalized, "^%x%x%x%x%x%x$") ~= nil,
		"Expected hex color in #RRGGBB format: " .. hex
	)

	local red = tonumber(string.sub(normalized, 1, 2), 16)
	local green = tonumber(string.sub(normalized, 3, 4), 16)
	local blue = tonumber(string.sub(normalized, 5, 6), 16)
	assert(red ~= nil and green ~= nil and blue ~= nil, "Could not parse hex color: " .. hex)

	return Color3.fromRGB(red, green, blue)
end

local TARGET_GRADIENT_COLOR = colorFromHex(TARGET_GRADIENT_COLOR_HEX)
local TEXT_COLOR_TO_MATCH = colorFromHex(TEXT_COLOR_TO_MATCH_HEX)
local TEXT_COLOR_REPLACEMENT = colorFromHex(TEXT_COLOR_REPLACEMENT_HEX)

local roots: { Instance } = Selection:Get()
if #roots == 0 then
	warn("[SetWhiteTextGradient] Select one or more GUI roots first.")
	return
end

local textObjects: { Instance } = {}
local seenInstances: { [Instance]: boolean } = {}

local function includeInstance(instance: Instance): ()
	if seenInstances[instance] then
		return
	end

	seenInstances[instance] = true
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		table.insert(textObjects, instance)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if seenInstances[descendant] then
			continue
		end

		seenInstances[descendant] = true
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			table.insert(textObjects, descendant)
		end
	end
end

local function getTextColor(instance: Instance): Color3?
	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		return instance.TextColor3
	end

	return nil
end

local function setGradientEndpoint(sequence: ColorSequence, color: Color3): ColorSequence
	local keypoints: { ColorSequenceKeypoint } = {}
	local foundEndpoint = false

	for _, keypoint in ipairs(sequence.Keypoints) do
		local value = keypoint.Value
		if keypoint.Time == 1 then
			value = color
			foundEndpoint = true
		end
		table.insert(keypoints, ColorSequenceKeypoint.new(keypoint.Time, value))
	end

	if not foundEndpoint then
		table.insert(keypoints, ColorSequenceKeypoint.new(1, color))
	end

	return ColorSequence.new(keypoints)
end

for _, root in ipairs(roots) do
	includeInstance(root)
end

table.sort(textObjects, function(left: Instance, right: Instance): boolean
	return left:GetFullName() < right:GetFullName()
end)

local updatedCount = 0
for _, textObject in ipairs(textObjects) do
	if getTextColor(textObject) ~= TEXT_COLOR_TO_MATCH then
		continue
	end

	if textObject:IsA("TextLabel") or textObject:IsA("TextButton") or textObject:IsA("TextBox") then
		textObject.TextColor3 = TEXT_COLOR_REPLACEMENT
	end

	local gradient = textObject:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = setGradientEndpoint(gradient.Color, TARGET_GRADIENT_COLOR)
		gradient.Rotation = 90
	else
		local newGradient = Instance.new("UIGradient")
		newGradient.Name = "UIGradient"
		newGradient.Color = ColorSequence.new(TEXT_COLOR_REPLACEMENT, TARGET_GRADIENT_COLOR)
		newGradient.Rotation = 90
		newGradient.Parent = textObject
	end

	updatedCount += 1
	print("[SetWhiteTextGradient] Updated " .. textObject:GetFullName())
end

print(string.format(
	"[SetWhiteTextGradient] Updated %d matching text objects; match=%s text=%s endpoint=%s",
	updatedCount,
	TEXT_COLOR_TO_MATCH_HEX,
	TEXT_COLOR_REPLACEMENT_HEX,
	TARGET_GRADIENT_COLOR_HEX
))
