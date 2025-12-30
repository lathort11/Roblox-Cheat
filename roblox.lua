--[[
    VAYS ENGINE v5.7 (Logo Update)
    - Added local file handling for custom logo image.
    - Replaced text header with image header in sidebar.
    - Fixed GUI Crashes (from v5.6)
]]

-- СЕРВИСЫ
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService") -- Добавлен HttpService

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
    Toggles = {}, -- Хранилище кнопок для синхронизации
    Dropdowns = {}
}

-- ПЕРЕМЕННЫЕ
local LastImpulseTime = 0
local HasShotOnce = false

-- ЦВЕТОВАЯ ПАЛИТРА
local Theme = {
    Background = Color3.fromRGB(20, 20, 20),
    Element = Color3.fromRGB(35, 35, 35),
    Accent = Color3.fromRGB(0, 180, 255), -- Неоновый синий
    Text = Color3.fromRGB(240, 240, 240),
    TextDark = Color3.fromRGB(150, 150, 150),
    Glow = Color3.fromRGB(0, 190, 255),
    Stroke = Color3.fromRGB(0, 180, 255)
}

-- НАСТРОЙКИ
local Settings = {
    ESP = false,
    ESP_Names = false,
    NR_Mode = "Classic", -- Classic, Smart
    MovementMode = "Constant", -- Constant, Impulse
    ImpulseInterval = 500,
    Aimbot = false,
    NoRecoil = false,
    RecoilStrength = 15,
    AimbotFOV = 100,
    AimbotSmooth = 0.2,
    WallCheck = true,
    ShowFOV = true,
    BoxColor = Color3.fromRGB(255, 50, 50),
    NameColor = Color3.fromRGB(255, 255, 255),
    FOVColor = Color3.fromRGB(255, 255, 255),
    MenuKey = Enum.KeyCode.RightAlt
}

-- БИНДЫ (Имя ключа должно совпадать с ключом в Settings)
local Keybinds = {
    {Name = "ESP", Key = Enum.KeyCode.Y, Setting = "ESP"},
    {Name = "Aimbot", Key = Enum.KeyCode.T, Setting = "Aimbot"},
    {Name = "No Recoil", Key = Enum.KeyCode.G, Setting = "NoRecoil"},
    {Name = "Wall Check", Key = Enum.KeyCode.B, Setting = "WallCheck"},
    {Name = "Unload", Key = Enum.KeyCode.Delete, Setting = "Unload"}
}

--// ФУНКЦИЯ ЗАГРУЗКИ ЛОГОТИПА //--
local function SetupLogoImage()
    -- Проверка поддержки файловой системы эксплойтом
    if not makefolder or not writefile or not isfile or not getcustomasset then
        warn("Executor does not support file system operations. Falling back to text logo.")
        return nil
    end

    local folderPath = "VAYS"
    local subFolderPath = folderPath .. "/logo"
    local filePath = subFolderPath .. "/Vays.png"
    local url = "https://raw.githubusercontent.com/lathort11/Roblox-Cheat/main/Vays.png"

    -- Создание папок, если их нет
    if not isfolder(folderPath) then makefolder(folderPath) end
    if not isfolder(subFolderPath) then makefolder(subFolderPath) end

    -- Скачивание файла, если его нет
    if not isfile(filePath) then
        local success, content = pcall(function() return game:HttpGet(url) end)
        if success then
            writefile(filePath, content)
            print("VAYS Logo downloaded successfully.")
        else
            warn("Failed to download logo image from URL.")
            return nil
        end
    end

    -- Возврат локального ассета
    local success, assetId = pcall(function() return getcustomasset(filePath) end)
    if success then
        return assetId
    else
        warn("Failed to load custom asset.")
        return nil
    end
end

local LogoAssetId = SetupLogoImage()

--// DRAWING LIB CHECK //--
local Drawing = Drawing or {new = function() return {Visible = false, Remove = function() end} end} -- Fallback

local FOVRing = Drawing.new("Circle")
FOVRing.Visible = false
FOVRing.Thickness = 1.5
FOVRing.Color = Theme.Accent
FOVRing.Filled = false
FOVRing.Radius = Settings.AimbotFOV
FOVRing.NumSides = 64
table.insert(CheatEnv.Drawings, FOVRing)

