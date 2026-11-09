-- A dropped weapon goes after a minute, on the machine that owns it (src/drops.lua).
local drops = obsidian.module("src/drops")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function ground()
	local g = { list = {}, removed = {} }
	g.world = {
		pickups = function(_, _, kinds)
			eq(kinds[1], "weapon_pickup")
			return g.list
		end,
		remove_pickup = function(unit) g.removed[#g.removed + 1] = unit return true end,
	}
	return g
end

test("a_dropped_weapon_goes_after_a_minute_on_the_machine_that_owns_it", function()
	local g = ground()
	local d = drops.new()
	local mine, other = {}, {}
	g.list = { { unit = mine, owned = true, opening = false }, { unit = other, owned = false, opening = false } }
	drops.update(d, 0.5, g.world)
	drops.update(d, 58, g.world)
	eq(#g.removed, 0, "not before the minute")
	drops.update(d, 2, g.world)
	eq(#g.removed, 1)
	eq(g.removed[1], mine, "the other machine's weapon is for that machine")
end)

test("a_weapon_in_a_stratagem_crate_is_left_alone", function()
	local g = ground()
	local d = drops.new()
	local crate = {}
	g.list = { { unit = crate, owned = true, opening = true } }
	drops.update(d, 0.5, g.world)
	-- Out of the crate, still not a dropped weapon.
	g.list = { { unit = crate, owned = true, opening = false } }
	drops.update(d, 61, g.world)
	eq(#g.removed, 0)
end)

test("a_picked_up_weapon_forgets_the_clock_so_a_new_drop_starts_again", function()
	local g = ground()
	local d = drops.new()
	local gun = {}
	g.list = { { unit = gun, owned = true, opening = false } }
	drops.update(d, 30, g.world)
	g.list = {}
	drops.update(d, 1, g.world)
	eq(d.seen[gun], nil, "gone from the ground")
	g.list = { { unit = gun, owned = true, opening = false } }
	drops.update(d, 1, g.world)
	drops.update(d, 30, g.world)
	eq(#g.removed, 0, "a fresh minute")
end)

test("an_api_without_pickups_does_nothing", function()
	drops.update(drops.new(), 100, {})
	drops.update(drops.new(), 100, nil)
end)

return T
