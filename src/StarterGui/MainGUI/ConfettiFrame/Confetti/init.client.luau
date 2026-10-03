local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ConfettiBurstPlayer = require(ReplicatedStorage.Modules.UI:WaitForChild("ConfettiBurstPlayer"))
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local confettiRemote = remotes:WaitForChild("PlayConfettiBurst") :: RemoteEvent

local singletonKey = "__SpeedBrainrotConfettiListener"
if shared[singletonKey] then
	script:Destroy()
	return
end
shared[singletonKey] = true

local COLORS = {
	Color3.fromRGB(255, 234, 92),
	Color3.fromRGB(255, 107, 107),
	Color3.fromRGB(88, 220, 255),
	Color3.fromRGB(130, 255, 116),
	Color3.fromRGB(188, 126, 255),
}

local BURST_DURATION = 1.5
local confettiFolder = script.Parent
local confettiHost = confettiFolder and confettiFolder.Parent
local confettiPlayer = if confettiHost and confettiHost:IsA("GuiObject")
	then ConfettiBurstPlayer.GetOrCreateSingleton(confettiHost)
	else nil
local confettiRemoteConnection: RBXScriptConnection? = nil
local isCleanedUp = false

confettiRemoteConnection = confettiRemote.OnClientEvent:Connect(
	function(colors: { Color3 }?, duration: number?, totalCount: number?, batchSize: number?, batchDelay: number?)
		if not confettiPlayer then
			return
		end

		confettiPlayer:PlayBurst(colors or COLORS, duration or BURST_DURATION, totalCount, batchSize, batchDelay)
	end
)

local function cleanupConfettiListener()
	if isCleanedUp then
		return
	end

	isCleanedUp = true

	if confettiRemoteConnection then
		confettiRemoteConnection:Disconnect()
		confettiRemoteConnection = nil
	end

	shared[singletonKey] = nil
end

script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanupConfettiListener()
	end
end)
script.Destroying:Connect(cleanupConfettiListener)
