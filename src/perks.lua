-- What a player's stats (src/upgrades.lua) do to their unit and weapons, kept up every frame: a respawn
-- brings a new unit with new weapons, and they take the same numbers. Everything here is this player's
-- own, whoever else carries the same weapon.
local rules = obsidian.module("src/rules")
local shield = obsidian.module("src/shield")
local trail = obsidian.module("src/trail")

local upgrades = obsidian.module("src/upgrades")

local api = obsidian.import("obsidian.api")

local M = {}

function M.stats()
	return {
		magnet = 1, xp_gain = 1, speed = 1, panic_heal = 0, capacity = 1, spread = 1, turn = 1,
		power = 1, firerate = 1, cycle = 1, shield = 0, cooldown = 1, call_time = 1, reflexes = 1,
		pierce = false, extra_cards = 0, extra_stratagems = 0, melee = 1, guard_dogs = 0, angels = 0, perks = {},
		dive = 1, get_up = 1, warp = 0, ignite = 0, needle = 0, democracy = 0, unstoppable = false,
		downed_damage = 1, recover = 1, strike_back = 0, padding = 0, armor = 0, liberty = false,
		merit = 0, vehicle = 1, battery = 0, cluster = 0, pockets = 0, weight_training = false,
		melee_rate = 1, dive_stun = 0, front_armor = 0, trail = 0, gunslinger = false,
	}
end

-- Armor, as the game's Heavy Armor perk sets it: the guarded copy on the master and the copy the damage
-- sums read, both through the health component's "armor" command (a direct write trips the game's
-- tamper check).
local function set_armor(unit, low, high)
	local data = { armor_min = low, armor_max = high }
	api.game.command(unit, "health", "armor", data)
	local aux = api.game.global("EntityAux")
	if aux and aux.queue_command_slave then pcall(aux.queue_command_slave, unit, "health", "armor", data) end
end

-- Extra Padding's armor goes on top of what the body has: its own, or Heavy Armor's once a perk sets
-- that. A value the game wrote since the last one written here is taken as the new base.
local function sync_armor(p, unit, health)
	if type(health.armor_min) ~= "number" or type(health.armor_max) ~= "number" then return end
	local base, wrote = p.body_base.armor, p.body_base.armor_wrote
	local now = { health.armor_min, health.armor_max }
	local function same(a, b) return a ~= nil and b ~= nil and a[1] == b[1] and a[2] == b[2] end
	if not base or not (same(now, wrote) or same(now, base)) then base, p.body_base.armor = now, now end
	local want = { base[1] + p.stats.armor, base[2] + p.stats.armor }
	if same(want, now) or same(want, wrote) then return end
	p.body_base.armor_wrote = want
	set_armor(unit, want[1], want[2])
end

-- Extra Padding and Diver's Resolve: more health and armor, and fewer presses to get up when downed. The
-- game reads them from the body's own state, which a new body starts from the shared settings, so each
-- body keeps its starting values and gets the stats on top. Raising the maximum heals the difference.
local function sync_body(p, unit)
	if p.body_unit ~= unit then p.body_unit, p.body_base = unit, {} end
	local health = api.game.master(unit, "health")
	if health and type(health.max_hitpoints) == "number" then
		p.body_base.max = p.body_base.max or health.max_hitpoints
		local want = p.body_base.max + p.stats.padding
		if health.max_hitpoints ~= want then
			local more = want - health.max_hitpoints
			health.max_hitpoints = want
			if more > 0 and not health.is_downed and not health.is_dead then api.game.command(unit, "health", "do_heal", more) end
		end
		-- This machine's HUD reads the copy every machine has. A new body's copy can come a frame after
		-- the master, or start again from the settings, so the copy is checked every frame, not only when the
		-- master changes: otherwise a respawn shows 125 / 100.
		local copy = api.game.slaves("health")[unit]
		if copy and copy.state and copy.state.max_hitpoints ~= want then copy.state.max_hitpoints = want end
		local shown = api.game.global("EntityAux").state(unit, "health")
		if type(shown) == "table" and shown.max_hitpoints ~= want then shown.max_hitpoints = want end
		sync_armor(p, unit, health)
	end
	local character = api.game.master(unit, "character")
	if character and type(character.get_up_presses_needed) == "number" then
		p.body_base.presses = p.body_base.presses or character.get_up_presses_needed
		local want = math.max(1, math.ceil(p.body_base.presses / p.stats.recover))
		if character.get_up_presses_needed ~= want then character.get_up_presses_needed = want end
	end
