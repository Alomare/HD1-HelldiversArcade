-- The galaxy map's Arcade, beside Proving Grounds, on the game's own screen for it.
--
-- The screen of the three fronts (MenuScreenCampaignRegion) gets an ARCADE tab before Proving Grounds.
-- Taking it flies the camera in as Proving Grounds does, onto a second copy of the Proving Grounds
-- screen (MenuScreenProvingGroundsMission) under the state name "survivors_selection": the same planet
-- and camera, the Back and Select buttons and the leaving question, with no markers on the planet. In
-- place of the mission's panel the screen draws three, in the game's panels, list boxes, selection boxes
-- and fonts:
--
--   Game Mode        the arcade's modes; Super Earth Survivors is the first.
--   Parameters       the mode's settings (starting faction, difficulty, planet type), changed with
--                    left and right as the game's option menus do, the difficulty bar's colored
--                    cells under the difficulty, then Refresh and Launch.
--   Mission Preview  the mission those settings make: the map with the planet's name on it, and
--                    the objectives the map has, listed as the game's mission screens list them.
--
-- The screen has one trial, the previewed mission. A changed setting makes the preview over a moment
-- later; Refresh (the button, the reload key, the key guide, or a click) keeps the settings and draws
-- a new map (src/seed.lua's layouts, a new time of day and light). Launch (the button, or the key
-- guide's Launch, the game's Select) picks the mission: it starts the mode's content (opts.start) and
-- leaves the galaxy map with the Survivors seed and a planet lent to the hellpods (src/campaign.lua),
-- and saves no planet. A refused start keeps the galaxy map open. Select on a parameter only moves to
-- Launch. The screen's texts are swapped only while it draws (M.with_texts).
--
-- Survivors is an expansion, and this screen is the way into the content, so every function here is
-- a wrap: Obsidian runs wraps in any lobby, before the content starts. Proving Grounds stays open
-- beside it until then. While the content runs, Obsidian closes Proving Grounds by the state name,
-- which this screen doesn't use.
local rng = obsidian.module("src/rng")
local campaign = obsidian.module("src/campaign")

local M = {}

M.TAB = "survivors_tab"
M.STATE = "survivors_selection"

-- The key guide's Refresh, a text key of the screen's own.
M.REFRESH_KEY = "survivors_refresh"

-- The Proving Grounds screen's words, as the Arcade's. A function takes game(key), the game's own
-- text for a key, and makes the word from it: the key guide's Select reads Launch, with the game's
-- button and spacing.
M.TEXTS = {
	survivors_tab = "ARCADE",
	menu_campaign = "ARCADE",
	campaign_leave_provinggrounds_confirmation = "Leave the ARCADE and go back to the galaxy map?",
	menu_campaign_select = function(game) return M.relabel(game("menu_campaign_select"), "Launch") end,
	[M.REFRESH_KEY] = function(game)
		return M.button_text(game("menu_campaign_select"), game("menu_campaign_back"), M.reload_button())
	end,
}

-- The modes, in the Game Mode panel's order. params: the Parameters rows, by M.choice key.
M.MODES = {
	{
		id = "survivors",
		name = "SUPER EARTH SURVIVORS",
		icon = "icon_faction_superearth_small",
		about = "A roguelite adventure where waves from all Super Earth enemies grow stronger by the minute. Pick up enough samples from kills, and you can choose from a collection of stacking upgrades that empower your Helldiver. Survive for 12 minutes, and you can either extract or keep fighting.",
		params = { "enemy", "difficulty", "environment" },
	},
}

-- Panel and row names, in the case of the game's own labels (M.cased).
M.PANELS = { "GAME MODE", "PARAMETERS", "MISSION PREVIEW" }
M.LABELS = { enemy = "STARTING FACTION", difficulty = "DIFFICULTY", environment = "BIOME" }

-- Planet types: the campaign's five (DifficultySettings.environment_lookup without Proving Grounds).
M.ENVIRONMENTS = 5
M.FACTIONS = 3

-- The parameters, kept while the game runs: each visit opens with the last ones.
M.choice = { mode = 1, enemy = 1, difficulty = 6, environment = 1 }

-- Seconds a changed parameter waits before the preview is made again, so scrolling through the
-- planet types doesn't load each one's map.
M.SETTLE = 0.3

local function g(name) return rawget(_G, name) end

local function is_tab(sub) return type(sub) == "table" and sub.name == M.TAB end

local function tab_index(subs)
	for i, sub in ipairs(subs or {}) do
		if is_tab(sub) then return i end
	end
	return nil
end

local function ours(screen) return type(screen) == "table" and screen.survivors == true end

local function pack(...) return { n = select("#", ...), ... } end

-- fn(...) with the game's text keys in `texts` showing these words, as Obsidian API's ui.with_texts
-- does it. That one is a guarded call, which answers "not_started" to an expansion before the content
-- runs, and the galaxy map draws before then. A word in `texts` may be a function of game(key), the
-- game's own text for a key. Answers what fn answers; an error in fn goes on after.
function M.with_texts(texts, fn, ...)
	local lm = g("LocalizationManager")
	if type(lm) ~= "table" or type(lm.string) ~= "function" then return fn(...) end
	local real = lm.string
	lm.string = function(self, key, ...)
		local own = texts[key]
		if type(own) == "function" then
			local ok, text = pcall(own, function(k) return real(self, k) end)
			if ok and type(text) == "string" then return text end
			return real(self, key, ...)
		end
		if own ~= nil then return own end
		return real(self, key, ...)
	end
	local r = pack(pcall(fn, ...))
	lm.string = real
	if not r[1] then error(r[2], 0) end
	return unpack(r, 2, r.n)
end

