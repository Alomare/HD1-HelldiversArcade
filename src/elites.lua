-- Elites: the game's own Assassinate targets (the Brood Commander, the Warlord and the Council Member,
-- the units the Assassinate objective sends: generic_marker_assassinate's enemy_unit_path), each with
-- a kind that adds something of its own. All three are in the factions' normal packages (race_bugs,
-- race_cyborgs, race_illuminates), which every Survivors map loads (src/level.lua), so nothing more
-- loads with the level.
--
-- The host spawns them, from ELITE_FROM minutes on, one every EVERY seconds or so, and keeps MOST(t)
-- alive at the most. The host owns them and runs what their kinds do. Every machine needs the kind for
-- the look: the host shares where each elite stands and its kind through lobby data, and every machine
-- binds the nearest unit of the right type to it (M.match).
--
-- Kinds:
--   fire     leaves the flamethrower's burning ground behind it as it moves, a wide fire where it dies,
--            and moves HALF_SWIFT times as fast
--   shock    arcs every SHOCK_EVERY seconds to the nearest units within SHOCK_RANGE, players and enemies,
--            while a Helldiver out of the drop pod is within SHOCK_RANGE; its own side takes half
--   noxious  its hits poison like a Stalker's, on death it leaves toxic ground for POOL_SECONDS, and it
--            moves HALF_SWIFT times as fast
--   bulwark  carries a shield dome on itself: units walk through, shots from outside stop on it
--   swift    moves SWIFT_SPEED times as fast and doesn't stagger from hits
--   brood    splits into BROOD_COUNT small enemies of its faction on death
local spots = obsidian.module("src/spots")
local art = obsidian.module("src/art")

local api = obsidian.import("obsidian.api")

local M = {}

local function g(name) return rawget(_G, name) end

M.KINDS = { "fire", "shock", "noxious", "bulwark", "swift", "brood" }
-- Each kind's effect on the body (Obsidian API's world.attach_effect, 1.33.1 for all but the shock) and
-- its icon in the atlas, which Better HUD shows in the middle of the elite's health bar (elite_mark).
M.LOOK = {
	fire = { effect = "fire", icon = "elite_fire" },
	shock = { effect = "enemy_shock", icon = "elite_shock" },
	noxious = { effect = "poison", icon = "elite_noxious" },
	bulwark = { effect = nil, icon = "elite_bulwark" },
	swift = { effect = nil, icon = "elite_swift" },
	brood = { effect = "confuse", icon = "elite_brood" },
}

-- The base unit by faction: catalog key and unit path.
M.UNITS = {
	bugs = { key = "bug_warrior_commander", path = "characters/bug_warrior/bug_warrior_commander" },
	cyborgs = { key = "cyborg_hulk_assassinate", path = "characters/cyborg_hulk_assassinate/cyborg_hulk_assassinate" },
	illuminates = { key = "illuminate_illusionist_assassinate", path = "characters/illuminate_illusionist_assassinate/illuminate_illusionist_assassinate" },
}
-- A small enemy of each faction, for the Brood's split.
M.SMALL = { bugs = "bug_scout", cyborgs = "cyborg_initiate", illuminates = "illuminate_tripod" }

-- When they come. The first at 3:00, once the squad has a few upgrades; then one every 60 to 90
-- seconds, one at a time until 8:00 and two after. Five to eight minutes of a twelve minute run see an
-- elite most of the time, without two of them piling up on top of the first Heat steps.
M.FROM = 3 -- minutes
M.EVERY = { 60, 90 } -- seconds between elites
M.AFTER_DEATH = 20 -- seconds at least between an elite's death and the next
M.TWO_FROM = 8 -- minutes from which two may be alive
M.RING = { 24, 32 } -- metres from the squad's centre, as a boss lands

function M.most(minutes)
	if minutes < M.FROM then return 0 end
	return minutes >= M.TWO_FROM and 2 or 1
end

-- The kinds' numbers.
M.FIRE_EVERY = 1 -- seconds between pools at the most
M.FIRE_STEP = 1.5 -- metres walked since the last pool
M.FIRE_UNIT = "gameobjects/gameobject_flamethrower_napalm_area" -- 1.8 m of fire for 5 seconds, in mission_common
M.SHOCK_EVERY = 1.5
M.SHOCK_RANGE = 8
M.SHOCK_TARGETS = 3
-- A Tesla Tower bolt is 1200 through armor: the elite's arcs are 5% of it, and 1.25% on players. Its own
-- side, the other enemies, take SHOCK_ALLY_SHARE of the 5%.
M.SHOCK_ENEMY_POWER = 60
M.SHOCK_PLAYER_POWER = 15
M.SHOCK_ALLY_SHARE = 0.5
-- Seconds a new Helldiver body lands for: the character's spawn_time, the intro_land cutscene in the
-- hellpod (characters/helldiver_private_01 character_info; character_component.lua:177-180).
M.LAND_SECONDS = 5.4
M.POISON = { "poison_slow", "poison_damage" } -- the Stalker's hit
M.POOL_UNIT = "gameobjects/gameobject_toxic_area" -- the toxic impact grenade's ground, 10 seconds, in mission_common
M.POOL_SECONDS = 30
M.POOL_EVERY = 10 -- the ground is laid again as each one runs out
M.DOME_UNIT = "equipment/equipment_shield_generator_shield_01" -- the projected shield, 2.8 m, in mission_common
M.DOME_BACK = 8 -- seconds before a broken dome comes back
-- The dome's actors that go (shield_dome_component.lua:54-57): the c_ two stop walkers (the game
-- takes them off a dome that fades, line 43), the inner shell stops shots from inside. The outer
-- shell, g_shield, stays and stops shots from outside.
M.DOME_LOOSE = { "c_shield", "c_shield_inner", "g_shield_inner" }
M.DOME_RIDE = 4 -- metres between a new dome and the Bulwark elite it rides on
M.DOME_LAG = 0.5 -- metres the outer shell may trail the dome before it's made again where the dome is
M.SWIFT_SPEED = 1.6
-- Noxious and Fire: half of Swift's boost.
M.HALF_SWIFT = 1 + (M.SWIFT_SPEED - 1) / 2
M.FASTER = { swift = M.SWIFT_SPEED, noxious = M.HALF_SWIFT, fire = M.HALF_SWIFT }
-- Fire's death: the flamethrower's ground at the spot and in a ring round it, laid again as it burns out.
M.BLAZE_RING = 6
M.BLAZE_RADIUS = 2.4 -- metres
M.BLAZE_SECONDS = 15
M.BLAZE_EVERY = 4.5
-- Toxic ground has no look of its own: the game's poison look puffs over it, on every machine.
M.CLOUD_EFFECT = "effects/generated/status_poison" -- in mission_common
M.CLOUD_EVERY = 0.6
M.CLOUD_SPOTS = 6
M.CLOUD_RADIUS = 2.2
M.SWIFT_IMMUNE = { "generic_stun", "knockdown" } -- bullet_stun is the stagger of every hit
M.BROOD_COUNT = 3

