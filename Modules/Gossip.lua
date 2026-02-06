local _, AQG = ...

AQG:RegisterEvent("GOSSIP_SHOW", function()
    -- Quest module runs first on the same event. If it selected a quest, skip gossip.
    if AQG.questHandled then return end

    local db = AutoQuestGossipDB
    if not db.gossipEnabled or not AQG:ShouldProceed() then return end

    local options = C_GossipInfo.GetOptions()
    if not options or #options == 0 then return end

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

    -- Debug: print detailed gossip info to debug panel
    if db.debugEnabled then
        AQG:DebugSeparator("GOSSIP_SHOW (Gossip)")
        AQG:Print("Gossip options (" .. #options .. "):")
        local wouldSelect = nil
        local blocked = db.gossipOnlySingle and #options > 1
        for i, option in ipairs(options) do
            local id = option.gossipOptionID or "nil"
            local autoSelect = option.selectOptionWhenOnlyOption and " [Blizzard auto-selects]" or ""
            local nilTag = not option.gossipOptionID and " [nil ID, blocked]" or ""
            local skipTag = (option.name and option.name:lower():find("skip")) and " [SKIP detected]" or ""
            local importantTag = (option.name and (option.name:find("<.+>") or option.name:find("|c"))) and " [IMPORTANT detected]" or ""
            AQG:Print("  " .. i .. ". " .. (option.name or "?") .. " (ID: " .. tostring(id) .. ")" .. autoSelect .. nilTag .. skipTag .. importantTag)
            if not wouldSelect and option.gossipOptionID and not option.selectOptionWhenOnlyOption then
                wouldSelect = i
            end
        end
        if hasSkip then
            AQG:Print("-> Skip option detected. Would NOT auto-select.")
        elseif hasImportant then
            AQG:Print("-> Important selection detected. Would NOT auto-select.")
        elseif blocked then
            AQG:Print("-> Multiple options, single-only mode ON. Would NOT auto-select.")
        elseif wouldSelect then
            AQG:Print("-> Would auto-select option " .. wouldSelect .. ": " .. (options[wouldSelect].name or "?"))
        else
            AQG:Print("-> No valid option to auto-select.")
        end
    end

    -- Dev mode: block automation after printing
    if db.devMode then return end

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

    -- If user wants single-option-only mode and there are multiple options, stop
    if db.gossipOnlySingle and #options > 1 then return end

    -- Select the first valid option
    for _, option in ipairs(options) do
        -- Skip options with nil gossipOptionID (Blizzard uses this to prevent automation)
        if option.gossipOptionID then
            -- Skip if Blizzard already auto-selects this option
            if not option.selectOptionWhenOnlyOption then
                AQG:Verbose("Gossip:", option.name or "?", "(ID:", option.gossipOptionID .. ")")
                AQG:Debug("Auto-select gossip:", option.name or "?", "(ID:", option.gossipOptionID .. ")")
                C_GossipInfo.SelectOption(option.gossipOptionID)
            end
            return
        end
    end
end)
