ControllerRebound = ControllerRebound or {}
ControllerRebound.RuleBar = ControllerRebound.RuleBar or {}

local ruleBar = ControllerRebound.RuleBar
local conditional = ControllerRebound.Conditional
local faces = { "A", "B", "X", "Y" }
local maxMacroBodyLength = 255
local routes = {
    A = { key = "PAD1", fallbackIndex = 4, order = 1, layoutPoint = "BOTTOM", layoutX = 0, layoutY = 24 },
    B = { key = "PAD2", fallbackIndex = 3, order = 2, layoutPoint = "RIGHT", layoutX = -8, layoutY = 0 },
    X = { key = "PAD3", fallbackIndex = 1, order = 3, layoutPoint = "LEFT", layoutX = 8, layoutY = 0 },
    Y = { key = "PAD4", fallbackIndex = 2, order = 4, layoutPoint = "TOP", layoutX = 0, layoutY = -24 },
}
ruleBar.state = ruleBar.state or {
    buttons = {},
    gears = {},
    initialized = false,
    waitingForForever = false,
    pending = false,
    macroSyncPending = false,
    rangeCheckSpells = {},
    rangeOutOfRange = {},
    mover = nil,
    modifierRouters = {},
}

local state = ruleBar.state
local bindingOwner
state.modifierRouters = state.modifierRouters or {}
state.rangeCheckSpells = state.rangeCheckSpells or {}
state.rangeOutOfRange = state.rangeOutOfRange or {}

