--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Maid = require(ReplicatedStorage.Modules:WaitForChild("Maid"))
local CoreConfigShared = require(ReplicatedStorage.Modules.Shared:WaitForChild("CoreConfig_Shared"))

local TreadmillBillboardController = {}
TreadmillBillboardController.__index = TreadmillBillboardController

type MaidType = typeof(Maid.new())

type TreadmillBinding = {
	instance: Instance,
	label: TextLabel?,
	maid: MaidType,
}

type Controller = {
	player: Player,
	maid: MaidType,
	worldMaids: { [Instance]: MaidType },
	treadmillBindings: { [Instance]: TreadmillBinding },
	destroyed: boolean,
	_bindWorld: (self: Controller, world: Instance) -> (),
	_unbindWorld: (self: Controller, world: Instance) -> (),
	_bindTreadmill: (self: Controller, ownerMaid: MaidType, treadmill: Instance) -> (),
	_refreshTreadmill: (self: Controller, binding: TreadmillBinding) -> (),
	_refreshAll: (self: Controller) -> (),
	_bind: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

local treadmillConfig = CoreConfigShared.treadmills
assert(typeof(treadmillConfig) == "table", "CoreConfigShared.treadmills is required")
local FREE_TREADMILL_CLAIMED_ATTRIBUTE = if RunService:IsStudio()
	then "FreeTreadmillStudioClaimed"
	else "FreeTreadmillClaimed"

local rebirthRequiredValue = treadmillConfig.rebirthTreadmillRequiredRebirths
local freeTreadmillSessionSecondsValue = treadmillConfig.freeTreadmillClaimSessionSeconds
local studioFreeTreadmillSessionSecondsValue = treadmillConfig.studioFreeTreadmillClaimSessionSeconds
assert(
	typeof(rebirthRequiredValue) == "number" and rebirthRequiredValue >= 0,
	"CoreConfigShared.treadmills.rebirthTreadmillRequiredRebirths must be non-negative"
)
assert(
	typeof(freeTreadmillSessionSecondsValue) == "number" and freeTreadmillSessionSecondsValue >= 0,
	"CoreConfigShared.treadmills.freeTreadmillClaimSessionSeconds must be non-negative"
)
assert(
	typeof(studioFreeTreadmillSessionSecondsValue) == "number" and studioFreeTreadmillSessionSecondsValue >= 0,
	"CoreConfigShared.treadmills.studioFreeTreadmillClaimSessionSeconds must be non-negative"
)

local REBIRTH_REQUIRED = math.floor(rebirthRequiredValue)
local FREE_TREADMILL_SESSION_SECONDS = math.floor(
	if RunService:IsStudio() then studioFreeTreadmillSessionSecondsValue else freeTreadmillSessionSecondsValue
)

function TreadmillBillboardController._refreshTreadmill(self: Controller, binding: TreadmillBinding): ()
	local treadmill = binding.instance
	if treadmill.Parent == nil then
		return
	end

	local labelName: string
	local labelText: string
	if treadmill.Name == "RebirthTreadmill" then
		labelName = "RebirthNeeded"
		labelText = string.format("REBIRTH %d REQUIRED", REBIRTH_REQUIRED)
	elseif treadmill.Name == "2xTreadmill" then
		labelName = "PlaytimeNeeded"
		local remainingValue = self.player:GetAttribute("FreeTreadmillClaimRemainingSeconds")
		local sessionRemainingSeconds = if typeof(remainingValue) == "number"
			then math.max(0, math.floor(remainingValue))
			else FREE_TREADMILL_SESSION_SECONDS
		local remainingSeconds = if self.player:GetAttribute(FREE_TREADMILL_CLAIMED_ATTRIBUTE) == true
			then 0
			else sessionRemainingSeconds
		local remainingMinutes = math.ceil(remainingSeconds / 60)
		labelText = string.format("%d MIN PLAYTIME NEEDED", remainingMinutes)
	else
		return
	end

	local label = binding.label
	if not label or label.Parent == nil or label.Name ~= labelName then
		local candidate = treadmill:FindFirstChild(labelName, true)
		label = if candidate and candidate:IsA("TextLabel") then candidate else nil
		binding.label = label
	end

	if label then
		label.Text = labelText
	end
end

function TreadmillBillboardController._refreshAll(self: Controller): ()
	if self.destroyed then
		return
	end

	for _, binding in pairs(self.treadmillBindings) do
		self:_refreshTreadmill(binding)
	end
end

function TreadmillBillboardController._bindTreadmill(
	self: Controller,
	ownerMaid: MaidType,
	treadmill: Instance
): ()
	if treadmill.Name ~= "RebirthTreadmill" and treadmill.Name ~= "2xTreadmill" then
		return
	end
	if self.treadmillBindings[treadmill] then
		return
	end

	local binding: TreadmillBinding = {
		instance = treadmill,
		label = nil,
		maid = Maid.new(),
	}
	self.treadmillBindings[treadmill] = binding
	ownerMaid:GiveTask(function()
		if self.treadmillBindings[treadmill] == binding then
			self.treadmillBindings[treadmill] = nil
		end
		binding.maid:DoCleaning()
	end)

	binding.maid:GiveTask(treadmill.DescendantAdded:Connect(function(descendant)
		if descendant.Name == "RebirthNeeded" or descendant.Name == "PlaytimeNeeded" then
			self:_refreshTreadmill(binding)
		end
	end))
	binding.maid:GiveTask(treadmill.DescendantRemoving:Connect(function(descendant)
		if descendant == binding.label then
			binding.label = nil
		end
	end))
	self:_refreshTreadmill(binding)
end

function TreadmillBillboardController._bindWorld(self: Controller, world: Instance): ()
	if self.worldMaids[world] then
		return
	end

	local worldMaid = Maid.new()
	self.worldMaids[world] = worldMaid
	local treadmillFolder: Instance? = nil
	local treadmillFolderMaid: MaidType? = nil

	local function unbindTreadmillFolder(): ()
		if treadmillFolderMaid then
			treadmillFolderMaid:DoCleaning()
			treadmillFolderMaid = nil
		end
		treadmillFolder = nil
	end

	local function bindTreadmillFolder(folder: Instance): ()
		unbindTreadmillFolder()
		treadmillFolder = folder
		local folderMaid = Maid.new()
		treadmillFolderMaid = folderMaid
		for _, treadmill in ipairs(folder:GetChildren()) do
			self:_bindTreadmill(folderMaid, treadmill)
		end
		folderMaid:GiveTask(folder.ChildAdded:Connect(function(treadmill)
			self:_bindTreadmill(folderMaid, treadmill)
		end))
		folderMaid:GiveTask(folder.ChildRemoved:Connect(function(treadmill)
			local binding = self.treadmillBindings[treadmill]
			if binding then
				self.treadmillBindings[treadmill] = nil
				binding.maid:DoCleaning()
			end
		end))
	end

	local existingFolder = world:FindFirstChild("Treadmills")
	if existingFolder then
		bindTreadmillFolder(existingFolder)
	end

	worldMaid:GiveTask(function()
		unbindTreadmillFolder()
		if self.worldMaids[world] == worldMaid then
			self.worldMaids[world] = nil
		end
	end)
	worldMaid:GiveTask(world.ChildAdded:Connect(function(child)
		if child.Name == "Treadmills" then
			bindTreadmillFolder(child)
		end
	end))
	worldMaid:GiveTask(world.ChildRemoved:Connect(function(child)
		if child == treadmillFolder then
			unbindTreadmillFolder()
		end
	end))
end

function TreadmillBillboardController._unbindWorld(self: Controller, world: Instance): ()
	local worldMaid = self.worldMaids[world]
	if not worldMaid then
		return
	end
	worldMaid:DoCleaning()
end

function TreadmillBillboardController._bind(self: Controller): ()
	local worlds = Workspace:FindFirstChild("Worlds")
	if not worlds then
		warn("TreadmillBillboardController: Workspace.Worlds missing")
		return
	end

	for _, world in ipairs(worlds:GetChildren()) do
		self:_bindWorld(world)
	end
	self.maid:GiveTask(worlds.ChildAdded:Connect(function(world)
		self:_bindWorld(world)
	end))
	self.maid:GiveTask(worlds.ChildRemoved:Connect(function(world)
		self:_unbindWorld(world)
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("Rebirths"):Connect(function()
		self:_refreshAll()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("FreeTreadmillClaimRemainingSeconds"):Connect(function()
		self:_refreshAll()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("FreeTreadmillClaimed"):Connect(function()
		self:_refreshAll()
	end))
	self.maid:GiveTask(self.player:GetAttributeChangedSignal("Data_Loaded"):Connect(function()
		self:_refreshAll()
	end))
	self.maid:GiveTask(function()
		for world in pairs(table.clone(self.worldMaids)) do
			self:_unbindWorld(world)
		end
		table.clear(self.treadmillBindings)
	end)
end

function TreadmillBillboardController.new(player: Player): Controller
	local self = setmetatable({
		player = player,
		maid = Maid.new(),
		worldMaids = {},
		treadmillBindings = {},
		destroyed = false,
	}, TreadmillBillboardController) :: Controller
	self:_bind()
	return self
end

function TreadmillBillboardController:Destroy(): ()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.maid:DoCleaning()
end

return TreadmillBillboardController
