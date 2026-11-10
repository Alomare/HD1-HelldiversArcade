-- The level-up screen's motion (src/card_anim.lua), rerolls and banishes (src/redraw.lua), and the
-- objectives' count every machine shares (src/sync.lua).
local rules = obsidian.module("src/rules")
local card_anim = obsidian.module("src/card_anim")
local redraw = obsidian.module("src/redraw")
local draft = obsidian.module("src/draft")
local upgrades = obsidian.module("src/upgrades")
local rng = obsidian.module("src/rng")
local sync = obsidian.module("src/sync")
local cards = obsidian.module("src/cards")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("the_backdrop_fades_in_and_starts_dark_after_another_level", function()
	eq(card_anim.backdrop(0), 0)
	near(card_anim.backdrop(rules.BACKDROP_IN / 2), 0.5)
	eq(card_anim.backdrop(rules.BACKDROP_IN), 1)
	eq(card_anim.backdrop(5), 1)
	eq(card_anim.backdrop(0, true), 1, "chained")
end)

test("cards_rise_and_fade_in_one_after_another", function()
	for i = 1, 4 do
		local a, dy = card_anim.card_in(card_anim.card_start(i), i)
		eq(a, 0, "card " .. i .. " not in yet")
		eq(dy, -rules.CARD_RISE, "below the slot")
		a, dy = card_anim.card_in(card_anim.card_start(i) + rules.CARD_IN, i)
		eq(a, 1) eq(dy, 0, "card " .. i .. " in the slot")
	end
	near(card_anim.card_start(2) - card_anim.card_start(1), rules.CARD_STAGGER)
	-- Ease-out: more than half way at half the time, and never going back.
	local mid = card_anim.card_in(card_anim.card_start(1) + rules.CARD_IN / 2, 1)
	eq(mid > 0.5, true, "ease-out: " .. mid)
	local last = -1
	for k = 0, 40 do
		local a = card_anim.card_in(k * 0.01, 2)
		eq(a >= last, true, "rises steadily")
		last = a
	end
end)

test("the_stratagems_and_prompts_come_in_after_the_last_card", function()
	local done = card_anim.row_done(3)
	near(done, card_anim.card_start(3) + rules.CARD_IN)
	eq(card_anim.extras(done, 3), 0)
	eq(card_anim.extras(done + rules.EXTRAS_IN, 3), 1)
	eq(card_anim.extras(0, 3), 0)
end)

test("presses_wait_until_the_cards_are_readable", function()
	eq(card_anim.accepts_input(0, 3), false)
	eq(card_anim.accepts_input(0.3, 3), false)
	eq(card_anim.accepts_input(math.max(rules.CARD_GRACE, card_anim.row_done(3)), 3), true)
	eq(card_anim.accepts_input(card_anim.row_done(3) - 0.01, 3), false, "not before the last card is up")
	eq(card_anim.accepts_input(card_anim.row_done(6), 6), true, "a longer row waits for the last card")
end)

test("a_pick_holds_the_chosen_card_bright_while_the_others_sink_away", function()
	local a, dy, bright = card_anim.pick(0, true)
	eq(a, 1) eq(dy, 0) eq(bright, 1)
	a, dy, bright = card_anim.pick(rules.PICK_HOLD, true)
	eq(a, 1) eq(dy, 0) eq(bright, 0, "back to normal by the end of the hold")
	a, dy = card_anim.pick(0, false)
	eq(a, 1) eq(dy, 0)
	a, dy = card_anim.pick(rules.PICK_OTHERS, false)
	eq(a, 0) eq(dy, -rules.CARD_SINK)
	eq(card_anim.pick_done(rules.PICK_HOLD - 0.01), false)
	eq(card_anim.pick_done(rules.PICK_HOLD), true)
	eq(rules.PICK_OTHERS <= rules.PICK_HOLD, true, "the others are gone before the turn moves on")
end)

test("the_screen_fades_out", function()
	eq(card_anim.screen_out(0), 1)
	near(card_anim.screen_out(rules.SCREEN_OUT / 2), 0.5)
	eq(card_anim.screen_out(rules.SCREEN_OUT), 0)
	eq(card_anim.closed(rules.SCREEN_OUT - 0.01), false)
	eq(card_anim.closed(rules.SCREEN_OUT), true)
end)

test("a_banished_card_sinks_away_and_the_new_one_rises_after_it", function()
	local a, dy = card_anim.banish_out(0)
	eq(a, 1) eq(dy, 0)
	a, dy = card_anim.banish_out(rules.BANISH_OUT)
	eq(a, 0) eq(dy, -rules.BANISH_SINK)
	eq(card_anim.banish_gone(rules.BANISH_OUT), true)
	eq((card_anim.banish_in(rules.BANISH_NEXT)), 0, "the new card waits")
	a, dy = card_anim.banish_in(rules.BANISH_NEXT + rules.CARD_IN)
	eq(a, 1) eq(dy, 0)
end)

