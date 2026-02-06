local addonName, AQG = ...

-- Default settings
local defaults = {
    -- Quest settings
    questEnabled = true,
    questAcceptEnabled = true,
    questTurnInEnabled = true,
    acceptDaily = true,
    acceptWeekly = true,
    acceptTrivial = false,
    acceptWarboundCompleted = false,
    acceptRegular = true,
    turnInDaily = true,
    turnInWeekly = true,
    turnInTrivial = false,
    turnInWarboundCompleted = false,
    turnInRegular = true,
    modifierKey = "SHIFT",
    invertModifier = false,

    -- Gossip settings
    gossipEnabled = true,
    gossipOnlySingle = true,

    -- Debug
    debugEnabled = false,
}

-- Shared addon table
AQG.questHandled = false -- flag to prevent gossip firing after quest selection

local function IsModifierDown()
    local key = AutoQuestGossipDB.modifierKey
    if key == "SHIFT" then return IsShiftKeyDown()
    elseif key == "CTRL" then return IsControlKeyDown()
    elseif key == "ALT" then return IsAltKeyDown()
    end
    return false
end

function AQG:ShouldProceed()
    local mod = IsModifierDown()
    local invert = AutoQuestGossipDB.invertModifier
    if invert then return mod else return not mod end
end

function AQG:ClassifyQuest(questID, frequency, isTrivial)
    -- Check daily: gossip frequency field, QuestIsDaily(), or tag info
    local isDaily = (frequency == 2) or (QuestIsDaily and QuestIsDaily())
    local isWeekly = (frequency == 3) or (QuestIsWeekly and QuestIsWeekly())

    -- Also check C_QuestLog.GetQuestTagInfo for additional frequency data
    if questID and (not isDaily and not isWeekly) then
        local tagInfo = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
        if tagInfo then
            -- worldQuestType indicates world quests which are often dailies
            if tagInfo.worldQuestType then
                isDaily = true
            end
        end
    end

    -- Check repeatable quests via QuestIsRepeatableQuest if available (often daily/weekly)
    if questID and (not isDaily and not isWeekly) then
        if C_QuestLog.IsRepeatableQuest and C_QuestLog.IsRepeatableQuest(questID) then
            isDaily = true
        end
    end

    local isTrivialQuest = isTrivial or (C_QuestLog.IsQuestTrivial and C_QuestLog.IsQuestTrivial(questID))
    local isWarboundCompleted = C_QuestLog.IsQuestFlaggedCompletedOnAccount
        and C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID)
    return isDaily, isWeekly, isTrivialQuest, isWarboundCompleted
end

function AQG:DebugQuestAPIs(questID)
    if not AutoQuestGossipDB.debugEnabled then return end
    local parts = {"  Raw APIs:"}
    if QuestIsDaily then
        table.insert(parts, "QuestIsDaily()=" .. tostring(QuestIsDaily()))
    end
    if QuestIsWeekly then
        table.insert(parts, "QuestIsWeekly()=" .. tostring(QuestIsWeekly()))
    end
    if questID then
        if C_QuestLog.IsQuestTrivial then
            table.insert(parts, "IsQuestTrivial=" .. tostring(C_QuestLog.IsQuestTrivial(questID)))
        end
        if C_QuestLog.IsQuestFlaggedCompletedOnAccount then
            table.insert(parts, "WarboundCompleted=" .. tostring(C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID)))
        end
        if C_QuestLog.IsRepeatableQuest then
            table.insert(parts, "IsRepeatable=" .. tostring(C_QuestLog.IsRepeatableQuest(questID)))
        end
        local tagInfo = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
        if tagInfo then
            table.insert(parts, "tagID=" .. tostring(tagInfo.tagID))
            table.insert(parts, "worldQuestType=" .. tostring(tagInfo.worldQuestType))
        else
            table.insert(parts, "tagInfo=nil")
        end
    end
    self:Debug(table.concat(parts, ", "))
end

function AQG:ShouldAutomate(questID, frequency, isTrivial, isAccept)
    local db = AutoQuestGossipDB
    local daily, weekly, trivial, warbound = self:ClassifyQuest(questID, frequency, isTrivial)
    local prefix = isAccept and "accept" or "turnIn"

    if daily then return db[prefix .. "Daily"] end
    if weekly then return db[prefix .. "Weekly"] end
    if trivial then return db[prefix .. "Trivial"] end
    if warbound then return db[prefix .. "WarboundCompleted"] end
    return db[prefix .. "Regular"]
end

local ADDON_COLOR = "|cff00ccff"
local SEPARATOR = ADDON_COLOR .. "--- AQG ----------------------------------------|r"

function AQG:Debug(...)
    if AutoQuestGossipDB.debugEnabled then
        print(ADDON_COLOR .. "AQG:|r", ...)
    end
end

function AQG:DebugSeparator(event)
    if AutoQuestGossipDB.debugEnabled then
        print(SEPARATOR)
        print(ADDON_COLOR .. "AQG:|r [" .. event .. "]")
    end
end

-- Event frame
local frame = CreateFrame("Frame")
AQG.frame = frame

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            -- Initialize saved variables with defaults
            if not AutoQuestGossipDB then
                AutoQuestGossipDB = {}
            end
            for k, v in pairs(defaults) do
                if AutoQuestGossipDB[k] == nil then
                    AutoQuestGossipDB[k] = v
                end
            end
            self:UnregisterEvent("ADDON_LOADED")

            -- Fire module init callbacks
            if AQG.onInit then
                for _, fn in ipairs(AQG.onInit) do
                    fn()
                end
            end
        end
        return
    end

    -- Dispatch to registered handlers
    if AQG.handlers and AQG.handlers[event] then
        for _, handler in ipairs(AQG.handlers[event]) do
            handler(...)
        end
    end
end)

function AQG:RegisterEvent(event, handler)
    if not self.handlers then self.handlers = {} end
    if not self.handlers[event] then
        self.handlers[event] = {}
        self.frame:RegisterEvent(event)
    end
    table.insert(self.handlers[event], handler)
end

function AQG:OnInit(fn)
    if not self.onInit then self.onInit = {} end
    table.insert(self.onInit, fn)
end

SLASH_AUTOQUESTGOSSIP1 = "/aqg"
SlashCmdList["AUTOQUESTGOSSIP"] = function()
    if AQG.settingsCategory then
        Settings.OpenToCategory(AQG.settingsCategory:GetID())
    end
end