M.SHARE_EVERY = 0.5 -- seconds between the host's shares of where the elites are
M.MATCH = 4 -- metres between a shared elite and the unit bound to it
M.ARCS_KEPT = 2
M.ARCS_FRESH = 1.5

-- The state of a run: the host's elites by unit, the kind of every elite this machine knows, the
-- host's schedule, the pools still to lay, the arcs, and when each Helldiver body was first seen (by
-- this machine's real-time clock) with what the shock has said about its landing.
function M.new()
	return { next_at = nil, alive = {}, kinds = setmetatable({}, { __mode = "k" }), looks = {}, pools = {},
		arcs = { seq = 0, events = {} }, seen_arcs = {}, share_in = 0, shared = {}, last_death = -math.huge,
		clock = 0, bodies = {}, landing_told = {}, clouds = {} }
end

-- The debug page's choices (src/debug.lua), kept across runs. base: "home" for the mission's own
-- faction, or a faction of M.UNITS. paused: the run's own schedule spawns nothing, until the run ends.
M.debug = { base = "home", count = 1, distance = 8, paused = false }

M.state = M.new()

-- Host: whether an elite is due at `now` (seconds of the run's clock) with `alive` out, and when the
-- next one is. draw(): a number from 0 to 1.
function M.due(e, now, alive, draw)
	if e.next_at == nil then e.next_at = M.FROM * 60 end
	if alive >= M.most(now / 60) or now < e.next_at or now < e.last_death + M.AFTER_DEATH then return false end
	e.next_at = now + M.EVERY[1] + draw() * (M.EVERY[2] - M.EVERY[1])
	return true
end

-- A kind none of the elites out has. taken: { [kind] = true }.
function M.pick_kind(taken, draw)
	local open = {}
	for _, k in ipairs(M.KINDS) do
		if not taken[k] then open[#open + 1] = k end
	end
	if #open == 0 then open = M.KINDS end
	return open[math.min(#open, math.floor(draw() * #open) + 1)]
end

-- The faction of the unit with this path, or nil when it isn't an elite's base.
function M.faction_of(path)
	for faction, u in pairs(M.UNITS) do
		if u.path == path then return faction end
	end
	return nil
end

local function flat2(a, b) return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 end

-- Binds shared elites to units: each spot ({ kind, x, y }) takes the nearest unit of `candidates`
-- ({ unit, pos }) within MATCH metres that isn't bound to another kind. kinds: unit -> kind, filled in.
function M.match(shared, candidates, kinds)
	local taken = {}
	for _, s in ipairs(shared) do
		local best, best_d = nil, M.MATCH * M.MATCH
		for _, c in ipairs(candidates) do
			local d = flat2(s, c.pos)
			local mine = kinds[c.unit]
			if d <= best_d and not taken[c.unit] and (mine == nil or mine == s.kind) then best, best_d = c.unit, d end
		end
		if best then
			taken[best] = true
			kinds[best] = s.kind
		end
	end
end

-- The nearest `count` of `list` ({ unit, pos }) within `range` of `from`, nearest first, not `self`.
function M.nearest(from, list, range, count, self)
	local near = {}
	for _, t in ipairs(list) do
		if t.unit ~= self and t.pos then
			local d = (t.pos.x - from.x) ^ 2 + (t.pos.y - from.y) ^ 2 + ((t.pos.z or 0) - (from.z or 0)) ^ 2
			if d <= range * range then near[#near + 1] = { t = t, d = d } end
		end
	end
	table.sort(near, function(a, b) return a.d < b.d end)
	local out = {}
	for i = 1, math.min(count, #near) do out[i] = near[i].t end
	return out
end

-- Whether a fire pool is due: FIRE_EVERY seconds since the last and FIRE_STEP metres from it.
function M.fire_due(f, pos, now)
	if f.at and now - f.at < M.FIRE_EVERY then return false end
	if f.pos and flat2(f.pos, pos) < M.FIRE_STEP * M.FIRE_STEP then return false end
	f.at, f.pos = now, { x = pos.x, y = pos.y, z = pos.z }
	return true
end

-- The toxic ground left by a Noxious elite: due now, and how many more after.
function M.new_pool(pos, now, kind)
	if kind == "fire" then
		return { kind = "fire", x = pos.x, y = pos.y, z = pos.z or 0, next = now, every = M.BLAZE_EVERY, left = math.ceil(M.BLAZE_SECONDS / M.BLAZE_EVERY) }
	end
	return { kind = "toxic", x = pos.x, y = pos.y, z = pos.z or 0, next = now, every = M.POOL_EVERY, left = math.ceil(M.POOL_SECONDS / M.POOL_EVERY) }
end

-- The spots a pool lays its units on: the toxic one in the middle, the fire in the middle and a ring.
function M.pool_spots(p)
	local out = { { x = p.x, y = p.y, z = p.z } }
	if p.kind == "fire" then
		for i = 1, M.BLAZE_RING do
			local a = (i - 1) / M.BLAZE_RING * 2 * math.pi
			out[#out + 1] = { x = p.x + math.cos(a) * M.BLAZE_RADIUS, y = p.y + math.sin(a) * M.BLAZE_RADIUS, z = p.z }
		end
	end
	return out
end

function M.pools_due(pools, now)
	local out = {}
	for i = #pools, 1, -1 do
		local p = pools[i]
		if now >= p.next then
			out[#out + 1] = p
			p.left, p.next = p.left - 1, now + (p.every or M.POOL_EVERY)
			if p.left <= 0 then table.remove(pools, i) end
		end
	end
	return out
end

local function num(x) return string.format("%.1f", x) end
local function whole(x) return string.format("%.0f", x) end

-- The host's text: the mission, then each elite out as kind@x,y.
function M.encode(mission, list)
	local parts = {}
	for i, s in ipairs(list) do parts[i] = s.kind .. "@" .. num(s.x) .. "," .. num(s.y) end
	return tostring(mission) .. ";" .. table.concat(parts, "|")
end

function M.decode(text)
	if type(text) ~= "string" then return nil end
	local mission, rest = text:match("^([^;]*);(.*)$")
	if not mission then return nil end
	local out = { mission = mission, list = {} }
	for kind, x, y in rest:gmatch("(%a+)@(-?[%d.]+),(-?[%d.]+)") do
		if M.LOOK[kind] then out.list[#out.list + 1] = { kind = kind, x = tonumber(x), y = tonumber(y) } end
	end
	return out
end

-- The Shock elites' arcs, as the host drew them: each one the elite's spot and its targets'.
function M.record_arc(side, from, targets, now)
	side.seq = side.seq + 1
	side.events[#side.events + 1] = { seq = side.seq, time = now, from = from, to = targets }
	while #side.events > M.ARCS_KEPT do table.remove(side.events, 1) end
end

local function point(p) return whole(p.x) .. "," .. whole(p.y) .. "," .. whole(p.z or 0) end

function M.encode_arcs(side, mission)
	if #side.events == 0 then return nil end
	local parts = { tostring(mission) }
	for _, ev in ipairs(side.events) do
		local pts = { point(ev.from) }
		for _, t in ipairs(ev.to) do pts[#pts + 1] = point(t) end
		parts[#parts + 1] = ev.seq .. "@" .. num(ev.time) .. "@" .. table.concat(pts, "|")
	end
	return table.concat(parts, ";")
end

function M.decode_arcs(text)
	if type(text) ~= "string" then return nil end
	local parts = {}
	for part in (text .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = part end
	if #parts < 1 or parts[1] == "" then return nil end
	local out = { mission = parts[1], events = {} }
	for i = 2, #parts do
		local seq, time, pts = parts[i]:match("^(%d+)@(-?[%d.]+)@(.*)$")
		if seq then
			local list = {}
			for x, y, z in pts:gmatch("(-?[%d.]+),(-?[%d.]+),(-?[%d.]+)") do list[#list + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) } end
			if #list >= 2 then
				out.events[#out.events + 1] = { seq = tonumber(seq), time = tonumber(time), from = list[1], to = { unpack(list, 2) } }
			end
		end
	end
	return out
end

-- Another machine's arcs not drawn yet, fresh and of this mission. The first text seen only sets
-- where to start.
function M.take_arcs(seen, peer, e, mission, now)
	if not e or e.mission ~= tostring(mission) then return {} end
	local top, out = seen[peer], {}
	local most = top or 0
	for _, ev in ipairs(e.events) do
		if top and ev.seq > top and math.abs(now - ev.time) <= M.ARCS_FRESH then out[#out + 1] = ev end
		most = math.max(most, ev.seq)
	end
	seen[peer] = most
	return out
end

-- What one arc does to a target of the Shock elite's list: a player takes SHOCK_PLAYER_POWER, the
-- elite's own side SHOCK_ALLY_SHARE of SHOCK_ENEMY_POWER.
function M.shock_power(t)
	if t.player then return M.SHOCK_PLAYER_POWER end
	return M.SHOCK_ENEMY_POWER * M.SHOCK_ALLY_SHARE
end

-- Whether a Helldiver body is still in its hellpod, from what this machine can read of it (info):
--   state      the name of the character's state, where this machine owns the body: a new body
--              lands in CharacterStateCutscene (character_component.lua:177-180), and only leaves it
--              once the intro_land animation is over
--   collision  the character's collision_enabled, which every machine has: the game turns it off for
--              the landing (and for a seat, a jump, the extraction and death), and while it's off the
--              body's damage zone is player_damage_zone_invulnerable (character_component.lua:878-960)
--   seated     the body sits in a vehicle, which turns collision off too
--   age        seconds since this machine first saw the body, for when neither can be read
function M.landing(info)
	if info.state ~= nil then return info.state == "CharacterStateCutscene" end
	if info.collision ~= nil then return info.collision == false and not info.seated end
	return info.age ~= nil and info.age < M.LAND_SECONDS
end

-- A Helldiver the Shock elite reacts to: alive and out of the drop pod.
function M.counts(t)
	return t.player == true and not t.dead and not t.landing
end

-- The Shock elite's targets from `from`: the nearest SHOCK_TARGETS of `list` ({ unit, pos, player,
-- dead, landing }) within SHOCK_RANGE, not `self`, Helldivers only once out of the pod. Nothing at all
-- unless such a Helldiver is in range: then nil and why, "landing" when only landing ones are.
function M.shock_targets(from, list, self)
	local open, helldiver, landing = {}, false, false
	for _, t in ipairs(list) do
		local near = #M.nearest(from, { t }, M.SHOCK_RANGE, 1, self) > 0
		if not t.player then
			open[#open + 1] = t
		elseif M.counts(t) then
			open[#open + 1] = t
			helldiver = helldiver or near
		elseif t.landing and not t.dead then
			landing = landing or near
		end
	end
	if not helldiver then return nil, landing and "landing" or "no_helldiver" end
	return M.nearest(from, open, M.SHOCK_RANGE, M.SHOCK_TARGETS, self)
end

-- Where `count` elites go around `at`, `metres` off it, evenly round: the first due +x.
function M.ring_spots(at, count, metres)
	local out = {}
	for i = 1, count do
		local a = (i - 1) * 2 * math.pi / count
		out[i] = { x = at.x + math.cos(a) * metres, y = at.y + math.sin(a) * metres, z = at.z or 0 }
	end
	return out
end

-- The path a star of bolts takes from the elite to each target and back, at body height.
function M.arc_path(from, targets)
	local up = function(p) return { x = p.x, y = p.y, z = (p.z or 0) + 1 } end
	local path = { up(from) }
	for i, t in ipairs(targets) do
		path[#path + 1] = up(t)
		if i < #targets then path[#path + 1] = up(from) end
	end
	return path
end

-- The game -------------------------------------------------------------------------------------------

local function position(unit)
	local ok, v = pcall(g("Unit").world_position, unit, 0)
	if not (ok and v) then return nil end
	local V = g("Vector3")
	return { x = V.x(v), y = V.y(v), z = V.z(v) }
end

-- A unit still in the level and not dead.
local function alive(unit)
	local ok, yes = pcall(g("Unit").alive, unit)
	if not (ok and yes) then return false end
	local ok2, st = pcall(g("EntityAux").state, unit, "health")
	return not (ok2 and type(st) == "table" and st.is_dead)
end

-- Unit.get_data on a destroyed unit takes the game down in the engine, past any pcall (helldivers.exe +0x13b8e0, the lookup behind every get_data), so a unit is asked only while Unit.alive says it's there.
local function path_of(unit)
	local ok_alive, alive = pcall(g("Unit").alive, unit)
	if not (ok_alive and alive) then return nil end
	local ok, path = pcall(g("Unit").get_data, unit, "unit_path")
	return ok and type(path) == "string" and path or nil
end

local function vec(p) return g("Vector3")(p.x, p.y, p.z or 0) end

-- A networked entity of the game where `pos` is: host only. Answers the unit, or nil.
local function spawn_entity(path, pos)
	local st = api.game.state()
	local spawner = type(st) == "table" and st.entity_spawner
	if not spawner then return nil end
	local ok, unit = pcall(spawner.spawn_entity, spawner, path, vec(pos), g("Quaternion").identity(), nil, {})
	if not ok then
		obsidian.log("arcade: elite: no " .. path .. ": " .. tostring(unit))
		return nil
	end
	return unit
end

local function command(unit, component, name, data)
	return pcall(g("EntityAux").queue_command_master, unit, component, name, data)
end

-- The spawn manager's answers for an elite: the unit spawned takes its kind.
local CALLBACKS = {}
function CALLBACKS.on_entity_spawned(_, unit, _, _, _, param)
	if not (param and unit) then return end
	local e = M.state
	e.alive[unit] = { kind = param.kind, faction = param.faction, fire = {}, shock_in = M.SHOCK_EVERY, swift_in = 0 }
	e.kinds[unit] = param.kind
	obsidian.log("arcade: a " .. param.kind .. " elite is out, " .. tostring(param.faction))
end
function CALLBACKS.on_group_failed(_, _, param)
	obsidian.log("arcade: the " .. tostring(param and param.kind) .. " elite found no ground")
	M.state.next_at = math.min(M.state.next_at or 0, (M.state.now or 0) + 5)
end

local function package_online(faction)
	local boot = g("Boot")
	local pm = type(boot) == "table" and boot.package_manager
	local ok, on = pcall(pm.is_package_online, pm, "resource_packages/race_" .. faction)
	return ok and on == true
end

-- Host only: an elite of `kind` and `faction` at `at`. false and why when it can't.
function M.spawn(kind, faction, at)
	local unit = M.UNITS[faction]
	if not (unit and M.LOOK[kind] and at) then return false, "bad_value" end
	if not package_online(faction) then return false, "not_loaded" end
	local st = api.game.state()
	local em = type(st) == "table" and st.encounter_manager
	local spawner = em and em.spawn_manager
	if not spawner then return false, "not_in_mission" end
	local pos = vec(at)
	local map = st.generated_level
	if map and map.get_closest_position_on_level then
		local ok, p = pcall(map.get_closest_position_on_level, map, pos)
		if ok and p then pos = p end
	end
	local ok, err = pcall(spawner.queue_group_spawn, spawner, pos, { units = { { unit_path = unit.path, amount = 1 } } }, CALLBACKS,
		{ kind = kind, faction = faction }, nil, 0, g("Network").peer_id())
	if not ok then return false, tostring(err) end
	return true
end

local function taken_kinds(e)
	local taken, n = {}, 0
	for unit, el in pairs(e.alive) do
		if alive(unit) then
			taken[el.kind] = true
			n = n + 1
		end
	end
	return taken, n
end

-- Host: the next elite, from one of the factions in play, around the squad.
local function spawn_due(e, run, squad, factions, draw)
	local taken = taken_kinds(e)
	local kind = M.pick_kind(taken, draw)
	local faction = factions[math.min(#factions, math.floor(draw() * #factions) + 1)]
	local st = api.game.state()
	local checks = spots.of_level(type(st) == "table" and st.generated_level or nil, api.world and api.world.raycast)
	local at = checks and spots.around(squad, M.RING[1], M.RING[2], run.director.rng, checks)
		or { x = squad.x + M.RING[1], y = squad.y, z = squad.z }
	local ok, why = M.spawn(kind, faction, at)
	obsidian.log("arcade: elite " .. kind .. " " .. tostring(faction) .. ": " .. tostring(ok) .. " " .. tostring(why or ""))
end

local function unit_alive(unit)
	local ok, yes = pcall(g("Unit").alive, unit)
	return ok and yes == true
end

-- What this machine can read of a Helldiver body's landing, for M.landing: the state's name where this
-- machine owns the body, else the collision every machine has, else how long it has been seen.
local function body_info(e, unit)
	local EA = g("EntityAux")
	local seen = e.bodies[unit]
	local info = { age = seen and e.clock - seen or nil }
	local ok_m, mine = pcall(EA.has_component_master, unit, "character")
	if ok_m and mine then
		local ok, cs = pcall(EA.state_master, unit, "character")
		local st = ok and type(cs) == "table" and cs.current_state
		if type(st) == "table" and type(st.name) == "string" then
			info.state = st.name
			return info
		end
	end
	local ok, cs = pcall(EA.state, unit, "character")
	if ok and type(cs) == "table" and type(cs.collision_enabled) == "boolean" then
		info.collision = cs.collision_enabled
		info.seated = cs.current_seat_unit ~= nil and unit_alive(cs.current_seat_unit)
	end
	return info
end

-- Every machine, every frame: when each Helldiver body was first seen. A respawn is a new body.
local function note_bodies(e)
	for unit in pairs(e.bodies) do
		if not unit_alive(unit) then e.bodies[unit], e.landing_told[unit] = nil, nil end
	end
	for _, a in ipairs(api.game.all_avatars()) do
		if not e.bodies[a.unit] then e.bodies[a.unit] = e.clock end
	end
end

-- The log lines that show the landing check at work in a game run: once as a body is skipped while it
-- lands, once as it counts again.
local function tell_landing(e, unit, landing, info)
	local told = e.landing_told[unit]
	local how = info.state and ("state " .. info.state) or info.collision ~= nil and ("collision " .. tostring(info.collision))
		or ("age " .. string.format("%.1f", info.age or -1))
	if landing and not told then
		e.landing_told[unit] = "landing"
		obsidian.log("arcade: shock elite: a Helldiver is landing, not counted (" .. how .. ")")
	elseif not landing and told == "landing" then
		e.landing_told[unit] = "out"
		obsidian.log("arcade: shock elite: the Helldiver is out of the pod after " .. string.format("%.1f", info.age or -1) .. " s (" .. how .. ")")
	end
end

-- Units the shock reaches: every player's body and every enemy, with where they stand. A body is
-- dead or still landing as M.counts reads it.
local function shock_list(e)
	local list = {}
	for _, a in ipairs(api.game.all_avatars()) do
		local p = position(a.unit)
		if p then
			local info = body_info(e, a.unit)
			local landing = M.landing(info)
			tell_landing(e, a.unit, landing, info)
			list[#list + 1] = { unit = a.unit, pos = p, player = true, dead = not alive(a.unit), landing = landing }
		end
	end
	for _, unit in ipairs(api.enemies.list()) do
		local p = position(unit)
		if p then list[#list + 1] = { unit = unit, pos = p } end
	end
	return list
end

local function shock(e, el, unit, pos, now)
	local targets, why = M.shock_targets(pos, shock_list(e), unit)
	if el.shock_why ~= why then
		el.shock_why = why
		obsidian.log("arcade: shock elite " .. (why and ("holds: " .. why) or "arcs: a Helldiver is near"))
	end
	el.shock_hits = targets and #targets or 0
	if not targets or #targets == 0 then return end
	local at = {}
	for _, t in ipairs(targets) do
		if t.player then
			if api.player.damage then pcall(api.player.damage, t.unit, M.shock_power(t), { through_armor = true, owner = unit }) end
		else
			pcall(api.enemies.damage, t.unit, M.shock_power(t), nil, { through_armor = true })
		end
		at[#at + 1] = t.pos
	end
	pcall(api.world.arc, M.arc_path(pos, at), { effect = "tesla" })
	M.record_arc(e.arcs, pos, at, now)
end

-- Host: the dome goes at once. The game's own deactivate has every machine take off the c_ actors
-- (shield_dome_component.lua:43), which ride_domes took off already.
local function drop_dome(el)
	if el.dome and unit_alive(el.dome) then
		local st = api.game.state()
		local spawner = type(st) == "table" and st.entity_spawner
		if spawner then pcall(spawner.despawn_entity, spawner, el.dome) end
	end
	el.dome = nil
end

-- The dome rides on the elite (ride_domes), so it's placed once. One the squad breaks comes back
-- DOME_BACK seconds later.
function M.dome_step(el, now, dome_alive)
	if el.dome then
		if dome_alive then return nil end
		el.dome, el.dome_lost = nil, now
	end
	if el.dome_lost and now - el.dome_lost < M.DOME_BACK then return nil end
	return "place"
end

local function bulwark(el, pos, now)
	if not M.dome_step(el, now, el.dome ~= nil and alive(el.dome)) then return end
	el.dome, el.dome_lost = spawn_entity(M.DOME_UNIT, pos), nil
	-- Enemies aim at a dome as they do at a player's: not at this one.
	if el.dome then command(el.dome, "enemy_target", "disable") end
end

local function flat_of(v)
	local V = g("Vector3")
	return { x = V.x(v), y = V.y(v) }
end

-- Every machine: what makes the dome a projected shield. Each machine makes the dome's actors at its
-- first update there (shield_dome_component.lua:50-58); then DOME_LOOSE go, and the dome rides on the
-- Bulwark elite it came up under, as a backpack rides on its wielder (equipment_component.lua:94).
local function ride_domes(e)
	local U, A, W = g("Unit"), g("Actor"), g("World")
	if not (api.game.slaves and U and A and W) then return end
	e.rides = e.rides or {}
	for dome in pairs(e.rides) do
		if not unit_alive(dome) then e.rides[dome] = nil end
	end
	local bulwarks
	for dome, ctx in pairs(api.game.slaves("shield_dome")) do
		local ride = e.rides[dome]
		local ready = type(ctx) == "table" and type(ctx.state) == "table" and ctx.state.initialized
		if ready and unit_alive(dome) then
			if not ride then
				ride = {}
				e.rides[dome] = ride
				for _, name in ipairs(M.DOME_LOOSE) do
					local ok, actor = pcall(U.actor, dome, name)
					if ok and actor then pcall(U.destroy_actor, dome, name) end
				end
			end
			local ok_s, shell = pcall(U.actor, dome, "g_shield")
			shell = ok_s and shell or nil
			if not ride.on then
				if not bulwarks then
					bulwarks = {}
					for unit, kind in pairs(e.kinds) do
						local p = kind == "bulwark" and alive(unit) and position(unit)
						if p then bulwarks[#bulwarks + 1] = { unit = unit, pos = p } end
					end
				end
				local at = position(dome)
				local near = at and M.nearest(at, bulwarks, M.DOME_RIDE, 1)[1]
				local st = api.game.state()
				local proxy = type(st) == "table" and st.world_proxy
				local ok_w, world = false, nil
				if proxy then ok_w, world = pcall(proxy.get_world, proxy) end
				if near and ok_w and world then
					-- Where the shell sits from the dome's middle, while both are where the game put them.
					local ok_p, sp = false, nil
					if shell then ok_p, sp = pcall(A.position, shell) end
					if ok_p and sp then
						local s = flat_of(sp)
						ride.offset = { x = s.x - at.x, y = s.y - at.y }
					end
					if pcall(W.link_unit, world, dome, 0, near.unit, 0) then
						pcall(U.set_local_position, dome, 0, g("Vector3")(0, 0, 0))
						pcall(U.set_local_rotation, dome, 0, g("Quaternion").identity())
						ride.on, ride.from = near.unit, at
						obsidian.log("arcade: bulwark dome rides on its elite (" .. (api.game.is_host() and "host" or "client")
							.. "), shell " .. (shell and "kept" or "missing"))
					end
				end
			elseif shell and ride.offset and alive(ride.on) then
				-- A shell that stays where it was made is made again where the dome is now.
				local at, ok_p, sp = position(dome), pcall(A.position, shell)
				if at and ok_p and sp then
					local s = flat_of(sp)
					local lag = (s.x - ride.offset.x - at.x) ^ 2 + (s.y - ride.offset.y - at.y) ^ 2
					if lag > M.DOME_LAG * M.DOME_LAG then
						pcall(U.destroy_actor, dome, "g_shield")
						pcall(U.create_actor, dome, "g_shield")
						if not ride.told then
							ride.told = true
							obsidian.log("arcade: bulwark dome: the shell stayed behind, made again as the elite walks")
						end
					elseif not ride.told and flat2(ride.from, at) > 1 then
						ride.told = true
						obsidian.log("arcade: bulwark dome: the shell walks with the elite")
					end
				end
			end
		end
	end
end

local function faster(el, unit, dt)
	local speed = M.FASTER[el.kind]
	if not speed then return end
	if el.kind == "swift" and not el.immune then
		el.immune = true
		for _, name in ipairs(M.SWIFT_IMMUNE) do command(unit, "status", "add_immunity_element", name) end
	end
	el.swift_in = (el.swift_in or 0) - dt
	if el.swift_in > 0 then return end
	el.swift_in = 0.5
	-- A slow sets the mover's multiplier below 1 and back to 1 when it ends: from 1, the elite's own.
	local ok, mover = pcall(g("EntityAux").state_master, unit, "navmesh_mover")
	local now = ok and type(mover) == "table" and mover.slow_multiplier or 1
	if now == 1 then pcall(g("EntityAux").queue_command_master_interface, unit, "movement", "set_slow", speed) end
end

-- Host, every frame of play: the schedule, and what each kind does.
local function host_update(e, run, dt, squad, factions, draw)
	local now = run.time
	local _, n = taken_kinds(e)
	if squad and run.alarm and not M.debug.paused and M.due(e, now, n, draw) then spawn_due(e, run, squad, factions, draw) end
	for unit, el in pairs(e.alive) do
		if not alive(unit) then
			drop_dome(el)
			e.alive[unit] = nil
		else
			local pos = position(unit)
			if pos then
				if el.kind == "fire" and M.fire_due(el.fire, pos, now) then spawn_entity(M.FIRE_UNIT, pos) end
				if el.kind == "shock" then
					el.shock_in = el.shock_in - dt
					if el.shock_in <= 0 then
						el.shock_in = M.SHOCK_EVERY
						shock(e, el, unit, pos, now)
					end
				end
				if el.kind == "bulwark" then bulwark(el, pos, now) end
				faster(el, unit, dt)
			end
		end
	end
	for _, p in ipairs(M.pools_due(e.pools, now)) do
		local unit = p.kind == "fire" and M.FIRE_UNIT or M.POOL_UNIT
		for _, spot in ipairs(M.pool_spots(p)) do spawn_entity(unit, spot) end
	end
end

-- Every machine: the poison look over each toxic ground, for as long as it lasts.
function M.new_cloud(pos, clock)
	return { x = pos.x, y = pos.y, z = pos.z or 0, until_at = clock + M.POOL_SECONDS, next = clock }
end

-- The spots due a puff at `clock`, and the clouds that are over go.
function M.clouds_due(clouds, clock)
	local out = {}
	for i = #clouds, 1, -1 do
		local c = clouds[i]
		if clock >= c.until_at then
			table.remove(clouds, i)
		elseif clock >= c.next then
			c.next = clock + M.CLOUD_EVERY
			c.turn = (c.turn or 0) + 1
			out[#out + 1] = { x = c.x, y = c.y, z = c.z }
			for k = 1, M.CLOUD_SPOTS do
				local a = (k + c.turn * 0.5) / M.CLOUD_SPOTS * 2 * math.pi
				local r = M.CLOUD_RADIUS * (k % 2 == 0 and 1 or 0.55)
				out[#out + 1] = { x = c.x + math.cos(a) * r, y = c.y + math.sin(a) * r, z = c.z }
			end
		end
	end
	return out
end

local function puff(spots)
	if #spots == 0 or not api.game.in_mission() then return end
	local st = api.game.state()
	local proxy = type(st) == "table" and st.world_proxy
	if not proxy then return end
	local ok, world = pcall(proxy.get_world, proxy)
	if not (ok and world) then return end
	local W, V = g("World"), g("Vector3")
	for _, s in ipairs(spots) do pcall(W.create_particles, world, M.CLOUD_EFFECT, V(s.x, s.y, s.z)) end
end

-- Better HUD keeps an elite's health bar showing while it lives, with its kind's icon in the middle of
-- it. kind nil clears the mark.
local function mark(unit, kind)
	local hud = obsidian.import("alomare.betterhud")
	if type(hud) ~= "table" or type(hud.elite_mark) ~= "function" then return end
	local icon = nil
	if kind then
		icon = art.image(M.LOOK[kind].icon)
		if not icon then return end
	end
	pcall(hud.elite_mark, unit, icon)
end

-- Every machine: the host's elites bound to units here, and the looks put on and taken off.
local function looks(e)
	for unit, handle in pairs(e.looks) do
		if not alive(unit) or not e.kinds[unit] then
			if handle ~= true then pcall(api.world.detach_effect, handle) end
			mark(unit, nil)
			e.looks[unit] = nil
		end
	end
	for unit, kind in pairs(e.kinds) do
		if not e.looks[unit] and alive(unit) then
			local effect = M.LOOK[kind].effect
			local ok, handle = false, nil
			if effect then ok, handle = pcall(api.world.attach_effect, unit, effect) end
			e.looks[unit] = ok and type(handle) == "number" and handle or true
			mark(unit, kind)
		end
	end
end

local function candidates()
	local out = {}
	for _, unit in ipairs(api.enemies.list()) do
		if M.faction_of(path_of(unit)) then
			local p = position(unit)
			if p then out[#out + 1] = { unit = unit, pos = p } end
		end
	end
	return out
end

local function share(e, run, host, dt)
	e.share_in = e.share_in - dt
	if e.share_in > 0 then return end
	e.share_in = M.SHARE_EVERY
	local mission = run.sync.mission
	if host then
		local list = {}
		for unit, el in pairs(e.alive) do
			local p = alive(unit) and position(unit)
			if p then list[#list + 1] = { kind = el.kind, x = p.x, y = p.y } end
		end
		pcall(api.lobby.share, "elites", #list > 0 and M.encode(mission, list) or nil)
		pcall(api.lobby.share, "elite_arcs", M.encode_arcs(e.arcs, mission))
		return
	end
	pcall(api.lobby.share, "elites", nil)
	pcall(api.lobby.share, "elite_arcs", nil)
	local shared = {}
	for _, text in pairs(api.lobby.shared("elites")) do
		local d = M.decode(text)
		if d and d.mission == tostring(mission) then
			for _, s in ipairs(d.list) do shared[#shared + 1] = s end
		end
	end
	if #shared > 0 then M.match(shared, candidates(), e.kinds) end
	for peer, text in pairs(api.lobby.shared("elite_arcs")) do
		for _, ev in ipairs(M.take_arcs(e.seen_arcs, peer, M.decode_arcs(text), mission, run.time)) do
			pcall(api.world.arc, M.arc_path(ev.from, ev.to), { effect = "tesla" })
		end
	end
end

-- Every frame of play, on every machine. factions: the factions in play now. draw(): 0 to 1.
function M.update(run, dt, dt_real, squad, factions, draw)
	local e = M.state
	e.now = run.time
	e.clock = e.clock + (dt_real or 0)
	local host = api.game.is_host()
	if host then note_bodies(e) end
	if host and not run.choice then host_update(e, run, dt, squad, factions, draw) end
	share(e, run, host, dt_real)
	e.clouds = e.clouds or {}
	puff(M.clouds_due(e.clouds, e.clock))
	looks(e)
	ride_domes(e)
end

-- An enemy died, on every machine. pos: where. Answers the elite's kind when it was one.
function M.on_killed(unit, pos, faction)
	local e = M.state
	local kind = e.kinds[unit]
	if not kind then return nil end
	e.kinds[unit] = nil
	local el = e.alive[unit]
	if el and api.game.is_host() then
		e.alive[unit] = nil
		e.last_death = e.now or 0
		drop_dome(el)
		if kind == "noxious" or kind == "fire" then e.pools[#e.pools + 1] = M.new_pool(pos, e.now or 0, kind) end
		if kind == "brood" then
			local small = M.SMALL[el.faction or faction]
			if small then
				local ok, why = api.enemies.spawn(small, M.BROOD_COUNT, vec(pos))
				if not ok then obsidian.log("arcade: no brood: " .. tostring(why)) end
			end
		end
	end
	if kind == "noxious" and pos then
		e.clouds = e.clouds or {}
		e.clouds[#e.clouds + 1] = M.new_cloud(pos, e.clock or 0)
	end
	obsidian.log("arcade: a " .. kind .. " elite fell")
	return kind
end

-- A player of this machine took a hit (on_damage_taken, on the machine that plays the body): a
-- Noxious elite's hit poisons.
function M.on_player_hit(unit, info)
	local from = type(info) == "table" and (info.owner_unit or info.attacker_unit)
	if not from or M.state.kinds[from] ~= "noxious" then return end
	if (tonumber(info.damage) or 0) <= 0 then return end
	pcall(g("EntityAux").queue_command_interface, unit, "damageable", "do_damage",
		{ power = 0, angle_hit = 0, angle_incidence = 0, owner_unit = from, attacker_unit = from, hit_status_effects = M.POISON })
end

-- The run is over: what this machine shares and shows goes.
function M.clear()
	local e = M.state
	for _, el in pairs(e.alive) do pcall(drop_dome, el) end
	for unit, handle in pairs(e.looks) do
		if handle ~= true then pcall(api.world.detach_effect, handle) end
		mark(unit, nil)
	end
	pcall(api.lobby.share, "elites", nil)
	pcall(api.lobby.share, "elite_arcs", nil)
	M.state = M.new()
	-- A pause from the debug page holds for one run only, so a real run never starts without elites.
	M.debug.paused = false
end

-- The debug page (src/debug.lua) ----------------------------------------------------------------------

-- The faction of the debug page's base: the mission's own for "home".
function M.debug_faction(base)
	if base ~= "home" and M.UNITS[base] then return base end
	local level = obsidian.module("src/level")
	return level.home or "bugs"
end

-- M.debug.count elites of `kind` ("random" for one none of the others has) round this machine's first
-- player, M.debug.distance metres off, on M.debug.base. Answers true and how many, or false and why.
function M.debug_spawn(run, kind)
	if not run then return false, "no_run" end
	if not api.game.is_host() then return false, "host_only" end
	local l = run.local_list[1]
	if not (l and l.pos) then return false, "no_squad" end
	local faction = M.debug_faction(M.debug.base)
	local done, why = 0, nil
	local taken = taken_kinds(M.state)
	for _, at in ipairs(M.ring_spots(l.pos, M.debug.count, M.debug.distance)) do
		local k = kind
		if k == "random" then
			k = M.pick_kind(taken, math.random)
			taken[k] = true
		end
		local ok, err = M.spawn(k, faction, at)
		if ok then done = done + 1 else why = why or err end
	end
	if done == 0 then return false, why end
	return true, done
end

-- The elites the host runs now, alive: { unit, el } in no set order.
local function living(e)
	local out = {}
	for unit, el in pairs(e.alive) do
		if alive(unit) then out[#out + 1] = { unit = unit, el = el } end
	end
	return out
end

-- The run's own schedule brings its next elite now: the waits between elites go, the rest stays (none
-- before FROM minutes, no more than MOST alive).
function M.debug_next(run)
	if not run then return false, "no_run" end
	if not api.game.is_host() then return false, "host_only" end
	local e = M.state
	if run.time < M.FROM * 60 then return false, "too_early" end
	if #living(e) >= M.most(run.time / 60) then return false, "at_most" end
	if M.debug.paused then return false, "paused" end
	e.next_at, e.last_death = run.time, -math.huge
	return true
end

-- Every elite alive goes. kill: true to kill them, which runs what their kinds do at death (the Brood's
-- split, the Noxious ground) and gives the kill; false to take them away with none of that.
function M.debug_clear(run, kill)
	if not run then return false, "no_run" end
	if not api.game.is_host() then return false, "host_only" end
	local e = M.state
	local list = living(e)
	if #list == 0 then return false, "no_elite" end
	for _, it in ipairs(list) do
		if kill then
			pcall(api.enemies.kill, it.unit)
		else
			drop_dome(it.el)
			e.alive[it.unit], e.kinds[it.unit] = nil, nil
			pcall(api.enemies.despawn, it.unit)
		end
	end
	return true, #list
end

-- Host: the Bulwark elites' domes go, as when the squad breaks one: each comes back DOME_BACK seconds on.
function M.debug_break_domes(run)
	if not run then return false, "no_run" end
	if not api.game.is_host() then return false, "host_only" end
	local e, found, broke = M.state, false, 0
	for _, it in ipairs(living(e)) do
		if it.el.kind == "bulwark" then
			found = true
			if it.el.dome then
				drop_dome(it.el)
				it.el.dome_lost = e.now or 0
				broke = broke + 1
			end
		end
	end
	if not found then return false, "no_bulwark" end
	if broke == 0 then return false, "no_dome" end
	return true, broke
end

-- A line for the debug page on the elites the host runs. now: the run's clock.
function M.summary(e, now)
	local kinds, shock, dome = {}, nil, nil
	for _, el in pairs(e.alive) do
		kinds[#kinds + 1] = el.kind:sub(1, 1):upper() .. el.kind:sub(2)
		if el.kind == "shock" and not shock then
			shock = el.shock_why == "landing" and "Shock holds: the Helldiver in range is still landing"
				or el.shock_why == "no_helldiver" and ("Shock holds: no Helldiver within " .. M.SHOCK_RANGE .. " m")
				or el.shock_hits and ("Shock arcs at " .. el.shock_hits) or "Shock waits"
		end
		if el.kind == "bulwark" and not dome then
			if el.dome then dome = "dome up"
			elseif el.dome_lost then dome = "dome back in " .. math.max(0, math.ceil(el.dome_lost + M.DOME_BACK - (now or 0))) .. " s"
			else dome = "dome coming" end
		end
	end
	if #kinds == 0 then return "No elites alive." end
	table.sort(kinds)
	local parts = { "Alive: " .. table.concat(kinds, ", ") }
	if shock then parts[#parts + 1] = shock end
	if dome then parts[#parts + 1] = "Bulwark " .. dome end
	return table.concat(parts, ". ") .. "."
end

return M
