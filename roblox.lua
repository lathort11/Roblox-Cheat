--[[
    Advanced Optimized Cheat Engine v4.6.4 + MULTI-MODE NO RECOIL
    - Constant & Impulse (Pulse) movement modes
    - Classic & Smart Recoil calculation
    - Added Impulse Interval Settings (0/none support)
    - ADDED: Aimbot Smoothness Control & Button Fixes
]]

-- СЕРВИСЫ
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CoreGui = game:GetService("CoreGui")

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
}

-- ПЕРЕМЕННЫЕ СОСТОЯНИЯ ДЛЯ ИМПУЛЬСА
local LastImpulseTime = 0
local HasShotOnce = false

-- НАСТРОЙКИ
local Settings = {
    ESP = false,
    ESP_Names = false,
    NR_Mode = "Classic",
    MovementMode = "Constant", -- "Constant" или "Impulse"
    ImpulseInterval = 500,     -- Задержка в мс
    Aimbot = false,
    
    -- НОВЫЕ НАСТРОЙКИ NO RECOIL
    NoRecoil = false,
    RecoilStrength = 15,
    
    -- Настройки Aimbot
    AimbotFOV = 100,
    AimbotSmooth = 0.2, -- Плавность Аимбота
    WallCheck = true,
    ShowFOV = true,
    
    BoxColor = Color3.fromRGB(255, 50, 50),
    NameColor = Color3.fromRGB(255, 255, 255),
    FOVColor = Color3.fromRGB(255, 255, 255),
    MenuKey = Enum.KeyCode.RightControl
}

local Keybinds = {
    ESP = Enum.KeyCode.Y,
    Aimbot = Enum.KeyCode.N,
    NoRecoil = Enum.KeyCode.G,
    WallCheck = Enum.KeyCode.B,
    Unload = Enum.KeyCode.Delete
}

--// СОЗДАНИЕ FOV КРУГА //--
local FOVRing = Drawing.new("Circle")
FOVRing.Visible = false
FOVRing.Thickness = 1.5
FOVRing.Color = Settings.FOVColor
FOVRing.Filled = false
FOVRing.Radius = Settings.AimbotFOV
FOVRing.NumSides = 64
table.insert(CheatEnv.Drawings, FOVRing)

--// GUI СОЗДАНИЕ //--
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OptimizedCheatGUI_v46"
if gethui then ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then syn.protect_gui(ScreenGui) ScreenGui.Parent = CoreGui
else ScreenGui.Parent = CoreGui end
table.insert(CheatEnv.UI, ScreenGui)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 320, 0, 580) -- Увеличил высоту для новых настроек
MainFrame.Position = UDim2.new(0.5, -160, 0.5, -290)
MainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
MainFrame.BorderSizePixel = 0
MainFrame.Visible = true
MainFrame.Parent = ScreenGui

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 30)
Title.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
Title.Text = "  Aimbot & ESP Menu v4.6.4 + NR"
Title.TextColor3 = Color3.new(1,1,1)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.Parent = MainFrame

local MenuContainer = Instance.new("Frame")
MenuContainer.Size = UDim2.new(1, -20, 1, -40)
MenuContainer.Position = UDim2.new(0, 10, 0, 35)
MenuContainer.BackgroundTransparency = 1
MenuContainer.Parent = MainFrame

local UIList = Instance.new("UIListLayout")
UIList.Padding = UDim.new(0, 5)
UIList.Parent = MenuContainer

-- 2. KEYBIND LIST
local KeybindFrame = Instance.new("Frame")
KeybindFrame.Name = "KeybindList"
KeybindFrame.Position = UDim2.new(0.01, 0, 0.4, 0)
KeybindFrame.Size = UDim2.new(0, 150, 0, 0)
KeybindFrame.AutomaticSize = Enum.AutomaticSize.Y
KeybindFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
KeybindFrame.BackgroundTransparency = 0.5
KeybindFrame.BorderSizePixel = 0
KeybindFrame.Parent = ScreenGui

