local passed, failed = 0, 0
local standardPrint = print

local function test(name, body)
    local ok, err = xpcall(body, debug.traceback)
    _G.print = standardPrint
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("FAIL " .. name .. "\n" .. err)
    end
end

local function expectEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function boot(options)
    options = options or {}
    local game = { frames = {}, registered = {}, unregistered = {}, combat = false, action = options.action or "INTERACTTARGET" }
    _G.GamepadDefaultsKeyModifierDB = options.saved
    _G.GAMEPAD_FACE_TOP = "PAD4"
    _G.UIParent = {}
    _G.SlashCmdList = {}
    _G.InCombatLockdown = function() return game.combat end
    _G.GetBindingAction = function(key)
        expectEqual(key, "PAD4", "queried key")
        return game.action
    end
    _G.RegisterStateDriver = function(frame, state, condition)
        game.registered[#game.registered + 1] = { frame = frame, state = state, condition = condition }
    end
    _G.UnregisterStateDriver = function(frame, state)
        game.unregistered[#game.unregistered + 1] = { frame = frame, state = state }
    end
    _G.CreateFrame = function(_, name)
        local frame = { events = {}, attributes = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(_, script) self.script = script end
        function frame:SetAttribute(key, value) self.attributes[key] = value end
        function frame:ClearBindings() self.cleared = (self.cleared or 0) + 1 end
        game.frames[#game.frames + 1] = frame
        if name then game.router = frame else game.eventFrame = frame end
        return frame
    end
    game.settingChanged = {}
    _G.Settings = {
        VarType = { Number = "number" },
        RegisterVerticalLayoutCategory = function(name) return { name = name } end,
        RegisterAddOnSetting = function(_, variable, key, saved)
            return { variable = variable, key = key, saved = saved }
        end,
        SetOnValueChangedCallback = function(variable, callback) game.settingChanged[variable] = callback end,
        CreateSliderOptions = function(minimum, maximum, step)
            return { minimum = minimum, maximum = maximum, step = step }
        end,
        CreateSlider = function(_, setting, options) game.slider = { setting = setting, options = options } end,
        RegisterAddOnCategory = function() end,
    }

    assert(loadfile("GamepadDefaultsKeyModifier.lua"))("GamepadDefaultsKeyModifier")
    game.fire = function(event, ...)
        if game.eventFrame.events[event] then game.eventFrame.script(game.eventFrame, event, ...) end
    end
    game.fire("ADDON_LOADED", "GamepadDefaultsKeyModifier")
    game.fire("PLAYER_LOGIN")
    return game
end

test("defaults leave the controller binding alone", function()
    local game = boot()
    expectEqual(_G.GamepadDefaultsKeyModifierDB.action, 0, "default action")
    expectEqual(#game.registered, 0, "registered state drivers")
    expectEqual(game.router.cleared, 1, "cleared bindings")
end)

test("world map is used without a target and the original action is retained", function()
    local game = boot()
    _G.GamepadDefaultsKeyModifierDB.action = 1
    game.settingChanged.GamepadDefaultsKeyModifier_action()

    expectEqual(game.router.attributes.key, "PAD4", "top face button")
    expectEqual(game.router.attributes["target-command"], "INTERACTTARGET", "target action")
    expectEqual(game.router.attributes["fallback-command"], "TOGGLEWORLDMAP", "no-target action")
    expectEqual(game.registered[1].state, "target", "state driver")
    expectEqual(game.registered[1].condition, "[@target,exists] 1; 0", "target condition")
end)

test("bags can be selected as the no-target action", function()
    local game = boot()
    _G.GamepadDefaultsKeyModifierDB.action = 2
    game.settingChanged.GamepadDefaultsKeyModifier_action()
    expectEqual(game.router.attributes["fallback-command"], "OPENALLBAGS", "no-target action")

    game.action = "CUSTOM_ACTION"
    game.settingChanged.GamepadDefaultsKeyModifier_action()
    expectEqual(game.router.attributes["target-command"], "CUSTOM_ACTION", "updated target action")
end)

test("binding changes requested in combat are applied after combat", function()
    local game = boot()
    game.combat = true
    _G.GamepadDefaultsKeyModifierDB.action = 1
    game.settingChanged.GamepadDefaultsKeyModifier_action()
    expectEqual(#game.registered, 0, "drivers registered in combat")
    expectEqual(game.eventFrame.events.PLAYER_REGEN_ENABLED, true, "combat-end event")

    game.combat = false
    game.fire("PLAYER_REGEN_ENABLED")
    expectEqual(game.router.attributes["fallback-command"], "TOGGLEWORLDMAP", "deferred action")
    expectEqual(game.eventFrame.events.PLAYER_REGEN_ENABLED, nil, "combat-end event removed")
end)

test("an unbound top face button reports the issue instead of installing a broken route", function()
    local messages = {}
    _G.print = function(message) messages[#messages + 1] = message end
    local game = boot({ action = "" })
    _G.GamepadDefaultsKeyModifierDB.action = 1
    local applied = game.settingChanged.GamepadDefaultsKeyModifier_action()
    expectEqual(applied, false, "apply result")
    expectEqual(#game.registered, 0, "registered state drivers")
    assert(messages[1]:find("No action is bound", 1, true))
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
