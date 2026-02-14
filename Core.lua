local addonName, AQG = ...

-- Constants
local ADDON_COLOR = "|cff00ccff"
local SEPARATOR = ADDON_COLOR ..
    "--- AQG ----------------------------------------|r"

local RETRY_TIME_DELAY = .25

local QuestAccountComplete = C_QuestLog.IsQuestFlaggedCompletedOnAccount
local IsRepeatableQuest    = C_QuestLog.IsRepeatableQuest
local GetQuestTagInfo      = C_QuestLog.GetQuestTagInfo
local IsQuestTrivial       = C_QuestLog.IsQuestTrivial
local GetTitleForQuestID   = C_QuestLog.GetTitleForQuestID

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

-- Default settings
local defaults = {
    -- Quest settings
    questEnabled = true,

    -- Quest Accept Settings
    questAcceptEnabled = true,
    acceptDaily = true,
    acceptWeekly = true,
    acceptTrivial = false,
    acceptWarboundCompleted = false,
    acceptMeta = false,
    acceptRegular = true,

    -- Content type filters (all default enabled)
    contentDungeon = true,
    contentRaid = true,
    contentPvP = true,
    contentGroup = true,
    contentDelve = true,
    contentWorldBoss = true,

    -- Quest Turn in Settings
    questTurnInEnabled = true,
    -- turnInDaily = true,
    -- turnInWeekly = true,
    -- turnInTrivial = false,
    -- turnInWarboundCompleted = false,
    -- turnInMeta = false,
    -- turnInRegular = true,
    modifierKey = "SHIFT",

    -- Gossip settings
    gossipEnabled = true,
    gossipOnlySingle = true,

    -- Output modes
    verboseEnabled = false,
    debugEnabled = false,
    devMode = false,
}

-- Shared addon table
AQG.questHandled = false -- flag to prevent gossip firing after quest selection

local function IsModifierDown()
    local key = AutoQuestGossipDB.modifierKey

    if     key == "SHIFT" then return IsShiftKeyDown()
    elseif key == "CTRL"  then return IsControlKeyDown()
    elseif key == "ALT"   then return IsAltKeyDown()
    end

    return false
end

function AQG:PausedByModKey(module_name)
    if IsModifierDown() then
        self:Debug("|cffff4444->", "["..module_name.."] Modifier key held",
                   " — automation paused.|r")
        return true
    end

    return false
end

function AQG:ClassifyQuest(questOrID)
    local quest = type(questOrID) == "table"
                  and questOrID or { questID = questOrID }

    local questID = quest.questID
    -- Enum.QuestFrequency: 0=Default, 1=Daily, 2=Weekly
    local isDaily = (quest.frequency == 1)
                    or (QuestIsDaily and QuestIsDaily())
    local isWeekly = (quest.frequency == 2)
                     or (QuestIsWeekly and QuestIsWeekly())
    local isMetaQuest = quest.isMeta or false

    -- Check GetQuestTagInfo for additional data
    local tagInfo = questID and
                    GetQuestTagInfo and
                    GetQuestTagInfo(questID)

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
        if IsRepeatableQuest and
           IsRepeatableQuest(questID) then
            isDaily = true
        end
    end

    local isTrivialQuest = quest.isTrivial
                          or (IsQuestTrivial and IsQuestTrivial(questID))

    local isWarboundCompleted = QuestAccountComplete and QuestAccountComplete(questID)

    return isDaily, isWeekly, isTrivialQuest, isWarboundCompleted, isMetaQuest
end

