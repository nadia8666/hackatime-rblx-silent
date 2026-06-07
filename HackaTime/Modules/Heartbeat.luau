--[[
	Heartbeat - Enhanced Time Tracking
	Improved heartbeat creation, timing, and data tracking.
	Features:
	- More accurate line change detection
	- Better activity time tracking
	- Improved dominant activity calculation
	- Enhanced line diff algorithm
]]
--
local Heartbeat = {}

local HeartbeatInterval = 60 -- seconds

-- ScriptDocument tracking state
local documentStates = {}
local fallbackStates = {}
local changeStates = {}
local lastKnownLineInfo = nil
local lastHeartbeatPayload = nil

-- Activity tracking
local ActivityTimeTracking = {
	LastReset = os.time(),
	TimeSpent = {},
	CurrentActivity = nil,
	LastActivitySwitch = os.time(),
}

function Heartbeat.init(activityCategories)
	for category, _ in pairs(activityCategories) do
		ActivityTimeTracking.TimeSpent[category] = 0
	end
end

function Heartbeat.updateActivityTimeTracking(currentCategory, activityCategories)
	local now = os.time()

	-- If activity changed, record time spent in previous activity
	if currentCategory ~= ActivityTimeTracking.CurrentActivity then
		if ActivityTimeTracking.CurrentActivity then
			local timeSpent = now - ActivityTimeTracking.LastActivitySwitch
			if not ActivityTimeTracking.TimeSpent[ActivityTimeTracking.CurrentActivity] then
				ActivityTimeTracking.TimeSpent[ActivityTimeTracking.CurrentActivity] = 0
			end
			ActivityTimeTracking.TimeSpent[ActivityTimeTracking.CurrentActivity] = ActivityTimeTracking.TimeSpent[ActivityTimeTracking.CurrentActivity]
				+ timeSpent
		end
		ActivityTimeTracking.CurrentActivity = currentCategory
		ActivityTimeTracking.LastActivitySwitch = now
	end

	-- Check if it's time to send a heartbeat
	if now - ActivityTimeTracking.LastReset >= HeartbeatInterval then
		return true
	end

	return false
end

function Heartbeat.getDominantActivity(activityCategories)
	local maxTime = 0
	local dominantActivity = nil
	local totalActiveTime = 0
	local now = os.time()

	-- Calculate total time spent in each activity including current activity
	local activityTimes = {}
	for category, timeSpent in pairs(ActivityTimeTracking.TimeSpent) do
		activityTimes[category] = timeSpent
		if category ~= activityCategories.IDLE and category ~= activityCategories.UNKNOWN then
			totalActiveTime = totalActiveTime + timeSpent
		end
	end

	-- Add current activity time if it's active
	if
		ActivityTimeTracking.CurrentActivity
		and ActivityTimeTracking.CurrentActivity ~= activityCategories.IDLE
		and ActivityTimeTracking.CurrentActivity ~= activityCategories.UNKNOWN
	then
		local currentActivityTime = now - ActivityTimeTracking.LastActivitySwitch
		activityTimes[ActivityTimeTracking.CurrentActivity] = (activityTimes[ActivityTimeTracking.CurrentActivity] or 0)
			+ currentActivityTime
		totalActiveTime = totalActiveTime + currentActivityTime
	end

	-- Return nil if no significant activity (less than 1 second total)
	if totalActiveTime < 1 then
		return nil
	end

	-- Find the activity with the most time spent
	for category, timeSpent in pairs(activityTimes) do
		if category ~= activityCategories.IDLE and category ~= activityCategories.UNKNOWN and timeSpent > maxTime then
			maxTime = timeSpent
			dominantActivity = category
		end
	end

	return dominantActivity
end

