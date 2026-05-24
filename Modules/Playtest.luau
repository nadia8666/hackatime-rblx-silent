--[[
	Playtest
	Manages detection of play-testing sessions.
]]--
local Playtest = {}
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local isServer = RunService:IsServer()
local isClient = RunService:IsClient() and not isServer
local PlayTestTracker = {
	isPlayTesting = false,
	startTime = 0,
	offset = 0,
	lastActiveTime = 0,
	dataStoreEnabled = false,
	totalPlaytestTime = 0,
	storage = {
		pcall(function()
			return DataStoreService:GetDataStore("HackaTime_PlayTest_Data")
		end)
	}
}
PlayTestTracker.dataStoreEnabled = PlayTestTracker.storage[1] or false
local hasMouseMoved = false -- This will be updated from the AI module
function PlayTestTracker.started()
	if PlayTestTracker.isPlayTesting then return end
	PlayTestTracker.isPlayTesting = true
	PlayTestTracker.startTime = os.clock()
	PlayTestTracker.lastActiveTime = os.clock()
	task.spawn(function()
		while PlayTestTracker.isPlayTesting do
			local deltaTime = task.wait(1)
			if deltaTime > 10 then
				PlayTestTracker.offset = PlayTestTracker.offset - deltaTime
			end
			if hasMouseMoved then
				PlayTestTracker.lastActiveTime = os.clock()
				hasMouseMoved = false
			end
		end
	end)
end
function PlayTestTracker.ended()
	if not PlayTestTracker.isPlayTesting then return end
	local endTime = os.clock()
	local duration = math.floor(endTime - PlayTestTracker.startTime + PlayTestTracker.offset + 0.5)
	-- Add to total playtest time (inspiration approach)
	if duration >= 5 then
		PlayTestTracker.totalPlaytestTime = PlayTestTracker.totalPlaytestTime + duration
		if isServer then
			if PlayTestTracker.storage[1] then
				pcall(function()
					local store = PlayTestTracker.storage[2]
					for i = 1, 3 do
						local success = pcall(function()
							store:IncrementAsync("playtest_total_time", duration)
						end)
						if success then break end
					end
				end)
			end
		end
	end
	PlayTestTracker.isPlayTesting = false
	PlayTestTracker.startTime = 0
	PlayTestTracker.offset = 0
end
function Playtest.isPlayTesting()
	return PlayTestTracker.isPlayTesting
end
function Playtest.isDataStoreEnabled()
	return PlayTestTracker.dataStoreEnabled
end
function Playtest.setMouseMoved(moved)
	hasMouseMoved = moved
end
-- Get last playtest info (inspiration approach)
function Playtest.getLastPlaytestInfo()
	if not PlayTestTracker.isPlayTesting then
		if PlayTestTracker.totalPlaytestTime > 0 then
			local time = PlayTestTracker.totalPlaytestTime
			PlayTestTracker.totalPlaytestTime = 0 -- Reset after reporting
			return time
		end
		return 0
	end
	-- If currently playtesting, return current session time
	local currentDuration = math.floor(os.clock() - PlayTestTracker.startTime + PlayTestTracker.offset + 0.5)
	return math.max(currentDuration, 0)
end
-- Check if can access API services (inspiration approach)
function Playtest.checkIfCanAccessAPIServices()
	local has_internet = false
	local api_services_enabled = false
	-- Test internet connection and API services
	local success = pcall(function()
		if PlayTestTracker.storage[1] then
			api_services_enabled = true
			-- Simple test to check internet
			local store = PlayTestTracker.storage[2]
			store:GetAsync("test_connection")
			has_internet = true
		end
	end)
	return has_internet, api_services_enabled
end
-- Enhanced playtest tracking (inspiration approach)
function Playtest.started()
	PlayTestTracker.started()
end
function Playtest.ended()
	PlayTestTracker.ended()
end
-- Get playtest status info (for GUI display)
function Playtest.getPlaytestStatus()
	return {
		isPlayTesting = PlayTestTracker.isPlayTesting,
		currentSessionTime = PlayTestTracker.isPlayTesting and 
			math.floor(os.clock() - PlayTestTracker.startTime + PlayTestTracker.offset + 0.5) or 0,
		totalPlaytestTime = PlayTestTracker.totalPlaytestTime,
		dataStoreEnabled = PlayTestTracker.dataStoreEnabled
	}
end
function Playtest.init()
	RunService.Heartbeat:Connect(function()
		local isRunning = RunService:IsRunning()
		local isStudio = RunService:IsStudio()
		local isPlayTest = isRunning and isStudio
		if isPlayTest and not PlayTestTracker.isPlayTesting then
			PlayTestTracker.started()
		elseif not isPlayTest and PlayTestTracker.isPlayTesting then
			PlayTestTracker.ended()
		end
	end)
	-- Handle server-side playtest startup (inspiration approach)
	if RunService:IsRunning() and RunService:IsStudio() then
		if RunService:IsServer() then
			-- Server-side initialization (inspiration approach)
			task.spawn(function() 
				wait(2)
				PlayTestTracker.started()
			end)
		end
	end
	-- BindToClose should only be called on the server
	if isServer then
		game:BindToClose(function()
			if PlayTestTracker.isPlayTesting then
				PlayTestTracker.ended()
			end
		end)
	end
end
return Playtest 