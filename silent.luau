local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local function GetCfg()
    local g = getgenv().RezolverSilent or {}
    return {
        Enabled = g.Enabled or false,
        TargetPart = g.TargetPart or "Head",
        Prediction = g.Prediction or 0.08,
        AutoPredict = (g.AutoPredict == true),
        GravPredict = (g.GravPredict == true),
        UseFOV = (g.UseFOV == true),
        FOVSize = g.FOVSize or 50,
        Resolver = (g.Resolver ~= false),
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

local function UpdatePrediction()
    local Cfg = GetCfg()
    if not State.Target then 
        State.PredictedPos = nil
        State.PredictedCFrame = nil
        return 
    end
    
    local part = State.Target:FindFirstChild(Cfg.TargetPart)
    if not part then return end

    -- Всегда используем резольвер (точнее чем AssemblyLinearVelocity)
    local vel = Vector3.new(0, 0, 0)
    local p = Players:GetPlayerFromCharacter(State.Target)
    if p and State.ResolvedVelocities[p] then 
        vel = State.ResolvedVelocities[p].Velocity 
    end

    -- Правильный расчёт пинга (RTT / 2)
    local ping = 50
    pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    local pingSec = (ping / 1000) / 2
    local pred = Cfg.AutoPredict and (0.05 + pingSec) or Cfg.Prediction
    
    local pos = part.Position + (vel * pred)
    
    -- GravPredict только если реально падает
    local hum = State.Target:FindFirstChild("Humanoid")
    if Cfg.GravPredict and hum and hum:GetState() == Enum.HumanoidStateType.Freefall then
        local fallSpeed = math.abs(vel.Y)
        if fallSpeed > 5 then
            pos = pos - Vector3.new(0, (Workspace.Gravity * 0.5 * (pred^2)), 0)
        end
    end
    
    State.PredictedPos = pos
    State.PredictedCFrame = CFrame.new(pos)

    -- Экспортируем данные для HitChance
    local p = Players:GetPlayerFromCharacter(State.Target)
    if p then
    local speed = vel.Magnitude
    local dist = (State.Target:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")) and (State.Target.HumanoidRootPart.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude or 0
    
    local chance = 100
    chance = chance - math.clamp(dist * 0.15, 0, 40)
    chance = chance - math.clamp(speed * 0.4, 0, 35)
    chance = chance - math.clamp((ping/1000) * 30, 0, 20)
    getgenv().RezolverSilent.LastHitChance = math.clamp(math.floor(chance), 5, 99)
end

-- Поиск цели
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
    if Cfg.Enabled and not checkcaller() and State.Target and State.PredictedCFrame then
        if typeof(self) == "Instance" and self:IsA("PlayerMouse") then
            if key == "Hit" or key == "hit" then
                return State.PredictedCFrame
            elseif key == "Target" or key == "target" then
                return State.Target:FindFirstChild(Cfg.TargetPart)
            end
        end
    end
    return OldIdx(self, key)
end))

print("[REZOLVER] Silent Aim V8 Loaded. Ultimate Stability.")
