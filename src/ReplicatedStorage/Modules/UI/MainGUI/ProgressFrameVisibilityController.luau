local ProgressFrameVisibilityController = {}
ProgressFrameVisibilityController.__index = ProgressFrameVisibilityController

type ProgressFrameVisibilityControllerObject = {
	screenGui: ScreenGui,
	stageProgressFrame: GuiObject?,
	eventProgressFrame: GuiObject?,
	originalStageProgressVisible: boolean?,
	originalEventProgressVisible: boolean?,
	eventActive: boolean,
	raceParticipant: boolean,
	destroyed: boolean,
}

local function getGuiObject(screenGui: ScreenGui, name: string): GuiObject?
	local instance = screenGui:FindFirstChild(name)
	return if instance and instance:IsA("GuiObject") then instance else nil
end

function ProgressFrameVisibilityController.new(screenGui: ScreenGui): ProgressFrameVisibilityControllerObject
	local stageProgressFrame = getGuiObject(screenGui, "StageProgressFrame")
	local eventProgressFrame = getGuiObject(screenGui, "EventProgress")

	return setmetatable({
		screenGui = screenGui,
		stageProgressFrame = stageProgressFrame,
		eventProgressFrame = eventProgressFrame,
		originalStageProgressVisible = if stageProgressFrame then stageProgressFrame.Visible else nil,
		originalEventProgressVisible = if eventProgressFrame then eventProgressFrame.Visible else nil,
		eventActive = false,
		raceParticipant = false,
		destroyed = false,
	}, ProgressFrameVisibilityController)
end

function ProgressFrameVisibilityController.Refresh(self: ProgressFrameVisibilityControllerObject)
	if self.destroyed then
		return
	end

	if self.eventProgressFrame then
		self.eventProgressFrame.Visible = self.eventActive
	end
	if self.stageProgressFrame then
		self.stageProgressFrame.Visible = not self.eventActive and not self.raceParticipant
	end
end

function ProgressFrameVisibilityController.SetEventActive(
	self: ProgressFrameVisibilityControllerObject,
	isActive: boolean
)
	if self.destroyed then
		return
	end

	self.eventActive = isActive
	self:Refresh()
end

function ProgressFrameVisibilityController.SetRaceParticipant(
	self: ProgressFrameVisibilityControllerObject,
	isParticipant: boolean
)
	if self.destroyed then
		return
	end

	self.raceParticipant = isParticipant
	self:Refresh()
end

function ProgressFrameVisibilityController.Destroy(self: ProgressFrameVisibilityControllerObject)
	if self.destroyed then
		return
	end
	self.destroyed = true

	if self.stageProgressFrame and self.originalStageProgressVisible ~= nil then
		self.stageProgressFrame.Visible = self.originalStageProgressVisible
	end
	if self.eventProgressFrame and self.originalEventProgressVisible ~= nil then
		self.eventProgressFrame.Visible = self.originalEventProgressVisible
	end
	self.stageProgressFrame = nil
	self.eventProgressFrame = nil
end

return ProgressFrameVisibilityController
