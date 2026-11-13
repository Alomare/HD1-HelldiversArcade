-- The game's alarm in a Survivors mission. In a normal mission, an enemy that spots the squad stops,
-- plays an alert (a scout's scream, a flare) and a few seconds later starts one of the game's
-- encounters (EnemyUtility.check_alarm). Each alarm while an encounter runs adds more of the game's
-- waves to it (EncounterManager.start_encounter), so here they came on top of the director's, and the
-- alerts never stopped. In a run no enemy raises an alarm: the alarm is the run's. After the landing a
-- countdown runs (rules.countdown), and at its end the host raises the alarm, then raises it again
-- whenever it goes quiet, so it stays on. Every enemy knows where the squad is and goes for it at once,
-- with no alert, scream or flare, and starts no encounter of its own.
local level = obsidian.module("src/level")

local M = {}

M.CHECK_EVERY = 5 -- seconds between the host's looks at whether the alarm went quiet

-- Set while the run raises the alarm, the only start_encounter that passes in a run once it's on.
local own = false
-- The run's alarm record while the first alarm is left to the game (M.wait_natural), or nil.
local waiting = nil

-- A run starts: its first alarm is the game's. a: the run's alarm record, { raised, wait }.
function M.wait_natural(a)
	waiting = a
end

-- No first alarm to wait for: the run raises it itself (a new host mid-run, the run's end).
function M.skip_natural()
	waiting = nil
end

function M.natural() return waiting ~= nil end

-- The game's own alarm went on: the run's record takes it as raised, and keeps it on from here.
function M.on_natural()
	local a = waiting
	waiting = nil
	if not a then return end
	a.raised, a.wait = true, M.CHECK_EVERY
	if obsidian.log then obsidian.log("arcade: the first alarm, raised by the enemy") end
end

-- Whether an enemy in a run knows where the squad is: always, once it has a player to go for.
function M.aware(state, seen)
	if seen then return true end
	local target = type(state) == "table" and state.closest_target_unit
	if target == nil then return false end
	local U = rawget(_G, "Unit")
	local ok, alive = pcall(U and U.alive or function() return false end, target)
	return ok and alive == true
end

-- What an enemy's alarm check does in a run, given whether it noticed the squad: one that did stops
-- patrolling, as it would once the alert was over, so the next update goes for the target.
function M.notice(state, noticed)
	if not noticed then return end
	state.alerted = false
	state.patroling = false
	state.has_triggered_encounter = true
end

-- Whether the host raises the alarm now: when it hasn't yet, or it went quiet and `wait` ran out.
function M.due(raised, running, wait)
	return not raised or (not running and wait <= 0)
end

-- Animation events that play an alert: a scout's scream, a Cyborg's flare.
M.ALERTS = { alert = true, alert_complete = true }

function M.install()
	-- Every enemy notices the squad here before an alert, whether through check_alarm or a state of the enemy's
	-- (the IFV, the jumping scouts, the Hive Lord, the Observers): in a run it goes off patrol instead
	-- and is told it saw nothing, so no alert starts.
	-- Until the first alarm, all of it is the game's.
	obsidian.hook("EnemyUtility", "check_alert", function(original, state, ...)
		local seen = original(state, ...)
		if not (level.active and not waiting and type(state) == "table") then return seen end
		-- Every enemy knows where the squad is, seen or not, and goes for it with no alert.
		M.notice(state, M.aware(state, seen))
		return false
	end)
	-- An alert under way when the alarm became the run's ends at once.
	obsidian.hook("EnemyUtility", "check_alarm", function(original, unit, dt, ctx, raycast, state, ...)
		if level.active and not waiting and type(state) == "table" and state.alerted then return M.notice(state, true) end
		return original(unit, dt, ctx, raycast, state, ...)
	end)
	-- Whatever still starts an alert plays it silently.
	obsidian.hook("EntityStateMachine", "animation_event", function(original, unit, event, ...)
		if level.active and not waiting and M.ALERTS[event] then return end
		return original(unit, event, ...)
	end)
	obsidian.hook("EncounterManager", "start_encounter", function(original, self, ...)
		if level.active and not own then
			if not waiting then return end
			local r = { original(self, ...) }
			M.on_natural()
			return unpack(r)
		end
		return original(self, ...)
	end)
end

-- Host only, each frame of the run while the squad is down: raises the alarm at the squad's centre
-- (`at`, a vector) when due, once the game's first alarm went on. a: the run's alarm record, { raised,
-- wait }. Answers true when raised.
function M.update(a, em, at, dt)
	if not (em and at) or waiting == a then return false end
	a.wait = (a.wait or 0) - dt
	local running = false
	if a.raised then
		local ok, on = pcall(em.is_active, em)
		running = ok and on == true
	end
	if not M.due(a.raised, running, a.wait) then
		if a.wait <= 0 then a.wait = M.CHECK_EVERY end
		return false
	end
	a.wait = M.CHECK_EVERY
	own = true
	local ok, err = pcall(em.start_encounter, em, at)
	own = false
	if not ok then obsidian.log("arcade: the alarm didn't go on: " .. tostring(err)) return false end
	a.raised = true
	return true
end

return M
