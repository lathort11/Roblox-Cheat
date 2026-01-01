--[[

VAYS ENGINE v6.5 (Split Targeting Modes)

CHANGELOG v6.5:
✓ Separated Targeting Logic for Aimbot and Aimlock
✓ Added "Aimlock Target Mode" (Central / Cursor)
✓ Renamed Aimlock Activation dropdown to "Trigger Mode" for clarity
✓ Fixed FOV rings to follow their specific modes independently

]]

-- СЕРВИСЫ

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")

local MenuBlur = Instance.new("BlurEffect")
MenuBlur.Size = 0
MenuBlur.Enabled = false
MenuBlur.Parent = Lighting

-- ПРОВЕРКА ОКРУЖЕНИЯ

local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ЗАЩИТА ОТ ПОВТОРНОГО ЗАПУСКА

if _G.CheatLoaded then
	warn("Скрипт уже запущен! Нажмите Unload для перезагрузки.")
	return
end

_G.CheatLoaded = true

-- ХРАНИЛИЩЕ

local CheatEnv = {
	Connections = {},
	Drawings = {},
	UI = {},
	Toggles = {},
	Dropdowns = {},
	UIConnections = {} 
}

-- ПЕРЕМЕННЫЕ

local LastImpulseTime = 0
local HasShotOnce = false
local TooltipLabel = nil
local AimlockEngaged = false
local AimlockEngagedFromGUI = false 

-- ЦВЕТОВАЯ ПАЛИТРА

local Theme = {
	Background = Color3.fromRGB(20, 20, 20),
	Element = Color3.fromRGB(35, 35, 35),
	Accent = Color3.fromRGB(0, 180, 255),
	Text = Color3.fromRGB(240, 240, 240),
	TextDark = Color3.fromRGB(150, 150, 150),
	Glow = Color3.fromRGB(0, 190, 255),
	Stroke = Color3.fromRGB(0, 180, 255),
	Green = Color3.fromRGB(0, 255, 100),
	Disabled = Color3.fromRGB(60, 60, 60)
}

-- НАСТРОЙКИ

local Settings = {
	ESP = false,
	ESP_Names = false,
	NR_Mode = "Classic",
	MovementMode = "Constant",
	ImpulseInterval = 500,
	Aimbot = false,
	NoRecoil = false,
	RecoilStrength = 15,
	AimbotFOV = 100,
	AimbotSmooth = 0.2,
    AimbotMode = "Central", -- Режим для Aimbot
	WallCheck = true,
	ShowFOV = true,
	BoxColor = Color3.fromRGB(255, 50, 50),
	NameColor = Color3.fromRGB(255, 255, 255),
	FOVColor = Color3.fromRGB(255, 255, 255),
	MenuKey = Enum.KeyCode.RightAlt,

	Aimlock = false,
	AimlockSmooth = 0.5,
	AimlockFOV = 90,
	AimlockPart = "Head",
	AimlockMode = "N Toggle", -- Это режим активации (триггер)
    AimlockTargetMode = "Central", -- [NEW] Режим наведения для Aimlock (Central/Cursor)
	Prediction = 0.135, -- [NEW] Стандартное значение для большинства пуль
    Deadzone = 3,       -- [NEW] Радиус в пикселях, где доводка отключается (анти-тряска)
    KnockedCheck = true,-- [NEW] Проверка на нокнутых

	TC_Hide = false,
	TC_NoAim = true,
	TC_Green = false
}

-- БИНДЫ

local Keybinds = {
	{Name = "ESP", Key = Enum.KeyCode.Y, Setting = "ESP"},
	{Name = "Aimlock", Key = Enum.KeyCode.N, Setting = "Aimlock"},
	{Name = "Aimbot", Key = Enum.KeyCode.T, Setting = "Aimbot"},
	{Name = "No Recoil", Key = Enum.KeyCode.G, Setting = "NoRecoil"},
	{Name = "Wall Check", Key = Enum.KeyCode.B, Setting = "WallCheck"},
	{Name = "Unload", Key = Enum.KeyCode.Delete, Setting = "Unload"}
}

--// ФУНКЦИЯ ЗАГРУЗКИ ЛОГОТИПА //--

local function SetupLogoImage()
	if not makefolder or not writefile or not isfile or not getcustomasset then return nil end
	local folderPath = "VAYS"
	local subFolderPath = folderPath .. "/logo"
	local filePath = subFolderPath .. "/Vays.png"
	local url = "https://raw.githubusercontent.com/lathort11/Roblox-Cheat/main/Vays.png"
	if not isfolder(folderPath) then makefolder(folderPath) end
	if not isfolder(subFolderPath) then makefolder(subFolderPath) end
	if not isfile(filePath) then
		local success, content = pcall(function() return game:HttpGet(url) end)
		if success then writefile(filePath, content) else return nil end
	end
	local success, assetId = pcall(function() return getcustomasset(filePath) end)
	return success and assetId or nil
end

local LogoAssetId = SetupLogoImage()

--// DRAWING LIB CHECK //--

local Drawing = Drawing or {new = function() return {Visible = false, Remove = function() end} end}

local FOVRing = Drawing.new("Circle")
FOVRing.Visible = false
FOVRing.Thickness = 1.5
FOVRing.Color = Theme.Accent
FOVRing.Filled = false
FOVRing.Radius = Settings.AimbotFOV
FOVRing.NumSides = 64
table.insert(CheatEnv.Drawings, FOVRing)

local AimlockRing = Drawing.new("Circle")
AimlockRing.Visible = false
AimlockRing.Thickness = 2
AimlockRing.Color = Color3.fromRGB(255, 0, 0)
AimlockRing.Filled = false
AimlockRing.NumSides = 64
table.insert(CheatEnv.Drawings, AimlockRing)

--// GUI ENGINE //--

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VAYSUI_v6.5"
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if gethui then ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then syn.protect_gui(ScreenGui) ScreenGui.Parent = CoreGui
else ScreenGui.Parent = CoreGui end
table.insert(CheatEnv.UI, ScreenGui)

-- TOOLTIP SYSTEM

