local _, AQG = ...

-- Quests that AQG must never accept automatically.
AQG.BlockedQuestIDs = {
    -- Many Fine Heroes (Vol'dun faction assault)
    -- Reason: Unwanted automatically pushed faction assault quest.
    [54134] = true,
}
