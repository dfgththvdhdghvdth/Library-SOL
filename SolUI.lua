--!nolint LocalShadow
--[[
    SolUI  -  UI library in the SOL Hub v3 style
    ---------------------------------------------------------------------------------------------
    local SolUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/USER/REPO/main/SolUI.lua"))()
    local Window = SolUI:CreateWindow({ Title = "My Hub", Subtitle = "v1.0" })
    local Tab = Window:CreateTab({ Name = "Main", Icon = "home" })
    Tab:CreateToggle({ Name = "Example", Default = false, Flag = "Example", Callback = function(v) print(v) end })

    Built for a wide range of executors (Xeno, Delta, Solara, Wave, Fluxus, Synapse-like...):
    no compound assignments, no `continue`, no CanvasGroup, no weak tables holding instances,
    and every executor-specific function is optional and pcall-wrapped.
]]

local Library = {
    Version = "1.1.0",
    Flags = {},          -- Flag name -> current value
    Options = {},        -- Flag name -> element object
    Themes = {},         -- Theme name -> colour table
    ThemeOrder = {},     -- display order of the themes
    Windows = {},
    Theme = "Mono",
    NotificationsEnabled = true,
    Unloaded = false,
}

----------------------------------------------------------------------------------------------------
-- Compatibility layer
----------------------------------------------------------------------------------------------------

local unpackFn = (table and table.unpack) or unpack

-- task library fallback (very old / stripped environments)
local task = task
if type(task) ~= "table" or type(task.spawn) ~= "function" then
    task = {}
    task.spawn = function(f, ...)
        local co = coroutine.create(f)
        local ok, err = coroutine.resume(co, ...)
        if not ok then warn("[SolUI] " .. tostring(err)) end
        return co
    end
    task.defer = task.spawn
    task.wait = function(t) return wait(t) end
    task.delay = function(t, f, ...)
        local args = { n = select("#", ...), ... }
        return task.spawn(function()
            wait(t)
            f(unpackFn(args, 1, args.n))
        end)
    end
end

local Clock = (os and os.clock) or tick or function() return 0 end

local function ClearTable(t)
    if table.clear then
        table.clear(t)
    else
        for k in pairs(t) do t[k] = nil end
    end
end

local function PackArgs(...)
    return { n = select("#", ...), ... }
end

-- first argument that is a function (safe with nils in between)
local function FirstFn(...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "function" then return v end
    end
    return nil
end

local function SafeIndex(tbl, key)
    if type(tbl) ~= "table" then return nil end
    local ok, v = pcall(function() return tbl[key] end)
    if ok then return v end
    return nil
end

local env
if type(getgenv) == "function" then
    local ok, e = pcall(getgenv)
    if ok and type(e) == "table" then env = e end
end
if not env and type(_G) == "table" then env = _G end
if not env or not pcall(function() env.__SolUI_probe = true; env.__SolUI_probe = nil end) then
    env = {}
end

local function Service(name)
    local ok, s = pcall(function() return game:GetService(name) end)
    if not ok or not s then return nil end
    local clone = FirstFn(cloneref, SafeIndex(env, "cloneref"))
    if clone then
        local ok2, c = pcall(clone, s)
        if ok2 and typeof(c) == "Instance" then return c end
    end
    return s
end

pcall(function()
    if not game:IsLoaded() then game.Loaded:Wait() end
end)

local Players          = Service("Players")
local TweenService     = Service("TweenService")
local UserInputService = Service("UserInputService")
local HttpService      = Service("HttpService")
local Workspace        = Service("Workspace") or workspace

-- LocalPlayer is read through pcall: Players can be missing or still loading on some executors
local function ReadLocalPlayer()
    if not Players then return nil end
    local ok, p = pcall(function() return Players.LocalPlayer end)
    if ok and typeof(p) == "Instance" then return p end
    return nil
end
local LocalPlayer = ReadLocalPlayer()
if Players and not LocalPlayer then
    local tries = 0
    while not LocalPlayer and tries < 100 do
        tries = tries + 1
        pcall(function() task.wait(0.1) end)
        LocalPlayer = ReadLocalPlayer()
    end
end

-- executor functions (resolved once, every call is pcall-wrapped)
local WriteFileFn  = FirstFn(writefile, SafeIndex(env, "writefile"))
local ReadFileFn   = FirstFn(readfile, SafeIndex(env, "readfile"))
local IsFileFn     = FirstFn(isfile, SafeIndex(env, "isfile"))
local DelFileFn    = FirstFn(delfile, SafeIndex(env, "delfile"))
local MakeFolderFn = FirstFn(makefolder, SafeIndex(env, "makefolder"))
local IsFolderFn   = FirstFn(isfolder, SafeIndex(env, "isfolder"))
local ListFilesFn  = FirstFn(listfiles, SafeIndex(env, "listfiles"))
local GetHuiFn     = FirstFn(gethui, get_hidden_gui, SafeIndex(env, "gethui"))
local ProtectGuiFn = FirstFn(SafeIndex(syn, "protect_gui"), protectgui, protect_gui, SafeIndex(env, "protect_gui"))
local ClipboardFn  = FirstFn(
    setclipboard, toclipboard, set_clipboard, setrbxclipboard,
    SafeIndex(Clipboard, "set"), SafeIndex(syn, "write_clipboard"), SafeIndex(env, "setclipboard")
)
local ExecNameFn   = FirstFn(identifyexecutor, getexecutorname, whatexecutor, SafeIndex(env, "identifyexecutor"))

local FS = {}
function FS.Write(path, content)
    if not WriteFileFn then return false end
    return (pcall(WriteFileFn, path, content))
end
function FS.Read(path)
    if not ReadFileFn then return nil end
    if IsFileFn then
        local ok, exists = pcall(IsFileFn, path)
        if ok and exists == false then return nil end
    end
    local ok, res = pcall(ReadFileFn, path)
    if ok and type(res) == "string" then return res end
    return nil
end
function FS.EnsureFolder(path)
    if not MakeFolderFn or not path or path == "" then return end
    if IsFolderFn then
        local ok, exists = pcall(IsFolderFn, path)
        if ok and exists then return end
    end
    pcall(MakeFolderFn, path)
end
function FS.List(path)
    local out = {}
    if not ListFilesFn then return out end
    local ok, res = pcall(ListFilesFn, path)
    if ok and type(res) == "table" then
        for _, p in ipairs(res) do
            if type(p) == "string" then out[#out + 1] = p end
        end
    end
    return out
end
function FS.Delete(path)
    if not DelFileFn then return false end
    return (pcall(DelFileFn, path))
end

local function SetClipboard(text)
    if not ClipboardFn then return false end
    return (pcall(ClipboardFn, text))
end

local function ExecutorName()
    if not ExecNameFn then return "Unknown" end
    local ok, name, ver = pcall(ExecNameFn)
    if not ok or name == nil then return "Unknown" end
    name = tostring(name)
    if ver ~= nil and tostring(ver) ~= "" and not string.find(name, tostring(ver), 1, true) then
        name = name .. " " .. tostring(ver)
    end
    return name
end

-- key names are handled as strings everywhere (old executors / unknown KeyCodes never error)
local function KeyName(k)
    if typeof(k) == "EnumItem" then
        -- only KeyCode items (Enum.UserInputType.MouseButton1 etc. are refused)
        local ok, n, et = pcall(function() return k.Name, tostring(k.EnumType) end)
        if not ok or type(n) ~= "string" or (et ~= "KeyCode" and et ~= "Enum.KeyCode") then return nil end
        k = n
    end
    if type(k) ~= "string" or k == "" then return nil end
    if k == "None" then return "None" end
    if k == "Unknown" then return nil end
    local ok, item = pcall(function() return Enum.KeyCode[k] end)
    if not ok or typeof(item) ~= "EnumItem" then return nil end
    local ok2, name = pcall(function() return item.Name end)
    if ok2 and type(name) == "string" and name ~= "Unknown" then return name end
    return nil
end

local function IsTouchOnly()
    local ok, res = pcall(function()
        return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    end)
    return ok and res == true
end

local function JSONEncode(t)
    local ok, s = pcall(function() return HttpService:JSONEncode(t) end)
    return ok and s or nil
end

local function JSONDecode(s)
    local ok, t = pcall(function() return HttpService:JSONDecode(s) end)
    return (ok and type(t) == "table") and t or nil
end

-- unique id for this SolUI instance (two scripts using SolUI must not share GUI names)
local InstanceId
do
    local ok, g = pcall(function() return HttpService:GenerateGUID(false) end)
    if ok and type(g) == "string" and g ~= "" then
        InstanceId = string.gsub(g, "[^%w]", "")
    else
        InstanceId = tostring(math.random(100000, 999999)) .. tostring(math.floor(Clock() * 1000) % 100000)
    end
end

local function TypingInTextBox()
    local ok, box = pcall(function() return UserInputService:GetFocusedTextBox() end)
    return ok and box ~= nil
end

----------------------------------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------------------------------

local LibTrash = {}
local GlowLayers = {} -- holder -> { layers = {Frame...}, key = themeKey|nil }, strong keys, cleaned on Destroying / unload
local Registry = {}   -- strong table: obj -> { prop = themeKey }, cleaned on Destroying / unload
local ThemeListeners = {}
local UnloadListeners = {}
local Listening, ConsumedAt = false, 0

local function Track(x, bin)
    bin = bin or LibTrash
    bin[#bin + 1] = x
    return x
end

local function EmptyBin(bin)
    for i = #bin, 1, -1 do
        local x = bin[i]
        pcall(function()
            if typeof(x) == "RBXScriptConnection" then
                x:Disconnect()
            elseif type(x) == "function" then
                x()
            else
                x:Destroy()
            end
        end)
    end
    ClearTable(bin)
end

local function RemoveFrom(list, x)
    if type(list) ~= "table" then return end
    for i = #list, 1, -1 do
        if list[i] == x then table.remove(list, i) end
    end
end

-- destroys every element of a list, newest first (used by Tab / Section / Window:Destroy)
local function DestroyElements(list)
    if type(list) ~= "table" then return end
    local copy = {}
    for i = 1, #list do copy[i] = list[i] end
    for i = #copy, 1, -1 do
        local el = copy[i]
        pcall(function() el:Destroy() end)
    end
    ClearTable(list)
end

local WindowRegistry = SafeIndex(env, "__SolUI_Windows")
if type(WindowRegistry) ~= "table" then
    WindowRegistry = {}
    pcall(function() env.__SolUI_Windows = WindowRegistry end)
end

----------------------------------------------------------------------------------------------------
-- Assets / themes
----------------------------------------------------------------------------------------------------

local Icons = {
    ["gamepad-2"]    = "rbxassetid://92483947987410",
    ["settings"]     = "rbxassetid://80758916183665",
    ["search"]       = "rbxassetid://121018724060431",
    ["x"]            = "rbxassetid://110786993356448",
    ["minus"]        = "rbxassetid://118026365011536",
    ["key"]          = "rbxassetid://96510194465420",
    ["power"]        = "rbxassetid://96479131758775",
    ["palette"]      = "rbxassetid://86350350950064",
    ["monitor"]      = "rbxassetid://72664649203050",
    ["chevron-down"] = "rbxassetid://134243273101015",
    ["user"]         = "rbxassetid://81589895647169",
    ["check"]        = "rbxassetid://93898873302694",
    ["copy"]         = "rbxassetid://78979572434545",
    ["trash-2"]      = "rbxassetid://109843431391323",
    ["play"]         = "rbxassetid://135609604299893",
    ["shield-check"] = "rbxassetid://87354736164608",
    ["external-link"]= "rbxassetid://129331830773832",
    ["info"]         = "rbxassetid://124560466474914",
    ["layout-grid"]  = "rbxassetid://81344910161871",
    ["discord"]      = "rbxassetid://4483345998",
}
-- friendly names mapped onto the icons above
local IconAlias = {
    home = "layout-grid", main = "layout-grid", grid = "layout-grid", dashboard = "layout-grid", layout = "layout-grid",
    gamepad = "gamepad-2", game = "gamepad-2", games = "gamepad-2", controller = "gamepad-2",
    gear = "settings", cog = "settings", ["settings-2"] = "settings", config = "settings",
    close = "x", cross = "x", ["log-out"] = "power", exit = "power", unload = "power",
    theme = "palette", paint = "palette", brush = "palette", display = "monitor", screen = "monitor", visual = "monitor",
    person = "user", profile = "user", player = "user", account = "user", users = "user",
    done = "check", ["circle-check"] = "check", tick = "check", clipboard = "copy", trash = "trash-2", delete = "trash-2",
    run = "play", start = "play", shield = "shield-check", security = "shield-check", safe = "shield-check",
    link = "external-link", external = "external-link", disc = "discord", discordapp = "discord", help = "info", about = "info", warning = "info",
    ["alert-circle"] = "info", ["alert-triangle"] = "info", lock = "key", find = "search", ["chevron"] = "chevron-down",
}
Library.Icons = Icons
local SHADOW = "rbxassetid://6014261993"

local function ResolveIcon(name)
    if name == nil or name == false then return "" end
    if type(name) == "number" then return "rbxassetid://" .. tostring(name) end
    name = tostring(name)
    if Icons[name] then return Icons[name] end
    local lower = string.lower(name)
    if Icons[lower] then return Icons[lower] end
    if IconAlias[lower] then return Icons[IconAlias[lower]] end
    if string.find(name, "^rbxassetid://") or string.find(name, "^rbxasset://") or string.find(name, "^http") then return name end
    if string.find(name, "^%d+$") then return "rbxassetid://" .. name end
    return ""
end

local function P(bg, s, s2, s3, st, sth, ac, acd, tx, mu)
    local function c(t) return Color3.fromRGB(t[1], t[2], t[3]) end
    return {
        Background = c(bg), Surface = c(s), Surface2 = c(s2), Surface3 = c(s3),
        Stroke = c(st), StrokeHover = c(sth), Accent = c(ac), AccentDark = c(acd),
        Text = c(tx), Muted = c(mu),
    }
end

local Presets = Library.Themes
Presets.Mono     = P({16,16,17},{20,20,21},{25,25,26},{40,40,42},{38,38,40},{84,84,88},{236,236,240},{20,20,22},{234,234,236},{128,128,134})
Presets.Midnight = P({15,18,26},{18,22,31},{22,26,37},{37,44,60},{34,40,55},{70,84,112},{128,160,246},{14,18,30},{228,232,242},{124,134,156})
Presets.Ocean    = P({12,20,24},{15,24,29},{18,29,35},{31,48,56},{29,44,52},{58,92,104},{110,214,222},{10,24,28},{226,238,240},{116,142,148})
Presets.Emerald  = P({13,20,17},{16,24,20},{20,29,24},{33,47,40},{30,44,37},{62,96,78},{132,226,170},{12,26,18},{228,240,233},{118,144,130})
Presets.Amber    = P({22,18,13},{27,22,16},{32,26,19},{49,41,31},{46,38,28},{100,82,58},{246,196,120},{30,22,10},{242,236,226},{148,134,114})
Presets.Nebula   = P({14,12,28},{18,15,35},{23,19,43},{39,32,68},{35,29,62},{84,68,140},{199,125,255},{22,10,40},{236,230,252},{132,122,168})
Presets.Crimson  = P({18,10,12},{23,12,15},{28,14,18},{46,24,29},{42,22,27},{104,46,56},{244,74,94},{32,8,12},{244,230,232},{150,114,120})
for _, n in ipairs({ "Mono", "Midnight", "Ocean", "Emerald", "Amber", "Nebula", "Crimson" }) do
    Library.ThemeOrder[#Library.ThemeOrder + 1] = n
end

local ThemeKeys = { "Background", "Surface", "Surface2", "Surface3", "Stroke", "StrokeHover", "Accent", "AccentDark", "Text", "Muted" }
local Theme = {}

local function BuildTheme()
    ClearTable(Theme)
    for k, v in pairs(Presets.Mono) do Theme[k] = v end
    for k, v in pairs(Presets[Library.Theme] or {}) do Theme[k] = v end
    Theme.Success = Theme.Success or Color3.fromRGB(110, 220, 150)
    Theme.Warning = Theme.Warning or Color3.fromRGB(240, 176, 108)
    Theme.Error   = Theme.Error or Color3.fromRGB(240, 110, 110)
end
BuildTheme()

----------------------------------------------------------------------------------------------------
-- UI primitives (SOL Hub v3)
----------------------------------------------------------------------------------------------------

local function Tween(obj, props, time, style, dir)
    local ok, t = pcall(function()
        return TweenService:Create(
            obj,
            TweenInfo.new(time or 0.2, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out),
            props
        )
    end)
    if ok and t then
        pcall(function() t:Play() end)
        return t
    end
    -- tween failed: apply instantly
    pcall(function() for k, v in pairs(props) do obj[k] = v end end)
    return nil
end

local function Bind(obj, prop, key, t)
    local entry = Registry[obj]
    if not entry then
        entry = {}
        Registry[obj] = entry
        pcall(function()
            obj.Destroying:Connect(function() Registry[obj] = nil end)
        end)
    end
    entry[prop] = key
    if t == false then return end
    if t then
        Tween(obj, { [prop] = Theme[key] }, t)
    else
        pcall(function() obj[prop] = Theme[key] end)
    end
end

local function ApplyTheme(instant)
    BuildTheme()
    for obj, props in pairs(Registry) do
        local okParent, parent = pcall(function() return obj.Parent end)
        if not okParent then
            Registry[obj] = nil
        elseif parent then
            for prop, key in pairs(props) do
                if instant then
                    pcall(function() obj[prop] = Theme[key] end)
                else
                    Tween(obj, { [prop] = Theme[key] }, 0.3)
                end
            end
        end
    end
    -- themed glows: one plain loop per glow (no Registry entries, no tweens)
    for _, info in pairs(GlowLayers) do
        if info.key then
            local c = Theme[info.key]
            for _, f in ipairs(info.layers) do
                pcall(function() f.BackgroundColor3 = c end)
            end
        end
    end
end

local function New(class, props, themed)
    local o = Instance.new(class)
    if o:IsA("GuiObject") then
        o.BorderSizePixel = 0
        pcall(function() o.AutoLocalize = false end)
    end
    if o:IsA("TextLabel") then
        o.BackgroundTransparency = 1
        o.Font = Enum.Font.Gotham
    end
    if o:IsA("TextButton") then
        o.AutoButtonColor = false
        o.Font = Enum.Font.Gotham
    end
    if o:IsA("TextBox") then o.Font = Enum.Font.Gotham end
    if o:IsA("ImageLabel") or o:IsA("ImageButton") then o.BackgroundTransparency = 1 end

    local parent
    for k, v in pairs(props or {}) do
        if k == "Parent" then
            parent = v
        else
            local ok, err = pcall(function() o[k] = v end)
            if not ok then
                warn("[SolUI] invalid property " .. class .. "." .. tostring(k) .. " : " .. tostring(err))
            end
        end
    end
    for prop, key in pairs(themed or {}) do Bind(o, prop, key) end
    if parent then o.Parent = parent end
    return o
end

local function Round(obj, r)
    return New("UICorner", {
        CornerRadius = (r == "full") and UDim.new(1, 0) or UDim.new(0, r),
        Parent = obj,
    })
end

local function Outline(obj, key, thickness, transparency)
    return New("UIStroke", {
        Thickness = thickness or 1,
        Transparency = transparency or 0,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = obj,
    }, { Color = key or "Stroke" })
end

-- transparency gradient (works with themed colours because it only fades)
local function Fade(obj, from, to, rotation)
    return New("UIGradient", {
        Parent = obj,
        Rotation = rotation or 0,
        Transparency = NumberSequence.new(from, to),
    })
end

-- colour gradient multiplier (white -> grey = accent -> darker accent)
local function Shade(obj, dark, rotation)
    return New("UIGradient", {
        Parent = obj,
        Rotation = rotation or 45,
        Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(dark, dark, dark)),
    })
end

-- lit rim: one stroke that is bright on the top edge and fades out toward the bottom
local function Rim(obj, key, top, bottom, thickness)
    local s = Outline(obj, key or "StrokeHover", thickness or 1, 0)
    New("UIGradient", {
        Parent = s,
        Rotation = 90,
        Transparency = NumberSequence.new(top or 0.25, bottom or 0.8),
    })
    return s
end

-- multi-stop transparency gradient helper: Stops({ {0, 1}, {0.5, 0.8}, {1, 1} })
local function Stops(list)
    local kps = {}
    for i, v in ipairs(list) do kps[i] = NumberSequenceKeypoint.new(v[1], v[2]) end
    return NumberSequence.new(kps)
end

local function Label(parent, text, size, colorKey, font, props)
    local p = {
        Parent = parent,
        Text = text,
        TextSize = size,
        Font = font or Enum.Font.Gotham,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    return New("TextLabel", p, { TextColor3 = colorKey or "Text" })
end

local function Icon(parent, name, size, colorKey, props)
    local p = {
        Parent = parent,
        Size = UDim2.fromOffset(size, size),
        Image = ResolveIcon(name),
        ScaleType = Enum.ScaleType.Fit,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    return New("ImageLabel", p, { ImageColor3 = colorKey or "Muted" })
end

local function Shadow(parent, transparency)
    return New("ImageLabel", {
        Parent = parent,
        Position = UDim2.fromOffset(-28, -28),
        Size = UDim2.new(1, 56, 1, 56),
        Image = SHADOW,
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = transparency or 0.5,
        ScaleType = Enum.ScaleType.Slice,
        SliceCenter = Rect.new(49, 49, 450, 450),
        ZIndex = 0,
    })
end

-- soft coloured glow, built only from rounded Frames (no image asset):
-- concentric pills stacked, their alphas add up toward the centre.
-- Valid transparency range: 0.4 .. 1 (1 = invisible).
local function glowLayerT(transparency, n)
    local T = math.clamp(transparency or 0.6, 0, 1)
    if T >= 1 then return 1 end
    T = math.max(0.05, 1 - (1 - T) * 0.8)
    return T ^ (1 / n)
end

local function SoftGlow(parent, color, pos, size, transparency, z, anchor)
    local themed = type(color) == "string"
    local function side(d) return d.Scale > 0 and 200 or d.Offset end
    local maxSide = math.max(side(size.X), side(size.Y))
    local n = math.clamp(math.floor(maxSide / 10), 8, 20)
    local holder = New("Frame", {
        Parent = parent,
        Name = "Glow",
        AnchorPoint = anchor or Vector2.new(0.5, 0.5),
        Position = pos,
        Size = size,
        BackgroundTransparency = 1,
        Visible = (transparency or 0.6) < 1,
        ZIndex = z or 1,
    })
    local layerT = glowLayerT(transparency, n)
    local c = themed and Theme[color] or color
    local layers = {}
    for i = 1, n do
        local k = 0.62 - (i - 1) * (0.5 / math.max(n - 1, 1))
        local f = New("Frame", {
            Parent = holder,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(k, k),
            BackgroundColor3 = c,
            BackgroundTransparency = layerT,
            ZIndex = z or 1,
        })
        Round(f, "full")
        layers[i] = f
    end
    GlowLayers[holder] = { layers = layers, key = themed and color or nil }
    pcall(function()
        holder.Destroying:Connect(function() GlowLayers[holder] = nil end)
    end)
    return holder
end

local function IsImageRef(s)
    return type(s) == "number" or (type(s) == "string" and (string.find(s, "^rbxasset") ~= nil or string.find(s, "^%d+$") ~= nil))
end

-- brand mark: soft accent glow + shaded accent tile with a lit rim and a letter (or an image)
local function Logo(parent, pos, size, radius, textSize, z, glowScale, mark)
    z = z or 1
    local g = glowScale or 2.3
    local cx, cy = pos.X.Offset + size / 2, pos.Y.Offset + size / 2
    local halo = SoftGlow(parent, "Accent",
        UDim2.new(pos.X.Scale, cx, pos.Y.Scale, cy),
        UDim2.fromOffset(size * g, size * g), 0.72, z)
    local tile = New("Frame", {
        Parent = parent,
        Position = pos,
        Size = UDim2.fromOffset(size, size),
        ZIndex = z + 1,
    }, { BackgroundColor3 = "Accent" })
    Round(tile, radius)
    Shade(tile, 0.68, 60)
    Rim(tile, "Text", 0.35, 1)
    local gloss = New("Frame", {
        Parent = tile,
        Size = UDim2.fromScale(1, 0.55),
        BackgroundColor3 = Color3.new(1, 1, 1),
        ZIndex = z + 1,
    })
    Round(gloss, radius)
    Fade(gloss, 0.78, 1, 90)
    if IsImageRef(mark) then
        New("ImageLabel", {
            Parent = tile,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(0.62, 0.62),
            Image = ResolveIcon(mark),
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = z + 2,
        }, { ImageColor3 = "AccentDark" })
    else
        Label(tile, string.sub(tostring(mark or "S"), 1, 2), textSize, "AccentDark", Enum.Font.GothamBlack, {
            Size = UDim2.fromScale(1, 1),
            TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None,
            ZIndex = z + 2,
        })
    end
    return tile, halo
end

local function SafeParent(gui, parent, title)
    if not parent then return false end
    pcall(function()
        local old = parent:FindFirstChild(gui.Name)
        if old and old ~= gui then old:Destroy() end
    end)
    -- orphans of the SAME title only (a crashed/old run), never another script's GUI
    if title then
        pcall(function()
            local live = WindowRegistry[title]
            for _, child in ipairs(parent:GetChildren()) do
                if child ~= gui and child:GetAttribute("SolUITitle") == title
                    and not (live and live.Alive and live.Gui == child) then
                    child:Destroy()
                end
            end
        end)
    end
    local ok = pcall(function() gui.Parent = parent end)
    -- parent can be a cloneref proxy: gui.Parent then returns the real instance, never "== parent"
    return ok and gui.Parent ~= nil
end

local function MountGui(name, order, title)
    local gui = Instance.new("ScreenGui")
    gui.Name = name
    if title then pcall(function() gui:SetAttribute("SolUITitle", title) end) end
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = order or 100
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() gui.AutoLocalize = false end)
    pcall(function() gui.ScreenInsets = Enum.ScreenInsets.None end)

    if ProtectGuiFn then pcall(ProtectGuiFn, gui) end

    -- 1) hidden UI container (most executors)
    if GetHuiFn then
        local ok, hui = pcall(GetHuiFn)
        if ok and typeof(hui) == "Instance" and SafeParent(gui, hui, title) then return gui end
    end
    -- 2) CoreGui (needs elevated identity, fails silently on some executors)
    local core = Service("CoreGui")
    if core and SafeParent(gui, core, title) then return gui end
    -- 3) PlayerGui (always works)
    local lp = LocalPlayer or ReadLocalPlayer()
    local pg
    if lp then
        pcall(function() pg = lp:FindFirstChildOfClass("PlayerGui") end)
        if not pg then
            local ok, res = pcall(function() return lp:WaitForChild("PlayerGui", 10) end)
            if ok then pg = res end
        end
    end
    if not SafeParent(gui, pg, title) then warn("[SolUI] could not mount " .. name) end
    return gui
end

local function Viewport()
    local cam = Workspace.CurrentCamera
    local vp = cam and cam.ViewportSize
    if not vp or vp.X < 2 or vp.Y < 2 then vp = Vector2.new(1280, 720) end
    return vp
end

local function FitScale(w, h)
    local vp = Viewport()
    local margin = (vp.X < 900) and 16 or 32
    return math.clamp(math.min((vp.X - margin) / w, (vp.Y - margin) / h), 0.4, 1)
end

-- fires callback whenever the screen size changes (rotation on phones, window resize on PC)
local function OnViewportChanged(callback, bin)
    local camConn
    local function hook()
        if camConn then camConn:Disconnect() end
        local cam = Workspace.CurrentCamera
        if cam then
            camConn = Track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(callback), bin)
        end
    end
    pcall(hook)
    pcall(function()
        Track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            hook()
            callback()
        end), bin)
    end)
