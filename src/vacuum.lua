-- The sample vacuum: once this machine's players have collected the target, every sample on the map
-- flies to the nearest player (src/orbs.lua). The target is rules.VACUUM_EVERY times the
-- need of the level the squad is on when the vacuum starts or goes off, rules.VACUUM_MOST at the most, and it stays until the next
-- time, so a level-up in between doesn't move it. The other machines hear it through lobby data and
-- pull the same samples, so nobody's game counts one twice. Runs without the game.
local rules = obsidian.module("src/rules")

local M = {}

function M.new() return { got = 0, seq = 0, seen = {}, target = nil } end

local function target_for(need)
	return need and need > 0 and math.min(need * rules.VACUUM_EVERY, rules.VACUUM_MOST) or nil
end

-- `amount` collected, with `need` the current level's: true when it goes off, and it starts over with
-- a target from that level.
function M.add(v, amount, need)
	v.target = v.target or target_for(need)
	v.got = v.got + amount
	if v.target and v.got >= v.target then
		v.got = 0
		v.seq = v.seq + 1
		v.target = target_for(need)
		return true
	end
	return false
end

-- Goes off before it's full: the ground holds as many samples as it may (rules.ORB_LIMIT). It starts
-- over with a target from the level of `need`.
function M.force(v, need)
	v.got = 0
	v.seq = v.seq + 1
	v.target = target_for(need)
end

-- Whether the samples on the ground call for the vacuum now: `waiting` not flying to anyone yet.
function M.full_ground(waiting)
	return waiting >= rules.ORB_LIMIT
end

-- How full it is, from 0 to 1. Before the first sample, `need` (the current level's) stands in.
function M.fraction(v, need)
	local target = v.target or target_for(need)
	if not target then return 0 end
	return math.min(v.got / target, 1)
end

-- What this machine shares after going off: the mission, the run, which one, where and when.
function M.encode(v, mission, run, pos, time)
	return string.format("%d;%d;%d;%.1f;%.1f;%d", mission, run, v.seq, pos.x, pos.y, math.floor(time))
end

function M.decode(text)
	if type(text) ~= "string" then return nil end
	local m, r, s, x, y, t = text:match("^(%d+);(%d+);(%d+);(%-?[%d.]+);(%-?[%d.]+);(%d+)$")
	if not m then return nil end
	return { mission = tonumber(m), run = tonumber(r), seq = tonumber(s), x = tonumber(x), y = tonumber(y), time = tonumber(t) }
end

-- Whether another machine's shared vacuum is one to pull for now: this mission, not seen before, and
-- fresh on the run's clock (a player joining late doesn't pull for one long gone).
function M.take(v, peer, e, mission, now)
	if not e or e.mission ~= mission then return false end
	local key = peer .. ":" .. e.run
	if v.seen[key] == e.seq then return false end
	v.seen[key] = e.seq
	return math.abs(now - e.time) <= rules.VACUUM_FRESH
end

return M
