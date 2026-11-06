-- Orbital bombardment windows: from 7:00 to 9:00, from 14:00 to 16:00, then for a minute every 6
-- minutes (22:00 to 23:00, 28:00 to 29:00, ...). During a window the host calls random red strike
-- stratagems near a random player, as the Proving Grounds' "orbital_bombardments" modifier does
-- (ProvingGroundsModifiersManager.orbital_bombardments): a flare 4 to 10 m from the player, its own
-- call-in plus at least 2 s more, and the next one once the interval and that call-in have passed. The
-- strikes belong to nobody and hit players too.
--
-- Every strike unit is in resource_packages/mission_common, which every mission loads on every machine
-- (internal/research/api/enemies.md 7.7), so no package is loaded for them.
--
-- A window is marked by sound only: the game's Exterminate wave alarm (the camera unit's
-- "genocide_wave_start" flow event, ObjectiveGenocideComponent.update_slaves), WARNING seconds before
-- it opens, on every machine from its own clock.
local api = obsidian.import("obsidian.api")

local M = {}

M.WINDOWS = { { 7, 9 }, { 14, 16 } } -- minutes
M.REPEAT_FROM = 22
M.REPEAT_EVERY = 6
M.REPEAT_LENGTH = 1
M.WARNING = 4 -- seconds before a window the alarm sounds
M.EVERY = 6 -- seconds between strikes, on top of each strike's own call-in
M.EXTRA_DELAY = 2 -- seconds added to a strike's call-in, at least (the Proving Grounds' floor)
M.RING = { 4, 10 } -- metres from the player a flare lands
M.DEBUG_SECONDS = 60 -- the debug page's window
M.ALARM_EVENT = "genocide_wave_start"

-- LoadoutSettings' stratagems of subtype "strike", without the Static Field, which is "strike_non_lethal"
-- too and isn't red.
M.STRIKES = {
	"stratagem_airstrike", "stratagem_dive_bomb", "stratagem_strafingrun", "stratagem_napalmstrike",
	"stratagem_strafingrun_heavy", "stratagem_close_air_support", "stratagem_missile_barrage", "stratagem_artillery",
	"stratagem_precision_artillery", "stratagem_orbital_strike", "stratagem_missile_strike", "stratagem_railcannon_strike",
}

local function g(name) return rawget(_G, name) end

-- The window that holds `minutes`: its start and end in minutes, or nil.
function M.window_of(minutes)
	for _, w in ipairs(M.WINDOWS) do
		if minutes >= w[1] and minutes < w[2] then return w[1], w[2] end
	end
	if minutes >= M.REPEAT_FROM then
		local start = M.REPEAT_FROM + math.floor((minutes - M.REPEAT_FROM) / M.REPEAT_EVERY + 1e-9) * M.REPEAT_EVERY
		if minutes < start + M.REPEAT_LENGTH then return start, start + M.REPEAT_LENGTH end
	end
	return nil
end