end

-- The body's maximum health, armor and current health, as the stat box shows them: nil when there's
-- no telling.
function M.body_numbers(unit)
	local health = unit and api.game.global("EntityAux").state(unit, "health")
	if type(health) ~= "table" then return nil end
	return health.max_hitpoints, health.armor_max, health.hitpoints
end

-- Health back at once, never past the maximum, and not while downed: Iron Saint's heal (M.heal_share).
function M.heal(unit, amount)
	local health = unit and api.game.global("EntityAux").state(unit, "health")
	if not health or health.is_dead or health.is_downed then return end
	local whole = math.min(math.floor(amount), math.floor((health.max_hitpoints or 0) - (health.hitpoints or 0)))
	if whole >= 1 then api.game.command(unit, "health", "do_heal", whole) end
end

-- A share of the body's max health back (Iron Saint).
function M.heal_share(unit, share)
	local health = unit and api.game.global("EntityAux").state(unit, "health")
	if type(health) ~= "table" then return end
	M.heal(unit, (health.max_hitpoints or 0) * share)
end

-- Panic: a hit starts the regeneration (M.panic), unless one is running. Hitpoints travel as whole
-- numbers, so the health goes on a point at a time, never past the maximum, and not while downed.
function M.panic(p)
	if p.stats.panic_heal <= 0 or (p.panic_left or 0) > 0 then return end
	p.panic_left, p.panic_owed = upgrades.PANIC_SECONDS, 0
end

local function sync_panic(p, unit, dt)
	if (p.panic_left or 0) <= 0 then return end
	local step = math.min(dt, p.panic_left)
	p.panic_left = p.panic_left - step
	p.panic_owed = p.panic_owed + p.stats.panic_heal / upgrades.PANIC_SECONDS * step
	local health = api.game.global("EntityAux").state(unit, "health")
	if not health or health.is_dead or health.is_downed then return end
	local room = (health.max_hitpoints or 0) - (health.hitpoints or 0)
	local whole = math.min(math.floor(p.panic_owed), math.floor(room))
	if whole >= 1 then
		p.panic_owed = p.panic_owed - whole
		api.game.command(unit, "health", "do_heal", whole)
	end
end

-- Unstoppable Freedom: every element of status is kept off the body, the way the game's own immunities
-- work. A new body after a death starts with none, and whatever was on the body comes off.
local function sync_immunity(p, unit)
	if not p.stats.unstoppable or p.immune_unit == unit then return end
	p.immune_unit = unit
	for element in pairs(rawget(_G, "StatusElementLookup") or {}) do
		api.game.command(unit, "status", "add_immunity_element", element)
	end
	api.game.command(unit, "status", "remove_all")
end

-- The character states the game moves at the weapon's move_speed_aim in (CharacterComponent's update):
-- wanted_move_speed times that factor.
local AIMING = { "CharacterStateAim", "CharacterStateAimFire", "CharacterStateAimWalk", "CharacterStateAimWalkFire",
	"CharacterStateFire", "CharacterStateWalkFire" }

-- Whether the body is firing a weapon now (Dynamo, src/battery.lua): one of the character's firing states.
local FIRING = { "CharacterStateAimFire", "CharacterStateAimWalkFire", "CharacterStateFire", "CharacterStateWalkFire" }
function M.firing(unit)
	local cs = unit and api.game.master(unit, "character")
	local state = cs and cs.current_state
	if state == nil then return false end
	for _, name in ipairs(FIRING) do
		if state == api.game.global(name) then return true end
	end
	return false
