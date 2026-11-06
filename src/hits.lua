-- The hits an explosion sends, seen as they go out. ExplosionManager.do_explosion hands
-- PhysicsWorld.overlap a function that queues each hit through EntityAux.queue_command_interface, and the
-- engine answers an overlap on a later physics step, after the explosion's call has returned: the game's
-- own code waits for the answer (SpawnManager's waiting_for_overlap). A filter put in front of the queue
-- only while the call runs sees none of the explosion's hits, so M.with also puts it there while each
-- overlap answer the call handed out runs.
local M = {}

local function g(name) return rawget(_G, name) end

-- f(...) with `filter` in front of EntityAux.queue_command_interface: filter(unit, interface, command,
-- data) answers false to drop the command.
local function filtered(filter, f, ...)
	local aux = g("EntityAux")
	local queue = type(aux) == "table" and aux.queue_command_interface
	if type(queue) ~= "function" then return f(...) end
	aux.queue_command_interface = function(unit, interface, command, ...)
		if filter(unit, interface, command, ...) == false then return end
		return queue(unit, interface, command, ...)
	end
	local r = { pcall(f, ...) }
	aux.queue_command_interface = queue
	if not r[1] then error(r[2], 0) end
	return unpack(r, 2, table.maxn(r))
end

-- fn(...) with `filter` on every command it queues, now or from the overlaps it starts.
function M.with(filter, fn, ...)
	local pw = g("PhysicsWorld")
	local overlap = type(pw) == "table" and pw.overlap
	if type(overlap) == "function" then
		pw.overlap = function(world, answer, ...)
			if type(answer) == "function" then
				local inner = answer
				answer = function(...) return filtered(filter, inner, ...) end
			end
			return overlap(world, answer, ...)
		end
	end
	local r = { pcall(filtered, filter, fn, ...) }
	if type(overlap) == "function" then pw.overlap = overlap end
	if not r[1] then error(r[2], 0) end
	return unpack(r, 2, table.maxn(r))
end

-- Whether a unit is a Helldiver: a character that isn't an enemy, a bot included.
function M.is_helldiver(unit)
	local aux = g("EntityAux")
	local ok, yes = pcall(aux.has_component, unit, "character")
	if not (ok and yes == true) then return false end
	local ok2, enemy = pcall(aux.has_component, unit, "enemy")
	return not (ok2 and enemy)
end

-- Whether a command is a hit.
function M.is_hit(interface, command)
	return interface == "damageable" and command == "do_damage"
end

return M
