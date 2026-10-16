--!strict

local Players = game:GetService("Players")

local Character = script.Parent
local Humanoid = Character:WaitForChild("Humanoid") :: Humanoid
local Player = Players.LocalPlayer

local DEFAULT_SIT_ANIMATION_ID = "rbxassetid://109644062453391"
local KART_SIT_ANIMATION_IDS: { [string]: string } = {
	["2_Snowmobile"] = "rbxassetid://93995264730867",
	["3_WitchBroom"] = "rbxassetid://105583475067532",
	["2_CoffinKart"] = "rbxassetid://70973292040782",
}

local currentTrack: AnimationTrack? = nil
local currentAnimation: Animation? = nil
local currentAnimationId: string? = nil
local alive = true
local connections: { RBXScriptConnection } = {}

local function disconnectConnections()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function stopCurrentTrack()
	local track = currentTrack
	currentTrack = nil
	if track then
		track:Stop(0.1)
		track:Destroy()
	end

	local animation = currentAnimation
	currentAnimation = nil
	if animation then
		animation:Destroy()
	end

	currentAnimationId = nil
end

local function getSitAnimationId(): string
	local equippedKart = Player:GetAttribute("Kart_RuntimeModelName")
		or Player:GetAttribute("Kart_Equipped")
	if typeof(equippedKart) == "string" then
		return KART_SIT_ANIMATION_IDS[equippedKart] or DEFAULT_SIT_ANIMATION_ID
	end

	return DEFAULT_SIT_ANIMATION_ID
end

local function getAnimator(): Animator
	local animator = Humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local newAnimator = Instance.new("Animator")
	newAnimator.Parent = Humanoid
	return newAnimator
end

local function playSitAnimation()
	if not alive or Humanoid.Health <= 0 then
		stopCurrentTrack()
		return
	end

	local animationId = getSitAnimationId()
	if currentTrack and currentAnimationId == animationId then
		if not currentTrack.IsPlaying then
			currentTrack:Play(0.1)
		end
		return
	end

	stopCurrentTrack()

	local animation = Instance.new("Animation")
	animation.Name = "KartSitAnimation"
	animation.AnimationId = animationId

	local track = getAnimator():LoadAnimation(animation)
	track.Name = "KartSitAnimation"
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.1)

	currentAnimation = animation
	currentAnimationId = animationId
	currentTrack = track
end

local function updateAnimation()
	if not alive then
		return
	end

	if Humanoid.Health <= 0 then
		stopCurrentTrack()
		return
	end

	playSitAnimation()
end

local function cleanup()
	if not alive then
		return
	end

	alive = false
	disconnectConnections()
	stopCurrentTrack()
end

table.insert(connections, Player:GetAttributeChangedSignal("Kart_Equipped"):Connect(updateAnimation))
table.insert(connections, Player:GetAttributeChangedSignal("Kart_RuntimeModelName"):Connect(updateAnimation))
table.insert(connections, Humanoid.Died:Connect(stopCurrentTrack))
table.insert(connections, Humanoid:GetPropertyChangedSignal("Sit"):Connect(updateAnimation))
table.insert(connections, Humanoid.StateChanged:Connect(function()
	updateAnimation()
end))

script.Destroying:Connect(cleanup)
updateAnimation()