--// GUI ENGINE //--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VAYSUI_v5.7"
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if gethui then ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then syn.protect_gui(ScreenGui) ScreenGui.Parent = CoreGui
else ScreenGui.Parent = CoreGui end
table.insert(CheatEnv.UI, ScreenGui)

-- 1. WATERMARK
local Watermark = Instance.new("Frame")
Watermark.Name = "Watermark"
Watermark.Size = UDim2.new(0, 190, 0, 32)
Watermark.Position = UDim2.new(0.01, 0, 0.01, 0)
Watermark.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
Watermark.BackgroundTransparency = 0.1
Watermark.BorderSizePixel = 0
Watermark.Parent = ScreenGui

local WM_Corner = Instance.new("UICorner")
WM_Corner.CornerRadius = UDim.new(0, 6)
WM_Corner.Parent = Watermark

local WM_Stroke = Instance.new("UIStroke")
WM_Stroke.Color = Theme.Stroke
WM_Stroke.Thickness = 1.2
WM_Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
WM_Stroke.Parent = Watermark

local AccentLine = Instance.new("Frame")
AccentLine.Size = UDim2.new(1, 0, 0, 2)
AccentLine.Position = UDim2.new(0, 0, 0, 0)
AccentLine.BorderSizePixel = 0
AccentLine.Parent = Watermark

local AL_Gradient = Instance.new("UIGradient")
AL_Gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Theme.Accent),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(1, Theme.Accent)
})
AL_Gradient.Parent = AccentLine

local AL_Corner = Instance.new("UICorner")
AL_Corner.CornerRadius = UDim.new(0, 6)
AL_Corner.Parent = AccentLine

local WM_Text = Instance.new("TextLabel")
WM_Text.Size = UDim2.new(1, -20, 1, 0)
WM_Text.Position = UDim2.new(0, 10, 0, 0)
WM_Text.BackgroundTransparency = 1
WM_Text.Text = "VAYS | FPS: 60 | MS: 20"
WM_Text.TextColor3 = Color3.fromRGB(255, 255, 255)
WM_Text.Font = Enum.Font.Code
WM_Text.TextSize = 13
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
    while true do
        TweenService:Create(AL_Gradient, TweenInfo.new(2, Enum.EasingStyle.Linear), {Offset = Vector2.new(1, 0)}):Play()
        task.wait(2)
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

local KB_Corner = Instance.new("UICorner")
KB_Corner.CornerRadius = UDim.new(0, 4)
KB_Corner.Parent = KeybindFrame

local KB_Stroke = Instance.new("UIStroke")
KB_Stroke.Color = Theme.Stroke
KB_Stroke.Thickness = 1
KB_Stroke.Transparency = 0.2
KB_Stroke.Parent = KeybindFrame

local KB_List = Instance.new("UIListLayout")
KB_List.SortOrder = Enum.SortOrder.LayoutOrder
KB_List.Padding = UDim.new(0, 2)
KB_List.HorizontalAlignment = Enum.HorizontalAlignment.Center
KB_List.Parent = KeybindFrame

local KB_Padding = Instance.new("UIPadding")
KB_Padding.PaddingTop = UDim.new(0, 6)
KB_Padding.PaddingBottom = UDim.new(0, 6)
KB_Padding.PaddingLeft = UDim.new(0, 10)
KB_Padding.PaddingRight = UDim.new(0, 10)
KB_Padding.Parent = KeybindFrame

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

local SB_Fix = Instance.new("Frame")
SB_Fix.Size = UDim2.new(0, 10, 1, 0)
SB_Fix.Position = UDim2.new(0, 110, 0, 0)
SB_Fix.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
SB_Fix.BackgroundTransparency = 0.5
SB_Fix.BorderSizePixel = 0
SB_Fix.Parent = MainFrame

local TabList = Instance.new("UIListLayout", SideBar)
TabList.Padding = UDim.new(0, 5)
TabList.HorizontalAlignment = Enum.HorizontalAlignment.Center

local TabPadding = Instance.new("UIPadding", SideBar)
TabPadding.PaddingTop = UDim.new(0, 10)

