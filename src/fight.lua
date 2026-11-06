-- What the fight upgrades do (src/upgrades.lua): primary hits that build up fire or poison on an enemy,
-- armor against hits from the front, a chance to live through a killing hit, less damage while downed,
-- and hits that go back to the enemy that dealt them. Obsidian API's combat.on_hit hears
-- the hits of this machine's players on every machine's enemies, and combat.on_fatal the hits that would
-- kill one of them (API 1.12.0). The statuses go out through api.enemies.apply_status, which reaches the
-- enemy's owner and names no weapon, so a burn's own damage never fills the build-up again.
local upgrades = obsidian.module("src/upgrades")
local summary = obsidian.module("src/summary")

local M = { state = nil }

-- What builds up on an enemy: the stat holding how much primary damage sets it off, and what it sets off.
-- icon: the upgrade's, which Better HUD shows over the enemy, filled with the build-up. seconds: how long the
-- effect runs when the game's StatusTemplateSettings can't say.
M.BUILD_UPS = {
	{ kind = "fire", stat = "ignite", statuses = { "regular_burn" }, icon = "ignition_rounds", seconds = 5 },
	{ kind = "poison", stat = "needle", statuses = { "poison_medium_damage", "poison_slow" }, icon = "needle_rounds", seconds = 4 },
}
-- Sustain: while an effect runs, a primary hit within this many seconds of its end sends it again, so
-- steady fire keeps it going. Each sending is a new copy of the status in the game, not a longer one,
-- so it's sent only near the end, never on every hit. While an effect runs, hits don't build up more of
-- it: setting it off again on top would stack copies and bonus hits.
M.SUSTAIN_LEAD = 1

local function g(name) return rawget(_G, name) end

-- How long a build-up's effect runs: the longest of its statuses.
function M.seconds_of(b)
	local templates = g("StatusTemplateSettings")
	local most = 0
	for _, name in ipairs(b.statuses) do
		local t = type(templates) == "table" and templates[name]
		local d = type(t) == "table" and tonumber(t.duration)
		if d and d > most and d < math.huge then most = d end
	end
	return most > 0 and most or b.seconds
end
-- Democracy Protects: a spared player stays spared this long, for the rest of a volley.
M.SPARED_FOR = 0.3

-- Build-ups and running effects by enemy, and spared players by unit.
function M.new() return { built = {}, spared = {}, running = {}, saint = {}, heals = {}, clouds = {}, clouded = {} } end

-- Napalm Needles: Ignition and Needle Rounds as one build-up that sets off both, at the lower of the two
-- shares, with both bonus hits. A burning enemy that dies leaves a cloud that poisons the enemies in it.
M.NAPALM = { kind = "napalm", statuses = { "regular_burn", "poison_medium_damage", "poison_slow" }, icon = "napalm_needles", seconds = 5, bonuses = 2 }
M.CLOUD = { statuses = { "poison_medium_damage", "poison_slow" }, seconds = 4 }

