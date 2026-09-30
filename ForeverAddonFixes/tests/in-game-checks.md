# Forever Addon Fixes: in-game checks

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
