-- The controller's top face button (Y on Xbox) with no target.
--
-- On the controller UI, Y is the game's own "inspect" button on its main action
-- bar (forever branch: Blizzard_GamepadActionBars/MainActionBarFrame.lua:562-577).
-- With a target, its release opens the target's menu; with none, it does nothing.
--
-- With no target, on the HUD (no window open), this binds Y to one of the game's
-- own key bindings instead: TOGGLEQUESTLOG or OPENALLBAGS (Bindings_Standard.xml).
-- Only while the game's top bar is the one under the face buttons: that's the bar
-- where Y is the inspect button. Holding LT or RT (or both), a vehicle's bar, or
-- another bar the game puts in its place (PageUnit.lua: ActionBarModKeyDownStateCheck)
-- has a skill on Y, so Y stays the game's there (GAMEPADACTIONBUTTON6, Bindings.xml).
-- The game's binding code then opens the window, so it opens as the game's own.
-- Opening it from addon code (a hook after the game's click) tainted the window,
-- and closing it then failed with "Interface action failed" (2026-11-24).
--
-- The binding sits on a secure frame of its own and is set by secure code:
-- • a state driver clears it as soon as you have a target, in combat too, so Y
--   opens the target's menu again
-- • the same state driver clears it for the whole fight: in combat, addon code
--   can't change it when you press LT or RT, and secure code can't see them
--   (no IsKeyDown in RestrictedEnvironment.lua), so Y stays the game's on every bar
-- • a post-hook on the game's SetActiveActionBar (PageUnit.lua) sets it again, or
--   clears it, each time the game changes the bar under the face buttons
-- • the game re-sets its own controller keys when a window opens or closes
--   (InputBindingManager.lua: AddBindingSet, RemoveSet, ClearBindings); a
--   post-hook on each sets the binding again after it, so it's the newest on Y,
--   or clears it while a window is open, so Y stays the game's there
-- Never a listener in the game's own list (BindToCoreBindingActive): the game
-- calls those while it opens a window, and addon code there tainted it (an
-- error on pressing Y with the window open, 2026-11-24).
local Modifier = _G.GamepadDefaultsKeyModifier

local FaceTopButton = {
    Y_KEY = GAMEPAD_FACE_TOP or "PAD4",
    -- The game's key binding for each setting (Modifier.ACTIONS ids); Off binds nothing.
    BINDING_FOR_ACTION = { [1] = "TOGGLEQUESTLOG", [2] = "OPENALLBAGS" },
}
Modifier.FaceTopButton = FaceTopButton

local bindingFrame                  -- the secure frame that holds the Y binding
local attributesAfterCombat = {}    -- attribute name -> value, set once combat ends

-- Runs in the game's secure environment each time an attribute of bindingFrame
-- changes; the game passes the changed attribute's name as `name`.
local UPDATE_BINDING_SNIPPET = [[
    local watched = name == "state-ybutton" or name == "hud-shown" or name == "top-bar-active"
        or name == "binding-command" or name == "rebind-count"
    if not watched then return end
    self:ClearBindings()
    local bindingCommand = self:GetAttribute("binding-command")
    local yFree = self:GetAttribute("state-ybutton") == "free"
    local onTheHud = self:GetAttribute("hud-shown") and self:GetAttribute("top-bar-active")
    if bindingCommand ~= "" and yFree and onTheHud then
        self:SetBinding(true, self:GetAttribute("binding-key"), bindingCommand)
    end
]]

local function bindingForChosenAction()
    return FaceTopButton.BINDING_FOR_ACTION[Modifier.GetSettings().action] or ""
end

-- Out of combat at once; in combat, once it ends (addon code can't change a
-- secure frame's attributes in combat).
local function setAttributeWhenAllowed(name, value)
    if InCombatLockdown() then
        attributesAfterCombat[name] = value
        return
    end
    bindingFrame:SetAttribute(name, value)
end

function FaceTopButton.ApplyAttributesAfterCombat()
    for name, value in pairs(attributesAfterCombat) do
        attributesAfterCombat[name] = nil
        local succeeded, errorMessage = pcall(bindingFrame.SetAttribute, bindingFrame, name, value)
        if not succeeded then geterrorhandler()(errorMessage) end
    end
end

-- The setting changed: the next press does the new thing, no reload.
function FaceTopButton.ApplyChosenAction()
    if not bindingFrame then return end
    setAttributeWhenAllowed("binding-command", bindingForChosenAction())
end

-- The game's stack of controller keys, or nil without the controller UI's code.
function FaceTopButton.GameBindingManager()
    local bindingManager = _G.GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    if type(bindingManager) ~= "table" or type(bindingManager.IsOnlyCoreBindingSetActive) ~= "function" then
        return nil
    end
    return bindingManager
end

-- True when only the game's HUD keys are on (no window open). Without the
-- game's binding manager, the HUD is taken as shown.
function FaceTopButton.HudShown()
    local bindingManager = FaceTopButton.GameBindingManager()
    return bindingManager == nil or bindingManager:IsOnlyCoreBindingSetActive() == true
end

-- The game's set of controller bars (PageUnit.lua), or nil without the controller UI.
function FaceTopButton.GamePageUnit()
    local mainBar = _G.GamepadMainActionBarFrame
    local pageUnit = type(mainBar) == "table" and mainBar.PageUnit
    if type(pageUnit) ~= "table" or type(pageUnit.GetActiveBar) ~= "function" or type(pageUnit.actionBars) ~= "table" then
        return nil
    end
    return pageUnit
end

-- True when the bar under the face buttons is the game's top bar, where Y is the
-- inspect button: no LT or RT held, no other bar in its place. Before the game
-- picked one, and without the controller UI's bars, the top bar is taken as active.
function FaceTopButton.TopBarActive()
    local pageUnit = FaceTopButton.GamePageUnit()
    if not pageUnit then return true end
    local activeBar = pageUnit:GetActiveBar()
    return activeBar == nil or activeBar == pageUnit.actionBars.topBar
end

local function afterActiveBarChanged()
    setAttributeWhenAllowed("top-bar-active", FaceTopButton.TopBarActive())
end

-- After the game changed its keys: on the HUD, the Y binding is set again after them.
local function afterGameKeysChanged()
    local shown = FaceTopButton.HudShown()
    setAttributeWhenAllowed("hud-shown", shown)
    if shown then
        setAttributeWhenAllowed("rebind-count", (bindingFrame:GetAttribute("rebind-count") or 0) + 1)
    end
end

-- The game's methods that change its controller keys (InputBindingManager.lua).
FaceTopButton.GAME_KEY_METHODS = { "AddBindingSet", "RemoveSet", "ClearBindings" }

local function hookGameKeyChanges()
    local bindingManager = FaceTopButton.GameBindingManager()
    if not bindingManager then return end
    for _, methodName in ipairs(FaceTopButton.GAME_KEY_METHODS) do
        if type(bindingManager[methodName]) == "function" then
            hooksecurefunc(bindingManager, methodName, afterGameKeysChanged)
        end
    end
end

local function hookActiveBarChanges()
    local pageUnit = FaceTopButton.GamePageUnit()
    if pageUnit and type(pageUnit.SetActiveActionBar) == "function" then
        hooksecurefunc(pageUnit, "SetActiveActionBar", afterActiveBarChanged)
    end
end

function FaceTopButton.Start()
    if bindingFrame then return end
    bindingFrame = CreateFrame("Frame", "GamepadDefaultsKeyModifierYBinding", UIParent, "SecureHandlerAttributeTemplate")
    bindingFrame:SetAttribute("binding-key", FaceTopButton.Y_KEY)
    bindingFrame:SetAttribute("hud-shown", FaceTopButton.HudShown())
    bindingFrame:SetAttribute("top-bar-active", FaceTopButton.TopBarActive())
    bindingFrame:SetAttribute("binding-command", bindingForChosenAction())
    bindingFrame:SetAttribute("_onattributechanged", UPDATE_BINDING_SNIPPET)
    -- Secure code sets "state-ybutton", in combat too: "game" with a target or in combat.
    RegisterStateDriver(bindingFrame, "ybutton", "[combat][@target,exists] game; free")
    hookGameKeyChanges()
    hookActiveBarChanges()
end
