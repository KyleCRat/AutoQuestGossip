local _, AQG = ...

AQG:RegisterEvent("GOSSIP_SHOW", function()
    -- Quest module runs first on the same event. If it selected a quest, skip gossip.
    if AQG.questHandled then return end

    local db = AutoQuestGossipDB
    if not db.gossipEnabled or not AQG:ShouldProceed() then return end

    local options = C_GossipInfo.GetOptions()
    if not options or #options == 0 then return end

    -- Dev mode: print options and what we would select, but don't act
    if db.devMode then
        AQG:DevSeparator("GOSSIP_SHOW (Gossip)")
        AQG:Print("Gossip options (" .. #options .. "):")
        local wouldSelect = nil
        local blocked = db.gossipOnlySingle and #options > 1
        for i, option in ipairs(options) do
            local id = option.gossipOptionID or "nil"
            local autoSelect = option.selectOptionWhenOnlyOption and " [Blizzard auto-selects]" or ""
            local nilTag = not option.gossipOptionID and " [nil ID, blocked]" or ""
            AQG:Print("  " .. i .. ". " .. (option.name or "?") .. " (ID: " .. tostring(id) .. ")" .. autoSelect .. nilTag)
            if not wouldSelect and option.gossipOptionID and not option.selectOptionWhenOnlyOption then
                wouldSelect = i
            end
        end
        if blocked then
            AQG:Print("-> Multiple options, single-only mode ON. Would NOT auto-select.")
        elseif wouldSelect then
            AQG:Print("-> Would auto-select option " .. wouldSelect .. ": " .. (options[wouldSelect].name or "?"))
        else
            AQG:Print("-> No valid option to auto-select.")
        end
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
                AQG:Debug("Auto-select gossip:", option.name or "?", "(ID:", option.gossipOptionID .. ")")
                C_GossipInfo.SelectOption(option.gossipOptionID)
            end
            return
        end
    end
end)
