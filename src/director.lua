-- The host's spawner: every few seconds of a wave it spends a budget on enemies around the squad, and
-- between waves it rests. The budget, the units on offer and the factions grow with time, and the
-- mission's difficulty sets how much of the budget it spends. It answers what to spawn; src/run.lua
-- spawns it.
local rules = obsidian.module("src/rules")

local M = {}

M.FACTIONS = { "bugs", "cyborgs", "illuminates" }

-- Enemy keys of Obsidian API's catalog, by faction and tier. A tier's cost is also the XP its orb gives.
-- The order follows the game's own waves (EncounterSettings, cheapest first): Tripods are the
-- Illuminates' first wave there, Apprentices and Outcasts come later and cost more. Observers and
-- Watchers are left out: each one that sees the squad starts one of the game's own encounters
-- (IlluminateObserverStateAlarm), which piled the game's waves on top of these. The Comrade joins the
-- Immolator and the Berserker, so a Cyborg wave has more than one gun in it.
M.ROSTER = {
	bugs = {
		{ "bug_scout" },
		{ "bug_warrior", "bug_scout_jumping" },
		{ "bug_warrior_elite", "bug_stalker" },
		{ "bug_tank", "bug_impaler" },
		{ "bug_tank_heavy", "bug_warrior_commander" },
	},
	cyborgs = {
		{ "cyborg_initiate", "cyborg_dog" },
		{ "cyborg_soldier", "cyborg_soldier_cannon", "cyborg_berserker" },
		{ "cyborg_soldier_shield", "cyborg_initiate_elite" },
		{ "cyborg_hulk", "cyborg_berserker_elite" },
		{ "cyborg_hulk_assassinate", "cyborg_ifv" },
	},
	illuminates = {
		{ "illuminate_tripod", "illuminate_apprentice" },
		{ "illuminate_tripod_elite" },
		{ "illuminate_hunter", "illuminate_trickster", "illuminate_obelisk" },
		{ "illuminate_illusionist" },
		{ "illuminate_illusionist_assassinate" },
	},
}

-- The Obelisk used to be a tier 2 unit, in packs of four like a Strider, though it carries 1200
-- points of shield over 450 health, the shield back in full four seconds after the last hit, and the
-- game's own waves bring one at a time (EncounterSettings "obelisk", cost 4, beside 1.5 to 2 for
-- Tripods). Packs of them piled up behind their shields, a few more every spawn, faster than a squad
-- could bring them down. Now it is tier 3, comes alone, at half the weight of the other tier 3 units,
-- and no more than LIMIT of a key are alive at once.
M.LIMIT = { illuminate_obelisk = 2 }
-- A unit's weight against the other units of the same tier, 1 when not listed.
M.WEIGHT = { illuminate_obelisk = 0.5 }

-- Fast melee that rushes in numbers. At most rules.SWARM_SHARE of a wave's enemies are these; past it
-- the wave takes the faction's other units.
M.SWARM = {
	bug_scout = true, bug_scout_jumping = true, bug_stalker = true,
	cyborg_dog = true, cyborg_berserker = true, cyborg_initiate_elite = true,
	illuminate_apprentice = true, illuminate_trickster = true,
}

-- Units on offer from an earlier Heat step than their tier's, at their own tier's cost. Warriors join
-- the Scouts from the start, so the bugs' first minutes aren't Scouts alone. The Illusionist, the
-- Illuminates' only tier 4 unit, comes from Heat 3 (5:00), as the game's own waves bring one from their
-- fifth wave on (EncounterSettings "apprentices"): from 9:00 a solo run saw one or two at the most.
M.EARLY = { bug_warrior = 1, illuminate_illusionist = 3 }

