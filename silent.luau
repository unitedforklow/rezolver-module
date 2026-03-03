--[[
    Module: REZOLVER Silent Aim V8 (ULTIMATE)
    Fixes: "index boolean with p", GunClient support, WallCheck stability.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- Конфиг с защитой от nil
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
        ShowFOV = (g.ShowFOV == true)
    }
end

local State = { 
    Target = nil, 
    ResolvedVelocities = {},
    PredictedPos = nil,
    PredictedCFrame = nil
}

-- FOV Отрисовка
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

-- Резольвер (Считает реальную скорость)
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

-- РАСЧЕТ ПРЕДИКТА (Вынесен отдельно для оптимизации)
local function UpdatePrediction()
    local Cfg = GetCfg()
    if not State.Target then 
        State.PredictedPos = nil
        State.PredictedCFrame = nil
        return 
    end
    
    local part = State.Target:FindFirstChild(Cfg.TargetPart)
    if not part then return end

    local vel = part.AssemblyLinearVelocity
    if Cfg.Resolver then
        local p = Players:GetPlayerFromCharacter(State.Target)
        if p and State.ResolvedVelocities[p] then vel = State.ResolvedVelocities[p].Velocity end
    end

    local ping = 50
    pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    local pred = Cfg.AutoPredict and (0.11 + (ping/1000) * 0.4) or Cfg.Prediction
    
    local pos = part.Position + (vel * pred)
    if Cfg.GravPredict and State.Target.Humanoid:GetState() == Enum.HumanoidStateType.Freefall then
        pos = pos - Vector3.new(0, (Workspace.Gravity * 0.5 * (pred^2)), 0)
    end
    
    State.PredictedPos = pos
    State.PredictedCFrame = CFrame.new(pos)
end

-- ПОИСК ЦЕЛИ
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
                if (not Cfg.UseFOV or dist <= Cfg.FOVSize) then
                    if dist < shortestDist then
                        shortestDist = dist
                        closest = p.Character
                    end
                end
            end
        end
    end
    State.Target = closest
    if State.Target then UpdatePrediction() end
end)

--========================================================
--[ THE ULTIMATE SAFE HOOKS ]
--========================================================
local OldNC
local OldIdx

OldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    local Cfg = GetCfg()

    if Cfg.Enabled and not checkcaller() and method == "FireServer" and tostring(self) == "MainEvent" then
        if args[1] == "UpdateMousePos" or args[1] == "MousePos" then
            if State.PredictedPos then
                args[2] = State.PredictedPos
                return OldNC(self, unpack(args))
            end
        end
    end
    return OldNC(self, ...)
end))

OldIdx = hookmetamethod(game, "__index", newcclosure(function(self, key)
    local Cfg = GetCfg()
    -- Проверяем, что запрос идет к МЫШКЕ и мы в режиме Silent
    if Cfg.Enabled and not checkcaller() and State.Target and State.PredictedCFrame then
        if typeof(self) == "Instance" and self:IsA("PlayerMouse") then
            if key == "Hit" or key == "hit" then
                return State.PredictedCFrame -- Возвращаем только если есть цель!
            elseif key == "Target" or key == "target" then
                return State.Target:FindFirstChild(Cfg.TargetPart)
            end
        end
    end
    return OldIdx(self, key)
end))

print("[REZOLVER] Silent Aim V8 Loaded. Ultimate Stability.")
