local addonName, AQG = ...

-- Constants
local ADDON_COLOR = "|cff00ccff"

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
    questTurnInDelve = false,
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
    allowSafeFallbackGossip = true,
    pauseOnAngleBracket = true,

    -- Output modes
    verboseEnabled = false,
    debugEnabled = false,
    devMode = false,
}

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
                   " - automation paused.|r")
        return true
    end

    return false
end

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
