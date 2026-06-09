local _, AQG = ...

AQG.Quest = AQG.Quest or {}
local Quest = AQG.Quest
local Decisions = AQG.QuestDecisions
local Safety = AQG.Safety
local ACTIONS = Decisions.Actions

local SetSelectedQuest = C_QuestLog.SetSelectedQuest
local GetInfo = C_QuestLog.GetInfo
local GetLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID

--------------------------------------------------------------------------------
-- Debug And Execution Guards
--------------------------------------------------------------------------------

local function DebugDecision(eventName, decision)
    if not AutoQuestGossipDB or not AutoQuestGossipDB.debugEnabled then
        return
    end

    AQG:DebugSeparator(eventName)
    Safety:DebugDecision("Quest", decision)

    if decision and Decisions:IsSafeQuestID(decision.targetID) then
        AQG:DebugQuestAPIs(decision.targetID)
    end
end

local function WarnDecision(decision)
    if decision and decision.warnText then
        AQG:Warn(decision.warnText)
    end
end

local function CanExecuteDecision(decision)
    if not decision or not decision.allowed then
        WarnDecision(decision)
        return false
    end

    if Safety:CheckModifierPaused("Quest") then
        return false
    end

    if Safety:CheckDevMode() then
        return false
    end

    return true
end

local function DebugRevalidationFailed(reason)
    AQG:Debug("-> Revalidation failed:", reason or "unknown")
end

local function QuestLabel(decision)
    return decision and decision.label or "?"
end

local function MakeGossipQuestResult(decision, executed, pending)
    return {
        decision = decision,
        executed = executed and true or false,
        pending = pending and true or false,
        selected = decision and decision.allowed or false,
    }
end

--------------------------------------------------------------------------------
-- Safe Current-State Reads
--------------------------------------------------------------------------------

local function ReadCurrentGoldCost()
    local value = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0

    if not Safety:IsSafeNumber(value) then
        return nil, "quest gold cost is unsafe"
    end

    return value, nil
end

local function ReadCurrentRewardChoiceCount()
    local value = GetNumQuestChoices and GetNumQuestChoices() or 0

    if not Safety:IsSafeNumber(value) then
        return nil, "reward choice count is unsafe"
    end

    return value, nil
end

local function ReadCurrentCompletable()
    local value = IsQuestCompletable and IsQuestCompletable()

    if Safety:IsSecret(value) then
        return nil, "quest completable flag is secret"
    end

    return value and true or false, nil
end

local function ReadCurrentPvPFlag()
    local value = QuestFlagsPVP and QuestFlagsPVP()

    if Safety:IsSecret(value) then
        return nil, "quest PvP flag is secret"
    end

    return value and true or false, nil
end

local function ReadCurrentAutoAcceptFlag()
    local value = QuestGetAutoAccept and QuestGetAutoAccept()

    if Safety:IsSecret(value) then
        return nil, "quest auto-accept flag is secret"
    end

    return value and true or false, nil
end

local function ReadCurrentRequiresCurrency()
    local value = GetNumQuestCurrencies and GetNumQuestCurrencies() or 0

    if not Safety:IsSafeNumber(value) then
        return nil, "required currency count is unsafe"
    end

    return value > 0, nil
end

--------------------------------------------------------------------------------
-- Gossip Quest Execution
--------------------------------------------------------------------------------

local function FindCurrentGossipQuest(source, questID)
    if not Decisions:IsSafeQuestID(questID) then
        return nil, "invalid quest ID"
    end

    local quests
    if source == "active" then
        quests = C_GossipInfo.GetActiveQuests()
    else
        quests = C_GossipInfo.GetAvailableQuests()
    end

    for _, quest in ipairs(quests or {}) do
        local currentQuestID = quest and quest.questID

        if Safety:IsSecret(currentQuestID) then
            return nil, "current gossip quest ID is secret"
        end

        if Safety:IsSafeNumber(currentQuestID) and currentQuestID == questID then
            return quest, nil
        end
    end

    return nil, "quest is no longer available from gossip"
end

