local entry = obsidian.module("src/entry")
local seed = obsidian.module("src/seed")
local rng = obsidian.module("src/rng")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

-- DifficultySettings.modulate_seed's digits, enough to tell the missions apart.
local settings = {
	modulate_seed = function(time, light, env, variant, enemy, kind, difficulty)
		return ((((time * 10 + light) * 10 + env) * 10 + variant) * 10 + enemy) * 100 + difficulty
	end,
}
local function make(choice) return seed.make(settings, choice) end

-- The game's reading of a seed (DifficultySettings.get_mission_params), with the game's list lengths.
local function params_of(s)
	return {
		time = math.floor(s / 1000000) % 10 % 4, light = math.floor(s / 100000) % 10 % 6,
		environment = math.floor(s / 10000) % 10 % 6, variant = math.floor(s / 1000) % 10 % 6,
		enemy = math.floor(s / 100) % 10 % 3, kind = math.floor((s % 100) / 20) % 5,
		difficulty = math.max(1, math.min((s % 100) % 20, 15)),
	}
end

local CHOICE = { mode = 1, enemy = 2, difficulty = 9, environment = 4 }

test("every_layout_reads_as_the_same_mission_and_seeds_a_different_map", function()
	for _, c in ipairs({
		{ time = 1, light = 1, environment = 1, variant = 1, enemy = 1, difficulty = 1 },
		{ time = 4, light = 3, environment = 5, variant = 3, enemy = 3, difficulty = 15 },
		{ time = 2, light = 2, environment = 4, variant = 2, enemy = 2, difficulty = 7 },
	}) do
		local plain = make(c)
		local want = params_of(plain)
		local n = seed.layouts(settings, plain % 10000000)
		eq(n > 20, true, "many layouts for one mission")
		local seen = {}
		for layout = 0, n - 1 do
			c.layout = layout
			local s = make(c)
			eq(seed.is_survivors(s), true, "a Survivors seed")
			eq(s < 2 ^ 31, true, "fits the network's uint31")
			eq(seen[s], nil, "a seed of its own for layout " .. layout)
			seen[s] = true
			for k, v in pairs(params_of(s)) do eq(v, want[k], k .. " reads the same") end
		end
		c.layout = 0
		eq(make(c), plain, "layout 0 is the plain seed")
		c.layout = n
		eq(seen[make(c)], true, "past the last layout, they come round again")
	end
end)

test("the_preview_is_a_trial_the_proving_grounds_screen_can_show", function()
	local m = entry.mission(make, CHOICE, { time = 3, light = 2, variant = 1, layout = 5 }, function(s) return "Planet " .. s end)
	eq(m.index, 1)
	eq(m.unlocked, true)
	eq(m.survivors, true, "marked, so leaving with it becomes a Survivors drop")
	eq(m.name, "Planet " .. m.seed)
	eq(m.planet.seed, m.seed)
	eq(m.planet.enemy, CHOICE.enemy - 1, "the game counts fronts from 0")
	eq(m.planet.difficulty, CHOICE.difficulty)
	eq(m.provinggrounds_seed, nil, "a normal mission, not a trial")
	eq(m.choice.enemy, CHOICE.enemy, "the hellpods' front")
	local p = params_of(m.seed)
	eq(p.enemy, CHOICE.enemy - 1) eq(p.difficulty, CHOICE.difficulty) eq(p.environment, CHOICE.environment - 1)
	eq(p.time, 2) eq(p.light, 1) eq(p.kind, 0, "a normal mission")
end)

test("refresh_keeps_the_parameters_and_makes_a_new_map", function()
	local r = rng.new(4)
	local last = entry.reroll(make, CHOICE, r, nil, nil).seed
	for _ = 1, 100 do
		local m = entry.reroll(make, CHOICE, r, nil, last)
		eq(m.seed ~= last, true, "a different seed each time")
		local p = params_of(m.seed)
		eq(p.enemy, CHOICE.enemy - 1) eq(p.difficulty, CHOICE.difficulty) eq(p.environment, CHOICE.environment - 1)
		eq(p.light < 3 and p.variant < 3, true, "light and variant as the campaign's planets have them")
		last = m.seed
	end
end)

