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

## Releasing
Each addon has its own version and releases.
1. Set `## Version:` in `<Addon>/<Addon>.toc` to the new version, then commit and push.
2. Tag that commit `<Addon>-v<version>`, for example `ForeverAddonFixes-v1.1.0`, and push the tag:
   ```
   git tag ForeverAddonFixes-v1.1.0
   git push origin ForeverAddonFixes-v1.1.0
   ```

The [Release workflow](.github/workflows/release.yml) then:
1. checks that the tag's version equals the toc's `## Version`;
2. waits for the commit's Tests run, and refuses to release unless it passed;
3. builds `<Addon>-<version>.zip` without the addon's `tests` folder;
4. publishes a GitHub release with that zip, and notes listing the commits that changed the addon since its previous release.

Good to know:
- **Tag a commit that was the last one in a push.** GitHub runs Tests only for the last commit of each push, so other commits have no test run and the release is refused. The error message explains how to get one.
- **Push tags one at a time.** GitHub starts no workflows when more than three tags are pushed at once.
- **If the tests failed:** fix it, bump the version, and tag the new commit. If a test run failed by fluke, re-run it on GitHub, then re-run the Release workflow.
- **GitHub's "Latest" label** always marks the newest release of any addon.
- **The release's own zip is test-free, and so are GitHub's automatic "Source code" archives.** The `tests` folders are marked `export-ignore` in `.gitattributes`, which also keeps them out of the Code → Download ZIP button. Clones and forks still have them.

## Tests
Every commit pushed to a branch runs the [Tests workflow](.github/workflows/tests.yml): each addon's unit tests, smoke tests and Lua 5.1 lint, on LuaJIT. Forever Addon Fixes' smoke tests run against the real code of GearQuestForever and AtlasLoot. The workflow downloads pinned releases of both from CurseForge, checked by sha256 (`tools/ci/fetch-test-deps.sh`). They are not part of this repository.

If CurseForge ever removes one of those pinned files, the Tests workflow fails, and releases are blocked, until `tools/ci/fetch-test-deps.sh` pins another file.

To run the tests locally, with LuaJIT on the PATH, from an addon's folder:
- `luajit tests/run.lua`
- `luajit tests/smoke.lua`. Forever Flight Timer: also with `FFT_SMOKE_FLIGHTMAP_PRELOADED=1` and with `FFT_SMOKE_BREAK_SETTINGS=1`. Forever Instance Timer: also with `FIT_SMOKE_BREAK_SETTINGS=1`.
- Forever Addon Fixes also has `tests/smoke_atlasloot.lua`. Point `AFIX_GQ_PATH` at a `GearQuestForever` folder and `AFIX_AL_PATH` at an `AtlasLootClassic` folder, for example the game's copies or those from `tools/ci/fetch-test-deps.sh <folder>`. Otherwise these smoke tests print `SKIP:`.
- `luajit tests/lint51.lua $(find . -name "*.lua" | sort)`

## Copying the addons into the game
`tools/sync-to-game.ps1` replaces the game's copy of an addon with this repository's folder, without its `tests` folder.
1. Once per PC: `tools\sync-to-game.ps1 -SetAddOnsPath "<WoW folder>\_classic_beta_\Interface\AddOns"`. The path is saved in the git-ignored `tools\sync-to-game.local`.
2. Then `tools\sync-to-game.ps1 -All`, or `tools\sync-to-game.ps1 -Addon ForeverAddonFixes`.
3. Restart the game, or `/reload` if no files were added or removed.

## License
- **The addons' own code:** [MIT](LICENSE).
- **Libraries bundled in Forever Flight Timer and Forever Instance Timer** (`Libs/`): they keep their own licenses. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
