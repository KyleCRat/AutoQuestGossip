local _, AQG = ...

AQG.QuestDecisions = AQG.QuestDecisions or {}
local Decisions = AQG.QuestDecisions
local Safety = AQG.Safety

local GetTitle = C_QuestLog.GetTitleForQuestID
local GetInfo = C_QuestLog.GetInfo
local GetLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID
local QuestAccountComplete = C_QuestLog.IsQuestFlaggedCompletedOnAccount
local IsRepeatableQuest = C_QuestLog.IsRepeatableQuest
local GetQuestTagInfo = C_QuestLog.GetQuestTagInfo
local IsQuestTrivial = C_QuestLog.IsQuestTrivial

local RETRY_TIME_DELAY = 0.25
local MAX_QUEST_DATA_RETRIES = 10
local questDataRetryCounts = {}

local ACTIONS = {
    GOSSIP_TURN_IN = "GOSSIP_TURN_IN",
    GOSSIP_ACCEPT = "GOSSIP_ACCEPT",
    GREETING_TURN_IN = "GREETING_TURN_IN",
    GREETING_ACCEPT = "GREETING_ACCEPT",
    ACCEPT_CONFIRM = "ACCEPT_CONFIRM",
    QUEST_DETAIL_ACCEPT = "QUEST_DETAIL_ACCEPT",
    QUEST_DETAIL_ACK_AUTO_ACCEPT = "QUEST_DETAIL_ACK_AUTO_ACCEPT",
    QUEST_PROGRESS_COMPLETE = "QUEST_PROGRESS_COMPLETE",
    QUEST_COMPLETE_REWARD = "QUEST_COMPLETE_REWARD",
    QUEST_AUTOCOMPLETE_SHOW = "QUEST_AUTOCOMPLETE_SHOW",
}

Decisions.Actions = ACTIONS

local CONTENT_TAG_MAP = {
      [1] = "contentGroup",
     [41] = "contentPvP",
     [62] = "contentRaid",
     [81] = "contentDungeon",
     [85] = "contentDungeon",   -- Heroic
     [88] = "contentRaid",      -- Raid (10)
     [89] = "contentRaid",      -- Raid (25)
    [113] = "contentPvP",       -- PVP World Quest
    [137] = "contentDungeon",   -- Dungeon World Quest
    [141] = "contentRaid",      -- Raid World Quest
    [145] = "contentDungeon",   -- Legionfall Dungeon World Quest
    [255] = "contentPvP",       -- War Mode PvP
    [256] = "contentPvP",       -- PvP Conquest
    [278] = "contentPvP",       -- PVP Elite World Quest
    [288] = "contentDelve",     -- Delve
    [289] = "contentWorldBoss", -- World Boss
}

local function RetryKey(prefix, questID)
    return prefix .. ":" .. tostring(questID)
end

local function ResetQuestDataRetry(key)
    questDataRetryCounts[key] = nil
end

local function ScheduleQuestDataRetry(key, callback)
    local retryCount = (questDataRetryCounts[key] or 0) + 1

    if retryCount > MAX_QUEST_DATA_RETRIES then
        AQG:Debug("|cffff4444[!] Quest data not cached, retry limit reached.|r")
        return false
    end

    questDataRetryCounts[key] = retryCount
    AQG:Debug("|cffff4444[!] Quest data not cached, retrying "
        .. retryCount .. "/" .. MAX_QUEST_DATA_RETRIES .. "...|r")

    C_Timer.After(RETRY_TIME_DELAY, callback)

    return true
end

--------------------------------------------------------------------------------
-- Quest-Specific Safe Reads
--------------------------------------------------------------------------------

local function SafeQuestID(value)
    local questID = Safety:RequireNumber(value, "quest ID")

    if not questID or questID == 0 then
        return nil
    end

    return questID
end

local function DebugValue(value)
    if Safety:IsSecret(value) then
        return "secret"
    end

    return tostring(value)
end

