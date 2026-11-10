-- The level-up cards, a player's upgrades over their HUD card, and their health and armor numbers. Drawn with a kit from
-- obsidian.ui in a 1920x1080 design space, y going up, in the game's own look (src/native). The layout
-- is plain numbers, so it can be tested.
local rules = obsidian.module("src/rules")
local art = obsidian.module("src/art")
local native = obsidian.module("src/native")
local evolve = obsidian.module("src/evolve")

local M = {}

M.W, M.H = 1920, 1080
local INK, BODY, DIM = native.WHITE, native.TEXT, native.GREY
local YELLOW = native.GOLD
local HEX, PIP = "#232321", "#3a3a37"
-- Layers: the run's HUD and orbs sit under these.
M.LAYER = 20

local rarity_of = {}
for _, r in ipairs(rules.RARITIES) do rarity_of[r.id] = r end

function M.rarity_color(id)
	return (rarity_of[id] or rules.RARITIES[1]).color
end

-- The darker shade a rarity's bar takes, so white text reads on it.
function M.bar_color(id)
	local r = rarity_of[id] or rules.RARITIES[1]
	return r.bar or r.color
end

-- A card's panel: the game's gradient box, a little see-through, with its thin frame and no black edge.
local CARD_BOX = { thick = 0, tint = "#ffffffe6" }

-- Where each player's cards go: one row across the screen alone, a column each with company. Over them
-- the bar of the time left, and over that the name of whose turn it is; under them the reroll and banish
-- prompts (tools: their centre x and baseline y), then the row of stratagems when there is one, then the controls.
-- named: one player's turn among several on this machine, with the name bar over the timer.
M.TOOLS_H = 72 -- the reroll and banish row under the cards, with the gaps
function M.layout(players, cards, strats, named)
	cards = cards or rules.CARDS
	strats = strats or 0
	local out = {}
	if players <= 1 then
		local w, h, gap = 360, 470, 30
		local size, strat_gap = 130, 16 -- the stratagem row, and the gap under the prompts
		local row = cards * w + (cards - 1) * gap
		local x0 = (M.W - row) / 2
		-- The cards and the prompts under them in the screen's vertical centre, with the stratagem row
		-- under those as one block when there is one. The timer, the name bar and the controls go around them.
		local block = h + M.TOOLS_H + (strats > 0 and strat_gap + size or 0)
		local bottom = math.floor((M.H - block) / 2)
		local y = bottom + block - h
		local hint_y = bottom - (strats > 0 and 60 or 70)
		local p = { area = { x = 0, y = 0, w = M.W, h = M.H }, title = { x = M.W / 2, y = y + h + 60 }, hint_y = hint_y, cards = {},
			timer = { x = x0, y = y + h + 26, w = row, h = 12 }, tools = { x = M.W / 2, y = y - 54 } }
		for i = 1, cards do p.cards[i] = { x = x0 + (i - 1) * (w + gap), y = y, w = w, h = h, wide = false } end
		if strats > 0 then
			local sx = (M.W - (strats * size + (strats - 1) * gap)) / 2
			p.strats = {}
			for i = 1, strats do p.strats[i] = { x = sx + (i - 1) * (size + gap), y = bottom, w = size, h = size } end
		end
		out[1] = p
		return out
	end
	local col = M.W / players
	local w = math.min(col - 56, 620)
	local gap, top = 22, 872
	local bottom = (strats > 0 and 204 or 150) + 50
	local h = math.min(216, math.floor((top - bottom - (cards - 1) * gap) / cards))
	for n = 1, players do
		local x = (n - 1) * col + (col - w) / 2
		local p = { area = { x = (n - 1) * col, y = 0, w = col, h = M.H }, title = { x = (n - 1) * col + col / 2, y = 912 }, hint_y = strats > 0 and 56 or 96, cards = {},
			timer = { x = x, y = top + 10, w = w, h = 12 }, tools = { x = (n - 1) * col + col / 2, y = bottom - 44 } }
		for i = 1, cards do p.cards[i] = { x = x, y = top - i * h - (i - 1) * gap, w = w, h = h, wide = true } end
		if strats > 0 then
			local sgap = 30
			local size = math.min(88, (w - (strats - 1) * sgap) / strats)
			local sx = x + (w - (strats * size + (strats - 1) * sgap)) / 2
			p.strats = {}
			for i = 1, strats do p.strats[i] = { x = sx + (i - 1) * (size + sgap), y = 100, w = size, h = size } end
		end
		out[n] = p
	end
	return out
