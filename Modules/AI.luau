--[[
	AI - Enhanced Activity Detection
	Improved activity tracking system with better reliability and accuracy.
	Features:
	- More accurate activity detection
	- Better state management
	- Improved idle timeout handling
	- Enhanced script tracking with proper line counting
	- Robust error handling
]]--
local AI = {}
local Util = require(assert(script.Parent):WaitForChild("Util"))

-- Services
local UserInputService = game:GetService("UserInputService")
local Selection = game:GetService("Selection")
local ScriptEditorService = game:GetService("ScriptEditorService")
local StudioService = game:GetService("StudioService")
local CoreGui = game:GetService("CoreGui")
local PluginGuiService = game:GetService("PluginGuiService")

-- Activity categories (WakaTime-compatible)
AI.ActivityCategories = {
	CODING = "coding",
	THINKING = "coding",
	DEBUGGING = "debugging",
	MODELING = "designing",
	BUILDING = "building", 
	UI_DESIGN = "designing",
	CONFIGURING = "coding",
	ANIMATING = "designing",
	IDLE = "idle",
	PLAY_TESTING = "manual testing",
	UNKNOWN = "unknown"
}

-- Internal action types
local enum = {
	actionType = {
		Idle = 0,
		Scripting = 1,
		ThinkingAboutCode = 2,
		Configuring = 3,
		Building = 4,
		UIing = 5,
		Testing = 6,
		ModellingNPC = 7,
		Animating = 8,
		Unknown = 9
	}
}

-- Map internal actions to WakaTime categories
local ActionToCategory = {
	[enum.actionType.Idle] = AI.ActivityCategories.IDLE,
	[enum.actionType.Scripting] = AI.ActivityCategories.CODING,
	[enum.actionType.ThinkingAboutCode] = AI.ActivityCategories.THINKING,
	[enum.actionType.Configuring] = AI.ActivityCategories.CONFIGURING,
	[enum.actionType.Building] = AI.ActivityCategories.BUILDING,
	[enum.actionType.UIing] = AI.ActivityCategories.UI_DESIGN,
	[enum.actionType.Testing] = AI.ActivityCategories.PLAY_TESTING,
	[enum.actionType.ModellingNPC] = AI.ActivityCategories.MODELING,
	[enum.actionType.Animating] = AI.ActivityCategories.ANIMATING,
	[enum.actionType.Unknown] = AI.ActivityCategories.UNKNOWN
}

-- Improved timeout settings (more generous for thinking time)
local stillRelevantTime = {
	[enum.actionType.Scripting] = 8, -- Increased from 5 to account for brief pauses
	[enum.actionType.ThinkingAboutCode] = 90, -- Increased from 60 for longer thinking
	[enum.actionType.UIing] = 10,
	[enum.actionType.Building] = 10,
	[enum.actionType.Configuring] = 10,
	[enum.actionType.ModellingNPC] = 10,
	[enum.actionType.Animating] = 90,
	[enum.actionType.Unknown] = 60,
}

local DEBOUNCE_SCRIPTS_COOLDOWN = 3 -- Reduced for faster response
local MOUSING_RELEVANT_FOR = 5

-- UI Classes for detection
local UIClasses = {
	"ScreenGui", "BillboardGui", "SurfaceGui", "StarterGui", "Frame", "CanvasGroup",
	"TextButton", "TextLabel", "ImageLabel", "ImageButton", "ScrollingFrame", "TextBox"
}

-- State variables
local currentAction = enum.actionType.Idle
local currentSubaction = nil
local currentActionPeakTime = 0
local debounceScriptsSince = 0
local amountOfScriptDocumentsOpened = 0
local isPluginUnloaded = false

-- Scripting state - Enhanced tracking
local scriptStates = {} -- Track state per script
local lastTimeTyped = 0
local lastTimeScriptChanged = 0
local oldSelectedScript = nil
local oldIsScript = false

-- General state
local currentSelectionConnection = nil
local lastTimeMoused = 0
local lastInteractionTime = 0

-- Activity signal tracking for good faith validation
local activitySignals = {
	lastTyping = 0,
	lastMouseMove = 0,
	lastKeyPress = 0,
	lastCursorMove = 0,
	lastScroll = 0,
	lastSelection = 0
}