local function getTrackedActivityTimes(activityCategories)
	local now = os.time()
	local activityTimes = {}
	local totalActiveTime = 0

	for category, timeSpent in pairs(ActivityTimeTracking.TimeSpent) do
		activityTimes[category] = timeSpent
		if category ~= activityCategories.IDLE and category ~= activityCategories.UNKNOWN then
			totalActiveTime = totalActiveTime + timeSpent
		end
	end

	if ActivityTimeTracking.CurrentActivity then
		local currentActivityTime = now - ActivityTimeTracking.LastActivitySwitch
		activityTimes[ActivityTimeTracking.CurrentActivity] = (activityTimes[ActivityTimeTracking.CurrentActivity] or 0)
			+ currentActivityTime
		if
			ActivityTimeTracking.CurrentActivity ~= activityCategories.IDLE
			and ActivityTimeTracking.CurrentActivity ~= activityCategories.UNKNOWN
		then
			totalActiveTime = totalActiveTime + currentActivityTime
		end
	end

	return activityTimes, totalActiveTime
end

function Heartbeat.resetActivityTimeTracking()
	local now = os.time()

	-- "Cut" the current activity session so we don't double-count time in the next interval
	if ActivityTimeTracking.CurrentActivity then
		ActivityTimeTracking.LastActivitySwitch = now
	end

	for category, _ in pairs(ActivityTimeTracking.TimeSpent) do
		ActivityTimeTracking.TimeSpent[category] = 0
	end
	ActivityTimeTracking.LastReset = now
end

local function getDocumentName(document, scriptInstance)
	if scriptInstance then
		local success, fullName = pcall(function()
			return scriptInstance:GetFullName()
		end)
		if success and fullName then
			return fullName
		end
		return scriptInstance.Name
	end

	local success, name = pcall(function()
		return document.Name
	end)
	return (success and name) or "Script"
end

local function getSourceState(lineInfo)
	if not lineInfo or not lineInfo.entity then
		return nil
	end
	return changeStates[lineInfo.source_key]
end

function Heartbeat.trackScriptDocument(document)
	if not document then
		return nil
	end

	local scriptInstance = nil
	pcall(function()
		scriptInstance = document:GetScript()
	end)

	local entity = getDocumentName(document, scriptInstance)
	local sourceKey = "doc:" .. tostring(document)
	local text = ""
	local lineCount = nil
	local cursorLine = nil
	local cursorColumn = nil
	local viewportStart = nil
	local viewportEnd = nil

	pcall(function()
		text = document:GetText()
	end)
	pcall(function()
		lineCount = document:GetLineCount()
	end)
	pcall(function()
		cursorLine, cursorColumn = document:GetSelectionStart()
	end)
	pcall(function()
		viewportStart, viewportEnd = document:GetViewport()
	end)

	local state = documentStates[document]
	local additions = 0
	local deletions = 0
	if state and state.text ~= text then
		local oldLineCount = state.lineCount or #string.split(state.text or "", "\n")
		local newLineCount = lineCount or #string.split(text, "\n")
		local delta = newLineCount - oldLineCount
		if delta > 0 then
			additions = delta
		elseif delta < 0 then
			deletions = -delta
		else
			additions = 1
			deletions = 1
		end
	end

	changeStates[sourceKey] = {
		text = text,
		lineCount = lineCount,
		entity = entity,
		updated_at = os.clock(),
	}

	documentStates[document] = {
		text = text,
		lineCount = lineCount,
		lastUpdate = os.clock(),
		entity = entity,
	}

	if not lastKnownLineInfo or lastKnownLineInfo.entity ~= entity then
		lastKnownLineInfo = {
			additions = 0,
			deletions = 0,
			entity = entity,
		}
	end

	lastKnownLineInfo.entity = entity
	lastKnownLineInfo.total_lines = lineCount
	lastKnownLineInfo.cursor_line = cursorLine
	lastKnownLineInfo.cursor_column = cursorColumn
	lastKnownLineInfo.viewport_start = viewportStart
	lastKnownLineInfo.viewport_end = viewportEnd
	lastKnownLineInfo.source_length = text and #text or nil
	lastKnownLineInfo.updated_at = os.time()
	lastKnownLineInfo.source = "ScriptDocument"
	lastKnownLineInfo.source_key = sourceKey
	lastKnownLineInfo.additions = (lastKnownLineInfo.additions or 0) + additions
	lastKnownLineInfo.deletions = (lastKnownLineInfo.deletions or 0) + deletions

	return lastKnownLineInfo
