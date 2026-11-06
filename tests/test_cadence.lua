-- 2.7.0's run cadence: the faction order, the boss order and packages, boss health by squad size, the
-- budget past 10 minutes, the tier 4 cap, the bombardment windows, Tank Hunter and the first anti-tank pick.
obsidian.import = obsidian.import or function() return {} end
local director = obsidian.module("src/director")
local bosses = obsidian.module("src/bosses")
local bombard = obsidian.module("src/bombard")
local hunter = obsidian.module("src/hunter")
local draft = obsidian.module("src/draft")
local rules = obsidian.module("src/rules")
local rng = obsidian.module("src/rng")
local upgrades = obsidian.module("src/upgrades")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("bosses_come_at_10_20_and_every_5_minutes_after", function()
	eq(director.boss_minute(1), 10)
	eq(director.boss_minute(2), 20)
	eq(director.boss_minute(3), 25)
	eq(director.boss_minute(6), 40)
	eq(director.bosses_by(9.99), 0)
	eq(director.bosses_by(10), 1)
	eq(director.bosses_by(19.9), 1)
	eq(director.bosses_by(20), 2)
	eq(director.bosses_by(24.9), 2)
	eq(director.bosses_by(25), 3)
	eq(director.bosses_by(41), 6)
	eq(rules.RUN_LENGTH, 15 * 60)
	eq(rules.OBJECTIVES_GONE_AT > rules.RUN_LENGTH, true, "follows the run's length")
end)

