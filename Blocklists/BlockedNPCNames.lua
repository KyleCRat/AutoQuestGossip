local _, AQG = ...

-- NPCs to skip by name (partial match)
AQG.BlockedNPCNames = {
    -- Reason: Dragonriding race NPCs with multiple course options.
    --   Also matches: "Bronze Timekeeper Assistant".
    "Bronze Timekeeper",

    -- Reason: Time-walking NPC that phases you to a different
    --   timeline. Auto-selecting could unexpectedly phase you.
    "Zidormi",

    -- Reason: NPC that handles Mythic Keystone Options. Don't automate.
    "Lindormi",

    -- Reason: Should not auto select anything at the delver's supplies, all
    --   three options are equally used. Even if the supplies' ID changes
    --   we need to still block so use name.
    "Delvers' Supplies",
}