function Decisions:IsSafeQuestID(value)
    return SafeQuestID(value) ~= nil
end

function Decisions:ClassifyQuest(questOrID)
    local quest = type(questOrID) == "table"
        and questOrID or { questID = questOrID }

    local questID = SafeQuestID(quest.questID)
    if not questID then
        return false, false, false, false, false
    end

    local frequency = Safety:OptionalNumber(quest.frequency, "quest frequency")
    local questIsDaily = QuestIsDaily and
        Safety:SafeBoolean(QuestIsDaily(), false) or false
    local questIsWeekly = QuestIsWeekly and
        Safety:SafeBoolean(QuestIsWeekly(), false) or false
    local isDaily = (frequency == 1)
        or questIsDaily
    local isWeekly = (frequency == 2)
        or questIsWeekly
    local isMetaQuest = Safety:SafeBoolean(quest.isMeta, false)
    local tagInfo = GetQuestTagInfo and GetQuestTagInfo(questID)

    if tagInfo then
        local worldQuestType =
            Safety:SafeBoolean(tagInfo.worldQuestType, false)
        local tagID = Safety:SafeNumber(tagInfo.tagID)

        if not isDaily and not isWeekly and worldQuestType then
            isDaily = true
        end

        if tagID == 284 then
            isMetaQuest = true
        end
    end

    local isRepeatable = IsRepeatableQuest and
        Safety:SafeBoolean(IsRepeatableQuest(questID), false) or false
    if questID and not isDaily and not isWeekly and
       isRepeatable then
        isDaily = true
    end

    local apiTrivial = IsQuestTrivial and
        Safety:SafeBoolean(IsQuestTrivial(questID), false) or false
    local isTrivialQuest = Safety:SafeBoolean(quest.isTrivial, false)
        or apiTrivial
    local isWarboundCompleted = QuestAccountComplete and
        Safety:SafeBoolean(QuestAccountComplete(questID), false) or false

    return isDaily, isWeekly, isTrivialQuest, isWarboundCompleted, isMetaQuest
end

function Decisions:GetContentFilterKey(questID)
    questID = SafeQuestID(questID)
    if not questID then return nil end

    local tagInfo = GetQuestTagInfo and GetQuestTagInfo(questID)

    local tagID = tagInfo and Safety:SafeNumber(tagInfo.tagID)
    if tagID then
        return CONTENT_TAG_MAP[tagID]
    end

    return nil
end

function Decisions:ShouldAllowContent(questID)
    if not SafeQuestID(questID) then
        AQG:Debug("Content Type: quest ID unsafe, disallowed by safety.")
        return false
    end

    local key = self:GetContentFilterKey(questID)

    if key then
        AQG:Debug("Content Type:", key,
            AutoQuestGossipDB[key] and "Allowed by settings."
                                   or "Disallowed by settings.")

        return AutoQuestGossipDB[key]
    end

    return true
end

function Decisions:ShouldAccept(questOrID)
    local quest = type(questOrID) == "table"
        and questOrID or { questID = questOrID }

    if not SafeQuestID(quest.questID) then
        AQG:Debug("Accept blocked: quest ID is unsafe.")
        return false
    end

    if not self:ShouldAllowContent(quest.questID) then return false end

    local db = AutoQuestGossipDB
    local daily, weekly, trivial, warbound, meta = self:ClassifyQuest(quest)

    if     meta then return db.acceptMeta end
    if    daily then return db.acceptDaily end
    if   weekly then return db.acceptWeekly end
    if  trivial then return db.acceptTrivial end
    if warbound then return db.acceptWarboundCompleted end

    return db.acceptRegular
end

function Decisions:ShouldTurnIn(questOrID)
    local quest = type(questOrID) == "table"
        and questOrID or { questID = questOrID }

    local questID = SafeQuestID(quest.questID)
    if not questID then
        AQG:Debug("Turn-in blocked: quest ID is unsafe.")
        return false
    end

    local title = Safety:OptionalString(GetTitle(questID))
    if title and title:find("Delver's Call:", 1, true) then
        return AutoQuestGossipDB.questTurnInDelve
    end

    return true
