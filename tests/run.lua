-- GamepadDefaultsKeyModifier against a fake game: the controller UI's main action
-- bar with its Y (inspect) button, the target, and the Settings API.
-- From GamepadDefaultsKeyModifier:  luajit tests/run.lua
-- GDKM_TEST="part of a name" runs only the tests whose name holds it.
local failed, passed = 0, 0
local only = os.getenv("GDKM_TEST")
local function test(name, testBody)
    if only and not name:find(only, 1, true) then return end
    local ok, err = xpcall(testBody, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. "\n" .. err) end
end
local function expectEqual(actual, expected, message)
    if actual ~= expected then error((message or "") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local game

-- A button as the game's frames behave: SetScript drops the hooks, HookScript runs after.
local function newButton()
    local button = { hooks = {} }
    function button:SetScript(_, script) self.script = script; self.hooks = {} end
    function button:GetScript() return self.script end
    function button:HookScript(_, hook) self.hooks[#self.hooks + 1] = hook end
    function button:IsForbidden() return false end
    function button:Click(down)
        if self.script then self.script(self, "LeftButton", down) end
        for _, hook in ipairs(self.hooks) do hook(self, "LeftButton", down) end
    end
    return button
end

-- options.saved: the saved settings; options.barReady: the game set up Y before PLAYER_LOGIN.
local function boot(options)
    options = options or {}
    game = { targetExists = false, modifierDown = false, questLog = 0, bags = 0, targetMenu = 0, frames = {} }
    _G.GamepadDefaultsKeyModifierDB = options.saved
    _G.SlashCmdList = {}
    _G.UnitExists = function(unit) return unit == "target" and game.targetExists end
    _G.ToggleQuestLog = function() game.questLog = game.questLog + 1 end
    _G.ToggleAllBags = function() game.bags = game.bags + 1 end
    _G.GamepadMode = { IsTargetingModifierDown = function() return game.modifierDown end }
    _G.hooksecurefunc = function(owner, key, hook)
        local original = owner[key]
        owner[key] = function(...) local results = { original(...) }; hook(...); return unpack(results) end
    end
    _G.CreateFrame = function()
        local frame = { events = {} }
        function frame:RegisterEvent(event) self.events[event] = true end
        function frame:UnregisterEvent(event) self.events[event] = nil end
        function frame:SetScript(_, script) self.script = script end
        game.frames[#game.frames + 1] = frame
        return frame
    end
    _G.Settings = {
        VarType = { Number = "number" },
        RegisterVerticalLayoutCategory = function(name) return { name = name, GetID = function() return name end } end,
        RegisterAddOnSetting = function() return {} end,
        CreateSliderOptions = function() return {} end,
        CreateSlider = function() return {} end,
        RegisterAddOnCategory = function() end,
    }

    -- The game's main bar and its Y button (MainActionBarFrame.lua:562-577, 669).
    game.inspectButton = newButton()
    local bar = { PageUnit = { actionBars = { topBar = { Right = { ActionButton2 = game.inspectButton } } } } }
    function bar.PostVariableSetUp()
        game.inspectButton:SetScript("OnClick", function(_, _, down)
            if not down and game.targetExists then game.targetMenu = game.targetMenu + 1 end
        end)
    end
    _G.GamepadMainActionBarFrame = bar
    if options.barReady ~= false then bar.PostVariableSetUp() end

    for _, file in ipairs({ "GamepadDefaultsKeyModifier.lua", "FaceTopButton.lua" }) do
        assert(loadfile(file))("GamepadDefaultsKeyModifier")
    end
    local function fire(event, ...)
        for _, frame in ipairs(game.frames) do if frame.events[event] and frame.script then frame.script(frame, event, ...) end end
    end
    fire("ADDON_LOADED", "GamepadDefaultsKeyModifier")
    fire("PLAYER_LOGIN")
end

local function pressY()
    game.inspectButton:Click(true)
    game.inspectButton:Click(false)
end

test("off by default: Y with no target does nothing, as the game", function()
    boot()
    pressY()
    expectEqual(game.questLog + game.bags, 0, "actions run")
end)

test("Quests & Map: Y with no target toggles the quest log and map, once per press", function()
    boot({ saved = { action = 1 } })
    pressY()
    expectEqual(game.questLog, 1, "quest log toggles")
    pressY()
    expectEqual(game.questLog, 2, "quest log toggles")
end)

test("Bags: Y with no target toggles the bags", function()
    boot({ saved = { action = 2 } })
    pressY()
    expectEqual(game.bags, 1, "bag toggles")
    expectEqual(game.questLog, 0, "quest log toggles")
end)

test("with a target, Y still opens its menu and nothing else", function()
    boot({ saved = { action = 1 } })
    game.targetExists = true
    pressY()
    expectEqual(game.targetMenu, 1, "target menus")
    expectEqual(game.questLog, 0, "quest log toggles")
end)

test("targeting modifier held (raid markers on Y): nothing added", function()
    boot({ saved = { action = 1 } })
    game.modifierDown = true
    pressY()
    expectEqual(game.questLog, 0, "quest log toggles")
end)

test("the game sets Y up after login: the hook goes on after, not lost to its SetScript", function()
    boot({ saved = { action = 1 }, barReady = false })
    expectEqual(_G.GamepadDefaultsKeyModifier.FaceTopButton.IsHooked(), false, "hooked before the game set it up")
    _G.GamepadMainActionBarFrame.PostVariableSetUp()
    pressY()
    expectEqual(game.questLog, 1, "quest log toggles")
end)

test("the setting changed in game applies to the next press, no reload", function()
    boot()
    _G.GamepadDefaultsKeyModifierDB.action = 2
    pressY()
    expectEqual(game.bags, 1, "bag toggles")
end)

test("no controller bar (controller UI off): nothing breaks", function()
    boot({ saved = { action = 1 } })
    _G.GamepadMainActionBarFrame = nil
    expectEqual(_G.GamepadDefaultsKeyModifier.FaceTopButton.Find(), nil, "button")
end)

test("saved keys the addon doesn't use are dropped, an unknown action falls back to Off", function()
    boot({ saved = { action = 9, old = true } })
    expectEqual(_G.GamepadDefaultsKeyModifierDB.old, nil, "old key")
    expectEqual(_G.GamepadDefaultsKeyModifierDB.action, 0, "action")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
