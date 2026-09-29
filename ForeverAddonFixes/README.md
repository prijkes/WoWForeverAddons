# Forever Addon Fixes

Fixes Lua errors that other addons throw on the WoW Forever client, **without editing their files**, so the fixes survive their updates.
- Each fix runs only when its addon is loaded.
- Each fix can be switched off on its own.
- Switching a fix off puts the other addon back exactly as it shipped.

## Fixes

### 1. GearQuest: skip hidden chat text (GearQuestForever)
**The error:**
```
GearQuestForever/Log.lua: attempt to index local 'msg' (a secret string value, while execution tainted by 'GearQuestForever')
```
**Why it happens.** In dungeons, raids and boss fights, the game hides the text of some chat messages from addons, such as skill-ups ("Your skill in Defense has increased to 45."). GearQuest reads every loot and skill-up line looking for items you looted or crafted. Reading hidden text throws this error.

**What the fix does.** GearQuest skips those hidden messages.

**What it loses: nothing GearQuest could use.** GearQuest only acts on loot and craft lines. A hidden line can't be read either way; without the fix, it just raises the error.

- **Tested with:** GearQuestForever 0.2.6-beta and 0.2.11-beta.
- **Other versions:** with any other version, `/afix status` says "untested with this version", and one chat notice appears per new version.

### 2. AtlasLoot: skip scans of hidden vendors (AtlasLootClassic)
**The error:**
```
AtlasLootClassic/Data/VendorPrice.lua:988: attempt to perform string conversion on a secret string value (execution tainted by 'AtlasLootClassic')
```
**Why it happens.** When you open a vendor, AtlasLoot reads your target's GUID to find out which vendor it is, so it can learn the vendor's special-currency prices. The game sometimes hides a vendor's identity from addons. Reading the hidden GUID throws this error.

**What the fix does.** AtlasLoot skips its price scan for that visit, as it already does when you have no target.

**What it loses:** only the special-currency prices AtlasLoot would have learned from that one visit. A later visit to the same vendor, when it isn't hidden, still records them.

- **Tested with:** AtlasLoot Forever releases 1.0.7 and 1.1.1.
- **Update detection doesn't work for AtlasLoot.** Its releases all report the same version, "Forever 1.60.1", so the "untested with this version" check can't notice an AtlasLoot update. `/afix status` says so.

## Commands
| Command | What it does |
|---|---|
| `/afix` or `/afix options` | Opens the options panel. It won't open during combat. |
| `/afix status` | Each fix and its state (active, off, waiting, not applied, not needed). An active fix also shows how many times it skipped this session. The last line shows the notices and debug settings. |
| `/afix on <number>` / `/afix off <number>` | Switches a fix on or off. The numbers come from `/afix status`: 1 is GearQuest, 2 is AtlasLoot. The fix's id works too, e.g. `/afix off AtlasLootClassic.hiddenVendor`. |
| `/afix notices on\|off` | Chat notices when a fix can't be put in place, or its addon has an untested version. |
| `/afix debug on\|off` | A chat line every time a fix skips something. What was hidden is never shown. |
| `/afix help` | The command list. `/addonfixes` works as well as `/afix`. |

## Options panel
The panel is in Options → AddOns → **Forever Addon Fixes**. It has one checkbox per fix (two at the moment), plus "Chat notices" and "Debug: report skips".

The panel's **Defaults** button asks what to reset. Pick **"These Settings"**: "All Settings" resets every game setting, not just this addon's.

## Notes
- **Stack traces.** Both fixes hand things on to the other addon with a tail call. So an error raised inside GearQuest's `HandleCraftChatMessage` or AtlasLoot's `ScanShownVendor` may show a `(tail call)` line in its stack trace, and may mention this addon. If you see one, `/afix off <number>` shows whether it's that addon's own error.
- **"Off" until the next reload.** If another addon has wrapped the same function after us, "off" can't unhook ours. It passes everything straight through until the next `/reload`, and `/afix status` says so.

## Is a fix still needed?
When an addon updates, its author may have fixed the bug. The check only means something if a hidden case actually happens while you test, so confirm that first, with the fix on.