-- // ЗАМЕНА ТЕКСТА BLOCK НА ИЗОБРАЖЕНИЕ //
local Logo
if LogoAssetId then
    -- Создаем ImageLabel если картинка загрузилась
    Logo = Instance.new("ImageLabel")
    Logo.Name = "LogoImage"
    Logo.Size = UDim2.new(0.8, 0, 0, 40) -- Немного уменьшил ширину для красоты
    Logo.BackgroundTransparency = 1
    Logo.Image = LogoAssetId
    Logo.ScaleType = Enum.ScaleType.Fit -- Сохраняем пропорции картинки
    Logo.Parent = SideBar
else
    -- Фоллбэк на текст если картинка не загрузилась
    Logo = Instance.new("TextLabel")
    Logo.Name = "LogoText"
    Logo.Size = UDim2.new(1, 0, 0, 40)
    Logo.Text = "VAYS" -- Заменил BLOCK на VAYS
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
local function CreateTabContainer(name)
    local Container = Instance.new("ScrollingFrame")
    Container.Size = UDim2.new(1, 0, 1, 0)
    Container.BackgroundTransparency = 1
    Container.ScrollBarThickness = 2
    Container.Visible = false
    Container.ScrollBarImageColor3 = Theme.Accent
    Container.BorderSizePixel = 0
    Container.Parent = ContentArea
    
    local Layout = Instance.new("UIListLayout", Container)
    Layout.Padding = UDim.new(0, 8)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder
    
    Tabs[name] = Container
    return Container
end

local CombatTab = CreateTabContainer("Combat")
local VisualsTab = CreateTabContainer("Visuals")
local MiscTab = CreateTabContainer("Misc")
local SystemTab = CreateTabContainer("System")

local function SwitchTab(name)
    for tabName, container in pairs(Tabs) do
        container.Visible = (tabName == name)
    end
end

local function CreateTabButton(name)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(0.9, 0, 0, 35)
    Button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    Button.Text = name
    Button.TextColor3 = Theme.TextDark
    Button.Font = Enum.Font.GothamMedium
    Button.TextSize = 13
    Button.Parent = SideBar
    
    local BC = Instance.new("UICorner", Button)
    BC.CornerRadius = UDim.new(0, 6)
    
    Button.MouseButton1Click:Connect(function()
        SwitchTab(name)
        for _, child in pairs(SideBar:GetChildren()) do
            if child:IsA("TextButton") then
                TweenService:Create(child, TweenInfo.new(0.2), {TextColor3 = Theme.TextDark, BackgroundColor3 = Color3.fromRGB(30, 30, 30)}):Play()
            end
        end
        TweenService:Create(Button, TweenInfo.new(0.2), {TextColor3 = Theme.Text, BackgroundColor3 = Theme.Element}):Play()
    end)
end

CreateTabButton("Combat")
CreateTabButton("Visuals")
CreateTabButton("Misc")
CreateTabButton("System")

local function GetCurrentParent(tabName) return Tabs[tabName] end

--// UI HELPER FUNCTIONS //--

local function UpdateKeybindList()
    if not KeybindFrame or not KeybindFrame.Parent then return end

    for _, child in pairs(KeybindFrame:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextLabel") then child:Destroy() end
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
    
    local Separator = Instance.new("Frame")
    Separator.Name = "Separator"
    Separator.Size = UDim2.new(1, 0, 0, 1)
    Separator.BackgroundColor3 = Theme.Stroke
    Separator.BackgroundTransparency = 0.5
    Separator.BorderSizePixel = 0
    Separator.Parent = KeybindFrame

    local activeCount = 0
    
    for _, bind in ipairs(Keybinds) do
        if bind.Setting ~= "Unload" and Settings[bind.Setting] then
            activeCount = activeCount + 1
            
            local Line = Instance.new("Frame")
            Line.Size = UDim2.new(1, 0, 0, 22)
            Line.BackgroundTransparency = 1
            Line.Parent = KeybindFrame
            
            local NameLbl = Instance.new("TextLabel")
            NameLbl.Size = UDim2.new(1, 0, 1, 0)
            NameLbl.BackgroundTransparency = 1
            NameLbl.Text = string.format("%s -- [%s]", bind.Name:upper(), bind.Key.Name)
            NameLbl.TextColor3 = Color3.fromRGB(230, 230, 230)
            NameLbl.Font = Enum.Font.GothamMedium
            NameLbl.TextSize = 13
            NameLbl.TextXAlignment = Enum.TextXAlignment.Center
            NameLbl.Parent = Line
        end
    end
    
    local targetHeight = (activeCount > 0) and (activeCount * 22 + 40) or 0
    
    TweenService:Create(KeybindFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Size = UDim2.new(0, 200, 0, targetHeight)
    }):Play()
    
    local targetTransparency = (activeCount == 0) and 1 or 0
    TweenService:Create(KeybindFrame, TweenInfo.new(0.2), {BackgroundTransparency = (activeCount == 0) and 1 or 0.1}):Play()
    TweenService:Create(KB_Stroke, TweenInfo.new(0.2), {Transparency = (activeCount == 0) and 1 or 0.2}):Play()
