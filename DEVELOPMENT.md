# Development

For working on the addons: the tests, the checks that need the real game, copying the addons into the game, releasing, and the bundled libraries. For installing and using the addons, see the [README](README.md).

## Tests
Every push to a branch runs the [Tests workflow](.github/workflows/tests.yml) on its last commit: each addon's unit tests, smoke tests and Lua 5.1 lint, on LuaJIT. Forever Addon Fixes' smoke tests run against the real code of GearQuestForever and AtlasLoot. The workflow downloads pinned releases of both from CurseForge, checked by sha256 (`tools/ci/fetch-test-deps.sh`). They are not part of this repository.

If CurseForge ever removes one of those pinned files, the Tests workflow fails, and releases are blocked, until `tools/ci/fetch-test-deps.sh` pins another file.

To run the tests locally, with LuaJIT on the PATH, from an addon's folder:

**Forever Flight Timer**
- `luajit tests/run.lua`: unit tests.
- `luajit tests/lint51.lua $(find . -name "*.lua" | sort)`: compile check, Lua 5.1 lint, and globals removed on this client.
- `luajit tests/smoke.lua`: the headless smoke test. It covers:
  - flight scenarios, what the bar shows, tooltips, the debug log, and the real options panel;
  - the next UI session after a logout mid-flight (`/reload`, relog, a pick while resuming), which it runs through `tests/smoke_resume.lua` in fresh processes.

  Also run it with `FFT_SMOKE_FLIGHTMAP_PRELOADED=1` and with `FFT_SMOKE_BREAK_SETTINGS=1`.

**Forever Instance Timer**
- `luajit tests/run.lua`: unit and end-to-end timeline tests
- `luajit tests/lint51.lua $(find . -name "*.lua" | sort)`: compile check, Lua 5.1 lint, and globals removed on this client
- `luajit tests/smoke.lua`: headless smoke test. It loads the whole addon and libraries, replays a play session, and renders and uses every control on the real options panel.
- `FIT_SMOKE_BREAK_SETTINGS=1 luajit tests/smoke.lua`: the same test with a broken Settings API

**Forever Addon Fixes**
- `luajit tests/run.lua`: unit tests.
- `luajit tests/smoke.lua`: runs against GearQuest's **real** `Core.lua` and `Log.lua`, from `../GearQuestForever` by default. It checks four things:
  - the error is reproduced without the fix;
  - the fix stops it;
  - readable messages change GearQuest's data exactly as without the fix;
  - load order, the panel, broken-panel fallbacks and untested versions all behave as specified.
- `luajit tests/smoke_atlasloot.lua`: runs against AtlasLoot's **real** `Data/VendorPrice.lua`, from `../AtlasLootClassic` by default. It checks five things:
  - the error is reproduced at line 988 without the fix;
  - the fix stops it;
  - readable vendors record exactly the same prices;
  - a skip doesn't stop a later readable visit from recording;
  - off/on, no target, and load order all behave as specified.
- `AFIX_GQ_PATH="<GearQuestForever folder>"` or `AFIX_AL_PATH="<AtlasLootClassic folder>"` runs the matching smoke test against another copy, for example the game's copies, or, after `tools/ci/fetch-test-deps.sh <folder>`, `<folder>/GearQuestForever-0.2.11-beta/GearQuestForever` and `<folder>/AtlasLootClassic-1.1.1/AtlasLootClassic`. The defaults only exist when the addon's folder sits in the game's AddOns folder next to those addons. In a checkout of the repository, set both variables, or the smoke tests print `SKIP:` and do nothing.
- `luajit tests/lint51.lua $(find . -name "*.lua" | sort)`: checks for Lua 5.1 syntax and removed globals.

## In-game checks
Some things can only be checked in the real game. Each addon's `tests/in-game-checks.md` lists them:
- [Forever Flight Timer](ForeverFlightTimer/tests/in-game-checks.md)
- [Forever Instance Timer](ForeverInstanceTimer/tests/in-game-checks.md)
- [Forever Addon Fixes](ForeverAddonFixes/tests/in-game-checks.md)

## Copying the addons into the game
`tools/sync-to-game.ps1` updates the game's copy of an addon in place to match this repository's folder, without its `tests` folder. It copies changed files and removes files the repository no longer has.

For safety it refuses in three cases:
- a game copy that is, or contains, a junction, a symbolic link or a `.git` folder;
- an AddOns folder inside this repository;
- this repository inside a game copy.

Keep the repository outside the game's folder.
1. Once per PC: `tools\sync-to-game.ps1 -SetAddOnsPath "<WoW folder>\_classic_beta_\Interface\AddOns"`. The path is saved in the git-ignored `tools\sync-to-game.local`.
2. Then `tools\sync-to-game.ps1 -All`, or `tools\sync-to-game.ps1 -Addon ForeverAddonFixes`.
3. Restart the game, or `/reload` if no files were added or removed.

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

## Bundled libraries
Forever Flight Timer and Forever Instance Timer bundle the same libraries: unmodified copies of the latest releases as of 2026-09-26. Their licenses are listed in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

| Library | Version | Source |
|---|---|---|
| Ace3 (LibStub, CallbackHandler-1.0, AceDB-3.0, AceDBOptions-3.0, AceGUI-3.0, AceConfig-3.0) | Release-r1403 | github.com/WoWUIDev/Ace3 |
| LibSharedMedia-3.0 | v12.1.0 (12000002) | repos.wowace.com/wow/libsharedmedia-3-0 |
| AceGUI-3.0-SharedMediaWidgets | trunk r65 (widgets 13, data 9004) | repos.wowace.com/wow/ace-gui-3-0-shared-media-widgets |

For SharedMediaWidgets, the newest SVN tag (v3.4.3) is older than trunk, so trunk is used.

Ace3 r1403 is required on this client. Older AceGUI checkboxes call `SetDesaturation`, which WoW 12.1 removed, and the options panel fails to open with them.
