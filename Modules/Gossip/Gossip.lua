local _, AQG = ...

local Decisions = AQG.GossipDecisions
local Safety = AQG.Safety
local ACTIONS = Decisions.Actions

local SelectOption = C_GossipInfo.SelectOption
local SelectOptionByIndex = C_GossipInfo.SelectOptionByIndex

local selectedGossipKeys = {}

--------------------------------------------------------------------------------
-- Debug And Formatting
--------------------------------------------------------------------------------

local function IconTag(decision)
    local option = decision and decision.option
    local icon = option and option.displayIcon

    if Safety:IsSafeNumber(icon) then
        return "|T" .. icon .. ":0|t "
    end

    return ""
end

local function OptionLabel(decision)
    if not decision then return "?" end

    return IconTag(decision) .. Safety:SafeString(decision.label, "?")
end

local function DebugDecision(eventName, decision)
    if not AutoQuestGossipDB or not AutoQuestGossipDB.debugEnabled then
        return
    end

    AQG:DebugSeparator(eventName)
    Safety:DebugDecision("Gossip", decision)

    if decision and decision.option then
        AQG:Debug("  option:", OptionLabel(decision))
    end
end

local function WarnDecision(decision)
    if decision and decision.warnText then
        AQG:Warn(decision.warnText)
    end
end

local function DebugRevalidationFailed(reason)
    AQG:Debug("-> Revalidation failed:", reason or "unknown")
end

--------------------------------------------------------------------------------
-- Execution Guards
--------------------------------------------------------------------------------

local function CanExecuteDecision(decision)
    if not decision or not decision.allowed then
        WarnDecision(decision)
        return false
    end

    if Safety:CheckModifierPaused("Gossip") then
        return false
    end

    if Safety:CheckDevMode() then
        return false
    end

    return true
end

local function LoopKey(decision)
    if not decision then return nil end

    if Safety:IsSafeNumber(decision.optionID) then
        return "id:" .. decision.optionID
    end

    if Safety:IsSafeNumber(decision.orderIndex) then
        return "index:" .. decision.orderIndex .. ":" ..
            Safety:SafeString(decision.label, "?")
    end

    return nil
end

local function SameDecision(expected, current)
    if not expected or not current then return false end
    if expected.action ~= current.action then return false end

    if expected.action == ACTIONS.SELECT_BLIZZARD_AUTO then
        return Safety:IsSafeNumber(expected.orderIndex) and
            expected.orderIndex == current.orderIndex
    end

    return Safety:IsSafeNumber(expected.optionID) and
        expected.optionID == current.optionID
end

local function RevalidateDecision(decision)
    local context = AQG.InteractionContext:Build("GOSSIP_REVALIDATE")
    local currentDecision = Decisions:DecideGossipAction(context)

    if not currentDecision or not currentDecision.allowed then
        return nil, currentDecision and currentDecision.reason
            or "gossip decision is no longer allowed"
    end

    if not SameDecision(decision, currentDecision) then
        return nil, "gossip option changed"
    end

    return currentDecision, nil
end

--------------------------------------------------------------------------------
-- Gossip Execution
--------------------------------------------------------------------------------

local function ExecuteGossipDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    local currentDecision, reason = RevalidateDecision(decision)
    if not currentDecision then
        DebugRevalidationFailed(reason)
        return false
    end

    if Safety:CheckModifierPaused("Gossip") then
        return false
    end

    if Safety:CheckDevMode() then
        return false
    end

    local loopKey = LoopKey(currentDecision)
    if not loopKey then
        DebugRevalidationFailed("gossip loop key is unavailable")
        return false
    end

    if selectedGossipKeys[loopKey] then
        AQG:Debug("-> Loop detected. Would NOT auto-select gossip.")
        AQG:Warn("Gossip loop detected - automation paused.")

        return false
    end

    selectedGossipKeys[loopKey] = true

    AQG:Verbose("Gossip:", OptionLabel(currentDecision),
        "(ID:", currentDecision.optionID or "?", ")")
    AQG:Debug("Auto-select gossip:", OptionLabel(currentDecision))

    if currentDecision.action == ACTIONS.SELECT_BLIZZARD_AUTO then
        SelectOptionByIndex(currentDecision.orderIndex)
    else
        SelectOption(currentDecision.optionID)
    end

    return true
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

local function OnGossipShow()
    local context = AQG.InteractionContext:Build("GOSSIP_SHOW")
    local decision = Decisions:DecideGossipAction(context)

    DebugDecision("GOSSIP_SHOW (Gossip)", decision)
    ExecuteGossipDecision(decision)
end

AQG:RegisterEvent("GOSSIP_SHOW", OnGossipShow)

AQG:RegisterEvent("GOSSIP_CLOSED", function()
    wipe(selectedGossipKeys)
end)
