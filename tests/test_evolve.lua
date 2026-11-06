-- Evolutions (src/evolve.lua and their effects) and the mouse on the cards and the summary (src/mouse.lua).
local upgrades = obsidian.module("src/upgrades")
local evolve = obsidian.module("src/evolve")
local draft = obsidian.module("src/draft")
local rules = obsidian.module("src/rules")
local rng = obsidian.module("src/rng")
local fight = obsidian.module("src/fight")
local orbs = obsidian.module("src/orbs")
local mouse = obsidian.module("src/mouse")
local cards = obsidian.module("src/cards")
local art = obsidian.module("src/art")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

local by = upgrades.by_id

local function kit()
	local k = { texts = {}, arts = {}, hexes = {}, rects = {} }
	local function size(o) return (o and o.size) or 20 end
	function k:measure(text, opts) return #text * size(opts) * 0.5, size(opts) end
	function k:text(text, x, y, opts) self.texts[#self.texts + 1] = { text = text, x = x, y = y } end
	function k:art(material, x, y, w, h, c, uv) self.arts[#self.arts + 1] = { x = x, y = y, w = w, h = h, c = c, uv = uv } return true end
	function k:hex(x, y, r, color, icon) self.hexes[#self.hexes + 1] = { x = x, y = y, r = r, icon = icon } end
	function k:rect(x, y, w, h, c) self.rects[#self.rects + 1] = { x = x, y = y, w = w, h = h, c = c } end
	for _, name in ipairs({ "panel", "band", "opacity", "bar", "poly", "outline", "icon" }) do k[name] = function() end end
	function k:layer(n) if n then self.z = n end return self.z or 0 end
	return k
end

test("the_seven_evolutions_pair_existing_upgrades_with_the_first_half_able_to_max", function()
	eq(#upgrades.EVOLUTIONS, 7)
	local uses = {}
	for _, e in ipairs(upgrades.EVOLUTIONS) do
		eq(e.rarity, "evolution", e.id)
		eq(e.max, 1, e.id)
		local a, b = by[e.evolves[1]], by[e.evolves[2]]
		eq(a ~= nil and b ~= nil, true, e.id .. " halves")
		eq(a.max ~= nil, true, e.id .. ": the first half has a max")
		eq(type(e.link), "string", e.id .. " link color")
		for _, id in ipairs(e.evolves) do uses[id] = (uses[id] or 0) + 1 end
	end
	eq(uses.kinetic_battery, 1, "Kinetic Battery is half of one pair")
	eq(uses.cluster_grenade, 2, "Cluster Grenade is half of two")
	eq(by.thunderstruck, nil, "Thunderstruck went with Stun Rounds")
	eq(by.stun_rounds, nil)
	local red = cards.rarity_color("evolution")
	for _, r in ipairs(rules.RARITIES) do
		if r.id ~= "evolution" then eq(r.color ~= red, true, "a red no other rarity uses") end
	end
end)

test("an_evolution_is_ready_once_the_first_half_is_maxed_and_the_second_held", function()
	local e = by.carpet_bombing
	eq(evolve.ready(e, { cluster_grenade = 2, deep_pockets = 1 }), false, "not maxed")
	eq(evolve.ready(e, { cluster_grenade = 3 }), false, "no second half")
	eq(evolve.ready(e, { cluster_grenade = 3, deep_pockets = 1 }), true)
	eq(evolve.ready(e, { deep_pockets = 4, cluster_grenade = 1 }), false, "the second half maxed isn't enough")
	eq(evolve.ready(by.dynamo, { weight_training = 1, kinetic_battery = 1 }), true, "Weight Training's max is 1")
	eq(evolve.ready(e, { cluster_grenade = 3, deep_pockets = 1, carpet_bombing = 1 }), false, "held already")
end)

test("taking_an_evolution_uses_both_halves_up_and_closes_the_other_pair", function()
	local owned, absorbed = { cluster_grenade = 3, deep_pockets = 2, sweet_liberty = 1, oxygenator = 3 }, {}
	eq(#evolve.offers(owned, absorbed), 2, "Carpet Bombing and Chain Reaction")
	evolve.take(owned, absorbed, by.carpet_bombing)
	eq(owned.cluster_grenade, nil)
	eq(owned.deep_pockets, nil)
	eq(owned.carpet_bombing, 1)
	eq(owned.oxygenator, 3, "the rest of the build stays")
	eq(absorbed.cluster_grenade, 3)
	eq(absorbed.deep_pockets, 2)
	eq(#evolve.offers(owned, absorbed), 0, "Chain Reaction can't form: its cluster is gone")
	eq(#evolve.hints(by.sweet_liberty, owned, absorbed), 0, "no partner hint for a pair that can't form")
	evolve.undo(owned, absorbed, by.carpet_bombing)
	eq(owned.cluster_grenade, 3, "the debug page gives the halves back")
	eq(owned.carpet_bombing, nil)
	eq(next(absorbed), nil)
end)

test("an_evolution_applies_both_halves_at_their_stacks_and_its_own_effect", function()
	local stats = {}
	local env = { stat = function(_, name, v) stats[name] = v end }
	by.carpet_bombing.apply(env, 1, 1, { cluster_grenade = 3, deep_pockets = 2 })
	eq(stats.cluster, 3)
	eq(stats.pockets, 2)
	eq(stats.carpet, upgrades.CARPET_RING)
	eq(stats.pockets_rate, upgrades.CARPET_RATE)
	stats = {}
	by.spiked_plating.apply(env, 1, 1, { strike_back = 5, extra_padding = 2 })
	near(stats.strike_back, 0.5)
	eq(stats.padding, 2 * upgrades.PADDING)
	eq(stats.strike_reach, upgrades.SPIKED_REACH)
end)

test("a_full_row_offers_one_evolution_at_most_and_a_banish_never", function()
	local owned = { kinetic_battery = 5, weight_training = 1 }
	local r = rng.new(7)
	local seen = 0
	for _ = 1, 400 do
		local row = draft.roll(owned, 10, r, 4, nil, {})
		local n = 0
		for _, u in ipairs(row) do if u.evolves then n = n + 1 end end
		eq(n <= 1, true, "one a row")
		seen = seen + n
		for _, u in ipairs(draft.roll(owned, 10, r, 1, nil, {})) do eq(u.evolves, nil, "a banish's card") end
	end
	eq(seen > 120 and seen < 280, true, "about half the rows: " .. seen)
	for _ = 1, 200 do
		for _, u in ipairs(draft.roll({ oxygenator = 1 }, 10, r, 3, nil, { kinetic_battery = 5 })) do
			eq(u.id ~= "kinetic_battery", true, "a used-up half isn't offered again")
			eq(u.evolves, nil, "nothing ready")
		end
	end
end)

test("cards_show_the_partners_and_the_map_panel_links_a_ready_pair", function()
	local hints = evolve.hints(by.cluster_grenade, {}, {})
	eq(#hints, 2, "Deep Pockets and Sweet Liberty")
	eq(#evolve.hints(by.oxygenator, {}, {}), 0, "not half of a pair")
	local halves = evolve.hints(by.chain_reaction, {}, {})
	eq(halves[1].id, "sweet_liberty")
	eq(halves[2].id, "cluster_grenade")
	eq(next(evolve.links({ cluster_grenade = 2, deep_pockets = 1 })), nil, "no half at max")
	local links = evolve.links({ cluster_grenade = 3, deep_pockets = 1, sweet_liberty = 1 })
	eq(#links.cluster_grenade, 2, "two pairs ready: two marks")
	eq(links.deep_pockets[1], by.carpet_bombing.link)
	eq(links.sweet_liberty[1], by.chain_reaction.link)
	local marks = cards.link_marks(by.cluster_grenade, 100, 100, 20, links.cluster_grenade)
	eq(#marks, 2)
	eq(marks[1].x + marks[1].w < marks[2].x, true, "side by side")
	eq(marks[1].y + marks[1].h < 100 - 20 * 1.065, true, "under the frame")
end)

test("a_cards_partner_icons_sit_on_the_rarity_row_at_the_right_half_again_as_big", function()
	eq(cards.HINT_R.tall, 20.4, "a ring as wide as the rarity's bar, or a little less: 20% under the 25.5 that overflowed it")
	eq(cards.HINT_R.wide, 18, "20% under 22.5")
	for players = 1, 4 do
		local r = cards.layout(players, 3)[players].cards[2]
		local spots, w = cards.hint_spots(r, 2)
		eq(w > 0, true)
		for _, s in ipairs(spots) do
			-- A ring as wide as the rarity's bar is tall and a little more sits on its frame.
			eq(s.x - s.r >= r.x and s.x + s.r <= r.x + r.w and s.y - s.r >= r.y and s.y + s.r <= r.y + r.h, true, players .. " players")
		end
		eq(spots[1].x > spots[2].x, true, "from the right edge leftward")
		if r.wide then
			eq(spots[1].y - spots[1].r >= r.y, true, "a wide card's along the bottom, where the rarity's name is")
			eq(spots[1].y < r.y + r.h / 2, true)
		else
			eq(spots[1].y, r.y + r.h - cards.RARITY_BAR / 2, "a tall card's in the middle of the rarity's bar")
			eq(spots[2].x - spots[2].r > r.x + r.w / 2, true, "on the right, clear of the rarity's name")
		end
	end
	art.ready = true
	local k = kit()
	local r = cards.layout(1, 3)[1].cards[1]
	cards.card(k, r, by.cluster_grenade, {}, "idle", 0, evolve.hints(by.cluster_grenade, {}, {}))
	local atlas = obsidian.module("src/atlas")
	local ring = 0
	for _, a in ipairs(k.arts) do
		if a.uv[1] * atlas.w == atlas.images.ring[1] and a.uv[2] * atlas.h == atlas.images.ring[2] then
			ring = ring + 1
			eq(a.c, cards.rarity_color("evolution"), "a ring in the Evolution red")
		end
	end
	eq(ring, 2, "a thin ring round each partner")
	art.ready = false
end)

test("napalm_needles_is_one_build_up_that_sets_off_both_and_leaves_a_cloud", function()
	local f = fight.new()
	local stats = { ignite = upgrades.BUILD_UP[3], needle = upgrades.BUILD_UP[1], napalm = true }
	local bug = {}
	-- 20% of 400 is 80: the lower share of the two.
	eq(fight.on_hit(f, stats, bug, { slot = "primary_weapon", damage = 50 }, 0, 400), nil)
	local out, extra = fight.on_hit(f, stats, bug, { slot = "primary_weapon", damage = 30 }, 0, 400)
	eq(out and table.concat(out, ","), "regular_burn,poison_medium_damage,poison_slow")
	eq(extra.bonus, 80, "both bonus hits")
	eq(fight.killed(f, bug, { x = 1, y = 2, z = 0 }, 1), true, "burning when it died")
	eq(fight.killed(f, {}, { x = 1, y = 2, z = 0 }, 1), false, "not burning: no cloud")
	local hits = {}
	local a, b = {}, {}
	local function near() return { a, b } end
	local function poison(enemy) hits[#hits + 1] = enemy end
	fight.step_clouds(f, 1, near, poison)
	eq(#hits, 2)
	fight.step_clouds(f, 2, near, poison)
	eq(#hits, 2, "poisoned already")
	fight.step_clouds(f, 1 + fight.CLOUD.seconds + 0.5, near, poison)
	eq(#hits, 2, "the cloud is gone by then")
	eq(#f.clouds, 0)
end)

test("iron_saint_saves_give_invulnerability_and_a_heal", function()
	local f = fight.new()
	fight.state = f
	local stats = { democracy = 0.5, saint_seconds = 2, saint_heal = 0.25 }
	local unit = {}
	eq(fight.spare(f, stats, unit, 10, function() return 0 end), true)
	eq(fight.saintly(f, unit, 11.5), true)
	eq(fight.saintly(f, unit, 12.5), false)
	eq(fight.spare(f, stats, unit, 11, function() return 1 end), true, "every killing hit in the window")
	eq(fight.take_heal(unit), 0.25)
	eq(fight.take_heal(unit), nil, "once")
	fight.state = nil
end)

test("spiked_plating_reaches_further_and_deals_back_twice", function()
	local base = { strike_back = 0.5 }
	eq(fight.strike_back(base, 100, 4), nil)
	near(fight.strike_back({ strike_back = 0.5, strike_reach = 6, strike_times = 2 }, 100, 4), 100)
end)

test("a_siphoned_sample_flies_to_its_player_from_anywhere", function()
	local o = orbs.new()
	local me, other = {}, {}
	orbs.drop(o, { x = 10, y = 0, z = 0 }, 3, nil, me)
	local players = { { pos = { x = 9.5, y = 0, z = 0 }, is_local = false, unit = other }, { pos = { x = 0, y = 0, z = 0 }, is_local = true, unit = me } }
	orbs.update(o, 0.1, players)
	eq(#o.list, 0, "another player standing on it takes it there, as with any sample")
	o = orbs.new()
	orbs.drop(o, { x = 10, y = 0, z = 0 }, 3, nil, me)
	players[1].pos = { x = 8, y = 0, z = 0 }
	orbs.update(o, 0.1, players)
	eq(o.list[1].x < 10 - rules.VACUUM_SPEED * 0.1 + 0.01, true, "on its way to its player, past the nearer one")
	o.list[1].age = rules.ORB_LIFE + 1
	orbs.update(o, 0.1, { players[2] })
	eq(#o.list, 1, "doesn't run out of time on the way")
	o.list[1].age = 0
	orbs.update(o, 0.1, { players[1] })
	eq(o.list[1].home, nil, "its player gone: an orb like the others")
end)

test("the_mouse_focuses_picks_and_presses_the_prompts", function()
	local spot = cards.layout(1, 3, 3)[1]
	local tools = { { x = 700, y = 100, w = 200, h = 40 }, { x = 1000, y = 100, w = 200, h = 40 } }
	local c = spot.cards[2]
	eq(select(1, mouse.over(spot, tools, c.x + 5, c.y + 5)), "card")
	eq(select(2, mouse.over(spot, tools, c.x + 5, c.y + 5)), 2)
	local s = spot.strats[3]
	eq(select(1, mouse.over(spot, tools, s.x + 1, s.y + 1)), "strat")
	eq(select(2, mouse.over(spot, tools, 1010, 110)), 2)
	eq(mouse.over(spot, tools, 5, 5), nil)
	local p = { cursor = 1, strat_cursor = 1, focus = "cards", strats = { {}, {}, {} } }
	eq(mouse.step(p, "card", 3, { moved = true }), nil)
	eq(p.cursor, 3)
	eq(mouse.step(p, "strat", 2, { moved = true }), nil)
	eq(p.focus, "strats")
	eq(mouse.step(p, "strat", 2, { click = true }), "pick_strat")
	eq(mouse.step(p, "tool", 1, { click = true }), "reroll")
	eq(mouse.step(p, "tool", 2, { moved = true }), nil, "a hover alone does nothing")
	eq(mouse.step(p, "tool", 2, { click = true }), "banish")
	eq(p.cursor, 3, "on the card last under the mouse")
	eq(p.focus, "cards")
	eq(mouse.step(p, "card", 1, { click = true }), "pick_card")
	eq(mouse.step(p, "card", 1, nil), nil, "no mouse")
end)

test("the_prompts_rects_follow_the_row_and_the_summary_has_a_continue_button", function()
	local k = kit()
	local groups = { { keys = { "R" }, label = "REROLL x1" }, { keys = { "X" }, label = "BANISH x0" } }
	local rects = cards.glyph_rects(k, 960, 300, groups)
	eq(#rects, 2)
	eq(rects[1].x + rects[1].w < rects[2].x, true, "apart")
	near((rects[1].x + rects[2].x + rects[2].w) / 2, 960, "centred")
	local screen = obsidian.module("src/summary_screen")
	local view = { players = { { slot = 1, controls = { { keys = { "E" }, label = "CONTINUE" } } }, { slot = 2, ready = true } } }
	local buttons = screen.buttons(k, view)
	eq(buttons[1] ~= nil, true, "the player who hasn't confirmed")
	eq(buttons[2], nil, "a ready player has none")
	local col = screen.layout(2).columns[1]
	eq(mouse.inside(col, buttons[1].x + buttons[1].w / 2, buttons[1].y + buttons[1].h / 2), true, "in the player's column")
end)

local function with_api(path)
	local had = obsidian.import
	obsidian.import = function() return {} end
	local m = dofile(path)
	obsidian.import = had
	return m
end

test("carpet_bombing_rings_each_cluster_blast_with_smaller_ones_shared_with_the_lobby", function()
	local grenades = with_api("src/grenades.lua")
	local half = function() return 0.5 end
	local spots = grenades.cluster_spots({ x = 0, y = 0, z = 0 }, 3, upgrades.CLUSTER_RADIUS, upgrades.CLUSTER_DELAY, half)
	local all = grenades.with_rings(spots, upgrades.CARPET_RING, upgrades.CARPET_RADIUS, upgrades.CARPET_DELAY, half)
	eq(#all, 3 * (1 + upgrades.CARPET_RING))
	local small = 0
	for _, s in ipairs(all) do if s.small then small = small + 1 eq(s.delay > upgrades.CLUSTER_DELAY - 1e-9, true) end end
	eq(small, 3 * upgrades.CARPET_RING)
	local info = grenades.smaller({ blast_power = 250, blast_radius = 3.5, center_power = 600, force = 300, on_explode_unit_path = "x" }, 0.5)
	eq(info.blast_power, 125)
	near(info.blast_radius, 1.75)
	eq(info.on_explode_unit_path, nil, "no second fire area")
	local side = grenades.new()
	grenades.record(side, "equipment/equipment_grenade_01", all, 4)
	local back = grenades.decode(grenades.encode(side, 7))
	local n = 0
	for _, s in ipairs(back.events[1].spots) do if s.small then n = n + 1 end end
	eq(#back.events[1].spots, #all)
	eq(n, small, "the rings stay small on the other machines")
	eq(#grenades.decode("7;1@2.0@equipment/equipment_grenade_01@1.0,2.0,0.0,0.30").events[1].spots, 1, "an older machine's text")
end)

test("dynamo_charges_the_battery_from_firing", function()
	local battery = with_api("src/battery.lua")
	local full = upgrades.battery_metres(1)
	near(battery.boosted(0, upgrades.DYNAMO_RATE * 1, full), upgrades.DYNAMO_RATE / full)
	eq(battery.boosted(0.5, nil, full), 0.5)
	eq(battery.boosted(0.9, full, full), 1)
end)

return T
