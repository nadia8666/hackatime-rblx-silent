--[[
	API
	Handles all network communication with the HackaTime API.
]]
--
local API = {}
local HttpService = game:GetService("HttpService")
local APIEndpoint = "https://hackatime.hackclub.com/api/hackatime/v1/users/current/heartbeats.bulk"
local HeartbeatsEndpoint = "https://hackatime.hackclub.com/api/hackatime/v1/users/0/heartbeats"
local UpEndpoint = "https://hackatime.hackclub.com/up"
-- Error codes for status reporting
API.ERROR_CODES = {
	OK = "OK",
	NO_API_KEY = "ERR_NO_API_KEY",
	NETWORK_ERROR = "ERR_NETWORK",
	AUTH_ERROR = "ERR_AUTH",
	RATE_LIMIT = "ERR_RATE_LIMIT",
	SERVER_ERROR = "ERR_SERVER",
	UNKNOWN = "ERR_UNKNOWN",
}
function API.sendHeartbeats(queue, apiKey)
	if not apiKey or apiKey == "" then
		return false, API.ERROR_CODES.NO_API_KEY, "API key is not set."
	end
	if #queue == 0 then
		return true, API.ERROR_CODES.OK, "Queue is empty." -- Not an error, but nothing to do
	end
	local jsonData = HttpService:JSONEncode(queue)
	local headers = {
		["Authorization"] = apiKey:match("^Bearer ") and apiKey or ("Bearer " .. apiKey),
		["Content-Type"] = "application/json",
	}
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = APIEndpoint,
			Method = "POST",
			Headers = headers,
			Body = jsonData,
		})
	end)
	if not success then
		return false, API.ERROR_CODES.NETWORK_ERROR, "Network error: " .. tostring(response)
	end
	if response.Success then
		return true, API.ERROR_CODES.OK, "Successfully sent " .. #queue .. " heartbeats."
	else
		local errorCode = API.ERROR_CODES.UNKNOWN
		local errorMessage = tostring(response.StatusMessage)
		local statusCode = response.StatusCode
		if statusCode == 401 then
			errorCode = API.ERROR_CODES.AUTH_ERROR
			errorMessage = "Authentication failed. Please check your API key."
		elseif statusCode == 429 then
			errorCode = API.ERROR_CODES.RATE_LIMIT
			errorMessage = "Rate limit reached. Please wait."
		elseif statusCode >= 500 then
			errorCode = API.ERROR_CODES.SERVER_ERROR
			errorMessage = "Server error: " .. errorMessage
		else
			errorMessage = "Unknown error: " .. errorMessage
		end
		return false, errorCode, errorMessage
	end
end

function API.checkDomainAccess()
	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = UpEndpoint,
			Method = "GET",
		})
	end)

	if not success then
		return false, API.ERROR_CODES.NETWORK_ERROR, "Roblox blocked or failed the request: " .. tostring(response)
	end

	if response.StatusCode == 200 then
		return true, API.ERROR_CODES.OK, "HackaTime is reachable."
	end

	return false, API.ERROR_CODES.NETWORK_ERROR, "HackaTime returned HTTP " .. tostring(response.StatusCode) .. "."
end

function API.validateAPIKey(apiKey)
	if not apiKey or apiKey == "" then
		return false, API.ERROR_CODES.NO_API_KEY, "API key is not set."
	end

	local payload = {
		time = 1716500000,
		entity = "test.txt",
		type = "file",
		category = "coding",
		is_write = false,
		project = "api-key-test",
	}

	local success, response = pcall(function()
		return HttpService:RequestAsync({
			Url = HeartbeatsEndpoint,
			Method = "POST",
			Headers = {
				["Authorization"] = apiKey:match("^Bearer ") and apiKey or ("Bearer " .. apiKey),
				["Content-Type"] = "application/json",
			},
			Body = HttpService:JSONEncode(payload),
		})
	end)

	if not success then
		return false, API.ERROR_CODES.NETWORK_ERROR, "Validation request failed: " .. tostring(response)
	end

	if response.Success then
		return true, API.ERROR_CODES.OK, "API key validated."
	end

	if response.StatusCode == 401 or response.StatusCode == 403 then
		return false, API.ERROR_CODES.AUTH_ERROR, "API key was rejected."
	end

	return false, API.ERROR_CODES.UNKNOWN, "Validation returned HTTP " .. tostring(response.StatusCode) .. "."
end
return API
