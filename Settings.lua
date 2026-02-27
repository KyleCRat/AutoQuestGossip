local addonName, AQG = ...

AQG:OnInit(function()
    local category, layout = Settings.RegisterVerticalLayoutCategory("AutoQuestGossip")

    local function AddCheckbox(key, name, tooltip)
        local setting = Settings.RegisterAddOnSetting(category, key, key, AutoQuestGossipDB, "boolean", name, AutoQuestGossipDB[key])
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    local function AddHeader(text)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end

    -- Quest Automation
    AddHeader("Quest Automation")
    AddCheckbox("questEnabled", "Enable Quest Automation", "Master toggle for all quest automation")

    AddHeader("Auto Accept")
    AddCheckbox("questAcceptEnabled", "Enable Auto Accept", "Automatically accept quests when offered")
    AddCheckbox("acceptDaily", "Daily Quests", "Auto-accept daily quests")
    AddCheckbox("acceptWeekly", "Weekly Quests", "Auto-accept weekly quests")
    AddCheckbox("acceptTrivial", "Trivial (Low Level) Quests", "Auto-accept quests that are grey/trivial for your level")
    AddCheckbox("acceptWarboundCompleted", "Warbound Completed Quests", "Auto-accept quests already completed on another character")
    AddCheckbox("acceptMeta", "Meta Quests", "Auto-accept meta/achievement quests")
    AddCheckbox("acceptRegular", "Regular Quests", "Auto-accept standard one-time quests")

    AddHeader("Auto Turn In")
    AddCheckbox("questTurnInEnabled", "Enable Auto Turn In", "Automatically turn in completed quests")
    -- AddCheckbox("turnInDaily", "Daily Quests", "Auto turn-in daily quests")
    -- AddCheckbox("turnInWeekly", "Weekly Quests", "Auto turn-in weekly quests")
    -- AddCheckbox("turnInTrivial", "Trivial (Low Level) Quests", "Auto turn-in quests that are grey/trivial for your level")
    -- AddCheckbox("turnInWarboundCompleted", "Warbound Completed Quests", "Auto turn-in quests already completed on another character")
    -- AddCheckbox("turnInMeta", "Meta Quests", "Auto turn-in meta/achievement quests")
    -- AddCheckbox("turnInRegular", "Regular Quests", "Auto turn-in standard one-time quests")

    -- Content Type Filters
    AddHeader("Content Type Filters")
    AddCheckbox("contentDungeon", "Dungeon Quests", "Allow automation of quests tagged as dungeon content")
    AddCheckbox("contentRaid", "Raid Quests", "Allow automation of quests tagged as raid content")
    AddCheckbox("contentPvP", "PvP Quests", "Allow automation of quests tagged as PvP content")
    AddCheckbox("contentGroup", "Group Quests", "Allow automation of quests tagged as requiring a group")
    AddCheckbox("contentDelve", "Delve Quests", "Allow automation of quests tagged as delve content")
    AddCheckbox("contentWorldBoss", "World Boss Quests", "Allow automation of quests tagged as world boss content")

    -- Modifier Key
    AddHeader("Modifier Key")

    do
        local function GetModifierOptions()
            local container = Settings.CreateControlTextContainer()
            container:Add("SHIFT", "Shift")
            container:Add("CTRL", "Ctrl")
            container:Add("ALT", "Alt")
            return container:GetData()
        end

        local setting = Settings.RegisterAddOnSetting(
            category, "modifierKey", "modifierKey", AutoQuestGossipDB, "string", "Modifier Key", AutoQuestGossipDB.modifierKey
        )
        Settings.CreateDropdown(category, setting, GetModifierOptions, "Hold this key to pause automation")
    end

    -- Gossip Automation
    AddHeader("Gossip Automation")
    AddCheckbox("gossipEnabled", "Enable Gossip Automation", "Automatically select gossip options when talking to NPCs")
    AddCheckbox("gossipOnlySingle", "Only Auto-Select Single Option",
        "When enabled, gossip will only be auto-selected if there is exactly one option. " ..
        "If there are multiple options, you choose manually.")
    AddCheckbox("pauseOnAngleBracket", "Pause on Bracket <Option>",
        "Pause automation when a gossip option contains angle bracket text (e.g. <Do something>). " ..
        "These often indicate player choices that may have consequences.")

    -- Output Modes
    AddHeader("Output Modes")
    AddCheckbox("verboseEnabled", "Verbose", "Print short messages to chat when the addon acts (e.g. 'Accept: Quest Name')")

    do
        local debugSetting = Settings.RegisterAddOnSetting(
            category, "debugEnabled", "debugEnabled", AutoQuestGossipDB, "boolean", "Debug", AutoQuestGossipDB.debugEnabled
        )
        Settings.CreateCheckbox(category, debugSetting,
            "Show the debug panel with full details on every quest and gossip interaction. " ..
            "Automation continues to work normally. Use /aqg debug to open the panel standalone.")

        local devSetting = Settings.RegisterAddOnSetting(
            category, "devMode", "devMode", AutoQuestGossipDB, "boolean", "Dev Mode", AutoQuestGossipDB.devMode
        )
        Settings.CreateCheckbox(category, devSetting,
            "Disables all automation so you can step through interactions manually. " ..
            "Requires Debug mode (will be enabled automatically).")

        -- Enabling Dev Mode -> also enable Debug
        Settings.SetOnValueChangedCallback("devMode", function(_, _, newValue)
            if newValue then
                AutoQuestGossipDB.debugEnabled = true
                debugSetting:SetValue(true)
            end
        end)

        -- Disabling Debug -> also disable Dev Mode
        Settings.SetOnValueChangedCallback("debugEnabled", function(_, _, newValue)
            if not newValue then
                AutoQuestGossipDB.devMode = false
                devSetting:SetValue(false)
            end
        end)
    end

    Settings.RegisterAddOnCategory(category)
    AQG.settingsCategory = category
end)
