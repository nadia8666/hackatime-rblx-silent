--[[
	Playtest
	Manages detection of play-testing sessions.
]]
--
const Playtest = {}
const RunService = game:GetService("RunService")
const isServer = RunService:IsServer()
const PlayTestTracker = {
	isPlayTesting = false,
	startTime = 0,
	offset = 0,
	lastActiveTime = 0,
	totalPlaytestTime = 0,
}

local hasMouseMoved = false -- This will be updated from the AI module
function PlayTestTracker.started()
	if PlayTestTracker.isPlayTesting then
		return
	end
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
function PlayTestTracker.getKey()
	return `place_{game.PlaceId}_playtest_time`
end
function PlayTestTracker.ended()
	if not PlayTestTracker.isPlayTesting then
		return
	end
	local endTime = os.clock()
	local duration = math.floor(endTime - PlayTestTracker.startTime + PlayTestTracker.offset + 0.5)
	-- Add to total playtest time (inspiration approach)
	if duration >= 5 then
		PlayTestTracker.totalPlaytestTime = PlayTestTracker.totalPlaytestTime + duration
		if isServer then
			plugin:SetSetting(PlayTestTracker.getKey(), (plugin:GetSetting(PlayTestTracker.getKey()) or 0) + duration)
		end
	end
	PlayTestTracker.isPlayTesting = false
	PlayTestTracker.startTime = 0
	PlayTestTracker.offset = 0
end
function Playtest.isPlayTesting()
	return PlayTestTracker.isPlayTesting
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
-- Enhanced playtest tracking (inspiration approach)
function Playtest.started()
	PlayTestTracker.started()
end
function Playtest.ended()
	PlayTestTracker.ended()
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
			task.delay(2, PlayTestTracker.started)
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
