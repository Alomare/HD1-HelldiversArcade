-- Weapons a player lets go of: a weapon lying on the ground for a minute is taken away, so the map doesn't
-- fill up with them over a long run. Only what a player dropped counts: a weapon that comes in the crate of a
-- stratagem waits for a player. Every machine runs this and takes away the weapons that machine owns, as the game's
-- rules require, so a dropped weapon goes for everyone at the same moment (Obsidian API's remove_pickup).
local M = {}

M.KEEP = 60            -- seconds a dropped weapon stays
M.LOOK_EVERY = 0.5     -- seconds between looks

function M.new()
	return { seen = {}, wait = 0, since = 0 }
end

-- One look at the ground. d: from M.new; dt: seconds since the last call; world: Obsidian API's world.
function M.update(d, dt, world)
	if not (world and world.pickups and world.remove_pickup) then return end
	d.since = d.since + dt
	d.wait = d.wait - dt
	if d.wait > 0 then return end
	d.wait = M.LOOK_EVERY
	local elapsed = d.since
	d.since = 0
	local here = {}
	for _, p in ipairs(world.pickups(nil, nil, { "weapon_pickup" }) or {}) do
		here[p.unit] = true
		local age = d.seen[p.unit]
		if age == nil then
			-- First sight: a weapon still in the crate that brought it is left alone from now on.
			if p.opening then age = false else age = 0 end
			d.seen[p.unit] = age
		end
		if age then
			age = age + elapsed
			d.seen[p.unit] = age
			if age >= M.KEEP and p.owned then
				world.remove_pickup(p.unit)
			end
		end
	end
	for unit in pairs(d.seen) do
		if not here[unit] then d.seen[unit] = nil end
	end
end

return M
