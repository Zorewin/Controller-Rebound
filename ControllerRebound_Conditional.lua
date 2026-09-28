ControllerRebound = ControllerRebound or {}
ControllerRebound.Conditional = ControllerRebound.Conditional or {}

local conditional = ControllerRebound.Conditional
local faces = { "A", "B", "X", "Y" }
local slotStoreVersion = 1
local maxMacroBodyLength = 255
local validFaces = { A = true, B = true, X = true, Y = true }
local allowed = {
    target = { ANY = true, ENEMY = true, FRIENDLY = true, TARGET = true, NONE = true },
    life = { ANY = true, ALIVE = true, DEAD = true },
    combat = { ANY = true, IN = true, OUT = true },
    group = { ANY = true, SOLO = true, PARTY = true, RAID = true },
}

conditional.choices = {
    target = { "ANY", "ENEMY", "FRIENDLY", "TARGET", "NONE" },
    life = { "ANY", "ALIVE", "DEAD" },
    combat = { "ANY", "IN", "OUT" },
    group = { "ANY", "SOLO", "PARTY", "RAID" },
}

conditional.labels = {
    target = { ANY = "Any target state", ENEMY = "Enemy target", FRIENDLY = "Friendly target", TARGET = "Any target", NONE = "No target" },
    life = { ANY = "Any target life", ALIVE = "Living target", DEAD = "Dead target" },
    combat = { ANY = "Any combat state", IN = "In combat", OUT = "Out of combat" },
    group = { ANY = "Any group state", SOLO = "Solo", PARTY = "In party", RAID = "In raid" },
}

conditional.callbacks = conditional.callbacks or {}

local function normalizedChoice(kind, value)
    if type(value) == "string" then
        value = value:match("^%s*(.-)%s*$"):upper()
    end
    if value and allowed[kind][value] then
        return value
    end
    return "ANY"
end

local function normalizedFace(face)
    if type(face) == "string" then
        face = face:match("^%s*(.-)%s*$"):upper()
    end
    return validFaces[face] and face or nil
end

function conditional.newSlot(face)
    return {
        face = normalizedFace(face),
        actionType = "spell",
        spellID = nil,
        macroText = nil,
        macroName = nil,
        macroIcon = nil,
        macroID = nil,
        enabled = true,
        target = "ANY",
        life = "ANY",
        combat = "ANY",
        group = "ANY",
    }
end

function conditional.normalizeSlot(slot, face)
    local normalized = conditional.newSlot(face or (type(slot) == "table" and slot.face))
    if type(slot) ~= "table" then
        return normalized
    end

    local actionType = slot.actionType == "macro" and "macro" or "spell"
    if actionType == "macro" and type(slot.macroText) == "string"
        and slot.macroText:match("%S") and #slot.macroText <= maxMacroBodyLength then
        normalized.actionType = "macro"
        normalized.macroText = slot.macroText
        normalized.macroName = type(slot.macroName) == "string" and slot.macroName or "Macro"
        local macroIcon = tonumber(slot.macroIcon)
        normalized.macroIcon = macroIcon and macroIcon > 0 and math.floor(macroIcon) or nil
        local macroID = tonumber(slot.macroID)
        normalized.macroID = macroID and macroID > 0 and math.floor(macroID) or nil
    else
        local spellID = tonumber(slot.spellID)
        normalized.spellID = spellID and spellID > 0 and math.floor(spellID) or nil
    end
    normalized.enabled = slot.enabled ~= false
    normalized.target = normalizedChoice("target", slot.target)
    normalized.life = normalizedChoice("life", slot.life)
    normalized.combat = normalizedChoice("combat", slot.combat)
    normalized.group = normalizedChoice("group", slot.group)
    if normalized.target == "NONE" then
        normalized.life = "ANY"
    end
    return normalized
end

function conditional.preparePersistentSlots(store, legacySlots)
    if type(store) ~= "table" then
        return nil
    end

    local source = store.slots
    if store.version ~= slotStoreVersion and type(legacySlots) == "table" then
        source = legacySlots
    end
    if type(source) ~= "table" then
        source = {}
    end

    local slots = {}
    for _, face in ipairs(faces) do
        slots[face] = conditional.normalizeSlot(source[face], face)
    end
    store.version = slotStoreVersion
    store.slots = slots
    return slots
end