end

local function SyncButton(settingKey)
    if CheatEnv.Toggles[settingKey] then
        local isActive = Settings[settingKey]
        local color = isActive and Theme.Accent or Color3.fromRGB(60,60,60)
        TweenService:Create(CheatEnv.Toggles[settingKey], TweenInfo.new(0.2), {BackgroundColor3 = color}):Play()
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

local function CreateToggle(text, settingKey, bindInfo, parent)
    local Frame = Instance.new("Frame")
    -- ИСПРАВЛЕНИЕ: Parent -> parent
    Frame.Parent = parent 
    Frame.Size = UDim2.new(1, 0, 0, 35)
    Frame.BackgroundColor3 = Theme.Element
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Frame
    
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
    
    local BtnCorner = Instance.new("UICorner")
    BtnCorner.CornerRadius = UDim.new(0, 4)
    BtnCorner.Parent = Button
    
    CheatEnv.Toggles[settingKey] = Button
    
    Button.MouseButton1Click:Connect(function()
        Settings[settingKey] = not Settings[settingKey]
        SyncButton(settingKey)
        UpdateKeybindList()
    end)
end

local function CreateDropdown(text, settingKey, options, parent)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 50)
    Frame.BackgroundColor3 = Theme.Element
    Frame.ZIndex = 5
    Frame.Parent = parent -- Added parent
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Frame
    
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
    
    local M_Corner = Instance.new("UICorner")
    M_Corner.CornerRadius = UDim.new(0, 4)
    M_Corner.Parent = MainBtn
    
    local DropList = Instance.new("ScrollingFrame")
    DropList.Size = UDim2.new(0.4, 0, 0, 0)
    DropList.Position = UDim2.new(0.55, 0, 0, 32)
    DropList.BackgroundColor3 = Color3.fromRGB(30,30,30)
    DropList.BorderSizePixel = 0
    DropList.ScrollBarThickness = 2
    DropList.Visible = false
    DropList.Parent = Frame
    DropList.ZIndex = 10
    
    local D_ListLayout = Instance.new("UIListLayout")
    D_ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    D_ListLayout.Parent = DropList
    
    local isOpen = false
    
    MainBtn.MouseButton1Click:Connect(function()
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
        
        OptBtn.MouseButton1Click:Connect(function()
            Settings[settingKey] = opt
            MainBtn.Text = opt .. " ▼"
            isOpen = false
            DropList.Visible = false
            TweenService:Create(Frame, TweenInfo.new(0.2), {Size = UDim2.new(1, 0, 0, 35)}):Play()
        end)
    end
end

local function CreateSlider(text, settingKey, min, max, isFloat, parent)
    -- ИСПРАВЛЕНИЕ: Frame создается ПЕРЕД тем как мы его используем
    local Frame = Instance.new("Frame")
    Frame.Parent = parent
    Frame.Size = UDim2.new(1, 0, 0, 50)
    Frame.BackgroundColor3 = Theme.Element
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Frame
    
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
    
    local S_Corner = Instance.new("UICorner")
    S_Corner.CornerRadius = UDim.new(1, 0)
    S_Corner.Parent = SliderBG
    
    local SliderFill = Instance.new("Frame")
    local startPercent = (Settings[settingKey] - min) / (max - min)
    SliderFill.Size = UDim2.new(math.clamp(startPercent, 0, 1), 0, 1, 0)
    SliderFill.BackgroundColor3 = Theme.Accent
    SliderFill.BorderSizePixel = 0
    SliderFill.Parent = SliderBG
    
    local F_Corner = Instance.new("UICorner")
    F_Corner.CornerRadius = UDim.new(1, 0)
    F_Corner.Parent = SliderFill
    
    local Trigger = Instance.new("TextButton")
    Trigger.Size = UDim2.new(1, 0, 1, 0)
    Trigger.BackgroundTransparency = 1
    Trigger.Text = ""
    Trigger.Parent = SliderBG
    
    local dragging = false
    
    Trigger.InputBegan:Connect(function(input)
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
end

local function CreateInput(text, settingKey, parent)
    -- ИСПРАВЛЕНИЕ: Frame создается ПЕРЕД тем как мы его используем
    local Frame = Instance.new("Frame")
    Frame.Parent = parent
    Frame.Size = UDim2.new(1, 0, 0, 35)
    Frame.BackgroundColor3 = Theme.Element
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Frame
    
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
    
    local I_Corner = Instance.new("UICorner")
    I_Corner.CornerRadius = UDim.new(0, 4)
    I_Corner.Parent = InputBox
    
    InputBox.FocusLost:Connect(function()
        local num = tonumber(InputBox.Text)
        if num then
            Settings[settingKey] = num
        else
            InputBox.Text = tostring(Settings[settingKey])
        end
    end)
end

local function CreateButton(text, color, callback, parent)
    -- ИСПРАВЛЕНИЕ: Убрана лишняя строка с Frame и исправлен Parent
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(1, 0, 0, 30)
    Button.BackgroundColor3 = color or Theme.Element
    Button.Text = text
    Button.TextColor3 = Theme.Text
    Button.Font = Enum.Font.GothamBold
    Button.Parent = parent -- Было ScrollContainer
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 6)
    Corner.Parent = Button
    
    Button.MouseButton1Click:Connect(callback)
end

--// DRAG LOGIC (RESTRICTED) //--
local function MakeDraggable(frame, restrictToMenu)
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
--// COMBAT //--
local C = GetCurrentParent("Combat")
CreateSection("-- AIMBOT --", C)
CreateToggle("Aimbot Active", "Aimbot", Keybinds[2], C) -- Fixed bind argument
CreateSlider("Aimbot FOV", "AimbotFOV", 10, 800, false, C)
CreateSlider("Smoothness", "AimbotSmooth", 0.01, 1.0, true, C)
CreateToggle("Wall Check", "WallCheck", Keybinds[4], C)

CreateSection("-- RECOIL --", C)
CreateToggle("No Recoil", "NoRecoil", Keybinds[3], C)
CreateDropdown("Recoil Mode", "NR_Mode", {"Classic", "Smart"}, C)
CreateSlider("Recoil Strength", "RecoilStrength", 0, 100, false, C)

--// VISUALS //--
local V = GetCurrentParent("Visuals")
CreateSection("-- ESP --", V)
CreateToggle("Enable ESP", "ESP", Keybinds[1], V)
CreateToggle("Show Names", "ESP_Names", nil, V)
CreateSection("-- OTHER --", V)
CreateToggle("Draw FOV Circle", "ShowFOV", nil, V)

--// MISC //--
local M = GetCurrentParent("Misc")
CreateSection("-- MOVEMENT --", M)
CreateDropdown("Movement Mode", "MovementMode", {"Constant", "Impulse"}, M)
CreateInput("Impulse Interval (ms)", "ImpulseInterval", M)

--// SYSTEM //--
local S = GetCurrentParent("System")
CreateSection("-- MENU --", S)
CreateButton("UNLOAD CHEAT", Color3.fromRGB(180, 40, 40), function()
    _G.CheatLoaded = false
    MenuBlur:Destroy()
    for i, conn in pairs(CheatEnv.Connections) do pcall(function() conn:Disconnect() end) end
    for i, drawing in pairs(CheatEnv.Drawings) do pcall(function() drawing:Remove() end) end
    for i, ui in pairs(CheatEnv.UI) do pcall(function() ui:Destroy() end) end
    warn("Unloaded.")
end, S)

SwitchTab("Combat")

--// LOGIC FUNCTIONS //--
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

local function IsVisible(targetPart, character)
    if not Settings.WallCheck then return true end
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    local origin = Camera.CFrame.Position
    local direction = (targetPart.Position - origin).Unit * (targetPart.Position - origin).Magnitude
    local result = Workspace:Raycast(origin, direction, rayParams)
    return (result and result.Instance:IsDescendantOf(character))
end

local function GetClosestTarget()
    local Closest = nil
    local MinDist = Settings.AimbotFOV
    local MousePos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    for _, Player in pairs(Players:GetPlayers()) do
        if Player ~= LocalPlayer and Player.Character and Player.Character:FindFirstChild("Head") and Player.Character.Humanoid.Health > 0 then
            local Head = Player.Character.Head
            local ScreenPos, OnScreen = Camera:WorldToViewportPoint(Head.Position)
            if OnScreen then
                local Dist = (Vector2.new(ScreenPos.X, ScreenPos.Y) - MousePos).Magnitude
                if Dist < MinDist and IsVisible(Head, Player.Character) then 
                    MinDist = Dist
                    Closest = Head
                end
            end
        end
    end
    return Closest
end

local function UpdateAimbot()
    FOVRing.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    FOVRing.Radius = Settings.AimbotFOV
    FOVRing.Visible = Settings.ShowFOV and Settings.Aimbot
    if Settings.Aimbot then
        local TargetPart = GetClosestTarget()
        if TargetPart then
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, TargetPart.Position), Settings.AimbotSmooth)
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
        pcall(function() ESP_Storage[player].Box:Remove() ESP_Storage[player].Tag:Remove() end)
        ESP_Storage[player] = nil
    end
