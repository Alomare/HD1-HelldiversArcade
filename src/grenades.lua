-- Grenade upgrades.
--
-- Cluster Grenade: a hand grenade's explosion is followed by more of the same, one per stack, around
-- it. Every machine runs a grenade's explosion (ExplosiveComponent.update_slaves calls
-- ExplosionManager.do_explosion), and the game counts a hit on the machine whose player owns it, so the
-- thrower's machine sets off the extra blasts with the grenade's own explosion. The other machines draw
-- the same blasts from lobby data with no power, for the look and the sound.
--
-- Deep Pockets: more grenades carried than the game's 2, and one back every few seconds. The count is
-- a protected field the game clamps to 2 in its own commands, so it's written through the API, and a
-- resupply, which sets it to 2, fills it to the upgrade's maximum instead. Better HUD draws the count
-- and the time to the next grenade.
local upgrades = obsidian.module("src/upgrades")
local summary = obsidian.module("src/summary")

local api = obsidian.import("obsidian.api")

local M = {}

-- The game carries 2 grenades; the count travels as 4 bits.
M.BASE = 2
M.MOST = 15
-- How many of this machine's last clusters the lobby data carries, and how long one is worth drawing.
M.KEPT = 3
M.FRESH = 1.5

local function g(name) return rawget(_G, name) end

-- The thrown grenades: equipment/equipment_grenade_01, _incendiary, _stun, _smoke and the impact ones.
function M.is_grenade(path)
	return type(path) == "string" and path:find("^equipment/equipment_.*grenade") ~= nil
end

-- A unit's path, as LuaSettingsManager knows it: the unit's "settings_path" data (the key the game
-- reads in get_settings_by_unit), or "unit_path" where a unit has that.
-- Unit.get_data on a destroyed unit takes the game down in the engine, past any pcall (helldivers.exe +0x13b8e0, the lookup behind every get_data), so a unit is asked only while Unit.alive says it's there.
-- The unit an explosion names can be gone already: the precision strike's shells are units of the world
-- whose own flow sets the explosion off.
function M.path_of(unit)
	local U = g("Unit")
	local ok_alive, alive = pcall(U.alive, unit)
	if not (ok_alive and alive) then return nil end
	for _, key in ipairs({ "settings_path", "unit_path" }) do
		local ok, path = pcall(U.get_data, unit, key)
		if ok and type(path) == "string" then return path end
	end
	return nil
end

-- Where the extra blasts go: `count` spots spread round `pos`, between half and all of `radius` away,
-- and the delay before each. draw(): a number from 0 to 1.
function M.cluster_spots(pos, count, radius, delay, draw)
	local out = {}
	local turn = draw() * 2 * math.pi
	for i = 1, count do
		local angle = turn + (i - 1) * 2 * math.pi / count + (draw() - 0.5) * 0.6
		local r = radius * (0.5 + 0.5 * draw())
		out[i] = { x = pos.x + math.cos(angle) * r, y = pos.y + math.sin(angle) * r, z = pos.z or 0, delay = delay * i }
	end
	return out
end

