# AutoQuestGossip

Automates quest accept/turn-in and gossip selection in World of Warcraft.

**Version:** 12.0.5-1

## Features

- **Quest Automation** — automatically accept and turn in quests from gossip windows, quest frames, and the objective tracker
- **Gossip Automation** — automatically select gossip options with smart filtering (quest > auto-select > vendor > first valid)
- **Quest Classification** — filter automation by quest type: daily, weekly, trivial, warbound completed, meta, and regular
- **Content Filters** — toggle automation for dungeon, raid, PvP, group, delve, and world boss quests
- **Safety Guards** — pauses on skip options, important (colored) options, angle bracket choices, cinematics, and Stay Awhile and Listen prompts
- **NPC Blocklists** — block automation for specific NPCs by ID or name
- **Modifier Key** — hold Shift, Ctrl, or Alt to temporarily pause all automation
- **Delve Turn-in Control** — separate setting for Delver's Call quest turn-ins
- **Debug Panel** — scrollable, copyable debug output anchored to quest/gossip frames or floating via `/aqg debug`
- **Dev Mode** — disables all actions while still printing debug info for testing

## Commands

- `/aqg` — open the settings panel
- `/aqg debug` — toggle the detached debug panel
