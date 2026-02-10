local _, AQG = ...

local GetTitle = C_QuestLog.GetTitleForQuestID

local function QuestType(questID, frequency, isTrivial, isMeta)
    local daily, weekly, trivial, warbound, meta =
          AQG:ClassifyQuest(questID, frequency, isTrivial, isMeta)

    return meta     and "Meta" or
           daily    and "Daily" or
           weekly   and "Weekly" or
           trivial  and "Trivial" or
           warbound and "Warbound" or
                        "Regular"
end

local function QuestLabel(quest)
    local title = quest.title or GetTitle(quest.questID) or "?"
    local questType = QuestType(quest.questID,
                                quest.frequency,
                                quest.isTrivial,
                                quest.isMeta)

    return title .. " (ID: " .. quest.questID .. " | Type: " .. questType .. ")"
end

local function QuestTitle(questID)
    return GetTitleText() or (questID and GetTitle(questID)) or "?"
end

-- GOSSIP_SHOW:
-- auto-select available and completable quests from the gossip window
local function OnGossipShow()
    AQG.questHandled = false
    local db = AutoQuestGossipDB

    if not db.questEnabled then return end

    if AQG:PausedByModKey("Quest") then return end

    -- If any gossip option has skip/important text, pause ALL automation (quest + gossip)
    local hasSkip, hasImportant = AQG:GossipHasDangerousOption()

    if hasSkip or hasImportant then
        if hasSkip then
            AQG:Warn("Skip option detected — automation paused.")
        end

        if hasImportant and not hasSkip then
            AQG:Warn("Important selections detected — automation paused.")
        end

        return
    end

    local activeQuests = C_GossipInfo.GetActiveQuests()
    local availableQuests = C_GossipInfo.GetAvailableQuests()

    -- Wait for quest data if not yet cached
    if not AQG:AreQuestsCached(activeQuests, OnGossipShow) then

        return
    end

    if not AQG:AreQuestsCached(availableQuests, OnGossipShow) then

        return
    end

    -- Debug: print detailed info to debug panel
    if db.debugEnabled then
        AQG:DebugSeparator("GOSSIP_SHOW")

        if #activeQuests > 0 then
            AQG:Debug("Active quests (turn-in):")

            for _, quest in ipairs(activeQuests) do
                local complete = quest.isComplete and "COMPLETE" or "incomplete"
                local allowed = quest.isComplete and AQG:ShouldAutomate(quest.questID, quest.frequency, quest.isTrivial, quest.isMeta, false)
                local action = allowed and " -> Would auto turn-in" or ""
                if quest.isComplete and not allowed then action = " -> Filtered out by settings" end
                if not quest.isComplete then action = " -> Not ready" end
                AQG:Debug("  " .. QuestLabel(quest) .. " [" .. complete .. "]" .. action)
            end
        end

        if #availableQuests > 0 then
            AQG:Debug("Available quests (accept):")

            for _, quest in ipairs(availableQuests) do
                local allowed = AQG:ShouldAutomate(quest.questID, quest.frequency, quest.isTrivial, quest.isMeta, true)
                local action = allowed and " -> Would auto-accept" or " -> Filtered out by settings"
                AQG:Debug("  " .. QuestLabel(quest) .. action)
            end
        end

        if #activeQuests == 0 and #availableQuests == 0 then
            AQG:Debug("No quests at this NPC.")
        end
    end

    -- Dev mode: block automation after printing
    if db.devMode then return end

    -- Turn in completed quests
    if db.questTurnInEnabled then
        for _, quest in ipairs(activeQuests) do
            if quest.isComplete and AQG:ShouldAutomate(quest.questID, quest.frequency, quest.isTrivial, quest.isMeta, false) then
                AQG:Verbose("Turn-in:", QuestLabel(quest))
                AQG:Debug("Auto turn-in:", QuestLabel(quest))
                C_GossipInfo.SelectActiveQuest(quest.questID)
                AQG.questHandled = true

                return
            end
        end
    end

    -- Accept available quests
    if db.questAcceptEnabled then
        for _, quest in ipairs(availableQuests) do
            if AQG:ShouldAutomate(quest.questID, quest.frequency, quest.isTrivial, quest.isMeta, true) then
                AQG:Verbose("Accept:", QuestLabel(quest))
                AQG:Debug("Auto-accept:", QuestLabel(quest))
                C_GossipInfo.SelectAvailableQuest(quest.questID)
                AQG.questHandled = true

                return
            end
        end
    end
end

AQG:RegisterEvent("GOSSIP_SHOW", OnGossipShow)