**GearQuest (fix 1):**
1. In a dungeon, type `/afix debug on`. Wait until a line "GearQuest skipped a hidden chat message" appears. Skill-ups trigger it, such as weapon or defense skill; if your skills are capped, you may get no skill-ups.
2. Type `/afix off 1`, and wait for the same kind of event again. In a dungeon, every skill-up line you see in your chat window is one of these hidden messages. The game still shows them to you and only hides them from addons.
3. See whether the error comes back:
   - **If it does:** the fix is still needed. Switch it back on with `/afix on 1`.
   - **If it doesn't:** GearQuest now handles it. Leave the fix off.

   If no hidden message arrived during step 2, the test tells you nothing.
4. Type `/afix debug off`.

**AtlasLoot (fix 2):** keep the vendor **targeted** throughout (right-click it). AtlasLoot only looks at your target, so without one it never reads anything, and "no error" would mean nothing.
1. Target a vendor and type `/dump C_Secrets.ShouldUnitIdentityBeSecret("target")`. If it prints `true`, the game hides that vendor from addons.
2. With `/afix debug on`, open that vendor: a line "AtlasLoot skipped a vendor scan" appears. If no such line appears, the test below tells you nothing.
3. Close the vendor window, type `/afix off 2`, and open the same vendor again, still targeted:
   - **An AtlasLoot error:** the fix is still needed. Switch it back on with `/afix on 2`.
   - **No error:** AtlasLoot now handles it.
4. Type `/afix debug off`.

If both fixes turn out to be unneeded, you can remove this addon.

## In-game test checklist
1. **Status.** After starting the game, `/afix status` shows:
   - `1. GearQuest: skip hidden chat text: active (GearQuestForever 0.2.11-beta), skipped 0 this session`, with no "untested" flag;
   - `2. AtlasLoot: skip scans of hidden vendors: active (AtlasLootClassic Forever 1.60.1; its releases share one version string), skipped 0 this session`.
2. **Opening the panel.** `/afix` opens it. Try it in combat too: it refuses with a message instead.
3. **The panel.** Options → AddOns shows **Forever Addon Fixes** with four checkboxes. Unticking and re-ticking a fix changes `/afix status` to "off" and back to "active".
4. **GearQuest in a dungeon.** Type `/afix debug on`. On a weapon or defense skill-up there is no GearQuest error. A line "GearQuest skipped a hidden chat message (1 this session)" appears, which also shows that chat lines print during lockdown. `/afix status` then counts the skip.
5. **GearQuest outside a dungeon.** With debug still on, loot an item: no "skipped" line appears. GearQuest still shows the loot, for example in its log or tracker when the item belongs to a hunt.
6. **GearQuest off and on.** `/afix off 1` in a dungeon: the next skill-up brings the GearQuest error back, which shows the fix is what stops it. `/afix on 1` fixes it again.
7. **AtlasLoot.** Target a vendor and check `/dump C_Secrets.ShouldUnitIdentityBeSecret("target")`:
   - **For a hidden vendor (`true`):** opening it with debug on shows "AtlasLoot skipped a vendor scan" and no AtlasLoot error.
   - **For a normal vendor (`false`):** nothing changes, and no skip line appears.
8. **AtlasLoot's unit tooltips.** `/dump GameTooltip:HasScript("OnTooltipSetUnit")` should print `false`. If it prints `true`, AtlasLoot's unit-tooltip code may also need a fix, so please report it.
9. **Afterwards.** Type `/afix debug off`.

## Development
The tests are in the GitHub repository (github.com/prijkes/WoWForeverAddons), not in release zips.

Offline tests, run from this folder:
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
- `AFIX_GQ_PATH="<GearQuestForever folder>"` or `AFIX_AL_PATH="<AtlasLootClassic folder>"` runs the matching smoke test against another copy. The defaults only exist when this folder sits in the game's AddOns folder next to those addons. In a checkout of the repository, set both variables, or the smoke tests print `SKIP:` and do nothing.
- `luajit tests/lint51.lua $(find . -name "*.lua" | sort)`: checks for Lua 5.1 syntax and removed globals.