end

function Heartbeat.trackScriptFallback(scriptInstance, cursorPosition)
	if not scriptInstance then
		return nil
	end

	local entity = getDocumentName(nil, scriptInstance)
	local sourceKey = "fallback:" .. tostring(scriptInstance)
	local success, source = pcall(function()
		return scriptInstance.Source
	end)
	if not success then
		return nil
	end

	local lineCount = #string.split(source or "", "\n")
	local state = fallbackStates[scriptInstance]
	local additions = 0
	local deletions = 0
	if state and state.source ~= source then
		local delta = lineCount - (state.lineCount or lineCount)
		if delta > 0 then
			additions = delta
		elseif delta < 0 then
			deletions = -delta
		else
			additions = 1
			deletions = 1
		end
	end

	changeStates[sourceKey] = {
		source = source,
		lineCount = lineCount,
		entity = entity,
		updated_at = os.clock(),
	}

	fallbackStates[scriptInstance] = {
		source = source,
		lineCount = lineCount,
		lastUpdate = os.clock(),
	}

	if not lastKnownLineInfo or lastKnownLineInfo.entity ~= entity then
		lastKnownLineInfo = {
			additions = 0,
			deletions = 0,
			entity = entity,
		}
	end

	lastKnownLineInfo.entity = entity
	lastKnownLineInfo.total_lines = lineCount
	lastKnownLineInfo.cursor_line = cursorPosition and cursorPosition.Line or nil
	lastKnownLineInfo.cursor_column = cursorPosition and cursorPosition.Character or nil
	lastKnownLineInfo.source_length = source and #source or nil
	lastKnownLineInfo.updated_at = os.time()
	lastKnownLineInfo.source = "LuaSourceContainer.Source"
	lastKnownLineInfo.source_key = sourceKey
	lastKnownLineInfo.additions = (lastKnownLineInfo.additions or 0) + additions
	lastKnownLineInfo.deletions = (lastKnownLineInfo.deletions or 0) + deletions

	return lastKnownLineInfo
end

function Heartbeat.createHeartbeatPayload(scriptName, activity, lineInfo, config, activityCategories)
	-- Normalize activity (thinking → coding)
	local actualActivity = activity
	if actualActivity == activityCategories.THINKING then
		actualActivity = activityCategories.CODING
	end

	-- Use provided lineInfo, or fall back to lastKnownLineInfo
	local effectiveLineInfo = lineInfo or lastKnownLineInfo
	local sourceState = getSourceState(effectiveLineInfo)

	-- Determine if this is a write operation
	local isWrite = false
	if sourceState then
		isWrite = (sourceState.additions or 0) > 0 or (sourceState.deletions or 0) > 0
	elseif effectiveLineInfo then
		isWrite = (effectiveLineInfo.additions or 0) > 0 or (effectiveLineInfo.deletions or 0) > 0
	end

	local payload = {
		type = actualActivity,
		time = os.time(),
		entity = effectiveLineInfo and effectiveLineInfo.entity or scriptName,
		category = actualActivity,
		project = config.CurrentProject,
		editor = "Roblox Studio",
		language = "lua",
		is_write = isWrite,
		lines = effectiveLineInfo and effectiveLineInfo.total_lines or nil,
		lineno = effectiveLineInfo and effectiveLineInfo.cursor_line or nil,
		cursorpos = effectiveLineInfo and effectiveLineInfo.cursor_column or nil,
		line_additions = sourceState and sourceState.additions
			or (effectiveLineInfo and effectiveLineInfo.additions or 0),
		line_deletions = sourceState and sourceState.deletions
			or (effectiveLineInfo and effectiveLineInfo.deletions or 0),
		source_key = effectiveLineInfo and effectiveLineInfo.source_key or nil,
		machine_name_id = config.MACHINE_ID,
		operating_system = config.OS_TYPE,
		project_root_count = 1,
		branch = "main",
		user_agent = "roblox-studio-wakatime/3.0.0",
	}

	lastHeartbeatPayload = payload
	return payload
