-- The numbers the mode is tuned by, in one place.
local M = {}

-- A Survivors seed: a normal mission seed with this above its seven digits of params.
M.SEED_MARK = 97
M.SEED_PARAMS = 10000000

-- Heat, the threat readout beside the XP bar, is archived: its code stays, off.
M.SHOW_HEAT = false

-- Seconds from the drop to the director's first spawn (the game's alarm goes on at the landing, src/
-- alarm.lua), and how long until the shuttle can be called. Nothing makes the
-- squad call it: the fight goes on, and the director's later factions and bosses are for those who stay.
M.ALARM_AFTER = 20
-- After the cards appear, presses and clicks wait this long (real seconds), so a shot fired just before
-- doesn't pick a card. By then the cards have come in (BACKDROP_IN and the cards' motion below).
M.CARD_GRACE = 0.5
M.RUN_LENGTH = 15 * 60 -- 12 minutes before

-- Every machine keeps the run's clock, and one more than this many seconds off the host's takes the
-- host's: a level-up starts a moment later where the XP arrives later, and a player joining late starts
-- at nothing.
M.CLOCK_SLACK = 3

-- Once the shuttle can be called, the map's objectives leave the list on every machine, and the host
-- completes them this long into the run, without the game's banner and music: by then every machine's
-- clock has passed RUN_LENGTH, so none of them takes it for an objective done.
M.OBJECTIVES_GONE_AT = M.RUN_LENGTH + M.CLOCK_SLACK + 1

-- A level-up: how long a choice can wait, in real seconds, while the enemies stand frozen.
M.CHOOSE_LIMIT = 45
M.CHOOSE_WARNING = 6 -- with this many seconds left, the bar of the time left flashes
M.CARDS = 3

-- The level-up screen's motion, in real seconds (the game may be paused under it) and design units
-- (src/card_anim.lua). The dark backdrop fades in; the cards rise and fade in one after another, from
-- CARD_DELAY, each CARD_STAGGER after the one before; the stratagem row and the button prompts fade in
-- once the last card is up. A pick holds the chosen card, brightened, for PICK_HOLD while the others
-- sink and fade, and the screen fades out once every machine has chosen.
M.BACKDROP_IN = 0.25
M.CARD_DELAY = 0.05
M.CARD_STAGGER = 0.06
M.CARD_IN = 0.2
M.CARD_RISE = 40 -- units a card rises as it comes in
M.EXTRAS_IN = 0.15
M.PICK_HOLD = 0.35
M.PICK_OTHERS = 0.2 -- the cards not chosen sink and fade in this long
M.CARD_SINK = 30 -- units they sink
M.SCREEN_OUT = 0.2
-- Banish: the card greys, sinks and fades in BANISH_OUT, and the new one rises in after BANISH_NEXT.
M.BANISH_OUT = 0.2
M.BANISH_SINK = 60
M.BANISH_NEXT = 0.1

-- Rerolls and banishes, each player's own: every sample vacuum gives every player REROLL_PER_VACUUM
-- rerolls, and every objective done gives every player BANISH_PER_OBJECTIVE banishes. A reroll draws
-- the whole row again; a banish takes the card under the cursor out of the player's draft for the rest
-- of the run and draws one in its place.
M.REROLL_PER_VACUUM = 1
M.BANISH_PER_OBJECTIVE = 1

-- Every this many levels the same screen also offers stratagems, until a player has this many. Each
-- stratagem level offers one category, in this order, round and round (src/draft.lua).
M.STRATAGEM_EVERY = 3
M.STRATAGEM_CYCLE = { "supply", "offensive", "defensive" }
M.STRATAGEM_CHOICES = 3
M.STRATAGEM_LIMIT = 12

-- With no reinforcements left, a player gets one back after this many seconds.
M.REINFORCEMENT_BACK = 180

-- Ammo boxes: a kill drops one with this chance. The host rolls for every kill, so a box comes once for
-- the lobby. Past the limit, the box furthest from the squad goes.
M.AMMO_CHANCE = 0.05
M.AMMO_LIMIT = 10

-- r: an rng (src/rng.lua). True when a kill drops an ammo box.
function M.drops_ammo(r)
	return r:random() < M.AMMO_CHANCE
