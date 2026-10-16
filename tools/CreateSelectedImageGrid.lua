--!strict
-- Run from Roblox Studio Command Bar with one ImageLabel or ImageButton selected.

local Selection = game:GetService("Selection")
local HttpService = game:GetService("HttpService")

type ImageInstance = ImageLabel | ImageButton

-- Configure grid. Three columns by two rows creates six tiles.
local COLUMNS = 3
local ROWS = 1
local GAP_X = 0.015
local GAP_Y = 0.015
local MAX_TILES = 100
local SOURCE_ID_ATTRIBUTE = "ImageGridSourceId"
local CLONE_SOURCE_ATTRIBUTE = "GeneratedImageGridSourceId"

local selected = Selection:Get()
if #selected ~= 1 then
	error("Select exactly one ImageLabel or ImageButton.")
end

local selectedInstance = selected[1]
if not selectedInstance:IsA("ImageLabel") and not selectedInstance:IsA("ImageButton") then
	error("Selected object must be an ImageLabel or ImageButton.")
end
local source: ImageInstance = selectedInstance

local parent = source.Parent
if not parent or not parent:IsA("GuiObject") then
	error("Selected image must be inside a Frame or other GuiObject.")
end

if COLUMNS < 1 or ROWS < 1 or COLUMNS ~= math.floor(COLUMNS) or ROWS ~= math.floor(ROWS) then
	error("Rows and columns must be positive whole numbers.")
end
if COLUMNS * ROWS > MAX_TILES then
	error(string.format("Grid is limited to %d images.", MAX_TILES))
end
if GAP_X < 0 or GAP_Y < 0 then
	error("Grid gaps cannot be negative.")
end

for _, child in ipairs(parent:GetChildren()) do
	if child:IsA("UIGridLayout") or child:IsA("UIListLayout") or child:IsA("UIPageLayout") then
		error("Parent layout overrides manual positioning. Remove or disable it first.")
	end
end

local cellWidth = (1 - GAP_X * (COLUMNS + 1)) / COLUMNS
local cellHeight = (1 - GAP_Y * (ROWS + 1)) / ROWS
if cellWidth <= 0 or cellHeight <= 0 then
	error("Grid gaps are too large for the configured rows and columns.")
end

local existingSourceId = source:GetAttribute(SOURCE_ID_ATTRIBUTE)
local sourceId = if typeof(existingSourceId) == "string" then existingSourceId else HttpService:GenerateGUID(false)

-- Studio Command Bar records DataModel changes for its own undo/redo history.
-- TryBeginRecording is plugin-only and cannot be started by this Command Bar script.
source:SetAttribute(SOURCE_ID_ATTRIBUTE, sourceId)


for _, child in ipairs(parent:GetChildren()) do
	if child ~= source and child:GetAttribute(CLONE_SOURCE_ATTRIBUTE) == sourceId then
		child:Destroy()
	end
end


local tileIndex = 0
for row = 1, ROWS do
	for column = 1, COLUMNS do
		tileIndex += 1
		local tile: ImageInstance = source
		if tileIndex > 1 then
			local clone = source:Clone()
			if not clone or (not clone:IsA("ImageLabel") and not clone:IsA("ImageButton")) then
				error("Could not clone selected image.")
			end
			tile = clone
			tile.Name = string.format("%s_R%d_C%d", source.Name, row, column)
			tile:SetAttribute(SOURCE_ID_ATTRIBUTE, nil)
			tile:SetAttribute(CLONE_SOURCE_ATTRIBUTE, sourceId)
		end

		tile.AnchorPoint = Vector2.new(0.5, 0.5)
		tile.Size = UDim2.fromScale(cellWidth, cellHeight)
		tile.Position = UDim2.fromScale(
			GAP_X + (column - 0.5) * (cellWidth + GAP_X),
			GAP_Y + (row - 0.5) * (cellHeight + GAP_Y)
		)
		tile.LayoutOrder = tileIndex

		if tileIndex > 1 then
			tile.Parent = parent
		end
	end
end

print(string.format("Created %d images (%d columns x %d rows).", COLUMNS * ROWS, COLUMNS, ROWS))