-- QUEST_ACCEPT_CONFIRM:
-- auto-confirm escort/shared quests started by another player
AQG:RegisterEvent("QUEST_ACCEPT_CONFIRM", function(playerName, questTitle)
    local db = AutoQuestGossipDB
    if not db.questEnabled or
       not db.questAcceptEnabled or
       AQG:PausedByModKey("Quest") then return end

    local label = (questTitle or "?") .. " (from " .. (playerName or "?") .. ")"

    if db.debugEnabled then
        AQG:DebugSeparator("QUEST_ACCEPT_CONFIRM")
        AQG:Debug("Escort/shared quest:", label)
        if db.devMode then
            AQG:Debug("-> Dev mode. Would NOT auto-confirm.")
        else
            AQG:Debug("-> Would auto-confirm.")
        end
    end

    if db.devMode then return end

    AQG:Verbose("Confirm:", label)
    AQG:Debug("Auto-confirm escort/shared quest:", label)
    ConfirmAcceptQuest()
end)

-- QUEST_DETAIL:
-- auto-accept the offered quest
local function OnQuestDetail()
    local db = AutoQuestGossipDB
    if not db.questEnabled or
       not db.questAcceptEnabled or
       AQG:PausedByModKey("Quest") then return end

    local questID = GetQuestID()
    if not questID or questID == 0 then return end

    if not AQG:IsQuestDataReady(questID, OnQuestDetail) then

        return
    end

    local title = QuestTitle(questID)
    local qType = QuestType(questID, nil, nil)
    local goldCost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    local allowed = AQG:ShouldAutomate(questID, nil, nil, nil, true)

    -- Debug: print detailed info to debug panel
    if db.debugEnabled then
        AQG:DebugSeparator("QUEST_DETAIL")
        AQG:Debug(title, "(ID:", questID, "| Type:", qType .. ")")
        AQG:DebugQuestAPIs(questID)

        if goldCost > 0 then
            AQG:Debug("-> Requires gold. Would NOT auto-accept.")
        elseif not allowed then
            AQG:Debug("-> Filtered out by settings. Would NOT auto-accept.")
        else
            AQG:Debug("-> Would auto-accept.")
        end
    end

    -- Dev mode: block automation after printing
    if db.devMode then return end

    if goldCost > 0 then return end
    if not allowed then return end

    AQG:Verbose("Accept:", title, "(ID:", questID, "| Type:", qType .. ")")
    AQG:Debug("Auto-accept:", title, "(ID:", questID, "| Type:", qType .. ")")

    if QuestGetAutoAccept and QuestGetAutoAccept() then
        AcknowledgeAutoAcceptQuest()
    else
        AcceptQuest()
    end
end

AQG:RegisterEvent("QUEST_DETAIL", OnQuestDetail)

-- QUEST_PROGRESS:
-- advance to the completion/reward step
local function OnQuestProgress()
    local db = AutoQuestGossipDB
    if not db.questEnabled or
       not db.questTurnInEnabled or
       AQG:PausedByModKey("Quest") then return end

    local questID = GetQuestID()

    if not AQG:IsQuestDataReady(questID, OnQuestProgress) then

        return
    end

    local completable = IsQuestCompletable()
    local title = QuestTitle()
    local qType = questID and questID ~= 0 and QuestType(questID, nil, nil) or "?"
    local allowed = questID and questID ~= 0 and AQG:ShouldAutomate(questID, nil, nil, nil, false)
    local goldCost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    local requiresCurrency = AQG:QuestItemIsCurrency()
    local requiresReagent, reagentName = AQG:QuestItemIsReagent()

    -- Debug: print detailed info to debug panel
    if db.debugEnabled then
        AQG:DebugSeparator("QUEST_PROGRESS")
        AQG:Debug(title, "(ID:", questID or "?", "| Type:", qType .. ")")
        AQG:DebugQuestAPIs(questID)

        if not completable then
            AQG:Debug("-> Not completable yet. Would NOT advance.")
        elseif goldCost > 0 then
            AQG:Debug("-> Requires gold (" .. GetCoinTextureString(goldCost) .. "). Would NOT advance.")
        elseif requiresCurrency then
            AQG:Debug("-> Requires currency. Would NOT advance.")
        elseif requiresReagent then
            AQG:Debug("-> Requires crafting reagent (" .. reagentName .. "). Would NOT advance.")
        elseif not allowed then
            AQG:Debug("-> Filtered out by settings. Would NOT advance.")
        else
            AQG:Debug("-> Would auto-advance to reward step.")
        end
    end

    -- Dev mode: block automation after printing
    if db.devMode then return end

    if not completable then return end
    if goldCost > 0 then return end
    if requiresCurrency then return end
    if requiresReagent then return end
    if questID and questID ~= 0 and not allowed then return end

    AQG:Verbose("Turn-in:", title, "(ID:", questID or "?", "| Type:", qType .. ")")
    AQG:Debug("Auto turn-in (progress):", title, "(ID:", questID or "?", "| Type:", qType .. ")")
    CompleteQuest()