local KBListLayout = Instance.new("UIListLayout")
KBListLayout.SortOrder = Enum.SortOrder.LayoutOrder
KBListLayout.Parent = KeybindFrame

--// DRAG SYSTEM //--
local function MakeDraggable(frame, restrictionFunc)
    local dragging, dragInput, dragStart, startPos
    table.insert(CheatEnv.Connections, frame.InputBegan:Connect(function(input)
        if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            if restrictionFunc and not restrictionFunc() then return end
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
            if restrictionFunc and not restrictionFunc() then dragging = false return end
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
end
MakeDraggable(MainFrame, nil)
MakeDraggable(KeybindFrame, function() return MainFrame.Visible end)

--// UI HELPERS //--
local ActiveLabels = {}
local function UpdateKeybindDisplay(name, keyEnum, isEnabled)
    local id = name .. "_Bind"
    if isEnabled then
        if not ActiveLabels[id] then
            local Label = Instance.new("TextLabel")
            Label.Size = UDim2.new(1, 0, 0, 25)
            Label.BackgroundTransparency = 1
            Label.Text = string.format("[%s] %s", keyEnum.Name, name)
            Label.TextColor3 = Color3.new(1,1,1)
            Label.Font = Enum.Font.Gotham
            Label.Parent = KeybindFrame
            ActiveLabels[id] = Label
        end
    else
        if ActiveLabels[id] then ActiveLabels[id]:Destroy() ActiveLabels[id] = nil end
    end
end

local function AddButton(text, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 30)
    Btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    Btn.Text = text
    Btn.TextColor3 = Color3.new(1,1,1)
    Btn.Font = Enum.Font.Gotham
    Btn.Parent = MenuContainer
    Btn.MouseButton1Click:Connect(function()
        callback(Btn)
    end)
    return Btn
end

local function AddControl(text, valueGetter, onPlus, onMinus)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 30)
    Frame.BackgroundTransparency = 1
    Frame.Parent = MenuContainer
    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.5, 0, 1, 0)
    Label.BackgroundTransparency = 1
    Label.Text = text .. ": " .. valueGetter()
    Label.TextColor3 = Color3.new(1,1,1)
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Font = Enum.Font.Gotham
    Label.Parent = Frame
    local Minus = Instance.new("TextButton")
    Minus.Size = UDim2.new(0, 30, 1, 0)
    Minus.Position = UDim2.new(0.7, 0, 0, 0)
    Minus.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    Minus.Text = "-"
    Minus.Parent = Frame
    local Plus = Instance.new("TextButton")
    Plus.Size = UDim2.new(0, 30, 1, 0)
    Plus.Position = UDim2.new(0.85, 0, 0, 0)
    Plus.BackgroundColor3 = Color3.fromRGB(50, 200, 50)
    Plus.Text = "+"
    Plus.Parent = Frame
    local function UpdateText() Label.Text = text .. ": " .. valueGetter() end
    Minus.MouseButton1Click:Connect(function() onMinus() UpdateText() end)
    Plus.MouseButton1Click:Connect(function() onPlus() UpdateText() end)
end

--// NO RECOIL LOGIC (SHARP + IMPULSE) //--
local function ApplyNoRecoil(dt)
    if not Settings.NoRecoil then return end
    if not dt then dt = 1/60 end -- Предотвращение ошибки nil
    
    local isPressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    
    if not isPressed then
        HasShotOnce = false -- Сброс флага одиночного выстрела
        return
    end

    if mousemoverel then
        local shake = math.random(-1, 1)
        local currentTime = tick() * 1000 -- Время в миллисекундах
        
        -- Расчет силы движения (Classic vs Smart)
        local finalY = (Settings.NR_Mode == "Classic") and Settings.RecoilStrength or (Settings.RecoilStrength * (dt * 60))

        if Settings.MovementMode == "Constant" then
            -- ПОСТОЯННЫЙ РЕЖИМ
            mousemoverel(shake, finalY)
        else
            -- ИМПУЛЬСНЫЙ РЕЖИМ
            if Settings.ImpulseInterval <= 0 then
                -- Одиночное движение за нажатие
                if not HasShotOnce then
                    mousemoverel(shake, finalY)
                    HasShotOnce = true
                end
            else
                -- Повторяющееся движение через паузу
                if (currentTime - LastImpulseTime) >= Settings.ImpulseInterval then
                    mousemoverel(shake, finalY)
                    LastImpulseTime = currentTime
                end
            end
        end
    end