local TooltipFrame = Instance.new("Frame")
TooltipFrame.Size = UDim2.new(0, 200, 0, 25)
TooltipFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
TooltipFrame.BorderSizePixel = 0
TooltipFrame.Visible = false
TooltipFrame.ZIndex = 100
TooltipFrame.Parent = ScreenGui

local TT_Stroke = Instance.new("UIStroke", TooltipFrame)
TT_Stroke.Color = Theme.Accent
TT_Stroke.Thickness = 1

local TT_Text = Instance.new("TextLabel")
TT_Text.Size = UDim2.new(1, -10, 1, 0)
TT_Text.Position = UDim2.new(0, 5, 0, 0)
TT_Text.BackgroundTransparency = 1
TT_Text.TextColor3 = Color3.fromRGB(255, 255, 255)
TT_Text.TextSize = 12
TT_Text.Font = Enum.Font.Gotham
TT_Text.Parent = TooltipFrame

local function AddTooltip(element, text)
	if not element then return end
	local conn1 = element.MouseEnter:Connect(function()
		TT_Text.Text = text
		local txtSize = game:GetService("TextService"):GetTextSize(text, 12, Enum.Font.Gotham, Vector2.new(500, 100))
		TooltipFrame.Size = UDim2.new(0, txtSize.X + 20, 0, txtSize.Y + 10)
		TooltipFrame.Visible = true
	end)
	local conn2 = element.MouseLeave:Connect(function()
		TooltipFrame.Visible = false
	end)
	local conn3 = element.MouseMoved:Connect(function(x, y)
		TooltipFrame.Position = UDim2.new(0, x + 15, 0, y + 15)
	end)
	table.insert(CheatEnv.UIConnections, conn1)
	table.insert(CheatEnv.UIConnections, conn2)
	table.insert(CheatEnv.UIConnections, conn3)
end

-- 1. WATERMARK

local Watermark = Instance.new("Frame")
Watermark.Name = "Watermark"
Watermark.Size = UDim2.new(0, 180, 0, 24)
Watermark.Position = UDim2.new(0.01, 0, 0.01, 0)
Watermark.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
Watermark.BackgroundTransparency = 0.2
Watermark.BorderSizePixel = 0
Watermark.Parent = ScreenGui

local WM_Corner = Instance.new("UICorner", Watermark)
WM_Corner.CornerRadius = UDim.new(0, 4)

local WM_Stroke = Instance.new("UIStroke", Watermark)
WM_Stroke.Color = Theme.Stroke
WM_Stroke.Thickness = 1
WM_Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local AccentLine = Instance.new("Frame")
AccentLine.Size = UDim2.new(1, 0, 0, 1.5)
AccentLine.Position = UDim2.new(0, 0, 0, 0)
AccentLine.BorderSizePixel = 0
AccentLine.Parent = Watermark

local AL_Gradient = Instance.new("UIGradient", AccentLine)
AL_Gradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Theme.Accent),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(1, Theme.Accent)
})

local WM_Text = Instance.new("TextLabel")
WM_Text.Size = UDim2.new(1, -10, 1, 0)
WM_Text.Position = UDim2.new(0, 8, 0, 0)
WM_Text.BackgroundTransparency = 1
WM_Text.Text = "VAYS | FPS: 0 | MS: 0"
WM_Text.TextColor3 = Color3.fromRGB(255, 255, 255)
WM_Text.Font = Enum.Font.Code
WM_Text.TextSize = 11
WM_Text.TextXAlignment = Enum.TextXAlignment.Left
WM_Text.Parent = Watermark

local function UpdateWM()
	local lastTime = tick()
	local frameCount = 0
	local fps = 0
	table.insert(CheatEnv.Connections, RunService.RenderStepped:Connect(function()
		frameCount = frameCount + 1
		if tick() - lastTime >= 1 then
			fps = frameCount
			frameCount = 0
			lastTime = tick()
			local ping = math.floor(LocalPlayer:GetNetworkPing() * 1000)
			WM_Text.Text = string.format("VAYS | FPS: %d | MS: %d", fps, ping)
		end
	end))
end

UpdateWM()

task.spawn(function()
	while _G.CheatLoaded do
		TweenService:Create(AL_Gradient, TweenInfo.new(2, Enum.EasingStyle.Linear), {Offset = Vector2.new(1, 0)}):Play()
		task.wait(2)
		if not _G.CheatLoaded then break end
		AL_Gradient.Offset = Vector2.new(-1, 0)
	end
end)

-- 2. KEYBIND LIST PANEL

local KeybindFrame = Instance.new("Frame")
KeybindFrame.Name = "KeybindFrame"
KeybindFrame.Size = UDim2.new(0, 180, 0, 0)
KeybindFrame.Position = UDim2.new(0.01, 0, 0.4, 0)
KeybindFrame.BackgroundColor3 = Theme.Background
KeybindFrame.BackgroundTransparency = 0.1
KeybindFrame.BorderSizePixel = 0
KeybindFrame.ClipsDescendants = true
KeybindFrame.Parent = ScreenGui

local KB_Corner = Instance.new("UICorner", KeybindFrame)
KB_Corner.CornerRadius = UDim.new(0, 4)

local KB_Stroke = Instance.new("UIStroke", KeybindFrame)
KB_Stroke.Color = Theme.Stroke
KB_Stroke.Thickness = 1
KB_Stroke.Transparency = 0.2

local KB_List = Instance.new("UIListLayout", KeybindFrame)
KB_List.SortOrder = Enum.SortOrder.LayoutOrder
KB_List.Padding = UDim.new(0, 2)
KB_List.HorizontalAlignment = Enum.HorizontalAlignment.Center

local KB_Padding = Instance.new("UIPadding", KeybindFrame)
KB_Padding.PaddingTop = UDim.new(0, 6)
KB_Padding.PaddingBottom = UDim.new(0, 6)
KB_Padding.PaddingLeft = UDim.new(0, 10)
KB_Padding.PaddingRight = UDim.new(0, 10)

