--[[
    Module: REZOLVER Silent Aim V6 (ULTIMATE STABLE)
    Fixes: "Argument #3 (boolean expected)" crash, Mouse Hook bug
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")

-- Ссылка на локальные объекты
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- Инициализация конфига с жесткими дефолтами (защита от nil)
local function GetSafeConfig()
    local g = getgenv().RezolverSilent or {}
    return {
        Enabled = g.Enabled or false,
        TargetPart = g.TargetPart or "Head",
        Prediction = g.Prediction or 0.155,
        AutoPredict = (g.AutoPredict == true),
        GravPredict = (g.GravPredict == true),
        UseFOV = (g.UseFOV == true),
        FOVSize = g.FOVSize or 50,
        Resolver = (g.Resolver == true),
        WallCheck = (g.WallCheck == true),
        ShowFOV = (g.ShowFOV == true),
        FOVColor = g.FOVColor or Color3.fromRGB(255, 255, 255),
        DebugMode = (g.DebugMode == true)
    }
end

local State = { Target = nil, ResolvedVelocities = {}, IsClicking = false }

-- Создание FOV (Rage)
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1
FOVCircle.NumSides = 64
FOVCircle.Filled = false

-- Дебаг текст
local DebugText = Drawing.new("Text")
DebugText.Size = 16
DebugText.Color = Color3.fromRGB(0, 255, 0)
DebugText.Outline = true
DebugText.Position = Vector2.new(15, 300)

local function IsValidTarget(char)
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local be = char:FindFirstChild("BodyEffects")
    if be and be:FindFirstChild("K.O") and be["K.O"].Value then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp.Position.Y < -50 then return false end
    return true
end

local function IsVisible(targetPart)
    local cam = Workspace.CurrentCamera
    if not cam or not targetPart then return false end
    
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character, cam}
    params.IgnoreWater = true
    
    local result = Workspace:Raycast(cam.CFrame.Position, targetPart.Position - cam.CFrame.Position, params)
    if result and result.Instance then
        if result.Instance:IsDescendantOf(targetPart.Parent) then return true end
        if result.Instance.Transparency > 0.4 or result.Instance.CanCollide == false then return true end
        return false
    end
    return true
end

-- Резольвер (История скоростей)
RunService.Heartbeat:Connect(function(dt)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = player.Character.HumanoidRootPart
            local data = State.ResolvedVelocities[player] or { LastPos = hrp.Position, Velocity = Vector3.new(0,0,0), History = {} }
            
            local currentVel = (hrp.Position - data.LastPos) / dt
            table.insert(data.History, 1, currentVel)
            if #data.History > 5 then table.remove(data.History, 6) end
            
            local avg = Vector3.new(0,0,0)
            for _, v in ipairs(data.History) do avg = avg + v end
            data.Velocity = avg / #data.History
            data.LastPos = hrp.Position
            State.ResolvedVelocities[player] = data
        end
    end
end)

-- Основной цикл
RunService.RenderStepped:Connect(function()
    local Cfg = GetSafeConfig()
    local Camera = Workspace.CurrentCamera
    local mPos = UserInputService:GetMouseLocation()

    -- Обновляем кружок
    FOVCircle.Position = mPos
    FOVCircle.Radius = Cfg.FOVSize
    FOVCircle.Color = Cfg.FOVColor
    FOVCircle.Visible = Cfg.Enabled and Cfg.ShowFOV
    
    -- Поиск цели
    local closest, shortestDist = nil, math.huge
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and IsValidTarget(p.Character) and p.Character:FindFirstChild(Cfg.TargetPart) then
            local part = p.Character[Cfg.TargetPart]
            local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
            if onScreen then
                local dist = (Vector2.new(pos.X, pos.Y) - mPos).Magnitude
                if (not Cfg.UseFOV or dist <= Cfg.FOVSize) and (not Cfg.WallCheck or IsVisible(part)) then
                    if dist < shortestDist then
                        shortestDist = dist
                        closest = p.Character
                    end
                end
            end
        end
    end
    State.Target = closest

    -- Дебаг
    if Cfg.DebugMode then
        DebugText.Visible = true
        DebugText.Text = string.format("[REZOLVER V6]\nTarget: %s\nVisible: %s\nSilent: %s", 
            State.Target and State.Target.Name or "None",
            tostring(State.Target ~= nil),
            tostring(Cfg.Enabled)
        )
    else
        DebugText.Visible = false
    end
end)

-- ХИТБОКС МАГИЯ
local function GetPredPos()
    local Cfg = GetSafeConfig()
    if not State.Target then return nil end
    local part = State.Target:FindFirstChild(Cfg.TargetPart)
    local hum = State.Target:FindFirstChild("Humanoid")
    if not part or not hum then return nil end

    local vel = part.AssemblyLinearVelocity
    if Cfg.Resolver and State.ResolvedVelocities[Players:GetPlayerFromCharacter(State.Target)] then
        vel = State.ResolvedVelocities[Players:GetPlayerFromCharacter(State.Target)].Velocity
    end

    local ping = 50
    pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    local pred = Cfg.AutoPredict and (0.11 + (ping/1000) * 0.4) or Cfg.Prediction
    
    local pos = part.Position + (vel * pred)
    if Cfg.GravPredict and hum:GetState() == Enum.HumanoidStateType.Freefall then
        pos = pos - Vector3.new(0, (Workspace.Gravity * 0.5 * (pred^2)), 0)
    end
    return pos
end

-- КРЮКИ (HOOKS)
local OldNC; OldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    local Cfg = GetSafeConfig()

    if Cfg.Enabled and State.Target and not checkcaller() and method == "FireServer" and tostring(self) == "MainEvent" then
        if args[1] == "UpdateMousePos" or args[1] == "MousePos" then
            local p = GetPredPos()
            if p then args[2] = p return OldNC(self, unpack(args)) end
        end
    end
    return OldNC(self, ...)
end))

local OldIdx; OldIdx = hookmetamethod(game, "__index", newcclosure(function(self, key)
    local Cfg = GetSafeConfig()
    if Cfg.Enabled and State.Target and not checkcaller() then
        if typeof(self) == "Instance" and self:IsA("PlayerMouse") then
            local p = GetPredPos()
            if p then
                if key == "Hit" then return CFrame.new(p) end
                if key == "Target" then return State.Target:FindFirstChild(Cfg.TargetPart) end
            end
        end
    end
    return OldIdx(self, key)
end))

print("[REZOLVER] Silent Aim V6 Loaded.")
