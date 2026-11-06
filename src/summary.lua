-- The end of a run: what each player did, and the screen that shows it before the game's own mission
-- end. Runs without the game, apart from M.install's hook.
--
-- The tally: each machine counts its own players, by their slot in the game's player list (the same on
-- every machine): kills, damage to enemies, samples, downs, deaths, Democracy Protects saves, and the
-- damage by source. Obsidian API's combat.on_hit names the weapon slot of a weapon hit only. The damage
-- the upgrades deal through api.enemies.damage or an explosion is marked as the hit goes out (M.mark_hit,
-- M.marking, src/hits.lua) and the hit on that enemy that follows takes the mark. Destroyer Support and Suitable
-- Replacement call a real stratagem, so a hit near where and soon after they called it is theirs (M.zone).
--
-- The hold: the host's StateGame.update_host ends the mission when the shuttle leaves (MissionManager
-- .extraction_done) or when everyone has been dead for 3 seconds (game_over_timer below 0). M.gate
-- keeps both from happening while the summary is up, then lets them go, and the game's own flow carries
-- on: the host sends rpc_on_mission_done, and every machine fades out to the mission end screens.
--
-- The sync: every machine shares its players' numbers and who has confirmed, under the lobby key
-- "summary", with the mission and its run (src/sync.lua), and a number for each summary the host opens.
-- The host's text also says whether the summary is open, cancelled or over. A machine follows the
-- host's: it opens the host's summary, and a closed one it hasn't seen open stays shut.
local M = {}

M.DELAY = 2 -- seconds from the end to the screen showing
M.FADE = 0.6 -- seconds it takes to fade in
M.LIMIT = 30 -- seconds to confirm, from when it shows
M.WARNING = 6 -- with this many seconds left, the bar of the time left flashes
M.GRACE = 1 -- seconds after it shows before a press counts: a shot isn't a confirm
M.TOP = 5 -- damage sources shown for each player
M.MARK_LIFE = 1 -- seconds a mark waits for its hit
M.SLACK = 1 -- seconds apart the host's age and this machine's may be before this one follows

-- The game counts game_over_timer down from 3 once everyone is dead. While held it's kept here, above
-- one step's countdown (16 frames of real time, more than 2.9 seconds only under 6 frames a second).
M.HOLD_TIMER = 2.9
M.WIPE_BELOW = 2.95

-- What a stratagem an upgrade calls is in for: its hits within `radius` metres of the call, of the
-- attacker or the enemy, for `seconds` after it. A unit that hit once in it stays the upgrade's.
M.ZONES = {
	destroyer_support = { radius = 12, seconds = 15 },
	suitable_replacement = { radius = 4, seconds = 30 },
}

