-- The end-of-run summary on screen, in the look of the level-up cards (src/cards.lua): the darkened
-- screen, the result with the game's chrome wings, the run's numbers under it, and a column for each
-- player with their name bar, their numbers and their top damage sources. Under the columns, the bar of
-- the time left. Drawn with a kit from obsidian.ui in the 1920x1080 design space, y going up. The layout
-- is plain numbers, so it can be tested.
local art = obsidian.module("src/art")
local native = obsidian.module("src/native")
local cards = obsidian.module("src/cards")
local summary = obsidian.module("src/summary")

local M = {}

M.W, M.H = 1920, 1080
M.LAYER = cards.LAYER
local INK, BODY, DIM, GOLD = native.WHITE, native.TEXT, native.GREY, native.GOLD
local RED = "#e8532f"
local HEX = "#232321"

M.TITLES = { extracted = "EXTRACTED", defeated = "DEFEATED" }

-- The numbers in a column, in order. `optional` rows show only when a player has some.
M.STATS = {
	{ key = "kills", label = "KILLS" },
	{ key = "damage", label = "DAMAGE" },
	{ key = "samples", label = "SAMPLES" },
	{ key = "downs", label = "TIMES DOWNED" },
	{ key = "deaths", label = "DEATHS" },
	{ key = "saves", label = "DEMOCRACY PROTECTS SAVES", optional = true },
}

-- Where things go. Columns side by side in the middle, as wide as fits up to 440 (560 alone).
M.TOP, M.BOTTOM = 830, 130
M.ROW = 36 -- a number's row
M.SOURCE_ROW = 60
function M.layout(players)
	players = math.max(1, players)
	local gap, margin = 30, 60
	local w = players == 1 and 560 or math.min(440, math.floor((M.W - 2 * margin - (players - 1) * gap) / players))
	local total = players * w + (players - 1) * gap
	local x0 = (M.W - total) / 2
	local out = { title = { x = M.W / 2, y = 966 }, header = { label_y = 906, value_y = 866 }, timer = { x = 510, y = 96, w = 900, h = 12 }, wait_y = 50, columns = {} }
	for i = 1, players do
		out.columns[i] = { x = x0 + (i - 1) * (w + gap), y = M.BOTTOM, w = w, h = M.TOP - M.BOTTOM }
	end
	return out
end

-- Inside a column: the name bar, the baseline of each number's row, the rule, the sources' heading and
-- the top of each source's row, and the prompt's baseline.
function M.column_parts(c, rows, sources)
	local top = c.y + c.h
	local out = { name = { x = c.x, y = top - 48, w = c.w, h = 40 }, rows = {}, sources = {} }
	for i = 1, rows do out.rows[i] = top - 92 - (i - 1) * M.ROW end
	local last = out.rows[rows] or top - 92
	out.rule = last - 22
	out.heading = out.rule - 34
	for i = 1, sources do out.sources[i] = out.heading - 16 - (i - 1) * M.SOURCE_ROW end
	out.prompt = c.y + 20
	return out
end

