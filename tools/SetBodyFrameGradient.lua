--!strict
-- Run from Roblox Studio Command Bar with one or more BodyFrames or UI roots selected.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Selection = game:GetService("Selection")

local DARKEN_FACTOR = 0.75
local BODY_FRAME_NAME = "BodyFrame"
local TOP_FRAME_NAME = "TopFrame"

local selected = Selection:Get()
if #selected == 0 then
	warn("[SetBodyFrameGradient] Select one or more BodyFrames or containing UI roots.")
	return
end

assert(DARKEN_FACTOR >= 0 and DARKEN_FACTOR <= 1, "DARKEN_FACTOR must be between 0 and 1.")

type GradientJob = {
	bodyFrame: GuiObject,
	main: GuiObject,
	bottomColor: Color3,
	bottomTime: number,
}

local bodyFrames: { GuiObject } = {}
local seenBodyFrames: { [GuiObject]: boolean } = {}
for _, selectedRoot in ipairs(selected) do
	local candidates: { Instance } = {}
	if selectedRoot.Name == BODY_FRAME_NAME then
		table.insert(candidates, selectedRoot)
	else
		for _, descendant in ipairs(selectedRoot:GetDescendants()) do
			if descendant.Name == BODY_FRAME_NAME then
				table.insert(candidates, descendant)
			end
		end
	end

	for _, candidate in ipairs(candidates) do
		if candidate:IsA("GuiObject") and not seenBodyFrames[candidate] then
			seenBodyFrames[candidate] = true
			table.insert(bodyFrames, candidate)
		end
	end
end

table.sort(bodyFrames, function(left: GuiObject, right: GuiObject): boolean
	return left:GetFullName() < right:GetFullName()
end)

local jobs: { GradientJob } = {}
local skippedCount = 0
for _, bodyFrame in ipairs(bodyFrames) do
	local topFrame = bodyFrame.Parent and bodyFrame.Parent:FindFirstChild(TOP_FRAME_NAME)
	local main = topFrame and topFrame:FindFirstChild("Main")
	local mainGradient = main and main:FindFirstChildOfClass("UIGradient")
	local bottomColorKeypoint = if mainGradient
		then mainGradient.Color.Keypoints[#mainGradient.Color.Keypoints]
		else nil

	if not main or not main:IsA("GuiObject") or not bottomColorKeypoint then
		skippedCount += 1
		warn("[SetBodyFrameGradient] Skipped " .. bodyFrame:GetFullName() .. "; TopFrame.Main.UIGradient missing or invalid.")
		continue
	end

	table.insert(jobs, {
		bodyFrame = bodyFrame,
		main = main,
		bottomColor = bottomColorKeypoint.Value,
		bottomTime = bottomColorKeypoint.Time,
	})
end

if #jobs == 0 then
	warn("[SetBodyFrameGradient] No valid BodyFrame targets found.")
	return
end

local beforeWaypointSucceeded, beforeWaypointFailure = pcall(function()
	ChangeHistoryService:SetWaypoint("Before Set BodyFrame Gradient")
end)
if not beforeWaypointSucceeded then
	warn("[SetBodyFrameGradient] Could not create undo waypoint; no changes made: " .. tostring(beforeWaypointFailure))
	return
end

for _, job in ipairs(jobs) do
	local gradient = job.bodyFrame:FindFirstChildOfClass("UIGradient")
	local createdGradient = gradient == nil
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "UIGradient"
	end

	local gradientColor = job.bottomColor:Lerp(Color3.new(0, 0, 0), DARKEN_FACTOR)
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(0, 0, 0)),
		ColorSequenceKeypoint.new(1, gradientColor),
	})
	job.bodyFrame.BackgroundColor3 = Color3.new(1, 1, 1)

	if createdGradient then
		gradient.Parent = job.bodyFrame
	end

	print(string.format(
		"[SetBodyFrameGradient] Updated %s from %s UIGradient time %.2f.",
		job.bodyFrame:GetFullName(),
		job.main:GetFullName(),
		job.bottomTime
	))
end

local afterWaypointSucceeded, afterWaypointFailure = pcall(function()
	ChangeHistoryService:SetWaypoint("Set BodyFrame Gradient")
end)
if afterWaypointSucceeded then
	print(string.format(
		"[SetBodyFrameGradient] Updated %d BodyFrame(s), skipped %d; darken factor=%.2f. Press Ctrl+Z once to undo.",
		#jobs,
		skippedCount,
		DARKEN_FACTOR
	))
else
	warn("[SetBodyFrameGradient] Updated properties, but final undo waypoint failed: " .. tostring(afterWaypointFailure))
end
