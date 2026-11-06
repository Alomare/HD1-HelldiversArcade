local samples = obsidian.module("src/samples")
local orbs = obsidian.module("src/orbs")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

-- api.world with props that record what's done to them.
local function fake_world()
	local w = { made = {} }
	function w.prop(unit, pos, opts)
		local p = { unit = unit, x = pos.x, y = pos.y, size = opts.scale, removed = false }
		function p:move(at) self.x, self.y = at.x, at.y end
		function p:scale(s) self.size = s end
		function p:remove() self.removed = true end
		w.made[#w.made + 1] = p
		return p
	end
	return w
end

test("each_orb_is_its_factions_sample_bigger_with_more_xp", function()
	samples.clear()
	local w, o = fake_world(), orbs.new()
	orbs.drop(o, { x = 0, y = 0 }, 1, "cyborgs")
	orbs.drop(o, { x = 5, y = 0 }, 60, "illuminates")
	orbs.drop(o, { x = 9, y = 0 }, 3)
	eq(samples.sync(w, o.list), true)
	eq(#w.made, 3)
	eq(w.made[1].unit, samples.UNITS.cyborgs)
	eq(w.made[2].unit, samples.UNITS.illuminates)
	eq(w.made[3].unit, samples.UNITS.bugs, "no faction known: the bugs'")
	eq(w.made[1].size < w.made[2].size, true, "a rarer drop is bigger")
end)

test("a_pulled_orb_moves_its_sample_and_a_taken_one_removes_it", function()
	samples.clear()
	local w, o = fake_world(), orbs.new()
	orbs.drop(o, { x = 0, y = 0 }, 1, "bugs")
	local near = 0.5 + (obsidian.module("src/rules").ORB_RADIUS + obsidian.module("src/rules").ORB_MAGNET) / 2
	orbs.drop(o, { x = near, y = 0 }, 1, "bugs")
	samples.sync(w, o.list)
	orbs.update(o, 0.01, { { pos = { x = 0.5, y = 0 }, is_local = true } })
	samples.sync(w, o.list)
	eq(w.made[1].removed, true, "taken")
	eq(w.made[2].removed, false)
	eq(w.made[2].x < near, true, "pulled towards the player")
	samples.sync(w, o.list)
	eq(#w.made, 2, "nothing made twice")
	samples.clear()
	eq(w.made[2].removed, true, "the run's end takes the rest")
end)

test("merged_orbs_grow_their_sample", function()
	samples.clear()
	local w, o = fake_world(), orbs.new()
	orbs.drop(o, { x = 0, y = 0 }, 8, "bugs")
	samples.sync(w, o.list)
	o.list[1].xp = 25
	o.list[1].age = samples.POP
	samples.sync(w, o.list)
	eq(w.made[1].size, samples.size(25))
	samples.clear()
end)

test("a_new_sample_grows_in_and_settles_at_its_size", function()
	samples.clear()
	local w, o = fake_world(), orbs.new()
	orbs.drop(o, { x = 0, y = 0 }, 1, "bugs")
	samples.sync(w, o.list)
	eq(w.made[1].size < 0.2, true, "it starts small")
	o.list[1].age = samples.POP * 0.8
	samples.sync(w, o.list)
	eq(w.made[1].size > 1, true, "it overshoots")
	o.list[1].age = samples.POP
	samples.sync(w, o.list)
	eq(w.made[1].size, 1, "and settles")
	samples.clear()
end)

return T
