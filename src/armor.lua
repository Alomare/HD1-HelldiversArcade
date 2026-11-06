-- Absolute Freedom on the weapons whose hits don't carry a weapon's attributes: lasers, flamethrowers and
-- arc weapons. A firearm sends ignore_armor with its hit (src/perks.lua tunes it on), but these build
-- their own hit data (WeaponUtility.shoot_beam_callback and shoot_flame_callback, and
-- ArcweaponComponent.command_slave), so the flag is added as the hit goes out. Only during those calls,
-- the game's EntityAux.queue_command_interface is swapped for one that marks a do_damage; nothing runs
-- for any other command or on any other frame. The flag travels with the hit, so the machine that
-- prices it, the shooter's or the enemy's owner, sees the armor at 0 (HealthComponent.calculate_damage).
local M = {}

local function g(name) return rawget(_G, name) end

-- Marks a hit's data: armor ignored.
function M.mark(command, data)
	if command == "do_damage" and type(data) == "table" then
		data.ignore_armor = true
		data.armorignore = true
	end
	return data
end

-- The player carrying `weapon`, or nil.
local function wielder(weapon)
	local aux = g("EntityAux")
	local ok, state = pcall(function() return aux.has_component(weapon, "equipment") and aux.state(weapon, "equipment") end)
	return ok and type(state) == "table" and state.wielder or nil
end

-- Runs fn(...) with the hits it sends marked, when `weapon` belongs to a player of this machine with
-- Absolute Freedom. stats_of(unit): that player's stats, or nil.
function M.run_marked(stats_of, weapon, fn, ...)
	local owner = weapon and wielder(weapon)
	local stats = owner and stats_of(owner)
	if not (stats and stats.pierce) then return fn(...) end
	local aux = g("EntityAux")
	local real = aux.queue_command_interface
	aux.queue_command_interface = function(unit, component, command, data, ...)
		return real(unit, component, command, M.mark(command, data), ...)
	end
	local r = { pcall(fn, ...) }
	aux.queue_command_interface = real
	if not r[1] then error(r[2], 0) end
	return unpack(r, 2, table.maxn(r))
end

function M.install(stats_of)
	-- The beam's and the flame's hit routine is made once per weapon, when it's set up: the routine
	-- handed back is wrapped.
	for _, name in ipairs({ "shoot_beam_callback", "shoot_flame_callback" }) do
		obsidian.hook("WeaponUtility", name, function(original, weapon, ...)
			local routine = original(weapon, ...)
			if type(routine) ~= "function" then return routine end
			return function(...) return M.run_marked(stats_of, weapon, routine, ...) end
		end)
	end
	-- An arc weapon sends its hits while it handles a shot.
	obsidian.hook("ArcweaponComponent", "command_slave", function(original, self, weapon, ...)
		return M.run_marked(stats_of, weapon, original, self, weapon, ...)
	end)
end

return M