-- Document connections for cleanup
local documentConnections = {}

-- Animation/modeling state
local oldHumanoid = nil
local tickWhenSelectedCharacter = nil
local characterThatGotSelected = nil
local characterOldCFrames = {}
local oldCharacter = nil
local currentCharacter = nil

-- Public state
AI.CurrentActivityCategory = AI.ActivityCategories.IDLE
AI.isStudioFocused = true
AI.LastActiveScript = nil
AI.LastActiveScriptInfo = nil -- Enhanced: track more script info
local lastUserActivity = os.clock()
local IDLE_TIMEOUT = 45 -- Increased from 30 for more generous idle detection
AI.playtestModule = nil
local heartbeatModule = nil

-- Plugin reference
local plugin = nil
local camera = workspace.CurrentCamera

-- Helper function to bind connections to plugin lifecycle
local function BindToPlugin(connection)
	if plugin then
		plugin.Unloading:Connect(function()
			connection:Disconnect()
		end)
	end
end

-- Helper functions
local function getFirstSelected()
	return Selection:Get()[1]
end

local function disconnectCurrentSelection()
	if currentSelectionConnection then
		currentSelectionConnection:Disconnect()
		currentSelectionConnection = nil
	end
end

local function connectCurrentSelection()
	disconnectCurrentSelection()
	local selected = getFirstSelected()
	if selected then
		currentSelectionConnection = selected.Changed:Connect(function()
			currentActionPeakTime = os.clock()
			lastUserActivity = os.clock()
		end)
	end
end

local function isDescendantOfType(instance, Type)
	if type(Type) == "table" then
		for _, Tipe in ipairs(Type) do
			if isDescendantOfType(instance, Tipe) then
				return true
			end
		end
		return false
	end

	while instance do
		if not instance.Parent then
			break
		end
		if instance:IsA(Type) then
			return true
		end
		instance = instance.Parent
	end
	return false
end

function AI.getSibling(instance, Type)
	while instance do
		local needed = instance:FindFirstChildWhichIsA(Type)
		if needed then
			return needed
		end
		if not instance.Parent then
			break
		end
		instance = instance.Parent
	end
	return nil
end

-- Get opened plugins
function AI.getOpenedPlugins()
	local enabledUIs = {}
	for i, u in ipairs(PluginGuiService:GetChildren()) do
		table.insert(enabledUIs, u)
	end
	return enabledUIs
end

-- Get core GUIs
function AI.getCoreGuis()
	local UIS = CoreGui:GetChildren()
	local enabledUIs = {}
	for i, u in ipairs(UIS) do
		if i % 100 == 0 then task.wait() end
		table.insert(enabledUIs, u)
	end
	return UIS
end

-- Get humanoid in front of camera
function AI.getHumanoidInFront()
	local radius = 20
	local partsNearCamera = workspace:GetPartBoundsInRadius(camera.CFrame.Position, radius)
	task.wait()
	for i, part in ipairs(partsNearCamera) do
		if part:IsA("BasePart") then
			if i % 50 == 0 then task.wait() end
		local humanoid = AI.getSibling(part, "Humanoid")
			if humanoid then
				local _, isOnScreen = camera:WorldToViewportPoint(part.Position)
				if isOnScreen then
					return humanoid
				end
			end
		end
	end
end

-- Default animation detection
function AI.isDefaultAnimating()
	if os.clock() - lastTimeMoused < MOUSING_RELEVANT_FOR then
		local humanoid = AI.getHumanoidInFront()
		if humanoid then
			return true, humanoid.Parent
		end
	end
end