end

--// WALL CHECK LOGIC //--
local function IsVisible(targetPart, character)
    if not Settings.WallCheck then return true end
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    local origin = Camera.CFrame.Position
    local direction = (targetPart.Position - origin).Unit * (targetPart.Position - origin).Magnitude
    local raycastResult = Workspace:Raycast(origin, direction, rayParams)
    if raycastResult then
        if raycastResult.Instance:IsDescendantOf(character) then return true end
    end
    return false
end

--// ESP LOGIC //--
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
            ESP_Storage[player].Box:Remove()
            ESP_Storage[player].Tag:Remove()
        end)
        ESP_Storage[player] = nil
    end
end

local function UpdateESP()
    for _, data in pairs(ESP_Storage) do
        local plr = data.Player
        if Settings.ESP and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health > 0 then
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
                else
                    data.Tag.Visible = false
                end
            else 
                data.Box.Visible = false data.Tag.Visible = false
            end
        else 
            data.Box.Visible = false data.Tag.Visible = false
        end
    end
end

--// AIMBOT LOGIC //--
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

--// UNLOAD //--
local function UnloadScript()
    _G.CheatLoaded = false
    for i, conn in pairs(CheatEnv.Connections) do pcall(function() conn:Disconnect() end) end
    for i, drawing in pairs(CheatEnv.Drawings) do pcall(function() drawing:Remove() end) end
    for i, ui in pairs(CheatEnv.UI) do pcall(function() ui:Destroy() end) end
    for plr, _ in pairs(ESP_Storage) do RemoveESP(plr) end
    table.clear(ESP_Storage)
    warn("Чистая выгрузка завершена!")
end

--// МЕНЮ ЭЛЕМЕНТЫ //--
local function AddLabel(t) local l = Instance.new("TextLabel") l.Size=UDim2.new(1,0,0,20) l.BackgroundTransparency=1 l.Text=t l.TextColor3=Color3.fromRGB(150,150,150) l.Parent=MenuContainer end

AddLabel("-- Functions --")
AddButton("Toggle ESP [Y]", function() 
    Settings.ESP = not Settings.ESP 
    UpdateKeybindDisplay("ESP", Keybinds.ESP, Settings.ESP) 
end)

local NamesBtn = AddButton("ESP Names: " .. tostring(Settings.ESP_Names), function(self) 
    Settings.ESP_Names = not Settings.ESP_Names 
    self.Text = "ESP Names: " .. tostring(Settings.ESP_Names) 
end)

AddButton("Toggle Aimbot [N]", function() 
    Settings.Aimbot = not Settings.Aimbot 
    UpdateKeybindDisplay("Aimbot", Keybinds.Aimbot, Settings.Aimbot) 
end)

local NRBtn = AddButton("No Recoil [G]: OFF", function(self) 
    Settings.NoRecoil = not Settings.NoRecoil 
    self.Text = "No Recoil [G]: " .. (Settings.NoRecoil and "ON" or "OFF")
    UpdateKeybindDisplay("No Recoil", Keybinds.NoRecoil, Settings.NoRecoil)
end)

local NRModeBtn = AddButton("NR Mode: " .. Settings.NR_Mode, function(self) 
    Settings.NR_Mode = (Settings.NR_Mode == "Classic" and "Smart" or "Classic")
    self.Text = "NR Mode: " .. Settings.NR_Mode
end)

