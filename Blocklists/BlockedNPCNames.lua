local _, AQG = ...

-- NPCs to skip by name (partial match)
AQG.BlockedNPCNames = {
    -- Reason: Dragonriding race NPCs with multiple course options.
    --   Also matches: "Bronze Timekeeper Assistant".
    "Bronze Timekeeper",

    -- Reason: Time-walking NPC that phases you to a different
    --   timeline. Auto-selecting could unexpectedly phase you.
    "Zidormi",
}