local function inCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function tell(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("[Controller Rebound] " .. message)
    end
end

function ruleBar.describeRoute(face)
    if type(face) == "string" then
        face = face:match("^%s*(.-)%s*$"):upper()
    end
    local route = routes[face]
    if not route then
        return nil
    end
    return {
        face = face,
        key = route.key,
        fallbackIndex = route.fallbackIndex,
        order = route.order,
        layoutPoint = route.layoutPoint,
        layoutX = route.layoutX or 0,
        layoutY = route.layoutY or 0,
    }
end

function ruleBar.planFaceModifierRouter(face, isInCombat)
    if type(face) == "string" then
        face = face:match("^%s*(.-)%s*$"):upper()
    end
    local route = routes[face]
    if not route then
        return nil, "invalid-face"
    end
    if isInCombat then
        return nil, "combat"
    end
    return {
        face = face,
        key = route.key,
        layers = { "bare", "lt", "rt", "ltrt", "lb", "rb", "lbrb" },
        leftTriggerIndex = 15,
        rightTriggerIndex = 16,
    }, nil
end

function ruleBar.selectGamepadLayer(leftTriggerHeld, rightTriggerHeld, leftShoulderHeld, rightShoulderHeld)
    if leftShoulderHeld and rightShoulderHeld then
        return "lbrb"
    end
    if leftShoulderHeld then
        return "lb"
    end
    if rightShoulderHeld then
        return "rb"
    end
    if leftTriggerHeld and rightTriggerHeld then
        return "ltrt"
    end
    if leftTriggerHeld then
        return "lt"
    end
    if rightTriggerHeld then
        return "rt"
    end
    return "bare"
end

function ruleBar.nativeLayerCandidates(layer)
    local namesByLayer = {
        lt = { "leftBar", "LeftBar", "left", "Left" },
        rt = { "rightBar", "RightBar", "right", "Right" },
        ltrt = { "bottomBar", "BottomBar", "bottom", "Bottom" },
        lb = { "friendlyTargetingBar", "FriendlyTargetingBar" },
        rb = { "hostileTargetingBar", "HostileTargetingBar" },
        lbrb = { "shortcutsBar", "ShortcutsBar" },
    }
    local names = namesByLayer[layer]
    if not names then
        return nil
    end
    local copy = {}
    for index, name in ipairs(names) do
        copy[index] = name
    end
    return copy
end

function ruleBar.getOverrideFaces(slots)
    slots = type(slots) == "table" and slots or conditional.getSlots()
    local selected = {}
    for _, face in ipairs(faces) do
        if conditional.isOverrideEnabled(slots[face]) then
            selected[#selected + 1] = face
        end
    end
    return selected
end

function ruleBar.resolveDraggedSpell(cursorType, cursorInfo1, cursorInfo2, cursorInfo3)
    if cursorType ~= "spell" then
        return nil
    end
    local spellID = tonumber(cursorInfo3)
    return spellID and spellID > 0 and math.floor(spellID) or nil
end

function ruleBar.resolveDraggedAction(cursorType, cursorInfo1, cursorInfo2, cursorInfo3, macroInfo)
    local spellID = ruleBar.resolveDraggedSpell(cursorType, cursorInfo1, cursorInfo2, cursorInfo3)
    if spellID then
        return { actionType = "spell", spellID = spellID }
    end
    if cursorType ~= "macro" then
        return nil
    end

    local macroID = tonumber(cursorInfo1)
    macroInfo = macroInfo or GetMacroInfo
    if not macroID or macroID <= 0 or type(macroInfo) ~= "function" then
        return nil
    end
    local name, icon, body = macroInfo(math.floor(macroID))
    if type(body) ~= "string" or not body:match("%S") or #body > maxMacroBodyLength then
        return nil
    end
    return {
        actionType = "macro",
        macroText = body,
        macroName = type(name) == "string" and name or "Macro",
        macroIcon = tonumber(icon),
        macroID = math.floor(macroID),
    }
end

-- Macro text is stored as a secure fallback, but can safely follow its source
-- macro whenever that source still has the same saved name.  A different name
-- at the old index is treated as a replacement, never as an automatic swap.
function ruleBar.resolveLiveMacroSlot(slot, macroInfo, macroIndexByName)
    slot = conditional.normalizeSlot(slot)
    if slot.actionType ~= "macro" or type(slot.macroName) ~= "string" or slot.macroName == "" then
        return nil
    end

    macroInfo = macroInfo or GetMacroInfo
    if type(macroInfo) ~= "function" then
        return nil
    end

    local function resolveAt(index)
        index = tonumber(index)
        if not index or index <= 0 then
            return nil
        end
        index = math.floor(index)
        local name, icon, body = macroInfo(index)
        if name ~= slot.macroName or type(body) ~= "string" or not body:match("%S") or #body > maxMacroBodyLength then
            return nil
        end
        local synced = conditional.normalizeSlot(slot)
        synced.macroID = index
        synced.macroName = name
        synced.macroIcon = tonumber(icon)
        synced.macroText = body
        return synced
    end

    local synced = resolveAt(slot.macroID)
    if synced then
        return synced
    end

    macroIndexByName = macroIndexByName or GetMacroIndexByName
    if type(macroIndexByName) ~= "function" then
        return nil
    end
    return resolveAt(macroIndexByName(slot.macroName))
end

function ruleBar.getGearFrameStrata()
    return "MEDIUM"
end

function ruleBar.getGearFrameLevelOffset()
    return 1
end

function ruleBar.resolveCooldownSpell(slot, macroInfo, macroSpell)
    slot = conditional.normalizeSlot(slot)
    if slot.actionType ~= "macro" then
        return slot.spellID
    end

    macroInfo = macroInfo or GetMacroInfo
    macroSpell = macroSpell or GetMacroSpell
    if not slot.macroID or type(macroInfo) ~= "function" or type(macroSpell) ~= "function" then
        return nil
    end
    local _, _, body = macroInfo(slot.macroID)
    if body ~= slot.macroText then
        return nil
    end
    local macroSpellID = macroSpell(slot.macroID)
    local spellID = macroSpellID and tonumber(macroSpellID)
    return spellID and spellID > 0 and math.floor(spellID) or nil
end

function ruleBar.getCooldownUpdateStrategy()
    return "duration-object"
end

function ruleBar.getUsabilityVisual(isUsable, insufficientPower)
    if isUsable then
        return { red = 1, green = 1, blue = 1, desaturated = false }
    end
    if insufficientPower then
        return { red = 0.5, green = 0.5, blue = 1, desaturated = false }
    end
    return { red = 0.4, green = 0.4, blue = 0.4, desaturated = true }
end

function ruleBar.getActionVisual(isUsable, insufficientPower, isOutOfRange)
    if isOutOfRange then
        return { red = 1, green = 0.1, blue = 0.1, desaturated = false }
    end
    return ruleBar.getUsabilityVisual(isUsable, insufficientPower)
end

function ruleBar.getRangeVisual(inRange)
    return { shown = inRange == false }
end

function ruleBar.getRangeCheckSpell(slot, spellHasRange)
    slot = conditional.normalizeSlot(slot)
    if not conditional.isOverrideEnabled(slot) then
        return nil
    end
    local spellID = ruleBar.resolveCooldownSpell(slot)
    if not spellID then
        return nil
    end
    spellHasRange = spellHasRange or (C_Spell and C_Spell.SpellHasRange)
    return type(spellHasRange) == "function" and spellHasRange(spellID) and spellID or nil
end

function ruleBar.getRangeEventState(inRange, checksRange)
    return checksRange == true and inRange == false
end

function ruleBar.shouldUseNativeActionIcon(slot, nativeActionType, nativeActionID)
    slot = conditional.normalizeSlot(slot)
    return slot.actionType == "spell" and slot.spellID == 6603
        and nativeActionType == "spell" and tonumber(nativeActionID) == 6603
end

local function getBindingOwner()
    if not bindingOwner and type(CreateFrame) == "function" then
        bindingOwner = CreateFrame("Frame")
        bindingOwner:Hide()
    end
    return bindingOwner
end

local validPoints = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true,
    LEFT = true, CENTER = true, RIGHT = true,
    BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function layoutDatabase()
    if type(ControllerReboundDB) ~= "table" then
        ControllerReboundDB = {}
    end
    return ControllerReboundDB
end

local function restoreFramePosition(frame, settingName, defaults)
    local saved = layoutDatabase()[settingName]
    local point = type(saved) == "table" and saved.point or defaults.point
    local relativePoint = type(saved) == "table" and saved.relativePoint or defaults.relativePoint
    local x = type(saved) == "table" and tonumber(saved.x) or defaults.x
    local y = type(saved) == "table" and tonumber(saved.y) or defaults.y
    point = validPoints[point] and point or defaults.point
    relativePoint = validPoints[relativePoint] and relativePoint or defaults.relativePoint
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relativePoint, x, y)
end

local function saveFramePosition(frame, settingName)
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if not validPoints[point] or not validPoints[relativePoint] then
        return
    end
    layoutDatabase()[settingName] = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function makeDraggable(frame, settingName)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if inCombat() then
            tell("Controller Rebound frames can only be moved out of combat.")
            return
        end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveFramePosition(self, settingName)
    end)
