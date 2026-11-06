-- Elites (src/elites.lua) and chests (src/chests.lua): the schedule, the binding of kinds, the arcs, the
-- drops and the opens through lobby data, against a fake Obsidian API.
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
	for _, k in ipairs(elites.KINDS) do eq(type(elites.LOOK[k].color), "string", k .. " has a color") end
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

test("the_dome_follows_and_comes_back_after_breaking", function()
	local elites = load("elites", fake())
	local el = {}
	eq(elites.dome_step(el, { x = 0, y = 0 }, 0, false), "place")
	el.dome, el.dome_pos, el.dome_at = {}, { x = 0, y = 0 }, 0
	eq(elites.dome_step(el, { x = 1, y = 0 }, 5, true), nil, "still inside")
	eq(elites.dome_step(el, { x = 4, y = 0 }, 1, true), nil, "moved, but too soon")
	eq(elites.dome_step(el, { x = 4, y = 0 }, 5, true), "move")
	eq(elites.dome_step(el, { x = 4, y = 0 }, 6, false), nil, "broken")
	eq(elites.dome_step(el, { x = 4, y = 0 }, 6 + elites.DOME_BACK, false), "place", "back after a while")
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

test("a_chests_rarity_follows_where_it_came_from", function()
	local chests = load("chests", fake())
	for i = 0, 99 do eq(chests.roll_rarity("boss", function() return i / 100 end) ~= "common", true, "a boss's is never common") end
	eq(chests.roll_rarity("elite", function() return 0 end), "common")
	eq(chests.roll_rarity("elite", function() return 0.999 end), "legendary")
end)

test("a_chest_opens_once_and_the_ground_has_a_limit", function()
	local chests = load("chests", fake())
	local c = chests.new()
	for i = 1, chests.LIMIT + 2 do chests.add(c, { x = i * 10, y = 0, z = 0 }, "rare", 1) end
	eq(#c.ground, chests.LIMIT, "the oldest went")
	eq(c.ground[1].id, 3)
	eq(chests.within(c.ground, { x = 31, y = 1, z = 0 }).id, 3)
	eq(chests.within(c.ground, { x = 35, y = 0, z = 0 }), nil, "out of reach")
	local ev = chests.open(c, 3)
	eq(ev.seq, 1) eq(ev.rarity, "rare")
	eq(chests.open(c, 3), nil, "once")
	eq(#c.ground, chests.LIMIT - 1)
end)

test("chests_and_opens_fit_in_lobby_data", function()
	local chests = load("chests", fake())
	local c = chests.new()
	for _ = 1, chests.LIMIT do chests.add(c, { x = -1234.5, y = -1234.5, z = -123.4 }, "legendary", 3) end
	local text = chests.encode_ground(1234567890, c.ground)
	eq(#text <= 200, true, "short enough: " .. #text)
	local d = chests.decode_ground(text)
	eq(#d.list, chests.LIMIT)
	eq(d.list[1].rarity, "legendary") eq(d.list[1].count, 3) near(d.list[1].z, -123.4)
	for i = 1, chests.LIMIT do chests.open(c, i) end
	local o = chests.decode_opened(chests.encode_opened(1234567890, c.opened))
	eq(#o.list, chests.OPENED_KEPT)
	local list, seen = chests.take_opened(nil, o)
	eq(#list, 0, "the first look only notes where they are")
	eq(seen, chests.LIMIT)
	local asked = chests.decode_asked(chests.encode_asked(5, { [4] = true, [2] = true }))
	eq(asked.ids[1], 2) eq(asked.ids[2], 4)
	eq(chests.encode_asked(5, {}), nil)
end)

local function run_of(n)
	local list = {}
	for i = 1, n do list[i] = { unit = {}, pos = { x = 0, y = 0, z = 0 } } end
	return { local_list = list, sync = { mission = 77 }, exiting = true }
end

test("an_open_anywhere_gives_every_player_their_own_upgrades", function()
	-- The client: a player asks, the host opens, the client's own players get theirs.
	local api = fake(false)
	local chests = load("chests", api)
	local run = run_of(2)
	local got = {}
	local grant = function(n, rarity, count)
		got[#got + 1] = n .. ":" .. rarity .. ":" .. count
		return { { id = "x", rarity = rarity, name = "X" } }
	end
	api.peers.host = { chests = "77;5@r@1@0.0,0.0,0.0", chest_opened = "77;3@4@c@1" }
	chests.update(run, 1, grant)
	eq(#got, 0, "the opens before only note where they are")
	eq(#chests.ground(), 1)
	eq(chests.press(run, { x = 1, y = 0, z = 0 }), true, "a press beside it")
	chests.update(run, 1, grant)
	eq(api.mine.chest_open, "77;5", "asked for")
	api.peers.host = { chests = "77;", chest_opened = "77;3@4@c@1|4@5@r@1" }
	chests.update(run, 1, grant)
	eq(table.concat(got, ","), "1:rare:1,2:rare:1", "every player of this machine")
	eq(#chests.state.panels, 2)
	eq(api.mine.chest_open, nil, "the ask goes once the chest is gone")
	chests.update(run, 1, grant)
	eq(#got, 2, "once")

	-- The host: the ask opens it, and the host's own players get theirs.
	local hapi = fake(true)
	local hchests = load("chests", hapi)
	local hrun = run_of(1)
	local hgot = 0
	local chest = hchests.drop({ x = 0, y = 0, z = 0 }, "boss", function() return 0.9 end)
	eq(chest.count, 3) eq(chest.rarity, "legendary")
	hapi.peers.friend = { chest_open = "77;" .. chest.id }
	hchests.update(hrun, 1, function(_, _, count) hgot = hgot + count return {} end)
	eq(hgot, 3)
	eq(#hchests.state.ground, 0)
	eq(hapi.mine.chest_opened, "77;1@1@l@3")
	eq(hchests.press(hrun, { x = 0, y = 0, z = 0 }), false, "nothing left to open")
end)

test("the_host_drops_a_chest_for_an_elite_a_boss_and_rarely_any_kill", function()
	local api = fake(true)
	local chests = load("chests", api)
	chests.on_kill({ x = 0, y = 0 }, false, true, function() return 0.5 end)
	chests.on_kill({ x = 0, y = 0 }, true, false, function() return 0.5 end)
	chests.on_kill({ x = 0, y = 0 }, false, false, function() return 0.5 end)
	eq(#chests.state.ground, 2, "the elite's and the boss's")
	eq(chests.state.ground[1].count, 1) eq(chests.state.ground[2].count, 3)
	chests.on_kill({ x = 0, y = 0 }, false, false, function() return 0.001 end)
	eq(#chests.state.ground, 3, "one in 500 kills")
	api.host = false
	chests.on_kill({ x = 0, y = 0 }, true, false, function() return 0.5 end)
	eq(#chests.state.ground, 3, "only the host drops")
end)

return T
