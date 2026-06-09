# AutoQuestGossip

Automates quest accept/turn-in and gossip selection in World of Warcraft.

**Version:** 12.0.5-1

## Features

- **Quest Automation** - automatically accept and turn in quests from gossip windows, quest frames, and the objective tracker
- **Gossip Automation** - automatically select gossip options with smart filtering (quest > auto-select > vendor > safe fallback)
- **Quest Classification** - filter automation by quest type: daily, weekly, trivial, warbound completed, meta, and regular
- **Content Filters** - toggle automation for dungeon, raid, PvP, group, delve, and world boss quests
- **Safety Guards** - pauses on skip options, important (colored) options, angle bracket choices, cinematics, and Stay Awhile and Listen prompts
- **NPC Blocklists** - block automation for specific NPCs by ID or name
- **Modifier Key** - hold Shift, Ctrl, or Alt to temporarily pause all automation
- **Delve Turn-in Control** - separate setting for Delver's Call quest turn-ins
- **Debug Panel** - scrollable, copyable debug output anchored to quest/gossip frames or floating via `/aqg debug`
- **Dev Mode** - disables all actions while still printing debug info for testing

## Safety Model

AQG is heuristic-driven: routine quest and gossip interactions are automated by default, while known-risk categories are blocked. NPC blocklists are hard denies for specific NPCs, not an allowlist requirement.

Quest accept filters control what types of quests AQG may accept. The PvP content filter allows PvP-tagged quest content, but any quest that would flag your character for PvP still requires manual acceptance.

Gossip fallback selection is optional and only applies when there is exactly one safe, available, known-icon fallback option after quest, vendor, and Blizzard true single-option choices are ruled out.

## Commands

- `/aqg` - open the settings panel
- `/aqg debug` - toggle the detached debug panel