end

local function createMover()
    if state.mover or type(CreateFrame) ~= "function" then
        return state.mover
    end
    local mover = CreateFrame("Frame", "ControllerReboundSpellClusterMover", UIParent)
    mover:SetSize(144, 144)
    mover:SetFrameStrata("MEDIUM")
    mover:EnableMouse(true)
    restoreFramePosition(mover, "spellClusterPosition", {
        point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -138, y = 142,
    })
    makeDraggable(mover, "spellClusterPosition")
    mover:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Controller Rebound spell cluster")
            GameTooltip:AddLine("Drag the empty middle space to move it.", 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end
    end)
    mover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    state.mover = mover
    return mover
end

local function spellInfo(spellID)
    if not spellID then
        return nil, nil
    end
    local name, icon
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info, second, third = C_Spell.GetSpellInfo(spellID)
        if type(info) == "table" then
            name = info.name
            icon = info.iconID
        elseif type(info) == "string" then
            name = info
            icon = third
        end
    end
    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        icon = C_Spell.GetSpellTexture(spellID) or icon
    end
    if name or icon then
        return name, icon
    end
    if type(GetSpellInfo) == "function" then
        local legacyName, _, legacyIcon = GetSpellInfo(spellID)
        return legacyName, legacyIcon
    end
    return tostring(spellID), nil
end

local function actionInfo(slot)
    if slot and slot.actionType == "macro" then
        return slot.macroName or "Macro", slot.macroIcon
    end
    return spellInfo(slot and slot.spellID)
end

local function refreshCooldown(face)
    local button = state.buttons[face]
    if not button or not button.cooldown then
        return
    end

    local spellID = ruleBar.resolveCooldownSpell(conditional.getSlot(face))
    if spellID and C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function"
        and type(button.cooldown.SetCooldownFromDurationObject) == "function" then
        button.cooldown:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(spellID))
    elseif type(button.cooldown.Clear) == "function" then
        button.cooldown:Clear()
    end
end

local function actionUsability(slot)
    local spellID = ruleBar.resolveCooldownSpell(slot)
    if not spellID then
        return nil, nil
    end
    if C_Spell and type(C_Spell.IsSpellUsable) == "function" then
        return C_Spell.IsSpellUsable(spellID)
    end
    if type(IsUsableSpell) == "function" then
        return IsUsableSpell(spellID)
    end
    return nil, nil
end

local function refreshUsability(face)
    local button = state.buttons[face]
    if not button or not button.icon then
        return
    end

    local slot = conditional.getSlot(face)
    if not conditional.isOverrideEnabled(slot) then
        button.icon:SetVertexColor(1, 1, 1)
        button.icon:SetDesaturated(true)
        return
    end

    local isUsable, insufficientPower = actionUsability(slot)
    if isUsable == nil then
        button.icon:SetVertexColor(1, 1, 1)
        button.icon:SetDesaturated(false)
        return
    end
    local visual = ruleBar.getActionVisual(isUsable, insufficientPower, state.rangeOutOfRange[face] == true)
    button.icon:SetVertexColor(visual.red, visual.green, visual.blue)
    button.icon:SetDesaturated(visual.desaturated)
end

local function refreshRange(face)
    local button = state.buttons[face]
    if not button or not button.rangeOverlay then
        return
    end
    local slot = conditional.getSlot(face)
    local inRange = state.rangeCheckSpells[face] and not state.rangeOutOfRange[face] or nil
    if not conditional.isOverrideEnabled(slot) then
        inRange = nil
    end
    button.rangeOverlay:Hide()
    refreshUsability(face)
end

local function fallbackButton(face)
    local route = routes[face]
    local main = _G.GamepadMainActionBarFrame
    local pageUnit = main and main.PageUnit
    local bars = pageUnit and pageUnit.actionBars
    local topBar = bars and bars.topBar
    local right = topBar and topBar.Right
    return route and right and right["ActionButton" .. route.fallbackIndex] or nil
end

local function nativeActionForButton(button)
    if not button then
        return nil, nil
    end
    local action = button.action
    if action == nil and type(button.GetAttribute) == "function" then
        action = button:GetAttribute("action")
    end
    if action == nil then
        return nil, nil
    end
    local getActionInfo = C_ActionBar and C_ActionBar.GetActionInfo or GetActionInfo
    if type(getActionInfo) ~= "function" then
        return nil, nil
    end
    return getActionInfo(action)
end

local function textureFromRegion(region)
    if region and type(region.GetTexture) == "function" then
        return region:GetTexture()
    end
    return nil
end

