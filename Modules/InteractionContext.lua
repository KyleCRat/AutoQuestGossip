local _, AQG = ...

AQG.InteractionContext = AQG.InteractionContext or {}
local Context = AQG.InteractionContext
local Safety = AQG.Safety

local UNKNOWN_VALUE = "?"

local ICON_VENDOR = 132060
local ICON_GOSSIP = 132053
local ICON_BINDER = 136458
local ICON_FLIGHTMASTER = 132057
local ICON_TRAINER = 132058

local KNOWN_GOSSIP_ICONS = {
    [ICON_VENDOR] = true,
    [ICON_GOSSIP] = true,
    [ICON_BINDER] = true,
    [ICON_FLIGHTMASTER] = true,
    [ICON_TRAINER] = true,
}

local BLOCKED_GOSSIP_ICONS = {
    [ICON_BINDER] = true,
    [ICON_FLIGHTMASTER] = true,
    [ICON_TRAINER] = true,
}

local GOSSIP_FLAG_QUEST = 1
local GOSSIP_FLAG_CINEMATIC = 4

--------------------------------------------------------------------------------
-- Unsafe Field Tracking
--------------------------------------------------------------------------------

local function MarkUnsafe(target, reason)
    target.safe = false

    if not target.unsafeReasons then
        target.unsafeReasons = {}
    end

    table.insert(target.unsafeReasons, reason)
end

local function ReadNumberField(target, source, key, required)
    local value = source and source[key]

    if Safety:IsSecret(value) then
        MarkUnsafe(target, key .. " is secret")
        return nil
    end

    if value == nil then
        if required then
            MarkUnsafe(target, key .. " is missing")
        end

        return nil
    end

    if type(value) ~= "number" then
        MarkUnsafe(target, key .. " is not a number")
        return nil
    end

    return value
end

local function ReadStringField(target, source, key, required, fallback)
    local value = source and source[key]

    if Safety:IsSecret(value) then
        MarkUnsafe(target, key .. " is secret")
        return fallback
    end

    if value == nil then
        if required then
            MarkUnsafe(target, key .. " is missing")
        end

        return fallback
    end

    if type(value) ~= "string" then
        MarkUnsafe(target, key .. " is not a string")
        return fallback
    end

    return value
end

local function ReadBooleanField(target, source, key, required, fallback)
    local value = source and source[key]

    if Safety:IsSecret(value) then
        MarkUnsafe(target, key .. " is secret")
        return fallback
    end

    if value == nil then
        if required then
            MarkUnsafe(target, key .. " is missing")
        end

        return fallback
    end

    if type(value) ~= "boolean" then
        MarkUnsafe(target, key .. " is not a boolean")
        return fallback
    end

    return value
end

--------------------------------------------------------------------------------
-- Gossip Option Snapshot
--------------------------------------------------------------------------------

local function AddGossipTextFlags(option)
    local name = option.name
    if not name then return end

    local lowerName = name:lower()

    option.isSkip = lowerName:find("skip", 1, true) ~= nil
    option.isImportant = name:find("|c", 1, true) ~= nil
    option.isAngleBracket = name:find("<.+>") ~= nil
    option.isDelve = name:find("%(Delve%)") ~= nil
    option.isStayAwhile = option.isAngleBracket and
        lowerName:find("awhile", 1, true) ~= nil
end

local function AddGossipFlagData(option)
    local flags = option.flags
    if not flags then return end

    option.isQuest = bit.band(flags, GOSSIP_FLAG_QUEST) ~= 0
    option.isCinematic = bit.band(flags, GOSSIP_FLAG_CINEMATIC) ~= 0
end

local function AddGossipIconData(option)
    local displayIcon = option.overrideIconID or option.icon

    option.displayIcon = displayIcon
    option.isVendor = displayIcon == ICON_VENDOR
    option.isKnownIcon = displayIcon and KNOWN_GOSSIP_ICONS[displayIcon] or false
    option.isBlockedIcon = displayIcon and BLOCKED_GOSSIP_ICONS[displayIcon] or false
    option.hasUnknownIcon = option.hasOptionID and not option.isKnownIcon
end

local function BuildGossipOption(rawOption, index)
    local option = {
        safe = true,
        unsafeReasons = {},
        index = index,
        optionID = nil,
        hasOptionID = false,
        name = UNKNOWN_VALUE,
    }

    if type(rawOption) ~= "table" then
        MarkUnsafe(option, "option is not a table")
        return option
    end

    option.optionID = ReadNumberField(option, rawOption, "gossipOptionID", false)
    option.hasOptionID = option.optionID ~= nil
    option.name = ReadStringField(option, rawOption, "name", true, UNKNOWN_VALUE)
    option.icon = ReadNumberField(option, rawOption, "icon", true)
    option.overrideIconID = ReadNumberField(option, rawOption, "overrideIconID", false)
    option.status = ReadNumberField(option, rawOption, "status", true)
    option.spellID = ReadNumberField(option, rawOption, "spellID", false)
    option.flags = ReadNumberField(option, rawOption, "flags", true)
    option.orderIndex = ReadNumberField(option, rawOption, "orderIndex", true)
    option.selectOptionWhenOnlyOption =
        ReadBooleanField(option, rawOption, "selectOptionWhenOnlyOption", true, false)

    AddGossipFlagData(option)
    AddGossipIconData(option)
    AddGossipTextFlags(option)

    return option
end