function AQG:DebugQuestAPIs(questID)
    if not AutoQuestGossipDB.debugEnabled then return end
    self:Debug("  Raw APIs:")

    if QuestIsDaily then
        self:Debug("    QuestIsDaily() =", tostring(QuestIsDaily()))
    end

    if QuestIsWeekly then
        self:Debug("    QuestIsWeekly() =", tostring(QuestIsWeekly()))
    end

    if questID then
        if IsQuestTrivial then
            self:Debug("    IsQuestTrivial =",
                tostring(IsQuestTrivial(questID)))
        end

        if QuestAccountComplete then
            self:Debug("    WarboundCompleted =",
                tostring(QuestAccountComplete(questID)))
        end

        if IsRepeatableQuest then
            self:Debug("    IsRepeatable =",
                tostring(IsRepeatableQuest(questID)))
        end

        local tagInfo = GetQuestTagInfo and GetQuestTagInfo(questID)

        if tagInfo then
            self:Debug("    tagID =",          tostring(tagInfo.tagID))
            self:Debug("    tagName =",        tostring(tagInfo.tagName))
            self:Debug("    worldQuestType =", tostring(tagInfo.worldQuestType))

            local contentKey = CONTENT_TAG_MAP[tagInfo.tagID]

            if contentKey then
                self:Debug("    contentFilter =", contentKey)
            end
        else
            self:Debug("    tagInfo = nil")
        end
    end
end

function AQG:GetContentFilterKey(questID)
    local tagInfo = questID and
        GetQuestTagInfo and GetQuestTagInfo(questID)

    if tagInfo and tagInfo.tagID then
        return CONTENT_TAG_MAP[tagInfo.tagID]
    end

    return nil
end

function AQG:ShouldAllowContent(questID)
    local key = self:GetContentFilterKey(questID)

    if key then
        AQG:Debug("Content Type:", key,
            AutoQuestGossipDB[key] and "Allowed by settings."
                                   or "Disallowed by settings.")

        return AutoQuestGossipDB[key]
    end

    return true -- no content tag = always allow
end

function AQG:IsQuestDataReady(questID, funcToRetry)
    if not questID or questID == 0 then
        return true
    end

    if GetTitleForQuestID(questID) then
        return true
    end

    if funcToRetry then
        self:Debug("|cffff4444[!] Quest data not cached,"
            .. " retrying...|r")
        C_Timer.After(RETRY_TIME_DELAY, function()
            funcToRetry(questID)
        end)
    end

    return false
end

function AQG:AreQuestsCached(quests, funcToRetry)
    for _, quest in ipairs(quests) do
        local id = quest.questID

        if id and id ~= 0
            and not GetTitleForQuestID(id) then

            if funcToRetry then
                self:Debug("|cffff4444[!] Quest data not cached,",
                           "retrying...|r")

                C_Timer.After(RETRY_TIME_DELAY, funcToRetry)
            end

            return false
        end
    end

    return true
end

function AQG:GetNPCName()
    return UnitName("npc") or "?"
end

function AQG:GetNPCID()
    local guid = UnitGUID("npc")

    return guid and select(6, strsplit("-", guid)) or "?"
end

function AQG:IsSkipOption(option)
    return option.name and
           option.name:lower():find("skip") ~= nil
end

function AQG:IsImportantOption(option)
    return option.name and
           (option.name:find("<.+>") or option.name:find("|c")) ~= nil
end

-- Check if any gossip option has dangerous/important text that should pause all automation
function AQG:GossipHasDangerousOption()
    local options = C_GossipInfo.GetOptions()

    if not options then return false, false end

    local hasSkip, hasImportant = false, false

    for _, option in ipairs(options) do
        if not hasSkip and self:IsSkipOption(option) then
            hasSkip = true
        end

        if not hasImportant and self:IsImportantOption(option) then
            hasImportant = true
        end

        if hasSkip and hasImportant then break end
    end

    return hasSkip, hasImportant
end

-- Check if a quest needs currency
function AQG:QuestItemIsCurrency()
    local currenciesRequired =
          GetNumQuestCurrencies and GetNumQuestCurrencies() or 0

    return currenciesRequired > 0
end

-- Check if a quest needs crafting reagents
function AQG:QuestItemIsReagent()
    local count = GetNumQuestItems and GetNumQuestItems() or 0

    for i = 1, count do
        local name, _, _, _, _, itemID = GetQuestItemInfo("required", i)

        if name and itemID then
            local isReagent = select(17, C_Item.GetItemInfo(itemID))

            if isReagent then
                return true, name
            end
        end
    end

    return false
end

