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

## In-game test checklist

1. `/itimer` opens the panel, and changes apply live to the preview. The status line updates while dropdowns, sliders and colour pickers stay open.
   - While the panel is open, the preview is drawn *on top of* the Settings window. If it covers something, move it with the Position X/Y sliders, or close the panel and use `/itimer unlock`.
2. Open every font, background and border picker and choose a few values.
3. `/itimer unlock`, drag, then `/itimer lock`. After `/reload` the position is kept.
4. Enter a dungeon: about a second after the loading screen, the timer appears already counting (0:01). `/reload` continues it.
5. Walk out alive: a chat line appears and the green final time shows for 10 s, then it hides.
6. Die and release: it keeps counting in pale blue. Run back in as a ghost: it continues in white.
7. Die, release, then use the spirit healer: about 3 s later you get the chat line and the frozen time, then it hides.
8. Hearth out alive: the run ends.
9. A raid and a battleground both start the timer. Dying in a battleground changes nothing.
10. Log out inside, then log back in: the timer continues, including the offline time.
11. Try each rule alternative in the Rules tab.
12. Profiles work, including switching profiles mid-run.
13. `/itimer status` and `/itimer debug` output makes sense.

### Reset defaults check

Do these on a test profile, in both addons. Profiles → New, then change a few settings on each tab. Afterwards, select your own profile again and delete the test one.

1. Display tab → **Reset defaults**: the popup asks "Reset all Forever Instance Timer settings in the current profile…". Cancel changes nothing. Accept puts the panel and the preview back to their defaults and prints one chat line.
2. Change a setting again. `/itimer defaults` prints a hint; `/itimer defaults confirm` resets.
3. Change a setting again, in both addons. **The game's Defaults hook**, checked safely. This line calls only the Instance Timer's and the Flight Timer's pages, the same way the game's Defaults → All Settings does; game settings, key bindings and other addons are left alone:

   `/run for _,c in ipairs(SettingsPanel:GetAllCategories()) do local n=c:GetName() if n=="Forever Flight Timer" or n=="Forever Instance Timer" then SettingsPanel:GetLayout(c):GetFrame():OnDefault() end end`

   Each addon prints its "by the game's Defaults button" line and is back to its defaults. If the game asks whether to allow custom scripts, accept and enter the line again.

**Warning:** do **not** test with the game's real Defaults → All Settings unless you mean it. It is the game's own reset: it also puts every game setting and your key bindings back to Blizzard's defaults, and resets other addons that support it. Only the real button can show taint, so if you ever use it on purpose, check that no "Interface action failed" or "action blocked" message names either addon.

### Right-click menu check

A locked timer is on screen inside an instance.

1. Right-click the timer: the menu shows the addon's name, then Options, Lock position (ticked while locked), Reset position, Reset current run. Each entry works, and toggling Lock position keeps the menu open.
2. While locked:
   - left-click something behind the timer (a unit or the ground): it reacts as if the timer weren't there;
   - middle-click and the extra mouse buttons work as usual. The last line of `/itimer status` shows which buttons pass through: `buttons 1-5 but the right one` means the game didn't accept buttons 6 and up, so the locked timer catches those;
   - hovering over the timer still shows unit tooltips behind it;
   - a right-drag that starts over the timer doesn't turn the camera: expected, since right-clicks go to the menu.
3. Turn "Right-click menu" off (Display tab): right-click does nothing, and the locked timer is fully click-through.
4. In combat, `/itimer unlock` and `/itimer lock` give no "Interface action failed" or "action blocked" message. Some changes wait for combat to end: an unlocked timer can't be dragged yet, and a timer locked in combat may be click-through, without the menu. That's expected; the last line of `/itimer status` then says `waiting for combat or a restriction to end`. After combat, right-click works when locked, and dragging works when unlocked.
5. In a battleground, out of combat: `/reload`, then `/itimer unlock` and `/itimer lock`. During a boss encounter, while out of combat (for example while dead): `/itimer lock` and `/itimer unlock`. No blocked-action message may appear. While the encounter or match lasts, the same waits as in item 4 are expected. Once it is over, the menu works on the locked timer.

## Development

The tests are in the GitHub repository (github.com/prijkes/WoWForeverAddons), not in release zips.

Offline tests use LuaJIT; run them from this folder:

- `luajit tests/run.lua`: unit and end-to-end timeline tests
- `luajit tests/lint51.lua $(find . -name "*.lua" | sort)`: compile check, Lua 5.1 lint, and globals removed on this client
- `luajit tests/smoke.lua`: headless smoke test. It loads the whole addon and libraries, replays a play session, and renders and uses every control on the real options panel.
- `FIT_SMOKE_BREAK_SETTINGS=1 luajit tests/smoke.lua`: the same test with a broken Settings API

The libraries are unmodified copies of the latest releases as of 2026-09-26:

| Library | Version | Source |
|---|---|---|
| Ace3 (LibStub, CallbackHandler-1.0, AceDB-3.0, AceDBOptions-3.0, AceGUI-3.0, AceConfig-3.0) | Release-r1403 | github.com/WoWUIDev/Ace3 |
| LibSharedMedia-3.0 | v12.1.0 (12000002) | repos.wowace.com/wow/libsharedmedia-3-0 |
| AceGUI-3.0-SharedMediaWidgets | trunk r65 (widgets 13, data 9004) | repos.wowace.com/wow/ace-gui-3-0-shared-media-widgets |

For SharedMediaWidgets, the newest SVN tag (v3.4.3) is older than trunk, so trunk is used.

Ace3 r1403 is required on this client. Older AceGUI checkboxes call `SetDesaturation`, which WoW 12.1 removed, and the options panel fails to open with them.
