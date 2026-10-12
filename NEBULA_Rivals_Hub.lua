-- NEBULA | Rivals Hub v1.0 RC - personal-use client-side build
-- No key system, external dependencies, or automatic network requests.
-- Combat features are best-effort; game-specific weapon systems may not respond.
-- Silent aim and server-side cosmetic/weapon unlocks are NOT implemented.

if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local UserInputService = game:GetService('UserInputService')
local TweenService = game:GetService('TweenService')
local Workspace = game:GetService('Workspace')
local HttpService = game:GetService('HttpService')
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local mouse = LocalPlayer:GetMouse()

local old = getgenv and getgenv().NEBULA_RIVALS
if old and old.Destroy then pcall(old.Destroy) end

local cfg = {
    Aim = false, Trigger = false, Rage = false, ESP = false,
    AimPart = 'Head', FOV = 170, Smooth = 0.28, MaxDistance = 700,
    TeamCheck = true, WallCheck = true, TriggerDelay = 0.08,
    RageFire = true, ShowFOV = true, Prediction = 0, ESPFill = 0.78, ESPOutline = 0.05,
    ESPColor = Color3.fromRGB(110, 156, 255),
}
local configFile = 'NEBULA_RIVALS_config.json'
local defaults = table.clone(cfg)
local refreshers = {}
local displayAlias = 'NEBULA User'
local function saveConfig()
    if type(writefile) ~= 'function' then return false, 'Executor does not support writefile' end
    local data = {}
    for k,v in pairs(cfg) do
        if typeof(v) == 'Color3' then data[k] = {__color = {math.floor(v.R*255+.5),math.floor(v.G*255+.5),math.floor(v.B*255+.5)}}
        else data[k] = v end
    end
    data.DisplayAlias = displayAlias
    local ok,err = pcall(function() writefile(configFile,HttpService:JSONEncode(data)) end)
    return ok, err
end
local function loadConfig()
    if type(readfile) ~= 'function' then return false, 'Executor does not support readfile' end
    local ok,data = pcall(function() return HttpService:JSONDecode(readfile(configFile)) end)
    if not ok or type(data) ~= 'table' then return false, 'No readable config file' end
    for k,default in pairs(defaults) do
        local value = data[k]
        if typeof(default) == 'Color3' and type(value)=='table' and type(value.__color)=='table' then
            local c=value.__color
            if type(c[1])=='number' and type(c[2])=='number' and type(c[3])=='number' then cfg[k]=Color3.fromRGB(math.clamp(c[1],0,255),math.clamp(c[2],0,255),math.clamp(c[3],0,255)) end
        elseif typeof(value)==typeof(default) then
            if type(default)=='number' then
                if value == value and value ~= math.huge and value ~= -math.huge then
                    local limits = {FOV={30,500}, Smooth={.05,1}, MaxDistance={100,2000}, TriggerDelay={.04,.5}, Prediction={0,.3}, ESPFill={0,1}, ESPOutline={0,1}}
                    local range = limits[k]
                    cfg[k] = range and math.clamp(value,range[1],range[2]) or value
                end
            elseif k == 'AimPart' then
                if value == 'Head' or value == 'HumanoidRootPart' then cfg[k]=value end
            else cfg[k]=value end
        end
    end
    if type(data.DisplayAlias)=='string' then displayAlias=string.sub(data.DisplayAlias,1,32) end
    for _,refresh in ipairs(refreshers) do refresh() end
    return true
end
local alive = true
local connections = {}
local highlights = {}
local lastFire = 0
local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end
local function characterOf(player)
    local char = player.Character
    local humanoid = char and char:FindFirstChildOfClass('Humanoid')
    if not char or not humanoid or humanoid.Health <= 0 then return nil end
    return char
end
local function targetPart(char)
    return char:FindFirstChild(cfg.AimPart) or char:FindFirstChild('HumanoidRootPart')
