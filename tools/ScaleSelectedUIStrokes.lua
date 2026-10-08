--!strict
-- Paste into Roblox Studio's Command Bar with one or more GUI roots selected.
-- Converts FixedSize UIStrokes while preserving their current apparent thickness.

local Selection = game:GetService("Selection")

local APPLY_CHANGES = true
local MAX_SKIP_DETAILS = 30

type SkipDetail = {
	path: string,
	reason: string,
}

local roots: { Instance } = Selection:Get()
if #roots == 0 then
	warn("[ScaleSelectedUIStrokes] Select one or more GUI roots first.")
	return
end

local strokes: { UIStroke } = {}
local seenInstances: { [Instance]: boolean } = {}

local function includeInstance(instance: Instance): ()
	if seenInstances[instance] then
		return
	end

	seenInstances[instance] = true
	if instance:IsA("UIStroke") then
		table.insert(strokes, instance)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if not seenInstances[descendant] then
			seenInstances[descendant] = true
			if descendant:IsA("UIStroke") then
				table.insert(strokes, descendant)
			end
		end
	end
end

for _, root in ipairs(roots) do
	includeInstance(root)
end

table.sort(strokes, function(left: UIStroke, right: UIStroke): boolean
	return left:GetFullName() < right:GetFullName()
end)

local function getTextMetrics(parent: GuiObject): (number?, boolean?, string?, number?)
	if parent:IsA("TextLabel") then
		return parent.TextSize, parent.TextScaled, parent.Text, parent.TextBounds.Y
	elseif parent:IsA("TextButton") then
		return parent.TextSize, parent.TextScaled, parent.Text, parent.TextBounds.Y
	elseif parent:IsA("TextBox") then
		return parent.TextSize, parent.TextScaled, parent.Text, parent.TextBounds.Y
	end

	return nil, nil, nil, nil
end

local function getReferenceSize(stroke: UIStroke): (number?, string?)
	local parent = stroke.Parent
	if parent == nil or not parent:IsA("GuiObject") then
		return nil, "parent is not a GuiObject"
	end

	local isContextualTextStroke = stroke.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual
	local textSize, textScaled, text, textBoundsY = getTextMetrics(parent)
	if isContextualTextStroke and textSize ~= nil then
		if textScaled then
			if text ~= nil and text ~= "" and textBoundsY ~= nil and textBoundsY > 0 then
				local explicitLineCount = 1
				for _ in string.gmatch(text, "\n") do
					explicitLineCount += 1
				end

				return textBoundsY / explicitLineCount, "TextBounds estimate"
			end

			local textSizeConstraint = parent:FindFirstChildOfClass("UITextSizeConstraint")
			if textSizeConstraint and textSizeConstraint.MaxTextSize > 0 then
				return textSizeConstraint.MaxTextSize, "UITextSizeConstraint.MaxTextSize fallback"
			end

			if textSize > 0 then
				return textSize, "TextSize fallback"
			end

			return nil, "TextScaled text has no measured bounds or configured size"
		end

		if textSize <= 0 then
			return nil, "TextSize is zero"
		end

		return textSize, "TextSize"
	end

	local size = parent.AbsoluteSize
	local shortestAxis = math.min(size.X, size.Y)
	if shortestAxis <= 0 then
		return nil, "parent AbsoluteSize is zero"
	end

	return shortestAxis, "parent shortest axis"
end

local convertedCount = 0
local alreadyScaledCount = 0
local skippedCount = 0
local skipDetails: { SkipDetail } = {}

for _, stroke in ipairs(strokes) do
	if stroke.StrokeSizingMode ~= Enum.StrokeSizingMode.FixedSize then
		alreadyScaledCount += 1
		continue
	end

	local referenceSize, referenceDescription = getReferenceSize(stroke)
	if referenceSize == nil then
		skippedCount += 1
		if #skipDetails < MAX_SKIP_DETAILS then
			table.insert(skipDetails, {
				path = stroke:GetFullName(),
				reason = referenceDescription or "unknown sizing reference",
			})
		end
		continue
	end

	local oldThickness = stroke.Thickness
	local convertedThickness = oldThickness / referenceSize
	if APPLY_CHANGES then
		local success, errorMessage = pcall(function()
			stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
			stroke.Thickness = convertedThickness
		end)

		if not success then
			pcall(function()
				stroke.StrokeSizingMode = Enum.StrokeSizingMode.FixedSize
				stroke.Thickness = oldThickness
			end)

			skippedCount += 1
			if #skipDetails < MAX_SKIP_DETAILS then
				table.insert(skipDetails, {
					path = stroke:GetFullName(),
					reason = tostring(errorMessage),
				})
			end
			continue
		end
	end

	convertedCount += 1
	print(string.format(
		"[ScaleSelectedUIStrokes] %s | %.4f -> %.6f (%s)",
		stroke:GetFullName(),
		oldThickness,
		convertedThickness,
		referenceDescription or "reference"
	))
end

local actionName = "Preview"
if APPLY_CHANGES then
	actionName = "Applied"
end

print(string.format(
	"[ScaleSelectedUIStrokes] %s | converted=%d alreadyScaled=%d skipped=%d scanned=%d",
	actionName,
	convertedCount,
	alreadyScaledCount,
	skippedCount,
	#strokes
))

for _, detail in ipairs(skipDetails) do
	warn(string.format("[ScaleSelectedUIStrokes] Skipped %s | %s", detail.path, detail.reason))
end

if skippedCount > #skipDetails then
	warn(string.format(
		"[ScaleSelectedUIStrokes] Omitted %d additional skip details.",
		skippedCount - #skipDetails
	))
end