-- The rows to show for these players: every row that isn't optional, and an optional one somebody has.
function M.rows_for(players)
	local out = {}
	for _, row in ipairs(M.STATS) do
		local show = not row.optional
		for _, p in ipairs(players) do
			if row.optional and p.stats and (p.stats[row.key] or 0) > 0 then show = true end
		end
		if show then out[#out + 1] = row end
	end
	return out
end

-- A whole number with commas: 12,345.
function M.number(n)
	local s = tostring(math.floor((tonumber(n) or 0) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function M.clock(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- The share of a total as a percent, "38%". Under 1% shows as "<1%".
function M.percent(part, total)
	if not (total and total > 0) then return "0%" end
	local p = part / total * 100
	if p > 0 and p < 1 then return "<1%" end
	return string.format("%d%%", math.floor(p + 0.5))
end

-- What the run's header says: { label, value }. The bosses only when one was killed.
function M.header(view)
	local out = {
		{ label = "TIME SURVIVED", value = M.clock(view.time) },
		{ label = "LEVEL", value = tostring(view.level or 1) },
	}
	if view.factions and #view.factions > 0 then out[#out + 1] = { label = view.factions[2] and "FACTIONS" or "FACTION", value = table.concat(view.factions, ", ") } end
	if (view.bosses or 0) > 0 then out[#out + 1] = { label = "BOSSES KILLED", value = tostring(view.bosses) } end
	return out
end

-- How a source looks: { name, upgrade (for an upgrade's badge), icon (a game icon), art (the mod's
-- image) }. deps: { by_id (src/upgrades.lua's), text = fn(key) for a game name or nil, stratagem_icon =
-- fn(name) or nil }.
local PLAIN = {
	primary = { name = "PRIMARY WEAPON", art = "icon_higher_calibre" },
	sidearm = { name = "SIDEARM", art = "icon_gunslinger" },
	support = { name = "SUPPORT WEAPON", art = "icon_extended_mag" },
	grenade = { name = "GRENADES", art = "icon_deep_pockets" },
	melee = { name = "MELEE", art = "icon_peak_physique" },
	stratagems = { name = "STRATAGEMS", art = "icon_arsenal_support" },
}

function M.source_look(key, deps)
	deps = deps or {}
	local kind, id = key:match("^(%w+):(.*)$")
	kind = kind or key
	if kind == "u" then
		local u = deps.by_id and deps.by_id[id]
		return { name = u and u.name:upper() or id:upper(), upgrade = u }
	end
	local base = PLAIN[kind] or PLAIN.stratagems
	local out = { name = base.name, art = base.art }
	if id and id ~= "" then
		local text = deps.text and deps.text(id)
		if type(text) == "string" and text ~= "" and text ~= id then out.name = text:upper() end
		if kind == "support" and deps.stratagem_icon then out.icon = deps.stratagem_icon(id) end
	end
	return out
end

-- A text at the given size, or smaller until it fits `width`.
local function fitted(kit, text, width, opts, least)
	local o = {}
	for k, v in pairs(opts) do o[k] = v end
	while o.size > (least or 14) and kit:measure(text, o) > width do o.size = o.size - 2 end
	return o
end

-- A source's picture centred on cx, cy, `size` across: an upgrade's badge, or the weapon's or kind's
-- icon in white without a frame, so the upgrades stand out.
local function source_icon(kit, look, cx, cy, size)
	if look.upgrade then
		art.badge(kit, look.upgrade, cx, cy, size / 2.4, cards.rarity_color(look.upgrade.rarity), HEX, INK)
		return
	end
	if look.icon and kit:icon(look.icon, cx - size / 2, cy - size / 2, size, size) then return end
	if look.art and art.center(kit, look.art, cx, cy, size * 0.85, INK) ~= false then return end
	kit:hex(cx, cy, size * 0.4, DIM)
end

local function draw_header(kit, L, view)
	local t = L.title
	local title = M.TITLES[view.kind] or M.TITLES.defeated
	local opts = { font = "body_large", size = 60, tracking = 3, align = "center", color = view.kind == "extracted" and GOLD or RED }
	native.text(kit, title, t.x, t.y, opts)
	native.wings(kit, t.x, t.y - 6, kit:measure(title, opts) / 2 + 30, 48)
	local items = M.header(view)
	local label = { font = "body_large", size = 20, tracking = 2, color = DIM }
	local value = { font = "body_large", size = 30, tracking = 1, color = INK }
	local widths, total, gap = {}, 0, 80
	for i, item in ipairs(items) do
		widths[i] = math.max(kit:measure(item.label, label), kit:measure(item.value, value))
		total = total + widths[i] + (i > 1 and gap or 0)
	end
	local x = M.W / 2 - total / 2
	for i, item in ipairs(items) do
		local cx = x + widths[i] / 2
		native.text(kit, item.label, cx, L.header.label_y, { font = label.font, size = label.size, tracking = label.tracking, color = label.color, align = "center" })
		native.text(kit, item.value, cx, L.header.value_y, { font = value.font, size = value.size, tracking = value.tracking, color = value.color, align = "center" })
		x = x + widths[i] + gap
	end
end

local function draw_column(kit, c, p, rows, deps, t)
	local tops = summary.TOP
	local list = p.sources or {}
	local parts = M.column_parts(c, #rows, math.min(#list, tops))
	native.box(kit, c.x, c.y, c.w, c.h, { thick = 0, tint = "#ffffffe6" })
	local z = kit:layer()
	-- The player's name on a bar of their color, as the HUD's cards show it; after an extraction, whether
	-- they made it on the right.
	local nb = parts.name
	native.bar(kit, nb.x, nb.y, nb.w, nb.h, p.color or GOLD)
	kit:layer(z + 2)
	local status
	if p.extracted == true then status = { "EXTRACTED", GOLD } elseif p.extracted == false then status = { "LEFT BEHIND", BODY } end
	local status_w = status and kit:measure(status[1], { font = "body_large", size = 20, tracking = 1 }) + 24 or 0
	local name = p.name or ("PLAYER " .. tostring(p.slot))
	native.text(kit, name, nb.x + 16, nb.y + 11, fitted(kit, name, nb.w - 32 - status_w, { font = "body_large", size = 26, color = INK }, 16))
	if status then native.text(kit, status[1], nb.x + nb.w - 16, nb.y + 12, { font = "body_large", size = 20, tracking = 1, align = "right", color = status[2] }) end
	-- The numbers.
	local stats = p.stats or {}
	for i, row in ipairs(rows) do
		local y = parts.rows[i]
		local value = p.stats and M.number(stats[row.key]) or "-"
		local value_opts = { font = "body_large", size = 24, align = "right", color = INK }
		local vw = kit:measure(value, value_opts)
		native.text(kit, row.label, c.x + 20, y, fitted(kit, row.label, c.w - 52 - vw, { font = "body_large", size = 22, tracking = 1, color = BODY }, 14))
		native.text(kit, value, c.x + c.w - 20, y, value_opts)
	end
	native.rule(kit, c.x + c.w / 2, parts.rule, c.w - 40, 3, DIM)
	native.text(kit, "TOP DAMAGE", c.x + 20, parts.heading, { font = "body_large", size = 20, tracking = 2, color = DIM })
	-- The sources: picture, name and damage, and a bar of the share of the player's damage.
	local total = stats.damage or 0
	for i, top in ipairs(parts.sources) do
		local e = list[i]
		local look = M.source_look(e.key, deps)
		kit:layer(z + 1)
		source_icon(kit, look, c.x + 44, top - 26, 44)
		kit:layer(z + 2)
		local dmg = M.number(e.damage)
		local dmg_opts = { font = "body_large", size = 22, align = "right", color = INK }
		local dw = kit:measure(dmg, dmg_opts)
		native.text(kit, look.name, c.x + 80, top - 26, fitted(kit, look.name, c.w - 80 - 20 - dw - 14, { font = "body_large", size = 22, color = INK }, 14))
		native.text(kit, dmg, c.x + c.w - 20, top - 26, dmg_opts)
		local share = total > 0 and math.min(e.damage / total, 1) or 0
		local track_w = c.w - 80 - 20 - 64
		kit:rect(c.x + 80, top - 48, track_w, 8, "#000000b0")
		kit:rect(c.x + 81, top - 47, (track_w - 2) * share, 6, look.upgrade and cards.rarity_color(look.upgrade.rarity) or GOLD)
		native.text(kit, M.percent(e.damage, total), c.x + c.w - 20, top - 52, { font = "body_large", size = 18, align = "right", color = BODY })
	end
	kit:layer(z + 2)
	-- Who has confirmed. A player of this machine who hasn't sees the button for it.
	local cx = c.x + c.w / 2
	if p.ready then
		native.text(kit, "READY", cx, parts.prompt, { font = "body_large", size = 26, tracking = 2, align = "center", color = GOLD })
	elseif p.controls then
		cards.glyphs(kit, cx, parts.prompt, p.controls)
	else
		native.text(kit, "WAITING", cx, parts.prompt, { font = "body_large", size = 26, tracking = 2, align = "center", color = DIM })
	end
	kit:layer(z)
end

-- Where each column's CONTINUE button is, for the mouse: { [slot] = { x, y, w, h } } for the players
-- whose column shows one (view.players' controls).
function M.buttons(kit, view)
	local L = M.layout(#view.players)
	local rows = M.rows_for(view.players)
	local out = {}
	for i, p in ipairs(view.players) do
		if p.controls and not p.ready then
			local c = L.columns[i]
			local parts = M.column_parts(c, #rows, math.min(#(p.sources or {}), summary.TOP))
			local rects = cards.glyph_rects(kit, c.x + c.w / 2, parts.prompt, p.controls)
			if rects[1] then out[p.slot] = rects[1] end
		end
	end
	return out
end

-- view: { kind, time, level, factions = { names }, bosses, alpha (0 to 1), left (seconds), closed,
-- waiting (this machine's players are ready, others aren't), t (seconds, for the flash), players = {
-- { slot, name, color, extracted (nil before no extraction), ready, controls, stats = { kills, damage,
-- samples, downs, deaths, saves } or nil, sources = { { key, damage } } } } }. deps: M.source_look's.
function M.draw(kit, view, deps)
	local was = kit:opacity()
	kit:opacity(view.alpha or 1)
	kit:layer(M.LAYER)
	-- Wider than the design space, for screens wider than 16:9.
	kit:rect(-M.W, -M.H, M.W * 3, M.H * 3, "#000000c8")
	kit:layer(M.LAYER + 1)
	local L = M.layout(#view.players)
	draw_header(kit, L, view)
	local rows = M.rows_for(view.players)
	for i, p in ipairs(view.players) do
		kit:layer(M.LAYER + 1)
		draw_column(kit, L.columns[i], p, rows, deps, view.t)
	end
	kit:layer(M.LAYER + 1)
	if not view.closed then
		local b = L.timer
		kit:rect(b.x, b.y, b.w, b.h, "#000000b0")
		local left = view.left or 0
		local flash = left < summary.WARNING and math.sin((view.t or 0) * 12) > 0
		kit:rect(b.x + 2, b.y + 2, (b.w - 4) * math.max(math.min(left / summary.LIMIT, 1), 0), b.h - 4, flash and RED or GOLD)
		if view.waiting then
			native.text(kit, "WAITING FOR THE SQUAD", M.W / 2, L.wait_y, { font = "body_large", size = 26, tracking = 2, align = "center", color = BODY })
		end
	end
	kit:opacity(was)
end

return M
