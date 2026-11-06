# Helldivers Arcade

Arcade game modes for HELLDIVERS (2015), played from the ARCADE tab of the galaxy map. The first mode is Super Earth Survivors.

## Super Earth Survivors

A game mode inspired by Vampire Survivors. The squad drops on an open map, and enemies come in waves of 30 seconds with a 20 second break between them, more and stronger as time goes on. A second faction, one of the other two, joins at 6 minutes, and the third at 12. Tier 4 enemies, such as tanks, Hulks and Illusionists, are held to 3 alive per player. On difficulty 4 and above, the first boss comes at 10 minutes, from the starting faction or the one that joined, the second at 20, and then one every 5 minutes, never of the same faction twice in a row. A boss holds a fifth of the usual boss health in solo, and 1.5, 2 or 2.5 times that for 2, 3 or 4 players. The starting faction's boss music plays from the first boss to the end of the mission.

From 7 to 9 minutes, from 14 to 16, and then for 1 minute every 6 minutes (22 to 23, 28 to 29, and on), random red strike stratagems fall near the squad, a few seconds apart, and hit Helldivers too. The game's wave alarm sounds 4 seconds before each of these bombardments.

Most kills drop research samples, which glow blue in this mode, and about one kill in twenty drops an ammo box. When the squad has gathered enough samples to level up, the enemies freeze, all health refills, and each player picks one of three upgrade cards: common, rare, perk or legendary. Every three levels, each player also picks a stratagem: supply, then offensive, then defensive, and round again. The first pick always offers an anti-tank support weapon the player has unlocked: the Recoilless Rifle, the LAW or the Satchel Charge. Levels ask 14 samples at first and a little more each time. 3.75 times the samples a level needs, 100 at the most, set off the sample vacuum, which pulls in every sample on the map; the thin yellow line under the XP bar shows how close it is.

Each player has rerolls and banishes, shown under the cards. Every sample vacuum gives every player 1 reroll, and every objective done gives every player 1 banish. A reroll (R, or Y on a controller) draws the whole row again. A banish (X on the keyboard or the controller) takes the card under the cursor out of that player's draft for the rest of the run, and another card is drawn instead. The screen fades in with the cards rising one after another, and fades out after a pick.

From 3 minutes, an elite comes every 60 to 90 seconds: a Brood Commander, a Warlord or a Council Member, the game's Assassinate targets, glowing in the color of the kind with the kind's name over it. One is out at a time until 8 minutes, two after that. Fire elites leave burning ground behind them. Shock elites arc to the 3 nearest units within 8 m every 1.5 seconds, Helldivers and enemies alike. Noxious elites poison with every hit and leave toxic ground for 30 seconds where they fall. Bulwark elites carry a projected shield over themselves and those near them. Swift elites move 1.6 times as fast and don't stagger when hit. Brood elites split into 3 small enemies of their faction when they fall.

An elite drops a chest of 1 upgrade, a boss a chest of 3, and about one other kill in 500 a chest of 1. The chest glows in the color of the rarity inside: common, rare or legendary, never common from a boss. Pressing interact beside it opens it, and every player in the squad gets their own upgrades of that rarity at once, drawn as the cards are, shown on a panel over each player's HUD card.

The alarm goes on as the squad lands and stays on, and the waves come from the Arcade. An enemy that spots the squad attacks at once, without a scream or a flare.

The map keeps the objectives the game gives it, of six kinds: Exterminate, Activate and Defend Launchpad, Assassinate, Capture Area, Activate SAM Site and Activate Truth Transmitter. Each one done gives the squad 25 samples. After 15 minutes the shuttle can be called. Boarding it pays the mission XP, and the fight goes on for a squad that stays.

When the shuttle leaves with at least one Helldiver on board, or the whole squad is down with no reinforcement on the way, the game stops and a summary fades in 2 seconds later, before the mission end screens. At the top: Extracted or Defeated, the time survived, the level reached, the factions faced and the bosses killed. Under that, a column for each player: kills, damage, samples collected, times downed, deaths, Democracy Protects saves when there were any, and the 5 sources that dealt the most damage, each with a share bar: the primary, sidearm and support weapons by name, grenades, melee, stratagems, and the upgrades that deal damage on their own, such as Kinetic Battery, Ignition Rounds, Strike Back, Sweet Liberty, Destroyer Support and Cluster Grenade. After an extraction, each name bar says who extracted and who was left behind. Each player confirms with the button that picks a card, and the mission ends once every player has confirmed, or after 30 seconds. Every player in the lobby sees the same screen.