local function nativeButtonIcon(button)
    if not button then
        return nil
    end
    for _, region in ipairs({ button.icon, button.Icon, button.iconTexture, button.IconTexture }) do
        local texture = textureFromRegion(region)
        if texture then
            return texture
        end
    end
    local name = type(button.GetName) == "function" and button:GetName() or nil
    return name and textureFromRegion(_G[name .. "Icon"]) or nil
end

local function nativeIconForSlot(face, slot)
    local fallback = fallbackButton(face)
    local nativeActionType, nativeActionID = nativeActionForButton(fallback)
    if ruleBar.shouldUseNativeActionIcon(slot, nativeActionType, nativeActionID) then
        return nativeButtonIcon(fallback)
    end
    return nil
end

local function buttonFromActionBar(bar, index)
    if not bar or not index then
        return nil
    end
    local name = "ActionButton" .. index
    return (bar.Right and bar.Right[name])
        or (bar.Left and bar.Left[name])
        or bar[name]
end

local function nativeLayerFallbackButton(face, layer)
    if layer == "bare" then
        return fallbackButton(face)
    end
    local route = routes[face]
    local main = _G.GamepadMainActionBarFrame
    local pageUnit = main and main.PageUnit
    local bars = pageUnit and pageUnit.actionBars
    if not route or not bars then
        return nil
    end
    local names = ruleBar.nativeLayerCandidates(layer)
    if not names then
        return nil
    end
    for _, name in ipairs(names) do
        local button = buttonFromActionBar(bars[name], route.fallbackIndex)
        if button then
            return button
        end
    end
    return nil
end

local function fallbackMacro(fallback)
    local name = fallback and fallback:GetName()
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local macro = string.format("/click %s LeftButton 1\n/click %s LeftButton 0", name, name)
    return #macro <= 255 and macro or nil
end

local function gamepadStateIndex(binding)
    local gamepad = C_GamePad
    if not gamepad or type(gamepad.ButtonBindingToIndex) ~= "function" then
        return nil
    end
    local index = tonumber(gamepad.ButtonBindingToIndex(binding))
    return index and index >= 0 and math.floor(index) + 1 or nil
end

-- The persistent face router does not change bindings in combat. Its secure
-- pre-click handler selects a preconfigured action before each face press:
-- Forever's native modifier layers always win; a bare face press follows Controller Rebound's
-- regular spell-or-native rule. Attributes stay unchanged until the release,
-- keeping one physical press on one destination.
local function configureFaceModifierRouter(face, button)
    if not button or inCombat()
        or type(SecureHandlerWrapScript) ~= "function"
        or type(SecureHandlerUnwrapScript) ~= "function" then
        return false
    end

    local plan = ruleBar.planFaceModifierRouter(face, false)
    if not plan then
        return false
    end
    local macros = {}
    for _, layer in ipairs(plan.layers) do
        local macro = fallbackMacro(nativeLayerFallbackButton(face, layer))
        if not macro then
            return false
        end
        macros[layer] = macro
    end
    local leftTriggerIndex = gamepadStateIndex("PADLTRIGGER")
    local rightTriggerIndex = gamepadStateIndex("PADRTRIGGER")
    local leftShoulderIndex = gamepadStateIndex("PADLSHOULDER")
    local rightShoulderIndex = gamepadStateIndex("PADRSHOULDER")
    if not leftTriggerIndex or not rightTriggerIndex or not leftShoulderIndex or not rightShoulderIndex then
        return false
    end
    button:SetAttribute("controllerrebound-router-lt-index", leftTriggerIndex)
    button:SetAttribute("controllerrebound-router-rt-index", rightTriggerIndex)
    button:SetAttribute("controllerrebound-router-lb-index", leftShoulderIndex)
    button:SetAttribute("controllerrebound-router-rb-index", rightShoulderIndex)
    button:SetAttribute("controllerrebound-router-macro-bare", macros.bare)
    button:SetAttribute("controllerrebound-router-macro-lt", macros.lt)
    button:SetAttribute("controllerrebound-router-macro-rt", macros.rt)
    button:SetAttribute("controllerrebound-router-macro-ltrt", macros.ltrt)
    button:SetAttribute("controllerrebound-router-macro-lb", macros.lb)
    button:SetAttribute("controllerrebound-router-macro-rb", macros.rb)
    button:SetAttribute("controllerrebound-router-macro-lbrb", macros.lbrb)

    if state.modifierRouters[face] == button then
        return true
    end
    local body = [[
        if down then
            local gamepadState = GetGamePadState()
            local buttons = gamepadState and gamepadState.buttons
            local leftTriggerHeld = buttons and buttons[self:GetAttribute("controllerrebound-router-lt-index")]
            local rightTriggerHeld = buttons and buttons[self:GetAttribute("controllerrebound-router-rt-index")]
            local leftShoulderHeld = buttons and buttons[self:GetAttribute("controllerrebound-router-lb-index")]
            local rightShoulderHeld = buttons and buttons[self:GetAttribute("controllerrebound-router-rb-index")]
            local layer = "bare"
            if leftShoulderHeld and rightShoulderHeld then
                layer = "lbrb"
            elseif leftShoulderHeld then
                layer = "lb"
            elseif rightShoulderHeld then
                layer = "rb"
            elseif leftTriggerHeld and rightTriggerHeld then
                layer = "ltrt"
            elseif leftTriggerHeld then
                layer = "lt"
            elseif rightTriggerHeld then
                layer = "rt"
            end
            if layer == "bare" then
                if self:GetAttribute("controllerrebound-bare-state") == "override" then
                    local overrideType = self:GetAttribute("controllerrebound-override-type")
                    if overrideType == "spell" then
                        self:SetAttribute("macrotext1", self:GetAttribute("controllerrebound-router-macro-bare"))
                        self:SetAttribute("type1", "spell")
                    else
                        self:SetAttribute("macrotext1", self:GetAttribute("controllerrebound-override-macro"))
                        self:SetAttribute("type1", "macro")
                    end
                else
                    self:SetAttribute("macrotext1", self:GetAttribute("controllerrebound-router-macro-bare"))
                    self:SetAttribute("type1", "macro")
                end
            else
                self:SetAttribute("macrotext1", self:GetAttribute("controllerrebound-router-macro-" .. layer))
                self:SetAttribute("type1", "macro")
            end
        end
    ]]
    local ok = pcall(SecureHandlerWrapScript, button, "OnClick", button, body)
    if not ok then
        return false
    end
    state.modifierRouters[face] = button
    return true
