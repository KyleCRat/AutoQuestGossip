local _, AQG = ...

local         GetOptions = C_GossipInfo.GetOptions
local       SelectOption = C_GossipInfo.SelectOption
local    GetActiveQuests = C_GossipInfo.GetActiveQuests
local GetAvailableQuests = C_GossipInfo.GetAvailableQuests

local selectedGossipIDs = {}

-- Gossip icon fileIDs (since Blizzard removed the type field in 10.0)
local ICON_VENDOR = 132060 -- VendorGossipIcon
local ICON_GOSSIP = 132053 -- GossipGossipIcon (chat bubble)

-- Icons we consider safe to automate
local SAFE_ICONS = {
    [ICON_VENDOR] = true,
    [ICON_GOSSIP] = true,
}

-- Icons that are known but should never be auto-selected.
-- Treated as "known" so they don't trigger the unknown-icon guard,
-- but options with these icons will always be skipped.
local ICON_BINDER      = 136458 -- BinderGossipIcon (innkeeper hearthstone bind)
local ICON_FLIGHTMASTER = 132057 -- TaxiGossipIcon (flight master)

local BLOCKED_ICONS = {
    [ICON_BINDER] = true,
    [ICON_FLIGHTMASTER] = true,
}

local MAX_GOSSIP_OPTIONS = 3

local function IsVendorOption(option)
    return option.icon == ICON_VENDOR or
        (option.overrideIconID and option.overrideIconID == ICON_VENDOR)
end

local function IconTag(option)
    local icon = option.overrideIconID or option.icon

    if icon then
        return "|T" .. icon .. ":0|t "
    end

    return ""
end

local function IsKnownIcon(option)
    local icon = option.overrideIconID or option.icon

    return icon and (SAFE_ICONS[icon] or BLOCKED_ICONS[icon])
end

local function IsBlockedIcon(option)
    local icon = option.overrideIconID or option.icon

    return icon and BLOCKED_ICONS[icon]
end

local function IsQuestOption(option)
    -- 000x bit set is a quest gossip
    if bit.band(option.flags, 1) ~= 0 then
        return true
    end

    return false
end

local function IsCinematicOption(option)
    -- 0x00 bit set is a cinematic gossip
    if bit.band(option.flags, 4) ~= 0 then
        return true
    end

    return false
end

local function DebugGossipOptions(options)
    AQG:DebugSeparator("GOSSIP_SHOW (Gossip)")

    for i, option in ipairs(options) do
        local id = tostring(option.gossipOptionID) or "nil"
        local icon_id = tostring(option.icon)

        local tags = ""

        if not option.gossipOptionID then
            tags = tags .. " [nil ID]"
        end

        if IsQuestOption(option) then
            tags = tags .. " [QUEST]"
        end

        if IsCinematicOption(option) then
            tags = tags .. " [CINEMATIC]"
        end

        if option.selectOptionWhenOnlyOption then
            tags = tags .. " [Auto-Select]"
        end

        if AQG:IsSkipOption(option) then
            tags = tags .. " [SKIP]"
        end

        if AQG:IsImportantOption(option) then
            tags = tags .. " [IMPORTANT]"
        end

        if AQG:IsAngleBracketOption(option) then
            tags = tags .. " [ANGLE-BRACKET]"
        end

        if AQG:IsStayAwhileOption(option) then
            tags = tags .. " [STAY-AWHILE]"
        end

        if IsVendorOption(option) then
            tags = tags .. " [VENDOR]"
        end

        if option.gossipOptionID and IsBlockedIcon(option) then
            tags = tags .. " [BLOCKED ICON]"
        elseif option.gossipOptionID and not IsKnownIcon(option) then
            tags = tags .. " [UNKNOWN ICON]"
        end

        AQG:Debug("  " .. i .. ". " .. IconTag(option) .. (option.name or "?")
            .. " (ID: " .. id .. ", iconID: " .. icon_id .. ")" .. tags)
    end
end

local function SelectGossip(option)
    if selectedGossipIDs[option.gossipOptionID] then
        AQG:Debug("-> Loop detected (auto-select option already selected).",
            "Would NOT auto-select.")
        AQG:Warn("Gossip loop detected — automation paused.")

        return false
    end

    -- Store the gossip ID we selected for loop detection
    selectedGossipIDs[option.gossipOptionID] = true

    -- If we have the mod key pressed, exit
    if AQG:PausedByModKey("Gossip") then return false end

    -- If we are in dev mode, don't take any actions
    if AutoQuestGossipDB.devMode then return false end

    AQG:Verbose("Gossip:",
        IconTag(option) .. (option.name or "?"),
        "(ID:", option.gossipOptionID .. ")")

    SelectOption(option.gossipOptionID)

    return true
end

