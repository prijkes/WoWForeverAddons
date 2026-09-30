# Forever Instance Timer: in-game checks

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

## Reset defaults check

Do these on a test profile, in both addons. Profiles → New, then change a few settings on each tab. Afterwards, select your own profile again and delete the test one.

1. Display tab → **Reset defaults**: the popup asks "Reset all Forever Instance Timer settings in the current profile…". Cancel changes nothing. Accept puts the panel and the preview back to their defaults and prints one chat line.
2. Change a setting again. `/itimer defaults` prints a hint; `/itimer defaults confirm` resets.
3. Change a setting again, in both addons. **The game's Defaults hook**, checked safely. This line calls only the Instance Timer's and the Flight Timer's pages, the same way the game's Defaults → All Settings does; game settings, key bindings and other addons are left alone:

   `/run for _,c in ipairs(SettingsPanel:GetAllCategories()) do local n=c:GetName() if n=="Forever Flight Timer" or n=="Forever Instance Timer" then SettingsPanel:GetLayout(c):GetFrame():OnDefault() end end`

   Each addon prints its "by the game's Defaults button" line and is back to its defaults. If the game asks whether to allow custom scripts, accept and enter the line again.

**Warning:** do **not** test with the game's real Defaults → All Settings unless you mean it. It is the game's own reset: it also puts every game setting and your key bindings back to Blizzard's defaults, and resets other addons that support it. Only the real button can show taint, so if you ever use it on purpose, check that no "Interface action failed" or "action blocked" message names either addon.

## Right-click menu check

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