-- Minutes from which each Heat step starts: step t also brings in tier t (the fifth has no regular
-- units: the tier 5 enemies are the bosses). An early version had 0, 2, 6, 11 and 15, with the factions at 8 and
-- 15: calm until 15:00, where the third faction, Heat 5 and the second boss all came at once. Now the
-- steps come earlier and apart: tier 4's tanks and Hulks at 9:00 (the Illusionist earlier, M.EARLY),
-- the third faction at 12:00 and Heat 5 at 14:00 (the timeline below).
M.HEAT_FROM = { 0, 2, 5, 9, 14 }
-- Now: the second faction at 6:00, one of the other two drawn from the mission seed, the third at
-- 12:00 (it used to be 7:00 and 13:00, the second always the next in M.FACTIONS).
M.FACTION_FROM = { 0, 6, 12 }
-- Bosses: the first at 10:00, the second at 20:00, then one every BOSS_EVERY minutes for a squad that
-- stays past the shuttle (rules.RUN_LENGTH, 15:00). Each is of another faction than the one before.
M.BOSS_FIRST = 10
M.BOSS_SECOND = 20
M.BOSS_EVERY = 5
-- Tier 4 enemies (tanks, Hulks, Illusionists) alive at once, at most, per player in the squad, beside
-- M.LIMIT's per key. There used to be no cap: past 10 minutes the budget bought one every spawn
-- or two, and they piled up faster than one anti-tank weapon and two stratagems bring them down. With 3
-- a player, a solo run meets 3 at most and a squad of four 12, and tier 4 still comes every wave.
M.TIER_LIMIT = { [4] = 3 }

-- The minute of the run's boss number i (1 on).
function M.boss_minute(i)
	if i <= 1 then return M.BOSS_FIRST end
	return M.BOSS_SECOND + M.BOSS_EVERY * (i - 2)
end

-- How many bosses are due by `minutes`.
function M.bosses_by(minutes)
	if minutes < M.BOSS_FIRST then return 0 end
	if minutes < M.BOSS_SECOND then return 1 end
	return 2 + math.floor((minutes - M.BOSS_SECOND) / M.BOSS_EVERY + 1e-9)
end

-- 1 to n from the mission seed and `salt`, the same on every machine.
function M.roll(seed, salt, n)
	local x = math.floor(math.abs(tonumber(seed) or 0)) % 2147483647
	for _ = 1, 3 do x = (x * 48271 + salt * 7919) % 2147483647 end
	return x % n + 1
end