end

-- The map's own objectives stay, as many as the game gives, of these kinds only (the part of a map
-- piece's name: Exterminate, Activate and Defend Launchpad, Assassinate, Capture Area, Activate SAM
-- Site, Activate Truth Transmitter). Done, they stay done. Each one done gives the squad this many
-- samples.
M.MAP_OBJECTIVES = true
M.OBJECTIVE_KINDS = { "exterminate", "missile_ramp", "assassinate", "flag", "samsite", "antenna" }
M.OBJECTIVE_SAMPLES = 25

-- The camera draws back as the fight grows: this much further each level, up to the most, from the
-- game's own distance.
M.CAMERA_DISTANCE = 17
M.ZOOM_PER_LEVEL = 0.025
M.ZOOM_MAX = 0.25

function M.camera_distance(level)
	return M.CAMERA_DISTANCE * (1 + math.min(M.ZOOM_PER_LEVEL * math.max(level - 1, 0), M.ZOOM_MAX))
end

-- After the cards close, the input stays held until the key that picked a card is up, and this long at
-- the most, so that key doesn't also dive or open the chat.
M.INPUT_GRACE = 0.4

-- The loadout of a Survivors drop: a primary weapon, a perk and this many stratagems of the player's
-- choosing, beside the game's fixed ones.
M.STRATAGEM_SLOTS = 2

-- The game's own sounds (Audiodiver's catalog of HD1 events). The game has no sound event of a sample's
-- own, and a level-up has to cut through the combat music, so neither is music.
M.SOUNDS = {
	level_up = "ui_objective_complete",
	sample_pickup = "ui_xp_score",
	card_move = "ui_move",
	card_pick = "ui_select",
	objectives_back = "objective_found",
	-- Democracy Protects saving the player: a bullet on armor, as the game plays it for a Helldiver's
	-- deflected hits (surface "metal" in effect_settings.lua).
	spared = "bullet_metal",
}
-- Democracy Protects' save: four copies of the sound at once, about 12 dB over one, and Better HUD's flash.
M.SPARE_SOUND_VOLUME = 4
M.SPARE_FLASH_SECONDS = 2

M.LEVEL_UP_VOLUME = 1.5 -- of its normal volume

-- Rarities, from most to least common: the weight at level 1, against the others, and how much each
-- level adds. Perk sits between rare and legendary, and only rolls while a perk is left to offer.
M.RARITIES = {
	{ id = "common", weight = 70, per_level = -0.6, color = "#c8c8c8", bar = "#6c6c68" },
	{ id = "rare", weight = 25, per_level = 0.4, color = "#4aa8ff", bar = "#2f7fd0" },
	{ id = "perk", weight = 12, per_level = 0.3, color = "#5fd068", bar = "#3b9a48" },
	{ id = "legendary", weight = 5, per_level = 0.2, color = "#ffc433", bar = "#d99a12" },
	-- Evolutions never roll as a rarity: a row offers one only when the player is ready for it
	-- (src/draft.lua, EVOLUTION_CHANCE).
	{ id = "evolution", weight = 0, per_level = 0, color = "#ff3d3d", bar = "#c4262b" },
}
-- A full row of cards offers an evolution the player is ready for with this chance, in place of one
-- card, and one evolution a row at the most.
M.EVOLUTION_CHANCE = 0.5
M.RARITY_FLOOR = 40 -- common never drops below this weight
-- Within a rarity, an upgrade the player already holds is this many times as likely as a new one, so a
-- build comes together.
M.HELD_WEIGHT = 3

-- The share of kills that drop a sample. Every machine makes its own samples, so the roll comes from
-- where the enemy fell, in cells wide enough that the machines agree on it, not from a random number.
M.ORB_CHANCE = 0.75
M.ORB_CELL = 2 -- metres

function M.drops_sample(x, y)
	local n = math.sin(math.floor(x / M.ORB_CELL) * 12.9898 + math.floor(y / M.ORB_CELL) * 78.233) * 43758.5453
	return n - math.floor(n) < M.ORB_CHANCE
end