end
local function predictedPosition(part)
    local root = part.Parent and part.Parent:FindFirstChild('HumanoidRootPart')
    local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
    return part.Position + velocity * cfg.Prediction
end
local function enemy(player)
    if player == LocalPlayer then return false end
    if cfg.TeamCheck and LocalPlayer.Team and player.Team == LocalPlayer.Team then return false end
    return characterOf(player) ~= nil
end
local function visible(part, char)
    if not cfg.WallCheck then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {LocalPlayer.Character, Camera}
    local origin = Camera.CFrame.Position
    local hit = Workspace:Raycast(origin, part.Position - origin, params)
    return not hit or hit.Instance:IsDescendantOf(char)
end
local function findTarget(useFOV)
    Camera = Workspace.CurrentCamera
    local center = Camera.ViewportSize * 0.5
    local best, bestDist = nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if enemy(player) then
            local char = player.Character
            local part = targetPart(char)
            if part then
                local distance = (part.Position - Camera.CFrame.Position).Magnitude
                if distance <= cfg.MaxDistance then
                    local screen, onscreen = Camera:WorldToViewportPoint(predictedPosition(part))
                    if onscreen and visible(part, char) then
                        local pixels = (Vector2.new(screen.X, screen.Y) - center).Magnitude
                        if (not useFOV or pixels <= cfg.FOV) and pixels < bestDist then
                            best, bestDist = part, pixels
                        end
                    end
                end
            end
        end
    end
    return best
end
local function fire()
    if os.clock() - lastFire < cfg.TriggerDelay then return end
    lastFire = os.clock()
    -- Executor-specific mouse functions may be unavailable.
    if type(mouse1press) == 'function' and type(mouse1release) == 'function' then
        pcall(mouse1press)
        task.delay(0.035, function() if alive then pcall(mouse1release) end end)
    elseif type(mouse1click) == 'function' then
        pcall(mouse1click)
    end
end

local gui = Instance.new('ScreenGui')
gui.Name = 'NEBULA_RIVALS_HUB'
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = game:GetService('CoreGui') end)
if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild('PlayerGui') end

local function round(parent, px)
    local c = Instance.new('UICorner'); c.CornerRadius = UDim.new(0, px); c.Parent = parent
end
local function stroke(parent, color, transparency)
    local s = Instance.new('UIStroke'); s.Color = color; s.Transparency = transparency or 0; s.Thickness = 1; s.Parent = parent
end
local function text(parent, value, size, color, bold)
    local t = Instance.new('TextLabel')
    t.BackgroundTransparency = 1; t.Text = value; t.TextSize = size
    t.TextColor3 = color or Color3.fromRGB(229,234,250)
    t.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Parent = parent
    return t
