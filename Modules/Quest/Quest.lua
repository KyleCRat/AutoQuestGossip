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

local function DebugQuestDecisionDetails(decision)
    if decision and Decisions:IsSafeQuestID(decision.targetID) then
        Decisions:DebugQuestAPIs(decision.targetID)
    end
end

local function DebugDecision(eventName, decision, options)
    Safety:DebugDecisionEvent(
        eventName,
        "Quest",
        decision,
        DebugQuestDecisionDetails,
        options
    )
end

local function CanExecuteDecision(decision)
    if not decision or not decision.allowed then
        Safety:WarnDecision(decision)
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
    Safety:DebugRevalidationFailed(reason)
end

local function QuestLabel(decision)
    return decision and decision.label or "?"
end

local function DebugExecution(decision)
    Safety:DebugDecisionExecution("Quest", decision, QuestLabel(decision))
end

local function SameQuestDecision(expected, current)
    if not expected or not current then return false end
    if expected.action ~= current.action then return false end

    return Safety:IsSafeNumber(expected.targetID) and
        Safety:IsSafeNumber(current.targetID) and
        expected.targetID == current.targetID
end

local function RevalidateDecision(decision, decideFunc)
    local currentDecision = decideFunc()

    if not currentDecision or not currentDecision.allowed then
        return nil, currentDecision and currentDecision.reason
            or "Could not confirm the quest action before acting."
    end

    if not SameQuestDecision(decision, currentDecision) then
        return nil, "The quest action changed before acting."
    end

    return currentDecision, nil
end

local function RevalidateForAction(decision, decideFunc)
    local currentDecision, reason = RevalidateDecision(decision, decideFunc)

    if not currentDecision then
        DebugRevalidationFailed(reason)
        return nil
    end

    if not CanExecuteDecision(currentDecision) then
        return nil
    end

    return currentDecision
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
        return nil, "Cannot safely read the quest gold cost."
    end

    return value, nil
end

local function ReadCurrentRewardChoiceCount()
    local value = GetNumQuestChoices and GetNumQuestChoices() or 0

    if not Safety:IsSafeNumber(value) then
        return nil, "Cannot safely read the reward choice count."
    end

    return value, nil
end

local function ReadCurrentCompletable()
    local value = IsQuestCompletable and IsQuestCompletable()

    if Safety:IsSecret(value) then
        return nil, "Cannot safely check whether this quest is complete."
    end

    return value and true or false, nil
end

local function ReadCurrentPvPFlag()
    local value = QuestFlagsPVP and QuestFlagsPVP()

    if Safety:IsSecret(value) then
        return nil, "Cannot safely check whether this quest flags you for PvP."
    end

    return value and true or false, nil
end

local function ReadCurrentAutoAcceptFlag()
    local value = QuestGetAutoAccept and QuestGetAutoAccept()

    if Safety:IsSecret(value) then
        return nil, "Cannot safely check this quest's auto-accept state."
    end

    return value and true or false, nil
end

local function ReadCurrentRequiresCurrency()
    local value = GetNumQuestCurrencies and GetNumQuestCurrencies() or 0

    if not Safety:IsSafeNumber(value) then
        return nil, "Cannot safely read the required currency count."
    end

    return value > 0, nil
end

--------------------------------------------------------------------------------
-- Gossip Quest Execution
--------------------------------------------------------------------------------

local function FindCurrentGossipQuest(source, questID)
    if not Decisions:IsSafeQuestID(questID) then
        return nil, "Cannot safely identify this quest."
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

    decision = RevalidateForAction(decision, function()
        local context = AQG.InteractionContext:Build("GOSSIP_QUEST_REVALIDATE")
        return Decisions:DecideGossipQuestAction(context)
    end)
    if not decision then
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
            DebugRevalidationFailed("Cannot safely check whether this quest is complete.")
            return false
        end

        if not isComplete then
            DebugRevalidationFailed("This quest is no longer complete.")
            return false
        end

        local shouldTurnIn, turnInReason =
            Decisions:ShouldTurnIn(decision.quest or decision.targetID)
        if not shouldTurnIn then
            DebugRevalidationFailed(turnInReason
                or "This quest turn-in is blocked by your AQG settings.")
            return false
        end

        AQG:Verbose("Turn-in:", QuestLabel(decision))
        DebugExecution(decision)
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

        local shouldAccept, acceptReason =
            Decisions:ShouldAccept(decision.quest or decision.targetID)
        if not shouldAccept then
            DebugRevalidationFailed(acceptReason
                or "This quest is blocked by your AQG settings.")
            return false
        end

        AQG:Verbose("Accept:", QuestLabel(decision))
        DebugExecution(decision)
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
        return false, "Cannot safely identify this quest greeting option."
    end

    local currentQuestID = GetActiveQuestID and GetActiveQuestID(index)
    if not Safety:IsSafeNumber(currentQuestID) or
       currentQuestID ~= decision.targetID then
        return false, "The active quest changed before acting."
    end

    local _title, isComplete = GetActiveTitle(index)
    if Safety:IsSecret(isComplete) or type(isComplete) ~= "boolean" then
        return false, "Cannot safely check whether the active quest is complete."
    end

    if not isComplete then
        return false, "The active quest is no longer complete."
    end

    local shouldTurnIn, turnInReason =
        Decisions:ShouldTurnIn(decision.quest or decision.targetID)
    if not shouldTurnIn then
        return false, turnInReason or
            "This quest turn-in is blocked by your AQG settings."
    end

    return true, nil