-- Modeling/Animation detection
function AI.isModellingOrAnimating()
	local selected = getFirstSelected()

	if selected then
		local humanoid = AI.getSibling(selected, "Humanoid")
		if humanoid then
			if oldHumanoid ~= humanoid then
				oldHumanoid = humanoid
				currentCharacter = humanoid.Parent
			end
		end
	end

	local isAnimating, character = AI.isDefaultAnimating()
	if isAnimating and character then
		if character ~= oldCharacter then
			oldCharacter = character
			characterOldCFrames = {}
			for i, obj in ipairs(character:GetDescendants()) do
				if obj:IsA("BasePart") then
					characterOldCFrames[obj] = obj.CFrame
				end
			end
			return nil, nil
		end

		local somethingIsChanged = false
		local partDelta
		local sameDelta = 0
		local totalParts = 0

		for i, obj in ipairs(character:GetDescendants()) do
			if obj:IsA("BasePart") then
				totalParts = totalParts + 1

				if not characterOldCFrames[obj] then
					characterOldCFrames[obj] = obj.CFrame
					return enum.actionType.ModellingNPC, character
				end

				local delta = (characterOldCFrames[obj].Position - obj.CFrame.Position).Magnitude

				if delta ~= 0 then
					if not partDelta then
						partDelta = delta
						sameDelta = sameDelta + 1
					else
						if delta == partDelta then
							sameDelta = sameDelta + 1
						end
					end
				end

				if characterOldCFrames[obj] ~= obj.CFrame then
					characterOldCFrames[obj] = obj.CFrame
					somethingIsChanged = true
				end
			end
		end

		if sameDelta == totalParts then
			return enum.actionType.ModellingNPC, character
		end

		if somethingIsChanged then
			return enum.actionType.Animating, character
		end
	else
		oldCharacter = nil
		characterOldCFrames = {}
	end

	-- Check for animation software when working with characters
	if currentCharacter then
		local openedUIs = AI.getCoreGuis()
		local openedWidgets = AI.getOpenedPlugins()
		local all = openedUIs
		for i, obj in ipairs(openedWidgets) do
			table.insert(all, obj)
		end

		local animationSoftwares = {
			{
				f = function(obj)
					return obj.Name == "MoonAnimator2Gui" and obj:IsA("Folder") and #obj:GetChildren() > 1
				end,
			},
		}

		for i, soft in ipairs(animationSoftwares) do
			for i, obj in ipairs(all) do
				local success, output = pcall(function()
					return soft.f(obj)
				end)
				if success and output then
					return enum.actionType.Animating, currentCharacter
				elseif not success then
					warn("HackaTime's animation detector error:", output)
				end
			end
		end
	end
end

-- Active script detection
function AI.getActiveScript()
	return StudioService.ActiveScript
end

-- Enhanced: Get script information including line count
local function getScriptInfo(script)
	if not script then return nil end
	
	local info = scriptStates[script] or {}
	local source = nil
	local lineCount = nil
	
	local cursorLine = nil
	local cursorColumn = nil
	local document = nil
	
	pcall(function()
		local scriptDocuments = ScriptEditorService:GetScriptDocuments()
		for _, scriptDocument in scriptDocuments do
			if scriptDocument:GetScript() == script then
				document = scriptDocument
				source = scriptDocument:GetText()
				lineCount = scriptDocument:GetLineCount()
				cursorLine, cursorColumn = scriptDocument:GetSelectionStart()
				break
			end
		end
	end)

	if not source then
		local success, fallbackSource = pcall(function()
			return script.Source
		end)
		if not success then
			return nil
		end
		source = fallbackSource
		lineCount = #string.split(source, "\n")
	end
	
	return {
		document = document,
		source = source,
		lineCount = lineCount or #string.split(source, "\n"),
		cursorLine = cursorLine,
		cursorColumn = cursorColumn,
		lastModified = os.clock()
	}
end