end
local main = Instance.new('Frame')
main.Name = 'Main'; main.Size = UDim2.fromOffset(680, 455)
main.Position = UDim2.new(0.5, -340, 0.5, -227)
main.BackgroundColor3 = Color3.fromRGB(12, 17, 32); main.Parent = gui
round(main, 16); stroke(main, Color3.fromRGB(63,79,124), .4)
local gradient = Instance.new('UIGradient')
gradient.Color = ColorSequence.new(Color3.fromRGB(24, 33, 60), Color3.fromRGB(9, 13, 25))
gradient.Rotation = 28; gradient.Parent = main
local header = Instance.new('Frame')
header.Size = UDim2.new(1,0,0,70); header.BackgroundTransparency = 1; header.Parent = main
local title = text(header, '✦  N E B U L A', 23, Color3.fromRGB(218,230,255), true)
title.Position = UDim2.fromOffset(24,14); title.Size = UDim2.fromOffset(320,30)
local subtitle = text(header, 'RIVALS  /  PRIVATE BUILD  /  v1.0', 10, Color3.fromRGB(122,151,207), true)
subtitle.Position = UDim2.fromOffset(26,43); subtitle.Size = UDim2.fromOffset(360,16)
local close = Instance.new('TextButton')
close.Size = UDim2.fromOffset(34,30); close.Position = UDim2.new(1,-48,0,18)
close.Text = '×'; close.TextSize = 24; close.TextColor3 = Color3.fromRGB(193,204,230)
close.BackgroundColor3 = Color3.fromRGB(36,47,74); close.Parent = header
round(close,8)
local divider = Instance.new('Frame')
divider.Position = UDim2.fromOffset(0,70); divider.Size = UDim2.new(1,0,0,1)
divider.BackgroundColor3 = Color3.fromRGB(56,74,117); divider.BorderSizePixel = 0; divider.Parent = main
local sidebar = Instance.new('Frame')
sidebar.Position = UDim2.fromOffset(15,88); sidebar.Size = UDim2.fromOffset(152,346)
sidebar.BackgroundColor3 = Color3.fromRGB(16,23,42); sidebar.Parent = main
round(sidebar, 12); stroke(sidebar, Color3.fromRGB(64,85,130),.75)
local content = Instance.new('Frame')
content.Position = UDim2.fromOffset(180,88); content.Size = UDim2.fromOffset(482,346)
content.BackgroundColor3 = Color3.fromRGB(16,23,42); content.Parent = main
round(content,12); stroke(content,Color3.fromRGB(64,85,130),.75)
local pages = {}; local buttons = {}
local names = {'Combat','Visuals','Cosmetics','Settings','About'}
for i, name in ipairs(names) do
    local b = Instance.new('TextButton')
    b.Size = UDim2.fromOffset(132,42); b.Position = UDim2.fromOffset(10,12+(i-1)*50)
    b.BackgroundColor3 = Color3.fromRGB(23,32,55)
    b.Text = '   '..name; b.TextXAlignment = Enum.TextXAlignment.Left
    b.Font = Enum.Font.GothamMedium; b.TextSize = 13
    b.TextColor3 = Color3.fromRGB(164,182,220); b.Parent = sidebar
    round(b,9); buttons[name] = b
    local page = Instance.new('ScrollingFrame')
    page.Size = UDim2.new(1,-24,1,-22); page.Position = UDim2.fromOffset(12,11)
    page.BackgroundTransparency = 1; page.BorderSizePixel = 0
    page.ScrollBarThickness = 3; page.ScrollBarImageColor3 = Color3.fromRGB(98,133,209)
    page.CanvasSize = UDim2.fromOffset(0,0); page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false; page.Parent = content; pages[name] = page
    local layout = Instance.new('UIListLayout')
    layout.Padding = UDim.new(0,9); layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Parent = page
end
local function selectPage(name)
    for key, page in pairs(pages) do
        page.Visible = key == name
        buttons[key].BackgroundColor3 = key == name and Color3.fromRGB(48,75,132) or Color3.fromRGB(23,32,55)
        buttons[key].TextColor3 = key == name and Color3.new(1,1,1) or Color3.fromRGB(164,182,220)
    end
end
for name,b in pairs(buttons) do connect(b.MouseButton1Click, function() selectPage(name) end) end
local function section(page, heading, description)
    local frame = Instance.new('Frame'); frame.Size = UDim2.new(1,-8,0,53)
    frame.BackgroundColor3 = Color3.fromRGB(25,35,59); frame.Parent = page
    round(frame,9)
    local a = text(frame,heading,14,Color3.fromRGB(226,236,255),true)
    a.Position = UDim2.fromOffset(13,7); a.Size = UDim2.new(1,-24,0,20)
    local d = text(frame,description,10,Color3.fromRGB(138,159,201))
    d.Position = UDim2.fromOffset(13,29); d.Size = UDim2.new(1,-24,0,16)
