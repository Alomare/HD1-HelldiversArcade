-- A Survivors mission leaves the campaign in the save as it was (src/campaign.lua). The game's mission
-- end is copied here as far as the campaign goes (StateMissionEnd.on_enter and save_stats, read from
-- lua/states/state_mission_end.lua), so a write that comes back shows up as a failed test.
local campaign = obsidian.module("src/campaign")
local entry = obsidian.module("src/entry")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local function fake_save(values)
	return { values = values, get = function(self, k) return self.values[k] end, set = function(self, k, v) self.values[k] = v end }
end

-- A campaign with the player on planet "b" of the cyborg front, its selected mission the last left.
local function campaign_save(planet_extra)
	local function missions(done) return { { completed = true, seed = 11 }, { completed = done, seed = 12 } } end
	local available = {
		{ current_region = 2, num_completed_planets = 1, planets = { { name = "a", missions = missions(false) } } },
		{ current_region = 4, num_completed_planets = 3, planets = { { name = "b", missions = missions(false) } } },
		{ current_region = 6, planets = { { name = "c", missions = missions(false) } } },
	}
	local current = { name = "b", region = 4, enemy = 1, selected_mission_index = 2, missions = missions(false) }
	for k, v in pairs(planet_extra or {}) do current[k] = v end
	return fake_save({
		available_planets = available, current_planet = current, dropzone_position = { x = 3, y = 4 },
		boss_planets = { [2] = { name = "boss_b" } }, next_mission_seed = 970000412, dialogue_info = {},
	})
end

-- StateMissionEnd.on_enter's campaign part, as the game runs it on the first host.
local function game_on_enter(state, params)
	local save = state.save
	state.mission_completed, state.is_last_mission = params.mission_completed, params.is_last_mission
	state.current_planet = save:get("current_planet")
	state.available_planets = save:get("available_planets")
	if not params.first_host then
		state.planet_completed = state.mission_completed and state.is_last_mission
		return
	end
	if state.available_planets and state.current_planet then
		for e, front in ipairs(state.available_planets) do
			for p, planet in ipairs(front.planets) do
				if planet.name == state.current_planet.name then state.current_enemy_index, state.current_planet_index = e, p end
			end
		end
	end
	local cp = state.current_planet
	if state.mission_completed and cp and (cp.defend_event or cp.attack_event) then
		state.event_completed = true
		cp.missions = { { completed = false, seed = 99 } }
	elseif state.mission_completed and cp then
		save:set("dropzone_position", nil)
		local i = cp.selected_mission_index or 1
		cp.missions[i].completed, cp.missions[i].mission_score = true, 500
		local front = state.current_enemy_index and state.available_planets[state.current_enemy_index]
		if front then front.planets[state.current_planet_index].missions[i].completed = true end
		state.planet_completed = true
		for _, m in ipairs(cp.missions) do
			if not m.completed then state.planet_completed = false end
		end
		if state.planet_completed then
			if cp.boss then
				local bosses = save:get("boss_planets")
				bosses[cp.enemy + 1] = nil
				save:set("boss_planets", bosses)
			elseif front then
				front.num_completed_planets = (front.num_completed_planets or 0) + 1
			end
			save:set("last_planet", cp)
			save:set("current_planet", nil)
		end
	end
	save:set("dialogue_info", { mission_completed = state.mission_completed })
end

-- StateMissionEnd.save_stats's campaign part.
local function game_save_stats(state)
	if not (state.current_planet and not state.current_planet.defend_event) then return end
	if state.available_planets then
		if state.current_enemy_index and state.current_planet_index then
			local p = state.available_planets[state.current_enemy_index].planets[state.current_planet_index]
			p.total_deaths, p.total_kills = (p.total_deaths or 0) + 2, (p.total_kills or 0) + 140
		end
		state.save:set("available_planets", state.available_planets)
	end
end

local function campaign_part(save)
	local out = {}
	for _, key in ipairs(campaign.KEYS) do out[key] = campaign.copy(save:get(key)) end
	return out
end

local function mission_end(save, params, guarded)
	local state = { save = save, mission_seed = 970000412 }
	if guarded then
		campaign.mission_end(save, game_on_enter, state, params)
		campaign.save_stats(save, game_save_stats, state)
	else
		game_on_enter(state, params)
		game_save_stats(state)
	end
	return state
end

test("the_copied_mission_end_does_change_the_campaign", function()
	local save = campaign_save()
	local before = campaign_part(save)
	mission_end(save, { mission_completed = true, first_host = true }, false)
	eq(campaign.same(campaign_part(save), before), false, "without the guard the copy marks the planet done")
	eq(save.values.current_planet, nil, "its last mission done, the game lets go of the planet")
	eq(save.values.available_planets[2].planets[1].missions[2].completed, true)
	eq(save.values.available_planets[2].num_completed_planets, 4)
end)

test("a_survivors_mission_leaves_the_campaign_as_it_was_won_or_lost", function()
	local cases = {
		{ "a win", {}, { mission_completed = true, first_host = true } },
		{ "a loss", {}, { mission_completed = false, first_host = true } },
		{ "a boss planet won", { boss = true }, { mission_completed = true, first_host = true } },
		{ "a defend event won", { defend_event = { id = 3 } }, { mission_completed = true, first_host = true } },
		{ "a win on a machine that took over as host", {}, { mission_completed = true, first_host = false, is_last_mission = true } },
	}
	for _, c in ipairs(cases) do
		local save = campaign_save(c[2])
		local planet = save.values.current_planet
		local before = campaign_part(save)
		local state = mission_end(save, c[3], true)
		eq(campaign.same(campaign_part(save), before), true, c[1] .. ": the campaign's keys")
		eq(save.values.current_planet, planet, c[1] .. ": the same planet table, not a copy")
		eq(state.planet_completed == true, false, c[1] .. ": no planet done")
		eq(state.event_completed, nil, c[1] .. ": no event mission done")
		local told = save.values.dialogue_info.mission_completed
		if c[3].first_host then eq(told, c[3].mission_completed, c[1] .. ": the ship's dialogue still hears how it went") end
	end
end)

