--!strict
-- Studio Command Bar utility.
-- Select one Model or Folder before running.
-- Preview: APPLY = false. Red Neon models are planned for removal.
-- Apply: inspect preview, press Ctrl+Z, then set APPLY = true and run again.

local Selection = game:GetService("Selection")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local selected = Selection:Get()
assert(#selected == 1, "Select exactly one Model or Folder")

local root = selected[1]
assert(root:IsA("Model") or root:IsA("Folder"), "Selection must be a Model or Folder")

local CELL_SIZE = 128
local REDUCTION = 0.25
local APPLY = false
local TARGET_MODE = "Type" -- "Type", "Height", or "TypeAndHeight"
local TARGET_TYPES = {
	"Rock",
	-- "Pine",
}
local HEIGHT_MIN = 0
local HEIGHT_MAX = 100

assert(
	TARGET_MODE == "Type" or TARGET_MODE == "Height" or TARGET_MODE == "TypeAndHeight",
	"TARGET_MODE must be Type, Height, or TypeAndHeight"
)
assert(HEIGHT_MIN <= HEIGHT_MAX, "HEIGHT_MIN must be less than or equal to HEIGHT_MAX")
if TARGET_MODE == "Type" or TARGET_MODE == "TypeAndHeight" then
	assert(#TARGET_TYPES > 0, "TARGET_TYPES cannot be empty for this TARGET_MODE")
end

local function escapePattern(text: string): string
	local escaped = text:gsub("([^%w])", "%%%1")
	return escaped
end

local function matchesTargetType(instance: Model): string?
	for _, targetType in ipairs(TARGET_TYPES) do
		local normalizedType = targetType:gsub("_+$", "")
		local pattern = "^" .. escapePattern(normalizedType) .. "_?%d+$"

		if instance.Name:match(pattern) then
			return normalizedType
		end
	end

	return nil
end

local function getTargetHeight(instance: Model): number
	-- TreeLeaves can cross a height band without representing tree placement.
	-- Use TreeTrunk base for trees; never use leaves for height eligibility.
	local treeTrunk = instance:FindFirstChild("TreeTrunk", true)
	if treeTrunk and treeTrunk:IsA("BasePart") then
		return treeTrunk.Position.Y - treeTrunk.Size.Y * 0.5
	end

	local boundingBoxCFrame, boundingBoxSize = instance:GetBoundingBox()
	return boundingBoxCFrame.Position.Y - boundingBoxSize.Y * 0.5
end

local function classify(instance: Instance): string?
	if not instance:IsA("Model") then
		return nil
	end

	if TARGET_MODE == "Height" then
		local height = getTargetHeight(instance)
		if height >= HEIGHT_MIN and height <= HEIGHT_MAX then
			return "Height"
		end
		return nil
	end

	local targetType = matchesTargetType(instance)
	if not targetType then
		return nil
	end

	if TARGET_MODE == "TypeAndHeight" then
		local height = getTargetHeight(instance)
		if height < HEIGHT_MIN or height > HEIGHT_MAX then
			return nil
		end
	end

	return targetType
end

type Candidate = {
	model: Model,
	position: Vector3,
	kind: string,
}

type Bucket = {
	key: string,
	kind: string,
	items: { Candidate },
	removeCount: number,
	capacity: number,
	remainder: number,
}

local candidates: { Candidate } = {}

local function addCandidate(instance: Instance)
	local kind = classify(instance)
	if not kind or not instance:IsA("Model") then
		return
	end

	table.insert(candidates, {
		model = instance,
		position = instance:GetPivot().Position,
		kind = kind,
	})
end

if TARGET_MODE ~= "Height" then
	addCandidate(root)
end

for _, descendant in ipairs(root:GetDescendants()) do
	addCandidate(descendant)
end

assert(#candidates > 0, "No numbered models matched TARGET_TYPES")

local buckets: { [string]: Bucket } = {}
local kindTotals: { [string]: number } = {}

for _, item in ipairs(candidates) do
	local cellX = math.floor(item.position.X / CELL_SIZE)
	local cellZ = math.floor(item.position.Z / CELL_SIZE)
	local key = string.format("%d:%d:%s", cellX, cellZ, item.kind)

	local bucket = buckets[key]
	if not bucket then
		bucket = {
			key = key,
			kind = item.kind,
			items = {},
			removeCount = 0,
			capacity = 0,
			remainder = 0,
		}
		buckets[key] = bucket
	end

	table.insert(bucket.items, item)
	kindTotals[item.kind] = (kindTotals[item.kind] or 0) + 1
end

local bucketList: { Bucket } = {}
local capacityByKind: { [string]: number } = {}
local assignedByKind: { [string]: number } = {}

for _, bucket in pairs(buckets) do
	-- Preserve at least one model for every occupied cell/type bucket.
	bucket.capacity = math.max(#bucket.items - 1, 0)

	local idealRemoval = #bucket.items * REDUCTION
	bucket.removeCount = math.min(math.floor(idealRemoval), bucket.capacity)
	bucket.remainder = idealRemoval - bucket.removeCount

	capacityByKind[bucket.kind] = (capacityByKind[bucket.kind] or 0) + bucket.capacity
	assignedByKind[bucket.kind] = (assignedByKind[bucket.kind] or 0) + bucket.removeCount
	table.insert(bucketList, bucket)
end

local remainingByKind: { [string]: number } = {}

for kind, total in pairs(kindTotals) do
	local targetRemove = math.min(
		math.floor(total * REDUCTION + 0.5),
		capacityByKind[kind] or 0
	)
	local assigned = assignedByKind[kind] or 0
	remainingByKind[kind] = targetRemove - assigned
end

table.sort(bucketList, function(left, right)
	if left.remainder == right.remainder then
		return left.key < right.key
	end

	return left.remainder > right.remainder
end)

local function hasRemainingRemovals(): boolean
	for _, remaining in pairs(remainingByKind) do
		if remaining > 0 then
			return true
		end
	end

	return false
end

while hasRemainingRemovals() do
	local changed = false

	for _, bucket in ipairs(bucketList) do
		local remaining = remainingByKind[bucket.kind] or 0
		if remaining > 0 and bucket.removeCount < bucket.capacity then
			bucket.removeCount += 1
			remainingByKind[bucket.kind] -= 1
			changed = true
		end
	end

	if not changed then
		break
	end
end

local function comesFirst(left: Candidate, right: Candidate): boolean
	local leftPosition = left.position
	local rightPosition = right.position

	if leftPosition.X ~= rightPosition.X then
		return leftPosition.X < rightPosition.X
	end

	if leftPosition.Z ~= rightPosition.Z then
		return leftPosition.Z < rightPosition.Z
	end

	if leftPosition.Y ~= rightPosition.Y then
		return leftPosition.Y < rightPosition.Y
	end

	return left.model:GetFullName() < right.model:GetFullName()
end

local function planarDistanceSquared(left: Candidate, right: Candidate): number
	local x = left.position.X - right.position.X
	local z = left.position.Z - right.position.Z
	return x * x + z * z
end

local toRemove: { Candidate } = {}

for _, bucket in ipairs(bucketList) do
	table.sort(bucket.items, comesFirst)

	local keepCount = #bucket.items - bucket.removeCount
	local kept: { Candidate } = {}
	local keptSet: { [Candidate]: boolean } = {}

	kept[1] = bucket.items[1]
	keptSet[bucket.items[1]] = true

	-- Keep points farthest apart inside each cell/type bucket.
	while #kept < keepCount do
		local bestCandidate: Candidate? = nil
		local bestDistance = -1

		for _, candidate in ipairs(bucket.items) do
			if not keptSet[candidate] then
				local nearestDistance = math.huge

				for _, chosen in ipairs(kept) do
					nearestDistance = math.min(
						nearestDistance,
						planarDistanceSquared(candidate, chosen)
					)
				end

				if nearestDistance > bestDistance
					or (
						nearestDistance == bestDistance
						and (bestCandidate == nil or comesFirst(candidate, bestCandidate))
					)
				then
					bestCandidate = candidate
					bestDistance = nearestDistance
				end
			end
		end

		assert(bestCandidate ~= nil, "Failed to select evenly distributed model")
		table.insert(kept, bestCandidate)
		keptSet[bestCandidate] = true
	end

	for _, item in ipairs(bucket.items) do
		if not keptSet[item] then
			table.insert(toRemove, item)
		end
	end
end

print(("Found %d models across %d spatial buckets"):format(#candidates, #bucketList))
print(("Target mode: %s"):format(TARGET_MODE))
if TARGET_MODE == "Height" or TARGET_MODE == "TypeAndHeight" then
	print(("Height range: %.2f to %.2f"):format(HEIGHT_MIN, HEIGHT_MAX))
end
if TARGET_MODE == "Type" or TARGET_MODE == "TypeAndHeight" then
	print(("Target types: %s"):format(table.concat(TARGET_TYPES, ", ")))
end
print(("Planned removal: %d models"):format(#toRemove))
print(("Cell size: %d studs"):format(CELL_SIZE))

if APPLY then
	local okBefore, beforeError = pcall(function()
		ChangeHistoryService:SetWaypoint("Before even tree rock reduction")
	end)
	assert(okBefore, tostring(beforeError))

	for _, item in ipairs(toRemove) do
		if item.model.Parent then
			-- Do not call Destroy(). Parent=nil keeps Studio Undo able to restore it.
			item.model.Parent = nil
		end
	end

	local okAfter, afterError = pcall(function()
		ChangeHistoryService:SetWaypoint("After even tree rock reduction")
	end)
	assert(okAfter, tostring(afterError))

	print("Applied. Press Ctrl+Z to restore removed models.")
else
	local okBefore, beforeError = pcall(function()
		ChangeHistoryService:SetWaypoint("Before tree rock preview")
	end)
	assert(okBefore, tostring(beforeError))

	for _, item in ipairs(toRemove) do
		for _, descendant in ipairs(item.model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Color = Color3.fromRGB(255, 0, 0)
				descendant.Material = Enum.Material.Neon
			end
		end
	end

	local okAfter, afterError = pcall(function()
		ChangeHistoryService:SetWaypoint("Tree rock preview")
	end)
	assert(okAfter, tostring(afterError))

	print("Preview applied: red Neon models are planned for removal.")
	print("Press Ctrl+Z once to restore original colors/materials before applying.")
end
