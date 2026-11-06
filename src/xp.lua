-- Team XP and levels. Every machine works the level out from the same total, so they agree.
local M = {}

-- XP from level `level` to the next. It used to start at 8 and grew by 5.4 a level plus 0.72 *
-- (level - 1) ^ 1.6: levels came fast at first and slowly later. Now the first asks more and each one
-- after adds less, so they come more evenly.
M.BASE = 14
M.STEP = 4.2
M.CURVE = 0.45

function M.need(level)
	return math.floor(M.BASE + M.STEP * (level - 1) + M.CURVE * (level - 1) ^ 1.6 + 0.5)
end

-- The level a total reaches, the XP into it, and the XP it needs.
function M.level_of(total)
	local level, left = 1, math.max(total or 0, 0)
	while left >= M.need(level) do
		left = left - M.need(level)
		level = level + 1
	end
	return level, left, M.need(level)
end

-- The XP bar's look: the fill follows the XP into the level smoothly, and the bar pulses a brighter
-- blue when samples come in. The fill is kept as a position in levels (3.25: a quarter into level 3),
-- so a level-up fills the bar to its end and starts it again from empty.
M.BAR_RATE = 8 -- per second: how quickly the fill closes on the XP
M.BAR_PULSE = 0.5 -- seconds a pulse takes to fade
M.BAR_BLUE, M.BAR_BRIGHT = { 0x3a, 0x8e, 0xe6 }, { 0x9c, 0xd2, 0xff }

function M.bar_new() return { pulse = 0 } end

-- One frame of the bar: total is the team's XP, dt seconds. Answers how full the bar shows (0 to 1)
-- and how strong the pulse is (0 to 1).
function M.bar_step(bar, total, dt)
	local level, into, need = M.level_of(total)
	local target = level + math.min(into / need, 1)
	dt = math.max(dt or 0, 0)
	if bar.pos == nil or total < bar.total then
		-- The first frame, or a new run: no easing from what was there.
		bar.pos, bar.pulse = target, 0
	else
		-- Several levels at once (the vacuum) show the last one filling.
		if target - bar.pos > 1 then bar.pos = target - 1 end
		bar.pos = bar.pos + (target - bar.pos) * math.min(dt * M.BAR_RATE, 1)
		if math.abs(target - bar.pos) < 1e-3 then bar.pos = target end
		bar.pulse = math.max(bar.pulse - dt / M.BAR_PULSE, 0)
		if total > bar.total then bar.pulse = 1 end
	end
	bar.total = total
	local fill = bar.pos - math.floor(bar.pos)
	-- On a level's end exactly, the bar stays full until the next level starts.
	if fill == 0 and bar.pos < target then fill = 1 end
	return fill, bar.pulse
end

-- The fill's color at a pulse's strength: the bar's blue, brightening towards a pale blue.
function M.bar_color(pulse)
	local t = math.max(0, math.min(pulse or 0, 1))
	local c = {}
	for i = 1, 3 do c[i] = math.floor(M.BAR_BLUE[i] + (M.BAR_BRIGHT[i] - M.BAR_BLUE[i]) * t + 0.5) end
	return string.format("#%02x%02x%02x", c[1], c[2], c[3])
end

return M
