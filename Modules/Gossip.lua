local _, AQG = ...

local selectedGossipIDs = {}

-- Gossip icon fileIDs (since Blizzard removed the type field in 10.0)
local ICON_VENDOR = 132060 -- VendorGossipIcon
local ICON_GOSSIP = 132053 -- GossipGossipIcon (chat bubble)

-- Icons we consider safe to automate
local SAFE_ICONS = {
    [ICON_VENDOR] = true,
    [ICON_GOSSIP] = true,
}

local function IsVendorOption(option)
    return option.icon == ICON_VENDOR or (option.overrideIconID and option.overrideIconID == ICON_VENDOR)
end

local function IconTag(option)
    local icon = option.overrideIconID or option.icon
    if icon then
        return "|T" .. icon .. ":0|t "
    end
    return ""
end

local function IsSafeIcon(option)
    local icon = option.overrideIconID or option.icon
    return icon and SAFE_ICONS[icon]
end

AQG:RegisterEvent("GOSSIP_SHOW", function()
    -- Quest module runs first on the same event. If it selected a quest, skip gossip.
    if AQG.questHandled then return end

    local db = AutoQuestGossipDB
    if not db.gossipEnabled or not AQG:ShouldProceed() then return end

    local options = C_GossipInfo.GetOptions()
    if not options or #options == 0 then return end

    -- Guards and directory NPCs typically have 10+ options (directions to bank, AH, etc.)
    -- Skip automation entirely for these NPCs.
    local MAX_GOSSIP_OPTIONS = 8
    if #options > MAX_GOSSIP_OPTIONS then
        AQG:Debug("NPC has", #options, "gossip options (>" .. MAX_GOSSIP_OPTIONS .. "). Likely a guard — skipping.")
        return
    end

    -- Check if the NPC is offering any quests (active or available).
    -- If so, don't auto-select gossip — the player should choose manually.
    local activeQuests = C_GossipInfo.GetActiveQuests()
    local availableQuests = C_GossipInfo.GetAvailableQuests()
    local hasQuests = (#activeQuests > 0) or (#availableQuests > 0)

    -- Check if any option contains "Skip" — these are story/intro skip prompts that
    -- should always pause automation so the player can choose intentionally.
    local hasSkip = false
    for _, option in ipairs(options) do
        if option.name and option.name:lower():find("skip") then
            hasSkip = true
            break
        end
    end

    -- Check if any option has <angle bracket> text or colored text (|c escape codes),
    -- which indicates important choices the player should review.
    local hasImportant = false
    for _, option in ipairs(options) do
        if option.name and (option.name:find("<.+>") or option.name:find("|c")) then
            hasImportant = true
            break
        end
    end

    -- Only skip selectOptionWhenOnlyOption when Blizzard is actually handling it (single option)
    local blizzardHandled = #options == 1

    -- Check for unknown (non-gossip, non-vendor) icon types
    local hasUnknownIcon = false
    for _, option in ipairs(options) do
        if option.gossipOptionID and not IsSafeIcon(option) then
            hasUnknownIcon = true
            break
        end
    end

    -- Find vendor option, auto-select flagged option, and first valid gossip option
    local vendorOption, autoSelectOption, firstOption
    for i, option in ipairs(options) do
        if option.gossipOptionID then
            if not vendorOption and IsVendorOption(option) then vendorOption = i end
            if not autoSelectOption and not blizzardHandled and option.selectOptionWhenOnlyOption then autoSelectOption = i end
            if not firstOption and not (blizzardHandled and option.selectOptionWhenOnlyOption) then firstOption = i end
        end
    end

    -- Debug: print detailed gossip info to debug panel
    if db.debugEnabled then
        AQG:DebugSeparator("GOSSIP_SHOW (Gossip)")
        AQG:Print("Gossip options (" .. #options .. "):")
        for i, option in ipairs(options) do
            local id = option.gossipOptionID or "nil"
            local autoSelect = option.selectOptionWhenOnlyOption and (blizzardHandled and " [Blizzard handling]" or " [auto-select flag]") or ""
            local nilTag = not option.gossipOptionID and " [nil ID, blocked]" or ""
            local skipTag = (option.name and option.name:lower():find("skip")) and " [SKIP detected]" or ""
            local importantTag = (option.name and (option.name:find("<.+>") or option.name:find("|c"))) and " [IMPORTANT detected]" or ""
            local vendorTag = IsVendorOption(option) and " [VENDOR]" or ""
            local unknownTag = (option.gossipOptionID and not option.selectOptionWhenOnlyOption and not IsSafeIcon(option)) and " [UNKNOWN ICON]" or ""
            AQG:Print("  " .. i .. ". " .. IconTag(option) .. (option.name or "?") .. " (ID: " .. tostring(id) .. ", icon: " .. tostring(option.icon) .. ")" .. autoSelect .. nilTag .. skipTag .. importantTag .. vendorTag .. unknownTag)
        end

        local blocked = db.gossipOnlySingle and #options > 1
        if hasQuests then
            AQG:Print("-> NPC has quests. Would NOT auto-select gossip.")
        elseif hasSkip then
            AQG:Print("-> Skip option detected. Would NOT auto-select.")
        elseif hasImportant then
            AQG:Print("-> Important selection detected. Would NOT auto-select.")
        elseif hasUnknownIcon then
            AQG:Print("-> Unknown gossip icon type detected. Would NOT auto-select.")
        elseif blocked then
            AQG:Print("-> Multiple options, single-only mode ON. Would NOT auto-select.")
        elseif autoSelectOption then
            if selectedGossipIDs[options[autoSelectOption].gossipOptionID] then
                AQG:Print("-> Loop detected (auto-select option already selected). Would NOT auto-select.")
            else
                AQG:Print("-> Would auto-select flagged option " .. autoSelectOption .. ": " .. (options[autoSelectOption].name or "?"))
            end
        elseif vendorOption then
            if selectedGossipIDs[options[vendorOption].gossipOptionID] then
                AQG:Print("-> Loop detected (vendor option already selected). Would NOT auto-select.")
            else
                AQG:Print("-> Would auto-select VENDOR option " .. vendorOption .. ": " .. (options[vendorOption].name or "?"))
            end
        elseif firstOption then
            if selectedGossipIDs[options[firstOption].gossipOptionID] then
                AQG:Print("-> Loop detected (option already selected this conversation). Would NOT auto-select.")
            else
                AQG:Print("-> Would auto-select option " .. firstOption .. ": " .. (options[firstOption].name or "?"))
            end
        else
            AQG:Print("-> No valid option to auto-select.")
        end
    end

    -- Dev mode: block automation after printing
    if db.devMode then return end

    -- If NPC has quests, don't auto-select gossip
    if hasQuests then return end

    -- If any option contains "Skip", pause automation so the player can choose
    if hasSkip then
        AQG:Warn("Skip option detected — automation paused.")
        return
    end

    -- If any option has important markers (brackets, colored text), pause automation
    if hasImportant then
        AQG:Warn("Important selections detected — automation paused.")
        return
    end

    -- If any option has an unknown icon type, pause and let user handle manually
    if hasUnknownIcon then
        AQG:Warn("Unknown gossip type detected — automation paused.")
        return
    end

    -- Helper to select a gossip option with loop detection
    local function SelectGossip(option)
        if selectedGossipIDs[option.gossipOptionID] then
            AQG:Warn("Gossip loop detected — automation paused.")
            return false
        end
        selectedGossipIDs[option.gossipOptionID] = true
        AQG:Verbose("Gossip:", IconTag(option) .. (option.name or "?"), "(ID:", option.gossipOptionID .. ")")
        AQG:Debug("Auto-select gossip:", IconTag(option) .. (option.name or "?"), "(ID:", option.gossipOptionID .. ")")
        C_GossipInfo.SelectOption(option.gossipOptionID)
        return true
    end

    -- Respect single-only mode first
    if db.gossipOnlySingle and #options > 1 then return end

    -- If Blizzard flagged an option for auto-select (multiple options), follow their lead
    if autoSelectOption then
        SelectGossip(options[autoSelectOption])
        return
    end

    -- If there's a vendor option, prefer it over regular gossip
    if vendorOption then
        SelectGossip(options[vendorOption])
        return
    end

    -- Select the first valid option
    for _, option in ipairs(options) do
        if option.gossipOptionID then
            -- Only skip if Blizzard is actually handling it (single option with the flag)
            if blizzardHandled and option.selectOptionWhenOnlyOption then return end
            SelectGossip(option)
            return
        end
    end
end)

-- Reset loop tracking when gossip window closes
AQG:RegisterEvent("GOSSIP_CLOSED", function()
    wipe(selectedGossipIDs)
end)