-- Enhanced scripting state detection with better tracking
function AI.getScriptingState()
	-- Clean up invalid script states
	for script, _ in pairs(scriptStates) do
		if not script or not script.Parent then
			scriptStates[script] = nil
		end
	end

	local openedScript = AI.getActiveScript()
	local isScript = false

	if openedScript then
		isScript = true
		local currentInfo = getScriptInfo(openedScript)
		if not currentInfo then return nil, nil end
		
		local source = currentInfo.source
		AI.LastActiveScript = openedScript
		AI.LastActiveScriptInfo = currentInfo

		-- Script changed
		if openedScript ~= oldSelectedScript then
			oldSelectedScript = openedScript
			lastTimeScriptChanged = os.clock()
			currentActionPeakTime = os.clock()
			debounceScriptsSince = 0
			lastUserActivity = os.clock()
			lastInteractionTime = os.clock()

			-- Initialize or update script state
			if not scriptStates[openedScript] then
				scriptStates[openedScript] = {
					source = source,
					lastTyped = os.clock(),
					lineCount = currentInfo.lineCount
				}
			end

			-- Track ScriptDocument info first, with Source fallback when needed.
			if heartbeatModule then
				if currentInfo.document then
					heartbeatModule.trackScriptDocument(currentInfo.document)
				else
					heartbeatModule.trackScriptFallback(openedScript, {Line = currentInfo.cursorLine, Character = currentInfo.cursorColumn})
				end
			end
		end

		-- Content changed (typing detected)
		local oldState = scriptStates[openedScript]
		if not oldState or source ~= oldState.source then
			scriptStates[openedScript] = {
				source = source,
				lastTyped = os.clock(),
				lineCount = currentInfo.lineCount
			}
			
			lastTimeTyped = os.clock()
			lastTimeScriptChanged = os.clock()
			currentActionPeakTime = os.clock()
			debounceScriptsSince = 0
			lastUserActivity = os.clock()
			lastInteractionTime = os.clock()

			-- Track ScriptDocument changes; fall back only if no document is open.
			if heartbeatModule then
				if currentInfo.document then
					heartbeatModule.trackScriptDocument(currentInfo.document)
				else
					heartbeatModule.trackScriptFallback(openedScript, {Line = currentInfo.cursorLine, Character = currentInfo.cursorColumn})
				end
			end
		end

		-- Determine current state based on activity
		if debounceScriptsSince + DEBOUNCE_SCRIPTS_COOLDOWN < os.clock() then
			local timeSinceTyped = os.clock() - lastTimeTyped
			local timeSinceActivity = os.clock() - lastUserActivity
			local timeSinceScriptChange = os.clock() - lastTimeScriptChanged
			
			-- Active scripting
			if timeSinceTyped < stillRelevantTime[enum.actionType.Scripting] then
				return enum.actionType.Scripting, openedScript
			-- Thinking/reading code
			elseif timeSinceActivity < IDLE_TIMEOUT and 
			       timeSinceScriptChange < stillRelevantTime[enum.actionType.ThinkingAboutCode] then
				return enum.actionType.ThinkingAboutCode, openedScript
			-- Idle
			else
				return enum.actionType.Idle, openedScript
			end
		end
	end

	-- Handle script selection changes
	if oldIsScript ~= isScript then
		oldIsScript = isScript
		if not isScript then
			local newAction = AI.getActionBySelection()
			if newAction then
				currentAction = newAction
				currentActionPeakTime = os.clock()
			end
		end
	end

	return nil, nil
end

-- Selection-based action detection
function AI.getActionBySelection()
	local selected = getFirstSelected()
	if selected then
		local isUiSelection = isDescendantOfType(selected, UIClasses)
		local isBuilding = isDescendantOfType(selected, "Workspace")
		local isScript = selected:IsA("LuaSourceContainer")
		local isCharacter = selected:FindFirstChildWhichIsA("Humanoid")

		-- Check anim/modeling first
		local newAction, newSubaction = AI.isModellingOrAnimating()
		if newAction then
			return newAction, newSubaction
		end

		if isCharacter then
			tickWhenSelectedCharacter = os.clock()
			characterThatGotSelected = selected
			return enum.actionType.ModellingNPC, characterThatGotSelected
		end

		if isScript then
			debounceScriptsSince = 0
			return AI.getScriptingState()
		else
			debounceScriptsSince = os.clock()
			if isUiSelection then
				return enum.actionType.UIing, selected
			elseif isBuilding then
				return enum.actionType.Building, selected
			else
				return enum.actionType.Configuring, selected
			end
		end
	else
		if characterThatGotSelected and tickWhenSelectedCharacter and 
		   os.clock() - tickWhenSelectedCharacter < 0.2 then
			return enum.actionType.Animating, characterThatGotSelected
		end
	end
	return nil, nil
end

