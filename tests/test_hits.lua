-- src/hits.lua and Trailblazer's blasts (src/trail.lua) against a fake engine in which an explosion's hits
-- go out from a physics overlap's answer, on a later step, as in the game (SpawnManager's
-- waiting_for_overlap), or straight from the call.
local hits = obsidian.module("src/hits")

local had_import = obsidian.import
obsidian.import = had_import or function() return {} end
local trail = obsidian.module("src/trail")
obsidian.import = had_import

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

-- EntityAux and PhysicsWorld as far as an explosion goes. Units are tables naming their components.
local function engine()
	local e = { queued = {}, waiting = {}, saved = { EntityAux, PhysicsWorld } }
	EntityAux = {
		queue_command_interface = function(unit, interface, command, data)
			e.queued[#e.queued + 1] = { unit = unit, interface = interface, command = command, data = data }
		end,
		has_component = function(unit, name) return type(unit) == "table" and unit[name] == true end,
	}
	PhysicsWorld = { overlap = function(world, answer, ...) e.waiting[#e.waiting + 1] = answer end }
	e.queue, e.overlap = EntityAux.queue_command_interface, PhysicsWorld.overlap
	-- The physics step: every overlap waiting gets its answer.
	function e.step(units)
		local list = e.waiting
		e.waiting = {}
		for _, answer in ipairs(list) do answer(units) end
	end
	-- ExplosionManager.do_explosion, as far as this goes: the hits from an overlap's answer, and the push
	-- from a second overlap that queues nothing.
	function e.explode()
		PhysicsWorld.overlap({}, function(units)
			for _, u in ipairs(units) do EntityAux.queue_command_interface(u, "damageable", "do_damage", { power = 32 }) end
		end, "position", 0)
		PhysicsWorld.overlap({}, function() end, "position", 0)
		return "gone off"
	end
	function e.restore() EntityAux, PhysicsWorld = e.saved[1], e.saved[2] end
	return e
end

local function with_engine(name, fn)
	test(name, function()
		local e = engine()
		local ok, err = pcall(fn, e)
		e.restore()
		if not ok then error(err, 0) end
	end)
end

local diver, bug = { character = true }, { character = true, enemy = true }

local function spare(unit, interface, command)
	if hits.is_hit(interface, command) and hits.is_helldiver(unit) then return false end
end

with_engine("a_filter_sees_the_hits_an_explosion_sends_a_step_after_the_call", function(e)
	eq(hits.with(spare, e.explode), "gone off", "the call answers as it would")
	eq(#e.queued, 0, "no hit goes out during the call")
	eq(PhysicsWorld.overlap, e.overlap, "the engine's overlap is back once the call returns")
	eq(EntityAux.queue_command_interface, e.queue, "and the game's queue")
	e.step({ diver, bug })
	eq(#e.queued, 1, "the hit on the Helldiver is dropped as it goes out")
	eq(e.queued[1].unit, bug)
	eq(EntityAux.queue_command_interface, e.queue, "the game's queue again after the answer")
	e.explode()
	e.step({ diver, bug })
	eq(#e.queued, 3, "a blast set off outside hits both")
end)

with_engine("filters_nest_the_inner_one_first_and_hits_sent_at_once_count_too", function(e)
	local marked = {}
	local function mark(unit, interface, command) if hits.is_hit(interface, command) then marked[#marked + 1] = unit end end
	hits.with(mark, function()
		hits.with(spare, function()
			e.explode()
			EntityAux.queue_command_interface(diver, "damageable", "do_damage", { power = 5 })
			EntityAux.queue_command_interface(bug, "damageable", "do_damage", { power = 5 })
		end)
	end)
	eq(#marked, 1, "a hit sent from the call itself is filtered there")
	e.step({ diver, bug })
	eq(#marked, 2, "the blast's hit kept is marked, the dropped one isn't")
	eq(marked[1], bug) eq(marked[2], bug)
	eq(#e.queued, 2)
	eq(PhysicsWorld.overlap, e.overlap) eq(EntityAux.queue_command_interface, e.queue)
end)

with_engine("an_error_in_the_call_puts_the_engine_back_and_goes_on_up", function(e)
	local ok, err = pcall(hits.with, spare, function() error("no world", 0) end)
	eq(ok, false) eq(err, "no world")
	eq(PhysicsWorld.overlap, e.overlap) eq(EntityAux.queue_command_interface, e.queue)
	eq(hits.is_helldiver(bug), false, "an enemy with a character isn't a Helldiver")
	eq(hits.is_helldiver({}), false)
end)

with_engine("a_trail_patchs_blasts_spare_the_player_who_left_it_and_burn_everyone_else", function(e)
	local other, patch, flame = { character = true }, {}, {}
	trail.owners[patch] = diver
	local function do_explosion(manager, unit, pos) return e.explode() end
	eq(trail.pulse(do_explosion, {}, patch, "pos"), "gone off")
	e.step({ diver, other, bug })
	eq(#e.queued, 2, "the player who left it walks through")
	eq(e.queued[1].unit, other, "another Helldiver burns")
	eq(e.queued[2].unit, bug)
	e.queued = {}
	trail.pulse(do_explosion, {}, flame, "pos")
	e.step({ diver, bug })
	eq(#e.queued, 2, "any other fire burns the player too")
	trail.owners[patch] = nil
end)

return T
