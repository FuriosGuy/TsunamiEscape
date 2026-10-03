--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MainFunctions = require(ReplicatedStorage.Modules.UI.MainFunctions)
local VisualFunctions = require(ReplicatedStorage.Modules.UI.VisualFunctions)

local WinCountShopShortcut = {}

local SHOP_OPEN_TIMEOUT_SECONDS = 3

type SessionMaid = {
	GiveTask: (self: SessionMaid, task: RBXScriptConnection | thread) -> (),
}

local function getButton(rotateImage: GuiObject): GuiButton?
	if rotateImage:IsA("GuiButton") then
		return rotateImage
	end

	local button = rotateImage:FindFirstChildWhichIsA("GuiButton", true)
	if button and button:IsA("GuiButton") then
		return button
	end

	return nil
end

local function scrollToWins(sessionMaid: SessionMaid)
	local shopFrame = VisualFunctions.ActiveFrameGroup.ShopFrame
	if not shopFrame then
		return
	end
	if shopFrame.Visible then
		MainFunctions.ToggleFrame("ShopFrame")
		return
	end

	local scrollBackground = shopFrame:FindFirstChild("ScrollBackground")
	local scrollingFrameInstance = scrollBackground and scrollBackground:FindFirstChild("ScrollingFrame")
	if not scrollingFrameInstance or not scrollingFrameInstance:IsA("ScrollingFrame") then
		return
	end

	local winsSection = scrollingFrameInstance:FindFirstChild("PassesWins")
	if not winsSection or not winsSection:IsA("GuiObject") then
		return
	end

	if not shopFrame.Visible then
		MainFunctions.ToggleFrame("ShopFrame")
	end

	local navigationThread = task.defer(function()
		local deadline = os.clock() + SHOP_OPEN_TIMEOUT_SECONDS
		while os.clock() < deadline do
			if not shopFrame.Parent then
				return
			end
			if shopFrame.Visible and shopFrame.Interactable then
				break
			end
			task.wait()
		end

		if not shopFrame.Parent or not shopFrame.Visible or not shopFrame.Interactable then
			return
		end
		task.wait()
		if not scrollingFrameInstance.Parent or not winsSection.Parent then
			return
		end

		local currentCanvasPosition = scrollingFrameInstance.CanvasPosition
		local sectionCanvasY = winsSection.AbsolutePosition.Y
			- scrollingFrameInstance.AbsolutePosition.Y
			+ currentCanvasPosition.Y
		local maximumCanvasY =
			math.max(0, scrollingFrameInstance.AbsoluteCanvasSize.Y - scrollingFrameInstance.AbsoluteSize.Y)
		scrollingFrameInstance.CanvasPosition =
			Vector2.new(currentCanvasPosition.X, math.clamp(sectionCanvasY, 0, maximumCanvasY))
	end)
	sessionMaid:GiveTask(navigationThread)
end

function WinCountShopShortcut.Bind(rotateImage: Instance, sessionMaid: SessionMaid)
	if
		not rotateImage:IsA("GuiObject")
		or rotateImage.Name ~= "RotateImage"
		or not rotateImage:FindFirstAncestor("WinCountFrame")
	then
		return
	end

	local button = getButton(rotateImage)
	if not button then
		return
	end

	sessionMaid:GiveTask(button.Activated:Connect(function()
		scrollToWins(sessionMaid)
	end))
end

return WinCountShopShortcut