test("factions_and_biomes_go_round_and_the_difficulty_stops_at_its_ends", function()
	local limits = { enemy = 3, difficulty = 15, environment = 5 }
	local c = { enemy = 3, difficulty = 15, environment = 1 }
	eq(entry.step(c, "enemy", 1, limits), true) eq(c.enemy, 1)
	eq(entry.step(c, "enemy", -1, limits), true) eq(c.enemy, 3)
	eq(entry.step(c, "environment", -1, limits), true) eq(c.environment, 5)
	eq(entry.step(c, "difficulty", 1, limits), false, "15 is the top") eq(c.difficulty, 15)
	c.difficulty = 1
	eq(entry.step(c, "difficulty", -1, limits), false, "1 is the bottom")
	eq(entry.step(c, "difficulty", 1, limits), true) eq(c.difficulty, 2)
end)

test("the_difficulty_range_is_the_games", function()
	local saved = { DifficultySettings, CampaignSettings }
	local ok, err = pcall(function()
		DifficultySettings, CampaignSettings = nil, nil
		eq(entry.max_difficulty(), 15, "the game's 15 when nothing says otherwise")
		DifficultySettings = { max_difficulty = 15 }
		CampaignSettings = { planet_difficulty_names = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }, difficulty_bar = { cells = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 } } }
		eq(entry.max_difficulty(), 12, "no further than the game has names for")
		eq(entry.limits().difficulty, 12)
	end)
	DifficultySettings, CampaignSettings = saved[1], saved[2]
	if not ok then error(err, 0) end
end)

test("the_panels_move_as_the_games_option_menus_do", function()
	local rows = entry.rows(entry.MODES[1])
	eq(rows, 5, "three parameters, Refresh, Launch")
	local ui = { panel = 1, mode = 1, row = 1 }
	eq(entry.navigate(ui, "down", 1, rows), nil, "one mode: nowhere to go")
	eq(entry.navigate(ui, "left", 1, rows), nil)
	eq(entry.navigate(ui, "select", 1, rows), "mode", "taking the mode")
	eq(ui.panel, 2, "and on to its parameters")
	local act, dir = entry.navigate(ui, "right", 1, rows)
	eq(act, "change") eq(dir, 1)
	act, dir = entry.navigate(ui, "left", 1, rows)
	eq(act, "change") eq(dir, -1)
	eq(entry.navigate(ui, "up", 1, rows), "move") eq(ui.row, 5, "up from the top goes round to Launch")
	eq(entry.navigate(ui, "up", 1, rows), "move") eq(ui.row, 4, "Refresh sits over Launch")
	eq(entry.navigate(ui, "select", 1, rows), "refresh")
	eq(entry.navigate(ui, "right", 1, rows), nil, "Refresh has no value")
	eq(entry.navigate(ui, "left", 1, rows), "move") eq(ui.panel, 1, "left from Refresh goes back to the modes")
	eq(entry.navigate(ui, "next_panel", 1, rows), "move") eq(ui.panel, 2, "the shoulder buttons switch panels")
	eq(entry.navigate(ui, "down", 1, rows), "move") eq(ui.row, 5)
	eq(entry.navigate(ui, "right", 1, rows), nil, "Launch has no value")
	eq(entry.navigate(ui, "select", 1, rows), "launch", "Select on Launch launches")
	eq(entry.navigate(ui, "down", 1, rows), "move") eq(ui.row, 1, "down from Launch goes round to the top")
	eq(entry.navigate(ui, "prev_panel", 1, rows), "move") eq(ui.panel, 1)
	local two = { panel = 1, mode = 2, row = 1 }
	eq(entry.navigate(two, "down", 2, rows), "move") eq(two.mode, 1, "modes go round")
end)

test("only_launch_launches", function()
	local rows = entry.rows(entry.MODES[1])
	local keys = { "up", "down", "left", "right", "prev_panel", "next_panel", "select" }
	for panel = 1, 2 do
		for row = 1, rows do
			for _, key in ipairs(keys) do
				local ui = { panel = panel, mode = 1, row = row }
				local act = entry.navigate(ui, key, 1, rows)
				local launches = panel == 2 and row == rows and key == "select"
				eq(act == "launch", launches, key .. " on panel " .. panel .. " row " .. row)
			end
		end
	end
	for i = 1, rows - 2 do
		local ui = { panel = 2, mode = 1, row = i }
		eq(entry.navigate(ui, "select", 1, rows), "move", "Select on a parameter only moves")
		eq(ui.row, rows, "onto Launch")
	end
end)

test("a_click_takes_what_the_cursor_is_over", function()
	local ui = { panel = 1, mode = 1, row = 1 }
	eq(entry.click(ui, nil), nil)
	local act, dir = entry.click(ui, { panel = 2, row = 2, dir = -1 })
	eq(act, "change") eq(dir, -1) eq(ui.panel, 2) eq(ui.row, 2)
	eq(entry.click(ui, { panel = 2, row = 4, refresh = true }), "refresh")
	eq(entry.click(ui, { panel = 2, row = 5, launch = true }), "launch") eq(ui.row, 5)
	eq(entry.click(ui, { panel = 1, row = 1 }), "pick") eq(ui.panel, 1)
end)

