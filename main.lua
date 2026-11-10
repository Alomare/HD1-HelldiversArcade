-- Helldivers Arcade: arcade game modes on the galaxy map. The first, Super Earth Survivors, is a mode after Vampire Survivors. See docs/design.md.
--
-- An expansion: Obsidian runs the hooks and the frame callback only while Survivors' content runs, in
-- every game in the lobby. The way in (the galaxy map's Survivors screen, the loadout row, the map
-- preview) is made of wraps, which run in any lobby. The host starts the content by picking a
-- Survivors mission and stops it by leaving Survivors; every other game follows the host.
-- Obsidian 1.1 refuses the mod by min_obsidian. Obsidian 1.0 doesn't read it, and would run every hook
-- in every lobby as an unspecified mod's, so Survivors stays out there.
if not (obsidian.capabilities and obsidian.capabilities.expansion) then
	obsidian.log("arcade: this Obsidian has no expansions, so Survivors stays off. Update Obsidian to 1.2.0 or later.")
	return
end

local seed = obsidian.module("src/seed")
local level = obsidian.module("src/level")
local run = obsidian.module("src/run")
local rules = obsidian.module("src/rules")
local input = obsidian.module("src/input")
local art = obsidian.module("src/art")
local entry = obsidian.module("src/entry")
local campaign = obsidian.module("src/campaign")
local fight = obsidian.module("src/fight")

local api = obsidian.import("obsidian.api")

local function g(name) return rawget(_G, name) end

level.install()
obsidian.module("src/bosses").install()
obsidian.module("src/shield").install()
obsidian.module("src/cards_hud").install()
obsidian.module("src/alarm").install()
-- Hits, killing hits and dives: what the fight upgrades do, for this machine's players in a run.
if not fight.install(api, run.stats_of, run.clock) then
	obsidian.log("arcade: Obsidian API before 1.12: no Ignition or Needle Rounds, and no Democracy Protects")
end
-- Democracy Protects saving the player: Better HUD flashes the health bar white, and the game's sound of a
-- bullet on armor plays, loud.
fight.on_spare = function(unit)
	run.on_spare(unit)
	local hud = obsidian.import("alomare.betterhud")
	if type(hud) == "table" and type(hud.flash_health) == "function" then hud.flash_health(unit, rules.SPARE_FLASH_SECONDS) end
	run.play_at(rules.SOUNDS.spared, rules.SPARE_SOUND_VOLUME)
end
-- Ignition and Needle Rounds: Better HUD shows the upgrade's icon over the enemy's health bar, filling
-- with the build-up and running down as it wears off or as the effect runs out.
fight.on_buildup = function(unit, kind, fraction, drain, id)
	local hud = obsidian.import("alomare.betterhud")
	if not (type(hud) == "table" and type(hud.status_buildup) == "function") then return end
	local u = id and obsidian.module("src/upgrades").by_id[id]
	hud.status_buildup(unit, kind, fraction or nil, drain, u and art.spec(u) or nil)
end
-- Tank Hunter: more damage to tier 4 enemies and bosses.
obsidian.module("src/hunter").install(api, run.stats_of)
-- The end-of-run summary: the damage of this machine's players by source, and the host's hold on the
-- mission's end until every player has seen it (src/summary.lua).
if api.combat and api.combat.on_hit then api.combat.on_hit(function(victim, hit) run.on_hit(victim, hit) end) end
obsidian.module("src/summary").install(function() return run.run and run.run.hold or nil end)
obsidian.module("src/dive").install(api, run.stats_of)
obsidian.module("src/trail").install()
-- Cluster Grenade and Deep Pockets.
local grenades = obsidian.module("src/grenades")
grenades.install(function() return run.run and run.run.grenades end, run.stats_of, run.clock, math.random)
grenades.install_resupply(run.stats_of)
-- Absolute Freedom on lasers, flamethrowers and arc weapons.
obsidian.module("src/armor").install(run.stats_of)
-- Super Earth Survivors' page in the in-game menu, for testing a run.
obsidian.module("src/debug").install(run)
obsidian.module("src/loadout").install(function()
	local ls = g("LoadoutSettings")
	if type(ls) == "table" and ls.nr_of_stratagem_slots == #ls.static_stratagems + rules.STRATAGEM_SLOTS then return rules.STRATAGEM_SLOTS end
	return nil
end)
obsidian.ui.frame(1920, 1080, { centered = true })
if not art.load() then obsidian.log("arcade: no art of its own, the cards use the game's icons") end

-- Choosing the mode on the galaxy map: the host's next drop is a Survivors mission. `again` is the one
-- just played, which stays the next drop back on the ship.
local chosen = nil
local ship_due = false
local again = nil

obsidian.hook("StateMenu", "get_mission_seed", function(original, self, ...)
	if chosen and self.is_server then return chosen end
	return original(self, ...)
end)

