local _, AQG = ...

local UNKNOWN_VALUE = "?"
AQG.Safety = AQG.Safety or {}
local Safety = AQG.Safety

-- Shared safety helpers only. Quest and gossip policy should stay in their
-- own decision modules.

--------------------------------------------------------------------------------
-- Local Formatting Helpers
--------------------------------------------------------------------------------

local function SafeDebugValue(value)
    if Safety:IsSecret(value) then
        return "<secret>"
    end

    return tostring(value)
end

local function CopyList(values)
    local copy = {}

    if type(values) ~= "table" then
        return copy
    end

    for _, value in ipairs(values) do
        table.insert(copy, value)
    end

    return copy
end

local function AddListValue(list, value)
    if not value then return end

    table.insert(list, value)
end

local function ListToString(values)
    if type(values) ~= "table" or #values == 0 then
        return "none"
    end

    local parts = {}

    for i, value in ipairs(values) do
        parts[i] = SafeDebugValue(value)
    end

    return table.concat(parts, ", ")
end

--------------------------------------------------------------------------------
-- Secret-Value And Primitive Guards
--------------------------------------------------------------------------------

function Safety:IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

function Safety:IsSafeNumber(value)
    if self:IsSecret(value) then return false end

    return type(value) == "number"
end

function Safety:SafeNumber(value)
    if self:IsSafeNumber(value) then
        return value
    end

    return nil
end

function Safety:RequireNumber(value, fieldName)
    if self:IsSecret(value) then
        return nil, (fieldName or "value") .. " is secret"
    end

    if value == nil then
        return nil, (fieldName or "value") .. " is missing"
    end

    if type(value) ~= "number" then
        return nil, (fieldName or "value") .. " is not a number"
    end

    return value, nil
end

function Safety:OptionalNumber(value, fieldName)
    if self:IsSecret(value) then
        return nil, (fieldName or "value") .. " is secret"
    end

    if value == nil then
        return nil, nil
    end

    if type(value) ~= "number" then
        return nil, (fieldName or "value") .. " is not a number"
    end

    return value, nil
end

function Safety:IsSafeBoolean(value)
    if self:IsSecret(value) then return false end

    return type(value) == "boolean"
end

function Safety:SafeBoolean(value, fallback)
    if self:IsSafeBoolean(value) then
        return value
    end

    return fallback
end

function Safety:OptionalBoolean(value, fieldName, fallback)
    if self:IsSecret(value) then
        return fallback, (fieldName or "value") .. " is secret"
    end

    if value == nil then
        return fallback, nil
    end

    if type(value) ~= "boolean" then
        return fallback, (fieldName or "value") .. " is not a boolean"
    end

    return value, nil
end

function Safety:IsTrue(value)
    if self:IsSecret(value) then return false end

    return value == true
end

function Safety:IsSafeString(value)
    if self:IsSecret(value) then return false end

    return type(value) == "string"
end

function Safety:SafeString(value, fallback)
    if self:IsSafeString(value) then
        return value
    end

    return fallback
end

function Safety:OptionalString(value, fieldName, fallback)
    if self:IsSecret(value) then
        return fallback, (fieldName or "value") .. " is secret"
    end

    if value == nil then
        return fallback, nil
    end

    if type(value) ~= "string" then
        return fallback, (fieldName or "value") .. " is not a string"
    end

    return value, nil
end

--------------------------------------------------------------------------------
-- Decision Construction And Mutation
--------------------------------------------------------------------------------

function Safety:MakeDecision(allowed, action, targetID, reason)
    return {
        allowed = allowed and true or false,
        action = action,
        targetID = targetID,
        reason = reason or "",
        blockers = {},
        warnings = {},
    }
end

function Safety:BlockDecision(reason, blockers)
    local decision = self:MakeDecision(false, nil, nil, reason)

    if type(blockers) == "table" then
        decision.blockers = CopyList(blockers)
    else
        AddListValue(decision.blockers, blockers)
    end

    return decision
end

function Safety:AppendBlocker(decision, blocker)
    if not decision then return nil end

    decision.allowed = false
    if not decision.blockers then decision.blockers = {} end
    AddListValue(decision.blockers, blocker)

    return decision
end

function Safety:AddDecisionWarning(decision, warning)
    if not decision then return nil end

    if not decision.warnings then decision.warnings = {} end
    AddListValue(decision.warnings, warning)
    if warning and not decision.warnText then
        decision.warnText = warning
    end

    return decision
end

--------------------------------------------------------------------------------
-- Decision Debug Output
--------------------------------------------------------------------------------

function Safety:DebugDecision(domain, decision)
    if not AutoQuestGossipDB or not AutoQuestGossipDB.debugEnabled then
        return
    end

    if not decision then
        AQG:Debug(domain or "Decision", "decision: none")
        return
    end

    local state = decision.allowed and "ALLOW" or "BLOCK"

    AQG:Debug(domain or "Decision", "decision:", state,
        "action:", decision.action or "none",
        "target:", decision.targetID and SafeDebugValue(decision.targetID) or "none",
        "reason:", decision.reason or "none")

    AQG:Debug("  blockers:", ListToString(decision.blockers))
    AQG:Debug("  warnings:", ListToString(decision.warnings))
end

