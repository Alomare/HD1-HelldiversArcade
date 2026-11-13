# Changelog

New, changed or removed features, one line each, brief and direct. The section for a release becomes the release notes.

## 1.3.0

- New: a 3 second countdown after the landing, drawn like the hellpod launch countdown. When it ends, the alarm goes on and stays on. Enemies never raise an alarm, and every enemy knows where the squad is and comes for it.
- New: a Fire elite leaves a wide fire where it dies, for 15 seconds.
- Changed: Noxious and Fire elites move faster, by half of the Swift boost.
- Changed: toxic ground from a Noxious elite shows a poison cloud on every machine.
- Changed: Cluster Grenade blasts land closer together (3.5 m instead of 6 m) and follow each other faster (0.15 s instead of 0.3 s).
- Changed: upgrades already held come up less often in the cards (twice as likely as a new one instead of three times).
- Changed: a ground full of samples (300) sets off the sample vacuum early instead of merging the oldest.
- Changed: the Script Profiler of Obsidian API shows the parts of the frame of a run one by one.
- Fixed: a reinforcement that came just as the last player died could leave the defeat summary up for good. The summary now closes as soon as a player is on the way back.

## 1.2.0

- New: Elite tools on the debug page: base unit, count and distance for spawned elites, a random kind, pausing elite spawns for the run, the next elite now, killing or removing every elite, breaking the Bulwark dome, and a status line.
- Changed: Cluster Grenade, Carpet Bombing, Sweet Liberty and Chain Reaction blasts show the fireball and play the sound of a player grenade, on every machine. Before, they did damage unseen.
- Changed: the first alarm is again the one the enemy raises. The first moments of a run for the host no longer count as taking over from a host that left, which raised the alarm at once.
- Changed: Shock elites only arc while a Helldiver out of the drop pod is within range, so a landing player is no longer hit, and the arcs do half damage to other enemies.
- Changed: the three panels of the Arcade screen span the width of the screen, staying within the middle 16:9 on wider screens.
- Changed: the Mission Preview shows the planet name in the top right corner of the map.
- Changed: the difficulty bar sits inside the difficulty selector, under the name.
- Changed: the upgrade panel of the map spaces the badges more closely, and shows the rerolls and banishes in larger text under the upgrades.
- Changed: the partner icons on an upgrade card are a tenth bigger and centred between the badge and the edge of the card.
- Changed: the icon of an elite is half again as big with Better HUD 1.17.0.

## 1.1.0

- New: a weapon dropped on the ground vanishes after a minute. Weapons in the crate of a stratagem stay.
- New: on a defeat, the combat music stops and the defeat music of the game plays.
- Changed: the first alarm is the one the enemy raises, with the scream or flare. The Arcade keeps the alarm on from then.
- Changed: the end-of-run summary shows at once instead of 2 seconds after the end.
- Changed: an upgrade card shows the partner icons of an evolution to the right of the badge, a fifth bigger.
- Changed: the dome of a Bulwark elite rides on the elite instead of being placed again as it walks. Anyone walks through it, and shots from outside stop on it.
- Changed: the level and clock in the top bar and the end-of-run summary use the body font instead of the title font.
- Removed: chests.
- Changed: the health bar of an elite shows all the time, with an icon for the kind in the middle of the bar, in place of the colored glow under the elite and the name over it. Needs Better HUD 1.16.0.
- Changed: needs Obsidian API 1.48.0.

## 1.0.0

- New: **Super Earth Survivors**, the first arcade game mode, picked from the ARCADE tab beside Proving Grounds on the galaxy map, with the starting faction, the difficulty and the map chosen there.
- New: enemies come in waves of 30 seconds with a 20 second break, more and stronger as time goes on. A second faction joins at 6:00 and a third at 12:00, elites come from 3:00, a boss at 10:00 and 20:00 and then every 5 minutes, and red strike bombardments fall near the squad from 7:00.
- New: kills drop research samples, and every level-up offers upgrade cards (common, rare, legendary, perk and evolution) and, every few levels, stratagems, with rerolls and banishes.
- New: upgrades for weapons, movement, health and armor, grenades, melee and stratagems, and evolutions that join two upgrades into one with a new effect.
- New: chests from elites, bosses and rare kills, with upgrades for every player in the squad.
- New: the shuttle can be called after 15 minutes, and a run ends with a summary: the result, the time survived, the level, the factions, the bosses and the damage of each player by source.
- New: up to four players, as an Obsidian expansion: everyone in the lobby runs the mod for an arcade mission, and the Galactic Campaign stays as it was.