end

function Heartbeat.getLineInfo()
	return lastKnownLineInfo
end

function Heartbeat.getSourceState()
	return changeStates[lastKnownLineInfo and lastKnownLineInfo.source_key or nil]
end

function Heartbeat.getLastHeartbeatPayload()
	return lastHeartbeatPayload
end

function Heartbeat.resetLineInfo()
	-- Reset change counters but preserve position data
	if lastKnownLineInfo then
		lastKnownLineInfo.additions = 0
		lastKnownLineInfo.deletions = 0
		-- Keep total_lines, cursor_line, cursor_column, and entity
	end
end

function Heartbeat.getInterval()
	return HeartbeatInterval
end

-- Check if current minute has countable activity
function Heartbeat.hasCountableActivityThisMinute(activityCategories)
	local _, totalActiveTime = getTrackedActivityTimes(activityCategories)
	return totalActiveTime >= 30
end

-- Validate that heartbeat should be sent (only at full minute intervals with legitimate activity)
function Heartbeat.shouldSendHeartbeat(activityCategories, AI)
	local now = os.time()
	local timeSinceReset = now - ActivityTimeTracking.LastReset

	-- Must be at least HeartbeatInterval (60 seconds)
	if timeSinceReset < HeartbeatInterval then
		return false
	end

	-- Must have countable activity this minute
	if not Heartbeat.hasCountableActivityThisMinute(activityCategories) then
		return false
	end

	local _, totalActiveTime = getTrackedActivityTimes(activityCategories)

	-- REQUIRE AT LEAST 30 SECONDS OF ACTUAL ACTIVITY
	if totalActiveTime < 30 then
		return false
	end

	-- Validate good faith activity if AI module available
	if AI and AI.hasGoodFaithActivity then
		-- Check for good faith activity in the last minute
		if not AI.hasGoodFaithActivity(HeartbeatInterval) then
			-- Not enough diverse activity signals - might just have window open
			return false
		end
	end

	return true
end

-- Get seconds until next heartbeat
function Heartbeat.getSecondsUntilNextHeartbeat()
	local now = os.time()
	local timeSinceReset = now - ActivityTimeTracking.LastReset
	return math.max(0, HeartbeatInterval - timeSinceReset)
end

-- Get total countable activity time in current minute
function Heartbeat.getCountableActivityTime(activityCategories)
	local _, totalActiveTime = getTrackedActivityTimes(activityCategories)
	return totalActiveTime
end

-- Get current activity statistics (for debugging/GUI)
function Heartbeat.getActivityStats()
	local activityTimes = select(1, getTrackedActivityTimes({ IDLE = "idle", UNKNOWN = "unknown" }))
	local stats = {
		current = ActivityTimeTracking.CurrentActivity,
		timeSpent = activityTimes,
		sinceReset = os.time() - ActivityTimeTracking.LastReset,
	}
	return stats
end

-- Clean up old file states (prevents memory leaks)
function Heartbeat.cleanupOldFileStates()
	local now = os.clock()
	local maxAge = 3600 -- 1 hour

	for document, state in pairs(documentStates) do
		if now - state.lastUpdate > maxAge then
			documentStates[document] = nil
		end
	end
	for scriptInstance, state in pairs(fallbackStates) do
		if not scriptInstance or not scriptInstance.Parent or now - state.lastUpdate > maxAge then
			fallbackStates[scriptInstance] = nil
		end
	end
end

return Heartbeat
