-- What every machine in the lobby agrees on, from what each one shares: the XP its players collected,
-- the last level its players finished choosing for, the host's clock, and how many objectives the squad has done. The team's XP is the sum, the
-- level comes from it, and the game runs again once every machine has chosen up to that level.
--
-- Lobby data outlives the mission, so a shared value names its mission (the seed) and its run (a number
-- each machine draws as its run starts), and a value of another mission doesn't count. A machine that
-- leaves takes nothing with it: its XP stays in the sum, and nobody waits for its choice. Back in the
-- same run, its value takes over again; a new run of its own starts from nothing, beside the old XP.
local xp = obsidian.module("src/xp")

local M = {}

function M.new(mission, run)
	return { mission = mission or 0, run = run or 0, mine = { xp = 0, chosen = 1, objectives = 0 }, peers = {}, gone = {} }
end

-- Every machine counts whole samples: a share of one shows on this machine only, so it would put this
-- machine a level ahead of what the others work out.
local function whole(n) return math.floor(n + 1e-9) end

-- What another machine shares, or nil for one that left.
function M.set_peer(s, peer, shared)
	local p = s.peers[peer]
	if not shared or shared.mission ~= s.mission then
		if p then s.gone[peer .. ":" .. p.run] = p end
		s.peers[peer] = nil
		return
	end
	s.gone[peer .. ":" .. shared.run] = nil
	s.peers[peer] = { xp = shared.xp, chosen = shared.chosen, run = shared.run, time = shared.time, host = shared.host, objectives = shared.objectives or 0 }
end

function M.team_xp(s)
	local total = whole(s.mine.xp)
	for _, p in pairs(s.peers) do total = total + p.xp end
	for _, p in pairs(s.gone) do total = total + p.xp end
	return total
end

function M.level(s)
	return (xp.level_of(M.team_xp(s)))
end

-- The level this machine's players should choose for next, or nil when they're up to date.
function M.to_choose(s)
	if s.mine.chosen < M.level(s) then return s.mine.chosen + 1 end
	return nil
end

-- True while any machine still here, this one included, still has a level to choose.
function M.choosing(s)
	local level = M.level(s)
	if s.mine.chosen < level then return true end
	for _, p in pairs(s.peers) do
		if p.chosen < level then return true end
	end
	return false
end

-- The run's clock as the host has it, or nil when the host isn't another machine.
function M.host_time(s)
	for _, p in pairs(s.peers) do
		if p.host then return p.time end
	end
	return nil
end

function M.collected(s, amount)
	s.mine.xp = s.mine.xp + amount
end

function M.chose(s, level)
	if level > s.mine.chosen then s.mine.chosen = level end
end

-- Objectives done: the host counts each one (M.objective_done), and every machine shares the most it
-- has seen, so the count reaches everyone and outlives a host who leaves. Answers the count.
function M.objective_done(s)
	s.mine.objectives = M.objectives(s) + 1
	return s.mine.objectives
end

function M.objectives(s)
	local most = s.mine.objectives
	for _, p in pairs(s.peers) do most = math.max(most, p.objectives or 0) end
	s.mine.objectives = most
	return most
end

-- The text this machine shares, and reading another's back. time: the run's clock in seconds. host:
-- whether this machine is the host.
function M.encode(s, time, host)
	return string.format("%d;%d;%d;%d;%d;%d;%d", s.mission, s.run, whole(s.mine.xp), s.mine.chosen, math.floor(time or 0), host and 1 or 0, M.objectives(s))
end

function M.decode(text)
	if type(text) ~= "string" then return nil end
	-- A value without the objectives' count counts none.
	local m, r, a, b, t, h, o = text:match("^(%d+);(%d+);(%d+);(%d+);(%d+);([01]);(%d+)$")
	if not m then m, r, a, b, t, h = text:match("^(%d+);(%d+);(%d+);(%d+);(%d+);([01])$") end
	if not m then return nil end
	return { mission = tonumber(m), run = tonumber(r), xp = tonumber(a), chosen = tonumber(b), time = tonumber(t), host = h == "1", objectives = tonumber(o) or 0 }
end

return M
