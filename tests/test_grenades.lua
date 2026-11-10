-- Cluster Grenade, Deep Pockets (src/grenades.lua) and Weight Training's factor (src/perks.lua), against
-- a fake Obsidian API.
local upgrades = obsidian.module("src/upgrades")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function fake()
	local api = { written = {}, inventory = {} }
	api.game = {
		master = function(unit, name) return name == "inventory" and api.inventory[unit] or nil end,
		protected = function(component, state, key, value)
			api.written[#api.written + 1] = { component = component, key = key, value = value }
			state[key] = value
			return true
		end,
	}
	local had = obsidian.import
	obsidian.import = function() return api end
	local grenades = dofile("src/grenades.lua")
	obsidian.import = had
	return grenades, api
end

local function fixed(...)
	local list, i = { ... }, 0
	return function()
		i = i % #list + 1
		return list[i]
	end
end

test("the_cards_read_with_their_numbers", function()
	eq(upgrades.by_id.cluster_grenade.text(1), "Grenades generate +1 explosion nearby.\nTotal: +1 explosion")
	eq(upgrades.by_id.cluster_grenade.text(3), "Grenades generate +1 explosion nearby.\nTotal: +3 explosions")
	eq(upgrades.by_id.deep_pockets.text(1), "Carry +1 grenade. Generate a grenade every 16 seconds.\nTotal: +1 grenade, every 16 s")
	eq(upgrades.by_id.deep_pockets.text(4), "Carry +1 grenade. Generate a grenade every 16 seconds.\nTotal: +4 grenades, every 10 s")
	eq(upgrades.by_id.weight_training.text(1), "Move freely while aiming or firing any weapon.")
end)

test("only_thrown_grenades_cluster", function()
	local grenades = fake()
	eq(grenades.is_grenade("equipment/equipment_grenade_01"), true)
	eq(grenades.is_grenade("equipment/equipment_impact_grenade_incendiary"), true)
	eq(grenades.is_grenade("equipment/equipment_grenade_stun"), true)
	eq(grenades.is_grenade("equipment/wep_grenadelauncher_01"), false, "a launcher's shell isn't a hand grenade")
	eq(grenades.is_grenade(nil), false)
end)

test("cluster_spots_spread_round_the_blast_one_after_another", function()
	local grenades = fake()
	local spots = grenades.cluster_spots({ x = 10, y = 20, z = 1 }, 3, 3.5, 0.15, fixed(0.5))
	eq(#spots, 3)
	for i, s in ipairs(spots) do
		local d = math.sqrt((s.x - 10) ^ 2 + (s.y - 20) ^ 2)
		eq(d >= 1.75 - 1e-6 and d <= 3.5 + 1e-6, true, "within the radius, not on top of the grenade")
		near(s.delay, 0.15 * i)
		eq(s.z, 1)
	end
end)

test("queued_blasts_go_off_as_their_delays_run_out", function()
	local grenades = fake()
	local side = grenades.new()
	side.queue = { { delay = 0.15 }, { delay = 0.30 } }
	local fired = 0
	grenades.step(side, 0.1, function() fired = fired + 1 end)
	eq(fired, 0)
	grenades.step(side, 0.1, function() fired = fired + 1 end)
	eq(fired, 1)
	grenades.step(side, 0.2, function() fired = fired + 1 end)
	eq(fired, 2)
	eq(#side.queue, 0)
end)

test("another_machine_draws_a_cluster_once_and_without_power", function()
	local grenades = fake()
	local mine, theirs = grenades.new(), grenades.new()
	grenades.record(mine, "equipment/equipment_grenade_01", { { x = 1, y = 2, z = 0, delay = 0.15 } }, 10)
	local e = grenades.decode(grenades.encode(mine, 555))
	eq(#grenades.take(theirs, "p", e, 555, 10), 0, "the first text only sets where to start")
	grenades.record(mine, "equipment/equipment_grenade_01", { { x = 3, y = -4, z = 0.5, delay = 0.3 } }, 11)
	e = grenades.decode(grenades.encode(mine, 555))
	local got = grenades.take(theirs, "p", e, 555, 11.2)
	eq(#got, 1)
	eq(got[1].path, "equipment/equipment_grenade_01")
	eq(got[1].spots[1].y, -4)
	near(got[1].spots[1].delay, 0.3)
	eq(#grenades.take(theirs, "p", e, 555, 11.3), 0, "once")
	eq(#grenades.take(theirs, "p", e, 556, 11.3), 0, "another mission")
	local h = grenades.harmless({ center_power = 300, blast_power = 100, force = 10, hit_status_effects = { "x" }, blast_radius = 6 })
	eq(h.center_power, 0)
	eq(h.blast_power, 0)
	eq(h.force, 0)
	eq(h.hit_status_effects, nil)
	eq(h.blast_radius, 6, "the same size, for the same look")
	eq(grenades.encode(grenades.new(), 555), nil)
end)

test("deep_pockets_makes_a_grenade_each_interval_up_to_the_most", function()
	local grenades, api = fake()
	local me, b = {}, {}
	api.inventory[me] = { num_grenades = 2 }
	eq(grenades.most(1), 3)
	eq(grenades.most(20), 15, "4 bits")
	near(grenades.pockets(b, 1, me, 8), 0.5, "half way to the next")
	eq(grenades.pockets(b, 1, me, 8), nil, "a third grenade, and full")
	eq(api.inventory[me].num_grenades, 3)
	eq(api.written[1].key, "num_grenades")
	eq(grenades.pockets(b, 1, me, 30), nil, "nothing past the most")
	eq(#api.written, 1)
	api.inventory[me].num_grenades = 0
	near(grenades.pockets(b, 4, me, 5), 0.5, "10 s at four stacks")
	eq(grenades.pockets(b, 0, me, 5), nil, "without the upgrade")
end)

test("weight_training_lifts_the_factor_to_jog_speed", function()
	local had = obsidian.import
	obsidian.import = had or function() return {} end
	local perks = dofile("src/perks.lua")
	obsidian.import = had
	near(perks.aim_factor(0, 1.5, 4), 4 / 1.5, "a support weapon that held the player still")
	near(perks.aim_factor(2, 1.5, 4), 4 / 1.5, "an SMG, slower than a jog")
	eq(perks.aim_factor(0, 4, 4), 1, "a state already at jog speed")
	eq(perks.aim_factor(3, 1.5, 4), 3, "a weapon faster than that keeps its own")
	eq(perks.aim_factor(0.5, 0, 4), 0.5)
end)

test("democracy_protects_resists_a_downing_hit_as_well_as_a_fatal_one", function()
	eq(upgrades.by_id.democracy_protects.text(1), "50% chance of resisting fatal or downing damage.")
	eq(upgrades.by_id.ironclad_democracy, nil, "removed")
	local had = obsidian.import
	obsidian.import = had or function() return {} end
	local fight = dofile("src/fight.lua")
	obsidian.import = had
	local asked = 0
	local function yes() asked = asked + 1 return true end
	local function no() asked = asked + 1 return false end
	local held, plain = { democracy = 0.5 }, { democracy = 0 }
	local d, k = fight.resist_downing(held, 40, -100, 60, false, yes)
	eq(d, 39, "resisted: 1 health left, standing")
	eq(k, false)
	d, k = fight.resist_downing(held, 40, -100, 60, false, no)
	eq(d, 60, "not resisted: downed as usual")
	eq(k, false)
	eq(asked, 2)
	asked = 0
	eq(fight.resist_downing(held, 40, -100, 30, false, yes), 30, "a hit that leaves health isn't asked about")
	eq(fight.resist_downing(held, 40, -100, 200, true, yes), 200, "a fatal hit is on_fatal's")
	eq(fight.resist_downing(held, -20, -100, 30, false, yes), 30, "already downed: only a fatal hit is resisted")
	eq(asked, 0)
	eq(fight.resist_downing(plain, 40, -100, 60, false, yes), 60, "without the upgrade")
	-- A new save plays the flash and the sound; the hits the moment after it covers don't.
	local played = 0
	fight.on_spare = function() played = played + 1 end
	local f, me = fight.new(), {}
	eq(fight.spare(f, held, me, 10, function() return 0.1 end), true)
	eq(fight.spare(f, held, me, 10.1, function() return 0.1 end), true)
	eq(played, 1)
	eq(fight.spare(f, held, me, 99, function() return 0.9 end), false, "a failed roll")
	eq(played, 1)
	fight.on_spare = nil
end)

test("the_strip_fills_with_the_build_up_wears_off_with_it_and_runs_out_with_the_effect", function()
	local had = obsidian.import
	obsidian.import = had or function() return {} end
	local fight = dofile("src/fight.lua")
	obsidian.import = had
	local f, enemy = fight.new(), {}
	local stats = { ignite = 0.4, needle = 0 }
	local _, extra = fight.on_hit(f, { ignite = 0, needle = 0 }, enemy, { slot = "primary_weapon", damage = 64 }, 0, 400)
	eq(next(extra.bars), nil, "no build-up upgrades, nothing to show")
	_, extra = fight.on_hit(f, stats, enemy, { slot = "primary_weapon", damage = 64 }, 0, 400)
	near(extra.bars.fire.fraction, 0.4, "64 of 160")
	near(extra.bars.fire.drain, fight.fade_of(400), "running down as it wears off")
	eq(extra.bars.poison, nil, "a kind the player doesn't build")
	local _, set = fight.on_hit(f, stats, enemy, { slot = "primary_weapon", damage = 100 }, 0, 400)
	eq(set.bars.fire.fraction, 1, "set off: full")
	eq(set.bars.fire.drain, 5, "running down with the burn")
	local out, kept = fight.on_hit(f, stats, enemy, { slot = "primary_weapon", damage = 10 }, 4.5, 400)
	eq(out and out[1], "regular_burn")
	eq(kept.bars.fire.fraction, 1, "kept going: full again")
	local _, mid = fight.on_hit(f, stats, enemy, { slot = "primary_weapon", damage = 10 }, 6, 400)
	eq(mid.bars.fire, nil, "while it runs, the strip is left to run down")
end)

-- The effects each grenade unit's on_explode flow plays, all in resource_packages/mission_common: no
-- other particle effect may ever be played (one that isn't loaded takes the game down).
local LOADED = {
	["effects/wep_handgrenade_explosion"] = true, ["effects/wep_handgrenade_explosion_fire"] = true,
	["effects/wep_handgrenade_explosion_stun"] = true, ["effects/generated/wep_handgrenade_smoke"] = true,
	["effects/wep_impactgrenade_explosion"] = true, ["effects/generated/artillery_blast"] = true,
	["effects/wep_grenadelauncher_incindiary"] = true, ["effects/surface_effects/artillery_default"] = true,
}

-- World, TimpaniWorld and Vector3 that record what's played; gives back a function that puts them back.
local function recording()
	local had = { rawget(_G, "World"), rawget(_G, "TimpaniWorld"), rawget(_G, "Vector3") }
	local rec = { effects = {}, sounds = {} }
	rawset(_G, "World", {
		create_particles = function(world, name, at) rec.effects[#rec.effects + 1] = { world = world, name = name, at = at } end,
		timpani_world = function(world) return { of = world } end,
	})
	rawset(_G, "TimpaniWorld", { trigger_event = function(tw, name, at) rec.sounds[#rec.sounds + 1] = { name = name, at = at } end })
	rawset(_G, "Vector3", function(x, y, z) return { x = x, y = y, z = z } end)
	return rec, function() rawset(_G, "World", had[1]) rawset(_G, "TimpaniWorld", had[2]) rawset(_G, "Vector3", had[3]) end
end

test("every_grenade_looks_like_its_own_flow_with_loaded_effects_only", function()
	local grenades = fake()
	for path, look in pairs(grenades.LOOKS) do
		eq(grenades.is_grenade(path), true, path)
		eq(LOADED[look.effect], true, path .. "'s effect is one its flow plays, in mission_common")
		eq(type(look.audio), "string", path)
	end
	eq(grenades.look_of("equipment/equipment_grenade_incendiary").effect, "effects/wep_handgrenade_explosion_fire")
	eq(grenades.look_of("equipment/equipment_grenade_stun").effect, "effects/wep_handgrenade_explosion_stun")
	eq(grenades.look_of("equipment/equipment_grenade_01").audio, "wep_handgrenade")
	eq(grenades.look_of("effects/not_loaded").effect, "effects/wep_handgrenade_explosion", "anything else: the game's own grenade")
	eq(grenades.look_of(nil).effect, "effects/wep_handgrenade_explosion")
end)

test("a_look_plays_what_the_explosion_manager_did_not", function()
	local grenades = fake()
	local rec, restore = recording()
	local ok, err = pcall(function()
		local world = {}
		grenades.play_look(world, "equipment/equipment_grenade_stun", { x = 1, y = 2, z = 3 }, { blast_radius = 6 })
		eq(#rec.effects, 1)
		eq(rec.effects[1].name, "effects/wep_handgrenade_explosion_stun")
		eq(rec.effects[1].world, world)
		eq(rec.effects[1].at.y, 2)
		eq(#rec.sounds, 1)
		eq(rec.sounds[1].name, "wep_handgrenade")
		-- An impact grenade whose explosive_info has an effect: the manager played it already.
		grenades.play_look(world, "equipment/equipment_impact_grenade_02", { x = 0, y = 0 }, { effect = "effects/wep_impactgrenade_explosion" })
		eq(#rec.effects, 1, "no second fireball")
		eq(#rec.sounds, 2, "but the sound")
		grenades.play_look(nil, "equipment/equipment_grenade_01", { x = 0, y = 0 })
		eq(#rec.effects, 1, "no world, nothing")
	end)
	restore()
	if not ok then error(err, 0) end
end)

test("cluster_blasts_and_another_machines_copies_play_the_grenade_look", function()
	local grenades, api = fake()
	local rec, restore = recording()
	local had_lsm = rawget(_G, "LuaSettingsManager")
	local ok, err = pcall(function()
		local world, in_mission = {}, true
		api.game.in_mission = function() return in_mission end
		api.game.state = function() return { world_proxy = { get_world = function() return world end } } end
		api.game.box = function(v) return v end
		local side, blasts = grenades.new(), {}
		side.manager = {}
		side.original = function(manager, unit, pos, info) blasts[#blasts + 1] = info end
		local info = { center_power = 600, blast_power = 250, blast_radius = 3.5 }
		side.queue = {
			{ x = 1, y = 1, z = 0, delay = 0.1, info = info, path = "equipment/equipment_grenade_incendiary" },
			{ x = 2, y = 2, z = 0, delay = 0.2, info = grenades.smaller(info, 0.5), path = "equipment/equipment_grenade_incendiary", small = true },
		}
		grenades.update(side, 0.25)
		eq(#blasts, 2, "both blasts went off")
		eq(#rec.effects, 2, "each with the grenade's fireball")
		eq(rec.effects[1].name, "effects/wep_handgrenade_explosion_fire")
		eq(rec.effects[2].name, "effects/wep_handgrenade_explosion_fire", "a Carpet Bombing ring too")
		eq(#rec.sounds, 2)
		-- Another machine's stun cluster, drawn here without power.
		rawset(_G, "LuaSettingsManager", {
			get_settings_by_settings_path = function(_, path) return { explosive_info = { blast_radius = 6, center_power = 0 } } end,
		})
		eq(grenades.show_remote(side, { path = "equipment/equipment_grenade_stun", spots = { { x = 5, y = 5, z = 0, delay = 0.1 } } }), true)
		grenades.update(side, 0.2)
		eq(#blasts, 3)
		eq(blasts[3].center_power, 0, "harmless")
		eq(rec.effects[3].name, "effects/wep_handgrenade_explosion_stun", "the same look as on the thrower's machine")
		-- Lobby text naming something that isn't a known grenade still plays only a loaded effect.
		eq(grenades.show_remote(side, { path = "equipment/equipment_grenade_madeup", spots = { { x = 0, y = 0, z = 0, delay = 0 } } }), true)
		grenades.update(side, 0.1)
		eq(rec.effects[4].name, "effects/wep_handgrenade_explosion")
		-- Out of a mission, a blast plays no look.
		in_mission = false
		side.queue = { { x = 0, y = 0, z = 0, delay = 0, info = info, path = "equipment/equipment_grenade_01" } }
		grenades.update(side, 0.1)
		eq(#rec.effects, 4)
	end)
	rawset(_G, "LuaSettingsManager", had_lsm)
	restore()
	if not ok then error(err, 0) end
end)

test("a_gone_unit_is_never_asked_for_its_data", function()
	-- Unit.get_data on a destroyed unit takes the game down past any pcall: the precision strike's shells
	-- are gone by the time their explosion names them.
	local grenades = fake()
	local had = rawget(_G, "Unit")
	local asked = 0
	rawset(_G, "Unit", { alive = function(u) return u.alive end, get_data = function(u, key) asked = asked + 1 return u[key] end })
	eq(grenades.path_of({ alive = false, settings_path = "equipment/equipment_grenade_01" }), nil, "a destroyed unit")
	eq(asked, 0, "and get_data never runs on it")
	eq(grenades.path_of({ alive = true, settings_path = "equipment/equipment_grenade_01" }), "equipment/equipment_grenade_01")
	eq(grenades.path_of(nil), nil)
	rawset(_G, "Unit", had)
end)

return T
