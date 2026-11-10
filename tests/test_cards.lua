local cards = obsidian.module("src/cards")
local upgrades = obsidian.module("src/upgrades")
local draft = obsidian.module("src/draft")
local rng = obsidian.module("src/rng")
local art = obsidian.module("src/art")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

-- A kit that records what it draws. Text is 0.5 of its size wide per letter.
local function fake_kit()
	local k = { texts = {}, panels = {}, hexes = {}, arts = {} }
	local function size(o) return (o and o.size) or 20 end
	function k:measure(text, opts) return #text * size(opts) * 0.5, size(opts) end
	function k:text(text, x, y, opts)
		local w = self:measure(text, opts)
		local left = (opts and opts.align == "center" and x - w / 2) or (opts and opts.align == "right" and x - w) or x
		self.texts[#self.texts + 1] = { text = text, x = left, y = y, w = w }
	end
	function k:panel(p) self.panels[#self.panels + 1] = p end
	function k:hex(x, y, r, color, icon) self.hexes[#self.hexes + 1] = { x = x, y = y, r = r, icon = icon } end
	function k:art(material, x, y, w, h, c, uv) self.arts[#self.arts + 1] = { x = x, y = y, w = w, h = h, uv = uv } return true end
	k.icons = {}
	function k:icon(name, x, y, w, h) self.icons[#self.icons + 1] = { name = name, x = x, y = y, w = w, h = h, z = self.z or 0 } end
	for _, name in ipairs({ "rect", "band", "opacity", "bar", "poly", "outline" }) do k[name] = function() end end
	function k:layer(n) if n then self.z = n end return self.z or 0 end
	return k
end

local function inside(r, x, y, w)
	return x >= r.x and x + (w or 0) <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function overlap(a, b)
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

test("cards_stay_on_screen_and_apart_for_one_to_four_players", function()
	for players = 1, 4 do
		local all = {}
		for n, spot in ipairs(cards.layout(players, 3)) do
			eq(#spot.cards, 3)
			for _, r in ipairs(spot.cards) do
				eq(r.x >= 0 and r.y >= 0 and r.x + r.w <= cards.W and r.y + r.h <= cards.H, true, players .. " players, player " .. n)
				eq(inside(spot.area, r.x, r.y, r.w), true, "in the player's own area")
				for _, other in ipairs(all) do eq(overlap(r, other), false, "cards overlap with " .. players .. " players") end
				all[#all + 1] = r
			end
		end
	end
end)

test("the_stratagem_row_and_the_time_bar_stay_on_screen_around_the_cards", function()
	for players = 1, 4 do
		for _, count in ipairs({ 3, 4 }) do
			for _, strats in ipairs({ 3, 5 }) do
				for n, spot in ipairs(cards.layout(players, count, strats)) do
					eq(#spot.strats, strats)
					eq(spot.timer.y >= spot.cards[1].y + spot.cards[1].h, true, "the bar over the cards")
					eq(spot.strats[1].w, spot.strats[1].h, "a square")
					eq(spot.hint_y + 30 <= spot.strats[1].y, true, "the controls under the stratagems")
					local all = {}
					for _, r in ipairs(spot.cards) do all[#all + 1] = r end
					for _, r in ipairs(spot.strats) do all[#all + 1] = r end
					all[#all + 1] = spot.timer
					for i, r in ipairs(all) do
						eq(r.x >= 0 and r.y >= 0 and r.x + r.w <= cards.W and r.y + r.h <= cards.H, true, players .. " players, " .. n)
						for j = i + 1, #all do eq(overlap(r, all[j]), false, players .. " players, " .. count .. " cards, " .. strats .. " stratagems") end
					end
				end
			end
		end
	end
end)

test("the_button_row_is_centred_and_each_group_shows_its_keys", function()
	local kit = fake_kit()
	cards.glyphs(kit, 960, 40, { { keys = { "A", "D" }, label = "MOVE" }, { keys = { "E" }, label = "CHOOSE" } })
	local left, right, found = math.huge, 0, {}
	for _, t in ipairs(kit.texts) do
		found[t.text] = true
		left, right = math.min(left, t.x), math.max(right, t.x + t.w)
	end
	eq(found.A and found.D and found.E and found.MOVE and found.CHOOSE, true)
	eq(math.abs((960 - left) - (right - 960)) < 12, true, "about centred: " .. left .. " to " .. right)
end)

test("every_card_text_fits_inside_its_card", function()
	art.ready = true
	for players = 1, 4 do
		local spots = cards.layout(players, 3)
		for _, u in ipairs(upgrades.list) do
			for _, owned in ipairs({ {}, { [u.id] = (u.max or 3) - 1 } }) do
				local kit = fake_kit()
				local r = spots[players].cards[2]
				cards.card(kit, r, u, owned, "cursor")
				for _, t in ipairs(kit.texts) do
					eq(inside(r, t.x, t.y, t.w), true, u.id .. " with " .. players .. " players: '" .. t.text .. "'")
				end
				local atlas, icon, frame = obsidian.module("src/atlas"), 0, 0
				local at = atlas.images["icon_" .. u.id]
				local edge = atlas.images[art.FRAMES[u.rarity][1]]
				for _, a in ipairs(kit.arts) do
					if at and a.uv[1] * atlas.w == at[1] and a.uv[2] * atlas.h == at[2] then icon = icon + 1 end
					if a.uv[1] * atlas.w == edge[1] and a.uv[2] * atlas.h == edge[2] then frame = frame + 1 end
				end
				eq(frame, 2, u.id .. "'s frame, its edge and its inside")
				eq(icon, 1, u.id .. "'s own icon")
			end
		end
	end
	art.ready = false
end)

test("without_the_art_a_card_shows_the_games_stratagem_icon", function()
	art.ready = false
	for _, u in ipairs(upgrades.list) do
		local kit = fake_kit()
		cards.card(kit, cards.layout(1, 3)[1].cards[1], u, {}, "idle")
		eq(kit.hexes[2].icon, u.icon, "on the rarity hex")
		eq(#kit.arts, 0)
	end
end)

test("every_upgrade_has_an_icon_and_every_rarity_a_frame_in_the_atlas", function()
	local atlas = obsidian.module("src/atlas")
	for id in pairs(upgrades.by_id) do eq(atlas.images["icon_" .. id] ~= nil, true, id) end
	for _, kind in ipairs({ "circle", "square", "diamond" }) do eq(atlas.images["frame_" .. kind] ~= nil, true, kind) end
end)

test("each_rarity_has_a_frame_of_its_own", function()
	local seen = {}
	for _, r in ipairs({ "common", "rare", "legendary" }) do
		local name = art.FRAMES[r][1]
		eq(seen[name], nil, r .. " shares a frame")
		seen[name] = true
	end
end)

test("a_card_shows_its_total_without_the_word", function()
	local kit = fake_kit()
	cards.card(kit, cards.layout(1, 3)[1].cards[1], upgrades.by_id.oxygenator, { oxygenator = 1 }, "idle")
	local found = {}
	for _, t in ipairs(kit.texts) do found[t.text] = true end
	eq(found["+20%"], true)
	eq(found["Total: +20%"], nil)
end)

test("a_card_puts_the_total_apart_from_what_it_does", function()
	local body, now = cards.split("Move 10% faster.\nTotal: +20%")
	eq(body, "Move 10% faster.")
	eq(now, "+20%")
	body, now = cards.split("Reloads are instant.")
	eq(body, "Reloads are instant.")
	eq(now, nil)
end)

test("a_level_up_screen_draws_each_players_row", function()
	local r = rng.new(4)
	local view = { waiting = true, players = {} }
	for n = 1, 3 do
		view.players[n] = { name = "P" .. n, row = draft.roll({}, 4, r), owned = {}, cursor = 2 }
	end
	view.players[2].chosen = view.players[2].row[3].id
	local kit = fake_kit()
	cards.draw(kit, view)
	eq(#kit.panels, 3, "the pulsing rim round the card each player hovers")
	local found = {}
	for _, t in ipairs(kit.texts) do found[t.text] = true end
	eq(found["LEVEL 4"], nil, "the bar on top says the level")
	eq(found["CHOSEN"], nil, "the frame says it")
	eq(found["NEW"], nil)
	eq(found["WAITING FOR THE SQUAD"], true)
	local strat = { name = "Solo", row = draft.roll({}, 4, r), owned = {}, cursor = 1, focus = "strats", strat_cursor = 2, time_left = 0.5,
		strats = { { id = "a", name = "One", icon = "x" }, { id = "b", name = "Two", icon = "y" }, { id = "c", name = "Three", icon = "z" } } }
	local solo = fake_kit()
	cards.draw(solo, { players = { strat } })
	found = {}
	for _, t in ipairs(solo.texts) do found[t.text] = true end
	eq(found.TWO, nil, "the icon says it")
	eq(found["PLAYER 1"], nil, "alone, no player's name")
end)

test("a_local_players_turn_is_the_single_players_screen_with_their_name", function()
	local r = rng.new(5)
	local turn = { name = "PLAYER 2", show_name = true, row = draft.roll({}, 4, r), owned = {}, cursor = 1, time_left = 1 }
	local kit = fake_kit()
	cards.draw(kit, { players = { turn } })
	local found = {}
	for _, t in ipairs(kit.texts) do found[t.text] = true end
	eq(found["PLAYER 2"], true, "whose turn it is")
	eq(#kit.panels, 1)
end)

test("text_wraps_at_the_width_and_keeps_its_line_breaks", function()
	local kit = fake_kit()
	local lines = cards.wrap(kit, "one two three four\nfive", 100, { size = 20 })
	eq(table.concat(lines, "|"), "one two|three four|five")
end)

test("the_map_panel_groups_upgrades_by_rarity_with_stacks_over_them", function()
	local groups = cards.owned_groups({ oxygenator = 2, sweet_liberty = 1, rapid_fire = 3, gunslinger = 1, nope = 3 }, upgrades)
	local order = {}
	for _, list in ipairs(groups) do order[#order + 1] = list[1].u.rarity end
	eq(table.concat(order, " "), "legendary perk rare common")
	local kit = fake_kit()
	local h = cards.owned_panel(kit, 100, 300, 360, { oxygenator = 2, sweet_liberty = 1, rapid_fire = 3, nope = 3 }, upgrades, 1)
	eq(h > 0, true)
	local found = {}
	for _, t in ipairs(kit.texts) do found[t.text] = true end
	eq(found["2"], true, "Oxygenator's stacks")
	eq(found["3"], true, "Rapid Fire's stacks")
	eq(found["1"], nil, "Sweet Liberty takes one stack: no count")
	eq(#kit.hexes, 6, "an unknown id is left out: two hexes each")
	eq(cards.owned_panel(fake_kit(), 100, 300, 360, {}, upgrades, 1), 0, "nothing owned, no panel")
end)

test("a_stack_count_sits_small_in_its_badges_top_right_corner", function()
	local kit = fake_kit()
	local owned = { oxygenator = 2, rapid_fire = 3, sweet_liberty = 1 }
	local h = cards.owned_panel(kit, 100, 300, 360, owned, upgrades, 1)
	-- Three groups of one badge each: each row a gap taller than the frame in it, half a gap between groups,
	-- and no line for the counts.
	local edge = 360 / cards.PANEL_COLUMNS * cards.PANEL_EDGE
	local cell = (360 - 2 * edge) / cards.PANEL_COLUMNS
	local r = cell * cards.PANEL_BADGE
	local gap = r * cards.PANEL_ROW_GAP
	near(h, 2 * (r * 2.13 + gap) + art.badge_height(r) + gap + 2 * gap / 2 + 2 * edge, "the panel's height")
	local badges = {}
	for i = 1, #kit.hexes, 2 do badges[#badges + 1] = kit.hexes[i] end
	local counts = 0
	for _, t in ipairs(kit.texts) do
		if t.text == "2" or t.text == "3" then
			counts = counts + 1
			local b
			for _, hex in ipairs(badges) do
				if t.x > hex.x - hex.r * 1.2 and t.x < hex.x + hex.r * 1.2 and math.abs(t.y - hex.y) < hex.r * 1.2 then b = hex end
			end
			eq(b ~= nil, true, "a count on a badge")
			eq(t.x > b.x, true, "right of the badge's middle")
			eq(t.y > b.y, true, "above the badge's middle")
		end
	end
	eq(counts, 4, "two counts, each over its faint shadow")
	local x, y, size = cards.count_spot(0, 0, 40)
	eq(size < 40, true, "smaller than the badge")
	near(y + size * 0.7, 40 * 1.065, "the figures' top on the frame's top")
	eq(x >= 40 * 1.065, true, "the right edge on the frame's right")
end)

test("the_stat_box_starts_at_the_cards_left_edge_with_the_text_level_with_the_icons", function()
	local parts = cards.stat_parts(80.4, 150, 50)
	eq(parts[1].text, "80 / 150", "health as current / maximum")
	eq(parts[1].icon, "mark_stat_health")
	eq(parts[2].text, "50") eq(parts[2].icon, "mark_stat_armor")
	eq(#cards.stat_parts(nil, nil, nil), 0)
	eq(cards.stat_parts(nil, 150, nil)[1].text, "150", "no current health: the maximum alone")
	local kit = fake_kit()
	local size = 20
	local L = cards.stat_layout(kit, 500, 100, size, parts)
	eq(L.x, 500, "the box's left edge on the card's")
	eq(L.y, 100)
	local last = L.x
	for _, item in ipairs(L.items) do
		near(item.icon_y, L.y + L.h / 2, "the icon on the box's middle")
		near(item.text_y + size * 0.35, item.icon_y, "the figures' middle on the icon's")
		eq(item.icon_x - item.size / 2 >= last, true, "after what's left of it")
		eq(item.text_x >= item.icon_x + item.size / 2, true, "the number right of its icon")
		last = item.text_x + kit:measure(item.text, { size = size })
	end
	eq(last <= L.x + L.w, true, "inside the box")
	eq(cards.stat_layout(kit, 500, 100, size, {}), nil, "nothing to show, no box")
	local drawn = fake_kit()
	eq(cards.stat_line(drawn, 500, 100, size, 80, 150, 50) ~= nil, true)
	local found = {}
	for _, t in ipairs(drawn.texts) do found[t.text] = true end
	eq(found["80 / 150"], true) eq(found["50"], true)
end)

-- A kit whose icons all draw, recording each, and whose points are pixels at 1.5 to the unit.
local function icon_kit()
	local k = fake_kit()
	function k:icon(name, x, y, w, h, c, uv)
		self.icons[#self.icons + 1] = { name = name, x = x, y = y, w = w, h = h, c = c, uv = uv }
		return true
	end
	function k:point(x, y) return x / 1.5, y / 1.5 end
	return k
end

local function extent(icons, name)
	local l, b, r, t = math.huge, math.huge, -math.huge, -math.huge
	for _, i in ipairs(icons) do
		if i.name == name then
			l, b, r, t = math.min(l, i.x), math.min(b, i.y), math.max(r, i.x + i.w), math.max(t, i.y + i.h)
		end
	end
	return l, b, r, t
end

test("the_panels_are_drawn_like_the_hud_card_with_the_frame_outside_the_box", function()
	local native = obsidian.module("src/native")
	-- Hud.draw_panel for a card 248 wide and 76 tall: basicbox_01 from -2 to 250 across and -1 to 77 up,
	-- the box itself from 0 to 248 with the image's inside, the edges in the image's own edge pixels.
	local parts = native.panel_parts(0, 0, 248, 76, 1)
	eq(#parts, 5)
	local l, b, r, t = math.huge, math.huge, -math.huge, -math.huge
	for _, p in ipairs(parts) do
		l, b, r, t = math.min(l, p[1]), math.min(b, p[2]), math.max(r, p[1] + p[3]), math.max(t, p[2] + p[4])
	end
	eq(l, -2) eq(r, 250) eq(b, -1) eq(t, 77)
	local box = parts[5]
	eq(box[1], 0) eq(box[2], 0) eq(box[3], 248) eq(box[4], 76)
	near(box[5][1], 0.25) near(box[5][2], 2 / 256) near(box[5][3], 0.75) near(box[5][4], 1 - 2 / 256)
	near(parts[1][5][3], 2 / 16, "the left edge from the image's left pixels")
	near(parts[2][5][2], 1 - 1 / 256, "the top edge from the image's top row")
	-- Scaled: the frame grows with the unit.
	parts = native.panel_parts(10, 20, 100, 50, 1.5)
	eq(parts[1][1], 10 - 3) eq(parts[1][3], 3) eq(parts[4][2], 20 - 1.5)
	-- Drawn: the card's tint, no black outline.
	local kit = icon_kit()
	native.panel(kit, 0, 0, 248, 76)
	eq(#kit.icons, 5)
	for _, i in ipairs(kit.icons) do eq(i.name, "basicbox_01") eq(i.c, native.PANEL_TINT) end
	eq(native.PANEL_TINT, "#ffffff96", "150 of 255, the HUD card's own alpha")
end)

test("the_stat_panel_and_the_upgrades_line_up_with_the_hud_cards_edges", function()
	local cards_hud = obsidian.module("src/cards_hud")
	-- A card at 1.5 pixels to the HUD unit: from pixel 144, 248 HUD units wide, the top at pixel 195.
	local c = { left = 144, top = 195, width = 248 * 1.5, scale = 1.5, cooling = false }
	local kit = icon_kit()
	local s = cards_hud.spot(kit, c)
	near(s.unit, 1, "one HUD unit in the kit's units")
	near(s.x, 96) near(s.w, 248)
	-- The card's own frame: basicbox_01 from 2 HUD units left of the card to 2 right of it.
	local card_left, card_right = 96 - 2 * s.unit, 96 + 248 + 2 * s.unit
	local L = cards.stat_line(kit, s.x, s.y, s.size, 80, 150, 50, s.unit)
	eq(L.x, s.x, "the stats from the card's left edge")
	local l = extent(kit.icons, "basicbox_01")
	near(l, card_left, "the stat panel's frame on the card's")
	local map = icon_kit()
	cards.owned_panel(map, s.x, s.map_y, s.w, { oxygenator = 2, rapid_fire = 3, sweet_liberty = 1 }, upgrades, 1, s.unit)
	local ml, mb, mr = extent(map.icons, "basicbox_01")
	near(ml, card_left, "the upgrades' left edge on the card's")
	near(mr, card_right, "and the right")
	eq(mb >= 130 + 1, true, "over the card's top frame")
	-- Every badge inside the panel, in a column of the panel.
	local edge = 248 / cards.PANEL_COLUMNS * cards.PANEL_EDGE
	local r = (248 - 2 * edge) / cards.PANEL_COLUMNS * cards.PANEL_BADGE
	local groups = cards.owned_groups({ oxygenator = 2, rapid_fire = 3, sweet_liberty = 1 }, upgrades)
	local _, rows, h = cards.owned_layout(groups, s.x, s.map_y + 500, s.w)
	for _, row in ipairs(rows) do
		for _, item in ipairs(row.items) do
			local half = r * 2.13 * art.FRAMES[item.u.rarity][4] / 2
			eq(item.cx - half >= s.x and item.cx + half <= s.x + s.w, true, item.u.id .. " across")
			eq(row.cy + half <= s.map_y + 500 and row.cy - half >= s.map_y + 500 - h, true, item.u.id .. " up")
		end
	end
	-- A margin of half a gap plus the edge between the frame and the outer badges.
	local first = rows[1].items[1]
	eq(first.cx - r * 2.13 / 2 - s.x >= edge + 1, true, "room inside the frame on the left")
	eq(s.map_y + 500 - (rows[1].cy + r * 2.13 / 2) >= edge + 1, true, "and at the top")
end)

test("the_map_panels_badges_sit_closer_and_still_clear_each_other", function()
	-- On the HUD card's 248 units.
	local edge = 248 / cards.PANEL_COLUMNS * cards.PANEL_EDGE
	local cell = (248 - 2 * edge) / cards.PANEL_COLUMNS
	local r = cell * cards.PANEL_BADGE
	local side = cell - r * 2.13
	eq(side < cell - cell * 0.36 * 2.13, true, "less room between two frames than at the old 0.36")
	eq(math.abs(side - 9.87) < 0.01, true, "9.9 units between two frames side by side")
	eq(r * 2.13 * art.LARGEST < cell, true, "two diamonds side by side don't touch")
	local row = r * cards.PANEL_ROW_GAP
	eq(math.abs(row - 8.18) < 0.01, true, "8.2 units between rows")
	eq(row > r * (cards.LINK_GAP + cards.LINK_H), true, "room for the link marks under a frame")
	-- Rows of several rarities: each the frame and the gap at least under the one over it.
	local groups = cards.owned_groups({ oxygenator = 1, rapid_fire = 1, gunslinger = 1, sweet_liberty = 1, deep_pockets = 1 }, upgrades)
	local _, rows = cards.owned_layout(groups, 0, 0, 248)
	for i = 2, #rows do
		eq(rows[i - 1].cy - rows[i].cy >= r * 2.13 + row - 1e-9, true, "rows apart by a frame and the gap at least")
	end
end)

test("the_rerolls_and_banishes_go_under_the_upgrades_always_in_one_place", function()
	local cards_hud = obsidian.module("src/cards_hud")
	local c = { left = 144, top = 195, width = 248 * 1.5, scale = 1.5, cooling = false }
	local s = cards_hud.spot(icon_kit(), c)
	local at = cards_hud.map_spots(s, true)
	eq(at.tools, s.map_y, "the strip just over the card, however many upgrades there are")
	near(at.owned, s.map_y + cards.tools_height(cards_hud.TOOLS_SIZE * s.unit) + cards_hud.TOOLS_GAP * s.unit, "the upgrades over the strip")
	eq(cards_hud.map_spots(s, false).owned, s.map_y, "no counts, the upgrades just over the card")
	eq(cards_hud.map_spots(s, false).tools, nil)
	eq(cards_hud.TOOLS_SIZE >= cards_hud.STAT_SIZE, true, "the counts no smaller than the health numbers")
end)

test("no_part_of_a_panel_is_drawn_twice", function()
	local native = obsidian.module("src/native")
	local parts = native.panel_parts(100, 50, 80, 30, 1.5)
	local area = 0
	for i, a in ipairs(parts) do
		area = area + a[3] * a[4]
		for j = i + 1, #parts do
			local b = parts[j]
			local w = math.min(a[1] + a[3], b[1] + b[3]) - math.max(a[1], b[1])
			local h = math.min(a[2] + a[4], b[2] + b[4]) - math.max(a[2], b[2])
			eq(w > 1e-9 and h > 1e-9, false, "parts " .. i .. " and " .. j .. " overlap")
		end
	end
	near(area, (80 + 2 * 3) * (30 + 2 * 1.5), "and together they cover the frame's outer box")
end)

test("the_stats_sit_over_the_cooldown_list_only_while_it_shows", function()
	local cards_hud = obsidian.module("src/cards_hud")
	local kit = icon_kit()
	local c = { left = 144, top = 195, width = 372, scale = 1.5, cooling = false }
	local top = 195 / 1.5
	local plain = cards_hud.spot(kit, c)
	near(plain.y, top + cards_hud.STAT_GAP, "just over the card")
	eq(cards_hud.STAT_GAP > 2, true, "the two frames, a unit each, don't touch")
	c.cooling = true
	local high = cards_hud.spot(kit, c)
	-- The cooldown icons, as Hud.draw_stratagem_cooldown_list moves them: from current_height - 2, 32
	-- tall, hopping in a stratagem's last second.
	local peak = 0
	for i = 0, 1000 do
		local t = i / 1000
		local y = -2
		if t < 1 then y = y + 3 * 32 * t * (1 - t) - 32 * (1 - t) end
		peak = math.max(peak, y + 32)
	end
	near(cards_hud.COOLDOWN_TOP, -2 + 32 + 32 / 3, "the hop's top")
	eq(cards_hud.COOLDOWN_TOP >= peak - 1e-3, true, "above every frame of the hop")
	-- The stat panel's bottom frame (1 HUD unit under the box) clears the hop's top.
	eq(high.y - 1 > top + peak, true, "over the cooldown icons")
	near(high.y - plain.y, cards_hud.COOLDOWN_TOP, "no higher than it needs")
	near(high.map_y, plain.map_y, "the map panel doesn't move: no cooldown list with the map open")
end)

test("the_cooldown_list_shows_by_the_games_own_tests", function()
	local cards_hud = obsidian.module("src/cards_hud")
	local function inv(...) return { stratagems = { ... } } end
	local cooling = { cooldown_timer = 12, loadout_info = { cooldown_time = 60 } }
	eq(cards_hud.cooldowns_shown(inv(cooling)), true)
	eq(cards_hud.cooldowns_shown(inv({ cooldown_timer = 0, loadout_info = { cooldown_time = 60 } })), false, "ready")
	eq(cards_hud.cooldowns_shown(inv({ cooldown_timer = 5, loadout_info = { cooldown_time = 0 } })), false, "a stratagem without a cooldown")
	eq(cards_hud.cooldowns_shown(inv({ cooldown_timer = 5, uses_left = 0, loadout_info = { cooldown_time = 60 } })), false, "used up")
	eq(cards_hud.cooldowns_shown(inv({ cooldown_timer = 5, uses_left = 2, loadout_info = { cooldown_time = 60 } })), true)
	eq(cards_hud.cooldowns_shown(nil), false)
	eq(cards_hud.cooldowns_shown({}), false)
	-- Recorded with the card: only in the states that draw the list.
	local hud = { hud_info = { { state = "normal", current_height = 76, width = 248 } }, hd_gui = { ui_scale = 1.5 },
		get_player_hud_pos = function() return { x = 96, y = 54 } end }
	cards_hud.record(hud, "u", 1, true)
	eq(cards_hud.seen.u.cooling, true)
	hud.hud_info[1].state = "map"
	cards_hud.record(hud, "u", 1, true)
	eq(cards_hud.seen.u.cooling, false)
	cards_hud.clear()
end)

return T