end

-- mouse + touch dragging. returns a function telling if the last press was a drag
-- keeps a frame fully on screen (offset-only nudge, works with any AnchorPoint)
local function ClampToViewport(frame)
    pcall(function()
        local vp = Viewport()
        local pos, size = frame.AbsolutePosition, frame.AbsoluteSize
        local dx, dy = 0, 0
        local maxX, maxY = math.max(0, vp.X - size.X), math.max(0, vp.Y - size.Y)
        if pos.X < 0 then dx = -pos.X elseif pos.X > maxX then dx = maxX - pos.X end
        if pos.Y < 0 then dy = -pos.Y elseif pos.Y > maxY then dy = maxY - pos.Y end
        if dx ~= 0 or dy ~= 0 then
            local p = frame.Position
            frame.Position = UDim2.new(p.X.Scale, p.X.Offset + dx, p.Y.Scale, p.Y.Offset + dy)
        end
    end)
end

local function MakeDraggable(frame, handle, bin)
    local MB1, Touch = Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch
    local dragging, dragInput, dragStart, startPos, moved = false, nil, nil, nil, false
    local endConn
    local function stop()
        if dragging then
            dragging = false
            ClampToViewport(frame)
        end
        if endConn then endConn:Disconnect() end
        endConn = nil
    end
    OnViewportChanged(function() ClampToViewport(frame) end, bin)

    Track(handle.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == MB1 or t == Touch then
            dragging = true
            moved = false
            dragInput = input
            dragStart = input.Position
            startPos = frame.Position
            if endConn then endConn:Disconnect() end
            endConn = Track(input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then stop() end
            end), bin)
        end
    end), bin)

    Track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        local t = input.UserInputType
        local isTouchDrag = t == Touch and dragInput and dragInput.UserInputType == Touch
        if t == Enum.UserInputType.MouseMovement or isTouchDrag then
            local d = input.Position - dragStart
            if math.abs(d.X) + math.abs(d.Y) > 6 then moved = true end
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end
    end), bin)

    Track(UserInputService.InputEnded:Connect(function(input)
        local t = input.UserInputType
        if t == MB1 or t == Touch then stop() end
    end), bin)

    return function() return moved end
end

-- horizontal / 2D drag helper for sliders and colour pickers: onMove(inputPosition)
local function DragArea(hit, onMove, bin)
    local MB1, Touch = Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch
    local dragging, dragType, lockedScroll = false, nil, nil
    -- the parent ScrollingFrame must not scroll while a slider / SV square is dragged (touch)
    local function unlock()
        if lockedScroll then
            local sf = lockedScroll
            lockedScroll = nil
            pcall(function() sf.ScrollingEnabled = true end)
        end
    end
    if bin then bin[#bin + 1] = unlock end
    Track(hit.InputBegan:Connect(function(input)
        local t = input.UserInputType
        if t == MB1 or t == Touch then
            dragging = true
            dragType = t
            pcall(function()
                local sf = hit.Parent
                while sf and not sf:IsA("ScrollingFrame") do sf = sf.Parent end
                if sf and sf.ScrollingEnabled ~= false then
                    lockedScroll = sf
                    sf.ScrollingEnabled = false
                end
            end)
            onMove(input.Position)
        end
    end), bin)
    Track(UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        local t = input.UserInputType
        if t == Enum.UserInputType.MouseMovement or (t == Touch and dragType == Touch) then
            onMove(input.Position)
        end
    end), bin)
    Track(UserInputService.InputEnded:Connect(function(input)
        local t = input.UserInputType
        if t == MB1 or t == Touch then
            dragging = false
            unlock()
        end
    end), bin)
end

-- press feedback (UIScale squeeze) for any button
local function Pressable(btn, amount)
    local s = New("UIScale", { Parent = btn, Scale = 1 })
    btn.MouseButton1Down:Connect(function() Tween(s, { Scale = amount or 0.96 }, 0.1) end)
    btn.MouseButton1Up:Connect(function() Tween(s, { Scale = 1 }, 0.25, Enum.EasingStyle.Back) end)
    btn.MouseLeave:Connect(function() Tween(s, { Scale = 1 }, 0.2) end)
    return s
end

local function Ripple(host)
    local size = math.max(host.AbsoluteSize.X, host.AbsoluteSize.Y) * 2.2
    local r = New("Frame", {
        Parent = host,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BackgroundTransparency = 0.85,
        ZIndex = host.ZIndex + 1,
    })
    Round(r, "full")
    Tween(r, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, 0.5)
    task.delay(0.55, function() pcall(function() r:Destroy() end) end)
end

local function Chip(props)
    local style = props.Style or "default"
    local primary = style == "primary"
    local danger = style == "danger"
    local baseT = primary and 0 or 0.35

    local btn = New("TextButton", {
        Parent = props.Parent,
        Size = props.Size,
        Position = props.Position,
        AnchorPoint = props.AnchorPoint or Vector2.new(0, 0),
        LayoutOrder = props.LayoutOrder or 0,
        Text = "",
        ClipsDescendants = true,
        BackgroundTransparency = baseT,
        ZIndex = props.ZIndex or 1,
    }, { BackgroundColor3 = primary and "Accent" or "Surface3" })
    Round(btn, props.Radius or 8)
    local stroke
    if primary then
        Shade(btn, 0.78, 90)
        stroke = Rim(btn, "Text", 0.45, 1)
        local gloss = New("Frame", {
            Parent = btn,
            Size = UDim2.fromScale(1, 0.5),
            BackgroundColor3 = Color3.new(1, 1, 1),
            ZIndex = btn.ZIndex,
        })
        Round(gloss, props.Radius or 8)
        Fade(gloss, 0.84, 1, 90)
    else
        stroke = Rim(btn, "StrokeHover", 0.35, 0.85)
    end
    Pressable(btn)

    local content = New("Frame", {
        Parent = btn,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 1,
        ZIndex = btn.ZIndex + 1,
    })
    New("UIListLayout", {
        Parent = content,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
    })

    local textKey = primary and "AccentDark" or (danger and "Error" or "Text")
    local iconKey = primary and "AccentDark" or (danger and "Error" or "Accent")
    if props.Icon then
        Icon(content, props.Icon, props.IconSize or 14, iconKey, { LayoutOrder = 1, ZIndex = btn.ZIndex + 1 })
    end
    local label = Label(content, props.Text or "", props.TextSize or 13, textKey,
        primary and Enum.Font.GothamBold or Enum.Font.GothamMedium, {
        Size = UDim2.new(0, 0, 1, 0),
        AutomaticSize = Enum.AutomaticSize.X,
        TextTruncate = Enum.TextTruncate.None,
        LayoutOrder = 2,
        ZIndex = btn.ZIndex + 1,
    })

    btn.MouseEnter:Connect(function()
        if primary then
            Tween(btn, { BackgroundTransparency = 0.12 }, 0.12)
        else
            Tween(btn, { BackgroundTransparency = 0 }, 0.12)
            Bind(stroke, "Color", danger and "Error" or "Accent", 0.12)
        end
    end)
    btn.MouseLeave:Connect(function()
        Tween(btn, { BackgroundTransparency = baseT }, 0.25)
        if not primary then
            Bind(stroke, "Color", "StrokeHover", 0.25)
        end
    end)
    btn.MouseButton1Click:Connect(function()
        Ripple(btn)
        if props.Callback then task.spawn(props.Callback) end
    end)

    return btn, label
end

local function IconButton(parent, iconName, position, callback, hoverKey)
    local b = New("TextButton", {
        Parent = parent,
        AnchorPoint = Vector2.new(1, 0),
        Position = position,
        Size = UDim2.fromOffset(32, 32),
        Text = "",
        BackgroundTransparency = 0.3,
        ZIndex = 3,
    }, { BackgroundColor3 = "Surface2" })
    Round(b, 9)
    local stroke = Rim(b, "StrokeHover", 0.3, 0.85)
    Pressable(b, 0.9)
    local ic = Icon(b, iconName, 16, "Muted", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        ZIndex = 4,
    })
    b.MouseEnter:Connect(function()
        Tween(b, { BackgroundTransparency = 0 }, 0.12)
        Bind(ic, "ImageColor3", hoverKey or "Text", 0.12)
        Bind(stroke, "Color", hoverKey or "StrokeHover", 0.12)
    end)
    b.MouseLeave:Connect(function()
        Tween(b, { BackgroundTransparency = 0.3 }, 0.2)
        Bind(ic, "ImageColor3", "Muted", 0.2)
        Bind(stroke, "Color", "StrokeHover", 0.2)
    end)
    b.MouseButton1Click:Connect(function()
        if callback then task.spawn(callback) end
    end)
    return b
end

----------------------------------------------------------------------------------------------------
-- Colour helpers (pure Lua: no Color3.fromHSV / ToHSV dependency)
----------------------------------------------------------------------------------------------------

local function HSVToColor(h, s, v)
    h = (h or 0) % 1
    s = math.clamp(s or 0, 0, 1)
    v = math.clamp(v or 0, 0, 1)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    local r, g, b
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return Color3.new(r, g, b)
end

local function ColorToHSV(c)
    local r, g, b = c.R, c.G, c.B
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then
            h = ((g - b) / d) % 6
        elseif mx == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
    end
    local s = (mx > 0) and (d / mx) or 0
    return h, s, mx
end

local function ToHex(c)
    local function b(x) return math.clamp(math.floor(x * 255 + 0.5), 0, 255) end
    return string.format("#%02X%02X%02X", b(c.R), b(c.G), b(c.B))
end

local function FromHex(s)
    if type(s) ~= "string" then return nil end
    s = string.gsub(s, "[#%s]", "")
    if #s == 3 then
        s = string.sub(s, 1, 1) .. string.sub(s, 1, 1) .. string.sub(s, 2, 2) .. string.sub(s, 2, 2) .. string.sub(s, 3, 3) .. string.sub(s, 3, 3)
    end
    if #s ~= 6 or string.find(s, "[^%x]") then return nil end
    return Color3.fromRGB(tonumber(string.sub(s, 1, 2), 16), tonumber(string.sub(s, 3, 4), 16), tonumber(string.sub(s, 5, 6), 16))
end

local function ToColor(v, fallback)
    if typeof(v) == "Color3" then return v end
    if type(v) == "string" then return FromHex(v) or fallback end
    if type(v) == "table" and type(v[1]) == "number" then
        return Color3.fromRGB(v[1], v[2] or 0, v[3] or 0)
    end
    return fallback
end

----------------------------------------------------------------------------------------------------
-- Notifications
----------------------------------------------------------------------------------------------------

local NotifGui, NotifHolder
local NotifOrder = 0
local NotifActive, NotifQueue = 0, {}
Library.MaxNotifications = 4

local function EnsureNotifs()
    if NotifGui and NotifGui.Parent and NotifHolder and NotifHolder.Parent then return end
    NotifActive, NotifQueue = 0, {}
    NotifGui = Track(MountGui("SolUI_Notifications_" .. InstanceId, 1000))
    NotifHolder = New("Frame", {
        Parent = NotifGui,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, -18, 1, -18),
        Size = UDim2.new(0, 300, 1, -36),
        BackgroundTransparency = 1,
    })
    New("UIListLayout", {
        Parent = NotifHolder,
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
    })
    local vp = Viewport()
    if vp.X < 700 then
        New("UIScale", { Parent = NotifHolder, Scale = math.max(vp.X / 700, 0.7) })
    end
end

local NotifKinds = {
    info    = { color = "Accent",  icon = "info" },
    success = { color = "Success", icon = "check" },
    error   = { color = "Error",   icon = "x" },
    warning = { color = "Warning", icon = "info" },
}

