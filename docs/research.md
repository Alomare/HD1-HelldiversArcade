# What the game allows

Findings from the decompiled scripts (`ObsidianModManager/internal/research/lifted`) and from runs in the game on 2026-11-01, Steam build 6001293. "Checked" means seen in the running game.

## Answered

| Question | Answer | How |
|---|---|---|
| Can a mission have no objectives? | Yes, checked | Skipping `GeneratedLevel.generate_mission` leaves the map whole, and the HUD lists only Extract. The mode keeps them now (`rules.MAP_OBJECTIVES`): each one done is bonus samples, through `on_objective_completed` |
| Can objectives be spawned during a run? | Not safely, checked | A spawned objective entity joins the mission's list, but its unit must be in a loaded package, and which ones are depends on the map's environment and faction: `gameobject_flag_01` stopped the game on a bugs desert. `Application.can_get` isn't in this engine, so a mod can't ask first |
| Can the screen hold nine missions? | Yes, checked | The Proving Grounds planet has 12 mission markers: 4 named `provinggrounds`, 7 for the campaign's missions, and the boss's. Nine go on the 11 that aren't the boss's; the camera frames Proving Grounds' 4 as the game does |
| Can a map lose its extraction? | No, checked | Skipping `generate_extract` leaves the game on a black screen before the drop. The mod keeps it and stops the shuttle being called instead (`ExtractBeaconComponent`: the player's `can_interact`, and `should_draw_ui`) |
| Can all three factions be on one map? | Yes, checked | `resource_packages/race_<faction>` loaded in `GeneratedLevel.load_resources`, before the drop, as Boss Variety loads a second one. A bug map held bugs, cyborgs and Illuminates at once |
| Does every machine get the same map? | Yes | Everything comes from the mission seed (`DifficultySettings.get_mission_params`), which the host sends |
| Can a mode mark its missions? | Yes, checked | The seed's digits past the seventh are free. `97 * 10^7 + params` reads as the normal mission it describes |
| Can a mod choose the next drop? | Yes, checked on the ship | The host's `StateMenu.get_mission_seed` decides what the hellpods start |
| Can the game slow down? | No, checked | `_G.TIME_SCALE` scales `GAME_DT` for the scripts, but the engine's animation and movement keep their pace. A level-up freezes the enemies instead (Obsidian API's `freeze`) |
| Can the alarm be sounded? | Yes, checked | `EncounterManager.start_encounter(position)`, on the host |
| Can enemies spawn where a mod wants? | Yes, checked | `EncounterManager.spawn_group(position, group)`, now `api.enemies.spawn(key, count, position)` |
| Can a mod draw at a point of the world? | Yes, checked | `CameraManager:world_to_screen(position)` gives pixels, now `api.world.to_screen(position)` |
| Can a mod read each controller? | Yes, keyboard checked | An input interface of its own, as Obsidian's in-game menu does (`PadManager:get_inputs`) |
| Can a mod run Lua it loads at runtime? | No | The game's `loadstring` gives nothing back. Probes ship with the test mod |
| Can the galaxy map have a mode of its own? | Yes, checked | The fronts screen's tabs are `MenuScreenCampaignRegion`'s `substate_object.substates`: Survivors goes in second, before Proving Grounds. Taking it flies the camera in as Proving Grounds does, onto a second `MenuScreenProvingGroundsMission` registered in `MenuScreenCampaign.states` as `survivors_selection`, fed Survivors missions as its trials. Obsidian closes Proving Grounds by its state name only. Texts are swapped while it draws (`api.ui.with_texts`) |
| Can a mod's screen look like the game's? | Yes, checked | Inside a menu screen, the game's own calls draw for it: `draw_main_panel`, the `selectionbox_01` bar, the `bar_difficulty` bar with `CampaignSettings.difficulty_bar` and `planet_difficulty_names`, and `MapWidget(seed)` for a map preview. Proving Grounds' mission panel is copied number for number |
| Do the hellpods start any seed? | Yes, checked | `StateMenu.update` opens them only with a planet or a trial in the save, then starts `get_mission_seed`. Leaving the galaxy map with a planet chosen (the player's, or one of `available_planets`) and the seed hook set gives a Survivors drop |
| Can a mod ship its own images? | Yes, checked | A white texture and a material on the game's font shader in the boot bundle, as Heroic UI does (`tools/build_art.py`). `kit:art` draws them in every state, tinted |
| Can the level show XP as things in it? | Yes, checked | Each faction's research sample (`gameobjects_spec/gameobject_<bug/cyborg/illuminate>_research_object`) spawns as a plain unit with `World.spawn_unit`, glow and highlight included, and scales with `Unit.set_local_scale` (`api.world.prop`). A unit whose package isn't loaded stops the game: `gameobjects_spec/gameobject_illuminate_carry_noglow` did |
| Can a mod draw things in the 3D world? | Yes, checked | `World.create_world_gui(world, Matrix4x4.identity(), 1, 1, "immediate", "material", <the mod's material>)`, then `Gui.bitmap_3d_uv` with the camera's rotation as the tm. The quad lies in the tm's x and z. Nothing goes over the network |
| Does the HUD's look come with the images? | Yes, checked | `basicbox_01` is the game's dark gradient box (24x380, a 3 pixel black edge), `hud_icon_color_gradient_01` the fading bar the name bars tint, `wing_01` the chrome title wings. A kit can draw all three in a mission |

| Can the loadout be limited? | Yes, checked | `LoadoutSettings.nr_of_stratagem_slots` is 8: the 4 `static_stratagems` and 4 of the player's. The screen and the drop both read it, so static + 1 leaves one choice. Its slot's x is a local of `draw_menu`, so `src/loadout.lua` moves the slot's 58x58 pieces while it draws |
| Can the ship go to a mission's planet? | Yes, checked | `StateMenu` only calls `MenuSpaceManager.planet_changed` when the planet's name changes, so the mod calls it itself once the galaxy map closes, with a region of that faction's |
| Can objectives come back? | Partly, checked | `api.mission.restart_objectives` brings back terminals and assassinations. Destroyed nests stay destroyed |
| Where does a sample's pickup sound come from? | The unit, checked for the call | The `on_picked_up` flow event of the sample unit. Nobody has listened to it yet |

## Things the engine does differently

- `type()` calls a vector `"vector3"`, not `"userdata"`. Obsidian API 1.5.0 knows a position by its fields.
- `kit:icon` draws only images the game has loaded: in a mission, the stratagem icons, rank icons and a few HUD images. Perk icons don't draw there.
- On a 21:9 screen, a 1920x1080 frame is a 16:9 area in the middle. Anything meant to cover the screen has to reach past it.
- A paused component keeps its queued commands, and some of their data is in `TempTableFactory` tables the game takes back at the end of the frame. Damage while frozen crashed on resume until Obsidian API 1.5.1 copied them.
- A weapon's state holds a pointer to settings shared by its type, and copies of some of them. Its hit test keeps the settings it was made with, so a private copy needs `remake_raycast`.
- `InventoryComponent` starts the shield from the backpack with `set_shield_info`, and turns it off with `set_shield_activated false`. Other states turn it off too, so only a changed `inv.backpack` says the backpack went.
- `inventory.switch_weapon_time` counts down to the wield, and character states wait on it. `interactor.interact_speed` drives the interaction's animation.
- A flare's `activation_time` starts from its stratagem's and counts down, so changing it as the flare appears changes that call-in alone.
- The Orbital Laser burns about 15 metres around its target: Destroyer Support killed its own player when the nearest enemy was next to them.
- Stratagems outside the loadout drop fine (flamethrower, exosuit), so a level can offer any of them. `gameobjects/pickup_ammunitionbox_01` is on every map tried, so it spawns safely.
- `available_planets` holds raw planets, with no region and fronts counted from 1. The planet screen builds the real table (`setup_planets`). A current planet with no region stops the ship in any game, modded or not; `entry.heal_planet` repairs one left by Survivors 0.1.0.
- A kit's guis draw in a fixed order on the same layer: its shapes, then the HUD's images (`kit:icon`), then text and the mod's own art. Whatever goes on a `basicbox_01` box has to be a layer above it.
- On the galaxy map, keyboard arrows come to `handle_input` as `up`/`down` for one frame; Q is back and E is select. Enter opens the text chat.
- The galaxy map's gui is a 1280x720 frame centred like a kit's 1920x1080 one, so a kit can draw over a menu panel at 1.5 times its numbers.

## Not answered yet

- **Real bosses:** the boss units are in `race_<faction>_boss`, a much bigger package. The director's tier 5 enemies stand in for now.
- **Map size and shape:** `GeneratedLevelSettings.get_level_settings` sets them per planet type. A Survivors map could be bigger or rounder; not tried.
- **Mouse on the galaxy map:** the Survivors panels take the keyboard and pads. Clicking a mission isn't wired yet.
- **Spawning more objectives:** a list of the units each environment package holds would make it safe, read from the bundles offline. Whether doing every objective sets off the mission's own end is to watch too.
- **Several local players:** upgrades go through each player's own unit now, and input by each player's own pad. Not run with two yet.
- **A lobby:** not run with two machines yet. The XP sum and the wait for everyone's choice go through `api.lobby.share`.
- **The campaign, in the game:** Early wins marked the current planet's selected mission done, as read in `StateMissionEnd.on_enter`: the first host marks it in `current_planet` and `available_planets`, finishes the planet on its last mission, and `save_stats` adds the mission's numbers to the planet. The mod now hides the planet from the mission end and lends the hellpods a planet only while `StateMenu.update_host` runs (`src/campaign.lua`). Offline tests run a copy of that mission end; a win and a loss on the ship still need a look in the game.