-- Carpet Bombing: after each of `spots`, `ring` smaller blasts round it, up to `radius` away, `delay`
-- after it and after each other. The spots marked small. Answers the cluster's spots and the rings'.
function M.with_rings(spots, ring, radius, delay, draw)
	local out = {}
	for _, s in ipairs(spots) do
		out[#out + 1] = s
		for _, r in ipairs(M.cluster_spots(s, ring, radius, delay, draw)) do
			r.delay = s.delay + r.delay
			r.small = true
			out[#out + 1] = r
		end
	end
	return out
end

-- A copy of an explosion's settings at `share` of its power and its reach.
function M.smaller(info, share)
	local out = {}
	for k, v in pairs(info) do out[k] = v end
	for _, k in ipairs({ "center_power", "blast_power", "force", "center_radius", "blast_radius" }) do
		if type(out[k]) == "number" then out[k] = out[k] * share end
	end
	-- A fire or smoke grenade's area comes with the cluster's own blasts, not again with each ring's.
	out.on_explode_unit_path = nil
	return out
end

function M.new() return { queue = {}, seq = 0, events = {}, seen = {}, busy = false, original = nil, manager = nil } end

-- The extra blasts due by now: each spot fires once its delay has run out. fire(spot) does the blast.
function M.step(side, dt, fire)
	for i = #side.queue, 1, -1 do
		local q = side.queue[i]
		q.delay = q.delay - dt
		if q.delay <= 0 then
			table.remove(side.queue, i)
			fire(q)
		end
	end
end

local function boxed(p)
	return api.game.box(g("Vector3")(p.x, p.y, p.z))
end

-- A copy of an explosion's settings with no power, push or status: for another machine's blasts.
function M.harmless(info)
	local out = {}
	for k, v in pairs(info) do out[k] = v end
	out.center_power, out.blast_power, out.force, out.hit_status_effects = 0, 0, 0, nil
	return out
end

local function blast(side, spot)
	if not (side.original and side.manager) then return end
	side.busy = true
	-- Its hits are Cluster Grenade's in the run's summary (src/summary.lua).
	local ok, err = pcall(summary.marking, spot.small and "carpet_bombing" or "cluster_grenade", spot.owner, function()
		return side.original(side.manager, nil, boxed(spot), spot.info, spot.owner, spot.owner)
	end)
	side.busy = false
	if not ok then obsidian.log("arcade: cluster blast: " .. tostring(err)) end
end

function M.update(side, dt)
	M.step(side, dt, function(spot) blast(side, spot) end)
end

-- stats_of(unit): the stats of this machine's player whose body that is. now(): the run's clock.
-- draw(): a number from 0 to 1. active(): whether a run is on.
function M.install(side_of, stats_of, now, draw)
	obsidian.hook("ExplosionManager", "do_explosion", function(original, self, unit, pos, info, attacker, owner, ...)
		local side = side_of()
		-- A grenade of this machine's player: its hits are the grenade's in the run's summary.
		local mine = side and not side.busy and owner ~= nil and M.is_grenade(M.path_of(unit)) and stats_of(owner) ~= nil
		local r
		if mine then
			local args = { ... }
			local n = select("#", ...)
			r = { summary.marking("grenade", owner, function() return original(self, unit, pos, info, attacker, owner, unpack(args, 1, n)) end) }
		else
			r = { original(self, unit, pos, info, attacker, owner, ...) }
		end
		if not side or side.busy or type(info) ~= "table" then return unpack(r) end
		side.original, side.manager = original, self
		local path = M.path_of(unit)
		if not M.is_grenade(path) then return unpack(r) end
		local stats = owner and stats_of(owner)
		local count = stats and stats.cluster or 0
		if count <= 0 then return unpack(r) end
		local at = api.game.unbox(pos)
		local spots = M.cluster_spots(at, count, upgrades.CLUSTER_RADIUS, upgrades.CLUSTER_DELAY, draw)
		if (stats.carpet or 0) > 0 then spots = M.with_rings(spots, stats.carpet, upgrades.CARPET_RADIUS, upgrades.CARPET_DELAY, draw) end
		local small = M.smaller(info, upgrades.CARPET_SIZE)
		for _, s in ipairs(spots) do
			s.info, s.owner = s.small and small or info, owner
			side.queue[#side.queue + 1] = s
		end
		M.record(side, path, spots, now())
		if not side.told then
			side.told = true
			obsidian.log(string.format("arcade: cluster: %d blasts queued round %.1f, %.1f", count, at.x, at.y))
		end
		return unpack(r)
	end)
end

function M.record(side, path, spots, now)
	side.seq = side.seq + 1
	side.events[#side.events + 1] = { seq = side.seq, time = now, path = path, spots = spots }
	while #side.events > M.KEPT do table.remove(side.events, 1) end
end

local function num(x) return string.format("%.1f", x) end

-- The lobby text: the mission, then each kept cluster as number@time@grenade@x,y,z,delay|...
function M.encode(side, mission)
	if #side.events == 0 then return nil end
	local parts = { tostring(mission) }
	for _, e in ipairs(side.events) do
		local spots = {}
		-- A Carpet Bombing ring's blast ends in ",s".
		for i, s in ipairs(e.spots) do spots[i] = num(s.x) .. "," .. num(s.y) .. "," .. num(s.z) .. "," .. string.format("%.2f", s.delay) .. (s.small and ",s" or "") end
		parts[#parts + 1] = e.seq .. "@" .. num(e.time) .. "@" .. e.path .. "@" .. table.concat(spots, "|")
	end
	return table.concat(parts, ";")
end

function M.decode(text)
	if type(text) ~= "string" then return nil end
	local parts = {}
	for part in (text .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = part end
	if #parts < 1 or parts[1] == "" then return nil end
	local out = { mission = parts[1], events = {} }
	for i = 2, #parts do
		local seq, time, path, spots = parts[i]:match("^(%d+)@(-?[%d.]+)@([^@]+)@(.*)$")
		if seq then
			local list = {}
			for piece in spots:gmatch("[^|]+") do
				local x, y, z, d, s = piece:match("^(-?[%d.]+),(-?[%d.]+),(-?[%d.]+),(-?[%d.]+)(,?s?)$")
				if x then list[#list + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z), delay = tonumber(d), small = s == ",s" or nil } end
			end
			out.events[#out.events + 1] = { seq = tonumber(seq), time = tonumber(time), path = path, spots = list }
		end
	end
	return out
end

-- Another machine's clusters not drawn yet, fresh and from this mission. The first text seen from a
-- machine only sets where to start.
function M.take(side, peer, e, mission, now)
	if not e or e.mission ~= tostring(mission) then return {} end
	local seen, out, top = side.seen[peer], {}, side.seen[peer] or 0
	for _, ev in ipairs(e.events) do
		if seen and ev.seq > seen and math.abs(now - ev.time) <= M.FRESH then out[#out + 1] = ev end
		top = math.max(top, ev.seq)
	end
	side.seen[peer] = top
	return out
end

-- Queues another machine's cluster here, without power.
function M.show_remote(side, ev)
	local lsm = g("LuaSettingsManager")
	local ok, settings = pcall(lsm.get_settings_by_settings_path, lsm, ev.path)
	if not (ok and type(settings) == "table") then ok, settings = pcall(lsm.get_settings_by_unit_path, lsm, ev.path) end
	local info = ok and type(settings) == "table" and settings.explosive_info
	if type(info) ~= "table" then return false end
	local harmless = M.harmless(info)
	local small = M.smaller(harmless, upgrades.CARPET_SIZE)
	for _, s in ipairs(ev.spots) do
		side.queue[#side.queue + 1] = { x = s.x, y = s.y, z = s.z, delay = s.delay, info = s.small and small or harmless, owner = nil }
	end
	return true
end

-- Deep Pockets: the most grenades a player with `stacks` carries.
function M.most(stacks)
	return math.min(M.MOST, M.BASE + stacks)
end

-- One of this machine's players each frame while alive, with `stacks` of Deep Pockets: a grenade back
-- each time the timer fills, while there's room. b: the player's { timer }. The share of the next
-- grenade made so far, or nil when full (or without the upgrade).
function M.pockets(b, stacks, unit, dt)
	if stacks <= 0 then b.timer = 0 return nil end
	local inv = api.game.master(unit, "inventory")
	local have = inv and tonumber(inv.num_grenades)
	if not have then return nil end
	local most = M.most(stacks)
	if have >= most then b.timer = 0 return nil end
	local every = upgrades.pockets_seconds(stacks)
	b.timer = (b.timer or 0) + dt
	if b.timer >= every then
		b.timer = 0
		api.game.protected("inventory", inv, "num_grenades", have + 1)
		if have + 1 >= most then return nil end
	end
	return b.timer / every
end

-- A resupply sets the count to the game's 2: a Deep Pockets player gets the upgrade's maximum.
function M.install_resupply(stats_of)
	obsidian.hook("InventoryComponent", "ammo_pickup", function(original, self, unit, ctx, ...)
		local r = { original(self, unit, ctx, ...) }
		local stats = stats_of(unit)
		local state = type(ctx) == "table" and ctx.state
		if stats and stats.pockets > 0 and type(state) == "table" then
			api.game.protected("inventory", state, "num_grenades", M.most(stats.pockets))
		end
		return unpack(r)
	end)
end

return M