end

function Decisions:RequiredQuestItemBlocksTurnIn()
    local count = GetNumQuestItems and GetNumQuestItems() or 0

    for i = 1, count do
        local name, _, _, _, _, itemID = GetQuestItemInfo("required", i)
        local itemName, nameReason =
            Safety:OptionalString(name, "required item name")

        if nameReason then
            return true, "?", nameReason
        end

        if itemName and not Safety:IsSafeNumber(itemID) then
            return true, itemName, "required item ID is unsafe"
        end

        if itemName then
            local isReagent = select(17, C_Item.GetItemInfo(itemID))

            if Safety:IsSecret(isReagent) then
                return true, itemName, "required item reagent flag is secret"
            end

            if isReagent then
                return true, itemName, "quest requires crafting reagent"
            end
        end
    end

    return false
end

function Decisions:DebugQuestAPIs(questID)
    if not AutoQuestGossipDB.debugEnabled then return end
    AQG:Debug("  Raw APIs:")

    if QuestIsDaily then
        AQG:Debug("    QuestIsDaily() =", DebugValue(QuestIsDaily()))
    end

    if QuestIsWeekly then
        AQG:Debug("    QuestIsWeekly() =", DebugValue(QuestIsWeekly()))
    end

    questID = SafeQuestID(questID)

    if questID then
        if IsQuestTrivial then
            AQG:Debug("    IsQuestTrivial =", DebugValue(IsQuestTrivial(questID)))
        end

        if QuestAccountComplete then
            AQG:Debug("    WarboundCompleted =",
                DebugValue(QuestAccountComplete(questID)))
        end

        if IsRepeatableQuest then
            AQG:Debug("    IsRepeatable =", DebugValue(IsRepeatableQuest(questID)))
        end

        local tagInfo = GetQuestTagInfo and GetQuestTagInfo(questID)

        if tagInfo then
            AQG:Debug("    tagID =", DebugValue(tagInfo.tagID))
            AQG:Debug("    tagName =", DebugValue(tagInfo.tagName))
            AQG:Debug("    worldQuestType =", DebugValue(tagInfo.worldQuestType))

            local tagID = Safety:SafeNumber(tagInfo.tagID)
            local contentKey = tagID and CONTENT_TAG_MAP[tagID]
            if contentKey then
                AQG:Debug("    contentFilter =", contentKey)
            end
        else
            AQG:Debug("    tagInfo = nil")
        end
    else
        AQG:Debug("    questID = unsafe")
    end
end

--------------------------------------------------------------------------------
-- Decision Helpers
--------------------------------------------------------------------------------

local function Block(reason, blockers)
    return Safety:BlockDecision(reason, blockers)
end

local function NoAction(reason)
    return Safety:MakeDecision(false, nil, nil, reason or "no quest action")
end

local function Allow(action, questID, reason)
    return Safety:MakeDecision(true, action, questID, reason)
end

local function WithWarning(decision, warning)
    return Safety:AddDecisionWarning(decision, warning)
end

local function AddQuestMetadata(decision, quest)
    if not decision or not quest then return decision end

    decision.quest = quest
    decision.title = Safety:OptionalString(quest.title)
    decision.questType = Decisions:QuestType(quest)
    decision.label = Decisions:QuestLabel(quest)

    return decision
end

local function CheckQuestModuleEnabled()
    if not AutoQuestGossipDB or not AutoQuestGossipDB.questEnabled then
        return Block("quest automation disabled", "quest disabled")
    end

    return nil
end

local function CheckAcceptEnabled()
    if not AutoQuestGossipDB.questAcceptEnabled then
        return Block("quest accept disabled", "quest accept disabled")
    end

    return nil
end

local function CheckTurnInEnabled()
    if not AutoQuestGossipDB.questTurnInEnabled then
        return Block("quest turn-in disabled", "quest turn-in disabled")
    end

    return nil