test("the_panels_fill_the_layout_with_even_gaps", function()
	local L = entry.LAYOUT
	local modes, params, preview = entry.panel_x(L)
	eq(modes, L.left)
	eq(params - (modes + L.mode_w), L.gap, "the first gap")
	eq(preview - (params + L.param_w), L.gap, "the second gap, the same")
	eq(preview + L.preview_w + L.right, L.width, "the preview, drawn from the right, meets the third")
	eq(L.left, L.right, "the same margin on both sides")
end)

test("the_parameters_stack_without_overlap", function()
	local L = entry.LAYOUT
	local top = L.y + L.h - 44
	local P = entry.params_layout(top, L.y, 3, 18)
	local last = top
	for i, r in ipairs(P.rows) do
		eq(r.label + 18 <= last, true, "label " .. i .. " under what is above")
		eq(r.box + entry.ROW <= r.label, true, "selector " .. i .. " under its label")
		last = r.box
	end
	eq(P.refresh + entry.ROW < last, true, "Refresh under the last selector")
	eq(P.launch + entry.LAUNCH_H < P.refresh, true, "Launch under Refresh")
	eq(P.launch > L.y, true, "inside the panel")
end)

test("the_parameters_make_room_for_the_difficulty_bar_under_its_selector", function()
	local L = entry.LAYOUT
	local top = L.y + L.h - 44
	local plain = entry.params_layout(top, L.y, 3, 18)
	local P = entry.params_layout(top, L.y, 3, 18, { [2] = 24 })
	eq(P.rows[1].label, plain.rows[1].label, "the rows above it stay")
	eq(P.rows[2].box, plain.rows[2].box)
	eq(plain.rows[2].bar, nil, "no bar where none is asked for")
	eq(P.rows[2].bar + 24 <= P.rows[2].box - entry.BAR_GAP, true, "the bar under the difficulty's selector")
	eq(P.rows[3].label + 18 < P.rows[2].bar, true, "the next label under the bar")
	eq(P.rows[3].box + entry.ROW <= P.rows[3].label, true)
	eq(P.refresh + entry.ROW < P.rows[3].box, true, "Refresh still under the last selector")
	eq(plain.rows[2].label - plain.rows[3].label, 66, "without a bar, the game's spacing")
end)

test("the_preview_puts_the_name_on_the_map_and_the_objectives_under_it", function()
	local L = entry.LAYOUT
	local top = L.y + L.h - 44
	local P = entry.preview_layout(top, L.y, 18)
	eq(P.map_top <= top, true, "the map under the heading")
	eq(P.map_top - P.map_bottom, entry.MAP.h)
	eq(P.name + 18 <= P.map_top and P.name > P.map_bottom, true, "the name inside the map's top")
	eq(P.ceiling < P.map_bottom, true, "the objectives under the map")
	eq(P.floor > L.y, true, "inside the panel")
	eq(entry.list_overflow(3, P.room), 0, "three objectives fit")
	eq(entry.list_overflow(0, P.room), 0)
	eq(entry.list_overflow(4, P.room) > 0, true, "a fourth scrolls")
	eq(entry.MAP.w <= L.preview_w - 24, true, "the map fits the panel")
	eq(entry.map_extent(entry.MAP.scale) <= entry.MAP.h, true, "a map turned 45 degrees fits the box's height")
	eq(entry.map_extent(entry.MAP.scale) <= entry.MAP.w, true, "and its width")
end)

test("the_scroll_arrows_have_a_column_of_their_own", function()
	local P = entry.preview_layout(entry.LAYOUT.y + entry.LAYOUT.h - 44, entry.LAYOUT.y, 18)
	local fit = entry.list_columns(3, P.room, entry.MAP.w)
	eq(fit.most, 0) eq(fit.list_w, entry.MAP.w, "rows that fit take the whole width") eq(fit.arrow_x, nil)
	local long = entry.list_columns(6, P.room, entry.MAP.w)
	eq(long.most > 0, true)
	eq(long.list_w < long.arrow_x, true, "the rows end before the arrows")
	eq(long.arrow_x + entry.ARROW, entry.MAP.w, "the arrows at the right edge")
end)