-- Main tracking function
function AI.TrackUser()
	-- Check scripting state first (highest priority)
	local newAction, newSubaction = AI.getScriptingState()
	if newAction then
		currentAction = newAction
		currentSubaction = newSubaction
		AI.CurrentActivityCategory = ActionToCategory[currentAction]
		return
	end

	-- Check modeling/animating
	local newAction, newSubaction = AI.isModellingOrAnimating()
	if newAction then
		currentAction = newAction
		currentSubaction = newSubaction
		AI.CurrentActivityCategory = ActionToCategory[currentAction]
		return
	end

	-- Check if current action is still relevant
	if currentAction ~= enum.actionType.Idle then
		local relevanceTime = stillRelevantTime[currentAction]
		if relevanceTime then
			if os.clock() - currentActionPeakTime > relevanceTime then
				-- Transition to idle
				currentAction = enum.actionType.Idle
				currentSubaction = nil
				AI.CurrentActivityCategory = ActionToCategory[currentAction]
			end
		end
	end
end

-- Merge subaction function
function AI.MergeSubaction(subaction, action)
	if type(subaction) == "string" then
		return subaction
	end
	if subaction and subaction:IsA("LuaSourceContainer") then
		return subaction
	end
	if action == enum.actionType.ModellingNPC or action == enum.actionType.Animating then
		return subaction
	end

	local c = subaction
	while c do
		if c and c.Parent and c.Parent.Parent == game then
			return c
		end
		if not c or not c.Parent then
			return "Unknown"
		end
		c = c.Parent
	end
end

-- CheckUnknown function
local function CheckUnknown()
	if currentAction == enum.actionType.Idle then
		-- Only set to unknown if there's recent user activity
		if os.clock() - lastUserActivity < 10 then
			currentAction = enum.actionType.Unknown
			currentSubaction = "Unknown"
			AI.CurrentActivityCategory = ActionToCategory[currentAction]
		end
	end
end

-- Main detection function with improved logic
function AI.detectCurrentActivity(isPlayTesting)
	-- Play testing overrides everything
	if isPlayTesting then
		if currentAction ~= enum.actionType.Testing then
			currentAction = enum.actionType.Testing
			currentSubaction = "Play Testing"
			currentActionPeakTime = os.clock()
			AI.CurrentActivityCategory = ActionToCategory[currentAction]
		end
		return
	end

	-- Check focus and inactivity
	local timeSinceActivity = os.clock() - lastUserActivity
	if not AI.isStudioFocused or timeSinceActivity > IDLE_TIMEOUT then
		if currentAction ~= enum.actionType.Idle then
			currentAction = enum.actionType.Idle
			currentSubaction = nil
			AI.CurrentActivityCategory = ActionToCategory[currentAction]
		end
		return
	end

	-- Run main tracking
	AI.TrackUser()

	-- Update activity category
	AI.CurrentActivityCategory = ActionToCategory[currentAction]

	-- Update last active script if scripting/thinking
	if (currentAction == enum.actionType.Scripting or 
	    currentAction == enum.actionType.ThinkingAboutCode) and 
	   currentSubaction and currentSubaction:IsA("LuaSourceContainer") then
		AI.LastActiveScript = currentSubaction
		AI.LastActiveScriptInfo = getScriptInfo(currentSubaction)
	end
end

-- Good faith activity validator
function AI.hasGoodFaithActivity(timeWindow)
	local now = os.clock()
	local signals = 0
	
	-- Count how many different types of activity in time window
	if now - activitySignals.lastTyping < timeWindow then signals = signals + 1 end
	if now - activitySignals.lastMouseMove < timeWindow then signals = signals + 1 end
	if now - activitySignals.lastKeyPress < timeWindow then signals = signals + 1 end
	if now - activitySignals.lastCursorMove < timeWindow then signals = signals + 1 end
	if now - activitySignals.lastScroll < timeWindow then signals = signals + 1 end
	
	-- Require at least 2 different activity types for "good faith"
	-- This prevents false positives from just having window open
	return signals >= 2
end

-- Backwards compatibility
function AI.GetCurrentAction()
	return currentAction, currentSubaction
end

function AI.getAmountOfScriptDocumentsOpened()
	return amountOfScriptDocumentsOpened
end