end

local function ValidateGreetingAccept(decision)
    local index = decision.index
    if not Safety:IsSafeNumber(index) then
        return false, "Cannot safely identify this quest greeting option."
    end

    local _isTrivial, _frequency, _repeatable, _legendary, questID =
        GetAvailableQuestInfo(index)
    if not Safety:IsSafeNumber(questID) or questID ~= decision.targetID then
        return false, "The available quest changed before acting."
    end

    local shouldAccept, acceptReason =
        Decisions:ShouldAccept(decision.quest or decision.targetID)
    if not shouldAccept then
        return false, acceptReason or
            "This quest is blocked by your AQG settings."
    end

    return true, nil
end

local function ExecuteQuestGreetingDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    decision = RevalidateForAction(decision, function()
        return Decisions:DecideQuestGreetingAction()
    end)
    if not decision then
        return false
    end

    if decision.action == ACTIONS.GREETING_TURN_IN then
        local ok, reason = ValidateGreetingTurnIn(decision)
        if not ok then
            DebugRevalidationFailed(reason)
            return false
        end

        AQG:Verbose("Turn-in:", QuestLabel(decision))
        DebugExecution(decision)
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
        DebugExecution(decision)
        SelectAvailableQuest(decision.index)

        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- Direct Quest Frame Execution
--------------------------------------------------------------------------------

local function ValidateCurrentQuest(decision)
    local ok, reason = Safety:ValidateCurrentQuest(decision.targetID, "QuestFrame")
    if not ok then
        return false, reason
    end

    return true, nil
end

local function ExecuteQuestAcceptConfirmDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    decision = RevalidateForAction(decision, function()
        return Decisions:DecideQuestAcceptConfirmAction(
            decision.playerName,
            decision.title,
            decision.targetID
        )
    end)
    if not decision then
        return false
    end

    local shouldAccept, acceptReason =
        Decisions:ShouldAccept(decision.quest or decision.targetID)
    if not shouldAccept then
        DebugRevalidationFailed(acceptReason
            or "This quest is blocked by your AQG settings.")
        return false
    end

    AQG:Verbose("Confirm:", QuestLabel(decision))
    DebugExecution(decision)
    ConfirmAcceptQuest()

    return true
end

