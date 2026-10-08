--!strict

local LiveEventService = require(script.Parent.Modules:WaitForChild("LiveEventService"))

LiveEventService.Init()

local cleanedUp = false
local function cleanup()
	if cleanedUp then
		return
	end
	cleanedUp = true
	LiveEventService.Destroy()
end

script.Destroying:Connect(cleanup)
script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanup()
	end
end)
game:BindToClose(cleanup)
