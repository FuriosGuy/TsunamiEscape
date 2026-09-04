--!strict
local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DebugModule = require(Modules:WaitForChild("DebugModule"))
local ConfigFolder = Modules:WaitForChild("Config")
local CoreConfig = require(ConfigFolder:WaitForChild("CoreConfig"))

local EconomyAnalytics = {}

local MODULE_NAME = "EconomyAnalytics"
local analyticsConfig = if CoreConfig.analytics then CoreConfig.analytics else nil
local ANALYTICS_ENABLED = if analyticsConfig and typeof(analyticsConfig.enabled) == "boolean"
	then analyticsConfig.enabled
	else true
local ECONOMY_EVENTS_ENABLED = if analyticsConfig and typeof(analyticsConfig.economyEventsEnabled) == "boolean"
	then analyticsConfig.economyEventsEnabled
	else true
local LIVE_SERVER_ONLY = if analyticsConfig and typeof(analyticsConfig.liveServerOnly) == "boolean"
	then analyticsConfig.liveServerOnly
	else true

type ScalarValue = string | number | boolean

export type CurrencyName = "Wins" | "XPSpeed"
export type CustomFields = {
	customField01: ScalarValue?,
	customField02: ScalarValue?,
	customField03: ScalarValue?,
}

local CURRENCY_BALANCE_ATTRIBUTES: { [CurrencyName]: string } = {
	Wins = "WinCount",
	XPSpeed = "AllXPSpeed",
}

local function canSendAnalytics(): boolean
	if not ANALYTICS_ENABLED or not ECONOMY_EVENTS_ENABLED then
		return false
	end

	if not RunService:IsServer() then
		return false
	end

	if LIVE_SERVER_ONLY and RunService:IsStudio() then
		return false
	end

	return true
end

local function isFinitePositive(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge and value > 0
end

local function isFiniteNumber(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

local function stringifyCustomFieldValue(value: ScalarValue): string
	if typeof(value) == "string" then
		return value
	end

	if typeof(value) == "number" then
		if value == math.huge then
			return "inf"
		end
		if value == -math.huge then
			return "-inf"
		end
		if value ~= value then
			return "nan"
		end
		return tostring(value)
	end

	return if value then "true" else "false"
end

local function sanitizeCustomFields(customFields: CustomFields?): { [string]: string }?
	if customFields == nil then
		return nil
	end

	local sanitized = {} :: { [string]: string }

	if customFields.customField01 ~= nil then
		sanitized[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] =
			string.sub(stringifyCustomFieldValue(customFields.customField01), 1, 100)
	end

	if customFields.customField02 ~= nil then
		sanitized[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] =
			string.sub(stringifyCustomFieldValue(customFields.customField02), 1, 100)
	end

	if customFields.customField03 ~= nil then
		sanitized[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] =
			string.sub(stringifyCustomFieldValue(customFields.customField03), 1, 100)
	end

	if next(sanitized) == nil then
		return nil
	end

	return sanitized
end

function EconomyAnalytics.GetBalance(player: Player, currencyName: CurrencyName): number
	local attributeName = CURRENCY_BALANCE_ATTRIBUTES[currencyName]
	local rawBalance = player:GetAttribute(attributeName)
	if typeof(rawBalance) ~= "number" or not isFiniteNumber(rawBalance) then
		return 0
	end

	return math.max(0, rawBalance)
end

function EconomyAnalytics.Log(
	player: Player,
	flowType: Enum.AnalyticsEconomyFlowType,
	currencyName: CurrencyName,
	amount: number,
	transactionTypeName: string,
	itemSku: string?,
	customFields: CustomFields?
)
	if not canSendAnalytics() then
		return
	end

	if player.Parent == nil or player.UserId <= 0 then
		return
	end

	if not isFinitePositive(amount) then
		return
	end

	local sanitizedAmount = math.max(1, math.round(amount))
	if not isFinitePositive(sanitizedAmount) then
		DebugModule.debugWarn(
			string.format(
				"Skipping economy event with non-finite amount | player=%s | currency=%s | amount=%s",
				player.Name,
				currencyName,
				tostring(amount)
			),
			MODULE_NAME
		)
		return
	end

	local balanceAttributeName = CURRENCY_BALANCE_ATTRIBUTES[currencyName]
	local rawEndingBalance = player:GetAttribute(balanceAttributeName)
	if typeof(rawEndingBalance) ~= "number" or not isFiniteNumber(rawEndingBalance) then
		DebugModule.debugWarn(
			string.format(
				"Skipping economy event with non-finite ending balance | player=%s | currency=%s | attribute=%s | value=%s",
				player.Name,
				currencyName,
				balanceAttributeName,
				tostring(rawEndingBalance)
			),
			MODULE_NAME
		)
		return
	end

	local endingBalance = math.max(0, math.round(rawEndingBalance))
	if not isFiniteNumber(endingBalance) then
		DebugModule.debugWarn(
			string.format(
				"Skipping economy event after balance normalization | player=%s | currency=%s | value=%s",
				player.Name,
				currencyName,
				tostring(rawEndingBalance)
			),
			MODULE_NAME
		)
		return
	end
	local sanitizedItemSku = string.sub(itemSku or "", 1, 100)
	local sanitizedCustomFields = sanitizeCustomFields(customFields)

	local ok, err = pcall(function()
		if sanitizedCustomFields then
			AnalyticsService:LogEconomyEvent(
				player,
				flowType,
				currencyName,
				sanitizedAmount,
				endingBalance,
				transactionTypeName,
				sanitizedItemSku,
				sanitizedCustomFields
			)
		else
			AnalyticsService:LogEconomyEvent(
				player,
				flowType,
				currencyName,
				sanitizedAmount,
				endingBalance,
				transactionTypeName,
				sanitizedItemSku
			)
		end
	end)

	if not ok then
		DebugModule.debugWarn(
			string.format(
				"Economy event failed | player=%s | flow=%s | currency=%s | amount=%s | item=%s | err=%s",
				player.Name,
				flowType.Name,
				currencyName,
				tostring(sanitizedAmount),
				sanitizedItemSku,
				tostring(err)
			),
			MODULE_NAME
		)
	end
end

function EconomyAnalytics.LogSource(
	player: Player,
	currencyName: CurrencyName,
	amount: number,
	transactionTypeName: string,
	itemSku: string?,
	customFields: CustomFields?
)
	EconomyAnalytics.Log(
		player,
		Enum.AnalyticsEconomyFlowType.Source,
		currencyName,
		amount,
		transactionTypeName,
		itemSku,
		customFields
	)
end

function EconomyAnalytics.LogSink(
	player: Player,
	currencyName: CurrencyName,
	amount: number,
	transactionTypeName: string,
	itemSku: string?,
	customFields: CustomFields?
)
	EconomyAnalytics.Log(
		player,
		Enum.AnalyticsEconomyFlowType.Sink,
		currencyName,
		amount,
		transactionTypeName,
		itemSku,
		customFields
	)
end

return EconomyAnalytics
