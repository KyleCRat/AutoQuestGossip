local _, AQG = ...

local              GetTitle = C_QuestLog.GetTitleForQuestID
local               GetInfo = C_QuestLog.GetInfo
local      SetSelectedQuest = C_QuestLog.SetSelectedQuest
local GetLogIndexForQuestID = C_QuestLog.GetLogIndexForQuestID

local function QuestType(questOrID)
    local daily, weekly, trivial, warbound, meta =
          AQG:ClassifyQuest(questOrID)

    return meta     and "Meta" or
           daily    and "Daily" or
           weekly   and "Weekly" or
           trivial  and "Trivial" or
           warbound and "Warbound" or
                        "Regular"
end

local function QuestLabel(quest)
    local title = quest.title or GetTitle(quest.questID) or "?"
    local questType = QuestType(quest)

    return title .. " (ID: " .. quest.questID .. " | Type: " .. questType .. ")"
end

local function QuestTitle(questID)
    return GetTitleText() or (questID and GetTitle(questID)) or "?"
end

--------------------------------------------------------------------------------
--- GOSSIP_SHOW:
---
--- auto-select available and completable quests from the gossip window
local function OnGossipShow()
    AQG.questHandled = false
    local db = AutoQuestGossipDB

    if not db.questEnabled then return end
    if AQG:PausedByModKey("Quest") then return end

    -- If any gossip option has skip/important text,
    -- pause ALL automation (quest + gossip)
    local hasSkip, hasImportant, hasAngleBracket = AQG:GossipHasDangerousOption()

    if hasSkip then
        AQG:Warn("Skip option detected — automation paused.")

        return
    elseif hasImportant then
        AQG:Warn("Important selections detected — automation paused.")

        return
    elseif hasAngleBracket and AutoQuestGossipDB.pauseOnAngleBracket then
        AQG:Warn("Angle bracket option detected — automation paused.")

        return
    end

    -- Wait for quest data if not yet cached
    local activeQuests = C_GossipInfo.GetActiveQuests()
    if not AQG:AreQuestsCached(activeQuests, OnGossipShow) then return end

    -- Check for a completable quest before waiting on available quest cache —
    -- turn-ins should proceed regardless of whether accept quests are cached
    local hasCompletable = false
    if db.questTurnInEnabled then
        for _, quest in ipairs(activeQuests) do
            if quest.isComplete then
                hasCompletable = true
                break
            end
        end
    end

    local availableQuests = C_GossipInfo.GetAvailableQuests()
    if not hasCompletable and not AQG:AreQuestsCached(availableQuests, OnGossipShow) then return end

    -- Debug: print detailed info to debug panel
    if db.debugEnabled then
        AQG:DebugSeparator("GOSSIP_SHOW")

        if #activeQuests > 0 then
            AQG:Debug("Active quests (turn-in):")

            for _, quest in ipairs(activeQuests) do
                local complete = quest.isComplete and "COMPLETE" or "incomplete"
                local allowed = quest.isComplete and db.questTurnInEnabled
                local action = allowed and "-> Would auto turn-in" or ""

                if quest.isComplete and not allowed then
                    action = "-> auto quest turn in is disabled"
                end

                if not quest.isComplete then
                    action = "-> Not ready"
                end

                AQG:Debug("  " .. QuestLabel(quest),
                          "[" .. complete .. "]", action)
            end
        end

        if #availableQuests > 0 then
            AQG:Debug("Available quests (accept):")

            for _, quest in ipairs(availableQuests) do
                local allowed = AQG:ShouldAccept(quest)
                local action = allowed and " -> Would auto-accept"
                    or " -> Available quest not allowed to be accepted"

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
            if quest.isComplete then
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
            if AQG:ShouldAccept(quest) then
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

--------------------------------------------------------------------------------
--- QUEST_ACCEPT_CONFIRM:
---
--- auto-confirm escort/shared quests started by another player
local function OnQuestAcceptConfirm(playerName, questTitle)
    local db = AutoQuestGossipDB

    if not db.questEnabled then return end
    if not db.questAcceptEnabled then return end
    if AQG:PausedByModKey("Quest") then return end

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
end

AQG:RegisterEvent("QUEST_ACCEPT_CONFIRM", OnQuestAcceptConfirm)

--------------------------------------------------------------------------------
--- QUEST_DETAIL:
---
--- auto-accept the offered quest
local function OnQuestDetail(questID)
    local db = AutoQuestGossipDB

    if not db.questEnabled then return end
    if not db.questAcceptEnabled then return end
    if AQG:PausedByModKey("Quest") then return end

    questID = questID or GetQuestID()
    if not questID or questID == 0 then return end

    if not AQG:IsQuestDataReady(questID, OnQuestDetail) then return end

    local title = QuestTitle(questID)
    local qType = QuestType(questID)
    local goldCost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    local allowed = AQG:ShouldAccept(questID)

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

-- QUEST_DETAIL passes questStartItemID (not questID), swallow it
AQG:RegisterEvent("QUEST_DETAIL", function() OnQuestDetail() end)

