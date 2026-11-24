-- The controller's top face button (Y on Xbox) with no target.
--
-- On the controller UI, Y is the game's own "inspect" button on its main action
-- bar (forever branch: Blizzard_GamepadActionBars/MainActionBarFrame.lua:562-577,
-- topBar.Right.ActionButton2, mapped to GAMEPAD_FACE_TOP in ActionBarTemplates.xml:262-269).
-- With a target, its release opens the target's menu; with none, it does nothing.
--
-- This file adds to it, after the game's own click (HookScript): on release, with
-- no target and the targeting modifier not held (it puts raid markers on Y), it
-- does what the settings say: the quest log and map, or the bags. The button, its
-- binding and its target menu stay the game's.
--
-- The game sets the button's click in PostVariableSetUp (MainActionBarFrame.lua:669)
-- with SetScript, which would drop a hook made before: so the hook goes on after it.
local Modifier = _G.GamepadDefaultsKeyModifier

local FaceTopButton = {}
Modifier.FaceTopButton = FaceTopButton

local hookedButton

-- What each setting does with no target (Modifier.ACTIONS ids).
local RUN = {
    [1] = function() if type(ToggleQuestLog) == "function" then ToggleQuestLog() end end,
    [2] = function() if type(ToggleAllBags) == "function" then ToggleAllBags() end end,
}

local function targetingModifierDown()
    local gamepadMode = _G.GamepadMode
    return type(gamepadMode) == "table" and type(gamepadMode.IsTargetingModifierDown) == "function"
        and gamepadMode.IsTargetingModifierDown() == true
end

-- After the game's own click.
local function afterClick(_, _, down)
    if down then return end   -- the game acts on release too
    if UnitExists("target") or targetingModifierDown() then return end
    local run = RUN[Modifier.GetSettings().action]
    if run then run() end
end

-- The game's Y button, once it's set up.
function FaceTopButton.Find()
    local bar = _G.GamepadMainActionBarFrame
    local button = type(bar) == "table" and bar.PageUnit and bar.PageUnit.actionBars
        and bar.PageUnit.actionBars.topBar and bar.PageUnit.actionBars.topBar.Right
        and bar.PageUnit.actionBars.topBar.Right.ActionButton2
    if type(button) ~= "table" or type(button.HookScript) ~= "function" then return nil end
    if button.IsForbidden and button:IsForbidden() then return nil end
    if not button:GetScript("OnClick") then return nil end   -- the game hasn't set it up yet
    return button
end

-- Hooks the game's Y button once; true when it's hooked.
function FaceTopButton.Hook()
    local button = FaceTopButton.Find()
    if not button then return false end
    if hookedButton == button then return true end
    button:HookScript("OnClick", afterClick)
    hookedButton = button
    return true
end

-- Now if the game's bar is set up, else right after it is.
function FaceTopButton.Start()
    if FaceTopButton.Hook() then return end
    local bar = _G.GamepadMainActionBarFrame
    if type(bar) == "table" and type(bar.PostVariableSetUp) == "function" then
        hooksecurefunc(bar, "PostVariableSetUp", FaceTopButton.Hook)
    end
end

function FaceTopButton.IsHooked() return hookedButton ~= nil end
