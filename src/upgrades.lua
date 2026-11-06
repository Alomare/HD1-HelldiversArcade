-- The upgrades a card can offer. Each one sets what its count of stacks gives, so taking it again only
-- raises the numbers. `env` is the bridge to the game (src/run.lua), and a test can give a fake one.
-- Most only set a player's stats, which src/perks.lua keeps on the player's unit and weapons.
--
-- Fields: id, rarity, icon (a stratagem icon, for when the mod's own art isn't there), name, max (nil
-- for no limit), text(stacks) for the card, apply(env, stacks, player) once a player has taken it, and
-- what it needs to be offered: needs (a list, any one unlocked stratagem will do), primary (a field
-- the player's primary weapon must have), newer_api (true when it needs Obsidian API 1.7.0) and api (a
-- call of Obsidian API it needs, such as "combat.on_hit"). A perk upgrade has perk, the game's perk it
-- adds, and group, when only one of a kind can be held.
local M = {}

local function pct(x) return string.format("%d%%", math.floor(x * 100 + 0.5)) end
local function secs(x) return (x == math.floor(x) and string.format("%d", x) or string.format("%.1f", x)) .. " s" end

M.EXPENDABLES = { "stratagem_machinegun_oneuse", "stratagem_law", "stratagem_satchelcharge" }
-- The Orbital Laser burns about 15 metres around its target.
M.LASER_CLEARANCE = 18
-- Ignition and Needle Rounds by stacks: the share of an enemy's max health in primary damage that sets the
-- fire or poison off.
M.BUILD_UP = { 0.40, 0.30, 0.20 }
-- The share of an enemy's max health is kept within these (src/fight.lua's need): small enemies don't
-- burn from one bullet, and bosses still burn.
M.BUILD_FLOOR = 40
M.BUILD_CAP = 1500
-- Setting a build-up off also hits the enemy for this share of max health, through armor, up to PROC_CAP.
M.PROC_BONUS = 0.10
M.PROC_CAP = 300
-- A build-up wears off: it runs down to nothing this many seconds after the last primary hit, from
-- BUILD_FADE[1] on an enemy of BUILD_FADE_HP[1] max health to BUILD_FADE[2] at BUILD_FADE_HP[2], on a
-- log scale between, so big enemies keep it longer.
M.BUILD_FADE = { 2, 8 }
M.BUILD_FADE_HP = { 100, 3000 }
M.WARP_METRES = 8
-- Panic: health back over PANIC_SECONDS (src/perks.lua), by stacks.
M.PANIC_HEAL = 50
M.PANIC_SECONDS = 2
-- Extra Padding: health added to the body's maximum and armor added to the body's, by stacks.
-- Hitpoints travel as a 16-bit number, far past six stacks.
M.PADDING = 20
M.PADDING_ARMOR = 10
-- Elusive Tactics, by stacks: how much farther a dive goes, and the seconds of stun on the enemies within
-- DIVE_STUN_RADIUS metres as it starts (src/dive.lua).
M.DIVE_FARTHER = 0.25
M.DIVE_STUN = 1
M.DIVE_STUN_RADIUS = 5
-- Peak Physique, by stacks: melee damage, and how much sooner the next melee can start (src/perks.lua).
M.MELEE_POWER = 0.30
M.MELEE_RATE = 0.50
-- Facetanker: armor against hits from the front half of the body, by stacks (src/fight.lua).
M.FRONT_ARMOR = 80
-- Trailblazer: the seconds each patch of fire a sprint leaves burns, by stacks (src/trail.lua).
M.TRAIL_SECONDS = 2
-- Broad Permit: options added to the level-up's upgrades and stratagems (src/rules.lua has the base).
M.PERMIT_CARDS = 1
M.PERMIT_STRATAGEMS = 2
-- Meritocracy: each sample collected takes this share of the full cooldown off recharging stratagems,
-- by stacks.
M.MERIT = 0.02
-- EXO Expert: how much faster a piloted vehicle moves and turns, by stacks.
M.EXO = 0.40
M.VEHICLES = { "stratagem_exosuit", "stratagem_exosuit_2", "stratagem_exosuit_3", "stratagem_apc", "stratagem_apc_cannon", "stratagem_bike", "stratagem_tankdestroyer" }
M.DEMOCRACY_CHANCE = 0.5
-- Tank Hunter: extra damage to tier 4 enemies and bosses, by stacks (src/hunter.lua).
M.TANK_HUNTER = 0.15
-- Kinetic Battery (src/battery.lua): a full charge every BATTERY_METRES moved at one stack, 2 s at a full
-- sprint (7 m/s), and 20% faster for each stack after. Each discharge hits stacks + 1 enemies for
-- BATTERY_POWER each: the first within BATTERY_FIRST metres, then BATTERY_JUMP metres from one to the next.
M.BATTERY_METRES = 14
M.BATTERY_RATE = 0.20
M.BATTERY_POWER = 150
M.BATTERY_FIRST = 12
M.BATTERY_JUMP = 6
-- Cluster Grenade (src/grenades.lua): each stack adds one more blast of the grenade's own explosion, up
-- to CLUSTER_RADIUS metres around it, CLUSTER_DELAY seconds after the one before.
M.CLUSTER_RADIUS = 6
M.CLUSTER_DELAY = 0.3
-- Deep Pockets (src/grenades.lua): +1 grenade carried per stack over the game's 2 (the count travels as
-- 4 bits, so 15 at most), and one grenade back every POCKETS_SECONDS, 2 s sooner per stack after the first.
M.POCKETS_SECONDS = 16
M.POCKETS_STEP = 2
function M.pockets_seconds(n) return math.max(1, M.POCKETS_SECONDS - M.POCKETS_STEP * (n - 1)) end
-- Weight Training: aiming and firing move the player at the game's jog speed (character_info.move_speed_jog).
M.JOG = 4
function M.battery_metres(n) return M.BATTERY_METRES / (1 + M.BATTERY_RATE * (n - 1)) end
function M.battery_chains(n) return n + 1 end
-- "1 second", "4 seconds".
local function seconds(x)
	local n = x == math.floor(x) and string.format("%d", x) or string.format("%.1f", x)
	return n .. (x == 1 and " second" or " seconds")