--------------------------------------------------------------------------------
--- QUEST_PROGRESS:
---
--- advance to the completion/reward step
local function OnQuestProgress(questID)
    local db = AutoQuestGossipDB

    if not db.questEnabled then return end
    if not db.questTurnInEnabled then return end
    if AQG:PausedByModKey("Quest") then return end

    questID = questID or GetQuestID()

    if not AQG:IsQuestDataReady(questID, OnQuestProgress) then return end

    local completable = IsQuestCompletable()
    local title = QuestTitle()
    local qType = questID and questID ~= 0 and QuestType(questID) or "?"
    local goldCost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    local requiresCurrency = AQG:QuestItemIsCurrency()
    local requiresReagent, reagentName = AQG:QuestItemIsReagent()

    if db.debugEnabled then
        AQG:DebugSeparator("QUEST_PROGRESS")
        AQG:Debug(title, "(ID:", questID or "?", "| Type:", qType .. ")")
        AQG:DebugQuestAPIs(questID)

        if not completable then
            AQG:Debug("-> Not completable yet. Would NOT advance.")
        elseif goldCost > 0 then
            AQG:Debug("-> Requires gold",
                      "(" .. GetCoinTextureString(goldCost) .. ").",
                      "Would NOT advance.")
        elseif requiresCurrency then
            AQG:Debug("-> Requires currency. Would NOT advance.")
        elseif requiresReagent then
            AQG:Debug("-> Requires crafting reagent (" .. reagentName .. ").",
                "Would NOT advance.")
        else
            AQG:Debug("-> Would auto-advance to reward step.")
        end
    end

    if db.devMode then return end

    if not completable then return end
    if goldCost > 0 then return end
    if requiresCurrency then return end
    if requiresReagent then return end

    AQG:Verbose("Turn-in:", title,
                "(ID:", questID or "?", "| Type:", qType .. ")")
    AQG:Debug("Auto turn-in (progress):", title,
              "(ID:", questID or "?", "| Type:", qType .. ")")
    CompleteQuest()
end

AQG:RegisterEvent("QUEST_PROGRESS", OnQuestProgress)

--------------------------------------------------------------------------------
--- QUEST_COMPLETE:
---
--- finalize turn-in if there's no reward choice to make
local function OnQuestComplete(questID)
    local db = AutoQuestGossipDB

    if not db.questEnabled then return end
    if not db.questTurnInEnabled then return end
    if AQG:PausedByModKey("Quest") then return end

    questID = questID or GetQuestID()

    if not AQG:IsQuestDataReady(questID, OnQuestComplete) then return end

    local title = QuestTitle(questID)
    local qType = questID and questID ~= 0 and QuestType(questID) or "?"
    local numChoices = GetNumQuestChoices()
    local goldCost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0

    if db.debugEnabled then
        AQG:DebugSeparator("QUEST_COMPLETE")
        AQG:Debug(title, "(ID:", questID or "?", "| Type:", qType .. ")")
        AQG:DebugQuestAPIs(questID)
        AQG:Debug("  Reward choices:", numChoices)

        if goldCost > 0 then
            AQG:Debug("-> Requires gold",
                      "(" .. GetCoinTextureString(goldCost) .. ").",
                      "Would NOT complete.")
        elseif numChoices > 1 then
            AQG:Debug("-> Multiple rewards. Would NOT auto-complete",
                      "(player must choose).")
        else
            AQG:Debug("-> Would auto-complete.")
        end
    end

    if db.devMode then return end

    if goldCost > 0 then return end
    if numChoices <= 1 then
        AQG:Verbose("Complete:", title,
                    "(ID:", questID or "?", "| Type:", qType .. ")")
        AQG:Debug("Auto turn-in (complete):", title,
                  "(ID:", questID or "?", "| Type:", qType .. ")")

        GetQuestReward(numChoices)
    end
end

AQG:RegisterEvent("QUEST_COMPLETE", OnQuestComplete)

--------------------------------------------------------------------------------
--- QUEST_AUTOCOMPLETE:
---
--- handle quests completed via the objective tracker
local function OnQuestAutocomplete(questID)
    local db = AutoQuestGossipDB

    if not db.questEnabled then return end
    if not db.questTurnInEnabled then return end
    if AQG:PausedByModKey("Quest") then return end

    local index = GetLogIndexForQuestID(questID)
    if not index then return end

    local info = GetInfo(index)
    if not info or not info.isAutoComplete then return end

    if not AQG:IsQuestDataReady(questID, OnQuestAutocomplete) then
        return
    end

    local title = info.title or QuestTitle(questID)
    local qType = QuestType(questID)

    if db.debugEnabled then
        AQG:DebugSeparator("QUEST_AUTOCOMPLETE")
        AQG:Debug(title, "(ID:", questID or "?", "| Type:", qType .. ")")
        AQG:Debug("-> Would show quest completion dialog.")
    end

    if db.devMode then return end

    AQG:Verbose("Auto-complete:", title,
        "(ID:", questID, "| Type:", qType .. ")")
    AQG:Debug("Auto-complete (tracker):", title,
        "(ID:", questID, "| Type:", qType .. ")")

    SetSelectedQuest(questID)
    ShowQuestComplete(GetSelectedQuest())
end

AQG:RegisterEvent("QUEST_AUTOCOMPLETE", OnQuestAutocomplete)
