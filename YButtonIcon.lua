-- The icon on the game's Y button, on the controller UI's main action bar.
--
-- The game shows a magnifier there (forever branch: MainActionBarFrame.lua:586-617,
-- UpdateInspectIcon): "crosshair_inspect_32" with a target, "crosshair_unableinspect_32"
-- without. While Y does the chosen action instead (FaceTopButton.lua: no target,
-- no window open, the targeting modifier up), this shows the action's icon on top
-- and fades the game's magnifier out; otherwise the game's own icon is back as it was.
--
-- A cosmetic layer only: the game's icon is never changed, only faded (its alpha,
-- kept to put back). Its updates are followed with post-hooks on the texture the
-- game sets (SetAtlas, SetTexture, SetColorTexture), and on the game's controller
-- key changes, so the game's own code and events run untouched.
local Modifier = _G.GamepadDefaultsKeyModifier
local FaceTopButton = Modifier.FaceTopButton

local YButtonIcon = {
    -- For each action (Modifier.ACTIONS ids): the game's atlases to try, in order
    -- (the cursor-style ones match the magnifier), then an item icon.
    ICONS = {
        [1] = { atlases = { "crosshair_directions_32" }, texture = "Interface\\Icons\\INV_Misc_Map_01" },
        [2] = { atlases = { "crosshair_lootall_32", "crosshair_pickup_32" }, texture = "Interface\\Icons\\INV_Misc_Bag_08" },
    },
    -- Only if the button has no CircleMask of its own: a round mask of the same size.
    ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
}
Modifier.YButtonIcon = YButtonIcon

local gameIcon            -- the game's texture on Y (its SpecialActionIcon)
local gameIconAlpha       -- its alpha before we faded it
local actionIcon          -- our texture, on top of it, cut round as the game's icons are

-- The game's icon on Y, or nil without the controller UI's bar.
local function findGameIcon()
    local bar = _G.GamepadMainActionBarFrame
    local actionBars = type(bar) == "table" and bar.PageUnit and bar.PageUnit.actionBars
    local button = actionBars and actionBars.topBar and actionBars.topBar.Right
        and actionBars.topBar.Right.ActionButton2
    if type(button) ~= "table" or (button.IsForbidden and button:IsForbidden()) then return nil end
    return button, button.SpecialActionIcon
end

local function atlasExists(atlas)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function showIcon(icon)
    for _, atlas in ipairs(icon.atlases) do
        if atlasExists(atlas) then
            actionIcon:SetAtlas(atlas)
            return
        end
    end
    actionIcon:SetTexture(icon.texture)
end

-- The game's controller buttons cut their icons with the button's own CircleMask
-- (ActionBarButton.xml:18-28), the magnifier too: ours goes under the same one,
-- so whatever goes past the ring is cut as on the game's icons.
local function roundMaskFor(button)
    if button.CircleMask then return button.CircleMask end
    local mask = button:CreateMaskTexture()
    mask:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    mask:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)
    mask:SetTexture(YButtonIcon.ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    return mask
end

-- Y does the chosen action now: no target, no targeting modifier, no window open.
local function yDoesTheAction()
    if UnitExists("target") then return false end
    if GamepadMode and GamepadMode.IsTargetingModifierDown and GamepadMode.IsTargetingModifierDown() then return false end
    return FaceTopButton.HudShown()
end

function YButtonIcon.Refresh()
    if not actionIcon then return end
    local icon = YButtonIcon.ICONS[Modifier.GetSettings().action]
    local showAction = icon ~= nil and yDoesTheAction()
    if showAction then
        showIcon(icon)
        gameIcon:SetAlpha(0)
    else
        gameIcon:SetAlpha(gameIconAlpha)
    end
    actionIcon:SetShown(showAction)
end

function YButtonIcon.Start()
    if actionIcon then return end
    local button, foundIcon = findGameIcon()
    if not (button and foundIcon) then return end
    gameIcon, gameIconAlpha = foundIcon, foundIcon:GetAlpha()

    local layer, sublevel = gameIcon:GetDrawLayer()
    actionIcon = button:CreateTexture(nil, layer, nil, math.min((sublevel or 0) + 1, 7))
    actionIcon:SetAllPoints(gameIcon)
    actionIcon:AddMaskTexture(roundMaskFor(button))
    actionIcon:Hide()

    for _, methodName in ipairs({ "SetAtlas", "SetTexture", "SetColorTexture" }) do
        hooksecurefunc(gameIcon, methodName, YButtonIcon.Refresh)
    end
    local bindingManager = FaceTopButton.GameBindingManager()
    if bindingManager then
        for _, methodName in ipairs(FaceTopButton.GAME_KEY_METHODS) do
            if type(bindingManager[methodName]) == "function" then
                hooksecurefunc(bindingManager, methodName, YButtonIcon.Refresh)
            end
        end
    end
    YButtonIcon.Refresh()
end
