local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlayerHandler = require(ReplicatedStorage.Modules.Shared:WaitForChild("PlayerHandler_Client"))
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

local MainFunctions = {}
local FRAME_TOGGLE_DEBOUNCE = 0.15
local MOVEMENT_CHECK_INTERVAL = 0.1
local lastFrameToggleTimes: { [string]: number } = {}
local TROLL_HUD_HIDE_KEYS = {
	"LevelsBarFrame",
	"SpeedMultiFrame",
	"BottomRightGridFrame",
	"SpeedBuyFrame",
	"RightSideButtonsFrame",
}

local MOVEMENT_KEYS = {
	[Enum.KeyCode.W] = true,
	[Enum.KeyCode.A] = true,
	[Enum.KeyCode.S] = true,
	[Enum.KeyCode.D] = true,
	[Enum.KeyCode.Up] = true,
	[Enum.KeyCode.Down] = true,
	[Enum.KeyCode.Left] = true,
	[Enum.KeyCode.Right] = true,
}

local function setTrollHudVisibility(isVisible: boolean)
	local hud = VisualFunctions.HUD
	for _, hudKey in ipairs(TROLL_HUD_HIDE_KEYS) do
		local guiObject = (hud :: any)[hudKey]
		if guiObject and guiObject:IsA("GuiObject") then
			if isVisible then
				guiObject:SetAttribute("TrollPrevVisible", guiObject.Visible)
				guiObject.Visible = false
			else
				local previousVisible = guiObject:GetAttribute("TrollPrevVisible")
				if typeof(previousVisible) == "boolean" then
					guiObject.Visible = previousVisible
				else
					guiObject.Visible = true
				end
				guiObject:SetAttribute("TrollPrevVisible", nil)
			end
		end
	end
end

function MainFunctions.SetFrameVisibleSimple(frameName: string, isVisible: boolean)
	local targetFrame = VisualFunctions.ActiveFrameGroup[frameName]
	if not targetFrame then
		return
	end

	targetFrame.Visible = isVisible
	targetFrame.Interactable = isVisible

	if frameName == "TrollFrame" then
		setTrollHudVisibility(isVisible)
	end
end

--[[
	Closes all managed frames except the one provided.
]]
function MainFunctions.CloseOtherFrames(except: Frame?)
	local frames = VisualFunctions.ActiveFrameGroup
	if not frames then
		return
	end

	local closeTasks = {}
	for _, frame in pairs(frames) do
		if frame and frame ~= except and frame.Visible then
			if frame.Name == "TrollFrame" then
				MainFunctions.SetFrameVisibleSimple("TrollFrame", false)
			else
				table.insert(closeTasks, VisualFunctions.CloseWindow(frame))
			end
		end
	end

	-- Wait for all close animations to finish (Yielding)
	if #closeTasks > 0 then
		for _, task in ipairs(closeTasks) do
			if typeof(task) == "RBXScriptSignal" then
				task:Wait()
			end
		end
	end
end

--[[
	Toggles a specific managed frame.
]]
function MainFunctions.ToggleFrame(frameName: string)
	local targetFrame = VisualFunctions.ActiveFrameGroup[frameName]
	if not targetFrame then
		return
	end

	local now = tick()
	local lastToggleTime = lastFrameToggleTimes[frameName] or 0
	if now - lastToggleTime < FRAME_TOGGLE_DEBOUNCE then
		return
	end
	lastFrameToggleTimes[frameName] = now

	if frameName == "TrollFrame" then
		if targetFrame.Visible then
			MainFunctions.SetFrameVisibleSimple("TrollFrame", false)
		else
			task.spawn(function()
				MainFunctions.CloseOtherFrames(targetFrame)
				MainFunctions.SetFrameVisibleSimple("TrollFrame", true)
			end)
		end
		return
	end

	if targetFrame.Visible then
		VisualFunctions.CloseWindow(targetFrame)
	else
		task.spawn(function()
			MainFunctions.CloseOtherFrames(targetFrame)
			VisualFunctions.OpenWindow(targetFrame)
		end)
	end
end

--[[
	Starts the movement gain detection.
	Fires a RemoteEvent to the server when movement keys are held.
]]
function MainFunctions.StartMovementDetection(humanoid: Humanoid): () -> ()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		return function() end
	end

	local MovementAction = remotes:FindFirstChild("MovementAction") :: RemoteEvent
	if not MovementAction then
		return function() end
	end

	local player = Players.LocalPlayer
	local stopped = false
	local lastMovementSignal = 0
	local lastMovementCheck = 0
	local movementConnection = RunService.Heartbeat:Connect(function()
		local now = tick()
		if stopped then
			return
		end
		if player:GetAttribute("SpinWheelModalOpen") == true then
			return
		end

		if now - lastMovementCheck < MOVEMENT_CHECK_INTERVAL then
			return
		end
		lastMovementCheck = now

		local interval = PlayerHandler.GetMovementInterval(player)
		if not interval then
			interval = 0.25
		end

		if now - lastMovementSignal < interval then
			return
		end

		if not humanoid or humanoid.Parent == nil or humanoid.Health <= 0 then
			return
		end

		local isMoving = humanoid.MoveDirection.Magnitude > 0.05
		for key in pairs(MOVEMENT_KEYS) do
			if UserInputService:IsKeyDown(key) then
				isMoving = true
				break
			end
		end

		if isMoving then
			lastMovementSignal = now
			MovementAction:FireServer()
		end
	end)

	local function stopMovement()
		if stopped then
			return
		end

		stopped = true
		movementConnection:Disconnect()
	end

	return stopMovement
end

--[[
	Stops the movement gain detection.
]]
function MainFunctions.StopMovementDetection(movementStopper: (() -> ())?)
	if movementStopper then
		movementStopper()
	end
end

return MainFunctions
