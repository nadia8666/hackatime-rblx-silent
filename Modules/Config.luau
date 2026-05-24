--[[
	Config
	Manages loading and saving of all plugin settings and persisted data.
]]--
local Config = {}
local HttpService = game:GetService("HttpService")
local plugin
-- Constants
local WAKATIME_ID_KEY = "WakaTimeProjectId"
-- Module state
Config.WakaTimeAPIKey = ""
Config.OS_TYPE = ""
Config.MACHINE_ID = ""
Config.CurrentProject = ""
Config.HeartbeatQueue = {}
Config.TrackPlaytest = true -- Default to enabled
local function detectOperatingSystem()
	local isMac = false
	pcall(function()
		local UserInputService = game:GetService("UserInputService")
		isMac = UserInputService.KeyboardEnabled and
			(UserInputService:IsKeyDown(Enum.KeyCode.LeftMeta) or
				UserInputService:IsKeyDown(Enum.KeyCode.RightMeta))
	end)
	return isMac and "darwin" or "Windows"
end
function Config.loadOS()
	Config.OS_TYPE = plugin:GetSetting("OverrideOS") or detectOperatingSystem()
	return Config.OS_TYPE
end
function Config.setOSOverride(osType)
	Config.OS_TYPE = osType
	local success, errorMsg = pcall(function()
		plugin:SetSetting("OverrideOS", osType)
	end)
	if not success then
		warn("Error saving OS setting: " .. tostring(errorMsg))
	end
	return success
end
function Config.isSetupComplete()
	return plugin:GetSetting("SetupComplete") == true and Config.WakaTimeAPIKey ~= ""
end
function Config.setSetupComplete(isComplete)
	plugin:SetSetting("SetupComplete", isComplete == true)
end
function Config.loadMachineId()
	local savedId = plugin:GetSetting("MachineId")
	if savedId then
		Config.MACHINE_ID = savedId
		return savedId
	end
	local id = HttpService:GenerateGUID(false)
	plugin:SetSetting("MachineId", id)
	Config.MACHINE_ID = id
	return id
end
function Config.loadAPIKey()
	local success, result = pcall(function()
		return plugin:GetSetting("WakaTimeAPIKey")
	end)
	if success and result and result ~= "" then
		Config.WakaTimeAPIKey = result
	else
		Config.WakaTimeAPIKey = ""
		print("No API key found. Please set it using the plugin settings.")
	end
	return Config.WakaTimeAPIKey
end
function Config.saveAPIKey(apiKey)
	local success, errorMsg = pcall(function()
		plugin:SetSetting("WakaTimeAPIKey", apiKey)
		Config.WakaTimeAPIKey = apiKey
	end)
	if success then
	else
		warn("Error saving API key: " .. tostring(errorMsg))
	end
	return success
end
function Config.persistQueue(queue)
	local success, err = pcall(function()
		if #queue > 0 then
			plugin:SetSetting("HeartbeatQueue", HttpService:JSONEncode(queue))
			plugin:SetSetting("LastSaveTime", os.time())
		else
			plugin:SetSetting("HeartbeatQueue", nil)
			plugin:SetSetting("LastSaveTime", nil)
		end
	end)
	if not success then
		warn("Failed to persist heartbeat queue: " .. tostring(err))
	end
end
function Config.loadQueue()
	local success, result = pcall(function()
		local savedQueue = plugin:GetSetting("HeartbeatQueue")
		local lastSaveTime = plugin:GetSetting("LastSaveTime")
		if savedQueue and lastSaveTime then
			if os.time() - lastSaveTime < 864000 then -- 10 days
				return HttpService:JSONDecode(savedQueue)
			end
		end
		return {}
	end)
	if success and result then
		Config.HeartbeatQueue = result
		print("Heartbeat queue loaded. Items in queue: " .. #Config.HeartbeatQueue)
	else
		Config.HeartbeatQueue = {}
		print("No saved heartbeat queue found or failed to load.")
	end
	return Config.HeartbeatQueue
end
function Config.getCurrentProjectName()
	local MarketplaceService = game:GetService("MarketplaceService")
	local storedId = game:GetService("ReplicatedStorage"):FindFirstChild(WAKATIME_ID_KEY)
	if storedId and storedId:IsA("StringValue") and storedId.Value ~= "" then
		Config.CurrentProject = storedId.Value
		return storedId.Value
	end
	local defaultNames = {["Game"] = true, ["Workspace"] = true, ["StarterPlayer"] = true, ["ReplicatedFirst"] = true, ["BaseGame"] = true, ["TestPlace"] = true, ["Project"] = true, ["Untitled"] = true, [""] = true}
	local projectName = nil
	pcall(function()
		local info = MarketplaceService:GetProductInfo(game.PlaceId)
		if info and info.Name and not defaultNames[info.Name] then
			projectName = info.Name
		end
	end)
	if not projectName and not defaultNames[game.Name] then
		projectName = game.Name
	end
	if not projectName and not defaultNames[workspace.Name] then
		projectName = workspace.Name
	end
	if not projectName and game.PlaceId and game.PlaceId > 0 then
		projectName = "Place" .. tostring(game.PlaceId)
	end
	if projectName then
		local idValue = Instance.new("StringValue")
		idValue.Name = WAKATIME_ID_KEY
		idValue.Value = projectName
		pcall(function()
			idValue.Parent = game:GetService("ReplicatedStorage")
			local comment = Instance.new("Message")
			comment.Parent = idValue
			comment.Text = "This is a WakaTime project identifier. Please don't delete it - it helps track your coding time consistently."
		end)
		Config.CurrentProject = projectName
		return projectName
	end
	local newId = "RoProject-" .. HttpService:GenerateGUID(false):sub(1, 8)
	local idValue = Instance.new("StringValue")
	idValue.Name = WAKATIME_ID_KEY
	idValue.Value = newId
	pcall(function()
		idValue.Parent = game:GetService("ReplicatedStorage")
		local comment = Instance.new("Message")
		comment.Parent = idValue
		comment.Text = "This is a WakaTime project identifier. Please don't delete it - it helps track your coding time consistently."
	end)
	Config.CurrentProject = newId
	return newId
end
-- Playtest tracking setting
function Config.loadPlaytestSetting()
	local trackPlaytest = plugin:GetSetting("TrackPlaytest")
	if trackPlaytest ~= nil then
		Config.TrackPlaytest = trackPlaytest
	else
		-- Default to true if not set
		Config.TrackPlaytest = true
		plugin:SetSetting("TrackPlaytest", true)
	end
end
function Config.setPlaytestTracking(enabled)
	Config.TrackPlaytest = enabled
	plugin:SetSetting("TrackPlaytest", enabled)
end
function Config.getSetting(settingName)
	if settingName == "track_playtest" then
		return Config.TrackPlaytest
	end
	return nil
end
function Config.init(p)
	plugin = p
end
return Config 