-- 3. MAIN MENU

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 500, 0, 380)
MainFrame.Position = UDim2.new(0.5, -250, 0.5, -190)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BackgroundTransparency = 0.05
MainFrame.BorderSizePixel = 0
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner", MainFrame)
MainCorner.CornerRadius = UDim.new(0, 8)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Color = Color3.fromRGB(60, 60, 60)
MainStroke.Thickness = 1

local SideBar = Instance.new("Frame")
SideBar.Size = UDim2.new(0, 120, 1, 0)
SideBar.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
SideBar.BackgroundTransparency = 0.5
SideBar.BorderSizePixel = 0
SideBar.Parent = MainFrame

local SB_Corner = Instance.new("UICorner", SideBar)
SB_Corner.CornerRadius = UDim.new(0, 8)

local TabList = Instance.new("UIListLayout", SideBar)
TabList.Padding = UDim.new(0, 5)
TabList.HorizontalAlignment = Enum.HorizontalAlignment.Center

local TabPadding = Instance.new("UIPadding", SideBar)
TabPadding.PaddingTop = UDim.new(0, 10)

local Logo
if LogoAssetId then
	Logo = Instance.new("ImageLabel")
	Logo.Name = "LogoImage"
	Logo.Size = UDim2.new(0.8, 0, 0, 40)
	Logo.BackgroundTransparency = 1
	Logo.Image = LogoAssetId
	Logo.ScaleType = Enum.ScaleType.Fit
	Logo.Parent = SideBar
else
	Logo = Instance.new("TextLabel")
	Logo.Name = "LogoText"
	Logo.Size = UDim2.new(1, 0, 0, 40)
	Logo.Text = "VAYS"
	Logo.TextColor3 = Theme.Accent
	Logo.Font = Enum.Font.GothamBold
	Logo.TextSize = 18
	Logo.BackgroundTransparency = 1
	Logo.Parent = SideBar
end

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -130, 1, -20)
ContentArea.Position = UDim2.new(0, 130, 0, 10)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainFrame

local Tabs = {}

local function CreateTabContainer(name, autoScroll)
	local Container = Instance.new("ScrollingFrame")
	Container.Size = UDim2.new(1, 0, 1, 0)
	Container.BackgroundTransparency = 1
	Container.ScrollBarThickness = autoScroll and 2 or 0
	Container.Visible = false
	Container.ScrollBarImageColor3 = Theme.Accent
	Container.BorderSizePixel = 0
	Container.Parent = ContentArea
	Container.VerticalScrollBarInset = Enum.ScrollBarInset.None

	local Layout = Instance.new("UIListLayout", Container)
	Layout.Padding = UDim.new(0, 8)
	Layout.SortOrder = Enum.SortOrder.LayoutOrder

	if autoScroll then
		Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
			Container.CanvasSize = UDim2.new(0, 0, 0, Layout.AbsoluteContentSize.Y + 20)
		end)
	else
		Container.CanvasSize = UDim2.new(0, 0, 0, 0)
		Container.ScrollingEnabled = false
	end

	Tabs[name] = Container
	return Container
end

local function CreateTabButton(name)
	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(0.9, 0, 0, 30)
	Button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	Button.Text = name
	Button.TextColor3 = Theme.Text
	Button.Font = Enum.Font.GothamBold
	Button.TextSize = 14
	Button.Parent = SideBar

	local Corner = Instance.new("UICorner", Button)
	Corner.CornerRadius = UDim.new(0, 4)

	local conn = Button.MouseButton1Click:Connect(function()
		for tabName, container in pairs(Tabs) do
			container.Visible = (tabName == name)
		end
	end)
	table.insert(CheatEnv.UIConnections, conn)

	return Button
end

local CombatTab = CreateTabContainer("Combat", true)
local VisualsTab = CreateTabContainer("Visuals", false)
local MiscTab = CreateTabContainer("Misc", false)
local SystemTab = CreateTabContainer("System", false)

CreateTabButton("Combat")
CreateTabButton("Visuals")
CreateTabButton("Misc")
CreateTabButton("System")

local function GetCurrentParent(tabName) return Tabs[tabName] end

local function SetFrameState(frame, enabled)
	if not frame then return end
	local alpha = enabled and 0 or 0.6
	local bgColor = enabled and Theme.Element or Theme.Disabled

	local function apply(inst)
		if inst:IsA("TextButton") or inst:IsA("TextBox") then
			inst.Active = enabled
		end
		if inst:IsA("TextLabel") then
			TweenService:Create(inst, TweenInfo.new(0.2), {TextTransparency = alpha}):Play()
		end
	end

	for _, v in pairs(frame:GetDescendants()) do apply(v) end
	TweenService:Create(frame, TweenInfo.new(0.2), {BackgroundColor3 = bgColor}):Play()
end

--// UI HELPER FUNCTIONS //--

local function UpdateKeybindList()
	if not KeybindFrame or not KeybindFrame.Parent then return end

	for _, child in pairs(KeybindFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then 
			child:Destroy()
		end
	end
	local Header = Instance.new("TextLabel")
	Header.Name = "Header"
	Header.Size = UDim2.new(1, 0, 0, 24)
	Header.BackgroundTransparency = 1
	Header.Text = "KEYBINDS"
	Header.TextColor3 = Color3.fromRGB(255, 255, 255)
	Header.Font = Enum.Font.GothamBold
	Header.TextSize = 14
	Header.Parent = KeybindFrame

	local Separator = Instance.new("Frame", KeybindFrame)
	Separator.Name = "Separator"
	Separator.Size = UDim2.new(1, 0, 0, 1)
	Separator.BackgroundColor3 = Theme.Stroke
	Separator.BackgroundTransparency = 0.5
	Separator.BorderSizePixel = 0

	local activeCount = 0

	for _, bind in ipairs(Keybinds) do
		local isShown = false

		if bind.Setting == "Aimlock" then
			isShown = AimlockEngaged
		elseif bind.Setting ~= "Unload" and Settings[bind.Setting] then
			isShown = true
		end

		if isShown then
			activeCount = activeCount + 1
			local Line = Instance.new("Frame", KeybindFrame)
			Line.Size = UDim2.new(1, 0, 0, 22)
			Line.BackgroundTransparency = 1

			local NameLbl = Instance.new("TextLabel", Line)
			NameLbl.Size = UDim2.new(1, 0, 1, 0)
			NameLbl.BackgroundTransparency = 1
			NameLbl.Text = string.format("%s -- [%s]", bind.Name:upper(), bind.Key.Name)
			NameLbl.TextColor3 = Color3.fromRGB(230, 230, 230)
			NameLbl.Font = Enum.Font.GothamMedium
			NameLbl.TextSize = 13
			NameLbl.TextXAlignment = Enum.TextXAlignment.Center
		end
	end

	local targetHeight = (activeCount > 0) and (activeCount * 22 + 40) or 0
	TweenService:Create(KeybindFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0, 200, 0, targetHeight)}):Play()
	TweenService:Create(KeybindFrame, TweenInfo.new(0.2), {BackgroundTransparency = (activeCount == 0) and 1 or 0.1}):Play()

	if KB_Stroke then
		TweenService:Create(KB_Stroke, TweenInfo.new(0.2), {Transparency = (activeCount == 0) and 1 or 0.2}):Play()
	end