end

-- Splits a text into lines that fit `width`, keeping its own line breaks.
function M.wrap(kit, text, width, opts)
	local lines = {}
	for para in (text .. "\n"):gmatch("(.-)\n") do
		local line = ""
		for word in para:gmatch("%S+") do
			local try = line == "" and word or line .. " " .. word
			if line ~= "" and kit:measure(try, opts) > width then
				lines[#lines + 1] = line
				line = word
			else
				line = try
			end
		end
		lines[#lines + 1] = line
	end
	return lines
end

-- A text at its size, or smaller until it fits `width`.
local function fitted(kit, text, width, opts, least)
	local o = {}
	for k, v in pairs(opts) do o[k] = v end
	while o.size > (least or 16) and kit:measure(text, o) > width do o.size = o.size - 2 end
	return o
end

-- What a card says, and the total it leads to: "Total: x" on its last line.
function M.split(text)
	local body, now = text:match("^(.-)\nTotal: (.+)$")
	if body then return body, now end
	return text, nil
end

-- A row of pips, one for each rank: what's owned, the one this card adds, and what's left.
local function pips(kit, cx, y, u, owned, color)
	local n = u.max or 0
	if n < 2 then return end
	local have, size, gap = owned[u.id] or 0, 18, 8
	local x = cx - (n * size + (n - 1) * gap) / 2
	for i = 1, n do
		local c = (i <= have and INK) or (i == have + 1 and color) or PIP
		kit:rect(x, y, size, size, c)
		x = x + size + gap
	end
end

-- An upgrade's badge.
local function badge(kit, u, cx, cy, r, color)
	art.badge(kit, u, cx, cy, r, color, HEX, INK)
end

-- The partner icons (src/evolve.lua's hints), each inside a thin ring of the Evolution color. A tall
-- card's sit to the right of its badge, halfway between the badge and the card's edge, in a column
-- centred on the badge's height. A wide card's text fills the space right of its badge, so there they
-- go along the bottom from the right edge leftward, on the row of the rarity's name. Answers the width
-- they take from that row: none on a tall card.
M.HINT_R = { tall = 24.5, wide = 21.6 }
M.HINT_GAP = 8
M.HINT_EDGE = 12
M.RARITY_BAR = 44
M.BADGE_R = 58 -- a tall card's badge
M.BADGE_DROP = 122 -- the badge's centre under the card's top
function M.hint_spots(r, count)
	local rad = r.wide and M.HINT_R.wide or M.HINT_R.tall
	local out = {}
	if not r.wide then
		local cx = r.x + r.w / 2
		local edge = cx + art.badge_height(M.BADGE_R) / 2
		local x = (edge + r.x + r.w) / 2
		local cy = r.y + r.h - M.BADGE_DROP
		local column = count * rad * 2 + (count - 1) * M.HINT_GAP
		for i = 1, count do out[i] = { x = x, y = cy + column / 2 - rad - (i - 1) * (rad * 2 + M.HINT_GAP), r = rad } end
		return out, 0
	end
	local cy = r.y + 4 + rad
	for i = 1, count do out[i] = { x = r.x + r.w - M.HINT_EDGE - rad - (i - 1) * (rad * 2 + M.HINT_GAP), y = cy, r = rad } end
	return out, count > 0 and count * rad * 2 + (count - 1) * M.HINT_GAP + M.HINT_EDGE or 0
end

local function draw_hints(kit, r, list)
	if not list or #list == 0 then return end
	local ring = M.rarity_color("evolution")
	for i, at in ipairs((M.hint_spots(r, #list))) do
		local u = list[i]
		if art.has("ring") and art.has("icon_" .. u.id) then
			art.center(kit, "glow", at.x, at.y, at.r * 2.6, "#00000080")
			art.center(kit, "ring", at.x, at.y, at.r * 2, ring)
			art.center(kit, "icon_" .. u.id, at.x, at.y, at.r * 1.2, INK)
		else
			kit:hex(at.x, at.y, at.r, ring)
			kit:hex(at.x, at.y, at.r * 0.85, HEX, u.icon)
		end
	end
end

local function tall_card(kit, r, u, owned, color, body, now, hint_w)
	local top, cx = r.y + r.h, r.x + r.w / 2
	-- The rarity's bar, as a player's name bar: its color fading out, white text on it.
	native.bar(kit, r.x, top - M.RARITY_BAR, r.w, M.RARITY_BAR, M.bar_color(u.rarity))
	local rarity = u.rarity:upper()
	native.text(kit, rarity, r.x + 16, top - 32, fitted(kit, rarity, r.w - 32 - (hint_w or 0), { font = "body_large", size = 24, tracking = 2, color = INK }, 16))
	local iy = top - M.BADGE_DROP
	art.center(kit, "glow", cx, iy, 240, color .. "60")
	badge(kit, u, cx, iy, M.BADGE_R, color)
	local title = u.name:upper()
	native.text(kit, title, cx, top - 236, fitted(kit, title, r.w - 28, { font = "body_large", size = 28, tracking = 1, align = "center", color = INK }, 20))
	native.rule(kit, cx, top - 256, r.w - 50, 3, DIM)
	local opts = { font = "body_large", size = 24, align = "center", color = BODY }
	local lines = M.wrap(kit, body, r.w - 36, opts)
	for _, size in ipairs({ 22, 20 }) do
		if #lines <= 3 then break end
		opts.size = size
		lines = M.wrap(kit, body, r.w - 36, opts)
	end
	for i, line in ipairs(lines) do kit:text(line, cx, top - 296 - (i - 1) * (opts.size + 8), opts) end
	pips(kit, cx, r.y + 50, u, owned, color)
	if now then
		native.text(kit, now, cx, r.y + 16, fitted(kit, now, r.w - 32, { font = "body_large", size = 24, align = "center", color = color }, 16))
	end
end

local function wide_card(kit, r, u, owned, color, body, now, hint_w)
	local top = r.y + r.h
	native.bar(kit, r.x, r.y, 220, r.h, color .. "50")
	-- The badge takes the card's height above the rarity's name, the biggest frame included.
	local radius = math.min(66, (r.h - 44) / art.badge_height(1))
	local cx, cy = r.x + 24 + 78, r.y + 36 + (r.h - 36) / 2
	badge(kit, u, cx, cy, radius, color)
	native.text(kit, u.rarity:upper(), cx, r.y + 12, { font = "body_large", size = 20, tracking = 2, align = "center", color = color })
	local tx, tw = r.x + 200, r.w - 222
	local title = u.name:upper()
	native.text(kit, title, tx, top - 50, fitted(kit, title, tw, { font = "body_large", size = 27, tracking = 1, color = INK }, 18))
	local opts = { font = "body_large", size = 24, color = BODY }
	local lines = M.wrap(kit, body, tw, opts)
	if #lines > 3 or r.h < 170 then
		opts.size = 20
		lines = M.wrap(kit, body, tw, opts)
	end
	for i, line in ipairs(lines) do kit:text(line, tx, top - 86 - (i - 1) * (opts.size + 6), opts) end
	if now and r.h >= 170 then
		native.text(kit, now, tx, r.y + 18, fitted(kit, now, tw - (hint_w or 0), { font = "body_large", size = 26, color = color }, 16))
	end
end

-- One card. `state`: "idle", "cursor" (hovered, in white) or "chosen" (pressed, in yellow).
-- t: seconds, for the hovered card's pulse. hints: the upgrades whose icons go in the corner
-- (src/evolve.lua's hints), or nil.
function M.card(kit, r, u, owned, state, t, hints)
	local color = M.rarity_color(u.rarity)
	local body, now = M.split(u.text((owned[u.id] or 0) + 1))
	local z = kit:layer()
	if state == "cursor" then
		local pulse = 0.5 + 0.5 * math.sin((t or 0) * 5)
		art.center(kit, "glow_soft", r.x + r.w / 2, r.y + r.h / 2, math.max(r.w, r.h) * (1.5 + 0.08 * pulse), string.format("#ffffff%02x", math.floor(10 + 14 * pulse)))
		local grow = 8 + 6 * pulse
		kit:panel({ r.x - grow, r.y - grow, r.w + grow * 2, r.h + grow * 2, line = string.format("#ffffff%02x", math.floor(110 + 145 * pulse)), line_width = 3 })
		native.box(kit, r.x, r.y, r.w, r.h, { thick = 6, line = INK, tint = CARD_BOX.tint })
	elseif state == "chosen" then
		native.box(kit, r.x, r.y, r.w, r.h, { thick = 6, line = YELLOW, tint = CARD_BOX.tint })
	else
		native.box(kit, r.x, r.y, r.w, r.h, CARD_BOX)
	end
	local _, hint_w = M.hint_spots(r, hints and #hints or 0)
	if r.wide then wide_card(kit, r, u, owned, color, body, now, hint_w) else tall_card(kit, r, u, owned, color, body, now, hint_w) end
	draw_hints(kit, r, hints)
	kit:layer(z)
end

-- One stratagem to pick: its icon in a square box.
local function strat_card(kit, r, s, state)
	if state == "cursor" then
		kit:panel({ r.x - 6, r.y - 6, r.w + 12, r.h + 12, line = INK, line_width = 2 })
	end
	native.box(kit, r.x, r.y, r.w, r.h, state == "idle" and CARD_BOX or { thick = 4, line = state == "chosen" and YELLOW or INK, tint = CARD_BOX.tint })
	local size = r.h - 20
	kit:icon(s.icon, r.x + 10, r.y + 10, size, size)
end

-- A key as the game draws one: its key cap is a character of its font, with the letter over it, as big
-- as fits (HdGui.text). M.keycap holds that character once src/run.lua has read it from the game; a
-- group marked `plain` holds a pad's buttons, whole characters of the font already.
local GLYPH_SIZE = 32

local function key_width(kit, text, plain)
	return kit:measure(M.keycap and not plain and M.keycap or text, { font = "body_large", size = GLYPH_SIZE })
end

local function draw_key(kit, text, x, y, plain, color)
	color = color or INK
	local opts = { font = "body_large", size = GLYPH_SIZE, color = color }
	if plain then
		kit:text(text, x, y, opts)
		return
	end
	if not M.keycap then
		native.text(kit, text, x, y, opts)
		return
	end
	kit:text(M.keycap, x, y, opts)
	local width = kit:measure(M.keycap, opts)
	local inner = { font = "body_large", size = GLYPH_SIZE * 0.72, color = color }
	while inner.size > 10 and kit:measure(text, inner) > width - 10 do inner.size = inner.size * 0.9 end
	local z = kit:layer()
	kit:layer(z + 1)
	kit:text(text, x + (width - kit:measure(text, inner)) / 2, y + (GLYPH_SIZE - inner.size) * 0.36, inner)
	kit:layer(z)
end

-- Where each group of a row of buttons (M.glyphs) is drawn, for the mouse: { x, y, w, h } each, its keys
-- and its label, a little taller than the text.
function M.glyph_rects(kit, cx, y, groups)
	local label = { font = "body_large", size = GLYPH_SIZE, color = INK }
	local gap, after, group_gap = 6, 12, 40
	local widths, total = {}, 0
	for g, group in ipairs(groups) do
		local w = 0
		for _, text in ipairs(group.keys) do w = w + key_width(kit, text, group.plain) + gap end
		w = w + after + kit:measure(group.label, label)
		widths[g] = w
		total = total + w + (g < #groups and group_gap or 0)
	end
	local out, x = {}, cx - total / 2
	for g, w in ipairs(widths) do
		out[g] = { x = x - 8, y = y - 12, w = w + 16, h = GLYPH_SIZE + 16 }
		x = x + w + group_gap
	end
	return out
end

-- A row of buttons and what they do, centred on a point. groups: { { keys = { text }, label, plain, dim, hover } };
-- a dim group (nothing left to use) is drawn grey.
function M.glyphs(kit, cx, y, groups)
	local label = { font = "body_large", size = GLYPH_SIZE, color = INK }
	local gap, after, group_gap = 6, 12, 40
	local total = 0
	for g, group in ipairs(groups) do
		for _, text in ipairs(group.keys) do total = total + key_width(kit, text, group.plain) + gap end
		total = total + after + kit:measure(group.label, label) + (g < #groups and group_gap or 0)
	end
	local x = cx - total / 2
	for _, group in ipairs(groups) do
		-- Under the mouse, a group that can be used is drawn in yellow.
		local color = group.dim and DIM or (group.hover and YELLOW) or INK
		for _, text in ipairs(group.keys) do
			draw_key(kit, text, x, y, group.plain, color)
			x = x + key_width(kit, text, group.plain) + gap
		end
		x = x + after
		native.text(kit, group.label, x, y, { font = "body_large", size = GLYPH_SIZE, color = color })
		x = x + kit:measure(group.label, label) + group_gap
	end
end

-- The sign between a name and the count: the multiplication sign when the game's font has it, an x
-- when it doesn't.
local TIMES = "\195\151"
function M.times(kit, opts)
	local ok, w = pcall(kit.measure, kit, TIMES, opts or { font = "body_large", size = GLYPH_SIZE })
	return (ok and type(w) == "number" and w > 0) and TIMES or "x"
end

-- "REROLL ×2": a name and a count.
function M.count_label(kit, name, n, opts)
	return name .. " " .. M.times(kit, opts) .. tostring(math.max(0, math.floor(n or 0)))
end

-- The reroll and banish prompts: tools = { { keys, plain, name, count, usable } }, grey when they can't
-- be used now.
function M.tool_groups(kit, tools)
	local out = {}
	for i, t in ipairs(tools or {}) do
		out[i] = { keys = t.keys, plain = t.plain, label = M.count_label(kit, t.name, t.count), dim = not t.usable }
	end
	return out
end

local function hex2(a) return string.format("%02x", math.floor(math.max(0, math.min(a, 1)) * 255 + 0.5)) end

-- The kit's opacity at `a` of the screen's own.
local function fade(kit, base, a)
	kit:opacity(base * math.max(0, math.min(a or 1, 1)))
end

local function moved(r, dy)
	if not dy or dy == 0 then return r end
	local out = {}
	for k, v in pairs(r) do out[k] = v end
	out.y = r.y + dy
	return out
end

-- view: { players = { { name, show_name, color, row = { upgrades }, owned = { [id] = n }, cursor, chosen,
-- strats = { { id, name, icon } }, strat_cursor, strat_pick, focus, time_left (0 to 1), seconds_left, controls,
-- tools (M.tool_groups), fx = { [i] = { alpha, dy, bright } }, extras (0 to 1), leaving = { { u, slot, alpha, dy } } } },
-- waiting, alpha (the whole screen, 0 to 1), backdrop (0 to 1) }. The motion's numbers come from src/card_anim.lua.
function M.draw(kit, view)
	local was = kit:opacity() or 1
	local base = view.alpha or 1
	kit:layer(M.LAYER)
	-- Wider than the design space, for screens wider than 16:9.
	fade(kit, base, view.backdrop or 1)
	kit:rect(-M.W, -M.H, M.W * 3, M.H * 3, "#000000b0")
	for n, p in ipairs(view.players) do
		local spot = M.layout(#view.players, #p.row, p.strats and #p.strats or 0, p.show_name)[n]
		local head = p.fx and p.fx[1] and p.fx[1].alpha or 1
		kit:layer(M.LAYER + 1)
		fade(kit, base, math.max(head, view.waiting and 1 or 0))
		-- Alone, whose cards these are goes without saying. show_name: one of several players on this
		-- machine, choosing in turn.
		if #view.players > 1 or p.show_name then
			native.bar(kit, spot.title.x - 200, spot.title.y - 14, 400, 38, p.color or YELLOW)
			native.text(kit, p.name or ("PLAYER " .. n), spot.title.x - 186, spot.title.y - 2, { font = "body_large", size = 26, color = INK })
		end
		local t = spot.timer
		if view.waiting then
			native.text(kit, "WAITING FOR THE SQUAD", spot.title.x, t.y - 8, { font = "body_large", size = 26, tracking = 2, align = "center", color = BODY })
		else
			kit:rect(t.x, t.y, t.w, t.h, "#000000b0")
			local flash = (p.seconds_left or math.huge) < rules.CHOOSE_WARNING and math.sin((view.t or 0) * 12) > 0
			kit:rect(t.x + 2, t.y + 2, (t.w - 4) * math.max(math.min(p.time_left or 0, 1), 0), t.h - 4, flash and "#e8532f" or YELLOW)
		end
		-- A banished card on the way out, grey, under the card drawn instead.
		for _, l in ipairs(p.leaving or {}) do
			local r = spot.cards[l.slot]
			if r and (l.alpha or 0) > 0 then
				local at = moved(r, l.dy)
				kit:layer(M.LAYER + 1)
				fade(kit, base, l.alpha)
				M.card(kit, at, l.u, p.owned or {}, "idle", view.t)
				kit:layer(M.LAYER + 4)
				kit:rect(at.x, at.y, at.w, at.h, "#1a1a18a8")
			end
		end
		local stratagems = p.strats ~= nil
		for i, u in ipairs(p.row) do
			local fx = p.fx and p.fx[i] or {}
			if (fx.alpha or 1) > 0 then
				local chosen = p.chosen == u.id
				local state = (chosen and "chosen") or (p.cursor == i and (not stratagems or p.focus == "cards") and "cursor") or "idle"
				local r = moved(spot.cards[i], fx.dy)
				kit:layer(M.LAYER + 1 + (state == "cursor" and 1 or 0))
				fade(kit, base, fx.alpha)
				-- A pick brightens the chosen card for a moment: a glow behind it and a white wash over it.
				local bright = fx.bright or 0
				if bright > 0 then
					art.center(kit, "glow_soft", r.x + r.w / 2, r.y + r.h / 2, math.max(r.w, r.h) * 1.7, "#ffe9a0" .. hex2(0.35 * bright))
				end
				M.card(kit, r, u, p.owned or {}, state, view.t, evolve.hints(u, p.owned or {}, p.absorbed))
				if bright > 0 then
					kit:layer(M.LAYER + 4)
					kit:rect(r.x, r.y, r.w, r.h, "#ffffff" .. hex2(0.18 * bright))
				end
			end
		end
		kit:layer(M.LAYER + 1)
		fade(kit, base, p.extras or 1)
		if stratagems then
			for i, s in ipairs(p.strats) do
				local state = (p.strat_pick == s.id and "chosen") or (p.focus == "strats" and p.strat_cursor == i and "cursor") or "idle"
				strat_card(kit, spot.strats[i], s, state)
			end
		end
		if p.tools and #p.tools > 0 and spot.tools then M.glyphs(kit, spot.tools.x, spot.tools.y, p.tools) end
		if p.controls then M.glyphs(kit, spot.title.x, spot.hint_y, p.controls) end
	end
	kit:opacity(was)
end

-- A player's rerolls and banishes, small, on a strip of the HUD card's panel with the bottom at y, from
-- x, w wide: over the upgrades' panel while the map is open. size: the text's height; unit as in
-- owned_panel. Answers the strip's height.
function M.tools_strip(kit, x, y, w, rerolls, banishes, size, unit)
	local h = size * 1.8
	kit:layer(M.LAYER - 5)
	native.panel(kit, x, y, w, h, { unit = unit })
	local z = kit:layer()
	kit:layer(z + 1)
	local opts = { font = "body_large", size = size, color = INK }
	local text_y = y + (h - size * 0.7) / 2
	local half = w / 2
	for i, item in ipairs({ { "REROLL", rerolls }, { "BANISH", banishes } }) do
		local o = { font = "body_large", size = size, align = "center", color = (item[2] or 0) > 0 and INK or DIM }
		native.text(kit, M.count_label(kit, item[1], item[2], opts), x + half * (i - 0.5), text_y, o)
	end
	kit:layer(z)
	return h
end
-- The upgrades a player has, over their HUD card while their map is open: badges only, four to a row,
-- grouped by rarity (evolution, legendary, perk, rare, common), each with its stacks in the badge's top right
-- corner when it can stack.
-- Plain numbers, so it can be tested. owned: { [id] = n }; catalog: src/upgrades. w: the card's width.
M.PANEL_COLUMNS = 4
M.PANEL_ORDER = { "evolution", "legendary", "perk", "rare", "common" }

function M.owned_groups(owned, catalog)
	local by = {}
	for id, n in pairs(owned) do
		local u = catalog.by_id[id]
		if u and n > 0 then
			by[u.rarity] = by[u.rarity] or {}
			table.insert(by[u.rarity], { u = u, n = n })
		end
	end
	local out = {}
	for _, rarity in ipairs(M.PANEL_ORDER) do
		local list = by[rarity]
		if list then
			table.sort(list, function(a, b) return a.u.name < b.u.name end)
			out[#out + 1] = list
		end
	end
	return out
end

-- Whether an upgrade shows a count of stacks: one that can be taken more than once.
local function stacks(u) return u.max == nil or u.max > 1 end

-- The stack count's size and place on a badge of radius r centred on cx, cy: a small number whose
-- right edge and top sit on the corner of the badge's frame. Answers the text's right x, its baseline
-- y (text stands on its baseline, its figures about 0.7 of its size tall) and its size.
M.COUNT_SIZE = 0.62 -- of r
function M.count_spot(cx, cy, r)
	local size = math.max(10, math.floor(r * M.COUNT_SIZE))
	local edge = r * 1.065 -- half a common or rare frame's side (art.badge's r * 2.13)
	return cx + edge + size * 0.1, cy + edge - size * 0.7, size
end

-- A stack count with a faint shadow, right-aligned on x.
local function count_text(kit, n, x, y, size)
	local text = tostring(n)
	local d = math.max(1, size / 12)
	kit:text(text, x + d, y - d, { font = "body_large", size = size, align = "right", color = "#00000070" })
	kit:text(text, x, y, { font = "body_large", size = size, align = "right", color = INK })
end

-- The panel's badges: r against the width of a column. A square or circle frame is r * 2.13 across, so
-- the gap between two is what's left of the column; a diamond is 1.15 times bigger and still clears
-- the next one. PANEL_EDGE, of a column, is a margin inside the panel's frame on every side, on top of
-- the half gap round each badge.
M.PANEL_BADGE = 0.36
M.PANEL_EDGE = 0.12

-- Where the panel's badges go, from x, w wide, the panel's top at `top`: each row a column's gap taller
-- than the frames in the row, the badges centred in it, and half a gap more between two groups, all
-- inside a margin of PANEL_EDGE. Answers r, the rows ({ items, cy }) and the height.
function M.owned_layout(groups, x, top, w)
	local edge = w / M.PANEL_COLUMNS * M.PANEL_EDGE
	local cell = (w - 2 * edge) / M.PANEL_COLUMNS
	local r = cell * M.PANEL_BADGE
	local gap = cell - r * 2.13
	local rows, y = {}, top - edge
	for g, list in ipairs(groups) do
		local frame = art.FRAMES[list[1].u.rarity] or art.FRAMES.common
		local height = r * 2.13 * frame[4] + gap
		for i = 1, #list, M.PANEL_COLUMNS do
			if i == 1 and g > 1 then y = y - gap / 2 end
			local row = { items = {}, cy = y - height / 2 }
			for k = i, math.min(i + M.PANEL_COLUMNS - 1, #list) do
				local c = k - i
				row.items[c + 1] = { u = list[k].u, n = list[k].n, cx = x + edge + (c + 0.5) * cell }
			end
			rows[#rows + 1] = row
			y = y - height
		end
	end
	return r, rows, top - y + edge
end

-- The thin link markers under a badge of radius r centred on cx, cy: one bar of each pair's link color
-- (src/evolve.lua's links), side by side, just under the frame. A list of { x, y, w, h, color }.
M.LINK_W = 1.3 -- of r, all the bars together
M.LINK_H = 0.12
M.LINK_GAP = 0.16 -- under the frame
function M.link_marks(u, cx, cy, r, colors)
	local out = {}
	if not colors or #colors == 0 then return out end
	local frame = art.FRAMES[u.rarity] or art.FRAMES.common
	local h = math.max(2, r * M.LINK_H)
	local y = cy - r * 1.065 * frame[4] - r * M.LINK_GAP - h
	local gap = #colors > 1 and r * 0.12 or 0
	local each = (r * M.LINK_W - gap * (#colors - 1)) / #colors
	local x = cx - r * M.LINK_W / 2
	for i, color in ipairs(colors) do
		out[i] = { x = x, y = y, w = each, h = h, color = color }
		x = x + each + gap
	end
	return out
end

-- Draws the panel with the bottom at y, from x, w wide, rising by `shown` (0 to 1) as the map opens.
-- The panel is drawn like the HUD card (native.panel), so with the card's x and width it lines up with
-- the card's edges. unit: how many of the kit's units make one of the HUD's. Answers the height.
function M.owned_panel(kit, x, y, w, owned, catalog, shown, unit)
	local groups = M.owned_groups(owned, catalog)
	if #groups == 0 then return 0 end
	local _, _, h = M.owned_layout(groups, x, 0, w)
	shown = math.max(0, math.min(shown or 1, 1))
	local bottom = y - h * (1 - shown)
	local r, rows = M.owned_layout(groups, x, bottom + h, w)
	kit:layer(M.LAYER - 5)
	native.panel(kit, x, bottom, w, h, { unit = unit })
	local z = kit:layer()
	local links = evolve.links(owned)
	for _, row in ipairs(rows) do
		for _, item in ipairs(row.items) do
			kit:layer(z)
			art.badge(kit, item.u, item.cx, row.cy, r, M.rarity_color(item.u.rarity), HEX, INK)
			for _, mark in ipairs(M.link_marks(item.u, item.cx, row.cy, r, links[item.u.id])) do kit:rect(mark.x, mark.y, mark.w, mark.h, mark.color) end
			if stacks(item.u) then
				kit:layer(z + 1)
				count_text(kit, item.n, M.count_spot(item.cx, row.cy, r))
			end
		end
	end
	kit:layer(z)
	return h
end

-- The stat box's look: the HUD card's own panel (native.panel), the numbers in white and the icons in
-- the light grey of the HUD card's loadout icons.
M.STAT_ICON = "#c8c8c8"

-- What the stat box says: health as current / maximum, then the armor. nil numbers are left out.
function M.stat_parts(health, max_health, armor)
	local function whole(v) return tostring(math.floor(v + 0.5)) end
	local out = {}
	if max_health then
		out[#out + 1] = { icon = "mark_stat_health", text = health and (whole(health) .. " / " .. whole(max_health)) or whole(max_health) }
	end
	if armor then out[#out + 1] = { icon = "mark_stat_armor", text = whole(armor) } end
	return out
end

-- Where the stat box and what's in it go: the box's left edge at `left` and the bottom at y, each icon
-- centred on the box's middle and each number's figures centred on the same line. size: the numbers'
-- height. Answers { x, y, w, h, items = { { icon, text, icon_x (centre), icon_y, size (the icon's),
-- text_x, text_y } } }, or nil with nothing to show.
function M.stat_layout(kit, left, y, size, parts)
	if #parts == 0 then return nil end
	local opts = { font = "body_large", size = size }
	local pad, icon, gap, between = size * 0.55, size * 1.15, size * 0.3, size * 0.8
	local h = size * 1.75
	local mid = y + h / 2
	local items, x = {}, left + pad
	for i, p in ipairs(parts) do
		local tw = kit:measure(p.text, opts)
		items[i] = { icon = p.icon, text = p.text, icon_x = x + icon / 2, icon_y = mid, size = icon, text_x = x + icon + gap, text_y = mid - size * 0.35 }
		x = x + icon + gap + tw + (i < #parts and between or 0)
	end
	return { x = left, y = y, w = x + pad - left, h = h, items = items }
end

-- A player's health (current / maximum) and armor on a panel like the HUD card's, the left edge at
-- `left` and the bottom at y: each an icon and a number. size: the numbers' height. unit: how many of
-- the kit's units make one of the HUD's, for the panel's frame. nil numbers are left out. Answers the
-- box ({ x, y, w, h }), or nil.
function M.stat_line(kit, left, y, size, health, max_health, armor, unit)
	local L = M.stat_layout(kit, left, y, size, M.stat_parts(health, max_health, armor))
	if not L then return nil end
	native.panel(kit, L.x, L.y, L.w, L.h, { unit = unit })
	local opts = { font = "body_large", size = size, color = INK }
	for _, item in ipairs(L.items) do
		if art.center(kit, item.icon, item.icon_x, item.icon_y, item.size, M.STAT_ICON) == false then
			-- Without the art, a plain square in the icon's place.
			kit:rect(item.icon_x - item.size * 0.3, item.icon_y - item.size * 0.3, item.size * 0.6, item.size * 0.6, M.STAT_ICON)
		end
		native.text(kit, item.text, item.text_x, item.text_y, opts)
	end
	return L
end

return M
