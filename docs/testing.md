# Testing

## Offline

```
luajit tests/run.lua
```

Runs the parts that don't need the game: XP and levels, the card draft and rarities, the spawner (waves and breaks, the difficulty share, the share of rushers in a wave, Heat) and a new host taking it over, the campaign left as it was by a copy of the game's mission end, and no line of the mod writing a campaign key, orbs, the sample vacuum, ammo drops, the getting-up timers, the loadout's stratagem row, the objective cap and list, the Survivors screen's missions, places and Refresh button, the sync between machines (whole samples, another mission's values, machines leaving and coming back, the host's clock), seeds, and the card and pause screens against a fake kit. `tests/test_expansion.lua` starts `main.lua` against a fake Obsidian loader and Obsidian API: the way in as wraps and the mode as hooks, no guarded call before the content, the start on the galaxy map and each refusal, every stop, a game that takes over the lobby, and what goes back when the content ends. Use the LuaJIT in Obsidian's repository, `target/luajit/luajit.exe`.

## In the game

The scripts are in `internal/testing`, which isn't committed. They follow HeroicUI's.

| Script | What it does |
|---|---|
| `lib.py begin` | Records save hashes and purges the player's deployed mods |
| `lib.py deploy` | Deploys a throwaway library: Survivors, Obsidian API, Obsidian Patches and `dev.tour` |
| `lib.py end` | Purges the throwaway library, redeploys the player's and compares the saves |
| `tour/` | `dev.tour`, a session mod that takes commands from a file and skips every save |
| `tour/probes.lua` | Probes run with `cmd:probe <name>`. The game's Lua has no parser, so they ship with the mod |
| `go.sh` | Redeploys, launches and runs a list of `drive.py` steps |

A file named `tour.god` in the logs folder makes the tester invulnerable once the mission is ready.

Straight into a Survivors mission (bugs, desert, difficulty 6), then XP orbs, a level-up and a pick:

```
SEED=971000006 WAIT=game sh internal/testing/go.sh "wait:MISSION READY:150" sleep:24 "cmd:probe orbs" sleep:2 shot:cards key:RIGHT key:ENTER
```

| Probe | What it does |
|---|---|
| `mix` | Spawns two enemies of each faction around the player |
| `census` | Counts the living enemies by faction |
| `orbs` | Drops a ring of XP orbs around the player |
| `level` | Adds XP |
| `later` | Moves the run's clock 7 minutes on |
| `ship` | On the ship: chooses Survivors and reads back the seed the hellpods would start |
| `info` | Screen projection, resolution, local players, pads, time scale |
| `galaxy` | Opens the galaxy map |
| `region` | Goes to the fronts screen, past a planet already chosen |
| `tab` | Moves to the Survivors tab |
| `enter`, `pick`, `launch` | The three missions, the next one, and leaving with the selected one |
| `pods` | The seed the hellpods would start, and the planet they'd take |
| `props`, `prop1`..`prop5` | Spawns candidate units for XP beside the player. `prop5` stops the game |
| `canget` | Whether the engine can tell a loaded unit (it can't) |
| `obj1`..`obj6`, `objs` | Spawns an objective beside the player, and lists the mission's. `obj1` stops the game on a bugs desert |
| `finishobj`, `xp` | Completes the objectives, and reads the samples collected |
| `killall`, `zoom` | Kills every enemy for the player, and reads the camera's distance |
| `markers` | The Survivors screen's marker places and where its missions went |

The galaxy map from the ship, to the missions and back to the hellpods:

```
WAIT=menu sh internal/testing/go.sh "cmd:probe galaxy" sleep:4 "cmd:probe region" sleep:3 "cmd:probe tab" sleep:2 shot:teaser key:E sleep:4 key:DOWN sleep:3 shot:missions key:E sleep:4 "cmd:probe pods"
```

The galaxy map takes E to select and Q to go back. Enter opens the text chat.

## The art

`python tools/build_art.py` draws every image from shapes and writes `res/art.texture`, `res/art.material` and `src/atlas.lua`. `internal/art_preview.png` shows the icons on their badges.

## What has been checked

On a 21:9 screen with keyboard and mouse, alone:

- A Survivors seed builds a map with no objectives, and loads all three factions.
- The shuttle can't be called during the run.
- The alarm at 20 seconds, then the spawner every 4 seconds, with the other factions joining by the clock.
- Orbs drawn where they lie, picked up, and the team's XP bar.
- A level-up: invulnerability, three cards with icons, a pick from the keyboard, and the next level's cards when two levels came at once. The time limit picks for a player who doesn't.
- The pause menu lists the upgrades with what they do.
- On the ship, the Survivors page sets the next drop's seed.
- At 12 minutes the objectives finish and the shuttle can be called, with its native countdown.

- The galaxy map's Survivors tab beside Proving Grounds, its panel, the three missions with their map previews and difficulty bars, the arrow keys, and leaving with a mission: the hellpods then hold its seed and the player's planet.
- The cards and the XP bar in the game's look, with the mod's own icons.
- The Survivors screen as Proving Grounds': the planet, three markers, the map preview, the difficulty bar and the objective, and leaving with a mission.
- The loading screen names the mission's planet.
- XP as the faction samples, bigger for bigger drops, dropped by real kills, and no "Extract" in the HUD before the win.
- A level-up freezes the enemies (two shots three seconds apart match), and the camera draws back (17, 17.4, 17.9).
- Nine missions on the Survivors screen.
- The map's objectives done give a level of samples each, and the game's own "Completed objective" banner.
- The pause list in the game's look, in compact rows.
- 19 enemies killed while frozen, then a card picked with the mouse: no crash. The crash was not reproduced on the old code first.
- The ship's planet and "orbiting" line follow the mission, and the loadout offers one centred stratagem slot.
- The UI at scale 0.8, with the bar against the top of the screen.
- Objectives coming back 30 seconds after the last, except destroyed nests.
- The stratagem row by key and by mouse, and Broad Permit's 4 and 5.
- Weapon stats tuned on one player's weapons, the shield adding up with a backpack, reinforcements coming back, no native samples, ammo boxes spawning, Suitable Replacement on death, and 12 stratagems ending the row and lasting through a respawn.

Not yet: dropping from the ship's hellpods into a Survivors mission, gamepads, several local players, a lobby, the feel of Fast Reflexes and Strategic Reserve's call times, the mouse on the galaxy map, the game's sounds by ear (the test mod used to mute them), and whether Space still dives or Enter opens the chat after a pick.
