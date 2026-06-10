local _, AQG = ...

AQG.GossipDecisions = AQG.GossipDecisions or {}
local Decisions = AQG.GossipDecisions
local Safety = AQG.Safety

local STATUS_AVAILABLE =
    Enum and Enum.GossipOptionStatus and Enum.GossipOptionStatus.Available or 0

local MAX_FALLBACK_OPTIONS = 3

local ACTIONS = {
    SELECT_QUEST = "GOSSIP_SELECT_QUEST",
    SELECT_BLIZZARD_AUTO = "GOSSIP_SELECT_BLIZZARD_AUTO",
    SELECT_VENDOR = "GOSSIP_SELECT_VENDOR",
    SELECT_FALLBACK = "GOSSIP_SELECT_FALLBACK",
}

Decisions.Actions = ACTIONS

--------------------------------------------------------------------------------
-- Decision Helpers
--------------------------------------------------------------------------------

local function Block(reason, blockers)
    return Safety:BlockDecision(reason, blockers)
end

local function NoAction(reason)
    return Safety:MakeDecision(false, nil, nil, reason or "no gossip action")
end

local function WithWarning(decision, warning)
    return Safety:AddDecisionWarning(decision, warning)
end

local function OptionLabel(option)
    if not option then return "?" end

    return Safety:SafeString(option.name, "?")
end

local function Allow(action, option, reason)
    local targetID = option.optionID or option.orderIndex
    local decision = Safety:MakeDecision(true, action, targetID, reason)

    decision.option = option
    decision.optionID = option.optionID
    decision.orderIndex = option.orderIndex
    decision.label = OptionLabel(option)

    return decision
end

local function HasActiveQuests(context)
    return context and context.quests and context.quests.hasActive or false
end

local function HasAvailableQuests(context)
    return context and context.quests and context.quests.hasAvailable or false
end

local function ForceGossip()
    local value = C_GossipInfo and C_GossipInfo.ForceGossip and
        C_GossipInfo.ForceGossip()
    local forceGossip, reason =
        Safety:OptionalBoolean(value, "force gossip", false)

    if reason then
        return nil, "Cannot safely read Blizzard's gossip state."
    end

    return forceGossip, reason
end

local function SafeFallbackGossipEnabled()
    return AutoQuestGossipDB and
        AutoQuestGossipDB.allowSafeFallbackGossip ~= false
end

local function ShouldPauseForImportantOption(option)
    return option and option.isImportant and not option.isDelve
end

--------------------------------------------------------------------------------
-- Option Classification
--------------------------------------------------------------------------------

function Decisions:ClassifyGossipOption(option)
    local result = {
        option = option,
        selectableByID = false,
        selectableByIndex = false,
        available = false,
        blockers = {},
    }

    if not option then
        table.insert(result.blockers, "missing option")
        return result
    end

    if not option.safe then
        table.insert(result.blockers, "unsafe option data")
    end

    if option.status ~= STATUS_AVAILABLE then
        table.insert(result.blockers, "option is not available")
    end

    if option.isBlockedIcon then
        table.insert(result.blockers, "blocked icon")
    end

    if option.hasUnknownIcon then
        table.insert(result.blockers, "unknown icon")
    end

    if option.isCinematic then
        table.insert(result.blockers, "cinematic option")
    end

    if ShouldPauseForImportantOption(option) then
        table.insert(result.blockers, "important option")
    end

    if Safety:IsSafeNumber(option.optionID) then
        result.selectableByID = true
    end

    if Safety:IsSafeNumber(option.orderIndex) then
        result.selectableByIndex = true
    end

    result.available = #result.blockers == 0

    return result
end

local function IsSelectableByID(option)
    local classification = Decisions:ClassifyGossipOption(option)

    return classification.available and classification.selectableByID
end

local function IsSelectableByIndex(option)
    local classification = Decisions:ClassifyGossipOption(option)

    return classification.available and classification.selectableByIndex
end

local function IsFallbackCandidate(option)
    if not IsSelectableByID(option) then return false end
    if option.isQuest then return false end
    if option.isVendor then return false end
    if option.isStayAwhile then return false end

    return option.isKnownIcon and not option.isBlockedIcon
end

--------------------------------------------------------------------------------
-- Shared Blockers
--------------------------------------------------------------------------------

local function FindImportantOptionRequiringPause(options)
    for _, option in ipairs(options or {}) do
        if ShouldPauseForImportantOption(option) then
            return option
        end
    end

    return nil
end

