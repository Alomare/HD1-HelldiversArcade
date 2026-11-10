-- Survivors as an Obsidian expansion: main.lua started against a fake loader and a fake Obsidian API
-- that records every call, then the content started and ended the way Obsidian does it.
local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function read(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	return text
end

-- Obsidian API's free calls (ObsidianAPI/main.lua, 1.17.0): the ones an expansion may make before the
-- content starts. Every other function of these tables answers "not_started" until then. The tables
-- left out (data, catalog, vehicles, lobby, map, audio, music, mod_settings) aren't guarded.
local FREE = {
	game = { "state", "state_name", "in_mission", "on_ship", "is_host", "lobby", "alone", "me", "avatar", "my_unit", "component",
		"all_avatars", "box", "unbox", "master", "masters", "slaves", "forfeit_progress", "hold_progress", "after", "global" },
	effects = { "define", "get", "is_on", "clear", "active" },
	edits = { "value", "table_value", "original", "list", "count", "revert", "revert_where", "table_changed", "revert_table", "revert_all" },
	console = { "denied", "commands" },
	world = { "shading", "flash", "cursor", "ahead", "raycast", "clear_decals" },
	player = { "lives" },
	gear = {},
	stratagems = {},
	enemies = { "available", "list", "count", "carried", "room", "info", "nearest", "near", "max_enemies", "waves" },
	mission = { "objectives", "params" },
	progress = { "samples", "max_samples", "loadout", "upgrades", "upgrade_limit", "rank", "owned_cosmetics" },
	events = { "on", "off" },
	combat = { "on_hit", "off_hit" },
	ui = { "hint", "open", "close", "menus" },
	bots = { "all" },
	menu = { "add", "open", "close", "toggle", "is_open", "toast" },
}

local function free(call)
	local part, name = call:match("^(.-)%.(.+)$")
	local list = FREE[part]
	if not list then return true end
	for _, n in ipairs(list) do
		if n == name then return true end
	end
	return false
end

-- The way in, which runs in any lobby, and the mode, which runs only with the content.
local WRAPS = {
	"StateMenu.on_enter", "MenuScreenCampaignRegion.on_enter", "MenuScreenBase.draw_substate_menu_options",
	"MenuScreenCampaignRegion.update_selection", "MenuScreenCampaignRegion.update_selection_cursor",
	"MenuScreenCampaignRegion.handle_input", "MenuScreenCampaign.show_state", "MenuScreenProvingGroundsMission.on_enter",
	"MenuScreenProvingGroundsMission.generate_trials", "MenuScreenProvingGroundsMission.setup_trial_positions",
	"MenuScreenProvingGroundsMission.draw_trial_markers", "MenuScreenProvingGroundsMission.update", "MenuScreenProvingGroundsMission.handle_input",
	"MenuScreenProvingGroundsMission.show_mission_info", "MenuScreenCampaign.draw_provinggrounds_mini_leaderboard",
	"MenuScreenCampaign.update", "MenuScreenCampaign.exit", "MenuScreenLoadout.draw_menu",
	"GeneratedLevel.initialize", "GeneratedLevel.generate_mission", "StateMainMenu.on_enter",
}
local HOOKS = {
	"StateMenu.get_mission_seed", "MenuSpaceManager.set_planet", "MenuSpaceManager.planet_changed", "TextChat.start_typing",
	"HintManager.add_hint", "EnemyUtility.check_alert", "EnemyUtility.check_alarm", "EntityStateMachine.animation_event", "EncounterManager.start_encounter", "HintManager.update", "MissionManager.update", "StateGame.setup_world",
	"StateGame.spawn_research_samples_on_all_markers", "ExtractBeaconComponent.reload_slave",
	"ExtractBeaconComponent.should_draw_ui", "MissionManager.draw_objective_list", "StateMissionStart.on_enter",
	"GeneratedLevel.load_resources", "GeneratedLevel.has_loaded_resources", "GeneratedLevel.release_enemy_package",
	"GeneratedLevel.get_package_size_in_bytes", "GeneratedLevel.get_package_loaded_bytes",
	"ShieldComponent.command_master", "HealthComponent.calculate_damage", "HealthComponent.setup_master", "HealthComponent.setup_slave",
	"WeaponUtility.shoot_beam_callback", "WeaponUtility.shoot_flame_callback", "ArcweaponComponent.command_slave",
	"CharacterStateDodge.on_enter", "CharacterStateDodge.update", "CharacterStateCrawl.update",
	"CharacterStateKnockedDown.update", "CharacterStateDownedGetUp.update",
	"TeleportShieldComponent.rpc_teleport_shield_out", "TeleportShieldComponent.update_slaves",
	"StateMissionEnd.on_enter", "StateMissionEnd.save_stats", "StateMenu.update_host", "Hud.draw_hud",
	"Hud.draw_stratagem_cooldown_list", "ExplosionManager.do_explosion", "InventoryComponent.ammo_pickup", "StateGame.update_host",
	"FlowCallbacks.status_area_enter",
}

-- A Survivors seed, the way the galaxy map makes one.
local SEED
do
	local settings = {
		modulate_seed = function(time, light, env, variant, enemy, kind, difficulty)
			return ((((time * 10 + light) * 10 + env) * 10 + variant) * 10 + enemy) * 100 + difficulty
		end,
	}
	SEED = obsidian.module("src/seed").make(settings, { time = 1, light = 1, environment = 1, variant = 1, enemy = 1, difficulty = 6 })
end

-- Obsidian API: every call is recorded as "part.name" and answers ctx.answers[name], nil by default.
local function fake_api(ctx)
	return setmetatable({}, { __index = function(api, part)
		local t = setmetatable({}, { __index = function(t, name)
			local key = part .. "." .. name
			local f = function(...)
				ctx.calls[#ctx.calls + 1] = key
				local a = ctx.answers[key]
				if type(a) == "function" then return a(...) end
				return a
			end
			rawset(t, name, f)
			return f
		end })
		rawset(api, part, t)
		return t
	end })
end

local GLOBALS = { "LoadoutSettings", "SaveManager", "Network", "LocalizationManager", "DifficultySettings", "Application" }

-- main.lua started with a fresh copy of every module. opts.capabilities replaces the loader's.
local function boot(opts)
	opts = opts or {}
	local ctx = { hooks = {}, wraps = {}, frames = {}, sessions = {}, calls = {}, answers = {}, notes = {}, logs = {},
		running = false, started = 0, stopped = 0, refuse = nil, client = false }
	local api = fake_api(ctx)
	local loaded = {}
	-- The content switching, as Obsidian does it: every on_session listener hears it at once.
	function ctx.switch(on)
		ctx.running = on
		for _, fn in ipairs(ctx.sessions) do fn(on) end
	end
	function ctx.module(name) return loaded[name] end
	local caps = opts.capabilities
	if caps == nil then caps = { expansion = true, notify = true, wrap = true } end
	obsidian = {
		version = 1,
		capabilities = caps or nil,
		module = function(name)
			if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
			return loaded[name]
		end,
		import = function(id) if id == "obsidian.api" then return api end end,
		hook = function(target, method, fn) ctx.hooks[tostring(target) .. "." .. method] = fn end,
		wrap = function(target, method, fn) ctx.wraps[tostring(target) .. "." .. method] = fn end,
		on_frame = function(fn) ctx.frames[#ctx.frames + 1] = fn end,
		on_session = function(fn) ctx.sessions[#ctx.sessions + 1] = fn end,
		log = function(text) ctx.logs[#ctx.logs + 1] = tostring(text) end,
		notify = function(text) ctx.notes[#ctx.notes + 1] = text end,
		toast = function(text) ctx.notes[#ctx.notes + 1] = text end,
		ui = { frame = function() end, art = function() return false end, canvas = function() return {} end },
		expansion = {
			start = function()
				ctx.started = ctx.started + 1
				if ctx.refuse then return false, ctx.refuse, ctx.refuse == "players_missing" and { "Rookie" } or nil end
				if not ctx.running then ctx.switch(true) end
				return true
			end,
			stop = function()
				if not ctx.running then return false, "not_running" end
				if ctx.client then return false, "not_host" end
				ctx.stopped = ctx.stopped + 1
				ctx.switch(false)
				return true
			end,
			running = function() return ctx.running end,
		},
	}
	ctx.main = dofile("main.lua")
	return ctx
end

-- A test with main.lua started: the harness's obsidian and the game's globals come back after.
local function booted(name, fn, opts)
	test(name, function()
		local saved = obsidian
		local ok, err = pcall(function() fn(boot(opts)) end)
		obsidian = saved
		for _, k in ipairs(GLOBALS) do _G[k] = nil end
		if not ok then error(err, 0) end
	end)
end

-- The player's own planet on the first front, which the hellpods can take.
local function save_with_planet()
	local values = { current_planet = { name = "x", region = 1, enemy = 0, selected_mission_index = 1, missions = { { completed = false } } } }
	return { values = values, get = function(self, k) return self.values[k] end, set = function(self, k, v) self.values[k] = v end }
end

-- The galaxy map leaving with a Survivors mission picked on the Survivors screen.
local function pick(ctx)
	local exited = false
	local galaxy = {
		active_state = { survivors = true, name = "survivors_selection" },
		selected_trial = { survivors = true, seed = SEED, name = "Test", choice = { enemy = 1 } },
	}
	ctx.wraps["MenuScreenCampaign.exit"](function() exited = true end, galaxy)
	return exited, galaxy
end

-- The galaxy map left from a screen of the campaign: "mission" picks one, "region" is the fronts' Back.
local function leave(ctx, state)
	local exited = false
	ctx.wraps["MenuScreenCampaign.exit"](function() exited = true end, { active_state = { name = state } })
	return exited
end

local function next_drop(ctx)
	return ctx.hooks["StateMenu.get_mission_seed"](function() return "campaign" end, { is_server = true })
end

local function count(list, item)
	local n = 0
	for _, x in ipairs(list) do if x == item then n = n + 1 end end
	return n
end

test("an_obsidian_without_expansions_starts_nothing", function()
	for _, caps in ipairs({ {}, false }) do
		local saved = obsidian
		local ok, err = pcall(function()
			local ctx = boot({ capabilities = caps })
			eq(ctx.main, nil, "main.lua returns before anything")
			eq(next(ctx.hooks), nil, "no hook")
			eq(next(ctx.wraps), nil, "no wrap")
			eq(#ctx.frames + #ctx.sessions, 0, "no frame callback, no on_session")
			eq(ctx.logs[1]:find("1.2.0", 1, true) ~= nil, true, "the log says which Obsidian")
		end)
		obsidian = saved
		if not ok then error(err, 0) end
	end
end)

booted("the_way_in_is_wraps_and_the_mode_is_hooks", function(ctx)
	local want = {}
	for _, k in ipairs(WRAPS) do want[k] = "wrap" end
	for _, k in ipairs(HOOKS) do want[k] = "hook" end
	for k in pairs(ctx.wraps) do eq(want[k], "wrap", k .. " as a wrap") end
	for k in pairs(ctx.hooks) do eq(want[k], "hook", k .. " as a hook") end
	for _, k in ipairs(WRAPS) do eq(ctx.wraps[k] ~= nil, true, k .. " installed") end
	for _, k in ipairs(HOOKS) do eq(ctx.hooks[k] ~= nil, true, k .. " installed") end
	eq(#ctx.frames, 1, "one frame callback, which Obsidian runs with the content")
	eq(#ctx.sessions, 1, "one on_session listener")
end)

booted("nothing_before_the_content_makes_a_guarded_call", function(ctx)
	eq(#ctx.calls > 0, true, "the fake API heard the start")
	for _, call in ipairs(ctx.calls) do eq(free(call), true, call .. " is free before the content starts") end
	eq(count(ctx.calls, "combat.on_fatal"), 0, "Democracy Protects waits for the content")
	-- The galaxy map draws the Survivors screen with its own words, and no Obsidian API call.
	ctx.calls = {}
	LocalizationManager = { string = function(_, key) return "game:" .. key end }
	local seen
	ctx.wraps["MenuScreenCampaign.update"](function() seen = LocalizationManager:string("menu_campaign") end, { active_state = { survivors = true } })
	eq(seen, "ARCADE", "the screen's title, while it draws")
	eq(LocalizationManager:string("menu_campaign"), "game:menu_campaign", "the game's own after")
	eq(#ctx.calls, 0, "no Obsidian API call on the galaxy map")
end)

booted("picking_a_survivors_mission_starts_the_content", function(ctx)
	SaveManager = save_with_planet()
	ctx.answers["combat.on_fatal"] = true
	local exited = pick(ctx)
	eq(ctx.started, 1)
	eq(ctx.running, true)
	eq(exited, true, "the galaxy map closes")
	eq(next_drop(ctx), SEED, "the hellpods take the Survivors mission")
	eq(ctx.module("src/campaign").lent ~= nil, true, "with a planet lent")
	eq(#ctx.notes, 0)
	eq(count(ctx.calls, "combat.on_fatal"), 1, "Democracy Protects goes in with the content")
	pick(ctx)
	eq(ctx.started, 1, "picking again while it runs asks nothing more")
	leave(ctx, "region")
	pick(ctx)
	eq(ctx.running, true, "and again after leaving")
	eq(count(ctx.calls, "combat.on_fatal"), 1, "Democracy Protects goes in once")
end)

booted("a_refused_start_keeps_the_galaxy_map_open", function(ctx)
	SaveManager = save_with_planet()
	ctx.refuse = "players_missing"
	local exited, galaxy = pick(ctx)
	eq(exited, false, "the Survivors screen stays")
	eq(ctx.running, false)
	eq(next_drop(ctx), "campaign", "the next drop stays the game's")
	eq(ctx.module("src/campaign").lent, nil, "no planet lent")
	eq(galaxy.set_current_planet_on_exit, nil, "the galaxy map is left as it was")
	eq(#ctx.notes, 0, "Obsidian names the players who don't run Survivors")
	ctx.refuse = "not_host"
	pick(ctx)
	eq(ctx.notes[1], "Only the host can start an arcade mission.")
	ctx.refuse = "busy"
	pick(ctx)
	eq(ctx.notes[2], "Helldivers Arcade can't start while another expansion is running.")
	ctx.refuse = nil
	eq(pick(ctx), true, "once everyone runs it, the pick goes ahead")
	eq(ctx.running, true)
end)

booted("a_mission_without_a_planet_for_the_hellpods_starts_nothing", function(ctx)
	SaveManager = { get = function() return nil end, set = function() end }
	eq(pick(ctx), false)
	eq(ctx.started, 0, "the planet comes first")
	eq(#ctx.notes, 1)
end)

booted("only_another_mission_picked_on_the_galaxy_map_ends_the_content", function(ctx)
	SaveManager = save_with_planet()
	pick(ctx)
	eq(leave(ctx, "mission"), true, "a campaign mission picked")
	eq(ctx.stopped, 1)
	eq(ctx.running, false)
	eq(next_drop(ctx), "campaign")
	eq(ctx.module("src/campaign").lent, nil)
	eq(leave(ctx, "region"), true, "closed with nothing running")
	eq(ctx.stopped, 1, "nothing to stop")
end)

booted("closing_the_galaxy_map_keeps_the_arcade_mission", function(ctx)
	SaveManager = save_with_planet()
	local own = SaveManager.values.current_planet
	pick(ctx)
	for _, state in ipairs({ "region", "start", "planet", "recap", "provinggrounds_selection" }) do
		-- The fronts' Back takes the planet and trial out of the save before the map closes.
		SaveManager.values.current_planet, SaveManager.values.selected_trial = nil, nil
		local galaxy = { active_state = { name = state }, current_planet_on_enter = own, set_current_planet_on_exit = true }
		local exited = false
		ctx.wraps["MenuScreenCampaign.exit"](function() exited = true end, galaxy)
		eq(exited, true, state .. ": the map closes")
		eq(ctx.running, true, state .. ": the content goes on")
		eq(next_drop(ctx), SEED, state .. ": the next drop is still the arcade mission")
		eq(SaveManager.values.current_planet, own, state .. ": the player's planet back in the save")
		eq(galaxy.set_current_planet_on_exit, false, state .. ": and the map leaves it there")
	end
	eq(ctx.stopped, 0)
	local galaxy = { active_state = { name = "provinggrounds_selection" }, selected_trial = { seed = 5 } }
	ctx.wraps["MenuScreenCampaign.exit"](function() end, galaxy)
	eq(ctx.stopped, 1, "a Proving Grounds trial picked ends it")
end)

booted("the_content_ends_on_the_main_menu_once_the_game_has_left_the_lobby", function(ctx)
	SaveManager = save_with_planet()
	pick(ctx)
	local during
	ctx.wraps["StateMainMenu.on_enter"](function() during = ctx.running end, {})
	eq(during, true, "the stop comes after the game's on_enter, which leaves the lobby")
	eq(ctx.running, false)
	ctx.wraps["StateMainMenu.on_enter"](function() end, {})
	eq(ctx.stopped, 1, "the title screen with nothing running")
end)

booted("a_game_that_follows_the_host_leaves_the_stop_to_obsidian", function(ctx)
	ctx.client = true
	ctx.switch(true)
	eq(count(ctx.calls, "combat.on_fatal"), 1, "the content started by the host")
	ctx.wraps["StateMainMenu.on_enter"](function() end, {})
	eq(ctx.running, true, "only the host stops it; leaving the lobby ends it here")
	ctx.switch(false)
	eq(ctx.running, false)
end)

booted("a_game_that_takes_over_the_lobby_on_the_ship_ends_the_content", function(ctx)
	ctx.client = true
	ctx.answers["game.on_ship"] = true
	ctx.switch(true)
	ctx.frames[1]()
	eq(ctx.running, true, "following the host, with the host's choice")
	-- The host left: Obsidian makes this game the host, and the content carries on here.
	ctx.client = false
	ctx.answers["game.is_host"] = true
	ctx.frames[1]()
	eq(ctx.running, false, "no Survivors mission chosen here, so normal missions")
	eq(ctx.stopped, 1)
end)

booted("a_host_with_a_survivors_drop_keeps_the_content_on_the_ship", function(ctx)
	ctx.answers["game.on_ship"] = true
	ctx.answers["game.is_host"] = true
	SaveManager = save_with_planet()
	pick(ctx)
	ctx.frames[1]()
	eq(ctx.running, true)
	eq(next_drop(ctx), SEED)
end)

booted("the_content_ending_puts_the_stratagem_row_back", function(ctx)
	LoadoutSettings = { nr_of_stratagem_slots = 6, static_stratagems = { "reinforce", "resupply" } }
	SaveManager = save_with_planet()
	pick(ctx)
	ctx.frames[1]()
	eq(LoadoutSettings.nr_of_stratagem_slots, 4, "the fixed ones and two of the player's")
	leave(ctx, "mission")
	eq(LoadoutSettings.nr_of_stratagem_slots, 6, "the game's row again")
	-- Without the content, the loadout screen draws the game's row.
	local drawn
	ctx.wraps["MenuScreenLoadout.draw_menu"](function() drawn = true end, { stratagem_icon_size = { 50, 50 } }, nil, {}, nil, nil, 400)
	eq(drawn, true)
end)

-- The Arcade screen's input, with the game's handle_input as MenuScreenProvingGroundsMission has it:
-- Select sets the galaxy map's selected trial and calls the galaxy map's exit.
booted("launch_on_the_arcade_screen_takes_the_mission_and_nothing_else_does", function(ctx)
	LoadoutSettings = { nr_of_stratagem_slots = 6, static_stratagems = { "reinforce", "resupply" } }
	SaveManager = save_with_planet()
	DifficultySettings = { modulate_seed = function(time, light, env, variant, enemy, kind, difficulty)
		return ((((time * 10 + light) * 10 + env) * 10 + variant) * 10 + enemy) * 100 + difficulty
	end }
	LocalizationManager = { string = function(_, key) return key end }
	local saved = { MenuScreenBase, Vector3 }
	local ok, err = pcall(function()
		local clicked = nil
		MenuScreenBase = {
			handle_input_cursor = function() end, reset_clickable_buttons = function() end,
			get_clicked_scroll_button = function() end,
			was_text_button_clicked = function(_, _, name) return name == clicked end,
		}
		local entry = ctx.module("src/entry")
		local galaxy = {}
		local screen = { survivors = true, parent = galaxy, selected_trial_index = 1,
			trials = { { survivors = true, seed = SEED, name = "Test", choice = { enemy = 1 } } } }
		galaxy.active_state = screen
		local exits, selects = 0, 0
		local function game_input(self, input)
			if input.select then
				selects = selects + 1
				self.parent.selected_trial = self.trials[self.selected_trial_index]
				self.parent.current_planet = nil
				ctx.wraps["MenuScreenCampaign.exit"](function() exits = exits + 1 end, self.parent)
			end
		end
		local handle = ctx.wraps["MenuScreenProvingGroundsMission.handle_input"]
		local ui = entry.ui(screen)
		ui.panel, ui.row = 2, 1
		handle(game_input, screen, { select = true })
		eq(selects, 0, "Select on a parameter doesn't launch")
		eq(ui.row, 5, "it moves onto Launch")
		ui.row = 4
		handle(game_input, screen, { reload_pressed = true })
		eq(screen.trials[1].seed ~= SEED, true, "the reload key rolls a new map")
		handle(game_input, screen, { select = true })
		eq(selects, 0, "Refresh doesn't launch")
		clicked = "refresh"
		handle(game_input, screen, { select_mouse = true })
		eq(selects, 0, "the key guide's Refresh doesn't launch")
		clicked = nil
		eq(ctx.started, 0, "nothing started yet")
		ui.row = 5
		handle(game_input, screen, { select = true })
		eq(selects, 1, "Launch picks the mission the game's way")
		eq(ctx.started, 1, "the content starts")
		eq(exits, 1, "the galaxy map closes")
		eq(next_drop(ctx), screen.trials[1].seed, "the hellpods take the previewed mission")
		eq(ctx.module("src/seed").is_survivors(next_drop(ctx)), true, "a Survivors drop")
		eq(galaxy.current_planet ~= nil, true, "with a planet lent")
		ctx.frames[1]()
		eq(LoadoutSettings.nr_of_stratagem_slots, 4, "the loadout: the fixed stratagems and two of the player's")
		clicked = "select"
		handle(game_input, screen, { select_mouse = true })
		eq(selects, 2, "the key guide's Launch launches too")
	end)
	MenuScreenBase, Vector3 = saved[1], saved[2]
	if not ok then error(err, 0) end
end)

booted("a_refused_launch_keeps_the_arcade_screen_open", function(ctx)
	SaveManager = save_with_planet()
	ctx.refuse = "players_missing"
	local exited, galaxy = pick(ctx)
	eq(ctx.started, 1)
	eq(exited, false, "the galaxy map stays open")
	eq(next_drop(ctx), "campaign", "no Survivors drop")
end)

booted("a_run_cut_short_ends_with_the_content", function(ctx)
	Network = { peer_id = function() return "1100001" end }
	ctx.client = true
	ctx.switch(true)
	local run = ctx.module("src/run")
	run.start(SEED, 6)
	eq(run.run ~= nil, true)
	ctx.calls = {}
	ctx.switch(false)
	eq(run.run, nil, "the run stops")
	eq(count(ctx.calls, "effects.clear"), 1, "the run's effects go, which set() can't do once the content is over")
	ctx.calls = {}
	ctx.switch(true)
	ctx.switch(false)
	eq(count(ctx.calls, "effects.clear"), 0, "no run, nothing to clear")
end)

-- Nothing of a run reaches the next: Elusive Tactics' stuns still to come (kept on the run's clock,
-- which starts again at 0) and every lobby key the run writes.
booted("a_stop_leaves_no_stuns_waiting_and_clears_the_runs_lobby_keys", function(ctx)
	Network = { peer_id = function() return "1100001" end }
	local cleared = {}
	ctx.answers["lobby.share"] = function(key, value) if value == nil then cleared[key] = true end end
	ctx.switch(true)
	local run, dive = ctx.module("src/run"), ctx.module("src/dive")
	run.start(SEED, 6)
	dive.queue[#dive.queue + 1] = { at = 900, status = dive.STUN_SHORT, enemies = { {} } }
	dive.now = 899
	run.stop()
	eq(#dive.queue, 0, "no stun waits for the next run's clock")
	eq(dive.now, 0)
	local text = read("src/run.lua")
	for key in text:gmatch('api%.lobby%.share,? ?%(?"([%w_]+)"') do eq(cleared[key], true, "the stop clears " .. key) end
	eq(cleared.siphon, true, "Sample Siphon's reach")
end)

-- Sweet Liberty's blast, as src/run.lua's env sets it off for a kill, in an engine whose explosions send
-- their hits from an overlap's answer a physics step later, as the game's do: the Helldivers in it take
-- nothing, and the enemies' hits are marked as Sweet Liberty's for the summary.
booted("a_sweet_liberty_blast_spares_helldivers_and_marks_its_hits_as_they_go_out", function(ctx)
	Network = { peer_id = function() return "1100001" end }
	local saved = { EntityAux, PhysicsWorld, LuaSettingsManager, Vector3 }
	local ok, err = pcall(function()
		local queued, waiting = {}, {}
		EntityAux = {
			queue_command_interface = function(unit) queued[#queued + 1] = unit end,
			has_component = function(unit, name) return unit[name] == true end,
			state = function() return nil end,
		}
		PhysicsWorld = { overlap = function(_, answer) waiting[#waiting + 1] = answer end }
		LuaSettingsManager = { get_settings_by_unit_path = function() return nil end }
		Vector3 = function(x, y, z) return { x = x, y = y, z = z } end
		local diver, bug = { character = true }, { character = true, enemy = true }
		ctx.answers["world.explode"] = function()
			PhysicsWorld.overlap({}, function(units)
				for _, u in ipairs(units) do EntityAux.queue_command_interface(u, "damageable", "do_damage", { power = 30 }) end
			end)
			return true
		end
		ctx.switch(true)
		local run = ctx.module("src/run")
		run.start(SEED, 6)
		local r = run.run
		r.local_list = { { unit = diver, slot = 1, pos = { x = 0, y = 0, z = 0 } } }
		r.slot_by_unit[diver] = 1
		r.players[1] = { stats = {} }
		r.env.liberty(1, { x = 1, y = 2, z = 0 })
		eq(#queued, 0, "nothing goes out during the call")
		for _, answer in ipairs(waiting) do answer({ diver, bug }) end
		eq(#queued, 1, "the Helldiver in the blast takes no hit")
		eq(queued[1], bug)
		local marks = r.tally.marks[bug]
		eq(marks and marks[1].source, "sweet_liberty", "the enemy's hit is Sweet Liberty's")
		eq(marks and marks[1].slot, 1)
		eq(r.tally.marks[diver], nil)
		run.stop()
	end)
	EntityAux, PhysicsWorld, LuaSettingsManager, Vector3 = saved[1], saved[2], saved[3], saved[4]
	if not ok then error(err, 0) end
end)

-- A Sweet Liberty blast's look is the grenade's effect and sound (src/run.lua's blast_look), with nothing
-- left in the level: a mission that ends with one still counted stands down and stops all the same.
booted("a_run_ending_with_a_blast_look_up_stands_down_and_stops_to_the_end", function(ctx)
	Network = { peer_id = function() return "1100001" end }
	local saved = { LuaSettingsManager, World, TimpaniWorld, Vector3 }
	local ok, err = pcall(function()
		local played = 0
		LuaSettingsManager = { get_settings_by_unit_path = function() return { explosive_info = { effect = "effects/blast", audio = "blast" } } end }
		World = { create_particles = function() played = played + 1 end, timpani_world = function() return {} end }
		TimpaniWorld = { trigger_event = function() played = played + 1 end }
		Vector3 = function(x, y, z) return { x = x, y = y, z = z } end
		ctx.answers["game.state"] = { world_proxy = { get_world = function() return {} end } }
		ctx.switch(true)
		local run = ctx.module("src/run")
		run.start(SEED, 6)
		local r = run.run
		run.blast_look(r, nil, { x = 1, y = 2, z = 0 })
		eq(#r.looks, 1, "one look counted")
		eq(played, 2, "the effect and the sound")
		run.stand_down(r)
		eq(r.exiting, true)
		eq(#r.looks, 0, "the count goes as the run stands down")
		run.blast_look(r, nil, { x = 1, y = 2, z = 0 })
		run.stop()
		eq(run.run, nil, "the run stops")
		eq(ctx.logs[#ctx.logs]:find("arcade: run over at", 1, true) ~= nil, true, "the stop ran to its end: " .. ctx.logs[#ctx.logs])
	end)
	LuaSettingsManager, World, TimpaniWorld, Vector3 = saved[1], saved[2], saved[3], saved[4]
	if not ok then error(err, 0) end
end)

-- A kit that counts what it draws.
local function counting_kit()
	local k = { drawn = 0, z = 0 }
	for _, name in ipairs({ "rect", "text", "icon", "art", "hex", "panel", "band", "poly", "outline" }) do
		k[name] = function(self) self.drawn = self.drawn + 1 return true end
	end
	function k:measure(text, opts) return #text * ((opts and opts.size) or 20) * 0.5 end
	function k:layer(n) if n then self.z = n end return self.z end
	function k:point(x, y) return x, y end
	function k:opacity() return 1 end
	return k
end

booted("a_photo_hides_everything_the_run_draws_and_the_run_goes_on", function(ctx)
	Network = { peer_id = function() return "1100001" end }
	Application = { resolution = function() return 1920, 1080 end }
	ctx.switch(true)
	local run = ctx.module("src/run")
	local samples = ctx.module("src/samples")
	run.start(SEED, 6)
	local synced = 0
	local real_sync = samples.sync
	samples.sync = function(...) synced = synced + 1 return real_sync(...) end
	local kit = counting_kit()
	run.draw(kit, false)
	eq(kit.drawn > 0, true, "the bar and the rest, without a photo")
	eq(synced, 1)
	-- Photo Mode turns Obsidian API's photo effect on.
	ctx.answers["effects.is_on"] = function(id) return id == "photo_mode" end
	kit = counting_kit()
	run.draw(kit, false)
	eq(kit.drawn, 0, "nothing over the picture")
	eq(synced, 2, "the samples in the level stay in line with the orbs")
	eq(run.kit, kit, "the mouse still reads the kit")
	-- The cards while choosing, too.
	run.run.choice = { players = { { row = {}, cursor = 1 } }, turn = 1, left = 5 }
	kit = counting_kit()
	run.draw(kit, false)
	eq(kit.drawn, 0, "no cards over the picture")
	run.run.choice = nil
	-- The photo over, everything is back.
	ctx.answers["effects.is_on"] = nil
	kit = counting_kit()
	run.draw(kit, false)
	eq(kit.drawn > 0, true)
	samples.sync = real_sync
end)

booted("with_no_planet_to_lend_after_a_run_the_content_ends", function(ctx)
	ctx.answers["game.is_host"] = true
	ctx.answers["game.on_ship"] = true
	DifficultySettings = { get_mission_params = function() return { enemy = 0, difficulty = 6 } end }
	SaveManager = save_with_planet()
	pick(ctx)
	ctx.module("src/run").run = nil
	-- A run of the Survivors mission played: back on the ship, the next drop is the same mission.
	ctx.answers["game.in_mission"] = true
	ctx.answers["mission.params"] = function() return { difficulty = 6 }, SEED end
	ctx.module("src/level").active = true
	Network = { peer_id = function() return "1100001" end }
	ctx.frames[1]()
	eq(ctx.module("src/run").run ~= nil, true, "the run started")
	ctx.answers["game.in_mission"] = nil
	ctx.module("src/level").active = false
	ctx.frames[1]()
	eq(ctx.module("src/run").run, nil, "and ended with the mission")
	ctx.frames[1]()
	eq(next_drop(ctx), SEED, "the same mission again")
	eq(ctx.running, true)
	-- The campaign has no planet left for the hellpods.
	ctx.module("src/run").run = nil
	ctx.answers["game.in_mission"] = true
	ctx.module("src/level").active = true
	ctx.frames[1]()
	ctx.answers["game.in_mission"] = nil
	ctx.module("src/level").active = false
	ctx.frames[1]()
	SaveManager = { get = function() return nil end, set = function() end }
	LoadoutSettings = { nr_of_stratagem_slots = 6, static_stratagems = { "reinforce", "resupply" } }
	ctx.frames[1]()
	eq(ctx.running, false, "normal missions, without the content")
	eq(next_drop(ctx), "campaign")
	eq(LoadoutSettings.nr_of_stratagem_slots, 6, "the frame stops before setting the row again")
end)

booted("the_map_preview_is_a_survivors_map_and_a_mission_only_with_the_content", function(ctx)
	local init = ctx.wraps["GeneratedLevel.initialize"]
	local function level_for(world)
		local self = { mission_type_name = "mission", enemy = "bugs" }
		init(function() end, self, world, SEED)
		return self
	end
	eq(level_for(nil).survivors, true, "the Survivors screen's preview, before the content")
	eq(level_for({}).survivors, false, "a mission without the content is the game's")
	eq(ctx.module("src/level").active, false)
	ctx.switch(true)
	eq(level_for({}).survivors, true)
	eq(ctx.module("src/level").active, true)
end)

test("the_manifest_makes_survivors_an_expansion_for_obsidian_1_2", function()
	local text = read("obsidian.json")
	eq(text:find('"scope": "expansion"', 1, true) ~= nil, true, "scope")
	eq(text:find('"min_obsidian": "1.2.0"', 1, true) ~= nil, true, "min_obsidian")
	eq(text:find("every_player", 1, true), nil, "every_player is for session mods")
	eq(text:match('"version": "(%d+%.%d+%.%d+)"') ~= nil, true, "a version")
	eq(text:find('"id": "alomare.arcade"', 1, true) ~= nil, true, "the id")
	local first
	for line in read("main.lua"):gmatch("[^\n]+") do
		if not line:find("^%s*%-%-") and line:find("%S") then first = line break end
	end
	eq(first, "if not (obsidian.capabilities and obsidian.capabilities.expansion) then", "main.lua starts with the check")
end)

test("the_readme_names_the_scope_and_the_versions_needed", function()
	local text = read("README.md")
	eq(text:find("expansion", 1, true) ~= nil, true, "the scope")
	eq(text:find("Obsidian 1.2.0", 1, true) ~= nil, true, "Obsidian")
	eq(text:find("Obsidian API 1.48.0", 1, true) ~= nil, true, "Obsidian API")
end)

return T