test("every_timing_is_short_and_the_cards_are_up_well_before_the_timer_matters", function()
	eq(card_anim.row_done(3) + rules.EXTRAS_IN < 1, true)
	eq(rules.BACKDROP_IN, 0.25)
	eq(rules.CARD_STAGGER, 0.06)
	eq(rules.CARD_IN, 0.2)
	eq(rules.SCREEN_OUT, 0.2)
end)

test("vacuums_give_rerolls_and_objectives_banishes", function()
	local b = redraw.new()
	eq(b.rerolls, 0) eq(b.banishes, 0)
	redraw.add(b, "rerolls", redraw.gain("rerolls", 2))
	redraw.add(b, "banishes", redraw.gain("banishes", 1))
	eq(b.rerolls, 2 * rules.REROLL_PER_VACUUM)
	eq(b.banishes, rules.BANISH_PER_OBJECTIVE)
	eq(redraw.gain("rerolls", -3), 0, "never takes any away")
end)

test("a_reroll_draws_the_row_again_and_needs_one_left", function()
	local b = redraw.new()
	local rolled = 0
	local function roll() rolled = rolled + 1 return { upgrades.list[1] } end
	eq(redraw.reroll(b, roll), nil, "none left")
	eq(rolled, 0)
	redraw.add(b, "rerolls", 1)
	eq(redraw.can_reroll(b), true)
	local row = redraw.reroll(b, roll)
	eq(#row, 1) eq(rolled, 1) eq(b.rerolls, 0)
	eq(redraw.can_reroll(b), false)
end)

test("a_banished_upgrade_never_comes_up_again_that_run", function()
	local b = redraw.new()
	redraw.add(b, "banishes", 1)
	local r = rng.new(7)
	local owned = {}
	local row = draft.roll(owned, 5, r, 3, redraw.allowed(b))
	local first = row[2]
	local function roll(filter) return draft.roll(owned, 5, r, 1, redraw.allowed(b, filter)) end
	local gone, new = redraw.banish(b, row, 2, roll, upgrades.fallback.id)
	eq(gone, first)
	eq(new ~= nil, true) eq(row[2], new)
	eq(new.id ~= first.id and new.id ~= row[1].id and new.id ~= row[3].id, true, "a card not in the row")
	eq(b.banishes, 0) eq(b.banned[first.id], true)
	for _ = 1, 200 do
		for _, u in ipairs(draft.roll(owned, 5, r, 4, redraw.allowed(b))) do eq(u.id ~= first.id, true, "banished for good") end
	end
	eq(redraw.banish(b, row, 1, roll, upgrades.fallback.id), nil, "none left")
end)

test("the_draft_keeps_its_own_rules_under_a_banish", function()
	local b = redraw.new()
	local function no_rares(u) return u.rarity ~= "rare" end
	local allowed = redraw.allowed(b, no_rares)
	b.banned.oxygenator = true
	eq(allowed(upgrades.by_id.oxygenator), false)
	for _, u in ipairs(upgrades.list) do
		if u.id ~= "oxygenator" then eq(allowed(u), no_rares(u), u.id) end
	end
end)

test("the_fallback_card_cant_be_banished_and_a_lone_card_stays_without_a_new_one", function()
	local b = redraw.new()
	redraw.add(b, "banishes", 2)
	local fb = upgrades.fallback
	eq(redraw.can_banish(b, { fb }, 1, fb.id), false)
	local a, c = upgrades.list[1], upgrades.list[2]
	local function nothing() return {} end
	local row = { a }
	eq(redraw.banish(b, row, 1, nothing, fb.id), nil, "the last card stays")
	eq(b.banishes, 2) eq(b.banned[a.id], nil, "and nothing is used")
	row = { a, c }
	local gone, new = redraw.banish(b, row, 1, nothing, fb.id)
	eq(gone, a) eq(new, nil)
	eq(#row, 1) eq(row[1], c, "the row closes up")
	eq(b.banishes, 1)
	-- A roll that answers a card already in the row (the fallback can be) counts as nothing new.
	row = { fb, c }
	gone, new = redraw.banish(b, row, 2, function() return { fb } end, fb.id)
	eq(gone, c) eq(new, nil) eq(#row, 1)
end)

test("every_machine_learns_the_objectives_done_and_keeps_the_most", function()
	local host, other = sync.new(970000006, 1), sync.new(970000006, 2)
	eq(sync.objectives(host), 0)
	eq(sync.objective_done(host), 1)
	sync.objective_done(host)
	sync.set_peer(other, "host", sync.decode(sync.encode(host, 10, true)))
	eq(sync.objectives(other), 2)
	-- The host leaves, and the next host counts on from there.
	sync.set_peer(other, "host", nil)
	eq(sync.objectives(other), 2, "kept")
	eq(sync.objective_done(other), 3)
	eq(sync.decode("970000006;1;5;1;61;1").objectives, 0, "a value without the count")
	eq(sync.decode("970000006;1;5;1;61;1;4").objectives, 4)
end)

-- A kit that records text.
local function fake_kit()
	local k = { texts = {} }
	function k:measure(text, opts) return #text * ((opts and opts.size) or 20) * 0.5, 20 end
	function k:text(text, x, y, opts) self.texts[#self.texts + 1] = { text = text, x = x, y = y, color = opts and opts.color } end
	function k:icon() return false end
	for _, name in ipairs({ "rect", "panel", "hex", "art", "band", "bar", "poly", "outline" }) do k[name] = function() end end
	function k:opacity(a) if a then self.alpha = a end return self.alpha or 1 end
	function k:layer(n) if n then self.z = n end return self.z or 0 end
	return k
end

test("the_prompts_sit_between_the_cards_and_the_stratagems", function()
	for _, strats in ipairs({ 0, 3, 5 }) do
		for _, count in ipairs({ 3, 4 }) do
			local spot = cards.layout(1, count, strats)[1]
			local card = spot.cards[1]
			eq(spot.tools.y + 32 + 14 <= card.y, true, "under the cards, clear of the hover rim")
			if strats > 0 then eq(spot.tools.y >= spot.strats[1].y + spot.strats[1].h + 6, true, "over the stratagems") end
			eq(spot.tools.y > spot.hint_y + 32, true, "over the controls")
			eq(spot.hint_y >= 0, true)
			eq(spot.title.y + 24 <= cards.H, true, "the name bar on screen")
		end
	end
end)

test("the_prompts_say_their_counts_and_go_grey_with_none_left", function()
	local kit = fake_kit()
	local r = rng.new(3)
	local tools = cards.tool_groups(kit, {
		{ keys = { "R" }, name = "REROLL", count = 2, usable = true },
		{ keys = { "X" }, name = "BANISH", count = 0, usable = false },
	})
	eq(tools[1].label, "REROLL \195\1512")
	eq(tools[2].label, "BANISH \195\1510")
	eq(tools[1].dim, false) eq(tools[2].dim, true)
	local view = { players = { { row = draft.roll({}, 3, r), owned = {}, cursor = 1, time_left = 1, tools = tools,
		fx = { { alpha = 0.5, dy = -10, bright = 1 } }, extras = 0.5, leaving = { { u = upgrades.list[1], slot = 1, alpha = 0.5, dy = -20 } } } },
		alpha = 0.8, backdrop = 0.5 }
	cards.draw(kit, view)
	local grey, white = false, false
	for _, t in ipairs(kit.texts) do
		if t.text == "BANISH \195\1510" and t.color == obsidian.module("src/native").GREY then grey = true end
		if t.text == "REROLL \195\1512" and t.color == obsidian.module("src/native").WHITE then white = true end
	end
	eq(white, true, "a reroll left: white")
	eq(grey, true, "no banish left: grey")
	eq(kit:opacity(), 1, "the kit's opacity as it was")
	-- Without the sign in the font, an x.
	local plain = fake_kit()
	function plain:measure(text, opts) if text == "\195\151" then return 0 end return #text * 10, 20 end
	eq(cards.count_label(plain, "REROLL", 3), "REROLL x3")
end)

test("the_map_shows_the_counts_on_a_strip_under_the_upgrades", function()
	local kit = fake_kit()
	local h = cards.tools_strip(kit, 100, 300, 360, 1, 0, 16, 1)
	eq(h, cards.tools_height(16))
	local found = {}
	for _, t in ipairs(kit.texts) do found[t.text] = true end
	eq(found["REROLL \195\1511"], true)
	eq(found["BANISH \195\1510"], true)
	-- Each count fits its half of the strip, smaller when it has to, three quarters at the least.
	local sized = fake_kit()
	function sized:text(text, x, y, opts) self.texts[#self.texts + 1] = { text = text, x = x, size = opts.size } end
	cards.tools_strip(sized, 0, 0, 248, 12, 3, 16, 1)
	for _, t in ipairs(sized.texts) do
		eq(sized:measure(t.text, { size = t.size }) <= 124 - 16, true, t.text .. " inside its half")
		eq(t.size >= 12, true, "no smaller than three quarters")
	end
	eq(sized.texts[2].x, 62, "the reroll centred in the left half (each over its shadow)")
	eq(sized.texts[4].x, 186, "the banish in the right")
end)

return T