-- Words in the case the game writes `sample` in: Title Case when the game's text has small letters,
-- CAPITALS otherwise.
function M.cased(text, sample)
	if type(sample) ~= "string" or not sample:gsub("\194\172.-\194\172", ""):find("%l") then return text:upper() end
	return (text:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

-- The highest difficulty: the game's, as far as the difficulty names and the bar's cells go.
function M.max_difficulty()
	local n = 15
	local ds, cs = g("DifficultySettings"), g("CampaignSettings")
	if type(ds) == "table" and tonumber(ds.max_difficulty) and ds.max_difficulty >= 1 then n = math.floor(ds.max_difficulty) end
	if type(cs) == "table" then
		if type(cs.planet_difficulty_names) == "table" and #cs.planet_difficulty_names > 0 then n = math.min(n, #cs.planet_difficulty_names) end
		local bar = cs.difficulty_bar
		if type(bar) == "table" and type(bar.cells) == "table" and #bar.cells > 0 then n = math.min(n, #bar.cells) end
	end
	return n
end

function M.limits()
	return { enemy = M.FACTIONS, difficulty = M.max_difficulty(), environment = M.ENVIRONMENTS }
end

-- One parameter one step along: factions and planet types go round, the difficulty stops at its ends.
-- True if it changed.
function M.step(choice, key, dir, limits)
	local n, v = limits[key], choice[key]
	if not n or not v then return false end
	local to = v + dir
	if key == "difficulty" then to = math.max(1, math.min(to, n)) else to = (to - 1) % n + 1 end
	if to == v then return false end
	choice[key] = to
	return true
end

-- What the map looks like beyond the parameters: time of day, light and variant as the campaign's
-- planets have them, and one of the seed's layouts.
function M.new_look(r)
	return { time = r:random(1, 4), light = r:random(1, 3), variant = r:random(1, 3), layout = r:random(0, 99999) }
end

-- The mission `choice` and `look` make, as a trial of the Proving Grounds screen: what its map, its
-- camera and its leaving read. make_seed(choice) -> seed is main.lua's. names(seed) -> a name, or nil.
function M.mission(make_seed, choice, look, names)
	local c = {
		time = look.time, light = look.light, environment = choice.environment, variant = look.variant,
		enemy = choice.enemy, difficulty = choice.difficulty, layout = look.layout,
	}
	local s = make_seed(c)
	return {
		survivors = true, unlocked = true, index = 1, seed = s, choice = c, look = look,
		name = (names and names(s)) or "SUPER EARTH SURVIVORS",
		planet = {
			name = "city_superearth", region = 0, seed = s, difficulty = c.difficulty, enemy = c.enemy - 1,
			environment = c.environment - 1, environment_variant = c.variant - 1, shading_environment = c.light - 1,
		},
	}
end

-- A mission with a new look, whose seed isn't `old`: a different map with the same parameters.
function M.reroll(make_seed, choice, r, names, old)
	local mission
	for _ = 1, 32 do
		mission = M.mission(make_seed, choice, M.new_look(r), names)
		if mission.seed ~= old then break end
	end
	return mission
end

-- The Parameters panel's rows: the mode's parameters, then Refresh, then Launch.
function M.rows(mode) return #mode.params + 2 end

-- Moving through the panels, as the game's option menus do. ui: { panel = 1 or 2, mode, row }; rows:
-- the Parameters rows (M.rows), Refresh and Launch last. key: up, down, left, right, prev_panel,
-- next_panel or select. Answers what the key does: "move", "mode" (a mode taken), "change" and a
-- direction, "refresh", "launch", or nil for nothing. Only Select on Launch launches: Select on a
-- parameter moves to Launch.
function M.navigate(ui, key, modes, rows)
	if ui.panel == 1 then
		if key == "up" or key == "down" then
			if modes < 2 then return nil end
			ui.mode = (ui.mode - 1 + (key == "down" and 1 or -1)) % modes + 1
			return "move"
		elseif key == "right" or key == "next_panel" then
			ui.panel = 2
			return "move"
		elseif key == "select" then
			ui.panel = 2
			return "mode"
		end
		return nil
	end
	local refresh, launch = rows - 1, rows
	local button = ui.row >= refresh
	if key == "up" or key == "down" then
		ui.row = (ui.row - 1 + (key == "down" and 1 or -1)) % rows + 1
		return "move"
	elseif key == "prev_panel" or (key == "left" and button) then
		ui.panel = 1
		return "move"
	elseif (key == "left" or key == "right") and not button then
		return "change", key == "left" and -1 or 1
	elseif key == "select" then
		if ui.row == launch then return "launch" end
		if ui.row == refresh then return "refresh" end
		ui.row = launch
		return "move"
	end
	return nil
end

-- A click on what the cursor was over (hover, from the last draw). Answers as M.navigate does, with
-- "pick" for a mode clicked.
function M.click(ui, hover)
	if type(hover) ~= "table" then return nil end
	ui.panel = hover.panel
	if hover.panel == 1 then
		ui.mode = hover.row
		return "pick"
	end
	ui.row = hover.row
	if hover.launch then return "launch" end
	if hover.refresh then return "refresh" end
	if hover.dir then return "change", hover.dir end
	return nil
end

-- The objectives a generated map has, each name once, in the order the map placed them, as the game's
-- mission screens list them (MapWidget.update): the extraction and the drop point aren't listed.
M.UNLISTED = { mission_objective_extract = true, mission_objective_droppoint = true }

function M.objectives(spawn_list)
	local out, seen = {}, {}
	for _, spawn in ipairs(type(spawn_list) == "table" and spawn_list or {}) do
		local list = type(spawn) == "table" and spawn.objectives
		for _, o in ipairs(type(list) == "table" and list or {}) do
			local name = type(o) == "table" and o.name
			if type(name) == "string" and not M.UNLISTED[name] and not seen[name] then
				seen[name] = true
				out[#out + 1] = { name = name, icon = o.icon }
			end
		end
	end
	return out
end

-- A planet as the game's planet screen builds it from the saved list (setup_planets): the list has no
-- region, and counts fronts from 1. The ship stops on a planet without a region, so this is the only
-- form that may become the current planet.
function M.planet_from(front, race, raw)
	local missions = {}
	for i, m in ipairs(raw.missions or {}) do missions[i] = m end
	return {
		position = raw.difficulty, region = front.current_region, enemy = race - 1, name = raw.name, seed = raw.seed,
		difficulty = raw.difficulty, environment = raw.environment, environment_variant = raw.environment_variant,
		shading_environment = raw.shading_environment, missions = missions, reward = raw.reward, is_scanned = raw.is_scanned,
	}
end

-- A current planet saved without its region, as this mod's first version left it, stops the ship in
-- any game, modded or not. Rebuilt from the saved list, or let go when it isn't there. True if changed.
function M.heal_planet(save)
	local current = save:get("current_planet")
	if type(current) ~= "table" or current.region ~= nil then return false end
	local available = save:get("available_planets")
	for race, front in ipairs(type(available) == "table" and available or {}) do
		for _, raw in ipairs(type(front) == "table" and front.planets or {}) do
			if raw.name == current.name then
				local planet = M.planet_from(front, race, raw)
				planet.selected_mission_index = current.selected_mission_index
				save:set("current_planet", planet)
				return true
			end
		end
	end
	save:set("current_planet", nil)
	save:set("next_mission_seed", nil)
	return true
end

-- The planet a Survivors drop lends the hellpods (src/campaign.lua), from the save as it is now: the
-- player's own on the mission's front, or one of the campaign's. front: 1 to 3. nil when there's none.
function M.lend_planet(save, front)
	return campaign.pick(save:get("current_planet"), save:get("available_planets"), front, M.pick_planet)
end

-- A planet of the campaign with a mission left, the home front's first. The mission screen sets the
-- same two fields before it leaves.
function M.pick_planet(available, home)
	if type(available) ~= "table" then return nil end
	local order = { home }
	for race = 1, 3 do
		if race ~= home then order[#order + 1] = race end
	end
	for _, race in ipairs(order) do
		local front = available[race]
		for _, planet in ipairs(type(front) == "table" and front.planets or {}) do
			for i, mission in ipairs(type(planet) == "table" and planet.missions or {}) do
				if mission.completed == false then
					local out = M.planet_from(front, race, planet)
					out.selected_mission_index = i
					return out
				end
			end
		end
	end
	return nil
end

-- A mission is named by its planet, which the loading screen shows too.
local function mission_name(s)
	return g("LocalizationManager"):string(obsidian.module("src/seed").planet_key(s))
end

-- A new roll's seed: the clock, and a count, so two rolls in one second still differ.
local rolls = 0
local function roll_seed()
	rolls = rolls + 1
	return math.floor((os.time() % 100000) * 7 + 1 + rolls * 7919)
end

-- Whether the galaxy map closes on another mission picked: the mission screen's Select (the only way
-- it leaves from there), or a Proving Grounds trial. Every other way out (Back on the fronts, on the
-- first screen, on Proving Grounds) only closes it.
function M.picks_other(screen)
	local state = type(screen) == "table" and type(screen.active_state) == "table" and screen.active_state.name
	if state == "mission" then return true end
	local trial = screen and screen.selected_trial
	return state == "provinggrounds_selection" and type(trial) == "table" and not trial.survivors
end

-- The galaxy map closing with an arcade mission chosen and nothing else picked: the arcade mission stays
-- the next drop. The fronts' Back takes the player's planet and trial out of the save, and the closing
-- map would then let the ship's mission go, so the save gets them back as they were when the map opened
-- and the map leaves them alone.
function M.keep(screen, save)
	save:set("current_planet", screen.current_planet_on_enter)
	save:set("selected_trial", screen.trial_on_enter)
	screen.current_planet = screen.current_planet_on_enter
	screen.selected_trial = nil
	screen.set_current_planet_on_exit = false
end

-- The Refresh button's words, laid out as the game's Select: its spacing, the reload button as the
-- device in use shows it (LocalizationManager's modifiers, which a mod's own words don't go through),
-- and the word in the case the game's Back is in.
-- A word in the case the game's text `sample` writes its words: Title Case when it has small letters,
-- CAPITALS otherwise (a button's mark aside).
function M.word_case(word, sample)
	local plain = type(sample) == "string" and (sample:gsub("\194\172.-\194\172", "")) or ""
	return plain:find("%l") and word or word:upper()
end

function M.button_text(select_text, back_text, button)
	local lead = type(select_text) == "string" and select_text:match("^(%s*)") or ""
	local trail = type(select_text) == "string" and select_text:match("(%s*)$") or ""
	if lead == "" and trail == "" then lead = "   " end
	return lead .. (button and (button .. " ") or "") .. M.word_case("Refresh", back_text) .. trail
end

-- The game's button text with another word: the button's mark and the spacing stay, the word takes
-- the case of the one it replaces: "Select" after the E button's mark, with "Launch", reads "Launch"
-- after the same mark.
function M.relabel(text, word)
	if type(text) ~= "string" then return word:upper() end
	local trail = text:match("(%s*)$")
	local head = text:match("^(.*\194\172%s*)") or text:match("^(%s*)")
	if #head + #trail >= #text then head = text:match("^(%s*)") end
	return head .. M.word_case(word, text) .. trail
end

-- The reload button's mark as the device in use shows it, from LocalizationManager's modifiers.
function M.reload_button()
	local lm = g("LocalizationManager")
	for _, m in ipairs(type(lm) == "table" and lm.modifiers or {}) do
		if m.modifier == "#mod_reload" and type(m.value) == "string" then return m.value end
	end
	return nil
end

local function game_text(key)
	local lm = g("LocalizationManager")
	if type(lm) ~= "table" then return nil end
	local ok, text = pcall(lm.string, lm, key)
	return ok and type(text) == "string" and text or nil
end

local function refresh_text()
	return M.button_text(game_text("menu_campaign_select"), game_text("menu_campaign_back"), M.reload_button())
end

-- The Launch button's word, in the case of the game's Back.
local function launch_text() return M.word_case("Launch", game_text("menu_campaign_back")) end

-- The region screen's camera move to the middle of the map, as enter_pg_menu_selection does it
-- (which Obsidian refuses in a modded game). Its own timer then shows the state, redirected below.
local function fly_in(region)
	local v3, unit = g("Vector3"), g("Unit")
	local offset = region.parent:get_idle_camera_offset("region")
	local from = unit.world_position(region.camera_unit, 0)
	local dir = v3.normalize(v3.zero() - from)
	region.camera_start_position = g("Vector3Aux").box(region.camera_start_position, from - offset)
	region.camera_end_position = g("Vector3Aux").box(region.camera_end_position, (v3.zero() - offset) - dir * 0.2)
	region.camera_start_rotation = g("QuaternionAux").box(region.camera_start_rotation, unit.world_rotation(region.camera_unit, 0))
	region.camera_end_rotation = g("QuaternionAux").box(region.camera_end_rotation, g("Quaternion").look(dir))
	region.enter_provinggrounds_selection_timer = 0.5
	region.camera_interp = 0
	region.camera_interp_multiplier = 1.5
	M.entering = true
	g("MenuScreenBase").play_sound_accept(region.parent, nil, region.user_pad_number)
end

local function on_tab(region)
	local s = type(region) == "table" and region.substate_object
	return s ~= nil and is_tab(s.substates[s.substate_index])
end

local function after_tab_move(region)
	if on_tab(region) and not M.entering then
		region.show_provinggrounds_screen = false
		region.show_leaderboard = false
		fly_in(region)
	end
end

-- The second Proving Grounds screen, made the first time it's needed.
local function survivors_screen(galaxy)
	local screen = galaxy.states[M.STATE]
	if screen then return screen end
	screen = g("MenuScreenProvingGroundsMission")(galaxy)
	screen.name = M.STATE
	screen.survivors = true
	galaxy.states[M.STATE] = screen
	return screen
end

-- fn(...) with the save's "selected_trial" (Proving Grounds' last pick) out of sight: the screen opens
-- on that trial's number, and this one has a single trial.
local function without_saved_trial(fn, ...)
	local save = g("SaveManager")
	if type(save) ~= "table" or type(save.get) ~= "function" then return fn(...) end
	local own, real = rawget(save, "get"), save.get
	rawset(save, "get", function(s, key, ...)
		if key == "selected_trial" then return nil end
		return real(s, key, ...)
	end)
	local r = pack(pcall(fn, ...))
	rawset(save, "get", own)
	if not r[1] then error(r[2], 0) end
	return unpack(r, 2, r.n)
end

-- Picking the mission: the screen sets the campaign's selected trial and leaves. A Survivors one starts
-- the content and becomes the Survivors seed, with a planet lent to the hellpods. The galaxy map leaves
-- holding that planet, which skips the "no planet" way out (it clears the next mission), and saves
-- none: the save keeps the player's own planet, or none (MenuScreenCampaign.on_exit). Without a planet,
-- or with the start refused, the galaxy map stays open on the Arcade screen.
local function take(screen)
	local mission = screen.selected_trial
	screen.selected_trial = nil
	local planet = M.lend_planet(g("SaveManager"), mission.choice.enemy)
	if not planet then
		if M.notify then M.notify("The hellpods need a planet: choose one on the galaxy map first.") end
		return false
	end
	if M.start and not M.start() then return false end
	campaign.lend(planet)
	screen.current_planet = planet
	screen.set_current_planet_on_exit = false
	M.set(mission.seed)
	obsidian.log("arcade: picked " .. tostring(mission.name) .. ", seed " .. tostring(mission.seed) .. ", the hellpods take " .. tostring(planet.name))
	return true
end

-- The screen's state: which panel and rows have the selection, and what the cursor is over.
function M.ui(screen)
	local ui = screen.arcade
	if not ui then
		ui = { panel = 1, mode = M.choice.mode or 1, row = 1, offset = 0, stick = 0 }
		screen.arcade = ui
	end
	return ui
end

local function sound(screen, kind)
	local base = g("MenuScreenBase")
	local fn = type(base) == "table" and base["play_sound_" .. kind]
	if fn then pcall(fn, screen, nil, screen.user_pad_number) end
end

-- The previewed mission made again: from the parameters with the same look, or with a new look
-- (Refresh). The trial keeps the place the camera looks at.
function M.apply(screen, reroll)
	local ui = M.ui(screen)
	ui.pending = nil
	local old = screen.trials and screen.trials[1]
	local mission
	if reroll or not ui.look then
		mission = M.reroll(M.make_seed, M.choice, rng.new(roll_seed()), mission_name, old and old.seed)
	else
		mission = M.mission(M.make_seed, M.choice, ui.look, mission_name)
	end
	ui.look, ui.offset = mission.look, 0
	mission.position = old and old.position
	screen.trials = { mission }
	screen.selected_trial_index, screen.last_selected_trial_index = 1, 1
	if screen.map_widget then pcall(screen.map_widget.set_seed, screen.map_widget, mission.planet.seed, nil) end
	return mission
end

function M.refresh(screen)
	local mission = M.apply(screen, true)
	sound(screen, "accept")
	obsidian.log("arcade: a new map, seed " .. tostring(mission.seed))
end

-- opts: make_seed(choice), set(seed or nil): main.lua's, which choose the next drop; start(): true once
-- Survivors' content runs, false when it was refused; notify(text).
function M.install(opts)
	M.make_seed, M.set, M.start, M.notify, M.chosen = opts.make_seed, opts.set, opts.start, opts.notify, opts.chosen
	local with_texts = M.with_texts

	obsidian.wrap("StateMenu", "on_enter", function(original, self, ...)
		local save = g("SaveManager")
		local ok, healed = pcall(M.heal_planet, save)
		if ok and healed then
			obsidian.log("arcade: repaired the saved planet")
			pcall(save.save, save)
		elseif not ok then
			obsidian.log("arcade: planet repair failed: " .. tostring(healed))
		end
		return original(self, ...)
	end)

	-- The tab, before Proving Grounds. The region screen's own code asks for Proving Grounds by the
	-- second tab's number, which the redirect below turns into ours.
	--
	-- Coming back from the Arcade screen, the region screen takes the way back from Proving Grounds,
	-- which starts its camera over the middle of the map. It knows no other screen of that planet, and
	-- from one it doesn't know it would start where the planet's camera was, far outside the map.
	obsidian.wrap("MenuScreenCampaignRegion", "on_enter", function(original, self, params, from, ...)
		if from == M.STATE then from = "provinggrounds_selection" end
		original(self, params, from, ...)
		M.entering = false
		local subs = self.substate_object and self.substate_object.substates
		if type(subs) == "table" and not tab_index(subs) then table.insert(subs, 2, { name = M.TAB }) end
	end)

	obsidian.wrap("MenuScreenBase", "draw_substate_menu_options", function(original, self, ...)
		if type(self) ~= "table" or not tab_index(self.substates) then return original(self, ...) end
		return with_texts(M.TEXTS, original, self, ...)
	end)

	obsidian.wrap("MenuScreenCampaignRegion", "update_selection", function(original, self, ...)
		original(self, ...)
		after_tab_move(self)
	end)
	obsidian.wrap("MenuScreenCampaignRegion", "update_selection_cursor", function(original, self, ...)
		original(self, ...)
		after_tab_move(self.parent)
	end)

	-- On the way in, the region screen takes no input, as it doesn't for Proving Grounds.
	obsidian.wrap("MenuScreenCampaignRegion", "handle_input", function(original, self, input, ...)
		if M.entering then return end
		if on_tab(self) and (input.select or input.select_mouse) and not self.substate_object.substate_index_cursor then
			fly_in(self)
			return
		end
		return original(self, input, ...)
	end)

	obsidian.wrap("MenuScreenCampaign", "show_state", function(original, self, name, ...)
		if name == "provinggrounds_selection" and (M.entering or on_tab(self.states and self.states.region)) then
			M.entering = false
			survivors_screen(self)
			return original(self, M.STATE, ...)
		end
		return original(self, name, ...)
	end)

	-- The screen: its trial is the previewed mission, it has one tab (so no tab row), and no Proving
	-- Grounds leaderboard.
	obsidian.wrap("MenuScreenProvingGroundsMission", "on_enter", function(original, self, ...)
		if not ours(self) then return original(self, ...) end
		local state = self.parent.parent
		local backend = state.trials_from_backend
		state.trials_from_backend = nil
		self.arcade = nil
		local ok, err = pcall(without_saved_trial, original, self, ...)
		state.trials_from_backend = backend
		if not ok then error(err, 0) end
		self.substate_object.substates = { { name = M.TAB } }
		self.substate_object.substate_index = 1
	end)

	obsidian.wrap("MenuScreenProvingGroundsMission", "generate_trials", function(original, self, ...)
		if not ours(self) then return original(self, ...) end
		local mission = M.reroll(M.make_seed, M.choice, rng.new(roll_seed()), mission_name, nil)
		M.ui(self).look = mission.look
		self.trials = { mission }
	end)

	-- The camera frames the middle of Proving Grounds' places, as the game does, and none of them
	-- gets a marker.
	obsidian.wrap("MenuScreenProvingGroundsMission", "setup_trial_positions", function(original, self, ...)
		if not ours(self) then return original(self, ...) end
		M.place(self)
	end)

	obsidian.wrap("MenuScreenProvingGroundsMission", "draw_trial_markers", function(original, self, ...)
		if not ours(self) then return original(self, ...) end
	end)

	-- A changed parameter makes the preview again once it has settled, before the screen draws.
	obsidian.wrap("MenuScreenProvingGroundsMission", "update", function(original, self, dt, ...)
		if not ours(self) then return original(self, dt, ...) end
		local ui = M.ui(self)
		if ui.pending then
			ui.pending = ui.pending - (tonumber(dt) or 0)
			if ui.pending <= 0 then
				local ok, err = pcall(M.apply, self)
				if not ok then obsidian.log("arcade: the preview failed: " .. tostring(err)) end
			end
		end
		return with_texts(M.TEXTS, M.update, self, original, dt, ...)
	end)

	-- Input: the game's Back (and the leaving question) and Select; the panels for the rest.
	obsidian.wrap("MenuScreenProvingGroundsMission", "handle_input", function(original, self, input, ...)
		if not ours(self) or type(input) ~= "table" then return original(self, input, ...) end
		local dialog = self.confirmation_dialog
		if dialog and dialog:is_active() then return original(self, input, ...) end
		local base = g("MenuScreenBase")
		base.handle_input_cursor(self, input, true)
		if input.back or base.was_text_button_clicked(self, input, "back") then return M.back(self, original) end
		if base.was_text_button_clicked(self, input, "select") then return M.start_mission(self, original) end
		M.handle(self, input, base, original)
		base.reset_clickable_buttons(self)
	end)

	obsidian.wrap("MenuScreenProvingGroundsMission", "show_mission_info", function(original, self, gui, z, dt)
		if not ours(self) then return original(self, gui, z, dt) end
		M.draw(self, gui, z, dt)
	end)

	obsidian.wrap("MenuScreenCampaign", "draw_provinggrounds_mini_leaderboard", function(original, self, ...)
		if ours(self.active_state) then return end
		return original(self, ...)
	end)

	obsidian.wrap("MenuScreenCampaign", "update", function(original, self, ...)
		if not ours(self.active_state) then return original(self, ...) end
		return with_texts(M.TEXTS, original, self, ...)
	end)

	-- Leaving the galaxy map: with a Survivors mission, it becomes the next drop. With a campaign mission
	-- or a Proving Grounds trial, the next drop is that one. Closed any other way, the next drop stays
	-- what it was: an arcade mission chosen before stays chosen.
	obsidian.wrap("MenuScreenCampaign", "exit", function(original, self, ...)
		if ours(self.active_state) and type(self.selected_trial) == "table" and self.selected_trial.survivors then
			if not take(self) then return end
		elseif M.picks_other(self) then
			if M.set then M.set(nil) end
		elseif M.chosen and M.chosen() then
			local ok, err = pcall(M.keep, self, g("SaveManager"))
			if not ok then obsidian.log("arcade: the closing map didn't keep the arcade mission: " .. tostring(err)) end
			-- The ship goes back to the arcade mission's planet.
			M.set(M.chosen())
		end
		return original(self, ...)
	end)
end

-- Back: the game's own, which asks before leaving. The game reads the question's words as Back is
-- pressed (MenuScreenProvingGroundsMission.handle_input), outside the draw, so the Arcade's words go in
-- here too, or the question would name Proving Grounds.
function M.back(screen, original)
	return M.with_texts(M.TEXTS, original, screen, { back = true })
end

-- Launch: the mission picked the game's way, its Select with the trial (MenuScreenProvingGroundsMission
-- .handle_input sets the galaxy map's selected trial and calls its exit, where take() starts the
-- content and lends the planet). A parameter still settling goes into the mission first.
function M.start_mission(screen, original)
	local ui = M.ui(screen)
	if ui.pending then M.apply(screen) end
	-- The hellpods' planet and the start are asked before the game's own pick, which tells the other
	-- players: a refused start then leaves the screen as it was, for everyone.
	local trial = screen.trials and screen.trials[screen.selected_trial_index or 1]
	if trial and trial.choice and not M.lend_planet(g("SaveManager"), trial.choice.enemy) then
		if M.notify then M.notify("The hellpods need a planet: choose one on the galaxy map first.") end
		return
	end
	if M.start and not M.start() then return end
	return original(screen, { select = true })
end

-- The game's update, then the key guide's Refresh after its Back and Launch (the game's Select), where
-- the game draws its guide: not with the leaving question open.
function M.update(screen, original, dt, ...)
	local r = pack(original(screen, dt, ...))
	local dialog = screen.confirmation_dialog
	local asking = dialog and dialog.is_active and dialog:is_active()
	if screen.mission_level and not screen.show_leaderboard and not asking then
		local ok, err = pcall(M.draw_guide, screen)
		if not ok and not M.guide_failed then
			M.guide_failed = true
			obsidian.log("arcade: the key guide's Refresh failed: " .. tostring(err))
		end
	end
	return unpack(r, 1, r.n)
end

function M.draw_guide(screen)
	local galaxy, base = screen.parent, g("MenuScreenBase")
	local gui = galaxy.gui_manager
	gui:begin_layout(g("Vector3")(galaxy.button_info_x, galaxy.button_info_y, 0), nil, "left", "bottom")
	local f = g("FontSettings").fonts.body_large
	gui:begin_template({ to_upper_case = false, color = g("Color")(255, 255, 255, 255), font_name = f.class, font_size = f.font_size, anchor = g("Vector2")(0, 0) })
	local ok, err = pcall(function()
		-- After the game's buttons, as the game adds each one's width.
		local lm = g("LocalizationManager")
		local x = gui:get_text_bounds(lm:string("menu_campaign_back")) + gui:get_text_bounds(lm:string("menu_campaign_select"))
		if screen.user_pad_number ~= rawget(_G, "KEYBOARD_MOUSE_PAD_NUMBER") then x = x + gui:get_text_bounds(lm:string("menu_loadout_scroll")) end
		base.check_and_draw_clickable_text_button(screen, gui, M.REFRESH_KEY, "refresh", g("Vector3")(x, 0, 990))
	end)
	gui:end_template()
	gui:end_layout()
	if not ok then error(err, 0) end
end

local function menu_key(input)
	if input.up then return "up" end
	if input.down then return "down" end
	if input.left then return "left" end
	if input.right then return "right" end
	if input.left_shoulder then return "prev_panel" end
	if input.right_shoulder or input.loadout_favorites_right_pressed then return "next_panel" end
	if input.select then return "select" end
	return nil
end

-- The panels' input: the selection, the parameters, Refresh, Launch, and the objective list's
-- scrolling. original: the game's handle_input, which takes the mission.
function M.handle(screen, input, base, original)
	local ui = M.ui(screen)
	local mode = M.MODES[ui.mode] or M.MODES[1]
	local act, dir
	if input.reload_pressed or base.was_text_button_clicked(screen, input, "refresh") then
		act = "refresh"
	elseif input.select_mouse then
		local arrow = base.get_clicked_scroll_button(screen, input)
		if arrow then
			ui.scroll = arrow == "scroll_up" and -20 or 20
		else
			act, dir = M.click(ui, ui.hover)
		end
	else
		local key = menu_key(input)
		if key then act, dir = M.navigate(ui, key, #M.MODES, M.rows(mode)) end
	end
	if input.scroll_up == 1 and ui.over_list then ui.scroll = -20 end
	if input.scroll_down == 1 and ui.over_list then ui.scroll = 20 end
	local look = input.look
	ui.stick = (look and g("Vector3").length(look) > 0.1) and look.y or 0

	if act == "move" then
		sound(screen, "scroll")
	elseif act == "mode" or act == "pick" then
		M.choice.mode = ui.mode
		sound(screen, "accept")
	elseif act == "change" then
		local key = mode.params[ui.row]
		if key and M.step(M.choice, key, dir, M.limits()) then
			ui.pending = M.SETTLE
			sound(screen, "scroll")
		else
			sound(screen, "invalid")
		end
	elseif act == "refresh" then
		M.refresh(screen)
	elseif act == "launch" then
		M.start_mission(screen, original)
	end
end

-- Where the camera looks: the middle of Proving Grounds' places, worked out as the game does it
-- (MenuScreenProvingGroundsMission.setup_trial_positions), without their markers.
function M.place(screen)
	local unit, vec = g("Unit"), g("Vector3")
	local centre, n = vec(0, 250, 0), 0
	for _, u in ipairs(g("Level").units(screen.mission_level)) do
		if unit.is_a(u, "gameobjects/mission_marker") and unit.get_data(u, "name") == "provinggrounds" then
			centre = centre + unit.world_position(u, 0)
			n = n + 1
		end
	end
	centre = centre / math.max(n, 1)
	screen.mission_center = g("Vector3Aux").box({}, centre)
	for _, trial in ipairs(screen.trials or {}) do trial.position = { x = centre.x, y = centre.y, z = centre.z } end
end

-- Drawing. The panels sit where the game's mission panel does (bottom right, 96 from the edges) and
-- to the left of it, in the 1280 by 720 the galaxy map lays out in, with even gaps between them.

M.LAYOUT = { width = 1280, left = 96, right = 96, y = 106, h = 490, gap = 16, mode_w = 300, param_w = 356, preview_w = 400 }

-- The panels' left edges, from the left of the 1280. The preview is drawn from the right edge, as the
-- game draws its mission panel, which puts it at the third.
function M.panel_x(L)
	local modes = L.left
	local params = modes + L.mode_w + L.gap
	return modes, params, params + L.param_w + L.gap
end

M.ROW = 32 -- a list box row, as the game's lists draw them
M.STEP = 37 -- from one list row to the next
M.LAUNCH_H = 40 -- the Launch button, a little taller than a row

-- The Parameters panel's rows, from the panel's content top (below the heading) and bottom: each
-- parameter's label and selector, and at the bottom Refresh with Launch under it. bars: { [row] =
-- height } for a row with a bar under its selector (the difficulty's), which takes that room more.
M.BAR_GAP = 6 -- between a selector and the bar under it
function M.params_layout(top, bottom, count, text_size, bars)
	local rows = {}
	local above = top - 4 + 26 - text_size -- so the first label sits 4 under the top
	for i = 1, count do
		local label = above - 26
		local r = { label = label, box = label - 8 - M.ROW }
		local bh = bars and bars[i]
		if bh then r.bar, r.bar_h = r.box - M.BAR_GAP - bh, bh end
		rows[i] = r
		above = r.bar or r.box
	end
	local launch = bottom + 16
	return { rows = rows, launch = launch, refresh = launch + M.LAUNCH_H + 10 }
end

-- The preview's map box: the list boxes' width, and tall enough for a map turned 45 degrees. The map
-- widget fits a map's longer side in 220 times the scale and turns it, so a square map stands
-- 220 * sqrt(2) * scale tall, the most any map does.
M.MAP = { w = 360, h = 300, scale = 0.95 }

function M.map_extent(scale) return 220 * math.sqrt(2) * scale end

-- The Mission Preview panel, from the content top and the panel's bottom: the map, with the planet's
-- name in its top left corner, and the objective list in the room left. y of each is its bottom.
M.NAME_INSET = 8 -- the name's distance from the map's top left corner
function M.preview_layout(top, bottom, text_size)
	local map_top = top - 4
	local map_bottom = map_top - M.MAP.h
	local ceiling = map_bottom - 12
	local floor = bottom + 12
	return { name = map_top - M.NAME_INSET - text_size, map_top = map_top, map_y = map_top - M.MAP.h / 2, map_bottom = map_bottom,
		ceiling = ceiling, floor = floor, room = ceiling - floor }
end

-- The objective list's columns, `w` wide in all: the rows across all of it when they fit, or beside a
-- column of their own on the right for the scroll arrows when they don't. Answers { list_w, most (how
-- far the list scrolls), arrow_x (from the list's left) }.
M.ARROW = 28
function M.list_columns(count, room, w)
	local most = M.list_overflow(count, room)
	if most == 0 then return { list_w = w, most = 0 } end
	return { list_w = w - M.ARROW - 6, most = most, arrow_x = w - M.ARROW }
end

local function v3(x, y, z) return g("Vector3")(x, y, z or 0) end
local function v2(x, y) return g("Vector2")(x, y) end
local function rgba(a, r, gr, b) return g("Color")(a, r, gr, b) end
local function say(key) return g("LocalizationManager"):string(key) end
local function font(name) return g("FontSettings").fonts[name] end

-- The game's menu colours: white for values and the selection, its light gray for the names of
-- options off the selection, its yellow for buttons under the cursor. SHADE darkens the parameter
-- selectors' list boxes, so they stand apart from the panel.
local WHITE, LABEL, YELLOW, SHADE = { 255, 255, 255, 255 }, { 255, 200, 200, 200 }, { 255, 240, 175, 80 }, { 255, 100, 100, 100 }
local function color(c, a) return rgba(a or c[1], c[2], c[3], c[4]) end

local function template(name, c)
	local f = font(name or "body_large")
	return { to_upper_case = false, color = color(c or WHITE), font_name = f.class, font_size = f.font_size, anchor = v2(0, 0) }
end

local function width(gui, text) return (gui:get_text_bounds(text)) end

local function over(screen, gui, x, y, w, h)
	return g("MenuScreenBase").is_box_selected_by_cursor(screen, gui, v3(x, y, 0), v2(w, h)) == true
end

local function blink(screen) return 200 - 80 * (screen.selection_blink or 0) end

-- A line cut from the panel's border (basicbox_01), as the game draws the map's frame. draw_rect
-- doesn't follow a right-aligned layout, and ran a rule across the next panel.
local function edge(gui, x, y, z, w, h, c)
	gui:draw_texture("basicbox_01", v3(x, y, z), v2(w, h), "uv", { v2(2 / 16, 1 - 1 / 256), v2(1 - 2 / 16, 1) }, "color", c)
end

local function frame(gui, x, y, w, h, z, c, t)
	edge(gui, x, y, z, w, t, c)
	edge(gui, x, y + h - t, z, w, t, c)
	edge(gui, x, y + t, z, t, h - 2 * t, c)
	edge(gui, x + w - t, y + t, z, t, h - 2 * t, c)
end

-- A line of text that fits `max`: scrolled while selected, cut with "..." otherwise, as the game's
-- lists draw names.
local function line(screen, gui, x, y, z, text, max, scroll, dt)
	local ok = pcall(screen.draw_selection_scroll, screen, gui, z, v2(x, y), text, max, scroll, dt, true, 20)
	if not ok then gui:draw_text(text, v3(x, y, z)) end
end

local function wrapped(gui, text, max)
	local ok, lines = pcall(gui.get_wrapped_lines, gui, text, max)
	if ok and type(lines) == "table" then return lines end
	return { text }
end

-- A panel's name at its top, where the game names a mission, over a thin rule.
local function heading(gui, x, y, w, h, z, text)
	local f = font("body_large")
	gui:begin_template(template("body_large"))
	gui:draw_text(text, v3(x + w / 2 - width(gui, text) / 2, y + h - 7 - f.font_size, z + 4))
	edge(gui, x + 12, y + h - 14 - f.font_size, z + 4, w - 24, 1, rgba(80, 255, 255, 255))
	gui:end_template()
	return y + h - 22 - f.font_size
end

-- A list box row at z, with an icon square when there's an icon. Layers above it, as the game's lists
-- stack them: the selection box (z + 1), icons (z + 2), text (z + 3).
local function row_box(gui, x, y, w, z, icon, tint, h)
	h = h or M.ROW
	local c = color(tint or WHITE)
	if icon then
		gui:draw_texture("listbox_01", v3(x, y, z), v2(h, h), "color", c)
		gui:draw_texture("listbox_01", v3(x + h + 2, y, z), v2(w - h - 2, h), "color", c)
		gui:draw_texture(icon, v3(x + 1, y, z + 2), v2(h, h))
	else
		gui:draw_texture("listbox_01", v3(x, y, z), v2(w, h), "color", c)
	end
end

-- The game's selection box, under the row's text as the game's option menus draw it: blinking on the
-- selected row, the mouse-over box under the cursor, and a faint one on a choice whose panel doesn't
-- have the selection.
local function highlight(screen, gui, x, y, w, z, state, h)
	local at, size = v3(x, y, z), v2(w, h or M.ROW)
	if state == "selected" then
		gui:draw_texture("selectionbox_01", at, size, "color", rgba(blink(screen), 255, 255, 255))
	elseif state == "hovered" then
		gui:draw_texture("selectionbox_mouseover_01", at, size, "color", rgba(blink(screen), 255, 255, 255))
	elseif state == "faint" then
		gui:draw_texture("selectionbox_01", at, size, "color", rgba(60, 255, 255, 255))
	end
end

local function state_of(selected, hovered, faint)
	return (selected and "selected") or (hovered and "hovered") or (faint and "faint") or nil
end

function M.draw_modes(screen, gui, z, dt, ui, sample)
	local L = M.LAYOUT
	local x = M.panel_x(L)
	local y, w, h = L.y, L.mode_w, L.h
	screen:draw_main_panel(gui, z, false, v3(x, y, z), h, w, "left", "bottom", 1)
	gui:begin_layout(nil, nil, "left", "bottom")
	local top = heading(gui, x, y, w, h, z, M.cased(M.PANELS[1], sample))
	local bx, bw, hover = x + 12, w - 24, nil
	local ry = top
	for i, mode in ipairs(M.MODES) do
		ry = top - 4 - M.ROW - (i - 1) * M.STEP
		local chosen = ui.mode == i
		local selected = chosen and ui.panel == 1
		gui:begin_template(template("body", WHITE))
		local hovered = over(screen, gui, bx, ry, bw, M.ROW)
		if hovered then hover = { panel = 1, row = i } end
		row_box(gui, bx, ry, bw, z + 1, mode.icon)
		highlight(screen, gui, bx, ry, bw, z + 2, state_of(selected, hovered, chosen))
		line(screen, gui, bx + 43, ry + 9, z + 4, mode.name, bw - 52, selected, dt)
		gui:end_template()
	end
	local mode = M.MODES[ui.mode]
	if mode and mode.about then
		local body = font("body")
		gui:begin_template(template("body", WHITE))
		local ty = ry - 16 - body.font_size
		for _, text in ipairs(wrapped(gui, mode.about, bw - 8)) do
			gui:draw_text(text, v3(bx + 4, ty, z + 4))
			ty = ty - (body.line_height or body.font_size) - (body.height_spacing or 4)
		end
		gui:end_template()
	end
	gui:end_layout()
	return hover
end

local function faction_name(i) return g("DifficultySettings").enemy_lookup[i] end

-- A parameter's value as the game names it, and the icon beside it.
function M.value_of(key, v)
	if key == "enemy" then
		local name = faction_name(v)
		return say("campaign_planet_race_" .. name), "icon_faction_" .. name .. "_small"
	elseif key == "difficulty" then
		return say(g("CampaignSettings").planet_difficulty_names[v])
	elseif key == "environment" then
		return say("campaign_planet_environment_" .. g("DifficultySettings").environment_lookup[v])
	end
	return tostring(v)
end

-- The game's difficulty bar (MenuScreenCampaignMission.show_mission_info), its colored cells only: the
-- cells up to the level, from the left of a bar centred on cx, with the bottom at y.
local function difficulty_bar(gui, cx, y, z, level)
	local bar = g("CampaignSettings").difficulty_bar
	local size = v2(bar.size[1], bar.size[2])
	local cells = bar.cells
	level = math.max(1, math.min(level, #cells))
	local x = cx - size.x / 2
	local right = cells[level].x + cells[level].width
	gui:draw_texture("bar_difficulty", v3(x + cells[1].x, y, z), v2(right - cells[1].x, size.y), "uv", { v2(cells[1].x / size.x, 0.5), v2(right / size.x, 1) })
end

-- The difficulty bar's height, or nil without the game's settings for it.
local function bar_height()
	local cs = g("CampaignSettings")
	local bar = type(cs) == "table" and cs.difficulty_bar
	return type(bar) == "table" and type(bar.size) == "table" and bar.size[2] or nil
end

-- Refresh: a list box button, white, yellow under the cursor as the game's text buttons are.
local function draw_refresh(screen, gui, bx, ry, bw, z, selected)
	gui:begin_template(template("body_large"))
	local hot = over(screen, gui, bx, ry, bw, M.ROW)
	row_box(gui, bx, ry, bw, z + 1)
	highlight(screen, gui, bx, ry, bw, z + 2, state_of(selected, hot))
	local text = refresh_text():match("^%s*(.-)%s*$")
	gui:draw_text(text, v3(bx + bw / 2 - width(gui, text) / 2, ry + 8, z + 4), "color", color((hot and not selected) and YELLOW or WHITE))
	gui:end_template()
	return hot
end

-- Launch: taller, framed in the game's yellow with its word in yellow; selected, the selection box
-- under it and the frame blinking as the game's outline does, the word in white.
local function draw_launch(screen, gui, bx, ry, bw, z, selected)
	local bh = M.LAUNCH_H
	gui:begin_template(template("body_large"))
	local hot = over(screen, gui, bx, ry, bw, bh)
	row_box(gui, bx, ry, bw, z + 1, nil, nil, bh)
	highlight(screen, gui, bx, ry, bw, z + 2, state_of(selected, hot), bh)
	local a = selected and (255 - 120 * (screen.selection_blink or 0)) or (hot and 255 or 200)
	frame(gui, bx, ry, bw, bh, z + 3, color(YELLOW, a), (selected or hot) and 2 or 1)
	local text = launch_text()
	gui:draw_text(text, v3(bx + bw / 2 - width(gui, text) / 2, ry + 12, z + 4), "color", color(selected and WHITE or YELLOW))
	gui:end_template()
	return hot
end

function M.draw_params(screen, gui, z, dt, ui, sample)
	local L = M.LAYOUT
	local _, x = M.panel_x(L)
	local y, w, h = L.y, L.param_w, L.h
	screen:draw_main_panel(gui, z, false, v3(x, y, z), h, w, "left", "bottom", 1)
	gui:begin_layout(nil, nil, "left", "bottom")
	local top = heading(gui, x, y, w, h, z, M.cased(M.PANELS[2], sample))
	local mode = M.MODES[ui.mode] or M.MODES[1]
	local body = font("body")
	local bx, bw, hover = x + 12, w - 24, nil
	-- The difficulty's selector has the difficulty bar under it.
	local bars, bh = {}, bar_height()
	for i, key in ipairs(mode.params) do
		if key == "difficulty" then bars[i] = bh end
	end
	local P = M.params_layout(top, y, #mode.params, body.font_size, bars)
	for i, key in ipairs(mode.params) do
		local ly, ry = P.rows[i].label, P.rows[i].box
		local selected = ui.panel == 2 and ui.row == i
		gui:begin_template(template("body", selected and WHITE or LABEL))
		gui:draw_text(M.cased(M.LABELS[key] or key, sample), v3(bx + 2, ly, z + 4))
		gui:end_template()
		gui:begin_template(template("body_large", WHITE))
		local hot_left = over(screen, gui, bx, ry, bw / 2, M.ROW)
		local hot_right = not hot_left and over(screen, gui, bx + bw / 2, ry, bw / 2, M.ROW)
		if hot_left or hot_right then hover = { panel = 2, row = i, dir = hot_left and -1 or 1 } end
		row_box(gui, bx, ry, bw, z + 1, nil, SHADE)
		highlight(screen, gui, bx, ry, bw, z + 2, state_of(selected, hot_left or hot_right))
		local text, icon = M.value_of(key, M.choice[key])
		local tw = width(gui, text)
		local iw = icon and 30 or 0
		local tx = bx + bw / 2 - (tw + iw) / 2
		if icon then gui:draw_texture(icon, v3(tx, ry + 3, z + 3), v2(26, 26)) end
		gui:draw_text(text, v3(tx + iw, ry + 8, z + 4))
		local a = (selected or hot_left or hot_right) and 255 or 160
		gui:draw_texture("icon_arrow_01", v3(bx + 2, ry, z + 4), v2(32, 32), "color", color(hot_left and YELLOW or WHITE, a))
		gui:draw_texture("icon_arrow_01", v3(bx + bw - 34, ry, z + 4), v2(32, 32), "color", color(hot_right and YELLOW or WHITE, a), "uv", { v2(1, 0), v2(0, 1) })
		if P.rows[i].bar then difficulty_bar(gui, bx + bw / 2, P.rows[i].bar, z + 3, M.choice.difficulty) end
		gui:end_template()
	end
	-- Refresh, and Launch under it, at the bottom.
	local rows = M.rows(mode)
	if draw_refresh(screen, gui, bx, P.refresh, bw, z, ui.panel == 2 and ui.row == rows - 1) then
		hover = { panel = 2, row = rows - 1, refresh = true }
	end
	if draw_launch(screen, gui, bx, P.launch, bw, z, ui.panel == 2 and ui.row == rows) then
		hover = { panel = 2, row = rows, launch = true }
	end
	gui:end_layout()
	return hover
end

-- An objective's line as the game's mission screens write it: Exterminate with its count.
function M.objective_text(name, seed)
	local lm = g("LocalizationManager")
	local unit = ({ mission_objective_exterminate = "gameobjects_spec/generic_marker_exterminate",
		mission_objective_genocide = "gameobjects_spec/generic_marker_genocide" })[name]
	if unit then
		local ok, text = pcall(function()
			local p = g("DifficultySettings").get_lookup_mission_params(seed)
			local count = g("LuaSettingsManager"):get_settings_by_unit_path(unit).objective_info.enemies_to_kill[p.enemy][p.difficulty]
			return lm:string_format(name, "#AMOUNT", count)
		end)
		if ok and type(text) == "string" then return text end
	end
	return lm:string(name)
end

-- The preview's objectives: the generated level's, or the map widget's own list when the level has
-- none to read.
local function preview_objectives(widget)
	if not widget then return {} end
	local ok, level = pcall(widget.get_generated_level, widget)
	local list = M.objectives(ok and type(level) == "table" and level.spawn_list or nil)
	if #list > 0 then return list end
	local okm, known = pcall(widget.get_mission_objectives, widget)
	if okm and type(known) == "table" then
		for name, o in pairs(known) do
			if type(name) == "string" and not M.UNLISTED[name] then list[#list + 1] = { name = name, icon = type(o) == "table" and o.icon or nil } end
		end
		table.sort(list, function(a, b) return a.name < b.name end)
	end
	return list
end

-- How far the objective list scrolls: `count` rows in `room`. 0 when they fit.
function M.list_overflow(count, room)
	return math.max(0, count * M.STEP - 5 - room)
end

-- The previewed mission, as the game's mission panel (show_mission_info) shows one (M.preview_layout):
-- the map with the planet's name in its top left corner, and under it the objectives in the game's
-- list boxes, scrolled as the game's are when they don't fit, with the scroll arrows in a column of
-- their own beside them.
function M.draw_preview(screen, gui, z, dt, ui, sample)
	local L = M.LAYOUT
	local m = screen.trials and screen.trials[screen.selected_trial_index or 1]
	local body = font("body")
	local w, h = L.preview_w, L.h
	local p = { x = -L.right - w, y = L.y }
	screen:draw_main_panel(gui, z, false, v3(p.x, p.y, z), h, w, "right", "bottom", 1)
	gui:begin_layout(nil, nil, "right", "bottom")
	local top = heading(gui, p.x, p.y, w, h, z, M.cased(M.PANELS[3], sample))
	ui.over_list = false
	if m then
		local P = M.preview_layout(top, p.y, body.font_size)
		local x, lw = p.x + (w - M.MAP.w) / 2, M.MAP.w
		if screen.map_widget then
			screen.map_widget:update(gui, dt, z + 10, v3(p.x + w / 2, P.map_y, 0), M.MAP.scale, v2(M.MAP.w, M.MAP.h), "right", "bottom")
		end
		-- The planet's name over the map, with the game's drop shadow so it reads on any map.
		gui:begin_template(template("body", WHITE))
		local nx = x + M.NAME_INSET
		gui:draw_text(m.name, v3(nx + 1, P.name - 1, z + 39), "color", rgba(200, 0, 0, 0))
		gui:draw_text(m.name, v3(nx, P.name, z + 40))
		gui:end_template()
		gui:begin_template(template())
		-- The objectives, in a list box each.
		local list = preview_objectives(screen.map_widget)
		local floor, ceiling, room = P.floor, P.ceiling, P.room
		local cols = M.list_columns(#list, room, lw)
		local most, rw = cols.most, cols.list_w
		ui.offset = math.max(0, math.min((ui.offset or 0) + (ui.scroll or 0) - (ui.stick or 0) * (tonumber(dt) or 0) * 60, most))
		ui.scroll = nil
		ui.over_list = over(screen, gui, x, floor, lw, room)
		if most > 0 then gui:begin_clip_view(v2(x + rw, floor), v2(rw, room)) end
		for i, o in ipairs(list) do
			local ry = ceiling - M.ROW - (i - 1) * M.STEP + ui.offset
			gui:draw_texture("listbox_01", v3(x, ry, z), v2(M.ROW, M.ROW))
			gui:draw_texture("listbox_01", v3(x + 34, ry, z), v2(rw - 34, M.ROW))
			if o.icon then gui:draw_texture(o.icon, v3(x + 1, ry, z + 1), v2(M.ROW, M.ROW)) end
			line(screen, gui, x + 43, ry + 8, z + 4, M.objective_text(o.name, m.seed), rw - 50, false, dt)
		end
		if most > 0 then
			gui:end_clip_view()
			-- The arrows at the top and the bottom of their column, the list's height apart.
			local base = g("MenuScreenBase")
			local arrows = rgba(255 - 100 * (screen.arrow_blink or 0), 255, 255, 255)
			local ax, size = x + cols.arrow_x, v2(M.ARROW, M.ARROW)
			if ui.offset > 0 then pcall(base.check_and_draw_scroll_button, screen, gui, "scroll_up", v3(ax, ceiling - M.ARROW, z + 4), size, math.rad(90), arrows) end
			if ui.offset < most then pcall(base.check_and_draw_scroll_button, screen, gui, "scroll_down", v3(ax, floor, z + 4), size, math.rad(-90), arrows) end
		end
		gui:end_template()
	end
	gui:end_layout()
end

-- The three panels, and the cursor taking the row it moves onto, as the game's menus do.
function M.draw(screen, gui, z, dt)
	local ui = M.ui(screen)
	local ok, sample = pcall(say, "campaign_mission_difficulty")
	sample = ok and sample or nil
	local hover = M.draw_modes(screen, gui, z, dt, ui, sample)
	hover = M.draw_params(screen, gui, z, dt, ui, sample) or hover
	M.draw_preview(screen, gui, z, dt, ui, sample)
	local cp = screen.cursor_position
	if type(cp) == "table" then
		local moved = ui.cx ~= nil and (cp.x ~= ui.cx or cp.y ~= ui.cy)
		ui.cx, ui.cy = cp.x, cp.y
		if moved and hover then
			local same = hover.panel == ui.panel and (hover.panel == 1 and hover.row == ui.mode or hover.panel == 2 and hover.row == ui.row)
			if not same then
				ui.panel = hover.panel
				if hover.panel == 1 then ui.mode = hover.row else ui.row = hover.row end
				sound(screen, "scroll")
			end
		end
	end
	ui.hover = hover
end

return M
