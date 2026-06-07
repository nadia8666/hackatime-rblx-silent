--[[
	GUI
	Creates and manages the plugin's user interface and first-run setup.
]]

local GUI = {}

local plugin
local Config, AI, API, Heartbeat, Playtest, Main
local DEBUG_CONTEXT_VISIBLE = false
local HttpService = game:GetService("HttpService")

local ColorScheme = {
	Light = {
		Background = Color3.fromRGB(243, 246, 252),
		BackgroundSecondary = Color3.fromRGB(229, 235, 246),
		Text = Color3.fromRGB(24, 30, 42),
		TextMuted = Color3.fromRGB(92, 103, 123),
		Primary = Color3.fromRGB(34, 105, 255),
		PrimaryHover = Color3.fromRGB(20, 87, 229),
		Success = Color3.fromRGB(19, 161, 94),
		Warning = Color3.fromRGB(217, 132, 20),
		Error = Color3.fromRGB(218, 55, 68),
		Border = Color3.fromRGB(205, 215, 232),
		CardBackground = Color3.fromRGB(255, 255, 255),
		Hero = Color3.fromRGB(224, 236, 255),
	},
	Dark = {
		Background = Color3.fromRGB(16, 19, 28),
		BackgroundSecondary = Color3.fromRGB(31, 37, 52),
		Text = Color3.fromRGB(244, 247, 255),
		TextMuted = Color3.fromRGB(167, 177, 198),
		Primary = Color3.fromRGB(92, 156, 255),
		PrimaryHover = Color3.fromRGB(116, 176, 255),
		Success = Color3.fromRGB(49, 207, 128),
		Warning = Color3.fromRGB(255, 177, 71),
		Error = Color3.fromRGB(255, 93, 108),
		Border = Color3.fromRGB(62, 72, 95),
		CardBackground = Color3.fromRGB(24, 29, 41),
		Hero = Color3.fromRGB(35, 52, 87),
	},
}

local CategoryIcons = {}
local StatusIcons = { Connected = "✅", Offline = "❌", Warning = "⚠️", Info = "ℹ️" }

local function getTheme()
	return settings().Studio.Theme.Name:lower():match("dark") and "Dark" or "Light"
end

local function createCard(parent, cornerRadius)
	local colors = ColorScheme[getTheme()]
	local card = Instance.new("Frame")
	card.BackgroundColor3 = colors.CardBackground
	card.BorderSizePixel = 0
	card.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, cornerRadius or 12)
	c.Parent = card
	local s = Instance.new("UIStroke")
	s.Color = colors.Border
	s.Thickness = 1
	s.Transparency = 0.35
	s.Parent = card
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, 14)
	p.PaddingBottom = UDim.new(0, 14)
	p.PaddingLeft = UDim.new(0, 14)
	p.PaddingRight = UDim.new(0, 14)
	p.Parent = card
	return card
end

local function createButton(parent, text, color, textColor)
	local colors = ColorScheme[getTheme()]
	local b = Instance.new("TextButton")
	b.Text = text
	b.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
	b.BackgroundColor3 = color or colors.Primary
	b.TextSize = 14
	b.Font = Enum.Font.SourceSansSemibold
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = (color or colors.Primary):Lerp(Color3.new(1, 1, 1), 0.08)
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = color or colors.Primary
	end)
	return b
end

local function createLabel(parent, text, size, color, font)
	local colors = ColorScheme[getTheme()]
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or colors.Text
	label.TextSize = size or 14
	label.Font = font or Enum.Font.SourceSans
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Parent = parent
	return label
end

local function createSectionHeader(parent, text)
	local colors = ColorScheme[getTheme()]
	local h = createLabel(parent, text, 12, colors.TextMuted, Enum.Font.SourceSansBold)
	h.Size = UDim2.new(1, 0, 0, 20)
	return h
end

local function createInputField(parent, placeholder, defaultText)
	local colors = ColorScheme[getTheme()]
	local cont = Instance.new("Frame")
	cont.BackgroundColor3 = colors.BackgroundSecondary
	cont.BorderSizePixel = 0
	cont.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = cont
	local i = Instance.new("TextBox")
	i.Size = UDim2.new(1, -16, 1, 0)
	i.Position = UDim2.fromOffset(8, 0)
	i.Text = defaultText or ""
	i.PlaceholderText = placeholder
	i.TextColor3 = colors.Text
	i.PlaceholderColor3 = colors.TextMuted
	i.BackgroundTransparency = 1
	i.TextSize = 14
	i.Font = Enum.Font.SourceSans
	i.TextXAlignment = Enum.TextXAlignment.Left
	i.ClearTextOnFocus = false
	i.Parent = cont
	return i
end

local function processToken(text)
	local token = text or ""
	if token:match("%$env:BEARER_TOKEN") then
		token = token:match('%$env:BEARER_TOKEN="(.-)"') or token
	end
	if token:match("export BEARER_TOKEN") then
		token = token:match('BEARER_TOKEN="(.-)"') or token
	end
	return token
end