-- Library:Notify({ Title, Content, Duration, Type }) or Library:Notify(title, content, duration, type)
function Library:Notify(opts, content, duration, kind)
    if Library.Unloaded then return nil end
    if type(opts) ~= "table" then
        opts = { Title = opts, Content = content, Duration = duration, Type = kind }
    end
    local k = string.lower(tostring(opts.Type or "info"))
    if k == "warn" then k = "warning" end
    if k == "err" then k = "error" end
    local info = NotifKinds[k] or NotifKinds.info
    if not Library.NotificationsEnabled and k ~= "error" then return nil end

    local okEnsure = pcall(EnsureNotifs)
    if not okEnsure or not NotifHolder then return nil end
    local actions = {}
    if type(opts.Actions) == "table" then
        for _, a in ipairs(opts.Actions) do
            if type(a) == "table" and #actions < 3 then actions[#actions + 1] = a end
        end
    end
    local dur = tonumber(opts.Duration) or 4
    local title = tostring(opts.Title or "Notification")
    local text = tostring(opts.Content or opts.Text or "")
    NotifOrder = NotifOrder + 1

    -- height grows with the content (about 34 characters per line, max 4 lines)
    local lines = math.clamp(math.ceil(#text / 34), 1, 4)
    if text == "" then lines = 0 end
    local height = 48 + lines * 15
    if height < 64 then height = 64 end
    if #actions > 0 then height = height + 34 end
    local color = Theme[info.color]

    local notif = { Closed = false, Queued = false, Duration = dur }
    local wrap, card
    local function show()
        notif.Queued = false
        NotifActive = NotifActive + 1
        wrap = New("Frame", {
            Parent = NotifHolder,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, height),
            ClipsDescendants = true,
            LayoutOrder = NotifOrder,
        })
        card = New("TextButton", {
            Parent = wrap,
            Text = "",
            Size = UDim2.fromScale(1, 1),
            Position = UDim2.new(1, 24, 0, 0),
            BackgroundColor3 = Theme.Surface2,
        })
        Round(card, 12)
        local ck = info.color -- theme key of the type colour (Accent / Success / Warning / Error)
        Bind(card, "BackgroundColor3", "Surface2")
        local cs = New("UIStroke", { Parent = card, Color = Theme.StrokeHover, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
        Bind(cs, "Color", "StrokeHover")
        New("UIGradient", { Parent = cs, Rotation = 90, Transparency = NumberSequence.new(0.2, 0.8) })

        local glow = New("Frame", {
            Parent = card,
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = color,
            BackgroundTransparency = 0,
        })
        Round(glow, 12)
        Bind(glow, "BackgroundColor3", ck)
        Fade(glow, 0.84, 1, 0)

        local strip = New("Frame", {
            Parent = card,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.fromOffset(3, 28),
            BackgroundColor3 = color,
            ZIndex = 2,
        })
        Round(strip, "full")
        Bind(strip, "BackgroundColor3", ck)

        SoftGlow(card, color, UDim2.fromOffset(31, 32), UDim2.fromOffset(78, 78), 0.8, 1)

        local tile = New("Frame", {
            Parent = card,
            Size = UDim2.fromOffset(34, 34),
            Position = UDim2.fromOffset(14, 15),
            BackgroundColor3 = color,
            BackgroundTransparency = 0.82,
            ZIndex = 2,
        })
        Round(tile, 10)
        Bind(tile, "BackgroundColor3", ck)
        Bind(New("UIStroke", { Parent = tile, Color = color, Transparency = 0.6, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }), "Color", ck)
        local nIcon = New("ImageLabel", {
            Parent = tile,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(16, 16),
            Image = ResolveIcon(opts.Icon or info.icon),
            ImageColor3 = color,
            ScaleType = Enum.ScaleType.Fit,
            ZIndex = 3,
        })
        Bind(nIcon, "ImageColor3", ck)

        local nTitle = New("TextLabel", {
            Parent = card,
            Text = title,
            Font = Enum.Font.GothamBold,
            TextSize = 13,
            TextColor3 = Theme.Text,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(60, 14),
            Size = UDim2.new(1, -74, 0, 16),
            ZIndex = 2,
        })
        Bind(nTitle, "TextColor3", "Text")
        local nText = New("TextLabel", {
            Parent = card,
            Text = text,
            TextSize = 12,
            TextColor3 = Theme.Muted,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = lines > 1,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(60, 33),
            Size = UDim2.new(1, -74, 0, math.max(lines, 1) * 15),
            ZIndex = 2,
        })
        Bind(nText, "TextColor3", "Muted")

        local bar = New("Frame", {
            Parent = card,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 14, 1, -1),
            Size = UDim2.new(1, -28, 0, 2),
            BackgroundColor3 = color,
            BackgroundTransparency = 0.15,
            ZIndex = 2,
        })
        Round(bar, "full")
        Bind(bar, "BackgroundColor3", ck)
        Fade(bar, 0.6, 0, 0)
        notif._bar = bar

        -- action buttons (each runs its callback in pcall, then closes the notification)
        if #actions > 0 then
            local row = New("Frame", {
                Parent = card,
                AnchorPoint = Vector2.new(0, 1),
                Position = UDim2.new(0, 60, 1, -10),
                Size = UDim2.new(1, -74, 0, 24),
                BackgroundTransparency = 1,
                ZIndex = 3,
            })
            New("UIListLayout", {
                Parent = row, FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6),
                SortOrder = Enum.SortOrder.LayoutOrder,
            })
            notif.Buttons = {}
            for i, a in ipairs(actions) do
                local primary = i == 1
                local btn = New("TextButton", {
                    Parent = row,
                    Name = "Action",
                    Text = tostring(a.Text or a.Name or ("Action " .. i)),
                    Font = Enum.Font.GothamBold,
                    TextSize = 11,
                    TextColor3 = primary and Theme.Background or Theme.Text,
                    BackgroundColor3 = primary and color or Theme.Surface3,
                    Size = UDim2.new(0, 0, 1, 0),
                    AutomaticSize = Enum.AutomaticSize.X,
                    LayoutOrder = i,
                    ZIndex = 4,
                })
                Round(btn, 7)
                Bind(btn, "TextColor3", primary and "Background" or "Text")
                Bind(btn, "BackgroundColor3", primary and ck or "Surface3")
                New("UIPadding", { Parent = btn, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) })
                Pressable(btn, 0.94)
                btn.MouseButton1Click:Connect(function()
                    if notif.Closed then return end
                    if type(a.Callback) == "function" then
                        local ok, err = pcall(a.Callback, notif)
                        if not ok then warn("[SolUI] notification action error: " .. tostring(err)) end
                    end
                    notif:Close()
                end)
                notif.Buttons[i] = btn
            end
        end


        card.MouseButton1Click:Connect(function() notif:Close() end)
        -- hover (mouse) or press-and-hold (touch) pauses; it never overrides an explicit :Pause()
        card.MouseEnter:Connect(function() notif._hover = true end)
        card.MouseLeave:Connect(function() notif._hover = false end)
        card.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then notif._hover = true end
        end)
        card.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch then notif._hover = false end
        end)
        Tween(card, { Position = UDim2.new(0, 0, 0, 0) }, 0.4, Enum.EasingStyle.Back)
        notif.Instance = wrap
        -- remaining-time bar, paused while hovered
        notif.Remaining = dur
        task.spawn(function()
            while not notif.Closed and notif.Remaining > 0 do
                local dt = task.wait(0.05) or 0.05
                if notif.Closed then break end
                if not notif.Paused and not notif._hover then notif.Remaining = math.max(0, notif.Remaining - dt) end
                pcall(function()
                    local fr = notif.Remaining / dur
                    bar.Size = UDim2.new(fr, -28 * fr, 0, 2)
                end)
            end
            notif:Close()
        end)
    end

    function notif:Close()
        if notif.Closed then return end
        notif.Closed = true
        if notif.Queued then
            for i, q in ipairs(NotifQueue) do
                if q.notif == notif then
                    table.remove(NotifQueue, i)
                    break
                end
            end
            return
        end
        NotifActive = math.max(0, NotifActive - 1)
        -- unregister from the theme registry right away
        pcall(function()
            Registry[wrap] = nil
            for _, o in ipairs(wrap:GetDescendants()) do Registry[o] = nil end
        end)
        task.spawn(function()
            if card and card.Parent then
                Tween(card, { Position = UDim2.new(1, 24, 0, 0) }, 0.28)
                task.wait(0.3)
                Tween(wrap, { Size = UDim2.new(1, 0, 0, 0) }, 0.2)
                task.wait(0.21)
            end
            pcall(function() wrap:Destroy() end)
        end)
        local nxt = table.remove(NotifQueue, 1)
        if nxt and not Library.Unloaded then pcall(nxt.show) end
    end
    function notif:Pause() notif.Paused = true end
    function notif:Resume() notif.Paused = false end

    if NotifActive >= (tonumber(Library.MaxNotifications) or 4) then
        notif.Queued = true
        NotifQueue[#NotifQueue + 1] = { notif = notif, show = show }
    else
        show()
    end
    return notif
end

-- runs a user callback in its own thread; an error only warns + shows an error notification
local function SafeCall(name, fn, ...)
    if type(fn) ~= "function" then return end
    local args = PackArgs(...)
    task.spawn(function()
        local ok, err = pcall(fn, unpackFn(args, 1, args.n))
        if not ok then
            local msg = tostring(err)
            warn("[SolUI] callback error in '" .. tostring(name) .. "': " .. msg)
            pcall(function()
                Library:Notify({ Title = "Callback error", Content = tostring(name) .. ": " .. msg, Type = "error", Duration = 6 })
            end)
        end
    end)
end
Library.SafeCall = SafeCall

----------------------------------------------------------------------------------------------------
-- Themes API
----------------------------------------------------------------------------------------------------

local ThemeInstant = false -- set by the live theme editor: recolour without tweens

function Library:SetTheme(name)
    if type(name) == "table" then
        local custom = name
        name = custom.Name or "Custom"
        Library:AddTheme(name, custom)
    end
    if not Presets[name] then
        warn("[SolUI] unknown theme '" .. tostring(name) .. "'")
        return false
    end
    Library.Theme = name
    ApplyTheme(ThemeInstant)
    for _, fn in ipairs(ThemeListeners) do pcall(fn, name) end
    return true
end

-- Library:AddTheme("Rose", { Accent = Color3.fromRGB(...), ... }) - missing keys come from Mono
function Library:AddTheme(name, colors)
    name = tostring(name)
    local t = {}
    for _, k in ipairs(ThemeKeys) do
        t[k] = ToColor(colors and colors[k], nil) or Presets.Mono[k]
    end
    for _, k in ipairs({ "Success", "Warning", "Error" }) do
        if colors and colors[k] then t[k] = ToColor(colors[k], nil) end
    end
    local exists = Presets[name] ~= nil
    Presets[name] = t
    if not exists then Library.ThemeOrder[#Library.ThemeOrder + 1] = name end
    if Library.Theme == name then ApplyTheme(ThemeInstant) end
    -- listeners (swatch lists) learn about new / changed themes too
    for _, fn in ipairs(ThemeListeners) do pcall(fn, Library.Theme) end
    return t
end

function Library:GetTheme()
    return Library.Theme, Theme
end

function Library:OnUnload(fn)
    if type(fn) == "function" then UnloadListeners[#UnloadListeners + 1] = fn end
end

function Library:SetClipboard(text)
    return SetClipboard(tostring(text))
end

Library.Executor = ExecutorName()   -- string, e.g. "Xeno" / "Delta" / "Unknown"
Library.GetExecutor = ExecutorName
Library.IsMobile = IsTouchOnly
Library.ToHex = ToHex
Library.FromHex = FromHex

----------------------------------------------------------------------------------------------------
-- Window
----------------------------------------------------------------------------------------------------

local Window = {}
Window.__index = Window
local Tab = {}
Tab.__index = Tab
local Section = {}
Section.__index = Section

local WindowCount = 0

local function SanitizeName(s)
    s = tostring(s or "")
    s = string.gsub(s, "[^%w%-_ ]", "")
    s = string.gsub(s, "^%s+", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

function Library.CreateWindow(_, opts)
    opts = opts or {}

    local title = tostring(opts.Title or opts.Name or "SolUI")
    -- re-executing the same script replaces the previous window with the same title
    -- (_unloading stops that Destroy from unloading the whole library when it was the last window)
    local previous = WindowRegistry[title]
    if previous and type(previous.Destroy) == "function" then
        local wasUnloading = Library._unloading
        Library._unloading = true
        pcall(function() previous:Destroy(true) end)
        Library._unloading = wasUnloading
    end
    if Library.Unloaded then
        Library.Unloaded = false
    end

    if opts.Theme then
        if Presets[opts.Theme] then
            Library.Theme = opts.Theme
            BuildTheme()
        else
            warn("[SolUI] unknown theme '" .. tostring(opts.Theme) .. "', using " .. Library.Theme)
        end
    end

    local W, H = 620, 420
    local size = opts.Size
    if typeof(size) == "UDim2" and size.X.Offset > 0 and size.Y.Offset > 0 then
        W, H = size.X.Offset, size.Y.Offset
    elseif typeof(size) == "Vector2" then
        W, H = size.X, size.Y
    end
    W = math.max(W, 460)
    H = math.max(H, 300)
    -- small phones (FitScale < 0.7): narrower sidebar so the content stays readable
    local SIDE = tonumber(opts.SidebarWidth) or ((FitScale(math.max(W, 460), math.max(H, 300)) < 0.7) and 130 or 180)
    local HEADER = 72
    local showProfile = opts.ShowProfile ~= false
    local rawFolder = tostring(opts.ConfigFolder or title)
    local folder = SanitizeName(rawFolder)
    if folder ~= rawFolder then
        -- sanitizing changed the name: add a short hash so "⭐ Hub" and "🔥 Hub" never share configs
        local h = 0
        for i = 1, #rawFolder do h = (h * 31 + string.byte(rawFolder, i)) % 16777216 end
        folder = (folder ~= "" and folder or "SolUI") .. "_" .. string.format("%06x", h)
    end
    if folder == "" then folder = "SolUI" end

    local self = setmetatable({
        Title = title,
        Subtitle = tostring(opts.Subtitle or ("v" .. Library.Version)),
        Tabs = {},
        Flags = Library.Flags,
        Options = {},
        ToggleKey = (KeyName(opts.ToggleKey) ~= "None" and KeyName(opts.ToggleKey)) or "RightShift",
        ConfigFolder = folder,
        Open = true,
        Alive = true,
        Library = Library,
        _trash = {},
        _keybinds = {},
        _size = Vector2.new(W, H),
    }, Window)
    WindowCount = WindowCount + 1
    Library.Windows[#Library.Windows + 1] = self
    WindowRegistry[title] = self
    local bin = self._trash

    local gui = MountGui("SolUI_" .. InstanceId .. "_" .. WindowCount, 900 + WindowCount, title)
    Track(gui, bin)
    self.Gui = gui

    local Root = New("Frame", {
        Name = "Window",
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(W, H),
        BackgroundTransparency = 1,
    })
    self.Root = Root
    local ShadowImg = Shadow(Root, 1)
    self._shadow = ShadowImg

    local Body = New("Frame", { Parent = Root, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, { BackgroundColor3 = "Background" })
    Round(Body, 16)
    Rim(Body, "StrokeHover", 0.05, 0.7)
    local Glow = New("Frame", { Parent = Body, Size = UDim2.new(1, 0, 0, 180), ZIndex = 1 }, { BackgroundColor3 = "Accent" })
    Round(Glow, 16)
    Fade(Glow, 0.9, 1, 90)

    -- fade cover (replaces CanvasGroup)
    local Cover = New("Frame", {
        Parent = Root, Size = UDim2.fromScale(1, 1), ZIndex = 50, BackgroundTransparency = 0,
    }, { BackgroundColor3 = "Background" })
    Round(Cover, 16)
    self._cover = Cover

    local scale = New("UIScale", { Scale = FitScale(W, H) * 0.9, Parent = Root })
    self._scale = scale
    self._target = FitScale(W, H)
    Tween(scale, { Scale = self._target }, 0.5, Enum.EasingStyle.Back)
    Tween(Cover, { BackgroundTransparency = 1 }, 0.35)
    Tween(ShadowImg, { ImageTransparency = 0.45 }, 0.4)
    task.delay(0.36, function() if Cover.BackgroundTransparency > 0.99 then Cover.Visible = false end end)

    ------------------------------------------------------------------ sidebar
    local Side = New("Frame", {
        Parent = Body,
        Size = UDim2.new(0, SIDE, 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 2,
    })
    local SideFill = New("Frame", { Parent = Side, Size = UDim2.new(1, 24, 1, 0), ZIndex = 2 }, { BackgroundColor3 = "Surface" })
    Round(SideFill, 16)
    Shade(SideFill, 0.82, 90)
    local SideLine = New("Frame", {
        Parent = Side,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0, 1, 1, 0),
        ZIndex = 3,
    }, { BackgroundColor3 = "Stroke" })
    New("UIGradient", { Parent = SideLine, Rotation = 90, Transparency = Stops({ { 0, 0.6 }, { 0.15, 0 }, { 0.85, 0 }, { 1, 0.6 } }) })

    local SideHeader = New("Frame", {
        Parent = Side,
        Size = UDim2.new(1, 0, 0, 68),
        BackgroundTransparency = 1,
        ZIndex = 3,
    })
    Logo(SideHeader, UDim2.fromOffset(16, 16), 36, 11, 19, 3, 2.1, opts.Logo or string.sub(title, 1, 1))
    self._titleLabel = Label(SideHeader, title, 15, "Text", Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(62, 16),
        Size = UDim2.new(1, -70, 0, 18),
        ZIndex = 4,
    })
    local VerBadge = New("Frame", {
        Parent = SideHeader,
        Position = UDim2.fromOffset(62, 37),
        Size = UDim2.fromOffset(0, 16),
        AutomaticSize = Enum.AutomaticSize.X,
        BackgroundTransparency = 0.86,
        ZIndex = 4,
    }, { BackgroundColor3 = "Accent" })
    Round(VerBadge, "full")
    Outline(VerBadge, "Accent", 1, 0.7)
    New("UIPadding", { Parent = VerBadge, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) })
    self._subtitleLabel = Label(VerBadge, self.Subtitle, 10, "Accent", Enum.Font.GothamBold, {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5,
    })
    -- long subtitles are clipped so the badge never leaves the sidebar
    New("UISizeConstraint", { Parent = self._subtitleLabel, MaxSize = Vector2.new(math.max(40, SIDE - 62 - 14 - 16), 16) })
    VerBadge.Visible = self.Subtitle ~= ""

    Label(Side, "MENU", 10, "Muted", Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(20, 76),
        Size = UDim2.new(1, -40, 0, 14),
        ZIndex = 3,
    })

    local bottomSpace = showProfile and 76 or 10
    local TabScroll = New("ScrollingFrame", {
        Parent = Side,
        Position = UDim2.fromOffset(0, 96),
        Size = UDim2.new(1, 0, 1, -(96 + bottomSpace)),
        BackgroundTransparency = 1,
        ScrollBarThickness = 0,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ZIndex = 3,
    })
    local TabCanvas = New("Frame", {
        Parent = TabScroll,
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        ZIndex = 3,
    })
    self._tabScroll, self._tabCanvas = TabScroll, TabCanvas

    local Indicator = New("Frame", {
        Parent = TabCanvas,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -20, 0, 38),
        BackgroundTransparency = 0.25,
        Visible = false,
        ZIndex = 3,
    }, { BackgroundColor3 = "Surface3" })
    Round(Indicator, 10)
    Rim(Indicator, "StrokeHover", 0.2, 0.8)
    local IndicatorGlow = New("Frame", { Parent = Indicator, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, { BackgroundColor3 = "Accent" })
    Round(IndicatorGlow, 10)
    Fade(IndicatorGlow, 0.8, 1, 0)
    SoftGlow(Indicator, "Accent", UDim2.new(0, 2, 0.5, 0), UDim2.fromOffset(46, 46), 0.72, 3)
    local IndicatorBar = New("Frame", {
        Parent = Indicator,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(3, 18),
        ZIndex = 4,
    }, { BackgroundColor3 = "Accent" })
    Round(IndicatorBar, "full")
    self._indicator = Indicator

    local TabStack = New("Frame", {
        Parent = TabCanvas,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        ZIndex = 5,
    })
    New("UIListLayout", { Parent = TabStack, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })
    self._tabStack = TabStack

    if showProfile then
        local Profile = New("Frame", {
            Parent = Side,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 10, 1, -10),
            Size = UDim2.new(1, -20, 0, 56),
            ZIndex = 3,
        }, { BackgroundColor3 = "Surface2" })
        Round(Profile, 12)
        Rim(Profile, "StrokeHover", 0.25, 0.85)
        local ProfileTint = New("Frame", { Parent = Profile, Size = UDim2.fromScale(1, 1), ZIndex = 3 }, { BackgroundColor3 = "Accent" })
        Round(ProfileTint, 12)
        Fade(ProfileTint, 0.9, 1, 0)
        local uid = 1
        pcall(function() uid = LocalPlayer.UserId end)
        local Avatar = New("ImageLabel", {
            Parent = Profile,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 10, 0.5, 0),
            Size = UDim2.fromOffset(34, 34),
            Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(uid) .. "&w=150&h=150",
            ZIndex = 4,
        }, { BackgroundColor3 = "Surface3" })
        Avatar.BackgroundTransparency = 0
        Round(Avatar, "full")
        Outline(Avatar, "Accent", 1.5, 0.25)
        SoftGlow(Profile, "Accent", UDim2.new(0, 27, 0.5, 0), UDim2.fromOffset(58, 58), 0.75, 3)
        local display = "Player"
        pcall(function() display = LocalPlayer.DisplayName end)
        Label(Profile, display, 13, "Text", Enum.Font.GothamBold, {
            Position = UDim2.fromOffset(54, 11),
            Size = UDim2.new(1, -62, 0, 16),
            ZIndex = 4,
        })
        local Dot = New("Frame", {
            Parent = Profile,
            Position = UDim2.fromOffset(55, 35),
            Size = UDim2.fromOffset(6, 6),
            ZIndex = 4,
        }, { BackgroundColor3 = "Success" })
        Round(Dot, "full")
        Outline(Dot, "Success", 3, 0.8)
        self._profileStatus = Label(Profile, tostring(opts.ProfileText or ExecutorName()), 11, "Muted", nil, {
            Position = UDim2.fromOffset(67, 30),
            Size = UDim2.new(1, -75, 0, 16),
            ZIndex = 4,
        })
    end

    ------------------------------------------------------------------ content / header
    local Content = New("Frame", {
        Parent = Body,
        Position = UDim2.fromOffset(SIDE + 1, 0),
        Size = UDim2.new(1, -(SIDE + 1), 1, 0),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 2,
    })
    local Header = New("Frame", {
        Parent = Content,
        Size = UDim2.new(1, 0, 0, HEADER),
        BackgroundTransparency = 1,
        ZIndex = 2,
    })
    self._pageTitle = Label(Header, "", 21, "Text", Enum.Font.GothamBlack, {
        Position = UDim2.fromOffset(22, 15),
        Size = UDim2.new(1, -130, 0, 26),
        ZIndex = 3,
    })
    self._pageDesc = Label(Header, "", 12, "Muted", Enum.Font.GothamMedium, {
        Position = UDim2.fromOffset(22, 42),
        Size = UDim2.new(1, -130, 0, 16),
        ZIndex = 3,
    })
    local HeaderLine = New("Frame", {
        Parent = Header,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 22, 1, 0),
        Size = UDim2.new(1, -44, 0, 1),
        ZIndex = 3,
    }, { BackgroundColor3 = "Stroke" })
    New("UIGradient", { Parent = HeaderLine, Transparency = Stops({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }) })
    local TitleBar = New("Frame", {
        Parent = Header,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 22, 1, 0),
        Size = UDim2.fromOffset(36, 2),
        ZIndex = 4,
    }, { BackgroundColor3 = "Accent" })
    Round(TitleBar, "full")
    SoftGlow(Header, "Accent", UDim2.new(0, 40, 1, -1), UDim2.fromOffset(70, 26), 0.82, 3)

    local Pages = New("Frame", {
        Parent = Content,
        Position = UDim2.fromOffset(0, HEADER),
        Size = UDim2.new(1, 0, 1, -HEADER),
        BackgroundTransparency = 1,
        ZIndex = 2,
    })
    self._pages = Pages

    ------------------------------------------------------------------ minimize pill (mobile friendly)
    local Pill = New("TextButton", {
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, 14),
        Size = UDim2.fromOffset(0, 40),
        AutomaticSize = Enum.AutomaticSize.X,
        Text = "",
        Visible = false,
        ZIndex = 30,
    }, { BackgroundColor3 = "Background" })
    Round(Pill, "full")
    Rim(Pill, "StrokeHover", 0.1, 0.7)
    Pressable(Pill, 0.94)
    New("UIPadding", { Parent = Pill, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 16) })
    New("UIListLayout", {
        Parent = Pill,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 9),
    })
    local PillLogo = New("Frame", { Parent = Pill, Size = UDim2.fromOffset(26, 26), LayoutOrder = 1, ZIndex = 31 }, { BackgroundColor3 = "Accent" })
    Round(PillLogo, "full")
    Shade(PillLogo, 0.68, 60)
    Rim(PillLogo, "Text", 0.4, 1)
    local mark = opts.Logo or string.sub(title, 1, 1)
    if IsImageRef(mark) then
        New("ImageLabel", {
            Parent = PillLogo, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(15, 15), Image = ResolveIcon(mark), ScaleType = Enum.ScaleType.Fit, ZIndex = 32,
        }, { ImageColor3 = "AccentDark" })
    else
        Label(PillLogo, string.sub(tostring(mark), 1, 2), 13, "AccentDark", Enum.Font.GothamBlack, {
            Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
            TextTruncate = Enum.TextTruncate.None, ZIndex = 32,
        })
    end
    Label(Pill, title, 13, "Text", Enum.Font.GothamBold, {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        TextTruncate = Enum.TextTruncate.None, LayoutOrder = 2, ZIndex = 31,
    })
    Label(Pill, "Tap to open", 11, "Muted", nil, {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        TextTruncate = Enum.TextTruncate.None, LayoutOrder = 3, ZIndex = 31,
    })
    self._pill = Pill
    local pillDragged = MakeDraggable(Pill, Pill, bin)
    Pill.MouseButton1Click:Connect(function()
        if pillDragged() then return end
        self:Show()
    end)

    IconButton(Header, "x", UDim2.new(1, -16, 0, 20), function() self:Destroy() end, "Error")
    IconButton(Header, "minus", UDim2.new(1, -54, 0, 20), function() self:Minimize() end)
    -- optional Discord invite button (Discord = "url" or Discord = true + Invite/DiscordInvite)
    local discordUrl
    if type(opts.Discord) == "string" and opts.Discord ~= "" then
        discordUrl = opts.Discord
    elseif opts.Discord == true then
        discordUrl = opts.Invite or opts.DiscordInvite
    end
    if type(discordUrl) == "string" and discordUrl ~= "" then
        self.DiscordInvite = discordUrl
        IconButton(Header, "discord", UDim2.new(1, -92, 0, 20), function()
            if SetClipboard(discordUrl) == true then
                Library:Notify({ Title = "Discord", Content = "Invite link copied", Type = "success", Duration = 3 })
            else
                Library:Notify({ Title = "Discord", Content = discordUrl, Type = "info", Duration = 6 })
            end
            local openFn = FirstFn(SafeIndex(env, "openurl"), SafeIndex(env, "open_url"))
            if openFn then pcall(openFn, discordUrl) end
        end)
    end

    -- global key handling: toggle key + keybind elements
    Track(UserInputService.InputBegan:Connect(function(input, processed)
        if not self.Alive then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        if Listening or Clock() - ConsumedAt < 0.25 then return end
        local name = KeyName(input.KeyCode)
        if not name then return end
        if processed or TypingInTextBox() then return end
        if name == self.ToggleKey then
            self:Toggle()
            return
        end
        for _, kb in ipairs(self._keybinds) do
            if kb.Value == name and kb.Alive then
                SafeCall(kb.Name, kb.Callback, name)
            end
        end
    end), bin)

    OnViewportChanged(function()
        self._target = FitScale(self._size.X, self._size.Y)
        if self.Open then Tween(scale, { Scale = self._target }, 0.2) end
    end, bin)

    MakeDraggable(Root, SideHeader, bin)
    MakeDraggable(Root, Header, bin)

    ------------------------------------------------ resize grip (bottom-right, mouse + touch)
    self.MinSize = Vector2.new(460, 300)
    self.Resizable = opts.Resizable ~= false
    local function clampSize(w, h)
        local vp = Viewport()
        local sc = scale.Scale > 0 and scale.Scale or 1
        local maxW, maxH = math.max(self.MinSize.X, vp.X / sc), math.max(self.MinSize.Y, vp.Y / sc)
        return math.floor(math.clamp(tonumber(w) or W, self.MinSize.X, maxW) + 0.5),
            math.floor(math.clamp(tonumber(h) or H, self.MinSize.Y, maxH) + 0.5)
    end
    function self:SetSize(w, h)
        if typeof(w) == "Vector2" then w, h = w.X, w.Y elseif type(w) == "table" then w, h = w[1], w[2] end
        local nw, nh = clampSize(w, h)
        self._size = Vector2.new(nw, nh)
        Root.Size = UDim2.fromOffset(nw, nh)
        return nw, nh
    end
    function self:GetSize() return self._size.X, self._size.Y end
    local Grip = New("TextButton", {
        Name = "ResizeGrip",
        Parent = Root,
        AnchorPoint = Vector2.new(1, 1),
        Position = UDim2.new(1, 0, 1, 0),
        -- touch: hit area >= 36 real pixels once multiplied by the UIScale
        Size = IsTouchOnly() and UDim2.fromOffset(math.max(36, math.ceil(36 / math.max(self._target, 0.4))), math.max(36, math.ceil(36 / math.max(self._target, 0.4))))
            or UDim2.fromOffset(22, 22),
        Text = "",
        BackgroundTransparency = 1,
        Visible = self.Resizable,
        ZIndex = 60,
    })
    self._grip = Grip
    for i = 1, 2 do
        local dot = New("Frame", {
            Parent = Grip,
            AnchorPoint = Vector2.new(1, 1),
            Position = UDim2.new(1, -5 - (i - 1) * 4, 1, -5),
            Size = UDim2.fromOffset(2, 6 + (2 - i) * 4),
            BackgroundTransparency = 0.5,
            ZIndex = 61,
        }, { BackgroundColor3 = "Muted" })
        Round(dot, "full")
    end
    do
        local MB1, Touch = Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch
        local resizing, rType, rStart, rSize = false, nil, nil, nil
        Track(Grip.InputBegan:Connect(function(input)
            local t = input.UserInputType
            if self.Resizable and (t == MB1 or t == Touch) then
                resizing, rType, rStart, rSize = true, t, input.Position, self._size
            end
        end), bin)
        Track(UserInputService.InputChanged:Connect(function(input)
            if not resizing then return end
            local t = input.UserInputType
            if t == Enum.UserInputType.MouseMovement or (t == Touch and rType == Touch) then
                local sc = scale.Scale > 0 and scale.Scale or 1
                local d = input.Position - rStart
                -- the window is centre-anchored: growing by d keeps the top-left corner in place
                local nw, nh = clampSize(rSize.X + d.X / sc, rSize.Y + d.Y / sc)
                local dw, dh = nw - self._size.X, nh - self._size.Y
                self:SetSize(nw, nh)
                local p = Root.Position
                Root.Position = UDim2.new(p.X.Scale, p.X.Offset + dw * sc / 2, p.Y.Scale, p.Y.Offset + dh * sc / 2)
            end
        end), bin)
        Track(UserInputService.InputEnded:Connect(function(input)
            local t = input.UserInputType
            if resizing and (t == MB1 or t == Touch) then resizing = false end
        end), bin)
    end
    function self:SetResizable(v)
        self.Resizable = v ~= false
        Grip.Visible = self.Resizable
    end

    return self