end

-- The factor a weapon needs for the state's speed to reach `jog`: its own when that's faster.
function M.aim_factor(own, wanted, jog)
	if type(wanted) ~= "number" or wanted <= 0 then return own end
	return math.max(own or 0, jog / wanted)
end

-- Weight Training: while aiming or firing, the weapon in hand moves the player at jog speed, the support
-- weapons that hold the player in place too; Gunslinger does the same for the sidearm alone. The factor
-- is a plain field of the weapon's state, which the game writes again on a reload of the weapon's
-- settings, so it's kept up every frame; the weapon's own goes back when the upgrade does.
function M.moves_freely(stats, sidearm)
	return stats.weight_training == true or (stats.gunslinger == true and sidearm == true)
end

local function sync_weight(p, unit)
	p.weight_own = p.weight_own or {}
	local g = api.game.global
	local inv = api.game.master(unit, "inventory")
	local weapon = inv and inv.current_weapon
	local ok, ws = pcall(g("EntityAux").state_interface, weapon, "weapon")
	if not (weapon and ok and type(ws) == "table") then return end
	if not M.moves_freely(p.stats, weapon == inv.sidearm_weapon) then
		if p.weight_own[weapon] ~= nil then ws.move_speed_aim, p.weight_own[weapon] = p.weight_own[weapon], nil end
		return
	end
	local cs = api.game.master(unit, "character")
	local state = cs and cs.current_state
	local aiming = false
	for _, name in ipairs(AIMING) do
		if state ~= nil and state == g(name) then aiming = true end
	end
	if not aiming then return end
	if p.weight_own[weapon] == nil then p.weight_own[weapon] = ws.move_speed_aim or 1 end
	ws.move_speed_aim = M.aim_factor(p.weight_own[weapon], cs.wanted_move_speed, upgrades.JOG)
end

