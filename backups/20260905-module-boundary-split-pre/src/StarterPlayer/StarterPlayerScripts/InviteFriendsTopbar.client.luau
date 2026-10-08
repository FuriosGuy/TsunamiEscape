--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UIFolder = Modules:WaitForChild("UI")
local InviteFriendsTopbar = require(UIFolder:WaitForChild("InviteFriendsTopbar"))

InviteFriendsTopbar.Start()
