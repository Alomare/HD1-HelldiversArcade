-- The level-up screen's motion as plain numbers: opacity from 0 to 1 and an offset in design units (y
-- up, so a negative dy is lower), from seconds of real time since a moment (the screen up, a pick, a
-- banish). Timings are rules.lua's. Runs without the game.
local rules = obsidian.module("src/rules")

local M = {}

-- 0 before `start`, 1 after start + dur, and a straight line between.
function M.progress(t, start, dur)
	if dur <= 0 then return t >= start and 1 or 0 end
	return math.max(0, math.min((t - start) / dur, 1))
end

-- Quick at first, settling at the end.
function M.ease_out(x)
	x = math.max(0, math.min(x, 1))
	return 1 - (1 - x) ^ 3
end

-- The dark backdrop, t seconds after the screen came up. full: already dark (another level straight
-- after the last one).
function M.backdrop(t, full)
	if full then return 1 end
	return M.progress(t, 0, rules.BACKDROP_IN)
end

-- When card i (from 1) starts coming in.
function M.card_start(i)
	return rules.CARD_DELAY + (i - 1) * rules.CARD_STAGGER
end

-- Card i, t seconds after the row was dealt: opacity and offset.
function M.card_in(t, i)
	local e = M.ease_out(M.progress(t, M.card_start(i), rules.CARD_IN))
	return e, -rules.CARD_RISE * (1 - e)
end

-- When every card of a row of n is up.
function M.row_done(n)
	return M.card_start(math.max(n, 1)) + rules.CARD_IN
end

-- The stratagem row and the button prompts: in once the last of n cards is up.
function M.extras(t, n)
	return M.progress(t, M.row_done(n), rules.EXTRAS_IN)
end

-- t seconds after a pick: a card's opacity, offset and brightness (from 1 at the pick to 0). The chosen
-- card stays where it is and brightens; the others sink and fade.
function M.pick(t, chosen)
	if chosen then return 1, 0, 1 - M.progress(t, 0, rules.PICK_HOLD) end
	local e = M.ease_out(M.progress(t, 0, rules.PICK_OTHERS))
	return 1 - e, -rules.CARD_SINK * e, 0
end

-- Whether the pick's moment is over, and the turn can move on.
function M.pick_done(t)
	return t >= rules.PICK_HOLD
end

-- The whole screen, t seconds after it started to close: opacity.
function M.screen_out(t)
	return 1 - M.progress(t, 0, rules.SCREEN_OUT)
end

function M.closed(t)
	return t >= rules.SCREEN_OUT
end

-- A banished card on the way out, t seconds after the banish: opacity and offset. Drawn grey.
function M.banish_out(t)
	local e = M.ease_out(M.progress(t, 0, rules.BANISH_OUT))
	return 1 - e, -rules.BANISH_SINK * e
end

function M.banish_gone(t)
	return t >= rules.BANISH_OUT
end

-- The card that takes a banished one's place, t seconds after the banish.
function M.banish_in(t)
	local e = M.ease_out(M.progress(t, rules.BANISH_NEXT, rules.CARD_IN))
	return e, -rules.CARD_RISE * (1 - e)
end

-- Whether presses count yet, t seconds after the row came up: once the grace is over and the cards are
-- readable.
function M.accepts_input(t, n)
	return t >= math.max(rules.CARD_GRACE, M.row_done(n))
end

return M
