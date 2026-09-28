ControllerRebound = ControllerRebound or {}

local function tell(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("[Controller Rebound] " .. message)
    end
end

local function help()
    tell("Drag a spell to A, B, X, or Y, then use its gear to choose when it casts.")
    tell("Bare face buttons use Controller Rebound rules. Native trigger and shoulder layers stay native.")
    tell("Commands: /controllerrebound help | status | test")
end

SLASH_CONTROLLERREBOUND1 = "/controllerrebound"
SLASH_CONTROLLERREBOUND2 = "/cr"
SlashCmdList.CONTROLLERREBOUND = function(message)
    local command, argument = "", ""
    if type(message) == "string" then
        command, argument = message:lower():match("^%s*(%S*)%s*(%S*)")
        command = command or ""
        argument = argument or ""
    end
    if command == "" or command == "help" then
        help()
        return
    end
    if command == "status" then
        local conditional = ControllerRebound.Conditional
        local active = 0
        if type(conditional) == "table" and type(conditional.getSlots) == "function" and type(conditional.isOverrideEnabled) == "function" then
            for _, slot in pairs(conditional.getSlots()) do
                if conditional.isOverrideEnabled(slot) then
                    active = active + 1
                end
            end
        end
        tell("Controller Rebound loaded. " .. tostring(active) .. " conditional face spell" .. (active == 1 and " is" or "s are") .. " active.")
        return
    end
    if command == "test" then
        if type(ControllerReboundTests) == "table" and type(ControllerReboundTests.run) == "function" then
            ControllerReboundTests.run()
        else
            tell("Diagnostics are unavailable.")
        end
        return
    end
    help()
end
