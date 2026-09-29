# Forever Flight Timer

Learns your flight-path times on WoW Forever (client 1.60.x, interface 16001) and counts down to landing.

- The **first** flight on a route counts up ("learning") and records the time. Every later flight on that route counts down, with the arrival time next to it, e.g. `0:32 (2:32 PM)`.
  - The arrival time follows the game clock's settings (realm or local time, 12 or 24 hours), unless you choose otherwise in the options.
- Times are shared by all your characters. A route is its exact path of flight points, so a multi-stop flight is learned separately from a direct one.
- **Flight-map tooltips** show the learned time for each destination, or "not flown yet".
- A **chat line** on landing shows the time and whether it was recorded.
- **Not recorded:**
  - early landings;
  - summons, and anything with a loading screen mid-flight;
  - relogging mid-flight (a `/reload` is fine);
  - two different destinations clicked at once;
  - flights under 5 seconds;
  - flights not started from the flight map (e.g. quest flights).
- Everything is configurable under Esc → Options → AddOns → Forever Flight Timer, or type `/ftimer`.
- **Right-click the bar** for a menu: Options, Lock position, Reset position. Other clicks go through it to the game world; the "Right-click menu" setting on the Display tab turns the menu off.
  - In combat, and during boss encounters, PvP matches, keystone dungeons and on restricted maps, the game may block changes to which clicks go through the bar, so the addon waits until that's over. Until then an unlocked bar can't be dragged, and a bar you lock may be fully click-through, without the menu.

## Commands

`/ftimer` and `/flighttimer` are the same command.

| Command | What it does |
|---|---|
| `/ftimer` | Open the options |
| `/ftimer unlock` / `lock` | Drag the bar with the left mouse button / lock it again |
| `/ftimer resetpos` | Move the bar back to its default place |
| `/ftimer defaults confirm` | Put every setting in the current profile back to its default, including the position. Learned times are kept. `/ftimer defaults` explains first |
| `/ftimer status` | Show the current flight, the last flight map (UI, map, nodes, origin), the last taxi reading and the right-click menu's state |
| `/ftimer routes` | List the learned routes; with debug on, also each route's path of node IDs |
| `/ftimer forget all` | Erase all learned times |
| `/ftimer debug` | Log flight-map, pick, takeoff and landing details to chat (toggle) |
| `/ftimer help` | List the commands |

## In-game checklist

Turn on `/ftimer debug` first. Its lines confirm the things that couldn't be checked outside the game; every event line has a timestamp.

1. **The flight map.** At a flight master, the debug lines show:
   - "flight map opened": the map system and the UI it should open, the map ID, the node count, and where the nodes came from (`C_TaxiMap`, or "the classic functions" as a fallback);
   - one line per flight point you can reach, with its node ID and path, e.g. `slot 2: Ratchet, The Barrens [80] REACHABLE, path 25>80`;
   - "slot check": should say the names **agree on all** slots, with no line about slots missing from the C_TaxiMap list;
   - a frame later, "flight map UI shown": which window really opened.
   Any "note:" line means something couldn't be read. Please send those lines.
2. **A first flight.** Hover a destination: the tooltip shows "Flight time: not flown yet". Pick it. The debug line "pick of slot …" shows the path and where the pick was resolved, e.g. `(open map session; the live read agrees)`.
   - "(map session closed … s before; …)" is fine too: the map just closed first.
   - Please send the line if it says the live read **failed** or **gave** something else. That shows how the taxi functions answer during the click.
   - Please also send it if it starts with "(live read; …": a normal click resolves from the map session. The exception is when an auto-taxi addon made the pick.
   - A second "flight map closed … (no open map session)" line right after the first one is expected: closing the window closes the map a second time.
   - If the map-open line said `C_TaxiMap`, the path uses node IDs (like `25>80`), never names (`n:…`).
3. Fly there. The bar counts up with "(learning)". On landing, the chat line says "new route learned", and debug shows "landing position: … map units from the destination" (a small number is good).
4. **The same route again.** The tooltip shows its time, and the bar counts down with the arrival time.
5. **A multi-stop route.**
   - Debug should show **no** "taxi flag was false" lines at the stops along the way.
   - The path lists every stop, e.g. `25>77>23`, and `/ftimer routes` shows the hop count.
   - If the path shows **"(fallback key: …)"**, or the route says **"hops unknown"**, the route couldn't be read; please report the line, which gives the reason.
