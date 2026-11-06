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