end

local function refreshAppearance(face)
    local button = state.buttons[face]
    if not button then
        return
    end
    local slot = conditional.getSlot(face)
    local actionName, icon = actionInfo(slot)
    button.icon:SetTexture(nativeIconForSlot(face, slot) or icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    button.faceText:SetText(face)
    button.actionName = actionName
    refreshUsability(face)
    refreshCooldown(face)
    refreshRange(face)
end

local function configureSecureButton(face)
    local button = state.buttons[face]
    local fallback = fallbackButton(face)
    if not button or not fallback or inCombat() then
        state.pending = true
        return false
    end

    local slot = conditional.getSlot(face)
    local macro = fallbackMacro(fallback)
    if not macro then
        state.pending = true
        return false
    end
    local stateDriver = conditional.buildStateDriver(slot)
    if not stateDriver then
        state.pending = true
        return false
    end
    if type(UnregisterAttributeDriver) == "function" then
        UnregisterAttributeDriver(button, "type1")
        UnregisterAttributeDriver(button, "controllerrebound-bare-state")
    end
    button:SetAttribute("controllerrebound-action-type", slot.actionType)
    button:SetAttribute("controllerrebound-fallback", fallback)
    button:SetAttribute("type1", "macro")
    button:SetAttribute("clickbutton1", nil)
    button:SetAttribute("macrotext1", macro)
    button:SetAttribute("spell1", slot.spellID)
    button:SetAttribute("controllerrebound-override-type", slot.actionType)
    button:SetAttribute("controllerrebound-override-macro", slot.macroText)
    if type(RegisterAttributeDriver) ~= "function" then
        return false
    end
    button:SetAttribute("controllerrebound-bare-state", "native")
    if not configureFaceModifierRouter(face, button) then
        state.pending = true
        return false
    end
    RegisterAttributeDriver(button, "controllerrebound-bare-state", stateDriver)
    state.pending = false
    return true
end

local function applyBindings()
    if inCombat() then
        state.pending = true
        return false
    end
    local owner = getBindingOwner()
    if not owner or type(SetOverrideBindingClick) ~= "function" or type(ClearOverrideBindings) ~= "function" then
        return false
    end

    ClearOverrideBindings(owner)
    for _, face in ipairs(ruleBar.getOverrideFaces()) do
        local button = state.buttons[face]
        local route = routes[face]
        if not button or not button:GetName() then
            return false
        end
        SetOverrideBindingClick(owner, true, route.key, button:GetName(), "LeftButton")
    end
    return true
end

function ruleBar.shouldInitializeForEvent(event, loginReady)
    return loginReady and (event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD")
end

local function refreshSettings()
    local panel = state.settings
    if not panel or not panel.face then
        return
    end
    local slot = conditional.getSlot(panel.face)
    panel.title:SetText(panel.face .. " Action Conditions")
    panel.enabled:SetChecked(slot.enabled)
    for _, checkbox in ipairs(panel.checkboxes) do
        checkbox:SetChecked(slot[checkbox.kind] == checkbox.value)
    end
end

local function refuseCombatEdit()
    if inCombat() then
        tell("Rule changes wait until you leave combat.")
        return true
    end
    return false
end

local function showSettings(face)
    if not state.settings then
        return
    end
    state.settings.face = face
    refreshSettings()
    state.settings:Show()
end

local function createSettings()
    if state.settings or type(CreateFrame) ~= "function" then
        return
    end
    local panel = CreateFrame("Frame", "ControllerReboundRuleSettings", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(346, 414)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    restoreFramePosition(panel, "settingsPosition", {
        point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT", x = -128, y = 218,
    })
    makeDraggable(panel, "settingsPosition")
    panel:Hide()
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.title:SetPoint("TOP", 0, -22)
    panel.title:SetText("Controller Rebound settings")
    panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.subtitle:SetPoint("TOP", 0, -47)
    panel.subtitle:SetText("The spell is used only when every checked condition is true.")
    panel.checkboxes = {}

    local function makeCheckbox(name, label, x, y)
        local checkbox = CreateFrame("CheckButton", "ControllerReboundRuleSettings" .. name, panel, "UICheckButtonTemplate")
        checkbox:SetSize(24, 24)
        checkbox:SetPoint("TOPLEFT", x, y)
        checkbox.label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 1, 0)
        checkbox.label:SetText(label)
        checkbox:SetHitRectInsets(0, -122, 0, 0)
        return checkbox
    end

    local function addHeading(label, x, y)
        local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heading:SetPoint("TOPLEFT", x, y)
        heading:SetText(label)
    end

    panel.enabled = makeCheckbox("Enabled", "Enable this action", 22, -72)
    panel.enabled:SetScript("OnClick", function(self)
        if refuseCombatEdit() then
            refreshSettings()
            return
        end
        conditional.updateSlot(panel.face, { enabled = self:GetChecked() and true or false })
        refreshSettings()
    end)

    local function addCondition(name, label, kind, value, x, y)
        local checkbox = makeCheckbox(name, label, x, y)
        checkbox.kind = kind
        checkbox.value = value
        checkbox:SetScript("OnClick", function(self)
            if refuseCombatEdit() then
                refreshSettings()
                return
            end
            local slot = conditional.getSlot(panel.face)
            local planned = conditional.planCheckboxChoice(slot, self.kind, self.value, self:GetChecked())
            if planned then
                conditional.updateSlot(panel.face, { [self.kind] = planned[self.kind] })
            end
            refreshSettings()
        end)
        panel.checkboxes[#panel.checkboxes + 1] = checkbox
    end

    addHeading("Target", 24, -108)
    addCondition("Enemy", "Enemy target", "target", "ENEMY", 22, -128)
    addCondition("Friendly", "Friendly target", "target", "FRIENDLY", 178, -128)
    addCondition("TargetExists", "Target exists", "target", "TARGET", 22, -154)
    addCondition("NoTarget", "No target", "target", "NONE", 178, -154)

    addHeading("Target life", 24, -190)
    addCondition("Living", "Living target", "life", "ALIVE", 22, -210)
    addCondition("Dead", "Dead target", "life", "DEAD", 178, -210)

    addHeading("Combat", 24, -246)
    addCondition("InCombat", "In combat", "combat", "IN", 22, -266)
    addCondition("OutCombat", "Out of combat", "combat", "OUT", 178, -266)

    addHeading("Group", 24, -302)
    addCondition("Solo", "Solo", "group", "SOLO", 22, -322)
    addCondition("Party", "In party", "group", "PARTY", 178, -322)
    addCondition("Raid", "In raid", "group", "RAID", 22, -348)

    panel.clear = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.clear:SetSize(100, 22)
    panel.clear:SetPoint("BOTTOMRIGHT", -122, 18)
    panel.clear:SetText("Clear action")
    panel.clear:SetScript("OnClick", function()
        if refuseCombatEdit() then return end
        conditional.clearAction(panel.face)
        refreshSettings()
    end)
    panel.close = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.close:SetSize(90, 22)
    panel.close:SetPoint("BOTTOMRIGHT", -22, 18)
    panel.close:SetScript("OnClick", function() panel:Hide() end)
    panel.close:SetText("Close")
    state.settings = panel
end

local function createSlot(face)
    if state.buttons[face] or type(CreateFrame) ~= "function" then
        return state.buttons[face]
    end
    local route = routes[face]
    local buttonName = "ControllerReboundSpellSlot" .. face
    local button = CreateFrame("Button", buttonName, state.mover or UIParent, "SecureActionButtonTemplate,SecureHandlerBaseTemplate")
    button:SetSize(40, 40)
    button:SetPoint(route.layoutPoint, state.mover or UIParent, route.layoutPoint, route.layoutX or 0, route.layoutY or 0)
    button:RegisterForClicks("AnyDown", "AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetFrameStrata("MEDIUM")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2)
    button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.rangeOverlay = button:CreateTexture(nil, "OVERLAY", nil, -1)
    button.rangeOverlay:SetAllPoints(button.icon)
    button.rangeOverlay:SetColorTexture(1, 0.1, 0.1, 0.28)
    button.rangeOverlay:Hide()
    button.border = button:CreateTexture(nil, "BORDER")
    button.border:SetPoint("TOPLEFT", 0, 0)
    button.border:SetPoint("BOTTOMRIGHT", 0, 0)
    button.border:Hide()
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button.icon)
    button.cooldown:SetFrameLevel(button:GetFrameLevel())
    button.cooldown:EnableMouse(false)
    if type(button.cooldown.SetDrawEdge) == "function" then
        button.cooldown:SetDrawEdge(false)
    end
    if type(button.cooldown.SetHideCountdownNumbers) == "function" then
        button.cooldown:SetHideCountdownNumbers(false)
    end
    button.faceText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.faceText:SetPoint("TOPLEFT", 3, -3)

    button:SetScript("OnReceiveDrag", function(self)
        if refuseCombatEdit() then return end
        local cursorType, cursorInfo1, cursorInfo2, cursorInfo3 = GetCursorInfo()
        local action = ruleBar.resolveDraggedAction(cursorType, cursorInfo1, cursorInfo2, cursorInfo3)
        if not action then
            tell("Drag a spell or macro onto this slot.")
            return
        end
        conditional.updateSlot(face, action)
        if action.actionType == "macro" then
            tell(face .. " slot loaded macro " .. tostring(action.macroName) .. ".")
        else
            local spellName = spellInfo(action.spellID)
            tell(face .. " slot loaded " .. tostring(spellName or action.spellID) .. " (spell " .. tostring(action.spellID) .. ").")
        end
        ClearCursor()
    end)
    button:SetScript("OnDragStart", function()
        if refuseCombatEdit() then return end
        local slot = conditional.getSlot(face)
        if slot.actionType == "spell" and slot.spellID and type(PickupSpell) == "function" then
            PickupSpell(slot.spellID)
        elseif slot.actionType == "macro" and slot.macroID and type(GetMacroInfo) == "function"
            and type(PickupMacro) == "function" and select(3, GetMacroInfo(slot.macroID)) == slot.macroText then
            PickupMacro(slot.macroID)
        end
    end)
    button:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(face .. " conditional action slot")
            local slot = conditional.getSlot(face)
            if self.actionName then GameTooltip:AddLine(self.actionName, 1, 1, 1) end
            GameTooltip:AddLine(conditional.isOverrideEnabled(slot) and "Rule active when its conditions match." or "Native Forever action: no active rule.", 0.8, 0.8, 0.8, true)
            GameTooltip:AddLine("Drag a spell or macro here; use the gear to choose conditions.", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    state.buttons[face] = button

    local gear = CreateFrame("Button", buttonName .. "Gear", state.mover or UIParent)
    gear:SetSize(13, 13)
    gear:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    gear:SetFrameStrata(ruleBar.getGearFrameStrata())
    gear:SetFrameLevel(button:GetFrameLevel() + ruleBar.getGearFrameLevelOffset())
    gear.icon = gear:CreateTexture(nil, "ARTWORK")
    gear.icon:SetAllPoints()
    gear.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetScript("OnClick", function() showSettings(face) end)
    gear:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(face .. " rule settings")
            GameTooltip:Show()
        end
    end)
    gear:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    state.gears[face] = gear
    return button
end

local function positionSlot(face)
    local button = state.buttons[face]
    local route = routes[face]
    local mover = state.mover
    if not button or not route or not mover or inCombat() then
        return
    end
    button:ClearAllPoints()
    button:SetPoint(route.layoutPoint, mover, route.layoutPoint, route.layoutX or 0, route.layoutY or 0)
end

function ruleBar.initialize()
    if inCombat() then
        state.pending = true
        return false
    end
    if type(RegisterAttributeDriver) ~= "function" or type(SetOverrideBindingClick) ~= "function" then
        return false
    end
    createMover()
    for _, face in ipairs(faces) do
        createSlot(face)
        positionSlot(face)
        if not fallbackButton(face) then
            state.waitingForForever = true
            return false
        end
    end
    createSettings()
    for _, face in ipairs(faces) do
        refreshAppearance(face)
        if not configureSecureButton(face) then
            return false
        end
    end
    ruleBar.refreshRangeChecks()
    if not applyBindings() then
        return false
    end
    state.initialized = true
    state.waitingForForever = false
    state.pending = false
    tell("Conditional face slots ready. Bare A/B/X/Y use Controller Rebound rules; native trigger and shoulder layers stay native.")
    return true
end

function ruleBar.refresh(face)
    if face then
        refreshAppearance(face)
        configureSecureButton(face)
    else
        for _, currentFace in ipairs(faces) do
            refreshAppearance(currentFace)
            configureSecureButton(currentFace)
        end
    end
    ruleBar.refreshRangeChecks()
    applyBindings()
end

function ruleBar.refreshCooldowns()
    for _, face in ipairs(faces) do
        refreshCooldown(face)
    end
end

function ruleBar.refreshUsability()
    for _, face in ipairs(faces) do
        refreshUsability(face)
    end
end

function ruleBar.refreshRanges()
    for _, face in ipairs(faces) do
        refreshRange(face)
    end
end

function ruleBar.refreshRangeChecks()
    local spellHasRange = C_Spell and C_Spell.SpellHasRange
    local enableRangeCheck = C_Spell and C_Spell.EnableSpellRangeCheck
    if type(spellHasRange) ~= "function" or type(enableRangeCheck) ~= "function" then
        state.rangeCheckSpells = {}
        state.rangeOutOfRange = {}
        ruleBar.refreshRanges()
        return false
    end

    local previousCounts, nextCounts, nextSpells = {}, {}, {}
    for _, face in ipairs(faces) do
        local previous = state.rangeCheckSpells[face]
        if previous then
            previousCounts[previous] = (previousCounts[previous] or 0) + 1
        end
        local spellID = ruleBar.getRangeCheckSpell(conditional.getSlot(face), spellHasRange)
        nextSpells[face] = spellID
        if spellID then
            nextCounts[spellID] = (nextCounts[spellID] or 0) + 1
        end
    end

    for spellID in pairs(previousCounts) do
        if not nextCounts[spellID] then
            enableRangeCheck(spellID, false)
        end
    end
    for spellID in pairs(nextCounts) do
        if not previousCounts[spellID] then
            enableRangeCheck(spellID, true)
        end
    end

    state.rangeCheckSpells = nextSpells
    state.rangeOutOfRange = {}
    local isSpellInRange = C_Spell and C_Spell.IsSpellInRange
    if type(isSpellInRange) == "function" then
        for face, spellID in pairs(nextSpells) do
            if spellID then
                state.rangeOutOfRange[face] = ruleBar.getRangeEventState(isSpellInRange(spellID), true)
            end
        end
    end
    ruleBar.refreshRanges()
    return true
end

function ruleBar.refreshVisuals()
    for _, face in ipairs(faces) do
        refreshAppearance(face)
    end
end

function ruleBar.syncMacros()
    if inCombat() then
        state.macroSyncPending = true
        return false
    end

    state.macroSyncPending = false
    for _, face in ipairs(faces) do
        local slot = conditional.getSlot(face)
        local synced = ruleBar.resolveLiveMacroSlot(slot)
        if synced and (synced.macroID ~= slot.macroID
            or synced.macroText ~= slot.macroText
            or synced.macroName ~= slot.macroName
            or synced.macroIcon ~= slot.macroIcon) then
            conditional.updateSlot(face, synced)
        end
    end
    return true
end

conditional.onChanged(function(face)
    if state.initialized then
        ruleBar.refresh(face)
    end
end)

local lifecycle = type(CreateFrame) == "function" and CreateFrame("Frame") or nil
if lifecycle then
    local retryElapsed = 0
    local rangeElapsed = 0
    local loginReady = false
    lifecycle:RegisterEvent("PLAYER_LOGIN")
    lifecycle:RegisterEvent("PLAYER_ENTERING_WORLD")
    lifecycle:RegisterEvent("PLAYER_REGEN_ENABLED")
    lifecycle:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    lifecycle:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    lifecycle:RegisterEvent("SPELL_UPDATE_USABLE")
    lifecycle:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
    lifecycle:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    lifecycle:RegisterEvent("SPELLS_CHANGED")
    lifecycle:RegisterEvent("PLAYER_TARGET_CHANGED")
    lifecycle:RegisterEvent("SPELL_RANGE_CHECK_UPDATE")
    lifecycle:RegisterEvent("UNIT_POWER_UPDATE")
    lifecycle:RegisterEvent("UPDATE_MACROS")
    lifecycle:RegisterEvent("ADDON_LOADED")
    lifecycle:SetScript("OnEvent", function(_, event, first, second, third)
        if event == "ADDON_LOADED" then
            return
        end
        if event == "PLAYER_LOGIN" then
            loginReady = true
        end
        if event == "PLAYER_REGEN_ENABLED" then
            local macroSyncWasPending = state.macroSyncPending
            if macroSyncWasPending then
                ruleBar.syncMacros()
            end
            if state.pending then
                ruleBar.refresh()
                ruleBar.initialize()
                return
            end
            if macroSyncWasPending then
                return
            end
        end
        if event == "UPDATE_MACROS" then
            ruleBar.syncMacros()
            ruleBar.refreshCooldowns()
            ruleBar.refreshRanges()
            return
        end
        if event == "SPELL_UPDATE_COOLDOWN" or event == "ACTIONBAR_UPDATE_COOLDOWN" then
            ruleBar.refreshCooldowns()
            return
        end
        if event == "PLAYER_TARGET_CHANGED" then
            ruleBar.refreshRanges()
            return
        end
        if event == "SPELL_RANGE_CHECK_UPDATE" then
            local spellID = tonumber(first)
            for _, face in ipairs(faces) do
                if state.rangeCheckSpells[face] == spellID then
                    state.rangeOutOfRange[face] = ruleBar.getRangeEventState(second, third)
                    refreshRange(face)
                end
            end
            return
        end
        if event == "SPELLS_CHANGED" or event == "ACTIONBAR_SLOT_CHANGED"
            or (event == "PLAYER_ENTERING_WORLD" and state.initialized) then
            ruleBar.refreshVisuals()
            ruleBar.refreshRangeChecks()
            return
        end
        if event == "SPELL_UPDATE_USABLE" or event == "ACTIONBAR_UPDATE_USABLE" then
            ruleBar.refreshUsability()
            return
        end
        if event == "UNIT_POWER_UPDATE" and first == "player" then
            ruleBar.refreshUsability()
            return
        end
        if not state.initialized and ruleBar.shouldInitializeForEvent(event, loginReady) then
            ruleBar.initialize()
        end
    end)
    lifecycle:SetScript("OnUpdate", function(_, elapsed)
        if not loginReady then
            return
        end
        if state.initialized then
            rangeElapsed = rangeElapsed + elapsed
            if rangeElapsed >= 0.2 then
                rangeElapsed = 0
                ruleBar.refreshRanges()
            end
            return
        end
        if not state.waitingForForever or inCombat() then
            return
        end
        retryElapsed = retryElapsed + elapsed
        if retryElapsed < 0.5 then
            return
        end
        retryElapsed = 0
        ruleBar.initialize()
    end)
end
