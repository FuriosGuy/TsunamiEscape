--!strict

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Maid = require(ReplicatedStorage.Modules:WaitForChild("Maid"))
local TweenConfig = require(ReplicatedStorage.Modules.UI:WaitForChild("TweenConfig"))

local MenuOpenController = {}
MenuOpenController.__index = MenuOpenController

local OPEN_TWEEN_INFO = TweenConfig.MenuOpen
local CLOSE_TWEEN_INFO = TweenConfig.MenuClose
local HIDDEN_TRANSPARENCY = 1

type TweenTarget = {
	instance: Instance,
	propertyName: string,
	visibleValue: number,
}

export type Controller = {
	Destroy: (self: Controller) -> (),
}

type ControllerState = Controller & {
	frame: GuiObject?,
	maid: any,
	tweenMaid: any,
	tweenTargets: { TweenTarget },
	isMenuOpen: boolean,
	isDestroyed: boolean,
}

local function addTweenTarget(targets: { TweenTarget }, instance: Instance, propertyName: string)
	local currentValue = (instance :: any)[propertyName]
	if typeof(currentValue) ~= "number" then
		return
	end

	table.insert(targets, {
		instance = instance,
		propertyName = propertyName,
		visibleValue = currentValue,
	})
end

local function collectTweenTargets(frame: GuiObject): { TweenTarget }
	local targets: { TweenTarget } = {}

	if frame:IsA("CanvasGroup") then
		addTweenTarget(targets, frame, "GroupTransparency")
	elseif frame:IsA("Frame") or frame:IsA("ScrollingFrame") then
		addTweenTarget(targets, frame, "BackgroundTransparency")
	end

	for _, descendant in ipairs(frame:GetDescendants()) do
		local insideCanvasGroup = frame:IsA("CanvasGroup")
		local ancestor = descendant.Parent
		while ancestor do
			if ancestor:IsA("CanvasGroup") then
				insideCanvasGroup = true
				break
			end
			if ancestor == frame then
				break
			end
			ancestor = ancestor.Parent
		end
		if insideCanvasGroup then
			continue
		end

		if descendant:IsA("CanvasGroup") then
			addTweenTarget(targets, descendant, "GroupTransparency")
		end

		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			addTweenTarget(targets, descendant, "TextTransparency")
		end

		if descendant:IsA("UIStroke") then
			addTweenTarget(targets, descendant, "Transparency")
		end
	end

	return targets
end

local function setTargetTransparency(target: TweenTarget, transparency: number)
	(target.instance :: any)[target.propertyName] = transparency
end

function MenuOpenController.new(root: Instance): Controller
	local self = setmetatable({
		frame = nil :: GuiObject?,
		maid = Maid.new(),
		tweenMaid = Maid.new(),
		tweenTargets = {} :: { TweenTarget },
		isMenuOpen = false,
		isDestroyed = false,
	}, MenuOpenController) :: ControllerState

	local candidate = root:FindFirstChild("MenuOpen", true)
	if not candidate or not candidate:IsA("GuiObject") then
		return self
	end

	self.frame = candidate
	self.tweenTargets = collectTweenTargets(candidate)
	self.maid:GiveTask(self.tweenMaid)

	for _, target in ipairs(self.tweenTargets) do
		setTargetTransparency(target, HIDDEN_TRANSPARENCY)
	end
	candidate.Visible = false

	local function setMenuOpen(isOpen: boolean)
		if self.isDestroyed or not self.frame then
			return
		end

		self.isMenuOpen = isOpen
		self.tweenMaid:DoCleaning()

		if isOpen then
			self.frame.Visible = true
		end

		local closeCompletionTween: Tween? = nil
		for _, target in ipairs(self.tweenTargets) do
			local goal = if isOpen then target.visibleValue else HIDDEN_TRANSPARENCY
			local tween = TweenService:Create(
				target.instance,
				if isOpen then OPEN_TWEEN_INFO else CLOSE_TWEEN_INFO,
				{ [target.propertyName] = goal }
			)
			self.tweenMaid:GiveTask(tween)
			if not isOpen and not closeCompletionTween then
				closeCompletionTween = tween
				local frame = self.frame
				self.tweenMaid:GiveTask(tween.Completed:Connect(function()
					if not self.isDestroyed and not self.isMenuOpen and self.frame == frame then
						frame.Visible = false
					end
				end))
			end
			tween:Play()
		end
	end

	self.maid:GiveTask(GuiService.MenuOpened:Connect(function()
		setMenuOpen(true)
	end))
	self.maid:GiveTask(GuiService.MenuClosed:Connect(function()
		setMenuOpen(false)
	end))

	setMenuOpen(GuiService.MenuIsOpen)
	return self
end

function MenuOpenController:Destroy()
	if self.isDestroyed then
		return
	end

	self.isDestroyed = true
	self.maid:DoCleaning()
	if self.frame then
		self.frame.Visible = false
	end
end

return MenuOpenController
