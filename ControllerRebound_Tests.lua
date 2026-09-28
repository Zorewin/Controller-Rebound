ControllerReboundTests = ControllerReboundTests or { cases = {} }

local tests = ControllerReboundTests

local function printResult(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("[Controller Rebound] " .. text)
    end
end

function tests.add(name, body)
    tests.cases[#tests.cases + 1] = { name = name, body = body }
end

function tests.assertEqual(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

function tests.run()
    local passed, failed = 0, 0
    for _, case in ipairs(tests.cases) do
        local ok, reason = pcall(case.body)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            printResult("FAIL " .. case.name .. ": " .. tostring(reason))
        end
    end
    printResult("Tests: " .. tostring(passed) .. " passed, " .. tostring(failed) .. " failed.")
end

tests.add("exposes the Controller Rebound public namespace", function()
    if type(ControllerRebound) ~= "table" or type(ControllerRebound.RuleBar) ~= "table" then
        error("ControllerRebound.RuleBar is unavailable")
    end
end)

tests.add("routes each face through its native controller token", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.describeRoute) ~= "function" then
        error("ControllerRebound.RuleBar.describeRoute is unavailable")
    end

    tests.assertEqual(ruleBar.describeRoute("A").key, "PAD1", "A token")
    tests.assertEqual(ruleBar.describeRoute("B").key, "PAD2", "B token")
    tests.assertEqual(ruleBar.describeRoute("X").key, "PAD3", "X token")
    tests.assertEqual(ruleBar.describeRoute("Y").key, "PAD4", "Y token")
end)

tests.add("gives every native modifier layer priority over a bare ControllerRebound rule", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.selectGamepadLayer) ~= "function" then
        error("ControllerRebound.RuleBar.selectGamepadLayer is unavailable")
    end

    tests.assertEqual(ruleBar.selectGamepadLayer(false, false), "bare", "bare face")
    tests.assertEqual(ruleBar.selectGamepadLayer(true, false), "lt", "LT priority")
    tests.assertEqual(ruleBar.selectGamepadLayer(false, true), "rt", "RT priority")
    tests.assertEqual(ruleBar.selectGamepadLayer(true, true), "ltrt", "LT+RT priority")
    tests.assertEqual(ruleBar.selectGamepadLayer(false, false, true, false), "lb", "LB priority")
    tests.assertEqual(ruleBar.selectGamepadLayer(false, false, false, true), "rb", "RB priority")
    tests.assertEqual(ruleBar.selectGamepadLayer(false, false, true, true), "lbrb", "LB+RB priority")
    tests.assertEqual(ruleBar.selectGamepadLayer(true, true, true, false), "lb", "LB contextual priority")
    tests.assertEqual(ruleBar.selectGamepadLayer(true, true, false, true), "rb", "RB contextual priority")
end)

tests.add("plans persistent modifier routing for all four faces", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.planFaceModifierRouter) ~= "function" then
        error("ControllerRebound.RuleBar.planFaceModifierRouter is unavailable")
    end

    for _, face in ipairs({ "A", "B", "X", "Y" }) do
        local plan, reason = ruleBar.planFaceModifierRouter(face, false)
        tests.assertEqual(reason, nil, face .. " plan reason")
        tests.assertEqual(plan.face, face, face .. " plan face")
        tests.assertEqual(plan.layers[4], "ltrt", face .. " trigger combined layer")
        tests.assertEqual(plan.layers[5], "lb", face .. " left shoulder layer")
        tests.assertEqual(plan.layers[6], "rb", face .. " right shoulder layer")
        tests.assertEqual(plan.layers[7], "lbrb", face .. " shoulder combined layer")
    end
    local plan, reason = ruleBar.planFaceModifierRouter("X", true)
    tests.assertEqual(plan, nil, "combat plan")
    tests.assertEqual(reason, "combat", "combat reason")
end)

tests.add("plans native targeting and shortcut bars for shoulder contexts", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.nativeLayerCandidates) ~= "function" then
        error("ControllerRebound.RuleBar.nativeLayerCandidates is unavailable")
    end

    tests.assertEqual(ruleBar.nativeLayerCandidates("lb")[1], "friendlyTargetingBar", "LB bar")
    tests.assertEqual(ruleBar.nativeLayerCandidates("rb")[1], "hostileTargetingBar", "RB bar")
    tests.assertEqual(ruleBar.nativeLayerCandidates("lbrb")[1], "shortcutsBar", "LB+RB bar")
end)

