-- GamepadDefaultsKeyModifier: gives the controller's top face button (Y on Xbox)
-- something to do when you have no target. Settings sit in the game's
-- Options > AddOns > Gamepad Defaults Key Modifier, or /gdkm.
--
-- Files, one job each:
--   GamepadDefaultsKeyModifier.lua   saved settings, the settings page, events, /gdkm
--   FaceTopButton.lua                adds the chosen action to the game's own Y button
local ADDON_NAME = ...

local Modifier = {
    -- action: what Y does with no target (an ACTIONS id). Off by default: nothing
    -- changes until the player picks one.
    DEFAULTS = { action = 0 },
    ACTIONS = {
        { id = 0, label = "Off" },
        { id = 1, label = "Quests & Map" },
        { id = 2, label = "Bags" },
    },
}
_G.GamepadDefaultsKeyModifier = Modifier

local function actionForId(id)
    for _, action in ipairs(Modifier.ACTIONS) do
        if action.id == id then return action end
    end
end

function Modifier.GetSettings()
    if type(GamepadDefaultsKeyModifierDB) ~= "table" then GamepadDefaultsKeyModifierDB = {} end
    local settings = GamepadDefaultsKeyModifierDB
    for key in pairs(settings) do
        if Modifier.DEFAULTS[key] == nil then settings[key] = nil end
    end
    if actionForId(settings.action) == nil then settings.action = Modifier.DEFAULTS.action end
    return settings
end

-- Settings: Options > AddOns > Gamepad Defaults Key Modifier

local function sliderOptions()
    local options = Settings.CreateSliderOptions(0, #Modifier.ACTIONS - 1, 1)
    local rightLabel = MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label
        and MinimalSliderWithSteppersMixin.Label.Right
    if rightLabel and options.SetLabelFormatter then
        options:SetLabelFormatter(rightLabel, function(value)
            local action = actionForId(math.floor(value + 0.5))
            return action and action.label or Modifier.ACTIONS[1].label
        end)
    end
    return options
end

function Modifier.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local settings = Modifier.GetSettings()
    local category = Settings.RegisterVerticalLayoutCategory("Gamepad Defaults Key Modifier")
    Modifier.category = category

    local setting = Settings.RegisterAddOnSetting(category, "GamepadDefaultsKeyModifier_action", "action", settings,
        Settings.VarType.Number, "Y with no target", Modifier.DEFAULTS.action)
    Settings.CreateSlider(category, setting, sliderOptions(),
        "What the controller's top face button (Y on Xbox) does when you have no target.\n\n"
        .. "• Off: nothing, as the game does\n"
        .. "• Quests & Map: opens or closes the quest log and map\n"
        .. "• Bags: opens or closes your bags\n\n"
        .. "With a target, Y still opens its menu.")
    Settings.RegisterAddOnCategory(category)
end

function Modifier.Open()
    if Modifier.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(Modifier.category:GetID())
    end
end

-- Events

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        Modifier.GetSettings()
        pcall(Modifier.RegisterSettings)
    elseif event == "PLAYER_LOGIN" then
        Modifier.FaceTopButton.Start()
    end
end)

-- /gdkm (or /gamepaddefaultskeymodifier) opens the settings.
SLASH_GAMEPADDEFAULTSKEYMODIFIER1 = "/gdkm"
SLASH_GAMEPADDEFAULTSKEYMODIFIER2 = "/gamepaddefaultskeymodifier"
SlashCmdList.GAMEPADDEFAULTSKEYMODIFIER = function()
    Modifier.Open()
end
