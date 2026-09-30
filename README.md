# WoWForeverAddons

Addons for World of Warcraft: Forever (client 1.60.1, interface 16001).

| Addon | What it does |
|---|---|
| [Forever Flight Timer](ForeverFlightTimer/README.md) | Learns your flight-path times and counts down to landing, with the arrival time and flight-map tooltips. |
| [Forever Instance Timer](ForeverInstanceTimer/README.md) | Times your dungeon, raid and battleground runs, and keeps counting through corpse runs. |
| [Forever Addon Fixes](ForeverAddonFixes/README.md) | Fixes Lua errors that other addons (GearQuestForever, AtlasLoot) throw on WoW Forever, without editing their files. |

## Installing
1. Download the addon's zip from [Releases](../../releases).
2. Extract it into your WoW Forever installation's `Interface\AddOns` folder. On the beta client that is `World of Warcraft\_classic_beta_\Interface\AddOns`. You should get, for example, `Interface\AddOns\ForeverFlightTimer\ForeverFlightTimer.toc`.
3. Restart the game.

## License
- **The addons' own code:** [MIT](LICENSE).
- **Libraries bundled in Forever Flight Timer and Forever Instance Timer** (`Libs/`): they keep their own licenses. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Development
Tests, releasing and copying the addons into the game: see [DEVELOPMENT.md](DEVELOPMENT.md).