end

local function SyncButton(settingKey)
	if CheatEnv.Toggles[settingKey] then
		local isActive = Settings[settingKey]
		local color = isActive and Theme.Accent or Color3.fromRGB(60,60,60)
		TweenService:Create(CheatEnv.Toggles[settingKey], TweenInfo.new(0.2), {BackgroundColor3 = color}):Play()
	end
end

local function UpdateTeamCheckDependencies()
	if Settings.TC_Hide then
		Settings.TC_Green = false
		if CheatEnv.Toggles["TC_Green"] then
			TweenService:Create(CheatEnv.Toggles["TC_Green"], TweenInfo.new(0.2), {BackgroundColor3 = Color3.fromRGB(60,60,60)}):Play()
			local frame = CheatEnv.Toggles["TC_Green"]:FindFirstAncestorOfClass("Frame")
			if frame then SetFrameState(frame, false) end
		end
	else
		if CheatEnv.Toggles["TC_Green"] then
			local frame = CheatEnv.Toggles["TC_Green"]:FindFirstAncestorOfClass("Frame")
			if frame then SetFrameState(frame, true) end
		end
	end
end

local function CreateSection(text, parent)
	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, 0, 0, 25)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.TextColor3 = Theme.Accent
	Label.Font = Enum.Font.GothamBold
	Label.TextSize = 14
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = parent
end

local function CreateToggle(text, settingKey, bindInfo, parent, customCallback)
	local Frame = Instance.new("Frame")
	Frame.Parent = parent
	Frame.Size = UDim2.new(1, 0, 0, 35)
	Frame.BackgroundColor3 = Theme.Element

	local Corner = Instance.new("UICorner", Frame)
	Corner.CornerRadius = UDim.new(0, 6)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(0.7, 0, 1, 0)
	Label.Position = UDim2.new(0, 10, 0, 0)
	Label.BackgroundTransparency = 1
	local suffix = bindInfo and (" ["..bindInfo.Name.."]") or ""
	Label.Text = text .. suffix
	Label.TextColor3 = Theme.Text
	Label.Font = Enum.Font.GothamMedium
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.TextSize = 14
	Label.Parent = Frame

	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(0, 40, 0, 20)
	Button.Position = UDim2.new(1, -50, 0.5, -10)
	Button.BackgroundColor3 = Settings[settingKey] and Theme.Accent or Color3.fromRGB(60,60,60)
	Button.Text = ""
	Button.Parent = Frame

	local BtnCorner = Instance.new("UICorner", Button)
	BtnCorner.CornerRadius = UDim.new(0, 4)

	CheatEnv.Toggles[settingKey] = Button

	local conn = Button.MouseButton1Click:Connect(function()
		if Button.Active == false then return end

		Settings[settingKey] = not Settings[settingKey]
		SyncButton(settingKey)

		if settingKey == "Aimlock" then
			if Settings[settingKey] then
				AimlockEngagedFromGUI = true
				if Settings.AimlockMode == "N Toggle" then
					AimlockEngaged = not AimlockEngaged
				elseif Settings.AimlockMode == "N Hold" then
					AimlockEngaged = true
				end
			else
				AimlockEngaged = false
				AimlockEngagedFromGUI = false
			end
		end

		if settingKey == "TC_Hide" then
			UpdateTeamCheckDependencies()
		end

		UpdateKeybindList()

		if customCallback then customCallback(Settings[settingKey]) end
	end)
	table.insert(CheatEnv.UIConnections, conn)

	return Frame
end