end

local function UpdateESP()
    for _, data in pairs(ESP_Storage) do
        local plr = data.Player
        if Settings.ESP and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and plr.Character.Humanoid.Health > 0 then
            local HRP = plr.Character.HumanoidRootPart
            local Pos, OnScreen = Camera:WorldToViewportPoint(HRP.Position)
            if OnScreen then
                local Size = (Camera:WorldToViewportPoint(HRP.Position - Vector3.new(0, 3, 0)).Y - Camera:WorldToViewportPoint(HRP.Position + Vector3.new(0, 2.6, 0)).Y) / 2
                local bWidth, bHeight = (Size * 1.5), (Size * 2)
                local bPosX, bPosY = (Pos.X - bWidth / 2), (Pos.Y - bHeight / 2)
                data.Box.Size = Vector2.new(bWidth, bHeight)
                data.Box.Position = Vector2.new(bPosX, bPosY)
                data.Box.Visible = true
                if Settings.ESP_Names then
                    data.Tag.Position = Vector2.new(Pos.X, bPosY - 18)
                    data.Tag.Visible = true
                else data.Tag.Visible = false end
            else data.Box.Visible = false data.Tag.Visible = false end
        else data.Box.Visible = false data.Tag.Visible = false end
    end
end

for _, v in pairs(Players:GetPlayers()) do if v ~= LocalPlayer then CreateESP(v) end end
table.insert(CheatEnv.Connections, Players.PlayerAdded:Connect(CreateESP))
table.insert(CheatEnv.Connections, Players.PlayerRemoving:Connect(RemoveESP))

table.insert(CheatEnv.Connections, UserInputService.InputBegan:Connect(function(input, processed)
    if input.KeyCode == Settings.MenuKey then
        MainFrame.Visible = not MainFrame.Visible
        MenuBlur.Enabled = MainFrame.Visible
        TweenService:Create(MenuBlur, TweenInfo.new(0.3), {Size = MainFrame.Visible and 20 or 0}):Play()
        return
    end
    if processed then return end
    
    for _, bind in ipairs(Keybinds) do
        if input.KeyCode == bind.Key then
            if bind.Setting == "Unload" then
                -- Unload Logic
            else
                Settings[bind.Setting] = not Settings[bind.Setting]
                SyncButton(bind.Setting)
                UpdateKeybindList()
            end
        end
    end
end))

table.insert(CheatEnv.Connections, RunService.RenderStepped:Connect(function(dt)
    UpdateESP()
    UpdateAimbot()
    ApplyNoRecoil(dt)
end))

UpdateKeybindList()

print(" Vays v5.7 (Logo Update) Loaded successfully.")
