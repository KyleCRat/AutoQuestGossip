local _, AQG = ...

local function QuestType(questID, frequency, isTrivial)
    local daily, weekly, trivial, warbound = AQG:ClassifyQuest(questID, frequency, isTrivial)
    return daily and "Daily" or weekly and "Weekly" or trivial and "Trivial" or warbound and "Warbound" or "Regular"
end

local function QuestLabel(quest)
    local title = quest.title or C_QuestLog.GetTitleForQuestID(quest.questID) or "?"
    return title .. " (ID: " .. quest.questID .. " | Type: " .. QuestType(quest.questID, quest.frequency, quest.isTrivial) .. ")"
end

-- GOSSIP_SHOW: auto-select available and completable quests from the gossip window
AQG:RegisterEvent("GOSSIP_SHOW", function()
    AQG.questHandled = false
    local db = AutoQuestGossipDB
    if not db.questEnabled or not AQG:ShouldProceed() then return end

    local activeQuests = C_GossipInfo.GetActiveQuests()
    local availableQuests = C_GossipInfo.GetAvailableQuests()

    -- Debug mode: print everything and what we would do, but don't act
    if db.debugEnabled then
        AQG:DebugSeparator("GOSSIP_SHOW")
        if #activeQuests > 0 then
            AQG:Debug("Active quests (turn-in):")
            for _, quest in ipairs(activeQuests) do
                local complete = quest.isComplete and "COMPLETE" or "incomplete"
                local allowed = quest.isComplete and AQG:ShouldAutomate(quest.questID, quest.frequency, quest.isTrivial, false)
                local action = allowed and " -> Would auto turn-in" or ""
                if quest.isComplete and not allowed then action = " -> Filtered out by settings" end
                if not quest.isComplete then action = " -> Not ready" end
                AQG:Debug("  " .. QuestLabel(quest) .. " [" .. complete .. "]" .. action)
            end
        end
        if #availableQuests > 0 then
            AQG:Debug("Available quests (accept):")
            for _, quest in ipairs(availableQuests) do
                local allowed = AQG:ShouldAutomate(quest.questID, quest.frequency, quest.isTrivial, true)
                local action = allowed and " -> Would auto-accept" or " -> Filtered out by settings"
                AQG:Debug("  " .. QuestLabel(quest) .. action)
            end
        end
        if #activeQuests == 0 and #availableQuests == 0 then
            AQG:Debug("No quests at this NPC.")
        end
        return
    end

    -- Turn in completed quests
    if db.questTurnInEnabled then
        for _, quest in ipairs(activeQuests) do
            if quest.isComplete and AQG:ShouldAutomate(quest.questID, quest.frequency, quest.isTrivial, false) then
                C_GossipInfo.SelectActiveQuest(quest.questID)
                AQG.questHandled = true
                return
            end
        end
    end

    -- Accept available quests
    if db.questAcceptEnabled then
        for _, quest in ipairs(availableQuests) do
            if AQG:ShouldAutomate(quest.questID, quest.frequency, quest.isTrivial, true) then
                C_GossipInfo.SelectAvailableQuest(quest.questID)
                AQG.questHandled = true
                return
            end
        end
    end
end)

-- QUEST_DETAIL: auto-accept the offered quest
AQG:RegisterEvent("QUEST_DETAIL", function()
    local db = AutoQuestGossipDB
    if not db.questEnabled or not db.questAcceptEnabled or not AQG:ShouldProceed() then return end

    local questID = GetQuestID()
    if not questID or questID == 0 then return end

    local title = GetTitleText() or C_QuestLog.GetTitleForQuestID(questID) or "?"
    local qType = QuestType(questID, nil, nil)
    local goldCost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    local allowed = AQG:ShouldAutomate(questID, nil, nil, true)

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
        return
    end

    if goldCost > 0 then return end
    if not allowed then return end

    if QuestGetAutoAccept and QuestGetAutoAccept() then
        AcknowledgeAutoAcceptQuest()
    else
        AcceptQuest()
    end
end)

-- QUEST_PROGRESS: advance to the completion/reward step
AQG:RegisterEvent("QUEST_PROGRESS", function()
    local db = AutoQuestGossipDB
    if not db.questEnabled or not db.questTurnInEnabled or not AQG:ShouldProceed() then return end

    local completable = IsQuestCompletable()
    local questID = GetQuestID()
    local title = GetTitleText() or (questID and C_QuestLog.GetTitleForQuestID(questID)) or "?"
    local allowed = questID and questID ~= 0 and AQG:ShouldAutomate(questID, nil, nil, false)

    if db.debugEnabled then
        AQG:DebugSeparator("QUEST_PROGRESS")
        local qType = questID and questID ~= 0 and QuestType(questID, nil, nil) or "?"
        AQG:Debug(title, "(ID:", questID or 0, "| Type:", qType .. ")")
        AQG:DebugQuestAPIs(questID)
        if not completable then
            AQG:Debug("-> Not completable yet. Would NOT advance.")
        elseif not allowed then
            AQG:Debug("-> Filtered out by settings. Would NOT advance.")
        else
            AQG:Debug("-> Would auto-advance to reward step.")
        end
        return
    end

    if not completable then return end
    if questID and questID ~= 0 and not allowed then return end

    CompleteQuest()
end)

-- QUEST_COMPLETE: finalize turn-in if there's no reward choice to make
AQG:RegisterEvent("QUEST_COMPLETE", function()
    local db = AutoQuestGossipDB
    if not db.questEnabled or not db.questTurnInEnabled or not AQG:ShouldProceed() then return end

    local questID = GetQuestID()
    local title = GetTitleText() or (questID and C_QuestLog.GetTitleForQuestID(questID)) or "?"
    local numChoices = GetNumQuestChoices()
    local allowed = not questID or questID == 0 or AQG:ShouldAutomate(questID, nil, nil, false)

    if db.debugEnabled then
        AQG:DebugSeparator("QUEST_COMPLETE")
        local qType = questID and questID ~= 0 and QuestType(questID, nil, nil) or "?"
        AQG:Debug(title, "(ID:", questID or 0, "| Type:", qType .. ")")
        AQG:DebugQuestAPIs(questID)
        AQG:Debug("  Reward choices:", numChoices)
        if not allowed then
            AQG:Debug("-> Filtered out by settings. Would NOT complete.")
        elseif numChoices > 1 then
            AQG:Debug("-> Multiple rewards. Would NOT auto-complete (player must choose).")
        else
            AQG:Debug("-> Would auto-complete.")
        end
        return
    end

    if not allowed then return end
    if numChoices <= 1 then
        GetQuestReward(numChoices)
    end
end)