end

local function CheckModifier()
    if Safety:CheckModifierPaused("Quest") then
        return Block("modifier key held", "modifier paused")
    end

    return nil
end

local function CheckNPCContext(npcContext)
    if not npcContext or not npcContext.safe then
        return Block("NPC identity unavailable or secret", "npc identity secret")
    end

    if npcContext.blocked then
        return Block(npcContext.blockReason or "NPC is blocked", "blocked NPC")
    end

    return nil
end

local function CheckCurrentNPC()
    return CheckNPCContext(Safety:BuildNPCContext("npc"))
end

local function CheckCommonQuestState(needsNPC)
    local block = CheckQuestModuleEnabled()
    if block then return block end

    if needsNPC then
        block = CheckCurrentNPC()
        if block then return block end
    end

    return CheckModifier()
end

local function CheckGossipSharedBlockers(context)
    local gossip = context and context.gossip or {}

    if gossip.unsafeOptionCount and gossip.unsafeOptionCount > 0 then
        return Block("gossip option data is unsafe", "unsafe gossip option")
    end

    if gossip.hasSkip then
        return WithWarning(
            Block("skip option detected", "skip option"),
            "Skip option detected - automation paused."
        )
    end

    if gossip.hasImportant then
        return WithWarning(
            Block("important option detected", "important option"),
            "Important selections detected - automation paused."
        )
    end

    if gossip.hasAngleBracket and AutoQuestGossipDB.pauseOnAngleBracket then
        return WithWarning(
            Block("angle bracket option detected", "angle bracket option"),
            "Angle bracket option detected - automation paused."
        )
    end

    return nil
end

local function ReadGoldCost()
    local value = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    local goldCost, reason = Safety:RequireNumber(value, "quest gold cost")

    if reason then
        return nil, reason
    end

    return goldCost, nil
end

local function ReadQuestChoiceCount()
    local value = GetNumQuestChoices and GetNumQuestChoices() or 0
    local numChoices, reason =
        Safety:RequireNumber(value, "quest reward choice count")

    if reason then
        return nil, reason
    end

    return numChoices, nil
end

local function ReadQuestCompletable()
    local value = IsQuestCompletable and IsQuestCompletable()
    local completable, reason =
        Safety:OptionalBoolean(value, "quest completable", false)

    if reason then
        return nil, reason
    end

    return completable, nil
end

local function ReadQuestPvP()
    local value = QuestFlagsPVP and QuestFlagsPVP()
    local isPvP, reason = Safety:OptionalBoolean(value, "quest PvP flag", false)

    if reason then
        return nil, reason
    end

    return isPvP, nil
end

local function ReadQuestAutoAccept()
    local value = QuestGetAutoAccept and QuestGetAutoAccept()
    local autoAccept, reason =
        Safety:OptionalBoolean(value, "quest auto-accept flag", false)

    if reason then
        return nil, reason
    end

    return autoAccept, nil
end

local function ReadRequiresCurrency()
    local value = GetNumQuestCurrencies and GetNumQuestCurrencies() or 0
    local count, reason = Safety:RequireNumber(value, "required currency count")

    if reason then
        return nil, reason
    end

    return count > 0, nil
end