local function ExecuteGossipQuestDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    if decision.action == ACTIONS.GOSSIP_TURN_IN then
        local currentQuest, reason =
            FindCurrentGossipQuest("active", decision.targetID)
        if not currentQuest then
            DebugRevalidationFailed(reason)
            return false
        end

        local isComplete = currentQuest.isComplete
        if Safety:IsSecret(isComplete) or type(isComplete) ~= "boolean" then
            DebugRevalidationFailed("quest complete flag is unsafe")
            return false
        end

        if not isComplete then
            DebugRevalidationFailed("quest is no longer complete")
            return false
        end

        if not AQG:ShouldTurnIn(decision.quest or decision.targetID) then
            DebugRevalidationFailed("quest no longer passes turn-in filters")
            return false
        end

        AQG:Verbose("Turn-in:", QuestLabel(decision))
        AQG:Debug("Auto turn-in:", QuestLabel(decision))
        C_GossipInfo.SelectActiveQuest(decision.targetID)

        return true
    end

    if decision.action == ACTIONS.GOSSIP_ACCEPT then
        local currentQuest, reason =
            FindCurrentGossipQuest("available", decision.targetID)
        if not currentQuest then
            DebugRevalidationFailed(reason)
            return false
        end

        if not AQG:ShouldAccept(decision.quest or decision.targetID) then
            DebugRevalidationFailed("quest no longer passes accept filters")
            return false
        end

        AQG:Verbose("Accept:", QuestLabel(decision))
        AQG:Debug("Auto-accept:", QuestLabel(decision))
        C_GossipInfo.SelectAvailableQuest(decision.targetID)

        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- Quest Greeting Execution
--------------------------------------------------------------------------------

local function ValidateGreetingTurnIn(decision)
    local index = decision.index
    if not Safety:IsSafeNumber(index) then
        return false, "quest greeting index is invalid"
    end

    local currentQuestID = GetActiveQuestID and GetActiveQuestID(index)
    if not Safety:IsSafeNumber(currentQuestID) or
       currentQuestID ~= decision.targetID then
        return false, "active quest changed"
    end

    local _title, isComplete = GetActiveTitle(index)
    if Safety:IsSecret(isComplete) or type(isComplete) ~= "boolean" then
        return false, "active quest complete flag is unsafe"
    end

    if not isComplete then
        return false, "active quest is no longer complete"
    end

    if not AQG:ShouldTurnIn(decision.quest or decision.targetID) then
        return false, "quest no longer passes turn-in filters"
    end

    return true, nil
end

local function ValidateGreetingAccept(decision)
    local index = decision.index
    if not Safety:IsSafeNumber(index) then
        return false, "quest greeting index is invalid"
    end

    local _isTrivial, _frequency, _repeatable, _legendary, questID =
        GetAvailableQuestInfo(index)
    if not Safety:IsSafeNumber(questID) or questID ~= decision.targetID then
        return false, "available quest changed"
    end

    if not AQG:ShouldAccept(decision.quest or decision.targetID) then
        return false, "quest no longer passes accept filters"
    end

    return true, nil
end

local function ExecuteQuestGreetingDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    if decision.action == ACTIONS.GREETING_TURN_IN then
        local ok, reason = ValidateGreetingTurnIn(decision)
        if not ok then
            DebugRevalidationFailed(reason)
            return false
        end

        AQG:Verbose("Turn-in:", QuestLabel(decision))
        AQG:Debug("Auto turn-in:", QuestLabel(decision))
        SelectActiveQuest(decision.index)

        return true
    end

    if decision.action == ACTIONS.GREETING_ACCEPT then
        local ok, reason = ValidateGreetingAccept(decision)
        if not ok then
            DebugRevalidationFailed(reason)
            return false
        end

        AQG:Verbose("Accept:", QuestLabel(decision))
        AQG:Debug("Auto-accept:", QuestLabel(decision))
        SelectAvailableQuest(decision.index)

        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- Direct Quest Frame Execution
--------------------------------------------------------------------------------

local function ValidateCurrentQuest(decision)
    local ok, reason = Safety:ValidateCurrentQuest(decision.targetID)
    if not ok then
        return false, reason
    end

    return true, nil
end

local function ExecuteQuestAcceptConfirmDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    if not AQG:ShouldAccept(decision.quest or decision.targetID) then
        DebugRevalidationFailed("quest no longer passes accept filters")
        return false
    end

    AQG:Verbose("Confirm:", QuestLabel(decision))
    AQG:Debug("Auto-confirm shared quest:", QuestLabel(decision))
    ConfirmAcceptQuest()

    return true
end

