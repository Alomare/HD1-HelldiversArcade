-- Kinetic Battery (src/battery.lua) against a fake Obsidian API that records what reaches the game.
local upgrades = obsidian.module("src/upgrades")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function fake()
	local api = { arcs = {}, hits = {}, attached = {}, detached = {}, handle = 0, enemies_near = {}, health = {} }
	api.game = { master = function(unit, name) return name == "health" and api.health[unit] or nil end }
	api.enemies = {
		chain = function(pos, count, first, jump)
			api.asked = { count = count, first = first, jump = jump }
			local out = {}
			for i = 1, math.min(count, #api.enemies_near) do out[i] = api.enemies_near[i] end
			return out
		end,
		damage = function(unit, power) api.hits[#api.hits + 1] = { unit = unit, power = power } return true end,
	}
	api.world = {
		arc = function(path) api.arcs[#api.arcs + 1] = path return true end,
		placement = function(unit) return { x = unit.x, y = unit.y, z = 0 } end,
		attach_effect = function(unit, effect)
			api.handle = api.handle + 1
			api.attached[api.handle] = { unit = unit, effect = effect }
			return api.handle
		end,
		detach_effect = function(h) api.detached[#api.detached + 1] = h return true end,
	}
	local had = obsidian.import
	obsidian.import = function() return api end
	local battery = dofile("src/battery.lua")
	obsidian.import = had
	return battery, api
end

-- Walks a body `metres` along x in steps of a metre, syncing each step.
local function walk(battery, b, stacks, unit, from, metres, side)
	local x = from
	battery.sync(b, stacks, unit, { x = x, y = 0, z = 0 }, side, 0)
	for _ = 1, metres do
		x = x + 1
		battery.sync(b, stacks, unit, { x = x, y = 0, z = 0 }, side, 0)
	end
	return x
end

test("the_card_numbers_follow_the_stacks", function()
	local body = "Discharge arc attacks towards 2 nearby enemies for every 14 m you move."
	eq(upgrades.by_id.kinetic_battery.text(1), body .. "\nTotal: 2 enemies every 14 m")
	eq(upgrades.by_id.kinetic_battery.text(3), body .. "\nTotal: 4 enemies every 10 m")
	eq(upgrades.by_id.kinetic_battery.text(5), body .. "\nTotal: 6 enemies every 7.8 m")
	near(upgrades.battery_metres(1) / 7, 2, "2 s at a full sprint at one stack")
end)

test("a_full_charge_arcs_through_the_chain_and_hurts_only_what_it_picked", function()
	local battery, api = fake()
	local me, side, b = {}, battery.new(), battery.new_player()
	api.enemies_near = { { x = 20, y = 0 }, { x = 24, y = 0 }, { x = 28, y = 0 } }
	walk(battery, b, 1, me, 0, 13, side)
	eq(#api.arcs, 0, "13 m: not full yet")
	walk(battery, b, 1, me, 13, 1, side)
	eq(#api.arcs, 1, "full at 14 m")
	eq(api.asked.count, 2)
	eq(api.asked.first, 12)
	eq(api.asked.jump, 6)
	eq(#api.hits, 2)
	eq(api.hits[1].power, 150)
	eq(#api.arcs[1], 3, "from the player through both enemies")
	eq(api.arcs[1][1].z, 1, "at body height")
	eq(b.charge, 0, "emptied")
	eq(side.seq, 1, "kept for the other machines")
end)

test("a_full_charge_waits_for_an_enemy", function()
	local battery, api = fake()
	local me, side, b = {}, battery.new(), battery.new_player()
	walk(battery, b, 1, me, 0, 30, side)
	eq(#api.arcs, 0)
	eq(b.charge, 1, "held full")
	api.enemies_near = { { x = 35, y = 0 } }
	battery.sync(b, 1, me, { x = 30, y = 0, z = 0 }, side, 0)
	eq(#api.arcs, 1, "goes off once one is near")
end)

test("the_crackle_shows_from_three_quarters_and_goes_with_the_discharge", function()
	local battery, api = fake()
	local me, side, b = {}, battery.new(), battery.new_player()
	walk(battery, b, 1, me, 0, 10, side)
	eq(b.glow, nil, "10 of 14 m")
	walk(battery, b, 1, me, 10, 1, side)
	eq(api.attached[b.glow].effect, "shock", "past three quarters at 11 m")
	eq(api.attached[b.glow].unit, me)
	api.enemies_near = { { x = 14, y = 0 } }
	walk(battery, b, 1, me, 11, 3, side)
	eq(b.glow, nil, "off after the discharge")
	eq(#api.detached, 1)
end)

test("crawling_charges_and_fires_while_downed_and_a_death_empties_it", function()
	local battery, api = fake()
	local me, side, b = {}, battery.new(), battery.new_player()
	api.enemies_near = { { x = 20, y = 0 } }
	api.health[me] = { is_downed = true }
	walk(battery, b, 1, me, 0, 14, side)
	eq(#api.arcs, 1, "crawling 14 m fires, downed")
	eq(b.charge, 0)
	api.health[me] = { is_downed = false }
	api.enemies_near = {}
	walk(battery, b, 1, me, 20, 10, side)
	near(b.charge, 10 / 14)
	battery.died(b)
	eq(b.charge, 0)
	-- A respawn far away isn't a walk.
	battery.sync(b, 1, me, { x = 0, y = 0, z = 0 }, side, 0)
	battery.sync(b, 1, me, { x = 200, y = 0, z = 0 }, side, 0)
	eq(b.charge, 0)
end)

test("more_stacks_charge_faster_and_chain_further", function()
	local battery, api = fake()
	local me, side, b = {}, battery.new(), battery.new_player()
	api.enemies_near = { {}, {}, {}, {}, {}, {}, {} }
	for _, e in ipairs(api.enemies_near) do e.x, e.y = 5, 0 end
	walk(battery, b, 5, me, 0, 8, side)
	eq(#api.arcs, 1, "full within 8 m at five stacks")
	eq(api.asked.count, 6)
end)

test("other_machines_draw_new_fresh_discharges_once", function()
	local battery = fake()
	local mine = battery.new()
	battery.record(mine, { { x = 0, y = 0, z = 1 }, { x = 5, y = 0, z = 1 } }, 10)
	local text = battery.encode(mine, 777, { { x = 1, y = 2, z = 0 } })
	local e = battery.decode(text)
	eq(e.mission, "777")
	eq(e.glowing[1].y, 2)
	local theirs = battery.new()
	eq(#battery.take(theirs, "peer", e, 777, 10), 0, "the first text only sets where to start")
	battery.record(mine, { { x = 0, y = 0, z = 1 }, { x = 7.26, y = -3, z = 1 } }, 11)
	e = battery.decode(battery.encode(mine, 777, {}))
	local paths = battery.take(theirs, "peer", e, 777, 11.2)
	eq(#paths, 1, "only the new one")
	near(paths[1][2].x, 7.3)
	eq(paths[1][2].y, -3)
	eq(#battery.take(theirs, "peer", e, 777, 11.5), 0, "drawn once")
	battery.record(mine, { { x = 0, y = 0, z = 1 }, { x = 1, y = 0, z = 1 } }, 12)
	e = battery.decode(battery.encode(mine, 777, {}))
	eq(#battery.take(theirs, "peer", e, 777, 20), 0, "too old to draw")
	eq(#battery.take(theirs, "peer", e, 778, 12), 0, "another mission")
	eq(battery.encode(battery.new(), 777, {}), nil, "nothing to share")
end)

test("a_shared_crackle_goes_on_the_nearest_player_of_that_spot", function()
	local battery, api = fake()
	local a, c = { name = "a" }, { name = "c" }
	local want = battery.match_glows({ { x = 0, y = 0 } }, { { unit = a, pos = { x = 1, y = 0 } }, { unit = c, pos = { x = 2.5, y = 0 } } })
	eq(want[a], true)
	eq(want[c], nil)
	eq(next(battery.match_glows({ { x = 50, y = 0 } }, { { unit = a, pos = { x = 0, y = 0 } } })), nil, "too far from anyone")
	local side = battery.new()
	battery.show_remote_glows(side, want)
	eq(api.attached[side.remote_glows[a]].unit, a)
	battery.show_remote_glows(side, {})
	eq(next(side.remote_glows), nil)
	eq(#api.detached, 1)
end)

return T
