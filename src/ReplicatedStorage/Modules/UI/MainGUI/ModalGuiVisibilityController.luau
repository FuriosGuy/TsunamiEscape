--!strict

type VisibilitySnapshot = {
	visible: boolean,
}

type Controller = {
	root: Instance,
	notificationFrame: GuiObject?,
	notificationDefaultZIndex: number?,
	visibilitySnapshot: { [GuiObject]: VisibilitySnapshot },
	alive: boolean,
	Capture: (self: Controller, modalFrame: GuiObject?) -> (),
	Restore: (self: Controller) -> (),
	SetNotificationLayer: (self: Controller, modalFrame: GuiObject?, isModalOpen: boolean) -> (),
	Destroy: (self: Controller) -> (),
}

local ModalGuiVisibilityController = {}
ModalGuiVisibilityController.__index = ModalGuiVisibilityController

local PRESERVED_FRAME_NAMES: { [string]: boolean } = {
	EventFrameList = true,
	EventProgress = true,
	StageProgressFrame = true,
	NotificationFrame = true,
	MinigameNotificationFrame = true,
	LevelUpFrame = true,
	ConfettiFrame = true,
}

function ModalGuiVisibilityController.new(root: Instance): Controller
	local notificationFrame = root:FindFirstChild("NotificationFrame", true)
	local typedNotificationFrame = if notificationFrame and notificationFrame:IsA("GuiObject")
		then notificationFrame
		else nil

	return setmetatable({
		root = root,
		notificationFrame = typedNotificationFrame,
		notificationDefaultZIndex = if typedNotificationFrame then typedNotificationFrame.ZIndex else nil,
		visibilitySnapshot = {},
		alive = true,
	}, ModalGuiVisibilityController) :: Controller
end

function ModalGuiVisibilityController.Capture(self: Controller, modalFrame: GuiObject?): ()
	if not self.alive then
		return
	end
	self:Restore()
	for _, child in ipairs(self.root:GetChildren()) do
		if child:IsA("GuiObject") then
			self.visibilitySnapshot[child] = {
				visible = child.Visible,
			}
			if child ~= modalFrame and not PRESERVED_FRAME_NAMES[child.Name] then
				child.Visible = false
			end
		end
	end
end

function ModalGuiVisibilityController.Restore(self: Controller): ()
	for guiObject, state in pairs(self.visibilitySnapshot) do
		if guiObject.Parent then
			guiObject.Visible = state.visible
		end
	end
	table.clear(self.visibilitySnapshot)
end

function ModalGuiVisibilityController.SetNotificationLayer(
	self: Controller,
	modalFrame: GuiObject?,
	isModalOpen: boolean
): ()
	local notificationFrame = self.notificationFrame
	if not notificationFrame or not notificationFrame.Parent then
		return
	end
	if isModalOpen then
		local modalZIndex = if modalFrame then modalFrame.ZIndex else notificationFrame.ZIndex
		notificationFrame.ZIndex = math.max(notificationFrame.ZIndex, modalZIndex + 1)
	elseif self.notificationDefaultZIndex ~= nil then
		notificationFrame.ZIndex = self.notificationDefaultZIndex
	end
end

function ModalGuiVisibilityController.Destroy(self: Controller): ()
	if not self.alive then
		return
	end
	self:Restore()
	self.alive = false
	self.notificationFrame = nil
	self.notificationDefaultZIndex = nil
end

return ModalGuiVisibilityController
