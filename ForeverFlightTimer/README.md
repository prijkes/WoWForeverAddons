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