test("backing_out_asks_in_the_arcades_words", function()
	LocalizationManager = { string = function(_, key) return "game:" .. key end }
	local ok, err = pcall(function()
		local asked
		entry.back({}, function(_, input)
			eq(input.back, true, "the game's Back")
			asked = LocalizationManager:string("campaign_leave_provinggrounds_confirmation")
		end)
		eq(asked, entry.TEXTS.campaign_leave_provinggrounds_confirmation)
		eq(asked:find("Proving"), nil, "no Proving Grounds in the question")
		eq(asked:find("ARCADE") ~= nil, true)
		eq(LocalizationManager:string("campaign_leave_provinggrounds_confirmation"), "game:campaign_leave_provinggrounds_confirmation", "the game's own after")
	end)
	LocalizationManager = nil
	if not ok then error(err, 0) end
end)

test("the_preview_lists_each_objective_of_the_map_once", function()
	local list = entry.objectives({
		{ objectives = { { name = "mission_objective_droppoint", icon = "drop" } } },
		{ objectives = { { name = "mission_objective_launch", icon = "launch" }, { name = "mission_objective_launch", icon = "launch" } } },
		{},
		{ objectives = { { name = "mission_objective_extract", icon = "extract" } } },
		{ objectives = { { icon = "nameless" }, { name = "mission_objective_sam", icon = "sam" } } },
		{ objectives = { { name = "mission_objective_launch", icon = "launch" } } },
	})
	eq(#list, 2, "no drop point, no extraction, each name once")
	eq(list[1].name, "mission_objective_launch") eq(list[1].icon, "launch")
	eq(list[2].name, "mission_objective_sam", "in the order the map placed them")
	eq(#entry.objectives(nil), 0)
end)

test("labels_follow_the_case_of_the_games_own", function()
	eq(entry.cased("STARTING FACTION", "Difficulty"), "Starting Faction")
	eq(entry.cased("STARTING FACTION", "DIFFICULTY"), "STARTING FACTION")
	eq(entry.cased("Biome", nil), "BIOME", "without the game's text, capitals")
	eq(entry.cased("MISSION PREVIEW", "\194\172E\194\172 DIFFICULTY"), "MISSION PREVIEW", "a button's mark isn't a word")
end)

test("the_tab_and_the_title_read_arcade", function()
	eq(entry.TEXTS[entry.TAB], "ARCADE")
	eq(entry.TEXTS.menu_campaign, "ARCADE")
	eq(entry.MODES[1].name, "SUPER EARTH SURVIVORS")
	for _, mode in ipairs(entry.MODES) do
		local words = " " .. mode.about:lower() .. " "
		eq(words:find("[^%a]its[^%a]"), nil, "no \"its\" in the description")
		eq(words:find("[^%a][iI][^%a']") or words:find("[^%a]my[^%a]") or words:find("[^%a]we[^%a]"), nil, "no first person")
	end
end)

test("the_pods_get_a_planet_with_a_mission_left_on_the_home_front_first", function()
	local done = { completed = true }
	local available = {
		{ planets = { { name = "a", missions = { done } } } },
		{ planets = { { name = "b", missions = { done, { completed = false } } } } },
		{ planets = { { name = "c", missions = { { completed = false } } } } },
	}
	available[2].current_region = 4
	local planet = entry.pick_planet(available, 2)
	eq(planet.name, "b")
	eq(planet.selected_mission_index, 2)
	eq(planet.region, 4, "the ship stops on a planet without a region")
	eq(planet.enemy, 1, "the game counts fronts from 0")
	eq(entry.pick_planet(available, 1).name, "b", "the next front when home has none")
	eq(entry.pick_planet({ { planets = { { missions = { done } } } } }, 1), nil)
	eq(entry.pick_planet(nil, 1), nil)
end)

local function fake_save(values)
	return { values = values, get = function(self, k) return self.values[k] end, set = function(self, k, v) self.values[k] = v end }
end

test("a_planet_saved_without_a_region_is_rebuilt_or_let_go", function()
	local available = { {}, { current_region = 3, planets = { { name = "b", difficulty = 5, seed = 9, missions = {} } } } }
	local save = fake_save({ available_planets = available, current_planet = { name = "b", selected_mission_index = 2 } })
	eq(entry.heal_planet(save), true)
	eq(save.values.current_planet.region, 3)
	eq(save.values.current_planet.enemy, 1)
	eq(save.values.current_planet.selected_mission_index, 2)
	eq(entry.heal_planet(save), false, "a whole planet is left alone")
	local gone = fake_save({ available_planets = available, current_planet = { name = "lost" }, next_mission_seed = 5 })
	eq(entry.heal_planet(gone), true)
	eq(gone.values.current_planet, nil)
	eq(gone.values.next_mission_seed, nil)
	eq(entry.heal_planet(fake_save({})), false, "no planet, nothing to do")
end)

test("the_refresh_button_reads_like_the_games_select", function()
	eq(entry.button_text("  \194\172E\194\172 Select", "\194\172Q\194\172 Back", "\194\172R\194\172"), "  \194\172R\194\172 Refresh")
	eq(entry.button_text("\194\172E\194\172 SELECT   ", "\194\172Q\194\172 BACK   ", "\194\172R\194\172"), "\194\172R\194\172 REFRESH   ")
	eq(entry.button_text(nil, nil, nil), "   REFRESH", "no game text: spaced, and no button")
end)

test("the_key_guides_select_reads_launch", function()
	eq(entry.relabel("  \194\172E\194\172 Select", "Launch"), "  \194\172E\194\172 Launch")
	eq(entry.relabel("\194\172E\194\172 SELECT   ", "Launch"), "\194\172E\194\172 LAUNCH   ", "the case and the spacing stay")
	eq(entry.relabel("Select", "Launch"), "Launch", "no button mark")
	eq(entry.relabel(nil, "Launch"), "LAUNCH")
	eq(entry.word_case("Launch", "\194\172q\194\172 BACK"), "LAUNCH", "a button's mark isn't a word")
	LocalizationManager = { string = function(_, key) return "\194\172E\194\172 SELECT   " end, modifiers = { { modifier = "#mod_reload", value = "\194\172R\194\172" } } }
	local ok, err = pcall(function()
		local select, refresh = entry.with_texts(entry.TEXTS, function()
			return LocalizationManager:string("menu_campaign_select"), LocalizationManager:string(entry.REFRESH_KEY)
		end)
		eq(select, "\194\172E\194\172 LAUNCH   ", "the key guide's Select, while the screen draws")
		eq(refresh, "\194\172R\194\172 REFRESH   ", "and Refresh after it")
		eq(LocalizationManager:string("menu_campaign_select"), "\194\172E\194\172 SELECT   ", "the game's own after")
	end)
	LocalizationManager = nil
	if not ok then error(err, 0) end
end)

test("the_arcade_screen_shows_its_words_only_while_it_draws", function()
	LocalizationManager = { string = function(_, key) return "game:" .. key end }
	local ok, err = pcall(function()
		local a, b, n = entry.with_texts({ menu_campaign = "ARCADE" }, function(x)
			return LocalizationManager:string("menu_campaign"), LocalizationManager:string("menu_campaign_back"), x
		end, 3)
		eq(a, "ARCADE", "a word of the screen's")
		eq(b, "game:menu_campaign_back", "the game's for the rest")
		eq(n, 3, "the function's arguments and answers pass through")
		eq(LocalizationManager:string("menu_campaign"), "game:menu_campaign", "the game's own after")
		local failed = pcall(entry.with_texts, { menu_campaign = "ARCADE" }, function() error("boom") end)
		eq(failed, false, "an error goes on")
		eq(LocalizationManager:string("menu_campaign"), "game:menu_campaign", "and the words go back")
	end)
	LocalizationManager = nil
	if not ok then error(err, 0) end
	eq(entry.with_texts({}, function() return "no game texts" end), "no game texts", "without the game's texts, fn runs as it is")
end)

test("the_pods_get_a_planet_lent_and_the_save_keeps_its_own", function()
	local available = { {}, { current_region = 3, planets = { { name = "b", missions = { { completed = false } } } } } }
	local own = { name = "x", region = 1, enemy = 0, selected_mission_index = 1, missions = { { completed = false } } }
	local save = fake_save({ available_planets = available, current_planet = own })
	eq(entry.lend_planet(save, 1), own, "the player's own planet, on the mission's front")
	local lent = entry.lend_planet(save, 2)
	eq(lent.name, "b", "a planet of the mission's front")
	eq(lent.region, 3)
	eq(lent.missions[1] ~= available[2].planets[1].missions[1], true, "a copy: nothing written into the campaign's missions")
	eq(save.values.current_planet, own, "the save keeps the player's planet")
	local none = fake_save({ available_planets = available })
	eq(entry.lend_planet(none, 1).name, "b", "no planet of the player's: one of the campaign's")
	eq(none.values.current_planet, nil, "and the save still has none")
	eq(entry.lend_planet(fake_save({ available_planets = {} }), 1), nil, "no mission left anywhere")
end)

return T
