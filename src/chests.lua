-- Chests: the game's carry case on the ground, glowing in the color of the rarity inside. Pressing
-- interact beside one opens it, and every player in the squad gets their own upgrades of that rarity,
-- drawn as the level-up cards draw them and taken at once.
--
-- Where they come from, all decided by the host: an elite drops a chest of 1 upgrade, a boss a chest of
-- 3, and any other kill has a KILL_CHANCE of a chest of 1. The rarity is rolled as it drops.
--
-- The look is a prop (Obsidian API's world.prop) on each machine, of gameobjects/carry_crate_01, the
-- carry case of mission_common: the 1p cases of gameobjects_spec are only in some level packages. The
-- open goes through the press of interact (CharacterComponent.handle_interact): beside a chest, the
-- press opens it instead of anything else.
--
-- Lobby data: the host shares the chests on the ground ("chests") and the last ones opened, each with a
-- number ("chest_opened"); every machine shares the chests its players asked to open ("chest_open").
-- The host opens what's asked, and every machine gives its own players their upgrades for each open
-- it hasn't seen. The first look at the host's opens only notes where they are.
local native = obsidian.module("src/native")
local art = obsidian.module("src/art")
local cards = obsidian.module("src/cards")
local cards_hud = obsidian.module("src/cards_hud")

local api = obsidian.import("obsidian.api")

local M = {}

local function g(name) return rawget(_G, name) end

M.UNIT = "gameobjects/carry_crate_01"
M.KILL_CHANCE = 1 / 500
M.COUNT = { elite = 1, boss = 3, kill = 1 }
-- The rarity of a chest, by where it came from: a boss's is never common.
M.WEIGHTS = {
	elite = { common = 50, rare = 35, legendary = 15 },
	kill = { common = 55, rare = 33, legendary = 12 },
	boss = { rare = 65, legendary = 35 },
}
M.RARITIES = { "common", "rare", "legendary" }
M.CODE = { common = "c", rare = "r", perk = "p", legendary = "l" }
M.REACH = 2.2 -- metres from a chest a press of interact opens it
M.LIMIT = 6 -- chests on the ground at once; past it the oldest goes
M.OPENED_KEPT = 4
M.SHARE_EVERY = 0.5
M.PANEL_SECONDS = 4
M.SOUND = "objective_found"

function M.new()
	return { next_id = 0, ground = {}, opened = {}, seq = 0, props = {}, seen = nil, asked = {}, panels = {}, share_in = 0, remote = nil }
end

M.state = M.new()

-- A rarity for a chest from `source` ("elite", "boss" or "kill"). draw(): 0 to 1.
function M.roll_rarity(source, draw)
	local weights = M.WEIGHTS[source] or M.WEIGHTS.kill
	local total = 0
	for _, id in ipairs(M.RARITIES) do total = total + (weights[id] or 0) end
	local x = draw() * total
	for _, id in ipairs(M.RARITIES) do
		x = x - (weights[id] or 0)
		if x < 0 then return id end
	end
	return M.RARITIES[#M.RARITIES]
end

-- Host: a chest on the ground. Answers it.
function M.add(c, pos, rarity, count)
	c.next_id = c.next_id + 1
	local chest = { id = c.next_id, rarity = rarity, count = count, x = pos.x, y = pos.y, z = pos.z or 0 }
	c.ground[#c.ground + 1] = chest
	while #c.ground > M.LIMIT do table.remove(c.ground, 1) end
	return chest
end

-- Host: opens chest `id`, if it's still on the ground. Answers the open ({ seq, id, rarity, count }).
function M.open(c, id)
	for i, chest in ipairs(c.ground) do
		if chest.id == id then
			table.remove(c.ground, i)
			c.seq = c.seq + 1
			local ev = { seq = c.seq, id = id, rarity = chest.rarity, count = chest.count }
			c.opened[#c.opened + 1] = ev
			while #c.opened > M.OPENED_KEPT do table.remove(c.opened, 1) end
			return ev
		end
	end
	return nil
end

-- The chest of `list` within REACH of `pos`, nearest first, or nil.
function M.within(list, pos)
	local best, best_d = nil, M.REACH * M.REACH
	for _, chest in ipairs(list) do
		local d = (chest.x - pos.x) ^ 2 + (chest.y - pos.y) ^ 2
		if d <= best_d and math.abs((chest.z or 0) - (pos.z or 0)) < 3 then best, best_d = chest, d end
	end
	return best
end

local RARITY_OF = {}
for id, code in pairs(M.CODE) do RARITY_OF[code] = id end

local function num(x) return string.format("%.1f", x) end

function M.encode_ground(mission, ground)
	local parts = {}
	for i, c in ipairs(ground) do parts[i] = c.id .. "@" .. M.CODE[c.rarity] .. "@" .. c.count .. "@" .. num(c.x) .. "," .. num(c.y) .. "," .. num(c.z) end
	return tostring(mission) .. ";" .. table.concat(parts, "|")
end

function M.decode_ground(text)
	if type(text) ~= "string" then return nil end
	local mission, rest = text:match("^([^;]*);(.*)$")
	if not mission then return nil end
	local out = { mission = mission, list = {} }
	for id, r, n, x, y, z in rest:gmatch("(%d+)@(%a)@(%d+)@(-?[%d.]+),(-?[%d.]+),(-?[%d.]+)") do
		if RARITY_OF[r] then
			out.list[#out.list + 1] = { id = tonumber(id), rarity = RARITY_OF[r], count = tonumber(n), x = tonumber(x), y = tonumber(y), z = tonumber(z) }
		end
	end
	return out
end

function M.encode_opened(mission, opened)
	local parts = {}
	for i, ev in ipairs(opened) do parts[i] = ev.seq .. "@" .. ev.id .. "@" .. M.CODE[ev.rarity] .. "@" .. ev.count end
	return tostring(mission) .. ";" .. table.concat(parts, "|")
end

function M.decode_opened(text)
	if type(text) ~= "string" then return nil end
	local mission, rest = text:match("^([^;]*);(.*)$")
	if not mission then return nil end
	local out = { mission = mission, list = {} }
	for seq, id, r, n in rest:gmatch("(%d+)@(%d+)@(%a)@(%d+)") do
		if RARITY_OF[r] then out.list[#out.list + 1] = { seq = tonumber(seq), id = tonumber(id), rarity = RARITY_OF[r], count = tonumber(n) } end
	end
	return out
end

-- The host's opens not seen yet here. seen: the highest number seen, nil before the first look, which
-- only notes it. Answers the opens and the new `seen`.
function M.take_opened(seen, e)
	local out, top = {}, seen or 0
	for _, ev in ipairs(e.list) do
		if seen and ev.seq > seen then out[#out + 1] = ev end
		top = math.max(top, ev.seq)
	end
	return out, top
end

function M.encode_asked(mission, asked)
	local ids = {}
	for id in pairs(asked) do ids[#ids + 1] = id end
	if #ids == 0 then return nil end
	table.sort(ids)
	return tostring(mission) .. ";" .. table.concat(ids, ",")
end

function M.decode_asked(text)
	if type(text) ~= "string" then return nil end
	local mission, rest = text:match("^([^;]*);(.*)$")
	if not mission then return nil end
	local out = { mission = mission, ids = {} }
	for id in rest:gmatch("%d+") do out.ids[#out.ids + 1] = tonumber(id) end
	return out
end

-- The game -------------------------------------------------------------------------------------------

-- How a chest shows its rarity: the case's own outline (the silhouette pass the game turns on for a
-- case to carry, ObjectiveCarryObjectComponent.setup_slave) in the rarity's color.
local function tint(unit, color)
	local aux, V4 = g("MaterialAux"), g("Vector4")
	if not (aux and V4 and unit) then return end
	local r, gr, b = tonumber(color:sub(2, 3), 16) / 255, tonumber(color:sub(4, 5), 16) / 255, tonumber(color:sub(6, 7), 16) / 255
	aux.set_shader_pass_flag(unit, nil, nil, "silhouette", true, true)
	aux.set_vector4(unit, nil, nil, "silhouette_color", V4(r, gr, b, 1), true)
end

local function vec(p) return g("Vector3")(p.x, p.y, p.z or 0) end

-- The props in line with the chests on the ground.
local function sync_props(c, list)
	local want = {}
	for _, chest in ipairs(list) do want[chest.id] = chest end
	for id, prop in pairs(c.props) do
		if not want[id] then
			pcall(prop.remove, prop)
			c.props[id] = nil
		end
	end
	if not api.world.prop or c.no_props then return end
	for id, chest in pairs(want) do
		if not c.props[id] then
			local prop, why = api.world.prop(M.UNIT, vec(chest))
			if not prop then
				if why ~= "not_in_mission" then
					c.no_props = true
					obsidian.log("arcade: no chest props: " .. tostring(why))
				end
				return
			end
			c.props[id] = prop
			local ok, err = pcall(tint, prop.unit, cards.rarity_color(chest.rarity))
			if not ok and not c.untinted then
				c.untinted = true
				obsidian.log("arcade: the chests keep the case's look: " .. tostring(err))
			end
		end
	end
end

-- The chests on the ground as this machine knows them: the host's own, or what the host shares.
function M.ground()
	local c = M.state
	if api.game.is_host() then return c.ground end
	return c.remote or {}
end

-- An open seen here: each player of this machine gets their upgrades, through c.grant(n, rarity,
-- count), which answers the upgrades player n took.
local function apply(c, local_list, ev)
	local grant = c.grant
	if not grant then return end
	for n in ipairs(local_list) do
		local ok, got = pcall(grant, n, ev.rarity, ev.count)
		if ok and type(got) == "table" and #got > 0 then
			c.panels[#c.panels + 1] = { n = n, rarity = ev.rarity, list = got, at = os.clock() }
		elseif not ok then
			obsidian.log("arcade: chest: " .. tostring(got))
		end
	end
	obsidian.log("arcade: chest " .. ev.id .. " opened, " .. ev.count .. " " .. ev.rarity)
	if c.play_at then pcall(c.play_at, M.SOUND, 1.5) end
end

-- Every frame of a run, on every machine. grant: as in apply. play_at(sound, volume): src/run.lua's.
function M.update(run, dt_real, grant, play_at)
	local c = M.state
	local host = api.game.is_host()
	local mission = run.sync.mission
	c.grant, c.play_at = grant, play_at
	c.share_in = c.share_in - dt_real
	if c.share_in <= 0 then
		c.share_in = M.SHARE_EVERY
		if host then
			-- The others' asks: each chest still on the ground opens.
			for _, text in pairs(api.lobby.shared("chest_open")) do
				local a = M.decode_asked(text)
				if a and a.mission == tostring(mission) then
					for _, id in ipairs(a.ids) do
						local ev = M.open(c, id)
						if ev then apply(c, run.local_list, ev) end
					end
				end
			end
			c.asked = {}
			pcall(api.lobby.share, "chests", M.encode_ground(mission, c.ground))
			pcall(api.lobby.share, "chest_opened", M.encode_opened(mission, c.opened))
			pcall(api.lobby.share, "chest_open", nil)
		else
			pcall(api.lobby.share, "chests", nil)
			pcall(api.lobby.share, "chest_opened", nil)
			local remote = {}
			for _, text in pairs(api.lobby.shared("chests")) do
				local d = M.decode_ground(text)
				if d and d.mission == tostring(mission) then remote = d.list end
			end
			c.remote = remote
			for _, text in pairs(api.lobby.shared("chest_opened")) do
				local d = M.decode_opened(text)
				if d and d.mission == tostring(mission) then
					local list
					list, c.seen = M.take_opened(c.seen, d)
					for _, ev in ipairs(list) do apply(c, run.local_list, ev) end
				end
			end
			-- An ask stays out until the chest is off the host's list.
			local there = {}
			for _, chest in ipairs(remote) do there[chest.id] = true end
			for id in pairs(c.asked) do
				if not there[id] then c.asked[id] = nil end
			end
			pcall(api.lobby.share, "chest_open", M.encode_asked(mission, c.asked))
		end
	end
	if not run.exiting then sync_props(c, M.ground()) end
end

-- Host: a chest from `source` where `pos` is. rarity: rolled when nil.
function M.drop(pos, source, draw, rarity, count)
	if not (pos and api.game.is_host()) then return nil end
	rarity = rarity or M.roll_rarity(source, draw)
	local chest = M.add(M.state, pos, rarity, count or M.COUNT[source] or 1)
	obsidian.log(string.format("arcade: a %s chest of %d from %s at %.0f, %.0f", rarity, chest.count, tostring(source), pos.x, pos.y))
	return chest
end

-- A kill on the host: a boss's chest, or the rare chest of any kill. Elites drop theirs through
-- M.drop("elite").
function M.on_kill(pos, boss, elite, draw)
	if not api.game.is_host() then return end
	if elite then M.drop(pos, "elite", draw)
	elseif boss then M.drop(pos, "boss", draw)
	elseif draw() < M.KILL_CHANCE then M.drop(pos, "kill", draw) end
end

-- A press of interact by this machine's player `n`, standing at `pos`: true when it opened (or asked
-- for) a chest, and the game's own interaction is skipped.
function M.press(run, pos)
	local c = M.state
	local chest = pos and M.within(M.ground(), pos)
	if not chest then return false end
	if api.game.is_host() then
		local ev = M.open(c, chest.id)
		if ev then apply(c, run.local_list, ev) end
	elseif not c.asked[chest.id] then
		c.asked[chest.id] = true
		c.share_in = 0
	end
	return true
end

-- run_of(): src/run.lua's run, or nil.
function M.install(run_of)
	obsidian.hook("CharacterComponent", "handle_interact", function(original, self, unit, ctx, ...)
		local run = run_of()
		if run and not run.exiting and not run.choice and not run.summary then
			for _, l in ipairs(run.local_list or {}) do
				if l.unit == unit then
					local ok, opened = pcall(M.press, run, l.pos)
					if ok and opened then return end
					if not ok then obsidian.log("arcade: chest press: " .. tostring(opened)) end
				end
			end
		end
		return original(self, unit, ctx, ...)
	end)
end

-- Pixels from the camera, into the kit's 1920x1080 design space.
local function on_screen(p)
	local px, py, on = api.world.to_screen(p)
	if not on then return nil end
	local w, h = g("Application").resolution()
	local s = math.min(w / 1920, h / 1080)
	return (px - (w - 1920 * s) / 2) / s, (py - (h - 1080 * s) / 2) / s
end

-- The key that opens a chest, as the game shows interact for the main device.
local function interact_key(keyboard)
	local text = obsidian.ui.prompt and obsidian.ui.prompt("interact") or nil
	if type(text) == "string" and text ~= "" then
		if keyboard and cards.keycap and text:sub(1, #cards.keycap) == cards.keycap then text = text:sub(#cards.keycap + 1) end
		return text
	end
	return keyboard and "E" or "X"
end

-- The chests' glow, OPEN beside the one a player of this machine stands at, and each player's panel of
-- what a chest just gave.
function M.draw(kit, run, keyboard)
	local c = M.state
	local ground = M.ground()
	local near = {}
	for _, l in ipairs(run.local_list) do
		local chest = l.pos and M.within(ground, l.pos)
		if chest then near[chest.id] = true end
	end
	for _, chest in ipairs(ground) do
		local x, y = on_screen({ x = chest.x, y = chest.y, z = chest.z + 0.4 })
		if x then
			local color = cards.rarity_color(chest.rarity)
			art.center(kit, "glow", x, y, 150, color .. "80")
			if near[chest.id] then
				cards.glyphs(kit, x, y + 46, { { keys = { interact_key(keyboard) }, label = "OPEN", plain = not keyboard } })
			end
		end
	end
	M.draw_panels(kit, run)
end

local TITLE = { common = "COMMON CHEST", rare = "RARE CHEST", perk = "PERK CHEST", legendary = "LEGENDARY CHEST" }

-- What a chest gave each player: a panel over their HUD card, in the HUD card's look, with each
-- upgrade's badge and name, for PANEL_SECONDS.
function M.draw_panels(kit, run)
	local c = M.state
	local now = os.clock()
	for i = #c.panels, 1, -1 do
		local p = c.panels[i]
		if now - p.at > M.PANEL_SECONDS then table.remove(c.panels, i) end
	end
	for _, p in ipairs(c.panels) do
		local l = run.local_list[p.n]
		local card = l and l.unit and cards_hud.seen[l.unit]
		local x, y, w, u
		if card and now - card.at <= cards_hud.STALE then
			local s = cards_hud.spot(kit, card)
			x, w, u = s.x, s.w, s.unit
			-- Over the health and armor numbers.
			y = s.y + cards_hud.STAT_SIZE * 1.75 * u + 6 * u
		else
			u, w = 1.5, 360
			x, y = (cards.W - w) / 2, 220
		end
		local row, pad = 24 * u, 6 * u
		local h = pad * 2 + 16 * u + row * #p.list
		kit:layer(cards.LAYER - 5)
		native.panel(kit, x, y, w, h, { unit = u })
		local color = cards.rarity_color(p.rarity)
		native.text(kit, TITLE[p.rarity] or "CHEST", x + pad, y + h - pad - 13 * u, { font = "heading", size = 13 * u, tracking = 1, color = color })
		for k, upg in ipairs(p.list) do
			local cy = y + h - pad - 16 * u - row * (k - 0.5)
			art.badge(kit, upg, x + pad + 10 * u, cy, 9 * u, cards.rarity_color(upg.rarity), "#232321", native.WHITE)
			native.text(kit, upg.name or upg.id, x + pad + 26 * u, cy - 5 * u, { font = "body_large", size = 13 * u, color = native.WHITE })
		end
	end
end

-- The mission is ending: the props go before the level does.
function M.clear_props()
	local c = M.state
	for id, prop in pairs(c.props) do
		pcall(prop.remove, prop)
		c.props[id] = nil
	end
	c.no_props = true
end

function M.clear()
	M.clear_props()
	for _, key in ipairs({ "chests", "chest_opened", "chest_open" }) do pcall(api.lobby.share, key, nil) end
	M.state = M.new()
end

-- The debug page: a chest of `rarity` and `count` upgrades beside this machine's first player.
function M.debug_drop(run, rarity, count)
	if not run then return false, "no_run" end
	if not api.game.is_host() then return false, "host_only" end
	local l = run.local_list[1]
	if not (l and l.pos) then return false, "no_squad" end
	M.drop({ x = l.pos.x + 2.5, y = l.pos.y, z = l.pos.z }, "debug", math.random, rarity, count)
	return true
end

return M