local function ExecuteQuestDetailDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    decision = RevalidateForAction(decision, function()
        return Decisions:DecideQuestDetailAction(decision.targetID)
    end)
    if not decision then
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
        DebugRevalidationFailed("This quest would flag you for PvP and must be accepted manually.")
        return false
    end

    local goldCost, goldReason = ReadCurrentGoldCost()
    if goldReason then
        DebugRevalidationFailed(goldReason)
        return false
    end
    if goldCost > 0 then
        DebugRevalidationFailed("This quest now requires gold.")
        return false
    end

    local shouldAccept, acceptReason =
        Decisions:ShouldAccept(decision.quest or decision.targetID)
    if not shouldAccept then
        DebugRevalidationFailed(acceptReason
            or "This quest is blocked by your AQG settings.")
        return false
    end

    local autoAccept, autoReason = ReadCurrentAutoAcceptFlag()
    if autoReason then
        DebugRevalidationFailed(autoReason)
        return false
    end

    AQG:Verbose("Accept:", QuestLabel(decision))
    DebugExecution(decision)

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

    decision = RevalidateForAction(decision, function()
        return Decisions:DecideQuestProgressAction(decision.targetID)
    end)
    if not decision then
        return false
    end

    local ok, reason = ValidateCurrentQuest(decision)
    if not ok then
        DebugRevalidationFailed(reason)
        return false
    end

    local shouldTurnIn, turnInReason =
        Decisions:ShouldTurnIn(decision.quest or decision.targetID)
    if not shouldTurnIn then
        DebugRevalidationFailed(turnInReason
            or "This quest turn-in is blocked by your AQG settings.")
        return false
    end

    local completable, completeReason = ReadCurrentCompletable()
    if completeReason then
        DebugRevalidationFailed(completeReason)
        return false
    end
    if not completable then
        DebugRevalidationFailed("This quest is no longer ready to turn in.")
        return false
    end

    local goldCost, goldReason = ReadCurrentGoldCost()
    if goldReason then
        DebugRevalidationFailed(goldReason)
        return false
    end
    if goldCost > 0 then
        DebugRevalidationFailed("This turn-in now requires gold.")
        return false
    end

    local requiresCurrency, currencyReason = ReadCurrentRequiresCurrency()
    if currencyReason then
        DebugRevalidationFailed(currencyReason)
        return false
    end
    if requiresCurrency then
        DebugRevalidationFailed("This turn-in now requires currency.")
        return false
    end

    local blocksRequiredItem, _itemName, itemReason =
        Decisions:RequiredQuestItemBlocksTurnIn()
    if blocksRequiredItem then
        DebugRevalidationFailed(itemReason)
        return false
    end

    AQG:Verbose("Turn-in:", QuestLabel(decision))
    DebugExecution(decision)
    CompleteQuest()

    return true
end

local function ExecuteQuestCompleteDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    decision = RevalidateForAction(decision, function()
        return Decisions:DecideQuestCompleteAction(decision.targetID)
    end)
    if not decision then
        return false
    end

    local ok, reason = ValidateCurrentQuest(decision)
    if not ok then
        DebugRevalidationFailed(reason)
        return false
    end

    local shouldTurnIn, turnInReason =
        Decisions:ShouldTurnIn(decision.quest or decision.targetID)
    if not shouldTurnIn then
        DebugRevalidationFailed(turnInReason
            or "This quest turn-in is blocked by your AQG settings.")
        return false
    end

    local goldCost, goldReason = ReadCurrentGoldCost()
    if goldReason then
        DebugRevalidationFailed(goldReason)
        return false
    end
    if goldCost > 0 then
        DebugRevalidationFailed("This turn-in now requires gold.")
        return false
    end

    local numChoices, choiceReason = ReadCurrentRewardChoiceCount()
    if choiceReason then
        DebugRevalidationFailed(choiceReason)
        return false
    end
    if numChoices > 1 then
        DebugRevalidationFailed("This quest now has multiple reward choices.")
        return false
    end

    AQG:Verbose("Complete:", QuestLabel(decision))
    DebugExecution(decision)
    GetQuestReward(numChoices)

    return true
end

local function ExecuteQuestAutocompleteDecision(decision)
    if not CanExecuteDecision(decision) then
        return false
    end

    decision = RevalidateForAction(decision, function()
        return Decisions:DecideQuestAutocompleteAction(decision.targetID)
    end)
    if not decision then
        return false
    end

    local shouldTurnIn, turnInReason =
        Decisions:ShouldTurnIn(decision.quest or decision.targetID)
    if not shouldTurnIn then
        DebugRevalidationFailed(turnInReason
            or "This quest turn-in is blocked by your AQG settings.")
        return false
    end

    local index = GetLogIndexForQuestID(decision.targetID)
    if not Safety:IsSafeNumber(index) then
        DebugRevalidationFailed("Cannot find this quest in your quest log.")
        return false
    end

    local info = GetInfo(index)
    if type(info) ~= "table" then
        DebugRevalidationFailed("Cannot read this quest from your quest log.")
        return false
    end

    local isAutoComplete = info.isAutoComplete
    if Safety:IsSecret(isAutoComplete) or type(isAutoComplete) ~= "boolean" then
        DebugRevalidationFailed("Cannot safely check whether this quest can auto-complete.")
        return false
    end

    if not isAutoComplete then
        DebugRevalidationFailed("This quest can no longer auto-complete.")
        return false
    end

    AQG:Verbose("Auto-complete:", QuestLabel(decision))
    DebugExecution(decision)
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
    DebugDecision("GOSSIP_SHOW (Quest)", decision, {
        suppressInteractionHeader = true,
    })

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
