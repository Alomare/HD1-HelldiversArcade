local rules = obsidian.module("src/rules")
local rng = obsidian.module("src/rng")
local xp = obsidian.module("src/xp")
local upgrades = obsidian.module("src/upgrades")
local draft = obsidian.module("src/draft")
local director = obsidian.module("src/director")
local orbs = obsidian.module("src/orbs")
local sync = obsidian.module("src/sync")
local seed = obsidian.module("src/seed")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

-- The game's own DifficultySettings, as far as seeds go (lua/settings/difficulty_settings.lua).
local Difficulty = {
	time_of_day_lookup = { 1, 2, 3, 4 }, shading_environment_lookup = { 1, 2, 3, 4, 5, 6, 7 },
	environment_lookup = { 1, 2, 3, 4, 5, 6 }, environment_variants = { 1, 2, 3, 4, 5, 6 }, enemy_lookup = { 1, 2, 3 },
	mission_type_lookup = { 1, 2, 3, 4, 5 }, mission_type_seed_base = 20, max_difficulty = 15,
}
function Difficulty.modulate_seed(a0, a1, a2, a3, a4, a5, a6, a7)
	local d = Difficulty
	local r = math.floor(a7 / 10000000) * 10000000
	r = r + 1000000 * (a0 % #d.time_of_day_lookup) + 100000 * (a1 % #d.shading_environment_lookup)
	r = r + 10000 * (a2 % #d.environment_lookup) + 1000 * (a3 % #d.environment_variants) + 100 * (a4 % #d.enemy_lookup)
	r = r + (a5 % #d.mission_type_lookup) * d.mission_type_seed_base
	return r + math.max(1, math.min(a6, d.max_difficulty))
end
function Difficulty.get_mission_params(s)
	local d = Difficulty
	return {
		time_of_day = math.floor(s / 1000000) % 10 % #d.time_of_day_lookup,
		environment = math.floor(s / 10000) % 10 % #d.environment_lookup,
		enemy = math.floor(s / 100) % 10 % #d.enemy_lookup,
		mission_type = math.floor((s % 100) / d.mission_type_seed_base) % #d.mission_type_lookup,
		difficulty = math.max(1, math.min((s % 100) % d.mission_type_seed_base, d.max_difficulty)),
	}
end

test("a_survivors_seed_reads_as_the_mission_it_describes", function()
	local s = seed.make(Difficulty, { time = 3, light = 2, environment = 4, variant = 1, enemy = 2, difficulty = 7 })
	eq(seed.is_survivors(s), true)
	eq(s < 2 ^ 31, true, "fits a signed 32-bit number")
	local p = Difficulty.get_mission_params(s)
	eq(p.time_of_day, 2) eq(p.environment, 3) eq(p.enemy, 1) eq(p.mission_type, 0, "a normal mission") eq(p.difficulty, 7)
	eq(seed.is_survivors(1234567), false)
	eq(seed.is_survivors(Difficulty.modulate_seed(0, 0, 0, 0, 0, 0, 5, 50000000)), false, "a training seed")
end)

test("levels_get_steeper_and_a_total_gives_one_level", function()
	eq(xp.need(1), 14)
	for level = 1, 40 do eq(xp.need(level + 1) > xp.need(level), true, "level " .. level) end
	local level, into, need = xp.level_of(xp.need(1) + xp.need(2) + 3)
	eq(level, 3) eq(into, 3) eq(need, xp.need(3))
	eq((xp.level_of(0)), 1)
	eq((xp.level_of(xp.need(1) - 1)), 1)
end)

test("the_xp_bar_eases_to_its_value_and_pulses_as_samples_come_in", function()
	local bar = xp.bar_new()
	local fill, pulse = xp.bar_step(bar, 4, 0.016)
	near(fill, 4 / xp.need(1), "the first frame shows the value at once")
	eq(pulse, 0, "and no pulse")
	fill, pulse = xp.bar_step(bar, 6, 0.016)
	eq(fill > 4 / xp.need(1) and fill < 6 / xp.need(1), true, "a gain eases in")
	eq(pulse, 1, "and pulses")
	local before = fill
	fill, pulse = xp.bar_step(bar, 6, 0.1)
	eq(fill > before and fill <= 6 / xp.need(1), true, "closing on the value, never past it")
	eq(pulse < 1 and pulse > 0, true, "the pulse fades")
	for _ = 1, 120 do fill, pulse = xp.bar_step(bar, 6, 0.016) end
	near(fill, 6 / xp.need(1), "settled on the value")
	eq(pulse, 0, "the pulse gone")
	-- A level up: the bar runs to its end, then fills the new level from empty.
	local total = xp.need(1) + 2
	fill = xp.bar_step(bar, total, 0.05)
	eq(fill > 6 / xp.need(1), true, "on its way to the end, not back down")
	local wrapped = false
	for _ = 1, 120 do
		local f = xp.bar_step(bar, total, 0.016)
		if f < fill then wrapped = true end
		fill = f
	end
	eq(wrapped, true, "it starts again from empty")
	near(fill, 2 / xp.need(2), "and settles on the new level's share")
	-- Several levels at once: only the last one fills.
	xp.bar_step(bar, xp.need(1) + xp.need(2) + xp.need(3) + 1, 0)
	eq(bar.pos >= 3, true, "no more than one level behind")
	-- A new run's lower total shows at once.
	fill, pulse = xp.bar_step(bar, 1, 0.016)
	near(fill, 1 / xp.need(1)) eq(pulse, 0)
	eq(xp.bar_color(0), "#3a8ee6", "the bar's blue")
	eq(xp.bar_color(1), "#9cd2ff", "brighter at a full pulse")
	eq(xp.bar_color(5), xp.bar_color(1), "never past it")
end)

test("levels_ask_more_at_first_and_grow_slower_than_2_3_0", function()
	local function old(level) return math.floor(8 + 5.4 * (level - 1) + 0.72 * (level - 1) ^ 1.6 + 0.5) end
	for level = 1, 3 do eq(xp.need(level) > old(level), true, "level " .. level .. " asks more") end
	for level = 5, 40 do eq(xp.need(level) < old(level), true, "level " .. level .. " asks less") end
	for level = 2, 40 do
		eq(xp.need(level) - xp.need(level - 1) < old(level) - old(level - 1), true, "level " .. level .. " grows slower")
	end
	eq(xp.need(10), 67)
	eq(xp.need(20), 144)
end)

test("every_upgrade_can_be_shown_and_applied", function()
	local seen = {}
	local calls = {}
	local env = setmetatable({}, { __index = function(_, k) return function(...) calls[#calls + 1] = k end end })
	for _, u in ipairs(upgrades.list) do
		eq(seen[u.id], nil, "a second " .. u.id)
		seen[u.id] = true
		eq(type(u.name) == "string" and #u.name > 0, true, u.id .. " name")
		eq(type(u.icon) == "string" and #u.icon > 0, true, u.id .. " icon")
		local found
		for _, r in ipairs(rules.RARITIES) do if r.id == u.rarity then found = true end end
		eq(found, true, u.id .. " rarity")
		for n = 1, u.max or 3 do eq(type(u.text(n)), "string", u.id .. " text") end
		u.apply(env, 1, 1)
	end
	eq(#calls >= #upgrades.list, true, "each apply reaches the game")
	for _, r in ipairs(rules.RARITIES) do
		local any
		for _, u in ipairs(upgrades.list) do if u.rarity == r.id then any = true end end
		eq(any, true, "an upgrade of each rarity: " .. r.id)
	end
end)

-- Images kit:icon can draw in a mission: the stratagem icons (LoadoutSettings.stratagems).
local STRATAGEM_ICONS = {}
for name in ([[stratagem_reinforcements stratagem_hellbomb stratagem_metal_detector stratagem_emergency_beacon
	stratagem_resupply stratagem_machinegun stratagem_lasercannon stratagem_recoillessrifle stratagem_drone_defensive
	stratagem_drone_heal stratagem_ammo_backpack stratagem_jumppack stratagem_projected_shield stratagem_shield_generator_pack
	stratagem_uav stratagem_airstrike stratagem_orbital_strike stratagem_railcannon_strike stratagem_missile_barrage
	stratagem_turret stratagem_tesla_tower]]):gmatch("%S+") do
	STRATAGEM_ICONS[name] = true
end

test("every_card_icon_is_one_the_kit_can_draw", function()
	for _, u in ipairs(upgrades.list) do eq(STRATAGEM_ICONS[u.icon], true, u.id .. ": " .. u.icon) end
	eq(STRATAGEM_ICONS[upgrades.fallback.icon], true)
end)

test("a_row_has_three_different_cards", function()
	local r = rng.new(1)
	for _ = 1, 200 do
		local row = draft.roll({}, 1, r)
		eq(#row, 3)
		eq(row[1] ~= row[2] and row[2] ~= row[3] and row[1] ~= row[3], true, "no repeats")
	end
end)

test("an_upgrade_at_its_limit_isnt_offered_and_patch_up_fills_in", function()
	local owned = {}
	for _, u in ipairs(upgrades.list) do owned[u.id] = u.max end
	owned.oxygenator = 0
	local row = draft.roll(owned, 5, rng.new(3))
	eq(#row, 2, "the one left and the fallback")
	local ids = { [row[1].id] = true, [row[2].id] = true }
	eq(ids.oxygenator and ids.patch_up, true)
end)

test("an_upgrade_already_held_comes_up_more_often", function()
	local r = rng.new(21)
	local held, other, n = 0, 0, 0
	for _, u in ipairs(upgrades.list) do
		if u.rarity == "common" then n = n + 1 end
	end
	for _ = 1, 3000 do
		for _, u in ipairs(draft.roll({ oxygenator = 1 }, 1, r)) do
			if u.id == "oxygenator" then held = held + 1 elseif u.id == "panic" then other = other + 1 end
		end
	end
	eq(held > other * 2, true, "held " .. held .. " against " .. other)
	eq(held < other * 4, true, "but not every row")
	eq(rules.HELD_WEIGHT, 3)
end)

test("patch_up_comes_only_when_a_slot_cant_be_filled", function()
	local r = rng.new(12)
	for _ = 1, 300 do
		for _, u in ipairs(draft.roll({}, 10, r)) do eq(u.id ~= "patch_up", true, "the pool is full") end
	end
end)

test("upgrades_a_player_cant_use_arent_offered", function()
	local r = rng.new(5)
	local function allowed(u) return u.needs == nil and u.primary == nil end
	for _ = 1, 300 do
		for _, u in ipairs(draft.roll({}, 20, r, 4, allowed)) do
			eq(u.needs, nil, u.id)
			eq(u.primary, nil, u.id)
		end
	end
end)

test("stratagem_levels_cycle_supply_offensive_defensive_and_fall_back_to_a_mix", function()
	eq(draft.stratagem_kind(2), nil)
	eq(draft.stratagem_kind(3), "supply")
	eq(draft.stratagem_kind(6), "offensive")
	eq(draft.stratagem_kind(9), "defensive")
	eq(draft.stratagem_kind(12), "supply", "round again")
	local pool = {}
	for i = 1, 4 do pool[#pool + 1] = { id = "s" .. i, kind = "supply" } end
	for i = 1, 2 do pool[#pool + 1] = { id = "o" .. i, kind = "offensive" } end
	local r = rng.new(3)
	for _ = 1, 50 do
		for _, s in ipairs(draft.roll_stratagems(pool, r, 3, "supply")) do eq(s.kind, "supply") end
	end
	-- Two offensive ones can't fill three: a mix, as Broad Permit's five can't be filled by four supply.
	local mixed = {}
	for _ = 1, 50 do
		for _, s in ipairs(draft.roll_stratagems(pool, r, 3, "offensive")) do mixed[s.kind] = true end
	end
	eq(mixed.supply, true, "the mixed pool")
	eq(#draft.roll_stratagems(pool, r, 5, "supply"), 5, "Broad Permit: five from the mix")
end)

test("stratagems_come_every_three_levels_until_twelve_and_never_twice_in_a_row", function()
	eq(draft.offers_stratagems(3, 5), true)
	eq(draft.offers_stratagems(9, 11), true)
	eq(draft.offers_stratagems(4, 5), false)
	eq(draft.offers_stratagems(12, 12), false, "twelve is the most")
	local pool = {}
	for i = 1, 6 do pool[i] = { id = i } end
	local r = rng.new(8)
	for _ = 1, 100 do
		local row = draft.roll_stratagems(pool, r, 5)
		eq(#row, 5)
		local seen = {}
		for _, s in ipairs(row) do
			eq(seen[s.id], nil, "no repeat")
			seen[s.id] = true
		end
	end
	eq(#draft.roll_stratagems({ pool[1] }, r, 3), 1, "no more than the pool has")
	eq(#pool, 6, "the pool stays whole")
end)

test("the_readme_lists_every_upgrade_with_its_card_text", function()
	local f = assert(io.open("README.md", "rb"))
	local text = f:read("*a")
	f:close()
	for _, u in ipairs(upgrades.list) do
		local body = u.text(1):match("^(.-)\nTotal:") or u.text(1)
		eq(text:find("| " .. u.name .. " | " .. body .. " |", 1, true) ~= nil, true, u.name)
	end
end)

test("a_perk_is_offered_when_owned_not_held_and_its_kind_is_free", function()
	local all = function() return true end
	local by = upgrades.by_id
	eq(upgrades.perk_open(by.cardio_accelerator, {}, all), true)
	eq(upgrades.perk_open(by.cardio_accelerator, { perk_cardio = true }, all), false, "held as the main perk or an extra")
	eq(upgrades.perk_open(by.cardio_accelerator, {}, function() return false end), false, "not owned")
	eq(upgrades.perk_open(by.stun_grenades, { perk_grenade_incendiary = true }, all), false, "one kind of grenade")
	eq(upgrades.perk_open(by.pyro, { perk_revolver_sidearm = true }, all), false, "one sidearm")
	eq(upgrades.perk_open(by.pyro, { perk_grenade_incendiary = true }, all), true, "a grenade doesn't take the sidearm's place")
	for _, u in ipairs(upgrades.list) do
		eq(u.perk ~= "perk_lasersight", true, "laser sight needs the main perk's frame code")
	end
end)

test("rarities_come_at_about_their_weights_and_legendaries_grow_with_level", function()
	local function share(level)
		local r, count = rng.new(7), { common = 0, rare = 0, perk = 0, legendary = 0 }
		for _ = 1, 4000 do local c = draft.roll({}, level, r, 1)[1].rarity count[c] = count[c] + 1 end
		return count
	end
	local early, late = share(1), share(30)
	eq(early.common > early.rare and early.rare > early.perk and early.perk > early.legendary, true, "common, then rare, then perk, then legendary")
	eq(early.legendary > 80 and early.legendary < 330, true, "about 5 in 100 at level 1: " .. early.legendary)
	eq(late.legendary > early.legendary, true, "more legendaries later")
	local w = draft.weights(200)
	eq(w.common, rules.RARITY_FLOOR, "common never drops below its floor")
end)

test("the_director_starts_with_the_missions_faction_and_brings_in_the_others", function()
	local order = director.order("cyborgs", 1234)
	eq(order[1], "cyborgs")
	eq(table.concat(director.factions("cyborgs", 0, 1234), ","), "cyborgs")
	eq(table.concat(director.factions("cyborgs", 5.9, 1234), ","), "cyborgs")
	eq(table.concat(director.factions("cyborgs", 6, 1234), ","), "cyborgs," .. order[2])
	eq(table.concat(director.factions("cyborgs", 11.9, 1234), ","), "cyborgs," .. order[2])
	eq(#director.factions("cyborgs", 12, 1234), 3)
	-- The second faction is either of the other two, by the seed, and the same for the same seed.
	local seen = {}
	for s = 1, 100 do
		local o = director.order("bugs", s * 7919)
		eq(o[2], director.order("bugs", s * 7919)[2])
		eq(o[2] ~= "bugs" and o[3] ~= "bugs" and o[2] ~= o[3], true)
		seen[o[2]] = true
	end
	eq(seen.cyborgs and seen.illuminates and true, true, "both can come second")
	local d = director.new("bugs", rng.new(11))
	local first = director.update(d, 0.1, 1, 0)
	eq(#first.spawns > 0, true, "something at once")
	for _, s in ipairs(first.spawns) do
		eq(s.faction, "bugs")
		eq(director.from(s.key, s.tier), 1, "only what Heat 1 offers at the start: " .. s.key)
	end
	local again = director.update(d, 1, 1, 0)
	eq(#again.spawns, 0, "nothing before the next spawn")
end)

test("the_director_spends_more_over_time_and_never_past_the_cap", function()
	local function spent(minutes, players)
		local d = director.new("illuminates", rng.new(5))
		director.update(d, minutes * 60, players, 0)
		-- Mid-wave, with a spawn due.
		d.next_spawn, d.rest_left, d.wave_left = 0, nil, rules.WAVE_SECONDS
		local total, count = 0, 0
		for _, s in ipairs(director.update(d, 0.01, players, 0).spawns) do
			total = total + rules.ORB_XP[s.tier] * s.count
			count = count + s.count
		end
		return total, count
	end
	local early, late = spent(0, 1), spent(9, 1)
	eq(late > early, true, "a bigger budget later: " .. early .. " then " .. late)
	eq(spent(9, 4) > late, true, "more for more players")
	local d = director.new("bugs", rng.new(2))
	d.time = 600
	local n = 0
	for _, s in ipairs(director.update(d, 0.01, 4, rules.ALIVE_CAP - 3).spawns) do n = n + s.count end
	eq(n <= 3 + 1, true, "room for 3, and the boss due at 10 minutes: " .. n)
	local easy = director.new("bugs", rng.new(2), 4)
	easy.time = 600
	n = 0
	for _, s in ipairs(director.update(easy, 0.01, 4, rules.alive_cap(4) - 2).spawns) do n = n + s.count end
	eq(n <= 2 + 1, true, "an easier mission's cap is lower: " .. n)
end)

test("bosses_come_at_their_minutes_and_the_run_is_won_at_its_end", function()
	local d = director.new("cyborgs", rng.new(9))
	local bosses = {}
	local won
	for second = 1, 31 * 60 do
		local out = director.update(d, 1, 2, 0)
		if out.boss then
			bosses[#bosses + 1] = second
			eq((director.tier_of(out.boss)), 5)
		end
		if out.won then won = second end
	end
	eq(#bosses, 4)
	eq(bosses[1], 600) eq(bosses[2], 1200) eq(bosses[3], 1500) eq(bosses[4], 1800)
	eq(won, 900, "the shuttle at 15:00")
end)

test("every_enemy_the_director_names_is_one_tier", function()
	for faction, tiers in pairs(director.ROSTER) do
		eq(#tiers, 5, faction)
		for tier, keys in ipairs(tiers) do
			for _, key in ipairs(keys) do
				local t, f = director.tier_of(key)
				eq(t, tier, key) eq(f, faction, key)
			end
		end
	end
	eq(director.tier_of("nope"), nil)
end)

test("about_three_kills_in_four_drop_a_sample_and_every_machine_agrees", function()
	local yes, total = 0, 0
	for x = -200, 200, 2 do
		for y = -200, 200, 2 do
			total = total + 1
			if rules.drops_sample(x + 0.5, y + 0.5) then yes = yes + 1 end
			eq(rules.drops_sample(x + 0.5, y + 0.5), rules.drops_sample(x + 0.9, y + 0.9), "the same spot, a little off")
		end
	end
	eq(yes / total > 0.72 and yes / total < 0.78, true, "the share: " .. yes / total)
end)

test("an_orb_goes_to_the_player_who_reaches_it", function()
	local o = orbs.new()
	orbs.drop(o, { x = 0, y = 0, z = 0 }, 3)
	orbs.drop(o, { x = 30, y = 0, z = 0 }, 5)
	local me = { pos = { x = 0.5, y = 0, z = 0 }, is_local = true }
	local them = { pos = { x = 30, y = 0.5, z = 0 }, is_local = false }
	local got, by = orbs.update(o, 0.1, { me, them })
	eq(got, 3, "only this machine's player counts")
	eq(by[1], 3)
	eq(#o.list, 0, "the other player's orb is gone too")
end)

test("an_orb_flies_to_a_player_within_its_pull_and_a_magnet_reaches_further", function()
	local rules = obsidian.module("src/rules")
	local start = (rules.ORB_RADIUS + rules.ORB_MAGNET) / 2
	local o = orbs.new()
	orbs.drop(o, { x = start, y = 0, z = 0 }, 1)
	local me = { pos = { x = 0, y = 0, z = 0 }, is_local = true }
	eq((orbs.update(o, 0.01, { me })), 0)
	eq(o.list[1].x < start, true, "it moves closer")
	local got = 0
	for _ = 1, 20 do got = got + orbs.update(o, 0.05, { me }) end
	eq(got, 1)
	local step = orbs.new()
	orbs.drop(step, { x = rules.ORB_MAGNET + 0.5, y = 0, z = 0 }, 1)
	eq((orbs.update(step, 0.05, { me })), 0, "out of reach: the player has to step on it")
	eq(step.list[1].x, rules.ORB_MAGNET + 0.5, "and it stays put")
	local far = orbs.new()
	orbs.drop(far, { x = rules.ORB_RADIUS * 1.5, y = 0, z = 0 }, 1)
	eq((orbs.update(far, 0, { { pos = me.pos, is_local = true, magnet = 2 } })), 1, "a doubled radius takes it at once")
end)

test("orbs_wear_off_and_too_many_merge_without_losing_xp", function()
	local o = orbs.new()
	orbs.drop(o, { x = 100, y = 100 }, 1)
	orbs.update(o, rules.ORB_LIFE + 1, {})
	eq(#o.list, 0)
	for i = 1, rules.ORB_LIMIT + 10 do orbs.drop(o, { x = i * 10, y = 0 }, 1) end
	eq(#o.list, rules.ORB_LIMIT)
	local total = 0
	for _, orb in ipairs(o.list) do total = total + orb.xp end
	eq(total, rules.ORB_LIMIT + 10)
end)

-- What machine `peer` shares in mission 970000006, run `run`.
local function peer_value(xp_, chosen, run, time, host)
	return sync.decode(string.format("970000006;%d;%d;%d;%d;%d", run or 1, xp_, chosen, time or 0, host and 1 or 0))
end

test("every_machine_waits_for_the_slowest_to_choose", function()
	local s = sync.new(970000006, 5)
	sync.set_peer(s, "b", peer_value(0, 1))
	eq(sync.choosing(s), false)
	sync.collected(s, xp.need(1))
	eq(sync.level(s), 2)
	eq(sync.to_choose(s), 2)
	eq(sync.choosing(s), true)
	sync.chose(s, 2)
	eq(sync.to_choose(s), nil)
	eq(sync.choosing(s), true, "the other machine hasn't chosen")
	sync.set_peer(s, "b", peer_value(0, 2))
	eq(sync.choosing(s), false)
	sync.set_peer(s, "b", peer_value(0, 2))
	sync.collected(s, xp.need(2))
	sync.set_peer(s, "b", nil)
	eq(sync.choosing(s), true, "this machine still has its own level")
	sync.chose(s, 3)
	eq(sync.choosing(s), false, "a machine that left doesn't hold anyone")
end)

test("the_teams_xp_is_the_sum_of_every_machines", function()
	local s = sync.new(970000006, 5)
	sync.collected(s, 5)
	sync.set_peer(s, "b", peer_value(7, 1))
	eq(sync.team_xp(s), 12)
	eq(sync.encode(s, 61.7, true), "970000006;5;5;1;61;1;0")
	eq(sync.decode("nonsense"), nil)
	eq(sync.decode("7;1"), nil, "the old format")
	eq(sync.decode(nil), nil)
	local back = sync.decode(sync.encode(s, 61.7, false))
	eq(back.mission, 970000006) eq(back.run, 5) eq(back.xp, 5) eq(back.chosen, 1) eq(back.time, 61) eq(back.host, false)
end)

test("both_machines_work_out_the_same_level_from_shares_of_a_sample", function()
	-- Molecular Scan makes shares of a sample. Each machine sees the other's as whole samples, so its
	-- own count has to be whole as well, or one machine levels up alone and waits for the other forever.
	local a, b = sync.new(970000006, 1), sync.new(970000006, 2)
	sync.collected(a, xp.need(1) - 0.4)
	sync.set_peer(b, "a", sync.decode(sync.encode(a, 0, true)))
	sync.set_peer(a, "b", sync.decode(sync.encode(b, 0, false)))
	eq(sync.team_xp(a), sync.team_xp(b))
	eq(sync.level(a), sync.level(b))
	eq(sync.level(a), 1)
end)

test("a_machine_that_leaves_keeps_its_xp_in_the_sum_and_comes_back_without_counting_twice", function()
	local s = sync.new(970000006, 5)
	sync.collected(s, 10)
	sync.set_peer(s, "b", peer_value(30, 3, 7))
	eq(sync.team_xp(s), 40)
	sync.set_peer(s, "b", nil)
	eq(sync.team_xp(s), 40, "its samples stay the squad's")
	sync.set_peer(s, "b", peer_value(32, 3, 7))
	eq(sync.team_xp(s), 42, "the same run back: its value takes over")
	sync.set_peer(s, "b", nil)
	sync.set_peer(s, "b", peer_value(4, 1, 9))
	eq(sync.team_xp(s), 46, "a new run of its own adds to what it had")
	eq(sync.choosing(s), true, "and it has levels to choose")
end)

test("another_missions_value_doesnt_count", function()
	-- Lobby data outlives the mission: a machine still loading shows the last mission's numbers.
	local s = sync.new(970000006, 5)
	sync.set_peer(s, "b", sync.decode("970000105;3;5000;25;900;0"))
	eq(sync.team_xp(s), 0)
	eq(sync.level(s), 1)
	eq(sync.choosing(s), false)
end)

test("the_hosts_clock_is_known_to_the_others", function()
	local s = sync.new(970000006, 5)
	eq(sync.host_time(s), nil)
	sync.set_peer(s, "b", peer_value(0, 1, 2, 300, false))
	eq(sync.host_time(s), nil, "not the host")
	sync.set_peer(s, "c", peer_value(0, 1, 3, 412, true))
	eq(sync.host_time(s), 412)
end)

test("a_new_host_picks_the_director_up_at_the_runs_clock", function()
	local d = director.new("bugs", rng.new(4))
	director.take_over(d, 11 * 60)
	eq(d.time, 660)
	eq(d.bosses_done, 1, "the boss at 10 minutes came with the old host")
	local out = director.update(d, 0.1, 2, 0)
	eq(out.boss, nil, "it doesn't come again")
	eq(#out.spawns > 0, true, "spawning goes on at once")
	local late = director.new("bugs", rng.new(4))
	director.take_over(late, rules.RUN_LENGTH + 5)
	eq(director.update(late, 0.1, 2, 0).won, nil, "won once, by the old host")
end)

test("peak_physique_adds_melee_damage_and_attack_rate_a_stack", function()
	local perks = obsidian.module("src/perks")
	local perks_stats = { melee = 1 }
	local changes = upgrades.by_id.peak_physique
	local stats = {}
	changes.apply({ stat = function(_, name, value) stats[name] = value end }, 3, 1)
	near(stats.melee, 1.9, "+30% damage a stack")
	near(stats.melee_rate, 2.5, "+50% attack rate a stack")
	local c = perks.melee_changes(stats)
	near(c.power, 1.9)
	near(c.duration, 0.4, "the swing over in 0.4 of the time")
	near(c.delay, 0.4, "and a bayonet's hit inside it")
	eq(next(perks.melee_changes(perks.stats())), nil, "nothing at no stacks")
	eq(changes.text(1), "Increase melee damage by 30% and melee attack rate by 50%.\nTotal: +30%, +50%")
	eq(upgrades.by_id.peak_physique.max, 5)
	eq(upgrades.by_id.guard_dog.max, 3)
	eq(upgrades.by_id.angel.max, 3)
	eq(perks_stats.melee, 1)
end)

test("two_levels_at_once_are_chosen_one_after_the_other", function()
	local s = sync.new()
	sync.collected(s, xp.need(1) + xp.need(2))
	eq(sync.to_choose(s), 2)
	sync.chose(s, 2)
	eq(sync.to_choose(s), 3)
	sync.chose(s, 3)
	eq(sync.choosing(s), false)
end)

test("the_steps_come_apart_and_every_change_is_announced_once", function()
	eq(director.threat(0), 1)
	eq(director.threat(1.99), 1)
	eq(director.threat(2), 2)
	eq(director.threat(5), 3)
	eq(director.threat(8.99), 3)
	eq(director.threat(9), 4, "Heat 4 at 9:00")
	eq(director.threat(14), 5)
	eq(director.threat(20), director.THREATS)
	local seen = {}
	local minute = 0
	while minute < 20 do
		for _, e in ipairs(director.events("bugs", minute, minute + 0.25)) do
			seen[#seen + 1] = minute + 0.25 .. ":" .. e.kind .. (e.faction and ("=" .. e.faction) or "")
		end
		minute = minute + 0.25
	end
	local o = director.order("bugs", nil)
	local b1, b2 = director.boss_faction("bugs", nil, 1), director.boss_faction("bugs", nil, 2)
	eq(table.concat(seen, " "), "2:heat 5:heat 6:faction=" .. o[2] .. " 9:heat 10:boss=" .. b1 .. " 12:faction=" .. o[3]
		.. " 14:heat 20:boss=" .. b2)
end)

test("the_camera_draws_back_with_each_level_up_to_a_quarter", function()
	local rules = obsidian.module("src/rules")
	near(rules.camera_distance(1), 17)
	near(rules.camera_distance(2), 17 * 1.025)
	near(rules.camera_distance(11), 17 * 1.25)
	near(rules.camera_distance(40), 17 * 1.25, "no further than a quarter")
end)

local fight = obsidian.module("src/fight")
local dive = obsidian.module("src/dive")

local function primary(damage) return { slot = "primary_weapon", damage = damage } end
local function sidearm(damage) return { slot = "sidearm_weapon", damage = damage } end

test("primary_hits_build_up_fire_and_poison_by_a_share_of_max_health", function()
	local f = fight.new()
	local stats = { ignite = upgrades.BUILD_UP[1], needle = 0 }
	local bug, other = {}, {}
	-- A 400-health enemy at one stack: 40% is 160.
	eq(fight.on_hit(f, stats, bug, primary(100), 0, 400), nil)
	local out, extra = fight.on_hit(f, stats, bug, primary(60), 0, 400)
	eq(out and out[1], "regular_burn", "160 of 160")
	eq(extra.bonus, 40, "10% of max health on top")
	eq(extra.effects.fire, 5, "the burn runs 5 s")
	eq(fight.on_hit(f, stats, other, primary(100), 0, 400), nil, "one enemy's build-up isn't another's")
	eq(fight.on_hit(f, stats, bug, sidearm(500), 0, 400), nil, "only the primary builds up")
	eq(fight.on_hit(f, stats, bug, { damage = 500 }, 0, 400), nil, "nor a grenade")
	stats.needle = upgrades.BUILD_UP[3]
	f = fight.new()
	out = fight.on_hit(f, stats, bug, primary(160), 0, 400)
	eq(out and table.concat(out, ","), "regular_burn,poison_medium_damage,poison_slow", "both fill at once")
end)

test("the_share_keeps_to_a_floor_and_a_cap_and_so_does_the_bonus", function()
	eq(fight.need(0.3, 30), upgrades.BUILD_FLOOR, "a scout dies before it burns")
	eq(fight.need(0.3, 270), 81, "a warrior")
	eq(fight.need(0.3, 2100), 630, "a tank")
	eq(fight.need(0.3, 250000), upgrades.BUILD_CAP, "a boss still burns")
	eq(fight.bonus(400), 40)
	eq(fight.bonus(250000), upgrades.PROC_CAP)
	eq(fight.need(0.3, nil), upgrades.BUILD_FLOOR, "no health known: the floor")
end)

test("steady_fire_keeps_an_effect_going_near_its_end_only", function()
	local f = fight.new()
	local stats = { ignite = upgrades.BUILD_UP[1], needle = 0 }
	local bug = {}
	local out, extra = fight.on_hit(f, stats, bug, primary(400), 0, 400)
	eq(out[1], "regular_burn")
	out, extra = fight.on_hit(f, stats, bug, primary(10), 2, 400)
	eq(out, nil, "3 s left: no second copy yet")
	eq(extra.bonus, 0)
	for t = 2.1, 3.9, 0.1 do
		out, extra = fight.on_hit(f, stats, bug, primary(400), t, 400)
		eq(out, nil, "no build-up while it burns, so no copies or bonus hits stacked on top")
		eq(extra.bonus, 0)
	end
	out, extra = fight.on_hit(f, stats, bug, primary(10), 4.2, 400)
	eq(out and out[1], "regular_burn", "under a second left: sent again")
	eq(extra.effects.fire, 5)
	eq(extra.bonus, 0, "keeping it going isn't setting it off")
	out = fight.on_hit(f, stats, bug, primary(10), 4.5, 400)
	eq(out, nil, "the new copy runs to 9.2")
	out = fight.on_hit(f, stats, bug, primary(10), 20, 400)
	eq(out, nil, "worn off: only the build-up can start it again")
end)

test("a_build_up_wears_off_sooner_on_small_enemies", function()
	near(fight.fade_of(50), upgrades.BUILD_FADE[1])
	near(fight.fade_of(100), 2)
	near(fight.fade_of(3000), 8)
	near(fight.fade_of(250000), upgrades.BUILD_FADE[2], "a boss: the longest")
	local mid = fight.fade_of(270)
	eq(mid > 3 and mid < 4.5, true, "a warrior: under 4.5 s")
	local f = fight.new()
	local stats = { ignite = upgrades.BUILD_UP[1], needle = 0 }
	local bug = {}
	-- 400 health: 160 sets it off, and it wears off over fade_of(400) seconds.
	local fade = fight.fade_of(400)
	fight.on_hit(f, stats, bug, primary(100), 0, 400)
	local _, extra = fight.on_hit(f, stats, bug, primary(50), fade / 2, 400)
	near(extra.bars.fire.fraction, 100 / 160, "half of 100 left, and 50 more")
	eq(fight.on_hit(f, stats, bug, primary(50), fade / 2 + fade, 400), nil, "all worn off by then")
end)

test("sidearm_hits_stun_nothing_now_stun_rounds_is_gone", function()
	local f = fight.new()
	eq(upgrades.by_id.stun_rounds, nil)
	eq(fight.on_hit(f, { stun_rounds = 2 }, {}, sidearm(10), 0), nil)
end)

test("elusive_tactics_dives_farther_and_plans_a_stun_of_its_seconds", function()
	local u = upgrades.by_id.elusive_tactics
	local stats = {}
	u.apply({ stat = function(_, name, v) stats[name] = v end }, 2, 1)
	near(stats.dive, 1 + 2 * upgrades.DIVE_FARTHER)
	eq(stats.dive_stun, 2 * upgrades.DIVE_STUN)
	eq(stats.dive_heal, nil, "no heal any more")
	eq(stats.get_up, nil, "nor a faster get-up")
	eq(u.text(1), "Dive 25% farther, stunning nearby enemies for 1 second.\nTotal: +25%, 1 s")
	local dive = obsidian.module("src/dive")
	local function plan(s)
		local out = {}
		for _, step in ipairs(dive.stun_plan(s)) do out[#out + 1] = step.at .. ":" .. step.status end
		return table.concat(out, ",")
	end
	eq(plan(1), "0:dog_hit_obstacle_stun", "the game's 1 s stun")
	eq(plan(2), "0:dog_hit_obstacle_stun,1:dog_hit_obstacle_stun", "the short one again a second later")
	eq(plan(3), "0:flashbang_stun", "the game's 3 s stun")
	eq(plan(4), "0:flashbang_stun,3:dog_hit_obstacle_stun")
	eq(plan(0), "")
end)

test("facetanker_takes_its_armor_off_hits_from_the_front_only", function()
	local half = math.pi / 2
	eq(fight.frontal(200, 80, 0, false, false), 120, "straight ahead")
	eq(fight.frontal(200, 80, half - 0.01, false, false), 120, "the edge of the front half")
	eq(fight.frontal(200, 80, half + 0.01, false, false), 200, "from behind the side")
	eq(fight.frontal(200, 80, math.pi, false, false), 200, "from behind")
	eq(fight.frontal(200, 80, -0.5, false, false), 120, "either side")
	eq(fight.frontal(200, 80, 2 * math.pi + 0.1, false, false), 120, "an angle past a turn")
	eq(fight.frontal(50, 80, 0, false, false), 0, "never below nothing")
	eq(fight.frontal(200, 80, 0, true, false), 200, "a hit that ignores armor, a status's included")
	eq(fight.frontal(200, 80, 0, false, true), 200)
	eq(fight.frontal(200, 80, nil, false, false), 200, "a hit with no angle")
	eq(fight.frontal(200, 0, 0, false, false), 200, "no Facetanker")
	local stats = {}
	upgrades.by_id.facetanker.apply({ stat = function(_, name, v) stats[name] = v end }, 2, 1)
	eq(stats.front_armor, 2 * upgrades.FRONT_ARMOR)
	eq(upgrades.by_id.facetanker.rarity, "rare")
end)

test("trailblazer_leaves_fire_every_step_and_takes_each_patch_after_its_seconds", function()
	local trail = obsidian.module("src/trail")
	local t = {}
	eq(trail.due(t, { x = 0, y = 0 }, 0), true, "the first")
	eq(trail.due(t, { x = 1, y = 0 }, 1), false, "too close to the last")
	eq(trail.due(t, { x = 2, y = 0 }, 0.1), false, "too soon")
	eq(trail.due(t, { x = 2, y = 0 }, 1.2), true)
	local list = { { unit = "a", ends = 2 }, { unit = "b", ends = 4 } }
	local gone = trail.expired(list, 3)
	eq(#gone, 1)
	eq(gone[1].unit, "a")
	eq(#list, 1)
	local stats = {}
	upgrades.by_id.trailblazer.apply({ stat = function(_, name, v) stats[name] = v end }, 2, 1)
	eq(stats.trail, 2 * upgrades.TRAIL_SECONDS)
end)

test("gunslinger_keeps_the_sidearm_full_and_lets_it_move_freely", function()
	local perks = obsidian.module("src/perks")
	local stats = perks.stats()
	eq(perks.moves_freely(stats, true), false)
	upgrades.by_id.quick_draw.apply({ stat = function(_, name, v) stats[name] = v end }, 1, 1)
	eq(upgrades.by_id.quick_draw.name, "Gunslinger")
	eq(upgrades.by_id.quick_draw.rarity, "legendary")
	eq(upgrades.by_id.gunslinger.name, "P-6 Gunslinger", "the perk card no longer shares the name")
	eq(perks.moves_freely(stats, true), true, "the sidearm moves freely")
	eq(perks.moves_freely(stats, false), false, "the other weapons don't")
	eq(perks.moves_freely({ weight_training = true }, false), true, "Weight Training for all")
	eq(perks.sidearm_spent({ rounds = 6, num_mags = 4, magazines_max = 4 }, false, 6), false, "full")
	eq(perks.sidearm_spent({ rounds = 5, num_mags = 4, magazines_max = 4 }, false, 6), true, "a shot")
	eq(perks.sidearm_spent({ rounds = 6, num_mags = 3, magazines_max = 4 }, false, 6), true, "a spare magazine short")
	eq(perks.sidearm_spent({ rounds = 6, is_reloading = true }, false, 6), true, "a reload")
	eq(perks.sidearm_spent({ rounds = 0 }, true, nil), false, "a heat weapon cool")
	eq(perks.sidearm_spent({ rounds = 12 }, true, nil), true, "and warm")
end)

test("democracy_protects_rolls_once_a_volley", function()
	local f = fight.new()
	local stats = { democracy = upgrades.DEMOCRACY_CHANCE }
	local me = {}
	local function roll(r) return function() return r end end
	eq(fight.spare(f, stats, me, 0, roll(0.7)), false)
	eq(fight.spare(f, stats, me, 0, roll(0.2)), true)
	eq(fight.spare(f, stats, me, 0.2, roll(0.9)), true, "the rest of the volley")
	eq(fight.spare(f, stats, me, 0.5, roll(0.9)), false)
	eq(fight.spare(f, { democracy = 0 }, {}, 0, roll(0)), false, "without the upgrade")
end)

test("strike_back_returns_its_share_to_enemies_within_reach", function()
	local stats = { strike_back = 0.2 }
	near(fight.strike_back(stats, 50, 1.5), 10)
	eq(fight.strike_back(stats, 50, fight.STRIKE_REACH + 0.1), nil, "too far")
	eq(fight.strike_back({ strike_back = 0 }, 50, 1), nil, "without the upgrade")
	eq(fight.strike_back(stats, 0, 1), nil, "a hit that cost nothing")
end)

test("a_warp_stops_short_of_what_would_stop_a_body", function()
	eq(dive.warp_length(8, nil), 8)
	eq(dive.warp_length(8, 20), 8)
	near(dive.warp_length(8, 5), 5 - dive.WARP_GAP)
	eq(dive.warp_length(8, 2), nil, "too short to be worth it")
end)

local vacuum = obsidian.module("src/vacuum")

test("the_vacuum_fills_with_three_times_a_level_and_starts_over", function()
	eq(rules.VACUUM_EVERY, 3.75)
	eq(rules.VACUUM_MOST, 100)
	local v = vacuum.new()
	local need = 20
	eq(vacuum.add(v, need * rules.VACUUM_EVERY - 1, need), false)
	near(vacuum.fraction(v, need), (need * rules.VACUUM_EVERY - 1) / (need * rules.VACUUM_EVERY))
	eq(vacuum.add(v, 1, need), true)
	eq(vacuum.fraction(v, need), 0, "empty again")
	eq(v.seq, 1)
	eq(vacuum.fraction(vacuum.new(), 0), 0, "no level to fill for")
end)

test("the_vacuum_keeps_its_target_until_it_goes_off", function()
	local v = vacuum.new()
	eq(vacuum.add(v, 1, 10), false)
	eq(v.target, 37.5, "the level it starts on")
	-- Level-ups in between raise the need, and the target stays.
	eq(vacuum.add(v, 27, 50), false)
	near(vacuum.fraction(v, 80), 28 / 37.5)
	eq(vacuum.add(v, 10, 20), true, "37.5 reached, whatever the level now")
	eq(v.target, 75, "the next one from the level it went off on")
	eq(vacuum.fraction(v, 20), 0)
	eq(vacuum.add(v, 74, 90), false)
	eq(vacuum.add(v, 1, 90), true)
	eq(v.target, 100, "never past rules.VACUUM_MOST")
end)

test("another_machines_vacuum_counts_once_and_only_while_fresh", function()
	local mine, theirs = vacuum.new(), vacuum.new()
	vacuum.add(theirs, 1000, 10)
	local e = vacuum.decode(vacuum.encode(theirs, 77, 5, { x = -12.5, y = 3 }, 100))
	eq(e.x, -12.5)
	eq(vacuum.take(mine, "peer", e, 77, 101), true)
	eq(vacuum.take(mine, "peer", e, 77, 101.5), false, "the same one again")
	eq(vacuum.take(mine, "other", e, 99, 101), false, "another mission's")
	vacuum.add(theirs, 1000, 10)
	local late = vacuum.decode(vacuum.encode(theirs, 77, 5, { x = 0, y = 0 }, 100))
	eq(vacuum.take(mine, "peer", late, 77, 100 + rules.VACUUM_FRESH + 1), false, "long gone")
	eq(vacuum.decode("nonsense"), nil)
end)

test("the_vacuum_pulls_every_sample_on_the_map_to_the_nearest_player", function()
	local o = orbs.new()
	orbs.drop(o, { x = 20, y = 0 }, 3)
	orbs.drop(o, { x = 250, y = 0 }, 5)
	eq(orbs.pull(o, { x = 0, y = 0 }, rules.VACUUM_RADIUS), 2, "the far one too")
	local me = { pos = { x = 0, y = 0, z = 0 }, is_local = true }
	local got = 0
	for _ = 1, 30 * 10 do got = got + orbs.update(o, 1 / 30, { me }) end
	eq(got, 8, "both arrived")
	eq(#o.list, 0)
end)

test("the_director_spawns_in_waves_with_a_break_between", function()
	local d = director.new("bugs", rng.new(21))
	local spawned_at, rests = {}, {}
	local resting_since
	for tick = 1, 300 * 10 do
		local t = tick / 10
		local out = director.update(d, 0.1, 1, 0)
		if #out.spawns > 0 and not out.boss then spawned_at[#spawned_at + 1] = t end
		if out.resting and not resting_since then resting_since = t end
		if not out.resting and resting_since then
			rests[#rests + 1] = t - resting_since
			resting_since = nil
		end
		eq(out.resting == true and #out.spawns > 0 and not out.boss, false, "nothing spawns in a break: " .. t)
	end
	eq(#rests >= 5, true, "breaks in five minutes: " .. #rests)
	for _, r in ipairs(rests) do near(math.floor(r * 10 + 0.5) / 10, rules.BREAK_SECONDS, "a break of " .. r) end
	-- Spawning comes back at once after a break.
	local first_wave_end = rules.WAVE_SECONDS
	local back
	for _, t in ipairs(spawned_at) do
		if t > first_wave_end + rules.BREAK_SECONDS - 0.15 then back = back or t end
	end
	eq(back ~= nil and back <= first_wave_end + rules.BREAK_SECONDS + 0.2, true, "the next wave opens with a spawn: " .. tostring(back))
end)

test("a_cycle_is_sixty_percent_spawning_and_forty_percent_break", function()
	near(rules.WAVE_SECONDS / (rules.WAVE_SECONDS + rules.BREAK_SECONDS), 0.6)
	local d = director.new("cyborgs", rng.new(8), 5)
	local resting, total = 0, 0
	for _ = 1, 10 * 60 * 10 do
		local out = director.update(d, 0.1, 1, 0)
		total = total + 1
		if out.resting then resting = resting + 1 end
	end
	local share = resting / total
	eq(share > 0.39 and share < 0.41, true, "time in breaks over ten minutes: " .. share)
end)

-- Enemies spent in the first two waves, by difficulty, for one player.
local function opening(home, difficulty)
	local d = director.new(home, rng.new(13), difficulty)
	local n = 0
	for _ = 1, (rules.WAVE_SECONDS * 2 + rules.BREAK_SECONDS) * 10 do
		for _, s in ipairs(director.update(d, 0.1, 1, 0).spawns) do n = n + s.count end
	end
	return n
end

test("a_mission_of_difficulty_five_or_less_starts_much_calmer", function()
	eq(rules.difficulty_share(5) <= 0.75, true)
	eq(rules.difficulty_share(1) < rules.difficulty_share(5), true)
	eq(rules.difficulty_share(8), 1)
	eq(rules.difficulty_share(14), 1)
	eq(rules.difficulty_share(nil), 1, "an unknown difficulty counts as a hard one")
	eq(rules.alive_cap(3) < rules.alive_cap(8), true)
	for _, home in ipairs(director.FACTIONS) do
		local easy, hard = opening(home, 3), opening(home, 10)
		eq(easy < hard * 0.8, true, home .. ": " .. easy .. " at 3, " .. hard .. " at 10")
		-- 1.4.0 spent 4 points every 4 seconds from the start: 40 enemies a wave; 1.5.0 brought 30.
		eq(easy <= 36, true, home .. ": the first two waves at difficulty 3 bring " .. easy)
	end
end)

test("the_budget_sits_between_1_4_and_1_5", function()
	near(director.budget(0, 1, 8), 3.5)
	near(director.budget(10, 1, 8), 23.5)
	near(director.budget(10, 1, 5), 23.5 * 0.72)
	eq(director.budget(10, 4, 8) > director.budget(10, 1, 8), true, "more for more players")
end)

-- Each wave of a run: how many enemies, how many rushers, and the most of one key.
local function waves_of(home, difficulty, players, seed_value)
	local d = director.new(home, rng.new(seed_value), difficulty)
	local list, cur, alive = {}, nil, {}
	for _ = 1, 16 * 60 * 10 do
		for i = #alive, 1, -1 do
			alive[i] = alive[i] - 0.1
			if alive[i] <= 0 then table.remove(alive, i) end
		end
		local out = director.update(d, 0.1, players, #alive)
		if out.resting then cur = nil elseif not cur then
			cur = { units = 0, swarm = 0, keys = {} }
			list[#list + 1] = cur
		end
		for n, s in ipairs(out.spawns) do
			if cur and not (out.boss and n == 1) then
				cur.units = cur.units + s.count
				if director.SWARM[s.key] then cur.swarm = cur.swarm + s.count end
				cur.keys[s.key] = (cur.keys[s.key] or 0) + s.count
			end
			for _ = 1, s.count do alive[#alive + 1] = 10 end
		end
	end
	return list
end

test("no_wave_is_mostly_fast_melee", function()
	for _, home in ipairs(director.FACTIONS) do
		for _, difficulty in ipairs({ 2, 5, 9, 14 }) do
			for _, players in ipairs({ 1, 4 }) do
				for s = 1, 3 do
					for i, w in ipairs(waves_of(home, difficulty, players, s * 31)) do
						local what = string.format("%s d%d x%d seed %d wave %d", home, difficulty, players, s, i)
						eq(w.swarm <= math.floor(rules.SWARM_SHARE * w.units), true, what .. ": " .. w.swarm .. " rushers of " .. w.units)
						for key, n in pairs(w.keys) do
							if director.SWARM[key] then eq(n * 2 <= w.units, true, what .. ": " .. n .. " " .. key .. " of " .. w.units) end
						end
					end
				end
			end
		end
	end
end)

test("every_faction_offers_more_than_rushers_from_the_start", function()
	for faction, tiers in pairs(director.ROSTER) do
		local calm = false
		for tier = 1, 4 do
			for _, key in ipairs(tiers[tier]) do
				if director.from(key, tier) == 1 and not director.SWARM[key] then calm = true end
			end
		end
		eq(calm, true, faction .. " has a unit at Heat 1 that isn't a rusher")
		for tier = 1, 4 do
			for _, key in ipairs(tiers[tier]) do eq(key:find("observer") == nil, true, key .. " raises the game's own alarm") end
		end
		for key in pairs(director.SWARM) do eq((director.tier_of(key)) ~= nil, true, key .. " is in the roster") end
	end
end)

test("a_boss_comes_on_its_minute_in_a_break_too", function()
	local d = director.new("cyborgs", rng.new(3))
	d.time = 600 - 1
	d.rest_left = 12
	local out = director.update(d, 1, 1, 0)
	eq(out.resting, true)
	eq(out.boss ~= nil, true)
	eq(#out.spawns, 1, "the boss alone")
end)

test("about_one_kill_in_twenty_drops_an_ammo_box", function()
	eq(rules.AMMO_CHANCE, 0.05)
	local r, yes = rng.new(17), 0
	for _ = 1, 20000 do if rules.drops_ammo(r) then yes = yes + 1 end end
	eq(yes > 850 and yes < 1150, true, "boxes in 20000 kills: " .. yes)
end)

test("getting_up_runs_faster_in_every_state_that_gets_a_player_up", function()
	local function has(list, x) for _, v in ipairs(list) do if v == x then return true end end return false end
	eq(has(dive.DIVE_STATES, "CharacterStateCrawl"), true, "a dive finished holding a direction")
	eq(has(dive.DIVE_STATES, "CharacterStateDodge"), true)
	eq(dive.GET_UP.CharacterStateKnockedDown ~= nil, true, "knockdowns and the hound's takedown")
	eq(dive.GET_UP.CharacterStateDownedGetUp ~= nil, true)
	local state = { dive_timer = 1, dive_get_up = false }
	dive.hurry_dive(state, 0.1, 1.6)
	eq(state.dive_timer, 1, "still held down by dodge")
	state.dive_get_up = true
	dive.hurry_dive(state, 0.1, 1.6)
	near(state.dive_timer, 1.06)
	local knocked = { stay_down_timer = 0.5, get_up_timer = 1 }
	dive.hurry(knocked, dive.GET_UP.CharacterStateKnockedDown, 0.1, 1.5)
	near(knocked.stay_down_timer, 0.45) eq(knocked.get_up_timer, 1, "one timer at a time")
	knocked.stay_down_timer = nil
	dive.hurry(knocked, dive.GET_UP.CharacterStateKnockedDown, 0.1, 1.5)
	near(knocked.get_up_timer, 0.95)
end)

local loadout = obsidian.module("src/loadout")

test("the_stratagem_slots_sit_in_the_middle_of_the_panel", function()
	eq(rules.STRATAGEM_SLOTS, 2)
	-- The game's slots: the first at 10, each 50 wide and 10 apart.
	local function row(width, count)
		local dx = loadout.offset(width, count, 50)
		local left = loadout.FIRST + dx
		local right = loadout.FIRST + (count - 1) * (50 + loadout.GAP) + 50 + dx
		return left, right
	end
	for _, count in ipairs({ 1, 2, 3 }) do
		local left, right = row(400, count)
		near(left, 400 - right, count .. " slots, as much room on each side")
	end
	near(loadout.offset(400, 1, 50), (400 - 50) / 2 - 10, "one slot, as before")
end)

local level = obsidian.module("src/level")

test("a_survivors_map_takes_only_the_allowed_objective_kinds", function()
	for _, name in ipairs({ "mission_1x1_exterminate_01", "mission_1x1_missile_ramp_01", "mission_1x1_assassinate_01",
		"mission_1x1_flag_01", "mission_2x1_flag_01", "mission_2x2_samsite_01", "mission_1x1_antenna_02" }) do
		eq(level.allowed_objective(name), true, name)
	end
	for _, name in ipairs({ "mission_2x2_bughole_01", "mission_5x3_convoy_01", "mission_1x1_flag_fortify_01", "mission_1x1_oildrill_01", "mission_2x2_cyborgaa_01" }) do
		eq(level.allowed_objective(name), false, name)
	end
	local list = { { name = "mission_1x1_antenna_01", cost = 2 }, { name = "mission_2x2_bughole_01", cost = 1 } }
	local allowed = level.allowed_objectives(list)
	eq(#allowed, 1) eq(allowed[1], list[1], "the game's own entry, at its own cost")
	eq(level.allowed_objectives({ { name = "mission_2x2_bughole_01" } }), nil, "none allowed: the game's list")
end)

test("the_list_shows_whats_left_then_only_the_extraction", function()
	local objs = {
		{ name = "mission_objective_extract", type = "objective_extract_lz", state = "pending" },
		{ name = "flag", type = "objective_interact_object", state = "pending" },
		{ name = "sam", type = "objective_destroy_object", state = "complete" },
	}
	local before = level.listed(objs, false)
	eq(#before, 1) eq(before[1].name, "flag")
	local after = level.listed(objs, true)
	eq(#after, 1) eq(after[1].name, "mission_objective_extract")
	eq(level.hint_busy({ queued_hints = {} }), false)
	eq(level.hint_busy({ queued_hints = { {} } }), true, "one waiting")
	eq(level.hint_busy({ current_hint = {}, queued_hints = {} }), true, "one showing")
	eq(level.hint_busy(nil), false)
end)

test("an_upgrade_needing_a_newer_api_names_the_call", function()
	eq(upgrades.has_api({ combat = { on_hit = function() end } }, "combat.on_hit"), true)
	eq(upgrades.has_api({ combat = {} }, "combat.on_hit"), false)
	eq(upgrades.has_api({}, "world.raycast"), false)
	for _, id in ipairs({ "ignition_rounds", "needle_rounds", "warp_pack", "democracy_protects" }) do
		eq(type(upgrades.by_id[id].api), "string", id)
	end
end)


local alarm = obsidian.module("src/alarm")

test("an_enemy_that_spots_the_squad_attacks_without_an_alert", function()
	local s = { patroling = true, alerted = false }
	alarm.notice(s, false)
	eq(s.patroling, true, "nothing seen, still patrolling")
	alarm.notice(s, true)
	eq(s.patroling, false, "seen: off patrol, so the next update attacks")
	eq(s.alerted, false, "no alert played")
	eq(s.has_triggered_encounter, true, "and starts no encounter")
end)

test("the_alarm_goes_on_once_and_again_only_when_quiet", function()
	eq(alarm.due(nil, false, 5), true, "at the landing")
	eq(alarm.due(true, true, -1), false, "still running")
	eq(alarm.due(true, false, 2), false, "quiet, between looks")
	eq(alarm.due(true, false, 0), true, "quiet at a look")
	local starts, active = 0, false
	local em = { is_active = function() return active end, start_encounter = function() starts = starts + 1 active = true end }
	local a = {}
	eq(alarm.update(a, em, { x = 0 }, 0.1), true)
	for _ = 1, 100 do alarm.update(a, em, { x = 0 }, 0.1) end
	eq(starts, 1, "on, and kept on while it runs")
	active = false
	for _ = 1, 60 do alarm.update(a, em, { x = 0 }, 0.1) end
	eq(starts, 2, "on again within a look once it went quiet")
end)

test("the_first_alarm_is_the_enemys_then_the_run_keeps_it_on", function()
	local starts, active = 0, false
	local em = { is_active = function() return active end, start_encounter = function() starts = starts + 1 active = true end }
	local a = {}
	alarm.wait_natural(a)
	eq(alarm.natural(), true)
	for _ = 1, 600 do eq(alarm.update(a, em, { x = 0 }, 0.1), false, "the run doesn't raise the first") end
	eq(starts, 0)
	-- An enemy raised it: start_encounter passed through the hook.
	active = true
	alarm.on_natural()
	eq(alarm.natural(), false)
	eq(a.raised, true)
	for _ = 1, 100 do alarm.update(a, em, { x = 0 }, 0.1) end
	eq(starts, 0, "kept while the enemy's runs")
	active = false
	for _ = 1, 60 do alarm.update(a, em, { x = 0 }, 0.1) end
	eq(starts, 1, "the run's once it went quiet")
	alarm.wait_natural({})
	alarm.skip_natural()
	eq(alarm.natural(), false, "a new host doesn't wait")
end)

-- src/perks.lua and src/shield.lua ask for Obsidian API as they load; what's tested here never calls it.
local had_import = obsidian.import
obsidian.import = had_import or function() return {} end
local perks_ok, perks = pcall(obsidian.module, "src/perks")
obsidian.import = had_import

test("meritocracy_takes_a_share_of_the_time_left_for_each_sample", function()
	eq(perks_ok, true, tostring(perks))
	near(perks.merit_keep(0.04, 1), 0.96, "one sample at 4%: 4% of what's left, whatever the sample's XP")
	near(perks.merit_keep(0.02, 3), 0.98 ^ 3, "three at once, one after another")
	eq(perks.merit_keep(0.02, 0), 1)
	near(30 * perks.merit_keep(0.02, 1), 29.4, "30 s left: 0.6 s off")
end)

test("rapid_fire_is_the_primary_weapons_only", function()
	eq(perks_ok, true, tostring(perks))
	local stats = perks.stats()
	stats.firerate = 1.2
	eq(perks.weapon_changes(stats, "primary_weapon", "weapon").firerate, 1.2)
	eq(perks.weapon_changes(stats, "sidearm_weapon", "weapon").firerate, nil, "not the sidearm")
	eq(perks.weapon_changes(stats, "support_weapon", "weapon").firerate, nil, "not a support weapon")
end)

return T
