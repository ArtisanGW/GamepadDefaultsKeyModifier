local ADDON_NAME = ...

local Modifier = {
    DEFAULTS = { action = 0 },
    KEY = GAMEPAD_FACE_TOP or "PAD4",
    ACTIONS = {
        { id = 0, label = "Off" },
        { id = 1, label = "World map", command = "TOGGLEWORLDMAP" },
        { id = 2, label = "Bags", command = "OPENALLBAGS" },
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

local router
local applyAfterCombat
local eventFrame = CreateFrame("Frame")

local function createRouter()
    if router then return router end
    router = CreateFrame("Frame", "GamepadDefaultsKeyModifierRouter", UIParent, "SecureHandlerStateTemplate")
    router:SetAttribute("_onstate-target", [[
        local key = self:GetAttribute("key")
        local command = self:GetAttribute(newstate == "1" and "target-command" or "fallback-command")
        if key and command then
            self:SetBinding(true, key, command)
        end
    ]])
    return router
end

function Modifier.Apply()
    if InCombatLockdown() then
        applyAfterCombat = true
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end

    applyAfterCombat = false
    eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")

    local frame = createRouter()
    UnregisterStateDriver(frame, "target")
    frame:ClearBindings()

    local action = actionForId(Modifier.GetSettings().action)
    if not action.command then return true end

    local targetCommand = GetBindingAction(Modifier.KEY)
    if not targetCommand or targetCommand == "" then
        print("|cffff5555Gamepad Defaults Key Modifier:|r No action is bound to " .. Modifier.KEY .. ".")
        return false
    end

    frame:SetAttribute("key", Modifier.KEY)
    frame:SetAttribute("target-command", targetCommand)
    frame:SetAttribute("fallback-command", action.command)
    RegisterStateDriver(frame, "target", "[@target,exists] 1; 0")
    return true
end

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

    local variableName = "GamepadDefaultsKeyModifier_action"
    local setting = Settings.RegisterAddOnSetting(category, variableName, "action", settings,
        Settings.VarType.Number, "When you have no target", Modifier.DEFAULTS.action)
    Settings.SetOnValueChangedCallback(variableName, Modifier.Apply)
    Settings.CreateSlider(category, setting, sliderOptions(),
        "Choose what the controller's top face button (Y on Xbox) does when you have no target.\n\n"
        .. "With a target, its existing action is unchanged.")
    Settings.RegisterAddOnCategory(category)
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        Modifier.GetSettings()
        Modifier.RegisterSettings()
    elseif event == "PLAYER_LOGIN" or (event == "PLAYER_REGEN_ENABLED" and applyAfterCombat) then
        Modifier.Apply()
    end
end)