local function ExecuteQuestDetailDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    local ok, reason = ValidateCurrentQuest(decision)
    if not ok then
        DebugRevalidationFailed(reason)
        return false
    end

    local isPvP, pvpReason = ReadCurrentPvPFlag()
    if pvpReason then
        DebugRevalidationFailed(pvpReason)
        return false
    end
    if isPvP then
        DebugRevalidationFailed("PvP quest accept requires manual confirmation")
        return false
    end

    local goldCost, goldReason = ReadCurrentGoldCost()
    if goldReason then
        DebugRevalidationFailed(goldReason)
        return false
    end
    if goldCost > 0 then
        DebugRevalidationFailed("quest now requires gold")
        return false
    end

    if not AQG:ShouldAccept(decision.quest or decision.targetID) then
        DebugRevalidationFailed("quest no longer passes accept filters")
        return false
    end

    local autoAccept, autoReason = ReadCurrentAutoAcceptFlag()
    if autoReason then
        DebugRevalidationFailed(autoReason)
        return false
    end

    AQG:Verbose("Accept:", QuestLabel(decision))
    AQG:Debug("Auto-accept:", QuestLabel(decision))

    if autoAccept then
        AcknowledgeAutoAcceptQuest()
    else
        AcceptQuest()
    end

    return true
end

local function ExecuteQuestProgressDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    local ok, reason = ValidateCurrentQuest(decision)
    if not ok then
        DebugRevalidationFailed(reason)
        return false
    end

    if not AQG:ShouldTurnIn(decision.quest or decision.targetID) then
        DebugRevalidationFailed("quest no longer passes turn-in filters")
        return false
    end

    local completable, completeReason = ReadCurrentCompletable()
    if completeReason then
        DebugRevalidationFailed(completeReason)
        return false
    end
    if not completable then
        DebugRevalidationFailed("quest is no longer completable")
        return false
    end

    local goldCost, goldReason = ReadCurrentGoldCost()
    if goldReason then
        DebugRevalidationFailed(goldReason)
        return false
    end
    if goldCost > 0 then
        DebugRevalidationFailed("quest now requires gold")
        return false
    end

    local requiresCurrency, currencyReason = ReadCurrentRequiresCurrency()
    if currencyReason then
        DebugRevalidationFailed(currencyReason)
        return false
    end
    if requiresCurrency then
        DebugRevalidationFailed("quest now requires currency")
        return false
    end

    local requiresReagent = AQG:QuestItemIsReagent()
    if requiresReagent then
        DebugRevalidationFailed("quest now requires a crafting reagent")
        return false
    end

    AQG:Verbose("Turn-in:", QuestLabel(decision))
    AQG:Debug("Auto turn-in (progress):", QuestLabel(decision))
    CompleteQuest()

    return true
end

local function ExecuteQuestCompleteDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    local ok, reason = ValidateCurrentQuest(decision)
    if not ok then
        DebugRevalidationFailed(reason)
        return false
    end

    if not AQG:ShouldTurnIn(decision.quest or decision.targetID) then
        DebugRevalidationFailed("quest no longer passes turn-in filters")
        return false
    end

    local goldCost, goldReason = ReadCurrentGoldCost()
    if goldReason then
        DebugRevalidationFailed(goldReason)
        return false
    end
    if goldCost > 0 then
        DebugRevalidationFailed("quest now requires gold")
        return false
    end

    local numChoices, choiceReason = ReadCurrentRewardChoiceCount()
    if choiceReason then
        DebugRevalidationFailed(choiceReason)
        return false
    end
    if numChoices > 1 then
        DebugRevalidationFailed("quest now has multiple reward choices")
        return false
    end

    AQG:Verbose("Complete:", QuestLabel(decision))
    AQG:Debug("Auto turn-in (complete):", QuestLabel(decision))
    GetQuestReward(numChoices)

    return true
end

local function ExecuteQuestAutocompleteDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    if not AQG:ShouldTurnIn(decision.quest or decision.targetID) then
        DebugRevalidationFailed("quest no longer passes turn-in filters")
        return false
    end

    local index = GetLogIndexForQuestID(decision.targetID)
    if not Safety:IsSafeNumber(index) then
        DebugRevalidationFailed("quest log entry is no longer available")
        return false
    end

    local info = GetInfo(index)
    if type(info) ~= "table" then
        DebugRevalidationFailed("quest log info is no longer available")
        return false
    end

    local isAutoComplete = info.isAutoComplete
    if Safety:IsSecret(isAutoComplete) or type(isAutoComplete) ~= "boolean" then
        DebugRevalidationFailed("autocomplete flag is unsafe")
        return false
    end

    if not isAutoComplete then
        DebugRevalidationFailed("quest is no longer auto-complete")
        return false
    end

    AQG:Verbose("Auto-complete:", QuestLabel(decision))
    AQG:Debug("Auto-complete (tracker):", QuestLabel(decision))
    SetSelectedQuest(decision.targetID)
    ShowQuestComplete(decision.targetID)

    return true
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