-- The starts of the windows after `from` up to and including `to`, in minutes.
function M.starts(from, to)
	local out = {}
	for _, w in ipairs(M.WINDOWS) do
		if w[1] > from and w[1] <= to then out[#out + 1] = w[1] end
	end
	local k = math.max(0, math.floor((from - M.REPEAT_FROM) / M.REPEAT_EVERY))
	while true do
		local start = M.REPEAT_FROM + k * M.REPEAT_EVERY
		if start > to then break end
		if start > from then out[#out + 1] = start end
		k = k + 1
	end
	return out
end

-- Whether the alarm sounds between `from` and `to` (seconds of the run's clock): WARNING seconds before
-- a window opens.
function M.warns(from, to)
	local lead = M.WARNING
	return #M.starts((from + lead) / 60, (to + lead) / 60) > 0
end

function M.new() return { wait = 0, forced_until = nil } end

-- Whether strikes fall at `time` (seconds): in a window, or in the debug page's.
function M.active(s, time)
	if s.forced_until and time < s.forced_until then return true end
	return M.window_of(time / 60) ~= nil
end

-- dt: game seconds. True when a strike is due now; the caller adds its call-in to s.wait.
function M.tick(s, dt, active)
	if not active then
		s.wait = 0
		return false
	end
	s.wait = s.wait - dt
	if s.wait > 0 then return false end
	s.wait = M.EVERY
	return true
end

-- The debug page: a window from `time` for DEBUG_SECONDS.
function M.force(s, time)
	s.forced_until = time + M.DEBUG_SECONDS
	s.wait = 0
end

-- The strikes the game has, of M.STRIKES.
function M.strikes()
	local have = {}
	local ok, list = pcall(function() return api.catalog.by_subtype("strike") end)
	if not (ok and type(list) == "table") then return M.STRIKES end
	for _, item in ipairs(list) do have[item.name] = true end
	local out = {}
	for _, name in ipairs(M.STRIKES) do
		if have[name] then out[#out + 1] = name end
	end
	return out
end

-- The alarm, on this machine.
function M.alarm()
	local cm, U = g("CameraManager"), g("Unit")
	local ok, camera = pcall(function() return cm:camera_unit() end)
	if not (ok and camera and U) then return false end
	return pcall(U.flow_event, camera, M.ALARM_EVENT)
end

-- A spot 4 to 10 m from `at`, on the level the way the Proving Grounds pick one, or a plain one in the ring.
local function spot(at, random)
	local st = api.game.state()
	local V3, Q, ssu = g("Vector3"), g("Quaternion"), g("SpatialSpawnUtlity")
	local world = type(st) == "table" and st.world_proxy and st.world_proxy:get_world()
	if V3 and Q and ssu and world then
		local ok, points = pcall(ssu.generate_points_in_donut, V3(at.x, at.y, at.z or 0), M.RING[1], M.RING[2], 360, Q.identity(), 1, 1, world)
		if ok and type(points) == "table" and points[1] then return points[1] end
	end
	local angle = random() * math.pi * 2
	local r = M.RING[1] + random() * (M.RING[2] - M.RING[1])
	return { x = at.x + math.cos(angle) * r, y = at.y + math.sin(angle) * r, z = at.z or 0 }
end

-- Host only: one strike near one of `players` ({ pos }). Answers the strike's name, or nil.
function M.strike(s, players, random)
	random = random or math.random
	local names = M.strikes()
	local targets = {}
	for _, p in ipairs(players or {}) do
		if p.pos then targets[#targets + 1] = p end
	end
	if #names == 0 or #targets == 0 then return nil end
	local name = names[math.floor(random() * #names) + 1] or names[1]
	local target = targets[math.floor(random() * #targets) + 1] or targets[1]
	local info = api.catalog.stratagem and api.catalog.stratagem(name)
	local activation = info and tonumber(info.activation_time) or 0
	local delay = math.max(activation, M.EXTRA_DELAY)
	local at = spot(target.pos, random)
	local st = api.stratagems
	local ok, why
	if st.call_unowned and info then
		ok, why = st.call_unowned(info, at, delay)
	else
		ok, why = st.call(name, at, delay)
	end
	s.wait = s.wait + activation
	if not ok then
		obsidian.log("arcade: no strike " .. name .. ": " .. tostring(why))
		return nil
	end
	return name
end

-- Every frame of a run outside the cards, on every machine. from, to: the run's clock before and after
-- this frame, in seconds. players: everyone on the field ({ pos }).
function M.update(s, from, to, dt, players, host)
	if M.warns(from, to) then
		M.alarm()
		obsidian.log("arcade: bombardment in " .. M.WARNING .. " s")
	end
	if not host then return end
	if M.tick(s, dt, M.active(s, to)) then
		local name = M.strike(s, players)
		if name then obsidian.log("arcade: bombardment, " .. name) end
	end
end

return M