-- The ship goes where the drop is: its planet, its name and the "orbiting" line take the Survivors
-- mission's own (the same planet the loading screen names) instead of the campaign planet lent to
-- the hellpods. The arguments: seed, faction, environment, variant, difficulty, name.
local function ship_planet(original, self, s, enemy, environment, variant, difficulty, name, ...)
	if chosen and seed.is_survivors(chosen) then
		local ds = g("DifficultySettings")
		local ok, p = pcall(ds.get_mission_params, chosen)
		if ok and p then
			-- The region has to be one of that faction's: the ship stops on one it can't find.
			local missions, region = ...
			local faction = ds.enemy_lookup[p.enemy + 1]
			local fronts = g("SaveManager"):get("available_planets")
			local front = type(fronts) == "table" and fronts[p.enemy + 1]
			local own = type(front) == "table" and front.current_region or nil
			if own ~= nil and g("CampaignSettings").get_region_info(faction, own) then
				return original(self, chosen, faction, p.environment, p.environment_variant, p.difficulty, seed.planet_key(chosen), missions, own)
			end
		end
	end
	return original(self, s, enemy, environment, variant, difficulty, name, ...)
end
obsidian.hook("MenuSpaceManager", "set_planet", ship_planet)
obsidian.hook("MenuSpaceManager", "planet_changed", ship_planet)

-- The key that picked a card mustn't open the chat as the cards close.
obsidian.hook("TextChat", "start_typing", function(original, self, ...)
	if input.blocking() then return end
	return original(self, ...)
end)