local function CheckCommonBlockers(context)
    local db = AutoQuestGossipDB

    if not db or not db.gossipEnabled then
        return Block("Gossip automation is disabled in AQG settings.",
            "gossip disabled")
    end

    local npc = context and context.npc
    if not npc or not npc.safe then
        return Block("Cannot safely identify this NPC.",
            "npc identity secret")
    end

    if npc.blocked then
        return Block(npc.blockReason or
            "This NPC is blocked by your blocklist.", "blocked NPC")
    end

    local gossip = context and context.gossip or {}
    local options = gossip.options or {}
    if (gossip.optionCount or 0) == 0 then
        return NoAction("no gossip options")
    end

    if (gossip.unsafeOptionCount or 0) > 0 then
        return Block("Cannot safely read this gossip interaction.",
            "unsafe gossip option")
    end

    if gossip.hasSkip then
        return WithWarning(
            Block("A skip option is available.", "skip option"),
            "A skip option is available. Choose manually."
        )
    end

    local importantOption = FindImportantOptionRequiringPause(options)
    if importantOption then
        return WithWarning(
            Block(
                "An important option requires manual selection: " ..
                    OptionLabel(importantOption),
                "important option"
            ),
            "An important option is available. Choose manually."
        )
    end

    if gossip.hasAngleBracket and db.pauseOnAngleBracket then
        return WithWarning(
            Block("A bracketed option is available.", "angle bracket option"),
            "A bracketed option is available. Choose manually."
        )
    end

    if HasAvailableQuests(context) and not HasActiveQuests(context) then
        return Block("This NPC has available quests. Choose manually.",
            "available quests")
    end

    if gossip.hasCinematic then
        return Block("A cinematic gossip option is available. Choose manually.",
            "cinematic")
    end

    if gossip.hasUnknownIcon then
        return Block("This NPC has an unknown gossip option. Choose manually.",
            "unknown icon")
    end

    if db.gossipOnlySingle and (gossip.optionCount or 0) > 1 then
        return Block("Multiple gossip options are available in single-option mode.",
            "multiple options")
    end

    return nil
end

--------------------------------------------------------------------------------
-- Selection Priority
--------------------------------------------------------------------------------

local function FindQuestOptions(options)
    local questOptions = {}

    for _, option in ipairs(options or {}) do
        if option.isQuest and not option.isStayAwhile then
            table.insert(questOptions, option)
        end
    end

    return questOptions
end

local function FindVendorOption(options)
    for _, option in ipairs(options or {}) do
        if option.isVendor and IsSelectableByID(option) then
            return option
        end
    end

    return nil
end

local function FindFallbackOptions(options)
    local fallbackOptions = {}

    for _, option in ipairs(options or {}) do
        if IsFallbackCandidate(option) then
            table.insert(fallbackOptions, option)
        end
    end

    return fallbackOptions
end

local function DecideBlizzardAutoSelect(context)
    local gossip = context and context.gossip or {}
    local options = gossip.options or {}

    if HasActiveQuests(context) or HasAvailableQuests(context) then
        return nil
    end

    if (gossip.optionCount or 0) ~= 1 then
        return nil
    end

    local forceGossip, forceReason = ForceGossip()
    if forceReason then
        return Block(forceReason, "unsafe force gossip")
    end

    if forceGossip then
        return nil
    end

    local option = options[1]
    if option and option.selectOptionWhenOnlyOption and
       IsSelectableByIndex(option) then
        return Allow(
            ACTIONS.SELECT_BLIZZARD_AUTO,
            option,
            "Blizzard true single-option auto-select"
        )
    end

    return nil
end

function Decisions:FindBestGossipOption(context)
    local gossip = context and context.gossip or {}
    local options = gossip.options or {}

    local questOptions = FindQuestOptions(options)
    if #questOptions == 1 and IsSelectableByID(questOptions[1]) then
        return ACTIONS.SELECT_QUEST, questOptions[1]
    end

    local autoDecision = DecideBlizzardAutoSelect(context)
    if autoDecision and autoDecision.allowed then
        return autoDecision.action, autoDecision.option
    end

    local vendorOption = FindVendorOption(options)
    if vendorOption then
        return ACTIONS.SELECT_VENDOR, vendorOption
    end

    if not SafeFallbackGossipEnabled() then
        return nil, nil
    end

    local fallbackOptions = FindFallbackOptions(options)
    if #fallbackOptions == 1 then
        return ACTIONS.SELECT_FALLBACK, fallbackOptions[1]
    end

    return nil, nil
end

function Decisions:DecideGossipAction(context)
    local block = CheckCommonBlockers(context)
    if block then return block end

    local gossip = context and context.gossip or {}
    local options = gossip.options or {}
    local questOptions = FindQuestOptions(options)

    if #questOptions > 1 then
        return Block("Multiple quest gossip options are available. Choose manually.",
            "multiple quest options")
    end

    if #questOptions == 1 then
        local questOption = questOptions[1]
        if IsSelectableByID(questOption) then
            return Allow(
                ACTIONS.SELECT_QUEST,
                questOption,
                "single quest gossip option"
            )
        end

        return Block("Cannot safely select the quest gossip option.",
            "blocked quest option")
    end

    local autoDecision = DecideBlizzardAutoSelect(context)
    if autoDecision then
        return autoDecision
    end

    if gossip.hasStayAwhile then
        return WithWarning(
            Block("Stay Awhile and Listen is available.", "stay awhile"),
            "Stay Awhile and Listen is available. Choose manually."
        )
    end

    local vendorOption = FindVendorOption(options)
    if vendorOption then
        return Allow(ACTIONS.SELECT_VENDOR, vendorOption, "safe vendor option")
    end

    if not SafeFallbackGossipEnabled() then
        return Block("Fallback gossip selection is disabled in AQG settings.",
            "fallback disabled")
    end

    if (gossip.optionCount or 0) > MAX_FALLBACK_OPTIONS then
        return Block("Too many gossip options are available for safe fallback selection.",
            "too many options")
    end

    local fallbackOptions = FindFallbackOptions(options)
    if #fallbackOptions == 1 then
        return Allow(
            ACTIONS.SELECT_FALLBACK,
            fallbackOptions[1],
            "single safe fallback gossip option"
        )
    end

    if #fallbackOptions > 1 then
        return Block("Multiple safe fallback options are available. Choose manually.",
            "ambiguous fallback")
    end

    return NoAction("no valid gossip option to auto-select")
end
