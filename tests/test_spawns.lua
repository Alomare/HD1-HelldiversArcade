-- Where the director's enemies come in (src/spots.lua) and what it picks per faction (src/director.lua):
-- the Obelisk's limit and the Illusionist's place in a run.
local spots = obsidian.module("src/spots")
local director = obsidian.module("src/director")
local rules = obsidian.module("src/rules")
local rng = obsidian.module("src/rng")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

-- A map of 6 by 6 tiles of 24 metres, the outer ring of them edge tiles, as GeneratedLevel has them.
local TILE, SIZE = 24, 6
local function tile_on_level(x, y)
	local tx, ty = math.floor(x / TILE), math.floor(y / TILE)
	return tx >= 1 and ty >= 1 and tx <= SIZE - 2 and ty <= SIZE - 2
end
-- Metres from (x, y) to the nearest edge tile or the outside.
local function to_border(x, y)
	return math.min(x - TILE, y - TILE, (SIZE - 1) * TILE - x, (SIZE - 1) * TILE - y)
end

test("a_spot_keeps_a_margin_from_the_border_tiles", function()
	eq(spots.clear(60, 60, tile_on_level), true, "the middle of the map")
	eq(spots.clear(TILE + 1, 60, tile_on_level), false, "a metre inside the level, beside an edge tile")
	eq(spots.clear(TILE + spots.MARGIN + 0.5, 60, tile_on_level), true, "just past the margin")
	eq(spots.clear(10, 60, tile_on_level), false, "in an edge tile")
end)

test("a_spot_stands_on_ground_the_spawn_manager_takes", function()
	local function flat() return 0 end
	eq(spots.clear(60, 60, tile_on_level, flat), true)
	eq(spots.clear(60, 60, tile_on_level, function() return 3 end), false, "on top of a rock or a wall")
	eq(spots.clear(60, 60, tile_on_level, function() return false end), false, "no ground under it")
	eq(spots.clear(60, 60, tile_on_level, function() return nil end), true, "unknown: the tiles decide")
	-- A rock on one side of the ring still leaves room for a group; on two sides it doesn't.
	local function rock_east(x) return x > 62 and 3 or 0 end
	eq(spots.clear(60, 60, tile_on_level, rock_east), true, "one ring point of four on a rock")
	local function rock_east_north(x, y) return (x > 62 or y > 62) and 3 or 0 end
	eq(spots.clear(60, 60, tile_on_level, rock_east_north), false, "two of four")
end)

test("spawns_around_a_squad_at_the_border_stay_inside", function()
	local checks = { on_level = tile_on_level }
	-- The squad stands 3 metres from the border, so most of the ring lies outside.
	local squad = { x = TILE + 3, y = 70, z = 0 }
	local got = 0
	for seed = 1, 200 do
		local at = spots.around(squad, rules.SPAWN_RING[1], rules.SPAWN_RING[2], rng.new(seed), checks)
		if at then
			got = got + 1
			eq(to_border(at.x, at.y) >= spots.MARGIN - 1e-9, true, string.format("seed %d: %.1f, %.1f", seed, at.x, at.y))
			local d = math.sqrt((at.x - squad.x) ^ 2 + (at.y - squad.y) ^ 2)
			eq(d >= rules.SPAWN_RING[1] - 1e-9 and d <= rules.SPAWN_RING[2] + 1e-9, true, "in the ring: " .. d)
		end
	end
	eq(got > 150, true, "most seeds find a spot: " .. got)
end)

test("with_no_clear_spot_the_nearest_point_well_inside_is_taken_or_nothing", function()
	-- A level of one tile in a ring of edge tiles: nothing 28 to 38 metres out is on it.
	local function one_tile(x, y) return math.floor(x / TILE) == 2 and math.floor(y / TILE) == 2 end
	local squad = { x = 60, y = 60, z = 0 }
	local pulled = 0
	local checks = {
		on_level = one_tile,
		pull_in = function() pulled = pulled + 1 return { x = 60, y = 60 } end,
	}
	eq(spots.around(squad, 28, 38, rng.new(1), checks), nil, "the tile's centre is on the squad: no spawn there")
	eq(pulled, 1)
	checks.pull_in = nil
	eq(spots.around(squad, 28, 38, rng.new(1), checks), nil)
	-- A far one is taken: a level of the one tile from 72 to 96 metres, 50 metres from the squad.
	local function far_tile(x, y) return math.floor(x / TILE) == 3 and math.floor(y / TILE) == 3 end
	local far = { on_level = far_tile, pull_in = function() return { x = 84, y = 84 } end }
	local at = spots.around({ x = 84, y = 34, z = 0 }, 10, 20, rng.new(3), far)
	eq(at ~= nil and at.x == 84 and at.y == 84, true, "pulled in")
end)

test("the_level_checks_ask_the_game_the_way_its_spawn_manager_does", function()
	local old = rawget(_G, "Vector3")
	rawset(_G, "Vector3", function(x, y, z) return { x = x, y = y, z = z } end)
	local cast
	local map = {
		is_position_on_level = function(_, v) return tile_on_level(v.x, v.y) end,
		get_closest_position_on_level = function() return { x = 1, y = 2, z = 0 } end,
	}
	local function raycast(from, to, filter)
		cast = { from = from, to = to, filter = filter }
		if from.x < 50 then return false end
		if from.x < 70 then return true, { x = from.x, y = from.y, z = 0.3 }, 99.7 end
		return false, "bad_type"
	end
	local checks = spots.of_level(map, raycast)
	rawset(_G, "Vector3", old)
	eq(checks.on_level(60, 60), true)
	eq(checks.on_level(10, 60), false)
	eq(checks.ground(60, 60), 0.3)
	eq(cast.filter, "spawn_check")
	eq(cast.from.z > 50 and cast.to.z < 0, true, "a ray from high up, down")
	eq(checks.ground(40, 60), false, "nothing hit")
	eq(checks.ground(80, 60), nil, "the ray couldn't be cast")
	eq(checks.pull_in(5, 5).y, 2)
	eq(spots.of_level(nil, raycast), nil, "off a mission")
end)

