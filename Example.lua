--[[
    SolUI - example script
    Upload SolUI.lua to your GitHub repository and replace USER/REPO below.

    Local testing (executor workspace folder):
        local SolUI = loadstring(readfile("SolUI.lua"))()
]]

local SolUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/USER/REPO/main/SolUI.lua"))()

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local Window = SolUI:CreateWindow({
    Title = "My Hub",
    Subtitle = "v1.0",
    Logo = "M",                         -- one letter, or an rbxassetid:// image
    Theme = "Mono",                     -- Mono, Midnight, Ocean, Emerald, Amber, Nebula, Crimson
    ToggleKey = Enum.KeyCode.RightShift,
    ConfigFolder = "MyHub",             -- configs are saved in workspace/MyHub/*.json
    Resizable = true,                   -- drag the bottom-right grip (size is saved in configs)
    Discord = "https://discord.gg/yourinvite", -- or Discord = true + Invite = "https://discord.gg/..."
})

----------------------------------------------------------------------------------------------------
-- Main tab: one of every element
----------------------------------------------------------------------------------------------------
local Main = Window:CreateTab({ Name = "Main", Icon = "home", Description = "Every element of the library" })

Main:CreateSection({ Name = "Buttons & toggles", Icon = "play" })

Main:CreateButton({
    Name = "Say hello",
    Callback = function()
        SolUI:Notify({ Title = "Hello!", Content = "Hi " .. LocalPlayer.DisplayName .. " 👋", Type = "success" })
    end,
})

Main:CreateButton({
    Name = "Reset demo values",
    Description = "Asks for confirmation before running",
    Confirm = true,
    Callback = function()
        SolUI.Options.DemoToggle:Set(false)
        SolUI.Options.DemoSlider:Set(50)
        print("[Example] values reset")
    end,
})

Main:CreateToggle({
    Name = "Demo toggle",
    Description = "Prints its state in the console",
    Default = false,
    Flag = "DemoToggle",
    Callback = function(state)
        print("[Example] toggle:", state)
    end,
})

Main:CreateSection({ Name = "Values", Icon = "monitor" })

Main:CreateSlider({
    Name = "Demo slider",
    Min = 0, Max = 100, Default = 50, Increment = 1, Suffix = "%",
    Flag = "DemoSlider",
    Callback = function(value) print("[Example] slider:", value) end,
})

Main:CreateSlider({
    Name = "Price range",
    Range = true,                       -- dual knobs, callback gets (min, max)
    Min = 0, Max = 1000, Default = { 100, 750 }, Increment = 10, Prefix = "$",
    Flag = "PriceRange",
    Callback = function(lo, hi) print("[Example] range:", lo, hi) end,
})

Main:CreateSlider({
    Name = "Walk speed multiplier",
    Min = 0.5, Max = 3, Default = 1, Increment = 0.05, Decimals = 2, Suffix = "x",
    Flag = "SpeedMult",
})

Main:CreateButton({
    Name = "Notification with actions",
    Callback = function()
        SolUI:Notify({
            Title = "Teleport?",
            Content = "Hover to pause the timer",
            Duration = 8,
            Actions = {
                { Text = "Yes", Callback = function() print("[Example] yes") end },
                { Text = "No" },
            },
        })
    end,
})

Main:CreateDropdown({
    Name = "Difficulty",
    Options = { "Easy", "Normal", "Hard" },
    Default = "Normal",
    Flag = "Difficulty",
    Callback = function(option) print("[Example] difficulty:", option) end,
})

Main:CreateDropdown({
    Name = "Favourite fruits",
    Options = { "Apple", "Banana", "Cherry", "Mango" },
    Default = { "Apple" },
    Multi = true,
    Flag = "Fruits",
    Callback = function(list) print("[Example] fruits:", table.concat(list, ", ")) end,
})

Main:CreateInput({
    Name = "Nickname",
    Placeholder = "Type something...",
    Flag = "Nickname",
    Callback = function(text) print("[Example] nickname:", text) end,
})

Main:CreateKeybind({
    Name = "Notify keybind",
    Default = Enum.KeyCode.G,
    Flag = "NotifyKey",
    Callback = function()
        SolUI:Notify({ Title = "Keybind", Content = "You pressed the keybind", Type = "info", Duration = 2 })
    end,
})

Main:CreateColorPicker({
    Name = "Favourite colour",
    Default = Color3.fromRGB(120, 170, 255),
    Flag = "FavColor",
    Callback = function(color) print("[Example] colour:", SolUI.ToHex(color)) end,
})

Main:EndSection()
Main:CreateLabel("Labels and paragraphs can be placed outside sections.")
Main:CreateParagraph({
    Title = "About",
    Content = "This example only prints and shows notifications. Replace the callbacks with your own code.",
})

----------------------------------------------------------------------------------------------------
-- Player tab: a harmless demo on your own character
----------------------------------------------------------------------------------------------------
local PlayerTab = Window:CreateTab({ Name = "Player", Icon = "user", Description = "Demo on your own character" })
PlayerTab:CreateSection({ Name = "Humanoid", Icon = "user" })

local function getHumanoid()
    local character = LocalPlayer.Character
    return character and character:FindFirstChildOfClass("Humanoid")
end

PlayerTab:CreateSlider({
    Name = "WalkSpeed (Demo)",
    Min = 16, Max = 50, Default = 16, Increment = 1,
    Flag = "DemoWalkSpeed",
    Callback = function(value)
        local humanoid = getHumanoid()
        if humanoid then humanoid.WalkSpeed = value end
    end,
})

PlayerTab:CreateButton({
    Name = "Show my stats",
    Callback = function()
        local humanoid = getHumanoid()
        SolUI:Notify({
            Title = LocalPlayer.Name,
            Content = humanoid and ("WalkSpeed: " .. humanoid.WalkSpeed .. "  |  Health: " .. math.floor(humanoid.Health)) or "No character yet",
            Type = "info",
        })
    end,
})

----------------------------------------------------------------------------------------------------
-- Extras: dropdown search/multi, progress bar, button grid, icon toggles
----------------------------------------------------------------------------------------------------
local Extras = Window:CreateTab({ Name = "Extras", Icon = "layout-grid", Description = "New elements" })
Extras:CreateSection({ Name = "Dropdowns", Icon = "search" })
local targets = Extras:CreateDropdown({
    Name = "Targets", Multi = true, Flag = "Targets",
    Options = { "Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel", "India", "Juliet" },
    Callback = function(list) print("[Example] targets:", table.concat(list, ", ")) end,
}) -- > 8 options: search box enabled automatically
Extras:CreateButton({ Name = "Select all targets", Callback = function() targets:SelectAll() end })
Extras:CreateButton({ Name = "Clear targets", Callback = function() targets:Clear() end })

Extras:CreateSection({ Name = "Progress", Icon = "info" })
local bar = Extras:CreateProgressBar({ Title = "Download", Value = 35 })
Extras:CreateButton({ Name = "+10%", Callback = function() bar:Set(bar:Get() + 10) end })

Extras:CreateSection({ Name = "Quick actions", Icon = "play" })
Extras:CreateButtonGrid({
    Title = "Teleports", Columns = 3,
    Buttons = {
        { Text = "Spawn", Icon = "user", Callback = function() print("[Example] spawn") end },
        { Text = "Shop", Icon = "key", Callback = function() print("[Example] shop") end },
        { Text = "Boss", Icon = "power", Callback = function() print("[Example] boss") end },
    },
})
Extras:CreateToggle({ Name = "God mode", Icon = "shield-check", Flag = "GodMode" })

-- v1.1: Checkbox, List, Modal, Tooltip
Extras:CreateCheckbox({ Name = "Auto collect", Flag = "AutoCollect", Tooltip = "Collects drops automatically",
    Callback = function(v) print("[Example] checkbox", v) end })
Extras:CreateList({ Name = "Targets", Options = { "Alpha", "Bravo", "Charlie" }, Multi = true, Height = 100,
    Flag = "Targets", Callback = function(v) print("[Example] list", table.concat(v, ", ")) end })
Extras:CreateModal({ Name = "Reset stats", Title = "Reset stats?", Content = "This cannot be undone.",
    ConfirmText = "Reset", Danger = true, Tooltip = "Opens a confirmation prompt",
    Callback = function(ok) print("[Example] confirmed:", ok) end })

----------------------------------------------------------------------------------------------------
-- Settings tab (themes, toggle key, configs, unload) + autoload
----------------------------------------------------------------------------------------------------
Window:CreateSettingsTab()
Window:LoadAutoloadConfig()

SolUI:OnUnload(function()
    print("[Example] unloaded")
end)

SolUI:Notify({ Title = "My Hub", Content = "Loaded! Press RightShift to hide/show.", Type = "success" })