local function CreateDropdown(text, settingKey, options, parent, customCallback)
	local Frame = Instance.new("Frame")
	Frame.Size = UDim2.new(1, 0, 0, 50)
	Frame.BackgroundColor3 = Theme.Element
	Frame.ZIndex = 5
	Frame.Parent = parent

	local Corner = Instance.new("UICorner", Frame)
	Corner.CornerRadius = UDim.new(0, 6)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(0.5, 0, 0, 35)
	Label.Position = UDim2.new(0, 10, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.TextColor3 = Theme.Text
	Label.Font = Enum.Font.GothamMedium
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.TextSize = 14
	Label.Parent = Frame
	Label.ZIndex = 6

	local MainBtn = Instance.new("TextButton")
	MainBtn.Size = UDim2.new(0.4, 0, 0, 25)
	MainBtn.Position = UDim2.new(0.55, 0, 0, 5)
	MainBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	MainBtn.Text = Settings[settingKey] .. " ▼"
	MainBtn.TextColor3 = Theme.Accent
	MainBtn.Font = Enum.Font.GothamBold
	MainBtn.TextSize = 12
	MainBtn.Parent = Frame
	MainBtn.ZIndex = 6

	local M_Corner = Instance.new("UICorner", MainBtn)
	M_Corner.CornerRadius = UDim.new(0, 4)

	local DropList = Instance.new("ScrollingFrame")
	DropList.Size = UDim2.new(0.4, 0, 0, 0)
	DropList.Position = UDim2.new(0.55, 0, 0, 32)
	DropList.BackgroundColor3 = Color3.fromRGB(30,30,30)
	DropList.BorderSizePixel = 0
	DropList.ScrollBarThickness = 2
	DropList.Visible = false
	DropList.Parent = Frame
	DropList.ZIndex = 10

	local D_ListLayout = Instance.new("UIListLayout", DropList)
	D_ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local isOpen = false

	local conn1 = MainBtn.MouseButton1Click:Connect(function()
		if MainBtn.Active == false then return end
		isOpen = not isOpen
		DropList.Visible = isOpen

		if isOpen then
			local count = #options
			local h = math.min(count * 25, 100)
			DropList.Size = UDim2.new(0.4, 0, 0, h)
			TweenService:Create(Frame, TweenInfo.new(0.2), {Size = UDim2.new(1, 0, 0, 35 + h + 5)}):Play()
		else
			DropList.Size = UDim2.new(0.4, 0, 0, 0)
			TweenService:Create(Frame, TweenInfo.new(0.2), {Size = UDim2.new(1, 0, 0, 35)}):Play()
		end
	end)
	table.insert(CheatEnv.UIConnections, conn1)

	for _, opt in ipairs(options) do
		local OptBtn = Instance.new("TextButton")
		OptBtn.Size = UDim2.new(1, 0, 0, 25)
		OptBtn.BackgroundColor3 = Color3.fromRGB(30,30,30)
		OptBtn.Text = opt
		OptBtn.TextColor3 = Theme.TextDark
		OptBtn.Font = Enum.Font.Gotham
		OptBtn.TextSize = 12
		OptBtn.Parent = DropList
		OptBtn.ZIndex = 11

		local conn2 = OptBtn.MouseButton1Click:Connect(function()
			Settings[settingKey] = opt
			MainBtn.Text = opt .. " ▼"
			isOpen = false
			DropList.Visible = false
			TweenService:Create(Frame, TweenInfo.new(0.2), {Size = UDim2.new(1, 0, 0, 35)}):Play()
			
			if settingKey == "AimlockMode" then
				if not AimlockEngagedFromGUI and AimlockEngaged then
					AimlockEngaged = false
				end
			end
			
			if customCallback then customCallback(opt) end
		end)
		table.insert(CheatEnv.UIConnections, conn2)
	end

	return Frame
end

local function CreateSlider(text, settingKey, min, max, isFloat, parent)
	local Frame = Instance.new("Frame")
	Frame.Parent = parent
	Frame.Size = UDim2.new(1, 0, 0, 50)
	Frame.BackgroundColor3 = Theme.Element

	local Corner = Instance.new("UICorner", Frame)
	Corner.CornerRadius = UDim.new(0, 6)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -20, 0, 20)
	Label.Position = UDim2.new(0, 10, 0, 5)
	Label.BackgroundTransparency = 1
	Label.Text = text .. ": " .. tostring(Settings[settingKey])
	Label.TextColor3 = Theme.Text
	Label.Font = Enum.Font.GothamMedium
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.TextSize = 14
	Label.Parent = Frame

	local SliderBG = Instance.new("Frame")
	SliderBG.Size = UDim2.new(1, -20, 0, 6)
	SliderBG.Position = UDim2.new(0, 10, 0, 30)
	SliderBG.BackgroundColor3 = Color3.fromRGB(20,20,20)
	SliderBG.Parent = Frame

	local S_Corner = Instance.new("UICorner", SliderBG)
	S_Corner.CornerRadius = UDim.new(1, 0)

	local SliderFill = Instance.new("Frame")
	local startPercent = (Settings[settingKey] - min) / (max - min)
	SliderFill.Size = UDim2.new(math.clamp(startPercent, 0, 1), 0, 1, 0)
	SliderFill.BackgroundColor3 = Theme.Accent
	SliderFill.BorderSizePixel = 0
	SliderFill.Parent = SliderBG

	local F_Corner = Instance.new("UICorner", SliderFill)
	F_Corner.CornerRadius = UDim.new(1, 0)

	local Trigger = Instance.new("TextButton")
	Trigger.Size = UDim2.new(1, 0, 1, 0)
	Trigger.BackgroundTransparency = 1
	Trigger.Text = ""
	Trigger.Parent = SliderBG

	local dragging = false

	Trigger.InputBegan:Connect(function(input)
		if Trigger.Active == false then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
	end)

	table.insert(CheatEnv.Connections, UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local pos = UDim2.new(math.clamp((input.Position.X - SliderBG.AbsolutePosition.X) / SliderBG.AbsoluteSize.X, 0, 1), 0, 1, 0)
			SliderFill.Size = pos
			local val = min + ((max - min) * pos.X.Scale)

			if isFloat then
				val = math.floor(val * 100) / 100
				Label.Text = text .. ": " .. string.format("%.2f", val)
			else
				val = math.floor(val)
				Label.Text = text .. ": " .. tostring(val)
			end

			Settings[settingKey] = val
		end
	end))

	table.insert(CheatEnv.Connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end))

	return Frame
end

