# Changelog

## [12.0.5-1] - 2026-04-20
- Automate quest accept/turn-in from gossip, quest detail, quest progress, quest complete, and quest autocomplete events
- Automate gossip option selection with icon-based filtering and priority chain (quest > auto-select > vendor > first valid)
- Support QUEST_GREETING for NPCs with quests but no gossip options
- Classify quests by type: daily, weekly, trivial, warbound completed, meta, and regular
- Content type filters for dungeon, raid, PvP, group, delve, and world boss quests
- Modifier key (shift/ctrl/alt) to pause automation when held
- Gossip loop detection with automatic reset on gossip close
- NPC blocklists by ID and name (Soiree NPCs, Zidormi, Lindormi, Teleport Pad, Delvers' Supplies, etc.)
- Pause on skip options, important (colored) options, angle bracket options, and cinematics
- Stay Awhile and Listen detection — blocks vendor/fallback selection while allowing quest options
- Setting to control Delver's Call quest turn-ins separately
- Debug panel with scrollable, copyable output anchored to quest/gossip frames
- Detached debug panel mode via `/aqg debug`
- Dev mode: disables all actions while still printing debug info
- Verbose mode for short chat messages on each action
- Settings panel with full configuration via the WoW addon settings UI
