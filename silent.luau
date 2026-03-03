--[[
    Module: REZOLVER Silent Aim V5 (DEBUG EDITION)
    Game: Da Hood
]]
local clref = cloneref or function(obj) return obj end
local cmpinst = compareinstances or function(a, b) return a == b end

local Players = clref(game:GetService("Players"))
local RunService = clref(game:GetService("RunService"))
local UserInputService = clref(game:GetService("UserInputService"))
local Workspace = clref(game:GetService("Workspace"))
local Stats = clref(game:GetService("Stats"))

local LocalPlayer = clref(Players.LocalPlayer)
local Mouse = clref(LocalPlayer:GetMouse())

getgenv().RezolverSilent = getgenv().RezolverSilent or {
    Enabled = true,
    TargetPart = "Head",
    Prediction = 0.155,
    AutoPredict = true,
    GravPredict = true,
    UseFOV = true,
    FOVSize = 50,
    Resolver = true,
    WallCheck = false,
    ShowFOV = true,
    FOVColor = Color3.fromRGB(80, 105, 255),
    DebugMode = true -- ВКЛЮЧЕН РЕЖИМ ОТЛАДКИ
}
local Cfg = getgenv().RezolverSilent
local State = { Target = nil, ResolvedVelocities = {}, IsClicking = false }

local FOVCircle = Drawing.new("Circle")
FOVCircle.Thickness = 1
FOVCircle.NumSides = 64
FOVCircle.Filled = false
FOVCircle.Transparency = 0.8

-- ВИЗУАЛЬНЫЙ ДЕБАГГЕР (Текст на экране)
local DebugText = Drawing.new("Text")
DebugText.Size = 16
DebugText.Color = Color3.fromRGB(0, 255, 0)
DebugText.Outline = true
DebugText.Position = Vector2.new(15, 300)
DebugText.Visible = Cfg.DebugMode

local function IsValidTarget(char)
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum or hum.Health <= 0 then return false end
    local be = char:FindFirstChild("BodyEffects")
    if be then
        if be:FindFirstChild("K.O") and be["K.O"].Value then return false end
        if be:FindFirstChild("Dead") and be["Dead"].Value then return false end
    end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp.Position.Y < -50 then return false end
    return true
end

local function IsVisible(targetPart)
    if not targetPart then return false end
    local camPos = Workspace.CurrentCamera.CFrame.Position
    local partPos = targetPart.Position
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character, Workspace.CurrentCamera}
    params.IgnoreWater = true
    
    local result = Workspace:Raycast(camPos, partPos - camPos, params)
    if result and result.Instance then
        if result.Instance:IsDescendantOf(targetPart.Parent) then return true end
        if result.Instance.Transparency > 0.4 or not result.Instance.CanCollide then return true end
        return false 
    end
    return true
end

local function GetPing()
    local ping = 50 
    pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    return ping
end

RunService.Heartbeat:Connect(function(dt)
    for _, player in ipairs(Players:GetPlayers()) do
        if not cmpinst(player, LocalPlayer) and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = player.Character.HumanoidRootPart
            if not State.ResolvedVelocities[player] then
                State.ResolvedVelocities[player] = { LastPos = hrp.Position, Velocity = Vector3.new(0,0,0), History = {} }
            else
                local data = State.ResolvedVelocities[player]
                local currentVel = (hrp.Position - data.LastPos) / dt
                table.insert(data.History, 1, currentVel)
                if #data.History > 5 then table.remove(data.History, 6) end
                local avgVel = Vector3.new(0, 0, 0)
                for _, v in ipairs(data.History) do avgVel = avgVel + v end
                data.Velocity = avgVel / #data.History
                data.LastPos = hrp.Position
            end
        end
    end
end)

local function GetTarget()
    local closest = nil
    local shortestDist = math.huge 
    local mPos = UserInputService:GetMouseLocation()
    local Camera = Workspace.CurrentCamera

    for _, p in pairs(Players:GetPlayers()) do
        if not cmpinst(p, LocalPlayer) and IsValidTarget(p.Character) and p.Character:FindFirstChild(Cfg.TargetPart) then
            local part = p.Character[Cfg.TargetPart]
            local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
            if onScreen then
                local distToMouse = (Vector2.new(pos.X, pos.Y) - mPos).Magnitude
                if not Cfg.UseFOV or distToMouse <= Cfg.FOVSize then
                    local visible = true
                    if Cfg.WallCheck then visible = IsVisible(part) end
                    
                    if visible and distToMouse < shortestDist then
                        shortestDist = distToMouse
                        closest = p.Character
                    end
                end
            end
        end
    end
    return closest
end