-- A Survivors drop takes rules.STRATAGEM_SLOTS stratagems of the player's choosing, beside the game's
-- fixed ones: the loadout screen and the drop itself both count the game's slots, on every machine.
local SLOTS = nil
local function limit_loadout(survivors)
	local ls = g("LoadoutSettings")
	if type(ls) ~= "table" then return end
	SLOTS = SLOTS or ls.nr_of_stratagem_slots
	local want = survivors and (#ls.static_stratagems + rules.STRATAGEM_SLOTS) or SLOTS
	if ls.nr_of_stratagem_slots ~= want then
		ls.nr_of_stratagem_slots = want
		obsidian.log("arcade: stratagem slots " .. tostring(want))
	end
end

-- The mission the game is on or about to start: the host's choice, the ship's seed, or the mission's.
local function current_seed()
	if chosen then return chosen end
	local st = api.game.state()
	if type(st) == "table" and type(st.mission_seed) == "number" then return st.mission_seed end
	local _, s = api.mission.params()
	return s
end

-- The game only moves the ship when the planet's name changes, and a Survivors drop keeps the name of
-- the planet lent to the hellpods. So the ship is sent once the galaxy map has closed.
local function send_ship()
	if not ship_due or not chosen then return end
	local st = api.game.state()
	local space = type(st) == "table" and st.menu_space_manager
	if not space or not api.game.on_ship() then return end
	for _, screen in ipairs(st.active_screens or {}) do
		if screen.name == "campaign" then return end
	end
	ship_due = false
	space:planet_changed(st.planet_seed, nil, nil, nil, nil, st.planet_name, st.planet_missions, st.planet_region)
end

local function notify(text)
	if obsidian.capabilities.notify then obsidian.notify(text) else obsidian.toast(text) end
end

-- Why the host's start was refused, for the reasons Obsidian doesn't tell the host itself. For
-- "players_missing", Obsidian shows the names of the players who don't run Survivors.
local REFUSED = {
	not_host = "Only the host can start an arcade mission.",
	busy = "Helldivers Arcade can't start while another expansion is running.",
}

-- Picking a Survivors mission starts the content, on the host's game.
local function start_content()
	-- The screen asks before the game's pick, and the pick asks again: once running, that's a yes.
	if obsidian.expansion.running() then return true end
	local ok, why = obsidian.expansion.start()
	if ok then return true end
	obsidian.log("arcade: the content didn't start: " .. tostring(why))
	if why ~= "players_missing" then notify(REFUSED[why] or "Helldivers Arcade couldn't start. Try again in a moment.") end
	return false
end

-- Leaving Survivors ends the content. Only the host's game can, and on the others this does nothing.
local function stop_content()
	if obsidian.expansion.running() then obsidian.expansion.stop() end
end

-- The galaxy map's ARCADE tab, beside Proving Grounds: Super Earth Survivors' parameters and the
-- mission they make (src/entry.lua). A campaign mission picked there, or the galaxy map left from the
-- fronts, sets nil: normal missions again, and the content ends. make_seed takes the screen's choice,
-- layout included (src/seed.lua).
entry.install({
	make_seed = function(choice) return seed.make(g("DifficultySettings"), choice) end,
	set = function(s)
		-- The same mission again (the galaxy map closed with it still chosen) leaves the ship where it is:
		-- the ship moving to the planet it's on plays the jump to it all the same.
		if s ~= chosen then ship_due = s ~= nil end
		chosen = s
		if s == nil then
			again = nil
			campaign.lend(nil)
			stop_content()
		end
	end,
	start = start_content,
	notify = notify,
	chosen = function() return chosen end,
})

-- The mission's end and the hellpods leave the campaign as it was (src/campaign.lua).
campaign.install(seed.is_survivors, function() return chosen end)

-- Back on the ship after a Survivors mission, the host's next drop is the same mission and the ship
-- stays on its planet, for another go. The hellpods get a planet lent again, from the save as it is
-- now, and nothing is saved. With no planet to lend, the ship goes back to the galaxy map's choice,
-- and the content ends: the next drop is a normal mission.
local function stay_on(s)
	if not api.game.is_host() then return end
	local ds = g("DifficultySettings")
	local ok, p = pcall(ds.get_mission_params, s)
	local front = ok and p and p.enemy + 1 or 1
	local ran, planet = pcall(entry.lend_planet, g("SaveManager"), front)
	if ran and planet then
		campaign.lend(planet)
		chosen, ship_due = s, true
		obsidian.log("arcade: the next drop is the same mission, seed " .. tostring(s))
	else
		campaign.lend(nil)
		obsidian.log("arcade: no planet to lend the hellpods, so normal missions again: " .. tostring(planet))
		stop_content()
	end
end

-- A run starts with the mission and ends with it. Like the hooks, the frame callback runs only while
-- the content does: everything in it belongs to a Survivors drop.
local canvas = obsidian.ui.canvas("survivors", { layer = 600 })
local paused = false

api.events.on("on_killed", function(unit, attacker, owner) run.on_killed(unit, attacker, owner) end)
api.events.on("on_pause", function(on) paused = on end)
api.events.on("on_objective_completed", function() run.on_objective() end)
api.events.on("on_damage_taken", function(unit, info) run.on_damage(unit, info) end)

obsidian.on_frame(function()
	-- A game that took over the lobby on the ship has no Survivors mission chosen: the choice left with
	-- the old host. The next drop is a normal one, so the content ends for the lobby.
	if not chosen and not again and not run.run and api.game.on_ship() and api.game.is_host() then
		stop_content()
		return
	end
	if again and not run.run and api.game.on_ship() then
		local s = again
		again = nil
		if chosen == nil then stay_on(s) end
		-- The content ended in stay_on: on_session(false) has put everything back.
		if not obsidian.expansion.running() then return end
	end
	local s = current_seed()
	pcall(limit_loadout, type(s) == "number" and seed.is_survivors(s))
	if not run.run then input.update(g("ENGINE_DT") or 0) end
	local sent, why = pcall(send_ship)
	if not sent then
		ship_due = false
		obsidian.log("arcade: couldn't move the ship: " .. tostring(why))
	end
	local st = api.game.state()
	local in_game = api.game.in_mission() and level.active
	if in_game and not run.run then
		local params, mission_seed = api.mission.params()
		if mission_seed and seed.is_survivors(mission_seed) then
			chosen = nil
			again = mission_seed
			-- The mission briefing on the ship says the game is paused and nothing says otherwise.
			paused = false
			run.start(mission_seed, type(params) == "table" and params.difficulty or nil)
		end
	elseif not in_game and run.run then
		run.stop()
	end
	if not run.run then return end
	local ok, err = pcall(run.update)
	if not ok then obsidian.log("arcade: update failed: " .. tostring(err)) end
	ok, err = pcall(run.draw, canvas, paused)
	if not ok then obsidian.log("arcade: draw failed: " .. tostring(err)) end
end)

-- Back on the main menu, Survivors is over for this game. The run ends first, while the content still
-- runs, since Obsidian API takes the run's effects back only then. The game leaves the lobby in
-- StateMainMenu.on_enter, so the stop after it tells no other player: in a lobby that plays on, the
-- next host carries the content on.
obsidian.wrap("StateMainMenu", "on_enter", function(original, self, ...)
	if run.run then pcall(run.stop) end
	original(self, ...)
	stop_content()
end)

-- The content starts and ends on every machine in the lobby, the host's first. Obsidian switches the
-- hooks and the frame callback by itself. The rest goes back here: the loadout's stratagem row (a
-- value written into LoadoutSettings), the next drop, and a run cut short. Survivors makes no custom
-- stratagems (api.stratagems.define), which nothing would pause.
obsidian.on_session(function(on)
	if on then
		fight.arm()
		return
	end
	local cut = run.run ~= nil
	if cut then
		local ok, err = pcall(run.stop)
		if not ok then obsidian.log("arcade: stopping the run failed: " .. tostring(err)) end
		-- run.stop's api.effects.set answers "not_started" once the content is over, and clear() works
		-- in any lobby: the freeze, invulnerability, camera distance and hidden HUD of the run go, with
		-- any other effect that was on.
		api.effects.clear()
	end
	chosen, ship_due, again, paused = nil, false, nil, false
	campaign.lend(nil)
	local ok, err = pcall(limit_loadout, false)
	if not ok then obsidian.log("arcade: the stratagem row didn't go back: " .. tostring(err)) end
	obsidian.log("arcade: the content ended" .. (cut and ", during a run" or ""))
end)

obsidian.log("Helldivers Arcade " .. tostring(obsidian.version) .. " ready")

-- For tests: the run, the map and the galaxy map's entry.
return { run = run, level = level, entry = entry, samples = obsidian.module("src/samples"), input = input, xp = obsidian.module("src/xp"), upgrades = obsidian.module("src/upgrades") }
