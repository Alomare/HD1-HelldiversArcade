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
--   fire     leaves the flamethrower's burning ground behind it as it moves
--   shock    arcs every SHOCK_EVERY seconds to the nearest units within SHOCK_RANGE, players and enemies
--   noxious  its hits poison like a Stalker's, and on death it leaves toxic ground for POOL_SECONDS
--   bulwark  carries a projected shield (the backpack's dome) over itself and those near it
--   swift    moves SWIFT_SPEED times as fast and doesn't stagger from hits
--   brood    splits into BROOD_COUNT small enemies of its faction on death
local spots = obsidian.module("src/spots")
local native = obsidian.module("src/native")
local art = obsidian.module("src/art")

local api = obsidian.import("obsidian.api")

local M = {}

local function g(name) return rawget(_G, name) end

M.KINDS = { "fire", "shock", "noxious", "bulwark", "swift", "brood" }
-- Each kind's color, the effect on the body (Obsidian API's world.attach_effect, 1.33.1 for all but
-- the shock) and the name over it.
M.LOOK = {
	fire = { color = "#ff6a1a", effect = "fire", name = "FIRE ELITE" },
	shock = { color = "#49c8ff", effect = "enemy_shock", name = "SHOCK ELITE" },
	noxious = { color = "#8ee03c", effect = "poison", name = "NOXIOUS ELITE" },
	bulwark = { color = "#f2d36b", effect = nil, name = "BULWARK ELITE" },
	swift = { color = "#f4f4f4", effect = nil, name = "SWIFT ELITE" },
	brood = { color = "#c45ad8", effect = "confuse", name = "BROOD ELITE" },
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
-- A Tesla Tower bolt is 1200 through armor: the elite's arcs are 5% of it on enemies and 1.25% on players.
M.SHOCK_ENEMY_POWER = 60
M.SHOCK_PLAYER_POWER = 15
M.POISON = { "poison_slow", "poison_damage" } -- the Stalker's hit
M.POOL_UNIT = "gameobjects/gameobject_toxic_area" -- the toxic impact grenade's ground, 10 seconds, in mission_common
M.POOL_SECONDS = 30
M.POOL_EVERY = 10 -- the ground is laid again as each one runs out
M.DOME_UNIT = "equipment/equipment_shield_generator_shield_01" -- the projected shield, 2.8 m, in mission_common
M.DOME_MOVE = 2.5 -- metres the elite walks out of the middle before the dome follows
M.DOME_EVERY = 3 -- seconds between moves at the most
M.DOME_BACK = 8 -- seconds before a broken dome comes back
M.SWIFT_SPEED = 1.6
M.SWIFT_IMMUNE = { "generic_stun", "knockdown" } -- bullet_stun is the stagger of every hit
M.BROOD_COUNT = 3

M.SHARE_EVERY = 0.5 -- seconds between the host's shares of where the elites are
M.MATCH = 4 -- metres between a shared elite and the unit bound to it
M.ARCS_KEPT = 2
M.ARCS_FRESH = 1.5

-- The state of a run: the host's elites by unit, the kind of every elite this machine knows, the
-- host's schedule, the pools still to lay, and the arcs.
function M.new()
	return { next_at = nil, alive = {}, kinds = setmetatable({}, { __mode = "k" }), looks = {}, pools = {},
		arcs = { seq = 0, events = {} }, seen_arcs = {}, share_in = 0, shared = {}, last_death = -math.huge }
end

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
function M.new_pool(pos, now)
	return { x = pos.x, y = pos.y, z = pos.z or 0, next = now, left = math.ceil(M.POOL_SECONDS / M.POOL_EVERY) }
end

function M.pools_due(pools, now)
	local out = {}
	for i = #pools, 1, -1 do
		local p = pools[i]
		if now >= p.next then
			out[#out + 1] = p
			p.left, p.next = p.left - 1, now + M.POOL_EVERY
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

-- Units the shock reaches: every player's body and every enemy, with where they stand.
local function shock_list()
	local list = {}
	for _, a in ipairs(api.game.all_avatars()) do
		local p = position(a.unit)
		if p then list[#list + 1] = { unit = a.unit, pos = p, player = true } end
	end
	for _, unit in ipairs(api.enemies.list()) do
		local p = position(unit)
		if p then list[#list + 1] = { unit = unit, pos = p } end
	end
	return list
end

local function shock(e, unit, pos, now)
	local targets = M.nearest(pos, shock_list(), M.SHOCK_RANGE, M.SHOCK_TARGETS, unit)
	if #targets == 0 then return end
	local at = {}
	for _, t in ipairs(targets) do
		if t.player then
			if api.player.damage then pcall(api.player.damage, t.unit, M.SHOCK_PLAYER_POWER, { through_armor = true, owner = unit }) end
		else
			pcall(api.enemies.damage, t.unit, M.SHOCK_ENEMY_POWER, nil, { through_armor = true })
		end
		at[#at + 1] = t.pos
	end
	pcall(api.world.arc, M.arc_path(pos, at), { effect = "tesla" })
	M.record_arc(e.arcs, pos, at, now)
end

local function unit_alive(unit)
	local ok, yes = pcall(g("Unit").alive, unit)
	return ok and yes == true
end

local function drop_dome(el)
	if el.dome and unit_alive(el.dome) then command(el.dome, "shield_dome", "deactivate") end
	el.dome = nil
end

-- The dome follows the elite: a new one where it stands once it walks out of the middle, the old one
-- switched off. One the squad breaks comes back DOME_BACK seconds later.
function M.dome_step(el, pos, now, dome_alive)
	if el.dome then
		if dome_alive then
			if flat2(el.dome_pos, pos) < M.DOME_MOVE * M.DOME_MOVE or now - el.dome_at < M.DOME_EVERY then return nil end
			return "move"
		end
		el.dome, el.dome_lost = nil, now
	end
	if el.dome_lost and now - el.dome_lost < M.DOME_BACK then return nil end
	return "place"
end

local function bulwark(el, pos, now)
	local step = M.dome_step(el, pos, now, el.dome and unit_alive(el.dome))
	if not step then return end
	if step == "move" then drop_dome(el) end
	el.dome = spawn_entity(M.DOME_UNIT, pos)
	el.dome_pos, el.dome_at, el.dome_lost = { x = pos.x, y = pos.y }, now, nil
	-- Enemies aim at a dome as they do at a player's: not at this one.
	if el.dome then command(el.dome, "enemy_target", "disable") end
end

local function swift(el, unit, dt)
	if not el.immune then
		el.immune = true
		for _, name in ipairs(M.SWIFT_IMMUNE) do command(unit, "status", "add_immunity_element", name) end
	end
	el.swift_in = el.swift_in - dt
	if el.swift_in > 0 then return end
	el.swift_in = 0.5
	-- A slow sets the mover's multiplier below 1 and back to 1 when it ends: from 1, the elite's own.
	local ok, mover = pcall(g("EntityAux").state_master, unit, "navmesh_mover")
	local now = ok and type(mover) == "table" and mover.slow_multiplier or 1
	if now == 1 then pcall(g("EntityAux").queue_command_master_interface, unit, "movement", "set_slow", M.SWIFT_SPEED) end
end

-- Host, every frame of play: the schedule, and what each kind does.
local function host_update(e, run, dt, squad, factions, draw)
	local now = run.time
	local _, n = taken_kinds(e)
	if squad and run.alarm and M.due(e, now, n, draw) then spawn_due(e, run, squad, factions, draw) end
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
						shock(e, unit, pos, now)
					end
				end
				if el.kind == "bulwark" then bulwark(el, pos, now) end
				if el.kind == "swift" then swift(el, unit, dt) end
			end
		end
	end
	for _, p in ipairs(M.pools_due(e.pools, now)) do spawn_entity(M.POOL_UNIT, p) end
end

-- Every machine: the host's elites bound to units here, and the looks put on and taken off.
local function looks(e)
	for unit, handle in pairs(e.looks) do
		if not alive(unit) or not e.kinds[unit] then
			if handle ~= true then pcall(api.world.detach_effect, handle) end
			e.looks[unit] = nil
		end
	end
	for unit, kind in pairs(e.kinds) do
		if not e.looks[unit] and alive(unit) then
			local effect = M.LOOK[kind].effect
			local ok, handle = false, nil
			if effect then ok, handle = pcall(api.world.attach_effect, unit, effect) end
			e.looks[unit] = ok and type(handle) == "number" and handle or true
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
	local host = api.game.is_host()
	if host and not run.choice then host_update(e, run, dt, squad, factions, draw) end
	share(e, run, host, dt_real)
	looks(e)
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
		if kind == "noxious" then e.pools[#e.pools + 1] = M.new_pool(pos, e.now or 0) end
		if kind == "brood" then
			local small = M.SMALL[el.faction or faction]
			if small then
				local ok, why = api.enemies.spawn(small, M.BROOD_COUNT, vec(pos))
				if not ok then obsidian.log("arcade: no brood: " .. tostring(why)) end
			end
		end
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

-- Pixels from the camera, into the kit's 1920x1080 design space, centred as obsidian.ui.frame puts it.
local function on_screen(p)
	local px, py, on = api.world.to_screen(p)
	if not on then return nil end
	local w, h = g("Application").resolution()
	local s = math.min(w / 1920, h / 1080)
	return (px - (w - 1920 * s) / 2) / s, (py - (h - 1080 * s) / 2) / s
end

-- A glow in the kind's color under each elite in view, and its name over it.
function M.draw(kit)
	for unit, kind in pairs(M.state.kinds) do
		local p = alive(unit) and position(unit)
		local look = M.LOOK[kind]
		if p and look then
			local x, y = on_screen(p)
			if x then
				art.center(kit, "glow", x, y, 190, look.color .. "70")
				local tx, ty = on_screen({ x = p.x, y = p.y, z = p.z + 3.2 })
				if tx then native.text(kit, look.name, tx, ty, { font = "heading", size = 20, tracking = 1, align = "center", color = look.color }) end
			end
		end
	end
end

-- The run is over: what this machine shares and draws goes.
function M.clear()
	local e = M.state
	for _, el in pairs(e.alive) do pcall(drop_dome, el) end
	for _, handle in pairs(e.looks) do
		if handle ~= true then pcall(api.world.detach_effect, handle) end
	end
	pcall(api.lobby.share, "elites", nil)
	pcall(api.lobby.share, "elite_arcs", nil)
	M.state = M.new()
end

-- The debug page: an elite of `kind` near this machine's first player, of the mission's own faction.
function M.debug_spawn(run, kind)
	if not run then return false, "no_run" end
	if not api.game.is_host() then return false, "host_only" end
	local l = run.local_list[1]
	if not (l and l.pos) then return false, "no_squad" end
	local level = obsidian.module("src/level")
	local faction = level.home or "bugs"
	return M.spawn(kind, faction, { x = l.pos.x + 8, y = l.pos.y, z = l.pos.z })
end

return M