test("the_first_boss_is_of_the_home_or_joined_faction_and_every_package_loads", function()
	local firsts = {}
	for _, home in ipairs(director.FACTIONS) do
		for s = 1, 300 do
			local seed = 971000000 + s * 37
			local order = director.order(home, seed)
			local plan = bosses.plan(home, seed)
			eq(plan[1].faction == home or plan[1].faction == order[2], true, "the first boss: " .. plan[1].faction)
			firsts[plan[1].faction == home and "home" or "joined"] = true
			local three = {}
			for i = 1, 3 do three[plan[i].faction] = true end
			eq(three.bugs and three.cyborgs and three.illuminates and true, true, "every faction in the first three")
			for i = 4, #plan do eq(plan[i].faction, plan[i - 3].faction, "a fixed turn of three") end
			eq(#bosses.packages(plan), 3, "every boss package loads with the level")
		end
	end
	eq(firsts.home and firsts.joined and true, true, "the first boss can be either")
end)

test("the_director_spawns_the_plans_boss_factions", function()
	local seed = 971004321
	local d = director.new("illuminates", rng.new(seed), nil, seed)
	local plan = bosses.plan("illuminates", seed)
	local n = 0
	for _ = 1, 26 * 60 do
		local out = director.update(d, 1, 1, 0)
		if out.boss then
			n = n + 1
			eq(out.spawns[1].faction, plan[n].faction, "boss " .. n)
		end
	end
	eq(n, 3)
end)

test("boss_health_grows_with_the_squad", function()
	near(bosses.health_share(1), 0.2)
	near(bosses.health_share(2), 0.3)
	near(bosses.health_share(3), 0.4)
	near(bosses.health_share(4), 0.5)
	near(bosses.health_share(8), 0.5, "four at most")
	near(bosses.health_share(nil), 0.2)
	eq(bosses.boss_health("characters/bug_boss/bug_boss", 25000, 4), 12500)
	eq(bosses.boss_health("characters/bug_boss/bug_boss", 25000, 2), 7500)
	eq(bosses.boss_health("characters/bug_warrior/bug_warrior", 270, 4), 270, "not a boss")
	eq(bosses.squad_size(), 1, "no game: one")
end)

test("the_budget_grows_at_half_the_rate_past_10_minutes", function()
	near(director.growth(5), 5)
	near(director.growth(10), 10)
	near(director.growth(20), 15)
	near(director.budget(10, 1, 15), 23.5)
	near(director.budget(20, 1, 15), 33.5)
	near(director.budget(40, 1, 15), 53.5)
	eq(director.budget(60, 1, 15) > director.budget(40, 1, 15), true, "no ceiling")
end)

test("tier_4_is_held_to_3_alive_per_player", function()
	eq(director.tier_limit(4, 1), 3)
	eq(director.tier_limit(4, 4), 12)
	eq(director.tier_limit(3, 4), math.huge)
	local alive = { bug_tank = 2, cyborg_hulk = 1 }
	local function alive_of(k) return alive[k] or 0 end
	eq(director.left_of("bug_impaler", alive_of, {}, 1), 0, "3 tier 4 alive, solo")
	eq(director.left_of("bug_impaler", alive_of, {}, 2), 3)
	eq(director.left_of("bug_impaler", alive_of, { illuminate_illusionist = 2 }, 2), 1, "planned ones count")
	-- A late solo run never has more than 3 alive.
	for seed = 1, 20 do
		local d = director.new("bugs", rng.new(seed), nil, seed)
		local units = {}
		local function count(k)
			local n = 0
			for _, u in ipairs(units) do if u == k then n = n + 1 end end
			return n
		end
		d.time = 30 * 60
		director.take_over(d, 30 * 60)
		for _ = 1, 600 do
			for _, s in ipairs(director.update(d, 0.5, 1, 0, count).spawns) do
				if s.tier == 4 then for _ = 1, s.count do units[#units + 1] = s.key end end
			end
			local n = 0
			for _, u in ipairs(units) do if (director.tier_of(u)) == 4 then n = n + 1 end end
			eq(n <= 3, true, "seed " .. seed .. ": " .. n)
		end
	end
end)

test("bombardment_windows_come_at_7_14_and_every_6_minutes_from_22", function()
	local function open(m) return bombard.window_of(m) ~= nil end
	eq(open(6.99), false) eq(open(7), true) eq(open(8.99), true) eq(open(9), false)
	eq(open(13.9), false) eq(open(14), true) eq(open(15.99), true) eq(open(16), false)
	eq(open(21.9), false) eq(open(22), true) eq(open(22.99), true) eq(open(23), false)
	eq(open(27.9), false) eq(open(28), true) eq(open(29), false) eq(open(34.5), true)
	eq(table.concat(bombard.starts(0, 40), ","), "7,14,22,28,34,40")
	eq(table.concat(bombard.starts(22, 28), ","), "28")
	-- The alarm sounds once, WARNING seconds before each window.
	local warned = {}
	local t = 0
	while t < 30 * 60 do
		if bombard.warns(t, t + 0.25) then warned[#warned + 1] = t + 0.25 end
		t = t + 0.25
	end
	eq(#warned, 4)
	eq(warned[1], 7 * 60 - bombard.WARNING)
	eq(warned[4], 28 * 60 - bombard.WARNING)
end)

test("strikes_fall_every_few_seconds_in_a_window_only", function()
	local s = bombard.new()
	eq(bombard.active(s, 6 * 60), false)
	eq(bombard.active(s, 7 * 60 + 1), true)
	eq(bombard.tick(s, 0.1, false), false)
	eq(bombard.tick(s, 0.1, true), true, "one at once")
	eq(bombard.tick(s, bombard.EVERY - 0.5, true), false)
	eq(bombard.tick(s, 1, true), true)
	bombard.force(s, 100)
	eq(bombard.active(s, 120), true, "the debug window")
	eq(bombard.active(s, 100 + bombard.DEBUG_SECONDS), false)
	eq(#bombard.STRIKES, 12)
	for _, name in ipairs(bombard.STRIKES) do eq(name ~= "stratagem_staticfield", true) end
end)

test("tank_hunter_hits_tier_4_and_bosses_for_15_percent_a_stack", function()
	local u = upgrades.by_id.tank_hunter
	eq(u.max, 5)
	eq(u.rarity, "common")
	eq(u.text(2), "Deal 15% more damage to heavy enemies and bosses.\nTotal: +30%")
	local stats = {}
	u.apply({ stat = function(_, k, v) stats[k] = v end }, 3, 1)
	near(stats.tank_hunter, 0.45)
	local catalog = {
		["characters/bug_tank/bug_tank"] = { key = "bug_tank" },
		["characters/cyborg_hulk/cyborg_hulk"] = { key = "cyborg_hulk" },
		["characters/bug_warrior/bug_warrior"] = { key = "bug_warrior" },
		["characters/cyborg_hulk/cyborg_hulk_assassinate"] = { key = "cyborg_hulk_assassinate" },
	}
	local function enemy_of(p) return catalog[p] end
	eq(hunter.is_tank("characters/bug_tank/bug_tank", enemy_of), true)
	eq(hunter.is_tank("characters/cyborg_hulk/cyborg_hulk", enemy_of), true)
	eq(hunter.is_tank("characters/cyborg_hulk/cyborg_hulk_assassinate", enemy_of), true, "tier 5 too")
	eq(hunter.is_tank("characters/bug_warrior/bug_warrior", enemy_of), false)
	eq(hunter.is_tank("characters/cyborg_boss/cyborg_boss_gatling_gun", enemy_of), true, "a boss part")
	eq(hunter.is_tank(nil, enemy_of), false)
	near(hunter.bonus(0.15, 1000, false), 150)
	eq(hunter.bonus(0.15, 1000, true), 0, "the mod's own hits and melee don't count")
	eq(hunter.bonus(0, 1000, false), 0)
	eq(hunter.bonus(0.15, 5, false), 0, "too small to send")
end)

test("the_first_stratagem_pick_offers_an_anti_tank_weapon", function()
	local pool = {
		{ id = "stratagem_resupply", kind = "supply" }, { id = "stratagem_machinegun", kind = "supply" },
		{ id = "stratagem_jumppack", kind = "supply" }, { id = "stratagem_flamethrower", kind = "supply" },
		{ id = "stratagem_mortar", kind = "supply" }, { id = "stratagem_law", kind = "supply" },
		{ id = "stratagem_airstrike", kind = "offensive" },
	}
	eq(draft.first_stratagem_pick(rules.STRATAGEM_EVERY), true)
	eq(draft.first_stratagem_pick(rules.STRATAGEM_EVERY * 2), false)
	for seed = 1, 200 do
		local row = draft.roll_stratagems(pool, rng.new(seed), 3, "supply", draft.ANTI_TANK)
		eq(#row, 3)
		local at, ids = false, {}
		for _, s in ipairs(row) do
			if s.id == "stratagem_law" then at = true end
			eq(ids[s.id], nil, "no stratagem twice")
			ids[s.id] = true
		end
		eq(at, true, "seed " .. seed)
	end
	-- Without one unlocked, the row is as before.
	local none = { pool[1], pool[2], pool[3], pool[4] }
	eq(#draft.roll_stratagems(none, rng.new(3), 3, "supply", draft.ANTI_TANK), 3)
	eq(table.concat(draft.ANTI_TANK, ","), "stratagem_recoilless,stratagem_law,stratagem_satchelcharge")
end)

return T