local MoveModeBtn = AddButton("Movement: " .. Settings.MovementMode, function(self) 
    Settings.MovementMode = (Settings.MovementMode == "Constant" and "Impulse" or "Constant")
    self.Text = "Movement: " .. Settings.MovementMode
end)

AddLabel("-- Settings --")

AddControl("Impulse MS", function() 
    return (Settings.ImpulseInterval <= 0 and "None" or tostring(Settings.ImpulseInterval)) 
end, 
function() Settings.ImpulseInterval = Settings.ImpulseInterval + 50 end,
function() Settings.ImpulseInterval = math.max(Settings.ImpulseInterval - 50, 0) end)

local WallCheckBtn = AddButton("Wall Check [B]: " .. tostring(Settings.WallCheck), function(self) 
    Settings.WallCheck = not Settings.WallCheck 
    self.Text = "Wall Check [B]: " .. tostring(Settings.WallCheck)
    UpdateKeybindDisplay("Wall Check", Keybinds.WallCheck, Settings.WallCheck)
end)

AddControl("FOV Radius", function() return tostring(Settings.AimbotFOV) end, 
    function() Settings.AimbotFOV = math.min(Settings.AimbotFOV + 10, 800) end,
    function() Settings.AimbotFOV = math.max(Settings.AimbotFOV - 10, 10) end
)

AddControl("Smoothness", function() return string.format("%.2f", Settings.AimbotSmooth) end,
    function() Settings.AimbotSmooth = math.min(Settings.AimbotSmooth + 0.05, 1) end,
    function() Settings.AimbotSmooth = math.max(Settings.AimbotSmooth - 0.05, 0.01) end
)

AddControl("NR Power", function() return tostring(Settings.RecoilStrength) end,
    function() Settings.RecoilStrength = Settings.RecoilStrength + 1 end,
    function() Settings.RecoilStrength = math.max(Settings.RecoilStrength - 1, 0) end
)

local UnloadBtn = AddButton("UNLOAD SCRIPT", UnloadScript)
UnloadBtn.BackgroundColor3 = Color3.fromRGB(150, 0, 0)

--// INIT //--
for _, v in pairs(Players:GetPlayers()) do if v ~= LocalPlayer then CreateESP(v) end end
table.insert(CheatEnv.Connections, Players.PlayerAdded:Connect(CreateESP))
table.insert(CheatEnv.Connections, Players.PlayerRemoving:Connect(RemoveESP))

table.insert(CheatEnv.Connections, UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Settings.MenuKey then 
        MainFrame.Visible = not MainFrame.Visible
    elseif input.KeyCode == Keybinds.ESP then 
        Settings.ESP = not Settings.ESP 
        UpdateKeybindDisplay("ESP", Keybinds.ESP, Settings.ESP)
    elseif input.KeyCode == Keybinds.Aimbot then 
        Settings.Aimbot = not Settings.Aimbot 
        UpdateKeybindDisplay("Aimbot", Keybinds.Aimbot, Settings.Aimbot)
    elseif input.KeyCode == Keybinds.NoRecoil then
        Settings.NoRecoil = not Settings.NoRecoil
        NRBtn.Text = "No Recoil [G]: " .. (Settings.NoRecoil and "ON" or "OFF")
        UpdateKeybindDisplay("No Recoil", Keybinds.NoRecoil, Settings.NoRecoil)
    elseif input.KeyCode == Keybinds.WallCheck then
        Settings.WallCheck = not Settings.WallCheck
        WallCheckBtn.Text = "Wall Check [B]: " .. tostring(Settings.WallCheck)
        UpdateKeybindDisplay("Wall Check", Keybinds.WallCheck, Settings.WallCheck)
    elseif input.KeyCode == Keybinds.Unload then 
        UnloadScript()
    end
end))

table.insert(CheatEnv.Connections, RunService.RenderStepped:Connect(function(dt)
    UpdateESP()
    UpdateAimbot()
    ApplyNoRecoil(dt)
end))

print("v4.6.4 FINAL Loaded. Smoothness and No-Nil logic active.")
