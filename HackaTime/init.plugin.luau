--[[
	HackaTime for Roblox Studio
	Main plugin script - handles initialization and orchestration of modules.
]]
--
-- Get the plugin object
local plugin = script:FindFirstAncestorWhichIsA("Plugin")
-- Debug: Check if plugin object exists
if not plugin then
	error("Plugin object not found! Make sure this script is inside a Plugin.")
end

-- Do not activate in local places
if game.PlaceId == 0 then
	return
end

local Main = {}
-- Service imports
local RunService = game:GetService("RunService")
-- Module imports
local Config = require("@self/Modules/Config")
local API = require("@self/Modules/API")
local AI = require("@self/Modules/AI")
local GUI = require("@self/Modules/GUI")
local Heartbeat = require("@self/Modules/Heartbeat")
local Playtest = require("@self/Modules/Playtest")
-- Plugin state
Main.IsOffline = false
Main.LastErrorCode = nil
Main.LastStatusMessage = ""
Main.HasSuccessfullyConnected = false
local HeartbeatQueue = {}
local guiInstance, updateGuiStatus
function Main.forceSend()
	-- Do not send if client is play testing
	if Playtest.isPlayTesting() and RunService:IsClient() and not RunService:IsServer() then
		Main.LastStatusMessage = "Heartbeats are sent from the server during play testing."
		return
	end
	if #HeartbeatQueue == 0 then
		Main.LastStatusMessage = "Queue is empty."
		return
	end
	Main.LastStatusMessage = "Sending " .. #HeartbeatQueue .. " heartbeats..."
	local success, errCode, msg = API.sendHeartbeats(HeartbeatQueue, Config.WakaTimeAPIKey)
	if success then
		Main.LastStatusMessage = msg
		HeartbeatQueue = {}
		Config.persistQueue(HeartbeatQueue)
		Main.IsOffline = false
		Main.LastErrorCode = nil
		Main.HasSuccessfullyConnected = true
	else
		Main.LastStatusMessage = msg
		Main.IsOffline = true
		Main.LastErrorCode = errCode
		if errCode ~= API.ERROR_CODES.AUTH_ERROR then
			Config.persistQueue(HeartbeatQueue)
		else
			HeartbeatQueue = {} -- Clear queue on auth error
			Config.persistQueue(HeartbeatQueue)
		end
	end
end
function Main.clearQueue()
	HeartbeatQueue = {}
	Config.persistQueue(HeartbeatQueue)
	Main.LastStatusMessage = "Queue cleared."
end
function Main.setProject(newId)
	if newId and newId ~= "" then
		plugin:SetSetting(`place_{game.PlaceId}_name`, newId) --TODO: sanitize input if it is not already, due to json escapes
	end
end
function Main.getQueueSize()
	return #HeartbeatQueue