local function formatOS(osType)
	if osType == "darwin" then
		return "🍎 macOS"
	end
	if osType == "Linux" then
		return "🐧 Linux"
	end
	if osType == "Windows" then
		return "💥 Windows"
	end
	return osType or "Not set"
end

local function friendlyCategory(category)
	if category == "coding" then
		return "Coding"
	end
	if category == "building" then
		return "Building"
	end
	if category == "designing" then
		return "Designing"
	end
	if category == "debugging" then
		return "Debugging"
	end
	if category == "manual testing" then
		return "Playtesting"
	end
	if category == "idle" then
		return "Waiting for activity"
	end
	if category == "unknown" then
		return "Checking activity"
	end
	return category or "Checking activity"
end

-- TODO: make the setup window not so unreasonably tall
function GUI.create()
	local colors = ColorScheme[getTheme()]
	local pluginGui = plugin:CreateDockWidgetPluginGui(
		"WakaTimeSettings",
		DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 390, 590, 360, 520)
	)
	pluginGui.Title = "HackaTime"

	CategoryIcons = {
		[AI.ActivityCategories.CODING] = "💻",
		[AI.ActivityCategories.THINKING] = "🤔",
		[AI.ActivityCategories.DEBUGGING] = "🔍",
		[AI.ActivityCategories.MODELING] = "👤",
		[AI.ActivityCategories.BUILDING] = "🏗️",
		[AI.ActivityCategories.UI_DESIGN] = "🎨",
		[AI.ActivityCategories.CONFIGURING] = "⚙️",
		[AI.ActivityCategories.ANIMATING] = "🎬",
		[AI.ActivityCategories.IDLE] = "⏸️",
		[AI.ActivityCategories.PLAY_TESTING] = "🎯",
		[AI.ActivityCategories.UNKNOWN] = "❓",
	}

	local mainFrame = Instance.new("Frame")
	mainFrame.Size = UDim2.fromScale(1, 1)
	mainFrame.BackgroundColor3 = colors.Background
	mainFrame.Parent = pluginGui

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, -12, 1, -12)
	scrollFrame.Position = UDim2.fromOffset(6, 6)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.CanvasSize = UDim2.fromOffset(0, 900)
	scrollFrame.Parent = mainFrame

	local uiListLayout = Instance.new("UIListLayout")
	uiListLayout.Padding = UDim.new(0, 12)
	uiListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	uiListLayout.Parent = scrollFrame
	local scrollPadding = Instance.new("UIPadding")
	scrollPadding.PaddingTop = UDim.new(0, 4)
	scrollPadding.PaddingLeft = UDim.new(0, 2)
	scrollPadding.PaddingRight = UDim.new(0, 8)
	scrollPadding.Parent = scrollFrame
	uiListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scrollFrame.CanvasSize = UDim2.fromOffset(0, uiListLayout.AbsoluteContentSize.Y + 24)
	end)

	local setupCard = createCard(scrollFrame, 14)
	setupCard.LayoutOrder = 0
	setupCard.AutomaticSize = Enum.AutomaticSize.Y
	setupCard.Size = UDim2.new(1, 0, 0, 0)
	local setupLayout = Instance.new("UIListLayout")
	setupLayout.Padding = UDim.new(0, 12)
	setupLayout.SortOrder = Enum.SortOrder.LayoutOrder
	setupLayout.Parent = setupCard

	local setupHero = Instance.new("Frame", setupCard)
	setupHero.LayoutOrder = 1
	setupHero.BackgroundColor3 = colors.Hero
	setupHero.BorderSizePixel = 0
	setupHero.Size = UDim2.new(1, 0, 0, 78)
	local setupHeroCorner = Instance.new("UICorner")
	setupHeroCorner.CornerRadius = UDim.new(0, 12)
	setupHeroCorner.Parent = setupHero
	local setupLogo = Instance.new("ImageLabel", setupHero)
	setupLogo.Size = UDim2.fromOffset(52, 52)
	setupLogo.Position = UDim2.fromOffset(10, 13)
	setupLogo.BackgroundTransparency = 1
	setupLogo.Image = "rbxassetid://85649168710314"
	local setupTitle =
		createLabel(setupHero, "Welcome to HackaTime for Roblox Studio", 24, colors.Text, Enum.Font.SourceSansBold)
	setupTitle.Position = UDim2.fromOffset(72, 12)
	setupTitle.Size = UDim2.new(1, -82, 0, 30)
	local setupSubtitle =
		createLabel(setupHero, "Roblox Studio time tracking", 13, colors.TextMuted, Enum.Font.SourceSansSemibold)
	setupSubtitle.Position = UDim2.fromOffset(72, 44)
	setupSubtitle.Size = UDim2.new(1, -82, 0, 22)
	local setupStepLabel = createLabel(setupCard, "", 14, colors.TextMuted)
	setupStepLabel.LayoutOrder = 2
	setupStepLabel.AutomaticSize = Enum.AutomaticSize.Y
	setupStepLabel.Size = UDim2.new(1, 0, 0, 0)
	local setupInput = createInputField(setupCard, "Paste API key from hackatime.hackclub.com/api-key", "")
	setupInput.Parent.LayoutOrder = 3
	setupInput.Parent.Size = UDim2.new(1, 0, 0, 40)
	setupInput.Parent.Visible = false
	local setupOSButtons = Instance.new("Frame", setupCard)
	setupOSButtons.LayoutOrder = 4
	setupOSButtons.BackgroundTransparency = 1
	setupOSButtons.Size = UDim2.new(1, 0, 0, 92)
	setupOSButtons.Visible = false
	local setupMacButton = createButton(setupOSButtons, "macOS", colors.BackgroundSecondary, colors.Text)
	setupMacButton.Size = UDim2.new(1, 0, 0, 28)
	local setupLinuxButton = createButton(setupOSButtons, "Linux", colors.BackgroundSecondary, colors.Text)
	setupLinuxButton.Position = UDim2.fromOffset(0, 32)
	setupLinuxButton.Size = UDim2.new(1, 0, 0, 28)
	local setupWinButton = createButton(setupOSButtons, "Windows", colors.BackgroundSecondary, colors.Text)
	setupWinButton.Position = UDim2.fromOffset(0, 64)
	setupWinButton.Size = UDim2.new(1, 0, 0, 28)
	local setupStatus = createLabel(setupCard, "", 13, colors.TextMuted)
	setupStatus.LayoutOrder = 5
	setupStatus.AutomaticSize = Enum.AutomaticSize.Y
	setupStatus.Size = UDim2.new(1, 0, 0, 0)
	local setupButton = createButton(setupCard, "Continue", colors.Primary, Color3.fromRGB(255, 255, 255))
	setupButton.LayoutOrder = 6
	setupButton.Size = UDim2.new(1, 0, 0, 38)

	local headerCard = createCard(scrollFrame, 14)
	headerCard.LayoutOrder = 1
	headerCard.Size = UDim2.new(1, 0, 0, 92)
	local debugCard = createCard(scrollFrame, 14)
	debugCard.LayoutOrder = 2
	debugCard.Size = UDim2.new(1, 0, 0, 320)
	debugCard.Visible = DEBUG_CONTEXT_VISIBLE
	local statusCard = createCard(scrollFrame, 14)
	statusCard.LayoutOrder = 3
	statusCard.Size = UDim2.new(1, 0, 0, 112)
	local projectCard = createCard(scrollFrame, 14)
	projectCard.LayoutOrder = 4
	projectCard.Size = UDim2.new(1, 0, 0, 126)
	local actionsCard = createCard(scrollFrame, 14)
	actionsCard.LayoutOrder = 5
	actionsCard.Size = UDim2.new(1, 0, 0, 156)
	local apiKeyCard = createCard(scrollFrame, 14)
	apiKeyCard.LayoutOrder = 6
	apiKeyCard.Size = UDim2.new(1, 0, 0, 152)
	local osCard = createCard(scrollFrame, 14)
	osCard.LayoutOrder = 7
	osCard.Size = UDim2.new(1, 0, 0, 132)
	local warningCard = createCard(scrollFrame, 14)
	warningCard.LayoutOrder = 8
	warningCard.Visible = false
	local statusContainer = createCard(scrollFrame, 14)
	statusContainer.LayoutOrder = 9
	statusContainer.Size = UDim2.new(1, 0, 0, 46)

	local logo = Instance.new("ImageLabel", headerCard)
	logo.Size = UDim2.fromOffset(56, 56)
	logo.Position = UDim2.fromOffset(0, 4)
	logo.BackgroundTransparency = 1
	logo.Image = "rbxassetid://85649168710314"
	local title = createLabel(headerCard, "HackaTime", 28, colors.Text, Enum.Font.SourceSansBold)
	title.Position = UDim2.fromOffset(66, 0)
	title.Size = UDim2.new(1, -136, 0, 34)
	local versionLabel = Instance.new("TextLabel", headerCard)
	versionLabel.Size = UDim2.fromOffset(48, 22)
	versionLabel.Position = UDim2.new(1, -48, 0, 4)
	versionLabel.Text = "v3"
	versionLabel.TextColor3 = colors.Primary
	versionLabel.BackgroundColor3 = colors.Hero
	versionLabel.TextSize = 12
	versionLabel.Font = Enum.Font.SourceSansBold
	versionLabel.BorderSizePixel = 0
	local versionCorner = Instance.new("UICorner")
	versionCorner.CornerRadius = UDim.new(0, 6)
	versionCorner.Parent = versionLabel
	local subtitle = createLabel(headerCard, "Roblox Studio time tracking", 14, colors.TextMuted)
	subtitle.Position = UDim2.fromOffset(66, 38)
	subtitle.Size = UDim2.new(1, -66, 0, 34)

	createSectionHeader(debugCard, "🧪 DEBUG CONTEXT")
	local debugFileLabel = createLabel(debugCard, "", 13, colors.Text)
	debugFileLabel.Position = UDim2.fromOffset(0, 24)
	debugFileLabel.Size = UDim2.new(1, 0, 0, 20)
	local debugLineLabel = createLabel(debugCard, "", 13, colors.TextMuted)
	debugLineLabel.Position = UDim2.fromOffset(0, 46)
	debugLineLabel.Size = UDim2.new(1, 0, 0, 20)
	local debugExtraLabel = createLabel(debugCard, "", 12, colors.TextMuted)
	debugExtraLabel.Position = UDim2.fromOffset(0, 70)
	debugExtraLabel.Size = UDim2.new(1, 0, 0, 34)
	local debugHeartbeatLabel = createLabel(debugCard, "", 11, colors.TextMuted)
	debugHeartbeatLabel.Position = UDim2.fromOffset(0, 106)
	debugHeartbeatLabel.Size = UDim2.new(1, 0, 0, 196)
	debugHeartbeatLabel.TextWrapped = true

	createSectionHeader(statusCard, "⏱️ CURRENT MINUTE")
	local categoryLabel = createLabel(statusCard, "", 22, colors.Primary, Enum.Font.SourceSansBold)
	categoryLabel.Position = UDim2.fromOffset(0, 25)
	categoryLabel.Size = UDim2.new(1, 0, 0, 30)
	local minuteActivityLabel = createLabel(statusCard, "", 13, colors.TextMuted)
	minuteActivityLabel.Position = UDim2.fromOffset(0, 58)
	minuteActivityLabel.Size = UDim2.new(1, 0, 0, 38)

	createSectionHeader(apiKeyCard, "🔑 API KEY")
	local tokenInput = createInputField(apiKeyCard, "Paste API key", Config.WakaTimeAPIKey)
	tokenInput.Parent.Size = UDim2.new(1, 0, 0, 40)
	tokenInput.Parent.Position = UDim2.fromOffset(0, 25)
	tokenInput.Text = Config.WakaTimeAPIKey ~= "" and "••••••••••••••••" or ""
	local apiKeyButtons = Instance.new("Frame", apiKeyCard)
	apiKeyButtons.Size = UDim2.new(1, 0, 0, 34)
	apiKeyButtons.Position = UDim2.fromOffset(0, 78)
	apiKeyButtons.BackgroundTransparency = 1
	local saveButton =
		createButton(apiKeyButtons, "💾 Save + Validate", colors.Primary, Color3.fromRGB(255, 255, 255))
	saveButton.Size = UDim2.new(0.56, 0, 1, 0)
	local getApiKeyButton = createButton(apiKeyButtons, "Get Key", colors.BackgroundSecondary, colors.Text)
	getApiKeyButton.Size = UDim2.new(0.4, 0, 1, 0)
	getApiKeyButton.Position = UDim2.new(0.6, 0, 0, 0)

	createSectionHeader(actionsCard, "📡 SYNC")
	local queueLabel = createLabel(actionsCard, "", 14, colors.Text)
	queueLabel.Position = UDim2.fromOffset(0, 25)
	queueLabel.Size = UDim2.new(1, 0, 0, 22)
	local actionButtons = Instance.new("Frame", actionsCard)
	actionButtons.Size = UDim2.new(1, 0, 0, 66)
	actionButtons.Position = UDim2.fromOffset(0, 52)
	actionButtons.BackgroundTransparency = 1
	local forceSendButton = createButton(actionButtons, "📤 Send Now", colors.Success, Color3.fromRGB(255, 255, 255))
	forceSendButton.Size = UDim2.new(0.48, 0, 0, 30)
	local clearQueueButton =
		createButton(actionButtons, "🗑️ Clear Queue", colors.Error, Color3.fromRGB(255, 255, 255))
	clearQueueButton.Size = UDim2.new(0.48, 0, 0, 30)
	clearQueueButton.Position = UDim2.new(0.52, 0, 0, 0)
	local helpButton = createButton(actionButtons, "❓ Help and Support", colors.BackgroundSecondary, colors.Text)
	helpButton.Size = UDim2.new(1, 0, 0, 30)
	helpButton.Position = UDim2.fromOffset(0, 36)

	createSectionHeader(projectCard, "🏗️ PROJECT")
	local projectLabel = createLabel(projectCard, "", 13, colors.TextMuted)
	projectLabel.Position = UDim2.fromOffset(0, 22)
	projectLabel.Size = UDim2.new(1, 0, 0, 18)
	local projectInput = createInputField(projectCard, "Override project name", "")
	projectInput.Parent.Size = UDim2.new(0.68, 0, 0, 36)
	projectInput.Parent.Position = UDim2.fromOffset(0, 46)
	local setProjectButton = createButton(projectCard, "📝 Set", colors.Primary, Color3.fromRGB(255, 255, 255))
	setProjectButton.Size = UDim2.new(0.28, 0, 0, 36)
	setProjectButton.Position = UDim2.new(0.72, 0, 0, 46)

	createSectionHeader(osCard, "🖥️ OPERATING SYSTEM")
	local currentOSLabel = createLabel(osCard, "", 14, colors.Text)
	currentOSLabel.Position = UDim2.fromOffset(0, 24)
	currentOSLabel.Size = UDim2.new(1, 0, 0, 22)
	local osButtons = Instance.new("Frame", osCard)
	osButtons.Size = UDim2.new(1, 0, 0, 34)
	osButtons.Position = UDim2.fromOffset(0, 58)
	osButtons.BackgroundTransparency = 1
	local macButton = createButton(osButtons, "🍎 macOS", colors.BackgroundSecondary, colors.Text)
	macButton.Size = UDim2.new(0.31, 0, 1, 0)
	local linuxButton = createButton(osButtons, "🐧 Linux", colors.BackgroundSecondary, colors.Text)
	linuxButton.Size = UDim2.new(0.34, 0, 1, 0)
	linuxButton.Position = UDim2.new(0.33, 0, 0, 0)
	local winButton = createButton(osButtons, "💥 Windows", colors.BackgroundSecondary, colors.Text)
	winButton.Size = UDim2.new(0.31, 0, 1, 0)
	winButton.Position = UDim2.new(0.69, 0, 0, 0)

	local playTestWarning = createLabel(
		warningCard,
		"🎯 Play test tracking sends from the server when the play test ends.",
		14,
		colors.Warning,
		Enum.Font.SourceSansSemibold
	)
	local statusLabel = createLabel(statusContainer, "", 14, colors.Success, Enum.Font.SourceSansSemibold)
	statusLabel.Size = UDim2.new(1, -72, 1, 0)
	statusLabel.TextYAlignment = Enum.TextYAlignment.Center
	local resetButton = createButton(statusContainer, "Reset", colors.BackgroundSecondary, colors.Text)
	resetButton.Size = UDim2.fromOffset(62, 24)
	resetButton.Position = UDim2.new(1, -62, 0.5, -12)
	resetButton.TextSize = 11

	local normalCards = {
		headerCard,
		debugCard,
		statusCard,
		projectCard,
		actionsCard,
		apiKeyCard,
		osCard,
		warningCard,
		statusContainer,
	}
	local setupStep = "welcome"
	local setupReadyAt = 0

	local function setNormalVisible(visible)
		for _, card in normalCards do
			if card ~= warningCard then
				card.Visible = visible and (card ~= debugCard or DEBUG_CONTEXT_VISIBLE)
			end
		end
	end

	local function fitTextLabel(label, minHeight)
		task.defer(function()
			local height = math.max(minHeight or 0, label.TextBounds.Y + 6)
			label.Size = UDim2.new(1, 0, 0, height)
		end)
	end

	local apiKeyFocused = false
	local function hideApiKey()
		if not apiKeyFocused and Config.WakaTimeAPIKey and Config.WakaTimeAPIKey ~= "" then
			tokenInput.Text = "••••••••••••••••"
		end
	end
	tokenInput.Focused:Connect(function()
		apiKeyFocused = true
		if tokenInput.Text:match("^•+$") then
			tokenInput.Text = ""
		end
	end)
	tokenInput.FocusLost:Connect(function()
		apiKeyFocused = false
		hideApiKey()
	end)

	local function showDialog(dialogTitle, message)
		local dialogBackground = Instance.new("Frame")
		dialogBackground.Size = UDim2.fromScale(1, 1)
		dialogBackground.BackgroundColor3 = Color3.new(0, 0, 0)
		dialogBackground.BackgroundTransparency = 0.45
		dialogBackground.ZIndex = 100
		dialogBackground.Parent = mainFrame
		local dialog = createCard(dialogBackground, 14)
		dialog.ZIndex = 101
		dialog.Position = UDim2.fromScale(0.08, 0.12)
		dialog.Size = UDim2.fromScale(0.84, 0.72)
		local dialogTitleLabel = createLabel(dialog, dialogTitle, 20, colors.Text, Enum.Font.SourceSansBold)
		dialogTitleLabel.Size = UDim2.new(1, 0, 0, 30)
		dialogTitleLabel.ZIndex = 102
		local messageText = createLabel(dialog, message, 14, colors.Text)
		messageText.Size = UDim2.new(1, 0, 1, -78)
		messageText.Position = UDim2.fromOffset(0, 40)
		messageText.ZIndex = 102
		local closeButton = createButton(dialog, "Close", colors.Primary, Color3.fromRGB(255, 255, 255))
		closeButton.ZIndex = 102
		closeButton.Size = UDim2.new(0.36, 0, 0, 34)
		closeButton.Position = UDim2.new(0.32, 0, 1, -38)
		closeButton.MouseButton1Click:Connect(function()
			dialogBackground:Destroy()
		end)
	end

	local function setSetupStep(step, message, buttonText)
		setupStep = step
		setupTitle.Text = step == "done" and "Setup complete" or "Welcome to HackaTime for Roblox Studio"
		setupStepLabel.Text = message
		setupButton.Text = buttonText or "Continue"
		setupStatus.Text = ""
		setupInput.Parent.Visible = step == "api"
		setupOSButtons.Visible = step == "os"
		setupButton.Visible = step ~= "os"
		fitTextLabel(setupStepLabel, 80)
		fitTextLabel(setupStatus, 0)
	end

	local function refreshSetup()
		local setupComplete = Config.isSetupComplete and Config.isSetupComplete()
		setupCard.Visible = not setupComplete
		setNormalVisible(setupComplete)
		if not setupComplete and (setupStep == "permission" or setupStep == "auto-update") then
			local waitLeft = math.max(0, math.ceil(setupReadyAt - os.clock()))
			setupButton.Active = waitLeft == 0
			setupButton.AutoButtonColor = waitLeft == 0
			setupButton.Text = waitLeft > 0 and ("READ PLEASE - " .. waitLeft .. "s") or "Continue"
		end
	end

	setSetupStep(
		"welcome",
		"HackaTime tracks the time you spend working in Roblox Studio and sends that activity to hackatime.hackclub.com.\n\nIt detects coding, building, UI design, animation, modeling, playtesting, and configuration work.\n\nIt only counts a minute after enough real activity has happened, then sends the main kind of work from that minute.",
		"Continue"
	)

	setupButton.MouseButton1Click:Connect(function()
		if setupStep == "welcome" then
			setupReadyAt = os.clock() + 5
			setSetupStep(
				"permission",
				"Roblox will ask whether this plugin can contact hackatime.hackclub.com.\n\nThis permission is required. Without it, HackaTime cannot validate your API key or send heartbeats.\n\nAfter the timer, press Continue and accept the Roblox permission prompt.",
				"Continue"
			)
		elseif setupStep == "permission" then
			if os.clock() < setupReadyAt then
				return
			end
			setupStatus.Text = "PRESS ACCEPT in the Roblox permission prompt. Checking hackatime.hackclub.com..."
			setupStatus.TextColor3 = colors.Primary
			setupStatus.TextSize = 18
			fitTextLabel(setupStatus, 34)
			local ok, _, msg = API.checkDomainAccess()
			if ok then
				setupStatus.TextColor3 = colors.TextMuted
				setupStatus.TextSize = 13
				setSetupStep(
					"api",
					"Network access works.\n\nGet your API key from:\nhttps://hackatime.hackclub.com/api-key\n\nCopy it, paste it below, then validate it. This plugin sends exactly one test heartbeat to confirm the key works.",
					"Validate API Key"
				)
			else
				setupStatus.TextColor3 = colors.TextMuted
				setupStatus.TextSize = 13
				setSetupStep(
					"http-failed",
					"HackaTime could not be reached. Roblox may have denied HTTP permission.\n\nOpen the Studio top bar and enable it here:\nPlugins > Manage Plugins > HTTP Requests\n\nEnable HTTP requests for hackatime.hackclub.com. Then press retry.",
					"Retry permission check"
				)
				setupStatus.Text = msg
				fitTextLabel(setupStatus, 22)
			end
		elseif setupStep == "http-failed" then
			setupStatus.Text = "PRESS ACCEPT if Roblox asks again. Re-checking HackaTime access..."
			setupStatus.TextColor3 = colors.Primary
			setupStatus.TextSize = 18
			fitTextLabel(setupStatus, 22)
			local ok, _, msg = API.checkDomainAccess()
			if ok then
				setupStatus.TextColor3 = colors.TextMuted
				setupStatus.TextSize = 13
				setSetupStep(
					"api",
					"Network access works.\n\nGet your API key from:\nhttps://hackatime.hackclub.com/api-key\n\nCopy it, paste it below, then validate it. This plugin sends exactly one test heartbeat to confirm the key works.",
					"Validate API Key"
				)
			else
				setupStatus.TextColor3 = colors.TextMuted
				setupStatus.TextSize = 13
				setupStatus.Text = msg
				fitTextLabel(setupStatus, 22)
			end
		elseif setupStep == "api" then
			local token = processToken(setupInput.Text)
			setupInput.Text = token
			setupStatus.Text = "Sending one validation heartbeat..."
			fitTextLabel(setupStatus, 22)
			local ok, _, msg = API.validateAPIKey(token)
			if ok then
				Config.saveAPIKey(token)
				setSetupStep(
					"os",
					"API key works.\n\nChoose your operating system once so HackaTime receives the right OS label with future heartbeats.",
					"Choose an OS below"
				)
			else
				setupStatus.Text = msg
				fitTextLabel(setupStatus, 22)
			end
		elseif setupStep == "auto-update" then
			if os.clock() < setupReadyAt then
				return
			end
			setSetupStep(
				"done",
				"All set. HackaTime will now track real Roblox Studio activity.\n\nSaved OS: "
					.. formatOS(Config.OS_TYPE)
					.. "\n\nA minute counts only when there are at least 30 total seconds of work.\n\nThe biggest category from that minute is what gets sent.\n\nStatus will appear in the normal dashboard below.",
				"Start using HackaTime"
			)
		elseif setupStep == "done" then
			Config.setSetupComplete(true)
			setupCard.Visible = false
			setNormalVisible(true)
		end
	end)

	local function finishOS(osType)
		local saved = Config.setOSOverride(osType)
		currentOSLabel.Text = "Current OS: " .. formatOS(Config.OS_TYPE)
		setupReadyAt = os.clock() + 10
		setSetupStep(
			"auto-update",
			"If possible, please enable auto update for this plugin.\n\nIn the Roblox Studio top bar, go to:\nPlugins > Manage Plugins\n\nThen set the checkmark on auto update for HackaTime. This helps keep tracking reliable when fixes are released.",
			"Continue"
		)
		if not saved then
			setupStatus.Text =
				"OS selected for this session. Studio could not persist the setting, so you may need to choose it again after restarting Studio."
			fitTextLabel(setupStatus, 34)
		end
	end

	saveButton.MouseButton1Click:Connect(function()
		local token = processToken(tokenInput.Text)
		if token:match("^•+$") then
			token = Config.WakaTimeAPIKey
		end
		tokenInput.Text = token
		local ok, _, msg = API.validateAPIKey(token)
		if ok and Config.saveAPIKey(token) then
			Config.setSetupComplete(true)
			hideApiKey()
			Main.forceSend()
		else
			Main.LastStatusMessage = msg
		end
	end)
	getApiKeyButton.MouseButton1Click:Connect(function()
		showDialog(
			"Get API Key",
			"Open this page and copy your API key:\n\nhttps://hackatime.hackclub.com/api-key\n\nPaste it into this plugin. Keep it secret."
		)
	end)
	forceSendButton.MouseButton1Click:Connect(function()
		Main.forceSend()
	end)
	clearQueueButton.MouseButton1Click:Connect(function()
		Main.clearQueue()
	end)
	helpButton.MouseButton1Click:Connect(function()
		showDialog(
			"❓ Help and Support",
			"Need help with HackaTime Roblox? Open Hack Club Slack and ask in #roblox-hackatime or #hackatime-v2.\n\n💬 Slack: hackclub.com/slack"
		)
	end)
	setupMacButton.MouseButton1Click:Connect(function()
		finishOS("darwin")
	end)
	setupLinuxButton.MouseButton1Click:Connect(function()
		finishOS("Linux")
	end)
	setupWinButton.MouseButton1Click:Connect(function()
		finishOS("Windows")
	end)
	macButton.MouseButton1Click:Connect(function()
		if setupStep == "os" then
			finishOS("darwin")
		else
			Config.setOSOverride("darwin")
		end
	end)
	linuxButton.MouseButton1Click:Connect(function()
		if setupStep == "os" then
			finishOS("Linux")
		else
			Config.setOSOverride("Linux")
		end
	end)
	winButton.MouseButton1Click:Connect(function()
		if setupStep == "os" then
			finishOS("Windows")
		else
			Config.setOSOverride("Windows")
		end
	end)
	setProjectButton.MouseButton1Click:Connect(function()
		Main.setProject(projectInput.Text)
		projectInput.Text = ""
	end)
	resetButton.MouseButton1Click:Connect(function()
		Config.saveAPIKey("")
		Config.setSetupComplete(false)
		Main.clearQueue()
		setupStep = "welcome"
		setupReadyAt = 0
		setSetupStep(
			"welcome",
			"HackaTime tracks the time you spend working in Roblox Studio and sends that activity to hackatime.hackclub.com.\n\nIt detects coding, building, UI design, animation, modeling, playtesting, and configuration work.\n\nIt only counts a minute after enough real activity has happened, then sends the main kind of work from that minute.",
			"Continue"
		)
		setupCard.Visible = true
		setNormalVisible(false)
		scrollFrame.CanvasPosition = Vector2.new(0, 0)
	end)

	local function updateStatus()
		if not pluginGui.Enabled then
			return
		end
		refreshSetup()

		local queueSize = Main.getQueueSize and Main.getQueueSize() or 0
		queueLabel.Text = "📊 Queue: " .. queueSize .. (queueSize == 1 and " item" or " items")
		local currentCategory = AI.CurrentActivityCategory
		local icon = CategoryIcons[currentCategory] or "🔄"
		categoryLabel.Text = icon .. " " .. friendlyCategory(currentCategory)

		local activityTime = Heartbeat.getCountableActivityTime
				and Heartbeat.getCountableActivityTime(AI.ActivityCategories)
			or 0
		local secondsUntilHeartbeat = Heartbeat.getSecondsUntilNextHeartbeat()
		local dominantActivity = Heartbeat.getDominantActivity and Heartbeat.getDominantActivity(AI.ActivityCategories)
			or currentCategory
		local hasEnoughActivity = activityTime >= 30
		local heartbeatReady = hasEnoughActivity and dominantActivity ~= nil
		local dominantLabel = dominantActivity
				and ((CategoryIcons[dominantActivity] or "🔄") .. " " .. friendlyCategory(dominantActivity))
			or "Keep working"
		if heartbeatReady then
			minuteActivityLabel.Text = "✅ You are good. Heartbeat will be sent as "
				.. dominantLabel
				.. " in about "
				.. secondsUntilHeartbeat
				.. "s."
		elseif activityTime > 0 then
			minuteActivityLabel.Text = "⏱️ "
				.. math.floor(activityTime)
				.. "s tracked. Need "
				.. math.ceil(30 - activityTime)
				.. "s more before this minute counts."
		else
			minuteActivityLabel.Text = "Start working in Studio and this minute will begin tracking."
		end
		minuteActivityLabel.TextColor3 = hasEnoughActivity and colors.Success
			or (activityTime > 0 and colors.Warning or colors.TextMuted)

		projectLabel.Text = "🏗️ Project: " .. Config.CurrentProject
		currentOSLabel.Text = "Current OS: " .. formatOS(Config.OS_TYPE)

		if DEBUG_CONTEXT_VISIBLE then
			local lineInfo = Heartbeat.getLineInfo and Heartbeat.getLineInfo()
			if lineInfo then
				debugFileLabel.Text = "📄 File: " .. tostring(lineInfo.entity or "No script detected yet")
				local lineText = lineInfo.cursor_line and tostring(lineInfo.cursor_line) or "not available"
				local columnText = lineInfo.cursor_column and tostring(lineInfo.cursor_column) or "not available"
				local totalText = lineInfo.total_lines and tostring(lineInfo.total_lines) or "not available"
				debugLineLabel.Text = "📍 Line: "
					.. lineText
					.. "  •  Column: "
					.. columnText
					.. "  •  Total lines: "
					.. totalText
				local viewport = "not available"
				if lineInfo.viewport_start and lineInfo.viewport_end then
					viewport = tostring(lineInfo.viewport_start) .. "-" .. tostring(lineInfo.viewport_end)
				end
				local age = lineInfo.updated_at and tostring(math.max(0, os.time() - lineInfo.updated_at)) .. "s ago"
					or "not available"
				local sourceLength = lineInfo.source_length and tostring(lineInfo.source_length) or "not available"
				local sourceKey = lineInfo.source_key and tostring(lineInfo.source_key) or "not available"
				debugExtraLabel.Text = "Source: "
					.. tostring(lineInfo.source or "unknown")
					.. " • Key: "
					.. sourceKey
					.. " • Viewport: "
					.. viewport
					.. " • Source length: "
					.. sourceLength
					.. " • Last update: "
					.. age
			else
				debugFileLabel.Text = "📄 File: No script detected yet"
				debugLineLabel.Text = "📍 Line: Open or edit a script to see ScriptDocument context"
				debugExtraLabel.Text = "Source: none • Viewport: none • Source length: none • Last update: none"
			end

			local lastPayload = Heartbeat.getLastHeartbeatPayload and Heartbeat.getLastHeartbeatPayload()
			if lastPayload then
				local encoded = HttpService:JSONEncode(lastPayload)
				if #encoded > 360 then
					encoded = encoded:sub(1, 360) .. "..."
				end
				debugHeartbeatLabel.Text = "Last heartbeat: " .. encoded
			else
				debugHeartbeatLabel.Text = "Last heartbeat: none yet"
			end
		end

		local statusText, statusIcon, statusColor
		if not Config.WakaTimeAPIKey or Config.WakaTimeAPIKey == "" then
			statusText, statusIcon, statusColor = "API key needed", StatusIcons.Warning, colors.Warning
		elseif Main.IsOffline then
			statusText, statusIcon, statusColor =
				"Needs attention"
					.. (Main.LastErrorCode and " - " .. Main.LastErrorCode or "")
					.. (Main.LastStatusMessage ~= "" and ": " .. Main.LastStatusMessage or ""),
				StatusIcons.Offline,
				colors.Error
		elseif not Main.HasSuccessfullyConnected then
			statusText, statusIcon, statusColor = "Ready", StatusIcons.Connected, colors.Success
		else
			statusText, statusIcon, statusColor = "Ready", StatusIcons.Connected, colors.Success
		end
		statusLabel.Text = statusIcon .. "  " .. statusText
		statusLabel.TextColor3 = statusColor

		warningCard.Visible = (Playtest.isPlayTesting() and game:GetService("RunService"):IsClient())
		local warningHeight = 0
		playTestWarning.Visible = Playtest.isPlayTesting() and game:GetService("RunService"):IsClient()
		if playTestWarning.Visible then
			playTestWarning.Size = UDim2.new(1, 0, 0, 36)
			playTestWarning.Position = UDim2.fromOffset(0, warningHeight)
			warningHeight = warningHeight + 42
		end
		if warningHeight > 0 then
			warningCard.Size = UDim2.new(1, 0, 0, warningHeight)
		else
			warningCard.Visible = false
		end
	end

	refreshSetup()
	return pluginGui, updateStatus
end

function GUI.init(p, main, config, ai, api, heartbeat, playtest)
	plugin = p
	Main = main
	Config = config
	AI = ai
	API = api
	Heartbeat = heartbeat
	Playtest = playtest
end

return GUI