test("whatever_the_mission_end_writes_anyway_goes_back", function()
	local save = campaign_save()
	local before = campaign_part(save)
	local back = campaign.mission_end(save, function(state, params)
		save:get("available_planets")[2].planets[1].missions[2].completed = true
		save:set("last_planet", { name = "b" })
		save:set("boss_planets", nil)
	end, {}, {})
	eq(table.concat(back, ","), "available_planets,last_planet,boss_planets")
	eq(campaign.same(campaign_part(save), before), true)
	local failing = campaign_save()
	local ok = pcall(campaign.mission_end, failing, function() failing:set("current_planet", nil) error("boom") end, {}, {})
	eq(ok, false, "the game's error goes on")
	eq(failing.values.current_planet.name, "b", "and the planet is back")
end)

test("the_pods_take_the_lent_planet_only_while_the_ship_runs", function()
	local own = { name = "x" }
	local save = fake_save({ current_planet = own })
	local lent = { name = "b" }
	local seen
	campaign.with_planet(save, lent, function() seen = save:get("current_planet") end)
	eq(seen, lent, "update_host sees the lent planet")
	eq(save.values.current_planet, own, "the save has the player's own after")
	local empty = fake_save({})
	pcall(campaign.with_planet, empty, lent, function() error("boom") end)
	eq(empty.values.current_planet, nil, "back to none after an error too")
	campaign.with_planet(save, own, function() seen = save:get("current_planet") end)
	eq(seen, own, "the player's own planet lent: nothing to swap")
end)

test("the_lent_planet_is_the_players_own_or_a_copy", function()
	local front = { current_region = 5, planets = { { name = "b", missions = { { completed = false } } } } }
	local available = { {}, front }
	local own = { name = "x", region = 1, enemy = 1, selected_mission_index = 1, missions = { { completed = true } } }
	eq(campaign.pick(own, available, 2, entry.pick_planet), own, "own, on the mission's front")
	local lent = campaign.pick(own, available, 1, entry.pick_planet)
	eq(lent.name, "b")
	eq(lent.missions ~= front.planets[1].missions, true, "a copy of the campaign's planet")
	eq(campaign.pick(own, {}, 1, entry.pick_planet), own, "nothing else: own on another front")
	eq(campaign.pick({ name = "x", missions = {} }, {}, 1, entry.pick_planet), nil, "a planet without a region doesn't open the pods")
	eq(campaign.pick(nil, nil, 1, entry.pick_planet), nil)
end)

-- Every line of the mod that sets one of the save's campaign keys, or tells the game to.
local SOURCES = { "main.lua" }
for _, name in ipairs({ "art", "atlas", "bosses", "campaign", "cards", "director", "dive", "draft", "alarm", "entry", "fight", "input", "level", "loadout",
	"native", "orbs", "perks", "rng", "rules", "run", "samples", "seed", "shield", "sync", "upgrades", "vacuum", "xp" }) do
	SOURCES[#SOURCES + 1] = "src/" .. name .. ".lua"
end

local WATCHED = { "current_planet", "available_planets", "last_planet", "boss_planets", "completed_planets", "dropzone_position",
	"next_mission_seed", "selected_trial", "mission_stats", "boss_influence" }

-- The only ones there may be: the repair of a planet Survivors 0.1.0 saved without a region, the planet
-- and trial put back as they were when the galaxy map closes without a pick, and the lend and put-back in
-- src/campaign.lua.
local ALLOWED = {
	["src/entry.lua"] = { 'save:set("current_planet", planet)', 'save:set("current_planet", nil)', 'save:set("next_mission_seed", nil)',
		'save:set("current_planet", screen.current_planet_on_enter)', 'save:set("selected_trial", screen.trial_on_enter)' },
	["src/campaign.lua"] = { 'save:set(key, M.same(was.value, was.copy) and was.value or M.copy(was.copy))', 'save:set("current_planet", nil)',
		'save:set("current_planet", planet)', 'if save:get("current_planet") == planet then save:set("current_planet", own) end' },
}

test("no_survivors_code_writes_the_campaign_in_the_save", function()
	for _, file in ipairs(SOURCES) do
		local f = assert(io.open(file, "r"))
		local text = f:read("*a")
		f:close()
		local found = {}
		for line in text:gmatch("[^\n]+") do
			local code = line:gsub("^%s+", ""):gsub("%s+$", "")
			if not code:find("^%-%-") then
				local writes = code:find(":set%(") or code:find("%.set%(") or code:find("user_set") or code:find("SaveManager.-:save")
				local named = false
				for _, key in ipairs(WATCHED) do
					if code:find('"' .. key .. '"', 1, true) then named = true end
				end
				if writes and (named or code:find("set%(key")) then found[#found + 1] = code end
				eq(code:find("set_current_planet_on_exit = true", 1, true), nil, file .. ": the galaxy map would save the planet")
				eq(code:find("CampaignManager", 1, true), nil, file .. ": " .. code)
				eq(code:find("user_set", 1, true), nil, file .. ": " .. code)
			end
		end
		local allowed = ALLOWED[file] or {}
		eq(#found, #allowed, file .. " campaign writes: " .. table.concat(found, " | "))
		for i, code in ipairs(found) do eq(code, allowed[i], file .. " line " .. i) end
	end
end)

return T