-- Peak Physique: each weapon's melee hits harder, and the swing is over sooner, so the next can start
-- sooner. CharacterStateMelee ends once the swing's time runs out (the weapon's melee_info.duration,
-- 0.33 s on most guns), and nothing else holds the next melee back. The hit lands after a delay that only
-- some weapons have (the bayonets' 0.2 s), cut by as much so it still lands inside the swing. The
-- animation plays at the game's own speed.
function M.melee_changes(stats)
	local c = {}
	if (stats.melee or 1) ~= 1 then c.power = stats.melee end
	local rate = stats.melee_rate or 1
	if rate ~= 1 and rate > 0 then c.duration, c.delay = 1 / rate, 1 / rate end
	return c
end

-- What one weapon's stats change by. slot: primary_weapon, sidearm_weapon or support_weapon.
function M.weapon_changes(stats, slot, component)
	local c = {}
	local function times(key, by) if by ~= 1 then c[key] = (c[key] or 1) * by end end
	-- Absolute Freedom: a firearm's hit carries ignore_armor, which takes the target's armor to 0
	-- (HealthComponent.calculate_damage) on every machine that prices it (WeaponUtility.shoot_ray_callback
	-- sends it with the hit). Armor piercing alone takes only 15 off, nothing against a tank.
	if stats.pierce and component == "firearm" then
		c.ignore_armor, c.armorpiercing = true, true
	elseif stats.pierce and slot ~= "support_weapon" then
		-- Beams, flames and arcs send their hits without it: armor piercing for those.
		c.armorpiercing = true
	end
	-- Every weapon: how fast it comes back.
	times("reload_duration", 1 / stats.cycle)
	times("reload_duration_fast", 1 / stats.cycle)
	times("heat_dissipation_per_second", stats.cycle)
	if slot == "primary_weapon" then
		-- Rapid Fire. Beams and arcs have no fire rate of their own: their heat builds slower instead.
		times("firerate", stats.firerate)
		times("rounds_per_second", stats.firerate)
		times("heat_increase", 1 / stats.firerate)
		times("heat_per_second", 1 / stats.firerate)
		if component == "arcweapon" then
			times("heat_per_second", 1 / stats.capacity)
		else
			times("magazine_capacity", stats.capacity)
			times("heat_capacity", stats.capacity)
		end
		times("spread", stats.spread)
		times("spread_min", stats.spread)
		times("spread_max", stats.spread)
		times("turn_speed_aim", stats.turn)
		times("power", stats.power)
		times("power_crit", stats.power)
		times("min_power", stats.power)
		times("max_power", stats.power)
	end
	return c
end

local function signature(changes)
	local keys = {}
	for k in pairs(changes) do keys[#keys + 1] = k end
	table.sort(keys)
	for i, k in ipairs(keys) do keys[i] = k .. "=" .. tostring(changes[k]) end
	return table.concat(keys, ";")
end

local function sync_weapons(cache, stats, unit)
	local melee = M.melee_changes(stats)
	local melee_sign = signature(melee)
	for _, w in ipairs(api.gear.weapons_of(unit)) do
		local changes = M.weapon_changes(stats, w.slot, w.component)
		local sign = signature(changes)
		if cache[w.unit] ~= sign then
			cache[w.unit] = sign
			api.gear.tune(w.unit, w.component, changes)
		end
		-- Only a weapon with a melee component of its own takes it.
		local key = tostring(w.unit) .. ":melee"
		if cache[key] ~= melee_sign and (cache[key] or melee_sign ~= "") then
			cache[key] = melee_sign
			if api.game.masters("melee")[w.unit] then api.gear.tune(w.unit, "melee", melee) end
		end
	end
end

-- Guard Dog and Angel: the drones of the game's drone packs, with the backpack slot left free (Obsidian
-- API's add_drone). A death takes them, as it drops a worn pack, and the new unit gets them again.
M.DRONES = {
	guard_dogs = "equipment/equipment_drone_defensive_backpack_01",
	angels = "equipment/equipment_drone_heal_backpack_01",
}

local function sync_drones(p, unit)
	if not api.gear.add_drone then return end
	p.drones = p.drones or {}
	if p.drones_unit ~= unit then p.drones_unit, p.drones_refused = unit, {} end
	for stat, path in pairs(M.DRONES) do
		local live = {}
		for _, d in ipairs(p.drones[stat] or {}) do
			if d.owner ~= unit then d:remove() elseif d:alive() then live[#live + 1] = d end
		end
		-- One refusal is enough until the next unit: the game won't change its mind every frame.
		while #live < p.stats[stat] and not p.drones_refused[stat] do
			local d, why = api.gear.add_drone(path, unit)
			if d then
				live[#live + 1] = d
			else
				p.drones_refused[stat] = true
				obsidian.log("arcade: no drone from " .. path .. ": " .. tostring(why))
			end
		end
		p.drones[stat] = live
	end
end

function M.remove_drones(p)
	for _, list in pairs(p.drones or {}) do
		for _, d in ipairs(list) do d:remove() end
	end
	p.drones = nil
end

local function reinforce_id()
	local s = api.catalog.stratagem("stratagem_reinforce")
	return s and s.id
end

local function reinforce_entry(inv)
	local id = reinforce_id()
	for _, e in ipairs(inv and inv.stratagems or {}) do
		if e.id == id then return e end
	end
	return nil
end

-- The HUD draws a cooldown's progress against the stratagem's own cooldown time, and past 100% the icon
-- tiles into a stack. So while it regenerates, the reinforcement's entry says the time it takes.
local function show_length(unit, seconds)
	local id = reinforce_id()
	local master, slave = api.game.master(unit, "inventory"), api.game.slaves("inventory")[unit]
	for _, inv in ipairs({ master or {}, slave and slave.state or {} }) do
		for _, e in ipairs(inv.stratagems or {}) do
			local info = e.loadout_info
			if e.id == id and info then
				if seconds and info.cooldown_time ~= seconds then
					local own = { survivors_real = info.survivors_real or info }
					for k, v in pairs(info) do own[k] = v end
					own.cooldown_time = seconds
					e.loadout_info = own
				elseif not seconds and info.survivors_real then
					e.loadout_info = info.survivors_real
				end
			end
		end
	end
end

local function set_cooldown(unit, entry, seconds)
	api.game.command(unit, "inventory", "set_stratagem_info", { id = entry.id, cooldown_timer = seconds })
	api.game.command(unit, "inventory", "broadcast_stratagem_cooldown")
end

-- The name of the perk a player took in the loadout, or nil.
function M.main_perk(unit)
	local inv = api.game.master(unit, "inventory")
	local ls = rawget(_G, "LoadoutSettings")
	local perk = inv and inv.perk and inv.perk > 0 and ls and ls.perks and ls.perks[inv.perk]
	return perk and perk.name or nil
end

-- Stratagem Priority cuts every cooldown by 40% with the same multiplier Strategic Reserve sets.
M.PRIORITY = "perk_stratagem_expert"
M.PRIORITY_COOLDOWN = 0.6

local function cooldown_multiplier(p, unit)
	local m = p.stats.cooldown
	local held = M.main_perk(unit) == M.PRIORITY
	for _, name in ipairs(p.stats.perks) do held = held or name == M.PRIORITY end
	if held then m = m * M.PRIORITY_COOLDOWN end
	return m
end

-- Strategic Reserve: the game scales every cooldown, so the reinforcement's own goes back up as it
-- starts. Each flare of the player's waits less as it appears.
local function sync_stratagems(p, unit, inv)
	local multiplier = cooldown_multiplier(p, unit)
	if p.cooldown_sent ~= multiplier or p.cooldown_unit ~= unit then
		p.cooldown_sent, p.cooldown_unit = multiplier, unit
		api.game.command(unit, "inventory", "set_stratagem_cooldown_multiplier", multiplier)
	end
	local entry = reinforce_entry(inv)
	if entry then
		local now = entry.cooldown_timer or 0
		if not p.regen_left and p.stats.cooldown < 1 and now > (p.reinforce_seen or 0) + 0.5 then
			now = now / p.stats.cooldown
			set_cooldown(unit, entry, now)
		end
		p.reinforce_seen = now
	end
	if p.stats.call_time < 1 then
		for _, ctx in pairs(api.game.masters("stratagem")) do
			local flare = ctx.state
			if flare.owner_unit == unit and not flare.survivors_call and (flare.activation_time or 0) > 0 then
				flare.survivors_call = true
				local info = flare.stratagem_info
				if not (info and info.name == "stratagem_reinforce") then flare.activation_time = flare.activation_time * p.stats.call_time end
			end
		end
	end
end

-- Fast Reflexes: the swap's timer runs faster, and an interaction takes a faster speed as it starts.
local function sync_reflexes(p, unit, inv, dt)
	if p.stats.reflexes <= 1 then return end
	if inv and (inv.switch_weapon_time or 0) > 0 then
		inv.switch_weapon_time = math.max(inv.switch_weapon_time - dt * (p.stats.reflexes - 1), 0)
	end
	local interactor = api.game.master(unit, "interactor")
	if interactor and interactor.interact_speed ~= p.interact_written then
		p.interact_written = (interactor.interact_speed or 1) * p.stats.reflexes
		interactor.interact_speed = p.interact_written
	end
end

-- Perk upgrades, as extra perks: a new body after a death starts with none.
local function sync_perks(p, unit)
	if #p.stats.perks == 0 or not api.gear.add_perk then return end
	if p.perks_unit ~= unit then p.perks_unit, p.perks_added = unit, {} end
	for _, name in ipairs(p.stats.perks) do
		if not p.perks_added[name] then
			-- Once a body: a refusal stays one.
			p.perks_added[name] = true
			local ok, why = api.gear.add_perk(name, unit)
			if not ok then obsidian.log("arcade: no " .. name .. ": " .. tostring(why)) end
		end
	end
end

-- Stratagems the player picked, which a respawn's new inventory doesn't have.
local function sync_picked(p, unit, inv)
	if not (inv and inv.stratagems) then return end
	for _, name in ipairs(p.stratagems) do
		local s = api.catalog.stratagem(name)
		local has = false
		for _, e in ipairs(inv.stratagems) do
			if s and e.id == s.id then has = true end
		end
		if s and not has then api.stratagems.give(name, unit) end
	end
end

-- Gunslinger: the sidearm's magazine and its spare magazines stay full, through the weapon's own
-- set_ammo, as a resupply fills them: after each shot, and whenever a reload starts. A heat weapon counts
-- heat in its rounds, so full is none. The game keeps the numbers within the weapon's own limits.
function M.sidearm_spent(ws, beam, top)
	if type(ws) ~= "table" or type(ws.rounds) ~= "number" then return false end
	if ws.is_reloading then return true end
	if beam then return ws.rounds > 0 end
	if type(ws.num_mags) == "number" and type(ws.magazines_max) == "number" and ws.num_mags < ws.magazines_max then return true end
	return top ~= nil and ws.rounds < top
end

local function sync_sidearm(p, unit, inv)
	if not p.stats.gunslinger then return end
	local weapon = inv and inv.sidearm_weapon
	local aux = api.game.global("EntityAux")
	if not (weapon and api.game.global("Unit").alive(weapon) and aux.has_interface(weapon, "weapon")) then return end
	local ok, ws = pcall(aux.state_master_interface, weapon, "weapon")
	if not (ok and type(ws) == "table") then return end
	if p.sidearm ~= weapon then p.sidearm, p.sidearm_top = weapon, nil end
	local beam = aux.has_component(weapon, "beamweapon")
	if type(ws.rounds) == "number" and (p.sidearm_top == nil or ws.rounds > p.sidearm_top) then p.sidearm_top = ws.rounds end
	if M.sidearm_spent(ws, beam, p.sidearm_top) then
		aux.queue_command_master_interface(weapon, "weapon", "set_ammo", { num_rounds = beam and 0 or 1000000, num_mags = 1000000 })
	end
end

-- EXO Expert's, defined below.
local sync_vehicle

function M.sync(p, unit, dt_game, dt_real)
	sync_panic(p, unit, dt_game)
	local inv = api.game.master(unit, "inventory")
	local mover = api.game.master(unit, "mover")
	if mover then
		local speed = p.stats.speed
		if speed ~= 1 then mover.velocity_scale = speed elseif p.speed_written ~= 1 then mover.velocity_scale = nil end
		p.speed_written = speed
	end
	sync_perks(p, unit)
	sync_immunity(p, unit)
	pcall(sync_weight, p, unit)
	sync_body(p, unit)
	sync_weapons(p.weapon_cache, p.stats, unit)
	shield.sync(unit, p.stats.shield)
	sync_stratagems(p, unit, inv)
	sync_reflexes(p, unit, inv, dt_real)
	sync_picked(p, unit, inv)
	sync_drones(p, unit)
	sync_vehicle(p, unit)
	pcall(sync_sidearm, p, unit, inv)
	local ok, err = pcall(trail.sync, p, unit, dt_game)
	if not ok and not p.trail_failed then
		p.trail_failed = true
		obsidian.log("arcade: trail: " .. tostring(err))
	end
end

-- Meritocracy: each sample collected takes `share` of the time left off every stratagem recharging, but
-- Reinforce, whose clock is the reinforcement's own (M.sync_reinforcement). It used to take a share
-- of the full cooldown for each point of the sample's XP, so a 3 XP sample at 4% took 12%.
-- The share of the time left that `samples` samples (1 when nil) leave.
function M.merit_keep(share, samples)
	return (1 - math.min(math.max(share or 0, 0), 1)) ^ math.max(samples or 1, 0)
end

-- samples: how many were collected at once.
function M.cut_cooldowns(unit, share, samples)
	if not unit or share <= 0 then return end
	local keep = M.merit_keep(share, samples)
	local inv = api.game.master(unit, "inventory")
	local reinforce = reinforce_id()
	local any = false
	for _, e in ipairs(inv and inv.stratagems or {}) do
		local left, full = e.cooldown_timer or 0, e.loadout_info and e.loadout_info.cooldown_time
		if e.id ~= reinforce and left > 0 and type(full) == "number" and full > 0 then
			api.game.command(unit, "inventory", "set_stratagem_info", { id = e.id, cooldown_timer = left * keep })
			any = true
		end
	end
	if any then api.game.command(unit, "inventory", "broadcast_stratagem_cooldown") end
end

-- EXO Expert: the vehicle the player drives moves and turns faster, as Obsidian API's vehicle_speed and
-- vehicle_turn do it for the main player, here for each of this machine's players. Walkers turn by a
-- blend factor under 1, where less is quicker; wheels and tracks in degrees a second. Each frame, since
-- the vehicle's own states write the turn as they change; the states that stand still are left alone.
local STOPPED = { exosuit = 1, apc = 0, bike = 0 }

local function let_go_vehicle(p)
	local v = p.vehicle_held
	p.vehicle_held = nil
	if not v then return end
	local mover = api.game.master(v, "mover")
	if mover then mover.velocity_scale = nil end
	local state = api.game.master(v, "vehicle")
	local info = state and state.vehicle_info
	if info and STOPPED[info.vehicle_type] ~= nil and state.rotation_speed ~= STOPPED[info.vehicle_type] then state.rotation_speed = info.turn_speed end
end

function sync_vehicle(p, unit)
	local character = api.game.master(unit, "character")
	local seat = character and character.current_seat_unit
	local state = seat and p.stats.vehicle ~= 1 and api.game.master(seat, "vehicle")
	if not state then
		let_go_vehicle(p)
		return
	end
	if p.vehicle_held ~= seat then
		let_go_vehicle(p)
		p.vehicle_held = seat
	end
	local mover = api.game.master(seat, "mover")
	if mover then mover.velocity_scale = p.stats.vehicle end
	local info = state.vehicle_info
	local stopped = info and STOPPED[info.vehicle_type]
	if stopped ~= nil and state.rotation_speed ~= stopped then
		state.rotation_speed = info.vehicle_type == "exosuit" and info.turn_speed ^ p.stats.vehicle or info.turn_speed * p.stats.vehicle
	end
end

function M.release_vehicle(p)
	pcall(let_go_vehicle, p)
end

-- Reinforcement regeneration: at 0 the clock runs, shown on the reinforcement stratagem as a cooldown.
function M.sync_reinforcement(p, record, unit, dt_game, st)
	local lives = record.extra_lives
	if not lives or st.infinite_respawns then return end
	if lives > 0 then
		-- A reinforcement came another way, as with Meritocracy: the clock is off.
		if p.regen_left and unit then
			local entry = reinforce_entry(api.game.master(unit, "inventory"))
			if entry then set_cooldown(unit, entry, 0) end
		end
		if unit then show_length(unit, nil) end
		p.regen_left, p.regen_shown = nil, nil
		return
	end
	p.regen_left = (p.regen_left or rules.REINFORCEMENT_BACK) - dt_game
	local inv = unit and api.game.master(unit, "inventory")
	local entry = reinforce_entry(inv)
	if p.regen_left <= 0 then
		st:set_extra_lives(record, 1)
		p.regen_left, p.regen_shown = nil, nil
		if entry then set_cooldown(unit, entry, 0) end
		if unit then show_length(unit, nil) end
		if not unit then record.spawn_timer = 0.01 end
		return true
	end
	if unit then show_length(unit, rules.REINFORCEMENT_BACK) end
	if entry and math.abs((entry.cooldown_timer or 0) - p.regen_left) > 1 then set_cooldown(unit, entry, p.regen_left) end
end

return M