local function CreateInput(text, settingKey, parent)
	local Frame = Instance.new("Frame")
	Frame.Parent = parent
	Frame.Size = UDim2.new(1, 0, 0, 35)
	Frame.BackgroundColor3 = Theme.Element

	local Corner = Instance.new("UICorner", Frame)
	Corner.CornerRadius = UDim.new(0, 6)

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(0.6, 0, 1, 0)
	Label.Position = UDim2.new(0, 10, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Text = text
	Label.TextColor3 = Theme.Text
	Label.Font = Enum.Font.GothamMedium
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.TextSize = 14
	Label.Parent = Frame

	local InputBox = Instance.new("TextBox")
	InputBox.Size = UDim2.new(0, 80, 0, 25)
	InputBox.Position = UDim2.new(1, -90, 0.5, -12.5)
	InputBox.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	InputBox.Text = tostring(Settings[settingKey])
	InputBox.TextColor3 = Theme.Accent
	InputBox.Font = Enum.Font.Code
	InputBox.TextSize = 14
	InputBox.Parent = Frame

	local I_Corner = Instance.new("UICorner", InputBox)
	I_Corner.CornerRadius = UDim.new(0, 4)

	local conn = InputBox.FocusLost:Connect(function()
		local num = tonumber(InputBox.Text)
		if num then
			if settingKey == "ImpulseInterval" then
				num = math.max(0, num) 
			end
			Settings[settingKey] = num
		end
		InputBox.Text = tostring(Settings[settingKey])
	end)
	table.insert(CheatEnv.UIConnections, conn)

	return Frame
end

local function CreateButton(text, color, callback, parent)
	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(1, 0, 0, 30)
	Button.BackgroundColor3 = color or Theme.Element
	Button.Text = text
	Button.TextColor3 = Theme.Text
	Button.Font = Enum.Font.GothamBold
	Button.Parent = parent

	local Corner = Instance.new("UICorner", Button)
	Corner.CornerRadius = UDim.new(0, 6)

	local conn = Button.MouseButton1Click:Connect(callback)
	table.insert(CheatEnv.UIConnections, conn)

	return Button
end

local function MakeDraggable(frame, restrictToMenu)
	if not frame then return end
	local dragging, dragInput, dragStart, startPos

	table.insert(CheatEnv.Connections, frame.InputBegan:Connect(function(input)
		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			if restrictToMenu and not MainFrame.Visible then return end
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end))

	table.insert(CheatEnv.Connections, frame.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
	end))

	table.insert(CheatEnv.Connections, UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			if restrictToMenu and not MainFrame.Visible then dragging = false return end
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
end

MakeDraggable(MainFrame, false)
MakeDraggable(Watermark, true)
MakeDraggable(KeybindFrame, true)

--// BUILDING MENU ELEMENTS //--

local C = GetCurrentParent("Combat")

CreateSection("-- AIMBOT --", C)
AddTooltip(CreateToggle("Aimbot Active", "Aimbot", Keybinds[3], C), "Automatically locks camera onto closest target")
-- [NEW] Aimbot Mode Dropdown
AddTooltip(CreateDropdown("Aimbot Mode", "AimbotMode", {"Central", "Cursor"}, C), "Central: Crosshair based / Cursor: Mouse based")
AddTooltip(CreateSlider("Aimbot FOV", "AimbotFOV", 10, 800, false, C), "Field of View radius for target acquisition")
AddTooltip(CreateSlider("Smoothness", "AimbotSmooth", 0.01, 1.0, true, C), "Lower value = Faster snap, Higher = Human-like movement")

CreateSection("-- AIMLOCK --", C)
AddTooltip(CreateToggle("Enable Aimlock", "Aimlock", Keybinds[2], C), "Toggle the separate Aimlock module")
CreateSlider("Aimlock FOV", "AimlockFOV", 10, 800, false, C)
CreateSlider("Aimlock Smooth", "AimlockSmooth", 0.01, 1.0, true, C)
CreateDropdown("Hit Point", "AimlockPart", {"Head", "Neck", "Chest"}, C)

-- [NEW] Added specific targeting mode for Aimlock
AddTooltip(CreateDropdown("Targeting Mode", "AimlockTargetMode", {"Central", "Cursor"}, C), "How Aimlock selects targets (Center or Mouse)")
-- Renamed previous "Mode" to "Trigger Mode" to avoid confusion
AddTooltip(CreateDropdown("Trigger Mode", "AimlockMode", {"N Toggle", "N Hold"}, C), "How to activate Aimlock")

-- Вставь это ПОСЛЕ создания слайдеров Aimbot/Aimlock
CreateSection("-- PREDICTION & CHECKS --", C)
AddTooltip(CreateSlider("Prediction", "Prediction", 0, 1, true, C), "Predict target movement (0.12 - 0.16 is standard)")
AddTooltip(CreateSlider("Deadzone", "Deadzone", 0, 10, false, C), "Pixels range to stop aiming (Fixes shaking)")
AddTooltip(CreateToggle("Ignore Knocked", "KnockedCheck", nil, C), "Don't aim at downed players")

CreateSection("-- Wall Check --", C)
AddTooltip(CreateToggle("Wall Check", "WallCheck", Keybinds[5], C), "Global check: Targets behind walls will be ignored")

CreateSection("-- NO RECOIL --", C)
AddTooltip(CreateToggle("No Recoil", "NoRecoil", Keybinds[4], C), "Eliminates visual and physical recoil when shooting")
AddTooltip(CreateDropdown("Recoil Mode", "NR_Mode", {"Classic", "Smart"}, C), "Classic = Static force, Smart = Dynamic compensation")
AddTooltip(CreateSlider("Recoil Strength", "RecoilStrength", 0, 100, false, C), "Intensity of recoil reduction")

AddTooltip(CreateDropdown("Movement Method", "MovementMode", {"Constant", "Impulse"}, C), "Constant = Smooth pull, Impulse = Discrete steps")
AddTooltip(CreateInput("Impulse Interval (ms)", "ImpulseInterval", C), "Delay between recoil compensation impulses")

local V = GetCurrentParent("Visuals")

CreateSection("-- ESP --", V)
AddTooltip(CreateToggle("Enable ESP", "ESP", Keybinds[1], V), "Draws 2D boxes around players")
AddTooltip(CreateToggle("Show Names", "ESP_Names", nil, V), "Displays player names above their boxes")

CreateSection("-- FOV VISUALS --", V)
AddTooltip(CreateToggle("Draw Aimbot FOV", "ShowFOV", nil, V), "Visualizes the Aimbot radius")

local M = GetCurrentParent("Misc")

CreateSection("-- TEAM CHECK --", M)

CreateToggle("Hide Teammates ESP", "TC_Hide", nil, M, function()
	UpdateTeamCheckDependencies()
end)

CreateToggle("No Aim at Teammates", "TC_NoAim", nil, M)
CreateToggle("Green Teammates ESP", "TC_Green", nil, M)

local S = GetCurrentParent("System")

CreateSection("-- MENU --", S)

AddTooltip(CreateButton("UNLOAD CHEAT", Color3.fromRGB(180, 40, 40), function()
	_G.CheatLoaded = false
	
	pcall(function()
		if MenuBlur then MenuBlur:Destroy() end
	end)
	
	pcall(function()
		for _, conn in pairs(CheatEnv.Connections) do
			if conn and conn.Connected then conn:Disconnect() end
		end
	end)
	
	pcall(function()
		for _, conn in pairs(CheatEnv.UIConnections) do
			if conn and conn.Connected then conn:Disconnect() end
		end
	end)
	
	pcall(function()
		for _, drawing in pairs(CheatEnv.Drawings) do
			if drawing and drawing.Remove then drawing:Remove() end
		end
	end)
	
	pcall(function()
		for _, ui in pairs(CheatEnv.UI) do
			if ui then ui:Destroy() end
		end
	end)
	
	warn("✓ VAYS v6.5 unloaded successfully.")
end, S), "Fully unload the script and clear memory")

Tabs["Combat"].Visible = true

--// LOGIC FUNCTIONS //--

local function IsTeammate(player)
	if not player or not LocalPlayer then return false end
	if not player.Team or not LocalPlayer.Team then return false end
	return player.Team == LocalPlayer.Team
end

local function ApplyNoRecoil(dt)
	if not Settings.NoRecoil then return end
	if not dt then dt = 1/60 end
	local isPressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	if not isPressed then HasShotOnce = false return end

	if mousemoverel then
		local shake = math.random(-1, 1)
		local currentTime = tick() * 1000
		local finalY = (Settings.NR_Mode == "Classic") and Settings.RecoilStrength or (Settings.RecoilStrength * (dt * 60))

		if Settings.MovementMode == "Constant" then
			mousemoverel(shake, finalY)
		else
			if Settings.ImpulseInterval <= 0 then
				if not HasShotOnce then mousemoverel(shake, finalY) HasShotOnce = true end
			else
				if (currentTime - LastImpulseTime) >= Settings.ImpulseInterval then
					mousemoverel(shake, finalY)
					LastImpulseTime = currentTime
				end
			end
		end
	end
end

-- [NEW] Helper to get Search Origin based on specific Mode string
local function GetScreenPosition(mode)
    if mode == "Cursor" then
        return UserInputService:GetMouseLocation()
    else
        return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    end
end

local function IsVisible(targetPart, character)
	if not Settings.WallCheck then return true end
	if not targetPart or not character then return false end
	
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	if LocalPlayer.Character then
		rayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
	end
	local origin = Camera.CFrame.Position
	local direction = (targetPart.Position - origin).Unit * (targetPart.Position - origin).Magnitude
	local result = Workspace:Raycast(origin, direction, rayParams)
	return (result and result.Instance:IsDescendantOf(character)) or false
end

-- [NEW] Updated to accept specific Origin Point
local function GetClosestTarget(fovLimit, hitPartName, originPoint)
    if not LocalPlayer or not LocalPlayer.Character then return nil end
    
    fovLimit = math.max(1, fovLimit or 100)
    local Closest = nil
    local MinDist = fovLimit
    local Origin = originPoint

    local realPartName = "Head"
    if hitPartName == "Neck" then realPartName = "Head" -- Обычно хитбоксы шеи привязаны к голове
    elseif hitPartName == "Chest" then realPartName = "UpperTorso" end

    for _, Player in pairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer and Player.Character then
            local humanoid = Player.Character:FindFirstChild("Humanoid")
            local char = Player.Character
            
            -- [IMPROVED] Проверки жизнедеятельности
            if humanoid and humanoid.Health > 0 then
                
                -- Проверка на нокнутых (KO Check)
                if Settings.KnockedCheck then
                    -- Проверка для Da Hood и подобных игр (KO_VAL / Grabbed)
                    if char:FindFirstChild("KO_VAL") or char:FindFirstChild("Grabbed") then continue end
                    -- Проверка состояния гуманоида (Ragdoll/FallingDown часто означает нок)
                    local state = humanoid:GetState()
                    if state == Enum.HumanoidStateType.Physics or state == Enum.HumanoidStateType.Dead then continue end
                end

                if Settings.TC_NoAim and IsTeammate(Player) then continue end

                local TargetPart = char:FindFirstChild(realPartName)
                if not TargetPart and hitPartName == "Chest" then 
                    TargetPart = char:FindFirstChild("Torso") 
                end

                if TargetPart then
                    local ScreenPos, OnScreen = Camera:WorldToViewportPoint(TargetPart.Position)
                    if OnScreen then
                        local Dist = (Vector2.new(ScreenPos.X, ScreenPos.Y) - Origin).Magnitude
                        if Dist < MinDist and IsVisible(TargetPart, Player.Character) then
                            MinDist = Dist
                            Closest = TargetPart
                        end
                    end
                end
            end
        end
    end

    return Closest
end

local function GetPredictedPos(targetPart)
    if not targetPart then return Vector3.new(0,0,0) end
    local velocity = Vector3.new(0,0,0)
    
    -- Пытаемся найти Velocity у RootPart (самое точное)
    if targetPart.Parent and targetPart.Parent:FindFirstChild("HumanoidRootPart") then
        velocity = targetPart.Parent.HumanoidRootPart.Velocity
    elseif targetPart:IsA("BasePart") then
        velocity = targetPart.Velocity
    end

    -- Формула: Позиция + (Скорость * Коэффициент времени)
    return targetPart.Position + (velocity * Settings.Prediction)
end

local function UpdateAimbot()
    if not Camera then return end
    
    local Origin = GetScreenPosition(Settings.AimbotMode)
    FOVRing.Position = Origin
    FOVRing.Radius = math.max(1, Settings.AimbotFOV or 100)
    FOVRing.Visible = Settings.ShowFOV and Settings.Aimbot

    if Settings.Aimbot then
        local TargetPart = GetClosestTarget(Settings.AimbotFOV, "Head", Origin)
        if TargetPart then
            -- [NEW] Используем предсказанную позицию
            local GoalPosition = GetPredictedPos(TargetPart)
            
            -- [NEW] Проверка Deadzone (если прицел уже на цели, не дергаем камеру)
            local ScreenPos = Camera:WorldToViewportPoint(GoalPosition)
            local DistToCenter = (Vector2.new(ScreenPos.X, ScreenPos.Y) - Origin).Magnitude
            
            if DistToCenter > Settings.Deadzone then
                Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, GoalPosition), Settings.AimbotSmooth)
            end
        end
    end
