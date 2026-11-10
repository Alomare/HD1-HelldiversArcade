-- Elites (src/elites.lua): the schedule, the binding of kinds, the arcs and the marks through lobby data,
-- against a fake Obsidian API.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

-- A fake API: lobby data by peer, the host or not, and what was asked of it.
local function fake(host)
	local api = { mine = {}, peers = {}, host = host ~= false, calls = {} }
	api.game = {
		is_host = function() return api.host end,
		state = function() return nil end,
		master = function() return nil end,
		all_avatars = function() return {} end,
	}
	api.lobby = {
		share = function(name, value) api.mine[name] = value return true end,
		shared = function(name)
			local out = {}
			for peer, data in pairs(api.peers) do out[peer] = data[name] end
			return out
		end,
	}
	api.enemies = { list = function() return {} end, spawn = function(key, n) api.calls[#api.calls + 1] = { key, n } return true end }
	api.world = {}
	return api
end

local function load(name, api)
	local had = obsidian.import
	obsidian.import = function() return api end
	obsidian.log = obsidian.log or function() end
	local m = dofile("src/" .. name .. ".lua")
	obsidian.import = had
	return m
end

local function seq(list)
	local i = 0
	return function()
		i = i + 1
		return list[(i - 1) % #list + 1]
	end
end

test("elites_come_from_three_minutes_one_at_a_time_then_two", function()
	local elites = load("elites", fake())
	local e = elites.new()
	local draw = seq({ 0.5 })
	eq(elites.due(e, 170, 0, draw), false, "before 3:00")
	eq(elites.due(e, 180, 0, draw), true, "at 3:00")
	eq(e.next_at, 180 + 75, "the next 60 to 90 seconds later")
	eq(elites.due(e, 200, 0, draw), false, "not yet")
	eq(elites.due(e, 300, 1, draw), false, "one alive is the most before 8:00")
	eq(elites.due(e, 300, 0, draw), true)
	eq(elites.due(e, 8 * 60, 1, draw), true, "two from 8:00")
	eq(elites.due(e, 9 * 60, 2, draw), false, "never three")
	e.last_death = 600
	eq(elites.due(e, 610, 0, draw), false, "a moment after a death")
	eq(elites.due(e, 621, 0, draw), true)
end)

test("an_elite_takes_a_kind_none_of_the_others_has", function()
	local elites = load("elites", fake())
	local taken = {}
	for i = 1, #elites.KINDS - 1 do taken[elites.KINDS[i]] = true end
	eq(elites.pick_kind(taken, seq({ 0.99 })), elites.KINDS[#elites.KINDS])
	eq(elites.pick_kind({}, seq({ 0 })), elites.KINDS[1])
	local atlas = dofile("src/atlas.lua")
	for _, k in ipairs(elites.KINDS) do eq(atlas.images[elites.LOOK[k].icon] ~= nil, true, k .. " has an icon in the atlas") end
end)

test("the_base_units_are_the_assassinate_targets", function()
	local elites = load("elites", fake())
	eq(elites.faction_of("characters/bug_warrior/bug_warrior_commander"), "bugs")
	eq(elites.faction_of("characters/cyborg_hulk_assassinate/cyborg_hulk_assassinate"), "cyborgs")
	eq(elites.faction_of("characters/illuminate_illusionist_assassinate/illuminate_illusionist_assassinate"), "illuminates")
	eq(elites.faction_of("characters/bug_warrior/bug_warrior"), nil)
end)

test("every_machine_binds_the_nearest_unit_to_a_shared_elite", function()
	local elites = load("elites", fake())
	local a, b, c = {}, {}, {}
	local kinds = {}
	local units = { { unit = a, pos = { x = 10, y = 0 } }, { unit = b, pos = { x = 1, y = 1 } }, { unit = c, pos = { x = 50, y = 50 } } }
	elites.match({ { kind = "fire", x = 0, y = 0 }, { kind = "shock", x = 11, y = 0 } }, units, kinds)
	eq(kinds[b], "fire")
	eq(kinds[a], "shock")
	eq(kinds[c], nil, "too far from any")
	elites.match({ { kind = "brood", x = 1, y = 1 } }, units, kinds)
	eq(kinds[b], "fire", "a bound unit keeps its kind")
end)

test("the_shock_reaches_the_nearest_within_range_and_not_itself", function()
	local elites = load("elites", fake())
	local me = {}
	local list = { { unit = me, pos = { x = 0, y = 0, z = 0 } }, { unit = 1, pos = { x = 3, y = 0, z = 0 } }, { unit = 2, pos = { x = 1, y = 0, z = 0 } },
		{ unit = 3, pos = { x = 7, y = 0, z = 0 } }, { unit = 4, pos = { x = 9, y = 0, z = 0 } }, { unit = 5, pos = { x = 2, y = 0, z = 0 } } }
	local out = elites.nearest({ x = 0, y = 0, z = 0 }, list, elites.SHOCK_RANGE, elites.SHOCK_TARGETS, me)
	eq(#out, 3)
	eq(out[1].unit, 2) eq(out[2].unit, 5) eq(out[3].unit, 1)
	eq(#elites.nearest({ x = 0, y = 0, z = 0 }, list, 8, 10, me), 4, "9 m is out of range")
	local path = elites.arc_path({ x = 0, y = 0, z = 0 }, { { x = 1, y = 0, z = 0 }, { x = 2, y = 0, z = 0 } })
	eq(#path, 4, "out to each and back between")
	eq(path[1].z, 1, "at body height")
end)

test("fire_pools_follow_the_walk_and_toxic_ground_lasts", function()
	local elites = load("elites", fake())
	local f = {}
	eq(elites.fire_due(f, { x = 0, y = 0 }, 0), true)
	eq(elites.fire_due(f, { x = 3, y = 0 }, 0.5), false, "too soon")
	eq(elites.fire_due(f, { x = 1, y = 0 }, 2), false, "standing still")
	eq(elites.fire_due(f, { x = 2, y = 0 }, 2), true)
	local pools = { elites.new_pool({ x = 0, y = 0 }, 100) }
	local laid = 0
	for t = 100, 140, 0.5 do laid = laid + #elites.pools_due(pools, t) end
	eq(laid, elites.POOL_SECONDS / elites.POOL_EVERY, "laid again as each runs out, for the whole time")
	eq(#pools, 0)
end)

test("the_dome_is_placed_once_and_comes_back_after_breaking", function()
	local elites = load("elites", fake())
	local el = {}
	eq(elites.dome_step(el, 0, false), "place")
	el.dome = {}
	eq(elites.dome_step(el, 5, true), nil, "rides on the elite, never placed again")
	eq(elites.dome_step(el, 60, true), nil)
	eq(elites.dome_step(el, 61, false), nil, "broken")
	eq(el.dome, nil)
	eq(elites.dome_step(el, 61 + elites.DOME_BACK - 1, false), nil, "not yet")
	eq(elites.dome_step(el, 61 + elites.DOME_BACK, false), "place", "back after a while")
	for _, name in ipairs(elites.DOME_LOOSE) do eq(name ~= "g_shield", true, "the outer shell stays") end
end)

test("the_elites_and_their_arcs_fit_in_lobby_data", function()
	local elites = load("elites", fake())
	local text = elites.encode(1234567890, { { kind = "noxious", x = -1234.5, y = 678.9 }, { kind = "bulwark", x = 12, y = -3 } })
	local d = elites.decode(text)
	eq(d.mission, "1234567890")
	eq(#d.list, 2)
	eq(d.list[1].kind, "noxious") near(d.list[1].x, -1234.5)
	local side = { seq = 0, events = {} }
	local far = { x = -1234.5, y = -1234.5, z = -123.4 }
	for t = 1, 3 do elites.record_arc(side, far, { far, far, far }, t) end
	local arcs = elites.encode_arcs(side, 1234567890)
	eq(#arcs <= 200, true, "short enough: " .. #arcs)
	local back = elites.decode_arcs(arcs)
	eq(#back.events, elites.ARCS_KEPT)
	eq(#back.events[1].to, 3)
	local seen = {}
	eq(#elites.take_arcs(seen, "host", back, 1234567890, 3), 0, "the first look only notes where they are")
	elites.record_arc(side, far, { far }, 4)
	eq(#elites.take_arcs(seen, "host", elites.decode_arcs(elites.encode_arcs(side, 1234567890)), 1234567890, 4), 1)
end)

test("better_hud_marks_an_elite_with_its_kinds_icon_while_it_lives", function()
	local api = fake(false)
	api.world = { attach_effect = function() return 7 end, detach_effect = function() end }
	local elites = load("elites", api)
	local art = obsidian.module("src/art")
	local was_ready, had_import = art.ready, obsidian.import
	local had_unit, had_aux = rawget(_G, "Unit"), rawget(_G, "EntityAux")
	art.ready = true
	local marks, calls = {}, 0
	local hud = { elite_mark = function(unit, icon) calls = calls + 1 marks[unit] = icon end }
	obsidian.import = function(id) return id == "alomare.betterhud" and hud or api end
	Unit = { alive = function(u) return u.alive ~= false end }
	EntityAux = { state = function() return {} end }
	local foe = {}
	elites.state.kinds[foe] = "fire"
	local run = { time = 0, sync = { mission = 1 } }
	elites.update(run, 0.1, 0.1)
	local atlas = dofile("src/atlas.lua")
	eq(marks[foe] and marks[foe].art, atlas.material, "the atlas's image")
	local r = atlas.images.elite_fire
	near(marks[foe].uv[1], r[1] / atlas.w)
	elites.update(run, 0.1, 0.1)
	eq(calls, 1, "marked once")
	foe.alive = false
	elites.update(run, 0.1, 0.1)
	eq(marks[foe], nil, "cleared once it dies")
	local other = {}
	elites.state.kinds[other] = "brood"
	elites.update(run, 0.1, 0.1)
	eq(marks[other] ~= nil, true)
	elites.clear()
	eq(marks[other], nil, "cleared with the run")
	-- Without Better HUD, or an old one, nothing happens.
	hud = {}
	elites.state.kinds[foe] = "shock"
	foe.alive = true
	elites.update(run, 0.1, 0.1)
	art.ready, obsidian.import, Unit, EntityAux = was_ready, had_import, had_unit, had_aux
end)

test("a_noxious_elites_hit_poisons_the_player", function()
	local elites = load("elites", fake())
	local sent
	local had = rawget(_G, "EntityAux")
	EntityAux = { queue_command_interface = function(u, i, c, data) sent = { u = u, i = i, c = c, data = data } end }
	local foe, player = {}, {}
	elites.state.kinds[foe] = "noxious"
	elites.on_player_hit(player, { owner_unit = foe, damage = 20 })
	eq(sent.u, player)
	eq(sent.data.hit_status_effects[1], "poison_slow")
	eq(sent.data.power, 0)
	sent = nil
	elites.state.kinds[foe] = "fire"
	elites.on_player_hit(player, { owner_unit = foe, damage = 20 })
	eq(sent, nil, "only a noxious one")
	EntityAux = had
end)


return T