function Quest:HandleGossipShow(context, retryFunc)
    local quests = context and context.quests or {}
    local activeQuests = quests.active or {}
    local availableQuests = quests.available or {}
    local gossip = context and context.gossip or {}
    local npc = context and context.npc or {}
    local shouldWaitForCache =
        AutoQuestGossipDB and
        AutoQuestGossipDB.questEnabled and
        npc.safe and
        not npc.blocked and
        not gossip.hasSkip and
        not gossip.hasImportant and
        not (gossip.hasAngleBracket and AutoQuestGossipDB.pauseOnAngleBracket) and
        not ((gossip.unsafeOptionCount or 0) > 0)

    if shouldWaitForCache then
        if not Decisions:AreContextQuestsCached(activeQuests, retryFunc) then
            return MakeGossipQuestResult(nil, false, true)
        end

        if not quests.hasCompletable and
           not Decisions:AreContextQuestsCached(availableQuests, retryFunc) then
            return MakeGossipQuestResult(nil, false, true)
        end
    end

    local decision = Decisions:DecideGossipQuestAction(context)
    DebugDecision("GOSSIP_SHOW (Quest)", decision)

    return MakeGossipQuestResult(
        decision,
        ExecuteGossipQuestDecision(decision),
        false
    )
end

local function OnQuestGreeting()
    local decision = Decisions:DecideQuestGreetingAction()
    DebugDecision("QUEST_GREETING", decision)
    ExecuteQuestGreetingDecision(decision)
end

AQG:RegisterEvent("QUEST_GREETING", OnQuestGreeting)

local function OnQuestAcceptConfirm(playerName, questTitle, questID)
    local decision =
        Decisions:DecideQuestAcceptConfirmAction(playerName, questTitle, questID)
    DebugDecision("QUEST_ACCEPT_CONFIRM", decision)
    ExecuteQuestAcceptConfirmDecision(decision)
end

AQG:RegisterEvent("QUEST_ACCEPT_CONFIRM", OnQuestAcceptConfirm)

local function OnQuestDetail(questID)
    questID = questID or GetQuestID()

    if Decisions:IsSafeQuestID(questID) and
       not Decisions:IsQuestDataReady(questID, OnQuestDetail) then
        return
    end

    local decision = Decisions:DecideQuestDetailAction(questID)
    DebugDecision("QUEST_DETAIL", decision)
    ExecuteQuestDetailDecision(decision)
end

-- QUEST_DETAIL passes questStartItemID, not questID.
AQG:RegisterEvent("QUEST_DETAIL", function()
    OnQuestDetail()
end)

local function OnQuestProgress(questID)
    questID = questID or GetQuestID()

    if Decisions:IsSafeQuestID(questID) and
       not Decisions:IsQuestDataReady(questID, OnQuestProgress) then
        return
    end

    local decision = Decisions:DecideQuestProgressAction(questID)
    DebugDecision("QUEST_PROGRESS", decision)
    ExecuteQuestProgressDecision(decision)
end

AQG:RegisterEvent("QUEST_PROGRESS", OnQuestProgress)

local function OnQuestComplete(questID)
    questID = questID or GetQuestID()

    if Decisions:IsSafeQuestID(questID) and
       not Decisions:IsQuestDataReady(questID, OnQuestComplete) then
        return
    end

    local decision = Decisions:DecideQuestCompleteAction(questID)
    DebugDecision("QUEST_COMPLETE", decision)
    ExecuteQuestCompleteDecision(decision)
end

AQG:RegisterEvent("QUEST_COMPLETE", OnQuestComplete)

local function OnQuestAutocomplete(questID)
    if Decisions:IsSafeQuestID(questID) and
       not Decisions:IsQuestDataReady(questID, OnQuestAutocomplete) then
        return
    end

    local decision = Decisions:DecideQuestAutocompleteAction(questID)
    DebugDecision("QUEST_AUTOCOMPLETE", decision)
    ExecuteQuestAutocompleteDecision(decision)
end

AQG:RegisterEvent("QUEST_AUTOCOMPLETE", OnQuestAutocomplete)