end

function Window:Show()
    if self.Open or not self.Alive then return end
    self.Open = true
    self._pill.Visible = false
    self.Root.Visible = true
    self._scale.Scale = self._target * 0.94
    self._cover.Visible = true
    self._cover.BackgroundTransparency = 0
    Tween(self._scale, { Scale = self._target }, 0.35, Enum.EasingStyle.Back)
    Tween(self._cover, { BackgroundTransparency = 1 }, 0.25)
    Tween(self._shadow, { ImageTransparency = 0.45 }, 0.25)
    task.delay(0.26, function() if self.Open and self.Alive then self._cover.Visible = false end end)
end

function Window:Hide(showPill)
    if self._prompt then pcall(self._prompt, false) end
    if Library.HideTooltip then Library:HideTooltip() end
    if not self.Open or not self.Alive then return end
    if self._cancelListen then pcall(self._cancelListen) end
    self.Open = false
    self._cover.Visible = true
    Tween(self._scale, { Scale = self._target * 0.94 }, 0.2)
    Tween(self._cover, { BackgroundTransparency = 0 }, 0.18)
    Tween(self._shadow, { ImageTransparency = 1 }, 0.2)
    task.delay(0.21, function()
        if not self.Open and self.Alive then self.Root.Visible = false end
    end)
    if showPill or IsTouchOnly() then
        self._pill.Visible = true
        local ps = self._pill:FindFirstChildOfClass("UIScale")
        if ps then
            ps.Scale = 0.6
            Tween(ps, { Scale = 1 }, 0.35, Enum.EasingStyle.Back)
        end
    end
end

function Window:Minimize()
    if self._prompt then pcall(self._prompt, false) end
    if Library.HideTooltip then Library:HideTooltip() end
    self:Hide(true)
end

function Window:Toggle()
    if self.Open then self:Hide(false) else self:Show() end
end

function Window:SetToggleKey(key)
    local n = KeyName(key)
    if n and n ~= "None" then
        self.ToggleKey = n
        -- keep the Settings "Toggle key" keybind in sync (silent: no callback loop)
        local kb = self._toggleKeyEl
        if kb and kb.Alive and kb.Value ~= n then pcall(function() kb:Set(n, true) end) end
    end
    return self.ToggleKey
end

function Window:SetTitle(text)
    local old = self.Title
    self.Title = tostring(text)
    if WindowRegistry[old] == self then WindowRegistry[old] = nil end
    if self.Alive then WindowRegistry[self.Title] = self end
    pcall(function() self.Gui:SetAttribute("SolUITitle", self.Title) end)
    self._titleLabel.Text = self.Title
end

function Window:SetSubtitle(text)
    self.Subtitle = tostring(text)
    self._subtitleLabel.Text = self.Subtitle
    self._subtitleLabel.Parent.Visible = self.Subtitle ~= ""
end

function Window:SetTheme(name)
    return Library:SetTheme(name)
end

function Window:Notify(opts, content, duration, kind)
    return Library:Notify(opts, content, duration, kind)
end

function Window:Destroy(instant)
    if self._prompt then pcall(self._prompt, false) end
    if Library.HideTooltip then Library:HideTooltip() end
    if not self.Alive then return end
    self.Alive = false
    self.Open = false
    local function finish()
        -- every element is destroyed: destroy hooks run, bins are emptied, Options / Flags entries go away
        DestroyElements(self._elements)
        for _, t in ipairs(self.Tabs) do t.Alive = false end
        for flag, el in pairs(self.Options) do
            if Library.Options[flag] == el then
                Library.Options[flag] = nil
                Library.Flags[flag] = nil
            end
            el.Alive = false
            if el._bin then EmptyBin(el._bin) end
        end
        ClearTable(self.Options)
        ClearTable(self._keybinds)
        -- theme listeners of this window (Settings tab) go away with it
        if self._themeListeners then
            for _, fn in ipairs(self._themeListeners) do
                for i = #ThemeListeners, 1, -1 do
                    if ThemeListeners[i] == fn then table.remove(ThemeListeners, i) end
                end
            end
            self._themeListeners = nil
        end
        EmptyBin(self._trash)
        for i = #Library.Windows, 1, -1 do
            if Library.Windows[i] == self then table.remove(Library.Windows, i) end
        end
        if WindowRegistry[self.Title] == self then WindowRegistry[self.Title] = nil end
        -- closing the last window unloads the whole library
        if #Library.Windows == 0 and not Library._unloading then Library:Unload() end
    end
    if instant or not self.Root or not self.Root.Parent then
        finish()
        return
    end
    pcall(function()
        self._cover.Visible = true
        Tween(self._scale, { Scale = self._target * 0.92 }, 0.2)
        Tween(self._cover, { BackgroundTransparency = 0 }, 0.2)
        Tween(self._shadow, { ImageTransparency = 1 }, 0.2)
    end)
    task.delay(0.22, finish)
end

function Library:Unload()
    if Library._unloading then return end
    Library._unloading = true
    for _, fn in ipairs(UnloadListeners) do
        local ok, err = pcall(fn)
        if not ok then warn("[SolUI] OnUnload error: " .. tostring(err)) end
    end
    ClearTable(UnloadListeners)
    for i = #Library.Windows, 1, -1 do
        local w = Library.Windows[i]
        pcall(function() w:Destroy(true) end)
    end
    ClearTable(Library.Windows)
    EmptyBin(LibTrash)
    pcall(function() if NotifGui then NotifGui:Destroy() end end)
    NotifGui, NotifHolder = nil, nil
    ClearTable(Library.Options)
    ClearTable(Library.Flags)
    ClearTable(Registry)
    ClearTable(GlowLayers)
    ClearTable(ThemeListeners)
    Listening = false
    Library.Unloaded = true
    Library._unloading = false
end
Library.Destroy = Library.Unload

----------------------------------------------------------------------------------------------------
-- Tabs
----------------------------------------------------------------------------------------------------

function Window:_layoutTabs()
    local n = #self.Tabs
    self._tabCanvas.Size = UDim2.new(1, 0, 0, n * 40)
    self._tabScroll.CanvasSize = UDim2.new(0, 0, 0, n * 40)
end

function Window:SelectTab(target)
    if Library.HideTooltip then Library:HideTooltip() end
    if self._cancelListen then pcall(self._cancelListen) end
    local tab = target
    if type(target) == "string" then
        tab = nil
        for _, t in ipairs(self.Tabs) do
            if t.Name == target then tab = t end
        end
    elseif type(target) == "number" then
        tab = self.Tabs[target]
    end
    if not tab or not tab.Alive then return end
    local previous = self.CurrentTab
    for i, t in ipairs(self.Tabs) do
        local on = t == tab
        t._page.Visible = on
        Bind(t._label, "TextColor3", on and "Text" or "Muted", 0.15)
        t._label.Font = on and Enum.Font.GothamBold or Enum.Font.GothamMedium
        Bind(t._icon, "ImageColor3", on and "Accent" or "Muted", 0.15)
        if on then
            t.Index = i
            self._indicator.Visible = true
            Tween(self._indicator, { Position = UDim2.fromOffset(10, (i - 1) * 40) }, 0.35, Enum.EasingStyle.Quint)
        end
    end
    self.CurrentTab = tab
    self._pageTitle.Text = tab.Title
    self._pageDesc.Text = tab.Description
    if tab.Description == "" then
        self._pageTitle.Position = UDim2.fromOffset(22, 23)
    else
        self._pageTitle.Position = UDim2.fromOffset(22, 15)
    end
    if previous ~= tab then
        local pad = tab._padding
        pad.PaddingTop = UDim.new(0, 28)
        Tween(pad, { PaddingTop = UDim.new(0, 16) }, 0.3)
    end
end

function Window:CreateTab(opts, icon)
    if type(opts) ~= "table" then opts = { Name = opts, Icon = icon } end
    local name = tostring(opts.Name or opts.Title or ("Tab " .. tostring(#self.Tabs + 1)))
    local tab = setmetatable({
        Name = name,
        Title = tostring(opts.Title or name),
        Description = tostring(opts.Description or opts.Desc or ""),
        Window = self,
        Alive = true,
        _order = 0,
    }, Tab)
    local index = #self.Tabs + 1
    self.Tabs[index] = tab
    tab.Index = index

    local btn = New("TextButton", {
        Parent = self._tabStack,
        Size = UDim2.new(1, 0, 0, 38),
        Text = "",
        BackgroundTransparency = 1,
        LayoutOrder = index,
        ZIndex = 5,
    })
    local iconName = opts.Icon
    if ResolveIcon(iconName) == "" then iconName = "layout-grid" end
    tab._icon = Icon(btn, iconName, 16, "Muted", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 14, 0.5, 0),
        ZIndex = 6,
    })
    tab._label = Label(btn, name, 13, "Muted", Enum.Font.GothamMedium, {
        Position = UDim2.fromOffset(40, 0),
        Size = UDim2.new(1, -48, 1, 0),
        ZIndex = 6,
    })
    tab._button = btn
    btn.MouseEnter:Connect(function()
        if self.CurrentTab ~= tab then Bind(tab._label, "TextColor3", "Text", 0.12) end
    end)
    btn.MouseLeave:Connect(function()
        if self.CurrentTab ~= tab then Bind(tab._label, "TextColor3", "Muted", 0.2) end
    end)
    btn.MouseButton1Click:Connect(function() self:SelectTab(tab) end)

    local page = New("ScrollingFrame", {
        Parent = self._pages,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ScrollBarThickness = 3,
        ScrollBarImageTransparency = 0.4,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        Visible = false,
        ZIndex = 2,
    }, { ScrollBarImageColor3 = "Accent" })
    pcall(function() page.AutomaticCanvasSize = Enum.AutomaticSize.Y end)
    tab._padding = New("UIPadding", {
        Parent = page, PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20),
        PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 18),
    })
    local layout = New("UIListLayout", { Parent = page, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) })
    -- manual canvas fallback (executors / old clients where AutomaticCanvasSize is missing or buggy)
    local function fit()
        pcall(function()
            page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 34)
        end)
    end
    pcall(function()
        Track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit), self._trash)
    end)
    fit()
    tab._page = page
    tab._container = page
    tab._layout = layout

    self:_layoutTabs()
    if index == 1 then self:SelectTab(tab) end
    return tab
end
Window.AddTab = Window.CreateTab

function Tab:Select()
    self.Window:SelectTab(self)
end

function Tab:SetTitle(text)
    self.Title = tostring(text)
    if self.Window.CurrentTab == self then self.Window._pageTitle.Text = self.Title end
end

function Tab:SetDescription(text)
    self.Description = tostring(text or "")
    if self.Window.CurrentTab == self then self.Window:SelectTab(self) end
end

function Tab:Destroy()
    if not self.Alive then return end
    DestroyElements(self._elements)
    self.Alive = false
    local w = self.Window
    for i = #w.Tabs, 1, -1 do
        if w.Tabs[i] == self then table.remove(w.Tabs, i) end
    end
    pcall(function() self._button:Destroy() end)
    pcall(function() self._page:Destroy() end)
    w:_layoutTabs()
    if w.CurrentTab == self then
        w.CurrentTab = nil
        if w.Tabs[1] then w:SelectTab(w.Tabs[1]) else w._indicator.Visible = false end
    else
        if w.CurrentTab then w:SelectTab(w.CurrentTab) end
    end
end

----------------------------------------------------------------------------------------------------
-- Sections (v3 groupbox)
----------------------------------------------------------------------------------------------------

local function NextOrder(owner)
    owner._order = owner._order + 1
    return owner._order
end

function Tab:CreateSection(opts)
    if type(opts) ~= "table" then opts = { Name = opts } end
    local name = tostring(opts.Name or opts.Title or "Section")
    local box = New("Frame", {
        Parent = self._container,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = NextOrder(self),
        ZIndex = 2,
    }, { BackgroundColor3 = "Surface2" })
    Round(box, 12)
    Rim(box, "StrokeHover", 0.2, 0.85)
    New("UIListLayout", { Parent = box, SortOrder = Enum.SortOrder.LayoutOrder })

    local header = New("TextButton", {
        Parent = box,
        Size = UDim2.new(1, 0, 0, 42),
        Text = "",
        BackgroundTransparency = 1,
        LayoutOrder = 1,
        ZIndex = 3,
    })
    local textX = 26
    if opts.Icon and ResolveIcon(opts.Icon) ~= "" then
        local tile = New("Frame", {
            Parent = header,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 12, 0.5, 0),
            Size = UDim2.fromOffset(26, 26),
            BackgroundTransparency = 0.86,
            ZIndex = 3,
        }, { BackgroundColor3 = "Accent" })
        Round(tile, 8)
        Outline(tile, "Accent", 1, 0.75)
        Icon(tile, opts.Icon, 14, "Accent", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            ZIndex = 4,
        })
        textX = 48
    else
        local m = New("Frame", {
            Parent = header,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 14, 0.5, 0),
            Size = UDim2.fromOffset(3, 14),
            ZIndex = 4,
        }, { BackgroundColor3 = "Accent" })
        Round(m, "full")
    end
    local titleLabel = Label(header, name, 13, "Text", Enum.Font.GothamBold, {
        Position = UDim2.fromOffset(textX, 0),
        Size = UDim2.new(1, -(textX + 120), 1, 0),
        ZIndex = 4,
    })
    local right = Label(header, tostring(opts.Value or ""), 11, "Muted", nil, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -36, 0.5, 0),
        Size = UDim2.fromOffset(100, 16),
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 4,
    })
    local chev = Icon(header, "chevron-down", 14, "Muted", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -14, 0.5, 0),
        ZIndex = 4,
    })
    local divider = New("Frame", {
        Parent = box,
        Size = UDim2.new(1, 0, 0, 1),
        LayoutOrder = 2,
        ZIndex = 3,
    }, { BackgroundColor3 = "Stroke" })
    New("UIGradient", { Parent = divider, Transparency = Stops({ { 0, 1 }, { 0.12, 0 }, { 0.88, 0 }, { 1, 1 } }) })
    local body = New("Frame", {
        Parent = box,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 3,
        ZIndex = 3,
    })
    New("UIPadding", {
        Parent = body, PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
        PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8),
    })
    New("UIListLayout", { Parent = body, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })

    local sec = setmetatable({
        Name = name,
        Tab = self,
        Window = self.Window,
        Alive = true,
        Collapsed = false,
        Instance = box,
        _isSection = true,
        _container = body,
        _order = 0,
        _title = titleLabel,
        _right = right,
    }, Section)

    function sec:SetCollapsed(v)
        sec.Collapsed = v == true
        body.Visible = not sec.Collapsed
        divider.Visible = not sec.Collapsed
        Tween(chev, { Rotation = sec.Collapsed and -90 or 0 }, 0.25)
    end
    header.MouseEnter:Connect(function() Bind(chev, "ImageColor3", "Text", 0.15) end)
    header.MouseLeave:Connect(function() Bind(chev, "ImageColor3", "Muted", 0.25) end)
    header.MouseButton1Click:Connect(function() sec:SetCollapsed(not sec.Collapsed) end)
    if opts.Collapsed then sec:SetCollapsed(true) end

    self._section = sec
    return sec