6. **Unknown readings.** Watch for "on-taxi reading … is unknown" lines. There should be none.
7. Request an **early landing**: the chat line says "not recorded: early landing".
8. Accept a **summon**, or queue into a battleground, mid-flight: the chat line says "not recorded: flight interrupted".
9. **Reload and relog.**
   - `/reload` mid-flight: the countdown carries on, and the landing is recorded.
   - Log out mid-flight and back in: it resumes, and the landing says "relogged".
10. **Other characters.** Fly the same route on another character. `/ftimer routes` (with debug on) shows each route's path. If a flight between the same two points gets a new path, the characters' known flight points change the route.
11. `/ftimer` opens the options. Changes apply live to the preview, including every font, texture, colour, clock and dropdown control.
12. `/ftimer forget all` clears the learned times.

### Reset defaults check

Do these on a test profile, in both addons. Profiles → New, then change a few settings on each tab. Afterwards, select your own profile again and delete the test one.

1. Display tab → **Reset defaults**: the popup asks "Reset all Forever Flight Timer settings in the current profile…". Cancel changes nothing. Accept puts the panel and the preview back to their defaults and prints one chat line.
2. Change a setting again. `/ftimer defaults` prints a hint; `/ftimer defaults confirm` resets.
3. Change a setting again, in both addons. **The game's Defaults hook**, checked safely. This line calls only the Flight Timer's and the Instance Timer's pages, the same way the game's Defaults → All Settings does; game settings, key bindings and other addons are left alone:

   `/run for _,c in ipairs(SettingsPanel:GetAllCategories()) do local n=c:GetName() if n=="Forever Flight Timer" or n=="Forever Instance Timer" then SettingsPanel:GetLayout(c):GetFrame():OnDefault() end end`

   Each addon prints its "by the game's Defaults button" line and is back to its defaults. If the game asks whether to allow custom scripts, accept and enter the line again.

**Warning:** do **not** test with the game's real Defaults → All Settings unless you mean it. It is the game's own reset: it also puts every game setting and your key bindings back to Blizzard's defaults, and resets other addons that support it. Only the real button can show taint, so if you ever use it on purpose, check that no "Interface action failed" or "action blocked" message names either addon.

### Right-click menu check

A locked bar is on screen during a flight.

1. Right-click the bar: the menu shows the addon's name, then Options, Lock position (ticked while locked), Reset position. Each entry works, and toggling Lock position keeps the menu open.
2. While locked:
   - left-click something behind the bar (a unit or the ground): it reacts as if the bar weren't there;
   - middle-click and the extra mouse buttons work as usual. The last line of `/ftimer status` shows which buttons pass through: `buttons 1-5 but the right one` means the game didn't accept buttons 6 and up, so the locked bar catches those;
   - hovering over the bar still shows unit tooltips behind it;
   - a right-drag that starts over the bar doesn't turn the camera: expected, since right-clicks go to the menu.
3. Turn "Right-click menu" off (Display tab): right-click does nothing, and the locked bar is fully click-through.
4. In combat, `/ftimer unlock` and `/ftimer lock` give no "Interface action failed" or "action blocked" message. The unlocked bar can't be dragged until combat ends: that's expected, and the last line of `/ftimer status` says `waiting for combat or a restriction to end`. The same wait happens during a boss encounter, a PvP match, a keystone dungeon or on a restricted map. After combat, dragging works when unlocked. On the ground the locked bar is hidden, so check that `/ftimer status` shows no wait, and try the right-click on your next flight.

## Development

The tests are in the GitHub repository (github.com/prijkes/WoWForeverAddons), not in release zips.

Offline tests use LuaJIT; run them from this folder:

- `luajit tests/run.lua`: unit tests.
- `luajit tests/lint51.lua $(find . -name "*.lua" | sort)`: compile check, Lua 5.1 lint, and globals removed on this client.
- `luajit tests/smoke.lua`: the headless smoke test. It covers:
  - flight scenarios, what the bar shows, tooltips, the debug log, and the real options panel;
  - the next UI session after a logout mid-flight (`/reload`, relog, a pick while resuming), which it runs through `tests/smoke_resume.lua` in fresh processes.

  Also run it with `FFT_SMOKE_FLIGHTMAP_PRELOADED=1` and with `FFT_SMOKE_BREAK_SETTINGS=1`.

The libraries are unmodified copies of the latest releases as of 2026-09-26:

| Library | Version |
|---|---|
| Ace3 | Release-r1403 (github.com/WoWUIDev/Ace3) |
| LibSharedMedia-3.0 | v12.1.0 (repos.wowace.com) |
| AceGUI-3.0-SharedMediaWidgets | trunk r65 (repos.wowace.com) |