local function BuildGreetingAvailableQuest(index)
    local isTrivial, frequency, repeatable, legendary, questID,
          important, meta, questInfoID = GetAvailableQuestInfo(index)
    local safeQuestID, reason =
        Safety:RequireNumber(questID, "available quest ID")

    if reason or safeQuestID == 0 then
        return nil, reason or "available quest ID is invalid"
    end

    local safeFrequency, frequencyReason =
        Safety:OptionalNumber(frequency, "available quest frequency")
    if frequencyReason then return nil, frequencyReason end

    local safeQuestInfoID, questInfoReason =
        Safety:OptionalNumber(questInfoID, "available quest info ID")
    if questInfoReason then return nil, questInfoReason end

    local safeIsTrivial, trivialReason =
        Safety:OptionalBoolean(isTrivial, "available quest trivial flag", false)
    if trivialReason then return nil, trivialReason end

    local safeRepeatable, repeatableReason =
        Safety:OptionalBoolean(repeatable, "available quest repeatable flag", false)
    if repeatableReason then return nil, repeatableReason end

    local safeLegendary, legendaryReason =
        Safety:OptionalBoolean(legendary, "available quest legendary flag", false)
    if legendaryReason then return nil, legendaryReason end

    local safeImportant, importantReason =
        Safety:OptionalBoolean(important, "available quest important flag", false)
    if importantReason then return nil, importantReason end

    local safeMeta, metaReason =
        Safety:OptionalBoolean(meta, "available quest meta flag", false)
    if metaReason then return nil, metaReason end

    return {
        questID = safeQuestID,
        title = Safety:SafeString(GetAvailableTitle(index), "?"),
        isTrivial = safeIsTrivial,
        frequency = safeFrequency,
        repeatable = safeRepeatable,
        isLegendary = safeLegendary,
        isImportant = safeImportant,
        isMeta = safeMeta,
        questInfoID = safeQuestInfoID,
    }, nil
end

local function BuildGreetingActiveQuest(index)
    local title, isComplete = GetActiveTitle(index)
    local questID = GetActiveQuestID and GetActiveQuestID(index)
    local safeQuestID, reason =
        Safety:RequireNumber(questID, "active quest ID")

    if reason or safeQuestID == 0 then
        return nil, reason or "active quest ID is invalid"
    end

    local safeIsComplete, completeReason =
        Safety:OptionalBoolean(isComplete, "active quest complete flag", false)
    if completeReason then return nil, completeReason end

    return {
        questID = safeQuestID,
        title = Safety:SafeString(title, "?"),
        isComplete = safeIsComplete,
    }, nil
end

--------------------------------------------------------------------------------
-- Quest Labels And Cache Checks
--------------------------------------------------------------------------------

function Decisions:QuestType(questOrID)
    local quest = type(questOrID) == "table"
        and questOrID or { questID = questOrID }

    if SafeQuestID(quest.questID) then
        local daily, weekly, trivial, warbound, meta =
            self:ClassifyQuest(quest)

        return meta     and "Meta" or
               daily    and "Daily" or
               weekly   and "Weekly" or
               trivial  and "Trivial" or
               warbound and "Warbound" or
                            "Regular"
    end

    if Safety:IsTrue(quest.isMeta) then return "Meta" end
    if Safety:IsSafeNumber(quest.frequency) and quest.frequency == 1 then
        return "Daily"
    end
    if Safety:IsSafeNumber(quest.frequency) and quest.frequency == 2 then
        return "Weekly"
    end
    if Safety:IsTrue(quest.isTrivial) then return "Trivial" end

    return "Unknown"
end

function Decisions:QuestTitle(questID)
    return Safety:OptionalString(GetTitleText and GetTitleText())
        or (SafeQuestID(questID) and Safety:OptionalString(GetTitle(questID)))
        or "?"
end

function Decisions:QuestLabel(quest)
    quest = type(quest) == "table" and quest or { questID = quest }

    local questID = quest.questID
    local title = Safety:OptionalString(quest.title)

    if not title and SafeQuestID(questID) then
        title = Safety:OptionalString(GetTitle(questID))
    end

    local idText = SafeQuestID(questID) and tostring(questID) or "?"

    return (title or "?") .. " (ID: " .. idText
        .. " | Type: " .. self:QuestType(quest) .. ")"
end

function Decisions:IsQuestDataReady(questID, funcToRetry)
    if not SafeQuestID(questID) then
        return false
    end

    local retryKey = RetryKey("quest", questID)

    if Safety:OptionalString(GetTitle(questID)) then
        ResetQuestDataRetry(retryKey)
        return true
    end

    if funcToRetry then
        ScheduleQuestDataRetry(retryKey, function()
            funcToRetry(questID)
        end)
    end

    return false