end
local function toggle(page, label, key)
    local line = Instance.new('Frame'); line.Size = UDim2.new(1,-8,0,40)
    line.BackgroundColor3 = Color3.fromRGB(25,35,59); line.Parent = page; round(line,9)
    local t = text(line,label,12,Color3.fromRGB(214,226,247),true)
    t.Position = UDim2.fromOffset(13,8); t.Size = UDim2.new(1,-95,0,24)
    local b = Instance.new('TextButton'); b.Size = UDim2.fromOffset(61,26)
    b.Position = UDim2.new(1,-72,0,7); b.Font = Enum.Font.GothamBold
    b.TextSize = 10; b.Parent = line; round(b,7)
    local function refresh()
        b.Text = cfg[key] and 'ON' or 'OFF'
        b.BackgroundColor3 = cfg[key] and Color3.fromRGB(66,117,210) or Color3.fromRGB(53,65,91)
        b.TextColor3 = Color3.new(1,1,1)
    end
    connect(b.MouseButton1Click,function() cfg[key] = not cfg[key]; refresh() end)
    table.insert(refreshers,refresh)
    refresh()
end
local function slider(page,label,key,minimum,maximum,step)
    local line = Instance.new('Frame'); line.Size = UDim2.new(1,-8,0,58)
    line.BackgroundColor3 = Color3.fromRGB(25,35,59); line.Parent = page; round(line,9)
    local t = text(line,label,12,Color3.fromRGB(214,226,247),true)
    t.Position = UDim2.fromOffset(13,7); t.Size = UDim2.new(1,-100,0,20)
    local value = text(line,tostring(cfg[key]),12,Color3.fromRGB(127,170,255),true)
    value.Position = UDim2.new(1,-85,0,7); value.Size = UDim2.fromOffset(70,20)
    value.TextXAlignment = Enum.TextXAlignment.Right
    local bar = Instance.new('Frame'); bar.Size = UDim2.new(1,-30,0,6)
    bar.Position = UDim2.fromOffset(15,39); bar.BackgroundColor3 = Color3.fromRGB(54,67,96)
    bar.Parent = line; round(bar,5)
    local fill = Instance.new('Frame'); fill.BackgroundColor3 = Color3.fromRGB(99,148,246)
    fill.Parent = bar; round(fill,5)
    local dragging = false
    local function update(pos)
        local alpha = math.clamp((pos-bar.AbsolutePosition.X)/math.max(1,bar.AbsoluteSize.X),0,1)
        local n = minimum + math.floor(((maximum-minimum)*alpha)/step + .5)*step
        cfg[key] = math.clamp(math.floor(n*100+.5)/100,minimum,maximum)
        value.Text = tostring(cfg[key]); fill.Size = UDim2.fromScale((cfg[key]-minimum)/(maximum-minimum),1)
    end
    local function refresh()
        value.Text = tostring(cfg[key])
        fill.Size = UDim2.fromScale(math.clamp((cfg[key]-minimum)/(maximum-minimum),0,1),1)
    end
    table.insert(refreshers,refresh)
    refresh()
    connect(bar.InputBegan,function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; update(input.Position.X)
        end
    end)
    connect(UserInputService.InputChanged,function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then update(input.Position.X) end
    end)
    connect(UserInputService.InputEnded,function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
end
local function buttonRow(page,label,callback)
    local b = Instance.new('TextButton'); b.Size = UDim2.new(1,-8,0,39)
    b.BackgroundColor3 = Color3.fromRGB(38,58,99); b.TextColor3 = Color3.fromRGB(224,236,255)
    b.TextSize = 12; b.Font = Enum.Font.GothamBold; b.Text = label; b.Parent = page; round(b,9)
    connect(b.MouseButton1Click,callback)
end
local function note(page, message)
    local t = text(page,message,11,Color3.fromRGB(145,164,202))
    t.Size = UDim2.new(1,-15,0,48); t.TextWrapped = true; t.TextYAlignment = Enum.TextYAlignment.Top
end
section(pages.Combat,'TARGETING ENGINE','Client-side aiming and input automation')
toggle(pages.Combat,'Aim Assist (hold RMB)','Aim')
toggle(pages.Combat,'Trigger Bot','Trigger')
toggle(pages.Combat,'Rage Mode (auto target)','Rage')
toggle(pages.Combat,'Auto Fire in Rage Mode','RageFire')
slider(pages.Combat,'FOV Radius (px)','FOV',30,500,10)
slider(pages.Combat,'Aim Smoothness','Smooth',.05,1,.05)
slider(pages.Combat,'Trigger Interval (s)','TriggerDelay',.04,.5,.02)
slider(pages.Combat,'Target Prediction (s)','Prediction',0,.3,.01)
buttonRow(pages.Combat,'Target Part: Head / Root',function()
    cfg.AimPart = cfg.AimPart == 'Head' and 'HumanoidRootPart' or 'Head'
end)
note(pages.Combat,'Silent aim requires game-specific shot logic and is not included in this build.')
section(pages.Visuals,'VISUAL TRACKING','Optional client-side player outlines')
toggle(pages.Visuals,'Player ESP','ESP')
toggle(pages.Visuals,'Show Aim FOV Circle','ShowFOV')
slider(pages.Visuals,'ESP Fill Transparency','ESPFill',0,1,.05)
slider(pages.Visuals,'ESP Outline Transparency','ESPOutline',0,1,.05)
note(pages.Visuals,'ESP uses Roblox Highlight instances. It does not reveal server-hidden entities.')
section(pages.Cosmetics,'APPEARANCE','Local-only interface customization')
note(pages.Cosmetics,'Server-authoritative weapon and skin unlocks cannot be reliably granted by a client script. This hub does not spoof ownership or purchases.')
buttonRow(pages.Cosmetics,'Switch UI Accent',function()
    cfg.ESPColor = cfg.ESPColor == Color3.fromRGB(110,156,255) and Color3.fromRGB(187,113,255) or Color3.fromRGB(110,156,255)
end)
section(pages.Settings,'PREFERENCES','Fine tune your targeting')
toggle(pages.Settings,'Team Check','TeamCheck')
toggle(pages.Settings,'Wall Check','WallCheck')
slider(pages.Settings,'Max Distance (studs)','MaxDistance',100,2000,50)
local status = text(pages.Settings,'Config: not saved',11,Color3.fromRGB(145,164,202))
status.Size = UDim2.new(1,-12,0,24)
buttonRow(pages.Settings,'Save Config',function()
    local ok,err=saveConfig();status.Text=ok and 'Config saved locally' or ('Save failed: '..tostring(err))
end)
buttonRow(pages.Settings,'Load Config',function()
    local ok,err=loadConfig();status.Text=ok and 'Config loaded' or ('Load failed: '..tostring(err))
end)
buttonRow(pages.Settings,'Reset Config',function()
    for k,v in pairs(defaults) do cfg[k]=v end
    displayAlias='NEBULA User'
    for _,refresh in ipairs(refreshers) do refresh() end
    status.Text='Defaults restored (save to persist)'
end)
local aliasBox=Instance.new('TextBox')
aliasBox.Size=UDim2.new(1,-8,0,38)
aliasBox.BackgroundColor3=Color3.fromRGB(25,35,59)
aliasBox.TextColor3=Color3.fromRGB(225,235,255)
aliasBox.PlaceholderText='Local display alias (UI only)'
aliasBox.Text=displayAlias
aliasBox.TextSize=12;aliasBox.Font=Enum.Font.Gotham
aliasBox.Parent=pages.Settings;round(aliasBox,9)
connect(aliasBox.FocusLost,function() displayAlias=string.sub(aliasBox.Text,1,32);aliasBox.Text=displayAlias end)
note(pages.Settings,'Display alias is cosmetic only; it does not change your Roblox identity.')
buttonRow(pages.Settings,'Disable Combat Features',function() cfg.Aim=false;cfg.Trigger=false;cfg.Rage=false end)
section(pages.About,'NEBULA / RIVALS','Private build • No key system')
note(pages.About,'Right Shift toggles the hub. Aim assist uses right mouse button. All features are best-effort and may be blocked by game/server protections.')
note(pages.About,'No external code is downloaded, no credentials are collected, and no weapon unlocks or silent-aim hooks are promised.')
selectPage('Combat')

local dragging, dragStart, startPos = false,nil,nil
connect(header.InputBegan,function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = input.Position; startPos = main.Position
    end
end)
connect(UserInputService.InputChanged,function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position-dragStart
        main.Position = UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,startPos.Y.Scale,startPos.Y.Offset+delta.Y)
    end
end)
connect(UserInputService.InputEnded,function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging=false end
end)
local function cleanup()
    alive = false
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    for _, h in pairs(highlights) do pcall(function() h:Destroy() end) end
    gui:Destroy()
