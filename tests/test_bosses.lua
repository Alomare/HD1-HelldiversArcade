-- The bosses' plan, the difficulty they need, their music, and the Warp Pack's landing burst.
-- None of these calls Obsidian API, so the harness's import answers an empty table.
obsidian.import = obsidian.import or function() return {} end
local bosses = obsidian.module("src/bosses")
local director = obsidian.module("src/director")
local dive = obsidian.module("src/dive")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("bosses_come_from_difficulty_4", function()
	eq(bosses.allowed(1), false)
	eq(bosses.allowed(3), false)
	eq(bosses.allowed(4), true)
	eq(bosses.allowed(15), true)
	eq(bosses.allowed(nil), false, "a mission whose difficulty isn't known")
end)

test("every_machine_plans_the_same_bosses_of_factions_in_play", function()
	for _, home in ipairs(director.FACTIONS) do
		for s = 971000000, 971000400, 37 do
			local plan = bosses.plan(home, s)
			eq(#plan, bosses.PLAN_LENGTH)
			local again = bosses.plan(home, s)
			for i, b in ipairs(plan) do
				eq(b.minute, director.boss_minute(i))
				eq(again[i].faction, b.faction, "the same from the same seed")
				if i > 1 then eq(b.faction ~= plan[i - 1].faction, true, "never the same faction twice in a row") end
				local in_play = false
				for _, f in ipairs(director.factions(home, b.minute, s)) do
					if f == b.faction then in_play = true end
				end
				eq(in_play, true, b.faction .. " in play at " .. b.minute)
				eq(bosses.UNITS[b.faction] ~= nil, true)
			end
		end
	end
end)

test("seeds_give_more_than_one_boss_faction", function()
	local seen = {}
	for s = 1, 200 do seen[bosses.plan("bugs", s * 101)[2].faction] = true end
	eq(seen.bugs and seen.cyborgs and seen.illuminates and true, true, "the last boss can be any faction")
end)

test("a_plan_loads_each_boss_package_once", function()
	local list = bosses.packages({ { faction = "bugs" }, { faction = "bugs" } })
	eq(#list, 1)
	eq(list[1], "resource_packages/race_bugs_boss")
	list = bosses.packages({ { faction = "bugs" }, { faction = "illuminates" } })
	eq(#list, 2)
	eq(list[2], "resource_packages/race_illuminates_boss")
end)

test("the_boss_due_is_the_last_minute_reached", function()
	local plan = { { minute = 10 }, { minute = 15 } }
	eq(bosses.due(plan, 9.9), nil)
	eq(bosses.due(plan, 10), 1)
	eq(bosses.due(plan, 14.5), 1)
	eq(bosses.due(plan, 15), 2)
	eq(bosses.due(plan, 40), 2)
end)

test("the_boss_music_is_3_db_over_the_player_s_music_volume", function()
	-- Boot: slider 10 is 0 dB, each step down 4 dB, 0 is silent.
	eq(bosses.music_db(10, false), 3)
	eq(bosses.music_db(7, false), -9)
	eq(bosses.music_db(nil, false), 3, "the game's default slider")
	eq(bosses.music_db(0, false), -60, "muted stays muted")
	eq(bosses.music_db(8, true), -60, "console background music mutes it, as the game does")
end)

test("the_boss_music_starts_with_a_boss_and_stays", function()
	local s = bosses.new_music()
	eq(bosses.music_step(s, false, nil), nil, "no boss yet")
	eq(bosses.music_step(s, true, nil), "play")
	s.on = true
	eq(bosses.music_step(s, false, 3), "volume", "the boost goes on once it plays")
	s.db = 3
	eq(bosses.music_step(s, false, 3), nil, "the boss gone, the music stays")
	eq(bosses.music_step(s, true, -9), "volume", "the player's slider moved")
end)

test("a_warp_lands_at_its_target_or_on_a_jump", function()
	local w = { target = { x = 8, y = 0, z = 0 } }
	eq(dive.landed(w, { x = 0, y = 0, z = 0 }), false)
	eq(dive.landed(w, { x = 7.5, y = 0.2, z = 0.4 }), true, "lifted a little where the player didn't fit")
	local remote = { last = { x = 0, y = 0, z = 0 } }
	eq(dive.landed(remote, { x = 0.3, y = 0, z = 0 }), false, "a dive's own movement")
	eq(dive.landed(remote, { x = 7, y = 0, z = 0 }), true)
	eq(dive.landed({}, { x = 7, y = 0, z = 0 }), false, "no frame to compare yet")
end)

test("a_boss_holds_a_fifth_of_its_health", function()
	eq(bosses.HEALTH_SHARE, 0.2)
	eq(bosses.boss_health("characters/bug_boss/bug_boss", 25000), 5000)
	eq(bosses.boss_health("characters/cyborg_boss/cyborg_boss_gatling_gun", 1500), 300, "a part of the Siegemech too")
	eq(bosses.boss_health("characters/illuminate_boss/illuminate_boss", 3), 1, "never under 1")
	eq(bosses.boss_health("characters/bug_warrior/bug_warrior", 270), 270, "not a boss")
	eq(bosses.boss_health(nil, 270), 270)
end)

test("every_upgrade_holds_up_past_its_limit_for_testing", function()
	local debug = obsidian.module("src/debug")
	local upgrades = obsidian.module("src/upgrades")
	for _, u in ipairs(upgrades.list) do
		local most = debug.most(u)
		if (u.max or 9) > 1 then eq(most, (u.max or 9) * 2, u.id) else eq(most, 1, u.id) end
		if u.text then
			local ok, text = pcall(u.text, most)
			eq(ok and type(text), "string", u.id .. " card text at " .. most)
		end
	end
	eq(upgrades.pockets_seconds(40) >= 1, true)
end)

test("absolute_freedom_makes_firearms_ignore_armor", function()
	local perks = obsidian.module("src/perks")
	local stats = perks.stats()
	stats.pierce = true
	local c = perks.weapon_changes(stats, "primary_weapon", "firearm")
	eq(c.ignore_armor, true, "armor to 0, not only 15 off")
	eq(c.armorpiercing, true)
	eq(perks.weapon_changes(stats, "support_weapon", "firearm").ignore_armor, true, "a support machine gun too")
	local beam = perks.weapon_changes(stats, "primary_weapon", "beamweapon")
	eq(beam.ignore_armor, nil, "a beam's hit doesn't carry it")
	eq(beam.armorpiercing, true)
	eq(perks.weapon_changes(stats, "support_weapon", "flameweapon").armorpiercing, nil)
	stats.pierce = false
	eq(perks.weapon_changes(stats, "primary_weapon", "firearm").ignore_armor, nil, "without the upgrade")
end)

test("absolute_freedom_marks_the_hits_of_lasers_flames_and_arcs_only_while_they_go_out", function()
	local armor = obsidian.module("src/armor")
	local sent = {}
	local real = function(unit, component, command, data) sent[#sent + 1] = { command = command, data = data } end
	local mine, theirs, me, them = {}, {}, {}, {}
	rawset(_G, "EntityAux", {
		queue_command_interface = real,
		has_component = function(u, c) return c == "equipment" end,
		state = function(u) return { wielder = (u == mine) and me or them } end,
	})
	local function stats_of(unit) if unit == me then return { pierce = true } end return nil end
	local function shoot(command)
		local aux = rawget(_G, "EntityAux")
		aux.queue_command_interface(nil, "damageable", command, { power = 50 })
		return "done"
	end
	eq(armor.run_marked(stats_of, mine, shoot, "do_damage"), "done")
	eq(sent[1].data.ignore_armor, true, "this player's laser")
	eq(sent[1].data.armorignore, true)
	eq(rawget(_G, "EntityAux").queue_command_interface, real, "put back right after")
	armor.run_marked(stats_of, theirs, shoot, "do_damage")
	eq(sent[2].data.ignore_armor, nil, "another player's weapon, or an enemy's flamer")
	armor.run_marked(stats_of, mine, shoot, "fire")
	eq(sent[3].data.ignore_armor, nil, "only hits")
	local ok = pcall(armor.run_marked, stats_of, mine, function() error("boom") end)
	eq(ok, false)
	eq(rawget(_G, "EntityAux").queue_command_interface, real, "put back after an error too")
	rawset(_G, "EntityAux", nil)
end)

return T