function AQG:ShouldAccept(questOrID)
    local quest = type(questOrID) == "table"
                  and questOrID or { questID = questOrID }

    if not self:ShouldAllowContent(quest.questID) then return false end

    local db = AutoQuestGossipDB
    local daily, weekly, trivial, warbound, meta =
          self:ClassifyQuest(quest)

    -- Return if the user has the quest type automation enabled
    if     meta then return db.acceptMeta end
    if    daily then return db.acceptDaily end
    if   weekly then return db.acceptWeekly end
    if  trivial then return db.acceptTrivial end
    if warbound then return db.acceptWarboundCompleted end

    return db.acceptRegular
end

-- TODO: Remove once confirmed we don't want per-quest-type turn in checks.
-- 90% sure we can just get rid of this, if we want to auto-turn in quests any
-- quest we complete we should just turn in. Just becuase it's a dungeon quest
-- that we don't want to automate, if I manually grab one and I have auto-turn
-- in enabled. That most likey means I'd want it to auto-turn in not just ignore
-- it randomly becuase of a content type block or something.
--
-- Remove all auto-turn in settings except for the primary turn in true / false
--
-- function AQG:ShouldTurnIn(questOrID)
--     local quest = type(questOrID) == "table"
--                   and questOrID or { questID = questOrID }

--     if not self:ShouldAllowContent(quest.questID) then return false end

--     local db = AutoQuestGossipDB
--     local daily, weekly, trivial, warbound, meta =
--           self:ClassifyQuest(quest)

--     -- Return if the user has the quest type automation enabled
--     if meta     then return db.turnInMeta end
--     if daily    then return db.turnInDaily end
--     if weekly   then return db.turnInWeekly end
--     if trivial  then return db.turnInTrivial end
--     if warbound then return db.turnInWarboundCompleted end

--     return db.turnInRegular
-- end

local function ArgsToString(...)
    local parts = {}

    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end

    return table.concat(parts, " ")
end

-- Warn: always prints to chat, also to panel if debug enabled
function AQG:Warn(...)
    if AutoQuestGossipDB and AutoQuestGossipDB.debugEnabled and self.PanelPrint then
        self:PanelPrint("|cffff4444[!] " .. ArgsToString(...) .. "|r")
    end

    print(ADDON_COLOR .. "AQG:|r |cffff4444" ..
          "\124TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:0|t", ..., "|r")
end

-- Verbose: short end-user messages to chat
function AQG:Verbose(...)
    if not AutoQuestGossipDB.verboseEnabled then return end

    print(ADDON_COLOR .. "AQG:|r", ...)
end

-- Debug: detailed output to panel only, never to chat
function AQG:Debug(...)
    if not AutoQuestGossipDB.debugEnabled then return end

    if self.PanelPrint then
        self:PanelPrint(ArgsToString(...))
    end
end

-- DebugSeparator: section header in the debug panel
function AQG:DebugSeparator(event)
    if not AutoQuestGossipDB.debugEnabled or
       not self.PanelPrint then return end

    self:PanelPrint(
        "|cff00ccff--- " .. event .. " ---|r"
    )
    self:PanelPrint(
        "NPC: " .. self:GetNPCName()
        .. " (ID: " .. self:GetNPCID() .. ")"
    )

    -- Ensure panel is visible (fallback if OnShow hook missed)
    if self.ShowPanel then
        local anchor =
            (DUIQuestFrame and DUIQuestFrame:IsShown() and DUIQuestFrame)
            or (GossipFrame and GossipFrame:IsShown() and GossipFrame)
            or (QuestFrame and QuestFrame:IsShown() and QuestFrame)

        if anchor then self:ShowPanel(anchor) end
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
                for _, func in ipairs(AQG.onInit) do
                    func()
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
SlashCmdList["AUTOQUESTGOSSIP"] = function(msg)
    local cmd = strtrim(msg):lower()

    if cmd == "debug" then
        if not AutoQuestGossipDB.debugEnabled then
            AutoQuestGossipDB.debugEnabled = true
            AQG:Debug("Debug mode enabled.")
        end

        if AQG.ToggleDetachedPanel then
            AQG:ToggleDetachedPanel()
        end
    else
        if AQG.settingsCategory then
            Settings.OpenToCategory(AQG.settingsCategory:GetID())
        end
    end
end
