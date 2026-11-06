-- The game's alarm in a Survivors mission. In a normal mission, an enemy that spots the squad stops,
-- plays an alert (a scout's scream, a flare) and a few seconds later starts one of the game's
-- encounters (EnemyUtility.check_alarm). Each alarm while an encounter runs adds more of the game's
-- waves to it (EncounterManager.start_encounter), so here they came on top of the director's, and the
-- alerts never stopped. In a run the alarm is the mission's own instead: the host raises it as the
-- squad lands and raises it again whenever it goes quiet, so it stays on. An enemy that spots the squad
-- attacks at once, with no alert, scream or flare, and no enemy starts an encounter.
local level = obsidian.module("src/level")

local M = {}

M.CHECK_EVERY = 5 -- seconds between the host's looks at whether the alarm went quiet

-- Set while the run raises the alarm, the only start_encounter that passes in a run.
local own = false

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
	obsidian.hook("EnemyUtility", "check_alert", function(original, state, ...)
		local seen = original(state, ...)
		if not (level.active and seen and type(state) == "table") then return seen end
		M.notice(state, true)
		return false
	end)
	-- An alert under way when the run started ends at once.
	obsidian.hook("EnemyUtility", "check_alarm", function(original, unit, dt, ctx, raycast, state, ...)
		if level.active and type(state) == "table" and state.alerted then return M.notice(state, true) end
		return original(unit, dt, ctx, raycast, state, ...)
	end)
	-- Whatever still starts an alert plays it silently.
	obsidian.hook("EntityStateMachine", "animation_event", function(original, unit, event, ...)
		if level.active and M.ALERTS[event] then return end
		return original(unit, event, ...)
	end)
	obsidian.hook("EncounterManager", "start_encounter", function(original, self, ...)
		if level.active and not own then return end
		return original(self, ...)
	end)
end

-- Host only, each frame of the run while the squad is down: raises the alarm at the squad's centre
-- (`at`, a vector) when due. a: the run's alarm record, { raised, wait }. Answers true when raised.
function M.update(a, em, at, dt)
	if not (em and at) then return false end
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