end

local function UpdateAimlock()
    if not Settings.Aimlock then
        AimlockRing.Visible = false
        AimlockEngaged = false
        return
    end

    if not Camera then return end
    
    local Origin = GetScreenPosition(Settings.AimlockTargetMode)
    AimlockRing.Position = Origin
    AimlockRing.Radius = math.max(1, Settings.AimlockFOV or 90)
    AimlockRing.Visible = AimlockEngaged

    if AimlockEngaged then
        local TargetPart = GetClosestTarget(Settings.AimlockFOV, Settings.AimlockPart, Origin)
        if TargetPart then
            -- [NEW] Используем предсказанную позицию
            local GoalPosition = GetPredictedPos(TargetPart)
            
            -- Динамическая плавность: чем ближе курсор к цели, тем плавнее движение (чтобы не проскакивать)
            local currentSmooth = Settings.AimlockSmooth
            -- Если хочешь добавить замедление у цели, раскомментируй строку ниже:
            -- currentSmooth = currentSmooth * 0.8 

            Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, GoalPosition), currentSmooth)
        end
    end
end

local ESP_Storage = {}

local function CreateESP(player)
	if ESP_Storage[player] then return end

	local Box = Drawing.new("Square")
	Box.Visible = false
	Box.Color = Settings.BoxColor
	Box.Thickness = 1.5

	local NameTag = Drawing.new("Text")
	NameTag.Visible = false
	NameTag.Text = player.Name
	NameTag.Size = 16
	NameTag.Center = true
	NameTag.Outline = true
	NameTag.Color = Settings.NameColor

	ESP_Storage[player] = {Box = Box, Tag = NameTag, Player = player}

	table.insert(CheatEnv.Drawings, Box)
	table.insert(CheatEnv.Drawings, NameTag)