end
local function metres(x)
	local s = string.format("%.1f", x)
	return (s:gsub("%.0$", "")) .. " m"
end

M.list = {
	-- Common
	{
		id = "oxygenator", rarity = "common", icon = "stratagem_jumppack", name = "Oxygenator", max = 5,
		text = function(n) return "Move 10% faster overall.\nTotal: +" .. pct(0.10 * n) end,
		apply = function(env, n, player) env.stat(player, "speed", 1 + 0.10 * n) end,
	},
	{
		id = "panic", rarity = "common", icon = "stratagem_drone_heal", name = "Panic", max = 3,
		text = function(n) return "Taking damage heals +" .. M.PANIC_HEAL .. " health over " .. M.PANIC_SECONDS .. " seconds.\nTotal: +" .. M.PANIC_HEAL * n .. " health" end,
		apply = function(env, n, player) env.stat(player, "panic_heal", M.PANIC_HEAL * n) end,
	},
	{
		id = "analysis_field", rarity = "common", icon = "stratagem_metal_detector", name = "Analysis Field", max = 5,
		text = function(n) return "Pick up samples from 35% further away.\nTotal: +" .. pct(0.35 * n) end,
		apply = function(env, n, player) env.stat(player, "magnet", 1 + 0.35 * n) end,
	},
	{
		id = "molecular_scan", rarity = "common", icon = "stratagem_uav", name = "Molecular Scan", max = 5,
		text = function(n) return "Samples are worth 12% more.\nTotal: +" .. pct(0.12 * n) end,
		apply = function(env, n, player) env.stat(player, "xp_gain", 1 + 0.12 * n) end,
	},
	{
		id = "extended_mag", rarity = "common", icon = "stratagem_ammo_backpack", name = "Extended Mag", max = 5,
		text = function(n) return "Increase primary magazine or heat capacity by 20%.\nTotal: +" .. pct(0.20 * n) end,
		apply = function(env, n, player) env.stat(player, "capacity", 1 + 0.20 * n) end,
	},
	{
		id = "steady_aim", rarity = "common", icon = "stratagem_lasercannon", name = "Steady Aim", max = 3, primary = "spread",
		text = function(n) return "Reduce primary spread by 15% and turn 20% faster while aiming.\nTotal: -" .. pct(0.15 * n) .. ", +" .. pct(0.20 * n) end,
		apply = function(env, n, player)
			env.stat(player, "spread", math.max(0.05, 1 - 0.15 * n))
			env.stat(player, "turn", 1 + 0.20 * n)
		end,
	},
	{
		id = "higher_calibre", rarity = "common", icon = "stratagem_machinegun", name = "Higher Calibre", max = 5,
		text = function(n) return "The primary weapon deals 15% more damage.\nTotal: +" .. pct(0.15 * n) end,
		apply = function(env, n, player) env.stat(player, "power", 1 + 0.15 * n) end,
	},
	{
		-- src/hunter.lua: tier 4 enemies (Tanks, Impalers, Hulks, Butchers, Illusionists) and up, and bosses.
		id = "tank_hunter", rarity = "common", icon = "stratagem_recoillessrifle", name = "Tank Hunter", max = 5, api = "combat.on_hit",
		text = function(n) return "Deal " .. pct(M.TANK_HUNTER) .. " more damage to heavy enemies and bosses.\nTotal: +" .. pct(M.TANK_HUNTER * n) end,
		apply = function(env, n, player) env.stat(player, "tank_hunter", M.TANK_HUNTER * n) end,
	},
	{
		id = "peak_physique", rarity = "common", icon = "stratagem_jumppack", name = "Peak Physique", max = 5, newer_api = true,
		text = function(n)
			return "Increase melee damage by " .. pct(M.MELEE_POWER) .. " and melee attack rate by " .. pct(M.MELEE_RATE) .. ".\nTotal: +"
				.. pct(M.MELEE_POWER * n) .. ", +" .. pct(M.MELEE_RATE * n)
		end,
		apply = function(env, n, player)
			env.stat(player, "melee", 1 + M.MELEE_POWER * n)
			env.stat(player, "melee_rate", 1 + M.MELEE_RATE * n)
		end,
	},
	{
		id = "divers_resolve", rarity = "common", icon = "stratagem_reinforcements", name = "Diver's Resolve", max = 3,
		text = function(n) return "Take 20% less damage while downed, and self-recover 15% faster.\nTotal: -" .. pct(0.20 * n) .. ", +" .. pct(0.15 * n) end,
		apply = function(env, n, player)
			env.stat(player, "downed_damage", math.max(0, 1 - 0.20 * n))
			env.stat(player, "recover", 1 + 0.15 * n)
		end,
	},
	{
		id = "strike_back", rarity = "common", icon = "stratagem_turret", name = "Strike Back", max = 5,
		text = function(n) return "10% of damage taken from enemies within 2 m is dealt back to them.\nTotal: " .. pct(0.10 * n) end,
		apply = function(env, n, player) env.stat(player, "strike_back", 0.10 * n) end,
	},
	{
		id = "extra_padding", rarity = "common", icon = "stratagem_shield_generator_pack", name = "Extra Padding", max = 6,
		text = function(n) return "Gain +" .. M.PADDING .. " health and +" .. M.PADDING_ARMOR .. " armor.\nTotal: +" .. M.PADDING * n .. " health, +" .. M.PADDING_ARMOR * n .. " armor" end,
		apply = function(env, n, player)
			env.stat(player, "padding", M.PADDING * n)
			env.stat(player, "armor", M.PADDING_ARMOR * n)
		end,
	},
	{
		id = "elusive_tactics", rarity = "common", icon = "stratagem_jumppack", name = "Elusive Tactics", max = 3,
		text = function(n)
			return "Dive " .. pct(M.DIVE_FARTHER) .. " farther, stunning nearby enemies for " .. seconds(M.DIVE_STUN) .. ".\nTotal: +"
				.. pct(M.DIVE_FARTHER * n) .. ", " .. secs(M.DIVE_STUN * n)
		end,
		apply = function(env, n, player)
			env.stat(player, "dive", 1 + M.DIVE_FARTHER * n)
			env.stat(player, "dive_stun", M.DIVE_STUN * n)
		end,
	},
	{
		id = "kinetic_battery", rarity = "common", icon = "stratagem_tesla_tower", name = "Kinetic Battery", max = 5, api = "world.arc",
		text = function(n)
			return "Discharge arc attacks towards " .. M.battery_chains(1) .. " nearby enemies for every " .. metres(M.battery_metres(1)) .. " you move.\nTotal: "
				.. M.battery_chains(n) .. " enemies every " .. metres(M.battery_metres(n))
		end,
		apply = function(env, n, player) env.stat(player, "battery", n) end,
	},
	{
		id = "cluster_grenade", rarity = "common", icon = "stratagem_airstrike", name = "Cluster Grenade", max = 3,
		text = function(n) return "Grenades generate +1 explosion nearby.\nTotal: +" .. n .. (n == 1 and " explosion" or " explosions") end,
		apply = function(env, n, player) env.stat(player, "cluster", n) end,
	},
	{
		id = "meritocracy", rarity = "common", icon = "stratagem_reinforcements", name = "Meritocracy", max = 5,
		text = function(n) return "Each sample collected takes 2% off the time left on each stratagem's cooldown.\nTotal: " .. pct(M.MERIT * n) .. " a sample" end,
		apply = function(env, n, player) env.stat(player, "merit", M.MERIT * n) end,
	},
	-- Rare
	{
		id = "arsenal_support", rarity = "rare", icon = "stratagem_recoillessrifle", name = "Arsenal Support", max = 5, needs = M.EXPENDABLES,
		text = function(n) return "Call down a random expendable support weapon every 60 seconds.\nTotal: Every " .. secs(math.max(5, 67 - 7 * n)) end,
		apply = function(env, n, player)
			env.every(player, "arsenal_support", math.max(5, 67 - 7 * n), function()
				local name = env.random_unlocked(M.EXPENDABLES)
				local pos = env.near(player)
				if name and pos then env.call_stratagem(player, name, pos) end
			end)
		end,
	},
	{
		id = "rapid_fire", rarity = "rare", icon = "stratagem_missile_barrage", name = "Rapid Fire", max = 4,
		text = function(n) return "The primary weapon fires 20% faster.\nTotal: +" .. pct(0.20 * n) end,
		apply = function(env, n, player) env.stat(player, "firerate", 1 + 0.20 * n) end,
	},
	{
		id = "quick_cycle", rarity = "rare", icon = "stratagem_drone_defensive", name = "Quick Cycle", max = 5,
		text = function(n) return "All weapons reload or cool down 20% faster.\nTotal: +" .. pct(0.20 * n) end,
		apply = function(env, n, player) env.stat(player, "cycle", 1 + 0.20 * n) end,
	},
	{
		id = "shield_generator_pack", rarity = "rare", icon = "stratagem_shield_generator_pack", name = "Shield Generator Pack", max = 4,
		text = function(n) return "A shield that takes 50 damage and comes back. Adds to a shield backpack.\nTotal: " .. 50 * n end,
		apply = function(env, n, player) env.stat(player, "shield", 50 * n) end,
	},
	{
		id = "strategic_reserve", rarity = "rare", icon = "stratagem_emergency_beacon", name = "Strategic Reserve", max = 3,
		text = function(n) return "Stratagems recharge 20% faster and have 15% faster call times.\nTotal: -" .. pct(0.20 * n) .. ", -" .. pct(0.15 * n) end,
		apply = function(env, n, player)
			env.stat(player, "cooldown", math.max(0.1, 1 - 0.20 * n))
			env.stat(player, "call_time", math.max(0.1, 1 - 0.15 * n))
		end,
	},
	{
		id = "fast_reflexes", rarity = "rare", icon = "stratagem_airstrike", name = "Fast Reflexes", max = 2,
		text = function(n) return "Swap weapons and pick up items 50% faster.\nTotal: +" .. pct(0.50 * n) end,
		apply = function(env, n, player) env.stat(player, "reflexes", 1 + 0.50 * n) end,
	},
	{
		id = "guard_dog", rarity = "rare", icon = "stratagem_drone_defensive", name = "Guard Dog", max = 3, needs = { "stratagem_drone_defensive_backpack" }, newer_api = true,
		text = function(n) return "A Guard Dog drone shoots nearby enemies, with no backpack slot taken.\nTotal: " .. n .. (n == 1 and " drone" or " drones") end,
		apply = function(env, n, player) env.stat(player, "guard_dogs", n) end,
	},
	{
		id = "angel", rarity = "rare", icon = "stratagem_drone_heal", name = "Angel", max = 3, needs = { "stratagem_drone_heal_backpack" }, newer_api = true,
		text = function(n) return "An Angel drone heals the player and nearby Helldivers, with no backpack slot taken.\nTotal: " .. n .. (n == 1 and " drone" or " drones") end,
		apply = function(env, n, player) env.stat(player, "angels", n) end,
	},
	{
		id = "exo_expert", rarity = "rare", icon = "stratagem_jumppack", name = "EXO Expert", max = 3, needs = M.VEHICLES,
		text = function(n) return "Piloted vehicles move and turn 40% faster.\nTotal: +" .. pct(M.EXO * n) end,
		apply = function(env, n, player) env.stat(player, "vehicle", 1 + M.EXO * n) end,
	},
	{
		id = "ignition_rounds", rarity = "rare", icon = "stratagem_airstrike", name = "Ignition Rounds", max = 3, api = "combat.on_hit",
		text = function(n) return "Primary hits set the enemy on fire at " .. pct(M.BUILD_UP[1]) .. " of max health.\nTotal: every " .. pct(M.BUILD_UP[math.min(n, #M.BUILD_UP)]) .. " of max health" end,
		apply = function(env, n, player) env.stat(player, "ignite", M.BUILD_UP[math.min(n, #M.BUILD_UP)]) end,
	},
	{
		id = "needle_rounds", rarity = "rare", icon = "stratagem_uav", name = "Needle Rounds", max = 3, api = "combat.on_hit",
		text = function(n) return "Primary hits poison the enemy at " .. pct(M.BUILD_UP[1]) .. " of max health.\nTotal: every " .. pct(M.BUILD_UP[math.min(n, #M.BUILD_UP)]) .. " of max health" end,
		apply = function(env, n, player) env.stat(player, "needle", M.BUILD_UP[math.min(n, #M.BUILD_UP)]) end,
	},
	{
		id = "deep_pockets", rarity = "rare", icon = "stratagem_resupply", name = "Deep Pockets", max = 4,
		text = function(n)
			return "Carry +1 grenade. Generate a grenade every " .. M.POCKETS_SECONDS .. " seconds.\nTotal: +" .. n .. (n == 1 and " grenade" or " grenades")
				.. ", every " .. secs(M.pockets_seconds(n))
		end,
		apply = function(env, n, player) env.stat(player, "pockets", n) end,
	},
	{
		-- src/fight.lua takes the armor off the power of a hit from the front, before the game prices it.
		id = "facetanker", rarity = "rare", icon = "stratagem_shield_generator_pack", name = "Facetanker", max = 3,
		text = function(n) return "Gain +" .. M.FRONT_ARMOR .. " armor against hits from the front.\nTotal: +" .. M.FRONT_ARMOR * n .. " armor" end,
		apply = function(env, n, player) env.stat(player, "front_armor", M.FRONT_ARMOR * n) end,
	},
	{
		id = "trailblazer", rarity = "rare", icon = "stratagem_airstrike", name = "Trailblazer", max = 2,
		text = function(n) return "Sprinting leaves a fire trail that burns for " .. seconds(M.TRAIL_SECONDS) .. ". It never burns the player.\nTotal: " .. secs(M.TRAIL_SECONDS * n) end,
		apply = function(env, n, player) env.stat(player, "trail", M.TRAIL_SECONDS * n) end,
	},
	-- Legendary
	{
		id = "destroyer_support", rarity = "legendary", icon = "stratagem_orbital_strike", name = "Destroyer Support", max = 3, needs = { "stratagem_orbital_strike" },
		text = function(n) return "Every 40 seconds, an instant Orbital Laser is called nearby.\nTotal: Every " .. secs(math.max(5, 50 - 10 * n)) end,
		apply = function(env, n, player)
			env.every(player, "destroyer_support", math.max(5, 50 - 10 * n), function()
				local pos = env.nearest_enemy(player, M.LASER_CLEARANCE)
				if pos then env.call_stratagem(player, "stratagem_orbital_strike", pos, "destroyer_support") end
			end)
		end,
	},
	{
		id = "sweet_liberty", rarity = "legendary", icon = "stratagem_hellbomb", name = "Sweet Liberty", max = 1,
		text = function() return "Enemies killed by the player explode." end,
		-- The blast has the look of the grenade the player carries (src/run.lua), and the other machines
		-- show it for this player's kills too.
		apply = function(env, _, player)
			env.stat(player, "liberty", true)
			env.on_kill(player, "sweet_liberty", function(pos) env.liberty(player, pos) end)
		end,
	},
	{
		id = "absolute_freedom", rarity = "legendary", icon = "stratagem_railcannon_strike", name = "Absolute Freedom", max = 1,
		text = function() return "All weapons ignore armor." end,
		apply = function(env, _, player) env.stat(player, "pierce", true) end,
	},
	{
		id = "suitable_replacement", rarity = "legendary", icon = "stratagem_turret", name = "Suitable Replacement", max = 1, needs = { "stratagem_turret" },
		text = function() return "On death, a Minigun Turret drops where the player fell." end,
		apply = function(env, _, player)
			env.on_death(player, "suitable_replacement", function(pos) env.call_stratagem(player, "stratagem_turret", pos, "suitable_replacement") end)
		end,
	},
	{
		id = "broad_permit", rarity = "legendary", icon = "stratagem_metal_detector", name = "Broad Permit", max = 1,
		-- The base is rules.CARDS (3) and rules.STRATAGEM_CHOICES (3): tests/test_logic.lua keeps the words in line.
		text = function() return "Choose between " .. (3 + M.PERMIT_CARDS) .. " upgrades and " .. (3 + M.PERMIT_STRATAGEMS) .. " stratagems on level up." end,
		apply = function(env, _, player)
			env.stat(player, "extra_cards", M.PERMIT_CARDS)
			env.stat(player, "extra_stratagems", M.PERMIT_STRATAGEMS)
		end,
	},
	{
		id = "warp_pack", rarity = "legendary", icon = "stratagem_jumppack", name = "Warp Pack", max = 1, api = "world.raycast",
		text = function() return "Diving teleports the player forward, up to " .. M.WARP_METRES .. " metres." end,
		apply = function(env, _, player) env.stat(player, "warp", M.WARP_METRES) end,
	},
	{
		id = "democracy_protects", rarity = "legendary", icon = "stratagem_reinforcements", name = "Democracy Protects", max = 1, api = "combat.on_fatal",
		text = function() return pct(M.DEMOCRACY_CHANCE) .. " chance of resisting fatal or downing damage." end,
		apply = function(env, _, player) env.stat(player, "democracy", M.DEMOCRACY_CHANCE) end,
	},
	{
		id = "unstoppable_freedom", rarity = "legendary", icon = "stratagem_shield_generator_pack", name = "Unstoppable Freedom", max = 1,
		text = function() return "Gain immunity to all status effects." end,
		apply = function(env, _, player) env.stat(player, "unstoppable", true) end,
	},
	{
		id = "weight_training", rarity = "legendary", icon = "stratagem_machinegun", name = "Weight Training", max = 1,
		text = function() return "Move freely while aiming or firing any weapon." end,
		apply = function(env, _, player) env.stat(player, "weight_training", true) end,
	},
	{
		-- src/perks.lua: the sidearm's ammo kept full, and Weight Training's speed while it's in hand.
		id = "quick_draw", rarity = "legendary", icon = "stratagem_resupply", name = "Gunslinger", max = 1,
		text = function() return "Sidearms never run out of ammo and don't slow the player down." end,
		apply = function(env, _, player) env.stat(player, "gunslinger", true) end,
	},
}

-- Whether the Obsidian API at hand has the call `path` names, such as "combat.on_hit".
function M.has_api(api, path)
	local at = api
	for part in path:gmatch("[^.]+") do
		if type(at) ~= "table" then return false end
		at = at[part]
	end
	return at ~= nil
end

-- Perks: the game's perks as an extra perk, on top of the one the player took (Obsidian API's add_perk).
-- Laser Aim Module isn't here: it runs code every frame, which only the main perk gets. Only one
-- grenade and one sidearm: each replaces the last.
M.PERKS = {
	{ id = "autoinjector", perk = "perk_adrenaline", name = "Autoinjector", text = "Heal over time, and get back up faster when downed." },
	{ id = "all_terrain_boots", perk = "perk_all_terrain_boots", name = "All Terrain Boots", text = "Rough ground and weather cause no slowdown." },
	{ id = "cardio_accelerator", perk = "perk_cardio", name = "Cardio Accelerator", text = "Sprint without running out of stamina." },
	{ id = "heavy_armor", perk = "perk_heavy_armor", name = "Heavy Armor", text = "Take far less damage from small arms, but sprint slower." },
	{ id = "incendiary_grenades", perk = "perk_grenade_incendiary", group = "grenade", name = "Incendiary Grenades", text = "Grenades leave a fire behind." },
	{ id = "stun_grenades", perk = "perk_grenade_stun", group = "grenade", name = "Stun Grenades", text = "Grenades stun everything in a large area." },
	{ id = "smoke_grenades", perk = "perk_grenade_smoke", group = "grenade", name = "Smoke Grenades", text = "Grenades make smoke that enemies can't see through." },
	{ id = "stratagem_priority", perk = "perk_stratagem_expert", name = "Stratagem Priority", text = "Stratagems recharge 40% faster." },
	{ id = "displacement_field", perk = "perk_teleport_shield", name = "Displacement Field", text = "A badly wounding hit teleports the player a short way instead." },
	{ id = "strong_arm", perk = "perk_strong_arm", name = "Strong Arm", text = "Throw farther and hit harder in melee." },
	{ id = "gunslinger", perk = "perk_revolver_sidearm", group = "sidearm", name = "P-6 Gunslinger", text = "The sidearm becomes the P-6 'Gunslinger' revolver." },
	{ id = "pyro", perk = "perk_flamepistol_sidearm", group = "sidearm", name = "Pyro", text = "The sidearm becomes the FLAM-24 'Pyro' flamer." },
	{ id = "singe", perk = "perk_plasmapistol_sidearm", group = "sidearm", name = "Singe", text = "The sidearm becomes the PLAS-3 'Singe' plasma pistol." },
	{ id = "precision_call_in", perk = "perk_precision_call_in", name = "Precision Call-in", text = "Stratagems land 1 second sooner." },
}

for _, p in ipairs(M.PERKS) do
	local text, perk = p.text, p.perk
	M.list[#M.list + 1] = {
		id = p.id, rarity = "perk", icon = "stratagem_resupply", name = p.name, max = 1, perk = perk, group = p.group,
		text = function() return text end,
		apply = function(env, _, player) env.add_perk(player, perk) end,
	}
end

-- Whether a perk upgrade can be offered to a player who holds `held` ({ [perk name] = true }, their
-- main perk included) and has unlocked what `unlocked(name)` says.
function M.perk_open(u, held, unlocked)
	if held[u.perk] or not unlocked(u.perk) then return false end
	if u.group then
		for _, other in ipairs(M.list) do
			if other.group == u.group and held[other.perk] then return false end
		end
	end
	return true
end

-- Evolutions (src/evolve.lua): a player holding both halves of a pair, the first at its max stacks, can be
-- offered the pair's evolution. Taking it uses both halves up: they leave the build, and the evolution
-- applies each at the stacks it had (absorbed, { [id] = stacks }, src/run.lua keeps it) and adds its own
-- effect. link: the color of the marker the halves' badges share on the map panel once the pair is ready.
M.CARPET_RING = 2 -- Carpet Bombing: smaller blasts round each cluster blast
M.CARPET_RADIUS = 3
M.CARPET_DELAY = 0.15
M.CARPET_SIZE = 0.6 -- of the grenade's power and radius
M.CARPET_RATE = 2 -- grenades back this many times as fast
M.NAPALM_CLOUD_RADIUS = 4
M.NAPALM_CLOUD_SECONDS = 4
M.NAPALM_CLOUD_TICK = 1
M.DYNAMO_RATE = 3.5 -- Dynamo: a second of firing charges as much as this many metres moved, half a sprint
M.SAINT_SECONDS = 2
M.SAINT_HEAL = 0.25
M.SPIKED_REACH = 6
M.SPIKED_TIMES = 2
M.SIPHON_RADIUS = 12
M.CHAIN_RADIUS = 4
M.CHAIN_LIMIT = 24 -- Chain Reaction's blasts waiting at once, at the most

local function evolution(e)
	local a, b, own = e.a, e.b, e.apply
	return {
		id = e.id, rarity = "evolution", icon = e.icon, name = e.name, max = 1, evolves = { a, b }, link = e.link,
		-- The halves are the icons in the card's corner (src/cards.lua).
		text = function() return e.text .. "\nTotal: Both halves kept" end,
		apply = function(env, _, player, absorbed)
			absorbed = absorbed or {}
			for _, id in ipairs({ a, b }) do
				local half = M.by_id[id]
				if half then half.apply(env, absorbed[id] or half.max or 1, player) end
			end
			own(env, player, absorbed)
		end,
	}
end

M.EVOLUTIONS = {
	evolution({ id = "carpet_bombing", name = "Carpet Bombing", a = "cluster_grenade", b = "deep_pockets", icon = "stratagem_airstrike", link = "#ff9a3c",
		text = "Cluster blasts set off " .. M.CARPET_RING .. " smaller blasts each. Grenades come back twice as fast.",
		apply = function(env, player)
			env.stat(player, "carpet", M.CARPET_RING)
			env.stat(player, "pockets_rate", M.CARPET_RATE)
		end }),
	evolution({ id = "napalm_needles", name = "Napalm Needles", a = "ignition_rounds", b = "needle_rounds", icon = "stratagem_uav", link = "#9be15d",
		text = "One build-up burns and poisons. Burning kills leave a " .. M.NAPALM_CLOUD_RADIUS .. " m poison cloud.",
		apply = function(env, player) env.stat(player, "napalm", true) end }),
	evolution({ id = "dynamo", name = "Dynamo", a = "weight_training", b = "kinetic_battery", icon = "stratagem_tesla_tower", link = "#ffe14a",
		text = "Firing also charges Kinetic Battery, at half the rate of a sprint.",
		apply = function(env, player) env.stat(player, "dynamo", M.DYNAMO_RATE) end }),
	evolution({ id = "iron_saint", name = "Iron Saint", a = "democracy_protects", b = "divers_resolve", icon = "stratagem_reinforcements", link = "#d9a3ff",
		text = "A save gives " .. M.SAINT_SECONDS .. " s of invulnerability and heals " .. pct(M.SAINT_HEAL) .. " of max health.",
		apply = function(env, player)
			env.stat(player, "saint_seconds", M.SAINT_SECONDS)
			env.stat(player, "saint_heal", M.SAINT_HEAL)
		end }),
	evolution({ id = "spiked_plating", name = "Spiked Plating", a = "strike_back", b = "extra_padding", icon = "stratagem_shield_generator_pack", link = "#ff6fae",
		text = "Strike Back reaches " .. M.SPIKED_REACH .. " m instead of 2 m and deals back twice the share.",
		apply = function(env, player)
			env.stat(player, "strike_reach", M.SPIKED_REACH)
			env.stat(player, "strike_times", M.SPIKED_TIMES)
		end }),
	evolution({ id = "sample_siphon", name = "Sample Siphon", a = "analysis_field", b = "molecular_scan", icon = "stratagem_metal_detector", link = "#4ae0c0",
		text = "Samples from kills within " .. M.SIPHON_RADIUS .. " m fly straight to the player.",
		apply = function(env, player) env.stat(player, "siphon", M.SIPHON_RADIUS) end }),
	evolution({ id = "chain_reaction", name = "Chain Reaction", a = "sweet_liberty", b = "cluster_grenade", icon = "stratagem_hellbomb", link = "#b0b8ff",
		text = "Sweet Liberty blasts cluster: each sets off as many more blasts as a grenade does.",
		apply = function(env, player) env.stat(player, "chain", true) end }),
}
for _, e in ipairs(M.EVOLUTIONS) do M.list[#M.list + 1] = e end

-- The card for a slot nothing else can fill. It has no limit, and it's never in the pool.
M.fallback = {
	id = "patch_up", rarity = "common", icon = "stratagem_resupply", name = "Patch Up",
	text = function() return "Refills health, ammo and grenades." end,
	apply = function(env, _, player) env.patch_up(player) end,
}

M.by_id = { [M.fallback.id] = M.fallback }
for _, u in ipairs(M.list) do M.by_id[u.id] = u end

return M