function Safety:DebugDecisionEvent(eventName, domain, decision, detailsFunc)
    if not AutoQuestGossipDB or not AutoQuestGossipDB.debugEnabled then
        return
    end

    AQG:DebugSeparator(eventName)
    self:DebugDecision(domain, decision)

    if detailsFunc then
        detailsFunc(decision)
    end
end

function Safety:DebugDecisionExecution(domain, decision, label)
    if not AutoQuestGossipDB or not AutoQuestGossipDB.debugEnabled then
        return
    end

    if not decision then
        AQG:Debug(domain or "Decision", "execute: no decision")
        return
    end

    AQG:Debug(domain or "Decision", "execute:",
        "action:", decision.action or "none",
        "target:", decision.targetID and SafeDebugValue(decision.targetID) or "none",
        "label:", label or "none")
end

function Safety:DebugRevalidationFailed(reason)
    if not AutoQuestGossipDB or not AutoQuestGossipDB.debugEnabled then
        return
    end

    AQG:Debug("-> Revalidation failed:", reason or "unknown")
end

function Safety:WarnDecision(decision)
    if decision and decision.warnText then
        AQG:Warn(decision.warnText)
    end
end

--------------------------------------------------------------------------------
-- Runtime Gates
--------------------------------------------------------------------------------

function Safety:CheckModifierPaused(moduleName)
    return AQG:PausedByModKey(moduleName)
end

function Safety:CheckDevMode()
    return AutoQuestGossipDB and AutoQuestGossipDB.devMode or false
end

--------------------------------------------------------------------------------
-- NPC Context And Blocklists
--------------------------------------------------------------------------------

function Safety:IsNPCSecret()
    local guid = UnitGUID("npc")

    if self:IsSecret(guid) then
        return true
    end

    return not guid
end

-- Main driver for NPC identity. Callers that need both identity and blocklist
-- state should use this instead of calling GetNPCName/GetNPCID separately.
function Safety:BuildNPCContext(unit)
    unit = unit or "npc"

    local guid = UnitGUID(unit)
    if self:IsSecret(guid) or not guid or type(guid) ~= "string" then
        return {
            safe = false,
            guid = nil,
            id = nil,
            name = UNKNOWN_VALUE,
            blocked = false,
            blockReason = "NPC identity is unavailable or secret",
        }
    end

    local name = self:SafeString(UnitName(unit), UNKNOWN_VALUE)
    local npcID = tonumber((select(6, strsplit("-", guid))))

    local context = {
        safe = true,
        guid = guid,
        id = npcID,
        name = name,
        blocked = false,
        blockReason = nil,
    }

    local allowed, reason = self:CheckNPCBlocklist(context)
    context.blocked = not allowed
    context.blockReason = reason

    return context
end

function Safety:GetNPCName()
    local context = self:BuildNPCContext("npc")

    return context.name or UNKNOWN_VALUE
end

function Safety:GetNPCID()
    local context = self:BuildNPCContext("npc")

    return context.id or UNKNOWN_VALUE
end

function Safety:CheckNPCBlocklist(npcContext)
    if not npcContext then
        return true
    end

    local npcID = npcContext.id
    if self:IsSafeNumber(npcID) and
       AQG.BlockedNPCIDs and AQG.BlockedNPCIDs[npcID] then
        return false, "blocked NPC ID"
    end

    local npcName = npcContext.name
    if self:IsSafeString(npcName) and AQG.BlockedNPCNames then
        for _, blockedName in ipairs(AQG.BlockedNPCNames) do
            if type(blockedName) == "string" and
               npcName:find(blockedName, 1, true) then
                return false, "blocked NPC name: " .. blockedName
            end
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- Final Pre-Action Revalidation
--------------------------------------------------------------------------------

function Safety:ValidateCurrentQuest(questID, frameName)
    if not self:IsSafeNumber(questID) or questID == 0 then
        return false, "invalid quest ID"
    end

    local currentQuestID = GetQuestID and GetQuestID()
    if self:IsSecret(currentQuestID) then
        return false, "current quest ID is secret"
    end

    if currentQuestID ~= nil then
        if type(currentQuestID) ~= "number" then
            return false, "current quest ID is invalid"
        end

        if currentQuestID == 0 then
            return false, "current quest is unavailable"
        end

        if currentQuestID ~= questID then
            return false, "current quest changed"
        end
    end

    if frameName then
        local frame = _G[frameName]
        if frame and frame.IsShown and not frame:IsShown() then
            return false, frameName .. " is hidden"
        end
    end

    return true
end

function Safety:ValidateCurrentGossipOption(optionID)
    if not self:IsSafeNumber(optionID) then
        return false, "invalid gossip option ID"
    end

    local options = C_GossipInfo and C_GossipInfo.GetOptions and
        C_GossipInfo.GetOptions()

    for _, option in ipairs(options or {}) do
        local currentOptionID = option and option.gossipOptionID

        if self:IsSafeNumber(currentOptionID) and
           currentOptionID == optionID then
            return true
        end
    end

    return false, "gossip option is no longer available"
end

--------------------------------------------------------------------------------
-- Compatibility Wrappers
--------------------------------------------------------------------------------

function AQG:IsNPCSecret()
    return Safety:IsNPCSecret()
end

function AQG:GetNPCName()
    return Safety:GetNPCName()
end

function AQG:GetNPCID()
    return Safety:GetNPCID()
end
