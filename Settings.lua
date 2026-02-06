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
    AddCheckbox("acceptRegular", "Regular Quests", "Auto-accept standard one-time quests")

    AddHeader("Auto Turn In")
    AddCheckbox("questTurnInEnabled", "Enable Auto Turn In", "Automatically turn in completed quests")
    AddCheckbox("turnInDaily", "Daily Quests", "Auto turn-in daily quests")
    AddCheckbox("turnInWeekly", "Weekly Quests", "Auto turn-in weekly quests")
    AddCheckbox("turnInTrivial", "Trivial (Low Level) Quests", "Auto turn-in quests that are grey/trivial for your level")
    AddCheckbox("turnInWarboundCompleted", "Warbound Completed Quests", "Auto turn-in quests already completed on another character")
    AddCheckbox("turnInRegular", "Regular Quests", "Auto turn-in standard one-time quests")

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
        Settings.CreateDropdown(category, setting, GetModifierOptions, "Hold this key to pause or activate automation")
    end

    AddCheckbox("invertModifier", "Hold Modifier to ACTIVATE (instead of pause)",
        "When checked, automation only runs while the modifier key is held down. " ..
        "When unchecked, automation runs by default and pauses while the modifier is held.")

    -- Gossip Automation
    AddHeader("Gossip Automation")
    AddCheckbox("gossipEnabled", "Enable Gossip Automation", "Automatically select gossip options when talking to NPCs")
    AddCheckbox("gossipOnlySingle", "Only Auto-Select Single Option",
        "When enabled, gossip will only be auto-selected if there is exactly one option. " ..
        "If there are multiple options, you choose manually.")

    -- Debug
    AddHeader("Debug")
    AddCheckbox("debugEnabled", "Enable Debug Output", "Prints quest information to chat when a quest is automatically accepted")

    Settings.RegisterAddOnCategory(category)
    AQG.settingsCategory = category
end)