end

function Decisions:AreContextQuestsCached(quests, funcToRetry)
    for _, quest in ipairs(quests or {}) do
        local questID = quest and quest.questID

        if quest and quest.safe and SafeQuestID(questID) and
           not Safety:OptionalString(GetTitle(questID)) then
            local retryKey = RetryKey("context", questID)

            if funcToRetry then
                ScheduleQuestDataRetry(retryKey, funcToRetry)
            end

            return false
        end

        if quest and quest.safe and SafeQuestID(questID) then
            ResetQuestDataRetry(RetryKey("context", questID))
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- Decision Entry Points
--------------------------------------------------------------------------------

function Decisions:DecideGossipQuestAction(context)
    local block = CheckQuestModuleEnabled()
    if block then return block end

    block = CheckNPCContext(context and context.npc)
    if block then return block end

    block = CheckModifier()
    if block then return block end

    block = CheckGossipSharedBlockers(context)
    if block then return block end

    local quests = context and context.quests or {}
    if quests.unsafeQuestCount and quests.unsafeQuestCount > 0 then
        return Block("quest data contains unsafe fields", "unsafe quest data")
    end

    if AutoQuestGossipDB.questTurnInEnabled then
        for _, quest in ipairs(quests.active or {}) do
            if quest.isComplete then
                if not quest.safe or not SafeQuestID(quest.questID) then
                    return Block("complete quest ID is unsafe", "unsafe quest ID")
                end

                if self:ShouldTurnIn(quest) then
                    local decision = Allow(
                        ACTIONS.GOSSIP_TURN_IN,
                        quest.questID,
                        "completed gossip quest"
                    )
                    return AddQuestMetadata(decision, quest)
                end
            end
        end
    end

    if AutoQuestGossipDB.questAcceptEnabled then
        for _, quest in ipairs(quests.available or {}) do
            if not quest.safe or not SafeQuestID(quest.questID) then
                return Block("available quest ID is unsafe", "unsafe quest ID")
            end

            if self:ShouldAccept(quest) then
                local decision = Allow(
                    ACTIONS.GOSSIP_ACCEPT,
                    quest.questID,
                    "allowed available gossip quest"
                )
                return AddQuestMetadata(decision, quest)
            end
        end
    end

    return NoAction("no eligible gossip quest action")
end

function Decisions:DecideQuestGreetingAction()
    local block = CheckCommonQuestState(true)
    if block then return block end

    if AutoQuestGossipDB.questTurnInEnabled then
        for index = 1, GetNumActiveQuests() do
            local quest, reason = BuildGreetingActiveQuest(index)

            if reason then
                return Block(reason, "unsafe active quest")
            end

            if quest.isComplete and self:ShouldTurnIn(quest) then
                local decision = Allow(
                    ACTIONS.GREETING_TURN_IN,
                    quest.questID,
                    "completed quest greeting quest"
                )
                decision.index = index

                return AddQuestMetadata(decision, quest)
            end
        end
    end

    if AutoQuestGossipDB.questAcceptEnabled then
        for index = 1, GetNumAvailableQuests() do
            local quest, reason = BuildGreetingAvailableQuest(index)

            if reason then
                return Block(reason, "unsafe available quest")
            end

            if self:ShouldAccept(quest) then
                local decision = Allow(
                    ACTIONS.GREETING_ACCEPT,
                    quest.questID,
                    "allowed quest greeting quest"
                )
                decision.index = index

                return AddQuestMetadata(decision, quest)
            end
        end
    end

    return NoAction("no eligible quest greeting action")
end