A panel above the left end of each HUD card shows the player's health, current and maximum, and armor, and moves up over the stratagems on cooldown while the game lists them. Opening the map shows the upgrades the player has instead, on a panel as wide as the card, grouped by rarity, with the number of stacks in the corner of each badge, and the rerolls and banishes left on a strip above it. Both panels are drawn like the HUD card. While Photo Mode (or anything else that turns on Obsidian API's photo effect) clears the screen, the Arcade draws nothing over the game, and the run carries on.

### Starting a mission

The ARCADE tab sits beside Proving Grounds. It opens a screen over the planet with three panels: Game Mode, where Super Earth Survivors is chosen; Parameters, which set the starting faction, the difficulty (with the game's difficulty bar under it) and the biome, with a Refresh button that rolls a new map with the same parameters and a Launch button under it; and Mission Preview, which shows the map with the planet's name and the objectives on it. Launch sends the ship to the mission, and the drop starts as a normal mission does.

The loadout takes two stratagems beside the fixed ones. After a mission the ship stays on it, so the next drop plays the same mission again, until a campaign mission is picked. Arcade missions leave the Galactic Campaign as it was: a win or a loss marks no mission or planet done, and the campaign planet stays the one chosen on the galaxy map.

## Requirements

- Obsidian 1.2.0 or later ([Obsidian Mod Manager](https://github.com/Alomare/ObsidianModManager))
- Obsidian API 1.33.1 or later ([Obsidian API](https://github.com/Alomare/ObsidianAPI)), for the pause on every machine, the Shock Elite's hits on players and the elites' looks
- Better HUD 1.14.0 or later ([Better HUD](https://github.com/Alomare/BetterHUD)), for the grenade count, the Deep Pockets meter, the Democracy Protects flash and the Ignition and Needle Rounds icons

## Multiplayer

Helldivers Arcade is an Obsidian expansion. Until the host picks an arcade mission, the mod runs as a client mod: matchmaking, Galactic War results and Proving Grounds work as in an unmodded game, and players without the mod can join. The pick needs every player in the lobby to run Helldivers Arcade at the same version, or Obsidian refuses it and names the players who don't. From then on, arcade missions stay out of the Galactic War, Proving Grounds is closed, and only players who run the same version can join. Picking a campaign mission or a Proving Grounds trial ends the arcade for the lobby, and leaving the lobby ends it for that player. Closing the galaxy map any other way keeps the arcade mission as the next drop.

## Upgrades

Upgrades and stratagems that need DLC or an unlock the player doesn't have aren't offered, so progress in the main game opens up more choices here.

A perk card adds one of the HELLDIVERS perks on top of the equipped one. The offer holds perks that are owned and not already held, with one grenade type and one sidearm at a time. Laser Aim Module isn't offered.

| Name | Function |
| --- | --- |
| Oxygenator | Move 10% faster overall. |
| Panic | Taking damage heals +50 health over 2 seconds. |
| Analysis Field | Pick up samples from 35% further away. |
| Molecular Scan | Samples are worth 12% more. |
| Extended Mag | Increase primary magazine or heat capacity by 20%. |
| Steady Aim | Reduce primary spread by 15% and turn 20% faster while aiming. |
| Higher Calibre | The primary weapon deals 15% more damage. |
| Tank Hunter | Deal 15% more damage to heavy enemies and bosses. |
| Peak Physique | Increase melee damage by 30% and melee attack rate by 50%. |
| Diver's Resolve | Take 20% less damage while downed, and self-recover 15% faster. |
| Strike Back | 10% of damage taken from enemies within 2 m is dealt back to them. |
| Extra Padding | Gain +20 health and +10 armor. |
| Elusive Tactics | Dive 25% farther, stunning nearby enemies for 1 second. |
| Kinetic Battery | Discharge arc attacks towards 2 nearby enemies for every 14 m you move. |
| Cluster Grenade | Grenades generate +1 explosion nearby. |
| Meritocracy | Each sample collected takes 2% off the time left on each stratagem's cooldown. |
| Arsenal Support | Call down a random expendable support weapon every 60 seconds. |
| Rapid Fire | The primary weapon fires 20% faster. |
| Quick Cycle | All weapons reload or cool down 20% faster. |
| Shield Generator Pack | A shield that takes 50 damage and comes back. Adds to a shield backpack. |
| Strategic Reserve | Stratagems recharge 20% faster and have 15% faster call times. |
| Fast Reflexes | Swap weapons and pick up items 50% faster. |
| Guard Dog | A Guard Dog drone shoots nearby enemies, with no backpack slot taken. |
| Angel | An Angel drone heals the player and nearby Helldivers, with no backpack slot taken. |
| EXO Expert | Piloted vehicles move and turn 40% faster. |
| Ignition Rounds | Primary hits set the enemy on fire at 40% of max health. |
| Needle Rounds | Primary hits poison the enemy at 40% of max health. |
| Deep Pockets | Carry +1 grenade. Generate a grenade every 16 seconds. |
| Facetanker | Gain +80 armor against hits from the front. |
| Trailblazer | Sprinting leaves a fire trail that burns for 2 seconds. It never burns the player. |
| Destroyer Support | Every 40 seconds, an instant Orbital Laser is called nearby. |
| Sweet Liberty | Enemies killed by the player explode. |
| Absolute Freedom | All weapons ignore armor. |
| Suitable Replacement | On death, a Minigun Turret drops where the player fell. |
| Broad Permit | Choose between 4 upgrades and 5 stratagems on level up. |
| Warp Pack | Diving teleports the player forward, up to 8 metres. |
| Democracy Protects | 50% chance of resisting fatal or downing damage. |
| Unstoppable Freedom | Gain immunity to all status effects. |
| Weight Training | Move freely while aiming or firing any weapon. |
| Gunslinger | Sidearms never run out of ammo and don't slow the player down. |
| Autoinjector | Heal over time, and get back up faster when downed. |
| All Terrain Boots | Rough ground and weather cause no slowdown. |
| Cardio Accelerator | Sprint without running out of stamina. |
| Heavy Armor | Take far less damage from small arms, but sprint slower. |
| Incendiary Grenades | Grenades leave a fire behind. |
| Stun Grenades | Grenades stun everything in a large area. |
| Smoke Grenades | Grenades make smoke that enemies can't see through. |
| Stratagem Priority | Stratagems recharge 40% faster. |
| Displacement Field | A badly wounding hit teleports the player a short way instead. |
| Strong Arm | Throw farther and hit harder in melee. |
| P-6 Gunslinger | The sidearm becomes the P-6 'Gunslinger' revolver. |
| Pyro | The sidearm becomes the FLAM-24 'Pyro' flamer. |
| Singe | The sidearm becomes the PLAS-3 'Singe' plasma pistol. |
| Precision Call-in | Stratagems land 1 second sooner. |
| Patch Up | Refills health, ammo and grenades. |

The game's magazine picture only knows a weapon's own magazine, so Extended Mag's extra rounds don't show in it. [Better HUD](https://github.com/Alomare/BetterHUD) counts the rounds left.

### Evolutions

Some upgrades come in pairs. A card that is half of a pair shows the partner's icon on the right of the rarity's row, and on the map's upgrade panel both badges get the same colored mark once one half is at the most stacks it can have and the other is held. With both halves held, the first at the most stacks it can have, a level-up can offer the pair's evolution on a red Evolution card, one a row at the most. Taking it replaces both halves with one badge: the evolution keeps everything both halves did at their stacks and adds a new effect, and neither half is offered again. Cluster Grenade is half of two pairs, so taking one of its evolutions closes the other.

| Name | Function | Pair |
| --- | --- | --- |
| Carpet Bombing | Cluster blasts set off 2 smaller blasts each. Grenades come back twice as fast. | Cluster Grenade (max) + Deep Pockets |
| Napalm Needles | One build-up burns and poisons. Burning kills leave a 4 m poison cloud. | Ignition Rounds (max) + Needle Rounds |
| Dynamo | Firing also charges Kinetic Battery, at half the rate of a sprint. | Weight Training + Kinetic Battery |
| Iron Saint | A save gives 2 s of invulnerability and heals 25% of max health. | Democracy Protects + Diver's Resolve |
| Spiked Plating | Strike Back reaches 6 m instead of 2 m and deals back twice the share. | Strike Back (max) + Extra Padding |
| Sample Siphon | Samples from kills within 12 m fly straight to the player. | Analysis Field (max) + Molecular Scan |
| Chain Reaction | Sweet Liberty blasts cluster: each sets off as many more blasts as a grenade does. | Sweet Liberty + Cluster Grenade |

## Credits

Most upgrade icons are from [game-icons.net](https://game-icons.net), under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Icons made by Lorc, Delapouite, Quoting, Sbed, Skoll and Carl Olsen; [CREDITS.md](CREDITS.md) says which is whose. The upgrades named after a stratagem or a perk show the game's own icon for it, the stars of Stratagem Priority and Precision Call-in are drawn for the mod, and Warp Pack's is from the [HELLDIVERS Wiki](https://helldivers.wiki.gg).