end
connect(close.MouseButton1Click,cleanup)
connect(UserInputService.InputBegan,function(input,processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then main.Visible = not main.Visible end
end)

-- FOV ring uses standard Roblox UI, not executor drawing APIs.
local fovRing = Instance.new('Frame')
fovRing.Name = 'AimFOV'
fovRing.AnchorPoint = Vector2.new(.5,.5)
fovRing.BackgroundTransparency = 1
fovRing.BorderSizePixel = 0
fovRing.Parent = gui
local fovCorner = Instance.new('UICorner')
fovCorner.CornerRadius = UDim.new(1,0)
fovCorner.Parent = fovRing
local fovStroke = Instance.new('UIStroke')
fovStroke.Color = Color3.fromRGB(120,158,255)
fovStroke.Transparency = .25
fovStroke.Thickness = 1.5
fovStroke.Parent = fovRing
local espTimer = 0
connect(RunService.RenderStepped,function(dt)
    Camera = Workspace.CurrentCamera
    if not alive or not Camera then return end
    local viewport = Camera.ViewportSize
    fovRing.Visible = cfg.ShowFOV and (cfg.Aim or cfg.Rage)
    fovRing.Size = UDim2.fromOffset(cfg.FOV*2,cfg.FOV*2)
    fovRing.Position = UDim2.fromOffset(viewport.X/2,viewport.Y/2)
    if cfg.Rage or (cfg.Aim and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)) then
        local target = findTarget(not cfg.Rage)
        if target then
            local destination = CFrame.lookAt(Camera.CFrame.Position,predictedPosition(target))
            Camera.CFrame = Camera.CFrame:Lerp(destination,cfg.Rage and 1 or cfg.Smooth)
            if cfg.Rage and cfg.RageFire then fire() end
        end
    end
    if cfg.Trigger then
        local ray = Camera:ViewportPointToRay(Camera.ViewportSize.X/2,Camera.ViewportSize.Y/2)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {LocalPlayer.Character,Camera}
        local hit = Workspace:Raycast(ray.Origin,ray.Direction*cfg.MaxDistance,params)
        if hit then
            for _,player in ipairs(Players:GetPlayers()) do
                local char = enemy(player) and player.Character
                if char and hit.Instance:IsDescendantOf(char) then fire();break end
            end
        end
    end
    espTimer += dt
    if espTimer >= .4 then
        espTimer = 0
        for _,player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer then
                local char = enemy(player) and player.Character
                local h = highlights[player]
                if cfg.ESP and char then
                    if not h or h.Parent ~= char then
                        if h then h:Destroy() end
                        h = Instance.new('Highlight');h.Name = 'NebulaOutline'
                        h.FillTransparency = cfg.ESPFill;h.OutlineTransparency = cfg.ESPOutline
                        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        h.Parent = char; highlights[player] = h
                    end
                    h.FillColor = cfg.ESPColor; h.OutlineColor = cfg.ESPColor
                    h.FillTransparency = cfg.ESPFill; h.OutlineTransparency = cfg.ESPOutline
                elseif h then h:Destroy(); highlights[player] = nil end
            end
        end
    end
end)
if getgenv then getgenv().NEBULA_RIVALS = {Destroy=cleanup, Config=cfg, Save=saveConfig, Load=loadConfig} end
print('[NEBULA] Hub loaded. RightShift toggles GUI.')