-- The build-ups a player with `stats` has, each with the share of max health that sets it off.
function M.build_ups(stats)
	if stats.napalm and (stats.ignite or 0) > 0 and (stats.needle or 0) > 0 then
		return { { b = M.NAPALM, share = math.min(stats.ignite, stats.needle) } }
	end
	local out = {}
	for _, b in ipairs(M.BUILD_UPS) do
		if (stats[b.stat] or 0) > 0 then out[#out + 1] = { b = b, share = stats[b.stat] } end
	end
	return out
end

-- An enemy died at `pos`: burning from Napalm Needles, it leaves a cloud there.
function M.killed(f, victim, pos, now)
	local run = f and victim and f.running[victim]
	if not (run and run.napalm and now < run.napalm and pos) then return false end
	f.running[victim] = nil
	f.clouds[#f.clouds + 1] = { pos = pos, ends = now + upgrades.NAPALM_CLOUD_SECONDS, next = now }
	return true
end

-- The clouds at `now`: every NAPALM_CLOUD_TICK, each poisons the enemies in it that aren't poisoned by a
-- cloud already. near(radius, pos): the enemies there. poison(enemy, statuses).
function M.step_clouds(f, now, near, poison)
	if not f then return end
	for i = #f.clouds, 1, -1 do
		local c = f.clouds[i]
		if now >= c.ends then
			table.remove(f.clouds, i)
		elseif now >= c.next then
			c.next = now + upgrades.NAPALM_CLOUD_TICK
			for _, enemy in ipairs(near(upgrades.NAPALM_CLOUD_RADIUS, c.pos) or {}) do
				if (f.clouded[enemy] or -math.huge) <= now then
					f.clouded[enemy] = now + M.CLOUD.seconds
					poison(enemy, M.CLOUD.statuses)
				end
			end
		end
	end
end

-- Iron Saint: the share of max health a save heals, once, for the player's machine to give.
function M.take_heal(unit)
	local f = M.state
	local heal = f and unit and f.heals[unit]
	if heal then f.heals[unit] = nil end
	return heal
end

-- Iron Saint: whether the player is invulnerable at `now`, after a save.
function M.saintly(f, unit, now)
	return f ~= nil and (f.saint[unit] or -math.huge) > now
end

-- The primary damage that sets a build-up off on an enemy of `max_hp`: `share` of it, within the floor
-- and the cap of src/upgrades.lua.
function M.need(share, max_hp)
	return math.max(upgrades.BUILD_FLOOR, math.min(upgrades.BUILD_CAP, share * (tonumber(max_hp) or 0)))
end

-- The extra hit when a build-up sets off, through armor.
function M.bonus(max_hp)
	return math.min(upgrades.PROC_CAP, upgrades.PROC_BONUS * (tonumber(max_hp) or 0))
end

-- How long a build-up on an enemy of `max_hp` takes to wear off after the last primary hit.
function M.fade_of(max_hp)
	local lo, hi = upgrades.BUILD_FADE_HP[1], upgrades.BUILD_FADE_HP[2]
	local hp = math.max(lo, math.min(hi, tonumber(max_hp) or 0))
	local t = math.log(hp / lo) / math.log(hi / lo)
	return upgrades.BUILD_FADE[1] + t * (upgrades.BUILD_FADE[2] - upgrades.BUILD_FADE[1])
end

-- What is left `now` of a build-up { amount, at, fade }: it runs down evenly to nothing over `fade`
-- seconds from the last hit.
function M.left_of(b, now)
	if not b or b.amount <= 0 then return 0 end
	return math.max(0, b.amount * (1 - (now - b.at) / b.fade))
end

-- A hit landed by a player with `stats` at the run's time `now`, on an enemy of `max_hp`: the statuses to
-- send the victim, or nil, and what else came of it: { bonus = damage of the extra hit, effects = { kind ->
-- seconds it runs from now } for the effects set off or kept going, bars = { kind -> { fraction, drain } }
-- for the strip under the enemy's health bar: how full it is now and the seconds it runs down to empty
-- over (the build-up wearing off, or the effect running out) }.
function M.on_hit(f, stats, victim, hit, now, max_hp)
	local out
	local extra = { bonus = 0, effects = {}, bars = {} }
	local function send(b)
		out = out or {}
		for _, s in ipairs(b.statuses) do out[#out + 1] = s end
		local seconds = M.seconds_of(b)
		local run = f.running[victim] or {}
		f.running[victim] = run
		run[b.kind] = now + seconds
		extra.effects[b.kind] = seconds
		extra.bars[b.kind] = { fraction = 1, drain = seconds, icon = b.icon }
	end
	if hit.slot == "primary_weapon" then
		for _, up in ipairs(M.build_ups(stats)) do
			local b, share = up.b, up.share
			if share > 0 then
				local ends = f.running[victim] and f.running[victim][b.kind]
				if ends and now < ends then
					-- Running: only kept going, in its last moments.
					if ends - now <= M.SUSTAIN_LEAD then send(b) end
				else
					local by = f.built[victim] or {}
					f.built[victim] = by
					local fade = M.fade_of(max_hp)
					local amount = M.left_of(by[b.kind], now) + hit.damage
					local need = M.need(share, max_hp)
					if amount >= need then
						by[b.kind] = nil
						extra.bonus = extra.bonus + M.bonus(max_hp) * (b.bonuses or 1)
						extra.bonus_from = extra.bonus_from or b.icon
						send(b)
					else
						by[b.kind] = { amount = amount, at = now, fade = fade }
						extra.bars[b.kind] = { fraction = amount / need, drain = fade, icon = b.icon }
					end
				end
			end
		end
	end
	return out, extra
end

-- A killing hit on a player with `stats`: whether they live through it. roll() is from 0 to 1.
function M.spare(f, stats, unit, now, roll)
	if (stats.democracy or 0) <= 0 then return false end
	if (f.spared[unit] or -math.huge) > now or M.saintly(f, unit, now) then return true end
	if roll() < stats.democracy then
		f.spared[unit] = now + M.SPARED_FOR
		-- Iron Saint: a while of invulnerability, and a heal once the hit is in (src/run.lua gives it).
		if (stats.saint_seconds or 0) > 0 then
			f.saint[unit] = now + stats.saint_seconds
			f.heals[unit] = stats.saint_heal
		end
		-- A new save, not the hits the moment after it covers: the flash and the sound (main.lua).
		if M.on_spare then pcall(M.on_spare, unit) end
		return true
	end
	return false
end

-- Democracy Protects on a downing hit, as the game prices a hit on a player with `stats`: a hit that
-- would leave a standing player downed (health at 0 or under, but above the constitution) is resisted
-- on a spare, leaving 1 health. A hit past the constitution is a fatal one, which Obsidian API's
-- on_fatal already asks about (M.install). The new damage and kills. decide(): whether Democracy
-- Protects spares the player, asked at most once per hit.
function M.resist_downing(stats, hp, constitution, damage, kills, decide)
	if (stats.democracy or 0) <= 0 or type(damage) ~= "number" or damage <= 0 or type(hp) ~= "number" or hp <= 0 then return damage, kills end
	local left = hp - damage
	if left > 0 or left <= constitution then return damage, kills end
	if decide() then return math.max(hp - 1, 0), false end
	return damage, kills
end

-- The game prices one hit more than once on the player's own machine (its prediction and the health
-- component), so a Democracy Protects roll is kept for a moment and every pricing of that hit agrees.
M.ROLL_KEPT = 0.25

-- Strike Back reaches an enemy this close to the player it hit.
M.STRIKE_REACH = 2

-- The share of a hit an enemy takes back from a player with `stats`, or nil.
function M.strike_back(stats, damage, metres)
	-- Spiked Plating reaches further and deals back more.
	if (stats.strike_back or 0) <= 0 or not (damage and damage > 0) or metres > (stats.strike_reach or M.STRIKE_REACH) then return nil end
	return damage * stats.strike_back * (stats.strike_times or 1)
end

-- Facetanker: armor against a hit from the front half of the body, as the hit's power taken down by it
-- before the game prices the hit, which comes to the same as more armor: the damage is the power past the
-- armor (HealthComponent.calculate_damage). angle_hit is the angle between where the body faces and where
-- the hit comes from (MeleeComponent.do_damage works it out so). A hit that ignores armor passes as it is,
-- and so does a status's damage over time, which carries armorignore (StatusSettings).
M.FRONT = math.pi / 2
function M.frontal(power, armor, angle_hit, armorignore, ignore_armor)
	if type(power) ~= "number" or type(angle_hit) ~= "number" or (armor or 0) <= 0 or armorignore or ignore_armor then return power end
	local a = (angle_hit + math.pi) % (2 * math.pi) - math.pi
	if math.abs(a) > M.FRONT then return power end
	return math.max(0, power - armor)
end

-- Facetanker, Diver's Resolve, Democracy Protects on downing hits, and Strike Back: the cost of a hit on a
-- player of this machine, as the game works it out, and the hits they take.
local function install_guard(api, find, clock)
	local rolls = {}
	obsidian.hook("HealthComponent", "calculate_damage", function(original, unit, power, armorignore, armorpiercing, angle_inc, angle_hit, ...)
		local own = find(unit)
		if own and (own.front_armor or 0) > 0 then power = M.frontal(power, own.front_armor, angle_hit, armorignore, (select(2, ...))) end
		local damage, zone, kills = original(unit, power, armorignore, armorpiercing, angle_inc, angle_hit, ...)
		local stats = type(damage) == "number" and damage > 0 and find(unit)
		-- Iron Saint's invulnerability after a save.
		if stats and M.state and M.saintly(M.state, unit, clock and clock() or 0) then return 0, zone, false end
		if stats and stats.downed_damage < 1 then
			local health = g("EntityAux").state(unit, "health")
			if health and health.is_downed then damage = damage * stats.downed_damage end
		end
		if stats and (stats.democracy or 0) > 0 and M.state then
			local health = g("EntityAux").state(unit, "health")
			if health then
				local now = clock and clock() or 0
				local function decide()
					local kept = rolls[unit]
					if kept and math.abs(now - kept.at) <= M.ROLL_KEPT then return kept.spare end
					local spare = M.state ~= nil and M.spare(M.state, stats, unit, now, math.random)
					rolls[unit] = { at = now, spare = spare }
					return spare
				end
				damage, kills = M.resist_downing(stats, health.hitpoints_real or health.hitpoints, health.constitution or -100, damage, kills, decide)
			end
		end
		return damage, zone, kills
	end)
	api.events.on("on_damage_taken", function(unit, hit)
		local stats = hit and find(unit)
		local enemy = stats and (hit.owner_unit or hit.attacker_unit)
		local U, aux = g("Unit"), g("EntityAux")
		if not (enemy and U.alive(enemy) and aux.has_component(enemy, "enemy")) then return end
		local back = M.strike_back(stats, hit.damage, g("Vector3").distance(U.world_position(enemy, 0), U.world_position(unit, 0)))
		if back then
			summary.mark_hit(enemy, "strike_back", unit)
			api.enemies.damage(enemy, back, nil, { through_armor = true })
		end
	end)
end

-- find(unit): the stats of the local player with that unit, or nil outside a run. clock(): the run's time.
function M.install(api, find, clock)
	install_guard(api, find, clock)
	if not (api.combat and api.combat.on_hit and api.combat.on_fatal) then return false end
	local f = M.new()
	M.state = f
	api.combat.on_hit(function(victim, hit)
		local stats = find(hit.owner_unit)
		if not stats or not g("EntityAux").has_component(victim, "enemy") then return end
		local health = g("EntityAux").state(victim, "health")
		local max_hp = health and tonumber(health.max_hitpoints) or 0
		local statuses, extra = M.on_hit(f, stats, victim, hit, clock(), max_hp)
		for _, status in ipairs(statuses or {}) do api.enemies.apply_status(victim, status) end
		if extra and extra.bonus > 0 then
			summary.mark_hit(victim, extra.bonus_from or "ignition_rounds", hit.owner_unit)
			api.enemies.damage(victim, extra.bonus, nil, { through_armor = true })
		end
		-- The icon over the enemy (main.lua): filled with the build-up, or full and running down with the
		-- effect once it is set off or kept going.
		if M.on_buildup and extra then
			for kind, bar in pairs(extra.bars) do pcall(M.on_buildup, victim, kind, bar.fraction, bar.drain, bar.icon) end
		end
	end)
	M.api = api
	M.fatal = function(unit)
		local stats = find(unit)
		return stats ~= nil and M.spare(f, stats, unit, clock(), math.random)
	end
	return true
end

-- Democracy Protects, once Survivors' content first runs: Obsidian API answers on_fatal with
-- "not_started" to an expansion before then. The listener stays for every later run, and like a hook
-- of this mod, it runs only while the content does. True once it's in.
function M.arm()
	if M.armed or not M.fatal then return M.armed == true end
	local ok, why = M.api.combat.on_fatal(M.fatal)
	M.armed = ok == true
	if not M.armed then obsidian.log("arcade: Democracy Protects isn't in: " .. tostring(why)) end
	return M.armed
end

-- A run over: nothing of it is kept.
function M.clear()
	if M.state then
		local fresh = M.new()
		for k, v in pairs(fresh) do M.state[k] = v end
	end
end

return M
