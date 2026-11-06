-- Kinetic Battery: moving fills a charge, by flat distance since the last discharge, crawling while
-- downed included. A full charge arcs from the player to the nearest enemy and on from enemy to enemy,
-- hurting only enemies (api.enemies.damage takes nothing else), downed or not. From three quarters of a
-- charge, the player's body crackles like a shocked Helldiver's. The player's own machine picks the
-- targets and sends the damage; the bolts and the
-- crackle go to the other machines through lobby data (encode/decode), and each one draws them there.
local upgrades = obsidian.module("src/upgrades")
local summary = obsidian.module("src/summary")

local api = obsidian.import("obsidian.api")

local M = {}

-- Charge shows on the body from this share of a full one.
M.GLOW_AT = 0.75
-- Bolts run this far above the ground, through the bodies rather than their feet.
M.HEIGHT = 1
-- A step longer than this in one frame is a respawn or a warp, not a walk, and charges nothing.
M.LONGEST_STEP = 3
-- How many of this machine's last discharges the lobby data carries, and for how long a remote one is
-- still worth drawing.
M.KEPT = 3
M.FRESH = 1.5
-- How near a shared crackle has to be to another machine's player to go on that body.
M.GLOW_MATCH = 3

function M.new_player() return { charge = 0, last = nil, glow = nil, glow_unit = nil } end

-- The machine's side: what it shares, and what it has drawn of the others'.
function M.new() return { seq = 0, events = {}, seen = {}, remote_glows = {} } end

-- The charge after a step from `from` to `to`, toward a full one every `full` metres.
function M.charged(charge, from, to, full)
	if not (from and to and full and full > 0) then return charge end
	local step = math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
	if step > M.LONGEST_STEP then return charge end
	-- Many small steps add up to a hair under the whole: that counts as the whole.
	local c = charge + step / full
	return c >= 1 - 1e-6 and 1 or c
end

-- Dynamo: `metres` more of charge, as if moved, toward a full one every `full` metres.
function M.boosted(charge, metres, full)
	if not (metres and metres > 0 and full and full > 0) then return charge end
	local c = charge + metres / full
	return c >= 1 - 1e-6 and 1 or c
end

local function at_height(p)
	return { x = p.x, y = p.y, z = (p.z or 0) + M.HEIGHT }
end