local function GetPredictedPosition()
    if not State.Target or not State.Target:FindFirstChild(Cfg.TargetPart) then return nil end
    local part = State.Target[Cfg.TargetPart]
    local targetHum = State.Target:FindFirstChild("Humanoid")
    local targetPlayer = Players:GetPlayerFromCharacter(State.Target)
    
    local velocity = part.AssemblyLinearVelocity
    if Cfg.Resolver and targetPlayer and State.ResolvedVelocities[targetPlayer] then
        velocity = State.ResolvedVelocities[targetPlayer].Velocity
    end

    local currentPred = Cfg.AutoPredict and math.clamp(0.11 + (GetPing() / 1000) * 0.4, 0.1, 0.25) or Cfg.Prediction
    local gravityCompensation = Vector3.new(0, 0, 0)
    
    if Cfg.GravPredict and targetHum and targetHum:GetState() == Enum.HumanoidStateType.Freefall then
        gravityCompensation = Vector3.new(0, (Workspace.Gravity * 0.5 * (currentPred ^ 2)), 0)
    end

    return part.Position + (velocity * currentPred) - gravityCompensation
end

RunService.RenderStepped:Connect(function()
    FOVCircle.Position = UserInputService:GetMouseLocation()
    FOVCircle.Radius = Cfg.FOVSize
    FOVCircle.Color = Cfg.FOVColor
    FOVCircle.Visible = Cfg.Enabled and Cfg.ShowFOV and Cfg.UseFOV
    State.Target = Cfg.Enabled and GetTarget() or nil

    -- ОБНОВЛЕНИЕ ВИЗУАЛЬНОГО ДЕБАГА
    if Cfg.DebugMode then
        DebugText.Visible = true
        local targetName = State.Target and State.Target.Name or "NONE"
        local dist = "0"
        if State.Target and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            dist = tostring(math.floor((State.Target[Cfg.TargetPart].Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude))
        end
        local currentPred = Cfg.AutoPredict and math.clamp(0.11 + (GetPing() / 1000) * 0.4, 0.1, 0.25) or Cfg.Prediction
        
        DebugText.Text = string.format(
            "[ REZOLVER SILENT DEBUG ]\nTarget: %s\nDistance: %s studs\nPing: %d ms\nPredict: %.3f\nWallCheck: %s",
            targetName, dist, GetPing(), currentPred, tostring(Cfg.WallCheck)
        )
    else
        DebugText.Visible = false
    end
end)

-- ОТСЛЕЖИВАЕМ КЛИК (Для дебаггера в консоль)
UserInputService.InputBegan:Connect(function(i, gp)
    if not gp and i.UserInputType == Enum.UserInputType.MouseButton1 then
        State.IsClicking = true
    end
end)
UserInputService.InputEnded:Connect(function(i, gp)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        State.IsClicking = false
    end
end)

--========================================================
--[ THE PERFECT SILENT HOOKS & DEBUG LOGS ]
--========================================================
local OldNamecall
local OldIndex

if hookmetamethod and newcclosure then
    OldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        -- Сниффер пакетов при клике мышки (Чтобы понять, чем стреляет оружие)
        if Cfg.DebugMode and State.IsClicking and not checkcaller() and method == "FireServer" then
            if tostring(self) == "MainEvent" then
                print("[DEBUG] MainEvent FireServer called with arg1:", tostring(args[1]))
            end
        end

        if Cfg.Enabled and not checkcaller() and State.Target and method == "FireServer" and tostring(self) == "MainEvent" then
            if type(args[1]) == "string" and (string.find(args[1], "MousePos") or string.find(args[1], "UpdateMousePos")) then
                local predictedPos = GetPredictedPosition()
                if predictedPos then
                    if Cfg.DebugMode and State.IsClicking then
                        print("[DEBUG] SUCCESS: Spoofed UpdateMousePos to Target Head!")
                    end
                    args[2] = predictedPos 
                    return OldNamecall(self, unpack(args))
                end
            end
        end
        return OldNamecall(self, ...)
    end))

    OldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
        if Cfg.Enabled and not checkcaller() and State.Target and (typeof(self) == "Instance" and self:IsA("PlayerMouse")) then
            local predictedPos = GetPredictedPosition()
            if predictedPos then
                if key == "Hit" or key == "hit" then
                    if Cfg.DebugMode and State.IsClicking then print("[DEBUG] Hooked Mouse.Hit") end
                    return CFrame.new(predictedPos)
                elseif key == "Target" or key == "target" then
                    return State.Target:FindFirstChild(Cfg.TargetPart)
                elseif key == "X" or key == "x" then
                    local screen, _ = Workspace.CurrentCamera:WorldToScreenPoint(predictedPos)
                    return screen.X
                elseif key == "Y" or key == "y" then
                    local screen, _ = Workspace.CurrentCamera:WorldToScreenPoint(predictedPos)
                    return screen.Y
                elseif key == "UnitRay" then
                    local camPos = Workspace.CurrentCamera.CFrame.Position
                    return Ray.new(camPos, (predictedPos - camPos).Unit)
                end
            end
        end
        return OldIndex(self, key)
    end))
end

print("[REZOLVER] Silent Aim V5 (DEBUG EDITION) Loaded.")