tests.add("binds only spell slots with a real selected condition", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.getOverrideFaces) ~= "function" then
        error("ControllerRebound.RuleBar.getOverrideFaces is unavailable")
    end

    local selected = ruleBar.getOverrideFaces({
        A = { enabled = true, spellID = 1, target = "ANY", life = "ANY", combat = "ANY", group = "ANY" },
        B = { enabled = true, spellID = 2, target = "ENEMY", life = "ANY", combat = "ANY", group = "ANY" },
        X = { enabled = false, spellID = 3, target = "ENEMY", life = "ANY", combat = "ANY", group = "ANY" },
        Y = { enabled = true, spellID = nil, target = "ENEMY", life = "ANY", combat = "ANY", group = "ANY" },
    })
    tests.assertEqual(#selected, 1, "selected face count")
    tests.assertEqual(selected[1], "B", "selected face")
end)

tests.add("compiles a bare spell rule to a secure spell-or-native driver", function()
    local conditional = ControllerRebound.Conditional
    if type(conditional) ~= "table" or type(conditional.buildTypeDriver) ~= "function" then
        error("ControllerRebound.Conditional.buildTypeDriver is unavailable")
    end

    tests.assertEqual(conditional.buildTypeDriver({
        enabled = true, spellID = 5176, target = "ENEMY", life = "ALIVE", combat = "IN", group = "ANY",
    }), "[combat,harm,nodead] spell; macro", "Wrath driver")
    tests.assertEqual(conditional.buildTypeDriver({
        enabled = true, spellID = 5176, target = "ANY", life = "ANY", combat = "ANY", group = "ANY",
    }), "macro", "native fallback driver")
end)

tests.add("preserves saved face spells while normalizing old slot data", function()
    local conditional = ControllerRebound.Conditional
    if type(conditional) ~= "table" or type(conditional.preparePersistentSlots) ~= "function" then
        error("ControllerRebound.Conditional.preparePersistentSlots is unavailable")
    end

    local store = {}
    local slots = conditional.preparePersistentSlots(store, {
        X = { spellID = 5176, enabled = true, target = "ENEMY", life = "ALIVE", combat = "IN", group = "ANY" },
    })
    tests.assertEqual(store.version, 1, "slot store version")
    tests.assertEqual(slots.X.spellID, 5176, "saved Wrath")
    tests.assertEqual(slots.X.target, "ENEMY", "saved condition")
end)

tests.add("uses Forever's fourth cursor value as a dropped spell ID", function()
    local ruleBar = ControllerRebound.RuleBar
    tests.assertEqual(ruleBar.resolveDraggedSpell("spell", 0, "player", 5176), 5176, "Wrath cursor")
    tests.assertEqual(ruleBar.resolveDraggedSpell("macro", 0, "player", 5176), nil, "non-spell cursor")
end)

tests.add("preserves a conditional macro's secure body and display data", function()
    local conditional = ControllerRebound.Conditional
    local slot = conditional.normalizeSlot({
        actionType = "macro",
        macroText = "/cast [@player] Rejuvenation",
        macroName = "Self heal",
        macroIcon = 136081,
        enabled = true,
        target = "FRIENDLY",
    }, "X")
    tests.assertEqual(slot.actionType, "macro", "macro action type")
    tests.assertEqual(slot.macroText, "/cast [@player] Rejuvenation", "macro body")
    tests.assertEqual(slot.macroName, "Self heal", "macro name")
    tests.assertEqual(slot.macroIcon, 136081, "macro icon")
    tests.assertEqual(conditional.isOverrideEnabled(slot), true, "macro rule is active")
end)

tests.add("resolves a dropped macro to a persistent action", function()
    local ruleBar = ControllerRebound.RuleBar
    local action = ruleBar.resolveDraggedAction("macro", 121, nil, nil, function(index)
        tests.assertEqual(index, 121, "macro cursor index")
        return "Self heal", 136081, "/cast [@player] Rejuvenation"
    end)
    tests.assertEqual(action.actionType, "macro", "resolved macro type")
    tests.assertEqual(action.macroText, "/cast [@player] Rejuvenation", "resolved macro body")
    tests.assertEqual(action.macroName, "Self heal", "resolved macro name")
    tests.assertEqual(action.macroIcon, 136081, "resolved macro icon")
end)

tests.add("resyncs an edited macro without losing its conditional rule", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.resolveLiveMacroSlot) ~= "function" then
        error("ControllerRebound.RuleBar.resolveLiveMacroSlot is unavailable")
    end

    local synced = ruleBar.resolveLiveMacroSlot({
        actionType = "macro",
        macroID = 121,
        macroName = "Druid rotation",
        macroIcon = 136081,
        macroText = "/cast Wrath",
        enabled = true,
        target = "ENEMY",
        combat = "IN",
    }, function(index)
        tests.assertEqual(index, 121, "live macro index")
        return "Druid rotation", 136096, "/cast Moonfire"
    end)

    tests.assertEqual(synced.macroID, 121, "synced macro index")
    tests.assertEqual(synced.macroText, "/cast Moonfire", "updated macro body")
    tests.assertEqual(synced.macroIcon, 136096, "updated macro icon")
    tests.assertEqual(synced.target, "ENEMY", "preserved target condition")
    tests.assertEqual(synced.combat, "IN", "preserved combat condition")