-- The factions in the order they join: the mission's own, then one of the other two drawn from the
-- seed, then the last one.
function M.order(home, seed)
	local others = {}
	for _, f in ipairs(M.FACTIONS) do
		if f ~= home then others[#others + 1] = f end
	end
	if #others < 2 then return { home, others[1] } end
	local second = M.roll(seed, 101, 2)
	return { home, others[second], others[3 - second] }
end

-- The faction of boss number i. The first is the home faction's or the one that joined at 6:00; after
-- it the three factions take turns in a fixed order drawn from the seed, so no boss is of the same
-- faction as the one before, and from the third on every faction has had one.
function M.boss_faction(home, seed, i)
	local order = M.order(home, seed)
	local first = order[M.roll(seed, 1, 2)]
	local rest = {}
	for _, f in ipairs(order) do
		if f ~= first then rest[#rest + 1] = f end
	end
	if #rest == 2 and M.roll(seed, 2, 2) == 2 then rest[1], rest[2] = rest[2], rest[1] end
	local cycle = { first, rest[1], rest[2] }
	return cycle[(i - 1) % #cycle + 1]
end
-- Small enemies come in packs of up to this many.
M.PACK = 4

local tier_of = {}
for faction, tiers in pairs(M.ROSTER) do
	for tier, keys in ipairs(tiers) do
		for _, key in ipairs(keys) do tier_of[key] = { tier = tier, faction = faction } end
	end
end

-- The tier (1 to 5) and faction of an enemy key, or nil for one the director doesn't spawn.
function M.tier_of(key)
	local t = tier_of[key]
	if t then return t.tier, t.faction end
	return nil
end

-- The factions in play at `minutes`, the mission's own first. seed: the mission's, which draws the
-- second faction (M.order).
function M.factions(home, minutes, seed)
	local order = M.order(home, seed)
	local out = {}
	for i, f in ipairs(order) do
		if minutes >= M.FACTION_FROM[i] then out[#out + 1] = f end
	end
	return out
end

-- How dangerous the run is at `minutes`, for the player to see: Heat, 1 to 5.
M.THREATS = #M.HEAT_FROM
function M.threat(minutes)
	local level = 1
	for step, from in ipairs(M.HEAT_FROM) do
		if minutes >= from then level = step end
	end
	return level
end

-- The Heat step from which `key` (of tier `tier`) is on offer.
function M.from(key, tier)
	return M.EARLY[key] or tier
end

-- How many of tier `tier` may be alive at once with `players` in the squad: math.huge for a tier
-- without a TIER_LIMIT.
function M.tier_limit(tier, players)
	local each = M.TIER_LIMIT[tier]
	if not each then return math.huge end
	return each * math.max(tonumber(players) or 1, 1)
end

-- How many more of `key` may come now: math.huge for a key without a LIMIT or a TIER_LIMIT.
-- alive_of(key): how many are alive, or nil when unknown. planned: what this spawn has already asked
-- for, by key. players: the squad, for TIER_LIMIT (1 when nil).
local function left_of(key, alive_of, planned, players)
	local left = math.huge
	local function count(k)
		local alive = alive_of and tonumber(alive_of(k)) or 0
		return alive + (planned and planned[k] or 0)
	end
	local limit = M.LIMIT[key]
	if limit then left = math.max(0, limit - count(key)) end
	local t = tier_of[key]
	local cap = t and M.tier_limit(t.tier, players)
	if cap and cap < math.huge then
		local n = 0
		for _, tiers in pairs(M.ROSTER) do
			for _, k in ipairs(tiers[t.tier]) do n = n + count(k) end
		end
		left = math.min(left, math.max(0, cap - n))
	end
	return left
end
M.left_of = left_of

-- The keys of a faction's tier on offer at Heat `heat`, without those at their LIMIT.
local function on_offer(faction, tier, heat, alive_of, planned, players)
	local out = {}
	for _, key in ipairs(M.ROSTER[faction][tier]) do
		if heat >= M.from(key, tier) and left_of(key, alive_of, planned, players) > 0 then out[#out + 1] = key end
	end
	return out
end

-- What changes after minute `from` up to and including minute `to`, in the order to announce it:
-- { kind = "faction", faction }, { kind = "heat" } or { kind = "boss" }. Plain time, so every machine
-- works out the same from the run's clock.
function M.events(home, from, to, seed)
	local out = {}
	local function due(minute) return minute > from and minute <= to end
	local order = M.order(home, seed)
	for i = 2, #order do
		if due(M.FACTION_FROM[i]) then out[#out + 1] = { kind = "faction", faction = order[i] } end
	end
	for step = 2, #M.HEAT_FROM do
		if due(M.HEAT_FROM[step]) then out[#out + 1] = { kind = "heat" } end
	end
	for i = M.bosses_by(from) + 1, M.bosses_by(to) do
		out[#out + 1] = { kind = "boss", faction = M.boss_faction(home, seed, i) }
	end
	return out
end

-- The minutes of growth the budget has at `minutes`: the full rate up to rules.BUDGET_FLAT_FROM, then
-- rules.BUDGET_LATE_SHARE of it, with no end.
function M.growth(minutes)
	local from = rules.BUDGET_FLAT_FROM
	if minutes <= from then return minutes end
	return from + (minutes - from) * rules.BUDGET_LATE_SHARE
end

-- What one spawn may spend: it grows with time and the squad, and the mission's difficulty takes its
-- share of it (rules.difficulty_share).
function M.budget(minutes, players, difficulty)
	return (rules.BUDGET_BASE + rules.BUDGET_PER_MINUTE * M.growth(minutes)) * (1 + rules.BUDGET_PER_PLAYER * (math.max(players, 1) - 1))
		* rules.difficulty_share(difficulty)
end

-- difficulty: the mission's, 1 to 15. nil counts as a hard mission. seed: the mission's, which draws
-- the faction order and the bosses' factions as every machine does (M.order, M.boss_faction).
function M.new(home, rng, difficulty, seed)
	return {
		home = home, rng = rng, difficulty = difficulty, seed = seed, time = 0, next_spawn = 0, bosses_done = 0, won = false,
		wave_left = rules.WAVE_SECONDS, bank = 0, wave_units = 0, wave_swarm = 0,
	}
end

-- A machine that becomes host mid-run, when the host leaves: the director picks up at the run's clock,
-- with the bosses before it already come, instead of starting the run over. It starts on a wave.
function M.take_over(d, time)
	d.time, d.next_spawn = time, time
	d.bosses_done = M.bosses_by(time / 60)
	d.won = time >= rules.RUN_LENGTH
	d.wave_left, d.rest_left = rules.WAVE_SECONDS, nil
	d.bank, d.wave_units, d.wave_swarm, d.saving = 0, 0, 0, nil
end

-- Waves: spawning goes on for rules.WAVE_SECONDS, then stops for a break of rules.BREAK_SECONDS, and
-- the next wave opens with a spawn at once. True while resting.
local function resting(d, dt)
	if d.rest_left then
		d.rest_left = d.rest_left - dt
		if d.rest_left > 0 then return true end
		d.rest_left, d.wave_left, d.next_spawn = nil, rules.WAVE_SECONDS, d.time
		d.wave_units, d.wave_swarm = 0, 0
		return false
	end
	d.wave_left = (d.wave_left or rules.WAVE_SECONDS) - dt
	if d.wave_left > 0 then return false end
	d.rest_left = rules.BREAK_SECONDS
	return true
end

-- How many more swarm enemies the wave takes and keeps to its share: r of them, with the wave's own,
-- stay within rules.SWARM_SHARE of the wave's enemies and those r.
local function swarm_room(d)
	local share = rules.SWARM_SHARE
	return math.floor((share * d.wave_units - d.wave_swarm) / (1 - share) + 1e-9)
end

local function weight_of(key) return M.WEIGHT[key] or 1 end

-- One of `keys` for `count` enemies, held to the wave's swarm share and each key's LIMIT: the key and
-- how many, or nil when only swarm is left and the wave has the full share.
local function pick_key(d, keys, count, alive_of, planned, players)
	local key = d.rng:pick(keys, weight_of)
	if not key then return nil end
	count = math.min(count, left_of(key, alive_of, planned, players))
	if not M.SWARM[key] then return key, count end
	local room = math.min(count, swarm_room(d))
	if room >= 1 then return key, room end
	local others = {}
	for _, k in ipairs(keys) do
		if not M.SWARM[k] then others[#others + 1] = k end
	end
	if #others == 0 then return nil end
	key = d.rng:pick(others, weight_of)
	return key, math.min(count, left_of(key, alive_of, planned, players))
end

-- The tiers of `faction` with a unit on offer at `heat`, the ones `budget` pays for, or every one when
-- budget is nil.
local function tiers_for(faction, heat, budget, alive_of, planned, players)
	local out = {}
	for tier = 1, 4 do
		if (budget == nil or rules.ORB_XP[tier] <= budget) and #on_offer(faction, tier, heat, alive_of, planned, players) > 0 then
			out[#out + 1] = tier
		end
	end
	return out
end

-- Cheaper tiers come more often, so a growing budget means more enemies before bigger ones.
local function tier_weight(t) return 1 / math.sqrt(rules.ORB_XP[t]) end

local function has(list, x)
	for _, v in ipairs(list) do if v == x then return true end end
	return false
end

-- dt: game seconds since the last call. players: how many in the squad. alive: enemies alive now.
-- alive_of(key), optional: how many of an enemy key are alive now, for M.LIMIT. Answers { spawns = {
-- { key, count, tier, faction } }, boss = key or nil, won = true once, resting = true during a break }.
function M.update(d, dt, players, alive, alive_of)
	d.time = d.time + dt
	local out = { spawns = {} }
	local minutes = d.time / 60
	if d.time >= rules.RUN_LENGTH and not d.won then
		d.won = true
		out.won = true
		return out
	end
	if minutes >= M.boss_minute(d.bosses_done + 1) then
		d.bosses_done = d.bosses_done + 1
		-- The faction every machine's plan has for it (src/bosses.lua), which loaded its package.
		local faction = M.boss_faction(d.home, d.seed, d.bosses_done)
		local keys = M.ROSTER[faction][5]
		out.boss = keys[d.rng:random(1, #keys)]
		out.spawns[1] = { key = out.boss, count = 1, tier = 5, faction = faction }
		alive = alive + 1
	end
	-- A boss comes on its minute, break or not.
	if resting(d, dt) then
		out.resting = true
		return out
	end
	if d.time < d.next_spawn then return out end
	d.next_spawn = d.time + rules.SPAWN_EVERY
	local heat = M.threat(minutes)
	-- What a spawn couldn't spend waits for the next one: a low budget still buys the units that cost
	-- more than one spawn's share, now and then.
	local budget = (d.bank or 0) + M.budget(minutes, players, d.difficulty)
	local factions = M.factions(d.home, minutes, d.seed)
	local room = rules.alive_cap(d.difficulty) - alive
	local planned = {}

	-- One purchase of `faction`'s `tier` (or a cheaper tier's non-swarm unit when only swarm is left
	-- there and the wave has the full share). True when something was bought.
	local function buy(faction, tier, tiers)
		local cost = rules.ORB_XP[tier]
		local count = math.min(tier <= 2 and M.PACK or 1, math.floor(budget / cost), room)
		local key
		key, count = pick_key(d, on_offer(faction, tier, heat, alive_of, planned, players), count, alive_of, planned, players)
		if not key then
			-- Only swarm in that tier and the wave has the full share: another tier's unit, the cheapest.
			for _, t in ipairs(tiers) do
				local others = {}
				for _, k in ipairs(on_offer(faction, t, heat, alive_of, planned, players)) do
					if not M.SWARM[k] then others[#others + 1] = k end
				end
				if #others > 0 then
					tier, cost, key = t, rules.ORB_XP[t], d.rng:pick(others, weight_of)
					count = math.min(t <= 2 and M.PACK or 1, math.floor(budget / cost), room, left_of(key, alive_of, planned, players))
					break
				end
			end
		end
		if not key or count < 1 then return false end
		out.spawns[#out.spawns + 1] = { key = key, count = count, tier = tier, faction = faction }
		budget = budget - cost * count
		room = room - count
		planned[key] = (planned[key] or 0) + count
		d.wave_units = d.wave_units + count
		if M.SWARM[key] then d.wave_swarm = d.wave_swarm + count end
		return true
	end

	-- The first draw of a spawn is among every tier on offer, whatever it costs. One the budget can't
	-- pay yet is saved for: the spawn buys nothing and keeps the budget, and the next spawns buy that
	-- tier first once they can. A tier used to be drawn only while the budget left paid for it, and
	-- the cheaper tiers came first and spent it: a solo run at difficulty 5 had a fresh budget of 20,
	-- a tier 4 enemy's cost, only from minute 12, so Illusionists, tanks and Hulks hardly came.
	if room > 0 and budget >= 1 then
		local save = d.saving
		if save and not (has(factions, save.faction) and has(tiers_for(save.faction, heat, nil, alive_of, planned, players), save.tier)) then
			save, d.saving = nil, nil
		end
		if not save then
			local faction = factions[d.rng:random(1, #factions)]
			local tier = d.rng:pick(tiers_for(faction, heat, nil, alive_of, planned, players), tier_weight)
			if tier then save = { faction = faction, tier = tier } end
		end
		if save and rules.ORB_XP[save.tier] > budget then
			d.saving = save
			d.bank = math.min(budget, rules.ORB_XP[save.tier])
			return out
		end
		d.saving = nil
		if save then buy(save.faction, save.tier, tiers_for(save.faction, heat, budget, alive_of, planned, players)) end
	end

	local tries = 0
	while budget >= 1 and room > 0 and tries < 32 do
		tries = tries + 1
		local faction = factions[d.rng:random(1, #factions)]
		local tiers = tiers_for(faction, heat, budget, alive_of, planned, players)
		local tier = d.rng:pick(tiers, tier_weight)
		if not tier then break end
		if not buy(faction, tier, tiers) and #factions == 1 then
			-- Nothing but swarm that pays: the rest waits for the next spawn.
			break
		end
	end
	d.bank = room > 0 and math.min(budget, rules.BANK_LIMIT) or 0
	return out
end

return M
