local addonName, AQG = ...

-- Constants
local ADDON_COLOR = "|cff00ccff"
local SEPARATOR = ADDON_COLOR .. "--- AQG ----------------------------------------|r"

local CONTENT_TAG_MAP = {
    [1] = "contentGroup",
    [41] = "contentPvP",
    [62] = "contentRaid",
    [81] = "contentDungeon",
    [85] = "contentDungeon",       -- Heroic
    [88] = "contentRaid",          -- Raid (10)
    [89] = "contentRaid",          -- Raid (25)
    [113] = "contentPvP",          -- PVP World Quest
    [137] = "contentDungeon",      -- Dungeon World Quest
    [141] = "contentRaid",         -- Raid World Quest
    [145] = "contentDungeon",      -- Legionfall Dungeon World Quest
    [255] = "contentPvP",          -- War Mode PvP
    [256] = "contentPvP",          -- PvP Conquest
    [278] = "contentPvP",          -- PVP Elite World Quest
    [288] = "contentDelve",        -- Delve
    [289] = "contentWorldBoss",    -- World Boss
}

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
    acceptMeta = false,
    acceptRegular = true,
    turnInDaily = true,
    turnInWeekly = true,
    turnInTrivial = false,
    turnInWarboundCompleted = false,
    turnInMeta = false,
    turnInRegular = true,
    modifierKey = "SHIFT",

    -- Content type filters (all default enabled)
    contentDungeon = true,
    contentRaid = true,
    contentPvP = true,
    contentGroup = true,
    contentDelve = true,
    contentWorldBoss = true,

    -- Gossip settings
    gossipEnabled = true,
    gossipOnlySingle = true,

    -- Debug / Dev
    debugEnabled = false,
    devMode = false,
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
    return not IsModifierDown()
end

function AQG:ClassifyQuest(questID, frequency, isTrivial, isMeta)
    -- Check daily: gossip frequency field, QuestIsDaily(), or tag info
    local isDaily = (frequency == 2) or (QuestIsDaily and QuestIsDaily())
    local isWeekly = (frequency == 3) or (QuestIsWeekly and QuestIsWeekly())
    local isMetaQuest = isMeta or false

    -- Check C_QuestLog.GetQuestTagInfo for additional data
    local tagInfo = questID and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
    if tagInfo then
        -- worldQuestType indicates world quests which are often dailies
        if not isDaily and not isWeekly and tagInfo.worldQuestType then
            isDaily = true
        end
        -- tagID 284 = Meta Quest
        if tagInfo.tagID == 284 then
            isMetaQuest = true
        end
    end

    -- Check repeatable quests via IsRepeatableQuest if available (often daily/weekly)
    if questID and (not isDaily and not isWeekly) then
        if C_QuestLog.IsRepeatableQuest and C_QuestLog.IsRepeatableQuest(questID) then
            isDaily = true
        end
    end

    local isTrivialQuest = isTrivial or (C_QuestLog.IsQuestTrivial and C_QuestLog.IsQuestTrivial(questID))
    local isWarboundCompleted = C_QuestLog.IsQuestFlaggedCompletedOnAccount
        and C_QuestLog.IsQuestFlaggedCompletedOnAccount(questID)
    return isDaily, isWeekly, isTrivialQuest, isWarboundCompleted, isMetaQuest
end

function AQG:DebugQuestAPIs(questID)
    if not AutoQuestGossipDB.devMode then return end
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
            table.insert(parts, "tagName=" .. tostring(tagInfo.tagName))
            table.insert(parts, "worldQuestType=" .. tostring(tagInfo.worldQuestType))
            local contentKey = CONTENT_TAG_MAP[tagInfo.tagID]
            if contentKey then
                table.insert(parts, "contentFilter=" .. contentKey)
            end
        else
            table.insert(parts, "tagInfo=nil")
        end
    end
    self:Debug(table.concat(parts, ", "))
end

function AQG:GetContentFilterKey(questID)
    local tagInfo = questID and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
    if tagInfo and tagInfo.tagID then
        return CONTENT_TAG_MAP[tagInfo.tagID]
    end
    return nil
end

function AQG:ShouldAllowContent(questID)
    local key = self:GetContentFilterKey(questID)
    if key then
        return AutoQuestGossipDB[key]
    end
    return true -- no content tag = always allow
end

function AQG:ShouldAutomate(questID, frequency, isTrivial, isMeta, isAccept)
    -- Content type filter (dungeon, raid, pvp, etc.)
    if not self:ShouldAllowContent(questID) then return false end

    local db = AutoQuestGossipDB
    local daily, weekly, trivial, warbound, meta = self:ClassifyQuest(questID, frequency, isTrivial, isMeta)
    local prefix = isAccept and "accept" or "turnIn"

    if meta then return db[prefix .. "Meta"] end
    if daily then return db[prefix .. "Daily"] end
    if weekly then return db[prefix .. "Weekly"] end
    if trivial then return db[prefix .. "Trivial"] end
    if warbound then return db[prefix .. "WarboundCompleted"] end
    return db[prefix .. "Regular"]
end

function AQG:Print(...)
    print(ADDON_COLOR .. "AQG:|r", ...)
end

function AQG:Debug(...)
    if AutoQuestGossipDB.debugEnabled then
        self:Print(...)
    end
end

function AQG:DevSeparator(event)
    if AutoQuestGossipDB.devMode then
        print(SEPARATOR)
        self:Print("[" .. event .. "]")
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
