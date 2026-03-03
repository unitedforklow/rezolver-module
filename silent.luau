--[[
    Module: REZOLVER Silent Aim V7 (BUG FIX)
    Fixes: "index boolean with p", GunClient arithmetic error.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

-- Безопасное получение конфига (без nil)
local function GetCfg()
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
        FOVColor = g.FOVColor or Color3.fromRGB(255, 255, 255)
    }
end

local State = { Target = nil, ResolvedVelocities = {} }

-- Отрисовка FOV
local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1
FOVCircle.NumSides = 64
FOVCircle.Visible = false

local function IsValid(char)
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local be = char:FindFirstChild("BodyEffects")
    if be and be:FindFirstChild("K.O") and be["K.O"].Value then return false end
    return true
end

-- WALL CHECK (Raycast)
local function IsVisible(targetPart)
    local cam = Workspace.CurrentCamera
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character, cam}
    local result = Workspace:Raycast(cam.CFrame.Position, targetPart.Position - cam.CFrame.Position, params)
    return (result == nil or result.Instance:IsDescendantOf(targetPart.Parent))
end

-- Резольвер
RunService.Heartbeat:Connect(function(dt)
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = player.Character.HumanoidRootPart
            local data = State.ResolvedVelocities[player] or { LastPos = hrp.Position, Velocity = Vector3.new(0,0,0) }
            data.Velocity = (hrp.Position - data.LastPos) / dt
            data.LastPos = hrp.Position
            State.ResolvedVelocities[player] = data
        end
    end
end)

-- Поиск цели в RenderStepped (для точности)
RunService.RenderStepped:Connect(function()
    local Cfg = GetCfg()
    local Camera = Workspace.CurrentCamera
    local mPos = UserInputService:GetMouseLocation()

    FOVCircle.Position = mPos
    FOVCircle.Radius = Cfg.FOVSize
    FOVCircle.Visible = Cfg.Enabled and Cfg.ShowFOV
    
    local closest, shortestDist = nil, math.huge
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and IsValid(p.Character) and p.Character:FindFirstChild(Cfg.TargetPart) then
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
end)

-- Расчет точки попадания
local function GetHitPos()
    local Cfg = GetCfg()
    if not State.Target then return nil end
    local part = State.Target:FindFirstChild(Cfg.TargetPart)
    if not part then return nil end

    local vel = part.AssemblyLinearVelocity
    if Cfg.Resolver and State.ResolvedVelocities[Players:GetPlayerFromCharacter(State.Target)] then
        vel = State.ResolvedVelocities[Players:GetPlayerFromCharacter(State.Target)].Velocity
    end

    local ping = 50
    pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    local pred = Cfg.AutoPredict and (0.11 + (ping/1000) * 0.4) or Cfg.Prediction
    
    local pos = part.Position + (vel * pred)
    -- Гравитация
    if Cfg.GravPredict and State.Target.Humanoid:GetState() == Enum.HumanoidStateType.Freefall then
        pos = pos - Vector3.new(0, (Workspace.Gravity * 0.5 * (pred^2)), 0)
    end
    return pos
end

--========================================================
--[ THE ONLY SAFE HOOK (NAME CALL) ]
--========================================================
local OldNC; OldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    local Cfg = GetCfg()

    -- Мы перехватываем ТОЛЬКО пакет UpdateMousePos, летящий на сервер
    if Cfg.Enabled and not checkcaller() and method == "FireServer" and tostring(self) == "MainEvent" then
        if args[1] == "UpdateMousePos" or args[1] == "MousePos" then
            local p = GetHitPos()
            if p then
                args[2] = p -- Подменяем только аргумент позиции
                return OldNC(self, unpack(args))
            end
        end
    end
    return OldNC(self, ...)
end))

print("[REZOLVER] Silent Aim V7 Loaded. Hooks cleaned.")