end
Tab.AddSection = Tab.CreateSection

-- elements created on the tab after this go straight onto the page again
function Tab:EndSection()
    self._section = nil
end

function Section:SetTitle(text) self.Name = tostring(text); self._title.Text = self.Name end
function Section:SetValue(text) self._right.Text = tostring(text or "") end
function Section:Destroy()
    if not self.Alive then return end
    DestroyElements(self._elements)
    self.Alive = false
    if self.Tab._section == self then self.Tab._section = nil end
    pcall(function() self.Instance:Destroy() end)
end
function Section:CreateSection(opts) return self.Tab:CreateSection(opts) end
Section.AddSection = Section.CreateSection

----------------------------------------------------------------------------------------------------
-- Elements
----------------------------------------------------------------------------------------------------

local Element = {}
Element.__index = Element

function Element:SetVisible(v)
    self.Visible = v ~= false
    pcall(function() self.Instance.Visible = self.Visible end)
end

function Element:OnChanged(fn)
    if type(fn) == "function" then
        self._listeners = self._listeners or {}
        self._listeners[#self._listeners + 1] = fn
    end
    return self
end

function Element:Destroy()
    if not self.Alive then return end
    self.Alive = false
    if self._onDestroy then
        for _, fn in ipairs(self._onDestroy) do
            local ok, err = pcall(fn)
            if not ok then warn("[SolUI] destroy hook error: " .. tostring(err)) end
        end
        self._onDestroy = nil
    end
    local w = self.Window
    if self.Flag then
        if Library.Options[self.Flag] == self then
            Library.Options[self.Flag] = nil
            Library.Flags[self.Flag] = nil
        end
        if w and w.Options[self.Flag] == self then w.Options[self.Flag] = nil end
    end
    if w then
        RemoveFrom(w._keybinds, self)
        RemoveFrom(w._elements, self)
    end
    RemoveFrom(self.Tab and self.Tab._elements, self)
    RemoveFrom(self.Section and self.Section._elements, self)
    if self._bin then EmptyBin(self._bin) end
    pcall(function() self.Instance:Destroy() end)
end

-- adds fn to the hooks run when the element is destroyed
local function OnDestroy(el, fn)
    el._onDestroy = el._onDestroy or {}
    el._onDestroy[#el._onDestroy + 1] = fn
end

local function MakeElement(kind, owner, opts)
    local tab = owner._isSection and owner.Tab or owner
    local section
    if owner._isSection then
        section = owner
    elseif owner._section and owner._section.Alive then
        section = owner._section
    end
    local el = setmetatable({
        Type = kind,
        Name = tostring(opts.Name or opts.Title or kind),
        Flag = opts.Flag,
        Callback = opts.Callback,
        Window = owner.Window,
        Tab = tab,
        Section = section,
        Alive = true,
        Visible = true,
        _bin = {},
    }, Element)
    local w = owner.Window
    w._elements = w._elements or {}
    w._elements[#w._elements + 1] = el
    tab._elements = tab._elements or {}
    tab._elements[#tab._elements + 1] = el
    if section then
        section._elements = section._elements or {}
        section._elements[#section._elements + 1] = el
    end
    return el
end

local function Register(el)
    if el.Flag == nil then return end
    el.Flag = tostring(el.Flag)
    Library.Flags[el.Flag] = el.Value
    Library.Options[el.Flag] = el
    el.Window.Options[el.Flag] = el
end

-- value changed: update the flag, run the callback and OnChanged listeners (all protected)
local function Changed(el, ...)
    if el.Flag then Library.Flags[el.Flag] = el.Value end
    SafeCall(el.Name, el.Callback, ...)
    if el._listeners then
        for _, fn in ipairs(el._listeners) do SafeCall(el.Name, fn, ...) end
    end
end

local function Target(owner)
    if owner._isSection then return owner, true end
    local s = owner._section
    if s and s.Alive then return s, true end
    return owner, false
end

-- element holder: a row inside a section, or a standalone card directly on the page
-- mode: nil = fixed height, "bare" = no card, "auto" = height follows the content
local function Host(owner, h, mode, clip)
    local o, inSection = Target(owner)
    local card = (not inSection) and mode ~= "bare"
    local pad = card and 4 or 0
    local holder = New("Frame", {
        Parent = o._container,
        Size = UDim2.new(1, 0, 0, (mode == "auto") and 0 or (h + pad * 2)),
        BackgroundTransparency = card and 0 or 1,
        ClipsDescendants = clip == true,
        LayoutOrder = NextOrder(o),
        ZIndex = 3,
    }, card and { BackgroundColor3 = "Surface2" } or nil)
    if card then
        Round(holder, 12)
        Rim(holder, "StrokeHover", 0.2, 0.85)
    end
    local inner
    if mode == "auto" then
        holder.AutomaticSize = Enum.AutomaticSize.Y
        if pad > 0 then
            New("UIPadding", {
                Parent = holder, PaddingLeft = UDim.new(0, pad), PaddingRight = UDim.new(0, pad),
                PaddingTop = UDim.new(0, pad), PaddingBottom = UDim.new(0, pad),
            })
        end
        inner = New("Frame", {
            Parent = holder,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            BackgroundTransparency = 1,
            ZIndex = 3,
        })
    else
        inner = New("Frame", {
            Parent = holder,
            Position = UDim2.fromOffset(pad, pad),
            Size = UDim2.new(1, -pad * 2, 0, h),
            BackgroundTransparency = 1,
            ZIndex = 3,
        })
    end
    local host = { holder = holder, inner = inner, pad = pad, inSection = inSection, card = card }
    function host.SetHeight(hh, t)
        local s = UDim2.new(1, 0, 0, hh + pad * 2)
        inner.Size = UDim2.new(1, -pad * 2, 0, hh)
        if t then Tween(holder, { Size = s }, t) else holder.Size = s end
    end
    return host
end

-- hoverable row (TextButton) filling the top of a host
local function HoverRow(parent, h)
    local row = New("TextButton", {
        Parent = parent,
        Size = UDim2.new(1, 0, 0, h),
        Text = "",
        BackgroundTransparency = 1,
        ZIndex = 3,
    }, { BackgroundColor3 = "Surface3" })
    Round(row, 8)
    row.MouseEnter:Connect(function() Tween(row, { BackgroundTransparency = 0.6 }, 0.12) end)
    row.MouseLeave:Connect(function() Tween(row, { BackgroundTransparency = 1 }, 0.2) end)
    return row
end

-- name (+ optional description) on the left of a row
local function RowText(row, name, desc, h, rightScale, rightOffset)
    local title = Label(row, name, 13, "Text", Enum.Font.GothamMedium, {
        Position = UDim2.fromOffset(10, desc and 7 or 0),
        Size = UDim2.new(1 - (rightScale or 0), -(rightOffset or 0), 0, desc and 18 or h),
        ZIndex = 4,
    })
    local d
    if desc then
        d = Label(row, desc, 11, "Muted", nil, {
            Position = UDim2.fromOffset(10, 25),
            Size = UDim2.new(1 - (rightScale or 0), -(rightOffset or 0), 0, 14),
            ZIndex = 4,
        })
    end
    return title, d
end

local function Opts(o, field)
    if type(o) == "table" then return o end
    local t = {}
    t[field or "Name"] = o
    return t
end

local function Desc(o)
    local d = o.Description or o.Desc
    if d == nil or d == "" then return nil end
    return tostring(d)
end

local Creators = {}

------------------------------------------------------------------ Button
function Creators:CreateButton(opts)
    opts = Opts(opts)
    local el = MakeElement("Button", self, opts)
    local desc = Desc(opts)
    local armed = false
    local label
    local function fire()
        if not el.Alive then return end
        if opts.Confirm then
            if not armed then
                armed = true
                label.Text = type(opts.Confirm) == "string" and opts.Confirm or "Click again to confirm"
                task.delay(3, function()
                    if armed then
                        armed = false
                        pcall(function() label.Text = el._text end)
                    end
                end)
                return
            end
            armed = false
            label.Text = el._text
        end
        Changed(el)
    end
    local host
    if desc then
        host = Host(self, 46)
        el._text = tostring(opts.ButtonText or "Run")
        local nameLabel = RowText(host.inner, el.Name, desc, 46, 0, 112)
        el._nameLabel = nameLabel
        local _
        _, label = Chip({
            Parent = host.inner,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -8, 0.5, 0),
            Size = UDim2.fromOffset(92, 28),
            Text = el._text,
            Icon = opts.Icon or "play",
            IconSize = 12,
            TextSize = 12,
            Style = opts.Style or "primary",
            Radius = 8,
            ZIndex = 4,
            Callback = fire,
        })
    else
        local inSection = select(2, Target(self))
        host = Host(self, inSection and 40 or 36, "bare")
        el._text = el.Name
        local _
        _, label = Chip({
            Parent = host.inner,
            Position = inSection and UDim2.fromOffset(4, 3) or UDim2.fromOffset(0, 0),
            Size = inSection and UDim2.new(1, -8, 0, 34) or UDim2.new(1, 0, 0, 36),
            Text = el._text,
            Icon = opts.Icon,
            Style = opts.Style,
            ZIndex = 4,
            Callback = fire,
        })
    end
    el.Instance = host.holder
    function el:SetText(t)
        if desc and el._nameLabel then
            -- with a description the chip keeps its ButtonText, only the row title changes
            el.Name = tostring(t)
            el._nameLabel.Text = el.Name
        else
            el._text = tostring(t)
            el.Name = el._text
            if not armed then label.Text = el._text end
        end
    end
    function el:Fire() Changed(el) end
    return el
end

------------------------------------------------------------------ Toggle
function Creators:CreateToggle(opts)
    opts = Opts(opts)
    local el = MakeElement("Toggle", self, opts)
    local desc = Desc(opts)
    local h = desc and 46 or 34
    local host = Host(self, h)
    el.Instance = host.holder
    local row = HoverRow(host.inner, h)
    local tTitle, tDesc = RowText(row, el.Name, desc, h, 0, 72)
    -- optional icon left of the title (Icon = "name" / rbxassetid)
    if opts.Icon and ResolveIcon(opts.Icon) ~= "" then
        local tile = New("Frame", {
            Parent = row,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 8, 0.5, 0),
            Size = UDim2.fromOffset(24, 24),
            BackgroundTransparency = 0.82,
            ZIndex = 4,
        }, { BackgroundColor3 = "Accent" })
        Round(tile, 7)
        el._icon = Icon(tile, opts.Icon, 13, "Accent", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            ZIndex = 5,
        })
        for _, l in ipairs({ tTitle, tDesc }) do
            if l then
                l.Position = UDim2.new(0, 42, 0, l.Position.Y.Offset)
                l.Size = UDim2.new(1, -(72 + 32), 0, l.Size.Y.Offset)
            end
        end
    end
    local value = opts.Default == true or opts.Value == true
    el.Value = value
    local track = New("Frame", {
        Parent = row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(38, 22),
        ZIndex = 4,
    }, { BackgroundColor3 = value and "Accent" or "Surface3" })
    Round(track, "full")
    Shade(track, 0.8, 90)
    local trackStroke = Outline(track, value and "Accent" or "Stroke")
    local knob = New("Frame", {
        Parent = track,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = value and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        ZIndex = 5,
    }, { BackgroundColor3 = value and "AccentDark" or "Muted" })
    Round(knob, "full")

    function el:Set(v, silent)
        v = v == true
        if v == el.Value then
            if el.Flag then Library.Flags[el.Flag] = v end
            return
        end
        el.Value = v
        Bind(track, "BackgroundColor3", v and "Accent" or "Surface3", 0.2)
        Bind(trackStroke, "Color", v and "Accent" or "Stroke", 0.2)
        Bind(knob, "BackgroundColor3", v and "AccentDark" or "Muted", 0.2)
        Tween(knob, { Position = v and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, 0.25, Enum.EasingStyle.Back)
        if silent then
            if el.Flag then Library.Flags[el.Flag] = v end
        else
            Changed(el, v)
        end
    end
    function el:Get() return el.Value end
    function el:Toggle() el:Set(not el.Value) end
    el._save = function() return el.Value end
    el._load = function(v) if type(v) == "boolean" then el:Set(v) end end
    row.MouseButton1Click:Connect(function() el:Set(not el.Value) end)
    Register(el)
    return el
end

------------------------------------------------------------------ Slider
-- number of decimals shown for an increment (works for 0.25, 0.1 and 1e-05 alike, max 4)
local function Decimals(inc)
    inc = tonumber(inc)
    if not inc or inc <= 0 then return 0 end
    for d = 0, 4 do
        local x = inc * (10 ^ d)
        if math.abs(x - math.floor(x + 0.5)) < 1e-6 then return d end
    end
    return 4
end

function Creators:CreateSlider(opts)
    opts = Opts(opts)
    local el = MakeElement("Slider", self, opts)
    local desc = Desc(opts)
    local min = tonumber(opts.Min) or 0
    local max = tonumber(opts.Max) or 100
    if max < min then min, max = max, min end
    if max == min then max = min + 1 end
    local inc = tonumber(opts.Increment or opts.Rounding) or 1
    if inc <= 0 then inc = 1 end
    local decimals = tonumber(opts.Decimals) and math.clamp(math.floor(tonumber(opts.Decimals)), 0, 6) or Decimals(inc)
    local suffix = tostring(opts.Suffix or "")
    local prefix = tostring(opts.Prefix or "")
    local isRange = opts.Range == true
    el.Min, el.Max, el.Increment, el.Decimals, el.Range = min, max, inc, decimals, isRange

    local h = desc and 62 or 50
    local trackY = desc and 47 or 35
    local host = Host(self, h)
    el.Instance = host.holder
    local row = New("Frame", { Parent = host.inner, Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, ZIndex = 3 }, { BackgroundColor3 = "Surface3" })
    Round(row, 8)
    Label(row, el.Name, 13, "Text", Enum.Font.GothamMedium, {
        Position = UDim2.fromOffset(10, 7),
        Size = UDim2.new(1, isRange and -134 or -96, 0, 18),
        ZIndex = 4,
    })
    if desc then
        Label(row, desc, 11, "Muted", nil, {
            Position = UDim2.fromOffset(10, 25),
            Size = UDim2.new(1, isRange and -134 or -96, 0, 14),
            ZIndex = 4,
        })
    end
    local valueWrap = New("Frame", {
        Parent = row,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 6),
        Size = UDim2.fromOffset(isRange and 110 or 72, 22),
        ZIndex = 4,
    }, { BackgroundColor3 = "Background" })
    Round(valueWrap, 7)
    local valueStroke = Rim(valueWrap, "StrokeHover", 0.25, 0.8)
    local valueBox = New("TextBox", {
        Parent = valueWrap,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 5,
    }, { TextColor3 = "Text" })

    local track = New("Frame", {
        Parent = row,
        Position = UDim2.fromOffset(10, trackY),
        Size = UDim2.new(1, -20, 0, 6),
        ZIndex = 4,
    }, { BackgroundColor3 = "Surface3" })
    Round(track, "full")
    Outline(track, "Stroke", 1, 0.3)
    local fill = New("Frame", {
        Parent = track,
        Size = UDim2.new(0, 0, 1, 0),
        ZIndex = 5,
    }, { BackgroundColor3 = "Accent" })
    Round(fill, "full")
    Shade(fill, 0.7, 180)
    local knob = New("Frame", {
        Parent = track,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        ZIndex = 7,
    }, { BackgroundColor3 = "Text" })
    Round(knob, "full")
    Outline(knob, "Accent", 2)
    SoftGlow(knob, "Accent", UDim2.fromScale(0.5, 0.5), UDim2.fromOffset(34, 34), 0.75, 6)
    -- second knob for Range = true
    local knob2
    if isRange then
        knob2 = New("Frame", {
            Parent = track,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.fromOffset(14, 14),
            ZIndex = 7,
        }, { BackgroundColor3 = "Text" })
        Round(knob2, "full")
        Outline(knob2, "Accent", 2)
    end
    -- tall, touch-friendly hit area (36px) around the 6px track
    local hit = New("TextButton", {
        Parent = row,
        Position = UDim2.fromOffset(4, trackY - 15),
        Size = UDim2.new(1, -8, 0, 36),
        Text = "",
        BackgroundTransparency = 1,
        ZIndex = 8,
    })

    local function num(v) return string.format("%." .. decimals .. "f", v) end
    local function fmt(v) return prefix .. num(v) .. suffix end
    local function snap(v)
        v = math.clamp(tonumber(v) or min, min, max)
        v = math.floor((v - min) / inc + 0.5) * inc + min
        v = math.clamp(v, min, max)
        return tonumber(num(v))
    end
    local function alpha(v) return (v - min) / (max - min) end
    local TI = 0.12
    local function render(t)
        local lo, hi
        if isRange then lo, hi = alpha(el.Value[1]), alpha(el.Value[2]) else lo, hi = 0, alpha(el.Value) end
        local goals = {
            { fill, { Position = UDim2.new(lo, 0, 0, 0), Size = UDim2.new(hi - lo, 0, 1, 0) } },
            { knob, { Position = UDim2.new(isRange and lo or hi, 0, 0.5, 0) } },
        }
        if knob2 then goals[3] = { knob2, { Position = UDim2.new(hi, 0, 0.5, 0) } } end
        for _, g in ipairs(goals) do
            if t then
                Tween(g[1], g[2], t, Enum.EasingStyle.Quint)
            else
                for k, v in pairs(g[2]) do g[1][k] = v end
            end
        end
        if isRange then
            valueBox.Text = fmt(el.Value[1]) .. " - " .. fmt(el.Value[2])
        else
            valueBox.Text = fmt(el.Value)
        end
    end
    local function norm(v, w)
        if isRange then
            local a, b
            if type(v) == "table" then a, b = v[1] or v.Min, v[2] or v.Max else a, b = v, w end
            a, b = snap(a), snap(b == nil and max or b)
            if a > b then a, b = b, a end
            return { a, b }
        end
        return snap(v)
    end
    local function same(a, b)
        if isRange then return a[1] == b[1] and a[2] == b[2] end
        return a == b
    end

    local def = opts.Default or opts.Value
    if isRange and type(def) ~= "table" then def = { min, max } end
    el.Value = norm(def or min)
    render()

    function el:Set(v, silent, w)
        if isRange and type(v) ~= "table" and v ~= nil then
            -- :Set(lo, hi) form
            v, w, silent = { v, silent }, nil, w
        end
        local n = norm(v, w)
        if n == nil then return end
        if same(n, el.Value) then
            render()
            return
        end
        el.Value = n
        render(TI)
        if silent then
            if el.Flag then Library.Flags[el.Flag] = n end
        elseif isRange then
            Changed(el, n[1], n[2])
        else
            Changed(el, n)
        end
    end
    function el:Get()
        if isRange then return el.Value[1], el.Value[2] end
        return el.Value
    end
    function el:SetRange(newMin, newMax)
        min = tonumber(newMin) or min
        max = tonumber(newMax) or max
        if max <= min then max = min + inc end
        el.Min, el.Max = min, max
        if isRange then el:Set({ el.Value[1], el.Value[2] }) else el:Set(el.Value) end
    end
    el._save = function()
        if isRange then return { el.Value[1], el.Value[2] } end
        return el.Value
    end
    el._load = function(v)
        if isRange and type(v) == "table" then el:Set(v)
        elseif not isRange and tonumber(v) then el:Set(tonumber(v)) end
    end

    local active -- 1 or 2: which knob a range drag moves
    DragArea(hit, function(pos)
        local ap, as = track.AbsolutePosition, track.AbsoluteSize
        if as.X <= 0 then return end
        local a = math.clamp((pos.X - ap.X) / as.X, 0, 1)
        local v = min + a * (max - min)
        if isRange then
            local lo, hi = el.Value[1], el.Value[2]
            if not active then active = (math.abs(v - lo) <= math.abs(v - hi)) and 1 or 2 end
            if active == 1 then el:Set({ math.min(v, hi), hi }) else el:Set({ lo, math.max(v, lo) }) end
        else
            el:Set(v)
        end
    end, el._bin)
    Track(UserInputService.InputEnded:Connect(function() active = nil end), el._bin)
    hit.MouseEnter:Connect(function()
        Tween(knob, { Size = UDim2.fromOffset(16, 16) }, 0.12)
        if knob2 then Tween(knob2, { Size = UDim2.fromOffset(16, 16) }, 0.12) end
    end)
    hit.MouseLeave:Connect(function()
        Tween(knob, { Size = UDim2.fromOffset(14, 14) }, 0.2)
        if knob2 then Tween(knob2, { Size = UDim2.fromOffset(14, 14) }, 0.2) end
    end)
    valueBox.Focused:Connect(function()
        Bind(valueStroke, "Color", "Accent", 0.15)
        if isRange then
            valueBox.Text = num(el.Value[1]) .. " - " .. num(el.Value[2])
        else
            valueBox.Text = num(el.Value)
        end
    end)
    valueBox.FocusLost:Connect(function()
        Bind(valueStroke, "Color", "StrokeHover", 0.2)
        local txt = valueBox.Text
        if prefix ~= "" then txt = string.gsub(txt, "^%s*" .. string.gsub(prefix, "%p", "%%%0"), "") end
        if isRange then
            -- explicit separator: "100-500", "-5 - 10", "100, 500", "100 to 500", "100 500"
            local t = string.gsub(txt, "\226\128\147", "-") -- en dash
            if prefix ~= "" then t = string.gsub(t, (string.gsub(prefix, "%p", "%%%0")), "") end
            local sfx = tostring(opts.Suffix or "")
            if sfx ~= "" then t = string.gsub(t, (string.gsub(sfx, "%p", "%%%0")), "") end
            t = string.gsub(t, "%s+to%s+", " ~ ")
            local a, b = string.match(t, "^%s*(%-?[%d%.]+)%s*[%-,;:~/]%s*(%-?[%d%.]+)%s*$")
            if not a then a, b = string.match(t, "^%s*(%-?[%d%.]+)%s+(%-?[%d%.]+)%s*$") end
            local lo, hi = tonumber(a), tonumber(b)
            if lo and hi then el:Set({ lo, hi }) end
        else
            local n = tonumber((string.match(txt, "%-?%d*%.?%d+")))
            if n then el:Set(n) end
        end
        render()
    end)
    Register(el)
    return el
end

------------------------------------------------------------------ Dropdown
function Creators:CreateDropdown(opts)
    opts = Opts(opts)
    local el = MakeElement("Dropdown", self, opts)
    local desc = Desc(opts)
    local multi = opts.Multi == true or opts.MultiSelect == true
    el.Multi = multi
    el.Options = {}
    local rowH = desc and 46 or 34
    local host = Host(self, rowH, nil, true)
    el.Instance = host.holder
    local header = HoverRow(host.inner, rowH)
    RowText(header, el.Name, desc, rowH, 0.46, 14)
    local box = New("Frame", {
        Parent = header,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.new(0.46, 0, 0, 26),
        ZIndex = 4,
    }, { BackgroundColor3 = "Background" })
    Round(box, 8)
    local boxStroke = Rim(box, "StrokeHover", 0.25, 0.8)
    local valueLabel = Label(box, "", 12, "Text", Enum.Font.GothamMedium, {
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -32, 1, 0),
        ZIndex = 5,
    })
    local chev = Icon(box, "chevron-down", 12, "Muted", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -9, 0.5, 0),
        ZIndex = 5,
    })

    local list = New("Frame", {
        Parent = host.inner,
        Position = UDim2.fromOffset(6, rowH + 2),
        Size = UDim2.new(1, -12, 0, 0),
        Visible = false,
        ZIndex = 5,
    }, { BackgroundColor3 = "Background" })
    Round(list, 8)
    Rim(list, "StrokeHover", 0.25, 0.85)
    local SEARCH_H = 30
    local searchWrap = New("Frame", {
        Parent = list,
        Position = UDim2.fromOffset(6, 5),
        Size = UDim2.new(1, -12, 0, SEARCH_H - 6),
        Visible = false,
        ZIndex = 7,
    }, { BackgroundColor3 = "Surface2" })
    Round(searchWrap, 6)
    local searchStroke = Rim(searchWrap, "Stroke", 0.2, 0.7)
    Icon(searchWrap, "search", 11, "Muted", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 8, 0.5, 0),
        ZIndex = 8,
    })
    local searchBox = New("TextBox", {
        Parent = searchWrap,
        Name = "Search",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(26, 0),
        Size = UDim2.new(1, -32, 1, 0),
        Text = "",
        PlaceholderText = tostring(opts.SearchPlaceholder or "Search..."),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 8,
    }, { TextColor3 = "Text", PlaceholderColor3 = "Muted" })
    el.SearchBox = searchBox
    local scroll = New("ScrollingFrame", {
        Parent = list,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ScrollBarThickness = 2,
        ScrollBarImageTransparency = 0.3,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        ZIndex = 6,
    }, { ScrollBarImageColor3 = "Accent" })
    New("UIPadding", {
        Parent = scroll, PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6),
        PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
    })
    New("UIListLayout", { Parent = scroll, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })

    local rows = {}
    el.Open = false

    local function isSelected(o)
        if multi then
            for _, v in ipairs(el.Value) do if v == o then return true end end
            return false
        end
        return el.Value == o
    end
    local function displayText()
        if multi then
            local n = #el.Value
            if n == 0 then return tostring(opts.Placeholder or "None") end
            if n <= 2 then return table.concat(el.Value, ", ") end
            return tostring(n) .. " selected"
        end
        if el.Value == nil then return tostring(opts.Placeholder or "Select...") end
        return tostring(el.Value)
    end
    local query = ""
    local function searchOn()
        if opts.Search == false then return false end
        return opts.Search == true or #el.Options > 8
    end
    local function matches(o)
        return query == "" or string.find(string.lower(o), query, 1, true) ~= nil
    end
    local function visibleCount()
        local n = 0
        for _, o in ipairs(el.Options) do if matches(o) then n = n + 1 end end
        return n
    end
    local function listHeight()
        local n = math.min(visibleCount(), tonumber(opts.MaxVisible) or 6)
        if n < 1 then n = 1 end
        return n * 28 - 2 + 8 + (searchOn() and SEARCH_H or 0)
    end
    local function layoutSearch()
        local on = searchOn()
        searchWrap.Visible = on
        scroll.Position = UDim2.fromOffset(0, on and SEARCH_H or 0)
        scroll.Size = UDim2.new(1, 0, 1, on and -SEARCH_H or 0)
    end
    -- live filter: hides non matching rows and resizes the list
    local function applyFilter()
        local n = 0
        for _, r in ipairs(rows) do
            local ok = matches(r.option)
            r.button.Visible = ok
            if ok then n = n + 1 end
        end
        scroll.CanvasSize = UDim2.new(0, 0, 0, n * 28 + 6)
        el.VisibleOptions = n
        if el.Open then
            list.Size = UDim2.new(1, -12, 0, listHeight())
            host.SetHeight(rowH + 2 + listHeight() + 6, 0.12)
        end
    end
    function el:SetSearch(text)
        query = string.lower(tostring(text or ""))
        if searchBox.Text ~= tostring(text or "") then searchBox.Text = tostring(text or "") end
        applyFilter()
    end
    pcall(function()
        Track(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            local q = string.lower(searchBox.Text)
            if q ~= query then
                query = q
                applyFilter()
            end
        end), el._bin)
    end)
    searchBox.Focused:Connect(function() Bind(searchStroke, "Color", "Accent", 0.15) end)
    searchBox.FocusLost:Connect(function() Bind(searchStroke, "Color", "Stroke", 0.2) end)
    local function refreshRows()
        for _, r in ipairs(rows) do
            local on = isSelected(r.option)
            Bind(r.label, "TextColor3", on and "Text" or "Muted", 0.12)
            r.label.Font = on and Enum.Font.GothamBold or Enum.Font.GothamMedium
            r.check.ImageTransparency = on and 0 or 1
            r.button.BackgroundTransparency = on and 0.5 or 1
        end
        valueLabel.Text = displayText()
        Bind(valueLabel, "TextColor3", ((multi and #el.Value > 0) or (not multi and el.Value ~= nil)) and "Text" or "Muted")
    end
    local function setOpen(v)
        el.Open = v == true
        if el.Open then layoutSearch() end
        local target = el.Open and (rowH + 2 + listHeight() + 6) or rowH
        if el.Open then
            list.Size = UDim2.new(1, -12, 0, listHeight())
            list.Visible = true
        end
        host.SetHeight(target, 0.22)
        Tween(chev, { Rotation = el.Open and 180 or 0 }, 0.22)
        Bind(boxStroke, "Color", el.Open and "Accent" or "StrokeHover", 0.15)
        if not el.Open then
            task.delay(0.23, function()
                if not el.Open then pcall(function() list.Visible = false end) end
            end)
        end
    end

    local function fireChange()
        if multi then
            local copy = {}
            for i, v in ipairs(el.Value) do copy[i] = v end
            Changed(el, copy)
        else
            Changed(el, el.Value)
        end
    end

    local function buildRows()
        for _, r in ipairs(rows) do pcall(function() r.button:Destroy() end) end
        ClearTable(rows)
        for i, o in ipairs(el.Options) do
            local b = New("TextButton", {
                Parent = scroll,
                Size = UDim2.new(1, 0, 0, 26),
                Text = "",
                BackgroundTransparency = 1,
                LayoutOrder = i,
                ZIndex = 7,
            }, { BackgroundColor3 = "Surface3" })
            Round(b, 6)
            local lbl = Label(b, o, 12, "Muted", Enum.Font.GothamMedium, {
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -36, 1, 0),
                ZIndex = 8,
            })
            local check = Icon(b, "check", 12, "Accent", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -9, 0.5, 0),
                ImageTransparency = 1,
                ZIndex = 8,
            })
            local r = { button = b, label = lbl, check = check, option = o }
            rows[#rows + 1] = r
            b.MouseEnter:Connect(function()
                if not isSelected(o) then Tween(b, { BackgroundTransparency = 0.7 }, 0.1) end
            end)
            b.MouseLeave:Connect(function()
                Tween(b, { BackgroundTransparency = isSelected(o) and 0.5 or 1 }, 0.15)
            end)
            b.MouseButton1Click:Connect(function()
                if multi then
                    local found
                    for idx, v in ipairs(el.Value) do if v == o then found = idx end end
                    if found then table.remove(el.Value, found) else el.Value[#el.Value + 1] = o end
                    -- keep the order of the option list
                    local ordered = {}
                    for _, opt in ipairs(el.Options) do
                        for _, v in ipairs(el.Value) do if v == opt then ordered[#ordered + 1] = opt end end
                    end
                    el.Value = ordered
                    refreshRows()
                    fireChange()
                else
                    if el.Value == o and opts.AllowNone then
                        el.Value = nil
                    else
                        el.Value = o
                    end
                    refreshRows()
                    setOpen(false)
                    fireChange()
                end
            end)
        end
        layoutSearch()
        applyFilter()
    end

    local function normalize(list_)
        local out, seen = {}, {}
        if type(list_) == "table" then
            for _, v in ipairs(list_) do
                local s = tostring(v)
                if not seen[s] then
                    seen[s] = true
                    out[#out + 1] = s
                end
            end
        end
        return out
    end
    local function has(o)
        for _, v in ipairs(el.Options) do if v == o then return true end end
        return false
    end
    local function coerce(v)
        if multi then
            local out = {}
            if type(v) == "table" then
                for _, x in ipairs(v) do
                    if has(tostring(x)) then out[#out + 1] = tostring(x) end
                end
            elseif v ~= nil and has(tostring(v)) then
                out[1] = tostring(v)
            end
            return out
        end
        if type(v) == "table" then v = v[1] end
        if v == nil then return nil end
        v = tostring(v)
        if has(v) then return v end
        return nil
    end

    el.Options = normalize(opts.Options or opts.Values or {})
    el.Value = coerce(opts.Default or opts.Value or opts.CurrentOption)
    if multi and el.Value == nil then el.Value = {} end
    buildRows()
    refreshRows()

    function el:Set(v, silent)
        local nv = coerce(v)
        -- AllowNone=false: an unknown value never clears a valid selection
        if not multi and nv == nil and not opts.AllowNone and el.Value ~= nil then return end
        el.Value = nv
        refreshRows()
        if silent then
            if el.Flag then Library.Flags[el.Flag] = el.Value end
        else
            fireChange()
        end
    end
    function el:Get() return el.Value end
    function el:Refresh(newOptions, keepSelection)
        el.Options = normalize(newOptions)
        if keepSelection == false then
            el.Value = multi and {} or nil
        else
            el.Value = coerce(el.Value)
            if multi and el.Value == nil then el.Value = {} end
        end
        if el.Flag then Library.Flags[el.Flag] = el.Value end
        buildRows()
        refreshRows()
    end
    function el:Add(option)
        local list_ = {}
        for i, v in ipairs(el.Options) do list_[i] = v end
        list_[#list_ + 1] = option
        el:Refresh(list_)
    end
    function el:Remove(option)
        local list_ = {}
        for _, v in ipairs(el.Options) do if v ~= tostring(option) then list_[#list_ + 1] = v end end
        el:Refresh(list_)
    end
    function el:SetOpen(v) setOpen(v) end
    function el:Open_() setOpen(true) end
    if multi then
        function el:SelectAll() el:Set(el.Options) end
        function el:Clear() el:Set({}) end
    end
    el._save = function() return el.Value end
    -- configs: only strings (or a list of strings for Multi) are accepted, anything else is ignored
    el._load = function(v)
        local t = type(v)
        if multi and t == "table" then
            local nv = coerce(v)
            if #nv == 0 and #v > 0 then return end -- every value unknown: keep the selection
            el:Set(nv)
        elseif t == "string" and has(v) then
            el:Set(v)
        end
    end

    header.MouseButton1Click:Connect(function() setOpen(not el.Open) end)
    Register(el)
    return el
end

------------------------------------------------------------------ ProgressBar
function Creators:CreateProgressBar(opts)
    opts = Opts(opts, "Title")
    local el = MakeElement("ProgressBar", self, { Name = opts.Title or opts.Name or "Progress", Flag = opts.Flag, Callback = opts.Callback })
    local desc = Desc(opts)
    local min = tonumber(opts.Min) or 0
    local max = tonumber(opts.Max) or 100
    if max <= min then max = min + 100 end
    local suffix = opts.Suffix ~= nil and tostring(opts.Suffix) or (opts.Max == nil and "%" or "")
    local decimals = tonumber(opts.Decimals) or 0
    el.Min, el.Max = min, max
    local h = desc and 58 or 46
    local barY = desc and 44 or 32
    local host = Host(self, h)
    el.Instance = host.holder
    local row = New("Frame", { Parent = host.inner, Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, ZIndex = 3 })
    RowText(row, el.Name, desc, desc and h or 28, 0, 70)
    local valueLabel = Label(row, "", 12, "Text", Enum.Font.GothamBold, {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, desc and 7 or 0),
        Size = UDim2.new(0, 60, 0, desc and 18 or 28),
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 4,
    })
    local track = New("Frame", {
        Parent = row,
        Position = UDim2.fromOffset(10, barY),
        Size = UDim2.new(1, -20, 0, 8),
        ZIndex = 4,
    }, { BackgroundColor3 = "Surface3" })
    Round(track, "full")
    Outline(track, "Stroke", 1, 0.3)
    local fill = New("Frame", { Parent = track, Size = UDim2.new(0, 0, 1, 0), ZIndex = 5 }, { BackgroundColor3 = "Accent" })
    Round(fill, "full")
    Shade(fill, 0.7, 180)
    el._fill = fill
    local function fmt(v) return string.format("%." .. decimals .. "f", v) .. suffix end
    local function render(t)
        local a = (el.Value - min) / (max - min)
        if t then Tween(fill, { Size = UDim2.new(a, 0, 1, 0) }, t, Enum.EasingStyle.Quint)
        else fill.Size = UDim2.new(a, 0, 1, 0) end
        valueLabel.Text = fmt(el.Value)
    end
    el.Value = math.clamp(tonumber(opts.Value or opts.Default) or min, min, max)
    render()
    function el:Set(v, silent)
        local n = tonumber(v)
        if not n then return end
        n = math.clamp(n, min, max)
        if n == el.Value then return end
        el.Value = n
        render(tonumber(opts.TweenTime) or 0.35)
        if silent then
            if el.Flag then Library.Flags[el.Flag] = n end
        else
            Changed(el, n)
        end
    end
    function el:Get() return el.Value end
    function el:GetPercent() return (el.Value - min) / (max - min) * 100 end
    function el:SetRange(a, b)
        min, max = tonumber(a) or min, tonumber(b) or max
        if max <= min then max = min + 1 end
        el.Min, el.Max = min, max
        el.Value = math.clamp(el.Value, min, max)
        render()
    end
    el._save = function() return el.Value end
    el._load = function(v) if type(v) == "number" then el:Set(v) end end
    Register(el)
    return el
end
Creators.CreateProgress = Creators.CreateProgressBar

------------------------------------------------------------------ ButtonGrid
function Creators:CreateButtonGrid(opts)
    opts = Opts(opts, "Title")
    local el = MakeElement("ButtonGrid", self, { Name = opts.Title or opts.Name or "" })
    local cols = math.clamp(math.floor(tonumber(opts.Columns) or 2), 1, 3)
    el.Columns, el.Buttons = cols, {}
    local list = type(opts.Buttons) == "table" and opts.Buttons or {}
    local hasTitle = el.Name ~= ""
    local CELL, GAP = 34, 6
    local host = Host(self, 0, "auto")
    el.Instance = host.holder
    New("UIPadding", {
        Parent = host.inner, PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
        PaddingTop = UDim.new(0, hasTitle and 0 or 6), PaddingBottom = UDim.new(0, 6),
    })
    New("UIListLayout", { Parent = host.inner, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })
    if hasTitle then
        Label(host.inner, el.Name, 13, "Text", Enum.Font.GothamMedium, {
            Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, ZIndex = 4,
        }).TextXAlignment = Enum.TextXAlignment.Left
    end
    local gridHolder = New("Frame", {
        Parent = host.inner,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = 2,
        ZIndex = 4,
    })
    local grid = New("UIGridLayout", {
        Parent = gridHolder,
        CellPadding = UDim2.fromOffset(GAP, GAP),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    el._grid = grid
    -- responsive: fewer columns when the row is narrow (mobile / small window)
    local function layout()
        local w = gridHolder.AbsoluteSize.X
        local c = cols
        if w > 0 and w < 150 * c then c = math.max(1, math.floor((w + GAP) / 150)) end
        c = math.clamp(c, 1, cols)
        el.ActiveColumns = c
        grid.CellSize = UDim2.new(1 / c, -GAP * (c - 1) / c, 0, CELL)
    end
    layout()
    pcall(function() Track(gridHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout), el._bin) end)
    for i, b in ipairs(list) do
        if type(b) == "table" then
            local text = tostring(b.Text or b.Name or ("Button " .. i))
            local btn = Chip({
                Parent = gridHolder,
                Text = text,
                Icon = b.Icon,
                Style = b.Style,
                LayoutOrder = i,
                ZIndex = 5,
                Callback = function() if el.Alive then SafeCall(text, b.Callback) end end,
            })
            el.Buttons[#el.Buttons + 1] = btn
        end
    end
    function el:SetColumns(n)
        cols = math.clamp(math.floor(tonumber(n) or cols), 1, 3)
        el.Columns = cols
        layout()
    end
    Register(el)
    return el
end

------------------------------------------------------------------ Input
function Creators:CreateInput(opts)
    opts = Opts(opts)
    local el = MakeElement("Input", self, opts)
    local desc = Desc(opts)
    local h = desc and 46 or 34
    local host = Host(self, h)
    el.Instance = host.holder
    local row = HoverRow(host.inner, h)
    RowText(row, el.Name, desc, h, 0.46, 14)
    local box = New("Frame", {
        Parent = row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.new(0.46, 0, 0, 26),
        ClipsDescendants = true,
        ZIndex = 4,
    }, { BackgroundColor3 = "Background" })
    Round(box, 8)
    local stroke = Rim(box, "StrokeHover", 0.25, 0.8)
    local numeric = opts.Numeric == true
    local default = opts.Default or opts.Value or ""
    local tb = New("TextBox", {
        Parent = box,
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(1, -20, 1, 0),
        Text = tostring(default),
        PlaceholderText = tostring(opts.Placeholder or opts.PlaceholderText or "Type here..."),
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        ClearTextOnFocus = opts.ClearOnFocus == true,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 5,
    }, { TextColor3 = "Text", PlaceholderColor3 = "Muted" })
    el.TextBox = tb
    if numeric then
        el.Value = tonumber(default)
    else
        el.Value = tostring(default)
    end
    local maxLen = tonumber(opts.MaxLength)

    pcall(function()
        Track(tb:GetPropertyChangedSignal("Text"):Connect(function()
            local t = tb.Text
            local cleaned = t
            if numeric then
                cleaned = string.gsub(cleaned, "[^%d%.%-]", "")
            end
            if maxLen and #cleaned > maxLen then cleaned = string.sub(cleaned, 1, maxLen) end
            if cleaned ~= t then tb.Text = cleaned end
        end), el._bin)
    end)

    function el:Set(v, silent)
        if numeric then
            local n = tonumber(v)
            if n == nil then
                tb.Text = el.Value ~= nil and tostring(el.Value) or ""
                return
            end
            el.Value = n
            tb.Text = tostring(n)
        else
            el.Value = tostring(v == nil and "" or v)
            tb.Text = el.Value
        end
        if silent then
            if el.Flag then Library.Flags[el.Flag] = el.Value end
        else
            Changed(el, el.Value)
        end
    end
    function el:Get() return el.Value end
    el._save = function() return el.Value end
    el._load = function(v) if type(v) == "string" or type(v) == "number" then el:Set(v) end end

    tb.Focused:Connect(function() Bind(stroke, "Color", "Accent", 0.15) end)
    tb.FocusLost:Connect(function(enter)
        Bind(stroke, "Color", "StrokeHover", 0.2)
        if opts.EnterOnly and not enter then return end
        el:Set(tb.Text)
        if opts.ClearAfter or opts.RemoveTextAfterFocusLost then tb.Text = "" end
    end)
    row.MouseButton1Click:Connect(function() pcall(function() tb:CaptureFocus() end) end)
    Register(el)
    return el
end
Creators.CreateTextbox = Creators.CreateInput

------------------------------------------------------------------ Keybind
function Creators:CreateKeybind(opts)
    opts = Opts(opts)
    local el = MakeElement("Keybind", self, opts)
    local desc = Desc(opts)
    local h = desc and 46 or 34
    local host = Host(self, h)
    el.Instance = host.holder
    local row = HoverRow(host.inner, h)
    RowText(row, el.Name, desc, h, 0, 118)
    el.Value = KeyName(opts.Default or opts.Value or opts.CurrentKeybind) or "None"
    el.ChangedCallback = opts.ChangedCallback
    local chip = New("TextButton", {
        Parent = row,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(96, 24),
        Text = el.Value,
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 4,
    }, { BackgroundColor3 = "Background", TextColor3 = "Muted" })
    Round(chip, 8)
    local chipStroke = Rim(chip, "StrokeHover", 0.25, 0.8)
    Pressable(chip, 0.94)
    local listenConn

    local function dropConn()
        if not listenConn then return false end
        local c = listenConn
        listenConn = nil
        pcall(function() c:Disconnect() end)
        RemoveFrom(el._bin, c)
        return true
    end
    local listenToken = 0
    local function stopListening()
        listenToken = listenToken + 1
        if el.Window._cancelListen == el._cancelListen then el.Window._cancelListen = nil end
        dropConn()
        pcall(function()
            chip.Text = el.Value
            Bind(chipStroke, "Color", "StrokeHover", 0.2)
            Bind(chip, "TextColor3", "Muted", 0.2)
        end)
        task.defer(function() Listening = false end)
    end
    -- destroyed while waiting for a key: release the global listening lock right away
    OnDestroy(el, function()
        if dropConn() then Listening = false end
    end)

    function el:Set(key, silent)
        local n = KeyName(key) or "None"
        el.Value = n
        chip.Text = n
        if el.Flag then Library.Flags[el.Flag] = n end
        if not silent then
            SafeCall(el.Name, el.ChangedCallback, n)
            if el._listeners then
                for _, fn in ipairs(el._listeners) do SafeCall(el.Name, fn, n) end
            end
        end
    end
    function el:Get() return el.Value end
    -- runs the press callback as if the key was pressed
    function el:Press() SafeCall(el.Name, el.Callback, el.Value) end
    el._save = function() return el.Value end
    el._load = function(v)
        local n = KeyName(v)
        if n then el:Set(n) else warn("[SolUI] invalid key '" .. tostring(v) .. "' for " .. el.Name) end
    end

    chip.MouseButton1Click:Connect(function()
        if Listening then return end
        if IsTouchOnly() then
            Library:Notify({ Title = "No keyboard", Content = "Keybinds need a keyboard", Type = "info" })
            return
        end
        Listening = true
        listenToken = listenToken + 1
        local myToken = listenToken
        -- Hide / outside click / 8 s timeout all stop listening (shortcuts are never left blocked)
        el._cancelListen = function() if listenConn then stopListening() end end
        el.Window._cancelListen = el._cancelListen
        task.delay(8, function()
            if listenToken == myToken and listenConn then stopListening() end
        end)
        chip.Text = "Press a key"
        Bind(chipStroke, "Color", "Accent", 0.15)
        Bind(chip, "TextColor3", "Accent", 0.15)
        listenConn = Track(UserInputService.InputBegan:Connect(function(input)
            local it = input.UserInputType
            if it == Enum.UserInputType.MouseButton1 or it == Enum.UserInputType.MouseButton2 or it == Enum.UserInputType.Touch then
                stopListening()
                return
            end
            if it ~= Enum.UserInputType.Keyboard then return end
            ConsumedAt = Clock()
            local name = KeyName(input.KeyCode)
            if name == "Escape" or name == nil or name == "Unknown" then
                stopListening()
                return
            end
            if name == "Backspace" or name == "Delete" then
                name = "None"
            end
            stopListening()
            el:Set(name)
        end), el._bin)
    end)
    el.Window._keybinds[#el.Window._keybinds + 1] = el
    Register(el)
    return el
end
Creators.CreateBind = Creators.CreateKeybind

------------------------------------------------------------------ ColorPicker
function Creators:CreateColorPicker(opts)
    opts = Opts(opts)
    local el = MakeElement("ColorPicker", self, opts)
    local desc = Desc(opts)
    local rowH = desc and 46 or 34
    local panelH = 124
    local host = Host(self, rowH, nil, true)
    el.Instance = host.holder
    local header = HoverRow(host.inner, rowH)
    RowText(header, el.Name, desc, rowH, 0, 120)
    local color = ToColor(opts.Default or opts.Value or opts.Color, nil) or Color3.fromRGB(255, 255, 255)
    local hh, ss, vv = ColorToHSV(color)
    el.Value = color

    local hexChip = Label(header, ToHex(color), 11, "Muted", Enum.Font.GothamBold, {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -58, 0.5, 0),
        Size = UDim2.fromOffset(60, 16),
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 4,
    })
    local swatch = New("Frame", {
        Parent = header,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(40, 22),
        BackgroundColor3 = color,
        ZIndex = 4,
    })
    Round(swatch, 7)
    local swStroke = Rim(swatch, "StrokeHover", 0.1, 0.6)

    local panel = New("Frame", {
        Parent = host.inner,
        Position = UDim2.fromOffset(6, rowH + 2),
        Size = UDim2.new(1, -12, 0, panelH),
        Visible = false,
        ZIndex = 5,
    }, { BackgroundColor3 = "Background" })
    Round(panel, 8)
    Rim(panel, "StrokeHover", 0.25, 0.85)

    -- saturation / value square
    local sv = New("Frame", {
        Parent = panel,
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(1, -148, 1, -16),
        BackgroundColor3 = HSVToColor(hh, 1, 1),
        ZIndex = 6,
    })
    Round(sv, 6)
    local white = New("Frame", { Parent = sv, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 7 })
    Round(white, 6)
    Fade(white, 0, 1, 0)
    local black = New("Frame", { Parent = sv, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 8 })
    Round(black, 6)
    Fade(black, 1, 0, 90)
    local svCursor = New("Frame", {
        Parent = sv,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(ss, 1 - vv),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = color,
        ZIndex = 10,
    })
    Round(svCursor, "full")
    New("UIStroke", { Parent = svCursor, Color = Color3.new(1, 1, 1), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    local svHit = New("TextButton", { Parent = sv, Size = UDim2.fromScale(1, 1), Text = "", BackgroundTransparency = 1, ZIndex = 11 })

    -- hue bar
    local hue = New("Frame", {
        Parent = panel,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -116, 0, 8),
        Size = UDim2.new(0, 14, 1, -16),
        BackgroundColor3 = Color3.new(1, 1, 1),
        ZIndex = 6,
    })
    Round(hue, 5)
    local kps = {}
    for i = 0, 6 do
        kps[#kps + 1] = ColorSequenceKeypoint.new(i / 6, HSVToColor((i / 6) % 1, 1, 1))
    end
    kps[7] = ColorSequenceKeypoint.new(1, HSVToColor(0, 1, 1))
    New("UIGradient", { Parent = hue, Rotation = 90, Color = ColorSequence.new(kps) })
    local hueCursor = New("Frame", {
        Parent = hue,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, hh),
        Size = UDim2.new(1, 6, 0, 5),
        BackgroundColor3 = Color3.new(1, 1, 1),
        ZIndex = 8,
    })
    Round(hueCursor, "full")
    Outline(hueCursor, "Background", 1)
    local hueHit = New("TextButton", { Parent = hue, Size = UDim2.new(1, 8, 1, 0), Position = UDim2.fromOffset(-4, 0), Text = "", BackgroundTransparency = 1, ZIndex = 9 })

    -- preview + hex + rgb
    local preview = New("Frame", {
        Parent = panel,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 8),
        Size = UDim2.fromOffset(96, 44),
        BackgroundColor3 = color,
        ZIndex = 6,
    })
    Round(preview, 8)
    Rim(preview, "StrokeHover", 0.1, 0.6)
    local hexWrap = New("Frame", {
        Parent = panel,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 60),
        Size = UDim2.fromOffset(96, 26),
        ZIndex = 6,
    }, { BackgroundColor3 = "Surface2" })
    Round(hexWrap, 7)
    local hexStroke = Rim(hexWrap, "StrokeHover", 0.25, 0.8)
    local hexBox = New("TextBox", {
        Parent = hexWrap,
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = ToHex(color),
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 7,
    }, { TextColor3 = "Text" })
    local rgbLabel = Label(panel, "", 11, "Muted", Enum.Font.GothamMedium, {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 94),
        Size = UDim2.fromOffset(96, 22),
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = 6,
    })

    local function render()
        local c = el.Value
        sv.BackgroundColor3 = HSVToColor(hh, 1, 1)
        svCursor.Position = UDim2.fromScale(ss, 1 - vv)
        svCursor.BackgroundColor3 = c
        hueCursor.Position = UDim2.fromScale(0.5, hh)
        swatch.BackgroundColor3 = c
        preview.BackgroundColor3 = c
        local hex = ToHex(c)
        hexChip.Text = hex
        hexBox.Text = hex
        rgbLabel.Text = string.format("%d, %d, %d", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end
    local function commit(silent)
        el.Value = HSVToColor(hh, ss, vv)
        render()
        if silent then
            if el.Flag then Library.Flags[el.Flag] = el.Value end
        else
            Changed(el, el.Value)
        end
    end
    render()

    function el:Set(c, silent)
        local col = ToColor(c, nil)
        if not col then return end
        local h2, s2, v2 = ColorToHSV(col)
        -- keep the current hue for greys so the square does not jump
        if s2 > 0 and v2 > 0 then hh = h2 end
        ss, vv = s2, v2
        el.Value = col
        render()
        if silent then
            if el.Flag then Library.Flags[el.Flag] = col end
        else
            Changed(el, col)
        end
    end
    function el:Get() return el.Value end
    function el:GetHex() return ToHex(el.Value) end
    el._save = function() return ToHex(el.Value) end
    el._load = function(v) el:Set(v) end

    el.Open = false
    local function setOpen(v)
        el.Open = v == true
        if el.Open then panel.Visible = true end
        host.SetHeight(el.Open and (rowH + 2 + panelH + 6) or rowH, 0.22)
        Bind(swStroke, "Color", el.Open and "Accent" or "StrokeHover", 0.15)
        if not el.Open then
            task.delay(0.23, function()
                if not el.Open then pcall(function() panel.Visible = false end) end
            end)
        end
    end
    function el:SetOpen(v) setOpen(v) end
    header.MouseButton1Click:Connect(function() setOpen(not el.Open) end)

    DragArea(svHit, function(pos)
        local ap, as = sv.AbsolutePosition, sv.AbsoluteSize
        if as.X <= 0 or as.Y <= 0 then return end
        ss = math.clamp((pos.X - ap.X) / as.X, 0, 1)
        vv = 1 - math.clamp((pos.Y - ap.Y) / as.Y, 0, 1)
        commit()
    end, el._bin)
    DragArea(hueHit, function(pos)
        local ap, as = hue.AbsolutePosition, hue.AbsoluteSize
        if as.Y <= 0 then return end
        hh = math.clamp((pos.Y - ap.Y) / as.Y, 0, 0.999)
        commit()
    end, el._bin)
    hexBox.Focused:Connect(function() Bind(hexStroke, "Color", "Accent", 0.15) end)
    hexBox.FocusLost:Connect(function()
        Bind(hexStroke, "Color", "StrokeHover", 0.2)
        local col = FromHex(hexBox.Text)
        if col then el:Set(col) else render() end
    end)
    Register(el)
    return el
end
Creators.CreateColorpicker = Creators.CreateColorPicker

------------------------------------------------------------------ Label / Paragraph / Divider
function Creators:CreateLabel(opts)
    opts = Opts(opts, "Text")
    local text = tostring(opts.Text or opts.Name or "")
    local el = MakeElement("Label", self, { Name = text })
    local host = Host(self, 0, "auto")
    el.Instance = host.holder
    New("UIPadding", {
        Parent = host.inner, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
    })
    local iconName = opts.Icon
    local offset = 0
    if iconName and ResolveIcon(iconName) ~= "" then
        Icon(host.inner, iconName, 14, "Accent", { Position = UDim2.fromOffset(0, 1), ZIndex = 4 })
        offset = 22
    end
    local lbl = Label(host.inner, text, 13, "Muted", Enum.Font.GothamMedium, {
        Position = UDim2.fromOffset(offset, 0),
        Size = UDim2.new(1, -offset, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = 4,
    })
    -- custom colour: unbind TextColor3 so theme changes don't overwrite it
    local function setColor(c)
        if c == nil then
            Bind(lbl, "TextColor3", "Muted")
        else
            if Registry[lbl] then Registry[lbl].TextColor3 = nil end
            lbl.TextColor3 = ToColor(c, Theme.Muted)
        end
    end
    if opts.Color then setColor(opts.Color) end
    function el:SetColor(c) setColor(c) end
    el.Value = text
    function el:Set(t)
        el.Value = tostring(t)
        lbl.Text = el.Value
    end
    el.SetText = el.Set
    return el
end

function Creators:CreateParagraph(opts, content)
    if type(opts) ~= "table" then opts = { Title = opts, Content = content } end
    local el = MakeElement("Paragraph", self, { Name = opts.Title or "Paragraph" })
    local host = Host(self, 0, "auto")
    el.Instance = host.holder
    New("UIPadding", {
        Parent = host.inner, PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
        PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 10),
    })
    New("UIListLayout", { Parent = host.inner, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) })
    local titleLabel = Label(host.inner, tostring(opts.Title or ""), 13, "Text", Enum.Font.GothamBold, {
        Size = UDim2.new(1, 0, 0, 16),
        LayoutOrder = 1,
        ZIndex = 4,
    })
    local contentLabel = Label(host.inner, tostring(opts.Content or opts.Text or ""), 12, "Muted", nil, {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None,
        TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 2,
        ZIndex = 4,
    })
    el.Value = { Title = titleLabel.Text, Content = contentLabel.Text }
    function el:Set(a, b)
        if type(a) == "table" then
            if a.Title ~= nil then titleLabel.Text = tostring(a.Title) end
            if a.Content ~= nil then contentLabel.Text = tostring(a.Content) end
        else
            if a ~= nil then titleLabel.Text = tostring(a) end
            if b ~= nil then contentLabel.Text = tostring(b) end
        end
        el.Value = { Title = titleLabel.Text, Content = contentLabel.Text }
    end
    function el:SetTitle(t) el:Set(t, nil) end
    function el:SetContent(t) el:Set(nil, t) end
    return el
end

function Creators:CreateDivider()
    local el = MakeElement("Divider", self, { Name = "Divider" })
    local host = Host(self, 9, "bare")
    el.Instance = host.holder
    local line = New("Frame", {
        Parent = host.inner,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 10, 0.5, 0),
        Size = UDim2.new(1, -20, 0, 1),
        ZIndex = 4,
    }, { BackgroundColor3 = "Stroke" })
    New("UIGradient", { Parent = line, Transparency = Stops({ { 0, 1 }, { 0.12, 0 }, { 0.88, 0 }, { 1, 1 } }) })
    return el
end

-- private: label / value row used by the settings tab (also public as CreateStat)
function Creators:CreateStat(name, value)
    local el = MakeElement("Stat", self, { Name = name })
    local host = Host(self, 30)
    el.Instance = host.holder
    Label(host.inner, tostring(name), 12, "Muted", nil, {
        Position = UDim2.fromOffset(10, 0),
        Size = UDim2.new(0.4, 0, 1, 0),
        ZIndex = 4,
    })
    local v = Label(host.inner, tostring(value), 12, "Text", Enum.Font.GothamMedium, {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 0),
        Size = UDim2.new(0.6, -20, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Right,
        ZIndex = 4,
    })
    el.Value = tostring(value)
    function el:Set(t) el.Value = tostring(t); v.Text = el.Value end
    return el
end

------------------------------------------------------------------ Tooltip
local TooltipGui, TooltipLabel
function Library:HideTooltip()
    if TooltipGui then TooltipGui.Visible = false end
end
local function PlaceTooltip()
    if not TooltipGui then return end
    local m = UserInputService:GetMouseLocation()
    local x, y = m.X + 14, m.Y + 20
    local cam = workspace.CurrentCamera
    if cam then
        local vp, sz = cam.ViewportSize, TooltipGui.AbsoluteSize
        x = math.max(0, math.min(x, vp.X - sz.X))
        y = math.max(0, math.min(y, vp.Y - sz.Y))
    end
    TooltipGui.Position = UDim2.fromOffset(x, y)
end
function Library:AttachTooltip(gui, text)
    if not gui or type(text) ~= "string" or text == "" or IsTouchOnly() then return end
    local conns = {}
    local function hide() if TooltipGui then TooltipGui.Visible = false end end
    local function alive() return gui.Parent ~= nil and gui:IsDescendantOf(game) and gui.Visible ~= false end
    conns[1] = gui.MouseEnter:Connect(function()
        if not alive() then return end
        local sg = gui:FindFirstAncestorWhichIsA("ScreenGui")
        if not sg then return end
        if not TooltipGui or not TooltipGui.Parent then
            TooltipGui = New("Frame", {
                Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
                BackgroundTransparency = 0.05, ZIndex = 400, Visible = false,
            }, { BackgroundColor3 = "Surface3" })
            Round(TooltipGui, 6)
            Outline(TooltipGui, "Stroke")
            New("UIPadding", { Parent = TooltipGui, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
                PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) })
            TooltipLabel = Label(TooltipGui, "", 11, "Text", nil, {
                Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
                TextWrapped = true, TextTruncate = Enum.TextTruncate.None, ZIndex = 401,
            })
            New("UISizeConstraint", { Parent = TooltipLabel, MaxSize = Vector2.new(244, math.huge) })
        end
        TooltipGui.Parent = sg
        TooltipLabel.Text = text
        PlaceTooltip()
        TooltipGui.Visible = true
        task.defer(PlaceTooltip)
    end)
    conns[2] = gui.MouseMoved:Connect(function()
        if not TooltipGui or not TooltipGui.Visible then return end
        if not alive() then hide() return end
        PlaceTooltip()
    end)
    conns[3] = gui.MouseLeave:Connect(hide)
    conns[4] = gui.AncestryChanged:Connect(function(_, parent) if not parent then hide() end end)
    return conns
end

------------------------------------------------------------------ Prompt / Modal
function Window:Prompt(opts)
    opts = type(opts) == "table" and opts or { Content = tostring(opts) }
    if self._prompt then self._prompt(false) end
    if Library.HideTooltip then Library:HideTooltip() end
    local parent = self.Gui or (self.Root and self.Root.Parent)
    if not parent then return end
    local done = false
    local cover = New("TextButton", {
        Parent = parent, Size = UDim2.fromScale(1, 1), Text = "", AutoButtonColor = false,
        BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 300,
    })
    Tween(cover, { BackgroundTransparency = 0.45 }, 0.2)
    local card = New("TextButton", {
        Parent = cover, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(320, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Text = "", AutoButtonColor = false, ZIndex = 301,
    }, { BackgroundColor3 = "Surface" })
    Round(card, 12)
    Rim(card, "StrokeHover", 0.2, 0.85)
    New("UIPadding", { Parent = card, PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
        PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14) })
    New("UIListLayout", { Parent = card, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) })
    Label(card, tostring(opts.Title or "Confirm"), 15, "Text", Enum.Font.GothamBold, {
        Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, ZIndex = 302,
    })
    Label(card, tostring(opts.Content or opts.Text or "Are you sure?"), 12, "Muted", nil, {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true,
        TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top,
        LayoutOrder = 2, ZIndex = 302,
    })
    local row = New("Frame", { Parent = card, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 3, ZIndex = 302 })
    local function close(ok)
        if done then return end
        done = true
        if self._prompt == close then self._prompt = nil end
        Tween(cover, { BackgroundTransparency = 1 }, 0.15)
        task.delay(0.15, function() pcall(function() cover:Destroy() end) end)
        if opts.Callback then SafeCall("Prompt", opts.Callback, ok == true) end
    end
    self._prompt = close
    if not IsTouchOnly() then
        local kc
        kc = UserInputService.InputBegan:Connect(function(input)
            if done then kc:Disconnect() return end
            if Listening or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
            if UserInputService:GetFocusedTextBox() then return end
            if input.KeyCode == Enum.KeyCode.Escape then close(false)
            elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then close(true) end
        end)
        cover.Destroying:Connect(function() if kc then kc:Disconnect() end end)
    end
    Chip({ Parent = row, Text = tostring(opts.CancelText or "Cancel"), Size = UDim2.new(0.5, -5, 1, 0),
        ZIndex = 303, Callback = function() close(false) end })
    Chip({ Parent = row, Text = tostring(opts.ConfirmText or "Confirm"), Size = UDim2.new(0.5, -5, 1, 0),
        Position = UDim2.new(0.5, 5, 0, 0), Style = opts.Danger and "danger" or "primary",
        ZIndex = 303, Callback = function() close(true) end })
    cover.MouseButton1Click:Connect(function() close(false) end)
    return close
end

function Library:Prompt(opts)
    local w = Library.Windows[1]
    if w then return w:Prompt(opts) end
end

function Creators:CreateModal(opts)
    opts = Opts(opts)
    local win = self.Window
    local btn = Creators.CreateButton(self, {
        Name = opts.Name or opts.Title or "Open", Description = opts.Description or opts.Desc,
        Callback = function()
            win:Prompt({
                Title = opts.Title, Content = opts.Content, ConfirmText = opts.ConfirmText,
                CancelText = opts.CancelText, Danger = opts.Danger, Callback = opts.Callback,
            })
        end,
    })
    if opts.Tooltip and btn and btn.Instance then Library:AttachTooltip(btn.Instance, opts.Tooltip) end
    return btn
end

------------------------------------------------------------------ Checkbox
function Creators:CreateCheckbox(opts)
    opts = Opts(opts)
    local el = MakeElement("Checkbox", self, opts)
    local desc = Desc(opts)
    local h = desc and 46 or 34
    local host = Host(self, h)
    el.Instance = host.holder
    local row = HoverRow(host.inner, h)
    RowText(row, el.Name, desc, h, 0, 44)
    local value = opts.Default == true or opts.Value == true
    el.Value = value
    local box = New("Frame", {
        Parent = row, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(20, 20), ZIndex = 4,
    }, { BackgroundColor3 = value and "Accent" or "Surface3" })
    Round(box, 5)
    local stroke = Outline(box, value and "Accent" or "Stroke")
    local mark = Icon(box, "check", 14, "AccentDark", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 5,
    })
    mark.ImageTransparency = value and 0 or 1
    function el:Set(v, silent)
        v = v == true
        if v ~= el.Value then
            el.Value = v
            Bind(box, "BackgroundColor3", v and "Accent" or "Surface3", 0.15)
            Bind(stroke, "Color", v and "Accent" or "Stroke", 0.15)
            Tween(mark, { ImageTransparency = v and 0 or 1 }, 0.15)
            if not silent then Changed(el, v) return end
        end
        if el.Flag then Library.Flags[el.Flag] = v end
    end
    function el:Get() return el.Value end
    function el:Toggle() el:Set(not el.Value) end
    el._save = function() return el.Value end
    el._load = function(v) if type(v) == "boolean" then el:Set(v) end end
    row.MouseButton1Click:Connect(function() el:Set(not el.Value) end)
    if opts.Tooltip then Library:AttachTooltip(row, opts.Tooltip) end
    Register(el)
    return el
end

------------------------------------------------------------------ List
function Creators:CreateList(opts)
    opts = Opts(opts)
    local el = MakeElement("List", self, opts)
    local desc = Desc(opts)
    local multi = opts.Multi == true
    local listH = tonumber(opts.Height) or 140
    local th = desc and 46 or 30
    local host = Host(self, th + listH + 8)
    el.Instance = host.holder
    local head = New("Frame", { Parent = host.inner, Size = UDim2.new(1, 0, 0, th), BackgroundTransparency = 1, ZIndex = 3 })
    RowText(head, el.Name, desc, th, 0, 10)
    local scroll = New("ScrollingFrame", {
        Parent = host.inner, Position = UDim2.fromOffset(6, th), Size = UDim2.new(1, -12, 0, listH),
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3,
        BackgroundTransparency = 0.4, ZIndex = 4,
    }, { BackgroundColor3 = "Surface3", ScrollBarImageColor3 = "Accent" })
    Round(scroll, 8)
    New("UIListLayout", { Parent = scroll, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) })
    New("UIPadding", { Parent = scroll, PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6),
        PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) })
    el.Options = {}
    local rows = {}
    local function norm(v)
        if multi then
            local out = {}
            if type(v) == "table" then for _, x in ipairs(v) do out[#out + 1] = tostring(x) end
            elseif v ~= nil then out[1] = tostring(v) end
            return out
        end
        if type(v) == "table" then v = v[1] end
        return v ~= nil and tostring(v) or nil
    end
    local function selected(o)
        if multi then
            for _, x in ipairs(el.Value) do if x == o then return true end end
            return false
        end
        return el.Value == o
    end
    local rowLabels = {}
    local function paint()
        for o, r in pairs(rows) do
            local on = selected(o)
            Bind(r, "BackgroundColor3", on and "Accent" or "Surface2", 0.12)
            r.BackgroundTransparency = on and 0.2 or 1
            local lab = rowLabels[r]
            if lab then Bind(lab, "TextColor3", on and "AccentDark" or "Text", 0.12) end
        end
    end
    local function copyVal()
        if multi then
            local c = {}
            for i, x in ipairs(el.Value or {}) do c[i] = x end
            return c
        end
        return el.Value
    end
    local function has(o)
        for _, x in ipairs(el.Options) do if x == o then return true end end
        return false
    end
    local function filter()
        if multi then
            local out, seen = {}, {}
            for _, x in ipairs(type(el.Value) == "table" and el.Value or {}) do
                if has(x) and not seen[x] then seen[x] = true; out[#out + 1] = x end
            end
            el.Value = out
        elseif el.Value ~= nil and not has(el.Value) then
            el.Value = nil
        end
    end
    local function setOptions(list)
        local out, seen = {}, {}
        for _, o in ipairs(type(list) == "table" and list or {}) do
            o = tostring(o)
            if not seen[o] then seen[o] = true; out[#out + 1] = o end
        end
        el.Options = out
    end
    local function commit(silent)
        paint()
        if silent then
            if el.Flag then Library.Flags[el.Flag] = copyVal() end
        else
            Changed(el, copyVal())
        end
    end
    local function build()
        for _, r in pairs(rows) do pcall(function() r:Destroy() end) end
        if el._emptyLabel then pcall(function() el._emptyLabel:Destroy() end); el._emptyLabel = nil end
        rows, rowLabels = {}, {}
        if #el.Options == 0 then
            local e = Label(scroll, "No items", 12, "Muted", nil, {
                Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(8, 0), ZIndex = 6,
            })
            el._emptyLabel = e
        end
        for i, o in ipairs(el.Options) do
            local r = New("TextButton", {
                Parent = scroll, Size = UDim2.new(1, 0, 0, 26), Text = "", LayoutOrder = i,
                BackgroundTransparency = 1, AutoButtonColor = false, ZIndex = 5,
            }, { BackgroundColor3 = "Surface2" })
            Round(r, 6)
            rowLabels[r] = Label(r, o, 12, "Text", Enum.Font.GothamMedium, {
                Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), ZIndex = 6,
            })
            r.MouseButton1Click:Connect(function()
                if multi then
                    local nv, found = {}, false
                    for _, x in ipairs(el.Value) do
                        if x == o then found = true else nv[#nv + 1] = x end
                    end
                    if not found then nv[#nv + 1] = o end
                    el.Value = nv
                else
                    el.Value = o
                end
                commit(false)
            end)
            rows[o] = r
        end
        paint()
    end
    setOptions(opts.Options)
    local init = opts.Default
    if init == nil then init = opts.Value end
    el.Value = norm(init) or (multi and {} or nil)
    if multi and type(el.Value) ~= "table" then el.Value = {} end
    filter()
    build()

    function el:Set(v, silent)
        el.Value = norm(v); if multi and not el.Value then el.Value = {} end
        filter()
        commit(silent)
    end
    function el:Get() return copyVal() end
    function el:Refresh(options, keep)
        setOptions(options)
        if not keep then el.Value = multi and {} or nil end
        filter()
        build()
        commit(true)
    end
    function el:Add(o)
        o = tostring(o)
        if has(o) then return end
        el.Options[#el.Options + 1] = o
        build()
    end
    function el:Remove(o)
        o = tostring(o)
        for i = #el.Options, 1, -1 do if el.Options[i] == o then table.remove(el.Options, i) end end
        filter()
        build()
        commit(true)
    end
    el._save = function() return copyVal() end
    el._load = function(v) el:Set(v) end
    if opts.Tooltip then Library:AttachTooltip(head, opts.Tooltip) end
    Register(el)
    return el
end

-- install creators (CreateX + AddX aliases) on tabs and sections
for k, fn in pairs(Creators) do
    Tab[k] = fn
    Section[k] = fn
    local short = string.match(k, "^Create(.+)$")
    if short then
        Tab["Add" .. short] = fn
        Section["Add" .. short] = fn
    end
end

----------------------------------------------------------------------------------------------------
-- Configs (JSON in <ConfigFolder>/<name>.json, silently disabled when the executor has no file API)
----------------------------------------------------------------------------------------------------

local function ConfigName(name)
    local n = SanitizeName(name)
    if n == "" then n = "default" end
    return n
end

local function EncodeValue(el)
    if type(el._save) ~= "function" then return nil end
    local ok, v = pcall(el._save)
    if not ok then return nil end
    return v
end

function Window:SaveConfig(name)
    name = ConfigName(name)
    if not WriteFileFn then
        Library:Notify({ Title = "Config", Content = "Your executor has no writefile, configs are disabled", Type = "warning" })
        return false, "writefile unavailable"
    end
    local data = { SolUI = 1, Theme = Library.Theme, ToggleKey = self.ToggleKey, Flags = {} }
    if self._size then data.WindowSize = { self._size.X, self._size.Y } end
    if Presets.Custom then
        data.CustomTheme = {}
        for _, k in ipairs(ThemeKeys) do data.CustomTheme[k] = ToHex(Presets.Custom[k]) end
    end
    for flag, el in pairs(self.Options) do
        if el.Alive ~= false then
            local v = EncodeValue(el)
            if v ~= nil then data.Flags[flag] = v end
        end
    end
    local ok, json = pcall(JSONEncode, data)
    if not ok or type(json) ~= "string" then
        Library:Notify({ Title = "Config", Content = "Could not encode the config", Type = "error" })
        return false, "encode failed"
    end
    FS.EnsureFolder(self.ConfigFolder)
    local wrote = FS.Write(self.ConfigFolder .. "/" .. name .. ".json", json)
    if not wrote then
        Library:Notify({ Title = "Config", Content = "Could not write " .. name .. ".json", Type = "error" })
        return false, "write failed"
    end
    return true
end

function Window:LoadConfig(name)
    name = ConfigName(name)
    if not ReadFileFn then
        Library:Notify({ Title = "Config", Content = "Your executor has no readfile, configs are disabled", Type = "warning" })
        return false, "readfile unavailable"
    end
    local raw = FS.Read(self.ConfigFolder .. "/" .. name .. ".json")
    if type(raw) ~= "string" or raw == "" then
        Library:Notify({ Title = "Config", Content = "Config '" .. name .. "' not found", Type = "error" })
        return false, "not found"
    end
    local ok, data = pcall(JSONDecode, raw)
    if not ok or type(data) ~= "table" then
        Library:Notify({ Title = "Config", Content = "Config '" .. name .. "' is corrupted", Type = "error" })
        return false, "decode failed"
    end
    local flags = type(data.Flags) == "table" and data.Flags or data
    for flag, v in pairs(flags) do
        local el = self.Options[flag]
        if el and el.Alive ~= false and type(el._load) == "function" then
            local okLoad, err = pcall(el._load, v)
            if not okLoad then warn("[SolUI] could not load flag '" .. tostring(flag) .. "': " .. tostring(err)) end
        end
    end
    if type(data.CustomTheme) == "table" then
        Library:AddTheme("Custom", data.CustomTheme)
        if data.Theme == "Custom" and Library.Theme == "Custom" then Library:SetTheme("Custom") end
    end
    if type(data.WindowSize) == "table" and self.SetSize then
        self:SetSize(tonumber(data.WindowSize[1]), tonumber(data.WindowSize[2]))
    end
    if type(data.Theme) == "string" and Presets[data.Theme] and data.Theme ~= Library.Theme then
        Library:SetTheme(data.Theme)
    end
    if type(data.ToggleKey) == "string" then self:SetToggleKey(data.ToggleKey) end
    return true
end

function Window:ListConfigs()
    local out = {}
    for _, path in ipairs(FS.List(self.ConfigFolder)) do
        local file = string.match(tostring(path), "([^/\\]+)%.json$")
        if file then out[#out + 1] = file end
    end
    table.sort(out)
    return out
end

function Window:DeleteConfig(name)
    name = ConfigName(name)
    return FS.Delete(self.ConfigFolder .. "/" .. name .. ".json")
end

-- autoload: Window:LoadAutoloadConfig() loads "autoload.json" if it exists
function Window:LoadAutoloadConfig()
    if not ReadFileFn then return false end
    local raw = FS.Read(self.ConfigFolder .. "/autoload.json")
    if type(raw) ~= "string" or raw == "" then return false end
    return self:LoadConfig("autoload")
end

-- current theme as a Lua table string: Library:AddTheme("Name", <this table>)
function Library:ExportTheme()
    local out = { "{" }
    for _, k in ipairs(ThemeKeys) do
        local c = Theme[k]
        out[#out + 1] = string.format("    %s = Color3.fromRGB(%d, %d, %d),", k,
            math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
    end
    out[#out + 1] = "}"
    return table.concat(out, "\n")
end

----------------------------------------------------------------------------------------------------
-- Settings tab
----------------------------------------------------------------------------------------------------

function Window:CreateSettingsTab(opts)
    opts = opts or {}
    local win = self
    local tab = self:CreateTab({
        Name = opts.Name or "Settings",
        Icon = opts.Icon or "settings",
        Title = opts.Title or "Settings",
        Description = opts.Description or "Interface, themes and configs",
    })

    ------------------------------------------------ Appearance
    local appearance = tab:CreateSection({ Name = "Appearance", Icon = "palette", Value = Library.Theme })
    local themeLabel = Label(appearance._container, "Theme: " .. Library.Theme, 13, "Text", Enum.Font.GothamMedium, {
        Size = UDim2.new(1, 0, 0, 30),
        LayoutOrder = NextOrder(appearance),
        ZIndex = 4,
    })
    New("UIPadding", { Parent = themeLabel, PaddingLeft = UDim.new(0, 10) })
    local holder = New("Frame", {
        Parent = appearance._container,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = NextOrder(appearance),
        ZIndex = 4,
    })
    New("UIPadding", { Parent = holder, PaddingLeft = UDim.new(0, 10), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6) })
    New("UIGridLayout", {
        Parent = holder,
        CellSize = UDim2.fromOffset(30, 30),
        CellPadding = UDim2.fromOffset(10, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local swatches = {}
    local function refreshSwatches()
        for name, s in pairs(swatches) do
            local on = name == Library.Theme
            s.ring.Transparency = on and 0 or 1
            s.check.ImageTransparency = on and 0 or 1
        end
        themeLabel.Text = "Theme: " .. Library.Theme
        appearance:SetValue(Library.Theme)
    end
    local function buildSwatches()
        for _, s in pairs(swatches) do pcall(function() s.button:Destroy() end) end
        ClearTable(swatches)
        for i, name in ipairs(Library.ThemeOrder) do
            local pr = Presets[name]
            if pr then
                local sw = New("TextButton", {
                    Parent = holder,
                    Text = "",
                    LayoutOrder = i,
                    BackgroundColor3 = pr.Accent,
                    ZIndex = 4,
                })
                Round(sw, "full")
                Shade(sw, 0.62, 45)
                Pressable(sw, 0.88)
                local ring = Outline(sw, "Text", 2)
                local check = New("ImageLabel", {
                    Parent = sw,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromOffset(14, 14),
                    Image = Icons.check,
                    ImageColor3 = pr.AccentDark,
                    ScaleType = Enum.ScaleType.Fit,
                    ZIndex = 5,
                })
                swatches[name] = { button = sw, ring = ring, check = check }
                sw.MouseEnter:Connect(function() themeLabel.Text = "Theme: " .. name end)
                sw.MouseLeave:Connect(function() themeLabel.Text = "Theme: " .. Library.Theme end)
                sw.MouseButton1Click:Connect(function() Library:SetTheme(name) end)
            end
        end
        refreshSwatches()
    end
    buildSwatches()
    local knownThemes = #Library.ThemeOrder
    win._themeListeners = win._themeListeners or {}
    local function addListener(fn)
        ThemeListeners[#ThemeListeners + 1] = fn
        table.insert(win._themeListeners, fn)
    end
    addListener(function()
        if not win.Alive then return end
        if #Library.ThemeOrder ~= knownThemes then
            knownThemes = #Library.ThemeOrder
            buildSwatches()
        else
            refreshSwatches()
        end
    end)

    ------------------------------------------------ Theme editor (live)
    local editorKeys = { "Accent", "AccentDark", "Background", "Surface", "Surface2", "Surface3", "Stroke", "StrokeHover", "Text", "Muted" }
    local editor = tab:CreateSection({ Name = "Theme editor", Icon = "palette" })
    local baseTheme = Library.Theme ~= "Custom" and Library.Theme or "Mono"
    local pickers, syncing = {}, false
    -- picker drags are batched: one instant (tween-free) recolour per frame
    local pendingColors, applyQueued = {}, false
    local function flushEditor()
        applyQueued = false
        if not win.Alive or Library.Unloaded then return end
        local t = {}
        for _, key in ipairs(ThemeKeys) do t[key] = Theme[key] end
        for _, key in ipairs({ "Success", "Warning", "Error" }) do t[key] = Theme[key] end
        for key, c in pairs(pendingColors) do t[key] = c end
        pendingColors = {}
        ThemeInstant = true
        syncing = true
        pcall(function()
            Library:AddTheme("Custom", t)
            if Library.Theme ~= "Custom" then Library:SetTheme("Custom") end
        end)
        syncing = false
        ThemeInstant = false
    end
    for _, k in ipairs(editorKeys) do
        pickers[k] = editor:CreateColorPicker({
            Name = k,
            Default = Theme[k],
            Callback = function(c)
                if syncing or not win.Alive then return end
                pendingColors[k] = c
                if not applyQueued then
                    applyQueued = true
                    task.defer(flushEditor)
                end
            end,
        })
    end
    local function syncPickers()
        syncing = true
        for k, p in pairs(pickers) do pcall(function() p:Set(Theme[k], true) end) end
        syncing = false
    end
    win._themePickers = pickers
    editor:CreateButton({
        Name = "Reset theme",
        Icon = "play",
        Callback = function()
            Library:SetTheme(baseTheme)
            Library:Notify({ Title = "Theme", Content = "Reset to " .. baseTheme, Type = "info", Duration = 3 })
        end,
    })
    editor:CreateButton({
        Name = "Export theme",
        Icon = "copy",
        Callback = function()
            local str = Library:ExportTheme()
            if Library:SetClipboard(str) then
                Library:Notify({ Title = "Theme exported", Content = "Copied to the clipboard as a Lua table", Type = "success", Duration = 3 })
            else
                print(str)
                Library:Notify({ Title = "Clipboard unavailable", Content = "Theme printed to the console (F9)", Type = "warning", Duration = 5 })
            end
        end,
    })
    addListener(function(name)
        if not win.Alive then return end
        if name ~= "Custom" then baseTheme = name end
        if not syncing then syncPickers() end
    end)

    ------------------------------------------------ Interface
    local interface = tab:CreateSection({ Name = "Interface", Icon = "monitor" })
    win._toggleKeyEl = interface:CreateKeybind({
        Name = "Toggle key",
        Description = "Shows / hides the window",
        Default = win.ToggleKey,
        ChangedCallback = function(key)
            if key == "None" or KeyName(key) == nil then
                -- the toggle key can't be cleared: put the real key back on the chip
                local kb = win._toggleKeyEl
                if kb then task.defer(function() if kb.Alive then pcall(function() kb:Set(win.ToggleKey, true) end) end end) end
                return
            end
            do
                win:SetToggleKey(key)
                Library:Notify({ Title = "Toggle key", Content = "Now bound to " .. key, Type = "success", Duration = 3 })
            end
        end,
    })
    interface:CreateToggle({
        Name = "Notifications",
        Description = "Errors are always shown",
        Default = Library.NotificationsEnabled ~= false,
        Callback = function(v) Library.NotificationsEnabled = v end,
    })

    ------------------------------------------------ Configuration
    local configs = tab:CreateSection({ Name = "Configuration", Icon = "layout-grid" })
    local canSave = WriteFileFn ~= nil and ReadFileFn ~= nil
    configs:SetValue(canSave and win.ConfigFolder or "unavailable")
    local currentName = "default"
    configs:CreateInput({
        Name = "Config name",
        Placeholder = "default",
        Callback = function(t)
            if t ~= "" then currentName = t end
        end,
    })
    local list = configs:CreateDropdown({
        Name = "Saved configs",
        Options = win:ListConfigs(),
        Callback = function(v) if v then currentName = v end end,
    })
    configs:CreateButton({
        Name = "Save config",
        Icon = "check",
        Callback = function()
            if win:SaveConfig(currentName) then
                list:Refresh(win:ListConfigs())
                list:Set(ConfigName(currentName), true)
                Library:Notify({ Title = "Config saved", Content = ConfigName(currentName) .. ".json", Type = "success", Duration = 3 })
            end
        end,
    })
    configs:CreateButton({
        Name = "Load config",
        Icon = "play",
        Callback = function()
            if win:LoadConfig(currentName) then
                Library:Notify({ Title = "Config loaded", Content = ConfigName(currentName) .. ".json", Type = "success", Duration = 3 })
            end
        end,
    })
    configs:CreateButton({
        Name = "Delete config",
        Icon = "trash-2",
        Style = "danger",
        Confirm = "Click again to delete",
        Callback = function()
            win:DeleteConfig(currentName)
            list:Refresh(win:ListConfigs(), false)
        end,
    })

    ------------------------------------------------ Session
    local session = tab:CreateSection({ Name = "Session", Icon = "power" })
    session:CreateStat("Library", "SolUI v" .. Library.Version)
    session:CreateStat("Executor", ExecutorName())
    session:CreateStat("Player", LocalPlayer and LocalPlayer.Name or "?")
    session:CreateButton({
        Name = "Unload interface",
        Icon = "power",
        Style = "danger",
        Confirm = true,
        Callback = function() Library:Unload() end,
    })
    tab:EndSection()
    win.SettingsTab = tab
    return tab
end

----------------------------------------------------------------------------------------------------

return Library