local function AddGossipAggregates(gossip, option)
    gossip.optionCount = gossip.optionCount + 1

    if not option.safe then
        gossip.unsafeOptionCount = gossip.unsafeOptionCount + 1
    end

    if option.isSkip then gossip.hasSkip = true end
    if option.isImportant then gossip.hasImportant = true end
    if option.isAngleBracket then gossip.hasAngleBracket = true end
    if option.isStayAwhile then gossip.hasStayAwhile = true end
    if option.isCinematic then gossip.hasCinematic = true end
    if option.hasUnknownIcon then gossip.hasUnknownIcon = true end
    if option.isBlockedIcon then gossip.hasBlockedIcon = true end
    if option.isQuest then gossip.hasQuestOption = true end
end

local function BuildGossipContext()
    local gossip = {
        options = {},
        optionCount = 0,
        unsafeOptionCount = 0,
        hasSkip = false,
        hasImportant = false,
        hasAngleBracket = false,
        hasStayAwhile = false,
        hasCinematic = false,
        hasUnknownIcon = false,
        hasBlockedIcon = false,
        hasQuestOption = false,
    }

    local rawOptions = C_GossipInfo and C_GossipInfo.GetOptions and
        C_GossipInfo.GetOptions() or {}

    for index, rawOption in ipairs(rawOptions) do
        local option = BuildGossipOption(rawOption, index)
        table.insert(gossip.options, option)
        AddGossipAggregates(gossip, option)
    end

    return gossip
end

--------------------------------------------------------------------------------
-- Quest Snapshot
--------------------------------------------------------------------------------

local function BuildQuestInfo(rawQuest, index, source)
    local quest = {
        safe = true,
        unsafeReasons = {},
        index = index,
        source = source,
        title = UNKNOWN_VALUE,
        questID = nil,
    }

    if type(rawQuest) ~= "table" then
        MarkUnsafe(quest, "quest is not a table")
        return quest
    end

    quest.title = ReadStringField(quest, rawQuest, "title", true, UNKNOWN_VALUE)
    quest.questID = ReadNumberField(quest, rawQuest, "questID", true)
    quest.questLevel = ReadNumberField(quest, rawQuest, "questLevel", true)
    quest.frequency = ReadNumberField(quest, rawQuest, "frequency", false)
    quest.questInfoID = ReadNumberField(quest, rawQuest, "questInfoID", true)
    quest.isTrivial = ReadBooleanField(quest, rawQuest, "isTrivial", true, false)
    quest.repeatable = ReadBooleanField(quest, rawQuest, "repeatable", false, false)
    quest.isComplete = ReadBooleanField(quest, rawQuest, "isComplete", false, false)
    quest.isLegendary = ReadBooleanField(quest, rawQuest, "isLegendary", true, false)
    quest.isIgnored = ReadBooleanField(quest, rawQuest, "isIgnored", true, false)
    quest.isImportant = ReadBooleanField(quest, rawQuest, "isImportant", true, false)
    quest.isMeta = ReadBooleanField(quest, rawQuest, "isMeta", true, false)

    return quest
end

local function AddQuestAggregates(quests, quest)
    if not quest.safe then
        quests.unsafeQuestCount = quests.unsafeQuestCount + 1
    end

    if quest.source == "active" then
        quests.hasActive = true
        quests.hasCompletable = quests.hasCompletable or quest.isComplete
    elseif quest.source == "available" then
        quests.hasAvailable = true
    end
end

local function BuildQuestContext()
    local quests = {
        active = {},
        available = {},
        unsafeQuestCount = 0,
        hasActive = false,
        hasAvailable = false,
        hasCompletable = false,
    }

    local activeQuests = C_GossipInfo and C_GossipInfo.GetActiveQuests and
        C_GossipInfo.GetActiveQuests() or {}

    for index, rawQuest in ipairs(activeQuests) do
        local quest = BuildQuestInfo(rawQuest, index, "active")
        table.insert(quests.active, quest)
        AddQuestAggregates(quests, quest)
    end

    local availableQuests = C_GossipInfo and C_GossipInfo.GetAvailableQuests and
        C_GossipInfo.GetAvailableQuests() or {}

    for index, rawQuest in ipairs(availableQuests) do
        local quest = BuildQuestInfo(rawQuest, index, "available")
        table.insert(quests.available, quest)
        AddQuestAggregates(quests, quest)
    end

    return quests
end

--------------------------------------------------------------------------------
-- Main Driver
--------------------------------------------------------------------------------

function Context:Build(eventName)
    return {
        event = eventName or "UNKNOWN",
        npc = Safety:BuildNPCContext("npc"),
        gossip = BuildGossipContext(),
        quests = BuildQuestContext(),
    }
end

function Context:Debug(context)
    if not AutoQuestGossipDB or not AutoQuestGossipDB.debugEnabled then
        return
    end

    if not context then
        AQG:Debug("Interaction context: none")
        return
    end

    local npc = context.npc or {}
    local gossip = context.gossip or {}
    local quests = context.quests or {}

    AQG:Debug("Interaction context:", context.event or "UNKNOWN")
    AQG:Debug("  NPC:", npc.name or UNKNOWN_VALUE,
        "(ID:", npc.id or UNKNOWN_VALUE, ")",
        npc.safe and "safe" or "unsafe")
    AQG:Debug("  Gossip options:", gossip.optionCount or 0,
        "unsafe:", gossip.unsafeOptionCount or 0,
        "cinematic:", tostring(gossip.hasCinematic),
        "unknownIcon:", tostring(gossip.hasUnknownIcon))
    AQG:Debug("  Quests active:", #(quests.active or {}),
        "available:", #(quests.available or {}),
        "completable:", tostring(quests.hasCompletable),
        "unsafe:", quests.unsafeQuestCount or 0)
end