function Decisions:DecideQuestAcceptConfirmAction(playerName, questTitle, questID)
    local block = CheckQuestModuleEnabled()
    if block then return block end

    block = CheckAcceptEnabled()
    if block then return block end

    block = CheckModifier()
    if block then return block end

    local safeQuestID, reason =
        Safety:RequireNumber(questID, "shared quest ID")
    if reason or safeQuestID == 0 then
        return Block(reason or "shared quest ID is invalid", "unsafe quest ID")
    end

    local quest = {
        questID = safeQuestID,
        title = Safety:SafeString(questTitle, "?"),
        playerName = Safety:SafeString(playerName, "?"),
    }

    if not self:ShouldAccept(quest) then
        return AddQuestMetadata(
            Block("shared quest blocked by accept filters", "accept filter"),
            quest
        )
    end

    local decision = Allow(
        ACTIONS.ACCEPT_CONFIRM,
        safeQuestID,
        "allowed shared quest"
    )
    decision.playerName = quest.playerName

    return AddQuestMetadata(decision, quest)
end

function Decisions:DecideQuestDetailAction(questID)
    local block = CheckCommonQuestState(true)
    if block then return block end

    block = CheckAcceptEnabled()
    if block then return block end

    local safeQuestID, reason =
        Safety:RequireNumber(questID, "quest detail ID")
    if reason or safeQuestID == 0 then
        return Block(reason or "quest detail ID is invalid", "unsafe quest ID")
    end

    local isPvP, pvpReason = ReadQuestPvP()
    if pvpReason then
        return Block(pvpReason, "unsafe PvP flag")
    end
    if isPvP then
        return Block("PvP quest accept requires manual confirmation", "PvP quest")
    end

    local goldCost, goldReason = ReadGoldCost()
    if goldReason then
        return Block(goldReason, "unsafe gold cost")
    end
    if goldCost > 0 then
        return Block("quest requires gold", "gold cost")
    end

    local quest = {
        questID = safeQuestID,
        title = self:QuestTitle(safeQuestID),
    }

    if not self:ShouldAccept(quest) then
        return AddQuestMetadata(
            Block("quest blocked by accept filters", "accept filter"),
            quest
        )
    end

    local autoAccept, autoReason = ReadQuestAutoAccept()
    if autoReason then
        return Block(autoReason, "unsafe auto-accept flag")
    end

    local action = autoAccept
        and ACTIONS.QUEST_DETAIL_ACK_AUTO_ACCEPT
        or ACTIONS.QUEST_DETAIL_ACCEPT
    local decision = Allow(action, safeQuestID, "allowed quest detail")
    decision.goldCost = goldCost
    decision.autoAccept = autoAccept

    return AddQuestMetadata(decision, quest)
end

function Decisions:DecideQuestProgressAction(questID)
    local block = CheckCommonQuestState(true)
    if block then return block end

    block = CheckTurnInEnabled()
    if block then return block end

    local safeQuestID, reason =
        Safety:RequireNumber(questID, "quest progress ID")
    if reason or safeQuestID == 0 then
        return Block(reason or "quest progress ID is invalid", "unsafe quest ID")
    end

    local quest = {
        questID = safeQuestID,
        title = self:QuestTitle(safeQuestID),
    }

    if not self:ShouldTurnIn(quest) then
        return AddQuestMetadata(
            Block("quest blocked by turn-in filters", "turn-in filter"),
            quest
        )
    end

    local completable, completeReason = ReadQuestCompletable()
    if completeReason then
        return Block(completeReason, "unsafe complete flag")
    end
    if not completable then
        return AddQuestMetadata(
            Block("quest is not completable", "not completable"),
            quest
        )
    end

    local goldCost, goldReason = ReadGoldCost()
    if goldReason then
        return Block(goldReason, "unsafe gold cost")
    end
    if goldCost > 0 then
        return AddQuestMetadata(Block("quest requires gold", "gold cost"), quest)
    end

    local requiresCurrency, currencyReason = ReadRequiresCurrency()
    if currencyReason then
        return Block(currencyReason, "unsafe currency count")
    end
    if requiresCurrency then
        return AddQuestMetadata(
            Block("quest requires currency", "required currency"),
            quest
        )
    end

    local blocksRequiredItem, itemName, itemReason =
        self:RequiredQuestItemBlocksTurnIn()
    if blocksRequiredItem then
        local decision = AddQuestMetadata(
            Block(itemReason, "required item"),
            quest
        )
        decision.requiredItemName = Safety:SafeString(itemName, "?")

        return decision
    end

    local decision = Allow(
        ACTIONS.QUEST_PROGRESS_COMPLETE,
        safeQuestID,
        "quest is ready for reward step"
    )
    decision.goldCost = goldCost

    return AddQuestMetadata(decision, quest)