-- The path a discharge draws: from the player through each enemy hit, at body height.
function M.path(from, targets_at)
	local path = { at_height(from) }
	for _, p in ipairs(targets_at) do path[#path + 1] = at_height(p) end
	return path
end

local function crackle(b, unit, want)
	if b.glow and (not want or b.glow_unit ~= unit) then
		pcall(api.world.detach_effect, b.glow)
		b.glow, b.glow_unit = nil, nil
	end
	if want and not b.glow and unit then
		local ok, handle = pcall(api.world.attach_effect, unit, "shock")
		if ok and type(handle) == "number" then b.glow, b.glow_unit = handle, unit end
	end
end

-- One of this machine's players, each frame while alive. stacks: the upgrade's. pos: where the body
-- stands. side: M.new()'s table, for the discharge to be shared. now: the run's clock. opts, from the
-- evolutions (src/upgrades.lua): metres (Dynamo: the metres of moving that this frame's firing counts as).
function M.sync(b, stacks, unit, pos, side, now, opts)
	opts = opts or {}
	if stacks <= 0 or not unit or not pos then
		crackle(b, unit, false)
		b.last = pos
		return nil
	end
	b.charge = M.charged(b.charge, b.last, pos, upgrades.battery_metres(stacks))
	b.charge = M.boosted(b.charge, opts.metres, upgrades.battery_metres(stacks))
	b.last = pos
	local fired = nil
	if b.charge >= 1 then
		local targets = api.enemies.chain(pos, upgrades.battery_chains(stacks), upgrades.BATTERY_FIRST, upgrades.BATTERY_JUMP)
		if #targets > 0 then
			local at = {}
			for _, enemy in ipairs(targets) do
				summary.mark_hit(enemy, "kinetic_battery", unit)
				api.enemies.damage(enemy, upgrades.BATTERY_POWER)
				at[#at + 1] = api.world.placement(enemy)
			end
			fired = M.path(pos, at)
			pcall(api.world.arc, fired)
			M.record(side, fired, now)
			b.charge = 0
		end
	end
	crackle(b, unit, b.charge >= M.GLOW_AT - 1e-6)
	return fired
end

-- A death empties the charge, and the crackle went with the body.
function M.died(b)
	b.charge, b.last = 0, nil
	if b.glow then pcall(api.world.detach_effect, b.glow) end
	b.glow, b.glow_unit = nil, nil
end

-- A discharge this machine drew, kept for the lobby data.
function M.record(side, path, now)
	side.seq = side.seq + 1
	side.events[#side.events + 1] = { seq = side.seq, time = now, path = path }
	while #side.events > M.KEPT do table.remove(side.events, 1) end
end

local function num(x) return string.format("%.1f", x) end

local function points_text(list)
	local out = {}
	for i, p in ipairs(list) do out[i] = num(p.x) .. "," .. num(p.y) .. "," .. num(p.z or 0) end
	return table.concat(out, "|")
end

local function points_of(text)
	local out = {}
	for x, y, z in (text or ""):gmatch("(-?[%d.]+),(-?[%d.]+),(-?[%d.]+)") do
		out[#out + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
	end
	return out
end

-- The lobby text: the mission, where this machine's crackling players stand, then each kept discharge
-- as its number, its time and its path. nil when there's nothing to show.
function M.encode(side, mission, glowing)
	if #side.events == 0 and #glowing == 0 then return nil end
	local parts = { tostring(mission), points_text(glowing) }
	for _, e in ipairs(side.events) do
		parts[#parts + 1] = e.seq .. "@" .. num(e.time) .. "@" .. points_text(e.path)
	end
	return table.concat(parts, ";")
end

function M.decode(text)
	if type(text) ~= "string" then return nil end
	local parts = {}
	for part in (text .. ";"):gmatch("([^;]*);") do parts[#parts + 1] = part end
	if #parts < 2 then return nil end
	local out = { mission = parts[1], glowing = points_of(parts[2]), events = {} }
	for i = 3, #parts do
		local seq, time, path = parts[i]:match("^(%d+)@(-?[%d.]+)@(.*)$")
		if seq then out.events[#out.events + 1] = { seq = tonumber(seq), time = tonumber(time), path = points_of(path) } end
	end
	return out
end

-- Another machine's discharges, from its lobby text: the paths not drawn yet, fresh and from this
-- mission. The first text seen from a machine only sets where to start, so a run joined late doesn't
-- draw old bolts.
function M.take(side, peer, e, mission, now)
	if not e or e.mission ~= tostring(mission) then return {} end
	local seen, out, top = side.seen[peer], {}, side.seen[peer] or 0
	for _, ev in ipairs(e.events) do
		if seen and ev.seq > seen and math.abs(now - ev.time) <= M.FRESH and #ev.path >= 2 then out[#out + 1] = ev.path end
		top = math.max(top, ev.seq)
	end
	side.seen[peer] = top
	return out
end

local function flat(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- The other machines' players who crackle: each shared spot goes to the nearest player of another
-- machine within GLOW_MATCH metres. others: { unit, pos } for each. The units, as a set.
function M.match_glows(glowing, others)
	local out = {}
	for _, spot in ipairs(glowing) do
		local best, best_d = nil, M.GLOW_MATCH
		for _, o in ipairs(others) do
			local d = flat(spot, o.pos)
			if d <= best_d and not out[o.unit] then best, best_d = o.unit, d end
		end
		if best then out[best] = true end
	end
	return out
end

-- Puts the crackle on the other machines' players in `want` and takes it off the rest.
function M.show_remote_glows(side, want)
	for unit, handle in pairs(side.remote_glows) do
		if not want[unit] then
			pcall(api.world.detach_effect, handle)
			side.remote_glows[unit] = nil
		end
	end
	for unit in pairs(want) do
		if not side.remote_glows[unit] then
			local ok, handle = pcall(api.world.attach_effect, unit, "shock")
			if ok and type(handle) == "number" then side.remote_glows[unit] = handle end
		end
	end
end

function M.clear(side, players)
	for _, b in pairs(players) do
		if b.battery then M.died(b.battery) end
	end
	M.show_remote_glows(side, {})
end

return M