function conditional.prepareCharacterSlots(characterStore, accountStore, legacySlots)
    if type(characterStore) ~= "table" then
        return nil
    end

    local source = characterStore.slots
    if type(source) ~= "table" then
        if type(accountStore) == "table" and accountStore.perCharacterMigrationClaimed ~= true then
            source = accountStore.slots
            if type(source) ~= "table" then
                source = legacySlots
            end
            accountStore.perCharacterMigrationClaimed = true
        end
        characterStore.slots = type(source) == "table" and source or {}
    end
    return conditional.preparePersistentSlots(characterStore)
end

local function database()
    if type(ControllerReboundSlotsDB) ~= "table" then
        ControllerReboundSlotsDB = {}
    end
    if type(ControllerReboundCharacterDB) ~= "table" then
        ControllerReboundCharacterDB = {}
    end
    local legacySlots = type(ControllerReboundDB) == "table" and ControllerReboundDB.conditionalSlots or nil
    conditional.prepareCharacterSlots(ControllerReboundCharacterDB, ControllerReboundSlotsDB, legacySlots)
    return ControllerReboundCharacterDB
end

function conditional.getSlot(face)
    face = normalizedFace(face)
    if not face then
        return nil
    end
    return conditional.normalizeSlot(database().slots[face], face)
end

function conditional.getSlots()
    local slots = {}
    for _, face in ipairs(faces) do
        slots[face] = conditional.getSlot(face)
    end
    return slots
end

function conditional.isOverrideEnabled(slot)
    slot = conditional.normalizeSlot(slot)
    local hasAction = slot.actionType == "macro" and slot.macroText or slot.spellID
    if not slot.enabled or not hasAction then
        return false
    end
    return slot.target ~= "ANY"
        or slot.life ~= "ANY"
        or slot.combat ~= "ANY"
        or slot.group ~= "ANY"
end

function conditional.buildStateDriver(slot)
    slot = conditional.normalizeSlot(slot)
    if not conditional.isOverrideEnabled(slot) then
        return "native"
    end

    local conditions = {}
    local target = {
        ENEMY = "harm",
        FRIENDLY = "help",
        TARGET = "exists",
        NONE = "noexists",
    }
    local life = { ALIVE = "nodead", DEAD = "dead" }
    local combat = { IN = "combat", OUT = "nocombat" }
    local group = { SOLO = "nogroup", PARTY = "group:party", RAID = "group:raid" }

    if combat[slot.combat] then conditions[#conditions + 1] = combat[slot.combat] end
    if target[slot.target] then conditions[#conditions + 1] = target[slot.target] end
    if life[slot.life] then conditions[#conditions + 1] = life[slot.life] end
    if group[slot.group] then conditions[#conditions + 1] = group[slot.group] end
    return "[" .. table.concat(conditions, ",") .. "] override; native"
end

function conditional.buildTypeDriver(slot)
    local stateDriver = conditional.buildStateDriver(slot)
    if stateDriver == "native" then
        return "macro"
    end
    if slot.actionType == "macro" then
        return stateDriver:gsub(" override; native$", " macro; macro")
    end
    return stateDriver:gsub(" override; native$", " spell; macro")
end

-- Native action-bar buttons already know their own fallback action.  Unlike
-- ControllerRebound's private button, they need "action" rather than a macro fallback.
function conditional.onChanged(callback)
    if type(callback) == "function" then
        conditional.callbacks[#conditional.callbacks + 1] = callback
    end
end

function conditional.notifyChanged(face)
    local slot = conditional.getSlot(face)
    for _, callback in ipairs(conditional.callbacks) do
        callback(face, slot)
    end
end

function conditional.planCheckboxChoice(slot, kind, value, checked)
    if not allowed[kind] or value == "ANY" or not allowed[kind][value] then
        return nil, "invalid-choice"
    end

    local planned = conditional.normalizeSlot(slot)
    if checked then
        planned[kind] = value
    elseif planned[kind] == value then
        planned[kind] = "ANY"
    end
    return conditional.normalizeSlot(planned, planned.face)
end

function conditional.updateSlot(face, changes)
    face = normalizedFace(face)
    if not face or type(changes) ~= "table" then
        return nil, "invalid-slot"
    end

    local current = conditional.getSlot(face)
    for key, value in pairs(changes) do
        current[key] = value
    end
    local nextSlot = conditional.normalizeSlot(current, face)
    database().slots[face] = nextSlot
    conditional.notifyChanged(face)
    return conditional.normalizeSlot(nextSlot, face)
end

function conditional.clearAction(face)
    return conditional.updateSlot(face, {
        actionType = "spell",
        spellID = nil,
        macroText = nil,
        macroName = nil,
        macroIcon = nil,
        macroID = nil,
    })
end

conditional.clearSpell = conditional.clearAction

function conditional.getFaces()
    return faces
end