AQG:RegisterEvent("GOSSIP_SHOW", function()
    local db      = AutoQuestGossipDB
    local options = GetOptions()

    -- DO NOTHING: If we do not have the gossip module enabled
    if not db.gossipEnabled then return end

    -- DO NOTHING: If there are no options for this event
    if not options or #options == 0 then return end

    -- DO NOTHING: Quest module runs first. If it selected a quest
    if AQG.questHandled then return end

    -- Check if the NPC is offering any quests (active or available).
    -- If so, don't auto-select gossip — the player should choose manually.
    local hasActiveQuests    = #GetActiveQuests() > 0
    local hasAvailableQuests = #GetAvailableQuests() > 0

    -- Check for skip/important text in gossip options
    local hasSkip, hasImportant, hasAngleBracket = AQG:GossipHasDangerousOption()

    -- Find vendor option
    -- auto-select flagged option
    -- Check for unknown (non-gossip, non-vendor) icon types
    local vendorOption
    local autoSelectOption
    local hasCinematicOption
    local hasStayAwhile  = false
    local questOptions   = {}
    local hasUnknownIcon = false

    for i, option in ipairs(options) do
        hasCinematicOption = IsCinematicOption(option)

        if option.gossipOptionID then
            if AQG:IsStayAwhileOption(option) then
                hasStayAwhile = true
            end

            if IsQuestOption(option) and not AQG:IsStayAwhileOption(option) then
                table.insert(questOptions, option)
            end

            if not vendorOption and IsVendorOption(option) then
                vendorOption = option
            end

            if not autoSelectOption and option.selectOptionWhenOnlyOption then
                autoSelectOption = option
            end

            if not hasUnknownIcon and not IsKnownIcon(option) then
                hasUnknownIcon = true
            end
        end
    end

    -- Debug: print gossip option listing
    DebugGossipOptions(options)

    -- DO NOTHING: If this NPC is on the blocked ID list
    local npcID = AQG:GetNPCID()
    if AQG.BlockedNPCIDs[npcID] then
        AQG:Debug("-> NPC ID", npcID, "is blocked.")

        return
    end

    -- DO NOTHING: If this NPC matches a blocked name
    local npcName = AQG:GetNPCName()
    for _, name in ipairs(AQG.BlockedNPCNames) do
        if npcName:find(name) then
            AQG:Debug("-> NPC name matches blocked:", name)

            return
        end
    end

    -- DO NOTHING: if a skip option is found
    if hasSkip then
        AQG:Debug("-> Skip option detected. Would NOT auto-select.")

        return
    end

    -- DO NOTHING: if an important dialog option is found
    if hasImportant then
        AQG:Debug("-> Important selection detected. Would NOT auto-select.")

        return
    end

    -- DO NOTHING: if an angle bracket option is found and setting is enabled
    if hasAngleBracket and db.pauseOnAngleBracket then
        AQG:Debug("-> Angle bracket option detected. Would NOT auto-select.")

        return
    end

    -- DO NOTHING: if quests are availble to pickup
    --   and there are no quests in progress
    if hasAvailableQuests and not hasActiveQuests then
        AQG:Debug("-> NPC has available quests. Would NOT auto-select gossip.")

        return
    end

    -- DO NOTHING: if there is a cinematic available
    if hasCinematicOption then
        AQG:Debug("-> NPC has a Cinematic. Would NOT auto-select gossip.")

        return
    end

    -- DO NOTHING: if there is a unknown icon
    if hasUnknownIcon then
        AQG:Debug("-> Unknown gossip icon type detected. Would NOT auto-select.")
        -- AQG:Warn("Unknown gossip type detected — automation paused.")

        return
    end

    -- DO NOTHING: if the user wants to pause on more than one gossip option
    if db.gossipOnlySingle and #options > 1 then
        AQG:Debug("-> Multiple options, single-only mode ON. Would NOT auto-select.")

        return
    end

    -- DO NOTHING: if there are multiple quest gossip options
    if #questOptions > 1 then
        AQG:Debug("-> Multiple Quest gossip options. Would NOT auto-select.")
        -- AQG:Warn("Multiple Quest gossip options — automation paused.")

        return
    end

    -- SELECT: Select quest gossip continuation option
    if #questOptions == 1 then
        local questOption = questOptions[1]

        AQG:Debug("-> Would auto-select Quest gossip:",
            IconTag(questOption) .. (questOption.name or "?"),
            "(ID:", questOption.gossipOptionID .. ")")

        SelectGossip(questOption)

        return
    end

    -- SELECT: Blizzard-flagged auto select option
    if autoSelectOption then
        AQG:Debug("-> Would auto-select Blizzard auto-select gossip:",
            IconTag(autoSelectOption) .. (autoSelectOption.name or "?"),
            "(ID:", autoSelectOption.gossipOptionID .. ")")

        SelectGossip(autoSelectOption)

        return
    end

    -- DO NOTHING: if a Stay Awhile option is present — quest and auto-select
    -- options above are still allowed, but vendor/fallback selection should not
    -- override a story prompt the player may want to click
    if hasStayAwhile then
        AQG:Debug("-> Stay Awhile option detected. Would NOT auto-select vendor or fallback.")
        AQG:Warn("Stay Awhile option detected — gossip paused.")

        return
    end

    -- TODO: Possibly want to avoid gossip if there are active quests?
    --
    -- DO NOTHING: if there are active quests at an NPC, and there is no
    -- auto-select option or quest option, don't do anything
    -- if hasActiveQuests then
    --     AQG:Debug("-> NPC has active quests.",
    --         "Would NOT auto-select vendor or first valid gossip.")

    --     return
    -- end

    -- SELECT: If there is a vendor option, prioritize selecting it
    if vendorOption then
        AQG:Debug("-> Would auto-select vendor option:",
            IconTag(vendorOption) .. (vendorOption.name or "?"),
            "(ID:", vendorOption.gossipOptionID .. ")")

        SelectGossip(vendorOption)

        return
    end

    -- DO NOTHING: If NPC has too many options (guards, dragonriding, etc.)
    if #options > MAX_GOSSIP_OPTIONS then
        AQG:Debug("-> NPC has", #options, "gossip options",
            "(>" .. MAX_GOSSIP_OPTIONS .. ").", "Skipping.")

        return
    end

    -- SELECT: First valid option
    for _, option in ipairs(options) do
        if option.gossipOptionID and not IsBlockedIcon(option) then
            AQG:Debug("Selecting:", option.gossipOptionID)
            SelectGossip(option)

            return
        end
    end

    AQG:Debug("No valid gossip option to auto-select.")
end)

-- Reset loop tracking when gossip window closes
AQG:RegisterEvent("GOSSIP_CLOSED", function()
    wipe(selectedGossipIDs)
end)