end)

tests.add("relinks a moved macro by its saved name", function()
    local ruleBar = ControllerRebound.RuleBar
    local synced = ruleBar.resolveLiveMacroSlot({
        actionType = "macro",
        macroID = 121,
        macroName = "Druid rotation",
        macroText = "/cast Wrath",
        target = "ENEMY",
    }, function(index)
        if index == 121 then
            return "Another macro", 136081, "/cast Rejuvenation"
        end
        if index == 222 then
            return "Druid rotation", 136096, "/cast Moonfire"
        end
    end, function(name)
        tests.assertEqual(name, "Druid rotation", "saved macro name")
        return 222
    end)

    tests.assertEqual(synced.macroID, 222, "moved macro index")
    tests.assertEqual(synced.macroText, "/cast Moonfire", "moved macro body")
    tests.assertEqual(synced.target, "ENEMY", "moved macro keeps rule")
end)

tests.add("keeps rule gears below normal dialog windows", function()
    local ruleBar = ControllerRebound.RuleBar
    tests.assertEqual(ruleBar.getGearFrameStrata(), "MEDIUM", "gear frame strata")
end)

tests.add("keeps each rule gear above its own action icon", function()
    local ruleBar = ControllerRebound.RuleBar
    tests.assertEqual(ruleBar.getGearFrameLevelOffset(), 1, "gear frame level offset")
end)

tests.add("resolves cooldowns from spells and verified macros", function()
    local ruleBar = ControllerRebound.RuleBar
    tests.assertEqual(ruleBar.resolveCooldownSpell({ actionType = "spell", spellID = 5176 }), 5176, "spell cooldown")
    tests.assertEqual(ruleBar.resolveCooldownSpell({
        actionType = "macro",
        macroID = 121,
        macroText = "/cast Rejuvenation",
    }, function(index)
        tests.assertEqual(index, 121, "macro cooldown index")
        return "Heal", 136081, "/cast Rejuvenation"
    end, function(index)
        tests.assertEqual(index, 121, "macro spell index")
        return 774
    end), 774, "macro cooldown")
    tests.assertEqual(ruleBar.resolveCooldownSpell({
        actionType = "macro",
        macroID = 121,
        macroText = "/cast Rejuvenation",
    }, function()
        return "Different macro", 136081, "/cast Healing Touch"
    end, function()
        return 5185
    end), nil, "stale macro cooldown")
end)

tests.add("treats a macro with no cast spell as cooldown-less", function()
    local ruleBar = ControllerRebound.RuleBar
    local ok, spellID = pcall(function()
        return ruleBar.resolveCooldownSpell({
            actionType = "macro",
            macroID = 1,
            macroText = "#showtooltip test",
        }, function(index)
            tests.assertEqual(index, 1, "no-spell macro index")
            return "TEST", 132120, "#showtooltip test"
        end, function()
            -- Forever's GetMacroSpell returns no value at all for this shape.
        end)
    end)
    tests.assertEqual(ok, true, "no-spell macro does not error")
    tests.assertEqual(spellID, nil, "no-spell macro cooldown")
end)

tests.add("uses duration objects for combat-safe cooldown display", function()
    local ruleBar = ControllerRebound.RuleBar
    tests.assertEqual(ruleBar.getCooldownUpdateStrategy(), "duration-object", "cooldown update strategy")
end)

tests.add("migrates legacy slots only to the first character profile", function()
    local conditional = ControllerRebound.Conditional
    local account = {
        slots = {
            X = { spellID = 5176, enabled = true, target = "ENEMY" },
        },
    }
    local firstCharacter = {}
    local firstSlots = conditional.prepareCharacterSlots(firstCharacter, account)
    tests.assertEqual(firstSlots.X.spellID, 5176, "first character keeps legacy Wrath")
    tests.assertEqual(account.perCharacterMigrationClaimed, true, "migration claimed")

    local secondCharacter = {}
    local secondSlots = conditional.prepareCharacterSlots(secondCharacter, account)
    tests.assertEqual(secondSlots.X.spellID, nil, "second character starts empty")
end)