end

local function RemoveESP(player)
	if ESP_Storage[player] then
		pcall(function() 
			if ESP_Storage[player].Box then ESP_Storage[player].Box:Remove() end
			if ESP_Storage[player].Tag then ESP_Storage[player].Tag:Remove() end
		end)
		ESP_Storage[player] = nil
	end
end

local function UpdateESP()
	for _, data in pairs(ESP_Storage) do
		local plr = data.Player
		if not plr then continue end
		
		local isTeam = IsTeammate(plr)

		if isTeam and Settings.TC_Hide then
			data.Box.Visible = false
			data.Tag.Visible = false
			continue
		end

		if Settings.ESP and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
			local humanoid = plr.Character:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local HRP = plr.Character.HumanoidRootPart
				local Pos, OnScreen = Camera:WorldToViewportPoint(HRP.Position)

				if OnScreen then
					local Size = (Camera:WorldToViewportPoint(HRP.Position - Vector3.new(0, 3, 0)).Y - Camera:WorldToViewportPoint(HRP.Position + Vector3.new(0, 2.6, 0)).Y) / 2
					local bWidth, bHeight = (Size * 1.5), (Size * 2)
					local bPosX, bPosY = (Pos.X - bWidth / 2), (Pos.Y - bHeight / 2)

					data.Box.Size = Vector2.new(bWidth, bHeight)
					data.Box.Position = Vector2.new(bPosX, bPosY)

					if isTeam and Settings.TC_Green then
						data.Box.Color = Theme.Green
					else
						data.Box.Color = Settings.BoxColor
					end

					data.Box.Visible = true

					if Settings.ESP_Names then
						data.Tag.Position = Vector2.new(Pos.X, bPosY - 18)
						data.Tag.Visible = true
						data.Tag.Color = (isTeam and Settings.TC_Green) and Theme.Green or Settings.NameColor
					else
						data.Tag.Visible = false
					end
				else
					data.Box.Visible = false
					data.Tag.Visible = false
				end
			else
				data.Box.Visible = false
				data.Tag.Visible = false
			end
		else
			data.Box.Visible = false
			data.Tag.Visible = false
		end
	end
end

for _, v in pairs(Players:GetPlayers()) do if v ~= LocalPlayer then CreateESP(v) end end

table.insert(CheatEnv.Connections, Players.PlayerAdded:Connect(CreateESP))
table.insert(CheatEnv.Connections, Players.PlayerRemoving:Connect(RemoveESP))

--// INPUT HANDLER //--

table.insert(CheatEnv.Connections, UserInputService.InputBegan:Connect(function(input, processed)
	if input.KeyCode == Settings.MenuKey then
		MainFrame.Visible = not MainFrame.Visible
		MenuBlur.Enabled = MainFrame.Visible
		TweenService:Create(MenuBlur, TweenInfo.new(0.3), {Size = MainFrame.Visible and 20 or 0}):Play()
		return
	end

	if input.KeyCode == Enum.KeyCode.N then
		if not Settings.Aimlock then
			Settings.Aimlock = true
			SyncButton("Aimlock")
		end

		if Settings.AimlockMode == "N Toggle" then
			AimlockEngaged = not AimlockEngaged
		elseif Settings.AimlockMode == "N Hold" then
			AimlockEngaged = true
		end
		AimlockEngagedFromGUI = false

		UpdateKeybindList()
		return
	end

	for _, bind in ipairs(Keybinds) do
		if input.KeyCode == bind.Key then
			if bind.Setting == "Aimlock" then continue end

			if bind.Setting ~= "Unload" then
				Settings[bind.Setting] = not Settings[bind.Setting]
				SyncButton(bind.Setting)
				UpdateKeybindList()
			end
		end
	end

	if processed then return end
end))

table.insert(CheatEnv.Connections, UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.N and Settings.AimlockMode == "N Hold" then
		AimlockEngaged = false
		UpdateKeybindList()
	end
end))

table.insert(CheatEnv.Connections, RunService.RenderStepped:Connect(function(dt)
	UpdateESP()
	UpdateAimlock()
	UpdateAimbot()
	ApplyNoRecoil(dt)
end))

UpdateKeybindList()

print("✓ VAYS v6.5 (Split Targeting Modes) Loaded successfully.")
