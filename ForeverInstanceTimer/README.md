# Forever Instance Timer

Shows how long you've been in a dungeon, raid or battleground on WoW Forever (client 1.60.x, interface 16001).

- The timer starts when you arrive in an instance and ends when you leave.
- Dying does not reset it. After you release, it keeps counting while you're a ghost, and it carries on when you run back in. Coming back to life *outside* (the spirit healer) ends the run.
- When a run ends, the final time is printed in chat and stays on screen for 10 seconds.
- Everything is configurable under Esc → Options → AddOns → Forever Instance Timer, or type `/itimer`.
- **Right-click the timer** for a menu: Options, Lock position, Reset position, Reset current run. Other clicks go through it to the game world; the "Right-click menu" setting on the Display tab turns the menu off.

## Commands

`/itimer` and `/instancetimer` are the same command.

| Command | What it does |
|---|---|
| `/itimer` | Open the options |
| `/itimer unlock` / `lock` | Drag the timer with the left mouse button / lock it again |
| `/itimer reset` | Restart the current run |
| `/itimer resetpos` | Move the timer back to its default place |
| `/itimer defaults confirm` | Put every setting in the current profile back to its default, including the position and the run rules (a run in progress follows them from then on). `/itimer defaults` explains first |
| `/itimer status` | Print the run state, the latest game-state reading and the right-click menu's state |
| `/itimer debug` | Log readings and state changes to chat (toggle) |
| `/itimer help` | List the commands |

## Known limitations

- Wings of one dungeon (Scarlet Monastery, Dire Maul, Blackrock Spire) share a map ID, so they count as the same instance.
- WoW saves addon data only on a normal logout or `/reload`. After a client crash, the timer resumes from the last saved state.
- The timer appears about a second after a loading screen. It waits for a second reading to confirm you're really inside, but it counts from the moment you arrived.
- If a client update ever breaks the options panel, the addon says so at login and the timer keeps working.
- In combat, and during boss encounters, PvP matches, keystone dungeons and on restricted maps, the game may block changes to which clicks go through the timer, so the addon waits until that's over. Until then an unlocked timer can't be dragged, and a timer you lock may be fully click-through, without the menu.
