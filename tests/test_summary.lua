-- The end-of-run summary (src/summary.lua, src/summary_screen.lua): the tally, the lobby text, the
-- following of the host, the hold on the mission's end and the screen's layout.
local summary = obsidian.module("src/summary")
local screen = obsidian.module("src/summary_screen")
local upgrades = obsidian.module("src/upgrades")

local T = {}
local function test(name, fn) T[#T + 1] = { name, fn } end

test("a_hit_takes_the_source_of_its_weapon_mark_effect_or_zone", function()
	eq(summary.source_of({ slot = "primary_weapon", item = "weapon_assaultrifle" }), "primary:weapon_assaultrifle")
	eq(summary.source_of({ slot = "sidearm_weapon" }), "sidearm:")
	eq(summary.source_of({ slot = "support_weapon", item = "stratagem_machinegun", mark = "grenade" }), "support:stratagem_machinegun", "a weapon over a mark")
	eq(summary.source_of({ mark = "grenade", self = true }), "grenade")
	eq(summary.source_of({ mark = "kinetic_battery", self = true }), "u:kinetic_battery")
	eq(summary.source_of({ self = true, running = "ignition_rounds" }), "u:ignition_rounds")
	eq(summary.source_of({ self = true }), "melee")
	eq(summary.source_of({ zone = "destroyer_support" }), "u:destroyer_support")
	eq(summary.source_of({}), "stratagems")
end)

test("marks_wait_in_order_and_run_out", function()
	local t = summary.tally()
	local bug = {}
	summary.mark(t, bug, "grenade", 1, 0)
	summary.mark(t, bug, "cluster_grenade", 2, 0.5)
	local source, slot = summary.take_mark(t, bug, 0.6)
	eq(source, "grenade")
	eq(slot, 1)
	source, slot = summary.take_mark(t, bug, 0.7)
	eq(source, "cluster_grenade")
	eq(slot, 2)
	eq(summary.take_mark(t, bug, 0.8), nil, "none left")
	summary.mark(t, bug, "strike_back", 1, 0)
	eq(summary.take_mark(t, bug, summary.MARK_LIFE + 0.1), nil, "too late")
end)

test("a_zone_binds_the_unit_that_hits_in_it", function()
	local t = summary.tally()
	summary.zone(t, "suitable_replacement", 3, { x = 10, y = 10 }, 100)
	summary.zone(t, "not_an_upgrade_with_a_zone", 3, { x = 0, y = 0 }, 100)
	eq(#t.zones, 1)
	local turret = {}
	eq(summary.zone_of(t, turret, { x = 50, y = 50 }, { x = 60, y = 60 }, 101), nil, "far from the call")
	local source, slot = summary.zone_of(t, turret, { x = 11, y = 10 }, { x = 30, y = 30 }, 101)
	eq(source, "suitable_replacement")
	eq(slot, 3)
	eq(summary.zone_of(t, turret, { x = 90, y = 90 }, nil, 500), "suitable_replacement", "bound for good")
	eq(summary.zone_of(t, {}, { x = 10, y = 10 }, nil, 100 + summary.ZONES.suitable_replacement.seconds + 1), nil, "the zone is over")
end)

test("damage_adds_up_by_source_and_the_top_sources_come_first", function()
	local t = summary.tally()
	summary.add_damage(t, 1, "primary:x", 100)
	summary.add_damage(t, 1, "grenade", 300)
	summary.add_damage(t, 1, "primary:x", 50)
	summary.add_damage(t, 1, "melee", 0)
	summary.add_damage(t, nil, "melee", 10)
	summary.add(t, 1, "kills")
	summary.add(t, 1, "samples", 4)
	local p = summary.player(t, 1)
	eq(p.damage, 450)
	eq(p.kills, 1)
	eq(p.samples, 4)
	local top = summary.top(p.sources)
	eq(#top, 2)
	eq(top[1].key, "grenade")
	eq(top[2].damage, 150)
	for i = 1, 8 do summary.add_damage(t, 2, "u:s" .. i, i) end
	eq(#summary.top(summary.player(t, 2).sources), summary.TOP, "five at most")
end)

test("the_lobby_text_round_trips", function()
	local s = summary.new("extracted", 123, 456, 2, 3.5)
	s.time, s.bosses, s.closed = 845.6, 2, true
	local text = summary.encode(s, true, {
		{ slot = 1, ready = true, extracted = true, kills = 120, damage = 34567.4, samples = 88, downs = 3, deaths = 1, saves = 2,
			sources = { { key = "primary:weapon_assaultrifle", damage = 20000 }, { key = "u:kinetic_battery", damage = 900 } } },
		{ slot = 3, ready = false, extracted = false, kills = 0, damage = 0, samples = 0, downs = 0, deaths = 0, saves = 0, sources = {} },
	})
	local d = summary.decode(text)
	eq(d.mission, 123)
	eq(d.run, 456)
	eq(d.seq, 2)
	eq(d.kind, "extracted")
	eq(d.host, true)
	near(d.age, 3.5)
	eq(d.closed, true)
	eq(d.time, 846)
	eq(d.bosses, 2)
	eq(#d.players, 2)
	eq(d.players[1].damage, 34567)
	eq(d.players[1].ready, true)
	eq(d.players[1].sources[2].key, "u:kinetic_battery")
	eq(d.players[2].slot, 3)
	eq(d.players[2].extracted, false)
	eq(#d.players[2].sources, 0)
	eq(summary.decode("nonsense"), nil)
	eq(summary.decode(nil), nil)
	local empty = summary.decode(summary.encode(summary.new("defeated", 1, 2, 1, 0), false, {}))
	eq(empty.kind, "defeated")
	eq(#empty.players, 0)
end)

test("a_machine_follows_the_host_of_its_own_mission_and_run", function()
	local rec = { host = true, mission = 5, run = 9, seq = 1, kind = "defeated", age = 0.5, closed = false }
	eq(summary.follow(nil, rec, 5, 9), "open")
	eq(summary.follow(nil, rec, 6, 9), nil, "another mission")
	eq(summary.follow(nil, rec, 5, 8), nil, "the host's last run")
	eq(summary.follow(nil, { host = false, mission = 5, run = 9, seq = 1, kind = "defeated", age = 0 }, 5, 9), nil, "not the host")
	rec.closed = true
	eq(summary.follow(nil, rec, 5, 9), nil, "first seen closed: missed, nothing to open")
	local s = summary.new("defeated", 5, 1, 1, 0.4)
	eq(summary.follow(s, rec, 5, 9), "close")
	rec.closed = false
	eq(summary.follow(s, rec, 5, 9), nil, "in step")
	rec.age = 4
	eq(summary.follow(s, rec, 5, 9), "sync")
	rec.kind = "cancelled"
	eq(summary.follow(s, rec, 5, 9), "cancel")
	eq(summary.follow(nil, rec, 5, 9), nil, "a cancelled one isn't opened")
	rec.kind, rec.seq = "defeated", 2
	eq(summary.follow(s, rec, 5, 9), "open", "the host's next one")
end)

test("the_screen_shows_after_the_delay_and_the_host_lets_go_when_all_are_ready_or_time_is_up", function()
	local s = summary.new("defeated", 1, 1, 1, 0)
	eq(summary.visible(s), false)
	eq(summary.accepts(s), false)
	summary.step(s, summary.DELAY + 0.1)
	eq(summary.visible(s), true)
	eq(summary.accepts(s), false, "a press right away doesn't count")
	summary.step(s, summary.GRACE)
	eq(summary.accepts(s), true)
	eq(summary.alpha(s), 1)
	eq(summary.should_release(s, { 1, 2 }, { [1] = true }), false, "player 2 hasn't confirmed")
	s.reports.peer = { players = { { slot = 2, ready = true } } }
	eq(summary.should_release(s, { 1, 2 }, summary.ready_set(s)), false, "player 1 is this machine's and hasn't")
	s.ready[1] = true
	eq(summary.should_release(s, { 1, 2 }, summary.ready_set(s)), true)
	local late = summary.new("defeated", 1, 1, 1, summary.DELAY + summary.LIMIT + 0.1)
	eq(summary.left(late), 0)
	eq(summary.should_release(late, { 1 }, {}), true, "time is up")
	late.closed = true
	eq(summary.should_release(late, { 1 }, {}), false, "once")
	eq(summary.should_release(summary.new("defeated", 1, 1, 1, 0.5), { 1 }, { [1] = true }), false, "not before it shows")
end)

-- StateGame.update_host as the hook sees it: a step that ends the mission the way the game does.
local function fake_game()
	local game = { update_host_current_step = 0, game_over_timer = 3, abort_mission = false, game_state = "playing", mission_manager = { extraction_done = false },
		alive = true, ended = false, saw_extraction = nil }
	local function update_host(self)
		self.saw_extraction = self.mission_manager.extraction_done
		if self.alive then self.game_over_timer = 3 else self.game_over_timer = self.game_over_timer - 0.27 end
		if self.game_state ~= "game_over" and (self.mission_manager.extraction_done or (not self.alive and self.game_over_timer < 0)) then
			self.game_state, self.ended = "game_over", true
		end
	end
	return game, update_host
end

local function hooked(h)
	local saved = obsidian.hook
	local hook
	obsidian.hook = function(target, method, fn)
		eq(target .. "." .. method, "StateGame.update_host")
		hook = fn
	end
	summary.install(function() return h end)
	obsidian.hook = saved
	return hook
end

test("the_shuttle_leaving_waits_for_the_summary", function()
	local h = { allowed = true }
	local hook = hooked(h)
	local game, original = fake_game()
	hook(original, game)
	eq(h.kind, nil, "nothing yet")
	game.mission_manager.extraction_done = true
	hook(original, game)
	eq(h.kind, "extracted")
	eq(h.fresh, true)
	eq(game.saw_extraction, false, "the step didn't see the shuttle go")
	eq(game.mission_manager.extraction_done, true, "everything else still does")
	eq(game.ended, false)
	for _ = 1, 50 do hook(original, game) end
	eq(game.ended, false, "held")
	h.released = true
	hook(original, game)
	eq(game.ended, true, "let go")
end)

test("a_wipe_waits_for_the_summary_and_somebody_up_again_cancels_it", function()
	local h = { allowed = true }
	local hook = hooked(h)
	local game, original = fake_game()
	game.alive = false
	hook(original, game)
	eq(h.kind, "defeated", "the countdown started")
	for _ = 1, 100 do hook(original, game) end
	eq(game.ended, false, "held at " .. game.game_over_timer)
	game.alive = true
	hook(original, game)
	eq(h.kind, nil, "cancelled")
	game.alive = false
	hook(original, game)
	eq(h.kind, "defeated", "a new one")
	h.released = true
	hook(original, game)
	eq(game.ended, true, "the mission ends on the next step")
end)

test("the_hold_leaves_aborts_other_steps_and_early_runs_alone", function()
	local h = { allowed = true }
	local hook = hooked(h)
	local game, original = fake_game()
	game.alive, game.abort_mission, game.game_over_timer = false, true, -1
	local abort = function(self) if self.game_over_timer < 0 then self.ended = true end end
	hook(abort, game)
	eq(game.ended, true, "an abort ends at once")
	eq(h.kind, nil)
	local early = { allowed = false }
	hook = hooked(early)
	game, original = fake_game()
	game.mission_manager.extraction_done = true
	hook(original, game)
	eq(game.ended, true, "a run not under way isn't held")
	local off = hooked(nil)
	game, original = fake_game()
	game.mission_manager.extraction_done = true
	off(original, game)
	eq(game.ended, true, "no run, no hold")
	hook = hooked({ allowed = true })
	game, original = fake_game()
	game.update_host_current_step = 4
	game.mission_manager.extraction_done = true
	hook(original, game)
	eq(game.saw_extraction, true, "only step 0 is looked at")
end)

test("summary_text_and_numbers", function()
	eq(screen.number(0), "0")
	eq(screen.number(999), "999")
	eq(screen.number(1000), "1,000")
	eq(screen.number(1234567.4), "1,234,567")
	eq(screen.clock(845), "14:05")
	eq(screen.percent(1, 3), "33%")
	eq(screen.percent(1, 1000), "<1%")
	eq(screen.percent(5, 0), "0%")
	local head = screen.header({ time = 61, level = 7, factions = { "Bugs" }, bosses = 0 })
	eq(#head, 3, "no bosses row without a boss")
	eq(head[3].label, "FACTION")
	eq(#screen.header({ time = 0, factions = { "Bugs", "Cyborgs" }, bosses = 1 }), 4)
	local deps = { by_id = upgrades.by_id, text = function(key) return key == "weapon_pistol" and "P-6 Pistol" or key end, stratagem_icon = function(n) return "icon_" .. n end }
	eq(screen.source_look("u:kinetic_battery", deps).name, "KINETIC BATTERY")
	eq(screen.source_look("u:kinetic_battery", deps).upgrade.id, "kinetic_battery")
	eq(screen.source_look("sidearm:weapon_pistol", deps).name, "P-6 PISTOL")
	eq(screen.source_look("primary:weapon_unknown", deps).name, "PRIMARY WEAPON", "a key the game has no name for")
	eq(screen.source_look("support:stratagem_mg", deps).icon, "icon_stratagem_mg")
	eq(screen.source_look("grenade", deps).name, "GRENADES")
	eq(screen.source_look("whatever", deps).name, "STRATAGEMS")
	for _, s in ipairs(screen.STATS) do
		eq(s.label:find("ITS", 1, true), nil)
	end
end)

-- A kit that records what it draws. Text is 0.5 of its size wide per letter.
local function fake_kit()
	local k = { texts = {} }
	local function size(o) return (o and o.size) or 20 end
	function k:measure(text, opts) return #text * size(opts) * 0.5, size(opts) end
	function k:text(text, x, y, opts)
		local w = self:measure(text, opts)
		local left = (opts and opts.align == "center" and x - w / 2) or (opts and opts.align == "right" and x - w) or x
		self.texts[#self.texts + 1] = { text = text, x = left, y = y, w = w }
	end
	for _, name in ipairs({ "rect", "band", "bar", "poly", "outline", "panel", "hex", "icon", "art" }) do k[name] = function() return false end end
	function k:opacity() return 1 end
	function k:layer(n) if n then self.z = n end return self.z or 0 end
	return k
end

test("columns_stay_on_screen_apart_and_hold_their_rows", function()
	for players = 1, 4 do
		local L = screen.layout(players)
		eq(#L.columns, players)
		for i, c in ipairs(L.columns) do
			eq(c.x >= 0 and c.x + c.w <= screen.W, true, players .. " players, column " .. i)
			if i > 1 then eq(c.x >= L.columns[i - 1].x + L.columns[i - 1].w, true, "apart") end
			local parts = screen.column_parts(c, #screen.STATS, summary.TOP)
			eq(parts.name.y + parts.name.h <= c.y + c.h, true, "the name bar inside")
			eq(parts.sources[summary.TOP] - screen.SOURCE_ROW >= parts.prompt + 32, true, "the last source over the prompt")
			eq(c.y + c.h < L.header.value_y, true, "under the header")
			eq(L.timer.y + L.timer.h < c.y, true, "the timer under the columns")
		end
	end
end)

test("the_screen_draws_for_four_players_and_keeps_text_in_the_columns", function()
	local players = {}
	for slot = 1, 4 do
		local sources = {}
		for i = 1, summary.TOP do sources[i] = { key = i == 1 and "u:destroyer_support" or ("primary:weapon_with_a_very_long_name_" .. i), damage = 1000 * (6 - i) } end
		players[slot] = { slot = slot, name = "A PLAYER NAME THAT IS FAR TOO LONG TO FIT " .. slot, ready = slot == 1, extracted = slot ~= 2,
			controls = slot == 2 and { { keys = { "E" }, label = "CONTINUE" } } or nil,
			stats = { kills = 1234, damage = 15000, samples = 300, downs = 4, deaths = 2, saves = slot == 3 and 2 or 0 }, sources = sources }
	end
	players[4].stats, players[4].sources = nil, nil
	local kit = fake_kit()
	screen.draw(kit, { kind = "extracted", time = 900, level = 20, factions = { "Bugs", "Cyborgs", "Illuminate" }, bosses = 2, alpha = 1, left = 12, t = 0, players = players },
		{ by_id = upgrades.by_id, text = function(k) return k end })
	eq(#kit.texts > 40, true, "it drew")
	local L = screen.layout(4)
	local saw_saves = false
	for _, t in ipairs(kit.texts) do
		if t.text == "DEMOCRACY PROTECTS SAVES" then saw_saves = true end
		if t.y < L.columns[1].y + L.columns[1].h and t.y > L.columns[1].y then
			local inside = false
			for _, c in ipairs(L.columns) do
				if t.x >= c.x - 1 and t.x + t.w <= c.x + c.w + 1 then inside = true end
			end
			eq(inside, true, "'" .. t.text .. "' inside a column")
		end
	end
	eq(saw_saves, true, "a player with saves brings the row in")
	local one = fake_kit()
	screen.draw(one, { kind = "defeated", time = 30, level = 1, factions = {}, bosses = 0, alpha = 0.5, left = 3, t = 1, waiting = true,
		players = { { slot = 1, ready = false, stats = { kills = 0, damage = 0, samples = 0, downs = 0, deaths = 1, saves = 0 }, sources = {} } } }, {})
	local titles = {}
	for _, t in ipairs(one.texts) do titles[t.text] = true end
	eq(titles.DEFEATED, true)
	eq(titles["WAITING FOR THE SQUAD"], true)
	eq(titles["DEMOCRACY PROTECTS SAVES"], nil, "nobody saved: no row")
	eq(titles["LEFT BEHIND"], nil, "no extraction marks after a defeat")
end)

return T
