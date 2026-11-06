-- Survivors seeds: a normal mission seed with a mark above its seven digits of params. Every machine
-- gets the same seed, so every one of them knows the mission is a Survivors one.
--
-- The game reads five of the params digits modulo a count (DifficultySettings.get_mission_params):
-- time of day 4, light 6, planet type 6, variant 6 and faction 3. A digit and that digit plus the count
-- read as the same mission, but GeneratedLevel seeds the map's randomizer with the whole seed, so they
-- lay out different maps. A layout number picks one of these spellings, so one faction, difficulty
-- and planet type has many maps, and every seed stays below the mark's next value (the seed goes over
-- the network as a uint31).
local rules = obsidian.module("src/rules")

local M = {}

function M.is_survivors(seed)
	return type(seed) == "number" and math.floor(seed / rules.SEED_PARAMS) == rules.SEED_MARK
end

-- Each read-modulo digit: its place, the DifficultySettings list whose length is the count, and the
-- game's count when the list isn't there.
M.DIGITS = {
	{ 1000000, "time_of_day_lookup", 4 },
	{ 100000, "shading_environment_lookup", 6 },
	{ 10000, "environment_lookup", 6 },
	{ 1000, "environment_variants", 6 },
	{ 100, "enemy_lookup", 3 },
}

local function count_of(settings, digit)
	local list = type(settings) == "table" and settings[digit[2]]
	return type(list) == "table" and #list > 0 and #list or digit[3]
end

-- How many spellings `params` has: the digits' choices multiplied.
function M.layouts(settings, params)
	local n = 1
	for _, d in ipairs(M.DIGITS) do
		local count = count_of(settings, d)
		local base = math.floor(params / d[1]) % 10 % count
		n = n * (math.floor((9 - base) / count) + 1)
	end
	return n
end

-- `params` spelled the way `layout` (a whole number, 0 for the plain one) picks, digit by digit.
function M.spell(settings, params, layout)
	layout = math.floor(math.abs(tonumber(layout) or 0))
	for _, d in ipairs(M.DIGITS) do
		local place, count = d[1], count_of(settings, d)
		local digit = math.floor(params / place) % 10
		local base = digit % count
		local choices = math.floor((9 - base) / count) + 1
		local pick = layout % choices
		layout = math.floor(layout / choices)
		params = params + (base + pick * count - digit) * place
	end
	return params
end

-- settings: the game's DifficultySettings. choice: 1-based indexes of time, light, planet, variant and
-- faction, a difficulty, and a layout (any whole number, 0 when left out). The mission type is always a
-- normal mission (index 1).
function M.make(settings, choice)
	local params = settings.modulate_seed(choice.time - 1, choice.light - 1, choice.environment - 1, choice.variant - 1,
		choice.enemy - 1, 0, choice.difficulty, 0)
	params = M.spell(settings, params % rules.SEED_PARAMS, choice.layout)
	return rules.SEED_MARK * rules.SEED_PARAMS + params
end

-- The planet a Survivors mission is on, as a text key of the game's 133 planet names.
function M.planet_key(seed)
	return string.format("planet_%02d", math.floor(seed) % 133 + 1)
end

return M