end

function Decisions:DecideQuestCompleteAction(questID)
    local block = CheckCommonQuestState(true)
    if block then return block end

    block = CheckTurnInEnabled()
    if block then return block end

    local safeQuestID, reason =
        Safety:RequireNumber(questID, "quest complete ID")
    if reason or safeQuestID == 0 then
        return Block(reason or "quest complete ID is invalid", "unsafe quest ID")
    end

    local quest = {
        questID = safeQuestID,
        title = self:QuestTitle(safeQuestID),
    }

    if not self:ShouldTurnIn(quest) then
        return AddQuestMetadata(
            Block("quest blocked by turn-in filters", "turn-in filter"),
            quest
        )
    end

    local numChoices, choiceReason = ReadQuestChoiceCount()
    if choiceReason then
        return Block(choiceReason, "unsafe reward choice count")
    end

    local goldCost, goldReason = ReadGoldCost()
    if goldReason then
        return Block(goldReason, "unsafe gold cost")
    end
    if goldCost > 0 then
        return AddQuestMetadata(Block("quest requires gold", "gold cost"), quest)
    end

    if numChoices > 1 then
        local decision = AddQuestMetadata(
            Block("quest has multiple reward choices", "multiple rewards"),
            quest
        )
        decision.numChoices = numChoices

        return decision
    end

    local decision = Allow(
        ACTIONS.QUEST_COMPLETE_REWARD,
        safeQuestID,
        "quest can complete without reward choice"
    )
    decision.numChoices = numChoices
    decision.goldCost = goldCost

    return AddQuestMetadata(decision, quest)
end

function Decisions:DecideQuestAutocompleteAction(questID)
    local block = CheckQuestModuleEnabled()
    if block then return block end

    block = CheckTurnInEnabled()
    if block then return block end

    block = CheckModifier()
    if block then return block end

    local safeQuestID, reason =
        Safety:RequireNumber(questID, "autocomplete quest ID")
    if reason or safeQuestID == 0 then
        return Block(reason or "autocomplete quest ID is invalid", "unsafe quest ID")
    end

    local quest = {
        questID = safeQuestID,
    }

    if not self:ShouldTurnIn(quest) then
        return AddQuestMetadata(
            Block("quest blocked by turn-in filters", "turn-in filter"),
            quest
        )
    end

    local index = GetLogIndexForQuestID(safeQuestID)
    local safeIndex, indexReason = Safety:RequireNumber(index, "quest log index")
    if indexReason then
        return Block(indexReason, "missing quest log entry")
    end

    local info = GetInfo(safeIndex)
    if type(info) ~= "table" then
        return Block("quest log info is unavailable", "missing quest info")
    end

    local isAutoComplete, autoCompleteReason =
        Safety:OptionalBoolean(info.isAutoComplete, "autocomplete flag", false)
    if autoCompleteReason then
        return Block(autoCompleteReason, "unsafe autocomplete flag")
    end
    if not isAutoComplete then
        return NoAction("quest is not auto-complete")
    end

    quest.title = Safety:SafeString(info.title, self:QuestTitle(safeQuestID))

    local decision = Allow(
        ACTIONS.QUEST_AUTOCOMPLETE_SHOW,
        safeQuestID,
        "quest can open autocomplete dialog"
    )
    decision.logIndex = safeIndex

    return AddQuestMetadata(decision, quest)
end
