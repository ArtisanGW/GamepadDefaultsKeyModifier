-- GamepadDefaultsKeyModifier against a fake game: a secure frame whose attribute
-- snippet runs as plain Lua, the target and combat state driver, the game's
-- controller binding manager and bars, combat, and the Settings API.
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

-- A frame. A secure one runs its "_onattributechanged" snippet on each SetAttribute,
-- and refuses attribute changes in combat, as the game does for addon code.
local function newFrame(template)
    local frame = { events = {}, attributes = {}, template = template, bindings = {} }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(_, script) self.script = script end
    function frame:GetAttribute(name) return self.attributes[name] end
    function frame:ClearBindings() self.bindings = {} end
    function frame:SetBinding(priority, key, command)
        self.bindings[key] = { priority = priority, command = command }
        game.bindsSet = game.bindsSet + 1
    end
    function frame:SetAttribute(name, value)
        if self.template and game.inCombat and not game.secureCall then error("ADDON_ACTION_BLOCKED SetAttribute") end
        self.attributes[name] = value
        local snippet = self.attributes._onattributechanged
        if snippet and name ~= "_onattributechanged" then
            assert(loadstring("local self, name, value = ...\n" .. snippet))(self, name, value)
        end
    end
    game.frames[#game.frames + 1] = frame
    return frame
end

-- options.saved: the saved settings; options.inCombat: logged in mid-fight;
-- options.noManager: the game's binding manager is missing.
local function boot(options)
    options = options or {}
    game = { frames = {}, inCombat = options.inCombat or false, hud = true, bindsSet = 0, targetExists = false }
    _G.GamepadDefaultsKeyModifierDB = options.saved
    _G.GamepadDefaultsKeyModifierYBinding = nil
    _G.SlashCmdList = {}
    _G.UIParent = {}
    _G.InCombatLockdown = function() return game.inCombat end
    _G.geterrorhandler = function() return error end
    _G.CreateFrame = function(_, name, _, template)
        local frame = newFrame(template)
        if name then _G[name] = frame end
        return frame
    end
    -- The state driver ("[combat][@target,exists] game; free"): secure code sets
    -- "state-ybutton", in combat too.
    game.driveState = function()
        if not game.driven then return end
        game.secureCall = true
        game.driven.frame:SetAttribute("state-" .. game.driven.state, (game.inCombat or game.targetExists) and "game" or "free")
        game.secureCall = false
    end
    _G.RegisterStateDriver = function(frame, state)
        game.driven = { frame = frame, state = state }
        game.driveState()
    end
    _G.UnitAffectingCombat = function(unit) return unit == "player" and game.inCombat end
    _G.hooksecurefunc = function(owner, methodName, hook)
        local original = owner[methodName]
        owner[methodName] = function(...) local results = { original(...) }; hook(...); return unpack(results) end
    end
    -- The game's key stack: a window adds its keys, closing it removes them.
    game.bindingManager = {
        IsOnlyCoreBindingSetActive = function() return game.hud end,
        BindToCoreBindingActive = function() game.joinedListeners = true end,
        AddBindingSet = function() game.hud = false end,
        RemoveSet = function() game.hud = true end,
        ClearBindings = function() game.hud = true end,
    }
    _G.GamepadSharedUtility = not options.noManager and { InputBindingManager = game.bindingManager } or nil
    -- The game's Y button on its controller bar, with its magnifier texture.
    local function newTexture()
        local texture = { alpha = 1, shown = true, masks = {} }
        function texture:SetAtlas(atlas) self.atlas, self.file = atlas, nil end
        function texture:SetTexture(file) self.file, self.atlas = file, nil end
        function texture:SetColorTexture() self.file, self.atlas = nil, nil end
        function texture:GetAlpha() return self.alpha end
        function texture:SetAlpha(alpha) self.alpha = alpha end
        function texture:SetShown(shown) self.shown = shown end
        function texture:Hide() self.shown = false end
        function texture:SetAllPoints() end
        function texture:SetPoint() end
        function texture:GetDrawLayer() return "ARTWORK", 0 end
        function texture:AddMaskTexture(mask) self.masks[mask] = true end
        function texture:RemoveMaskTexture(mask) self.masks[mask] = nil end
        return texture
    end
    game.gameIcon = newTexture()
    game.gameIcon:SetAtlas("crosshair_unableinspect_32")
    game.circleMask = newTexture()
    local button = { SpecialActionIcon = game.gameIcon, CircleMask = game.circleMask }
    function button:CreateTexture() game.actionIcon = newTexture(); return game.actionIcon end
    function button:CreateMaskTexture() return newTexture() end
    function button:IsForbidden() return false end
    -- Its bars: the one under the face buttons changes with LT and RT (PageUnit.lua).
    game.topBar, game.leftBar = { Right = { ActionButton2 = button } }, {}
    local pageUnit = { actionBars = { topBar = game.topBar, leftBar = game.leftBar }, activeBar = game.topBar }
    function pageUnit:GetActiveBar() return self.activeBar end
    function pageUnit:SetActiveActionBar(bar) self.activeBar = bar end
    game.pageUnit = pageUnit
    _G.GamepadMainActionBarFrame = { PageUnit = pageUnit }
    game.atlases = options.atlases or { crosshair_directions_32 = true, crosshair_lootall_32 = true }
    _G.C_Texture = { GetAtlasInfo = function(atlas) return game.atlases[atlas] and {} or nil end }
    _G.UnitExists = function(unit) return unit == "target" and game.targetExists end
    _G.GamepadMode = { IsTargetingModifierDown = function() return game.modifierDown == true end }
    game.settingCallbacks = {}
    _G.Settings = {
        VarType = { Number = "number" },
        RegisterVerticalLayoutCategory = function(name) return { name = name, GetID = function() return name end } end,
        RegisterAddOnSetting = function()
            return { SetValueChangedCallback = function(_, callback) table.insert(game.settingCallbacks, callback) end }
        end,
        CreateSliderOptions = function() return {} end,
        CreateSlider = function() return {} end,
        RegisterAddOnCategory = function() end,
    }
    for _, file in ipairs({ "Code/GamepadDefaultsKeyModifier.lua", "Code/FaceTopButton.lua", "Code/YButtonIcon.lua" }) do
        assert(loadfile(file))("GamepadDefaultsKeyModifier")
    end
    game.fire = function(event, ...)
        for _, frame in ipairs(game.frames) do if frame.events[event] and frame.script then frame.script(frame, event, ...) end end
    end
    game.fire("ADDON_LOADED", "GamepadDefaultsKeyModifier")
    game.fire("PLAYER_LOGIN")
end

local function bindingFrame() return _G.GamepadDefaultsKeyModifierYBinding end
local function yBinding()
    local binding = bindingFrame() and bindingFrame().bindings.PAD4
    return binding and binding.command
end
-- The game redraws its magnifier on each target change (UpdateInspectIcon).
local function setTarget(exists)
    game.targetExists = exists
    game.gameIcon:SetAtlas(exists and "crosshair_inspect_32" or "crosshair_unableinspect_32")
    game.driveState()
end
-- A fight starts or ends: the state driver follows, then the game's event.
local function setCombat(inCombat)
    game.inCombat = inCombat
    game.driveState()
    game.fire(inCombat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
-- The game puts another bar under the face buttons (LT or RT held), or the top one back.
local function setActiveBar(bar)
    game.pageUnit:SetActiveActionBar(bar)
end
-- A window opens (its keys go on the game's stack) or closes (they come off).
local function setHud(active)
    if active then game.bindingManager:RemoveSet() else game.bindingManager:AddBindingSet() end
end

test("off by default: Y keeps the game's own binding", function()
    boot()
    expectEqual(yBinding(), nil, "Y bound")
end)

test("Quests & Map: Y with no target, on the HUD, is the game's Toggle Quest Log", function()
    boot({ saved = { action = 1 } })
    expectEqual(yBinding(), "TOGGLEQUESTLOG", "Y bound")
    expectEqual(bindingFrame().bindings.PAD4.priority, true, "over the game's own keys")
end)

test("Bags: Y with no target is the game's Open All Bags", function()
    boot({ saved = { action = 2 } })
    expectEqual(yBinding(), "OPENALLBAGS", "Y bound")
end)

test("a target gives Y back to the game, and losing it takes it again", function()
    boot({ saved = { action = 1 } })
    setTarget(true)
    expectEqual(yBinding(), nil, "Y bound with a target")
    setTarget(false)
    expectEqual(yBinding(), "TOGGLEQUESTLOG", "Y bound without one")
end)

test("a target in combat gives Y back too: the state driver is secure", function()
    boot({ saved = { action = 1 } })
    game.inCombat = true
    setTarget(true)
    expectEqual(yBinding(), nil, "Y bound with a target in combat")
end)

test("a window open gives Y back; its closing sets the binding again, the newest on Y", function()
    boot({ saved = { action = 1 } })
    setHud(false)
    expectEqual(yBinding(), nil, "Y bound with a window open")
    local before = game.bindsSet
    setHud(true)
    expectEqual(yBinding(), "TOGGLEQUESTLOG", "Y bound on the HUD again")
    assert(game.bindsSet > before, "set again after the game re-set its keys")
end)

test("never in the game's own listener list: it'd taint the game opening a window", function()
    boot({ saved = { action = 1 } })
    expectEqual(game.joinedListeners, nil, "joined the game's listeners")
end)

test("the game clearing all its keys: the binding is set again after", function()
    boot({ saved = { action = 1 } })
    setHud(false)
    game.bindingManager:ClearBindings()
    expectEqual(yBinding(), "TOGGLEQUESTLOG", "Y bound")
end)

test("a window closing in combat: set again once combat ends", function()
    boot({ saved = { action = 1 } })
    setHud(false)
    setCombat(true)
    setHud(true)
    expectEqual(yBinding(), nil, "Y bound during combat")
    setCombat(false)
    expectEqual(yBinding(), "TOGGLEQUESTLOG", "Y bound after combat")
end)

test("LT or RT held: Y is the game's, for the skill on that bar; the top bar back takes it again", function()
    boot({ saved = { action = 1 } })
    setActiveBar(game.leftBar)
    expectEqual(yBinding(), nil, "Y bound on another bar")
    setActiveBar(game.topBar)
    expectEqual(yBinding(), "TOGGLEQUESTLOG", "Y bound on the top bar")
end)

test("in combat: Y is the game's on every bar, as addon code can't follow LT and RT then", function()
    boot({ saved = { action = 1 } })
    setCombat(true)
    expectEqual(yBinding(), nil, "Y bound in combat")
    setActiveBar(game.leftBar)
    setActiveBar(game.topBar)
    expectEqual(yBinding(), nil, "Y bound in combat after LT")
    setCombat(false)
    expectEqual(yBinding(), "TOGGLEQUESTLOG", "Y bound after combat")
end)

test("combat ending with LT held: Y stays the game's until the top bar is back", function()
    boot({ saved = { action = 1 } })
    setCombat(true)
    setActiveBar(game.leftBar)
    setCombat(false)
    expectEqual(yBinding(), nil, "Y bound with LT held")
    setActiveBar(game.topBar)
    expectEqual(yBinding(), "TOGGLEQUESTLOG", "Y bound on the top bar")
end)

test("the setting changed in game applies at once, no reload", function()
    boot()
    _G.GamepadDefaultsKeyModifierDB.action = 2
    for _, callback in ipairs(game.settingCallbacks) do callback() end
    expectEqual(yBinding(), "OPENALLBAGS", "Y bound")
    _G.GamepadDefaultsKeyModifierDB.action = 0
    for _, callback in ipairs(game.settingCallbacks) do callback() end
    expectEqual(yBinding(), nil, "Y bound when Off")
end)

test("logged in mid-fight: the secure frame is made once combat ends", function()
    boot({ saved = { action = 1 }, inCombat = true })
    expectEqual(bindingFrame(), nil, "frame made in combat")
    game.inCombat = false
    game.fire("PLAYER_REGEN_ENABLED")
    expectEqual(yBinding(), "TOGGLEQUESTLOG", "Y bound after combat")
end)

test("no controller binding manager: the HUD is assumed, nothing breaks", function()
    boot({ saved = { action = 1 }, noManager = true })
    expectEqual(yBinding(), "TOGGLEQUESTLOG", "Y bound")
end)

test("saved keys the addon doesn't use are dropped, an unknown action falls back to Off", function()
    boot({ saved = { action = 9, old = true } })
    expectEqual(_G.GamepadDefaultsKeyModifierDB.old, nil, "old key")
    expectEqual(_G.GamepadDefaultsKeyModifierDB.action, 0, "action")
end)

-- Y's icon
local function iconShown() return game.actionIcon and game.actionIcon.shown and (game.actionIcon.atlas or game.actionIcon.file) or nil end

test("icon: Off keeps the game's magnifier", function()
    boot()
    expectEqual(iconShown(), nil, "our icon")
    expectEqual(game.gameIcon.alpha, 1, "magnifier alpha")
end)

test("icon: Quests & Map shows a map in place of the magnifier with no target", function()
    boot({ saved = { action = 1 } })
    expectEqual(iconShown(), "crosshair_directions_32", "our icon")
    expectEqual(game.gameIcon.alpha, 0, "magnifier alpha")
end)

test("icon: a target brings the game's magnifier back as it was", function()
    boot({ saved = { action = 2 } })
    expectEqual(iconShown(), "crosshair_lootall_32", "our icon")
    setTarget(true)
    expectEqual(iconShown(), nil, "our icon with a target")
    expectEqual(game.gameIcon.alpha, 1, "magnifier alpha")
    expectEqual(game.gameIcon.atlas, "crosshair_inspect_32", "the game's own icon untouched")
end)

test("icon: the targeting modifier (raid markers) shows the game's icon", function()
    boot({ saved = { action = 1 } })
    game.modifierDown = true
    game.gameIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    expectEqual(iconShown(), nil, "our icon")
end)

test("icon: LT or RT held shows the game's icon, the top bar back shows ours", function()
    boot({ saved = { action = 1 } })
    setActiveBar(game.leftBar)
    expectEqual(iconShown(), nil, "our icon on another bar")
    expectEqual(game.gameIcon.alpha, 1, "magnifier alpha")
    setActiveBar(game.topBar)
    expectEqual(iconShown(), "crosshair_directions_32", "our icon on the top bar")
end)

test("icon: in combat the game's icon, after it ours", function()
    boot({ saved = { action = 1 } })
    setCombat(true)
    expectEqual(iconShown(), nil, "our icon in combat")
    setCombat(false)
    expectEqual(iconShown(), "crosshair_directions_32", "our icon after combat")
end)

test("icon: a window open shows the game's icon, closing it shows ours again", function()
    boot({ saved = { action = 1 } })
    setHud(false)
    expectEqual(iconShown(), nil, "our icon with a window open")
    setHud(true)
    expectEqual(iconShown(), "crosshair_directions_32", "our icon after")
end)

test("icon: cut round by the button's own CircleMask, as the game's icons", function()
    boot({ saved = { action = 1 } })
    assert(game.actionIcon.masks[game.circleMask], "the button's CircleMask")
end)

test("icon: without the game's atlas, the item icon", function()
    boot({ saved = { action = 1 }, atlases = {} })
    expectEqual(iconShown(), "Interface\\Icons\\INV_Misc_Map_01", "our icon")
end)

test("icon: the setting changed in game shows at once", function()
    boot()
    _G.GamepadDefaultsKeyModifierDB.action = 2
    for _, callback in ipairs(game.settingCallbacks) do callback() end
    expectEqual(iconShown(), "crosshair_lootall_32", "our icon")
end)

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