end

AQG:RegisterEvent("QUEST_PROGRESS", OnQuestProgress)

-- QUEST_COMPLETE:
-- finalize turn-in if there's no reward choice to make
local function OnQuestComplete()
    local db = AutoQuestGossipDB
    if not db.questEnabled or
       not db.questTurnInEnabled or
       AQG:PausedByModKey("Quest") then return end

    local questID = GetQuestID()

    if not AQG:IsQuestDataReady(questID, OnQuestComplete) then

        return
    end

    local title = QuestTitle(questID)
    local qType = questID and questID ~= 0 and QuestType(questID, nil, nil) or "?"
    local numChoices = GetNumQuestChoices()
    local allowed = not questID or questID == 0 or AQG:ShouldAutomate(questID, nil, nil, nil, false)
    local goldCost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0

    -- Debug: print detailed info to debug panel
    if db.debugEnabled then
        AQG:DebugSeparator("QUEST_COMPLETE")
        AQG:Debug(title, "(ID:", questID or "?", "| Type:", qType .. ")")
        AQG:DebugQuestAPIs(questID)
        AQG:Debug("  Reward choices:", numChoices)
        if not allowed then
            AQG:Debug("-> Filtered out by settings. Would NOT complete.")
        elseif goldCost > 0 then
            AQG:Debug("-> Requires gold (" .. GetCoinTextureString(goldCost) .. "). Would NOT complete.")
        elseif numChoices > 1 then
            AQG:Debug("-> Multiple rewards. Would NOT auto-complete (player must choose).")
        else
            AQG:Debug("-> Would auto-complete.")
        end
    end

    -- Dev mode: block automation after printing
    if db.devMode then return end

    if not allowed then return end
    if goldCost > 0 then return end
    if numChoices <= 1 then
        AQG:Verbose("Complete:", title, "(ID:", questID or "?", "| Type:", qType .. ")")
        AQG:Debug("Auto turn-in (complete):", title, "(ID:", questID or "?", "| Type:", qType .. ")")
        GetQuestReward(numChoices)
    end
end

AQG:RegisterEvent("QUEST_COMPLETE", OnQuestComplete)

-- QUEST_AUTOCOMPLETE:
-- handle quests completed via the objective tracker
local autocompleteQuestID

local function OnQuestAutocomplete()
    local questID = autocompleteQuestID
    local db = AutoQuestGossipDB
    if not db.questEnabled or
       not db.questTurnInEnabled or
       AQG:PausedByModKey("Quest") then return end

    local index = C_QuestLog.GetLogIndexForQuestID(questID)
    if not index then return end

    local info = C_QuestLog.GetInfo(index)
    if not info or not info.isAutoComplete then return end

    if not AQG:IsQuestDataReady(questID, OnQuestAutocomplete) then

        return
    end

    local title = info.title or QuestTitle(questID)
    local qType = QuestType(questID, nil, nil)
    local allowed = AQG:ShouldAutomate(questID, nil, nil, nil, false)

    if db.debugEnabled then
        AQG:DebugSeparator("QUEST_AUTOCOMPLETE")
        AQG:Debug(title, "(ID:", questID or "?", "| Type:", qType .. ")")
        if not allowed then
            AQG:Debug("-> Filtered out by settings."
                .. " Would NOT show completion.")
        else
            AQG:Debug("-> Would show quest completion dialog.")
        end
    end

    if db.devMode then return end
    if not allowed then return end

    AQG:Verbose("Auto-complete:", title,
        "(ID:", questID, "| Type:", qType .. ")")
    AQG:Debug("Auto-complete (tracker):", title,
        "(ID:", questID, "| Type:", qType .. ")")
    C_QuestLog.SetSelectedQuest(questID)
    ShowQuestComplete(C_QuestLog.GetSelectedQuest())
end

AQG:RegisterEvent("QUEST_AUTOCOMPLETE", function(questID)
    autocompleteQuestID = questID
    OnQuestAutocomplete()
end)
