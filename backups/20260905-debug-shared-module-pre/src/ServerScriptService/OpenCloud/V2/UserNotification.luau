-- Open Cloud V2 UserNotification

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugModule = require(game:GetService("ServerScriptService").Modules:WaitForChild("DebugModule_Server"))

local module = {}
local MODULE_NAME = "UserNotification"

export type UserNotification = {
	path: string?, 
	id: string?, 
	source: Sources?, 
	payload: Payload?
}
export type Payload = {
	type: string?, 
	messageId: string?, 
	parameters: {[string] : Payload_ParameterValue}?, 
	joinExperience: Payload_JoinExperience?, 
	analyticsData: Payload_AnalyticsData?
}
export type Payload_AnalyticsData = {
	category: string
}
export type Payload_JoinExperience = {
	launchData: string
}
export type Payload_ParameterValue = {
	stringValue: string?, 
	int64Value: number?
}
export type Sources = {
	universe: string
}

export type OpenCloudError = {
	code : string,
	message : string
}

export type UserNotificationResult =
	{
		statusCode : number,
		response : UserNotification,
		error : OpenCloudError
	}

function module.createUserNotification(userId : number, userNotification : UserNotification) : UserNotificationResult
	local oc = game:GetService("OpenCloudService")

	local notLoadedStr = "Open Cloud not loaded."

	local resp
	local success

	local MAX_RETRIES = 20
	local retryCount = 0

	while retryCount < MAX_RETRIES do
		success, resp = pcall(function()
			return oc:InvokeAsync("v2", "userNotification", {
				["user"] = userId, 
				["userNotification"] = userNotification
			})
		end)
		if not success and resp == notLoadedStr then
			task.wait(0.5)
			retryCount += 1
		else
			break
		end
	end

	if not success then
		return {
			["response"] = nil,
			["statusCode"] = 500,
			["error"] = {
				["code"] = "UNEXPECTED_ERROR",
				["message"] = resp
			}
		}
	end

	if typeof(resp) ~= "table" then
		DebugModule.debugWarn(
			"Open Cloud user notification returned an invalid response | userId=" .. tostring(userId),
			MODULE_NAME
		)
		return {
			["response"] = nil,
			["statusCode"] = 500,
			["error"] = {
				["code"] = "UNEXPECTED_ERROR",
				["message"] = resp
			}
		}
	end
	local statusCode = resp["StatusCode"]
	local bodyStr = resp["Body"]
	if typeof(statusCode) ~= "number" or typeof(bodyStr) ~= "string" then
		DebugModule.debugWarn(
			"Open Cloud user notification returned an incomplete response | userId="
				.. tostring(userId)
				.. " | statusCode="
				.. tostring(statusCode),
			MODULE_NAME
		)
		return {
			["response"] = nil,
			["statusCode"] = 500,
			["error"] = {
				["code"] = "INVALID_RESPONSE",
				["message"] = "Open Cloud response was missing StatusCode or Body"
			}
		}
	end
	local hs = game:GetService("HttpService")
	if statusCode == 200 then
		local decodeSuccess, responseJson = pcall(function()
			return hs:JSONDecode(bodyStr)
		end)
		if not decodeSuccess or typeof(responseJson) ~= "table" then
			DebugModule.debugWarn(
				"Open Cloud user notification returned invalid success JSON | userId=" .. tostring(userId),
				MODULE_NAME
			)
			return {
				["response"] = nil,
				["statusCode"] = 500,
				["error"] = {
					["code"] = "INVALID_RESPONSE_BODY",
					["message"] = "Open Cloud success response was not valid JSON"
				}
			}
		end
		return {
			["response"] = responseJson,
			["statusCode"] = 200,
			["error"] = nil
		}
	else
		local decodeSuccess, bodyJson = pcall(function()
			return hs:JSONDecode(bodyStr)
		end)
		if not decodeSuccess then
			bodyJson = {
				["code"] = "UNEXPECTED_ERROR",
				["message"] = bodyStr
			}
		end
		DebugModule.debugWarn(
			"Open Cloud user notification request rejected | userId="
				.. tostring(userId)
				.. " | statusCode="
				.. tostring(statusCode)
				.. " | code="
				.. tostring(bodyJson["code"])
				.. " | message="
				.. tostring(bodyJson["message"]),
			MODULE_NAME
		)
		return {
			["response"] = nil,
			["statusCode"] = statusCode,
			["error"] = bodyJson
		}
	end
end

return module
