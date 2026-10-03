-- Paste this entire file into the Roblox Studio Command Bar.
-- Read-only audit: it never changes the selected instances.

local Selection = game:GetService("Selection")

local UDim2Properties = {
	"Position",
	"Size",
	"CanvasSize",
	"CellSize",
	"CellPadding",
}

local UDimProperties = {
	"Padding",
	"PaddingTop",
	"PaddingBottom",
	"PaddingLeft",
	"PaddingRight",
}

local MAX_FINDINGS_TO_PRINT = 500

local function readProperty(instance, propertyName)
	local success, value = pcall(function()
		return instance[propertyName]
	end)

	if success then
		return value
	end

	return nil
end

local function classifyUDim2(value)
	local xUsesOffset = value.X.Scale == 0 and value.X.Offset ~= 0
	local yUsesOffset = value.Y.Scale == 0 and value.Y.Offset ~= 0

	if not xUsesOffset and not yUsesOffset then
		return nil
	end

	if value.X.Scale == 0 and value.Y.Scale == 0 then
		return "FULL_OFFSET"
	end

	return "MIXED_SCALE_OFFSET"
end

local function classifyUDim(value)
	if value.Scale == 0 and value.Offset ~= 0 then
		return "FULL_OFFSET"
	end

	return nil
end

local function formatUDim2(value)
	return string.format(
		"UDim2.new(%.4f, %d, %.4f, %d)",
		value.X.Scale,
		value.X.Offset,
		value.Y.Scale,
		value.Y.Offset
	)
end

local function formatUDim(value)
	return string.format("UDim.new(%.4f, %d)", value.Scale, value.Offset)
end

local roots = Selection:Get()
if #roots == 0 then
	warn("[GuiScaleOffsetAudit] Select one or more GUI roots before running this command.")
	return
end

local instances = {}
local seenInstances = {}

local function addInstance(instance)
	if seenInstances[instance] then
		return
	end

	seenInstances[instance] = true
	table.insert(instances, instance)

	for _, descendant in ipairs(instance:GetDescendants()) do
		if not seenInstances[descendant] then
			seenInstances[descendant] = true
			table.insert(instances, descendant)
		end
	end
end

for _, root in ipairs(roots) do
	addInstance(root)
end

table.sort(instances, function(left, right)
	return left:GetFullName() < right:GetFullName()
end)

local findings = {}
local fullOffsetCount = 0
local mixedCount = 0

local function addFinding(instance, propertyName, issueType, formattedValue)
	if issueType == "FULL_OFFSET" then
		fullOffsetCount += 1
	else
		mixedCount += 1
	end

	table.insert(findings, {
		instance = instance,
		propertyName = propertyName,
		issueType = issueType,
		formattedValue = formattedValue,
	})
end

for _, instance in ipairs(instances) do
	for _, propertyName in ipairs(UDim2Properties) do
		local value = readProperty(instance, propertyName)
		if typeof(value) == "UDim2" then
			local issueType = classifyUDim2(value)
			if issueType then
				addFinding(instance, propertyName, issueType, formatUDim2(value))
			end
		end
	end

	for _, propertyName in ipairs(UDimProperties) do
		local value = readProperty(instance, propertyName)
		if typeof(value) == "UDim" then
			local issueType = classifyUDim(value)
			if issueType then
				addFinding(instance, propertyName, issueType, formatUDim(value))
			end
		end
	end
end

print("========== GUI SCALE/OFFSET AUDIT ==========")
print(string.format("Roots: %d | Instances scanned: %d", #roots, #instances))
print(string.format("Fully offset findings: %d | Mixed findings: %d", fullOffsetCount, mixedCount))

if #findings == 0 then
	print("No non-zero offset-only or mixed scale/offset properties found.")
	print("============================================")
	return
end

local findingsToPrint = math.min(#findings, MAX_FINDINGS_TO_PRINT)
for index = 1, findingsToPrint do
	local finding = findings[index]
	print(string.format(
		"[%s] %s.%s = %s",
		finding.issueType,
		finding.instance:GetFullName(),
		finding.propertyName,
		finding.formattedValue
	))
end

if #findings > MAX_FINDINGS_TO_PRINT then
	warn(string.format(
		"[GuiScaleOffsetAudit] Printed %d of %d findings to avoid flooding the output.",
		MAX_FINDINGS_TO_PRINT,
		#findings
	))
end

print("============================================")