-- Initialization
function AI.init(playtestModule, heartbeatModuleRef, pluginObject)
	-- Store references
	AI.playtestModule = playtestModule
	heartbeatModule = heartbeatModuleRef
	plugin = pluginObject

	-- Initialize state
	currentAction = enum.actionType.Idle
	currentSubaction = nil
	currentActionPeakTime = os.clock()
	debounceScriptsSince = os.clock()
	lastTimeTyped = os.clock()
	lastTimeScriptChanged = os.clock()
	lastTimeMoused = os.clock()
	lastUserActivity = os.clock()
	lastInteractionTime = os.clock()
	AI.CurrentActivityCategory = ActionToCategory[currentAction]

	-- Plugin unloading handler
	if plugin then
		plugin.Unloading:Connect(function()
			disconnectCurrentSelection()
			isPluginUnloaded = true
			scriptStates = {}
		end)
	end

	-- Focus detection
	BindToPlugin(UserInputService.WindowFocused:Connect(function()
		AI.isStudioFocused = true
		lastUserActivity = os.clock()
		lastInteractionTime = os.clock()
	end))

	BindToPlugin(UserInputService.WindowFocusReleased:Connect(function()
		AI.isStudioFocused = false
		-- IMMEDIATELY go idle when window loses focus
		currentAction = enum.actionType.Idle
		currentSubaction = nil
		AI.CurrentActivityCategory = ActionToCategory[currentAction]
	end))
	-- Enhanced: Use TextDocumentDidChange event for real-time script editing detection
	BindToPlugin(ScriptEditorService.TextDocumentDidChange:Connect(function(document, changesArray)
		-- Force focus to true whenever we detect typing, to prevent "stuck" false focus state
		AI.isStudioFocused = true
		
		-- Use pcall for safety when accessing document properties
		local scriptSuccess, script = pcall(function() return document:GetScript() end)
		
		if scriptSuccess and script then
			-- Mark as actively typing
			lastTimeTyped = os.clock()
			lastUserActivity = os.clock()
			lastInteractionTime = os.clock()
			currentActionPeakTime = os.clock()
			activitySignals.lastTyping = os.clock()
			
			-- Update script state
			local success, source = pcall(function() return document:GetText() end)
			if success and source then
				scriptStates[script] = {
					source = source,
					lastTyped = os.clock(),
					lineCount = #string.split(source, "\n")
				}
				
				-- Track ScriptDocument directly so draft text, cursor, and line counts stay accurate.
				if heartbeatModule then
					heartbeatModule.trackScriptDocument(document)
				end
			end
			
			-- Set to scripting mode
			if currentAction ~= enum.actionType.Scripting then
				currentAction = enum.actionType.Scripting
				currentSubaction = script
				AI.CurrentActivityCategory = ActionToCategory[currentAction]
				AI.LastActiveScript = script
			end
		end
	end))
	
	-- Enhanced: Track when scripts are opened and set up per-document tracking
	BindToPlugin(ScriptEditorService.TextDocumentDidOpen:Connect(function(document)
		local script = document:GetScript()
		if script then
			oldSelectedScript = script
			lastTimeScriptChanged = os.clock()
			lastUserActivity = os.clock()
			currentActionPeakTime = os.clock()
			
			-- Initialize script state
			local success, source = pcall(function() return document:GetText() end)
			if success and source then
				scriptStates[script] = {
					source = source,
					lastTyped = os.clock(),
					lineCount = #string.split(source, "\n")
				}
			end
			
			-- Set up per-document event tracking
			local connections = {}
			
			-- Track cursor/selection changes (detects code navigation WITHOUT typing)
			local selectionConn = document.SelectionChanged:Connect(function(positionLine, positionChar, anchorLine, anchorChar)
				lastInteractionTime = os.clock()
				lastUserActivity = os.clock()
				currentActionPeakTime = os.clock()
				activitySignals.lastCursorMove = os.clock()
				activitySignals.lastSelection = os.clock()
				
				-- Update ScriptDocument cursor and viewport context even when not typing.
				if heartbeatModule and script == oldSelectedScript then
					pcall(function()
						heartbeatModule.trackScriptDocument(document)
					end)
				end
				
				-- If user is navigating code, they're actively working
				if currentAction == enum.actionType.Idle then
					currentAction = enum.actionType.ThinkingAboutCode
					currentSubaction = script
					AI.CurrentActivityCategory = ActionToCategory[currentAction]
				end
			end)
			table.insert(connections, selectionConn)
			
			-- Track viewport changes (detects scrolling = code reading)
			local viewportConn = document.ViewportChanged:Connect(function(startLine, endLine)
				lastInteractionTime = os.clock()
				lastUserActivity = os.clock()
				activitySignals.lastScroll = os.clock()
				
				-- User is actively reading/reviewing code
				if currentAction == enum.actionType.Idle or currentAction == enum.actionType.Unknown then
					currentAction = enum.actionType.ThinkingAboutCode
					currentSubaction = script
					AI.CurrentActivityCategory = ActionToCategory[currentAction]
					currentActionPeakTime = os.clock()
				end
			end)
			table.insert(connections, viewportConn)
			
			-- Store connections for cleanup
			documentConnections[document] = connections
		end
	end))
	
	-- Enhanced: Track when scripts are closed and clean up connections
	BindToPlugin(ScriptEditorService.TextDocumentDidClose:Connect(function(document)
		-- Wrap GetScript in pcall as accessing a closed document can error
		local success, script = pcall(function() return document:GetScript() end)
		if success and script and script == oldSelectedScript then
			oldSelectedScript = nil
			-- Don't immediately go idle, user might open another script
		end
		
		-- Clean up document-specific connections
		if documentConnections[document] then
			for _, connection in documentConnections[document] do
				connection:Disconnect()
			end
			documentConnections[document] = nil
		end
	end))


	-- Selection changes with improved debouncing
	local lastSelectionIndex = 0
	BindToPlugin(Selection.SelectionChanged:Connect(function()
		AI.isStudioFocused = true -- Force focus true on selection change
		lastSelectionIndex = lastSelectionIndex + 1
		local mySelectionIndex = lastSelectionIndex
		lastUserActivity = os.clock()
		lastInteractionTime = os.clock()
		
		task.wait(0.05) -- Reduced wait for faster response

		if lastSelectionIndex == mySelectionIndex then
			local newAction, newSubaction = AI.getActionBySelection()
			if newAction then
				currentAction = newAction
				currentSubaction = newSubaction
				currentActionPeakTime = os.clock()
				AI.CurrentActivityCategory = ActionToCategory[currentAction]
				connectCurrentSelection()
			end
			CheckUnknown()
		end
	end))

	-- Input changes (mouse movement)
	BindToPlugin(UserInputService.InputChanged:Connect(function()
		AI.isStudioFocused = true -- Force focus true on mouse move
		currentActionPeakTime = os.clock()
		lastTimeMoused = os.clock()
		lastUserActivity = os.clock()
		lastInteractionTime = os.clock()
		activitySignals.lastMouseMove = os.clock()
		CheckUnknown()
	end))
	
	-- Also track key presses for better activity detection
	BindToPlugin(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- Always track key presses as activity signal, even if processed by Studio (e.g. typing in editor)
		activitySignals.lastKeyPress = os.clock()
		AI.isStudioFocused = true -- Force focus true on key press
		
		if not gameProcessed then
			lastUserActivity = os.clock()
			lastInteractionTime = os.clock()
			currentActionPeakTime = os.clock()
		end
	end))

	-- Script document counting
	task.spawn(function()
		while not isPluginUnloaded do
			task.wait(1)
			local scriptDocuments = ScriptEditorService:GetScriptDocuments()
			amountOfScriptDocumentsOpened = 0
			for _, scriptDocument in scriptDocuments do
				if not scriptDocument:IsCommandBar() then
					amountOfScriptDocumentsOpened = amountOfScriptDocumentsOpened + 1
				end
			end
		end
	end)
end

-- Cleanup
function AI.cleanup()
	isPluginUnloaded = true
	disconnectCurrentSelection()
	scriptStates = {}
	
	-- Clean up all document connections
	for document, connections in pairs(documentConnections) do
		for _, connection in connections do
			pcall(function() connection:Disconnect() end)
		end
	end
	documentConnections = {}
end

return AI