-- The upgrades whose effect still hurts after the hit that set it off: a hit with no weapon on an enemy
-- they run on is theirs (src/fight.lua's running effects).
M.RUNNING = { fire = "ignition_rounds", poison = "needle_rounds" }

local function whole(n) return math.floor((tonumber(n) or 0) + 0.5) end

-- The tally ---------------------------------------------------------------------------------------

function M.tally()
	return { players = {}, marks = setmetatable({}, { __mode = "k" }), zones = {}, bound = setmetatable({}, { __mode = "k" }), bosses = 0, kills = {} }
end

function M.player(t, slot)
	local p = t.players[slot]
	if not p then
		p = { kills = 0, damage = 0, samples = 0, downs = 0, deaths = 0, saves = 0, sources = {} }
		t.players[slot] = p
	end
	return p
end

function M.add(t, slot, field, n)
	if not slot then return end
	local p = M.player(t, slot)
	p[field] = (p[field] or 0) + (n or 1)
end

function M.add_damage(t, slot, source, amount)
	amount = tonumber(amount) or 0
	if not slot or amount <= 0 then return end
	local p = M.player(t, slot)
	p.damage = p.damage + amount
	p.sources[source] = (p.sources[source] or 0) + amount
end

-- A hit to come on `victim` from an upgrade: `source` (an upgrade id or "grenade"), for the player in
-- `slot`. Marks wait in order and run out after M.MARK_LIFE.
function M.mark(t, victim, source, slot, now)
	if victim == nil then return end
	local list = t.marks[victim]
	if not list then
		list = {}
		t.marks[victim] = list
	end
	list[#list + 1] = { source = source, slot = slot, at = now }
end

-- The oldest mark on `victim` still waiting, taken off: its source and slot, or nil.
function M.take_mark(t, victim, now)
	local list = victim ~= nil and t.marks[victim]
	if not list then return nil end
	while #list > 0 do
		local m = table.remove(list, 1)
		if now - m.at <= M.MARK_LIFE then
			if #list == 0 then t.marks[victim] = nil end
			return m.source, m.slot
		end
	end
	t.marks[victim] = nil
	return nil
end

-- An upgrade's stratagem called at `pos` (src/upgrades.lua's env.call_stratagem).
function M.zone(t, source, slot, pos, now)
	local z = M.ZONES[source]
	if not (z and pos) then return end
	t.zones[#t.zones + 1] = { source = source, slot = slot, x = pos.x, y = pos.y, from = now, to = now + z.seconds, radius = z.radius }
	-- Old ones go.
	for i = #t.zones, 1, -1 do
		if t.zones[i].to < now then table.remove(t.zones, i) end
	end
end

local function within(z, p)
	return p ~= nil and (p.x - z.x) ^ 2 + (p.y - z.y) ^ 2 <= z.radius ^ 2
end

-- The upgrade a hit with no weapon and no mark belongs to, by its attacker: one bound before, or a
-- zone it or the enemy is in now, which binds it. attacker_at, victim_at: { x, y } or nil.
function M.zone_of(t, attacker, attacker_at, victim_at, now)
	local b = attacker ~= nil and t.bound[attacker]
	if b then return b.source, b.slot end
	for i = #t.zones, 1, -1 do
		local z = t.zones[i]
		if now >= z.from and now <= z.to and (within(z, attacker_at) or within(z, victim_at)) then
			if attacker ~= nil then t.bound[attacker] = { source = z.source, slot = z.slot } end
			return z.source, z.slot
		end
	end
	return nil
end

-- A hit's source, as a key: "primary:<item>", "sidearm:<item>", "support:<stratagem>", "u:<upgrade
-- id>", "grenade", "melee" or "stratagems". h: { slot (the weapon slot or nil), item (the weapon's
-- name: an item, or the stratagem of a support weapon), mark (a marked source), self (the attacker is
-- the player), running (the upgrade of an effect running on the enemy), zone (an upgrade's zone) }.
local SLOT_KEYS = { primary_weapon = "primary", sidearm_weapon = "sidearm", support_weapon = "support" }

function M.source_of(h)
	local slot = h.slot and SLOT_KEYS[h.slot]
	if slot then return slot .. ":" .. (h.item or "") end
	if h.mark == "grenade" then return "grenade" end
	if h.mark then return "u:" .. h.mark end
	if h.self then
		if h.running then return "u:" .. h.running end
		return "melee"
	end
	if h.zone then return "u:" .. h.zone end
	return "stratagems"
end

-- A player's sources by damage, the most first, `n` at most: { { key, damage } }.
function M.top(sources, n)
	local list = {}
	for key, damage in pairs(sources or {}) do
		if damage >= 1 then list[#list + 1] = { key = key, damage = damage } end
	end
	table.sort(list, function(a, b)
		if a.damage ~= b.damage then return a.damage > b.damage end
		return a.key < b.key
	end)
	while #list > (n or M.TOP) do table.remove(list) end
	return list
end

-- Calls from the upgrades: run.lua sets on_mark and on_marking for a run, and without them nothing is
-- marked. owner: the player's body.
M.on_mark, M.on_marking = nil, nil

function M.mark_hit(victim, source, owner)
	if M.on_mark then pcall(M.on_mark, victim, source, owner) end
end

-- fn(), with every enemy it queues a hit on marked for `source`.
function M.marking(source, owner, fn)
	if M.on_marking then return M.on_marking(source, owner, fn) end
	return fn()
end

-- The screen's state --------------------------------------------------------------------------------

-- kind: "extracted" or "defeated". seq: the host's number for it. age: seconds since the end, the
-- host's when following it.
function M.new(kind, mission, run, seq, age)
	return { kind = kind, mission = mission, run = run, seq = seq, age = age or 0, ready = {}, closed = false, reports = {}, time = 0, bosses = 0 }
end

function M.step(s, dt) s.age = s.age + (dt or 0) end

function M.visible(s) return s.age >= M.DELAY end

function M.alpha(s)
	return math.max(0, math.min((s.age - M.DELAY) / M.FADE, 1))
end

-- Seconds left to confirm.
function M.left(s)
	return math.max(0, M.LIMIT - math.max(0, s.age - M.DELAY))
end

-- Whether a press counts now.
function M.accepts(s)
	return not s.closed and s.age >= M.DELAY + M.GRACE
end

-- Whether every slot in `slots` has confirmed. ready: { [slot] = true }.
function M.all_ready(slots, ready)
	if #slots == 0 then return false end
	for _, slot in ipairs(slots) do
		if not ready[slot] then return false end
	end
	return true
end

-- The host: whether to let the game go on now.
function M.should_release(s, slots, ready)
	return not s.closed and M.visible(s) and (M.left(s) <= 0 or M.all_ready(slots, ready))
end

-- Who has confirmed, from this machine and every report. mine: { [slot] = true }.
function M.ready_set(s)
	local out = {}
	for slot in pairs(s.ready) do out[slot] = true end
	for _, report in pairs(s.reports) do
		for _, p in ipairs(report.players or {}) do
			if p.ready then out[p.slot] = true end
		end
	end
	return out
end

-- A machine following the host's text `rec` (decoded): "open", "close", "cancel", "sync" or nil.
-- host_run: the host's run, from its run text (src/sync.lua).
function M.follow(s, rec, mission, host_run)
	if not (rec and rec.host and rec.mission == mission and rec.run == host_run) then return nil end
	if not s or s.seq ~= rec.seq then
		-- A summary first seen closed or cancelled is one this machine missed: nothing to open.
		if rec.closed or rec.kind == "cancelled" then return nil end
		return "open"
	end
	if rec.kind == "cancelled" then return "cancel" end
	if rec.closed and not s.closed then return "close" end
	if math.abs(s.age - rec.age) > M.SLACK then return "sync" end
	return nil
end

-- The lobby text ----------------------------------------------------------------------------------

local KINDS = { extracted = "e", defeated = "d", cancelled = "x" }
local KIND_OF = { e = "extracted", d = "defeated", x = "cancelled" }

-- players: { { slot, ready, extracted, kills, damage, samples, downs, deaths, saves, sources = { { key,
-- damage } } } }. host: whether this machine is the host.
function M.encode(s, host, players)
	local parts = {}
	for _, p in ipairs(players or {}) do
		local src = {}
		for _, e in ipairs(p.sources or {}) do src[#src + 1] = e.key .. "=" .. whole(e.damage) end
		parts[#parts + 1] = table.concat({ whole(p.slot), p.ready and 1 or 0, p.extracted and 1 or 0, whole(p.kills), whole(p.damage), whole(p.samples),
			whole(p.downs), whole(p.deaths), whole(p.saves), table.concat(src, "/") }, ",")
	end
	return string.format("%d;%d;%d;%s;%d;%.1f;%d;%d;%d;%s", s.mission, s.run, s.seq, KINDS[s.kind] or "d", host and 1 or 0, s.age, s.closed and 1 or 0,
		whole(s.time), whole(s.bosses), table.concat(parts, "|"))
end

local function decode_player(text)
	local f = {}
	for v in (text .. ","):gmatch("([^,]*),") do f[#f + 1] = v end
	if #f ~= 10 then return nil end
	for i = 1, 9 do
		if not f[i]:match("^%d+$") then return nil end
	end
	local p = { slot = tonumber(f[1]), ready = f[2] == "1", extracted = f[3] == "1", kills = tonumber(f[4]), damage = tonumber(f[5]), samples = tonumber(f[6]),
		downs = tonumber(f[7]), deaths = tonumber(f[8]), saves = tonumber(f[9]), sources = {} }
	for key, damage in f[10]:gmatch("([%w_:]+)=(%d+)") do p.sources[#p.sources + 1] = { key = key, damage = tonumber(damage) } end
	return p
end

function M.decode(text)
	if type(text) ~= "string" then return nil end
	local m, r, q, k, h, a, c, t, b, rest = text:match("^(%d+);(%d+);(%d+);([edx]);([01]);([%d.]+);([01]);(%d+);(%d+);(.*)$")
	if not m then return nil end
	local out = { mission = tonumber(m), run = tonumber(r), seq = tonumber(q), kind = KIND_OF[k], host = h == "1", age = tonumber(a), closed = c == "1",
		time = tonumber(t), bosses = tonumber(b), players = {} }
	if rest ~= "" then
		for part in (rest .. "|"):gmatch("([^|]*)|") do
			local p = decode_player(part)
			if p then out.players[#out.players + 1] = p end
		end
	end
	return out
end

-- The hold ----------------------------------------------------------------------------------------

-- h: { kind (what's held: "extracted" or "defeated", nil for nothing), released, allowed (a run that
-- may end on a summary) }. v: the game's state before StateGame.update_host's step: extraction_done,
-- timer (game_over_timer), abort (abort_mission), over (game_state is "game_over"). What to change
-- for this step: { timer = a value for game_over_timer, hide_extraction = true }.
function M.gate(h, v)
	local act = {}
	-- An abort from the menu ends the mission at once, as it always does.
	if v.over or v.abort or not h.allowed then return act end
	if v.extraction_done and not h.kind then h.kind, h.fresh = "extracted", true end
	if h.kind and not h.released then
		if v.extraction_done then act.hide_extraction = true end
		if (tonumber(v.timer) or 0) < M.HOLD_TIMER then act.timer = M.HOLD_TIMER end
	elseif h.kind == "defeated" and h.released then
		act.timer = -1
	end
	return act
end

-- After the step: everyone dead and the game counting down opens a defeat; somebody back up while one
-- is held cancels it. "defeated", "cancel" or nil.
function M.after(h, v)
	if v.over or v.abort or not h.allowed then return nil end
	local timer = tonumber(v.timer) or 0
	if not h.kind and timer < M.WIPE_BELOW then
		h.kind, h.fresh = "defeated", true
		return "defeated"
	end
	if h.kind == "defeated" and not h.released and timer >= 3 then
		h.kind = nil
		return "cancel"
	end
	return nil
end

-- The hook on the host's update. get(): the run's hold table, or nil outside a run.
function M.install(get)
	obsidian.hook("StateGame", "update_host", function(original, self, ...)
		local h = get()
		if not h or self.update_host_current_step ~= 0 then return original(self, ...) end
		local mm = self.mission_manager
		local function view()
			return { extraction_done = type(mm) == "table" and mm.extraction_done == true, timer = self.game_over_timer, abort = self.abort_mission == true,
				over = self.game_state == "game_over" }
		end
		local act = M.gate(h, view())
		if act.timer then self.game_over_timer = act.timer end
		local hidden = act.hide_extraction and type(mm) == "table"
		if hidden then mm.extraction_done = false end
		local r = { pcall(original, self, ...) }
		if hidden then mm.extraction_done = true end
		if not r[1] then error(r[2], 0) end
		M.after(h, view())
		return unpack(r, 2)
	end)
end

return M
