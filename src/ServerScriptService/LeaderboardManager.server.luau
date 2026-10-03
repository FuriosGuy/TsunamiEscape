local LeaderboardService = require(script.Parent.Modules.LeaderboardService)

LeaderboardService.Init()

local cleanedUp = false
local function cleanup()
	if cleanedUp then
		return
	end
	cleanedUp = true
	LeaderboardService.Shutdown()
end

script.Destroying:Connect(cleanup)
script.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		cleanup()
	end
end)