-- XP an orb gives, by the tier of the enemy it came from.
M.ORB_XP = { 1, 3, 8, 20, 60 }
-- A sample is picked up by stepping on it; Analysis Field reaches further.
M.ORB_RADIUS = 0.9 -- metres a player has to come within to pick one up
M.ORB_MAGNET = 1.6 -- metres from which an orb starts to fly to the player
M.ORB_SPEED = 14 -- metres per second when it flies
M.ORB_LIFE = 90 -- seconds before an orb nobody took is gone
M.PICKUP_SOUND_VOLUME = 0.7 -- of its normal volume
M.PICKUP_SOUND_GAP = 0.08 -- seconds between pickup sounds, when many come at once
M.ORB_LIMIT = 300 -- orbs on the ground at most; past this, the oldest merge into the newest
-- The sample vacuum: once a machine's players have collected this many times the need of the level the
-- squad was on when the vacuum started or last went off, every sample on the map flies in. Both were a
-- quarter lower before (3 and 80), when the vacuum reached only the samples in view (26 metres).
M.VACUUM_EVERY = 3.75
M.VACUUM_MOST = 100 -- samples: the target never asks for more
M.VACUUM_RADIUS = math.huge -- metres: the whole map
M.VACUUM_SPEED = 30 -- metres per second
M.VACUUM_FRESH = 3 -- seconds of the run's clock another machine's vacuum still counts

-- The director: how often it spawns, how far from the squad, and how much it can spend. An early version spent 4
-- points every 4 seconds plus 2.5 a minute, with 40 alive: dozens of rushers on a low difficulty. A later one
-- spent 3 every 5 seconds plus 1.6 a minute, with 32 alive: too calm at difficulty 5 until 15:00. This
-- is the middle of the two.
M.SPAWN_EVERY = 4.5
M.SPAWN_RING = { 28, 38 } -- metres from the squad's centre: just off screen
M.ALIVE_CAP = 36 -- on a hard mission, and less on easier ones (alive_cap)
M.BUDGET_BASE = 3.5 -- spent per spawn at the start, for one player on a hard mission
M.BUDGET_PER_MINUTE = 2 -- at 10 minutes a spawn spends 23.5
M.BUDGET_PER_PLAYER = 0.6 -- each player past the first adds this share
-- From this minute the budget grows at BUDGET_LATE_SHARE of its rate, with no end: a solo spawn spends
-- 23.5 at 10:00, 33.5 at 20:00 and 53.5 at 40:00, where the full rate gave 43.5 at 20:00 and 83.5 at
-- 40:00, more than four tier 4 enemies a spawn.
M.BUDGET_FLAT_FROM = 10
M.BUDGET_LATE_SHARE = 0.5
-- What a spawn couldn't spend carries to the next, up to a tier 3 enemy's cost.
M.BANK_LIMIT = 8
-- Waves, 60/40: the director spawns for this many seconds, then rests this many. Was 40 then 10 to 15.
M.WAVE_SECONDS = 30
M.BREAK_SECONDS = 20
-- At most this share of a wave's enemies are fast melee rushers (director.SWARM); past it, the wave
-- takes the faction's other units.
M.SWARM_SHARE = 0.4

-- The share of the budget, and of ALIVE_CAP, a mission spends at each difficulty (1 to 15): half on the
-- easiest, a full one from 8.
M.DIFFICULTY_SHARE = { 0.45, 0.5, 0.55, 0.62, 0.72, 0.8, 0.9, 1 }

function M.difficulty_share(difficulty)
	local d = math.floor(tonumber(difficulty) or #M.DIFFICULTY_SHARE)
	return M.DIFFICULTY_SHARE[math.max(1, math.min(d, #M.DIFFICULTY_SHARE))]
end

-- Enemies alive at once past which the director waits (the game's own count, theirs included).
function M.alive_cap(difficulty)
	return math.floor(M.ALIVE_CAP * M.difficulty_share(difficulty) + 0.5)
end

-- Sweet Liberty: the blast at a kill, and the look of the killer's grenade going off there, this many at
-- once at the most, each kept this long for its effect to play out (a thrown grenade's
-- time_until_unit_removed).
M.LIBERTY_POWER = 60
M.LIBERTY_RADIUS = 3.5
M.BLAST_LOOKS = 16
M.BLAST_LOOK_SECONDS = 2.5

return M
