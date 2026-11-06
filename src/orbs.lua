-- XP orbs on the ground. Every machine drops the same orb where an enemy died. A machine's own players
-- collect it for XP; when someone else's player reaches it, it just goes, because their game counts it.
-- Positions are plain { x, y, z } tables, so this runs without the game.
local rules = obsidian.module("src/rules")

local M = {}

function M.new()
	return { list = {} }
end

local function dist2(a, b)
	local dx, dy = a.x - b.x, a.y - b.y
	return dx * dx + dy * dy
end

-- faction: whose enemy dropped it, for its look. home: the unit of the player it flies straight to
-- (Sample Siphon), or nil.
function M.drop(o, pos, xp, faction, home)
	o.list[#o.list + 1] = { x = pos.x, y = pos.y, z = pos.z or 0, xp = xp, age = 0, faction = faction, home = home }
	-- Past the limit the oldest orb gives its XP to the newest, so nothing is lost.
	while #o.list > rules.ORB_LIMIT do
		local old = table.remove(o.list, 1)
		local new = o.list[#o.list]
		new.xp = new.xp + old.xp
	end
end

-- The sample vacuum (src/vacuum.lua): every orb within `radius` metres of pos flies to the nearest
-- player, however far, until someone takes it. Every machine pulls the same orbs.
function M.pull(o, pos, radius)
	local n = 0
	for _, orb in ipairs(o.list) do
		if dist2(orb, pos) <= radius * radius then
			orb.pulled = true
			n = n + 1
		end
	end
	return n
end

-- players: { { pos = {x,y,z}, is_local = bool, magnet = scale, unit } }. An orb with a home flies to that
-- player, from anywhere, as fast as the vacuum's. Answers the XP collected by this
-- machine's players, and for each local player index how much they took and how many samples.
function M.update(o, dt, players)
	local got, by, count = 0, {}, {}
	local keep = {}
	for _, orb in ipairs(o.list) do
		orb.age = orb.age + dt
		local taken = false
		local nearest, best, found
		for i, p in ipairs(players) do
			local d2 = dist2(orb, p.pos)
			local reach = rules.ORB_RADIUS * (p.magnet or 1)
			if d2 <= reach * reach then
				taken = true
				if p.is_local then
					got = got + orb.xp
					by[i] = (by[i] or 0) + orb.xp
					count[i] = (count[i] or 0) + 1
				end
				break
			end
			local homing = orb.home ~= nil and p.unit == orb.home
			local pull = (orb.pulled or homing) and math.huge or rules.ORB_MAGNET * (p.magnet or 1)
			if homing then
				nearest, best, found = p, d2, true
			elseif not found and d2 <= pull * pull and (not best or d2 < best) then
				nearest, best = p, d2
			end
		end
		-- The player it flew to is gone (dead, or left): an orb like the others.
		if orb.home and not found and not taken then orb.home = nil end
		if not taken and nearest then
			local d = math.sqrt(best)
			local step = math.min(((orb.pulled or nearest.unit == orb.home and orb.home ~= nil) and rules.VACUUM_SPEED or rules.ORB_SPEED) * dt, d)
			orb.x = orb.x + (nearest.pos.x - orb.x) / d * step
			orb.y = orb.y + (nearest.pos.y - orb.y) / d * step
			orb.z = orb.z + ((nearest.pos.z or orb.z) - orb.z) * math.min(step / d, 1)
		end
		orb.taken = taken
		-- A pulled orb is on its way to someone: it doesn't run out of time first.
		if not taken and (orb.age < rules.ORB_LIFE or orb.pulled or orb.home) then keep[#keep + 1] = orb end
	end
	o.list = keep
	return got, by, count
end

return M