-- A run of the director with enemies that live `life` seconds per tier: what came, by key and minute.
local function run_of(home, difficulty, seed, minutes, life)
	local d = director.new(home, rng.new(seed), difficulty)
	local alive, came, most = {}, {}, {}
	local function alive_of(key)
		local n = 0
		for _, a in ipairs(alive) do if a.key == key then n = n + 1 end end
		return n
	end
	for tick = 1, minutes * 60 * 10 do
		local t = tick / 10
		for i = #alive, 1, -1 do if alive[i].die <= t then table.remove(alive, i) end end
		for _, s in ipairs(director.update(d, 0.1, 1, #alive, alive_of).spawns) do
			came[#came + 1] = { key = s.key, count = s.count, minute = t / 60 }
			for _ = 1, s.count do alive[#alive + 1] = { key = s.key, die = t + life * s.tier } end
		end
		for key, limit in pairs(director.LIMIT) do
			local n = alive_of(key)
			most[key] = math.max(most[key] or 0, n)
			eq(n <= limit, true, string.format("%s: %d %s alive at %.1f", home, n, key, t))
		end
	end
	return came, most
end

test("obelisks_come_alone_and_at_most_two_alive", function()
	eq((director.tier_of("illuminate_obelisk")), 3, "a tier 3 unit")
	eq(director.LIMIT.illuminate_obelisk, 2)
	local obelisks, illuminates = 0, 0
	for seed = 1, 8 do
		-- Long-lived enemies: the squad doesn't kill them, as with Obelisks behind their shield.
		local came = run_of("illuminates", 8, seed, 14, 120)
		for _, c in ipairs(came) do
			if c.key == "illuminate_obelisk" then
				eq(c.count, 1, "an Obelisk comes alone")
				obelisks = obelisks + 1
			end
			if c.key:find("illuminate", 1, true) then illuminates = illuminates + c.count end
		end
	end
	eq(obelisks > 0, true, "Obelisks still come")
	eq(obelisks * 10 < illuminates, true, obelisks .. " Obelisks of " .. illuminates .. " Illuminates")
end)

test("one_spawn_never_asks_for_more_obelisks_than_the_limit", function()
	local d = director.new("illuminates", rng.new(1))
	for seed = 1, 50 do
		d = director.new("illuminates", rng.new(seed))
		d.time, d.next_spawn = 11 * 60, 0
		d.rest_left, d.wave_left, d.bosses_done = nil, rules.WAVE_SECONDS, 1
		local n = 0
		for _, s in ipairs(director.update(d, 0.01, 4, 0).spawns) do
			if s.key == "illuminate_obelisk" then n = n + s.count end
		end
		eq(n <= director.LIMIT.illuminate_obelisk, true, "seed " .. seed .. ": " .. n)
	end
	eq(director.left_of("illuminate_obelisk", function() return 1 end, {}), 1)
	eq(director.left_of("illuminate_obelisk", function() return 1 end, { illuminate_obelisk = 1 }), 0)
	eq(director.left_of("illuminate_tripod", function() return 99 end, {}), math.huge, "no limit")
end)

test("illusionists_come_in_a_solo_run_at_difficulty_five", function()
	local seeds_with = 0
	for seed = 1, 10 do
		local came = run_of("illuminates", 5, seed, 12, 30)
		local n = 0
		for _, c in ipairs(came) do
			if c.key == "illuminate_illusionist" then
				n = n + c.count
				eq(c.minute >= director.HEAT_FROM[director.from("illuminate_illusionist", 4)], true, "not before Heat 3")
			end
		end
		if n > 0 then seeds_with = seeds_with + 1 end
	end
	eq(seeds_with >= 8, true, "runs with an Illusionist before 12:00: " .. seeds_with .. " of 10")
end)

test("every_faction_brings_its_tier_four_in_a_solo_run_at_difficulty_five", function()
	for _, home in ipairs(director.FACTIONS) do
		local n = 0
		for seed = 1, 10 do
			for _, c in ipairs(run_of(home, 5, seed, 12, 30)) do
				local tier, faction = director.tier_of(c.key)
				if tier == 4 and faction == home then n = n + c.count end
			end
		end
		-- Up to 2.6.0 a solo run at difficulty 5 had the budget for one only from minute 12: none in ten
		-- runs, for every faction.
		eq(n >= 5, true, home .. ": tier 4 enemies in ten runs: " .. n)
	end
end)

test("a_saved_up_tier_is_bought_once_the_budget_pays", function()
	local d = director.new("bugs", rng.new(7), 1)
	-- Heat 4 for a solo run at difficulty 1: a spawn's budget is far under a tier 4 enemy's cost.
	d.time, d.next_spawn, d.bosses_done = 9.5 * 60, 0, 1
	d.saving = { faction = "bugs", tier = 4 }
	d.bank = 0
	local out = director.update(d, 0.01, 1, 0)
	eq(#out.spawns, 0, "the spawn keeps the budget")
	eq(d.bank > 0 and d.bank <= rules.ORB_XP[4], true, "saved: " .. d.bank)
	local bought
	for _ = 1, 10 do
		d.next_spawn = 0
		for _, s in ipairs(director.update(d, 0.01, 1, 0).spawns) do
			if s.tier == 4 then bought = true end
		end
		if bought then break end
	end
	eq(bought, true, "the tier 4 enemy came")
	eq(d.saving, nil)
end)

return T