tests.add("uses Blizzard action-bar colors for usable and unavailable actions", function()
    local ruleBar = ControllerRebound.RuleBar
    local usable = ruleBar.getUsabilityVisual(true, false)
    tests.assertEqual(usable.desaturated, false, "usable saturation")
    tests.assertEqual(usable.red, 1, "usable red")
    tests.assertEqual(usable.green, 1, "usable green")
    tests.assertEqual(usable.blue, 1, "usable blue")

    local insufficientPower = ruleBar.getUsabilityVisual(false, true)
    tests.assertEqual(insufficientPower.desaturated, false, "power saturation")
    tests.assertEqual(insufficientPower.red, 0.5, "power red")
    tests.assertEqual(insufficientPower.green, 0.5, "power green")
    tests.assertEqual(insufficientPower.blue, 1, "power blue")

    local unavailable = ruleBar.getUsabilityVisual(false, false)
    tests.assertEqual(unavailable.desaturated, true, "unavailable saturation")
    tests.assertEqual(unavailable.red, 0.4, "unavailable red")
    tests.assertEqual(unavailable.green, 0.4, "unavailable green")
    tests.assertEqual(unavailable.blue, 0.4, "unavailable blue")
end)

tests.add("prioritizes Blizzard's red out-of-range color over other action states", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.getActionVisual) ~= "function" then
        error("ControllerRebound.RuleBar.getActionVisual is unavailable")
    end

    local outOfRange = ruleBar.getActionVisual(false, true, true)
    tests.assertEqual(outOfRange.desaturated, false, "out-of-range saturation")
    tests.assertEqual(outOfRange.red, 1, "out-of-range red")
    tests.assertEqual(outOfRange.green, 0.1, "out-of-range green")
    tests.assertEqual(outOfRange.blue, 0.1, "out-of-range blue")
end)

tests.add("shows an independent warning only when an action is out of range", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.getRangeVisual) ~= "function" then
        error("ControllerRebound.RuleBar.getRangeVisual is unavailable")
    end

    tests.assertEqual(ruleBar.getRangeVisual(false).shown, true, "out of range is shown")
    tests.assertEqual(ruleBar.getRangeVisual(true).shown, false, "in range is hidden")
    tests.assertEqual(ruleBar.getRangeVisual(nil).shown, false, "unknown range is hidden")
end)

tests.add("enables event-based range checks only for ranged conditional actions", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.getRangeCheckSpell) ~= "function" then
        error("ControllerRebound.RuleBar.getRangeCheckSpell is unavailable")
    end

    local ranged = ruleBar.getRangeCheckSpell({
        actionType = "spell",
        spellID = 5176,
        enabled = true,
        target = "ENEMY",
    }, function(spellID)
        tests.assertEqual(spellID, 5176, "range spell ID")
        return true
    end)
    tests.assertEqual(ranged, 5176, "ranged spell is subscribed")
    tests.assertEqual(ruleBar.getRangeCheckSpell({
        actionType = "spell",
        spellID = 6603,
        enabled = true,
        target = "ENEMY",
    }, function()
        return false
    end), nil, "melee spell is not subscribed")
end)

tests.add("turns Blizzard range events into an out-of-range state", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.getRangeEventState) ~= "function" then
        error("ControllerRebound.RuleBar.getRangeEventState is unavailable")
    end

    tests.assertEqual(ruleBar.getRangeEventState(false, true), true, "reported out of range")
    tests.assertEqual(ruleBar.getRangeEventState(true, true), false, "reported in range")
    tests.assertEqual(ruleBar.getRangeEventState(false, false), false, "spell without a range check")
end)

tests.add("uses a matching native Attack icon instead of a stale spell texture", function()
    local ruleBar = ControllerRebound.RuleBar
    if type(ruleBar) ~= "table" or type(ruleBar.shouldUseNativeActionIcon) ~= "function" then
        error("ControllerRebound.RuleBar.shouldUseNativeActionIcon is unavailable")
    end

    tests.assertEqual(ruleBar.shouldUseNativeActionIcon({ actionType = "spell", spellID = 6603 }, "spell", 6603), true, "matching Attack action")
    tests.assertEqual(ruleBar.shouldUseNativeActionIcon({ actionType = "spell", spellID = 6603 }, "spell", 5176), false, "different native spell")
    tests.assertEqual(ruleBar.shouldUseNativeActionIcon({ actionType = "spell", spellID = 5176 }, "spell", 5176), false, "ordinary spell")
end)

tests.add("waits for login before initializing controller buttons", function()
    local ruleBar = ControllerRebound.RuleBar
    tests.assertEqual(ruleBar.shouldInitializeForEvent("PLAYER_LOGIN", true), true, "login initializes")
    tests.assertEqual(ruleBar.shouldInitializeForEvent("PLAYER_ENTERING_WORLD", false), false, "world event waits for login")
end)
