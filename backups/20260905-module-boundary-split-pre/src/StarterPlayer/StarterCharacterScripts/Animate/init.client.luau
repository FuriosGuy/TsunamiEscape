local Character = script.Parent
local Humanoid = Character:WaitForChild("Humanoid")

local animNames = {
	sit = {
		{ id = "rbxassetid://109644062453391", weight = 10 },
	},
}

local currentTrack: AnimationTrack? = nil

local function getSitAnimation(): Animation
	local animation = Instance.new("Animation")
	animation.Name = "SitOnlyAnimation"
	animation.AnimationId = animNames.sit[1].id
	return animation
end

local function stopCurrentTrack()
	if currentTrack then
		currentTrack:Stop(0.1)
		currentTrack:Destroy()
		currentTrack = nil
	end
end

local function playSitAnimation()
	local animator = Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = Humanoid
	end

	if currentTrack and currentTrack.IsPlaying then
		return
	end

	stopCurrentTrack()

	local sitAnimation = getSitAnimation()
	local track = animator:LoadAnimation(sitAnimation)
	track.Name = "SitOnlyAnimation"
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play(0.1)
	currentTrack = track
end

local function updateAnimation()
	if Humanoid.Health <= 0 then
		stopCurrentTrack()
		return
	end

	playSitAnimation()
end

Humanoid.Died:Connect(stopCurrentTrack)
Humanoid:GetPropertyChangedSignal("Sit"):Connect(updateAnimation)
Humanoid.StateChanged:Connect(function()
	updateAnimation()
end)

updateAnimation()
