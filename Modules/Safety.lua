local _, AQG = ...

local UNKNOWN_VALUE = "?"
AQG.Safety = AQG.Safety or {}
local Safety = AQG.Safety
local DEBUG_DEDUPE_SECONDS = 0.75
local recentDecisionDebug = {}

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

local function DebugList(label, values)
    if type(values) ~= "table" or #values == 0 then
        AQG:Debug("  " .. label .. ": none")
        return
    end

    AQG:Debug("  " .. label .. ":")

    for _, value in ipairs(values) do
        AQG:Debug("    - " .. SafeDebugValue(value))
    end
end

local function ShouldPrintBlockers(decision)
    local blockers = decision and decision.blockers
    if type(blockers) ~= "table" or #blockers == 0 then
        return false
    end

    if #blockers == 1 and decision.reason and decision.reason ~= "" then
        return false
    end

    return true
end

local function DecisionResult(decision)
    if not decision then
        return "NONE"
    end

    if decision.allowed then
        return "ALLOW"
    end

    if type(decision.blockers) == "table" and #decision.blockers > 0 then
        return "BLOCK"
    end

    return "NO ACTION"
end

local function DecisionDebugSignature(eventName, domain, decision)
    local npcID = AQG.GetNPCID and AQG:GetNPCID() or "?"
    local npcName = AQG.GetNPCName and AQG:GetNPCName() or "?"

    if not decision then
        return table.concat({
            tostring(eventName),
            tostring(domain),
            tostring(npcID),
            tostring(npcName),
            "none",
        }, "|")
    end

    return table.concat({
        tostring(eventName),
        tostring(domain),
        tostring(npcID),
        tostring(npcName),
        DecisionResult(decision),
        tostring(decision.action or "none"),
        decision.targetID and SafeDebugValue(decision.targetID) or "none",
        tostring(decision.reason or "none"),
        ListToString(decision.blockers),
        ListToString(decision.warnings),
    }, "|")
end

local function ShouldSuppressDecisionDebug(signature)
    if not GetTime then
        return false
    end

    local now = GetTime()
    local lastPrinted = recentDecisionDebug[signature]
    recentDecisionDebug[signature] = now

    return lastPrinted and (now - lastPrinted) < DEBUG_DEDUPE_SECONDS
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
        AQG:Debug((domain or "Decision") .. " decision:")
        AQG:Debug("  result: NONE")
        AQG:Debug("  reason: no decision was built")
        return
    end

    AQG:Debug((domain or "Decision") .. " decision:")
    AQG:Debug("  result: " .. DecisionResult(decision))
    AQG:Debug("  action: " .. (decision.action or "none"))
    AQG:Debug("  target: " ..
        (decision.targetID and SafeDebugValue(decision.targetID) or "none"))
    AQG:Debug("  reason: " .. (decision.reason or "none"))

    if ShouldPrintBlockers(decision) then
        DebugList("additional blockers", decision.blockers)
    end

    if type(decision.warnings) == "table" and #decision.warnings > 0 then
        DebugList("warnings", decision.warnings)
    end
end

function Safety:DebugDecisionEvent(eventName, domain, decision, detailsFunc, options)
    if not AutoQuestGossipDB or not AutoQuestGossipDB.debugEnabled then
        return
    end

    local signature = DecisionDebugSignature(eventName, domain, decision)
    if ShouldSuppressDecisionDebug(signature) then
        return
    end

    if not (options and options.suppressInteractionHeader) and
       AQG.DebugInteractionSeparator then
        AQG:DebugInteractionSeparator(eventName)
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
        AQG:Debug((domain or "Decision") .. " execution:")
        AQG:Debug("  result: NO ACTION")
        AQG:Debug("  reason: no decision was built")
        return
    end

    AQG:Debug((domain or "Decision") .. " execution:")
    AQG:Debug("  action: " .. (decision.action or "none"))
    AQG:Debug("  target: " ..
        (decision.targetID and SafeDebugValue(decision.targetID) or "none"))
    AQG:Debug("  label: " .. (label or "none"))
end

function Safety:DebugRevalidationFailed(reason)
    if not AutoQuestGossipDB or not AutoQuestGossipDB.debugEnabled then
        return
    end

    AQG:Debug("Revalidation failed:")
    AQG:Debug("  reason: " .. (reason or "unknown"))
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