end
local function init()
	-- Handle server-side playtest detection (inspiration approach)
	if RunService:IsRunning() then
		if not RunService:IsStudio() then
			return
		end
		-- Server-side playtest initialization
		if RunService:IsServer() then
			pcall(function()
				Playtest.init(plugin)
				Playtest.started()
				game:BindToClose(function()
					Playtest.ended(plugin)
				end)
			end)
		end
		return
	end
	-- Initialize modules that need the plugin object
	Config.init(plugin)
	GUI.init(plugin, Main, Config, AI, API, Heartbeat, Playtest)
	-- Load configuration
	Config.loadOS()
	Config.loadMachineId()
	Config.loadAPIKey()
	Config.loadPlaytestSetting()
	Config.getCurrentProjectName()
	HeartbeatQueue = Config.loadQueue()
	-- Initialize other modules
	Playtest.init(plugin)
	Heartbeat.init(AI.ActivityCategories)
	AI.init(Playtest, Heartbeat, plugin)
	-- Plugin unloading handler (from inspiration)
	plugin.Unloading:Connect(function()
		AI.cleanup()
		Config.persistQueue(HeartbeatQueue)
	end)
	-- Create toolbar and GUI with error handling
	local success, errorMsg = pcall(function()
		local toolbar = plugin:CreateToolbar("HackaTime")
		-- Try different icon approaches in case the asset ID is problematic TODO: ...? what?
		local iconOptions = {
			"http://www.roblox.com/asset/?id=85649168710314",
			"rbxassetid://85649168710314",
			"",
		}
		local settingsButton
		for i, iconUrl in ipairs(iconOptions) do
			local buttonSuccess = pcall(function()
				settingsButton = toolbar:CreateButton("HackaTime", "Open HackaTime Plugin GUI", iconUrl)
			end)
			if buttonSuccess then
				break
			else
			end
		end
		if not settingsButton then
			error("Failed to create toolbar button with any icon option")
		end
		guiInstance, updateGuiStatus = GUI.create()
		if not Config.isSetupComplete() then
			guiInstance.Enabled = true
		end
		settingsButton.Click:Connect(function()
			guiInstance.Enabled = not guiInstance.Enabled
		end)
	end)
	if not success then
		warn("HackaTime: Failed to create toolbar/GUI: " .. tostring(errorMsg))
		return
	end
	-- Start main loops
	-- Main detection loop (following inspiration's approach)
	local currentAction = -1
	local DeltaTime = 0
	local LastTimeActionTracked = 0
	local LastTimeStudioPlaytestingTracked = os.clock() - 15
	local ACTION_TRACK_COOLDOWN = 1
	local PLAYTEST_TRACK_COOLDOWN = 45
	local lastCycleTick = os.clock()
	-- Check playtest function (from inspiration)
	local function CheckPlaytest()
		-- Check if playtest tracking is enabled (inspiration approach)
		if not Config.getSetting("track_playtest") then
			return
		end
		-- Record playtest time (inspiration approach)
		if Playtest then
			local success = pcall(function()
				local t = Playtest.getLastPlaytestInfo()
				if t and t > 0 then
					-- Record playtest time to heartbeat with proper timing
					local hb = Heartbeat.createHeartbeatPayload(
						"Play Testing",
						AI.ActivityCategories.PLAY_TESTING,
						nil,
						Config,
						AI.ActivityCategories
					)
					table.insert(HeartbeatQueue, hb)
				end
			end)
			if not success then
				-- Silently handle errors in playtest detection
			end
		end
	end
	local debounceCheckPlaytest = false
	local function mainLoop()
		local lct = lastCycleTick
		lastCycleTick = os.clock()
		DeltaTime = lastCycleTick - lct
		if DeltaTime > 10 then
			DeltaTime = 1 -- PC went to sleep mode, don't add so much delta time
		end
		-- Check for playtest tracking periodically (from inspiration)
		if currentAction ~= 0 and os.clock() - LastTimeStudioPlaytestingTracked > PLAYTEST_TRACK_COOLDOWN then
			LastTimeStudioPlaytestingTracked = os.clock()
			if not debounceCheckPlaytest then
				debounceCheckPlaytest = true
				task.spawn(function()
					pcall(function()
						CheckPlaytest()
					end)
					debounceCheckPlaytest = false
				end)
			end
		end
		-- Main activity detection
		if not Playtest.isPlayTesting() then
			local isPlayTesting = Playtest.isPlayTesting()
			-- Wrap in pcall to prevent crashes from stopping the heartbeat loop
			pcall(function()
				AI.detectCurrentActivity(isPlayTesting)
			end)
		end
		-- Collect and record data with improved error handling
		if os.clock() - LastTimeActionTracked > ACTION_TRACK_COOLDOWN then
			-- Track user actions
			local trackSuccess, trackError = pcall(function()
				AI.TrackUser()
			end)
			if not trackSuccess then
				warn("HackaTime: Error tracking user activity:", trackError)
			end

			-- Get current action
			task.wait()
			local newAction, newSubaction
			local actionSuccess, actionError = pcall(function()
				newAction, newSubaction = AI.GetCurrentAction()
				newSubaction = AI.MergeSubaction(newSubaction, newAction)
			end)

			if not actionSuccess then
				warn("HackaTime: Error getting current action:", actionError)
			end

			-- Update current action if changed
			if newAction and currentAction ~= newAction then
				currentAction = newAction
			end

			-- Record data and send heartbeats (only at full minute intervals)
			task.wait()
			local heartbeatSuccess, heartbeatError = pcall(function()
				-- Update activity tracking for heartbeats
				local timeToSendHeartbeat =
					Heartbeat.updateActivityTimeTracking(AI.CurrentActivityCategory, AI.ActivityCategories)
				if timeToSendHeartbeat then
					-- Wrap heartbeat generation in pcall to ensure we always reset tracking
					local genSuccess, genError = pcall(function()
						-- Validate that we should send heartbeat (good faith activity check)
						if Heartbeat.shouldSendHeartbeat(AI.ActivityCategories, AI) then
							local dominantActivity = Heartbeat.getDominantActivity(AI.ActivityCategories)
							if dominantActivity then
								local entityName = "Roblox Studio"
								local lineInfo = nil

								-- Determine entity name and line info based on activity
								if
									dominantActivity == AI.ActivityCategories.CODING
									or dominantActivity == AI.ActivityCategories.THINKING
								then
									lineInfo = Heartbeat.getLineInfo()
									if lineInfo and lineInfo.entity then
										entityName = lineInfo.entity
									end
									if AI.LastActiveScript then
										local success, name = pcall(function()
											return AI.LastActiveScript.Name
										end)
										if not lineInfo or not lineInfo.entity then
											entityName = (success and name) or "Script"
										end
									end
								elseif dominantActivity == AI.ActivityCategories.BUILDING then
									entityName = "Workspace Editing"
								elseif dominantActivity == AI.ActivityCategories.UI_DESIGN then
									entityName = "UI Design"
								elseif dominantActivity == AI.ActivityCategories.ANIMATING then
									entityName = "Animation Editing"
								elseif dominantActivity == AI.ActivityCategories.MODELING then
									entityName = "Character Modeling"
								elseif dominantActivity == AI.ActivityCategories.PLAY_TESTING then
									entityName = "Play Testing"
								end

								-- Create and queue heartbeat
								local hb = Heartbeat.createHeartbeatPayload(
									entityName,
									dominantActivity,
									lineInfo,
									Config,
									AI.ActivityCategories
								)
								table.insert(HeartbeatQueue, hb)
								Heartbeat.resetLineInfo()

								-- Send heartbeats asynchronously
								task.spawn(function()
									pcall(function()
										Main.forceSend()
									end)
								end)
							end
						end
					end)

					if not genSuccess then
						warn("HackaTime: Error generating heartbeat: " .. tostring(genError))
					end

					-- Always reset tracking if interval passed, even if generation failed
					Heartbeat.resetActivityTimeTracking()
				end
			end)

			if not heartbeatSuccess then
				warn("HackaTime: Error processing heartbeat:", heartbeatError)
			end

			LastTimeActionTracked = os.clock()
			task.wait()
		end
		-- Update GUI with current state
		if guiInstance and updateGuiStatus then
			updateGuiStatus()
		end
	end
	-- Activity detection and time tracking loop (using inspiration's polling approach)
	RunService.Heartbeat:Connect(function()
		-- When window loses focus, immediately stop ALL activity tracking
		if not AI.isStudioFocused then
			if updateGuiStatus then
				updateGuiStatus()
			end -- keep gui updated even if window not focused
			return -- Don't run main loop at all when unfocused
		end
		-- Run main loop logic only when focused
		pcall(mainLoop)
	end)
	-- GUI update loop
	task.spawn(function()
		while true do
			task.wait(2)
			if guiInstance and guiInstance.Enabled then
				updateGuiStatus()
			end
		end
	end)
	-- Persist queue periodically and cleanup
	task.spawn(function()
		while true do
			task.wait(300) -- 5 minutes
			Config.persistQueue(HeartbeatQueue)
			-- Clean up old file states to prevent memory leaks
			pcall(Heartbeat.cleanupOldFileStates)
		end
	end)
	-- BindToClose should only be used on the server side to avoid errors in the plugin environment
	if RunService:IsServer() then
		game:BindToClose(function()
			Config.persistQueue(HeartbeatQueue)
		end)
	end
end
init()
