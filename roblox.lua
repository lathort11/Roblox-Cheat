--[[
	VAYS ENGINE v6.8 "CB MASTER UPDATE"

CHANGELOG v6.8: "CB MASTER UPDATE"
═══════════════════════════════════
★ NO FALL DAMAGE - Complete fall damage immunity
★ AUTO RESPAWN - Automatically respawn when dead
★ FREEZE SPRAY - Removes weapon recoil patterns completely
★ FORCE FULL AUTO - Makes all weapons fully automatic
★ VIEWMODEL CHANGER - X/Y/Z offset sliders
★ FIRE RATE MULTIPLIER - Slider 1-10x speed
★ RELOAD SPEED MULTIPLIER - Slider 1-10x speed
★ SPREAD MULTIPLIER - Slider 0-1 (0 = no spread)
★ IMPROVED WEAPON MODS - Better original value caching
★ MAX RANGE - Bullets travel infinite distance

PREVIOUS (v6.7):
✓ AimbotPart, Target Priority, Adaptive Smoothing
✓ Oval FOV, Target Indicator, FlickBot, Auto Switch
✓ Per-frame caching, Visibility cache, Prediction

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
local MarketplaceService = game:GetService("MarketplaceService")
local SharedRayParams = RaycastParams.new()
SharedRayParams.FilterType = Enum.RaycastFilterType.Exclude

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
    ToggleMeta = {},
    Dropdowns = {},
    UIConnections = {},
    UI_Elements = {}, -- [NEW] Для хранения ссылок на элементы UI (чтобы их блочить)
    KeybindChipRefs = {},
    RebindWindows = {},
    ActiveRebindCapture = nil,
    NoSpreadOriginals = {},
    WeaponModsDirty = false,
    AutoShotNextShot = 0,
    AutoShotState = {
        CurrentTarget = nil,
        StickyTarget = nil,
        StickyStartTime = 0,
        LastUpdate = 0,
        LastTargetSwap = 0,
        VisibilityUntil = setmetatable({}, { __mode = "k" })
    }
}

-- Keep camera reference updated (respawn / camera swap)
local function UpdateCamera()
    Camera = Workspace.CurrentCamera
end
UpdateCamera()
table.insert(CheatEnv.Connections, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(UpdateCamera))

-- ПЕРЕМЕННЫЕ

local LastImpulseTime = 0
local HasShotOnce = false
local AimlockEngaged = false
local AimlockEngagedFromGUI = false
local VelocityBuffers = {}
local PredictionStates = {}
local PredictionFrameCache = setmetatable({}, { __mode = "k" })
local WallStorage = {}
local OriginalWallProperties = {}
local CB_OriginalLighting = nil
local CB_OriginalCamera = nil
local CB_BombTimerLabel = nil
local RestoreCBVisuals, RestoreWalls, ApplyWeaponMods, ApplyCBVisuals

-- [NEW] Independent States for Aimbot and Aimlock
local AimbotState = {
    CurrentTarget = nil,
    StickyTarget = nil,
    StickyStartTime = 0,
    Engaged = false,
    RMBHeld = false,
    LastUpdate = 0,
    LastTargetSwap = 0,
    VisibilityUntil = setmetatable({}, { __mode = "k" })
}
local AimlockState = {
    CurrentTarget = nil,
    StickyTarget = nil,
    StickyStartTime = 0,
    LastUpdate = 0,
    Engaged = false,
    RMBHeld = false,
    LastTargetSwap = 0,
    VisibilityUntil = setmetatable({}, { __mode = "k" })
}

local v3_new = Vector3.new
local v2_new = Vector2.new
local math_random, math_clamp, math_sqrt, math_max, math_huge, math_exp = math.random, math.clamp, math.sqrt, math.max, math.huge, math.exp
local math_min, math_abs = math.min, math.abs

local TARGET_OCCLUSION_GRACE, TARGET_SWITCH_MARGIN, TARGET_CURRENT_BONUS, TARGET_STICKY_BONUS = 0.16, 0.18, 0.28, 0.16

local VisibilityCache = {}
local VISIBILITY_CACHE_TTL = 0.15                                       -- 150ms cache to cut repeated raycasts

-- [NEW v2] Prediction Engine Constants (single table to save local registers)
local PredConst = {
    RING_BUFFER_SIZE = 20,
    VELOCITY_MAX_AGE = 1.0,
    ANOMALY_SPEED_THRESHOLD = 500,
    ANOMALY_ACCEL_THRESHOLD = 800,
    PREDICTION_TIME_MAX = 2.5,
    RAYCAST_CLAMP_DISTANCE = 5,
    MIN_VELOCITY_THRESHOLD = 0.5,
    CONFIDENCE_DECAY_RATE = 3.0,
    ACCEL_SMOOTHING_ALPHA = 0.3,
    TIME_SOLVER_EPS = 0.001,
    KALMAN_MIN_DT = 1 / 240,
    KALMAN_MAX_DT = 0.2,
    KALMAN_RESET_TIMEOUT = 0.6,
    KALMAN_Q_BASE = 22,
    KALMAN_R_BASE = 0.55,
    MANEUVER_ACCEL_THRESHOLD = 110,
    MANEUVER_LATERAL_THRESHOLD = 125,
    MANEUVER_JERK_THRESHOLD = 900,
}
PredConst.ClampRayParams = RaycastParams.new()
PredConst.ClampRayParams.FilterType = Enum.RaycastFilterType.Exclude
local FrameTargetCache = { target = nil, tick = 0, fov = 0, part = "", ox = 0, oy = 0 }

-- ЦВЕТОВАЯ ПАЛИТРА (PREMIUM v2)

local Theme = {
    Background = Color3.fromRGB(8, 10, 18),
    Element = Color3.fromRGB(22, 28, 42),
    Panel = Color3.fromRGB(12, 16, 28),
    PanelSoft = Color3.fromRGB(18, 24, 36),
    Accent = Color3.fromRGB(0, 190, 255),
    AccentSoft = Color3.fromRGB(100, 220, 255),
    AccentSecondary = Color3.fromRGB(140, 80, 255),
    Text = Color3.fromRGB(240, 245, 255),
    TextDark = Color3.fromRGB(120, 140, 175),
    Glow = Color3.fromRGB(0, 200, 255),
    Stroke = Color3.fromRGB(40, 60, 100),
    Green = Color3.fromRGB(50, 240, 160),
    Disabled = Color3.fromRGB(35, 42, 58),
    Error = Color3.fromRGB(255, 70, 90),
    Warning = Color3.fromRGB(255, 190, 60),
    CardBg = Color3.fromRGB(16, 20, 34),
    CardBorder = Color3.fromRGB(35, 50, 80),
    GlowSoft = Color3.fromRGB(30, 80, 140)
}

local CurrentGameData = {
    name = "",
    placeId = 0,
    jobId = "",
    playerCount = 0,
    themeColor = Color3.fromRGB(0, 180, 255)
}

local MM2_Data = {
    PLACE_ID = 140300200285376,
    Roles = {},
    GunDrops = {},
    Hero = nil,
    IsMM2 = (game.PlaceId == 140300200285376)
}

-- НАСТРОЙКИ

local Settings = {
    ESP = false,
    ESP_Box = true,
    ESP_Names = false,
    ESP_Skeleton = false,
    ESP_HealthBar = false,
    ESP_HealthText = false,
    ESP_BoxFill = false,
    ESP_BoxFillTransparency = 0.5,
    ESP_Distance = false,
    ESP_Weapon = false,
    ESP_Tracers = false,    -- [NEW] Lines from bottom screen to player
    ESP_CornerBox = false,  -- [NEW] Corner style box instead of full
    ESP_Chams = false,
    ESP_ChamsVisibleOnly = true,
    ESP_MaxDistance = 1000, -- [NEW] Max render distance (studs)
    NR_Mode = "Classic",
    MovementMode = "Constant",
    ImpulseInterval = 500,
    Aimbot = false,
    NoRecoil = false,
    RecoilStrength = 15,
    AimbotFOV = 100,
    AimbotSmooth = 0.2,
    AimbotSmoothMode = "Old", -- Old / Mousemoverel
    AimbotMode = "Old",
    AimbotTrigger = "T Toggle", -- T Toggle / RMB Hold / RMB Toggle
    AimbotUpdateFPS = 30, -- Lower = smoother but slower response
    AutoShot = false,
    AutoShotDelay = 110, -- milliseconds between shots
    AimbotPart = "Head", -- [NEW] Target part for Aimbot
    WallCheck = true,
    ShowFOV = true,
    BoxColor = Color3.fromRGB(255, 50, 50),
    NameColor = Color3.fromRGB(255, 255, 255),
    DistanceColor = Color3.fromRGB(200, 200, 200), -- [NEW]
    WeaponColor = Color3.fromRGB(220, 220, 220),   -- [NEW]
    FOVColor = Color3.fromRGB(255, 255, 255),
    MenuKey = Enum.KeyCode.RightAlt,
    NonMovementClickGUI = false,
    KeybindsEnableLabel = false,
    UI_BlurParticles = false,
    UI_BP_Count = 26,
    UI_BP_Speed = 180,
    UI_BP_Size = 24,
    UI_BP_DirX = -1,
    UI_BP_DirY = 1,
    UI_BP_Blur = 10,

    Aimlock = false,
    AimlockSmooth = 0.5,
    AimlockSmoothMode = "Old", -- Old / Mousemoverel
    AimlockFOV = 90,
    ShowAimlockFOV = true, -- [NEW]
    AimlockPart = "Head",
    AimlockTrigger = "N Key", -- N Key / RMB Hold / RMB Toggle
    AimlockMode = "N Toggle",
    AimlockTargetMode = "Old", -- [UPDATED] Было Central -> Old
    AimlockUpdateFPS = 30, -- Lower = smoother but slower response
    AimlockForceStick = true, -- [NEW] Hard lock target while Aimlock is active

    -- [NEW] Humanization & Sticky Aim Settings
    Humanize = true,      -- Enable Bezier curves
    HumanizePower = 1.0,  -- Curve intensity
    ReactionTime = 0.05,  -- Simulated delay (seconds)
    StickyAim = true,     -- Stick to target
    StickyDuration = 1.0, -- How long to stick (seconds) ignoring better targets

    -- [NEW v6.7] Advanced Aimbot Features
    TargetPriority = "Crosshair", -- Crosshair / Health / Distance / Threat
    AdaptiveSmoothing = true,     -- Smoothing changes based on distance
    OvalFOV = false,              -- Aspect-ratio corrected FOV
    TargetIndicator = true,       -- Visual indicator on locked target
    FlickBot = false,             -- Instant flick to target
    FlickSpeed = 0.8,             -- Flick intensity (0.5-1.0)
    AutoSwitch = true,            -- Auto-switch when target dies

    PredictionEnabled = true,     -- [NEW] Toggle Prediction
    PredictionMode = "Standard",  -- [NEW] Standard / Smart
    PredictionFilter = "Adaptive Kalman", -- None / Kalman / Adaptive Kalman
    Prediction = 0.135,
    PredictionIterations = 4,
    PredictionConfidenceFloor = 0.12,
    KalmanProcessNoise = 1.0,
    KalmanMeasurementNoise = 1.0,
    ManeuverSensitivity = 1.0,
    Deadzone = 3,
    KnockedCheck = true,

    TC_Hide = false,
    TC_NoAim = true,
    TC_Green = false,
    Misc_Fullbright = false,          -- [NEW] Global fullbright (all games)
    Misc_FB_Brightness = 3,           -- [NEW] Fullbright brightness (1-5)
    Misc_FB_Exposure = 0.35,          -- [NEW] Fullbright exposure (-1 to 2)
    Misc_FB_DisableShadows = true,    -- [NEW] Disable shadows while fullbright is active
    -- [NEW v6.7] Баллистика
    BulletSpeed = 2200,
    BulletDrop = 0.4,
    VelocitySmoothing = true,
    AdaptivePrediction = true,
    PredictionMultiplier = 1.3,
    MM2_ESP_Player = false,
    MM2_ESP_Sheriff = false,
    MM2_ESP_Murder = false,
    MM2_ESP_Hero = false,
    MM2_ESP_GunDrop = false,
    NoSpread = false,
    WallShot = false,
    WallShotMode = "Aiming",          -- добавить после NoSpread
    WallShotMethod = "Hook (Silent)", -- [NEW] Bypass Method
    AdvancedTeamCheck = false,

    -- [NEW] CB Weapon Mods
    RapidFire = false,
    InstantReload = false,
    InfiniteAmmo = false,
    MaxPenetration = false,
    CounterStrafe = false, -- [NEW]
    ArmorPierce = false,
    NoFalloff = false,
    MaxRange = false,
    DamageMult = 1, -- 1 = Normal, can go up to 10

    -- [NEW v6.8] CB Master Features
    NoFallDamage = false,
    AutoRespawn = false,
    FreezeSpray = false,    -- Removes recoil pattern
    ForceFullAuto = false,  -- Makes all guns automatic
    ViewmodelX = 0,         -- Viewmodel offset X (-20 to 20)
    ViewmodelY = 0,         -- Viewmodel offset Y (-20 to 20)
    ViewmodelZ = 0,         -- Viewmodel offset Z (-20 to 20)
    FireRateMultiplier = 1, -- Fire rate multiplier (1 = normal, 10 = fastest)
    ReloadMultiplier = 1,   -- Reload speed multiplier (1 = normal, 10 = instant)
    SpreadMultiplier = 1,   -- Spread multiplier (0 = no spread, 1 = normal)

    -- [NEW v6.8] CB Visual Features
    CB_Fullbright = false,     -- Max brightness, no shadows
    CB_NoFog = false,          -- Remove fog/haze
    CB_NoBlur = false,         -- Disable blur effects
    CB_NightVision = false,    -- Green night vision effect
    CB_HighSaturation = false, -- Vibrant colors
    CB_NoSky = false,          -- Remove sky for better visibility
    CB_BombTimerESP = false,   -- Show bomb timer on screen
    CB_CustomBrightness = 1,   -- Brightness level (1-3)
    CB_CustomContrast = 0      -- Contrast level (-1 to 1)
}

local SharedHookState = _G.VAYS_HOOK_STATE
if type(SharedHookState) ~= "table" then
    SharedHookState = {
        active = false,
        settings = nil,
        getWallStorage = nil,
        fallRemote = nil,
        raycastInstalled = false,
        fallDamageInstalled = false
    }
    _G.VAYS_HOOK_STATE = SharedHookState
end

SharedHookState.active = true
SharedHookState.settings = Settings
SharedHookState.getWallStorage = function()
    return WallStorage
end

local MM2_Colors = {
    Player = Color3.fromRGB(255, 255, 255), -- White
    Sheriff = Color3.fromRGB(0, 100, 255),  -- Blue
    Murder = Color3.fromRGB(255, 0, 0),     -- Red
    Hero = Color3.fromRGB(255, 255, 0),     -- Yellow
    GunDrop = Color3.fromRGB(150, 0, 255)   -- Purple
}

local SCPRP_Teams = {
    MainDepartments = {
        ["Medical Department"] = true,
        ["Rapid Response Team"] = true,
        ["Mobile Task Force"] = true,
        ["Intelligence Agency"] = true,
        ["Administrative Department"] = true,
        ["Internal Security Department"] = true,
        ["Security Department"] = true,
        ["Scientific Department"] = true,
    },

    ThreatDepartments = {
        ["Class - D"] = true,
        ["Chaos Insurgency"] = true,
    }
}

-- [CONFIG SYSTEM] BACKEND

-- Forward declarations for functions used in ConfigSystem.Load
local SyncButton
local UpdateMM2Dependencies, UpdateTeamCheckDependencies, UpdateESPBoxDependencies, UpdatePredictionDependencies
local SetFrameState -- Forward declare
local ApplyClickGuiMovementState

local ConfigSystem = {
    Path = "VAYS/config/",
    DefaultConfigName = nil,
    LoadedConfigName = nil,
    DeleteMode = false,
    OverwriteMode = false,
    SelectedConfig = nil,
    UpdateUI = nil,     -- Placeholder for UI update function
    RefreshAllUI = nil, -- [NEW] Refresh all sliders/dropdowns
    Notify = nil,       -- [NEW] Notification function
    Defaults = {},
    Ranges = {
        AimbotFOV = { min = 10, max = 800 },
        AimbotSmooth = { min = 0.01, max = 1.0 },
        AimbotUpdateFPS = { min = 10, max = 240 },
        AutoShotDelay = { min = 10, max = 500 },
        AimlockFOV = { min = 10, max = 800 },
        AimlockSmooth = { min = 0.01, max = 1.0 },
        AimlockUpdateFPS = { min = 10, max = 240 },
        Prediction = { min = 0, max = 1 },
        PredictionIterations = { min = 1, max = 8 },
        PredictionConfidenceFloor = { min = 0, max = 0.8 },
        KalmanProcessNoise = { min = 0.1, max = 4.0 },
        KalmanMeasurementNoise = { min = 0.1, max = 4.0 },
        ManeuverSensitivity = { min = 0.5, max = 2.5 },
        Deadzone = { min = 0, max = 10 },
        RecoilStrength = { min = 0, max = 100 },
        BulletSpeed = { min = 100, max = 10000 },
        BulletDrop = { min = 0, max = 5 },
        HumanizePower = { min = 0.1, max = 10 },
        ReactionTime = { min = 0, max = 2.0 },
        StickyDuration = { min = 0, max = 5.0 },
        PredictionMultiplier = { min = 0.1, max = 5.0 },
        Misc_FB_Brightness = { min = 1, max = 5 },
        Misc_FB_Exposure = { min = -1, max = 2 },
        ImpulseInterval = { min = 0, max = 5000 },
        ESP_BoxFillTransparency = { min = 0, max = 1 },
        DamageMult = { min = 1, max = 10 },
        FlickSpeed = { min = 0.3, max = 1.0 },
        ViewmodelX = { min = -20, max = 20 },
        ViewmodelY = { min = -20, max = 20 },
        ViewmodelZ = { min = -20, max = 20 },
        FireRateMultiplier = { min = 1, max = 10 },
        ReloadMultiplier = { min = 1, max = 10 },
        SpreadMultiplier = { min = 0, max = 1 },
        CB_CustomBrightness = { min = 1, max = 3 },
        CB_CustomContrast = { min = -1, max = 1 },
        ESP_MaxDistance = { min = 100, max = 5000 },
        UI_BP_Count = { min = 8, max = 80 },
        UI_BP_Speed = { min = 20, max = 420 },
        UI_BP_Size = { min = 8, max = 52 },
        UI_BP_DirX = { min = -1, max = 1 },
        UI_BP_DirY = { min = -1, max = 1 },
        UI_BP_Blur = { min = 0, max = 30 }
    },
    -- [NEW] Valid dropdown options for validation
    DropdownOptions = {
        NR_Mode = { "Classic", "Smart" },
        MovementMode = { "Constant", "Impulse" },
        AimbotMode = { "Old", "Mousemoverel" },
        AimbotSmoothMode = { "Old", "Mousemoverel" },
        AimbotTrigger = { "T Toggle", "RMB Hold", "RMB Toggle" },
        AimbotPart = { "Head", "Neck", "Chest" },                         -- [NEW]
        TargetPriority = { "Crosshair", "Health", "Distance", "Threat" }, -- [NEW]
        AimlockPart = { "Head", "Neck", "Chest" },
        AimlockSmoothMode = { "Old", "Mousemoverel" },
        AimlockTrigger = { "N Key", "RMB Hold", "RMB Toggle" },
        AimlockTargetMode = { "Old", "Mousemoverel" },
        AimlockMode = { "N Toggle", "N Hold" },
        PredictionMode = { "Standard", "Smart" },
        PredictionFilter = { "None", "Kalman", "Adaptive Kalman" },
        WallShotMode = { "Aiming", "Whole Map", "On Click (L)" },
        WallShotMethod = { "Hook (Silent)", "Reparent (Remove)", "CanQuery (Soft)" }
    }
}

for k, v in pairs(Settings) do
    ConfigSystem.Defaults[k] = v
end

function ConfigSystem.EnsureFolder()
    if not isfolder or not makefolder then return end
    if not isfolder("VAYS") then makefolder("VAYS") end
    if not isfolder("VAYS/config") then makefolder("VAYS/config") end
end

function ConfigSystem.GetList()
    ConfigSystem.EnsureFolder()
    if not listfiles then return {} end
    local files = listfiles(ConfigSystem.Path)
    local configs = {}
    for _, path in ipairs(files) do
        if path:match("%.json$") then
            local name = path:match("[/\\]([^/\\]+)%.json$")
            if name then table.insert(configs, name) end
        end
    end
    table.sort(configs)
    return configs
end

function ConfigSystem.NormalizeName(name)
    if type(name) ~= "string" then
        return nil, "Invalid name type"
    end

    local normalized = name
    normalized = normalized:gsub("[\r\n\t]", " ")
    normalized = normalized:gsub("^%s+", ""):gsub("%s+$", "")
    normalized = normalized:gsub("[<>:\"/\\|%?%*]", "_")
    normalized = normalized:gsub("%s+", " ")
    normalized = normalized:gsub("%.+$", "")

    if normalized == "" then
        return nil, "Empty name"
    end

    if #normalized > 64 then
        normalized = normalized:sub(1, 64)
    end

    return normalized
end

function ConfigSystem.Serialize()
    local diff = {}
    for key, value in pairs(Settings) do
        if ConfigSystem.Defaults[key] ~= nil then
            local valType = typeof(value)

            if valType == "Color3" then
                local def = ConfigSystem.Defaults[key]
                if value.R ~= def.R or value.G ~= def.G or value.B ~= def.B then
                    diff[key] = { _type = "Color3", R = value.R, G = value.G, B = value.B }
                end
            elseif valType == "EnumItem" then
                -- [NEW] Serialize Enum items (like MenuKey)
                local def = ConfigSystem.Defaults[key]
                if value ~= def then
                    local enumTypeName = value.EnumType and value.EnumType.Name or tostring(value.EnumType)
                    diff[key] = { _type = "Enum", EnumType = enumTypeName, Name = value.Name }
                end
            elseif value ~= ConfigSystem.Defaults[key] then
                diff[key] = value
            end
        end
    end

    local success, result = pcall(function()
        return HttpService:JSONEncode(diff)
    end)

    if not success then
        warn("[Config] Serialize error: " .. tostring(result))
        return "{}"
    end

    return result
end

function ConfigSystem.Deserialize(jsonString)
    local success, data = pcall(function()
        return HttpService:JSONDecode(jsonString)
    end)
    if not success or type(data) ~= "table" then
        return nil, "Invalid JSON"
    end
    return data
end

function ConfigSystem.Validate(key, value)
    local defaultVal = ConfigSystem.Defaults[key]
    if defaultVal == nil then return nil end

    local valType = typeof(defaultVal)

    if valType == "boolean" then
        if type(value) ~= "boolean" then return defaultVal end
        return value
    elseif valType == "number" then
        if type(value) ~= "number" then return defaultVal end
        local range = ConfigSystem.Ranges[key]
        if range then
            value = math.clamp(value, range.min, range.max)
        end
        return value
    elseif valType == "string" then
        if type(value) ~= "string" then return defaultVal end
        if key == "AimbotTrigger" and value == "Always" then
            value = "T Toggle"
        end
        -- [NEW] Validate dropdown options
        local validOptions = ConfigSystem.DropdownOptions[key]
        if validOptions then
            local isValid = false
            for _, opt in ipairs(validOptions) do
                if opt == value then
                    isValid = true
                    break
                end
            end
            if not isValid then
                warn("[Config] Invalid dropdown value for " .. key .. ": " .. value)
                return defaultVal
            end
        end
        return value
    elseif valType == "Color3" then
        if type(value) == "table" then
            -- Support both old format and new format with _type
            if value.R and value.G and value.B then
                return Color3.new(
                    math.clamp(tonumber(value.R) or 0, 0, 1),
                    math.clamp(tonumber(value.G) or 0, 0, 1),
                    math.clamp(tonumber(value.B) or 0, 0, 1)
                )
            end
        end
        return defaultVal
    elseif valType == "EnumItem" then
        -- [NEW] Deserialize Enum items
        if type(value) == "table" and value._type == "Enum" then
            local enumTypeName = value.EnumType
            if type(enumTypeName) == "string" then
                enumTypeName = enumTypeName:gsub("^Enum%.", "")
            end
            local success, result = pcall(function()
                local enumType = Enum[enumTypeName]
                if enumType and value.Name then
                    return enumType[value.Name]
                end
            end)
            if success and result then
                return result
            end
        end
        return defaultVal
    end

    return defaultVal
end

function ConfigSystem.Save(name)
    ConfigSystem.EnsureFolder()
    if not writefile then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Файловая система недоступна",
                Color3.fromRGB(255, 80, 80))
        end
        return false
    end

    local normalizedName, nameErr = ConfigSystem.NormalizeName(name)
    if not normalizedName then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Некорректное имя конфига: " .. tostring(nameErr),
                Color3.fromRGB(255, 80, 80))
        end
        return false
    end
    name = normalizedName

    local json = ConfigSystem.Serialize()

    local success, err = pcall(function()
        writefile(ConfigSystem.Path .. name .. ".json", json)
    end)

    if not success then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Не удалось сохранить: " .. tostring(err),
                Color3.fromRGB(255, 80, 80))
        end
        return false
    end

    if ConfigSystem.UpdateUI then ConfigSystem.UpdateUI() end

    -- [NEW] Show notification
    if ConfigSystem.Notify then
        ConfigSystem.Notify("Конфиг сохранён", name, Color3.fromRGB(80, 255, 120))
    end

    return true
end

function ConfigSystem.Load(name)
    if not isfile then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Файловая система недоступна",
                Color3.fromRGB(255, 80, 80))
        end
        return false, "No file system"
    end

    local normalizedName, nameErr = ConfigSystem.NormalizeName(name)
    if not normalizedName then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Некорректное имя конфига: " .. tostring(nameErr),
                Color3.fromRGB(255, 80, 80))
        end
        return false, "Invalid name"
    end
    name = normalizedName

    local path = ConfigSystem.Path .. name .. ".json"
    if not isfile(path) then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Конфиг не найден: " .. name,
                Color3.fromRGB(255, 80, 80))
        end
        return false, "File not found"
    end

    local success, content = pcall(function()
        return readfile(path)
    end)

    if not success then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Не удалось прочитать файл",
                Color3.fromRGB(255, 80, 80))
        end
        return false, "Read error"
    end

    local data, err = ConfigSystem.Deserialize(content)
    if not data then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Повреждённый конфиг: " .. (err or "unknown"),
                Color3.fromRGB(255, 80, 80))
        end
        return false, err
    end

    -- Reset to defaults first
    for key, val in pairs(ConfigSystem.Defaults) do
        Settings[key] = val
    end

    -- Track what was loaded
    local loadedCount = 0

    -- Apply loaded (validated) values
    for key, val in pairs(data) do
        local validated = ConfigSystem.Validate(key, val)
        if validated ~= nil then
            Settings[key] = validated
            loadedCount = loadedCount + 1
        end
    end

    -- Sync UI toggles (with safety check)
    if SyncButton then
        for key, _ in pairs(CheatEnv.Toggles) do
            pcall(SyncButton, key)
        end
    end

    -- [NEW] Refresh all sliders and dropdowns
    if ConfigSystem.RefreshAllUI then
        pcall(ConfigSystem.RefreshAllUI)
    end

    -- Update dependencies (with safety check)
    if UpdateMM2Dependencies then pcall(UpdateMM2Dependencies) end
    if UpdateTeamCheckDependencies then pcall(UpdateTeamCheckDependencies) end
    if UpdateESPBoxDependencies then pcall(UpdateESPBoxDependencies) end
    if UpdatePredictionDependencies then pcall(UpdatePredictionDependencies) end
    if ApplyClickGuiMovementState then pcall(ApplyClickGuiMovementState) end
    if CheatEnv.UpdateKeybindList then pcall(CheatEnv.UpdateKeybindList) end
    if CheatEnv.ApplyBlurParticleState then pcall(CheatEnv.ApplyBlurParticleState, true) end

    ConfigSystem.LoadedConfigName = name
    if ConfigSystem.UpdateUI then ConfigSystem.UpdateUI() end

    -- [NEW] Show notification
    if ConfigSystem.Notify then
        ConfigSystem.Notify("Конфиг загружен", name .. " (" .. loadedCount .. " настроек)", Color3.fromRGB(80, 255, 120))
    end

    return true
end

function ConfigSystem.Delete(name)
    if not delfile then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Функция удаления недоступна",
                Color3.fromRGB(255, 80, 80))
        end
        return false
    end

    local normalizedName, nameErr = ConfigSystem.NormalizeName(name)
    if not normalizedName then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Некорректное имя конфига: " .. tostring(nameErr),
                Color3.fromRGB(255, 80, 80))
        end
        return false
    end
    name = normalizedName

    local path = ConfigSystem.Path .. name .. ".json"
    if isfile and isfile(path) then
        local success, err = pcall(function()
            delfile(path)
        end)

        if not success then
            if ConfigSystem.Notify then
                ConfigSystem.Notify("Ошибка", "Не удалось удалить: " .. tostring(err),
                    Color3.fromRGB(255, 80, 80))
            end
            return false
        end

        if ConfigSystem.LoadedConfigName == name then
            ConfigSystem.LoadedConfigName = nil
        end
        if ConfigSystem.DefaultConfigName == name then
            ConfigSystem.DefaultConfigName = nil
        end

        if ConfigSystem.UpdateUI then ConfigSystem.UpdateUI() end

        if ConfigSystem.Notify then
            ConfigSystem.Notify("Конфиг удалён", name, Color3.fromRGB(255, 180, 80))
        end
        return true
    end

    if ConfigSystem.Notify then ConfigSystem.Notify("Ошибка", "Конфиг не найден: " .. name, Color3.fromRGB(255, 80, 80)) end
    return false
end

function ConfigSystem.SetDefault(name)
    ConfigSystem.EnsureFolder()
    if not writefile then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Файловая система недоступна",
                Color3.fromRGB(255, 80, 80))
        end
        return
    end

    local normalizedName, nameErr = ConfigSystem.NormalizeName(name)
    if not normalizedName then
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Ошибка", "Некорректное имя конфига: " .. tostring(nameErr),
                Color3.fromRGB(255, 80, 80))
        end
        return
    end
    name = normalizedName

    local success = pcall(function()
        writefile(ConfigSystem.Path .. "default.txt", name)
    end)

    if success then
        ConfigSystem.DefaultConfigName = name
        if ConfigSystem.UpdateUI then ConfigSystem.UpdateUI() end
        if ConfigSystem.Notify then
            ConfigSystem.Notify("Дефолт установлен", name, Color3.fromRGB(120, 200, 255))
        end
    end
end

function ConfigSystem.GetDefault()
    ConfigSystem.EnsureFolder()
    if not isfile then return nil end
    local path = ConfigSystem.Path .. "default.txt"
    if isfile(path) then
        local ok, rawName = pcall(function()
            return readfile(path)
        end)
        if not ok then
            return nil
        end
        local normalizedName = ConfigSystem.NormalizeName(rawName)
        return normalizedName
    end
    return nil
end

-- БИНДЫ

local Keybinds = {
    { Name = "ESP",        Key = Enum.KeyCode.Y,      Setting = "ESP" },
    { Name = "Aimlock",    Key = Enum.KeyCode.N,      Setting = "Aimlock" },
    { Name = "Aimbot",     Key = Enum.KeyCode.T,      Setting = "Aimbot" },
    { Name = "No Recoil",  Key = Enum.KeyCode.G,      Setting = "NoRecoil" },
    { Name = "Wall Check", Key = Enum.KeyCode.B,      Setting = "WallCheck" },
    { Name = "Unload",     Key = Enum.KeyCode.Delete, Setting = "Unload" }
}

--// ФУНКЦИЯ ЗАГРУЗКИ ЛОГОТИПА //--

local function SetupLogoImage()
    if not isfolder or not makefolder or not writefile or not isfile or not getcustomasset then return nil end
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

local Drawing = Drawing or { new = function() return { Visible = false, Remove = function() end } end }

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
AimlockRing.Radius = Settings.AimlockFOV
AimlockRing.NumSides = 64
table.insert(CheatEnv.Drawings, AimlockRing)

-- [NEW] Target Indicator (Crosshair on locked target)
local TargetIndicator = {
    Circle = Drawing.new("Circle"),
    LineH = Drawing.new("Line"),
    LineV = Drawing.new("Line")
}
TargetIndicator.Circle.Visible = false
TargetIndicator.Circle.Thickness = 2
TargetIndicator.Circle.Color = Color3.fromRGB(255, 50, 50)
TargetIndicator.Circle.Filled = false
TargetIndicator.Circle.Radius = 8
TargetIndicator.Circle.NumSides = 16

TargetIndicator.LineH.Visible = false
TargetIndicator.LineH.Thickness = 1.5
TargetIndicator.LineH.Color = Color3.fromRGB(255, 50, 50)

TargetIndicator.LineV.Visible = false
TargetIndicator.LineV.Thickness = 1.5
TargetIndicator.LineV.Color = Color3.fromRGB(255, 50, 50)

table.insert(CheatEnv.Drawings, TargetIndicator.Circle)
table.insert(CheatEnv.Drawings, TargetIndicator.LineH)
table.insert(CheatEnv.Drawings, TargetIndicator.LineV)

local function UpdateTargetIndicator(screenPos, visible)
    if not Settings.TargetIndicator or not visible then
        TargetIndicator.Circle.Visible = false
        TargetIndicator.LineH.Visible = false
        TargetIndicator.LineV.Visible = false
        return
    end

    local x, y = screenPos.X, screenPos.Y
    local size = 12

    TargetIndicator.Circle.Position = Vector2.new(x, y)
    TargetIndicator.Circle.Visible = true

    TargetIndicator.LineH.From = Vector2.new(x - size, y)
    TargetIndicator.LineH.To = Vector2.new(x + size, y)
    TargetIndicator.LineH.Visible = true

    TargetIndicator.LineV.From = Vector2.new(x, y - size)
    TargetIndicator.LineV.To = Vector2.new(x, y + size)
    TargetIndicator.LineV.Visible = true
end

--// GUI ENGINE //--

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VAYSUI_v6.8"
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
if gethui then
    ScreenGui.Parent = gethui()
elseif syn and syn.protect_gui then
    syn.protect_gui(ScreenGui)
    ScreenGui.Parent = CoreGui
else
    ScreenGui.Parent = CoreGui
end
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

-- [NEW] NOTIFICATION SYSTEM
local NotificationContainer = Instance.new("Frame")
NotificationContainer.Name = "NotificationContainer"
NotificationContainer.Size = UDim2.new(0, 280, 1, 0)
NotificationContainer.Position = UDim2.new(1, -290, 0, 60)
NotificationContainer.BackgroundTransparency = 1
NotificationContainer.Parent = ScreenGui
NotificationContainer.ZIndex = 200

local NC_Layout = Instance.new("UIListLayout", NotificationContainer)
NC_Layout.SortOrder = Enum.SortOrder.LayoutOrder
NC_Layout.Padding = UDim.new(0, 8)
NC_Layout.VerticalAlignment = Enum.VerticalAlignment.Top

local NotificationQueue = {}
local CurrentLayoutOrder = 0

local function ShowNotification(title, message, color)
    color = color or Theme.Accent
    CurrentLayoutOrder = CurrentLayoutOrder + 1

    local Notif = Instance.new("Frame")
    Notif.Name = "Notification"
    Notif.Size = UDim2.new(1, 0, 0, 55)
    Notif.BackgroundColor3 = Color3.fromRGB(18, 18, 25)
    Notif.BackgroundTransparency = 0.1
    Notif.BorderSizePixel = 0
    Notif.Position = UDim2.new(1, 50, 0, 0) -- Start off-screen
    Notif.LayoutOrder = CurrentLayoutOrder
    Notif.Parent = NotificationContainer
    Notif.ZIndex = 201

    local N_Corner = Instance.new("UICorner", Notif)
    N_Corner.CornerRadius = UDim.new(0, 8)

    local N_Stroke = Instance.new("UIStroke", Notif)
    N_Stroke.Color = color
    N_Stroke.Thickness = 1.5
    N_Stroke.Transparency = 0.3

    -- Accent Bar
    local AccentBar = Instance.new("Frame", Notif)
    AccentBar.Size = UDim2.new(0, 4, 1, -8)
    AccentBar.Position = UDim2.new(0, 4, 0, 4)
    AccentBar.BackgroundColor3 = color
    AccentBar.BorderSizePixel = 0
    AccentBar.ZIndex = 202

    local AB_Corner = Instance.new("UICorner", AccentBar)
    AB_Corner.CornerRadius = UDim.new(0, 2)

    -- Title
    local TitleLabel = Instance.new("TextLabel", Notif)
    TitleLabel.Size = UDim2.new(1, -20, 0, 22)
    TitleLabel.Position = UDim2.new(0, 16, 0, 6)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = title
    TitleLabel.TextColor3 = color
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextSize = 14
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.ZIndex = 202

    -- Message
    local MsgLabel = Instance.new("TextLabel", Notif)
    MsgLabel.Size = UDim2.new(1, -20, 0, 18)
    MsgLabel.Position = UDim2.new(0, 16, 0, 28)
    MsgLabel.BackgroundTransparency = 1
    MsgLabel.Text = message
    MsgLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    MsgLabel.Font = Enum.Font.Gotham
    MsgLabel.TextSize = 12
    MsgLabel.TextXAlignment = Enum.TextXAlignment.Left
    MsgLabel.TextTruncate = Enum.TextTruncate.AtEnd
    MsgLabel.ZIndex = 202

    -- Animate in
    TweenService:Create(Notif, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0, 0, 0, 0)
    }):Play()

    -- Auto-hide after 3 seconds
    task.delay(3, function()
        local tweenOut = TweenService:Create(Notif, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(1, 50, 0, 0),
            BackgroundTransparency = 1
        })
        tweenOut:Play()
        tweenOut.Completed:Wait()
        Notif:Destroy()
    end)
end

-- Register notification function to ConfigSystem
ConfigSystem.Notify = ShowNotification

-- Add to UI for proper cleanup
table.insert(CheatEnv.UI, NotificationContainer)

-- ═══════════════════════════════════════════════════════════════
-- PREMIUM WATERMARK v8 — SINGLE-ROW AURORA
-- ═══════════════════════════════════════════════════════════════

local Watermark do
Watermark = Instance.new("Frame")
Watermark.Name = "Watermark"
Watermark.Size = UDim2.new(0, 0, 0, 42)
Watermark.Position = UDim2.new(0.01, 0, 0.01, 0)
Watermark.BackgroundColor3 = Color3.fromRGB(10, 12, 22)
Watermark.BackgroundTransparency = 0.05
Watermark.BorderSizePixel = 0
Watermark.Parent = ScreenGui
Watermark.AutomaticSize = Enum.AutomaticSize.X
Watermark.ZIndex = 100
Watermark.ClipsDescendants = true

local WM_Corner = Instance.new("UICorner", Watermark)
WM_Corner.CornerRadius = UDim.new(0, 10)

local WM_BgGradient = Instance.new("UIGradient", Watermark)
WM_BgGradient.Rotation = 90
WM_BgGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 22, 40)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(12, 14, 28)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 10, 20))
})

local WM_Stroke = Instance.new("UIStroke", Watermark)
WM_Stroke.Thickness = 1.2
WM_Stroke.Transparency = 0.2
WM_Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

local WM_StrokeGradient = Instance.new("UIGradient", WM_Stroke)
WM_StrokeGradient.Rotation = 0
WM_StrokeGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 200, 255)),
    ColorSequenceKeypoint.new(0.2, Color3.fromRGB(100, 120, 255)),
    ColorSequenceKeypoint.new(0.45, Color3.fromRGB(180, 80, 255)),
    ColorSequenceKeypoint.new(0.65, Color3.fromRGB(0, 255, 200)),
    ColorSequenceKeypoint.new(0.85, Color3.fromRGB(80, 180, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 200, 255))
})

local WM_TopLine = Instance.new("Frame")
WM_TopLine.Name = "AuroraLine"
WM_TopLine.Size = UDim2.new(1, 0, 0, 2)
WM_TopLine.Position = UDim2.new(0, 0, 0, 0)
WM_TopLine.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
WM_TopLine.BorderSizePixel = 0
WM_TopLine.ZIndex = 105
WM_TopLine.Parent = Watermark

local WM_TopGradient = Instance.new("UIGradient", WM_TopLine)
WM_TopGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 80, 255)),
    ColorSequenceKeypoint.new(0.25, Color3.fromRGB(0, 220, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 180)),
    ColorSequenceKeypoint.new(0.75, Color3.fromRGB(180, 80, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 80, 255))
})
WM_TopGradient.Rotation = 0

local WM_InnerGlow = Instance.new("Frame")
WM_InnerGlow.Name = "InnerGlow"
WM_InnerGlow.Size = UDim2.new(0.4, 0, 1, 0)
WM_InnerGlow.Position = UDim2.new(0, 0, 0, 0)
WM_InnerGlow.BackgroundColor3 = Color3.fromRGB(60, 40, 180)
WM_InnerGlow.BackgroundTransparency = 0.94
WM_InnerGlow.BorderSizePixel = 0
WM_InnerGlow.ZIndex = 101
WM_InnerGlow.Parent = Watermark

local IG_Gradient = Instance.new("UIGradient", WM_InnerGlow)
IG_Gradient.Rotation = 0
IG_Gradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.5),
    NumberSequenceKeypoint.new(0.6, 0.9),
    NumberSequenceKeypoint.new(1, 1)
})

-- ═══ SINGLE-ROW HORIZONTAL LAYOUT ═══
local WM_Content = Instance.new("Frame")
WM_Content.Name = "Content"
WM_Content.Size = UDim2.new(0, 0, 1, 0)
WM_Content.BackgroundTransparency = 1
WM_Content.AutomaticSize = Enum.AutomaticSize.X
WM_Content.Parent = Watermark
WM_Content.ZIndex = 102

local WM_Layout = Instance.new("UIListLayout", WM_Content)
WM_Layout.FillDirection = Enum.FillDirection.Horizontal
WM_Layout.VerticalAlignment = Enum.VerticalAlignment.Center
WM_Layout.Padding = UDim.new(0, 0)
WM_Layout.SortOrder = Enum.SortOrder.LayoutOrder

-- 1. Logo
local LogoWrap = Instance.new("Frame")
LogoWrap.Name = "LogoWrap"
LogoWrap.Size = UDim2.new(0, 56, 0, 48)
LogoWrap.BackgroundTransparency = 1
LogoWrap.BorderSizePixel = 0
LogoWrap.LayoutOrder = 1
LogoWrap.Parent = WM_Content
LogoWrap.ZIndex = 102

local LogoBox = Instance.new("Frame", LogoWrap)
LogoBox.Size = UDim2.new(0, 36, 0, 36)
LogoBox.Position = UDim2.new(0, 10, 0.5, 0)
LogoBox.AnchorPoint = Vector2.new(0, 0.5)
LogoBox.BackgroundColor3 = Color3.fromRGB(15, 18, 35)
LogoBox.BorderSizePixel = 0
LogoBox.ZIndex = 102

local LB_Corner = Instance.new("UICorner", LogoBox)
LB_Corner.CornerRadius = UDim.new(0, 8)

local LC_Stroke = Instance.new("UIStroke", LogoBox)
LC_Stroke.Thickness = 1.2
LC_Stroke.Transparency = 0.15
local LC_StrokeGrad = Instance.new("UIGradient", LC_Stroke)
LC_StrokeGrad.Rotation = 45
LC_StrokeGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 200, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(140, 80, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 255, 180))
})

local LogoDisplay = Instance.new("ImageLabel", LogoBox)
LogoDisplay.Size = UDim2.new(0.82, 0, 0.82, 0)
LogoDisplay.AnchorPoint = Vector2.new(0.5, 0.5)
LogoDisplay.Position = UDim2.new(0.5, 0, 0.5, 0)
LogoDisplay.BackgroundTransparency = 1
LogoDisplay.ScaleType = Enum.ScaleType.Fit
LogoDisplay.Image = LogoAssetId or "rbxassetid://18600022261"
LogoDisplay.ImageColor3 = Color3.fromRGB(255, 255, 255)
LogoDisplay.ZIndex = 103

local StatusDot = Instance.new("Frame", LogoBox)
StatusDot.Size = UDim2.new(0, 7, 0, 7)
StatusDot.Position = UDim2.new(1, -8, 0, 0)
StatusDot.BackgroundColor3 = Color3.fromRGB(80, 255, 160)
StatusDot.BorderSizePixel = 0
StatusDot.ZIndex = 106
Instance.new("UICorner", StatusDot).CornerRadius = UDim.new(1, 0)

local StatusRing = Instance.new("Frame", LogoBox)
StatusRing.Size = UDim2.new(0, 11, 0, 11)
StatusRing.Position = UDim2.new(1, -10, 0, -2)
StatusRing.BackgroundTransparency = 1
StatusRing.BorderSizePixel = 0
StatusRing.ZIndex = 105
Instance.new("UICorner", StatusRing).CornerRadius = UDim.new(1, 0)
local SR_Stroke = Instance.new("UIStroke", StatusRing)
SR_Stroke.Thickness = 1
SR_Stroke.Color = Color3.fromRGB(80, 255, 160)
SR_Stroke.Transparency = 0.5

-- 2. Title
local WM_TitleWrap = Instance.new("Frame")
WM_TitleWrap.Name = "TitleWrap"
WM_TitleWrap.Size = UDim2.new(0, 0, 1, 0)
WM_TitleWrap.AutomaticSize = Enum.AutomaticSize.X
WM_TitleWrap.BackgroundTransparency = 1
WM_TitleWrap.LayoutOrder = 2
WM_TitleWrap.Parent = WM_Content
WM_TitleWrap.ZIndex = 102

local WM_Title = Instance.new("TextLabel", WM_TitleWrap)
WM_Title.Name = "Title"
WM_Title.Size = UDim2.new(0, 0, 1, 0)
WM_Title.AutomaticSize = Enum.AutomaticSize.X
WM_Title.BackgroundTransparency = 1
WM_Title.Text = "<b>VAYS</b> <font color='rgb(80,200,255)'>v6.8</font>"
WM_Title.RichText = true
WM_Title.TextColor3 = Color3.fromRGB(235, 240, 255)
WM_Title.Font = Enum.Font.GothamBlack
WM_Title.TextSize = 14
WM_Title.TextXAlignment = Enum.TextXAlignment.Left
WM_Title.ZIndex = 103

-- 3. Divider
local WM_DivWrap = Instance.new("Frame")
WM_DivWrap.Name = "DivWrap"
WM_DivWrap.Size = UDim2.new(0, 14, 0, 22)
WM_DivWrap.BackgroundTransparency = 1
WM_DivWrap.LayoutOrder = 3
WM_DivWrap.Parent = WM_Content
WM_DivWrap.ZIndex = 102

local DivLine = Instance.new("Frame", WM_DivWrap)
DivLine.Size = UDim2.new(0, 1, 1, 0)
DivLine.Position = UDim2.new(0.5, 0, 0, 0)
DivLine.AnchorPoint = Vector2.new(0.5, 0)
DivLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
DivLine.BackgroundTransparency = 0.82
DivLine.BorderSizePixel = 0
DivLine.ZIndex = 102

-- 4. Stats pills
local WM_StatsRow = Instance.new("Frame")
WM_StatsRow.Name = "Stats"
WM_StatsRow.Size = UDim2.new(0, 0, 1, 0)
WM_StatsRow.AutomaticSize = Enum.AutomaticSize.X
WM_StatsRow.BackgroundTransparency = 1
WM_StatsRow.LayoutOrder = 4
WM_StatsRow.Parent = WM_Content
WM_StatsRow.ZIndex = 103

local WM_StatsLayout = Instance.new("UIListLayout", WM_StatsRow)
WM_StatsLayout.FillDirection = Enum.FillDirection.Horizontal
WM_StatsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
WM_StatsLayout.Padding = UDim.new(0, 5)
WM_StatsLayout.SortOrder = Enum.SortOrder.LayoutOrder

local WM_StatsRPad = Instance.new("UIPadding", WM_StatsRow)
WM_StatsRPad.PaddingRight = UDim.new(0, 12)

-- Pill factory
local function CreatePill(parent, bgColor, strokeColor, textColor, order)
    local Pill = Instance.new("Frame")
    Pill.Size = UDim2.new(0, 0, 0, 22)
    Pill.AutomaticSize = Enum.AutomaticSize.X
    Pill.BackgroundColor3 = bgColor
    Pill.BackgroundTransparency = 0.1
    Pill.BorderSizePixel = 0
    Pill.LayoutOrder = order or 0
    Pill.Parent = parent
    Pill.ZIndex = 103

    Instance.new("UICorner", Pill).CornerRadius = UDim.new(0, 6)

    local PillStroke = Instance.new("UIStroke", Pill)
    PillStroke.Thickness = 1
    PillStroke.Color = strokeColor
    PillStroke.Transparency = 0.65

    local PP = Instance.new("UIPadding", Pill)
    PP.PaddingLeft = UDim.new(0, 8)
    PP.PaddingRight = UDim.new(0, 8)

    local PL = Instance.new("UIListLayout", Pill)
    PL.FillDirection = Enum.FillDirection.Horizontal
    PL.VerticalAlignment = Enum.VerticalAlignment.Center
    PL.Padding = UDim.new(0, 5)
    PL.SortOrder = Enum.SortOrder.LayoutOrder

    -- Color dot
    local Dot = Instance.new("Frame")
    Dot.Size = UDim2.new(0, 5, 0, 5)
    Dot.BackgroundColor3 = strokeColor
    Dot.BorderSizePixel = 0
    Dot.LayoutOrder = 0
    Dot.Parent = Pill
    Dot.ZIndex = 104
    Instance.new("UICorner", Dot).CornerRadius = UDim.new(1, 0)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0, 0, 1, 0)
    Label.AutomaticSize = Enum.AutomaticSize.X
    Label.BackgroundTransparency = 1
    Label.Font = Enum.Font.GothamMedium
    Label.TextSize = 11
    Label.TextColor3 = textColor
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.LayoutOrder = 1
    Label.Parent = Pill
    Label.ZIndex = 104

    return Pill, Label, PillStroke, Dot
end

local playerName = LocalPlayer.Name or "Unknown"
local WM_PlayerPill, WM_PlayerText = CreatePill(
    WM_StatsRow, Color3.fromRGB(18, 22, 42), Color3.fromRGB(100, 140, 255), Color3.fromRGB(195, 210, 255), 1)
WM_PlayerText.Text = playerName

local WM_FpsPill, WM_FpsText, WM_FpsStroke, WM_FpsDot = CreatePill(
    WM_StatsRow, Color3.fromRGB(14, 34, 26), Color3.fromRGB(80, 240, 160), Color3.fromRGB(180, 255, 215), 2)
WM_FpsText.Text = "0 FPS"

local WM_PingPill, WM_PingText, WM_PingStroke, WM_PingDot = CreatePill(
    WM_StatsRow, Color3.fromRGB(22, 20, 40), Color3.fromRGB(140, 130, 255), Color3.fromRGB(205, 200, 255), 3)
WM_PingText.Text = "0ms"

local WM_TimePill, WM_TimeText = CreatePill(
    WM_StatsRow, Color3.fromRGB(16, 26, 40), Color3.fromRGB(80, 190, 255), Color3.fromRGB(175, 225, 255), 4)
WM_TimeText.Text = "00:00:00"

-- Color resolvers
local function ResolveFpsColors(fps)
    if fps >= 120 then
        return Color3.fromRGB(12, 42, 32), Color3.fromRGB(80, 255, 170), Color3.fromRGB(175, 255, 215)
    elseif fps >= 60 then
        return Color3.fromRGB(26, 40, 16), Color3.fromRGB(170, 235, 90), Color3.fromRGB(215, 250, 165)
    elseif fps >= 30 then
        return Color3.fromRGB(44, 35, 12), Color3.fromRGB(255, 195, 75), Color3.fromRGB(255, 225, 155)
    end
    return Color3.fromRGB(48, 18, 18), Color3.fromRGB(255, 105, 105), Color3.fromRGB(255, 180, 180)
end

local function ResolvePingColors(ping)
    if ping <= 40 then
        return Color3.fromRGB(12, 42, 32), Color3.fromRGB(80, 235, 165), Color3.fromRGB(175, 255, 215)
    elseif ping <= 85 then
        return Color3.fromRGB(36, 38, 16), Color3.fromRGB(225, 220, 105), Color3.fromRGB(250, 240, 175)
    elseif ping <= 140 then
        return Color3.fromRGB(46, 35, 14), Color3.fromRGB(255, 180, 85), Color3.fromRGB(255, 220, 160)
    end
    return Color3.fromRGB(48, 18, 18), Color3.fromRGB(255, 105, 105), Color3.fromRGB(255, 180, 180)
end

local function AnimatePillText(label)
    label.TextTransparency = 0.5
    TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        TextTransparency = 0
    }):Play()
end

-- Stats updater
local function UpdateWM()
    local lastTime = tick()
    local frameCount = 0
    local lastFps, lastPing, lastClock = -1, -1, ""

    table.insert(CheatEnv.Connections, RunService.RenderStepped:Connect(function()
        frameCount = frameCount + 1
        if tick() - lastTime >= 1 then
            local fps = frameCount
            frameCount = 0
            lastTime = tick()

            local ping = math.floor((LocalPlayer:GetNetworkPing() or 0) * 1000 + 0.5)
            local nowClock = os.date("%H:%M:%S")

            WM_FpsText.Text = string.format("%d FPS", fps)
            WM_PingText.Text = string.format("%dms", ping)
            WM_TimeText.Text = nowClock

            local fpsBg, fpsStroke, fpsTxt = ResolveFpsColors(fps)
            TweenService:Create(WM_FpsPill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {BackgroundColor3 = fpsBg}):Play()
            WM_FpsStroke.Color = fpsStroke
            WM_FpsText.TextColor3 = fpsTxt
            if WM_FpsDot then WM_FpsDot.BackgroundColor3 = fpsStroke end

            local pingBg, pingStroke, pingTxt = ResolvePingColors(ping)
            TweenService:Create(WM_PingPill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {BackgroundColor3 = pingBg}):Play()
            WM_PingStroke.Color = pingStroke
            WM_PingText.TextColor3 = pingTxt
            if WM_PingDot then WM_PingDot.BackgroundColor3 = pingStroke end

            if fps ~= lastFps then AnimatePillText(WM_FpsText); lastFps = fps end
            if ping ~= lastPing then AnimatePillText(WM_PingText); lastPing = ping end
            if nowClock ~= lastClock then AnimatePillText(WM_TimeText); lastClock = nowClock end
        end
    end))
end
UpdateWM()

-- Entrance animation
Watermark.Position = UDim2.new(0.01, 0, -0.03, 0)
Watermark.BackgroundTransparency = 1
WM_Stroke.Transparency = 1
WM_TopLine.BackgroundTransparency = 1

task.delay(0.15, function()
    TweenService:Create(Watermark, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.01, 0, 0.01, 0), BackgroundTransparency = 0.05
    }):Play()
    TweenService:Create(WM_Stroke, TweenInfo.new(0.4, Enum.EasingStyle.Quad), {Transparency = 0.2}):Play()
    TweenService:Create(WM_TopLine, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {BackgroundTransparency = 0}):Play()
end)

-- Continuous animations
task.spawn(function()
    local t1 = TweenService:Create(WM_StrokeGradient,
        TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Offset = Vector2.new(1, 0) })
    local t2 = TweenService:Create(WM_TopGradient,
        TweenInfo.new(2.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Offset = Vector2.new(1, 0) })
    local t3 = TweenService:Create(LC_StrokeGrad,
        TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 405 })
    t1:Play() t2:Play() t3:Play()

    while _G.CheatLoaded do
        local a1 = TweenService:Create(WM_Stroke, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.45})
        local a2 = TweenService:Create(LC_Stroke, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.5})
        local a3 = TweenService:Create(SR_Stroke, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.85})
        local a4 = TweenService:Create(WM_InnerGlow, TweenInfo.new(2.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0.97})
        a1:Play() a2:Play() a3:Play() a4:Play()
        a1.Completed:Wait()
        if not _G.CheatLoaded then break end

        local b1 = TweenService:Create(WM_Stroke, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.2})
        local b2 = TweenService:Create(LC_Stroke, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.15})
        local b3 = TweenService:Create(SR_Stroke, TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Transparency = 0.5})
        local b4 = TweenService:Create(WM_InnerGlow, TweenInfo.new(2.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {BackgroundTransparency = 0.94})
        b1:Play() b2:Play() b3:Play() b4:Play()
        b1.Completed:Wait()
    end
    t1:Cancel() t2:Cancel() t3:Cancel()
end)
end



--// GAME TAG COMPONENT //--

local function CreateGameTag()
    -- Основной контейнер (сильно прозрачный черный фон)
    local GameTag = Instance.new("Frame")
    GameTag.Name = "GameTag"
    GameTag.Size = UDim2.new(0, 475, 0, 96)
    GameTag.Position = UDim2.new(1, -1900, 0, 750)
    GameTag.BackgroundColor3 = Color3.fromRGB(0, 0, 0) -- Черный фон
    GameTag.BackgroundTransparency = 0.7               -- Сильно прозрачный (30% видимости)
    GameTag.BorderSizePixel = 0
    GameTag.ClipsDescendants = false
    GameTag.Parent = ScreenGui
    GameTag.ZIndex = 50
    GameTag.Visible = false -- Скрыт по умолчанию

    local GT_Corner = Instance.new("UICorner", GameTag)
    GT_Corner.CornerRadius = UDim.new(0, 12)

    -- Layout (flex-direction: row)
    local GT_Layout = Instance.new("UIListLayout", GameTag)
    GT_Layout.FillDirection = Enum.FillDirection.Horizontal
    GT_Layout.Padding = UDim.new(0, 16)
    GT_Layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    GT_Layout.VerticalAlignment = Enum.VerticalAlignment.Center

    local GT_Padding = Instance.new("UIPadding", GameTag)
    GT_Padding.PaddingLeft = UDim.new(0, 16)
    GT_Padding.PaddingRight = UDim.new(0, 16)

    -- Иконка игры (96×96, rounded-2xl)
    local GameIcon = Instance.new("ImageLabel")
    GameIcon.Name = "GameIcon"
    GameIcon.Size = UDim2.new(0, 96, 0, 96)
    GameIcon.BackgroundTransparency = 1
    GameIcon.ScaleType = Enum.ScaleType.Crop
    GameIcon.Parent = GameTag

    local Icon_Corner = Instance.new("UICorner", GameIcon)
    Icon_Corner.CornerRadius = UDim.new(0, 16)

    -- Подсветка иконки цветом темы
    local Icon_Glow = Instance.new("UIStroke", GameIcon)
    Icon_Glow.Thickness = 4
    Icon_Glow.Color = Theme.Accent
    Icon_Glow.Transparency = 0.6

    -- Контейнер для текста
    local InfoContainer = Instance.new("Frame")
    InfoContainer.Name = "InfoContainer"
    InfoContainer.Size = UDim2.new(1, -112, 1, 0)
    InfoContainer.BackgroundTransparency = 1
    InfoContainer.Parent = GameTag

    local Info_Layout = Instance.new("UIListLayout", InfoContainer)
    Info_Layout.FillDirection = Enum.FillDirection.Vertical
    Info_Layout.Padding = UDim.new(0, 6)
    Info_Layout.VerticalAlignment = Enum.VerticalAlignment.Center

    -- Хранилище для доступа к полям
    local rows = {}

    -- Создание обычной строки
    local function CreateRow(labelText)
        local Row = Instance.new("Frame")
        Row.Size = UDim2.new(1, 0, 0, 20)
        Row.BackgroundTransparency = 1
        Row.Parent = InfoContainer

        local Label = Instance.new("TextLabel")
        Label.Name = "Label"
        Label.Size = UDim2.new(0.25, 0, 1, 0)
        Label.BackgroundTransparency = 1
        Label.Text = labelText .. ":"
        Label.Font = Enum.Font.Gotham
        Label.TextSize = 14
        Label.TextColor3 = Color3.fromRGB(107, 114, 128)
        Label.TextXAlignment = Enum.TextXAlignment.Left
        Label.Parent = Row

        local Value = Instance.new("TextLabel")
        Value.Name = "Value"
        Value.Size = UDim2.new(0.75, 0, 1, 0)
        Value.Position = UDim2.new(0.25, 0, 0, 0)
        Value.BackgroundTransparency = 1
        Value.Text = ""
        Value.Font = Enum.Font.GothamMedium
        Value.TextSize = 14
        Value.TextColor3 = Color3.fromRGB(255, 255, 255)
        Value.TextXAlignment = Enum.TextXAlignment.Left
        Value.Parent = Row

        rows[labelText] = { Row = Row, Label = Label, Value = Value }
    end

    -- Создание player row с меткой "Player:"
    local function CreatePlayerRow()
        local Row = Instance.new("Frame")
        Row.Name = "player"
        Row.Size = UDim2.new(1, 0, 0, 20)
        Row.BackgroundTransparency = 1
        Row.Parent = InfoContainer

        -- Метка "Player:"
        local PlayerLabel = Instance.new("TextLabel")
        PlayerLabel.Name = "PlayerLabel"
        PlayerLabel.Size = UDim2.new(0.25, 0, 1, 0)
        PlayerLabel.BackgroundTransparency = 1
        PlayerLabel.Text = "Player:"
        PlayerLabel.Font = Enum.Font.Gotham
        PlayerLabel.TextSize = 14
        PlayerLabel.TextColor3 = Color3.fromRGB(107, 114, 128)
        PlayerLabel.TextXAlignment = Enum.TextXAlignment.Left
        PlayerLabel.Parent = Row

        -- Контейнер для иконки и числа
        local PlayerValueContainer = Instance.new("Frame")
        PlayerValueContainer.Name = "PlayerValueContainer"
        PlayerValueContainer.Size = UDim2.new(0.75, 0, 1, 0)
        PlayerValueContainer.Position = UDim2.new(0.25, 0, 0, 0)
        PlayerValueContainer.BackgroundTransparency = 1
        PlayerValueContainer.Parent = Row

        local PVC_Layout = Instance.new("UIListLayout", PlayerValueContainer)
        PVC_Layout.FillDirection = Enum.FillDirection.Horizontal
        PVC_Layout.Padding = UDim.new(0, 6)

        -- Иконка
        local Icon = Instance.new("ImageLabel")
        Icon.Name = "Icon"
        Icon.Size = UDim2.new(0, 14, 0, 14)
        Icon.BackgroundTransparency = 1
        Icon.Image = "rbxassetid://18600022261"
        Icon.Parent = PlayerValueContainer

        -- Число игроков
        local PlayerValue = Instance.new("TextLabel")
        PlayerValue.Name = "PlayerValue"
        PlayerValue.Size = UDim2.new(0, 100, 1, 0)
        PlayerValue.BackgroundTransparency = 1
        PlayerValue.Text = "0"
        PlayerValue.Font = Enum.Font.GothamBold
        PlayerValue.TextSize = 14
        PlayerValue.TextColor3 = Color3.fromRGB(255, 255, 255)
        PlayerValue.TextXAlignment = Enum.TextXAlignment.Left
        PlayerValue.Parent = PlayerValueContainer

        rows["player"] = { Row = Row, Icon = Icon, PlayerLabel = PlayerLabel, PlayerValue = PlayerValue }
    end

    -- Создаем строки
    CreateRow("game")
    CreateRow("id")
    CreateRow("job-id")
    CreatePlayerRow()

    return GameTag, rows
end

local GameTag, GameTagRows = CreateGameTag()

-- Функция обновления данных
local function UpdateGameTag()
    local playerCount = #Players:GetPlayers()
    GameTagRows["player"].PlayerValue.Text = tostring(playerCount)
    GameTagRows["id"].Value.Text = tostring(game.PlaceId)
    GameTagRows["job-id"].Value.Text = game.JobId or "N/A"

    if (not CurrentGameData.infoCache) or (tick() - (CurrentGameData.infoCacheAt or 0) >= 60) then
        local success, info = pcall(function()
            return MarketplaceService:GetProductInfo(game.PlaceId)
        end)
        CurrentGameData.infoCacheAt = tick()
        if success and info then
            CurrentGameData.infoCache = info
        end
    end

    if CurrentGameData.infoCache then
        local info = CurrentGameData.infoCache
        GameTagRows["game"].Value.Text = info.Name or "Unknown"
        if info.IconImageAssetId then
            GameTag.GameIcon.Image = "rbxassetid://" .. info.IconImageAssetId
        end
    else
        GameTagRows["game"].Value.Text = "Game #" .. game.PlaceId
    end
end

-- Загрузка иконки users
local function LoadUsersIcon()
    if not isfolder or not makefolder or not writefile or not isfile or not getcustomasset then return end

    local folderPath = "VAYS/icons"
    local filePath = folderPath .. "/users.png"
    local url = "https://raw.githubusercontent.com/lathort11/Roblox-Cheat/main/users.png"

    if not isfolder("VAYS") then makefolder("VAYS") end
    if not isfolder(folderPath) then makefolder(folderPath) end

    if not isfile(filePath) then
        local success, content = pcall(function() return game:HttpGet(url) end)
        if success then writefile(filePath, content) end
    end

    local success, assetId = pcall(function() return getcustomasset(filePath) end)
    if success then
        GameTagRows["player"].Icon.Image = assetId
    end
end

LoadUsersIcon()

-- Обновляем каждые 5 секунд
task.spawn(function()
    while _G.CheatLoaded do
        UpdateGameTag()
        task.wait(5)
    end
end)

UpdateGameTag()

--// WELCOME & SESSION TIME LABELS //--

local SessionStartTime = tick()

local function FormatSessionTime()
    local elapsed = tick() - SessionStartTime
    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    local seconds = math.floor(elapsed % 60)
    return string.format("%d:%02d:%02d", hours, minutes, seconds)
end

-- Приветствие сверху (самый верх)
local WelcomeLabel = Instance.new("TextLabel")
WelcomeLabel.Name = "WelcomeLabel"
WelcomeLabel.Size = UDim2.new(0, 0, 0, 25)
WelcomeLabel.Position = UDim2.new(0.5, 0, 0, 10) -- ❗ Самый верх
WelcomeLabel.AnchorPoint = Vector2.new(0.5, 0)
WelcomeLabel.BackgroundTransparency = 1
WelcomeLabel.Text = string.format("Yo %s, welcome to Vays Cheat", LocalPlayer.Name or "Player") -- ❗ Убран смайлик
WelcomeLabel.Font = Enum.Font.GothamBold
WelcomeLabel.TextSize = 20                                                                      -- ❗ Уменьшен текст
WelcomeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
WelcomeLabel.TextStrokeTransparency = 0.5
WelcomeLabel.Visible = false -- ❗ Только в GUI
WelcomeLabel.Parent = ScreenGui
WelcomeLabel.ZIndex = 100
table.insert(CheatEnv.UI, WelcomeLabel)

-- Время сессии снизу (самый низ)
local SessionLabel = Instance.new("TextLabel")
SessionLabel.Name = "SessionLabel"
SessionLabel.Size = UDim2.new(0, 0, 0, 20)
SessionLabel.Position = UDim2.new(0.5, 0, 1, -20) -- ❗ Самый низ
SessionLabel.AnchorPoint = Vector2.new(0.5, 1)
SessionLabel.BackgroundTransparency = 1
SessionLabel.Text = "You're already playing: 0:00:00" -- ❗ Формат с секундами
SessionLabel.Font = Enum.Font.GothamMedium
SessionLabel.TextSize = 14                            -- ❗ Уменьшен текст
SessionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
SessionLabel.TextStrokeTransparency = 0.7
SessionLabel.Visible = false -- ❗ Только в GUI
SessionLabel.Parent = ScreenGui
SessionLabel.ZIndex = 100
table.insert(CheatEnv.UI, SessionLabel)

-- Обновление времени каждую секунду
task.spawn(function()
    while _G.CheatLoaded do
        SessionLabel.Text = "You're already playing: " .. FormatSessionTime()
        task.wait(1)
    end
end)

-- 2. KEYBIND LIST PANEL (Modern Glassmorphism Design)

-- Color scheme for different functions
local KeybindColors = {
    ESP = Color3.fromRGB(0, 255, 136),        -- Green
    Aimbot = Color3.fromRGB(0, 212, 255),     -- Cyan
    Aimlock = Color3.fromRGB(255, 136, 0),    -- Orange
    NoRecoil = Color3.fromRGB(170, 0, 255),   -- Purple
    WallCheck = Color3.fromRGB(255, 221, 0),  -- Yellow
    Default = Theme.Accent                     -- Fallback
}

local KeybindIcons = {
    ESP = "👁️",
    Aimbot = "🎯",
    Aimlock = "🔒",
    NoRecoil = "🔫",
    WallCheck = "🧱",
    Default = "⚡"
}

local KeybindFrame = Instance.new("Frame")
KeybindFrame.Name = "KeybindFrame"
KeybindFrame.BackgroundColor3 = Color3.fromRGB(12, 16, 28)
KeybindFrame.BackgroundTransparency = 0.02
KeybindFrame.BorderSizePixel = 0
KeybindFrame.ClipsDescendants = true
KeybindFrame.Size = UDim2.new(0, 256, 0, 0)
KeybindFrame.Position = UDim2.new(0, 14, 0, 76)
KeybindFrame.ZIndex = 60
KeybindFrame.Visible = false
KeybindFrame.Parent = ScreenGui
table.insert(CheatEnv.UI, KeybindFrame)

local KB_Corner = Instance.new("UICorner", KeybindFrame)
KB_Corner.CornerRadius = UDim.new(0, 10)

local KB_Stroke = Instance.new("UIStroke", KeybindFrame)
KB_Stroke.Color = Theme.Stroke
KB_Stroke.Thickness = 1.15
KB_Stroke.Transparency = 0.1

CheatEnv.UI_Elements["KeybindGlowStroke"] = Instance.new("UIStroke", KeybindFrame)
CheatEnv.UI_Elements["KeybindGlowStroke"].Color = Theme.Accent
CheatEnv.UI_Elements["KeybindGlowStroke"].Thickness = 2
CheatEnv.UI_Elements["KeybindGlowStroke"].Transparency = 0.84
CheatEnv.UI_Elements["KeybindGlowStroke"].ApplyStrokeMode = Enum.ApplyStrokeMode.Border

CheatEnv.UI_Elements["KeybindGradient"] = Instance.new("UIGradient", KeybindFrame)
CheatEnv.UI_Elements["KeybindGradient"].Rotation = 122
CheatEnv.UI_Elements["KeybindGradient"].Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 28, 46)),
    ColorSequenceKeypoint.new(0.55, Color3.fromRGB(12, 16, 28)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 10, 18))
})

local KB_List = Instance.new("UIListLayout", KeybindFrame)
KB_List.SortOrder = Enum.SortOrder.LayoutOrder
KB_List.Padding = UDim.new(0, 6)
KB_List.HorizontalAlignment = Enum.HorizontalAlignment.Center

local KB_Padding = Instance.new("UIPadding", KeybindFrame)
KB_Padding.PaddingTop = UDim.new(0, 10)
KB_Padding.PaddingBottom = UDim.new(0, 10)
KB_Padding.PaddingLeft = UDim.new(0, 10)
KB_Padding.PaddingRight = UDim.new(0, 10)

-- 3. MAIN MENU

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 1100, 0, 700)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
MainFrame.BackgroundColor3 = Theme.Background
MainFrame.BackgroundTransparency = 0.01
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Visible = true
MainFrame:SetAttribute("UserMoved", false)
MainFrame.Parent = ScreenGui

local SideBar, ContentArea
do
local MainCorner = Instance.new("UICorner", MainFrame)
MainCorner.CornerRadius = UDim.new(0, 12)

local MainStroke = Instance.new("UIStroke", MainFrame)
MainStroke.Thickness = 1.2
MainStroke.Transparency = 0.15

-- Gradient stroke (cyan → purple → cyan)
local MainStrokeGrad = Instance.new("UIGradient", MainStroke)
MainStrokeGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 190, 255)),
    ColorSequenceKeypoint.new(0.35, Color3.fromRGB(80, 60, 200)),
    ColorSequenceKeypoint.new(0.65, Color3.fromRGB(140, 80, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 190, 255))
})

local MainGradient = Instance.new("UIGradient", MainFrame)
MainGradient.Rotation = 135
MainGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 16, 28)),
    ColorSequenceKeypoint.new(0.4, Color3.fromRGB(8, 11, 20)),
    ColorSequenceKeypoint.new(0.7, Color3.fromRGB(6, 9, 16)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 6, 12))
})

local MainGlow = Instance.new("UIStroke", MainFrame)
MainGlow.Color = Theme.Accent
MainGlow.Thickness = 2
MainGlow.Transparency = 0.82
MainGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

SideBar = Instance.new("Frame")
SideBar.Size = UDim2.new(0, 210, 1, -24)
SideBar.Position = UDim2.new(0, 12, 0, 12)
SideBar.BackgroundColor3 = Theme.Panel
SideBar.BackgroundTransparency = 0.06
SideBar.BorderSizePixel = 0
SideBar.Parent = MainFrame

local SB_Corner = Instance.new("UICorner", SideBar)
SB_Corner.CornerRadius = UDim.new(0, 10)

local SB_Gradient = Instance.new("UIGradient", SideBar)
SB_Gradient.Rotation = 100
SB_Gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 24, 40)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(12, 16, 30)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 12, 24))
})

local TabList = Instance.new("UIListLayout", SideBar)
TabList.Padding = UDim.new(0, 6)
TabList.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabList.SortOrder = Enum.SortOrder.LayoutOrder

local TabPadding = Instance.new("UIPadding", SideBar)
TabPadding.PaddingTop = UDim.new(0, 12)
TabPadding.PaddingLeft = UDim.new(0, 10)
TabPadding.PaddingRight = UDim.new(0, 10)
TabPadding.PaddingBottom = UDim.new(0, 10)

local Logo
if LogoAssetId then
    Logo = Instance.new("ImageLabel")
    Logo.Name = "LogoImage"
    Logo.LayoutOrder = 1
    Logo.Size = UDim2.new(1, -16, 0, 80)
    Logo.BackgroundTransparency = 1
    Logo.Image = LogoAssetId
    Logo.ScaleType = Enum.ScaleType.Fit
    Logo.Parent = SideBar
else
    -- Logo container
    local LogoHolder = Instance.new("Frame")
    LogoHolder.Name = "LogoHolder"
    LogoHolder.LayoutOrder = 1
    LogoHolder.Size = UDim2.new(1, -16, 0, 76)
    LogoHolder.BackgroundTransparency = 1
    LogoHolder.Parent = SideBar

    Logo = Instance.new("TextLabel")
    Logo.Name = "LogoText"
    Logo.Size = UDim2.new(1, 0, 0, 38)
    Logo.Position = UDim2.new(0, 0, 0, 10)
    Logo.Text = "VAYS"
    Logo.TextColor3 = Theme.Accent
    Logo.Font = Enum.Font.GothamBlack
    Logo.TextSize = 26
    Logo.BackgroundTransparency = 1
    Logo.Parent = LogoHolder

    -- Gradient on logo text
    local LogoGrad = Instance.new("UIGradient", Logo)
    LogoGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 220, 255)),
        ColorSequenceKeypoint.new(0.6, Color3.fromRGB(120, 140, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 80, 255))
    })

    -- Version subtitle
    local VersionLabel = Instance.new("TextLabel")
    VersionLabel.Name = "Version"
    VersionLabel.Size = UDim2.new(1, 0, 0, 14)
    VersionLabel.Position = UDim2.new(0, 0, 0, 48)
    VersionLabel.Text = "PREMIUM v6.8"
    VersionLabel.TextColor3 = Theme.TextDark
    VersionLabel.Font = Enum.Font.GothamMedium
    VersionLabel.TextSize = 10
    VersionLabel.BackgroundTransparency = 1
    VersionLabel.Parent = LogoHolder

    -- Separator line with gradient
    local LogoSep = Instance.new("Frame")
    LogoSep.Size = UDim2.new(0.85, 0, 0, 1)
    LogoSep.Position = UDim2.new(0.075, 0, 1, -4)
    LogoSep.BackgroundColor3 = Theme.Accent
    LogoSep.BorderSizePixel = 0
    LogoSep.BackgroundTransparency = 0.3
    LogoSep.Parent = LogoHolder

    local SepGrad = Instance.new("UIGradient", LogoSep)
    SepGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 200, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(140, 80, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 200, 255))
    })
    SepGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8),
        NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(1, 0.8)
    })
end

ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -246, 1, -24)
ContentArea.Position = UDim2.new(0, 234, 0, 12)
ContentArea.BackgroundColor3 = Theme.Panel
ContentArea.BackgroundTransparency = 0.04
ContentArea.BorderSizePixel = 0
ContentArea.Parent = MainFrame

local CA_Corner = Instance.new("UICorner", ContentArea)
CA_Corner.CornerRadius = UDim.new(0, 10)

local CA_Gradient = Instance.new("UIGradient", ContentArea)
CA_Gradient.Rotation = 130
CA_Gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 22, 38)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10, 14, 26)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 10, 20))
})

local IntroScale = Instance.new("UIScale", MainFrame)
IntroScale.Name = "IntroScale"
IntroScale.Scale = 0.97

task.defer(function()
    if not MainFrame or not MainFrame.Parent then return end
    TweenService:Create(IntroScale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Scale = 1
    }):Play()
end)

task.spawn(function()
    local grad1 = TweenService:Create(MainGradient,
        TweenInfo.new(16, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true),
        { Offset = Vector2.new(0.16, 0.08) })
    local grad2 = TweenService:Create(SB_Gradient,
        TweenInfo.new(14, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true),
        { Offset = Vector2.new(0.12, 0.22) })
    local grad3 = TweenService:Create(CA_Gradient,
        TweenInfo.new(18, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true),
        { Offset = Vector2.new(-0.18, 0.1) })
    grad1:Play()
    grad2:Play()
    grad3:Play()

    while _G.CheatLoaded and MainFrame.Parent do
        local dim = TweenService:Create(MainGlow, TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
            Transparency = 0.86
        })
        dim:Play()
        dim.Completed:Wait()
        if not _G.CheatLoaded or not MainFrame.Parent then break end

        local bright = TweenService:Create(MainGlow,
            TweenInfo.new(1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                Transparency = 0.74
            })
        bright:Play()
        bright.Completed:Wait()
    end

    grad1:Cancel()
    grad2:Cancel()
    grad3:Cancel()
end)
end

local Tabs = {}
local TabButtons = {}
local ActiveTabName = nil
local TabButtonOrder = 0

local function CreateTabContainer(name, autoScroll)
    local Container = Instance.new("ScrollingFrame")
    Container.Name = name .. "Tab"
    Container:SetAttribute("TabName", name)
    Container.Size = UDim2.new(1, 0, 1, 0)
    Container.BackgroundTransparency = 1
    Container.ScrollBarThickness = autoScroll and 4 or 0
    Container.Visible = false
    Container.ScrollBarImageColor3 = Theme.Accent
    Container.BorderSizePixel = 0
    Container.Parent = ContentArea
    Container.VerticalScrollBarInset = Enum.ScrollBarInset.None

    local Layout = Instance.new("UIListLayout", Container)
    Layout.Padding = UDim.new(0, 10)
    Layout.SortOrder = Enum.SortOrder.LayoutOrder

    local Padding = Instance.new("UIPadding", Container)
    Padding.PaddingTop = UDim.new(0, 12)
    Padding.PaddingBottom = UDim.new(0, 12)
    Padding.PaddingLeft = UDim.new(0, 12)
    Padding.PaddingRight = UDim.new(0, 12)

    if autoScroll then
        local layoutConn = Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            Container.CanvasSize = UDim2.new(0, 0, 0, Layout.AbsoluteContentSize.Y + 28)
        end)
        table.insert(CheatEnv.UIConnections, layoutConn)
    else
        Container.CanvasSize = UDim2.new(0, 0, 0, 0)
        Container.ScrollingEnabled = false
    end

    Tabs[name] = Container
    return Container
end

local function SetActiveTab(name)
    if not name then return end
    local target = Tabs[name]
    if not target then return end

    local previousName = ActiveTabName
    local previous = previousName and Tabs[previousName] or nil
    local isSame = (previousName == name)
    ActiveTabName = name

    if not isSame then
        local previousOrder = previousName and TabButtons[previousName] and TabButtons[previousName].Order or 0
        local targetOrder = TabButtons[name] and TabButtons[name].Order or previousOrder
        local direction = (targetOrder >= previousOrder) and 1 or -1

        local offsetIn = 34 * direction
        local offsetOut = -28 * direction
        local basePosition = UDim2.new(0, 0, 0, 0)

        target.Visible = true
        target.Position = UDim2.new(0, offsetIn, 0, 0)
        target.ScrollBarImageTransparency = 0.35

        local inTween = TweenService:Create(target, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Position = basePosition,
            ScrollBarImageTransparency = 0
        })
        inTween:Play()

        if previous and previous ~= target and previous.Parent then
            previous.Visible = true
            previous.ScrollBarImageTransparency = 0
            local outTween = TweenService:Create(previous,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                    Position = UDim2.new(0, offsetOut, 0, 0),
                    ScrollBarImageTransparency = 0.35
                })
            outTween:Play()

            local previousTabName = previousName
            task.delay(0.19, function()
                if previous and previous.Parent and ActiveTabName ~= previousTabName then
                    previous.Visible = false
                    previous.Position = basePosition
                    previous.ScrollBarImageTransparency = 0
                end
            end)
        end

        for tabName, container in pairs(Tabs) do
            if tabName ~= name and container ~= previous then
                container.Visible = false
                container.Position = UDim2.new(0, 0, 0, 0)
                container.ScrollBarImageTransparency = 0
            end
        end
    else
        target.Visible = true
        target.Position = UDim2.new(0, 0, 0, 0)
        target.ScrollBarImageTransparency = 0
        for tabName, container in pairs(Tabs) do
            if tabName ~= name then
                container.Visible = false
                container.Position = UDim2.new(0, 0, 0, 0)
                container.ScrollBarImageTransparency = 0
            end
        end
    end

    for tabName, tabData in pairs(TabButtons) do
        local isActive = (tabName == name)
        if tabData and tabData.Button then
            TweenService:Create(tabData.Button, TweenInfo.new(0.18), {
                BackgroundColor3 = isActive and Theme.Element or Theme.PanelSoft
            }):Play()
            tabData.Button.TextColor3 = isActive and Theme.Text or Theme.TextDark
        end
        if tabData and tabData.Stroke then
            TweenService:Create(tabData.Stroke, TweenInfo.new(0.18), {
                Transparency = isActive and 0.2 or 0.7
            }):Play()
            tabData.Stroke.Color = isActive and Theme.AccentSoft or Theme.Stroke
        end
        if tabData and tabData.Accent then
            tabData.Accent.Visible = isActive
        end
    end
end

local function TrackUIConnection(conn)
    if conn then
        table.insert(CheatEnv.UIConnections, conn)
    end
    return conn
end

local function EnsureControlScale(instance, name)
    if not instance or typeof(instance) ~= "Instance" then return nil end
    local scaleName = name or "AnimScale"
    local scale = instance:FindFirstChild(scaleName)
    if not scale then
        scale = Instance.new("UIScale")
        scale.Name = scaleName
        scale.Scale = 1
        scale.Parent = instance
    end
    return scale
end

local function TweenControlScale(instance, targetScale, duration, easingStyle, easingDirection)
    local scale = EnsureControlScale(instance)
    if not scale then return end
    TweenService:Create(
        scale,
        TweenInfo.new(duration or 0.11, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
        { Scale = targetScale or 1 }
    ):Play()
end

local function BindAnimatedButton(button, options)
    if not button then return end
    options = options or {}

    local stroke = options.Stroke
    local hovered = false
    local pressed = false

    local baseStroke = nil
    if stroke then
        baseStroke = (options.BaseStrokeTransparency ~= nil) and options.BaseStrokeTransparency or stroke.Transparency
    end
    local hoverStroke = stroke and ((options.HoverStrokeTransparency ~= nil) and options.HoverStrokeTransparency or
        math_max(0, (baseStroke or 0.65) - 0.22)) or nil
    local pressStroke = stroke and ((options.PressStrokeTransparency ~= nil) and options.PressStrokeTransparency or
        math_max(0, (hoverStroke or 0.4) - 0.08)) or nil

    local function resolveEnabled()
        local custom = options.EnabledCheck
        if custom then
            local ok, result = pcall(custom)
            if ok then
                return result ~= false
            end
        end
        return button.Active ~= false
    end

    local function resolveBaseColor()
        local getter = options.GetBaseColor
        if getter then
            local ok, value = pcall(getter)
            if ok and typeof(value) == "Color3" then
                return value
            end
        end
        return options.BaseColor or button.BackgroundColor3
    end

    local function resolveHoverColor(baseColor)
        if typeof(options.HoverColor) == "Color3" then
            return options.HoverColor
        end
        local mix = options.HoverMix or 0.08
        return baseColor:Lerp(Color3.new(1, 1, 1), mix)
    end

    local function resolvePressColor(hoverColor)
        if typeof(options.PressColor) == "Color3" then
            return options.PressColor
        end
        local mix = options.PressMix or 0.12
        return hoverColor:Lerp(Color3.new(0, 0, 0), mix)
    end

    local function applyState()
        if not button or not button.Parent then return end
        local enabled = resolveEnabled()
        local baseColor = resolveBaseColor()
        local hoverColor = resolveHoverColor(baseColor)
        local pressColor = resolvePressColor(hoverColor)

        if options.ChangeColor ~= false then
            local targetColor = baseColor
            if enabled and hovered then
                targetColor = hoverColor
            end
            if enabled and pressed and hovered then
                targetColor = pressColor
            end
            TweenService:Create(button, TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                BackgroundColor3 = targetColor
            }):Play()
        end

        if stroke then
            local targetStroke = baseStroke
            if enabled and hovered then
                targetStroke = hoverStroke
            end
            if enabled and hovered and pressed then
                targetStroke = pressStroke
            end
            TweenService:Create(stroke, TweenInfo.new(0.11, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = targetStroke
            }):Play()
        end

        local hoverScale = options.HoverScale or 1.012
        local pressScale = options.PressScale or 0.97
        local targetScale = 1
        if enabled and hovered then
            targetScale = hoverScale
        end
        if enabled and hovered and pressed then
            targetScale = pressScale
        end
        TweenControlScale(button, targetScale, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end

    TrackUIConnection(button.MouseEnter:Connect(function()
        hovered = true
        applyState()
    end))

    TrackUIConnection(button.MouseLeave:Connect(function()
        hovered = false
        pressed = false
        applyState()
    end))

    if button:IsA("TextButton") or button:IsA("ImageButton") then
        TrackUIConnection(button.MouseButton1Down:Connect(function()
            pressed = true
            applyState()
        end))
        TrackUIConnection(button.MouseButton1Up:Connect(function()
            pressed = false
            applyState()
        end))
        TrackUIConnection(button.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                pressed = false
                applyState()
            end
        end))
    end
end

local function BindAnimatedCard(frame, stroke, options)
    if not frame then return end
    options = options or {}

    local baseColor = options.BaseColor or frame.BackgroundColor3
    local hoverColor = options.HoverColor or baseColor:Lerp(Color3.new(1, 1, 1), options.HoverMix or 0.055)
    local baseStroke = nil
    if stroke then
        baseStroke = (options.BaseStrokeTransparency ~= nil) and options.BaseStrokeTransparency or stroke.Transparency
    end
    local hoverStroke = stroke and ((options.HoverStrokeTransparency ~= nil) and options.HoverStrokeTransparency or
        math_max(0, (baseStroke or 0.75) - 0.28)) or nil
    local hoverScale = options.HoverScale or 1.006

    local function applyHover(isHover)
        if not frame or not frame.Parent then return end
        local color = isHover and hoverColor or baseColor
        TweenService:Create(frame, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = color
        }):Play()
        if stroke then
            TweenService:Create(stroke, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Transparency = isHover and hoverStroke or baseStroke
            }):Play()
        end
        TweenControlScale(frame, isHover and hoverScale or 1, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end

    TrackUIConnection(frame.MouseEnter:Connect(function()
        applyHover(true)
    end))
    TrackUIConnection(frame.MouseLeave:Connect(function()
        applyHover(false)
    end))
end

local function CreateTabButton(name)
    local Button = Instance.new("TextButton")
    TabButtonOrder = TabButtonOrder + 1
    Button.LayoutOrder = 20 + TabButtonOrder
    Button.Size = UDim2.new(1, -4, 0, 40)
    Button.BackgroundColor3 = Color3.fromRGB(14, 18, 30)
    Button.BackgroundTransparency = 0.15
    Button.Text = string.upper(name)
    Button.TextColor3 = Theme.TextDark
    Button.Font = Enum.Font.GothamBold
    Button.TextSize = 13
    Button.AutoButtonColor = false
    Button.TextXAlignment = Enum.TextXAlignment.Left
    Button.Parent = SideBar

    local Corner = Instance.new("UICorner", Button)
    Corner.CornerRadius = UDim.new(0, 8)

    local Padding = Instance.new("UIPadding", Button)
    Padding.PaddingLeft = UDim.new(0, 18)

    local ButtonStroke = Instance.new("UIStroke", Button)
    ButtonStroke.Color = Theme.CardBorder
    ButtonStroke.Thickness = 1
    ButtonStroke.Transparency = 0.7

    -- Gradient accent bar (left side)
    local Accent = Instance.new("Frame")
    Accent.Name = "Accent"
    Accent.Size = UDim2.new(0, 3, 0.65, 0)
    Accent.Position = UDim2.new(0, 5, 0.175, 0)
    Accent.BackgroundColor3 = Theme.Accent
    Accent.BorderSizePixel = 0
    Accent.Visible = false
    Accent.Parent = Button

    local AccentCorner = Instance.new("UICorner", Accent)
    AccentCorner.CornerRadius = UDim.new(1, 0)

    -- Gradient on accent bar
    local AccentGrad = Instance.new("UIGradient", Accent)
    AccentGrad.Rotation = 90
    AccentGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 210, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(100, 120, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 70, 255))
    })

    local tabHovered = false

    local conn = Button.MouseButton1Click:Connect(function()
        SetActiveTab(name)
    end)
    TrackUIConnection(conn)

    local hoverInConn = Button.MouseEnter:Connect(function()
        tabHovered = true
        if ActiveTabName == name then return end
        TweenService:Create(Button, TweenInfo.new(0.12), { BackgroundColor3 = Theme.Element }):Play()
        TweenService:Create(ButtonStroke, TweenInfo.new(0.12), { Transparency = 0.45 }):Play()
        TweenControlScale(Button, 1.012, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end)
    local hoverOutConn = Button.MouseLeave:Connect(function()
        tabHovered = false
        if ActiveTabName == name then return end
        TweenService:Create(Button, TweenInfo.new(0.12), { BackgroundColor3 = Theme.PanelSoft }):Play()
        TweenService:Create(ButtonStroke, TweenInfo.new(0.12), { Transparency = 0.7 }):Play()
        TweenControlScale(Button, 1, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end)
    TrackUIConnection(hoverInConn)
    TrackUIConnection(hoverOutConn)

    local pressDownConn = Button.MouseButton1Down:Connect(function()
        if ActiveTabName == name then return end
        TweenControlScale(Button, 0.97, 0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end)
    local pressUpConn = Button.MouseButton1Up:Connect(function()
        if ActiveTabName == name then
            TweenControlScale(Button, 1, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            return
        end
        TweenControlScale(Button, tabHovered and 1.012 or 1, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end)
    TrackUIConnection(pressDownConn)
    TrackUIConnection(pressUpConn)

    TabButtons[name] = {
        Button = Button,
        Accent = Accent,
        Stroke = ButtonStroke,
        Order = TabButtonOrder
    }

    if not ActiveTabName then
        SetActiveTab(name)
    end

    return Button
end

CreateTabContainer("Combat", true)
CreateTabContainer("Visuals", true)
CreateTabContainer("Misc", false)
CreateTabContainer("System", true)

CreateTabButton("Combat")
CreateTabButton("Visuals")
CreateTabButton("Misc")
CreateTabButton("System")

local function SetupSearchUI()
    local searchState = {
        Entries = {},
        ResultRows = {},
        CurrentResults = {},
        SelectedIndex = 0,
        MaxResults = 10,
        Synonyms = {
            ESP = { "wallhack", "boxes", "outline", "tracer", "name", "distance" },
            Aimbot = { "aim", "assist", "lock" },
            Aimlock = { "aim", "lock", "snap" },
            PredictionEnabled = { "predict", "bullet lead" },
            NoRecoil = { "recoil", "spray" },
            NoSpread = { "spread", "accuracy" },
            WallShot = { "wallbang", "through wall" },
            Misc_Fullbright = { "brightness", "lighting" },
            AutoRespawn = { "respawn" }
        }
    }
    CheatEnv.SearchState = searchState

    local function NormalizeSearchText(text)
        if type(text) ~= "string" then return "" end
        local normalized = text:lower()
        normalized = normalized:gsub("[%c%p]+", " ")
        normalized = normalized:gsub("%s+", " ")
        return normalized
    end

    local function ResolveTabName(parent)
        if not parent then return "System" end
        local attr = parent:GetAttribute("TabName")
        if type(attr) == "string" and attr ~= "" then
            return attr
        end
        for tabName, container in pairs(Tabs) do
            if container == parent then
                return tabName
            end
        end
        return "System"
    end

    local function LevenshteinLimited(a, b, maxDist)
        local la, lb = #a, #b
        if math_abs(la - lb) > maxDist then
            return maxDist + 1
        end

        local prev, curr = {}, {}
        for j = 0, lb do
            prev[j] = j
        end

        for i = 1, la do
            curr[0] = i
            local minRow = curr[0]
            local ai = a:sub(i, i)

            for j = 1, lb do
                local cost = (ai == b:sub(j, j)) and 0 or 1
                local deletion = prev[j] + 1
                local insertion = curr[j - 1] + 1
                local substitution = prev[j - 1] + cost

                local best = deletion
                if insertion < best then best = insertion end
                if substitution < best then best = substitution end

                curr[j] = best
                if best < minRow then minRow = best end
            end

            if minRow > maxDist then
                return maxDist + 1
            end

            prev, curr = curr, prev
        end

        return prev[lb]
    end

    local function BuildSearchText(label, settingKey, tabName, tags)
        local parts = { label or "", tabName or "", settingKey or "", tags or "" }
        local aliases = searchState.Synonyms[settingKey]
        if aliases then
            parts[#parts + 1] = table.concat(aliases, " ")
        end
        return NormalizeSearchText(table.concat(parts, " "))
    end

    local function RegisterSearchEntry(label, settingKey, frame, parent, tags)
        if type(label) ~= "string" or label == "" then return end
        if typeof(frame) ~= "Instance" then return end

        local tabName = ResolveTabName(parent)
        local entry = {
            label = label,
            settingKey = settingKey,
            frame = frame,
            tabName = tabName,
            searchText = BuildSearchText(label, settingKey, tabName, tags)
        }

        frame:SetAttribute("SearchLabel", label)
        table.insert(searchState.Entries, entry)
    end

    CheatEnv.RegisterSearchEntry = RegisterSearchEntry

    local SearchWrap = Instance.new("Frame")
    SearchWrap.Name = "SearchWrap"
    SearchWrap.LayoutOrder = 2
    SearchWrap.Size = UDim2.new(1, -4, 0, 38)
    SearchWrap.BackgroundTransparency = 1
    SearchWrap.ZIndex = 40
    SearchWrap.Parent = SideBar

    local SearchBox = Instance.new("TextBox")
    SearchBox.Name = "SearchBox"
    SearchBox.Size = UDim2.new(1, 0, 0, 34)
    SearchBox.Position = UDim2.new(0, 0, 0, 0)
    SearchBox.BackgroundColor3 = Theme.Element
    SearchBox.BackgroundTransparency = 0.04
    SearchBox.BorderSizePixel = 0
    SearchBox.PlaceholderText = "Search settings..."
    SearchBox.PlaceholderColor3 = Theme.TextDark
    SearchBox.Text = ""
    SearchBox.TextColor3 = Theme.Text
    SearchBox.Font = Enum.Font.GothamMedium
    SearchBox.TextSize = 13
    SearchBox.ClearTextOnFocus = false
    SearchBox.TextXAlignment = Enum.TextXAlignment.Left
    SearchBox.ZIndex = 41
    SearchBox.Parent = SearchWrap

    local SB_Corner = Instance.new("UICorner", SearchBox)
    SB_Corner.CornerRadius = UDim.new(0, 8)

    local SB_Stroke = Instance.new("UIStroke", SearchBox)
    SB_Stroke.Color = Theme.Stroke
    SB_Stroke.Thickness = 1
    SB_Stroke.Transparency = 0.6

    local searchFocusConn = SearchBox.Focused:Connect(function()
        SB_Stroke.Color = Theme.AccentSoft
        TweenService:Create(SB_Stroke, TweenInfo.new(0.12), { Transparency = 0.22 }):Play()
    end)
    local searchBlurConn = SearchBox.FocusLost:Connect(function()
        SB_Stroke.Color = Theme.Stroke
        TweenService:Create(SB_Stroke, TweenInfo.new(0.12), { Transparency = 0.6 }):Play()
    end)
    table.insert(CheatEnv.UIConnections, searchFocusConn)
    table.insert(CheatEnv.UIConnections, searchBlurConn)

    local SB_Padding = Instance.new("UIPadding", SearchBox)
    SB_Padding.PaddingLeft = UDim.new(0, 10)
    SB_Padding.PaddingRight = UDim.new(0, 10)

    local ResultsFrame = Instance.new("ScrollingFrame")
    ResultsFrame.Name = "SearchResults"
    ResultsFrame.Size = UDim2.new(1, 0, 0, 0)
    ResultsFrame.Position = UDim2.new(0, 0, 0, 38)
    ResultsFrame.BackgroundColor3 = Theme.Panel
    ResultsFrame.BackgroundTransparency = 0.04
    ResultsFrame.BorderSizePixel = 0
    ResultsFrame.ScrollBarThickness = 3
    ResultsFrame.ScrollBarImageColor3 = Theme.Accent
    ResultsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    ResultsFrame.Visible = false
    ResultsFrame.ZIndex = 50
    ResultsFrame.Parent = SearchWrap

    local RF_Corner = Instance.new("UICorner", ResultsFrame)
    RF_Corner.CornerRadius = UDim.new(0, 8)

    local RF_Stroke = Instance.new("UIStroke", ResultsFrame)
    RF_Stroke.Color = Theme.Stroke
    RF_Stroke.Thickness = 1
    RF_Stroke.Transparency = 0.5

    local ResultsLayout = Instance.new("UIListLayout", ResultsFrame)
    ResultsLayout.Padding = UDim.new(0, 3)
    ResultsLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local ResultsPadding = Instance.new("UIPadding", ResultsFrame)
    ResultsPadding.PaddingTop = UDim.new(0, 4)
    ResultsPadding.PaddingBottom = UDim.new(0, 4)
    ResultsPadding.PaddingLeft = UDim.new(0, 4)
    ResultsPadding.PaddingRight = UDim.new(0, 4)

    local function ClearResultRows()
        for i = #searchState.ResultRows, 1, -1 do
            local row = searchState.ResultRows[i]
            if row and row.Parent then
                row:Destroy()
            end
            searchState.ResultRows[i] = nil
        end
        for i = #searchState.CurrentResults, 1, -1 do
            searchState.CurrentResults[i] = nil
        end
        searchState.SelectedIndex = 0
    end

    local function SetResultRowState(row, isSelected)
        if not row or not row:IsA("TextButton") then return end
        local bgColor = isSelected and Theme.PanelSoft or Theme.Element
        local textColor = isSelected and Theme.AccentSoft or Theme.Text
        TweenService:Create(row, TweenInfo.new(0.1), {
            BackgroundColor3 = bgColor,
            TextColor3 = textColor
        }):Play()

        local stroke = row:FindFirstChild("SearchStroke")
        if stroke and stroke:IsA("UIStroke") then
            TweenService:Create(stroke, TweenInfo.new(0.1), {
                Transparency = isSelected and 0.25 or 0.72
            }):Play()
            stroke.Color = isSelected and Theme.AccentSoft or Theme.Stroke
        end
    end

    local function SetSelectedResult(index, keepInView)
        local total = #searchState.CurrentResults
        if total <= 0 then
            searchState.SelectedIndex = 0
            return
        end

        local selected = math_clamp(index, 1, total)
        searchState.SelectedIndex = selected

        for i = 1, #searchState.ResultRows do
            SetResultRowState(searchState.ResultRows[i], i == selected)
        end

        if keepInView then
            local row = searchState.ResultRows[selected]
            if row and row.Parent == ResultsFrame then
                local rowTop = row.AbsolutePosition.Y - ResultsFrame.AbsolutePosition.Y + ResultsFrame.CanvasPosition.Y
                local rowBottom = rowTop + row.AbsoluteSize.Y
                local visibleTop = ResultsFrame.CanvasPosition.Y
                local visibleBottom = visibleTop + ResultsFrame.AbsoluteSize.Y

                if rowTop < visibleTop then
                    ResultsFrame.CanvasPosition = Vector2.new(0, math_max(0, rowTop - 3))
                elseif rowBottom > visibleBottom then
                    ResultsFrame.CanvasPosition = Vector2.new(0,
                        math_max(0, rowBottom - ResultsFrame.AbsoluteSize.Y + 3))
                end
            end
        end
    end

    local function CloseSearchResults()
        ResultsFrame.Visible = false
        ResultsFrame.Size = UDim2.new(1, 0, 0, 0)
        ResultsFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
        ResultsFrame.CanvasPosition = Vector2.new(0, 0)
        ClearResultRows()
    end

    local OpenSearchEntry

    local function CommitSearchSelection(entry)
        if not entry then return end
        OpenSearchEntry(entry)
        SearchBox.Text = entry.label
        CloseSearchResults()
    end

    OpenSearchEntry = function(entry)
        if not entry or not entry.frame or not entry.frame.Parent then return end
        SetActiveTab(entry.tabName)

        task.defer(function()
            local frame = entry.frame
            if not frame or not frame.Parent then return end

            local tab = Tabs[entry.tabName]
            if tab and tab:IsA("ScrollingFrame") then
                local targetY = frame.AbsolutePosition.Y - tab.AbsolutePosition.Y + tab.CanvasPosition.Y - 24
                tab.CanvasPosition = Vector2.new(0, math_max(0, targetY))
            end

            local originalColor = frame.BackgroundColor3
            TweenService:Create(frame, TweenInfo.new(0.15), { BackgroundColor3 = Theme.Accent }):Play()
            task.delay(0.16, function()
                if frame and frame.Parent then
                    TweenService:Create(frame, TweenInfo.new(0.22), { BackgroundColor3 = originalColor }):Play()
                end
            end)
        end)
    end

    local function ScoreSearchEntry(entry, queryNorm)
        local searchable = entry.searchText
        if searchable == queryNorm then
            return 1200
        end

        local directPos = searchable:find(queryNorm, 1, true)
        if directPos then
            if directPos == 1 then
                return 980
            end
            return 760 - math_min(160, directPos)
        end

        local best = 0
        for token in searchable:gmatch("%S+") do
            if token == queryNorm then
                if 900 > best then best = 900 end
            elseif token:sub(1, #queryNorm) == queryNorm then
                if 790 > best then best = 790 end
            elseif #queryNorm >= 4 and #token >= 4 then
                local dist = LevenshteinLimited(token, queryNorm, 2)
                if dist <= 2 then
                    local fuzzyScore = 650 - dist * 80
                    if fuzzyScore > best then best = fuzzyScore end
                end
            end
        end

        return best
    end

    local function RefreshSearchResults(query)
        local queryNorm = NormalizeSearchText(query)
        ClearResultRows()

        if queryNorm == "" then
            CloseSearchResults()
            return
        end

        local ranked = {}
        for i = 1, #searchState.Entries do
            local entry = searchState.Entries[i]
            if entry and entry.frame and entry.frame.Parent then
                local score = ScoreSearchEntry(entry, queryNorm)
                if score > 0 then
                    ranked[#ranked + 1] = { score = score, entry = entry }
                end
            end
        end

        table.sort(ranked, function(a, b)
            if a.score == b.score then
                return a.entry.label < b.entry.label
            end
            return a.score > b.score
        end)

        local rowsCount = 0
        if #ranked == 0 then
            local Empty = Instance.new("TextLabel")
            Empty.Size = UDim2.new(1, 0, 0, 28)
            Empty.BackgroundTransparency = 1
            Empty.Text = "No results"
            Empty.TextColor3 = Theme.TextDark
            Empty.Font = Enum.Font.GothamMedium
            Empty.TextSize = 12
            Empty.ZIndex = 51
            Empty.Parent = ResultsFrame
            searchState.ResultRows[#searchState.ResultRows + 1] = Empty
            rowsCount = 1
        else
            local limit = math_min(searchState.MaxResults, #ranked)
            for i = 1, limit do
                local entry = ranked[i].entry
                local rowIndex = i
                local Row = Instance.new("TextButton")
                Row.Size = UDim2.new(1, 0, 0, 30)
                Row.BackgroundColor3 = Theme.Element
                Row.BorderSizePixel = 0
                Row.Text = entry.label .. "  [" .. entry.tabName .. "]"
                Row.TextColor3 = Theme.Text
                Row.Font = Enum.Font.GothamMedium
                Row.TextSize = 12
                Row.TextXAlignment = Enum.TextXAlignment.Left
                Row.AutoButtonColor = false
                Row.ZIndex = 51
                Row.Parent = ResultsFrame

                local RC = Instance.new("UICorner", Row)
                RC.CornerRadius = UDim.new(0, 6)

                local RS = Instance.new("UIStroke", Row)
                RS.Name = "SearchStroke"
                RS.Color = Theme.Stroke
                RS.Thickness = 1
                RS.Transparency = 0.72

                local RP = Instance.new("UIPadding", Row)
                RP.PaddingLeft = UDim.new(0, 8)

                local enterConn = Row.MouseEnter:Connect(function()
                    SetSelectedResult(rowIndex, false)
                end)
                local leaveConn = Row.MouseLeave:Connect(function()
                    if searchState.SelectedIndex ~= rowIndex then
                        SetResultRowState(Row, false)
                    end
                end)
                local clickConn = Row.MouseButton1Click:Connect(function()
                    searchState.SelectedIndex = rowIndex
                    CommitSearchSelection(entry)
                end)
                table.insert(CheatEnv.UIConnections, enterConn)
                table.insert(CheatEnv.UIConnections, leaveConn)
                table.insert(CheatEnv.UIConnections, clickConn)

                searchState.ResultRows[#searchState.ResultRows + 1] = Row
                searchState.CurrentResults[#searchState.CurrentResults + 1] = entry
                rowsCount = rowsCount + 1
            end
        end

        local contentHeight = rowsCount * 33 + 6
        local visibleHeight = math_min(190, contentHeight)
        ResultsFrame.Visible = true
        ResultsFrame.CanvasSize = UDim2.new(0, 0, 0, contentHeight)
        ResultsFrame.CanvasPosition = Vector2.new(0, 0)
        TweenService:Create(ResultsFrame, TweenInfo.new(0.12), { Size = UDim2.new(1, 0, 0, visibleHeight) }):Play()

        if #searchState.CurrentResults > 0 then
            SetSelectedResult(1, false)
        end
    end

    local textConn = SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        RefreshSearchResults(SearchBox.Text)
    end)
    table.insert(CheatEnv.UIConnections, textConn)

    local focusLostConn = SearchBox.FocusLost:Connect(function(enterPressed)
        if enterPressed then
            local index = searchState.SelectedIndex > 0 and searchState.SelectedIndex or 1
            local selected = searchState.CurrentResults[index]
            if selected then
                CommitSearchSelection(selected)
            end
        end
    end)
    table.insert(CheatEnv.UIConnections, focusLostConn)

    local quickFocusConn = UserInputService.InputBegan:Connect(function(input, processed)
        if not MainFrame.Visible then return end

        local focusedBox = UserInputService:GetFocusedTextBox()
        if focusedBox == SearchBox then
            if input.KeyCode == Enum.KeyCode.Down then
                if #searchState.CurrentResults > 0 then
                    local nextIndex = searchState.SelectedIndex + 1
                    if nextIndex > #searchState.CurrentResults then
                        nextIndex = 1
                    end
                    SetSelectedResult(nextIndex, true)
                end
                return
            end

            if input.KeyCode == Enum.KeyCode.Up then
                if #searchState.CurrentResults > 0 then
                    local prevIndex = searchState.SelectedIndex - 1
                    if prevIndex < 1 then
                        prevIndex = #searchState.CurrentResults
                    end
                    SetSelectedResult(prevIndex, true)
                end
                return
            end

            if input.KeyCode == Enum.KeyCode.Return then
                local index = searchState.SelectedIndex > 0 and searchState.SelectedIndex or 1
                local selected = searchState.CurrentResults[index]
                if selected then
                    CommitSearchSelection(selected)
                end
                return
            end

            if input.KeyCode == Enum.KeyCode.Escape then
                SearchBox.Text = ""
                CloseSearchResults()
                SearchBox:ReleaseFocus()
                return
            end
        end

        if processed then return end

        if input.KeyCode == Enum.KeyCode.Slash then
            SearchBox:CaptureFocus()
            return
        end
    end)
    table.insert(CheatEnv.UIConnections, quickFocusConn)
end
SetupSearchUI()

-- ============================================
-- CONFIG GUI SYSTEM
-- ============================================

local ConfigFrame, CreateConfigModal, ConfigHint

do
    ConfigFrame = Instance.new("Frame")
    ConfigFrame.Name = "ConfigFrame"
    ConfigFrame.Size = UDim2.new(0, 300, 0, 420)
    ConfigFrame.Position = UDim2.new(1, -316, 1, -436)
    ConfigFrame.BackgroundColor3 = Theme.Background
    ConfigFrame.BackgroundTransparency = 0.02
    ConfigFrame.BorderSizePixel = 0
    ConfigFrame.Visible = false
    ConfigFrame:SetAttribute("UserMoved", false)
    ConfigFrame.Parent = ScreenGui
    ConfigFrame.ZIndex = 50

    local CF_Corner = Instance.new("UICorner", ConfigFrame)
    CF_Corner.CornerRadius = UDim.new(0, 12)

    local CF_Stroke = Instance.new("UIStroke", ConfigFrame)
    CF_Stroke.Color = Theme.Stroke
    CF_Stroke.Thickness = 1.2
    CF_Stroke.Transparency = 0.35

    -- Config Header
    local ConfigHeader = Instance.new("TextLabel")
    ConfigHeader.Name = "Header"
    ConfigHeader.Size = UDim2.new(1, 0, 0, 38)
    ConfigHeader.BackgroundColor3 = Theme.Panel
    ConfigHeader.BackgroundTransparency = 0.08
    ConfigHeader.Text = "CONFIG MANAGER"
    ConfigHeader.TextColor3 = Theme.Accent
    ConfigHeader.Font = Enum.Font.GothamBold
    ConfigHeader.TextSize = 17
    ConfigHeader.Parent = ConfigFrame
    ConfigHeader.ZIndex = 51

    local CH_Corner = Instance.new("UICorner", ConfigHeader)
    CH_Corner.CornerRadius = UDim.new(0, 12)

    -- Button Container (2x2 Grid)
    local ButtonContainer = Instance.new("Frame")
    ButtonContainer.Name = "ButtonContainer"
    ButtonContainer.Size = UDim2.new(1, -24, 0, 86)
    ButtonContainer.Position = UDim2.new(0, 12, 0, 52)
    ButtonContainer.BackgroundTransparency = 1
    ButtonContainer.Parent = ConfigFrame
    ButtonContainer.ZIndex = 51

    -- Grid Layout
    local GridLayout = Instance.new("UIGridLayout", ButtonContainer)
    GridLayout.CellSize = UDim2.new(0.5, -5, 0.5, -4)
    GridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
    GridLayout.SortOrder = Enum.SortOrder.LayoutOrder

    -- Create Config Button
    local Btn_Create = Instance.new("TextButton")
    Btn_Create.Name = "Create"
    Btn_Create.LayoutOrder = 1
    Btn_Create.BackgroundColor3 = Theme.Element
    Btn_Create.Text = "Создать"
    Btn_Create.TextColor3 = Theme.Text
    Btn_Create.Font = Enum.Font.GothamMedium
    Btn_Create.TextSize = 13
    Btn_Create.Parent = ButtonContainer
    Btn_Create.ZIndex = 52

    local BC_Corner = Instance.new("UICorner", Btn_Create)
    BC_Corner.CornerRadius = UDim.new(0, 6)

    -- Delete Config Button
    local Btn_Delete = Instance.new("TextButton")
    Btn_Delete.Name = "Delete"
    Btn_Delete.LayoutOrder = 2
    Btn_Delete.BackgroundColor3 = Theme.Element
    Btn_Delete.Text = "Удалить"
    Btn_Delete.TextColor3 = Theme.Text
    Btn_Delete.Font = Enum.Font.GothamMedium
    Btn_Delete.TextSize = 13
    Btn_Delete.Parent = ButtonContainer
    Btn_Delete.ZIndex = 52

    local BD_Corner = Instance.new("UICorner", Btn_Delete)
    BD_Corner.CornerRadius = UDim.new(0, 6)

    -- Overwrite Config Button
    local Btn_Overwrite = Instance.new("TextButton")
    Btn_Overwrite.Name = "Overwrite"
    Btn_Overwrite.LayoutOrder = 3
    Btn_Overwrite.BackgroundColor3 = Theme.Element
    Btn_Overwrite.Text = "Перезаписать"
    Btn_Overwrite.TextColor3 = Theme.Text
    Btn_Overwrite.Font = Enum.Font.GothamMedium
    Btn_Overwrite.TextSize = 12
    Btn_Overwrite.Parent = ButtonContainer
    Btn_Overwrite.ZIndex = 52

    local BO_Corner = Instance.new("UICorner", Btn_Overwrite)
    BO_Corner.CornerRadius = UDim.new(0, 6)

    -- Open Folder Button
    local Btn_OpenFolder = Instance.new("TextButton")
    Btn_OpenFolder.Name = "OpenFolder"
    Btn_OpenFolder.LayoutOrder = 4
    Btn_OpenFolder.BackgroundColor3 = Theme.Element
    Btn_OpenFolder.Text = "Открыть папку"
    Btn_OpenFolder.TextColor3 = Theme.Text
    Btn_OpenFolder.Font = Enum.Font.GothamMedium
    Btn_OpenFolder.TextSize = 11
    Btn_OpenFolder.Parent = ButtonContainer
    Btn_OpenFolder.ZIndex = 52

    local BOF_Corner = Instance.new("UICorner", Btn_OpenFolder)
    BOF_Corner.CornerRadius = UDim.new(0, 6)

    -- Hint Label (for Delete/Overwrite modes)
    ConfigHint = Instance.new("TextLabel")
    ConfigHint.Name = "Hint"
    ConfigHint.Size = UDim2.new(1, -24, 0, 24)
    ConfigHint.Position = UDim2.new(0, 12, 0, 144)
    ConfigHint.BackgroundTransparency = 1
    ConfigHint.Text = ""
    ConfigHint.TextColor3 = Color3.fromRGB(255, 200, 100)
    ConfigHint.Font = Enum.Font.GothamMedium
    ConfigHint.TextSize = 12
    ConfigHint.TextWrapped = true
    ConfigHint.Visible = false
    ConfigHint.Parent = ConfigFrame
    ConfigHint.ZIndex = 51

    -- Config List Container
    local ConfigListContainer = Instance.new("ScrollingFrame")
    ConfigListContainer.Name = "ConfigList"
    ConfigListContainer.Size = UDim2.new(1, -24, 1, -182)
    ConfigListContainer.Position = UDim2.new(0, 12, 0, 176)
    ConfigListContainer.BackgroundColor3 = Theme.PanelSoft
    ConfigListContainer.BackgroundTransparency = 0.12
    ConfigListContainer.BorderSizePixel = 0
    ConfigListContainer.ScrollBarThickness = 4
    ConfigListContainer.ScrollBarImageColor3 = Theme.Accent
    ConfigListContainer.Parent = ConfigFrame
    ConfigListContainer.ZIndex = 51
    ConfigListContainer.CanvasSize = UDim2.new(0, 0, 0, 0)

    local CLC_Corner = Instance.new("UICorner", ConfigListContainer)
    CLC_Corner.CornerRadius = UDim.new(0, 8)

    local CLC_Layout = Instance.new("UIListLayout", ConfigListContainer)
    CLC_Layout.Padding = UDim.new(0, 5)
    CLC_Layout.SortOrder = Enum.SortOrder.Name

    local CLC_Padding = Instance.new("UIPadding", ConfigListContainer)
    CLC_Padding.PaddingTop = UDim.new(0, 5)
    CLC_Padding.PaddingBottom = UDim.new(0, 5)
    CLC_Padding.PaddingLeft = UDim.new(0, 5)
    CLC_Padding.PaddingRight = UDim.new(0, 5)

    -- Auto-resize config list
    local configLayoutConn = CLC_Layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        ConfigListContainer.CanvasSize = UDim2.new(0, 0, 0, CLC_Layout.AbsoluteContentSize.Y + 10)
    end)
    table.insert(CheatEnv.UIConnections, configLayoutConn)

    -- Create Config Modal
    CreateConfigModal = Instance.new("Frame")
    CreateConfigModal.Name = "CreateConfigModal"
    CreateConfigModal.Size = UDim2.new(0, 220, 0, 148)
    CreateConfigModal.Position = UDim2.new(0, -232, 0, 0) -- Left of ConfigFrame initially
    CreateConfigModal.BackgroundColor3 = Theme.Background
    CreateConfigModal.BackgroundTransparency = 0.02
    CreateConfigModal.BorderSizePixel = 0
    CreateConfigModal.Visible = false
    CreateConfigModal.Parent = ConfigFrame
    CreateConfigModal.ZIndex = 60

    local CCM_Corner = Instance.new("UICorner", CreateConfigModal)
    CCM_Corner.CornerRadius = UDim.new(0, 12)

    local CCM_Stroke = Instance.new("UIStroke", CreateConfigModal)
    CCM_Stroke.Color = Theme.Accent
    CCM_Stroke.Thickness = 1
    CCM_Stroke.Transparency = 0.3

    local CCM_Header = Instance.new("TextLabel")
    CCM_Header.Size = UDim2.new(1, 0, 0, 30)
    CCM_Header.BackgroundTransparency = 1
    CCM_Header.Text = "Create Config"
    CCM_Header.TextColor3 = Theme.Accent
    CCM_Header.Font = Enum.Font.GothamBold
    CCM_Header.TextSize = 15
    CCM_Header.Parent = CreateConfigModal
    CCM_Header.ZIndex = 61

    local CCM_Label = Instance.new("TextLabel")
    CCM_Label.Size = UDim2.new(1, -24, 0, 20)
    CCM_Label.Position = UDim2.new(0, 12, 0, 36)
    CCM_Label.BackgroundTransparency = 1
    CCM_Label.Text = "Config name:"
    CCM_Label.TextColor3 = Theme.TextDark
    CCM_Label.Font = Enum.Font.Gotham
    CCM_Label.TextSize = 13
    CCM_Label.TextXAlignment = Enum.TextXAlignment.Left
    CCM_Label.Parent = CreateConfigModal
    CCM_Label.ZIndex = 61

    local CCM_Input = Instance.new("TextBox")
    CCM_Input.Size = UDim2.new(1, -24, 0, 30)
    CCM_Input.Position = UDim2.new(0, 12, 0, 60)
    CCM_Input.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    CCM_Input.Text = ""
    CCM_Input.PlaceholderText = "config"
    CCM_Input.TextColor3 = Theme.Text
    CCM_Input.PlaceholderColor3 = Theme.TextDark
    CCM_Input.Font = Enum.Font.GothamMedium
    CCM_Input.TextSize = 14
    CCM_Input.ClearTextOnFocus = false
    CCM_Input.Parent = CreateConfigModal
    CCM_Input.ZIndex = 61

    local CCMI_Corner = Instance.new("UICorner", CCM_Input)
    CCMI_Corner.CornerRadius = UDim.new(0, 6)

    local CCM_CreateBtn = Instance.new("TextButton")
    CCM_CreateBtn.Size = UDim2.new(1, -24, 0, 30)
    CCM_CreateBtn.Position = UDim2.new(0, 12, 0, 104)
    CCM_CreateBtn.BackgroundColor3 = Theme.Accent
    CCM_CreateBtn.Text = "Создать"
    CCM_CreateBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    CCM_CreateBtn.Font = Enum.Font.GothamBold
    CCM_CreateBtn.TextSize = 14
    CCM_CreateBtn.Parent = CreateConfigModal
    CCM_CreateBtn.ZIndex = 61

    local CCMB_Corner = Instance.new("UICorner", CCM_CreateBtn)
    CCMB_Corner.CornerRadius = UDim.new(0, 6)

    -- Make ConfigFrame draggable (only when MainFrame visible)
    local function MakeConfigDraggable()
        local dragging, dragInput, dragStart, startPos

        table.insert(CheatEnv.Connections, ConfigHeader.InputBegan:Connect(function(input)
            if not MainFrame.Visible then return end
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = ConfigFrame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end))

        table.insert(CheatEnv.Connections, ConfigHeader.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end))

        table.insert(CheatEnv.Connections, UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                if not MainFrame.Visible then
                    dragging = false
                    return
                end
                local delta = input.Position - dragStart
                ConfigFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y)
                ConfigFrame:SetAttribute("UserMoved", true)
            end
        end))
    end

    MakeConfigDraggable()

    -- CONFIG SYSTEM UI LOGIC

    -- Update the config list UI
    ConfigSystem.UpdateUI = function()
        -- Clear existing items
        for _, child in pairs(ConfigListContainer:GetChildren()) do
            if child:IsA("Frame") then
                child:Destroy()
            end
        end

        -- Get configs
        local configs = ConfigSystem.GetList()
        local defaultConfig = ConfigSystem.GetDefault()

        for _, configName in ipairs(configs) do
            local Item = Instance.new("Frame")
            Item.Name = configName
            Item.Size = UDim2.new(1, -4, 0, 36)
            Item.BackgroundColor3 = Theme.Element
            Item.BorderSizePixel = 0
            Item.Parent = ConfigListContainer
            Item.ZIndex = 52

            local Item_Corner = Instance.new("UICorner", Item)
            Item_Corner.CornerRadius = UDim.new(0, 6)

            local ItemStroke = Instance.new("UIStroke", Item)
            ItemStroke.Color = Theme.Stroke
            ItemStroke.Thickness = 1
            ItemStroke.Transparency = 0.65

            -- Highlight if loaded or default
            local isLoaded = (ConfigSystem.LoadedConfigName == configName)
            local isDefault = (defaultConfig == configName)

            if isLoaded then
                ItemStroke.Color = Theme.Green
                ItemStroke.Thickness = 1.5
                ItemStroke.Transparency = 0.16
            end
            BindAnimatedCard(Item, ItemStroke, {
                BaseColor = Theme.Element,
                HoverColor = Theme.PanelSoft,
                BaseStrokeTransparency = ItemStroke.Transparency,
                HoverStrokeTransparency = isLoaded and 0.04 or 0.34,
                HoverScale = 1.004
            })

            -- Config Name Label
            local NameLabel = Instance.new("TextLabel")
            NameLabel.Size = UDim2.new(1, -102, 1, 0)
            NameLabel.Position = UDim2.new(0, 10, 0, 0)
            NameLabel.BackgroundTransparency = 1
            NameLabel.Text = configName .. (isDefault and " ⭐" or "")
            NameLabel.TextColor3 = isLoaded and Theme.Green or Theme.Text
            NameLabel.Font = Enum.Font.GothamMedium
            NameLabel.TextSize = 13
            NameLabel.TextXAlignment = Enum.TextXAlignment.Left
            NameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            NameLabel.Parent = Item
            NameLabel.ZIndex = 53

            -- Load Button
            local LoadBtn = Instance.new("TextButton")
            LoadBtn.Size = UDim2.new(0, 42, 0, 24)
            LoadBtn.Position = UDim2.new(1, -92, 0.5, -12)
            LoadBtn.BackgroundColor3 = Theme.Accent
            LoadBtn.Text = "Load"
            LoadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            LoadBtn.Font = Enum.Font.GothamBold
            LoadBtn.TextSize = 11
            LoadBtn.Parent = Item
            LoadBtn.ZIndex = 53

            local LB_Corner = Instance.new("UICorner", LoadBtn)
            LB_Corner.CornerRadius = UDim.new(0, 5)

            local LB_Stroke = Instance.new("UIStroke", LoadBtn)
            LB_Stroke.Color = Theme.Stroke
            LB_Stroke.Thickness = 1
            LB_Stroke.Transparency = 0.45
            BindAnimatedButton(LoadBtn, {
                Stroke = LB_Stroke,
                BaseColor = Theme.Accent,
                HoverColor = Theme.AccentSoft,
                PressColor = Theme.Accent,
                BaseStrokeTransparency = 0.45,
                HoverStrokeTransparency = 0.22,
                PressStrokeTransparency = 0.12,
                HoverScale = 1.02,
                PressScale = 0.95
            })

            -- Default Button
            local DefaultBtn = Instance.new("TextButton")
            DefaultBtn.Size = UDim2.new(0, 42, 0, 24)
            DefaultBtn.Position = UDim2.new(1, -46, 0.5, -12)
            DefaultBtn.BackgroundColor3 = isDefault and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(60, 60, 60)
            DefaultBtn.Text = "Def"
            DefaultBtn.TextColor3 = isDefault and Color3.fromRGB(0, 0, 0) or Theme.TextDark
            DefaultBtn.Font = Enum.Font.GothamBold
            DefaultBtn.TextSize = 11
            DefaultBtn.Parent = Item
            DefaultBtn.ZIndex = 53

            local DB_Corner = Instance.new("UICorner", DefaultBtn)
            DB_Corner.CornerRadius = UDim.new(0, 5)

            local DB_Stroke = Instance.new("UIStroke", DefaultBtn)
            DB_Stroke.Color = Theme.Stroke
            DB_Stroke.Thickness = 1
            DB_Stroke.Transparency = 0.5
            BindAnimatedButton(DefaultBtn, {
                Stroke = DB_Stroke,
                GetBaseColor = function()
                    return isDefault and Color3.fromRGB(255, 200, 50) or Color3.fromRGB(60, 60, 60)
                end,
                HoverColor = isDefault and Color3.fromRGB(255, 220, 110) or Color3.fromRGB(88, 88, 98),
                PressColor = isDefault and Color3.fromRGB(235, 180, 40) or Color3.fromRGB(50, 50, 58),
                BaseStrokeTransparency = 0.5,
                HoverStrokeTransparency = 0.28,
                PressStrokeTransparency = 0.16,
                HoverScale = 1.02,
                PressScale = 0.95
            })

            -- Load Button Click
            local loadConn = LoadBtn.MouseButton1Click:Connect(function()
                if ConfigSystem.DeleteMode or ConfigSystem.OverwriteMode then
                    ConfigSystem.SelectedConfig = configName
                    ConfigHint.Text = "Выбран: " .. configName .. ". Нажмите кнопку ещё раз."
                    return
                end

                local success = ConfigSystem.Load(configName)
            end)
            table.insert(CheatEnv.UIConnections, loadConn)

            -- Default Button Click
            local defConn = DefaultBtn.MouseButton1Click:Connect(function()
                ConfigSystem.SetDefault(configName)
            end)
            table.insert(CheatEnv.UIConnections, defConn)

            -- Selection for Delete/Overwrite
            local itemConn = Item.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    if ConfigSystem.DeleteMode or ConfigSystem.OverwriteMode then
                        ConfigSystem.SelectedConfig = configName
                        ConfigHint.Text = "Выбран: " .. configName .. ". Нажмите кнопку ещё раз."
                    end
                end
            end)
            table.insert(CheatEnv.UIConnections, itemConn)
        end
    end

    -- Button Hover Effects
    local function AddButtonHover(btn)
        if not btn then return end
        local stroke = btn:FindFirstChildOfClass("UIStroke")
        local baseColor = btn.BackgroundColor3
        BindAnimatedButton(btn, {
            Stroke = stroke,
            BaseColor = baseColor,
            HoverColor = baseColor:Lerp(Color3.new(1, 1, 1), 0.1),
            PressColor = baseColor:Lerp(Color3.new(0, 0, 0), 0.08),
            HoverScale = 1.015,
            PressScale = 0.96,
            BaseStrokeTransparency = stroke and stroke.Transparency or nil,
            HoverStrokeTransparency = stroke and 0.28 or nil,
            PressStrokeTransparency = stroke and 0.16 or nil
        })
    end

    AddButtonHover(Btn_Create)
    AddButtonHover(Btn_Delete)
    AddButtonHover(Btn_Overwrite)
    AddButtonHover(Btn_OpenFolder)

    -- CREATE BUTTON LOGIC
    local createConn = Btn_Create.MouseButton1Click:Connect(function()
        -- Cancel other modes
        ConfigSystem.DeleteMode = false
        ConfigSystem.OverwriteMode = false
        ConfigSystem.SelectedConfig = nil
        ConfigHint.Visible = false

        -- Position modal dynamically
        local cfPos = ConfigFrame.AbsolutePosition
        local activeCamera = Camera or Workspace.CurrentCamera
        local screenSize = activeCamera and activeCamera.ViewportSize or ScreenGui.AbsoluteSize

        if cfPos.X > screenSize.X / 2 then
            -- ConfigFrame is on right side, show modal on left
            CreateConfigModal.Position = UDim2.new(0, -232, 0, 0)
        else
            -- ConfigFrame is on left side, show modal on right
            CreateConfigModal.Position = UDim2.new(1, 12, 0, 0)
        end

        CreateConfigModal.Visible = not CreateConfigModal.Visible
        CCM_Input.Text = ""
    end)
    table.insert(CheatEnv.UIConnections, createConn)

    -- CREATE MODAL SUBMIT
    local createModalConn = CCM_CreateBtn.MouseButton1Click:Connect(function()
        local configName = CCM_Input.Text
        if configName == "" then
            configName = "config"
        end

        -- Sanitize name (remove invalid characters)
        configName = configName:gsub("[^%w%s%-_]", "")
        if configName == "" then configName = "config" end

        ConfigSystem.Save(configName)
        CreateConfigModal.Visible = false
        CCM_Input.Text = ""
    end)
    table.insert(CheatEnv.UIConnections, createModalConn)

    -- DELETE BUTTON LOGIC
    local deleteConn = Btn_Delete.MouseButton1Click:Connect(function()
        CreateConfigModal.Visible = false
        ConfigSystem.OverwriteMode = false

        if ConfigSystem.DeleteMode then
            -- Second click - perform delete
            if ConfigSystem.SelectedConfig then
                ConfigSystem.Delete(ConfigSystem.SelectedConfig)
                ConfigSystem.SelectedConfig = nil
            end
            ConfigSystem.DeleteMode = false
            ConfigHint.Visible = false
        else
            -- First click - enter delete mode
            ConfigSystem.DeleteMode = true
            ConfigSystem.SelectedConfig = nil
            ConfigHint.Text = "Выберите конфиг и нажмите Удалить ещё раз"
            ConfigHint.Visible = true
        end
    end)
    table.insert(CheatEnv.UIConnections, deleteConn)

    -- OVERWRITE BUTTON LOGIC
    local overwriteConn = Btn_Overwrite.MouseButton1Click:Connect(function()
        CreateConfigModal.Visible = false
        ConfigSystem.DeleteMode = false

        if ConfigSystem.OverwriteMode then
            -- Second click - perform overwrite
            if ConfigSystem.SelectedConfig then
                ConfigSystem.Save(ConfigSystem.SelectedConfig)
                ConfigSystem.SelectedConfig = nil
            end
            ConfigSystem.OverwriteMode = false
            ConfigHint.Visible = false
        else
            -- First click - enter overwrite mode
            ConfigSystem.OverwriteMode = true
            ConfigSystem.SelectedConfig = nil
            ConfigHint.Text = "Выберите конфиг и нажмите Перезаписать ещё раз"
            ConfigHint.Visible = true
        end
    end)
    table.insert(CheatEnv.UIConnections, overwriteConn)

    -- OPEN FOLDER BUTTON LOGIC
    local openFolderConn = Btn_OpenFolder.MouseButton1Click:Connect(function()
        ConfigSystem.EnsureFolder()
        if setclipboard then
            setclipboard(ConfigSystem.Path)
            print("✓ Config path copied to clipboard: " .. ConfigSystem.Path)
        end
        -- Some executors support openfolder
        pcall(function()
            if openfolder then
                openfolder(ConfigSystem.Path)
            end
        end)
    end)
    table.insert(CheatEnv.UIConnections, openFolderConn)

    -- Cancel modes when clicking elsewhere
    local cancelModesConn = ConfigFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            -- Small delay to allow button clicks to register first
            task.delay(0.1, function()
                if not ConfigSystem.DeleteMode and not ConfigSystem.OverwriteMode then return end
                -- If still in mode but no selection made on a config item, cancel
                -- This is handled by the button clicks themselves
            end)
        end
    end)
    table.insert(CheatEnv.UIConnections, cancelModesConn)

    -- Register UI elements
    table.insert(CheatEnv.UI, ConfigFrame)
    table.insert(CheatEnv.UI, CreateConfigModal)
end

local function GetUIViewportSize()
    local activeCamera = Camera or Workspace.CurrentCamera
    if activeCamera and activeCamera.ViewportSize.X > 0 and activeCamera.ViewportSize.Y > 0 then
        return activeCamera.ViewportSize
    end
    return ScreenGui.AbsoluteSize
end

local function ClampFrameToViewport(frame, viewport, padding)
    if not frame or not viewport then return end
    local absSize = frame.AbsoluteSize
    if absSize.X <= 0 or absSize.Y <= 0 then return end

    padding = padding or 8
    local absPos = frame.AbsolutePosition
    local maxX = viewport.X - absSize.X - padding
    local maxY = viewport.Y - absSize.Y - padding
    local clampedLeft = math_clamp(absPos.X, padding, math_max(padding, maxX))
    local clampedTop = math_clamp(absPos.Y, padding, math_max(padding, maxY))
    local anchor = frame.AnchorPoint

    frame.Position = UDim2.new(
        0,
        math.floor(clampedLeft + absSize.X * anchor.X + 0.5),
        0,
        math.floor(clampedTop + absSize.Y * anchor.Y + 0.5)
    )
end

local function ApplyResponsiveLayout()
    local viewport = GetUIViewportSize()
    if not viewport or viewport.X <= 0 or viewport.Y <= 0 then return end

    local menuWidth = math_clamp(math.floor(viewport.X * 0.8), 760, 1180)
    local menuHeight = math_clamp(math.floor(viewport.Y * 0.82), 520, 760)
    MainFrame.Size = UDim2.new(0, menuWidth, 0, menuHeight)

    if MainFrame:GetAttribute("UserMoved") then
        task.defer(function()
            local currentViewport = GetUIViewportSize()
            if currentViewport then
                ClampFrameToViewport(MainFrame, currentViewport, 8)
            end
        end)
    else
        MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    end

    local sidebarWidth = math_clamp(math.floor(menuWidth * 0.2), 186, 230)
    SideBar.Size = UDim2.new(0, sidebarWidth, 1, -24)
    ContentArea.Size = UDim2.new(1, -(sidebarWidth + 36), 1, -24)
    ContentArea.Position = UDim2.new(0, sidebarWidth + 24, 0, 12)

    local configWidth = math_clamp(math.floor(viewport.X * 0.24), 270, 340)
    local configHeight = math_clamp(math.floor(viewport.Y * 0.58), 340, 460)
    ConfigFrame.Size = UDim2.new(0, configWidth, 0, configHeight)

    if ConfigFrame:GetAttribute("UserMoved") then
        task.defer(function()
            local currentViewport = GetUIViewportSize()
            if currentViewport then
                ClampFrameToViewport(ConfigFrame, currentViewport, 8)
            end
        end)
    else
        ConfigFrame.Position = UDim2.new(1, -(configWidth + 16), 1, -(configHeight + 16))
    end
end

do
    local lastViewport = Vector2.new(-1, -1)
    local responsiveConn = RunService.RenderStepped:Connect(function()
        local viewport = GetUIViewportSize()
        if not viewport then return end
        if viewport.X == lastViewport.X and viewport.Y == lastViewport.Y then return end
        lastViewport = viewport
        ApplyResponsiveLayout()
    end)
    table.insert(CheatEnv.Connections, responsiveConn)
    task.defer(ApplyResponsiveLayout)
end

-- ============================================
-- ADDITION SECTION
-- ============================================

-- Проверка Place ID для MM2
local MM2Tab = nil
if game.PlaceId == MM2_Data.PLACE_ID then
    MM2Tab = CreateTabContainer("MM2", false)

    -- ✅ СОЗДАЁМ КНОПКУ MM2 ТОЛЬКО В MM2
    local MM2Button = CreateTabButton("MM2")
    MM2Button.LayoutOrder = 101 -- ✅ ПОСЛЕ "-- ADDITION --"
end

-- После блока MM2
local CounterBloxTab = nil
if game.PlaceId == 301549746 then
    CounterBloxTab = CreateTabContainer("CB", true)
    local CBButton = CreateTabButton("CB")
    CBButton.LayoutOrder = 102
end

-- SCP:RP Tab
local SCPRP_Tab = nil
if game.PlaceId == 5041144419 then
    SCPRP_Tab = CreateTabContainer("SCP:RP", false)
    local SCPRP_Button = CreateTabButton("SCP:RP")
    SCPRP_Button.LayoutOrder = 103
end

local function GetCurrentParent(tabName) return Tabs[tabName] end

SetFrameState = function(frame, enabled)
    if not frame then return end
    local alpha = enabled and 0 or 0.6
    local bgColor = enabled and Theme.Element or Theme.Disabled

    local function apply(inst)
        if inst:IsA("TextButton") or inst:IsA("TextBox") then
            inst.Active = enabled
        end
        if inst:IsA("TextLabel") then
            TweenService:Create(inst, TweenInfo.new(0.2), { TextTransparency = alpha }):Play()
        end
    end

    for _, v in pairs(frame:GetDescendants()) do apply(v) end
    TweenService:Create(frame, TweenInfo.new(0.2), { BackgroundColor3 = bgColor }):Play()
end

--// UI HELPER FUNCTIONS //--

local function IsAimbotActive(module)
    if module == "Aimlock" then
        if not Settings.Aimlock then return false end
        local trigger = Settings.AimlockTrigger or "N Key"
        if trigger == "N Key" then
            return AimlockEngaged
        end
        if trigger == "RMB Hold" then
            return AimlockState.RMBHeld
        end
        if trigger == "RMB Toggle" then
            return AimlockState.Engaged
        end
        return AimlockEngaged
    end

    if not Settings.Aimbot then return false end

    local trigger = Settings.AimbotTrigger or "T Toggle"
    if trigger == "T Toggle" or trigger == "Always" then
        return true
    end
    if trigger == "RMB Hold" then
        return AimbotState.RMBHeld
    end
    if trigger == "RMB Toggle" then
        return AimbotState.Engaged
    end
    return true
end

CheatEnv.FindKeybindBySetting = function(settingKey)
    for _, bindData in ipairs(Keybinds) do
        if bindData.Setting == settingKey then
            return bindData
        end
    end
    return nil
end

CheatEnv.GetBindDisplayText = function(bindData, wrapBrackets)
    if not bindData or not bindData.Key then
        return ".."
    end
    if wrapBrackets then
        local keyName = bindData.Key.Name or ""
        if #keyName > 3 then
            keyName = keyName:sub(1, 3)
        end
        return "[" .. keyName .. "]"
    end
    return bindData.Key.Name
end

CheatEnv.GetBindChipShortText = function(bindData)
    if not bindData or not bindData.Key then
        return ".."
    end
    local keyName = bindData.Key.Name or ""
    if #keyName > 3 then
        return keyName:sub(1, 3)
    end
    return keyName
end

CheatEnv.RefreshMenuBindChip = function(settingKey)
    local chipRefs = CheatEnv.KeybindChipRefs and CheatEnv.KeybindChipRefs[settingKey]
    if type(chipRefs) ~= "table" then
        return
    end

    local bindData = CheatEnv.FindKeybindBySetting(settingKey)
    local chipText = CheatEnv.GetBindChipShortText(bindData)
    for i = #chipRefs, 1, -1 do
        local chip = chipRefs[i]
        if chip and chip.Parent then
            chip.Text = chipText
        else
            table.remove(chipRefs, i)
        end
    end
end

CheatEnv.RefreshRebindWindowButton = function(settingKey)
    local rebindWindows = CheatEnv.RebindWindows
    if type(rebindWindows) ~= "table" then
        return
    end

    local state = rebindWindows[settingKey]
    if not state then
        return
    end

    if not state.Frame or not state.Frame.Parent then
        rebindWindows[settingKey] = nil
        return
    end

    if state.BindButton then
        state.BindButton.Text = CheatEnv.GetBindDisplayText(state.BindData, false)
        state.BindButton.BackgroundColor3 = Color3.fromRGB(52, 62, 80)
    end
end

CheatEnv.FinishRebindCapture = function(mode, newKey)
    local capture = CheatEnv.ActiveRebindCapture
    if type(capture) ~= "table" or not capture.Active then
        return false
    end

    CheatEnv.ActiveRebindCapture = nil

    local bindData = capture.BindData
    if mode == "apply" and bindData and newKey then
        for _, otherBind in ipairs(Keybinds) do
            if otherBind ~= bindData and otherBind.Key == newKey then
                otherBind.Key = nil
                CheatEnv.RefreshMenuBindChip(otherBind.Setting)
                CheatEnv.RefreshRebindWindowButton(otherBind.Setting)
            end
        end
        bindData.Key = newKey
    elseif mode == "clear" and bindData then
        bindData.Key = nil
    end

    local bindButton = capture.BindButton
    if bindButton and bindButton.Parent then
        bindButton.Text = CheatEnv.GetBindDisplayText(bindData, false)
        bindButton.BackgroundColor3 = Color3.fromRGB(52, 62, 80)
    end

    if bindData then
        CheatEnv.RefreshMenuBindChip(bindData.Setting)
        CheatEnv.RefreshRebindWindowButton(bindData.Setting)
    end

    if CheatEnv.UpdateKeybindList then
        CheatEnv.UpdateKeybindList()
    end
    return true
end

CheatEnv.BeginRebindCapture = function(bindData, bindButton)
    if not bindData or not bindButton then
        return
    end

    CheatEnv.FinishRebindCapture("cancel")

    CheatEnv.ActiveRebindCapture = {
        Active = true,
        BindData = bindData,
        BindButton = bindButton
    }

    bindButton.Text = "..."
    bindButton.BackgroundColor3 = Theme.Accent
end

CheatEnv.MakeRebindWindowDraggable = function(frame, dragHandle)
    if not frame or not dragHandle then return end
    local dragging, dragInput, dragStart, startPos

    TrackUIConnection(dragHandle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end))

    TrackUIConnection(dragHandle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    TrackUIConnection(UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
            frame:SetAttribute("UserMoved", true)
        end
    end))
end

CheatEnv.GetRebindSpawnPosition = function()
    local viewport = GetUIViewportSize()
    local baseX = 24
    local baseY = 160

    if viewport and viewport.X > 0 and viewport.Y > 0 then
        baseX = math.floor(viewport.X * 0.12)
        baseY = math.floor(viewport.Y * 0.32)
    end

    if MainFrame and MainFrame.Parent then
        local absPos = MainFrame.AbsolutePosition
        local absSize = MainFrame.AbsoluteSize
        if absSize.X > 0 and absSize.Y > 0 then
            baseX = absPos.X - 290
            baseY = absPos.Y + math.floor(absSize.Y * 0.3)
        end
    end

    local openCount = 0
    for _, state in pairs(CheatEnv.RebindWindows) do
        if state and state.Frame and state.Frame.Parent then
            openCount = openCount + 1
        end
    end

    return UDim2.new(0, baseX + (openCount % 4) * 16, 0, baseY + openCount * 24), openCount
end

CheatEnv.CloseRebindWindow = function(settingKey, animated)
    local windowState = CheatEnv.RebindWindows[settingKey]
    if not windowState then
        return
    end
    CheatEnv.RebindWindows[settingKey] = nil

    local capture = CheatEnv.ActiveRebindCapture
    if capture and capture.Active and capture.BindData and capture.BindData.Setting == settingKey then
        CheatEnv.FinishRebindCapture("cancel")
    end

    local frame = windowState.Frame
    if not frame or not frame.Parent then
        return
    end

    if not animated then
        frame:Destroy()
        return
    end

    local targetPos = UDim2.new(frame.Position.X.Scale, frame.Position.X.Offset, frame.Position.Y.Scale, frame.Position.Y.Offset + 10)
    TweenService:Create(frame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = targetPos,
        BackgroundTransparency = 1
    }):Play()

    local windowScale = frame:FindFirstChild("RebindScale")
    if windowScale and windowScale:IsA("UIScale") then
        TweenService:Create(windowScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Scale = 0.9
        }):Play()
    end

    task.delay(0.16, function()
        if frame and frame.Parent then
            frame:Destroy()
        end
    end)
end

CheatEnv.OpenRebindWindow = function(settingKey)
    local menuVisible = MainFrame and MainFrame.Visible
    if CheatEnv.MenuAnimState and CheatEnv.MenuAnimState.visible ~= nil then
        menuVisible = CheatEnv.MenuAnimState.visible
    end
    if not menuVisible then
        return
    end

    local bindData = CheatEnv.FindKeybindBySetting(settingKey)
    if not bindData then
        return
    end

    local existing = CheatEnv.RebindWindows[settingKey]
    if existing and existing.Frame and existing.Frame.Parent then
        local existingScale = EnsureControlScale(existing.Frame, "RebindScale")
        if existingScale then
            existingScale.Scale = 0.95
            TweenService:Create(existingScale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Scale = 1
            }):Play()
        end
        return
    end
    CheatEnv.RebindWindows[settingKey] = nil

    local spawnPos, openCount = CheatEnv.GetRebindSpawnPosition()
    local zBase = 80 + openCount * 2

    local frame = Instance.new("Frame")
    frame.Name = "Rebind_" .. settingKey
    frame.Size = UDim2.new(0, 312, 0, 164)
    frame.Position = spawnPos
    frame.BackgroundColor3 = Color3.fromRGB(10, 16, 28)
    frame.BackgroundTransparency = 0.02
    frame.BorderSizePixel = 0
    frame.ZIndex = zBase
    frame:SetAttribute("UserMoved", false)
    frame.Parent = ScreenGui
    table.insert(CheatEnv.UI, frame)

    local frameCorner = Instance.new("UICorner", frame)
    frameCorner.CornerRadius = UDim.new(0, 12)

    local frameStroke = Instance.new("UIStroke", frame)
    frameStroke.Color = Color3.fromRGB(52, 74, 108)
    frameStroke.Thickness = 1.15
    frameStroke.Transparency = 0.16
    frameStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local frameGlow = Instance.new("UIStroke", frame)
    frameGlow.Color = Theme.Accent
    frameGlow.Thickness = 2
    frameGlow.Transparency = 0.88
    frameGlow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

    local frameGradient = Instance.new("UIGradient", frame)
    frameGradient.Rotation = 126
    frameGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 26, 44)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(10, 16, 28)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 10, 18))
    })

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 42)
    header.BackgroundColor3 = Color3.fromRGB(14, 22, 40)
    header.BackgroundTransparency = 0.04
    header.BorderSizePixel = 0
    header.ZIndex = zBase + 1
    header.Parent = frame

    local headerCorner = Instance.new("UICorner", header)
    headerCorner.CornerRadius = UDim.new(0, 12)

    local headerStroke = Instance.new("UIStroke", header)
    headerStroke.Color = Color3.fromRGB(56, 82, 120)
    headerStroke.Thickness = 1
    headerStroke.Transparency = 0.34

    local headerGradient = Instance.new("UIGradient", header)
    headerGradient.Rotation = 105
    headerGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 36, 60)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 18, 34))
    })

    local topAccent = Instance.new("Frame")
    topAccent.Size = UDim2.new(1, -20, 0, 2)
    topAccent.Position = UDim2.new(0, 10, 0, 6)
    topAccent.BorderSizePixel = 0
    topAccent.BackgroundColor3 = Theme.Accent
    topAccent.ZIndex = zBase + 2
    topAccent.Parent = header

    local topAccentGradient = Instance.new("UIGradient", topAccent)
    topAccentGradient.Rotation = 0
    topAccentGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.Accent),
        ColorSequenceKeypoint.new(0.5, Theme.AccentSoft),
        ColorSequenceKeypoint.new(1, Theme.Accent)
    })

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -42, 0, 20)
    title.Position = UDim2.new(0, 16, 0, 11)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "REBIND"
    title.TextColor3 = Color3.fromRGB(230, 240, 255)
    title.TextSize = 13
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.ZIndex = zBase + 2
    title.Parent = header

    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -42, 0, 14)
    subtitle.Position = UDim2.new(0, 16, 0, 25)
    subtitle.BackgroundTransparency = 1
    subtitle.Font = Enum.Font.Gotham
    subtitle.Text = (bindData.Name or settingKey):upper() .. " BIND SETTINGS"
    subtitle.TextColor3 = Color3.fromRGB(154, 176, 206)
    subtitle.TextSize = 9
    subtitle.TextXAlignment = Enum.TextXAlignment.Center
    subtitle.ZIndex = zBase + 2
    subtitle.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 22, 0, 22)
    closeBtn.Position = UDim2.new(1, -27, 0, 10)
    closeBtn.BackgroundColor3 = Color3.fromRGB(70, 28, 36)
    closeBtn.Text = "X"
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 12
    closeBtn.TextColor3 = Color3.fromRGB(255, 135, 135)
    closeBtn.AutoButtonColor = false
    closeBtn.ZIndex = zBase + 2
    closeBtn.Parent = header

    local closeCorner = Instance.new("UICorner", closeBtn)
    closeCorner.CornerRadius = UDim.new(0, 6)

    local closeStroke = Instance.new("UIStroke", closeBtn)
    closeStroke.Color = Color3.fromRGB(120, 58, 68)
    closeStroke.Thickness = 1
    closeStroke.Transparency = 0.32

    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 50)
    row.Position = UDim2.new(0, 10, 0, 60)
    row.BackgroundColor3 = Color3.fromRGB(20, 28, 44)
    row.BackgroundTransparency = 0.04
    row.BorderSizePixel = 0
    row.ZIndex = zBase + 1
    row.Parent = frame

    local rowCorner = Instance.new("UICorner", row)
    rowCorner.CornerRadius = UDim.new(0, 9)

    local rowStroke = Instance.new("UIStroke", row)
    rowStroke.Color = Color3.fromRGB(50, 72, 104)
    rowStroke.Thickness = 1
    rowStroke.Transparency = 0.34

    local rowGradient = Instance.new("UIGradient", row)
    rowGradient.Rotation = 90
    rowGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 38, 58)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 24, 38))
    })

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -126, 1, 0)
    nameLabel.Position = UDim2.new(0, 12, 0, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = (bindData.Name or settingKey) .. ":"
    nameLabel.TextColor3 = Color3.fromRGB(232, 240, 255)
    nameLabel.Font = Enum.Font.GothamMedium
    nameLabel.TextSize = 12
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.ZIndex = zBase + 2
    nameLabel.Parent = row

    local bindButton = Instance.new("TextButton")
    bindButton.Size = UDim2.new(0, 92, 0, 30)
    bindButton.Position = UDim2.new(1, -100, 0.5, -15)
    bindButton.BackgroundColor3 = Color3.fromRGB(52, 62, 80)
    bindButton.BackgroundTransparency = 0.04
    bindButton.Text = CheatEnv.GetBindDisplayText(bindData, false)
    bindButton.TextColor3 = Color3.fromRGB(236, 243, 255)
    bindButton.Font = Enum.Font.GothamBold
    bindButton.TextSize = 11
    bindButton.AutoButtonColor = false
    bindButton.ZIndex = zBase + 2
    bindButton.Parent = row

    local bindBtnCorner = Instance.new("UICorner", bindButton)
    bindBtnCorner.CornerRadius = UDim.new(0, 7)

    local bindBtnStroke = Instance.new("UIStroke", bindButton)
    bindBtnStroke.Color = Color3.fromRGB(82, 106, 146)
    bindBtnStroke.Thickness = 1
    bindBtnStroke.Transparency = 0.28

    local bindBtnGradient = Instance.new("UIGradient", bindButton)
    bindBtnGradient.Rotation = 90
    bindBtnGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(66, 84, 112)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(44, 52, 70))
    })

    local hintLabel = Instance.new("TextLabel")
    hintLabel.Size = UDim2.new(1, -20, 0, 36)
    hintLabel.Position = UDim2.new(0, 10, 1, -42)
    hintLabel.BackgroundTransparency = 1
    hintLabel.Text = "Click/RMB/MMB on key box, then press key. ESC = cancel, BACKSPACE = clear."
    hintLabel.TextColor3 = Color3.fromRGB(150, 172, 202)
    hintLabel.Font = Enum.Font.Gotham
    hintLabel.TextSize = 9
    hintLabel.TextXAlignment = Enum.TextXAlignment.Left
    hintLabel.TextWrapped = true
    hintLabel.ZIndex = zBase + 1
    hintLabel.Parent = frame

    local rebindScale = EnsureControlScale(frame, "RebindScale")
    frame.Position = UDim2.new(spawnPos.X.Scale, spawnPos.X.Offset, spawnPos.Y.Scale, spawnPos.Y.Offset + 10)
    frame.BackgroundTransparency = 1
    frameStroke.Transparency = 1
    frameGlow.Transparency = 1
    if rebindScale then
        rebindScale.Scale = 0.9
    end
    TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
        Position = spawnPos,
        BackgroundTransparency = 0.02
    }):Play()
    TweenService:Create(frameStroke, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Transparency = 0.16
    }):Play()
    TweenService:Create(frameGlow, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Transparency = 0.88
    }):Play()
    if rebindScale then
        TweenService:Create(rebindScale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Scale = 1
        }):Play()
    end

    TrackUIConnection(closeBtn.MouseButton1Click:Connect(function()
        CheatEnv.CloseRebindWindow(settingKey, true)
    end))

    TrackUIConnection(closeBtn.MouseEnter:Connect(function()
        TweenService:Create(closeBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = Color3.fromRGB(88, 34, 46)
        }):Play()
    end))
    TrackUIConnection(closeBtn.MouseLeave:Connect(function()
        TweenService:Create(closeBtn, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = Color3.fromRGB(70, 28, 36)
        }):Play()
    end))

    TrackUIConnection(bindButton.InputBegan:Connect(function(input)
        local inputType = input.UserInputType
        if inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.MouseButton2 or inputType == Enum.UserInputType.MouseButton3 then
            CheatEnv.BeginRebindCapture(bindData, bindButton)
        end
    end))

    TrackUIConnection(bindButton.MouseEnter:Connect(function()
        TweenService:Create(bindButton, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = Color3.fromRGB(66, 80, 104)
        }):Play()
    end))
    TrackUIConnection(bindButton.MouseLeave:Connect(function()
        TweenService:Create(bindButton, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            BackgroundColor3 = Color3.fromRGB(52, 62, 80)
        }):Play()
    end))

    CheatEnv.MakeRebindWindowDraggable(frame, header)
    ClampFrameToViewport(frame, GetUIViewportSize(), 8)

    CheatEnv.RebindWindows[settingKey] = {
        Frame = frame,
        BindButton = bindButton,
        BindData = bindData
    }
end

CheatEnv.CreateParticleLine = function(parent, x1, y1, x2, y2, thickness, zIndex)
    local line = Instance.new("Frame")
    line.AnchorPoint = Vector2.new(0, 0.5)
    line.BackgroundColor3 = Color3.new(1, 1, 1)
    line.BorderSizePixel = 0
    line.ZIndex = zIndex or 66
    line.Parent = parent

    local dx = x2 - x1
    local dy = y2 - y1
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.001 then
        length = 0.001
    end

    local angle = 0
    if math.abs(dx) < 0.0001 then
        angle = (dy >= 0) and 90 or -90
    else
        angle = math.deg(math.atan(dy / dx))
        if dx < 0 then
            angle = angle + 180
        end
    end

    line.Position = UDim2.new(0, x1, 0, y1)
    line.Size = UDim2.new(0, length, 0, thickness or 2)
    line.Rotation = angle
    return line
end

CheatEnv.GetBlurParticleDirection = function()
    local dx = tonumber(Settings.UI_BP_DirX) or -1
    local dy = tonumber(Settings.UI_BP_DirY) or 1
    local magnitude = math.sqrt(dx * dx + dy * dy)
    if magnitude < 0.001 then
        return Vector2.new(-0.7071, 0.7071)
    end
    return Vector2.new(dx / magnitude, dy / magnitude)
end

CheatEnv.BuildBlurParticleVisual = function(holder, kind, size, zIndex)
    local nodes = {}
    local function addNode(node)
        nodes[#nodes + 1] = node
        return node
    end

    local function addStarShape(cx, cy, outerRadius, innerRadius, thickness)
        local points = {}
        for i = 0, 9 do
            local angle = math.rad(-90 + i * 36)
            local radius = (i % 2 == 0) and outerRadius or innerRadius
            points[#points + 1] = Vector2.new(
                cx + math.cos(angle) * radius,
                cy + math.sin(angle) * radius
            )
        end
        for i = 1, #points do
            local p1 = points[i]
            local p2 = points[(i % #points) + 1]
            addNode(CheatEnv.CreateParticleLine(holder, p1.X, p1.Y, p2.X, p2.Y, thickness, zIndex))
        end
    end

    local function addDiamond(x, y, radius)
        local diamond = Instance.new("Frame")
        diamond.AnchorPoint = Vector2.new(0.5, 0.5)
        diamond.Size = UDim2.new(0, radius * 2, 0, radius * 2)
        diamond.Position = UDim2.new(0, x, 0, y)
        diamond.Rotation = 45
        diamond.BackgroundColor3 = Color3.new(1, 1, 1)
        diamond.BorderSizePixel = 0
        diamond.ZIndex = zIndex
        diamond.Parent = holder
        addNode(diamond)
    end

    local function addDot(x, y, radius)
        local dot = Instance.new("Frame")
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
        dot.Size = UDim2.new(0, radius * 2, 0, radius * 2)
        dot.Position = UDim2.new(0, x, 0, y)
        dot.BackgroundColor3 = Color3.new(1, 1, 1)
        dot.BorderSizePixel = 0
        dot.ZIndex = zIndex
        dot.Parent = holder

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = dot
        addNode(dot)
    end

    if kind == "starfall" then
        addStarShape(size * 0.44, size * 0.56, size * 0.2, size * 0.09, math.max(1, size * 0.055))

        local trailThickness = math.max(1, size * 0.048)
        for i = 0, 4 do
            local offset = i * size * 0.07
            addNode(CheatEnv.CreateParticleLine(
                holder,
                size * (0.94 - i * 0.06),
                size * (0.14 + i * 0.05),
                size * (0.60 - i * 0.08),
                size * (0.46 + i * 0.06),
                trailThickness,
                zIndex
            ))
        end

        addDiamond(size * 0.74, size * 0.2, math.max(2, size * 0.055))
        addDiamond(size * 0.83, size * 0.66, math.max(2, size * 0.05))
        addDiamond(size * 0.28, size * 0.35, math.max(1.8, size * 0.048))
        addDiamond(size * 0.62, size * 0.8, math.max(1.5, size * 0.04))

        addDot(size * 0.26, size * 0.84, math.max(1.4, size * 0.025))
        addDot(size * 0.68, size * 0.36, math.max(1.2, size * 0.021))
        addDot(size * 0.77, size * 0.52, math.max(1.1, size * 0.018))
        addDot(size * 0.48, size * 0.18, math.max(1.0, size * 0.016))
        addDot(size * 0.57, size * 0.74, math.max(0.9, size * 0.014))
    else
        addStarShape(size * 0.5, size * 0.5, size * 0.43, size * 0.18, math.max(1, size * 0.08))
    end

    return nodes
end

CheatEnv.GetBlurParticleSpawn = function(viewport, direction)
    local margin = 60
    local spawnX
    local spawnY

    if direction.X < -0.2 then
        spawnX = viewport.X + margin + math.random() * 60
    elseif direction.X > 0.2 then
        spawnX = -margin - math.random() * 60
    else
        spawnX = math.random() * viewport.X
    end

    if direction.Y > 0.2 then
        spawnY = -margin - math.random() * 60
    elseif direction.Y < -0.2 then
        spawnY = viewport.Y + margin + math.random() * 60
    else
        spawnY = math.random() * viewport.Y
    end

    if math.abs(direction.X) > math.abs(direction.Y) then
        spawnY = spawnY + (math.random() - 0.5) * viewport.Y * 0.35
    else
        spawnX = spawnX + (math.random() - 0.5) * viewport.X * 0.35
    end

    return Vector2.new(spawnX, spawnY)
end

CheatEnv.SpawnBlurParticle = function(viewport)
    local canvas = CheatEnv.UI_Elements["BlurParticleCanvas"]
    if not canvas or not canvas.Parent then
        return nil
    end

    local sizeBase = math.max(8, tonumber(Settings.UI_BP_Size) or 24)
    local size = math.max(8, sizeBase * (0.65 + math.random() * 0.8))
    local direction = CheatEnv.GetBlurParticleDirection()
    local position = CheatEnv.GetBlurParticleSpawn(viewport, direction)

    local holder = Instance.new("Frame")
    holder.Name = "BlurParticle"
    holder.AnchorPoint = Vector2.new(0.5, 0.5)
    holder.Size = UDim2.new(0, size, 0, size)
    holder.Position = UDim2.new(0, position.X, 0, position.Y)
    holder.BackgroundTransparency = 1
    holder.BorderSizePixel = 0
    holder.ZIndex = 66
    holder.Parent = canvas

    local kind = (math.random() < 0.58) and "star" or "starfall"
    local nodes = CheatEnv.BuildBlurParticleVisual(holder, kind, size, 66)

    local baseSpeed = math.max(20, tonumber(Settings.UI_BP_Speed) or 180)
    local speed = baseSpeed * (0.55 + math.random() * 0.95)
    local perpendicular = Vector2.new(-direction.Y, direction.X)
    local sideDrift = (math.random() - 0.5) * baseSpeed * 0.35
    local velocity = direction * speed + perpendicular * sideDrift

    return {
        Holder = holder,
        Nodes = nodes,
        Position = position,
        Velocity = velocity,
        Spin = (math.random() - 0.5) * 90,
        HueOffset = math.random(),
        Transparency = 0.15 + math.random() * 0.3
    }
end

CheatEnv.ResetBlurParticles = function(removeBlurEffect)
    local state = CheatEnv.BlurParticleState
    if type(state) == "table" and type(state.Particles) == "table" then
        for i = #state.Particles, 1, -1 do
            local particle = state.Particles[i]
            if particle and particle.Holder and particle.Holder.Parent then
                particle.Holder:Destroy()
            end
            state.Particles[i] = nil
        end
    end

    local canvas = CheatEnv.UI_Elements["BlurParticleCanvas"]
    if canvas and canvas.Parent then
        canvas:Destroy()
    end
    CheatEnv.UI_Elements["BlurParticleCanvas"] = nil

    local blurEffect = CheatEnv.UI_Elements["BlurParticleBlurEffect"]
    if blurEffect then
        if removeBlurEffect then
            blurEffect:Destroy()
            CheatEnv.UI_Elements["BlurParticleBlurEffect"] = nil
        else
            blurEffect.Enabled = false
            blurEffect.Size = 0
        end
    end
end

CheatEnv.ApplyBlurParticleState = function(forceReset)
    if not Settings.UI_BlurParticles then
        CheatEnv.ResetBlurParticles(false)
        return
    end

    if forceReset then
        CheatEnv.ResetBlurParticles(false)
    end

    if type(CheatEnv.BlurParticleState) ~= "table" then
        CheatEnv.BlurParticleState = {
            Particles = {},
            LastTick = tick()
        }
    elseif type(CheatEnv.BlurParticleState.Particles) ~= "table" then
        CheatEnv.BlurParticleState.Particles = {}
    end

    if not CheatEnv.UI_Elements["BlurParticleCanvas"] then
        local canvas = Instance.new("Frame")
        canvas.Name = "BlurParticleCanvas"
        canvas.BackgroundTransparency = 1
        canvas.BorderSizePixel = 0
        canvas.Size = UDim2.new(1, 0, 1, 0)
        canvas.Position = UDim2.new(0, 0, 0, 0)
        canvas.ZIndex = 65
        canvas.Parent = ScreenGui
        CheatEnv.UI_Elements["BlurParticleCanvas"] = canvas
        table.insert(CheatEnv.UI, canvas)
    end

    local blurEffect = CheatEnv.UI_Elements["BlurParticleBlurEffect"]
    if not blurEffect then
        blurEffect = Instance.new("BlurEffect")
        blurEffect.Name = "VAYS_BlurParticles"
        blurEffect.Parent = Lighting
        CheatEnv.UI_Elements["BlurParticleBlurEffect"] = blurEffect
    end
    blurEffect.Enabled = true
    blurEffect.Size = math.max(0, tonumber(Settings.UI_BP_Blur) or 10)
end

CheatEnv.UpdateBlurParticles = function(dt)
    if not Settings.UI_BlurParticles then
        return
    end

    if not CheatEnv.UI_Elements["BlurParticleCanvas"] then
        CheatEnv.ApplyBlurParticleState(false)
    end

    local canvas = CheatEnv.UI_Elements["BlurParticleCanvas"]
    if not canvas or not canvas.Parent then
        return
    end

    local viewport = GetUIViewportSize()
    if not viewport or viewport.X <= 0 or viewport.Y <= 0 then
        return
    end

    canvas.Size = UDim2.new(0, viewport.X, 0, viewport.Y)

    local blurEffect = CheatEnv.UI_Elements["BlurParticleBlurEffect"]
    if blurEffect then
        blurEffect.Enabled = true
        blurEffect.Size = math.max(0, tonumber(Settings.UI_BP_Blur) or 10)
    end

    local state = CheatEnv.BlurParticleState
    if type(state) ~= "table" then
        state = { Particles = {}, LastTick = tick() }
        CheatEnv.BlurParticleState = state
    end
    if type(state.Particles) ~= "table" then
        state.Particles = {}
    end

    local particles = state.Particles
    local particleCount = #particles
    local targetCount = math.clamp(math.floor(tonumber(Settings.UI_BP_Count) or 26), 8, 80)
    local direction = CheatEnv.GetBlurParticleDirection()
    local speedBase = math.max(20, tonumber(Settings.UI_BP_Speed) or 180)
    local now = tick()

    for i = particleCount, 1, -1 do
        local particle = particles[i]
        if not particle or not particle.Holder or not particle.Holder.Parent then
            table.remove(particles, i)
        else
            local currentSpeed = particle.Velocity.Magnitude
            if currentSpeed < 1 then
                currentSpeed = speedBase
            end
            local targetVelocity = direction * currentSpeed
            local alignAlpha = math.min(1, dt * 1.1)
            particle.Velocity = particle.Velocity + (targetVelocity - particle.Velocity) * alignAlpha

            particle.Position = particle.Position + particle.Velocity * dt
            particle.Holder.Position = UDim2.new(0, particle.Position.X, 0, particle.Position.Y)
            particle.Holder.Rotation = particle.Holder.Rotation + particle.Spin * dt

            local hue = (now * 0.22 + particle.HueOffset) % 1
            local rainbow = Color3.fromHSV(hue, 1, 1)
            for n = 1, #particle.Nodes do
                local node = particle.Nodes[n]
                if node and node.Parent then
                    node.BackgroundColor3 = rainbow
                    node.BackgroundTransparency = particle.Transparency
                end
            end

            if particle.Position.X < -100 or particle.Position.X > viewport.X + 100 or
                particle.Position.Y < -100 or particle.Position.Y > viewport.Y + 100 then
                particle.Holder:Destroy()
                table.remove(particles, i)
            end
        end
    end

    local addLimit = 6
    while #particles < targetCount and addLimit > 0 do
        local newParticle = CheatEnv.SpawnBlurParticle(viewport)
        if newParticle then
            particles[#particles + 1] = newParticle
        end
        addLimit = addLimit - 1
    end
end

local function UpdateKeybindList()
    if not KeybindFrame or not KeybindFrame.Parent then return end

    local keybindGlowStroke = CheatEnv.UI_Elements["KeybindGlowStroke"]

    local activeBinds = {}
    for _, bind in ipairs(Keybinds) do
        if bind.Setting ~= "Unload" then
            local isShown = false
            if bind.Setting == "Aimlock" then
                isShown = IsAimbotActive("Aimlock")
            elseif bind.Setting == "Aimbot" then
                isShown = IsAimbotActive()
            elseif Settings[bind.Setting] then
                isShown = true
            end

            if isShown then
                table.insert(activeBinds, bind)
            end
        end
    end

    local activeCount = #activeBinds
    local rowPool = CheatEnv.KeybindRowPool
    if not rowPool then
        rowPool = {}
        CheatEnv.KeybindRowPool = rowPool
    end

    local headerBar = CheatEnv.UI_Elements["KeybindHeaderBar"]
    local counterLabel = CheatEnv.UI_Elements["KeybindCounterLabel"]

    if not headerBar then
        headerBar = Instance.new("Frame")
        headerBar.Name = "HeaderBar"
        headerBar.Size = UDim2.new(1, 0, 0, 34)
        headerBar.BackgroundColor3 = Color3.fromRGB(14, 20, 34)
        headerBar.BackgroundTransparency = 0.04
        headerBar.BorderSizePixel = 0
        headerBar.LayoutOrder = 0

        local HB_Corner = Instance.new("UICorner", headerBar)
        HB_Corner.CornerRadius = UDim.new(0, 7)

        local HB_Stroke = Instance.new("UIStroke", headerBar)
        HB_Stroke.Color = Color3.fromRGB(48, 66, 100)
        HB_Stroke.Thickness = 1
        HB_Stroke.Transparency = 0.38

        local HB_Gradient = Instance.new("UIGradient", headerBar)
        HB_Gradient.Rotation = 105
        HB_Gradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 34, 56)),
            ColorSequenceKeypoint.new(0.6, Color3.fromRGB(14, 20, 34)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 14, 24))
        })

        local Accent = Instance.new("Frame")
        Accent.Size = UDim2.new(0, 4, 1, -10)
        Accent.Position = UDim2.new(0, 6, 0, 5)
        Accent.BackgroundColor3 = Theme.Accent
        Accent.BorderSizePixel = 0
        Accent.Parent = headerBar

        local AccentCorner = Instance.new("UICorner", Accent)
        AccentCorner.CornerRadius = UDim.new(0, 3)

        local Header = Instance.new("TextLabel")
        Header.Name = "Header"
        Header.Size = UDim2.new(1, -92, 1, 0)
        Header.Position = UDim2.new(0, 16, 0, 0)
        Header.BackgroundTransparency = 1
        Header.Text = "LIVE KEYBINDS"
        Header.TextColor3 = Color3.fromRGB(236, 243, 255)
        Header.Font = Enum.Font.GothamBold
        Header.TextSize = 13
        Header.TextXAlignment = Enum.TextXAlignment.Left
        Header.Parent = headerBar

        counterLabel = Instance.new("TextLabel")
        counterLabel.Name = "Counter"
        counterLabel.Size = UDim2.new(0, 70, 0, 22)
        counterLabel.Position = UDim2.new(1, -76, 0.5, -11)
        counterLabel.BackgroundColor3 = Color3.fromRGB(22, 38, 56)
        counterLabel.BackgroundTransparency = 0.05
        counterLabel.TextColor3 = Theme.Accent
        counterLabel.Font = Enum.Font.GothamBold
        counterLabel.TextSize = 11
        counterLabel.Text = "0"
        counterLabel.Parent = headerBar

        local CounterCorner = Instance.new("UICorner", counterLabel)
        CounterCorner.CornerRadius = UDim.new(0, 6)

        local CounterStroke = Instance.new("UIStroke", counterLabel)
        CounterStroke.Color = Color3.fromRGB(72, 96, 132)
        CounterStroke.Thickness = 1
        CounterStroke.Transparency = 0.4

        CheatEnv.UI_Elements["KeybindHeaderBar"] = headerBar
        CheatEnv.UI_Elements["KeybindCounterLabel"] = counterLabel
        table.insert(CheatEnv.UI, headerBar)
    end

    -- Pooling: remove rows from layout without destroying instances.
    for i = 1, #rowPool do
        local row = rowPool[i]
        if row and row.Frame then
            row.Frame.Parent = nil
        end
    end
    headerBar.Parent = nil

    if activeCount == 0 then
        KeybindFrame.Visible = false
        KeybindFrame.Size = UDim2.new(0, 256, 0, 0)
        KeybindFrame.BackgroundTransparency = 1
        if KB_Stroke then
            KB_Stroke.Transparency = 1
        end
        if keybindGlowStroke then
            keybindGlowStroke.Transparency = 1
        end
        return
    end

    KeybindFrame.Visible = true
    if counterLabel then
        counterLabel.Text = tostring(activeCount) .. " ON"
    end

    headerBar.Parent = KeybindFrame

    for i = 1, activeCount do
        local bind = activeBinds[i]
        local row = rowPool[i]

        if not row then
            local line = Instance.new("Frame")
            line.Size = UDim2.new(1, 0, 0, 28)
            line.BackgroundColor3 = Color3.fromRGB(16, 22, 34)
            line.BackgroundTransparency = 0.01
            line.BorderSizePixel = 0

            local lineCorner = Instance.new("UICorner", line)
            lineCorner.CornerRadius = UDim.new(0, 6)

            local lineStroke = Instance.new("UIStroke", line)
            lineStroke.Color = Color3.fromRGB(36, 52, 78)
            lineStroke.Thickness = 1
            lineStroke.Transparency = 0.42

            local lineGradient = Instance.new("UIGradient", line)
            lineGradient.Rotation = 95
            lineGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(20, 28, 42)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(14, 18, 30))
            })

            local lineAccent = Instance.new("Frame", line)
            lineAccent.Size = UDim2.new(0, 3, 1, -10)
            lineAccent.Position = UDim2.new(0, 5, 0, 5)
            lineAccent.BorderSizePixel = 0

            local lineAccentCorner = Instance.new("UICorner", lineAccent)
            lineAccentCorner.CornerRadius = UDim.new(0, 2)

            local iconLbl = Instance.new("TextLabel", line)
            iconLbl.Size = UDim2.new(0, 16, 1, 0)
            iconLbl.Position = UDim2.new(0, 13, 0, 0)
            iconLbl.BackgroundTransparency = 1
            iconLbl.TextColor3 = Color3.fromRGB(245, 245, 245)
            iconLbl.Font = Enum.Font.GothamBold
            iconLbl.TextSize = 13

            local nameLbl = Instance.new("TextLabel", line)
            nameLbl.Size = UDim2.new(1, -142, 1, 0)
            nameLbl.Position = UDim2.new(0, 32, 0, 0)
            nameLbl.BackgroundTransparency = 1
            nameLbl.TextColor3 = Color3.fromRGB(235, 242, 255)
            nameLbl.Font = Enum.Font.GothamMedium
            nameLbl.TextSize = 12
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left

            local keyChip = Instance.new("TextButton", line)
            keyChip.Size = UDim2.new(0, 54, 0, 20)
            keyChip.Position = UDim2.new(1, -116, 0.5, -10)
            keyChip.BackgroundColor3 = Color3.fromRGB(34, 42, 58)
            keyChip.BackgroundTransparency = 0.05
            keyChip.BorderSizePixel = 0
            keyChip.TextColor3 = Color3.fromRGB(232, 238, 248)
            keyChip.Font = Enum.Font.GothamBold
            keyChip.TextSize = 9
            keyChip.AutoButtonColor = false

            local keyChipCorner = Instance.new("UICorner", keyChip)
            keyChipCorner.CornerRadius = UDim.new(0, 5)

            local keyChipStroke = Instance.new("UIStroke", keyChip)
            keyChipStroke.Color = Color3.fromRGB(58, 74, 104)
            keyChipStroke.Thickness = 1
            keyChipStroke.Transparency = 0.36

            local keyChipGradient = Instance.new("UIGradient", keyChip)
            keyChipGradient.Rotation = 90
            keyChipGradient.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(44, 56, 76)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(30, 36, 50))
            })

            TrackUIConnection(keyChip.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton2 and row and row.BindData and row.BindData.Setting then
                    CheatEnv.OpenRebindWindow(row.BindData.Setting)
                end
            end))

            TrackUIConnection(keyChip.MouseEnter:Connect(function()
                TweenService:Create(keyChip, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    BackgroundTransparency = 0
                }):Play()
            end))
            TrackUIConnection(keyChip.MouseLeave:Connect(function()
                TweenService:Create(keyChip, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    BackgroundTransparency = 0.05
                }):Play()
            end))

            local statusChip = Instance.new("TextLabel", line)
            statusChip.Size = UDim2.new(0, 52, 0, 20)
            statusChip.Position = UDim2.new(1, -56, 0.5, -10)
            statusChip.BackgroundColor3 = Color3.fromRGB(24, 66, 46)
            statusChip.BackgroundTransparency = 0.05
            statusChip.BorderSizePixel = 0
            statusChip.Text = "ENABLED"
            statusChip.TextColor3 = Color3.fromRGB(120, 255, 170)
            statusChip.Font = Enum.Font.GothamBold
            statusChip.TextSize = 9

            local statusChipCorner = Instance.new("UICorner", statusChip)
            statusChipCorner.CornerRadius = UDim.new(0, 5)

            local statusChipStroke = Instance.new("UIStroke", statusChip)
            statusChipStroke.Color = Color3.fromRGB(70, 112, 90)
            statusChipStroke.Thickness = 1
            statusChipStroke.Transparency = 0.4

            row = {
                Frame = line,
                Accent = lineAccent,
                Icon = iconLbl,
                NameLabel = nameLbl,
                KeyChip = keyChip,
                StatusChip = statusChip
            }
            rowPool[i] = row
            table.insert(CheatEnv.UI, line)
        end

        local bindColor = KeybindColors[bind.Setting] or KeybindColors.Default
        row.Accent.BackgroundColor3 = bindColor
        row.Icon.Text = KeybindIcons[bind.Setting] or KeybindIcons.Default
        row.Icon.TextColor3 = bindColor:Lerp(Color3.fromRGB(245, 248, 255), 0.45)
        row.NameLabel.Text = bind.Name:upper()
        row.BindData = bind
        if row.StatusChip then
            row.StatusChip.BackgroundColor3 = bindColor:Lerp(Color3.fromRGB(18, 26, 38), 0.78)
            row.StatusChip.TextColor3 = bindColor:Lerp(Color3.fromRGB(238, 245, 255), 0.35)
        end
        if Settings.KeybindsEnableLabel then
            row.KeyChip.Text = "Enable"
        else
            row.KeyChip.Text = CheatEnv.GetBindDisplayText(bind, true)
        end

        row.Frame.LayoutOrder = i + 1
        row.Frame.Parent = KeybindFrame
    end

    local targetHeight = activeCount * 28 + 56
    TweenService:Create(KeybindFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        { Size = UDim2.new(0, 256, 0, targetHeight) }):Play()
    TweenService:Create(KeybindFrame, TweenInfo.new(0.2), { BackgroundTransparency = 0.02 })
        :Play()

    if KB_Stroke then
        TweenService:Create(KB_Stroke, TweenInfo.new(0.2), { Transparency = 0.12 }):Play()
    end
    if keybindGlowStroke then
        TweenService:Create(keybindGlowStroke, TweenInfo.new(0.2), { Transparency = 0.8 }):Play()
    end
end
CheatEnv.UpdateKeybindList = UpdateKeybindList

SyncButton = function(settingKey)
    local toggle = CheatEnv.Toggles[settingKey]
    if not toggle then return end

    local isActive = Settings[settingKey]
    local color = isActive and Theme.Accent or Theme.Disabled
    TweenService:Create(toggle, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = color }):Play()
    TweenControlScale(toggle, 1.04, 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    task.delay(0.09, function()
        if toggle and toggle.Parent then
            TweenControlScale(toggle, 1, 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        end
    end)

    toggle.Text = ""
    toggle.TextColor3 = isActive and Color3.fromRGB(12, 20, 28) or Theme.TextDark

    local meta = CheatEnv.ToggleMeta and CheatEnv.ToggleMeta[settingKey]
    if meta then
        if meta.Knob then
            local targetPos = isActive and UDim2.new(1, -24, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)
            TweenService:Create(meta.Knob, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = targetPos
            }):Play()
        end
        if meta.AccentBar then
            TweenService:Create(meta.AccentBar, TweenInfo.new(0.2), {
                BackgroundColor3 = isActive and Theme.Accent or Theme.Disabled
            }):Play()
        end
        if meta.BtnGradient then
            if isActive then
                meta.BtnGradient.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 210, 255)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 170, 240))
                })
            else
                meta.BtnGradient.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Theme.Disabled),
                    ColorSequenceKeypoint.new(1, Theme.Disabled)
                })
            end
        end
        if meta.ButtonStroke then
            meta.ButtonStroke.Color = isActive and Theme.Accent or Theme.CardBorder
        end
    end
end

-- [NEW] Storage for sliders and dropdowns to enable refresh on config load
CheatEnv.Sliders = {}   -- {settingKey = {Frame, Label, SliderFill, Knob, min, max, isFloat, text}}
CheatEnv.Dropdowns = {} -- {settingKey = {MainBtn}}

-- [NEW] Function to refresh all sliders visually
local function RefreshSliders()
    for settingKey, sliderData in pairs(CheatEnv.Sliders) do
        local value = Settings[settingKey]
        if value ~= nil and sliderData then
            local percent = (value - sliderData.min) / (sliderData.max - sliderData.min)
            percent = math.clamp(percent, 0, 1)

            if sliderData.SliderFill then
                sliderData.SliderFill.Size = UDim2.new(percent, 0, 1, 0)
            end
            if sliderData.Knob then
                sliderData.Knob.Position = UDim2.new(percent, 0, 0.5, 0)
            end

            if sliderData.ValueBadge then
                if sliderData.isFloat then
                    sliderData.ValueBadge.Text = string.format("%.2f", value)
                else
                    sliderData.ValueBadge.Text = tostring(value)
                end
            elseif sliderData.Label then
                if sliderData.isFloat then
                    sliderData.Label.Text = sliderData.text .. ": " .. string.format("%.2f", value)
                else
                    sliderData.Label.Text = sliderData.text .. ": " .. tostring(value)
                end
            end
        end
    end
end

-- [NEW] Function to refresh all dropdowns visually
local function RefreshDropdowns()
    for settingKey, dropdownData in pairs(CheatEnv.Dropdowns) do
        local value = Settings[settingKey]
        if value ~= nil and dropdownData and dropdownData.MainBtn then
            dropdownData.MainBtn.Text = value .. " ▼"
        end
    end
end

-- [NEW] Refresh all UI elements (called on config load)
ConfigSystem.RefreshAllUI = function()
    RefreshSliders()
    RefreshDropdowns()
end

-- [UPDATED] Fixed Team Check Dependencies
UpdateTeamCheckDependencies = function()
    -- Если TC_Hide (скрыть ESP тимейтов) ВКЛЮЧЕН, мы должны отключить возможность красить их в зеленый
    if Settings.TC_Hide then
        -- Скрываем ESP полностью, значит опция "Green" бесполезна
        if CheatEnv.Toggles["TC_Green"] then
            -- Визуальное отключение
            local frame = CheatEnv.Toggles["TC_Green"]:FindFirstAncestorOfClass("Frame")
            if frame then SetFrameState(frame, false) end
        end
    else
        -- Если мы видим тимейтов, мы можем их красить
        if CheatEnv.Toggles["TC_Green"] then
            local frame = CheatEnv.Toggles["TC_Green"]:FindFirstAncestorOfClass("Frame")
            if frame then SetFrameState(frame, true) end
        end
    end
end

UpdateESPBoxDependencies = function()
    local boxEnabled = Settings.ESP_Box

    if not boxEnabled then
        if Settings.ESP_CornerBox then
            Settings.ESP_CornerBox = false
            SyncButton("ESP_CornerBox")
        end
        if Settings.ESP_BoxFill then
            Settings.ESP_BoxFill = false
            SyncButton("ESP_BoxFill")
        end
    end

    local cornerToggle = CheatEnv.Toggles["ESP_CornerBox"]
    if cornerToggle and cornerToggle.Parent then
        SetFrameState(cornerToggle.Parent, boxEnabled)
    end

    local fillToggle = CheatEnv.Toggles["ESP_BoxFill"]
    if fillToggle and fillToggle.Parent then
        SetFrameState(fillToggle.Parent, boxEnabled)
    end

    local fillSliderFrame = CheatEnv.UI_Elements["ESP_BoxFillTransparency_Frame"]
    if fillSliderFrame then
        SetFrameState(fillSliderFrame, boxEnabled and Settings.ESP_BoxFill)
    end
end

UpdatePredictionDependencies = function()
    local predictionEnabled = Settings.PredictionEnabled == true
    local predictionMode = Settings.PredictionMode or "Standard"
    local filterMode = Settings.PredictionFilter or "Adaptive Kalman"
    local filterEnabled = predictionEnabled and filterMode ~= "None"
    local adaptiveFilterEnabled = predictionEnabled and filterMode == "Adaptive Kalman"

    local standardOnlyFrame = CheatEnv.UI_Elements["PredictionSlider"]
    if standardOnlyFrame then
        SetFrameState(standardOnlyFrame, predictionEnabled and predictionMode == "Standard")
    end

    local commonPredictionFrames = {
        "PredictionIterationsFrame",
        "PredictionConfidenceFloorFrame"
    }
    for i = 1, #commonPredictionFrames do
        local frame = CheatEnv.UI_Elements[commonPredictionFrames[i]]
        if frame then
            SetFrameState(frame, predictionEnabled)
        end
    end

    local filterFrames = {
        "KalmanProcessNoiseFrame",
        "KalmanMeasurementNoiseFrame"
    }
    for i = 1, #filterFrames do
        local frame = CheatEnv.UI_Elements[filterFrames[i]]
        if frame then
            SetFrameState(frame, filterEnabled)
        end
    end

    local adaptiveOnlyFrame = CheatEnv.UI_Elements["ManeuverSensitivityFrame"]
    if adaptiveOnlyFrame then
        SetFrameState(adaptiveOnlyFrame, adaptiveFilterEnabled)
    end
end

local function CreateSection(text, parent)
    local Holder = Instance.new("Frame")
    Holder.Size = UDim2.new(1, 0, 0, 42)
    Holder.BackgroundTransparency = 1
    Holder.Parent = parent

    -- Subtle ambient glow behind section
    local GlowBg = Instance.new("Frame")
    GlowBg.Size = UDim2.new(1, 0, 0, 42)
    GlowBg.BackgroundColor3 = Theme.Accent
    GlowBg.BackgroundTransparency = 0.96
    GlowBg.BorderSizePixel = 0
    GlowBg.Parent = Holder

    local GlowCorner = Instance.new("UICorner", GlowBg)
    GlowCorner.CornerRadius = UDim.new(0, 8)

    local GlowGradient = Instance.new("UIGradient", GlowBg)
    GlowGradient.Rotation = 0
    GlowGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.85),
        NumberSequenceKeypoint.new(0.5, 0.97),
        NumberSequenceKeypoint.new(1, 1)
    })

    -- Clean section text (remove dashes)
    local cleanText = text:gsub("^[%-═%s]+", ""):gsub("[%-═%s]+$", "")

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -16, 0, 28)
    Label.Position = UDim2.new(0, 8, 0, 2)
    Label.BackgroundTransparency = 1
    Label.Text = cleanText
    Label.TextColor3 = Theme.Text
    Label.Font = Enum.Font.GothamBlack
    Label.TextSize = 13
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextTransparency = 0.08
    Label.Parent = Holder

    -- Gradient accent underline (Cyan → Purple)
    local Divider = Instance.new("Frame")
    Divider.Size = UDim2.new(1, -8, 0, 2)
    Divider.Position = UDim2.new(0, 4, 1, -4)
    Divider.BackgroundColor3 = Theme.Accent
    Divider.BorderSizePixel = 0
    Divider.Parent = Holder

    local DivCorner = Instance.new("UICorner", Divider)
    DivCorner.CornerRadius = UDim.new(1, 0)

    local DivGradient = Instance.new("UIGradient", Divider)
    DivGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 200, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 80, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 60, 255))
    })
    DivGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.7, 0.4),
        NumberSequenceKeypoint.new(1, 0.95)
    })
end

local function CreateToggle(text, settingKey, bindInfo, parent, customCallback)
    local Frame = Instance.new("Frame")
    Frame.Parent = parent
    Frame.Size = UDim2.new(1, 0, 0, 50)
    Frame.BackgroundColor3 = Theme.CardBg

    local Corner = Instance.new("UICorner", Frame)
    Corner.CornerRadius = UDim.new(0, 10)

    local Stroke = Instance.new("UIStroke", Frame)
    Stroke.Color = Theme.CardBorder
    Stroke.Thickness = 1
    Stroke.Transparency = 0.5
    BindAnimatedCard(Frame, Stroke, {
        BaseColor = Theme.CardBg,
        HoverColor = Theme.Element,
        BaseStrokeTransparency = 0.5,
        HoverStrokeTransparency = 0.2,
        HoverScale = 1.005
    })

    -- Left accent bar (lights up when active)
    local AccentBar = Instance.new("Frame")
    AccentBar.Size = UDim2.new(0, 3, 0.6, 0)
    AccentBar.Position = UDim2.new(0, 6, 0.2, 0)
    AccentBar.BackgroundColor3 = Settings[settingKey] and Theme.Accent or Theme.Disabled
    AccentBar.BorderSizePixel = 0
    AccentBar.Parent = Frame

    local AB_Corner = Instance.new("UICorner", AccentBar)
    AB_Corner.CornerRadius = UDim.new(1, 0)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -120, 1, 0)
    Label.Position = UDim2.new(0, 18, 0, 0)
    Label.BackgroundTransparency = 1
    local suffix = bindInfo and ("  ") or ""
    Label.Text = text .. suffix
    Label.TextColor3 = Theme.Text
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextSize = 13
    Label.Parent = Frame

    -- Keybind chip (if bound)
    if bindInfo then
        local KeyChip = Instance.new("TextButton")
        KeyChip.Size = UDim2.new(0, 26, 0, 16)
        KeyChip.Position = UDim2.new(1, -118, 0.5, -8)
        KeyChip.BackgroundColor3 = Color3.fromRGB(25, 30, 50)
        KeyChip.BackgroundTransparency = 0.1
        KeyChip.Text = CheatEnv.GetBindChipShortText(bindInfo)
        KeyChip.TextColor3 = Theme.TextDark
        KeyChip.Font = Enum.Font.GothamBold
        KeyChip.TextSize = 9
        KeyChip.BorderSizePixel = 0
        KeyChip.AutoButtonColor = false
        KeyChip.Parent = Frame

        local KC_Corner = Instance.new("UICorner", KeyChip)
        KC_Corner.CornerRadius = UDim.new(0, 4)

        local KC_Stroke = Instance.new("UIStroke", KeyChip)
        KC_Stroke.Color = Theme.CardBorder
        KC_Stroke.Thickness = 1
        KC_Stroke.Transparency = 0.4

        if not CheatEnv.KeybindChipRefs[bindInfo.Setting] then
            CheatEnv.KeybindChipRefs[bindInfo.Setting] = {}
        end
        table.insert(CheatEnv.KeybindChipRefs[bindInfo.Setting], KeyChip)

        TrackUIConnection(KeyChip.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                CheatEnv.OpenRebindWindow(bindInfo.Setting)
            end
        end))
    end

    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(0, 52, 0, 26)
    Button.Position = UDim2.new(1, -64, 0.5, -13)
    Button.BackgroundColor3 = Settings[settingKey] and Theme.Accent or Theme.Disabled
    Button.Text = ""
    Button.TextColor3 = Settings[settingKey] and Color3.fromRGB(12, 20, 28) or Theme.TextDark
    Button.Font = Enum.Font.GothamBold
    Button.TextSize = 10
    Button.AutoButtonColor = false
    Button.Parent = Frame

    local BtnCorner = Instance.new("UICorner", Button)
    BtnCorner.CornerRadius = UDim.new(1, 0)

    -- Gradient fill for ON state
    local BtnGradient = Instance.new("UIGradient", Button)
    BtnGradient.Rotation = 90
    if Settings[settingKey] then
        BtnGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 210, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 170, 240))
        })
    else
        BtnGradient.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Theme.Disabled),
            ColorSequenceKeypoint.new(1, Theme.Disabled)
        })
    end

    local ButtonStroke = Instance.new("UIStroke", Button)
    ButtonStroke.Color = Settings[settingKey] and Theme.Accent or Theme.CardBorder
    ButtonStroke.Thickness = 1
    ButtonStroke.Transparency = 0.4
    BindAnimatedButton(Button, {
        Stroke = ButtonStroke,
        ChangeColor = false,
        BaseStrokeTransparency = 0.4,
        HoverStrokeTransparency = 0.15,
        PressStrokeTransparency = 0.05,
        HoverScale = 1.04,
        PressScale = 0.94
    })

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 22, 0, 22)
    Knob.Position = Settings[settingKey] and UDim2.new(1, -24, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)
    Knob.BackgroundColor3 = Color3.fromRGB(250, 252, 255)
    Knob.BorderSizePixel = 0
    Knob.Parent = Button
    Knob.ZIndex = 2

    local KnobCorner = Instance.new("UICorner", Knob)
    KnobCorner.CornerRadius = UDim.new(1, 0)

    -- Knob subtle shadow
    local KnobShadow = Instance.new("UIStroke", Knob)
    KnobShadow.Color = Color3.fromRGB(0, 0, 0)
    KnobShadow.Thickness = 1
    KnobShadow.Transparency = 0.8

    CheatEnv.Toggles[settingKey] = Button
    CheatEnv.ToggleMeta[settingKey] = {
        Knob = Knob,
        AccentBar = AccentBar,
        BtnGradient = BtnGradient,
        ButtonStroke = ButtonStroke
    }
    if CheatEnv.RegisterSearchEntry then
        CheatEnv.RegisterSearchEntry(text, settingKey, Frame, parent, "toggle switch")
    end

    local conn = Button.MouseButton1Click:Connect(function()
        if Button.Active == false then return end

        Settings[settingKey] = not Settings[settingKey]
        SyncButton(settingKey)
        TweenService:Create(Knob, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, 26, 0, 26)
        }):Play()
        task.delay(0.09, function()
            if Knob and Knob.Parent then
                TweenService:Create(Knob, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    Size = UDim2.new(0, 24, 0, 24)
                }):Play()
            end
        end)

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
                AimlockState.Engaged = false
                AimlockState.RMBHeld = false
                AimlockRing.Visible = false -- [FIX] Force hiding ring
            end
        end

        if settingKey == "Aimbot" and not Settings[settingKey] then
            AimbotState.Engaged = false
            AimbotState.RMBHeld = false
        end

        if settingKey == "TC_Hide" then
            UpdateTeamCheckDependencies()
        end

        UpdateKeybindList()

        if customCallback then customCallback(Settings[settingKey]) end
    end)
    TrackUIConnection(conn)

    return Frame
end

local function CreateDropdown(text, settingKey, options, parent, customCallback)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 58)
    Frame.BackgroundColor3 = Theme.PanelSoft
    Frame.ZIndex = 5
    Frame.Parent = parent

    local Corner = Instance.new("UICorner", Frame)
    Corner.CornerRadius = UDim.new(0, 10)

    local Stroke = Instance.new("UIStroke", Frame)
    Stroke.Color = Theme.CardBorder
    Stroke.Thickness = 1
    Stroke.Transparency = 0.5
    BindAnimatedCard(Frame, Stroke, {
        BaseColor = Theme.CardBg,
        HoverColor = Theme.Element,
        BaseStrokeTransparency = 0.5,
        HoverStrokeTransparency = 0.22,
        HoverScale = 1.004
    })

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.5, 0, 0, 24)
    Label.Position = UDim2.new(0, 14, 0, 6)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = Theme.Text
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextSize = 13
    Label.Parent = Frame
    Label.ZIndex = 6

    local MainBtn = Instance.new("TextButton")
    MainBtn.Size = UDim2.new(0.42, 0, 0, 28)
    MainBtn.Position = UDim2.new(0.54, 0, 0, 15)
    MainBtn.BackgroundColor3 = Color3.fromRGB(20, 28, 48)
    MainBtn.Text = Settings[settingKey] .. " ▼"
    MainBtn.TextColor3 = Theme.AccentSoft
    MainBtn.Font = Enum.Font.GothamBold
    MainBtn.TextSize = 12
    MainBtn.AutoButtonColor = false
    MainBtn.Parent = Frame
    MainBtn.ZIndex = 6

    local M_Corner = Instance.new("UICorner", MainBtn)
    M_Corner.CornerRadius = UDim.new(0, 7)

    local M_Stroke = Instance.new("UIStroke", MainBtn)
    M_Stroke.Color = Theme.CardBorder
    M_Stroke.Thickness = 1
    M_Stroke.Transparency = 0.4
    BindAnimatedButton(MainBtn, {
        Stroke = M_Stroke,
        BaseColor = Color3.fromRGB(20, 28, 48),
        HoverColor = Color3.fromRGB(28, 36, 60),
        PressColor = Color3.fromRGB(16, 22, 40),
        BaseStrokeTransparency = 0.4,
        HoverStrokeTransparency = 0.18,
        PressStrokeTransparency = 0.08,
        HoverScale = 1.02,
        PressScale = 0.96
    })

    local DropList = Instance.new("ScrollingFrame")
    DropList.Size = UDim2.new(0.42, 0, 0, 0)
    DropList.Position = UDim2.new(0.54, 0, 0, 48)
    DropList.BackgroundColor3 = Color3.fromRGB(18, 24, 42)
    DropList.BorderSizePixel = 0
    DropList.ScrollBarThickness = 3
    DropList.ScrollBarImageColor3 = Theme.Accent
    DropList.Visible = false
    DropList.Parent = Frame
    DropList.ZIndex = 10

    local D_ListLayout = Instance.new("UIListLayout", DropList)
    D_ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local D_Corner = Instance.new("UICorner", DropList)
    D_Corner.CornerRadius = UDim.new(0, 7)

    local D_Stroke = Instance.new("UIStroke", DropList)
    D_Stroke.Color = Theme.CardBorder
    D_Stroke.Thickness = 1
    D_Stroke.Transparency = 0.4

    local isOpen = false

    local function CloseDropdown(animateDuration)
        isOpen = false
        MainBtn.Text = tostring(Settings[settingKey]) .. " ▼"
        TweenService:Create(Frame, TweenInfo.new(0.18), { Size = UDim2.new(1, 0, 0, 58) }):Play()

        local closeTime = animateDuration or 0.14
        TweenService:Create(DropList, TweenInfo.new(closeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = UDim2.new(0.42, 0, 0, 0),
            BackgroundTransparency = 1
        }):Play()
        task.delay(closeTime + 0.01, function()
            if DropList and DropList.Parent and not isOpen then
                DropList.Visible = false
            end
        end)
    end

    local function OpenDropdown()
        isOpen = true
        MainBtn.Text = tostring(Settings[settingKey]) .. " ▲"
        local count = #options
        local h = math_min(count * 28, 140)

        DropList.Visible = true
        DropList.Size = UDim2.new(0.42, 0, 0, 0)
        DropList.BackgroundTransparency = 1
        DropList.CanvasSize = UDim2.new(0, 0, 0, count * 28)

        TweenService:Create(Frame, TweenInfo.new(0.2), { Size = UDim2.new(1, 0, 0, 56 + h + 8) }):Play()
        TweenService:Create(DropList, TweenInfo.new(0.17, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = UDim2.new(0.42, 0, 0, h),
            BackgroundTransparency = 0
        }):Play()
    end

    local conn1 = MainBtn.MouseButton1Click:Connect(function()
        if MainBtn.Active == false then return end
        if isOpen then
            CloseDropdown()
        else
            OpenDropdown()
        end
    end)
    TrackUIConnection(conn1)

    for _, opt in ipairs(options) do
        local OptBtn = Instance.new("TextButton")
        OptBtn.Size = UDim2.new(1, 0, 0, 28)
        OptBtn.BackgroundColor3 = Theme.Element
        OptBtn.Text = opt
        OptBtn.TextColor3 = Theme.TextDark
        OptBtn.Font = Enum.Font.GothamMedium
        OptBtn.TextSize = 12
        OptBtn.Parent = DropList
        OptBtn.ZIndex = 11
        OptBtn.AutoButtonColor = false
        BindAnimatedButton(OptBtn, {
            BaseColor = Theme.Element,
            HoverColor = Theme.PanelSoft,
            PressColor = Theme.Panel,
            HoverScale = 1.01,
            PressScale = 0.97
        })

        local conn2 = OptBtn.MouseButton1Click:Connect(function()
            Settings[settingKey] = opt
            MainBtn.Text = opt .. " ▼"
            CloseDropdown()

            if settingKey == "AimlockMode" then
                if not AimlockEngagedFromGUI and AimlockEngaged then
                    AimlockEngaged = false
                end
            end

            if settingKey == "AimlockTrigger" then
                AimlockEngaged = false
                AimlockEngagedFromGUI = false
                AimlockState.Engaged = false
                AimlockState.RMBHeld = false
                UpdateKeybindList()
            end

            if settingKey == "AimbotTrigger" then
                AimbotState.Engaged = false
                AimbotState.RMBHeld = false
                UpdateKeybindList()
            end

            if customCallback then customCallback(opt) end
        end)
        TrackUIConnection(conn2)
    end

    -- [NEW] Register dropdown for config refresh
    CheatEnv.Dropdowns[settingKey] = {
        MainBtn = MainBtn
    }
    if CheatEnv.RegisterSearchEntry then
        CheatEnv.RegisterSearchEntry(text, settingKey, Frame, parent, table.concat(options, " "))
    end

    return Frame
end

local function CreateSlider(text, settingKey, min, max, isFloat, parent, elementId)
    local Frame = Instance.new("Frame")
    Frame.Parent = parent
    Frame.Size = UDim2.new(1, 0, 0, 68)
    Frame.BackgroundColor3 = Theme.CardBg

    if elementId then CheatEnv.UI_Elements[elementId] = Frame end

    local Corner = Instance.new("UICorner", Frame)
    Corner.CornerRadius = UDim.new(0, 10)

    local Stroke = Instance.new("UIStroke", Frame)
    Stroke.Color = Theme.CardBorder
    Stroke.Thickness = 1
    Stroke.Transparency = 0.5
    BindAnimatedCard(Frame, Stroke, {
        BaseColor = Theme.CardBg,
        HoverColor = Theme.Element,
        BaseStrokeTransparency = 0.5,
        HoverStrokeTransparency = 0.22,
        HoverScale = 1.004
    })

    -- Label (left side)
    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -90, 0, 22)
    Label.Position = UDim2.new(0, 14, 0, 8)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = Theme.Text
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextSize = 13
    Label.Parent = Frame

    -- Value badge (right side pill)
    local startVal = Settings[settingKey]
    local ValueBadge = Instance.new("TextLabel")
    ValueBadge.Size = UDim2.new(0, 70, 0, 20)
    ValueBadge.Position = UDim2.new(1, -82, 0, 9)
    ValueBadge.BackgroundColor3 = Color3.fromRGB(20, 28, 48)
    ValueBadge.BackgroundTransparency = 0.15
    ValueBadge.BorderSizePixel = 0
    if isFloat then
        ValueBadge.Text = string.format("%.2f", startVal)
    else
        ValueBadge.Text = tostring(startVal)
    end
    ValueBadge.TextColor3 = Theme.AccentSoft
    ValueBadge.Font = Enum.Font.GothamBold
    ValueBadge.TextSize = 11
    ValueBadge.Parent = Frame

    local VB_Corner = Instance.new("UICorner", ValueBadge)
    VB_Corner.CornerRadius = UDim.new(0, 5)

    local VB_Stroke = Instance.new("UIStroke", ValueBadge)
    VB_Stroke.Color = Theme.CardBorder
    VB_Stroke.Thickness = 1
    VB_Stroke.Transparency = 0.45

    -- Slider track
    local SliderBG = Instance.new("Frame")
    SliderBG.Size = UDim2.new(1, -28, 0, 6)
    SliderBG.Position = UDim2.new(0, 14, 0, 46)
    SliderBG.BackgroundColor3 = Color3.fromRGB(25, 30, 45)
    SliderBG.Parent = Frame

    local SB_Stroke = Instance.new("UIStroke", SliderBG)
    SB_Stroke.Color = Theme.CardBorder
    SB_Stroke.Thickness = 1
    SB_Stroke.Transparency = 0.55

    local S_Corner = Instance.new("UICorner", SliderBG)
    S_Corner.CornerRadius = UDim.new(1, 0)

    -- Gradient fill (cyan → purple)
    local SliderFill = Instance.new("Frame")
    local startPercent = (Settings[settingKey] - min) / (max - min)
    SliderFill.Size = UDim2.new(math.clamp(startPercent, 0, 1), 0, 1, 0)
    SliderFill.BackgroundColor3 = Theme.Accent
    SliderFill.BorderSizePixel = 0
    SliderFill.Parent = SliderBG

    local F_Corner = Instance.new("UICorner", SliderFill)
    F_Corner.CornerRadius = UDim.new(1, 0)

    local FillGradient = Instance.new("UIGradient", SliderFill)
    FillGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 200, 255)),
        ColorSequenceKeypoint.new(0.7, Color3.fromRGB(80, 140, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 80, 255))
    })

    -- Knob with glow
    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 14, 0, 14)
    Knob.AnchorPoint = Vector2.new(0.5, 0.5)
    Knob.Position = UDim2.new(math.clamp(startPercent, 0, 1), 0, 0.5, 0)
    Knob.BackgroundColor3 = Color3.fromRGB(245, 250, 255)
    Knob.BorderSizePixel = 0
    Knob.Parent = SliderBG
    Knob.ZIndex = 2

    local K_Corner = Instance.new("UICorner", Knob)
    K_Corner.CornerRadius = UDim.new(1, 0)

    local K_Stroke = Instance.new("UIStroke", Knob)
    K_Stroke.Color = Theme.Accent
    K_Stroke.Thickness = 1.5
    K_Stroke.Transparency = 0.25

    local Trigger = Instance.new("TextButton")
    Trigger.Size = UDim2.new(1, 0, 1, 0)
    Trigger.BackgroundTransparency = 1
    Trigger.Text = ""
    Trigger.Parent = SliderBG

    local dragging = false
    local sliderHovered = false

    local function SetSliderVisualState(isHover, isDragging)
        local knobSize = isDragging and UDim2.new(0, 18, 0, 18) or (isHover and UDim2.new(0, 16, 0, 16) or UDim2.new(0, 14, 0, 14))
        TweenService:Create(Knob, TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
            Size = knobSize
        }):Play()
        TweenService:Create(SB_Stroke, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Transparency = isHover and 0.3 or 0.55
        }):Play()
        TweenService:Create(K_Stroke, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Transparency = isDragging and 0.05 or (isHover and 0.12 or 0.25),
            Thickness = isDragging and 2 or 1.5
        }):Play()
    end

    local function UpdateSliderFromX(xPos)
        local pos = UDim2.new(
            math.clamp((xPos - SliderBG.AbsolutePosition.X) / SliderBG.AbsoluteSize.X, 0, 1), 0, 1, 0)
        SliderFill.Size = pos
        Knob.Position = UDim2.new(pos.X.Scale, 0, 0.5, 0)
        local val = min + ((max - min) * pos.X.Scale)

        if isFloat then
            val = math.floor(val * 100) / 100
            ValueBadge.Text = string.format("%.2f", val)
        else
            val = math.floor(val)
            ValueBadge.Text = tostring(val)
        end

        Settings[settingKey] = val
    end

    local triggerEnterConn = Trigger.MouseEnter:Connect(function()
        sliderHovered = true
        SetSliderVisualState(true, dragging)
    end)
    local triggerLeaveConn = Trigger.MouseLeave:Connect(function()
        sliderHovered = false
        SetSliderVisualState(false, dragging)
    end)
    TrackUIConnection(triggerEnterConn)
    TrackUIConnection(triggerLeaveConn)

    local triggerBeganConn = Trigger.InputBegan:Connect(function(input)
        if Trigger.Active == false then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            UpdateSliderFromX(input.Position.X)
            SetSliderVisualState(sliderHovered, true)
        end
    end)
    TrackUIConnection(triggerBeganConn)

    table.insert(CheatEnv.Connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            UpdateSliderFromX(input.Position.X)
        end
    end))

    table.insert(CheatEnv.Connections, UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            SetSliderVisualState(sliderHovered, false)
        end
    end))

    -- [NEW] Register slider for config refresh
    CheatEnv.Sliders[settingKey] = {
        Frame = Frame,
        Label = Label,
        ValueBadge = ValueBadge,
        SliderFill = SliderFill,
        Knob = Knob,
        min = min,
        max = max,
        isFloat = isFloat,
        text = text
    }
    if CheatEnv.RegisterSearchEntry then
        CheatEnv.RegisterSearchEntry(text, settingKey, Frame, parent, "slider range value")
    end

    return Frame
end

local function CreateInput(text, settingKey, parent)
    local Frame = Instance.new("Frame")
    Frame.Parent = parent
    Frame.Size = UDim2.new(1, 0, 0, 50)
    Frame.BackgroundColor3 = Theme.CardBg

    local Corner = Instance.new("UICorner", Frame)
    Corner.CornerRadius = UDim.new(0, 9)

    local Stroke = Instance.new("UIStroke", Frame)
    Stroke.Color = Theme.Stroke
    Stroke.Thickness = 1
    Stroke.Transparency = 0.75
    BindAnimatedCard(Frame, Stroke, {
        BaseColor = Theme.PanelSoft,
        HoverColor = Theme.Element,
        BaseStrokeTransparency = 0.75,
        HoverStrokeTransparency = 0.48,
        HoverScale = 1.003
    })

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(0.56, 0, 1, 0)
    Label.Position = UDim2.new(0, 12, 0, 0)
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = Theme.Text
    Label.Font = Enum.Font.GothamMedium
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextSize = 14
    Label.Parent = Frame

    local InputBox = Instance.new("TextBox")
    InputBox.Size = UDim2.new(0, 110, 0, 30)
    InputBox.Position = UDim2.new(1, -122, 0.5, -15)
    InputBox.BackgroundColor3 = Theme.Element
    InputBox.Text = tostring(Settings[settingKey])
    InputBox.TextColor3 = Theme.AccentSoft
    InputBox.Font = Enum.Font.Code
    InputBox.TextSize = 15
    InputBox.Parent = Frame

    local I_Corner = Instance.new("UICorner", InputBox)
    I_Corner.CornerRadius = UDim.new(0, 7)

    local I_Stroke = Instance.new("UIStroke", InputBox)
    I_Stroke.Color = Theme.Stroke
    I_Stroke.Thickness = 1
    I_Stroke.Transparency = 0.55

    local hoverInConn = InputBox.MouseEnter:Connect(function()
        if UserInputService:GetFocusedTextBox() == InputBox then return end
        TweenService:Create(I_Stroke, TweenInfo.new(0.1), { Transparency = 0.35 }):Play()
        TweenControlScale(InputBox, 1.01, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end)
    local hoverOutConn = InputBox.MouseLeave:Connect(function()
        if UserInputService:GetFocusedTextBox() == InputBox then return end
        TweenService:Create(I_Stroke, TweenInfo.new(0.1), { Transparency = 0.55 }):Play()
        TweenControlScale(InputBox, 1, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end)
    TrackUIConnection(hoverInConn)
    TrackUIConnection(hoverOutConn)

    local focusConn = InputBox.Focused:Connect(function()
        I_Stroke.Color = Theme.AccentSoft
        TweenService:Create(I_Stroke, TweenInfo.new(0.1), { Transparency = 0.12 }):Play()
        TweenControlScale(InputBox, 1.02, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end)
    TrackUIConnection(focusConn)

    local conn = InputBox.FocusLost:Connect(function()
        local num = tonumber(InputBox.Text)
        if num then
            if settingKey == "ImpulseInterval" then
                num = math.max(0, num)
            end
            Settings[settingKey] = num
        end
        InputBox.Text = tostring(Settings[settingKey])

        I_Stroke.Color = Theme.Stroke
        TweenService:Create(I_Stroke, TweenInfo.new(0.1), { Transparency = 0.55 }):Play()
        TweenControlScale(InputBox, 1, 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    end)
    TrackUIConnection(conn)
    if CheatEnv.RegisterSearchEntry then
        CheatEnv.RegisterSearchEntry(text, settingKey, Frame, parent, "input number")
    end

    return Frame
end

local function CreateButton(text, color, callback, parent)
    local Button = Instance.new("TextButton")
    Button.Size = UDim2.new(1, 0, 0, 42)
    Button.BackgroundColor3 = color or Theme.Element
    Button.Text = text
    Button.TextColor3 = Theme.Text
    Button.Font = Enum.Font.GothamBold
    Button.TextSize = 13
    Button.AutoButtonColor = false
    Button.Parent = parent

    local Corner = Instance.new("UICorner", Button)
    Corner.CornerRadius = UDim.new(0, 10)

    local Stroke = Instance.new("UIStroke", Button)
    Stroke.Color = Theme.CardBorder
    Stroke.Thickness = 1
    Stroke.Transparency = 0.4
    BindAnimatedButton(Button, {
        Stroke = Stroke,
        BaseColor = Button.BackgroundColor3,
        HoverColor = Button.BackgroundColor3:Lerp(Color3.new(1, 1, 1), 0.12),
        PressColor = Button.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.1),
        BaseStrokeTransparency = 0.4,
        HoverStrokeTransparency = 0.15,
        PressStrokeTransparency = 0.05,
        HoverScale = 1.018,
        PressScale = 0.955
    })

    local conn = Button.MouseButton1Click:Connect(function()
        TweenService:Create(Button, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            TextTransparency = 0.12
        }):Play()
        task.delay(0.08, function()
            if Button and Button.Parent then
                TweenService:Create(Button, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                    TextTransparency = 0
                }):Play()
            end
        end)
        callback()
    end)
    TrackUIConnection(conn)
    if CheatEnv.RegisterSearchEntry then
        CheatEnv.RegisterSearchEntry(text, nil, Button, parent, "action button")
    end

    return Button
end

ApplyClickGuiMovementState = function()
    if not MainFrame then return end
    if Settings.NonMovementClickGUI then
        MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0) -- zero offsets from center anchor
        MainFrame:SetAttribute("UserMoved", false)
    end
end

local function MakeDraggable(frame, restrictToMenu)
    if not frame then return end
    local dragging, dragInput, dragStart, startPos

    table.insert(CheatEnv.Connections, frame.InputBegan:Connect(function(input)
        if frame == MainFrame and Settings.NonMovementClickGUI then
            return
        end
        if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
            if restrictToMenu and not MainFrame.Visible then return end
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end))

    table.insert(CheatEnv.Connections, frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput =
                input
        end
    end))

    table.insert(CheatEnv.Connections, UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            if frame == MainFrame and Settings.NonMovementClickGUI then
                dragging = false
                return
            end
            if restrictToMenu and not MainFrame.Visible then
                dragging = false
                return
            end
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale,
                startPos.Y.Offset + delta.Y)
            if frame:GetAttribute("UserMoved") ~= nil then
                frame:SetAttribute("UserMoved", true)
            end
        end
    end))
end

MakeDraggable(MainFrame, false)
MakeDraggable(Watermark, true)
MakeDraggable(KeybindFrame, true)

-- ✅ ПЕРЕМЕСТИЛИ ФУНКЦИЮ UpdateMM2Dependencies СЮДА
UpdateMM2Dependencies = function()
    local isMainEspEnabled = Settings.ESP
    local mm2Toggles = {
        "MM2_ESP_Player", "MM2_ESP_Sheriff",
        "MM2_ESP_Murder", "MM2_ESP_Hero", "MM2_ESP_GunDrop"
    }

    for _, settingName in ipairs(mm2Toggles) do
        local toggle = CheatEnv.Toggles[settingName]
        if toggle then
            local parentFrame = toggle.Parent
            if parentFrame then
                SetFrameState(parentFrame, isMainEspEnabled)
            end
        end
    end
end

-- MM2 dependency sync is executed after MM2 toggle frames are created below.

--// BUILDING MENU ELEMENTS //--

local C = GetCurrentParent("Combat")

CreateSection("-- AIMBOT --", C)
AddTooltip(CreateToggle("Aimbot Active", "Aimbot", Keybinds[3], C), "Automatically locks camera onto closest target")
AddTooltip(CreateDropdown("Aimbot Mode", "AimbotMode", { "Old", "Mousemoverel" }, C),
    "Old: Crosshair based / Mousemoverel: Mouse based")
AddTooltip(CreateDropdown("Smooth Mode", "AimbotSmoothMode", { "Old", "Mousemoverel" }, C),
    "Choose smoothness formula independently from Aimbot Mode")
AddTooltip(CreateDropdown("Aimbot Trigger", "AimbotTrigger", { "T Toggle", "RMB Hold", "RMB Toggle" }, C),
    "T key toggle mode or activate with right mouse")
AddTooltip(CreateDropdown("Hit Point", "AimbotPart", { "Head", "Neck", "Chest" }, C), "Target body part for Aimbot")
AddTooltip(CreateSlider("Aimbot FOV", "AimbotFOV", 10, 800, false, C), "Field of View radius for target acquisition")
AddTooltip(CreateSlider("Smoothness", "AimbotSmooth", 0.01, 1.0, true, C),
    "Lower value = Faster snap, Higher = Human-like movement")
AddTooltip(CreateSlider("Aimbot Update FPS", "AimbotUpdateFPS", 10, 240, false, C),
    "Lower = smoother but slower response")
AddTooltip(CreateToggle("Auto Shot", "AutoShot", nil, C), "Automatically fires when Aimbot has a valid target")
AddTooltip(CreateSlider("Auto Shot Delay (ms)", "AutoShotDelay", 10, 500, false, C),
    "Interval between automatic shots")

CreateSection("-- TARGETING --", C)
AddTooltip(CreateDropdown("Target Priority", "TargetPriority", { "Crosshair", "Health", "Distance", "Threat" }, C),
    "Crosshair: Closest to aim | Health: Lowest HP | Distance: Closest 3D | Threat: Has weapon")
AddTooltip(CreateToggle("Adaptive Smoothing", "AdaptiveSmoothing", nil, C), "Smoothing changes based on target distance")
AddTooltip(CreateToggle("Oval FOV", "OvalFOV", nil, C), "Aspect-ratio corrected FOV (wider horizontal)")
AddTooltip(CreateToggle("Target Indicator", "TargetIndicator", nil, C), "Visual crosshair on locked target")
AddTooltip(CreateToggle("Auto Switch", "AutoSwitch", nil, C), "Instantly switch when target dies")

CreateSection("-- FLICK BOT --", C)
AddTooltip(CreateToggle("Enable Flick", "FlickBot", nil, C), "Instant snap to target (rage style)")
AddTooltip(CreateSlider("Flick Speed", "FlickSpeed", 0.3, 1.0, true, C), "Flick intensity (higher = faster)")


CreateSection("-- AIMLOCK --", C)
AddTooltip(CreateToggle("Enable Aimlock", "Aimlock", Keybinds[2], C), "Toggle the separate Aimlock module")
AddTooltip(CreateToggle("Force Stick (Hard Lock)", "AimlockForceStick", nil, C),
    "Forces crosshair to stay attached to target model while Aimlock is active")
CreateSlider("Aimlock FOV", "AimlockFOV", 10, 800, false, C)
CreateSlider("Aimlock Smooth", "AimlockSmooth", 0.01, 1.0, true, C)
CreateSlider("Aimlock Update FPS", "AimlockUpdateFPS", 10, 240, false, C)
CreateDropdown("Hit Point", "AimlockPart", { "Head", "Neck", "Chest" }, C)

-- [NEW] Updated naming for Aimlock Target Mode
AddTooltip(CreateDropdown("aimbot mode", "AimlockTargetMode", { "Old", "Mousemoverel" }, C),
    "Old (Center) or Mousemoverel (Cursor)")
AddTooltip(CreateDropdown("Smooth Mode", "AimlockSmoothMode", { "Old", "Mousemoverel" }, C),
    "Choose smoothness formula independently from Aimlock mode")
AddTooltip(CreateDropdown("Aimlock Trigger", "AimlockTrigger", { "N Key", "RMB Hold", "RMB Toggle" }, C),
    "Activate aimlock with N key or right mouse")
AddTooltip(CreateDropdown("Trigger Mode", "AimlockMode", { "N Toggle", "N Hold" }, C), "How to activate Aimlock")

CreateSection("-- PREDICTION & CHECKS --", C)

AddTooltip(CreateToggle("Enable Prediction", "PredictionEnabled", nil, C, function()
    UpdatePredictionDependencies()
end), "Toggle all prediction calculations")

AddTooltip(CreateDropdown("Prediction Mode", "PredictionMode", { "Standard", "Smart" }, C, function()
    UpdatePredictionDependencies()
end), "Smart mode automatically calculates based on Ping/Distance")

AddTooltip(CreateDropdown("Prediction Filter", "PredictionFilter", { "None", "Kalman", "Adaptive Kalman" }, C, function()
    UpdatePredictionDependencies()
end), "Adaptive Kalman auto-tunes for movement patterns; Kalman = fixed")

-- [NEW] Prediction Slider with ID
AddTooltip(CreateSlider("Prediction", "Prediction", 0, 1, true, C, "PredictionSlider"),
    "Predict target movement (Disabled in Smart Mode)")

AddTooltip(CreateSlider("Solver Iterations", "PredictionIterations", 1, 8, false, C, "PredictionIterationsFrame"),
    "Iterative intercept refinement passes (higher = more precise, more CPU)")
AddTooltip(CreateSlider("Confidence Floor", "PredictionConfidenceFloor", 0, 0.8, true, C, "PredictionConfidenceFloorFrame"),
    "Minimum confidence multiplier when movement is chaotic")
AddTooltip(CreateSlider("Kalman Process Q", "KalmanProcessNoise", 0.1, 4.0, true, C, "KalmanProcessNoiseFrame"),
    "How aggressively filter expects sudden motion changes")
AddTooltip(CreateSlider("Kalman Measure R", "KalmanMeasurementNoise", 0.1, 4.0, true, C, "KalmanMeasurementNoiseFrame"),
    "How much filter distrusts incoming target positions")
AddTooltip(CreateSlider("Maneuver Sens.", "ManeuverSensitivity", 0.5, 2.5, true, C, "ManeuverSensitivityFrame"),
    "Sensitivity of dodge/strafe detection for adaptive Kalman")

AddTooltip(CreateSlider("Deadzone", "Deadzone", 0, 10, false, C), "Pixels range to stop aiming (Fixes shaking)")
AddTooltip(CreateToggle("Ignore Knocked", "KnockedCheck", nil, C), "Don't aim at downed players")
CreateSlider("Bullet Speed", "BulletSpeed", 100, 10000, false, C)
CreateSlider("Bullet Drop", "BulletDrop", 0, 3, true, C)
CreateSlider("Prediction Multiplier", "PredictionMultiplier", 0.5, 3.0, true, C)
CreateToggle("Velocity Smoothing", "VelocitySmoothing", nil, C)
CreateToggle("Adaptive Prediction", "AdaptivePrediction", nil, C)

CreateSection("-- HUMANIZATION --", C)
AddTooltip(CreateToggle("Humanize Aim", "Humanize", nil, C), "Enables Bezier curves and random sway for legit look")
CreateSlider("Curve Power", "HumanizePower", 0.1, 5.0, true, C)
AddTooltip(CreateSlider("Reaction Time (s)", "ReactionTime", 0, 0.5, true, C), "Delay before locking onto a new target")
AddTooltip(CreateToggle("Sticky Aim", "StickyAim", nil, C), "Prevents rapid target switching")
CreateSlider("Sticky Duration", "StickyDuration", 0.1, 2.0, true, C)

CreateSection("-- Wall Check --", C)
AddTooltip(CreateToggle("Wall Check", "WallCheck", Keybinds[5], C), "Global check: Targets behind walls will be ignored")

CreateSection("-- NO RECOIL --", C)
AddTooltip(CreateToggle("No Recoil", "NoRecoil", Keybinds[4], C), "Eliminates visual and physical recoil when shooting")
AddTooltip(CreateDropdown("Recoil Mode", "NR_Mode", { "Classic", "Smart" }, C),
    "Classic = Static force, Smart = Dynamic compensation")
AddTooltip(CreateSlider("Recoil Strength", "RecoilStrength", 0, 100, false, C), "Intensity of recoil reduction")

AddTooltip(CreateDropdown("Movement Method", "MovementMode", { "Constant", "Impulse" }, C),
    "Constant = Smooth pull, Impulse = Discrete steps")
AddTooltip(CreateInput("Impulse Interval (ms)", "ImpulseInterval", C), "Delay between recoil compensation impulses")

local V = GetCurrentParent("Visuals")

CreateSection("-- ESP --", V)

AddTooltip(CreateToggle("Enable ESP", "ESP", Keybinds[1], V, function(state)
    if MM2_Data.IsMM2 then
        UpdateMM2Dependencies()
    end
end), "Draws 2D boxes around players")

AddTooltip(CreateToggle("Show Names", "ESP_Names", nil, V), "Displays player names")
AddTooltip(CreateToggle("Show Distance", "ESP_Distance", nil, V), "Shows distance in meters")
AddTooltip(CreateToggle("Show Weapon", "ESP_Weapon", nil, V), "Shows currently equipped tool")

CreateSection("-- ESP STYLE --", V)
AddTooltip(CreateToggle("Player Box", "ESP_Box", nil, V, function()
    UpdateESPBoxDependencies()
end), "Main box around player model")
AddTooltip(CreateToggle("Corner Box", "ESP_CornerBox", nil, V), "Uses corner lines instead of full box")
AddTooltip(CreateToggle("Fill Box", "ESP_BoxFill", nil, V, function()
    UpdateESPBoxDependencies()
end), "Adds a glass-like fill to the box")
CheatEnv.UI_Elements["ESP_BoxFillTransparency_Frame"] = CreateSlider("Fill Transparency", "ESP_BoxFillTransparency", 0, 1, true, V)
AddTooltip(CreateToggle("Tracers", "ESP_Tracers", nil, V), "Lines from screen bottom to players")
AddTooltip(CreateToggle("Chams", "ESP_Chams", nil, V), "3D highlight around player body")
AddTooltip(CreateToggle("Chams Only Visible", "ESP_ChamsVisibleOnly", nil, V),
    "Show chams only when player is visible (not through walls)")
AddTooltip(CreateSlider("Max Distance", "ESP_MaxDistance", 100, 5000, false, V), "Maximum ESP render distance (studs)")

CreateSection("-- ESP DETAILS --", V)
AddTooltip(CreateToggle("Health Bar", "ESP_HealthBar", nil, V), "Visual health indicator (left side)")
AddTooltip(CreateToggle("Health Text", "ESP_HealthText", nil, V), "Displays HP number")
AddTooltip(CreateToggle("Skeleton ESP", "ESP_Skeleton", nil, V), "Draws lines between character joints")

CreateSection("-- FOV VISUALS --", V)
AddTooltip(CreateToggle("Draw Aimbot FOV", "ShowFOV", nil, V), "Visualizes the Aimbot radius")
AddTooltip(CreateToggle("Draw Aimlock FOV", "ShowAimlockFOV", nil, V), "Visualizes the Aimlock radius")

local M = GetCurrentParent("Misc")

CreateSection("-- TEAM CHECK --", M)

CreateToggle("Hide Teammates ESP", "TC_Hide", nil, M, function()
    UpdateTeamCheckDependencies()
end)

CreateToggle("No Aim at Teammates", "TC_NoAim", nil, M)
CreateToggle("Green Teammates ESP", "TC_Green", nil, M)
CreateSection("-- VISUAL --", M)
AddTooltip(CreateToggle("Fullbright", "Misc_Fullbright", nil, M, function(state)
    local backup = CheatEnv.MiscLightingBackup

    if state then
        if not backup then
            backup = {
                Brightness = Lighting.Brightness,
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
                GlobalShadows = Lighting.GlobalShadows
            }
            pcall(function()
                backup.ExposureCompensation = Lighting.ExposureCompensation
            end)
            CheatEnv.MiscLightingBackup = backup
        end

        Lighting.Brightness = Settings.Misc_FB_Brightness or 3
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        if Settings.Misc_FB_DisableShadows then
            Lighting.GlobalShadows = false
        else
            Lighting.GlobalShadows = backup.GlobalShadows
        end
        pcall(function()
            Lighting.ExposureCompensation = Settings.Misc_FB_Exposure or 0.35
        end)
        return
    end

    if backup then
        Lighting.Brightness = backup.Brightness or Lighting.Brightness
        Lighting.Ambient = backup.Ambient or Lighting.Ambient
        Lighting.OutdoorAmbient = backup.OutdoorAmbient or Lighting.OutdoorAmbient
        if backup.GlobalShadows ~= nil then
            Lighting.GlobalShadows = backup.GlobalShadows
        end
        if backup.ExposureCompensation ~= nil then
            pcall(function()
                Lighting.ExposureCompensation = backup.ExposureCompensation
            end)
        end
        CheatEnv.MiscLightingBackup = nil
    end
end),
    "Global fullbright lighting (works in most games)")
AddTooltip(CreateSlider("Fullbright Level", "Misc_FB_Brightness", 1, 5, true, M),
    "Main brightness strength for Misc Fullbright")
AddTooltip(CreateSlider("FB Exposure", "Misc_FB_Exposure", -1, 2, true, M),
    "Exposure compensation while Fullbright is active")
AddTooltip(CreateToggle("FB Disable Shadows", "Misc_FB_DisableShadows", nil, M),
    "Disable world shadows while Fullbright is active")

local S = GetCurrentParent("System")

CreateSection("-- MENU --", S)
AddTooltip(CreateToggle("Non Movement ClickGUI", "NonMovementClickGUI", nil, S, function(enabled)
    if enabled and ApplyClickGuiMovementState then
        ApplyClickGuiMovementState()
    end
end), "Disables ClickGUI dragging and moves it to zero offsets")
CreateSection("-- KEYBINDS --", S)
AddTooltip(CreateToggle("Enable", "KeybindsEnableLabel", nil, S, function()
    UpdateKeybindList()
end), "Replace keybind button text with 'Enable'")

CreateSection("-- BLUR PARTICLES --", S)
AddTooltip(CreateToggle("Blur Particle", "UI_BlurParticles", nil, S, function()
    if CheatEnv.ApplyBlurParticleState then
        CheatEnv.ApplyBlurParticleState(true)
    end
end), "Rainbow star and starfall particles with blur")
AddTooltip(CreateSlider("Particle Count", "UI_BP_Count", 8, 80, false, S),
    "Amount of particles on screen")
AddTooltip(CreateSlider("Particle Speed", "UI_BP_Speed", 20, 420, false, S),
    "How fast particles move")
AddTooltip(CreateSlider("Particle Size", "UI_BP_Size", 8, 52, false, S),
    "Base particle size")
AddTooltip(CreateSlider("Particle Blur", "UI_BP_Blur", 0, 30, false, S),
    "Blur strength while effect is enabled")
AddTooltip(CreateSlider("Direction X", "UI_BP_DirX", -1, 1, true, S),
    "Horizontal direction (-1 = left, 1 = right)")
AddTooltip(CreateSlider("Direction Y", "UI_BP_DirY", -1, 1, true, S),
    "Vertical direction (-1 = up, 1 = down)")

local function UnloadCheat()
    if not _G.CheatLoaded then return end

    _G.CheatLoaded = false

    if _G.VAYS_HOOK_STATE then
        _G.VAYS_HOOK_STATE.active = false
        _G.VAYS_HOOK_STATE.settings = nil
        _G.VAYS_HOOK_STATE.getWallStorage = nil
        _G.VAYS_HOOK_STATE.fallRemote = nil
    end

    -- [NEW] Restore walls before unload
    pcall(function()
        RestoreWalls()
    end)

    pcall(function()
        for valueObj, originalValue in pairs(CheatEnv.NoSpreadOriginals) do
            if valueObj and valueObj.Parent and valueObj:IsA("NumberValue") then
                valueObj.Value = originalValue
            end
        end
    end)

    pcall(function()
        Settings.RapidFire = false
        Settings.InstantReload = false
        Settings.InfiniteAmmo = false
        Settings.MaxPenetration = false
        Settings.ArmorPierce = false
        Settings.NoFalloff = false
        Settings.MaxRange = false
        Settings.DamageMult = 1
        Settings.FreezeSpray = false
        Settings.ForceFullAuto = false
        Settings.FireRateMultiplier = 1
        Settings.ReloadMultiplier = 1
        Settings.SpreadMultiplier = 1
        Settings.NoSpread = false

        if type(ApplyWeaponMods) == "function" then
            ApplyWeaponMods()
        end
    end)

    pcall(function()
        if MenuBlur then MenuBlur:Destroy() end
    end)

    pcall(function()
        if CheatEnv.ResetBlurParticles then
            CheatEnv.ResetBlurParticles(true)
        end
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
        if RestoreCBVisuals then
            RestoreCBVisuals()
        end
    end)

    pcall(function()
        Settings.Misc_Fullbright = false
        local backup = CheatEnv.MiscLightingBackup
        if backup then
            Lighting.Brightness = backup.Brightness or Lighting.Brightness
            Lighting.Ambient = backup.Ambient or Lighting.Ambient
            Lighting.OutdoorAmbient = backup.OutdoorAmbient or Lighting.OutdoorAmbient
            if backup.GlobalShadows ~= nil then
                Lighting.GlobalShadows = backup.GlobalShadows
            end
            if backup.ExposureCompensation ~= nil then
                pcall(function()
                    Lighting.ExposureCompensation = backup.ExposureCompensation
                end)
            end
            CheatEnv.MiscLightingBackup = nil
        end
    end)

    pcall(function()
        for _, ui in pairs(CheatEnv.UI) do
            if ui then ui:Destroy() end
        end
    end)

    -- Clear caches
    VisibilityCache = {}
    WallStorage = {}
    OriginalWallProperties = {}
    VelocityBuffers = {}
    PredictionStates = {}
    PredictionFrameCache = setmetatable({}, { __mode = "k" })
    AimbotState.VisibilityUntil = setmetatable({}, { __mode = "k" })
    AimlockState.VisibilityUntil = setmetatable({}, { __mode = "k" })
    AimbotState.CurrentTarget = nil
    AimbotState.StickyTarget = nil
    AimlockState.CurrentTarget = nil
    AimlockState.StickyTarget = nil
    CheatEnv.NoSpreadOriginals = {}
    CheatEnv.WeaponModsDirty = false

    warn("✓ VAYS v6.8 unloaded successfully.")
end

AddTooltip(CreateButton("UNLOAD CHEAT", Color3.fromRGB(180, 40, 40), UnloadCheat, S), "Fully unload the script and clear memory")

-- MM2 Tab Content (if exists)
if MM2Tab then
    local MM2 = GetCurrentParent("MM2")

    CreateSection("-- MM2 ESP --", MM2)

    CreateToggle("Player (White)", "MM2_ESP_Player", nil, MM2, function()
        UpdateMM2Dependencies()
    end)
    CreateToggle("Sheriff (Blue)", "MM2_ESP_Sheriff", nil, MM2, function()
        UpdateMM2Dependencies()
    end)
    CreateToggle("Murder (Red)", "MM2_ESP_Murder", nil, MM2, function()
        UpdateMM2Dependencies()
    end)
    CreateToggle("Hero (Yellow)", "MM2_ESP_Hero", nil, MM2, function()
        UpdateMM2Dependencies()
    end)
    CreateToggle("Gun Drop (Purple)", "MM2_ESP_GunDrop", nil, MM2, function()
        UpdateMM2Dependencies()
    end)

    -- Apply initial enabled/disabled state once MM2 controls exist.
    UpdateMM2Dependencies()
end

-- Counter Blox Tab Content
if CounterBloxTab then
    local CB = GetCurrentParent("CB")

    CreateSection("═══ COUNTER BLOX v6.8 ═══", CB)

    -- ANTI-CHEAT BYPASS
    CreateSection("-- PLAYER MODS --", CB)
    AddTooltip(CreateToggle("No Fall Damage", "NoFallDamage", nil, CB), "Prevents fall damage completely")
    AddTooltip(CreateToggle("Auto Respawn", "AutoRespawn", nil, CB), "Automatically respawns when dead (!!!DETECT!!!)")

    -- WALL SHOT
    CreateSection("-- WALL HACKS --", CB)
    AddTooltip(CreateToggle("Wall Shot", "WallShot", nil, CB, function(val)
        if not val then
            RestoreWalls()
        end
    end), "Shoot through walls")

    AddTooltip(CreateDropdown("Mode", "WallShotMode", { "Aiming", "Whole Map", "On Click (L)" }, CB),
        "Aiming: Transparent walls in crosshair | Whole Map: All walls | On Click: Toggle with L key")

    AddTooltip(
        CreateDropdown("Method", "WallShotMethod", { "Hook (Silent)", "Reparent (Remove)", "CanQuery (Soft)" }, CB),
        "Hook: Silent logic | Reparent: Works on all execs | CanQuery: Soft disable")

    -- MOVEMENT
    CreateSection("-- MOVEMENT --", CB)
    AddTooltip(CreateToggle("Counter-Strafe", "CounterStrafe", nil, CB),
        "Stops you instantly when releasing WASD for perfect accuracy")

    -- WEAPON MODS (toggles)
    CreateSection("-- WEAPON MODS --", CB)

    AddTooltip(CreateToggle("No Spread", "NoSpread", nil, CB), "Sets weapon spread to 0")
    AddTooltip(CreateToggle("Freeze Spray", "FreezeSpray", nil, CB), "Removes recoil pattern (first shot accuracy)")
    AddTooltip(CreateToggle("Force Full Auto", "ForceFullAuto", nil, CB), "Makes all weapons fully automatic")
    AddTooltip(CreateToggle("Infinite Ammo", "InfiniteAmmo", nil, CB), "Never run out of ammo")
    AddTooltip(CreateToggle("Rapid Fire", "RapidFire", nil, CB), "Increases fire rate dramatically")
    AddTooltip(CreateToggle("Instant Reload", "InstantReload", nil, CB), "Removes reload time completely")
    AddTooltip(CreateToggle("Max Penetration", "MaxPenetration", nil, CB), "Maximum wall penetration")
    AddTooltip(CreateToggle("Armor Piercing", "ArmorPierce", nil, CB), "100% armor penetration")
    AddTooltip(CreateToggle("No Damage Falloff", "NoFalloff", nil, CB), "Full damage at any range")
    AddTooltip(CreateToggle("Max Range", "MaxRange", nil, CB), "Bullets keep max distance")

    -- WEAPON SLIDERS (more control)
    CreateSection("-- FINE TUNING --", CB)

    AddTooltip(CreateSlider("Damage Multiplier", "DamageMult", 1, 10, false, CB),
        "Multiply base weapon damage (1 = normal)")
    AddTooltip(CreateSlider("Fire Rate Multi", "FireRateMultiplier", 1, 10, false, CB),
        "Fire rate speed (1 = normal, 10 = fastest)")
    AddTooltip(CreateSlider("Reload Speed", "ReloadMultiplier", 1, 10, false, CB),
        "Reload speed (1 = normal, 10 = instant)")
    AddTooltip(CreateSlider("Spread Multi", "SpreadMultiplier", 0, 1, true, CB),
        "Spread amount (0 = no spread, 1 = normal)")

    -- VIEWMODEL CHANGER
    CreateSection("-- VIEWMODEL CHANGER --", CB)

    AddTooltip(CreateSlider("Viewmodel X", "ViewmodelX", -20, 20, true, CB), "Horizontal viewmodel offset")
    AddTooltip(CreateSlider("Viewmodel Y", "ViewmodelY", -20, 20, true, CB), "Vertical viewmodel offset")
    AddTooltip(CreateSlider("Viewmodel Z", "ViewmodelZ", -20, 20, true, CB), "Depth viewmodel offset")

    CreateButton("Reset Viewmodel", Color3.fromRGB(255, 100, 100), function()
        Settings.ViewmodelX = 0
        Settings.ViewmodelY = 0
        Settings.ViewmodelZ = 0
        -- Force immediate apply by resetting defaults
        pcall(function()
            LocalPlayer:SetAttribute("ViewmodelX", 1) -- CB default
            LocalPlayer:SetAttribute("ViewmodelY", 0)
            LocalPlayer:SetAttribute("ViewmodelZ", 0)
        end)
        ConfigSystem.Notify("Viewmodel", "Reset to default position", Color3.fromRGB(255, 255, 100))
    end, CB)

    -- CB VISUALS (NEW v6.8)
    CreateSection("-- CB VISUALS --", CB)

    AddTooltip(CreateToggle("Fullbright", "CB_Fullbright", nil, CB), "Maximum brightness, no shadows")
    AddTooltip(CreateToggle("No Fog/Haze", "CB_NoFog", nil, CB), "Remove atmosphere fog and haze")
    AddTooltip(CreateToggle("No Blur", "CB_NoBlur", nil, CB), "Disable blur effects (flash, scope)")
    AddTooltip(CreateToggle("Night Vision", "CB_NightVision", nil, CB), "Green night vision effect")
    AddTooltip(CreateToggle("High Saturation", "CB_HighSaturation", nil, CB), "Vibrant, colorful visuals")
    AddTooltip(CreateToggle("No Sky", "CB_NoSky", nil, CB), "Remove sky for cleaner view")
    AddTooltip(CreateToggle("Bomb Timer ESP", "CB_BombTimerESP", nil, CB), "Show bomb timer on screen")

    CreateSection("-- VISUAL TUNING --", CB)

    AddTooltip(CreateSlider("Brightness", "CB_CustomBrightness", 1, 3, true, CB), "Screen brightness (1 = normal)")
    AddTooltip(CreateSlider("Contrast", "CB_CustomContrast", -1, 1, true, CB), "Screen contrast adjustment")

    CreateButton("Reset Visuals", Color3.fromRGB(255, 150, 100), function()
        Settings.CB_Fullbright = false
        Settings.CB_NoFog = false
        Settings.CB_NoBlur = false
        Settings.CB_NightVision = false
        Settings.CB_HighSaturation = false
        Settings.CB_NoSky = false
        Settings.CB_CustomBrightness = 1
        Settings.CB_CustomContrast = 0
        ApplyCBVisuals() -- Reset to defaults
        ConfigSystem.Notify("Visuals", "Reset to default", Color3.fromRGB(255, 255, 100))
    end, CB)

    -- APPLY BUTTON
    CreateSection("-- APPLY --", CB)

    CreateButton("Apply All Weapon Mods", Theme.Accent, function()
        ApplyWeaponMods()
        ConfigSystem.Notify("CB Mods", "All weapon modifications applied!", Color3.fromRGB(80, 255, 120))
    end, CB)

    CreateButton("Reset Weapons", Color3.fromRGB(150, 150, 150), function()
        -- Reload the game's weapon data by re-joining
        ConfigSystem.Notify("Info", "Rejoin game to reset weapons to default", Color3.fromRGB(255, 255, 100))
    end, CB)
end

if SCPRP_Tab then
    local SCP = GetCurrentParent("SCP:RP")

    CreateSection("-- SCP:RP TEAM CHECK --", SCP)

    CreateToggle(
        "Advanced Team Check",
        "AdvancedTeamCheck",
        nil,
        SCP
    )
end

SetActiveTab("Combat")
--// LOGIC FUNCTIONS //--

local function IsTeammate(player)
    if not player or not LocalPlayer then return false end

    if not player.Team or not LocalPlayer.Team then return false end

    return player.Team == LocalPlayer.Team
end

-- Per-frame cache for ResolveCharacterModel (cleared each RenderStepped)
local _ResolveCharCache = {}
local _ResolveCharCacheTick = 0
local TargetScanPlayers = {}

local function RebuildTargetScanPlayers()
    for i = #TargetScanPlayers, 1, -1 do
        TargetScanPlayers[i] = nil
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            TargetScanPlayers[#TargetScanPlayers + 1] = plr
        end
    end
end

function ResolveCharacterRoot(character)
    if not character then return nil end
    return character:FindFirstChild("HumanoidRootPart")
        or character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or character:FindFirstChild("LowerTorso")
        or character:FindFirstChild("RootPart")
        or character:FindFirstChild("Head")
        or character.PrimaryPart
        or character:FindFirstChildWhichIsA("BasePart")
end

function ResolveCharacterModel(player)
    if not player then return nil end

    -- Per-frame cache: avoid resolving same player multiple times per frame
    local frameTick = math.floor(tick() * 60)
    if frameTick ~= _ResolveCharCacheTick then
        _ResolveCharCache = {}
        _ResolveCharCacheTick = frameTick
    end
    if _ResolveCharCache[player] ~= nil then
        local cached = _ResolveCharCache[player]
        if cached == false then return nil end
        return cached
    end

    local char = player.Character
    if char and char.Parent then
        _ResolveCharCache[player] = char
        return char
    end

    _ResolveCharCache[player] = false
    return nil
end

function ResolvePlayerFromCharacterModel(character)
    if not character then return nil end

    return Players:GetPlayerFromCharacter(character)
end

RebuildTargetScanPlayers()

local function ApplyNoRecoil(dt)
    if not Settings.NoRecoil then return end
    if not dt then dt = 1 / 60 end
    local isPressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    if not isPressed then
        HasShotOnce = false
        return
    end

    if mousemoverel then
        local shake = math.random(-1, 1)
        local currentTime = tick() * 1000
        local finalY = (Settings.NR_Mode == "Classic") and Settings.RecoilStrength or
            (Settings.RecoilStrength * (dt * 60))

        if Settings.MovementMode == "Constant" then
            if mousemoverel then
                mousemoverel(shake, finalY)
            end
        else
            if Settings.ImpulseInterval <= 0 then
                if not HasShotOnce then
                    if mousemoverel then
                        mousemoverel(shake, finalY)
                    end
                    HasShotOnce = true
                end
            else
                if (currentTime - LastImpulseTime) >= Settings.ImpulseInterval then
                    if mousemoverel then
                        mousemoverel(shake, finalY)
                    end
                    LastImpulseTime = currentTime
                end
            end
        end
    end
end

-- Counter Blox Wall Shot Logic
local function IsWall(part)
    if not part or not part:IsA("BasePart") then return false end

    -- Игнорируем пол и землю
    local nameLower = part.Name:lower()
    if nameLower:find("floor") or nameLower:find("ground") or nameLower:find("terrain") then
        return false
    end

    if part.Parent then
        local parentName = part.Parent.Name:lower()
        if parentName:find("floor") or parentName:find("ground") then
            return false
        end
    end

    -- Проверка что это стена (большие вертикальные части)
    local size = part.Size

    -- Вертикальные стены (высокие)
    if size.Y > 5 then
        return true
    end

    -- Горизонтальные стены (широкие и тонкие)
    if (size.X > 10 and size.Z > 0.5 and size.Z < 5) or
        (size.Z > 10 and size.X > 0.5 and size.X < 5) then
        return true
    end

    -- Дополнительная проверка: если объект называется "Wall"
    if nameLower:find("wall") or nameLower:find("barrier") then
        return true
    end

    return false
end

local function SaveWallProperties(part)
    if not OriginalWallProperties[part] then
        OriginalWallProperties[part] = {
            Parent = part.Parent,
            CanCollide = part.CanCollide,
            CanQuery = part.CanQuery,
            Transparency = part.Transparency,
            LocalTransparencyModifier = part.LocalTransparencyModifier
        }
    end
end

local function MakeWallInvisible(part, mode)
    SaveWallProperties(part)

    local method = Settings.WallShotMethod or "Hook (Silent)"

    -- [METHOD 1]: Hook (Silent) - Best
    if method:find("Hook") then
        if mode == "Ghost" then
            part.Transparency = 0.7
            part.LocalTransparencyModifier = 0.7
        end

        -- [METHOD 2]: Reparent (Physical Removal) - Universal
    elseif method:find("Reparent") then
        part.Parent = nil

        -- [METHOD 3]: CanQuery (Soft Disable)
    elseif method:find("CanQuery") then
        part.CanQuery = false
        part.CanCollide = false
        if mode == "Ghost" then
            part.Transparency = 0.7
            part.LocalTransparencyModifier = 0.7
        end
    end

    WallStorage[part] = true
end

RestoreWalls = function()
    for part, _ in pairs(WallStorage) do
        if OriginalWallProperties[part] then
            local props = OriginalWallProperties[part]

            -- Restore properties
            pcall(function()
                part.Transparency = props.Transparency
                part.LocalTransparencyModifier = props.LocalTransparencyModifier
                part.CanQuery = props.CanQuery
                part.CanCollide = props.CanCollide

                -- Restore Parent if needed
                if props.Parent and part.Parent ~= props.Parent then
                    part.Parent = props.Parent
                end
            end)
        end
    end
    WallStorage = {}
    OriginalWallProperties = {}
end


local function BuildRaycastFilter(outList)
    local list = outList or {}
    local idx = 0
    local localChar = LocalPlayer and LocalPlayer.Character
    if localChar then
        idx = idx + 1
        list[idx] = localChar
    end
    if Camera then
        idx = idx + 1
        list[idx] = Camera
    end
    for i = idx + 1, #list do
        list[i] = nil
    end
    return list
end


local function GetWallsInCrosshair()
    if not Camera then return {} end

    local rayParams = PredConst.WallRayParams
    if not rayParams then
        rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        PredConst.WallRayParams = rayParams
    end

    local ignoreList = BuildRaycastFilter(PredConst.WallIgnoreList)
    PredConst.WallIgnoreList = ignoreList
    rayParams.FilterDescendantsInstances = ignoreList

    local origin = Camera.CFrame.Position
    local direction = Camera.CFrame.LookVector * 2000

    local walls = PredConst.WallsBuffer
    if not walls then
        walls = {}
        PredConst.WallsBuffer = walls
    end
    for i = #walls, 1, -1 do
        walls[i] = nil
    end
    local currentOrigin = origin

    -- Collect walls efficiently
    for i = 1, 20 do -- Reduced distinct checks for performance
        local result = Workspace:Raycast(currentOrigin, direction, rayParams)
        if not result then break end

        local hitPart = result.Instance

        if IsWall(hitPart) then
            walls[#walls + 1] = hitPart
        end

        -- Ignore this wall to find the next one behind it
        ignoreList[#ignoreList + 1] = hitPart
        rayParams.FilterDescendantsInstances = ignoreList

        -- Advance origin slightly to avoid precision issues
        currentOrigin = result.Position + direction.Unit * 0.5
    end

    return walls
end

local LastWallShotTime = 0
local function ApplyWallShot()
    if game.PlaceId ~= 301549746 then return end
    if not Settings.WallShot then
        if next(WallStorage) then RestoreWalls() end -- Only restore if needed
        return
    end

    -- Throttle updates (slower for Reparent to reduce flicker)
    local delay = (Settings.WallShotMethod and Settings.WallShotMethod:find("Reparent")) and 0.15 or 0.05
    if tick() - LastWallShotTime < delay then return end
    LastWallShotTime = tick()

    if Settings.WallShotMode == "Aiming" then
        -- For Reparent/CanQuery methods, we MUST restore walls first to see them with Raycast
        -- This causes 1 frame of visibility (flicker), but allows "unhiding" when looking away
        local method = Settings.WallShotMethod or "Hook"
        if method:find("Reparent") or method:find("CanQuery") then
            RestoreWalls()
        end

        local currentWalls = GetWallsInCrosshair()
        local currentWallsSet = {}

        -- Process current walls
        for _, wall in ipairs(currentWalls) do
            currentWallsSet[wall] = true
            if not WallStorage[wall] then
                MakeWallInvisible(wall, "Ghost")
            end
        end

        -- Override for Hook method: Restore walls that are NO LONGER in crosshair
        -- (Reparent method already restored everything at start of frame)
        if not method:find("Reparent") and not method:find("CanQuery") then
            for wall, _ in pairs(WallStorage) do
                if not currentWallsSet[wall] then
                    -- Full restore logic inline
                    if OriginalWallProperties[wall] then
                        local props = OriginalWallProperties[wall]
                        wall.Transparency = props.Transparency
                        wall.LocalTransparencyModifier = props.LocalTransparencyModifier
                        if props.Parent and wall.Parent ~= props.Parent then wall.Parent = props.Parent end
                        wall.CanCollide = props.CanCollide
                        wall.CanQuery = props.CanQuery
                    end
                    WallStorage[wall] = nil
                    OriginalWallProperties[wall] = nil
                end
            end
        end
    elseif Settings.WallShotMode == "Whole Map" then
        -- Add ALL walls to storage (Silent mode)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local pos = LocalPlayer.Character.HumanoidRootPart.Position
            if next(WallStorage) == nil or tick() % 5 < 0.1 then
                for _, obj in ipairs(Workspace:GetDescendants()) do
                    if IsWall(obj) and not WallStorage[obj] then
                        MakeWallInvisible(obj, "Silent")
                    end
                end
            end
        end
    elseif Settings.WallShotMode == "On Click (L)" then
        -- Logic moved to InputBegan for toggle behavior
    end
end

-- [UPDATED] Helper to get Search Origin based on specific Mode string (Renamed keys)
local function GetScreenPosition(mode)
    if mode == "Mousemoverel" then -- Was Cursor
        return UserInputService:GetMouseLocation()
    end
    if not Camera then
        return UserInputService:GetMouseLocation()
    else                           -- Old (Central)
        return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    end
end
local function IsVisible(targetPart, character)
    if not Settings.WallCheck then return true end
    if not Camera then return false end
    if not targetPart or not character then return false end

    local origin = Camera.CFrame.Position
    local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")

    -- ✅ ОПТИМИЗАЦИЯ: Переиспользуем SharedRayParams вместо new() каждый вызов
    local rayParams = SharedRayParams
    rayParams.IgnoreWater = true
    local ignoreList = PredConst.VisibleIgnoreList
    if not ignoreList then
        ignoreList = {}
        PredConst.VisibleIgnoreList = ignoreList
    end

    local checkCount = torso and 2 or 1
    for i = 1, checkCount do
        local targetPos = (i == 1 and targetPart.Position) or torso.Position
        local currentOrigin = origin
        BuildRaycastFilter(ignoreList)
        local maxIterations = 4

        for _ = 1, maxIterations do
            local direction = (targetPos - currentOrigin)
            local distance = direction.Magnitude
            if distance <= 0.001 then
                break
            end
            local directionUnit = direction / distance

            rayParams.FilterDescendantsInstances = ignoreList
            local result = Workspace:Raycast(currentOrigin, direction, rayParams)
            if not result then return true end

            local hitPart = result.Instance
            if not hitPart then
                break
            end

            if hitPart:IsDescendantOf(character) then return true end

            local canPass = false
            if hitPart:IsA("BasePart") then
                canPass = hitPart.Transparency > 0.25 or hitPart.Material == Enum.Material.Glass or not hitPart.CanQuery
            end

            if canPass then
                ignoreList[#ignoreList + 1] = hitPart
                currentOrigin = result.Position + (directionUnit * 0.1)
            else
                break
            end
        end
    end

    return false
end

local function IsVisibleCached(targetPart, character)
    -- 1. Быстрая проверка настроек
    if not Settings.WallCheck then return true end
    if not targetPart or not character then return false end

    -- 2. Создаем уникальный ключ для этой пары (игрок + часть тела)
    local cacheKey = targetPart

    -- 3. Проверяем если ли уже результат в кеше
    local cached = VisibilityCache[cacheKey]
    local currentTime = tick()

    -- 4. Если есть и не устарел -> возвращаем сохраненное значение
    if cached and (currentTime - cached.time) < VISIBILITY_CACHE_TTL then
        return cached.visible
    end

    -- 5. Если кэша нет или устарел -> используем умную проверку IsVisible
    local visible = IsVisible(targetPart, character)

    -- 6. Сохраняем результат в кэш
    VisibilityCache[cacheKey] = {
        visible = visible, -- true/false
        time = currentTime -- когда проверили
    }
    return visible
end

local KnockedFlagNames = { "KO", "Knocked", "Downed", "IsDowned", "DBNO", "Stunned" }

local function ValueIndicatesKnocked(valueObj)
    if not valueObj then
        return false
    end

    if valueObj:IsA("BoolValue") then
        return valueObj.Value == true
    end

    if valueObj:IsA("IntValue") or valueObj:IsA("NumberValue") then
        return valueObj.Value > 0
    end

    if valueObj:IsA("StringValue") then
        local valueLower = tostring(valueObj.Value):lower()
        return valueLower == "true" or valueLower == "knocked" or valueLower == "downed"
    end

    return false
end

local function IsCharacterKnocked(targetPlayer, character, humanoid)
    if not Settings.KnockedCheck then
        return false
    end

    local containers = { character, humanoid, targetPlayer }
    for _, container in ipairs(containers) do
        if container then
            for _, flagName in ipairs(KnockedFlagNames) do
                local flagObj = container:FindFirstChild(flagName)
                if ValueIndicatesKnocked(flagObj) then
                    return true
                end

                local ok, attrVal = pcall(function()
                    return container:GetAttribute(flagName)
                end)
                if ok then
                    if type(attrVal) == "boolean" and attrVal then
                        return true
                    end
                    if type(attrVal) == "number" and attrVal > 0 then
                        return true
                    end
                    if type(attrVal) == "string" then
                        local lowered = attrVal:lower()
                        if lowered == "true" or lowered == "knocked" or lowered == "downed" then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end


local function GetPartVelocity(part)
    if not part then
        return v3_new(0, 0, 0)
    end

    local ok, vel = pcall(function()
        return part.AssemblyLinearVelocity
    end)
    if ok and vel then
        return vel
    end

    local okLegacy, legacyVel = pcall(function()
        return part.Velocity
    end)
    if okLegacy and legacyVel then
        return legacyVel
    end

    return v3_new(0, 0, 0)
end

local function SmoothStep01(value)
    value = math_clamp(value, 0, 1)
    return value * value * (3 - (2 * value))
end

local function GetDynamicDeadzone(baseDeadzone, velocityMag, distance3d)
    local deadzone = math_max(0, baseDeadzone or 0)
    local speedFactor = math_clamp((velocityMag or 0) / 120, 0, 1)
    local distFactor = math_clamp((distance3d or 0) / 250, 0, 1)

    deadzone = deadzone * (1 - speedFactor * 0.45)
    deadzone = deadzone * (0.85 + distFactor * 0.35)

    return math_max(0, deadzone)
end

local function BuildSmoothFactor(baseSmooth, distance2d, deadzone, distance3d, adaptiveEnabled, smoothMode, flickEnabled, flickSpeed)
    local smooth = math_clamp(baseSmooth or 0.2, 0.01, 1)
    local normalized = SmoothStep01((distance2d - deadzone) / 180)

    if smoothMode == "Old" then
        smooth = smooth * (0.35 + normalized * 0.95)
    else
        smooth = smooth * (0.5 + normalized * 1.1)
    end

    if adaptiveEnabled then
        if distance3d < 50 then
            smooth = smooth * 0.72
        elseif distance3d > 180 then
            smooth = smooth * 1.2
        end
    end

    if flickEnabled and distance2d > 55 then
        smooth = math_max(smooth, flickSpeed or 0.8)
    end

    return math_clamp(smooth, 0.01, 1), normalized
end

local function ApplyHumanizedDelta(delta, timeAlive, humanizePower)
    local distance = delta.Magnitude
    if distance <= 0.001 then
        return delta
    end

    local power = math_max(0.1, humanizePower or 1)
    local wobbleScale = math_clamp(distance / 220, 0.25, 1)

    local swayX = math.sin(timeAlive * 4.7) * distance * 0.06 * power * wobbleScale
    local swayY = math.cos(timeAlive * 3.9) * distance * 0.04 * power * wobbleScale

    return delta + v2_new(swayX, swayY)
end

local function GetClosestTarget(fovLimit, hitPartName, originPoint, state)
    if not Camera then
        return nil
    end

    state = state or AimbotState
    state.VisibilityUntil = state.VisibilityUntil or setmetatable({}, { __mode = "k" })

    local currentSticky = state.StickyTarget
    local currentTick = tick()
    local frameTick = math.floor(currentTick * 60)
    local knockedCheckEnabled = Settings.KnockedCheck
    local originX = originPoint and math.floor(originPoint.X + 0.5) or 0
    local originY = originPoint and math.floor(originPoint.Y + 0.5) or 0

    if FrameTargetCache.tick == frameTick and
        FrameTargetCache.fov == fovLimit and
        FrameTargetCache.part == hitPartName and
        FrameTargetCache.ox == originX and
        FrameTargetCache.oy == originY then
        local cached = FrameTargetCache.target
        if cached and cached.Parent then
            state.CurrentTarget = cached
            return cached
        end
    end

    if Settings.StickyAim and currentSticky then
        local stickyTime = currentTick - state.StickyStartTime
        if stickyTime < (Settings.StickyDuration or 1) then
            local target = currentSticky
            if target and target.Parent then
                local hum = target.Parent:FindFirstChild("Humanoid")
                local isAlive = (not hum) or (hum.Health > 0)
                local stickyVisible = IsVisibleCached(target, target.Parent)
                if stickyVisible then
                    state.VisibilityUntil[target] = currentTick + TARGET_OCCLUSION_GRACE
                end

                local stickyGraceUntil = state.VisibilityUntil[target]
                local stickyHasVision = stickyVisible or (stickyGraceUntil and stickyGraceUntil > currentTick)
                local stickyKnocked = false
                if knockedCheckEnabled then
                    local stickyPlayer = ResolvePlayerFromCharacterModel(target.Parent)
                    stickyKnocked = IsCharacterKnocked(stickyPlayer, target.Parent, hum)
                end

                if isAlive and (not stickyKnocked) and stickyHasVision then
                    local sp, onScreen = Camera:WorldToViewportPoint(target.Position)
                    local dx = sp.X - originPoint.X
                    local dy = sp.Y - originPoint.Y
                    local dist = math_sqrt(dx * dx + dy * dy)
                    if onScreen and dist <= fovLimit * 1.35 then
                        state.CurrentTarget = target
                        return target
                    end
                end
            end
        else
            state.StickyTarget = nil
        end
    end

    if state.CurrentTarget and state.CurrentTarget.Parent then
        local hum = state.CurrentTarget.Parent:FindFirstChild("Humanoid")
        if hum and hum.Health <= 0 then
            state.CurrentTarget = nil
            state.StickyTarget = nil
            state.StickyStartTime = 0
        end
    end

    local bestTarget, bestScore = nil, -math_huge
    local currentTargetScore = -math_huge
    local partName =
        hitPartName == "Neck" and "Head"
        or hitPartName == "Chest" and "UpperTorso"
        or "Head"

    local fovX, fovY = fovLimit, fovLimit
    if Settings.OvalFOV then
        local aspectRatio = Camera.ViewportSize.X / Camera.ViewportSize.Y
        fovX = fovLimit * aspectRatio
    end

    if not Settings.AutoSwitch and state.CurrentTarget and state.CurrentTarget.Parent then
        local lockedTarget = state.CurrentTarget
        local lockedChar = lockedTarget.Parent
        local lockedHum = lockedChar:FindFirstChild("Humanoid")
        local lockedAlive = (not lockedHum) or (lockedHum.Health > 0)
        local lockedKnocked = false
        if knockedCheckEnabled then
            local lockedPlayer = ResolvePlayerFromCharacterModel(lockedChar)
            lockedKnocked = IsCharacterKnocked(lockedPlayer, lockedChar, lockedHum)
        end

        if lockedAlive and (not lockedKnocked) then
            local sp, onScreen = Camera:WorldToViewportPoint(lockedTarget.Position)
            if onScreen then
                local deltaX = math.abs(sp.X - originPoint.X)
                local deltaY = math.abs(sp.Y - originPoint.Y)
                local normalizedDist = math_sqrt((deltaX / fovX) ^ 2 + (deltaY / fovY) ^ 2)

                local lockedVisible = IsVisibleCached(lockedTarget, lockedChar)
                if lockedVisible then
                    state.VisibilityUntil[lockedTarget] = currentTick + TARGET_OCCLUSION_GRACE
                end
                local lockedGrace = state.VisibilityUntil[lockedTarget]

                if normalizedDist <= 1 and (lockedVisible or (lockedGrace and lockedGrace > currentTick)) then
                    return lockedTarget
                end
            end
        end
    end

    local W_Dist, W_Health, W_Angle, W_Threat = -1.5, -0.3, -1.2, 0
    local priority = Settings.TargetPriority
    if priority == "Health" then
        W_Health = -3.0
        W_Dist = -0.5
        W_Angle = -0.5
    elseif priority == "Distance" then
        W_Dist = -3.0
        W_Health = -0.2
        W_Angle = -0.3
    elseif priority == "Threat" then
        W_Threat = 2.0
        W_Dist = -1.0
        W_Health = -0.5
        W_Angle = -0.8
    end

    local camCF = Camera.CFrame
    local camPos = camCF.Position
    local lookVector = camCF.LookVector

    for i = 1, #TargetScanPlayers do
        local plr = TargetScanPlayers[i]
        local char = ResolveCharacterModel(plr)
        if char then
            local hum = char:FindFirstChild("Humanoid")
            if hum and hum.Health <= 0 then continue end
            if Settings.TC_NoAim and IsTeammate(plr) then continue end
            if knockedCheckEnabled and IsCharacterKnocked(plr, char, hum) then continue end

            local root = ResolveCharacterRoot(char)
            if not root then continue end

            local part = char:FindFirstChild(partName)
            if not part and partName == "UpperTorso" then
                part = char:FindFirstChild("Torso")
            end
            if not part then
                part = root
            end
            if not part then continue end

            local sp, onScreen = Camera:WorldToViewportPoint(part.Position)
            if not onScreen then continue end

            local deltaX = sp.X - originPoint.X
            local deltaY = sp.Y - originPoint.Y
            local normalizedDist = math_sqrt((deltaX / fovX) ^ 2 + (deltaY / fovY) ^ 2)
            if normalizedDist > 1 then continue end

            local dist2d = math_sqrt(deltaX * deltaX + deltaY * deltaY)
            local partPos = part.Position
            local dist3d = (partPos - camPos).Magnitude

            local directionToTarget = (partPos - camPos).Unit
            local lookDot = math_clamp(lookVector:Dot(directionToTarget), -1, 1)

            local canSee = IsVisibleCached(part, char)
            if canSee then
                state.VisibilityUntil[part] = currentTick + TARGET_OCCLUSION_GRACE
            else
                local graceUntil = state.VisibilityUntil[part]
                if not graceUntil or graceUntil <= currentTick then
                    continue
                end
            end

            local maxHealth = (hum and hum.MaxHealth) or 100
            if maxHealth <= 0 then maxHealth = 100 end
            local currentHealth = (hum and hum.Health) or 100
            if hum and currentHealth <= 0 then continue end

            local score
            if priority == "Distance" then
                score = (W_Dist * (dist3d / 500))
            else
                score = (W_Dist * (dist2d / math_max(1, fovLimit)))
            end

            score = score + (W_Health * (currentHealth / maxHealth))
            score = score + (W_Angle * (1 - lookDot))

            if not canSee then
                score = score - 0.6
            end

            if W_Threat > 0 then
                local tool = char:FindFirstChildOfClass("Tool")
                if tool then
                    score = score + W_Threat
                end
            end

            local velocity = GetPartVelocity(part)
            if velocity.Magnitude > 15 then
                score = score + 0.4
            end

            if part == state.CurrentTarget then
                score = score + TARGET_CURRENT_BONUS
            end
            if part == state.StickyTarget then
                score = score + TARGET_STICKY_BONUS
            end
            if part == state.CurrentTarget then
                currentTargetScore = score
            end

            if score > bestScore then
                bestScore = score
                bestTarget = part
            end
        end
    end

    if bestTarget and state.CurrentTarget and bestTarget ~= state.CurrentTarget and currentTargetScore > -math_huge then
        local switchMargin = TARGET_SWITCH_MARGIN
        if Settings.StickyAim then
            switchMargin = switchMargin + 0.08
        end
        if (bestScore - currentTargetScore) < switchMargin then
            bestTarget = state.CurrentTarget
            bestScore = currentTargetScore
        end
    end

    local previousTarget = state.CurrentTarget
    state.CurrentTarget = bestTarget

    if previousTarget ~= bestTarget then
        state.LastTargetSwap = currentTick
    end

    if bestTarget ~= state.StickyTarget then
        state.StickyTarget = bestTarget
        state.StickyStartTime = currentTick
    end

    if bestTarget then
        state.VisibilityUntil[bestTarget] = currentTick + TARGET_OCCLUSION_GRACE
    end

    FrameTargetCache.target = bestTarget
    FrameTargetCache.tick = frameTick
    FrameTargetCache.fov = fovLimit
    FrameTargetCache.part = hitPartName
    FrameTargetCache.ox = originX
    FrameTargetCache.oy = originY

    return bestTarget
end


task.spawn(function()
    while _G.CheatLoaded do
        task.wait(5)
        if not _G.CheatLoaded then break end

        -- ✅ ОПТИМИЗАЦИЯ: Инкрементальная очистка вместо полного сброса
        local ct = tick()
        for k, v in pairs(VisibilityCache) do
            if ct - v.time > 1.0 then
                VisibilityCache[k] = nil
            end
        end
    end
end)
-- ═══════════════════════════════════════════
-- [NEW v2] RING BUFFER HELPERS
-- ═══════════════════════════════════════════

local function GetOrCreateBuffer(player)
    if not player then return nil end
    local buf = VelocityBuffers[player]
    if buf then return buf end

    local samples = {}
    for i = 1, PredConst.RING_BUFFER_SIZE do
        samples[i] = { vel = v3_new(0, 0, 0), time = 0, valid = false }
    end

    buf = {
        samples = samples,
        head = 1,
        count = 0,
        lastUpdate = 0,
        smoothedAccel = v3_new(0, 0, 0),
        confidence = 0,
    }
    VelocityBuffers[player] = buf
    return buf
end

local function PushSample(buf, velocity, currentTime)
    if not buf then return end
    local sample = buf.samples[buf.head]
    sample.vel = velocity
    sample.time = currentTime
    sample.valid = true
    buf.head = (buf.head % PredConst.RING_BUFFER_SIZE) + 1
    if buf.count < PredConst.RING_BUFFER_SIZE then
        buf.count = buf.count + 1
    end
    buf.lastUpdate = currentTime
end

local function IterateBufferNewToOld(buf, callback)
    if not buf or buf.count == 0 then return end
    local idx = ((buf.head - 2) % PredConst.RING_BUFFER_SIZE) + 1
    for i = 1, buf.count do
        local sample = buf.samples[idx]
        if sample.valid then
            if callback(sample, i) then return end
        end
        idx = ((idx - 2) % PredConst.RING_BUFFER_SIZE) + 1
    end
end

local function IsAnomalousVelocity(newVel, prevVel, dt)
    if newVel.Magnitude > PredConst.ANOMALY_SPEED_THRESHOLD then
        return true
    end
    if prevVel and dt > 0 then
        local accel = ((newVel - prevVel) / dt).Magnitude
        if accel > PredConst.ANOMALY_ACCEL_THRESHOLD then
            return true
        end
    end
    return false
end

-- ═══════════════════════════════════════════
-- [NEW v2] ENVIRONMENT RAYCAST CLAMP
-- ═══════════════════════════════════════════

local function ClampPredictionToEnvironment(currentPos, predictedPos, character)
    if not currentPos or not predictedPos then return predictedPos, nil end
    local delta = predictedPos - currentPos
    local dist = delta.Magnitude
    if dist < 1 then return predictedPos, nil end

    local filterList = {}
    if character then filterList[#filterList + 1] = character end
    local localChar = LocalPlayer and LocalPlayer.Character
    if localChar then filterList[#filterList + 1] = localChar end
    if Camera then filterList[#filterList + 1] = Camera end
    PredConst.ClampRayParams.FilterDescendantsInstances = filterList

    local result = Workspace:Raycast(currentPos, delta, PredConst.ClampRayParams)
    if result then
        local hitDist = (result.Position - currentPos).Magnitude
        local clampedDist = math_max(0, hitDist - PredConst.RAYCAST_CLAMP_DISTANCE)
        return currentPos + delta.Unit * clampedDist, result
    end
    return predictedPos, nil
end

-- ═══════════════════════════════════════════
-- [IMPROVED v2] VELOCITY SMOOTHING (Ring Buffer + Anomaly Filter)
-- ═══════════════════════════════════════════

local function GetSmoothedVelocity(player, currentVelocity)
    if not Settings.VelocitySmoothing then
        return currentVelocity
    end

    if not player or not player.Parent then
        VelocityBuffers[player] = nil
        return currentVelocity
    end

    local currentTime = tick()
    local buf = GetOrCreateBuffer(player)

    -- Предыдущий сэмпл для проверки аномалии
    local prevSample = nil
    if buf.count > 0 then
        local prevIdx = ((buf.head - 2) % PredConst.RING_BUFFER_SIZE) + 1
        prevSample = buf.samples[prevIdx]
    end

    -- Детекция аномалии (телепорт/лаг)
    local dt = (prevSample and prevSample.valid) and (currentTime - prevSample.time) or 0
    local isAnomaly = IsAnomalousVelocity(
        currentVelocity,
        prevSample and prevSample.valid and prevSample.vel or nil,
        dt
    )

    if isAnomaly then
        buf.confidence = math_max(0, buf.confidence - 0.5)
    else
        buf.confidence = math_min(1, buf.confidence + 0.1)
    end

    PushSample(buf, currentVelocity, currentTime)

    -- Низкая уверенность → сырые данные без сглаживания
    if buf.confidence < 0.3 then
        return currentVelocity
    end

    -- Взвешенное среднее (свежие сэмплы весят больше)
    local sumVel = v3_new(0, 0, 0)
    local totalWeight = 0

    IterateBufferNewToOld(buf, function(sample)
        local age = currentTime - sample.time
        if age > PredConst.VELOCITY_MAX_AGE then return true end

        local weight = math_exp(-age * PredConst.CONFIDENCE_DECAY_RATE)
        sumVel = sumVel + (sample.vel * weight)
        totalWeight = totalWeight + weight
    end)

    return totalWeight > 0 and (sumVel / totalWeight) or currentVelocity
end

-- ═══════════════════════════════════════════
-- [IMPROVED v2] ACCELERATION (EMA Smoothed, Multi-Sample)
-- ═══════════════════════════════════════════

local function GetEstimatedAcceleration(player)
    local buf = VelocityBuffers[player]
    if not buf or buf.count < 2 then
        return v3_new(0, 0, 0)
    end

    local prevSample = nil
    local accelSum = v3_new(0, 0, 0)
    local accelWeight = 0
    local currentTime = tick()

    IterateBufferNewToOld(buf, function(sample)
        local age = currentTime - sample.time
        if age > PredConst.VELOCITY_MAX_AGE then return true end

        if prevSample then
            local sdt = prevSample.time - sample.time
            if sdt > 0.001 then
                local accel = (prevSample.vel - sample.vel) / sdt
                if accel.Magnitude < PredConst.ANOMALY_ACCEL_THRESHOLD then
                    local weight = math_exp(-age * 2)
                    accelSum = accelSum + accel * weight
                    accelWeight = accelWeight + weight
                end
            end
        end
        prevSample = sample
    end)

    if accelWeight <= 0 then
        return v3_new(0, 0, 0)
    end

    local rawAccel = accelSum / accelWeight

    -- EMA сглаживание ускорения
    buf.smoothedAccel = buf.smoothedAccel * (1 - PredConst.ACCEL_SMOOTHING_ALPHA) + rawAccel * PredConst.ACCEL_SMOOTHING_ALPHA

    -- Ограничение модуля
    if buf.smoothedAccel.Magnitude > 350 then
        buf.smoothedAccel = buf.smoothedAccel.Unit * 350
    end

    return buf.smoothedAccel
end

-- Cleanup velocity buffers
task.spawn(function()
    while _G.CheatLoaded do
        task.wait(10)
        local currentTime = tick()
        for player, buf in pairs(VelocityBuffers) do
            if not player or not player.Parent or (currentTime - buf.lastUpdate) > 5 then
                VelocityBuffers[player] = nil
            end
        end
        for player, state in pairs(PredictionStates) do
            local stale = (not player) or (not player.Parent)
            if not stale and state then
                local age = currentTime - (state.lastTime or currentTime)
                stale = age > 5
            end
            if stale then
                PredictionStates[player] = nil
                PredictionFrameCache[player] = nil
            end
        end
    end
end)

-- ✅ ОПТИМИЗАЦИЯ: Кеш пинга (обновляется раз в 0.5 сек вместо каждого кадра)
local _PingCache = { val = 0, time = 0 }
local function GetCachedPing()
    local t = tick()
    if t - _PingCache.time > 0.5 then
        _PingCache.val = LocalPlayer:GetNetworkPing()
        _PingCache.time = t
    end
    return _PingCache.val
end

--// BEZIER & MATH HELPERS //--

local function BezierCubic(t, p0, p1, p2, p3)
    return (1 - t) ^ 3 * p0 + 3 * (1 - t) ^ 2 * t * p1 + 3 * (1 - t) * t ^ 2 * p2 + t ^ 3 * p3
end

-- Generates control points for a "human-like" arc
local function GetBezierPoints(startPos, endPos, intensity, bias1, bias2)
    local distance = (endPos - startPos).Magnitude
    if distance < 5 then return startPos, endPos, endPos, endPos end -- Too close for curves

    local direction = (endPos - startPos).Unit
    local perpendicular = Vector2.new(-direction.Y, direction.X)

    -- Randomize curve side and depth
    local curveBias1 = (type(bias1) == "number") and bias1 or ((math.random() - 0.5) * 2)
    local curveBias2 = (type(bias2) == "number") and bias2 or ((math.random() - 0.5) * 2)
    local r1 = curveBias1 * intensity * (distance * 0.3)
    local r2 = curveBias2 * intensity * (distance * 0.3)

    local p1 = startPos + (direction * (distance * 0.3)) + (perpendicular * r1)
    local p2 = startPos + (direction * (distance * 0.6)) + (perpendicular * r2)

    return startPos, p1, p2, endPos
end

PredConst.BlendVector2 = function(current, target, alpha)
    if not current then
        return target
    end
    return current + ((target - current) * math_clamp(alpha, 0, 1))
end

PredConst.ResetHumanizerState = function(state)
    if state then
        state.HumanizeData = nil
    end
end

PredConst.GetOrCreateHumanizerState = function(state, targetPart, currentTime)
    if not state then
        return nil
    end

    local data = state.HumanizeData
    if data and data.target == targetPart then
        return data
    end

    local bias1 = (math_random() * 2) - 1
    local bias2 = (math_random() * 2) - 1
    if math_abs(bias1) < 0.18 then
        bias1 = bias1 >= 0 and 0.18 or -0.18
    end
    if math_abs(bias2) < 0.12 then
        bias2 = bias2 >= 0 and 0.12 or -0.12
    end

    data = {
        target = targetPart,
        startedAt = currentTime,
        lastTime = currentTime,
        phase = math_random() * 6.28318,
        curveBias1 = bias1,
        curveBias2 = bias2,
        overshootBias = 0.82 + math_random() * 0.52,
        velocityBias = -0.18 + math_random() * 0.78,
        speedBias = 0.9 + math_random() * 0.22,
        breathRate = 0.85 + math_random() * 0.7,
        jitterRate = 4.5 + math_random() * 2.8,
        offset = v2_new(0, 0),
        output = nil
    }

    state.HumanizeData = data
    return data
end

PredConst.GetProjectedScreenVelocity = function(screenPoint, worldPosition, targetVelocity)
    if not Camera or not worldPosition or not targetVelocity then
        return v2_new(0, 0)
    end

    local speed = targetVelocity.Magnitude
    if speed <= 0.05 then
        return v2_new(0, 0)
    end

    local lookAhead = math_clamp(0.018 + (speed / 2200), 0.018, 0.055)
    local futureScreen, onScreen = Camera:WorldToViewportPoint(worldPosition + (targetVelocity * lookAhead))
    if not onScreen then
        return v2_new(0, 0)
    end

    return v2_new(futureScreen.X, futureScreen.Y) - screenPoint
end

PredConst.GetHumanizedScreenPoint = function(state, targetPart, originPoint, screenPoint, worldPosition, targetVelocity,
                                             currentTime, humanizePower, distance3d)
    local delta = screenPoint - originPoint
    local distance = delta.Magnitude
    if distance <= 0.001 then
        return screenPoint, 1, 1
    end

    local power = math_clamp(humanizePower or 1, 0.1, 6)
    local data = PredConst.GetOrCreateHumanizerState(state, targetPart, currentTime)
    if not data then
        return screenPoint, 1, 1
    end

    local dt = math_clamp(currentTime - (data.lastTime or currentTime), 1 / 240, 0.12)
    data.lastTime = currentTime

    local timeAlive = currentTime - (data.startedAt or currentTime)
    local settle = SmoothStep01(math_clamp(timeAlive / (0.16 + power * 0.05), 0, 1))
    local distanceFactor = math_clamp(distance / 240, 0.18, 1.25)
    local depthFactor = math_clamp((distance3d or 0) / 220, 0.35, 1.15)

    local p0, p1, p2, p3 = GetBezierPoints(
        v2_new(0, 0),
        delta,
        math_clamp((0.18 + power * 0.05) * distanceFactor * (1 - settle * 0.72), 0.04, 0.42),
        data.curveBias1,
        data.curveBias2
    )
    local bezierProgress = math_clamp(0.62 + settle * 0.26, 0.55, 0.94)
    local curvePoint = BezierCubic(bezierProgress, p0, p1, p2, p3)
    local curveOffset = curvePoint - delta

    local legacyOffset = ApplyHumanizedDelta(delta, timeAlive, power * 0.45) - delta
    local projectedVelocity = PredConst.GetProjectedScreenVelocity(screenPoint, worldPosition, targetVelocity)
    local velocityOffset = projectedVelocity * ((0.08 + power * 0.018) * data.velocityBias) * (1 - settle * 0.5) *
        depthFactor

    local breathingOffset = v2_new(
        math.sin(currentTime * (1.18 + data.breathRate * 0.34) + data.phase) * distance * 0.0065,
        math.cos(currentTime * (1.04 + data.breathRate * 0.26) + data.phase * 1.37) * distance * 0.0048
    ) * power * depthFactor

    local nearFactor = math_clamp((34 - distance) / 34, 0, 1)
    local microJitter = v2_new(
        math.sin(currentTime * data.jitterRate + data.phase * 0.7),
        math.cos(currentTime * (data.jitterRate * 1.18) + data.phase * 1.12)
    ) * ((0.18 + power * 0.08) * nearFactor)

    local desiredOffset = curveOffset + (legacyOffset * (0.42 + depthFactor * 0.12)) + velocityOffset + breathingOffset +
        microJitter
    local offsetAlpha = math_clamp(dt * (6.4 + power * 1.3), 0.08, 0.5)
    data.offset = PredConst.BlendVector2(data.offset, desiredOffset, offsetAlpha)

    local overshootScale = 1 +
        math_clamp((1 - settle) * 0.055 * power * data.overshootBias * math_clamp(distance / 90, 0, 1), 0, 0.16)
    local desiredDelta = (delta * overshootScale) + data.offset
    local maxMagnitude = distance * (1.05 + (1 - settle) * 0.12 * data.overshootBias) + math_max(2, nearFactor * 3)
    if desiredDelta.Magnitude > maxMagnitude then
        desiredDelta = desiredDelta.Unit * maxMagnitude
    end

    if not data.output then
        data.output = delta * (0.18 + math_random() * 0.06)
    end

    local outputAlpha = math_clamp(dt * (7.6 + power * 1.4), 0.08, 0.58)
    data.output = PredConst.BlendVector2(data.output, desiredDelta, outputAlpha)

    if data.output.Magnitude > 0.001 and data.output:Dot(delta) < 0 then
        data.output = PredConst.BlendVector2(data.output, delta, 0.55)
    end

    local smoothScale = math_clamp((0.78 + settle * 0.24) * (0.96 + (data.speedBias - 1) * 0.35), 0.68, 1.08)
    local stepScale = math_clamp(0.82 + settle * 0.22 + distanceFactor * 0.08, 0.76, 1.12)

    return originPoint + data.output, smoothScale, stepScale
end

PredConst.ResetKalmanAxis = function(axis, position, velocity)
    axis.x = position
    axis.v = velocity
    axis.p11 = 2.5
    axis.p12 = 0
    axis.p22 = 14
end

PredConst.ResetPredictionState = function(state, position, velocity, currentTime)
    PredConst.ResetKalmanAxis(state.xAxis, position.X, velocity.X)
    PredConst.ResetKalmanAxis(state.yAxis, position.Y, velocity.Y)
    PredConst.ResetKalmanAxis(state.zAxis, position.Z, velocity.Z)
    state.lastTime = currentTime
    state.lastRawVelocity = velocity
    state.lastRawAccel = v3_new(0, 0, 0)
    state.confidence = 1
    state.lastManeuver = "stable"
end

PredConst.GetOrCreatePredictionState = function(player, position, velocity, currentTime)
    if not player then
        return nil
    end

    local state = PredictionStates[player]
    if not state then
        state = {
            xAxis = {},
            yAxis = {},
            zAxis = {},
            lastTime = currentTime,
            lastRawVelocity = velocity,
            lastRawAccel = v3_new(0, 0, 0),
            confidence = 1,
            lastManeuver = "stable"
        }
        PredictionStates[player] = state
        PredConst.ResetPredictionState(state, position, velocity, currentTime)
        return state
    end

    if (currentTime - (state.lastTime or currentTime)) > PredConst.KALMAN_RESET_TIMEOUT then
        PredConst.ResetPredictionState(state, position, velocity, currentTime)
    end

    return state
end

PredConst.KalmanPredictAxis = function(axis, dt, q)
    axis.x = axis.x + axis.v * dt

    local dt2 = dt * dt
    local dt3 = dt2 * dt
    local dt4 = dt2 * dt2

    local q11 = 0.25 * dt4 * q
    local q12 = 0.5 * dt3 * q
    local q22 = dt2 * q

    local p11 = axis.p11
    local p12 = axis.p12
    local p22 = axis.p22

    axis.p11 = p11 + dt * (p12 + p12 + dt * p22) + q11
    axis.p12 = p12 + dt * p22 + q12
    axis.p22 = p22 + q22
end

PredConst.KalmanUpdateAxis = function(axis, measurement, r)
    local p11 = axis.p11
    local p12 = axis.p12
    local p22 = axis.p22

    local innovation = measurement - axis.x
    local s = p11 + r
    if s <= 1e-5 then
        return math_abs(innovation)
    end

    local invS = 1 / s
    local k1 = p11 * invS
    local k2 = p12 * invS

    axis.x = axis.x + k1 * innovation
    axis.v = axis.v + k2 * innovation

    axis.p11 = math_max((1 - k1) * p11, 1e-5)
    axis.p12 = (1 - k1) * p12
    axis.p22 = math_max(p22 - k2 * p12, 1e-5)

    return math_abs(innovation)
end

PredConst.KalmanPredictState = function(state, dt, q)
    PredConst.KalmanPredictAxis(state.xAxis, dt, q)
    PredConst.KalmanPredictAxis(state.yAxis, dt, q)
    PredConst.KalmanPredictAxis(state.zAxis, dt, q)
end

PredConst.KalmanUpdateState = function(state, measurement, r)
    local ix = PredConst.KalmanUpdateAxis(state.xAxis, measurement.X, r)
    local iy = PredConst.KalmanUpdateAxis(state.yAxis, measurement.Y, r)
    local iz = PredConst.KalmanUpdateAxis(state.zAxis, measurement.Z, r)
    return (ix + iy + iz) / 3
end

PredConst.ReadKalmanState = function(state)
    return v3_new(state.xAxis.x, state.yAxis.x, state.zAxis.x),
        v3_new(state.xAxis.v, state.yAxis.v, state.zAxis.v)
end

PredConst.ClassifyPredictionManeuver = function(character, velocity, acceleration, jerkMagnitude, lateralAccelMagnitude)
    local sensitivity = math_max(0.2, Settings.ManeuverSensitivity or 1.0)
    local accelThreshold = PredConst.MANEUVER_ACCEL_THRESHOLD / sensitivity
    local lateralThreshold = PredConst.MANEUVER_LATERAL_THRESHOLD / sensitivity
    local jerkThreshold = PredConst.MANEUVER_JERK_THRESHOLD / sensitivity

    local humanoid = character and character:FindFirstChild("Humanoid")
    if humanoid then
        local humanoidState = humanoid:GetState()
        if humanoidState == Enum.HumanoidStateType.Freefall or humanoidState == Enum.HumanoidStateType.Jumping then
            return "airborne", 1.85, 1.0, 0.82
        end
    end

    local speed = velocity.Magnitude
    local accelMag = acceleration.Magnitude

    if jerkMagnitude > jerkThreshold or lateralAccelMagnitude > lateralThreshold then
        return "dodge", 3.4, 0.85, 0.52
    end

    if accelMag > accelThreshold then
        return "turn", 1.95, 0.95, 0.74
    end

    if speed < 3 then
        return "idle", 0.65, 1.2, 0.96
    end

    return "stable", 0.85, 1.25, 1.0
end

local function GetPredictedPos(targetPart, targetPlayer)
    if not targetPart then
        return v3_new(0, 0, 0)
    end
    if not Settings.PredictionEnabled then
        return targetPart.Position
    end
    if not Camera then
        return targetPart.Position
    end

    local now = tick()
    local frameTick = math.floor(now * 120)
    if targetPlayer then
        local cached = PredictionFrameCache[targetPlayer]
        if cached and cached.tick == frameTick and cached.part == targetPart then
            return cached.pos
        end
    end

    -- ═══ 1. СБОР ДАННЫХ ═══
    local origin = Camera.CFrame.Position
    local measuredPos = targetPart.Position
    local rawVelocity = GetPartVelocity(targetPart)
    local character = targetPart.Parent

    local bulletSpeed = math_max(1, Settings.BulletSpeed or 2200)
    local bulletDrop = Settings.BulletDrop or 0
    local gravity = Workspace.Gravity

    -- ═══ 2. СГЛАЖИВАНИЕ СКОРОСТИ ═══
    local velocity = rawVelocity
    if Settings.VelocitySmoothing and targetPlayer then
        velocity = GetSmoothedVelocity(targetPlayer, rawVelocity)
    end

    local speed = velocity.Magnitude
    if speed < PredConst.MIN_VELOCITY_THRESHOLD then
        velocity = v3_new(0, 0, 0)
        speed = 0
    end

    -- ═══ 3. БАЗОВОЕ УСКОРЕНИЕ ═══
    local gravityAccel = v3_new(0, 0, 0)
    if character then
        local hum = character:FindFirstChild("Humanoid")
        if hum then
            local state = hum:GetState()
            if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
                gravityAccel = v3_new(0, -gravity, 0)
            end
        end
    end

    local moveAccel = v3_new(0, 0, 0)
    if targetPlayer and Settings.VelocitySmoothing then
        moveAccel = GetEstimatedAcceleration(targetPlayer)
    end

    local acceleration = gravityAccel + v3_new(moveAccel.X * 0.2, 0, moveAccel.Z * 0.2)

    -- ═══ 4. KALMAN ФИЛЬТР + АДАПТАЦИЯ ═══
    local filterMode = Settings.PredictionFilter or "Adaptive Kalman"
    local useKalman = targetPlayer and (filterMode == "Kalman" or filterMode == "Adaptive Kalman")
    local filteredPos = measuredPos
    local filteredVel = velocity
    local kalmanState = nil
    local kalmanConfidence = 1

    if useKalman then
        kalmanState = PredConst.GetOrCreatePredictionState(targetPlayer, measuredPos, velocity, now)
        local dt = math_clamp(now - (kalmanState.lastTime or now), PredConst.KALMAN_MIN_DT, PredConst.KALMAN_MAX_DT)

        local previousRawVel = kalmanState.lastRawVelocity or rawVelocity
        local rawAccel = (rawVelocity - previousRawVel) / math_max(dt, PredConst.KALMAN_MIN_DT)
        local prevAccel = kalmanState.lastRawAccel or v3_new(0, 0, 0)
        local jerkMagnitude = ((rawAccel - prevAccel) / math_max(dt, PredConst.KALMAN_MIN_DT)).Magnitude

        local velocityMag = velocity.Magnitude
        local lateralAccelMagnitude = 0
        if velocityMag > 1 then
            local forward = velocity / velocityMag
            local lateralAccel = rawAccel - forward * rawAccel:Dot(forward)
            lateralAccelMagnitude = lateralAccel.Magnitude
        end

        local qScale, rScale, maneuverConfidence = 1, 1, 1
        local maneuverName = "stable"
        if filterMode == "Adaptive Kalman" then
            maneuverName, qScale, rScale, maneuverConfidence =
                PredConst.ClassifyPredictionManeuver(character, velocity, rawAccel, jerkMagnitude, lateralAccelMagnitude)
        end

        local qBase = PredConst.KALMAN_Q_BASE * math_max(0.05, Settings.KalmanProcessNoise or 1.0)
        local rBase = PredConst.KALMAN_R_BASE * math_max(0.05, Settings.KalmanMeasurementNoise or 1.0)
        local q = qBase * qScale
        local r = rBase * rScale

        PredConst.KalmanPredictState(kalmanState, dt, q)
        local innovation = PredConst.KalmanUpdateState(kalmanState, measuredPos, r)
        filteredPos, filteredVel = PredConst.ReadKalmanState(kalmanState)

        local innovationPenalty = math_clamp(innovation / (6 + velocityMag * 0.05), 0, 1)
        local targetConfidence = math_clamp((1 - innovationPenalty) * maneuverConfidence, 0, 1)
        kalmanState.confidence = kalmanState.confidence + (targetConfidence - kalmanState.confidence) * 0.22
        kalmanState.confidence = math_clamp(kalmanState.confidence, 0, 1)
        kalmanState.lastManeuver = maneuverName
        kalmanState.lastTime = now
        kalmanState.lastRawVelocity = rawVelocity
        kalmanState.lastRawAccel = rawAccel

        kalmanConfidence = kalmanState.confidence
        filteredVel = velocity:Lerp(filteredVel, 0.75)
    end

    speed = filteredVel.Magnitude
    local distance = (filteredPos - origin).Magnitude

    -- ═══ 5. ВРЕМЯ ПОЛЁТА (начальное + Smart mode) ═══
    local time = distance / bulletSpeed
    if Settings.PredictionMode == "Smart" then
        local ping = GetCachedPing()
        local frameDelay = 1 / 60
        local speedMultiplier = 1 + math_clamp(speed / 180, 0, 0.45)
        local distMultiplier = 1 + math_clamp(distance / 800, 0, 0.2)
        local stabilityPenalty = 1 + (1 - kalmanConfidence) * 0.35
        time = (time + ping + frameDelay) * speedMultiplier * distMultiplier * stabilityPenalty
    end

    -- ═══ 6. ADAPTIVE MULTIPLIER ═══
    local predictionMultiplier = Settings.PredictionMultiplier or 1
    if Settings.AdaptivePrediction then
        local speedFactor = math_clamp(speed / 120, 0, 1)
        local distanceFactor = math_clamp(distance / 350, 0, 1)
        local stabilityFactor = 1 + (1 - kalmanConfidence) * 0.3
        predictionMultiplier = predictionMultiplier * (1 + speedFactor * 0.35 + distanceFactor * 0.15) * stabilityFactor
    end
    time = math_clamp(time * predictionMultiplier, 0, PredConst.PREDICTION_TIME_MAX)

    -- ═══ 7. ИТЕРАТИВНЫЙ РЕШАТЕЛЬ (адаптивно + критерий сходимости) ═══
    local iterations = math_clamp(math.floor(Settings.PredictionIterations or 4), 1, 8)
    if distance > 300 and iterations < 6 then
        iterations = iterations + 1
    end

    local predictedPos = filteredPos
    local prevTime = time
    for _ = 1, iterations do
        local t2 = time * time
        predictedPos = filteredPos + filteredVel * time + 0.5 * acceleration * t2
        if bulletDrop > 0 then
            predictedPos = predictedPos + v3_new(0, -0.5 * gravity * bulletDrop * t2, 0)
        end

        local newTime = math_clamp((predictedPos - origin).Magnitude / bulletSpeed, 0, PredConst.PREDICTION_TIME_MAX)
        if math_abs(newTime - prevTime) <= PredConst.TIME_SOLVER_EPS then
            time = newTime
            break
        end
        prevTime = newTime
        time = newTime
    end

    -- ═══ 8. STANDARD MODE: ручная коррекция ═══
    if Settings.PredictionMode == "Standard" then
        local ping = GetCachedPing()
        predictedPos = predictedPos + filteredVel * ((Settings.Prediction + ping * 0.5) * predictionMultiplier)
    end

    -- ═══ 9. RAYCAST CLAMPING + коррекция состояния ═══
    local clampedPos, hitResult = ClampPredictionToEnvironment(filteredPos, predictedPos, character)
    predictedPos = clampedPos
    if hitResult and kalmanState then
        local n = hitResult.Normal
        local vn = filteredVel:Dot(n)
        if vn < 0 then
            filteredVel = filteredVel - n * vn
            kalmanState.xAxis.v = filteredVel.X
            kalmanState.yAxis.v = filteredVel.Y
            kalmanState.zAxis.v = filteredVel.Z
        end
        kalmanState.confidence = math_max(0, kalmanState.confidence * 0.82)
        kalmanConfidence = kalmanState.confidence
    end

    -- ═══ 10. CONFIDENCE SCALING ═══
    local finalConfidence = 1
    if targetPlayer then
        local buf = VelocityBuffers[targetPlayer]
        if buf then
            finalConfidence = finalConfidence * math_clamp(buf.confidence, 0, 1)
        end
        finalConfidence = finalConfidence * math_clamp(kalmanConfidence, 0, 1)
    end

    local confidenceFloor = math_clamp(Settings.PredictionConfidenceFloor or 0.12, 0, 0.9)
    finalConfidence = math_clamp(finalConfidence, confidenceFloor, 1)
    predictedPos = measuredPos + (predictedPos - measuredPos) * finalConfidence

    if targetPlayer then
        PredictionFrameCache[targetPlayer] = {
            tick = frameTick,
            part = targetPart,
            pos = predictedPos
        }
    end

    return predictedPos
end

CheatEnv.TriggerAutoShotClick = function()
    if mouse1click then
        pcall(mouse1click)
        return
    end

    if mouse1press and mouse1release then
        pcall(mouse1press)
        task.delay(0.015, function()
            pcall(mouse1release)
        end)
        return
    end

    local ok, virtualInput = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if not ok or not virtualInput then
        return
    end

    local mousePos = UserInputService:GetMouseLocation()
    pcall(function()
        virtualInput:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 0)
        virtualInput:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 0)
    end)
end

CheatEnv.UpdateAutoShot = function()
    local state = CheatEnv.AutoShotState
    if not state then return end

    if not Settings.AutoShot then
        state.CurrentTarget = nil
        CheatEnv.AutoShotNextShot = 0
        return
    end

    if not Camera or (MainFrame and MainFrame.Visible) then
        state.CurrentTarget = nil
        return
    end

    if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        return
    end

    local now = tick()
    local updateFps = math_max(1, Settings.AimbotUpdateFPS or 30)
    local minInterval = 1 / updateFps
    if (now - (state.LastUpdate or 0)) < minInterval then
        return
    end
    state.LastUpdate = now

    local origin = GetScreenPosition(Settings.AimbotMode or "Old")
    local targetPart = GetClosestTarget(Settings.AimbotFOV or 100, Settings.AimbotPart or "Head", origin, state)
    state.CurrentTarget = targetPart
    if not targetPart then
        return
    end

    local delaySec = math_clamp(Settings.AutoShotDelay or 110, 10, 500) / 1000
    if now < (CheatEnv.AutoShotNextShot or 0) then
        return
    end

    CheatEnv.AutoShotNextShot = now + delaySec
    if CheatEnv.TriggerAutoShotClick then
        CheatEnv.TriggerAutoShotClick()
    end
end

local function UpdateAimbot()
    if not Camera then return end

    if not IsAimbotActive() then
        FOVRing.Visible = false
        AimbotState.CurrentTarget = nil
        PredConst.ResetHumanizerState(AimbotState)
        UpdateTargetIndicator(Vector2.new(0, 0), false)
        return
    end

    local now = tick()
    local updateFps = math_max(1, Settings.AimbotUpdateFPS or 30)
    local minInterval = 1 / updateFps
    if (now - AimbotState.LastUpdate) < minInterval then
        return
    end
    AimbotState.LastUpdate = now

    local currentAimbotMode = Settings.AimbotMode or "Old"
    local Origin = GetScreenPosition(currentAimbotMode)

    FOVRing.Color = Settings.FOVColor or Theme.Accent
    FOVRing.Position = Origin
    if Settings.OvalFOV then
        local aspectRatio = Camera.ViewportSize.X / Camera.ViewportSize.Y
        FOVRing.Radius = math_max(1, (Settings.AimbotFOV or 100) * aspectRatio)
    else
        FOVRing.Radius = math_max(1, Settings.AimbotFOV or 100)
    end
    FOVRing.Visible = Settings.ShowFOV and Settings.Aimbot

    local TargetPart = GetClosestTarget(Settings.AimbotFOV, Settings.AimbotPart or "Head", Origin, AimbotState)
    if not TargetPart then
        AimbotState.CurrentTarget = nil
        PredConst.ResetHumanizerState(AimbotState)
        UpdateTargetIndicator(Vector2.new(0, 0), false)
        return
    end

    if Settings.ReactionTime > 0 and (now - AimbotState.StickyStartTime) < Settings.ReactionTime then
        return
    end

    local targetPlayer = nil
    if TargetPart.Parent then
        targetPlayer = ResolvePlayerFromCharacterModel(TargetPart.Parent)
    end

    local GoalPosition = GetPredictedPos(TargetPart, targetPlayer)
    local ScreenPos, OnScreen = Camera:WorldToViewportPoint(GoalPosition)
    if not OnScreen then
        UpdateTargetIndicator(Vector2.new(0, 0), false)
        return
    end

    local dist3d = (TargetPart.Position - Camera.CFrame.Position).Magnitude
    local targetVelocity = GetPartVelocity(TargetPart)
    local velocityMag = targetVelocity.Magnitude
    local smoothMode = Settings.AimbotSmoothMode or "Old"
    local baseDeadzone = Settings.Deadzone or 0
    local effectiveDeadzone = GetDynamicDeadzone(baseDeadzone, velocityMag, dist3d)
    local targetScreenPoint = v2_new(ScreenPos.X, ScreenPos.Y)
    local aimPoint = targetScreenPoint
    local humanizeSmoothScale, humanizeStepScale = 1, 1

    if Settings.Humanize then
        aimPoint, humanizeSmoothScale, humanizeStepScale = PredConst.GetHumanizedScreenPoint(
            AimbotState,
            TargetPart,
            Origin,
            targetScreenPoint,
            GoalPosition,
            targetVelocity,
            now,
            Settings.HumanizePower,
            dist3d
        )
    else
        PredConst.ResetHumanizerState(AimbotState)
    end

    UpdateTargetIndicator(targetScreenPoint, true)

    if currentAimbotMode == "Mousemoverel" then
        local mousePos = UserInputService:GetMouseLocation()
        local delta = aimPoint - mousePos
        local dist = delta.Magnitude

        if dist <= effectiveDeadzone then
            return
        end

        local smooth, normalized = BuildSmoothFactor(
            Settings.AimbotSmooth,
            dist,
            effectiveDeadzone,
            dist3d,
            Settings.AdaptiveSmoothing,
            smoothMode,
            Settings.FlickBot,
            Settings.FlickSpeed
        )
        smooth = math_clamp(smooth * humanizeSmoothScale, 0.01, 1)

        local move = delta * smooth

        if dist < 5 and not Settings.Humanize then
            move = move + v2_new(math_random(-1, 1) / 10, math_random(-1, 1) / 10)
        end

        local maxStep = 900 * (0.55 + normalized * 0.65) * humanizeStepScale
        if move.Magnitude > maxStep then
            move = move.Unit * maxStep
        end

        if mousemoverel then
            mousemoverel(move.X, move.Y)
        end
    else
        local DistToCenter = (aimPoint - Origin).Magnitude

        if DistToCenter > effectiveDeadzone then
            local finalSmooth = BuildSmoothFactor(
                Settings.AimbotSmooth,
                DistToCenter,
                effectiveDeadzone,
                dist3d,
                Settings.AdaptiveSmoothing,
                smoothMode,
                Settings.FlickBot,
                Settings.FlickSpeed
            )

            if Settings.Humanize then
                finalSmooth = finalSmooth * humanizeSmoothScale
            end
            finalSmooth = math_clamp(finalSmooth, 0.01, 1)

            local aimRay = Camera:ViewportPointToRay(aimPoint.X, aimPoint.Y, 0)
            local lookTarget = Camera.CFrame.Position + (aimRay.Direction * dist3d)
            Camera.CFrame = Camera.CFrame:Lerp(
                CFrame.new(Camera.CFrame.Position, lookTarget),
                finalSmooth
            )
        end
    end
end

local CurrentAimlockTarget = nil
local LastTargetTime = 0
local TARGET_LOCK_TIME = 0.15 -- 150 мс

local function IsAimlockTargetValid(targetPart, state, currentTime)
    local function resetVisibility()
        if not targetPart then
            return
        end

        VisibilityCache[targetPart] = nil
        if state and state.VisibilityUntil then
            state.VisibilityUntil[targetPart] = nil
        end
    end

    if not targetPart or not targetPart.Parent then
        return false
    end
    if not targetPart:IsDescendantOf(Workspace) then
        return false
    end

    local character = targetPart.Parent
    local humanoid = character:FindFirstChild("Humanoid")
    if humanoid and humanoid.Health <= 0 then
        return false
    end

    local targetPlayer = ResolvePlayerFromCharacterModel(character)

    if Settings.KnockedCheck then
        if IsCharacterKnocked(targetPlayer, character, humanoid) then
            resetVisibility()
            return false
        end
    end

    if Settings.TC_NoAim and targetPlayer and IsTeammate(targetPlayer) then
        resetVisibility()
        return false
    end

    if Settings.WallCheck then
        local now = currentTime or tick()
        state = state or AimlockState
        state.VisibilityUntil = state.VisibilityUntil or setmetatable({}, { __mode = "k" })

        if IsVisible(targetPart, character) then
            state.VisibilityUntil[targetPart] = now + TARGET_OCCLUSION_GRACE
            VisibilityCache[targetPart] = {
                visible = true,
                time = now
            }
        else
            resetVisibility()
            return false
        end
    end

    return true
end

local function UpdateAimlock()
    if not Settings.Aimlock then
        AimlockRing.Visible = false
        CurrentAimlockTarget = nil
        AimlockState.CurrentTarget = nil
        PredConst.ResetHumanizerState(AimlockState)
        return
    end

    if not Camera then return end

    local now = tick()
    local updateFps = math_max(1, Settings.AimlockUpdateFPS or 30)
    local minInterval = 1 / updateFps
    if (now - AimlockState.LastUpdate) < minInterval then
        return
    end
    AimlockState.LastUpdate = now

    local currentAimlockMode = Settings.AimlockTargetMode or "Old"
    local forceStick = Settings.AimlockForceStick == true
    local origin = GetScreenPosition(currentAimlockMode)

    if not IsAimbotActive("Aimlock") then
        AimlockRing.Visible = false
        CurrentAimlockTarget = nil
        AimlockState.CurrentTarget = nil
        PredConst.ResetHumanizerState(AimlockState)
        return
    end

    AimlockRing.Position = origin
    AimlockRing.Radius = math_max(1, Settings.AimlockFOV or 90)
    AimlockRing.Visible = Settings.ShowAimlockFOV and Settings.Aimlock

    local targetPart = CurrentAimlockTarget
    if not IsAimlockTargetValid(targetPart, AimlockState, now) then
        targetPart = nil
        CurrentAimlockTarget = nil
    end

    local shouldRescan = not targetPart
    if not shouldRescan and not forceStick and (now - LastTargetTime > TARGET_LOCK_TIME) then
        shouldRescan = true
    end

    if shouldRescan then
        targetPart = GetClosestTarget(Settings.AimlockFOV, Settings.AimlockPart, origin, AimlockState)
        CurrentAimlockTarget = targetPart
        LastTargetTime = now
    end

    if not targetPart then
        PredConst.ResetHumanizerState(AimlockState)
        return
    end

    if Settings.ReactionTime > 0 and (now - AimlockState.StickyStartTime) < Settings.ReactionTime then
        return
    end

    local targetPlayer = nil
    if targetPart.Parent then
        targetPlayer = ResolvePlayerFromCharacterModel(targetPart.Parent)
    end

    local goalPosition = GetPredictedPos(targetPart, targetPlayer)
    local screenPos, onScreen = Camera:WorldToViewportPoint(goalPosition)
    if not onScreen then
        if forceStick then
            CurrentAimlockTarget = nil
        end
        return
    end

    local smoothMode = Settings.AimlockSmoothMode or "Old"
    local targetVelocity = GetPartVelocity(targetPart)
    local dist3d = (targetPart.Position - Camera.CFrame.Position).Magnitude
    local deadzone = GetDynamicDeadzone(Settings.Deadzone or 3, targetVelocity.Magnitude, dist3d)
    local targetScreenPoint = v2_new(screenPos.X, screenPos.Y)
    local aimPoint = targetScreenPoint
    local humanizeSmoothScale, humanizeStepScale = 1, 1

    if Settings.Humanize and not forceStick then
        aimPoint, humanizeSmoothScale, humanizeStepScale = PredConst.GetHumanizedScreenPoint(
            AimlockState,
            targetPart,
            origin,
            targetScreenPoint,
            goalPosition,
            targetVelocity,
            now,
            (Settings.HumanizePower or 1) * 0.85,
            dist3d
        )
    else
        PredConst.ResetHumanizerState(AimlockState)
    end

    if currentAimlockMode == "Mousemoverel" then
        local mousePos = UserInputService:GetMouseLocation()
        local delta = aimPoint - mousePos

        if forceStick then
            if delta.Magnitude > 1200 then
                delta = delta.Unit * 1200
            end
            if mousemoverel then
                mousemoverel(delta.X, delta.Y)
            end
            return
        end

        local distance = delta.Magnitude
        if distance <= deadzone then
            return
        end

        local smoothFactor, normalized = BuildSmoothFactor(
            Settings.AimlockSmooth,
            distance,
            deadzone,
            dist3d,
            Settings.AdaptiveSmoothing,
            smoothMode,
            false,
            nil
        )
        smoothFactor = math_clamp(smoothFactor * humanizeSmoothScale, 0.01, 1)

        if distance < 1 and delta.Magnitude > 0 then
            delta = delta.Unit * 1
        end

        if not Settings.Humanize then
            local humanization = v2_new(
                math_random(-15, 15) / 100,
                math_random(-15, 15) / 100
            )
            delta = delta + humanization
        end

        local move = delta * smoothFactor
        local maxStep = 780 * (0.6 + normalized * 0.5) * humanizeStepScale
        if move.Magnitude > maxStep then
            move = move.Unit * maxStep
        end

        if mousemoverel then
            mousemoverel(move.X, move.Y)
        end
    else
        local camCF = Camera.CFrame
        local camPos = camCF.Position
        local aimRay = Camera:ViewportPointToRay(aimPoint.X, aimPoint.Y, 0)
        local lookTarget = camPos + (aimRay.Direction * dist3d)
        local lookCF = CFrame.new(camPos, lookTarget)

        if forceStick then
            Camera.CFrame = lookCF
            return
        end

        local dist = (aimPoint - origin).Magnitude
        if dist > deadzone then
            local smooth = BuildSmoothFactor(
                Settings.AimlockSmooth,
                dist,
                deadzone,
                dist3d,
                Settings.AdaptiveSmoothing,
                smoothMode,
                false,
                nil
            )
            smooth = math_clamp(smooth * humanizeSmoothScale, 0.01, 1)
            Camera.CFrame = camCF:Lerp(lookCF, smooth)
        end
    end
end

local ESP_Storage = {}

-- [START] MM2 LOGIC VARIABLES & FUNCTIONS

MM2_Data.IsMM2 = (game.PlaceId == MM2_Data.PLACE_ID)
MM2_Data.Roles = MM2_Data.Roles or {}
MM2_Data.GunDrops = MM2_Data.GunDrops or {}

-- Функция определения роли (из mm2.lua)
local function GetMM2Role(player)
    if not player or not player.Character then return "Player" end

    local char = player.Character
    local backpack = player:FindFirstChild("Backpack")

    -- Проверка ножа
    local function checkMurd(container)
        if not container then return false end
        local knife = container:FindFirstChild("Knife") or container:FindFirstChild("Slash")
        if knife then return true end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and tool:FindFirstChild("MakeFlyingHandle") then return true end
        end
        return false
    end

    -- Проверка пистолета
    local function checkGun(container)
        if not container then return false end
        if container:FindFirstChild("Gun") or container:FindFirstChild("Revolver") then return true end
        for _, tool in ipairs(container:GetChildren()) do
            if tool:IsA("Tool") and tool:FindFirstChild("IsGun") then return true end
        end
        return false
    end

    if checkMurd(char) or checkMurd(backpack) then return "Murder" end
    if checkGun(char) or checkGun(backpack) then
        return (player == MM2_Data.Hero) and "Hero" or "Sheriff"
    end

    return "Player" -- Обычный Innocent
end

-- Фоновые задачи для MM2 (запускаются только если мы в MM2)
if MM2_Data.IsMM2 then
    -- Обновление ролей раз в 0.5 сек
    task.spawn(function()
        while _G.CheatLoaded do
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer then
                    MM2_Data.Roles[player] = GetMM2Role(player)
                end
            end
            task.wait(0.5)
        end
    end)

    -- Поиск выпавшего пистолета раз в 2 сек
    task.spawn(function()
        while _G.CheatLoaded do
            local drops = {}
            for _, obj in ipairs(Workspace:GetChildren()) do
                if obj.Name == "GunDrop" or (obj:IsA("Tool") and obj:FindFirstChild("IsGun")) then
                    table.insert(drops, obj)
                end
            end
            MM2_Data.GunDrops = drops
            task.wait(1.5)
        end
    end)
end

-- Для отрисовки GunDrop нам понадобится отдельное хранилище Drawing
local DropDrawings = {}

local function UpdateGunDropESP()
    -- ✅ РАННИЙ ВЫХОД если ESP выключен или это не MM2
    if not MM2_Data.IsMM2 or not Settings.ESP then
        for _, d in pairs(DropDrawings) do
            d.Box.Visible = false
            d.Text.Visible = false
        end
        return
    end

    -- ✅ Проверка конкретной настройки GunDrop
    if not Settings.MM2_ESP_GunDrop then
        for _, d in pairs(DropDrawings) do
            d.Box.Visible = false
            d.Text.Visible = false
        end
        return
    end

    -- Очистка старых
    for obj, drawing in pairs(DropDrawings) do
        if not table.find(MM2_Data.GunDrops, obj) or not obj.Parent then
            pcall(function()
                drawing.Box:Remove()
                drawing.Text:Remove()
            end)
            DropDrawings[obj] = nil
        end
    end

    -- Отрисовка новых
    for _, gun in ipairs(MM2_Data.GunDrops) do
        if not gun or not gun.Parent then continue end

        if not DropDrawings[gun] then
            local Box = Drawing.new("Square")
            Box.Thickness = 1.5
            Box.Color = MM2_Colors.GunDrop
            Box.Filled = false

            local Text = Drawing.new("Text")
            Text.Size = 11
            Text.Font = 2
            Text.Center = true
            Text.Outline = true
            Text.OutlineColor = Color3.new(0, 0, 0)
            Text.Color = MM2_Colors.GunDrop
            Text.Text = "GUN DROP"

            table.insert(CheatEnv.Drawings, Box)
            table.insert(CheatEnv.Drawings, Text)
            DropDrawings[gun] = { Box = Box, Text = Text }
        end

        local d = DropDrawings[gun]

        -- ✅ ЗАЩИТА: pcall для GetPivot (может быть nil)
        local success, p = pcall(function()
            return gun:IsA("Model") and gun:GetPivot().Position or gun.Position
        end)

        if not success or not p then continue end

        local pos, onScreen = Camera:WorldToViewportPoint(p)

        if onScreen then
            d.Box.Size = Vector2.new(15, 15)
            d.Box.Position = Vector2.new(pos.X - 7, pos.Y - 7)
            d.Box.Visible = true

            d.Text.Position = Vector2.new(pos.X, pos.Y - 20)
            d.Text.Visible = true
        else
            d.Box.Visible = false
            d.Text.Visible = false
        end
    end
end
-- [END] MM2 LOGIC


--// SCP:RP TEAM CHECK HELPERS (Moved Up) //--

local function GetSCPRP_Mode(player)
    if not player or not player.Team then return nil end

    local teamName = player.Team.Name

    if SCPRP_Teams.MainDepartments[teamName] then
        return "MAIN"
    end

    if SCPRP_Teams.ThreatDepartments[teamName] then
        return "THREAT"
    end

    return nil
end

local function SCPRP_AdvancedTeamCheck(targetPlayer)
    if not Settings.AdvancedTeamCheck then
        return true -- обычный ESP
    end

    if not LocalPlayer.Team or not targetPlayer.Team then
        return false
    end

    local myMode = GetSCPRP_Mode(LocalPlayer)
    local targetTeam = targetPlayer.Team.Name

    -- РЕЖИМ 1: Основные отделы
    if myMode == "MAIN" then
        -- Видим ВСЕХ, кроме Class-D и Chaos
        if SCPRP_Teams.ThreatDepartments[targetTeam] then
            return false
        end
        return true
    end

    -- РЕЖИМ 2: Class-D / Chaos
    if myMode == "THREAT" then
        -- Видим ТОЛЬКО Class-D и Chaos
        return SCPRP_Teams.ThreatDepartments[targetTeam] == true
    end

    return false
end

local function GetSCPRP_ESPColor(targetPlayer)
    if not Settings.AdvancedTeamCheck then
        return Settings.BoxColor
    end

    local myMode = GetSCPRP_Mode(LocalPlayer)
    local teamName = targetPlayer.Team and targetPlayer.Team.Name

    if myMode == "MAIN" then
        return Color3.fromRGB(0, 255, 0)
    end

    if myMode == "THREAT" and SCPRP_Teams.ThreatDepartments[teamName] then
        return Color3.fromRGB(255, 60, 60)
    end

    return Settings.BoxColor
end



-- [OPTIMIZED] Helper to hide all ESP elements for a player
local function HideAllESP(data)
    if not data then return end
    data.BoxOutline.Visible = false
    data.Box.Visible = false
    data.BoxFill.Visible = false
    data.Tag.Visible = false
    data.DistanceTag.Visible = false
    data.WeaponTag.Visible = false
    data.HealthBarOutline.Visible = false
    data.HealthBar.Visible = false
    data.HealthText.Visible = false
    if data.TopBar then data.TopBar.Visible = false end
    if data.Tracer then data.Tracer.Visible = false end
    if data.Skeleton then
        for _, l in ipairs(data.Skeleton) do l.Visible = false end
    end
    -- Corner box lines + outlines
    if data.CornerLines then
        for _, l in ipairs(data.CornerLines) do l.Visible = false end
    end
    if data.CornerOutlines then
        for _, l in ipairs(data.CornerOutlines) do l.Visible = false end
    end
    if data.Chams then
        data.Chams.Enabled = false
    end
end

local function CreateESP(player)
    if ESP_Storage[player] then return end

    -- Box shadow (thin black outline for depth)
    local BoxOutline = Drawing.new("Square")
    BoxOutline.Visible = false
    BoxOutline.Color = Color3.new(0, 0, 0)
    BoxOutline.Thickness = 1.5
    BoxOutline.Filled = false

    -- Main box (crisp 1px line)
    local Box = Drawing.new("Square")
    Box.Visible = false
    Box.Color = Settings.BoxColor
    Box.Thickness = 1
    Box.Filled = false

    -- Box fill
    local BoxFill = Drawing.new("Square")
    BoxFill.Visible = false
    BoxFill.Color = Settings.BoxColor
    BoxFill.Transparency = Settings.ESP_BoxFillTransparency
    BoxFill.Thickness = 1
    BoxFill.Filled = true

    -- Accent TopBar line above box
    local TopBar = Drawing.new("Line")
    TopBar.Visible = false
    TopBar.Color = Settings.BoxColor
    TopBar.Thickness = 2

    -- Corner Box Lines (8 lines for corners)
    local CornerLines = {}
    for i = 1, 8 do
        local line = Drawing.new("Line")
        line.Visible = false
        line.Color = Settings.BoxColor
        line.Thickness = 1.5
        table.insert(CornerLines, line)
    end

    -- Corner Shadow Outlines (8 black lines behind corners for depth)
    local CornerOutlines = {}
    for i = 1, 8 do
        local line = Drawing.new("Line")
        line.Visible = false
        line.Color = Color3.new(0, 0, 0)
        line.Thickness = 3
        table.insert(CornerOutlines, line)
    end

    -- Tracer Line (thin)
    local Tracer = Drawing.new("Line")
    Tracer.Visible = false
    Tracer.Color = Settings.BoxColor
    Tracer.Thickness = 1

    -- Health bar background (dark fill)
    local HealthBarOutline = Drawing.new("Square")
    HealthBarOutline.Visible = false
    HealthBarOutline.Color = Color3.fromRGB(10, 10, 10)
    HealthBarOutline.Thickness = 1
    HealthBarOutline.Filled = true

    -- Health bar fill
    local HealthBar = Drawing.new("Square")
    HealthBar.Visible = false
    HealthBar.Color = Color3.new(0, 1, 0)
    HealthBar.Thickness = 1
    HealthBar.Filled = true

    -- Health text (pixel, small)
    local HealthText = Drawing.new("Text")
    HealthText.Visible = false
    HealthText.Text = ""
    HealthText.Size = 10
    HealthText.Center = true
    HealthText.Outline = true
    HealthText.OutlineColor = Color3.new(0, 0, 0)
    HealthText.Color = Color3.new(1, 1, 1)
    HealthText.Font = 2

    -- Name tag (pixel)
    local NameTag = Drawing.new("Text")
    NameTag.Font = 2
    NameTag.Visible = false
    NameTag.Text = player.DisplayName or player.Name
    NameTag.Size = 13
    NameTag.Center = true
    NameTag.Outline = true
    NameTag.OutlineColor = Color3.new(0, 0, 0)
    NameTag.Color = Settings.NameColor

    -- Distance tag (pixel)
    local DistanceTag = Drawing.new("Text")
    DistanceTag.Font = 2
    DistanceTag.Visible = false
    DistanceTag.Text = ""
    DistanceTag.Size = 10
    DistanceTag.Center = true
    DistanceTag.Outline = true
    DistanceTag.OutlineColor = Color3.new(0, 0, 0)
    DistanceTag.Color = Settings.DistanceColor

    -- Weapon tag (pixel)
    local WeaponTag = Drawing.new("Text")
    WeaponTag.Font = 2
    WeaponTag.Visible = false
    WeaponTag.Text = ""
    WeaponTag.Size = 10
    WeaponTag.Center = true
    WeaponTag.Outline = true
    WeaponTag.OutlineColor = Color3.new(0, 0, 0)
    WeaponTag.Color = Settings.WeaponColor

    -- Skeleton (thin elegant lines)
    local Skeleton = {}
    for i = 1, 14 do
        local Line = Drawing.new("Line")
        Line.Visible = false
        Line.Color = Settings.BoxColor
        Line.Thickness = 1
        table.insert(Skeleton, Line)
    end

    ESP_Storage[player] = {
        BoxOutline = BoxOutline,
        Box = Box,
        BoxFill = BoxFill,
        TopBar = TopBar,
        Chams = nil,
        CornerLines = CornerLines,
        CornerOutlines = CornerOutlines,
        Tracer = Tracer,
        Tag = NameTag,
        DistanceTag = DistanceTag,
        WeaponTag = WeaponTag,
        Skeleton = Skeleton,
        HealthBarOutline = HealthBarOutline,
        HealthBar = HealthBar,
        HealthText = HealthText,
        Player = player,
        LastUpdate = 0
    }

    table.insert(CheatEnv.Drawings, BoxOutline)
    table.insert(CheatEnv.Drawings, Box)
    table.insert(CheatEnv.Drawings, BoxFill)
    table.insert(CheatEnv.Drawings, TopBar)
    table.insert(CheatEnv.Drawings, Tracer)
    table.insert(CheatEnv.Drawings, HealthBarOutline)
    table.insert(CheatEnv.Drawings, HealthBar)
    table.insert(CheatEnv.Drawings, HealthText)
    table.insert(CheatEnv.Drawings, NameTag)
    table.insert(CheatEnv.Drawings, DistanceTag)
    table.insert(CheatEnv.Drawings, WeaponTag)
    for _, line in ipairs(Skeleton) do table.insert(CheatEnv.Drawings, line) end
    for _, line in ipairs(CornerLines) do table.insert(CheatEnv.Drawings, line) end
    for _, line in ipairs(CornerOutlines) do table.insert(CheatEnv.Drawings, line) end
end

local function RemoveESP(player)
    if ESP_Storage[player] then
        pcall(function()
            local d = ESP_Storage[player]
            if d.BoxOutline then d.BoxOutline:Remove() end
            if d.Box then d.Box:Remove() end
            if d.BoxFill then d.BoxFill:Remove() end
            if d.TopBar then d.TopBar:Remove() end
            if d.Chams then d.Chams:Destroy() end
            if d.Tracer then d.Tracer:Remove() end
            if d.Tag then d.Tag:Remove() end
            if d.DistanceTag then d.DistanceTag:Remove() end
            if d.WeaponTag then d.WeaponTag:Remove() end
            if d.HealthBarOutline then d.HealthBarOutline:Remove() end
            if d.HealthBar then d.HealthBar:Remove() end
            if d.HealthText then d.HealthText:Remove() end
            if d.Skeleton then for _, l in ipairs(d.Skeleton) do l:Remove() end end
            if d.CornerLines then for _, l in ipairs(d.CornerLines) do l:Remove() end end
            if d.CornerOutlines then for _, l in ipairs(d.CornerOutlines) do l:Remove() end end

            -- Clean up references from CheatEnv.Drawings to prevent memory leak
            local function removeFromDrawings(obj)
                for i = #CheatEnv.Drawings, 1, -1 do
                    if CheatEnv.Drawings[i] == obj then
                        table.remove(CheatEnv.Drawings, i)
                        break
                    end
                end
            end
            removeFromDrawings(d.BoxOutline)
            removeFromDrawings(d.Box)
            removeFromDrawings(d.BoxFill)
            removeFromDrawings(d.TopBar)
            removeFromDrawings(d.Tracer)
            removeFromDrawings(d.HealthBarOutline)
            removeFromDrawings(d.HealthBar)
            removeFromDrawings(d.HealthText)
            removeFromDrawings(d.Tag)
            removeFromDrawings(d.DistanceTag)
            removeFromDrawings(d.WeaponTag)
            if d.Skeleton then for _, l in ipairs(d.Skeleton) do removeFromDrawings(l) end end
            if d.CornerLines then for _, l in ipairs(d.CornerLines) do removeFromDrawings(l) end end
            if d.CornerOutlines then for _, l in ipairs(d.CornerOutlines) do removeFromDrawings(l) end end
        end)
        ESP_Storage[player] = nil
    end
end

local function UpdatePlayerChams(player, data, color, shouldEnable)
    if not data then return end

    if not shouldEnable then
        if data.Chams then
            data.Chams.Enabled = false
        end
        return
    end

    local char = ResolveCharacterModel(player)
    if not player or not char then
        if data.Chams then
            data.Chams.Enabled = false
        end
        return
    end

    if not data.Chams or data.Chams.Adornee ~= char or not data.Chams.Parent then
        if data.Chams then
            pcall(function() data.Chams:Destroy() end)
        end

        local highlight = Instance.new("Highlight")
        highlight.Name = "VAYS_ESP_Chams"
        highlight.Adornee = char
        highlight.Parent = Workspace
        highlight.FillTransparency = 0.45
        highlight.OutlineTransparency = 0.2
        highlight.Enabled = true
        data.Chams = highlight
        table.insert(CheatEnv.UI, highlight)
    end

    data.Chams.Adornee = char
    data.Chams.FillColor = color
    data.Chams.OutlineColor = Color3.new(0, 0, 0)
    data.Chams.DepthMode = Settings.ESP_ChamsVisibleOnly and Enum.HighlightDepthMode.Occluded or
        Enum.HighlightDepthMode.AlwaysOnTop
    data.Chams.Enabled = true
end

-- [NEW] Helper to draw a line between two points
local function DrawLine(line, p1, p2, color)
    local v1, onScreen1 = Camera:WorldToViewportPoint(p1)
    local v2, onScreen2 = Camera:WorldToViewportPoint(p2)

    if onScreen1 and onScreen2 then
        line.From = Vector2.new(v1.X, v1.Y)
        line.To = Vector2.new(v2.X, v2.Y)
        line.Color = color
        line.Visible = true
    else
        line.Visible = false
    end
end

local function UpdateSkeleton(player, storage, color)
    local char = ResolveCharacterModel(player)
    if not char then return end

    -- Hide all lines first
    for _, line in ipairs(storage.Skeleton) do line.Visible = false end

    if not Settings.ESP_Skeleton then return end

    -- R15 Logic
    if char:FindFirstChild("UpperTorso") then
        local Head = char:FindFirstChild("Head")
        local UpperTorso = char:FindFirstChild("UpperTorso")
        local LowerTorso = char:FindFirstChild("LowerTorso")

        -- Arms
        local L_UpperArm = char:FindFirstChild("LeftUpperArm")
        local L_LowerArm = char:FindFirstChild("LeftLowerArm")
        local L_Hand = char:FindFirstChild("LeftHand")
        local R_UpperArm = char:FindFirstChild("RightUpperArm")
        local R_LowerArm = char:FindFirstChild("RightLowerArm")
        local R_Hand = char:FindFirstChild("RightHand")

        -- Legs
        local L_UpperLeg = char:FindFirstChild("LeftUpperLeg")
        local L_LowerLeg = char:FindFirstChild("LeftLowerLeg")
        local L_Foot = char:FindFirstChild("LeftFoot")
        local R_UpperLeg = char:FindFirstChild("RightUpperLeg")
        local R_LowerLeg = char:FindFirstChild("RightLowerLeg")
        local R_Foot = char:FindFirstChild("RightFoot")

        local idx = 1
        local function Link(p1, p2)
            if p1 and p2 and storage.Skeleton[idx] then
                DrawLine(storage.Skeleton[idx], p1.Position, p2.Position, color)
                idx = idx + 1
            end
        end

        Link(Head, UpperTorso)
        Link(UpperTorso, LowerTorso)

        Link(UpperTorso, L_UpperArm)
        Link(L_UpperArm, L_LowerArm)
        Link(L_LowerArm, L_Hand)

        Link(UpperTorso, R_UpperArm)
        Link(R_UpperArm, R_LowerArm)
        Link(R_LowerArm, R_Hand)

        Link(LowerTorso, L_UpperLeg)
        Link(L_UpperLeg, L_LowerLeg)
        Link(L_LowerLeg, L_Foot)

        Link(LowerTorso, R_UpperLeg)
        Link(R_UpperLeg, R_LowerLeg)
        Link(R_LowerLeg, R_Foot)

        -- R6 Logic
    elseif char:FindFirstChild("Torso") then
        local Head = char:FindFirstChild("Head")
        local Torso = char:FindFirstChild("Torso")
        local L_Arm = char:FindFirstChild("Left Arm")
        local R_Arm = char:FindFirstChild("Right Arm")
        local L_Leg = char:FindFirstChild("Left Leg")
        local R_Leg = char:FindFirstChild("Right Leg")

        local idx = 1
        local function Link(p1, p2)
            if p1 and p2 and storage.Skeleton[idx] then
                DrawLine(storage.Skeleton[idx], p1.Position, p2.Position, color)
                idx = idx + 1
            end
        end

        Link(Head, Torso)
        Link(Torso, L_Arm)
        Link(Torso, R_Arm)
        Link(Torso, L_Leg)
        Link(Torso, R_Leg)
    end
end


-- [REDESIGNED] Helper to draw corner box with shadow outlines
local function DrawCornerBox(data, x, y, w, h, color)
    local cornerSize = math.min(w, h) * 0.22 -- 22% for tighter corners
    local lines = data.CornerLines
    local outlines = data.CornerOutlines
    if not lines or #lines < 8 then return end

    -- Corner positions for both color and shadow lines
    local corners = {
        -- Top-Left
        { Vector2.new(x, y), Vector2.new(x + cornerSize, y) },
        { Vector2.new(x, y), Vector2.new(x, y + cornerSize) },
        -- Top-Right
        { Vector2.new(x + w, y), Vector2.new(x + w - cornerSize, y) },
        { Vector2.new(x + w, y), Vector2.new(x + w, y + cornerSize) },
        -- Bottom-Left
        { Vector2.new(x, y + h), Vector2.new(x + cornerSize, y + h) },
        { Vector2.new(x, y + h), Vector2.new(x, y + h - cornerSize) },
        -- Bottom-Right
        { Vector2.new(x + w, y + h), Vector2.new(x + w - cornerSize, y + h) },
        { Vector2.new(x + w, y + h), Vector2.new(x + w, y + h - cornerSize) },
    }

    for i = 1, 8 do
        -- Shadow outline (black, drawn first = behind)
        if outlines and outlines[i] then
            outlines[i].From = corners[i][1]
            outlines[i].To = corners[i][2]
            outlines[i].Color = Color3.new(0, 0, 0)
            outlines[i].Visible = true
        end
        -- Main color line (drawn on top)
        lines[i].From = corners[i][1]
        lines[i].To = corners[i][2]
        lines[i].Color = color
        lines[i].Visible = true
    end
end

local ESPWasEnabled = false

local function UpdateESP()
    if not Camera then
        for _, data in pairs(ESP_Storage) do
            HideAllESP(data)
        end
        for _, d in pairs(DropDrawings) do
            d.Box.Visible = false
            d.Text.Visible = false
        end
        return
    end

    -- 1. Обновляем ESP оружия (только для MM2)
    if MM2_Data.IsMM2 then
        UpdateGunDropESP()
    end

    if not Settings.ESP then
        if ESPWasEnabled then
            for _, data in pairs(ESP_Storage) do
                HideAllESP(data)
            end
        end
        ESPWasEnabled = false
        return
    end
    ESPWasEnabled = true

    -- [OPTIMIZATION] Cache camera values
    local camPos = Camera.CFrame.Position
    local viewportSize = Camera.ViewportSize
    local screenBottom = Vector2.new(viewportSize.X / 2, viewportSize.Y)

    -- 2. Обновляем ESP игроков
    for player, data in pairs(ESP_Storage) do
        local plr = data.Player
        local char = ResolveCharacterModel(plr)
        if not plr or not char then
            HideAllESP(data)
            continue
        end

        if game.PlaceId == 5041144419 and Settings.AdvancedTeamCheck then
            if not SCPRP_AdvancedTeamCheck(plr) then
                HideAllESP(data)
                continue
            end
        end
        local isTeam = IsTeammate(plr)
        if isTeam and Settings.TC_Hide then
            HideAllESP(data)
            continue
        end

        -- MM2 Логика
        local mm2_Role = "Player"
        local mm2_Color = Settings.BoxColor
        local shouldDraw = true

        if MM2_Data.IsMM2 then
            mm2_Role = MM2_Data.Roles[plr] or "Player"
            if mm2_Role == "Murder" then
                shouldDraw = Settings.MM2_ESP_Murder
                mm2_Color = MM2_Colors.Murder
            elseif mm2_Role == "Sheriff" then
                shouldDraw = Settings.MM2_ESP_Sheriff
                mm2_Color = MM2_Colors.Sheriff
            elseif mm2_Role == "Hero" then
                shouldDraw = Settings.MM2_ESP_Hero
                mm2_Color = MM2_Colors.Hero
            else -- Player
                shouldDraw = Settings.MM2_ESP_Player
                mm2_Color = MM2_Colors.Player
            end
        else
            -- Не MM2 - используем стандартную логику
            if isTeam and Settings.TC_Green then
                mm2_Color = Theme.Green
            end

            -- [NEW] SCP:RP Color Logic
            if game.PlaceId == 5041144419 then
                mm2_Color = GetSCPRP_ESPColor(plr)
            end
        end

        -- Отрисовка
        local root = ResolveCharacterRoot(char)
        if not root then
            root = char:FindFirstChild("Head") or char:FindFirstChildWhichIsA("BasePart")
        end
        local humanoid = char:FindFirstChild("Humanoid")
        local aliveOk = ((not humanoid) or humanoid.Health > 0)
        if shouldDraw and root and aliveOk then
            local anchorPart = root
            local hrpPos = anchorPart.Position

            -- [OPTIMIZATION] Distance culling
            local distance = (hrpPos - camPos).Magnitude
            if distance > Settings.ESP_MaxDistance then
                HideAllESP(data)
                continue
            end

            local Pos, OnScreen = Camera:WorldToViewportPoint(hrpPos)
            if OnScreen then
                local Size = (Camera:WorldToViewportPoint(hrpPos - Vector3.new(0, 3, 0)).Y - Camera:WorldToViewportPoint(hrpPos + Vector3.new(0, 2.6, 0)).Y) /
                    2
                local bWidth, bHeight = (Size * 1.5), (Size * 2)
                local bPosX, bPosY = (Pos.X - bWidth / 2), (Pos.Y - bHeight / 2)

                UpdatePlayerChams(plr, data, mm2_Color, Settings.ESP_Chams)

                -- ═══════════════════════════════════
                -- BOX RENDERING (Standard or Corner)
                -- ═══════════════════════════════════
                if Settings.ESP_Box then
                    if Settings.ESP_CornerBox then
                        -- Corner Box with shadow outlines
                        data.Box.Visible = false
                        data.BoxOutline.Visible = false
                        DrawCornerBox(data, bPosX, bPosY, bWidth, bHeight, mm2_Color)
                    else
                        -- Hide corner elements
                        if data.CornerLines then
                            for _, l in ipairs(data.CornerLines) do l.Visible = false end
                        end
                        if data.CornerOutlines then
                            for _, l in ipairs(data.CornerOutlines) do l.Visible = false end
                        end
                        -- Shadow outline (1px bigger on each side)
                        data.BoxOutline.Size = Vector2.new(bWidth + 2, bHeight + 2)
                        data.BoxOutline.Position = Vector2.new(bPosX - 1, bPosY - 1)
                        data.BoxOutline.Visible = true

                        -- Main crisp box
                        data.Box.Size = Vector2.new(bWidth, bHeight)
                        data.Box.Position = Vector2.new(bPosX, bPosY)
                        data.Box.Color = mm2_Color
                        data.Box.Visible = true
                    end
                else
                    data.Box.Visible = false
                    data.BoxOutline.Visible = false
                    if data.CornerLines then
                        for _, l in ipairs(data.CornerLines) do l.Visible = false end
                    end
                    if data.CornerOutlines then
                        for _, l in ipairs(data.CornerOutlines) do l.Visible = false end
                    end
                end

                -- ═══════════════════════════════════
                -- BOX FILL
                -- ═══════════════════════════════════
                if Settings.ESP_Box and Settings.ESP_BoxFill then
                    data.BoxFill.Size = Vector2.new(bWidth - 2, bHeight - 2)
                    data.BoxFill.Position = Vector2.new(bPosX + 1, bPosY + 1)
                    data.BoxFill.Color = mm2_Color
                    data.BoxFill.Transparency = Settings.ESP_BoxFillTransparency
                    data.BoxFill.Visible = true
                else
                    data.BoxFill.Visible = false
                end

                -- ═══════════════════════════════════
                -- ACCENT TOP BAR (colored line above box)
                -- ═══════════════════════════════════
                if Settings.ESP_Box and data.TopBar then
                    data.TopBar.From = Vector2.new(bPosX, bPosY - 3)
                    data.TopBar.To = Vector2.new(bPosX + bWidth, bPosY - 3)
                    data.TopBar.Color = mm2_Color
                    data.TopBar.Visible = true
                elseif data.TopBar then
                    data.TopBar.Visible = false
                end

                -- ═══════════════════════════════════
                -- TRACER (thin line from screen bottom)
                -- ═══════════════════════════════════
                if Settings.ESP_Tracers and data.Tracer then
                    data.Tracer.From = screenBottom
                    data.Tracer.To = Vector2.new(Pos.X, bPosY + bHeight)
                    data.Tracer.Color = mm2_Color
                    data.Tracer.Visible = true
                elseif data.Tracer then
                    data.Tracer.Visible = false
                end

                -- ═══════════════════════════════════
                -- HEALTH BAR (slim left bar with gradient)
                -- ═══════════════════════════════════
                if Settings.ESP_HealthBar and humanoid then
                    local hp = humanoid.Health
                    local maxHp = humanoid.MaxHealth
                    if maxHp <= 0 then maxHp = 100 end
                    local hpPercent = math.clamp(hp / maxHp, 0, 1)

                    -- Smooth health gradient: Red → Yellow → Green
                    local hpColor = Color3.fromHSV(hpPercent * 0.33, 0.9, 1)

                    local barWidth = 2 -- Slim modern bar
                    local barX = bPosX - (barWidth + 4)

                    -- Dark background
                    data.HealthBarOutline.Size = Vector2.new(barWidth + 2, bHeight + 2)
                    data.HealthBarOutline.Position = Vector2.new(barX - 1, bPosY - 1)
                    data.HealthBarOutline.Color = Color3.fromRGB(10, 10, 10)
                    data.HealthBarOutline.Visible = true

                    -- Inner bar (fills bottom → up)
                    local fillHeight = math.max(bHeight * hpPercent, 1)
                    data.HealthBar.Size = Vector2.new(barWidth, fillHeight)
                    data.HealthBar.Position = Vector2.new(barX, bPosY + (bHeight - fillHeight))
                    data.HealthBar.Color = hpColor
                    data.HealthBar.Visible = true

                    -- Health text (above health bar)
                    if Settings.ESP_HealthText then
                        local hpNum = math.floor(hp)
                        data.HealthText.Text = tostring(hpNum)
                        data.HealthText.Position = Vector2.new(barX + (barWidth / 2), bPosY - 12)
                        data.HealthText.Color = hpColor
                        data.HealthText.Visible = true
                    else
                        data.HealthText.Visible = false
                    end
                else
                    data.HealthBarOutline.Visible = false
                    data.HealthBar.Visible = false
                    data.HealthText.Visible = false
                end

                -- ═══════════════════════════════════
                -- NAME TAG (above box / above topbar)
                -- ═══════════════════════════════════
                if Settings.ESP_Names then
                    data.Tag.Position = Vector2.new(Pos.X, bPosY - 18)
                    data.Tag.Color = mm2_Color
                    if MM2_Data.IsMM2 and mm2_Role ~= "Player" then
                        data.Tag.Text = "[" .. mm2_Role:upper() .. "] " .. plr.DisplayName
                    else
                        data.Tag.Text = plr.DisplayName
                    end
                    data.Tag.Visible = true
                else
                    data.Tag.Visible = false
                end

                -- ═══════════════════════════════════
                -- BOTTOM INFO (Weapon → Distance)
                -- ═══════════════════════════════════
                local bottomOffset = bPosY + bHeight + 2

                -- Weapon
                if Settings.ESP_Weapon then
                    local tool = char:FindFirstChildOfClass("Tool")
                    data.WeaponTag.Text = tool and tool.Name or "-"
                    data.WeaponTag.Position = Vector2.new(Pos.X, bottomOffset)
                    data.WeaponTag.Color = Settings.WeaponColor
                    data.WeaponTag.Visible = true
                    bottomOffset = bottomOffset + 11
                else
                    data.WeaponTag.Visible = false
                end

                -- Distance (clean format)
                if Settings.ESP_Distance then
                    data.DistanceTag.Text = math.floor(distance) .. "m"
                    data.DistanceTag.Position = Vector2.new(Pos.X, bottomOffset)
                    data.DistanceTag.Color = Settings.DistanceColor
                    data.DistanceTag.Visible = true
                else
                    data.DistanceTag.Visible = false
                end

                -- ═══════════════════════════════════
                -- SKELETON
                -- ═══════════════════════════════════
                if Settings.ESP_Skeleton then
                    UpdateSkeleton(plr, data, mm2_Color)
                elseif data.Skeleton then
                    for _, l in ipairs(data.Skeleton) do l.Visible = false end
                end
            else
                HideAllESP(data)
            end
        else
            HideAllESP(data)
        end
    end
end

for _, v in pairs(Players:GetPlayers()) do if v ~= LocalPlayer then CreateESP(v) end end

table.insert(CheatEnv.Connections, Players.PlayerAdded:Connect(function(player)
    CreateESP(player)
    RebuildTargetScanPlayers()
end))
table.insert(CheatEnv.Connections, Players.PlayerRemoving:Connect(function(player)
    RemoveESP(player)
    VelocityBuffers[player] = nil
    PredictionStates[player] = nil
    PredictionFrameCache[player] = nil
    RebuildTargetScanPlayers()
end))

-- Counter Blox No Spread Logic
local function ApplyNoSpread()
    if game.PlaceId ~= 301549746 then return end

    local originals = CheatEnv.NoSpreadOriginals
    local WeaponsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Weapons")
    if not WeaponsFolder then
        if not Settings.NoSpread and next(originals) then
            for valueObj, originalValue in pairs(originals) do
                if valueObj and valueObj.Parent and valueObj:IsA("NumberValue") then
                    valueObj.Value = originalValue
                end
            end
            CheatEnv.NoSpreadOriginals = {}
        end
        return
    end

    if Settings.NoSpread then
        for _, weapon in ipairs(WeaponsFolder:GetChildren()) do
            local spread = weapon:FindFirstChild("Spread")
            if spread then
                for _, v in ipairs(spread:GetDescendants()) do
                    if v:IsA("NumberValue") then
                        if originals[v] == nil then
                            originals[v] = v.Value
                        end
                        v.Value = 0
                    end
                end
            end
        end
        return
    end

    if next(originals) then
        for valueObj, originalValue in pairs(originals) do
            if valueObj and valueObj.Parent and valueObj:IsA("NumberValue") then
                valueObj.Value = originalValue
            end
        end
        CheatEnv.NoSpreadOriginals = {}
    end
end

-- Запуск No Spread при включении
-- Helper function to check if any weapon mods are active
local function IsAnyModActive()
    return Settings.RapidFire or Settings.InstantReload or Settings.InfiniteAmmo or
        Settings.MaxPenetration or Settings.ArmorPierce or Settings.NoFalloff or Settings.MaxRange or Settings.NoSpread or
        Settings.DamageMult > 1 or Settings.FreezeSpray or Settings.ForceFullAuto or
        Settings.FireRateMultiplier > 1 or Settings.ReloadMultiplier > 1 or
        Settings.SpreadMultiplier < 1
end

-- Main Heartbeat Loop for Weapon Logic
table.insert(CheatEnv.Connections, RunService.Heartbeat:Connect(function()
    if game.PlaceId ~= 301549746 then
        return
    end

    local now = tick()

    -- Apply/restore No Spread values
    if Settings.NoSpread or next(CheatEnv.NoSpreadOriginals) then
        if (now - (CheatEnv.LastNoSpreadApply or 0)) >= 0.25 then
            CheatEnv.LastNoSpreadApply = now
            ApplyNoSpread()
        end
    end

    -- Apply/restore Weapon Mods (run once more after disable to revert)
    local anyModsActive = IsAnyModActive()
    if anyModsActive then
        CheatEnv.WeaponModsDirty = true
    end

    if anyModsActive or CheatEnv.WeaponModsDirty then
        if (now - (CheatEnv.LastWeaponModsApply or 0)) >= 1 then
            CheatEnv.LastWeaponModsApply = now
            if type(ApplyWeaponMods) == "function" then
                ApplyWeaponMods()
            end
            if not anyModsActive then
                CheatEnv.WeaponModsDirty = false
            end
        end
    end

    -- Run wall logic on Heartbeat to avoid RenderStepped stalls.
    if Settings.WallShot or next(WallStorage) then
        ApplyWallShot()
    end
end))

-- [NEW] CB WEAPON MODS LOGIC v6.8
ApplyWeaponMods = function()
    if game.PlaceId ~= 301549746 then return end

    local WeaponsFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Weapons")
    if not WeaponsFolder then return end

    local function CacheOriginal(container, valueObj, originalName)
        if not valueObj then return nil end

        local existing = container:FindFirstChild(originalName)
        if existing then
            if existing:IsA("NumberValue") or existing:IsA("IntValue") or existing:IsA("BoolValue") or existing:IsA("StringValue") then
                return existing
            end
            return nil
        end

        local className = valueObj.ClassName
        if className ~= "NumberValue" and className ~= "IntValue" and className ~= "BoolValue" and className ~= "StringValue" then
            className = "NumberValue"
        end

        local original = Instance.new(className)
        original.Name = originalName
        original.Value = valueObj.Value
        original.Parent = container
        return original
    end

    -- Recursive function to process any container
    local function ProcessContainer(container)
        -- Fire Rate (with slider support)
        local fireRate = container:FindFirstChild("FireRate")
        if fireRate and fireRate:IsA("NumberValue") then
            local original = CacheOriginal(container, fireRate, "OriginalFireRate")
            if original then
                if Settings.RapidFire then
                    fireRate.Value = 0.01 -- Max speed
                elseif Settings.FireRateMultiplier > 1 then
                    fireRate.Value = original.Value / Settings.FireRateMultiplier
                else
                    fireRate.Value = original.Value
                end
            end
        end

        -- Reload Time (with slider support)
        local reload = container:FindFirstChild("ReloadTime")
        if reload and reload:IsA("NumberValue") then
            local original = CacheOriginal(container, reload, "OriginalReloadTime")
            if original then
                if Settings.InstantReload then
                    reload.Value = 0.01
                elseif Settings.ReloadMultiplier > 1 then
                    reload.Value = original.Value / Settings.ReloadMultiplier
                else
                    reload.Value = original.Value
                end
            end
        end

        -- Infinite Ammo
        local ammo = container:FindFirstChild("Ammo")
        local stored = container:FindFirstChild("StoredAmmo")
        if ammo and ammo:IsA("IntValue") then
            local originalAmmo = CacheOriginal(container, ammo, "OriginalAmmo")
            if originalAmmo then
                if Settings.InfiniteAmmo then
                    ammo.Value = 999
                else
                    ammo.Value = originalAmmo.Value
                end
            end
        end
        if stored and stored:IsA("IntValue") then
            local originalStored = CacheOriginal(container, stored, "OriginalStoredAmmo")
            if originalStored then
                if Settings.InfiniteAmmo then
                    stored.Value = 9999
                else
                    stored.Value = originalStored.Value
                end
            end
        end

        -- Spread (with slider support)
        local spread = container:FindFirstChild("Spread")
        if spread and (spread:IsA("NumberValue") or spread:IsA("IntValue")) then
            local original = CacheOriginal(container, spread, "OriginalSpread")
            if original then
                if Settings.NoSpread then
                    spread.Value = 0
                elseif Settings.SpreadMultiplier < 1 then
                    local scaled = original.Value * Settings.SpreadMultiplier
                    if spread:IsA("IntValue") then
                        scaled = math.floor(scaled + 0.5)
                    end
                    spread.Value = scaled
                else
                    spread.Value = original.Value
                end
            end
        end

        -- Force Full Auto
        local autoVal = container:FindFirstChild("Auto")
        if autoVal and autoVal:IsA("BoolValue") then
            local original = CacheOriginal(container, autoVal, "OriginalAuto")
            if original then
                if Settings.ForceFullAuto then
                    autoVal.Value = true
                else
                    autoVal.Value = original.Value
                end
            end
        end

        -- Freeze Spray (clear recoil pattern)
        local pattern = container:FindFirstChild("Pattern")
        if pattern and pattern:IsA("StringValue") then
            local original = CacheOriginal(container, pattern, "OriginalPattern")
            if original then
                if Settings.FreezeSpray then
                    -- Set to straight up pattern (no recoil)
                    pattern.Value = '[{"fMagnitude":0,"fAngle":90}]'
                else
                    pattern.Value = original.Value
                end
            end
        end

        -- Scoped Pattern too
        local scopedPattern = container:FindFirstChild("ScopedPattern")
        if scopedPattern and scopedPattern:IsA("StringValue") then
            local original = CacheOriginal(container, scopedPattern, "OriginalScopedPattern")
            if original then
                if Settings.FreezeSpray then
                    scopedPattern.Value = '[{"fMagnitude":0,"fAngle":90}]'
                else
                    scopedPattern.Value = original.Value
                end
            end
        end

        -- Damage Multiplier
        local dmg = container:FindFirstChild("DMG")
        if dmg and dmg:IsA("IntValue") then
            local original = CacheOriginal(container, dmg, "OriginalDMG")
            if original then
                if Settings.DamageMult > 1 then
                    dmg.Value = math.floor(original.Value * Settings.DamageMult)
                else
                    dmg.Value = original.Value
                end
            end
        end

        -- Max Penetration
        local pen = container:FindFirstChild("Penetration")
        if pen and (pen:IsA("IntValue") or pen:IsA("NumberValue")) then
            local original = CacheOriginal(container, pen, "OriginalPenetration")
            if original then
                if Settings.MaxPenetration then
                    pen.Value = 999
                else
                    pen.Value = original.Value
                end
            end
        end

        -- Armor Piercing
        local armorPen = container:FindFirstChild("ArmorPenetration")
        if armorPen and (armorPen:IsA("NumberValue") or armorPen:IsA("IntValue")) then
            local original = CacheOriginal(container, armorPen, "OriginalArmorPenetration")
            if original then
                if Settings.ArmorPierce then
                    armorPen.Value = 100
                else
                    armorPen.Value = original.Value
                end
            end
        end

        -- No Falloff
        local rangeMod = container:FindFirstChild("RangeModifier")
        if rangeMod and (rangeMod:IsA("IntValue") or rangeMod:IsA("NumberValue")) then
            local original = CacheOriginal(container, rangeMod, "OriginalRangeModifier")
            if original then
                if Settings.NoFalloff then
                    rangeMod.Value = 100
                else
                    rangeMod.Value = original.Value
                end
            end
        end

        -- Max Range
        local range = container:FindFirstChild("Range")
        if range and (range:IsA("IntValue") or range:IsA("NumberValue")) then
            local original = CacheOriginal(container, range, "OriginalRange")
            if original then
                if Settings.MaxRange then
                    range.Value = 99999
                else
                    range.Value = original.Value
                end
            end
        end

        -- Recurse into children folders (Primary, Secondary, etc)
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Folder") or child:IsA("Configuration") then
                ProcessContainer(child)
            end
        end
    end

    for _, weapon in ipairs(WeaponsFolder:GetChildren()) do
        if weapon:IsA("Folder") then
            ProcessContainer(weapon)
        end
    end
end

-- [IMPROVED] Counter-Strafe System
CS_LastMoveDir = Vector3.zero
CS_WasMoving = false
CS_StopTime = 0

function ApplyCounterStrafe()
    if not Settings.CounterStrafe then return end
    if not LocalPlayer.Character then return end

    local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local hum = LocalPlayer.Character:FindFirstChild("Humanoid")
    if not root or not hum then return end

    local moveDir = hum.MoveDirection
    local vel = root.AssemblyLinearVelocity
    local horizontalVel = Vector3.new(vel.X, 0, vel.Z)
    local speed = horizontalVel.Magnitude

    -- Detect key release (was moving, now stopped input)
    local isInputting = moveDir.Magnitude > 0.1

    if CS_WasMoving and not isInputting then
        -- Player just released movement keys!
        CS_StopTime = tick()
        CS_LastMoveDir = CS_LastMoveDir.Unit -- Normalize for direction
    end

    -- Apply counter-force for 100ms after key release
    if not isInputting and (tick() - CS_StopTime) < 0.1 then
        if speed > 1 then
            -- Instant stop with slight counter-impulse
            local counterForce = -horizontalVel * 0.95
            root.AssemblyLinearVelocity = Vector3.new(counterForce.X, vel.Y, counterForce.Z)
        end
    end

    -- Track state for next frame
    CS_WasMoving = isInputting
    if isInputting then
        CS_LastMoveDir = moveDir
    end
end

-- [NEW v6.8] NO FALL DAMAGE SYSTEM
ExtState = {
    FallDamageHooked = false,
    LastDeathCheck = 0,
    VM_DefaultX = 1, VM_DefaultY = 0, VM_DefaultZ = 0,
    VM_LastX = nil, VM_LastY = nil, VM_LastZ = nil
}

function SetupNoFallDamage()
    if game.PlaceId ~= 301549746 then return end
    if ExtState.FallDamageHooked then return end
    if type(SharedHookState) ~= "table" then return end

    -- Find the FallDamage remote
    local Events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
    if not Events then return end

    local FallDamageRemote = Events:FindFirstChild("FallDamage")
    if not FallDamageRemote then return end
    SharedHookState.fallRemote = FallDamageRemote

    if SharedHookState.fallDamageInstalled then
        ExtState.FallDamageHooked = true
        return
    end

    -- Hook the remote's FireServer
    if hookfunction then
        pcall(function()
            local oldFireServer
            oldFireServer = hookfunction(FallDamageRemote.FireServer, function(self, ...)
                local hookState = _G.VAYS_HOOK_STATE
                local stateSettings = hookState and hookState.settings
                local stateRemote = hookState and hookState.fallRemote
                if hookState and hookState.active and stateSettings and self == stateRemote and stateSettings.NoFallDamage then
                    return -- Block fall damage
                end
                if oldFireServer then
                    return oldFireServer(self, ...)
                end
            end)
            if oldFireServer then
                ExtState.FallDamageHooked = true
                SharedHookState.fallDamageInstalled = true
                print("✓ [CB] No Fall Damage hook installed")
            end
        end)
    end
end

-- [NEW v6.8] AUTO RESPAWN SYSTEM
ExtState.CheckAutoRespawn = function()
    if game.PlaceId ~= 301549746 then return end
    if not Settings.AutoRespawn then return end
    if tick() - ExtState.LastDeathCheck < 1 then return end -- Throttle to 1 check per second

    ExtState.LastDeathCheck = tick()

    -- Check if player is dead via Status.Alive
    local statusFolder = LocalPlayer:FindFirstChild("Status")
    if statusFolder then
        local aliveVal = statusFolder:FindFirstChild("Alive")
        if aliveVal and aliveVal:IsA("BoolValue") and not aliveVal.Value then
            -- Player is dead, try to respawn
            local Events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
            if Events then
                local Spawnme = Events:FindFirstChild("Spawnme")
                if Spawnme and Spawnme:IsA("RemoteEvent") then
                    pcall(function()
                        Spawnme:FireServer()
                    end)
                end
            end
        end
    end
end

-- [NEW v6.8] VIEWMODEL CHANGER SYSTEM
-- CB Default values: ViewmodelX = 1, ViewmodelY = 0, ViewmodelZ = 0

function ApplyViewmodelOffset()
    if game.PlaceId ~= 301549746 then return end

    local player = LocalPlayer
    if not player then return end

    -- Calculate final values (default + user offset)
    local finalX = ExtState.VM_DefaultX + Settings.ViewmodelX
    local finalY = ExtState.VM_DefaultY + Settings.ViewmodelY
    local finalZ = ExtState.VM_DefaultZ + Settings.ViewmodelZ

    -- Only update if values changed (performance)
    if finalX ~= ExtState.VM_LastX or finalY ~= ExtState.VM_LastY or finalZ ~= ExtState.VM_LastZ then
        ExtState.VM_LastX, ExtState.VM_LastY, ExtState.VM_LastZ = finalX, finalY, finalZ

        pcall(function()
            player:SetAttribute("ViewmodelX", finalX)
            player:SetAttribute("ViewmodelY", finalY)
            player:SetAttribute("ViewmodelZ", finalZ)
        end)
    end
end

-- [NEW v6.8] CB VISUALS SYSTEM
function SaveOriginalVisuals()
    if CB_OriginalLighting then return end -- Already saved

    local currentCam = workspace.CurrentCamera
    if not currentCam then return end

    CB_OriginalLighting = {
        Brightness = Lighting.Brightness,
        Ambient = Lighting.Ambient,
        OutdoorAmbient = Lighting.OutdoorAmbient,
        GlobalShadows = Lighting.GlobalShadows,
        FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart,
    }

    -- Save Atmosphere if exists
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if atmosphere then
        CB_OriginalLighting.AtmosphereDensity = atmosphere.Density
        CB_OriginalLighting.AtmosphereHaze = atmosphere.Haze
        CB_OriginalLighting.AtmosphereGlare = atmosphere.Glare
    end

    -- Save Camera ColorCorrection if exists
    local camCC = currentCam:FindFirstChildOfClass("ColorCorrectionEffect")
    if camCC then
        CB_OriginalCamera = {
            CCBrightness = camCC.Brightness,
            CCContrast = camCC.Contrast,
            CCSaturation = camCC.Saturation,
            CCTintColor = camCC.TintColor,
            CCEnabled = camCC.Enabled,
        }
    end

    -- Save Camera Blur if exists
    local camBlur = currentCam:FindFirstChildOfClass("BlurEffect")
    if camBlur then
        CB_OriginalCamera = CB_OriginalCamera or {}
        CB_OriginalCamera.BlurSize = camBlur.Size
        CB_OriginalCamera.BlurEnabled = camBlur.Enabled
    end

    -- Save Lighting ColorCorrection if exists
    local lightCC = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
    if lightCC then
        CB_OriginalLighting.LightCCBrightness = lightCC.Brightness
        CB_OriginalLighting.LightCCContrast = lightCC.Contrast
        CB_OriginalLighting.LightCCSaturation = lightCC.Saturation
    end

    -- Save Sky
    local sky = Lighting:FindFirstChildOfClass("Sky")
    if sky then
        CB_OriginalLighting.Sky = sky
        CB_OriginalLighting.SkyParent = sky.Parent
    end
end

ApplyCBVisuals = function()
    if game.PlaceId ~= 301549746 then return end

    SaveOriginalVisuals()

    local currentCam = workspace.CurrentCamera
    if not currentCam then return end

    -- FULLBRIGHT
    if Settings.CB_Fullbright then
        Lighting.Brightness = 3
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        Lighting.GlobalShadows = false
    else
        if CB_OriginalLighting then
            Lighting.Brightness = CB_OriginalLighting.Brightness or 1
            Lighting.Ambient = CB_OriginalLighting.Ambient or Color3.fromRGB(127, 127, 127)
            Lighting.OutdoorAmbient = CB_OriginalLighting.OutdoorAmbient or Color3.fromRGB(127, 127, 127)
            Lighting.GlobalShadows = CB_OriginalLighting.GlobalShadows
        end
    end

    -- NO FOG / HAZE
    local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
    if Settings.CB_NoFog then
        Lighting.FogEnd = 1000000
        Lighting.FogStart = 1000000
        if atmosphere then
            atmosphere.Density = 0
            atmosphere.Haze = 0
            atmosphere.Glare = 0
        end
    else
        if CB_OriginalLighting then
            Lighting.FogEnd = CB_OriginalLighting.FogEnd or 100000
            Lighting.FogStart = CB_OriginalLighting.FogStart or 0
            if atmosphere then
                atmosphere.Density = CB_OriginalLighting.AtmosphereDensity or 0.2
                atmosphere.Haze = CB_OriginalLighting.AtmosphereHaze or 1
                atmosphere.Glare = CB_OriginalLighting.AtmosphereGlare or 0.2
            end
        end
    end

    -- NO BLUR (Camera blur)
    local camBlur = currentCam:FindFirstChildOfClass("BlurEffect")
    if camBlur then
        if Settings.CB_NoBlur then
            camBlur.Enabled = false
            camBlur.Size = 0
        else
            if CB_OriginalCamera then
                camBlur.Enabled = CB_OriginalCamera.BlurEnabled ~= false
                camBlur.Size = CB_OriginalCamera.BlurSize or 0
            end
        end
    end

    -- NIGHT VISION + HIGH SATURATION + BRIGHTNESS/CONTRAST
    local camCC = currentCam:FindFirstChildOfClass("ColorCorrectionEffect")
    if not camCC then
        camCC = Instance.new("ColorCorrectionEffect")
        camCC.Name = "VAYS_CB_ColorCorrection"
        camCC.Parent = currentCam
    end

    if Settings.CB_NightVision then
        camCC.Enabled = true
        camCC.TintColor = Color3.fromRGB(100, 255, 100) -- Green tint
        camCC.Brightness = 0.3
        camCC.Contrast = 0.5
        camCC.Saturation = -0.5
    elseif Settings.CB_HighSaturation then
        camCC.Enabled = true
        camCC.TintColor = Color3.fromRGB(255, 255, 255)
        camCC.Brightness = Settings.CB_CustomBrightness - 1
        camCC.Contrast = Settings.CB_CustomContrast
        camCC.Saturation = 0.8
    else
        -- Apply custom brightness/contrast without special effects
        camCC.Enabled = true
        camCC.TintColor = Color3.fromRGB(255, 255, 255)
        camCC.Brightness = Settings.CB_CustomBrightness - 1
        camCC.Contrast = Settings.CB_CustomContrast
        camCC.Saturation = 0
    end

    -- NO SKY
    local sky = Lighting:FindFirstChildOfClass("Sky")
    if Settings.CB_NoSky then
        if sky then
            if CB_OriginalLighting then
                CB_OriginalLighting.Sky = CB_OriginalLighting.Sky or sky
                CB_OriginalLighting.SkyParent = CB_OriginalLighting.SkyParent or sky.Parent
            end
            sky.Parent = nil -- Remove from Lighting (store reference)
        end
    else
        if CB_OriginalLighting and CB_OriginalLighting.Sky and CB_OriginalLighting.Sky.Parent == nil then
            CB_OriginalLighting.Sky.Parent = CB_OriginalLighting.SkyParent or Lighting
        end
    end
end

RestoreCBVisuals = function()
    local lighting = game:GetService("Lighting")
    local currentCam = Workspace.CurrentCamera

    if CB_OriginalLighting then
        lighting.Brightness = CB_OriginalLighting.Brightness or lighting.Brightness
        lighting.Ambient = CB_OriginalLighting.Ambient or lighting.Ambient
        lighting.OutdoorAmbient = CB_OriginalLighting.OutdoorAmbient or lighting.OutdoorAmbient
        if CB_OriginalLighting.GlobalShadows ~= nil then
            lighting.GlobalShadows = CB_OriginalLighting.GlobalShadows
        end
        lighting.FogEnd = CB_OriginalLighting.FogEnd or lighting.FogEnd
        lighting.FogStart = CB_OriginalLighting.FogStart or lighting.FogStart

        local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
        if atmosphere then
            if CB_OriginalLighting.AtmosphereDensity ~= nil then
                atmosphere.Density = CB_OriginalLighting.AtmosphereDensity
            end
            if CB_OriginalLighting.AtmosphereHaze ~= nil then
                atmosphere.Haze = CB_OriginalLighting.AtmosphereHaze
            end
            if CB_OriginalLighting.AtmosphereGlare ~= nil then
                atmosphere.Glare = CB_OriginalLighting.AtmosphereGlare
            end
        end

        local lightCC = lighting:FindFirstChildOfClass("ColorCorrectionEffect")
        if lightCC then
            if CB_OriginalLighting.LightCCBrightness ~= nil then
                lightCC.Brightness = CB_OriginalLighting.LightCCBrightness
            end
            if CB_OriginalLighting.LightCCContrast ~= nil then
                lightCC.Contrast = CB_OriginalLighting.LightCCContrast
            end
            if CB_OriginalLighting.LightCCSaturation ~= nil then
                lightCC.Saturation = CB_OriginalLighting.LightCCSaturation
            end
        end

        if CB_OriginalLighting.Sky and CB_OriginalLighting.Sky.Parent == nil then
            CB_OriginalLighting.Sky.Parent = CB_OriginalLighting.SkyParent or lighting
        end
    end

    if currentCam then
        local camCC = currentCam:FindFirstChildOfClass("ColorCorrectionEffect")
        if camCC and CB_OriginalCamera and CB_OriginalCamera.CCBrightness ~= nil then
            camCC.Brightness = CB_OriginalCamera.CCBrightness
            camCC.Contrast = CB_OriginalCamera.CCContrast or 0
            camCC.Saturation = CB_OriginalCamera.CCSaturation or 0
            camCC.TintColor = CB_OriginalCamera.CCTintColor or Color3.fromRGB(255, 255, 255)
            camCC.Enabled = CB_OriginalCamera.CCEnabled == true
        else
            local vaysCC = currentCam:FindFirstChild("VAYS_CB_ColorCorrection")
            if vaysCC then
                vaysCC:Destroy()
            end
        end

        local camBlur = currentCam:FindFirstChildOfClass("BlurEffect")
        if camBlur and CB_OriginalCamera then
            if CB_OriginalCamera.BlurEnabled ~= nil then
                camBlur.Enabled = CB_OriginalCamera.BlurEnabled
            end
            if CB_OriginalCamera.BlurSize ~= nil then
                camBlur.Size = CB_OriginalCamera.BlurSize
            end
        end
    end
end

-- [NEW v6.8] BOMB TIMER ESP
function UpdateBombTimerESP()
    if game.PlaceId ~= 301549746 then return end
    if not Camera then
        if CB_BombTimerLabel then
            CB_BombTimerLabel.Visible = false
        end
        return
    end

    -- Create or update bomb timer label
    if Settings.CB_BombTimerESP then
        local statusFolder = workspace:FindFirstChild("Status")
        if not statusFolder then return end

        local timer = statusFolder:FindFirstChild("Timer")
        local bombActive = statusFolder:FindFirstChild("ITSGOINGTOEXPLODE")

        if not CB_BombTimerLabel then
            CB_BombTimerLabel = Drawing.new("Text")
            CB_BombTimerLabel.Size = 22
            CB_BombTimerLabel.Font = 2
            CB_BombTimerLabel.Outline = true
            CB_BombTimerLabel.OutlineColor = Color3.fromRGB(0, 0, 0)
            CB_BombTimerLabel.Center = true
            table.insert(CheatEnv.Drawings, CB_BombTimerLabel)
        end

        if bombActive and bombActive.Value == true then
            local timeLeft = timer and timer.Value or 0
            CB_BombTimerLabel.Visible = true
            CB_BombTimerLabel.Position = Vector2.new(Camera.ViewportSize.X / 2, 100)

            if timeLeft <= 10 then
                CB_BombTimerLabel.Color = Color3.fromRGB(255, 50, 50) -- Red when low
                CB_BombTimerLabel.Text = "💣 BOMB: " .. tostring(timeLeft) .. "s 💣"
            else
                CB_BombTimerLabel.Color = Color3.fromRGB(255, 200, 50) -- Yellow
                CB_BombTimerLabel.Text = "💣 BOMB: " .. tostring(timeLeft) .. "s"
            end
        else
            CB_BombTimerLabel.Visible = false
        end
    else
        if CB_BombTimerLabel then
            CB_BombTimerLabel.Visible = false
        end
    end
end

-- CB Features Heartbeat Loop
table.insert(CheatEnv.Connections, RunService.Heartbeat:Connect(function()
    -- Misc global fullbright
    if Settings.Misc_Fullbright then
        local backup = CheatEnv.MiscLightingBackup
        if not backup then
            backup = {
                Brightness = Lighting.Brightness,
                Ambient = Lighting.Ambient,
                OutdoorAmbient = Lighting.OutdoorAmbient,
                GlobalShadows = Lighting.GlobalShadows
            }
            pcall(function()
                backup.ExposureCompensation = Lighting.ExposureCompensation
            end)
            CheatEnv.MiscLightingBackup = backup
        end

        Lighting.Brightness = Settings.Misc_FB_Brightness or 3
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
        Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
        if Settings.Misc_FB_DisableShadows then
            Lighting.GlobalShadows = false
        else
            Lighting.GlobalShadows = backup.GlobalShadows
        end
        pcall(function()
            Lighting.ExposureCompensation = Settings.Misc_FB_Exposure or 0.35
        end)
    else
        local backup = CheatEnv.MiscLightingBackup
        if backup then
            Lighting.Brightness = backup.Brightness or Lighting.Brightness
            Lighting.Ambient = backup.Ambient or Lighting.Ambient
            Lighting.OutdoorAmbient = backup.OutdoorAmbient or Lighting.OutdoorAmbient
            if backup.GlobalShadows ~= nil then
                Lighting.GlobalShadows = backup.GlobalShadows
            end
            if backup.ExposureCompensation ~= nil then
                pcall(function()
                    Lighting.ExposureCompensation = backup.ExposureCompensation
                end)
            end
            CheatEnv.MiscLightingBackup = nil
        end
    end

    -- Counter-Strafe
    ApplyCounterStrafe()

    -- Auto Respawn check
    ExtState.CheckAutoRespawn()

    -- Viewmodel offset (only when values change significantly)
    if game.PlaceId == 301549746 then
        ApplyViewmodelOffset()

        -- CB Visuals (apply every frame for toggles)
        ApplyCBVisuals()

        -- Bomb Timer ESP
        UpdateBombTimerESP()
    end
end))

-- Initialize CB hooks
if game.PlaceId == 301549746 then
    task.delay(1, SetupNoFallDamage)
end

-- [NEW] RAYCAST HOOK FOR WALL SHOT
-- This hooks into the game's Raycast calls and filters out walls
function SetupRaycastHook()
    if game.PlaceId ~= 301549746 then return end
    if type(SharedHookState) == "table" and SharedHookState.raycastHookEnabled then return end
    if type(SharedHookState) == "table" and SharedHookState.raycastInstalled then
        SharedHookState.raycastHookEnabled = true
        return
    end
    if not hookmetamethod then
        warn("[WallShot] hookmetamethod not available - using fallback method")
        return
    end

    local success, err = pcall(function()
        SharedHookState.originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            local method = getnamecallmethod()
            local args = { ... }

            -- Intercept Raycast calls on Workspace
            if method == "Raycast" and self == Workspace then
                local hookState = _G.VAYS_HOOK_STATE
                local stateSettings = hookState and hookState.settings
                local wallShotEnabled = hookState and hookState.active and stateSettings and stateSettings.WallShot

                if wallShotEnabled then
                    local origin = args[1]
                    local direction = args[2]
                    local rayParams = args[3]

                    if rayParams then
                        -- Clone the params to avoid modifying original
                        local newParams = RaycastParams.new()
                        newParams.FilterType = rayParams.FilterType
                        newParams.IgnoreWater = rayParams.IgnoreWater
                        newParams.CollisionGroup = rayParams.CollisionGroup
                        pcall(function()
                            newParams.RespectCanCollide = rayParams.RespectCanCollide
                        end)
                        pcall(function()
                            newParams.BruteForceAllSlow = rayParams.BruteForceAllSlow
                        end)

                        -- Get current filter list
                        local filterList = rayParams.FilterDescendantsInstances or {}

                        -- Add all walls from current runtime storage to filter
                        local newFilter = {}
                        for _, v in ipairs(filterList) do
                            table.insert(newFilter, v)
                        end

                        local wallStorageRef = nil
                        if hookState and hookState.getWallStorage then
                            local ok, result = pcall(hookState.getWallStorage)
                            if ok and type(result) == "table" then
                                wallStorageRef = result
                            end
                        end

                        if wallStorageRef then
                            for wall, _ in pairs(wallStorageRef) do
                                if wall and wall.Parent then
                                    table.insert(newFilter, wall)
                                end
                            end
                        end

                        newParams.FilterDescendantsInstances = newFilter

                        if SharedHookState and SharedHookState.originalNamecall then
                            return SharedHookState.originalNamecall(self, origin, direction, newParams)
                        end
                    end
                end
            end

            if SharedHookState and SharedHookState.originalNamecall then
                return SharedHookState.originalNamecall(self, ...)
            end
        end)
    end)

    if success then
        if type(SharedHookState) == "table" then
            SharedHookState.raycastHookEnabled = true
        end
        if type(SharedHookState) == "table" then
            SharedHookState.raycastInstalled = true
        end
        print("✓ [WallShot] Raycast hook installed successfully")
    else
        warn("[WallShot] Hook failed: " .. tostring(err))
    end
end

-- Initialize hook if in Counter Blox
if game.PlaceId == 301549746 then
    task.delay(1, SetupRaycastHook) 
end

-- SCP Logic moved up to prevent scope errors

CheatEnv.OffsetUDim2 = function(pos, dx, dy)
    return UDim2.new(pos.X.Scale, pos.X.Offset + (dx or 0), pos.Y.Scale, pos.Y.Offset + (dy or 0))
end

CheatEnv.MenuAnimState = CheatEnv.MenuAnimState or {
    token = 0,
    visible = MainFrame.Visible == true,
    mainScale = EnsureControlScale(MainFrame, "MenuToggleScale"),
    configScale = EnsureControlScale(ConfigFrame, "ConfigToggleScale")
}

if CheatEnv.MenuAnimState.mainScale then
    CheatEnv.MenuAnimState.mainScale.Scale = 1
end
if CheatEnv.MenuAnimState.configScale then
    CheatEnv.MenuAnimState.configScale.Scale = 1
end

CheatEnv.AnimateOverlayLabel = function(label, show, openStrokeTransparency)
    if not label or not label.Parent then return end

    if show then
        label.Visible = true
        label.TextTransparency = 1
        label.TextStrokeTransparency = 1
        TweenService:Create(label, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            TextTransparency = 0,
            TextStrokeTransparency = openStrokeTransparency or 0.6
        }):Play()
    else
        local fade = TweenService:Create(label, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            TextTransparency = 1,
            TextStrokeTransparency = 1
        })
        fade:Play()
    end
end

CheatEnv.AnimateGameTag = function(show)
    if not GameTag or not GameTag.Parent then return end

    local targetPos = GameTag.Position
    if show then
        GameTag.Visible = true
        GameTag.BackgroundTransparency = 1
        GameTag.Position = CheatEnv.OffsetUDim2(targetPos, 0, 12)
        TweenService:Create(GameTag, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = targetPos,
            BackgroundTransparency = 0.7
        }):Play()
    else
        local fade = TweenService:Create(GameTag, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = CheatEnv.OffsetUDim2(targetPos, 0, 10),
            BackgroundTransparency = 1
        })
        fade:Play()
    end
end

CheatEnv.SetMenuVisibleAnimated = function(show)
    local menuAnimState = CheatEnv.MenuAnimState
    if menuAnimState.visible == show then return end
    menuAnimState.visible = show
    menuAnimState.token = menuAnimState.token + 1
    local token = menuAnimState.token

    if not show then
        if CheatEnv.ActiveRebindCapture and CheatEnv.FinishRebindCapture then
            CheatEnv.FinishRebindCapture("cancel")
        end
        if CheatEnv.RebindWindows and CheatEnv.CloseRebindWindow then
            local rebindKeys = {}
            for settingKey, state in pairs(CheatEnv.RebindWindows) do
                if state then
                    rebindKeys[#rebindKeys + 1] = settingKey
                end
            end
            for i = 1, #rebindKeys do
                CheatEnv.CloseRebindWindow(rebindKeys[i], true)
            end
        end
    end

    if CheatEnv.UpdateKeybindList then
        task.defer(CheatEnv.UpdateKeybindList)
    end

    if menuAnimState.tweens then
        for i = 1, #menuAnimState.tweens do
            local tween = menuAnimState.tweens[i]
            if tween then
                pcall(function()
                    tween:Cancel()
                end)
            end
        end
    end
    local activeTweens = {}
    menuAnimState.tweens = activeTweens

    local function PlayTween(instance, info, goal)
        if not instance then return nil end
        local tween = TweenService:Create(instance, info, goal)
        activeTweens[#activeTweens + 1] = tween
        tween:Play()
        return tween
    end

    local mainScale = menuAnimState.mainScale
    local configScale = menuAnimState.configScale

    local mainTargetPos = MainFrame.Position
    local configTargetPos = ConfigFrame and ConfigFrame.Position or nil
    local gameTagTargetPos = GameTag and GameTag.Position or nil

    if show then
        MainFrame.Visible = true
        if ConfigFrame then
            ConfigFrame.Visible = true
        end
        MenuBlur.Enabled = true

        MainFrame.Position = CheatEnv.OffsetUDim2(mainTargetPos, 0, 24)
        if mainScale then
            mainScale.Scale = 0.9
        end

        if ConfigFrame and configTargetPos then
            ConfigFrame.Position = CheatEnv.OffsetUDim2(configTargetPos, 0, 18)
            if configScale then
                configScale.Scale = 0.92
            end
        end

        PlayTween(MenuBlur, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = 22
        })

        PlayTween(MainFrame, TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Position = mainTargetPos
        })
        if mainScale then
            PlayTween(mainScale, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Scale = 1
            })
        end

        task.delay(0.04, function()
            if menuAnimState.token ~= token or not menuAnimState.visible then return end
            if ConfigFrame and configTargetPos then
                PlayTween(ConfigFrame, TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
                    Position = configTargetPos
                })
                if configScale then
                    PlayTween(configScale, TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                        Scale = 1
                    })
                end
            end
        end)

        task.delay(0.06, function()
            if menuAnimState.token ~= token or not menuAnimState.visible then return end
            CheatEnv.AnimateGameTag(true)
            CheatEnv.AnimateOverlayLabel(WelcomeLabel, true, 0.5)
            CheatEnv.AnimateOverlayLabel(SessionLabel, true, 0.7)
        end)
    else
        CreateConfigModal.Visible = false
        ConfigSystem.DeleteMode = false
        ConfigSystem.OverwriteMode = false
        ConfigHint.Visible = false

        CheatEnv.AnimateOverlayLabel(WelcomeLabel, false)
        CheatEnv.AnimateOverlayLabel(SessionLabel, false)
        CheatEnv.AnimateGameTag(false)

        PlayTween(MenuBlur, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Size = 0
        })

        PlayTween(MainFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = CheatEnv.OffsetUDim2(mainTargetPos, 0, 24)
        })
        if mainScale then
            PlayTween(mainScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Scale = 0.9
            })
        end

        if ConfigFrame and configTargetPos then
            PlayTween(ConfigFrame, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = CheatEnv.OffsetUDim2(configTargetPos, 0, 18)
            })
            if configScale then
                PlayTween(configScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                    Scale = 0.92
                })
            end
        end

        task.delay(0.22, function()
            if menuAnimState.token ~= token or menuAnimState.visible then return end
            MainFrame.Visible = false
            MainFrame.Position = mainTargetPos
            if mainScale then
                mainScale.Scale = 1
            end
            if ConfigFrame then
                ConfigFrame.Visible = false
                if configTargetPos then
                    ConfigFrame.Position = configTargetPos
                end
                if configScale then
                    configScale.Scale = 1
                end
            end
            if GameTag then
                GameTag.Visible = false
                if gameTagTargetPos then
                    GameTag.Position = gameTagTargetPos
                end
            end
            if WelcomeLabel then
                WelcomeLabel.Visible = false
            end
            if SessionLabel then
                SessionLabel.Visible = false
            end
            MenuBlur.Enabled = false
        end)
    end
end


--// INPUT HANDLER //--

table.insert(CheatEnv.Connections, UserInputService.InputBegan:Connect(function(input, processed)
    local activeCapture = CheatEnv.ActiveRebindCapture
    if activeCapture and activeCapture.Active then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            local keyCode = input.KeyCode
            if keyCode == Enum.KeyCode.Escape then
                CheatEnv.FinishRebindCapture("cancel")
            elseif keyCode == Enum.KeyCode.Backspace then
                CheatEnv.FinishRebindCapture("clear")
            elseif keyCode and keyCode ~= Enum.KeyCode.Unknown then
                CheatEnv.FinishRebindCapture("apply", keyCode)
            end
        end
        return
    end

    if input.KeyCode == Settings.MenuKey then
        CheatEnv.SetMenuVisibleAnimated(not (CheatEnv.MenuAnimState and CheatEnv.MenuAnimState.visible))
        return
    end

    if processed then return end

    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        if MainFrame and MainFrame.Visible then return end

        local handled = false

        local aimbotTrigger = Settings.AimbotTrigger or "T Toggle"
        if (aimbotTrigger == "RMB Hold" or aimbotTrigger == "RMB Toggle") and not Settings.Aimbot then
            Settings.Aimbot = true
            SyncButton("Aimbot")
            handled = true
        end

        if aimbotTrigger == "RMB Hold" then
            AimbotState.RMBHeld = true
            handled = true
        elseif aimbotTrigger == "RMB Toggle" then
            AimbotState.Engaged = not AimbotState.Engaged
            handled = true
        elseif aimbotTrigger == "T Toggle" or aimbotTrigger == "Always" then
            handled = true
        end

        local aimlockTrigger = Settings.AimlockTrigger or "N Key"
        if aimlockTrigger == "RMB Hold" or aimlockTrigger == "RMB Toggle" then
            if not Settings.Aimlock then
                Settings.Aimlock = true
                SyncButton("Aimlock")
            end
            AimlockEngagedFromGUI = false
            if aimlockTrigger == "RMB Hold" then
                AimlockState.RMBHeld = true
            else
                AimlockState.Engaged = not AimlockState.Engaged
            end
            handled = true
        end

        if handled then
            UpdateKeybindList()
            return
        end
    end

    -- [UPDATED] Wall Shot "On Click (L)" Logic - Toggle Wall under Crosshair
    if input.KeyCode == Enum.KeyCode.L and Settings.WallShot and Settings.WallShotMode == "On Click (L)" then
        if not Camera then return end

        local rayParams = PredConst.ClickRayParams
        if not rayParams then
            rayParams = RaycastParams.new()
            rayParams.FilterType = Enum.RaycastFilterType.Exclude
            PredConst.ClickRayParams = rayParams
        end
        local clickIgnore = BuildRaycastFilter(PredConst.ClickIgnoreList)
        PredConst.ClickIgnoreList = clickIgnore
        rayParams.FilterDescendantsInstances = clickIgnore

        -- Perform a precise raycast based on what the user sees
        local origin = Camera.CFrame.Position
        local direction = Camera.CFrame.LookVector * 2000

        local result = Workspace:Raycast(origin, direction, rayParams)

        if result and result.Instance then
            local part = result.Instance
            if not part:IsA("BasePart") then
                return
            end

            -- Safety checks to prevent removing the world
            local name = part.Name:lower()
            local isFloor = name:find("floor") or name:find("ground") or name:find("baseplate")

            -- Also check size to prevent removing massive map geometry baseplates
            if part.Size.X > 500 or part.Size.Z > 500 then isFloor = true end

            if not isFloor and part.Parent and not part.Parent:FindFirstChild("Humanoid") then
                if not WallStorage[part] then
                    MakeWallInvisible(part, "Ghost")
                else
                    local props = OriginalWallProperties[part]
                    if props then
                        pcall(function()
                            part.Transparency = props.Transparency
                            part.LocalTransparencyModifier = props.LocalTransparencyModifier
                            part.CanQuery = props.CanQuery
                            part.CanCollide = props.CanCollide
                            if props.Parent and part.Parent ~= props.Parent then
                                part.Parent = props.Parent
                            end
                        end)
                    end

                    WallStorage[part] = nil
                    OriginalWallProperties[part] = nil
                end
            end
        end
        return
    end

    local aimlockBind = CheatEnv.FindKeybindBySetting("Aimlock")
    local aimlockKey = aimlockBind and aimlockBind.Key or Enum.KeyCode.N
    if aimlockKey and input.KeyCode == aimlockKey and (Settings.AimlockTrigger or "N Key") == "N Key" then
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
            if bind.Setting == "Unload" then
                UnloadCheat()
                return
            end
            if bind.Setting == "Aimlock" then continue end
            if bind.Setting ~= "Unload" then
                Settings[bind.Setting] = not Settings[bind.Setting]
                SyncButton(bind.Setting)
                if bind.Setting == "Aimbot" and not Settings.Aimbot then
                    AimbotState.Engaged = false
                    AimbotState.RMBHeld = false
                end
                UpdateKeybindList()
                return
            end
        end
    end
end))

table.insert(CheatEnv.Connections, UserInputService.InputEnded:Connect(function(input)
    local aimlockBind = CheatEnv.FindKeybindBySetting("Aimlock")
    local aimlockKey = aimlockBind and aimlockBind.Key or Enum.KeyCode.N
    if aimlockKey and input.KeyCode == aimlockKey and Settings.AimlockMode == "N Hold" and (Settings.AimlockTrigger or "N Key") == "N Key" then
        AimlockEngaged = false
        UpdateKeybindList()
    end

    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        local changed = false
        if Settings.AimbotTrigger == "RMB Hold" and AimbotState.RMBHeld then
            AimbotState.RMBHeld = false
            changed = true
        end
        if Settings.AimlockTrigger == "RMB Hold" and AimlockState.RMBHeld then
            AimlockState.RMBHeld = false
            changed = true
        end
        if changed then
            UpdateKeybindList()
        end
    end
end))

table.insert(CheatEnv.Connections, UserInputService.WindowFocusReleased:Connect(function()
    local changed = false
    if AimbotState.RMBHeld then
        AimbotState.RMBHeld = false
        changed = true
    end
    if AimlockState.RMBHeld then
        AimlockState.RMBHeld = false
        changed = true
    end
    if changed then
        UpdateKeybindList()
    end
end))

table.insert(CheatEnv.Connections, RunService.RenderStepped:Connect(function(dt)
    if CheatEnv.UpdateBlurParticles then
        CheatEnv.UpdateBlurParticles(dt)
    end

    UpdateESP()

    if Settings.Aimlock or AimlockRing.Visible or AimlockState.RMBHeld or AimlockState.Engaged then
        UpdateAimlock()
    end

    if Settings.Aimbot or FOVRing.Visible or TargetIndicator.Circle.Visible or AimbotState.RMBHeld or AimbotState.Engaged then
        UpdateAimbot()
    end

    if CheatEnv.UpdateAutoShot then
        CheatEnv.UpdateAutoShot()
    end

    if Settings.NoRecoil then
        ApplyNoRecoil(dt)
    end
end))

UpdateKeybindList()
UpdateTeamCheckDependencies() -- Apply initial state
UpdateESPBoxDependencies()    -- Apply initial state
UpdatePredictionDependencies()

-- AUTO-LOAD DEFAULT CONFIG ON STARTUP
do
    ConfigSystem.DefaultConfigName = ConfigSystem.GetDefault()
    if ConfigSystem.DefaultConfigName then
        if isfile and isfile(ConfigSystem.Path .. ConfigSystem.DefaultConfigName .. ".json") then
            if ConfigSystem.Load(ConfigSystem.DefaultConfigName) then
                print("✓ Auto-loaded default config: " .. ConfigSystem.DefaultConfigName)
            end
        end
    end
    -- Initialize config list UI
    if ConfigSystem.UpdateUI then
        ConfigSystem.UpdateUI()
    end
end

print("✓ VAYS v6.8 (CB MASTER UPDATE) Loaded successfully.")
 
