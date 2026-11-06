-- One Survivors run, from the drop to the end of the mission: the clock, the alarm, the spawner, the
-- orbs, the shared XP, the level-ups and what's drawn over the game.
local rules = obsidian.module("src/rules")
local rng = obsidian.module("src/rng")
local xp = obsidian.module("src/xp")
local upgrades = obsidian.module("src/upgrades")
local evolve = obsidian.module("src/evolve")
local draft = obsidian.module("src/draft")
local director = obsidian.module("src/director")
local bombard = obsidian.module("src/bombard")
local orbs = obsidian.module("src/orbs")
local sync = obsidian.module("src/sync")
local cards = obsidian.module("src/cards")
local input = obsidian.module("src/input")
local level = obsidian.module("src/level")
local native = obsidian.module("src/native")
local samples = obsidian.module("src/samples")
local perks = obsidian.module("src/perks")
local art = obsidian.module("src/art")
local shield = obsidian.module("src/shield")
local fight = obsidian.module("src/fight")
local vacuum = obsidian.module("src/vacuum")
local cards_hud = obsidian.module("src/cards_hud")
local bosses = obsidian.module("src/bosses")
local alarm = obsidian.module("src/alarm")
local battery = obsidian.module("src/battery")
local grenades = obsidian.module("src/grenades")
local spots = obsidian.module("src/spots")
local summary = obsidian.module("src/summary")
local summary_screen = obsidian.module("src/summary_screen")
local card_anim = obsidian.module("src/card_anim")
local redraw = obsidian.module("src/redraw")
local mouse = obsidian.module("src/mouse")
local elites = obsidian.module("src/elites")
local chests = obsidian.module("src/chests")
local trail = obsidian.module("src/trail")
local dive = obsidian.module("src/dive")
local hits = obsidian.module("src/hits")

-- Better HUD draws a Deep Pockets player's grenade count and the time to the next one.
local function grenade_meter(unit, fraction)
	local hud = obsidian.import("alomare.betterhud")
	if type(hud) == "table" and type(hud.grenade_meter) == "function" then pcall(hud.grenade_meter, unit, fraction) end
end

local api = obsidian.import("obsidian.api")

local M = { run = nil }

local BAR, THREAT
local show_hud, share_summary

local function g(name) return rawget(_G, name) end

local function vec(t) return g("Vector3")(t.x, t.y, t.z or 0) end

local function plain(v)
	local V = g("Vector3")
	return { x = V.x(v), y = V.y(v), z = V.z(v) }
end

local function position(unit)
	local ok, v = pcall(g("Unit").world_position, unit, 0)
	return ok and v and plain(v) or nil
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- This machine's players, in the order of the game's player list, the dead too, or a death would move
-- the next player into their place: { unit, slot, pos, record }. unit is nil while dead.
local function local_players()
	local out = {}
	local st = api.game.state()
	for i, record in ipairs(type(st) == "table" and st.players or {}) do
		local go = record.player_go
		if go and go:exists() and go:owned() then
			local unit = api.game.avatar(record)
			local health = unit and api.game.master(unit, "health")
			if health and health.is_dead then unit = nil end
			out[#out + 1] = { unit = unit, slot = i, record = record, pos = unit and position(unit) or nil }
		end
	end
	return out
end

local function all_players()
	local out = {}
	for _, a in ipairs(api.game.all_avatars()) do
		local pos = position(a.unit)
		if pos then out[#out + 1] = { unit = a.unit, pos = pos, is_local = a.owned } end
	end
	return out
end

local function centre(list)
	local x, y, z, n = 0, 0, 0, 0
	for _, p in ipairs(list) do
		if p.pos then x, y, z, n = x + p.pos.x, y + p.pos.y, z + p.pos.z, n + 1 end
	end
	if n == 0 then return nil end
	return { x = x / n, y = y / n, z = z / n }
end

-- The bridge src/upgrades.lua works through. `player` is an index into this machine's players.
local function env_for(run)
	local env = {}
	function env.stat(player, name, value) run.players[player].stats[name] = value end
	function env.add_perk(player, name)
		local list = run.players[player].stats.perks
		list[#list + 1] = name
	end
	-- The call-in is the player's own, so are its kills. Dead, they have no unit: the main player's then.
	-- source: the upgrade calling it, whose damage it is in the run's summary (src/summary.lua).
	function env.call_stratagem(player, name, pos, source)
		local p = run.local_list[player]
		api.stratagems.call(name, vec(pos), 0, p and p.unit)
		if source and p then summary.zone(run.tally, source, p.slot, pos, run.time) end
	end
	-- The enemy nearest to the player at least `least` metres away, so a strike doesn't reach them too.
	function env.nearest_enemy(player, least)
		local p = run.local_list[player]
		if not (p and p.pos) then return nil end
		local best, best_d = nil, math.huge
		for _, unit in ipairs(api.enemies.list()) do
			local at = position(unit)
			if at then
				local d = math.sqrt((at.x - p.pos.x) ^ 2 + (at.y - p.pos.y) ^ 2)
				if d >= (least or 0) and d < best_d then best, best_d = at, d end
			end
		end
		return best
	end
	-- A spot on the map a few steps from the player.
	function env.near(player)
		local p = run.local_list[player]
		return p and p.pos and M.spot_around(p.pos, 5, 9, run.draws) or nil
	end
	function env.random_unlocked(names)
		local open = {}
		for _, name in ipairs(names) do
			if api.catalog.unlocked(name) then open[#open + 1] = name end
		end
		return #open > 0 and open[run.draws:random(1, #open)] or nil
	end
	-- Sweet Liberty: a blast where the player's kill fell, which looks like the player's grenade.
	function env.liberty(player, pos)
		local p = run.local_list[player]
		summary.marking("sweet_liberty", p and p.unit, function()
			M.sparing(function() api.world.explode(vec(pos), rules.LIBERTY_POWER, rules.LIBERTY_RADIUS) end)
		end)
		M.blast_look(run, M.grenade_of(p and p.unit), pos)
		-- Chain Reaction: as many more as a grenade of the player's clusters into, round the blast.
		local stats = run.players[player] and run.players[player].stats
		if stats and stats.chain and (stats.cluster or 0) > 0 then
			run.chain = run.chain or {}
			local spots = grenades.cluster_spots(pos, stats.cluster, upgrades.CHAIN_RADIUS, upgrades.CLUSTER_DELAY, function() return run.draws:random() end)
			for _, s in ipairs(spots) do
				if #run.chain < upgrades.CHAIN_LIMIT then run.chain[#run.chain + 1] = { pos = s, delay = s.delay, player = player } end
			end
		end
	end
	function env.patch_up(player)
		local p = run.local_list[player]
		if p and p.unit then
			api.player.heal(p.unit)
			api.gear.refill(p.unit)
		end
	end
	function env.every(player, id, seconds, fn)
		local key = player .. ":" .. id
		local old = run.timers[key]
		run.timers[key] = { every = seconds, left = old and math.min(old.left, seconds) or seconds, fn = fn }
	end
	function env.on_kill(player, id, fn) run.kill_hooks[player .. ":" .. id] = { player = player, fn = fn } end
	function env.on_death(player, id, fn) run.death_hooks[player .. ":" .. id] = { player = player, fn = fn } end
	return env
end

-- A point on the level `from` to `to` metres around a position. nil when eight tries miss the map.
function M.spot_around(pos, from, to, r)
	local st = api.game.state()
	local map = st and st.generated_level
	for _ = 1, 8 do
		local angle = r:random() * math.pi * 2
		local radius = from + r:random() * (to - from)
		local at = { x = pos.x + math.cos(angle) * radius, y = pos.y + math.sin(angle) * radius, z = pos.z }
		if not map then return at end
		local ok, on = pcall(map.is_position_on_level, map, vec(at))
		if ok and on then return at end
	end
	return nil
end

-- difficulty: the mission's, 1 to 15, which sets how hard the director spawns.
function M.start(mission_seed, difficulty)
	if difficulty == nil then
		local ok, p = pcall(g("DifficultySettings").get_mission_params, mission_seed)
		difficulty = ok and type(p) == "table" and p.difficulty or nil
	end
	local run = {
		time = 0, alarm = false, game_alarm = {}, seed = mission_seed, won = false,
		director = director.new(level.home or "bugs", rng.new(mission_seed), difficulty, mission_seed), bombard = bombard.new(),
		draws = rng.new(mission_seed + (g("Network").peer_id and #tostring(g("Network").peer_id()) or 0) + os.time()),
		orbs = orbs.new(), vacuum = vacuum.new(), battery = battery.new(), grenades = grenades.new(), players = {}, timers = {}, kill_hooks = {}, death_hooks = {},
		choice = nil, shared_at = 0, local_list = {}, looks = {}, liberty_peers = {},
	}
	run.sync = sync.new(mission_seed, run.draws:random(1, 2 ^ 30))
	elites.state, chests.state = elites.new(), chests.new()
	dive.clear()
	run.env = env_for(run)
	-- The end-of-run summary: what each player of this machine did, and the hold on the mission's end.
	run.tally, run.hold, run.slot_by_unit = summary.tally(), { allowed = false }, setmetatable({}, { __mode = "k" })
	summary.on_mark = function(victim, source, owner) M.mark(run, victim, source, owner) end
	summary.on_marking = function(source, owner, fn) return M.marking(run, source, owner, fn) end
	M.run = run
	level.extract_open = false
	obsidian.log("arcade: run started, home faction " .. tostring(level.home) .. ", difficulty " .. tostring(difficulty))
end

-- The game's HUD steps aside for the cards, unless something had it off already.
local function hide_hud(run)
	if run.hud_before == nil then run.hud_before = api.effects.is_on("hide_hud") end
	api.effects.set("hide_hud", true)
	level.choosing = true
end

function show_hud(run)
	level.choosing = false
	if run.hud_before ~= nil then api.effects.set("hide_hud", run.hud_before) end
	run.hud_before = nil
	-- Coming back the HUD drops its images and draws each again only when something about it changes,
	-- or the weapons' icons stay gone until the next swap. A changed fade counts.
	local st = api.game.state()
	for _, info in ipairs(st and st.hud and st.hud.hud_info or {}) do info.previous_fade = nil end
end

-- The world stands still for the cards and the summary: the game pauses as its own pause menu does
-- (Obsidian API's world.time_scale at 0, as Photo Mode uses), so everything stops, enemies included, and
-- comes back as it was. Every machine opens the cards and the summary itself, at the same level or end,
-- so each one pauses its own game (opts.lobby, API 1.33.1) and they all stand still together, give or
-- take the moment the lobby data takes to arrive. With an older API that only pauses alone, the enemies
-- are frozen instead (the API's freeze effect).
function M.hold_world(run, on)
	if on then
		if not run.paused then
			local ok, done = pcall(function()
				if not api.world.time_scale then return false end
				return api.world.time_scale(0, { lobby = true }) == true
			end)
			run.paused = ok and done == true
		end
		if not run.paused then api.effects.set("freeze", true) end
	else
		if run.paused then pcall(api.world.time_scale, 1) end
		run.paused = nil
		api.effects.set("freeze", false)
	end
end

function M.stop()
	local run = M.run
	if not run then return end
	M.run = nil
	for _, p in pairs(run.players) do
		pcall(perks.remove_drones, p)
		perks.release_vehicle(p)
		pcall(trail.release, p)
	end
	-- Lobby data outlives the mission: the next run mustn't read this one's numbers.
	pcall(api.lobby.share, "run", nil)
	pcall(api.lobby.share, "vacuum", nil)
	pcall(api.lobby.share, "liberty", nil)
	pcall(api.lobby.share, "siphon", nil)
	pcall(api.lobby.share, "battery", nil)
	pcall(battery.clear, run.battery, run.players)
	pcall(api.lobby.share, "cluster", nil)
	pcall(api.lobby.share, "summary", nil)
	summary.on_mark, summary.on_marking = nil, nil
	run.grenades.queue = {}
	for n, l in ipairs(run.local_list) do
		if l.unit then grenade_meter(l.unit, nil) end
	end
	samples.clear()
	cards_hud.clear()
	pcall(bosses.on_run_stop)
	pcall(elites.clear)
	pcall(chests.clear)
	dive.clear()
	fight.clear()
	shield.clear()
	input.release_now()
	input.cursor("game")
	M.hold_world(run, false)
	api.effects.set("camera_distance", false)
	if run.god_before ~= nil then api.effects.set("god", run.god_before) end
	show_hud(run)
	obsidian.log(string.format("arcade: run over at %s, level %d", clock(run.time), sync.level(run.sync)))
end

local function player_state(run, n)
	run.players[n] = run.players[n] or { owned = {}, absorbed = {}, stats = perks.stats(), weapon_cache = {}, stratagems = {}, redraw = redraw.new() }
	return run.players[n]
end

-- Every player of this machine gains rerolls (a vacuum went off) or banishes (an objective done):
-- `count` of those events.
local function grant_all(run, kind, count)
	if count <= 0 then return end
	local n = 0
	for i in ipairs(run.local_list) do
		redraw.add(player_state(run, i).redraw, kind, redraw.gain(kind, count))
		n = i
	end
	obsidian.log("arcade: " .. n .. " players gain " .. redraw.gain(kind, count) .. " " .. kind)
end

-- The stats of this machine's player whose body `unit` is, or nil: nobody's, or no run.
function M.stats_of(unit)
	local run = M.run
	if not run or unit == nil then return nil end
	for n, l in ipairs(run.local_list) do
		if l.unit == unit then return player_state(run, n).stats end
	end
	return nil
end

-- The run's clock, in seconds of play.
function M.clock()
	return M.run and M.run.time or 0
end

-- The grenade a player carries, by its unit's path: the inventory keeps it on every machine, and the
-- loadout keeps its package loaded. The game's own grenade when there's no telling.
local GRENADE = "equipment/equipment_grenade_01"
function M.grenade_of(unit)
	if unit == nil then return GRENADE end
	local ok, inventory = pcall(g("EntityAux").state, unit, "inventory")
	local path = ok and type(inventory) == "table" and inventory.grenade_unit_path
	return type(path) == "string" and path ~= "" and path or GRENADE
end

-- A grenade going off at `pos`, for the eyes and ears only: the particle effect and the sound of the
-- grenade's explosion, as the game's explosion manager plays them (the effect and audio of the grenade's
-- explosive_info, ExplosionManager.do_explosion), at most BLAST_LOOKS in BLAST_LOOK_SECONDS. The blast
-- itself is Obsidian API's explode. Before, a copy of the grenade's unit played its on_explode flow,
-- which some grenades' flows can't run on a unit that isn't one of the game's entities.
function M.explosive_info(path)
	local lsm = g("LuaSettingsManager")
	local ok, settings = pcall(lsm.get_settings_by_unit_path, lsm, path)
	local info = ok and type(settings) == "table" and settings.explosive_info
	return type(info) == "table" and info or nil
end

function M.blast_look(run, path, pos)
	if not pos or #run.looks >= rules.BLAST_LOOKS then return end
	local info = M.explosive_info(path or GRENADE) or M.explosive_info(GRENADE)
	local st = api.game.state()
	local proxy = type(st) == "table" and st.world_proxy
	if not (info and proxy) then return end
	local world, at = proxy:get_world(), vec(pos)
	if type(info.effect) == "string" then pcall(g("World").create_particles, world, info.effect, at) end
	if type(info.audio) == "string" then
		pcall(function() g("TimpaniWorld").trigger_event(g("World").timpani_world(world), info.audio, at) end)
	end
	run.looks[#run.looks + 1] = { left = rules.BLAST_LOOK_SECONDS }
end

-- A look leaves nothing in the level to take away: run.looks only counts the recent ones, against
-- BLAST_LOOKS.
local function update_looks(run, dt)
	for i = #run.looks, 1, -1 do
		local look = run.looks[i]
		look.left = look.left - dt
		if look.left <= 0 then table.remove(run.looks, i) end
	end
end

-- Sweet Liberty's and Chain Reaction's blasts hurt enemies only: the hits on Helldivers are dropped as
-- the explosion sends them, a physics step after the call (src/hits.lua). At melee range the blast came
-- down on the player.
local function spare_helldivers(unit, interface, command)
	if hits.is_hit(interface, command) and hits.is_helldiver(unit) then return false end
end

function M.sparing(fn)
	hits.with(spare_helldivers, fn)
end

-- The machine whose player made a kill, when it isn't this one: that player's peer, or nil.
local function peer_of(killer)
	if killer == nil then return nil end
	for _, a in ipairs(api.game.all_avatars()) do
		if a.unit == killer and not a.owned then
			local ok, peer = pcall(a.record.player_go.owner, a.record.player_go)
			return ok and peer or nil
		end
	end
	return nil
end

-- An enemy died: an orb where it fell, on every machine, and the kill effects of the player who did it.
-- A teammate's Sweet Liberty kill shows its blast here too. The host rolls for an ammo box.
function M.on_killed(unit, attacker, owner)
	local run = M.run
	if not run or run.exiting then return end
	-- A destroyed unit's get_data takes the game down, past the pcall (src/grenades.lua).
	local ok_alive, alive = pcall(g("Unit").alive, unit)
	if not (ok_alive and alive) then return end
	local ok, path = pcall(g("Unit").get_data, unit, "unit_path")
	local enemy = ok and path and api.catalog.enemy(path)
	if not enemy then return end
	local pos = position(unit)
	if not pos then return end
	local tier = director.tier_of(enemy.key) or (enemy.boss and 5) or 1
	-- Every machine hears every kill, so each counts the bosses for itself; a kill counts for the
	-- player of this machine who made it.
	if not run.summary then
		if enemy.boss then run.tally.bosses = run.tally.bosses + 1 end
		summary.add(run.tally, run.slot_by_unit[owner or attacker or false], "kills")
	end
	if rules.drops_sample(pos.x, pos.y) then orbs.drop(run.orbs, pos, rules.ORB_XP[tier], enemy.faction, M.siphon_home(run, pos)) end
	-- Napalm Needles: a burning enemy leaves a poison cloud.
	pcall(fight.killed, fight.state, unit, pos, run.time)
	for _, hook in pairs(run.kill_hooks) do
		local p = run.local_list[hook.player]
		if p and (owner == p.unit or attacker == p.unit) then pcall(hook.fn, pos) end
	end
	local killer = owner or attacker
	local peer = next(run.liberty_peers) ~= nil and peer_of(killer)
	if peer and run.liberty_peers[peer] then M.blast_look(run, M.grenade_of(killer), pos) end
	if api.game.is_host() and rules.drops_ammo(run.draws) then M.drop_ammo(run, pos) end
	-- Elites (src/elites.lua) and chests (src/chests.lua): the host drops a chest for an elite, a boss,
	-- or now and then any kill.
	local ok_e, kind = pcall(elites.on_killed, unit, pos, enemy.faction)
	pcall(chests.on_kill, pos, enemy.boss, ok_e and kind ~= nil, function() return run.draws:random() end)
end

-- Sample Siphon: the player a kill at `pos` sends its sample to, the nearest within reach who has it,
-- or nil. Every machine knows who has it (the lobby's "siphon", M.share), so the sample flies to the same
-- player everywhere.
function M.siphon_home(run, pos)
	local best, best_d
	for _, a in ipairs(api.game.all_avatars()) do
		local reach
		if a.owned then
			reach = M.stats_of(a.unit) and M.stats_of(a.unit).siphon or 0
		else
			local ok, peer = pcall(function() return a.record.player_go:owner() end)
			reach = ok and run.siphon_peers and run.siphon_peers[peer] or 0
		end
		local at = reach > 0 and position(a.unit)
		if at then
			local d = math.sqrt((at.x - pos.x) ^ 2 + (at.y - pos.y) ^ 2)
			if d <= reach and (not best_d or d < best_d) then best, best_d = a.unit, d end
		end
	end
	return best
end

-- Chain Reaction: blasts queued after a Sweet Liberty blast, { pos, delay, player }, each like it.
local function step_chain(run, dt)
	for i = #(run.chain or {}), 1, -1 do
		local q = run.chain[i]
		q.delay = q.delay - dt
		if q.delay <= 0 then
			table.remove(run.chain, i)
			local p = run.local_list[q.player]
			summary.marking("chain_reaction", p and p.unit, function()
				M.sparing(function() api.world.explode(vec(q.pos), rules.LIBERTY_POWER, rules.LIBERTY_RADIUS) end)
			end)
			M.blast_look(run, M.grenade_of(p and p.unit), q.pos)
		end
	end
end

-- Taking damage: Panic's regeneration starts, and a Noxious elite's hit poisons. info: the hit.
function M.on_damage(unit, info)
	local run = M.run
	if not run then return end
	for n, l in ipairs(run.local_list) do
		if l.unit == unit then
			pcall(elites.on_player_hit, unit, info)
			perks.panic(player_state(run, n))
		end
	end
end

-- The summary's tally (src/summary.lua) -------------------------------------------------------------

-- The slot of this machine's player whose body `unit` is, or was: a hit can land after a death.
local function slot_of(run, unit)
	if unit == nil then return nil end
	return run.slot_by_unit[unit]
end

-- An upgrade's hit to come on `victim`, for the player whose body is `owner`; the main player's when
-- that's nobody of this machine (api.enemies.damage names the main player).
function M.mark(run, victim, source, owner)
	local slot = slot_of(run, owner) or (run.local_list[1] and run.local_list[1].slot)
	if slot then summary.mark(run.tally, victim, source, slot, os.clock()) end
end

-- fn(), with every hit it sends marked for `source`: an explosion sends its hits a physics step after
-- the call (src/hits.lua). Only for a player of this machine, whose machine counts the hits.
function M.marking(run, source, owner, fn)
	local slot = slot_of(run, owner)
	if not slot then return fn() end
	local tally = run.tally
	return hits.with(function(unit, interface, command)
		if hits.is_hit(interface, command) then summary.mark(tally, unit, source, slot, os.clock()) end
	end, fn)
end

-- A weapon's name for the summary: the item of a primary or sidearm, the stratagem of a support
-- weapon. Kept by weapon unit.
local weapon_items = setmetatable({}, { __mode = "k" })
local function weapon_item(slot, weapon)
	if weapon == nil then return nil end
	local known = weapon_items[weapon]
	if known ~= nil then return known or nil end
	local ok_alive, alive = pcall(g("Unit").alive, weapon)
	if not (ok_alive and alive) then return nil end
	local paths = {}
	for _, key in ipairs({ "unit_path", "settings_path" }) do
		local ok, path = pcall(g("Unit").get_data, weapon, key)
		if ok and type(path) == "string" then paths[#paths + 1] = path end
	end
	local item
	for _, path in ipairs(paths) do
		if slot == "support_weapon" then
			local lsm = g("LuaSettingsManager")
			local ok, settings_path = pcall(function() return lsm:get_settings_path_by_unit_path(path) end)
			for _, s in ipairs(api.catalog.support_weapons()) do
				if s.unit_path == path or (ok and s.unit_path == settings_path) then item = s.name end
			end
		else
			item = item or api.catalog.item_name(path)
		end
		if item then break end
	end
	weapon_items[weapon] = item or false
	return item
end

local function flat_position(unit)
	if unit == nil then return nil end
	local ok, alive = pcall(g("Unit").alive, unit)
	return ok and alive and position(unit) or nil
end

-- A hit a player of this machine landed (Obsidian API's combat.on_hit): its damage goes to its source.
function M.on_hit(victim, hit)
	local run = M.run
	if not run or run.summary or run.exiting or type(hit) ~= "table" then return end
	local ok, enemy = pcall(g("EntityAux").has_component, victim, "enemy")
	if not (ok and enemy) then return end
	local slot = slot_of(run, hit.owner_unit)
	local h = { slot = hit.slot, self = hit.attacker_unit ~= nil and hit.attacker_unit == hit.owner_unit }
	if hit.slot then
		h.item = weapon_item(hit.slot, hit.attacker_unit)
	else
		local source, marked = summary.take_mark(run.tally, victim, os.clock())
		if source then
			h.mark, slot = source, marked or slot
		elseif h.self then
			local running = fight.state and fight.state.running[victim]
			for kind, id in pairs(summary.RUNNING) do
				if running and running[kind] and running[kind] > run.time then h.running = id end
			end
		else
			local zone, zslot = summary.zone_of(run.tally, hit.attacker_unit, flat_position(hit.attacker_unit), flat_position(victim), run.time)
			if zone then h.zone, slot = zone, zslot or slot end
		end
	end
	summary.add_damage(run.tally, slot, summary.source_of(h), hit.damage)
end

-- Democracy Protects saved a player of this machine.
function M.on_spare(unit)
	local run = M.run
	if run and not run.summary then summary.add(run.tally, slot_of(run, unit), "saves") end
end

-- An objective done: the host adds rules.OBJECTIVE_SAMPLES to the squad's samples, so they count once.
function M.on_objective()
	local run = M.run
	if not run or run.won or not api.game.is_host() then return end
	sync.collected(run.sync, rules.OBJECTIVE_SAMPLES)
	-- Counted in the run's shared value, so every machine hands out the banishes (M.update).
	sync.objective_done(run.sync)
	obsidian.log("arcade: objective done, +" .. rules.OBJECTIVE_SAMPLES .. " samples")
end

-- One enemy, as a group of one: Obsidian API's spawn of a single enemy goes through the encounter
-- manager's spawn_enemy, which does nothing once 16 enemies are alive (GameSettings
-- .MAX_NUM_ALLOWED_ENEMIES) and still answers true. A group isn't held to that cap.
local function spawn_one(key, at)
	local enemy = api.catalog.enemy(key)
	local st = api.game.state()
	local em = type(st) == "table" and st.encounter_manager
	if not (enemy and enemy.unit and em) then return api.enemies.spawn(key, 1, vec(at)) end
	local ok, err = pcall(em.spawn_group, em, vec(at), { units = { { unit_path = enemy.unit, amount = 1 } } })
	return ok, err
end

-- Host only: spawns what the director asks for in a ring around the squad, on the map. A boss is
-- src/bosses.lua's: the faction's real boss, from its own package.
local function spawn(run, plan, squad)
	if not squad then return end
	for _, sp in ipairs(plan) do
		if sp.tier == 5 then
			local ok, why = bosses.spawn(run.time / 60, squad)
			if not ok then obsidian.log("arcade: no boss: " .. tostring(why)) end
		else
			-- Away from the map's border and on open ground (src/spots.lua), so the group can't end up in
			-- or behind the border walls.
			local st = api.game.state()
			local checks = spots.of_level(type(st) == "table" and st.generated_level or nil, api.world and api.world.raycast)
			local at
			if checks then
				at = spots.around(squad, rules.SPAWN_RING[1], rules.SPAWN_RING[2], run.director.rng, checks)
				if not at then obsidian.log("arcade: no clear spot for " .. sp.key) end
			else
				at = M.spot_around(squad, rules.SPAWN_RING[1], rules.SPAWN_RING[2], run.director.rng)
			end
			if at then
				local done, why
				if sp.count == 1 then done, why = spawn_one(sp.key, at) else done, why = api.enemies.spawn(sp.key, sp.count, vec(at)) end
				if not done then obsidian.log("arcade: " .. sp.key .. " didn't spawn: " .. tostring(why)) end
			end
		end
	end
end

-- Host only: an ammo box where a kill fell, or just beside it when that spot is off the map. At the
-- limit the box furthest from the squad goes, so what the squad left behind doesn't use up the limit.
local AMMO_BOX = "gameobjects/pickup_ammunitionbox_01"
function M.drop_ammo(run, pos)
	local from = run.squad or pos
	local count, furthest, far = 0, nil, -1
	for unit in pairs(api.game.masters("ammo_pickup")) do
		count = count + 1
		local at = position(unit)
		if at then
			local d = (at.x - from.x) ^ 2 + (at.y - from.y) ^ 2
			if d > far then furthest, far = unit, d end
		end
	end
	local st = api.game.state()
	if count >= rules.AMMO_LIMIT and furthest then pcall(st.entity_spawner.despawn_entity, st.entity_spawner, furthest) end
	local at = M.spot_around(pos, 0, 1.5, run.draws)
	if at then
		local ok, why = api.enemies.spawn_entity(AMMO_BOX, vec(at))
		if not ok then obsidian.log("arcade: no ammo box: " .. tostring(why)) end
	end
end

-- What a player is allowed to be offered: what their unlocks and their weapon can use.
local function allowed_for(run, n)
	local l = run.local_list[n]
	local primary
	for _, w in ipairs(l and l.unit and api.gear.weapons_of(l.unit) or {}) do
		if w.slot == "primary_weapon" then primary = w.info end
	end
	local held = {}
	local main = l and l.unit and perks.main_perk(l.unit)
	if main then held[main] = true end
	for _, name in ipairs(player_state(run, n).stats.perks) do held[name] = true end
	return function(u)
		-- Drones and melee tuning came in Obsidian API 1.7.0, and add_drone is how to tell.
		if u.newer_api and not api.gear.add_drone then return false end
		if u.api and not upgrades.has_api(api, u.api) then return false end
		-- A perk the player owns and doesn't hold yet, and an API that adds perks (1.9.0).
		if u.perk then return api.gear.add_perk ~= nil and upgrades.perk_open(u, held, api.catalog.unlocked) end
		if u.primary and primary and (tonumber(primary[u.primary]) or 0) <= 0 then return false end
		if not u.needs then return true end
		for _, name in ipairs(u.needs) do
			if api.catalog.unlocked(name) then return true end
		end
		return false
	end
end

-- The stratagems a player owns and could add: not the ones every player has.
local function stratagem_pool()
	local fixed = {}
	local ls = g("LoadoutSettings")
	for _, name in ipairs(ls and ls.static_stratagems or {}) do fixed[name] = true end
	local out = {}
	for _, s in ipairs(api.catalog.stratagems()) do
		if not fixed[s.name] and s.icon and api.catalog.unlocked(s.name) then
			out[#out + 1] = { id = s.name, name = api.catalog.text(s.name), icon = s.icon, kind = s.stratagem_type }
		end
	end
	return out
end

local function stratagems_of(l)
	local inv = l and l.unit and api.game.master(l.unit, "inventory")
	return inv and inv.stratagems and #inv.stratagems or 0
end

-- A row of `count` cards for player n at level lvl: what draft.roll offers, without what they banished.
-- also: a filter on top, for a banish's one card.
local function roll_row(run, n, lvl, count, also)
	local p = player_state(run, n)
	local allowed = redraw.allowed(p.redraw, allowed_for(run, n))
	local filter = allowed
	if also then filter = function(u) return also(u) and allowed(u) end end
	return draft.roll(p.owned, lvl, run.draws, count, filter, p.absorbed)
end

local function open_choice(run, lvl)
	local list = {}
	for n, l in ipairs(run.local_list) do
		local p = player_state(run, n)
		local stats = p.stats
		local count = rules.CARDS + stats.extra_cards
		local entry = { row = roll_row(run, n, lvl, count), count = count, cursor = 1, chosen = nil, focus = "cards", dealt_at = 0, slot_at = {}, leaving = {} }
		if draft.offers_stratagems(lvl, stratagems_of(l)) then
			entry.strats = draft.roll_stratagems(stratagem_pool(), run.draws, rules.STRATAGEM_CHOICES + stats.extra_stratagems, draft.stratagem_kind(lvl),
				draft.first_stratagem_pick(lvl) and draft.ANTI_TANK or nil)
			if #entry.strats == 0 then entry.strats = nil else entry.strat_cursor = 1 end
		end
		list[n] = entry
		-- A level refills health.
		if l.unit then api.player.heal(l.unit) end
	end
	-- Players on one machine choose in turn, from player 1, each on the whole screen with a full timer.
	-- clock: real seconds since the screen came up, for the motion (src/card_anim.lua). chained: straight
	-- after another level's cards, so the backdrop is dark already.
	run.choice = { level = lvl, players = list, left = rules.CHOOSE_LIMIT, turn = 1, clock = 0, turn_at = 0, chained = run.chained == true }
	run.chained = nil
	-- Invulnerability a player already had, from the Trainer say, stays after the choice.
	if run.god_before == nil then run.god_before = api.effects.is_on("god") end
	M.hold_world(run, true)
	api.effects.set("god", true)
	hide_hud(run)
	input.hold()
	M.play_at(rules.SOUNDS.level_up, rules.LEVEL_UP_VOLUME)
	obsidian.log("arcade: level " .. lvl .. ", choosing")
end

local reapply

local function take(run, n, u)
	local p = player_state(run, n)
	-- An evolution uses both halves up: they leave the build, and the stats start over with the
	-- evolution applying them at their stacks (src/evolve.lua).
	if u.evolves then
		evolve.take(p.owned, p.absorbed, u)
		reapply(run, n)
		obsidian.log("arcade: player " .. n .. " evolved " .. u.evolves[1] .. " and " .. u.evolves[2] .. " into " .. u.id)
		return
	end
	p.owned[u.id] = (p.owned[u.id] or 0) + 1
	local ok, err = pcall(u.apply, run.env, p.owned[u.id], n, p.absorbed)
	if not ok then obsidian.log("arcade: " .. u.id .. " failed: " .. tostring(err)) end
	obsidian.log("arcade: player " .. n .. " took " .. u.id .. " (" .. p.owned[u.id] .. ")")
end

-- A chest (src/chests.lua): `count` upgrades of `rarity` for player n, drawn as the cards are, and
-- taken at once. Answers the upgrades.
function M.grant(n, rarity, count)
	local run = M.run
	if not (run and run.local_list[n]) then return {} end
	local row = roll_row(run, n, sync.level(run.sync), count, function(u) return u.rarity == rarity end)
	for _, u in ipairs(row) do take(run, n, u) end
	return row
end

-- The debug page (src/debug.lua): an upgrade's stacks set directly. The player's stats start over and
-- every upgrade held is applied again at its stacks, so a removed one leaves nothing behind. An
-- evolution set to 0 gives its halves back.
function M.set_stacks(n, id, count)
	local run = M.run
	local u = upgrades.by_id[id]
	if not (run and u) then return false end
	local p = player_state(run, n)
	-- The debug page may go past the upgrade's own limit (src/debug.lua).
	count = math.max(0, math.floor(count))
	if u.evolves and count == 0 then
		evolve.undo(p.owned, p.absorbed, u)
	else
		p.owned[id] = count > 0 and count or nil
	end
	reapply(run, n)
	obsidian.log("arcade: debug: player " .. n .. " " .. id .. " = " .. count)
	return true
end

-- The debug page: evolution `id`, its halves set up first (the first at its max).
function M.give_evolution(n, id)
	local run = M.run
	local e = upgrades.by_id[id]
	if not (run and e and e.evolves) then return false, "no_run" end
	local p = player_state(run, n)
	if (p.owned[id] or 0) > 0 then return false, "held" end
	-- A half another evolution used up comes back from it first.
	for _, other in ipairs(upgrades.EVOLUTIONS) do
		local shares = other.evolves[1] == e.evolves[1] or other.evolves[1] == e.evolves[2] or other.evolves[2] == e.evolves[1] or other.evolves[2] == e.evolves[2]
		if shares and (p.owned[other.id] or 0) > 0 then evolve.undo(p.owned, p.absorbed, other) end
	end
	evolve.set_up(p.owned, e)
	take(run, n, e)
	return true
end

-- Every upgrade player n holds applied again at its stacks, on fresh stats.
function reapply(run, n)
	local p = player_state(run, n)
	p.stats = perks.stats()
	local prefix = n .. ":"
	for _, list in ipairs({ run.timers, run.kill_hooks, run.death_hooks }) do
		for key in pairs(list) do
			if key:sub(1, #prefix) == prefix then list[key] = nil end
		end
	end
	for _, held in ipairs(upgrades.list) do
		local stacks = p.owned[held.id]
		if stacks then
			local ok, err = pcall(held.apply, run.env, stacks, n, p.absorbed)
			if not ok then obsidian.log("arcade: " .. held.id .. " failed: " .. tostring(err)) end
		end
	end
end

-- The debug page: one more reroll or banish for player n. kind: "rerolls" or "banishes".
function M.add_redraw(n, kind)
	local run = M.run
	if not run then return false, "no_run" end
	redraw.add(player_state(run, n).redraw, kind, 1)
	return true
end

-- Whether player n could be offered upgrade `id` now.
function M.allowed(n, id)
	local run = M.run
	local u = upgrades.by_id[id]
	if not (run and u and run.local_list[n]) then return false end
	local ok, yes = pcall(function() return allowed_for(run, n)(u) end)
	return ok and yes == true
end

function M.stacks(n, id)
	local run = M.run
	return run and run.players[n] and run.players[n].owned[id] or 0
end

-- Samples' XP for the team, as collecting them gives it.
function M.add_xp(amount)
	local run = M.run
	if not run then return false end
	sync.collected(run.sync, amount)
	return true
end

-- Enough XP for the next level.
function M.level_up()
	local run = M.run
	if not run then return false end
	local _, into, need = xp.level_of(sync.team_xp(run.sync))
	sync.collected(run.sync, math.max(1, need - into))
	return true
end

-- The run's clock, which sets the Heat, the factions and the bosses due. The host's clock is
-- everyone's, so only the host's moves.
function M.set_minutes(minutes)
	local run = M.run
	if not run then return false, "no_run" end
	if not api.game.is_host() then return false, "host_only" end
	run.time = math.max(0, minutes * 60)
	-- The director follows, with the bosses before the new time counted as come.
	director.take_over(run.director, run.time)
	return true
end

function M.spawn_boss()
	local run = M.run
	if not run then return false, "no_run" end
	if not api.game.is_host() then return false, "host_only" end
	return bosses.spawn(run.time / 60, run.squad)
end

function M.fill_battery(n)
	local run = M.run
	local p = run and run.players[n]
	if not (p and p.battery) then return false end
	p.battery.charge = 1
	return true
end

local function take_stratagem(run, n, name)
	local p = player_state(run, n)
	local have = false
	for _, s in ipairs(p.stratagems) do have = have or s == name end
	if not have then p.stratagems[#p.stratagems + 1] = name end
	local l = run.local_list[n]
	if l and l.unit then
		local ok, why = api.stratagems.give(name, l.unit)
		if not ok then obsidian.log("arcade: no " .. name .. ": " .. tostring(why)) end
	end
	obsidian.log("arcade: player " .. n .. " took " .. name)
end

-- Everyone has chosen: what's picked now is what counts.
local function confirm_all(run)
	for n, p in ipairs(run.choice.players) do
		take(run, n, upgrades.by_id[p.chosen])
		if p.strats then take_stratagem(run, n, p.strat_pick) end
	end
end

-- Moves and picks with one input. Up and down go between the rows when there are two. A pick can be
-- swapped for another until everyone has chosen.
-- A reroll: the whole row drawn again by the same rules, dealt in again.
local function try_reroll(run, c, n, p)
	local b = player_state(run, n).redraw
	local row = redraw.reroll(b, function() return roll_row(run, n, c.level, p.count or #p.row) end)
	if not row or #row == 0 then return false end
	p.row, p.cursor = row, math.min(p.cursor, #row)
	local still = false
	for _, u in ipairs(row) do still = still or u.id == p.chosen end
	if not still then p.chosen = nil end
	p.dealt_at, p.slot_at, p.leaving = c.clock, {}, {}
	obsidian.log("arcade: player " .. n .. " rerolled, " .. b.rerolls .. " left")
	return true
end

-- A banish of the card under the cursor: it greys and sinks away, and a new one rises in the same slot.
local function try_banish(run, c, n, p)
	local b = player_state(run, n).redraw
	local slot = p.cursor
	local gone, new = redraw.banish(b, p.row, slot, function(filter) return roll_row(run, n, c.level, 1, filter) end, upgrades.fallback and upgrades.fallback.id)
	if not gone then return false end
	p.leaving[#p.leaving + 1] = { u = gone, slot = slot, at = c.clock }
	if new then
		p.slot_at[slot] = c.clock
	else
		-- Nothing new to draw: the row closes up.
		p.slot_at, p.leaving = {}, {}
		p.cursor = math.min(p.cursor, #p.row)
	end
	if p.chosen == gone.id then p.chosen = nil end
	obsidian.log("arcade: player " .. n .. " banished " .. gone.id .. ", " .. b.banishes .. " left")
	return true
end

local function step_input(run, c, n, p, ev)
	if ev.reroll and try_reroll(run, c, n, p) then api.audio.play(rules.SOUNDS.card_pick) return end
	if ev.banish and (not p.strats or p.focus == "cards") and try_banish(run, c, n, p) then api.audio.play(rules.SOUNDS.card_pick) return end
	local row = p.focus == "strats" and p.strats or p.row
	local was_card, was_strat, was_focus = p.cursor, p.strat_cursor, p.focus
	if p.strats then
		if ev.up then p.focus = "cards" end
		if ev.down then p.focus = "strats" end
		if ev.left or ev.right then
			local step = ev.left and -1 or 1
			if p.focus == "cards" then p.cursor = math.max(1, math.min(#row, p.cursor + step)) end
			if p.focus == "strats" then p.strat_cursor = math.max(1, math.min(#row, p.strat_cursor + step)) end
		end
	else
		if ev.left or ev.up then p.cursor = math.max(1, p.cursor - 1) end
		if ev.right or ev.down then p.cursor = math.min(#p.row, p.cursor + 1) end
	end
	local picked = false
	if ev.select then
		if p.focus == "cards" then
			p.chosen, picked = p.row[p.cursor].id, true
			if p.strats and not p.strat_pick then p.focus = "strats" end
		else
			p.strat_pick, picked = p.strats[p.strat_cursor].id, true
			if not p.chosen then p.focus = "cards" end
		end
	end
	-- The mouse, the first local player's only (src/mouse.lua): hover focuses, a click picks, and the
	-- prompts under the cards reroll and banish.
	local m = n == 1 and ev.mouse or nil
	local kind, over = nil, nil
	if m then kind, over = M.under_mouse(c, n, m) end
	p.tool_hover = kind == "tool" and over or nil
	local act = mouse.step(p, kind, over, m)
	if act == "reroll" or act == "banish" then
		local ok = (act == "reroll" and try_reroll or try_banish)(run, c, n, p)
		if ok then api.audio.play(rules.SOUNDS.card_pick) return end
	elseif act == "pick_card" then
		p.chosen, picked = p.row[over].id, true
	elseif act == "pick_strat" then
		p.strat_pick, picked = p.strats[over].id, true
	end
	if not picked and (p.cursor ~= was_card or p.strat_cursor ~= was_strat or p.focus ~= was_focus) then
		api.audio.play(rules.SOUNDS.card_move)
	end
	if picked then api.audio.play(rules.SOUNDS.card_pick) end
end

local function has_chosen(p)
	return p.chosen ~= nil and (not p.strats or p.strat_pick ~= nil)
end

local is_bot

local function pick_for(p)
	p.chosen = p.chosen or p.row[p.cursor].id
	if p.strats then p.strat_pick = p.strat_pick or p.strats[p.strat_cursor].id end
end

-- The next player's turn with a full timer, past any bots, who take what's under their cursor. It ends the
-- choice for this machine after the last.
local function next_turn(run, c)
	while c.turn < #c.players do
		c.turn = c.turn + 1
		if not is_bot(run.local_list[c.turn]) then
			c.left = rules.CHOOSE_LIMIT
			c.turn_at = c.clock
			c.players[c.turn].dealt_at = c.clock
			input.release(rules.INPUT_GRACE)
			return
		end
		pick_for(c.players[c.turn])
	end
	c.finished = true
	sync.chose(run.sync, c.level)
end

-- The player whose turn it is reads their own pad, or every device when they're alone on this
-- machine. Once they've chosen, the next player gets the screen and a full timer.
-- Real time keeps the motion going while the game is paused (GAME_DT is 0 then). A pick holds the
-- chosen card for a moment (rules.PICK_HOLD) before the turn moves on.
local function step_choice(run, dt_real)
	local c = run.choice
	c.clock = c.clock + dt_real
	if c.finished then return end
	local n = c.turn
	local p = c.players[n]
	local presses = input.read()
	if p.picked_at then
		if card_anim.pick_done(c.clock - p.picked_at) then next_turn(run, c) end
		return
	end
	c.left = c.left - dt_real
	-- Just up, the cards take nothing: a click meant as a shot would pick one, and the cards are still
	-- coming in.
	if not card_anim.accepts_input(c.clock - c.turn_at, #p.row) then return end
	local inputs = {}
	if #c.players == 1 then
		for _, ev in pairs(presses) do inputs[#inputs + 1] = ev end
	else
		inputs[1] = presses[M.pad_of(run.local_list[n], n)]
	end
	for _, ev in ipairs(inputs) do step_input(run, c, n, p, ev) end
	if c.left <= 0 then pick_for(p) end
	if has_chosen(p) then p.picked_at = c.clock end
end

-- The input a local player picks with: the game's own pad number, 0 for the keyboard and mouse and then
-- PadManager's pads, as input.read numbers them.
function M.pad_of(l, n)
	local pad = l and l.record and l.record.pad_number
	return type(pad) == "number" and pad or n - 1
end

-- A player who died: what they took for that moment. pos is where they last stood.
local function fire_death(run, n, pos)
	for _, hook in pairs(run.death_hooks) do
		if hook.player == n and pos then
			local ok, err = pcall(hook.fn, pos)
			if not ok then obsidian.log("arcade: on death failed: " .. tostring(err)) end
		end
	end
end

-- The evolutions' part in a Kinetic Battery frame (battery.sync's opts): Dynamo's charge from firing.
function M.battery_opts(stats, unit, dt)
	local opts = {}
	if (stats.dynamo or 0) > 0 and dt > 0 and perks.firing(unit) then opts.metres = stats.dynamo * dt end
	return opts
end

local function sync_players(run, dt_game, dt_real)
	local st = api.game.state()
	for n, l in ipairs(run.local_list) do
		local p = player_state(run, n)
		p.battery = p.battery or battery.new_player()
		if l.unit then
			pcall(perks.sync, p, l.unit, dt_game, dt_real)
			local ok, err = pcall(battery.sync, p.battery, p.stats.battery, l.unit, l.pos, run.battery, run.time, M.battery_opts(p.stats, l.unit, dt_game))
			if not ok then obsidian.log("arcade: kinetic battery: " .. tostring(err)) end
			-- Iron Saint: the heal of a save, once the hit it resisted is in.
			local heal = fight.take_heal(l.unit)
			if heal then pcall(perks.heal_share, l.unit, heal) end
			p.pockets = p.pockets or {}
			local got, fraction = pcall(grenades.pockets, p.pockets, p.stats.pockets, l.unit, dt_game * (p.stats.pockets_rate or 1))
			if got and (fraction ~= nil or p.pockets.shown) then
				grenade_meter(l.unit, fraction)
				p.pockets.shown = fraction ~= nil
			end
			p.last_pos = l.pos or p.last_pos
			local health = api.game.master(l.unit, "health")
			local downed = type(health) == "table" and health.is_downed == true
			if downed and not p.was_downed then summary.add(run.tally, l.slot, "downs") end
			p.was_downed = downed
		elseif p.alive then
			p.was_downed = false
			-- Boarding the shuttle takes the body too.
			if not M.extracted(l.record) then summary.add(run.tally, l.slot, "deaths") end
			battery.died(p.battery)
			-- A map hazard can leave no ground under the spot: a little way off, then.
			local spot = p.last_pos and M.spot_around(p.last_pos, 0, 3, run.draws) or p.last_pos
			fire_death(run, n, spot)
		end
		p.alive = l.unit ~= nil
		local ok, err = pcall(perks.sync_reinforcement, p, l.record, l.unit, dt_game, st)
		if not ok then obsidian.log("arcade: reinforcement failed: " .. tostring(err)) end
	end
end

local function share(run, dt_real)
	run.shared_at = run.shared_at - dt_real
	if run.shared_at > 0 then return end
	run.shared_at = 0.5
	local host = api.game.is_host()
	if not host then run.hosting = false end
	api.lobby.share("run", sync.encode(run.sync, run.time, host))
	local seen = {}
	for peer, text in pairs(api.lobby.shared("run")) do
		seen[peer] = true
		sync.set_peer(run.sync, peer, sync.decode(text))
	end
	for peer in pairs(run.sync.peers) do
		if not seen[peer] then sync.set_peer(run.sync, peer, nil) end
	end
	-- Another machine's vacuum: the same samples fly in here, to whoever is nearest, as there.
	for peer, text in pairs(api.lobby.shared("vacuum")) do
		local e = vacuum.decode(text)
		if vacuum.take(run.vacuum, peer, e, run.sync.mission, run.time) then
			orbs.pull(run.orbs, e, rules.VACUUM_RADIUS)
			grant_all(run, "rerolls", 1)
		end
	end
	-- The machines with a Sweet Liberty player, by the mission they're in: their kills' blasts show here.
	local liberty = false
	for _, p in pairs(run.players) do liberty = liberty or p.stats.liberty == true end
	api.lobby.share("liberty", liberty and tostring(run.sync.mission) or nil)
	run.liberty_peers = {}
	for peer, text in pairs(api.lobby.shared("liberty")) do
		if text == tostring(run.sync.mission) then run.liberty_peers[peer] = true end
	end
	-- Sample Siphon: the reach of this machine's best, by mission, so every machine sends the same samples.
	local siphon = 0
	for _, p in pairs(run.players) do siphon = math.max(siphon, p.stats.siphon or 0) end
	api.lobby.share("siphon", siphon > 0 and (tostring(run.sync.mission) .. ":" .. siphon) or nil)
	run.siphon_peers = {}
	for peer, text in pairs(api.lobby.shared("siphon")) do
		local mission, reach = tostring(text):match("^(.-):([%d.]+)$")
		if mission == tostring(run.sync.mission) then run.siphon_peers[peer] = tonumber(reach) end
	end
	-- Kinetic Battery: this machine's discharges and crackling players go out, the others' are drawn here.
	local glowing = {}
	for n, l in ipairs(run.local_list) do
		local b = run.players[n] and run.players[n].battery
		if b and b.glow and l.pos then glowing[#glowing + 1] = l.pos end
	end
	api.lobby.share("battery", battery.encode(run.battery, run.sync.mission, glowing))
	local others = {}
	for _, a in ipairs(all_players()) do
		if not a.is_local then others[#others + 1] = a end
	end
	local want = {}
	for peer, text in pairs(api.lobby.shared("battery")) do
		local e = battery.decode(text)
		for _, path in ipairs(battery.take(run.battery, peer, e, run.sync.mission, run.time)) do pcall(api.world.arc, path) end
		if e and e.mission == tostring(run.sync.mission) then
			for unit in pairs(battery.match_glows(e.glowing, others)) do want[unit] = true end
		end
	end
	battery.show_remote_glows(run.battery, want)
	-- Cluster Grenade: this machine's clusters go out, the others' go off here without power.
	api.lobby.share("cluster", grenades.encode(run.grenades, run.sync.mission))
	for peer, text in pairs(api.lobby.shared("cluster")) do
		for _, ev in ipairs(grenades.take(run.grenades, peer, grenades.decode(text), run.sync.mission, run.time)) do
			pcall(grenades.show_remote, run.grenades, ev)
		end
	end
	-- The end-of-run summary: this machine's players' numbers out, the host's summary followed.
	local ok_s, err_s = pcall(share_summary, run, host)
	if not ok_s then obsidian.log("arcade: summary: " .. tostring(err_s)) end
	-- The host's clock decides when the shuttle opens and what's announced, for everyone.
	local host_time = not host and sync.host_time(run.sync)
	if host_time and math.abs(host_time - run.time) > rules.CLOCK_SLACK then
		obsidian.log(string.format("arcade: clock %s, the host's %s", clock(run.time), clock(host_time)))
		run.time = host_time
	end
end

-- The mission is ending (extraction, a wipe or an abort): the game fades out, then despawns every
-- unit it owns and changes state. Nothing new may come into the world by then, so the run stands down
-- at once: no more spawns, ammo boxes or blasts, and its own props (samples, chests, drones) go.
function M.stand_down(run)
	if run.exiting then return end
	run.exiting = true
	samples.clear()
	run.looks = {}
	pcall(chests.clear_props)
	for _, p in pairs(run.players) do pcall(perks.remove_drones, p) end
	obsidian.log("arcade: the mission is ending, the run stands down at " .. clock(run.time))
end

-- The end-of-run summary (src/summary.lua, src/summary_screen.lua) ---------------------------------

-- Whether a player's record says they boarded the shuttle.
function M.extracted(record)
	local go = record and record.player_go
	if not go then return false end
	local ok, yes = pcall(function() return go:has("has_extracted") and go:get("has_extracted") end)
	return ok and yes == true
end

-- The slots of the players in the game, every machine's.
local function present_slots()
	local out = {}
	local st = api.game.state()
	for i, record in ipairs(type(st) == "table" and st.players or {}) do
		local go = record.player_go
		local ok, there = pcall(function() return go and go:exists() end)
		if ok and there then out[#out + 1] = i end
	end
	return out
end

-- The summary comes up: the game stops as for the cards, and a level-up being chosen is dropped, as
-- nothing more comes of it. kind: "extracted" or "defeated". seq: the host's number for it. age: the
-- host's seconds since the end.
local function open_summary(run, kind, seq, age)
	run.choice = nil
	run.summary = summary.new(kind, run.sync.mission, run.sync.run, seq, age)
	run.summary.time, run.summary.bosses = run.time, run.tally.bosses
	run.hold.kind = kind
	if run.god_before == nil then run.god_before = api.effects.is_on("god") end
	M.hold_world(run, true)
	api.effects.set("god", true)
	hide_hud(run)
	input.hold()
	input.cursor("hidden")
	obsidian.log(string.format("arcade: summary %d, %s at %s", seq, kind, clock(run.time)))
end

-- A summary the host took back: somebody is up again.
local function cancel_summary(run)
	local s = run.summary
	if not s then return end
	run.summary, run.hold.kind = nil, nil
	run.cancelled = s
	s.kind = "cancelled"
	input.release(rules.INPUT_GRACE)
	input.cursor("game")
	M.hold_world(run, false)
	api.effects.set("god", run.god_before == true)
	run.god_before = nil
	show_hud(run)
	obsidian.log("arcade: summary " .. s.seq .. " cancelled")
end

-- What this machine shares of its players for the summary.
local function own_report(run)
	local s = run.summary
	local out = {}
	for _, l in ipairs(run.local_list) do
		local t = summary.player(run.tally, l.slot)
		local game = l.record and type(l.record.stats) == "table" and l.record.stats or {}
		out[#out + 1] = { slot = l.slot, ready = s.ready[l.slot] == true, extracted = s.kind == "extracted" and M.extracted(l.record),
			kills = tonumber(game.kills) or t.kills, damage = t.damage, samples = t.samples, downs = t.downs, deaths = tonumber(game.deaths) or t.deaths,
			saves = t.saves, sources = summary.top(t.sources) }
	end
	return out
end

-- The lobby side: this machine's text out, the others' in, and the host's followed.
function share_summary(run, host)
	local s = run.summary or run.cancelled
	api.lobby.share("summary", s and summary.encode(s, host, run.summary and own_report(run) or {}) or nil)
	for peer, text in pairs(api.lobby.shared("summary")) do
		local rec = summary.decode(text)
		local p = rec and run.sync.peers[peer]
		if p and rec.mission == run.sync.mission and rec.run == p.run then
			if rec.host and not host then
				local what = summary.follow(run.summary, rec, run.sync.mission, p.run)
				if what == "open" then
					open_summary(run, rec.kind, rec.seq, rec.age)
				elseif what == "cancel" then
					cancel_summary(run)
				elseif what == "close" then
					run.summary.closed = true
					M.hold_world(run, false)
				elseif what == "sync" then
					run.summary.age = rec.age
				end
				if run.summary and run.summary.seq == rec.seq then run.summary.time, run.summary.bosses = rec.time, rec.bosses end
			end
			if run.summary and rec.seq == run.summary.seq then run.summary.reports[peer] = rec end
		end
	end
end

-- The confirm press of the local players, the same as picking a card: alone on the machine, any
-- device; with company, each player's own. Bots confirm at once. The host lets the game go on once
-- every player in the game has confirmed or the time is up.
-- A local player no one holds a pad for: Obsidian API's bots.
function is_bot(l)
	if not (l and api.bots and api.bots.all) then return false end
	for _, b in ipairs(api.bots.all()) do
		if b.record ~= nil and b.record == l.record then return true end
	end
	return false
end

local function step_summary(run, dt_real)
	local s = run.summary
	summary.step(s, dt_real)
	local presses = input.read()
	if summary.accepts(s) then
		local alone = #run.local_list == 1
		for n, l in ipairs(run.local_list) do
			if not s.ready[l.slot] then
				if is_bot(l) then
					s.ready[l.slot] = true
				else
					local list = {}
					if alone then
						for _, ev in pairs(presses) do list[#list + 1] = ev end
					else
						list[1] = presses[M.pad_of(l, n)]
					end
					for _, ev in ipairs(list) do
						-- The mouse: the first local player's, on their CONTINUE button (M.draw_summary).
						local m = n == 1 and ev.mouse or nil
						if m then s.mouse_at = { x = m.x, y = m.y } end
						local clicked = false
						if m and m.click and s.button and M.kit then
							local x, y = M.kit:point(m.x, m.y)
							clicked = mouse.inside(s.button, x, y)
						end
						if ev.select or clicked then
							s.ready[l.slot] = true
							api.audio.play(rules.SOUNDS.card_pick)
							break
						end
					end
				end
			end
		end
	end
	if api.game.is_host() and summary.should_release(s, present_slots(), summary.ready_set(s)) then
		s.closed = true
		run.hold.released = true
		M.hold_world(run, false)
		obsidian.log("arcade: summary " .. s.seq .. " over, the mission ends")
	end
end

-- The confirm button under a column.
function M.confirm_controls(device, pad)
	if device == "keyboard" then return { { keys = { "E" }, label = "CONTINUE" } } end
	local text = obsidian.ui.prompt and obsidian.ui.prompt("select", pad) or nil
	return { { keys = { text and text ~= "" and text or "A" }, label = "CONTINUE", plain = true } }
end

-- How a source looks: the game's names for weapons and stratagems, the stratagem icons from
-- LoadoutSettings (which kit:icon draws).
local LOOK = {
	by_id = upgrades.by_id,
	text = function(key)
		local ok, text = pcall(api.catalog.text, key)
		return ok and text or nil
	end,
	stratagem_icon = function(name)
		local ls = g("LoadoutSettings")
		for _, s in ipairs(ls and ls.stratagems or {}) do
			if s.name == name then return s.icon end
		end
		return nil
	end,
}

function M.draw_summary(kit, run)
	local s = run.summary
	local ready = summary.ready_set(s)
	local present = present_slots()
	local view = { kind = s.kind, time = s.time, level = sync.level(run.sync), bosses = s.bosses, alpha = summary.alpha(s), left = summary.left(s),
		closed = s.closed, t = os.clock(), factions = {}, players = {} }
	for _, f in ipairs(director.factions(level.home or "bugs", (s.time or 0) / 60, run.seed)) do view.factions[#view.factions + 1] = api.catalog.text(f) end
	-- Every machine's numbers by slot, this machine's own over any report.
	local by_slot = {}
	for _, report in pairs(s.reports) do
		for _, p in ipairs(report.players or {}) do by_slot[p.slot] = p end
	end
	local mine, locals = {}, {}
	for n, l in ipairs(run.local_list) do locals[l.slot] = n end
	for _, p in ipairs(own_report(run)) do by_slot[p.slot] = p mine[p.slot] = true end
	local slots, seen = {}, {}
	for _, slot in ipairs(present) do slots[#slots + 1], seen[slot] = slot, true end
	for slot in pairs(by_slot) do
		if not seen[slot] then slots[#slots + 1] = slot end
	end
	table.sort(slots)
	local names = {}
	local ok, list = pcall(function() return obsidian.ui.data.players() end)
	for _, p in ipairs(ok and list or {}) do names[p.slot] = p end
	local alone = #run.local_list == 1
	local all_mine = #run.local_list > 0
	for _, slot in ipairs(slots) do
		local p = by_slot[slot]
		local info = names[slot] or {}
		local entry = { slot = slot, name = info.name, color = info.color, ready = ready[slot] == true }
		if p then
			entry.stats = { kills = p.kills, damage = p.damage, samples = p.samples, downs = p.downs, deaths = p.deaths, saves = p.saves }
			entry.sources = p.sources
			if s.kind == "extracted" then entry.extracted = p.extracted == true end
		end
		local n = locals[slot]
		if n and not entry.ready then
			all_mine = false
			local l = run.local_list[n]
			local pad = M.pad_of(l, n)
			local device = alone and input.main_device() or (pad == 0 and "keyboard" or "pad")
			if not is_bot(l) then entry.controls = M.confirm_controls(device, not alone and pad > 0 and pad or nil) end
		end
		view.players[#view.players + 1] = entry
	end
	view.waiting = all_mine and not summary.all_ready(present, ready)
	cards.keycap = cards.keycap or M.read_keycap()
	-- The first local player's CONTINUE button takes the mouse: yellow under it, and a click on it confirms.
	local first = run.local_list[1]
	s.button = nil
	if first and ((alone and input.main_device() == "keyboard") or (not alone and M.pad_of(first, 1) == 0)) then
		s.button = summary_screen.buttons(kit, view)[first.slot]
		local m = s.mouse_at and { kit:point(s.mouse_at.x, s.mouse_at.y) }
		for _, entry in ipairs(view.players) do
			if entry.slot == first.slot and entry.controls and m and mouse.inside(s.button, m[1], m[2]) then entry.controls[1].hover = true end
		end
	end
	input.cursor(s.button and "menu" or "hidden")
	summary_screen.draw(kit, view, LOOK)
end

function M.update()
	local run = M.run
	if not run then return end
	local st_exit = api.game.state()
	if run.exiting or (type(st_exit) == "table" and (st_exit.wants_exit or st_exit.abort_mission or st_exit.game_state == "game_over")) then
		M.stand_down(run)
		return
	end
	local dt_game, dt_real = g("GAME_DT") or 0, g("ENGINE_DT") or 0
	run.local_list = local_players()
	for _, l in ipairs(run.local_list) do
		if l.unit then run.slot_by_unit[l.unit] = l.slot end
	end
	-- The mission's end waits for the summary once the run is under way (src/summary.lua's hold).
	run.hold.allowed = run.time >= rules.ALARM_AFTER
	local everyone = all_players()
	local squad = centre(everyone)
	run.squad = squad or run.squad
	local ok_b, err_b = pcall(bosses.update, dt_real, squad)
	if not ok_b then obsidian.log("arcade: bosses: " .. tostring(err_b)) end

	-- The host's hold saw the mission end, or took a defeat back (StateGame.update_host).
	if run.hold.fresh then
		run.hold.fresh = nil
		if run.hold.kind and not run.summary then
			run.summary_seq = (run.summary_seq or 0) + 1
			open_summary(run, run.hold.kind, run.summary_seq, 0)
		end
	end
	if run.summary and not run.hold.kind and not run.summary.closed then cancel_summary(run) end

	share(run, dt_real)
	input.update(dt_real)
	-- While the summary is up, the run stands still: no clock, spawns, timers or samples.
	if run.summary then
		step_summary(run, dt_real)
		return
	end
	update_looks(run, dt_real)
	run.dt_real = dt_real
	sync_players(run, run.choice and 0 or dt_game, dt_real)
	pcall(grenades.update, run.grenades, dt_game)
	-- Chain Reaction's blasts and Napalm Needles' clouds.
	local ok_c, err_c = pcall(step_chain, run, dt_game)
	if not ok_c then obsidian.log("arcade: chain reaction: " .. tostring(err_c)) end
	pcall(fight.step_clouds, fight.state, run.time, api.enemies.near, function(enemy, statuses)
		for _, s in ipairs(statuses) do api.enemies.apply_status(enemy, s) end
	end)
	-- Elusive Tactics' stuns still to come.
	pcall(dive.step, api, run.time)
	-- Elites: the host's spawns and kinds, every machine's looks. Chests: drops, opens and upgrades.
	local ok_el, err_el = pcall(elites.update, run, run.choice and 0 or dt_game, dt_real, squad,
		director.factions(level.home or "bugs", run.time / 60, run.seed), function() return run.director.rng:random() end)
	if not ok_el then obsidian.log("arcade: elites: " .. tostring(err_el)) end
	local ok_c, err_c = pcall(chests.update, run, dt_real, M.grant, M.play_at)
	if not ok_c then obsidian.log("arcade: chests: " .. tostring(err_c)) end

	-- Objectives done, as the run's shared value counts them: a banish for every player for each new one.
	local done = sync.objectives(run.sync)
	if done > (run.objectives_paid or 0) then
		grant_all(run, "banishes", done - (run.objectives_paid or 0))
		run.objectives_paid = done
	end

	local team_level = sync.level(run.sync)
	if team_level ~= run.zoomed then
		run.zoomed = team_level
		api.effects.set("camera_distance", rules.camera_distance(team_level))
	end

	-- Level-ups: open the cards when this machine has a level to choose, and let time run again
	-- once every machine has chosen.
	if not run.choice then
		local lvl = sync.to_choose(run.sync)
		if lvl and #run.local_list > 0 then open_choice(run, lvl) end
	end
	if run.choice then
		step_choice(run, dt_real)
		local c = run.choice
		if c.finished and not sync.choosing(run.sync) then
			-- The screen fades out before the game goes on.
			c.closing_at = c.closing_at or c.clock
		end
		if c.closing_at and card_anim.closed(c.clock - c.closing_at) then
			confirm_all(run)
			run.choice = nil
			input.release(rules.INPUT_GRACE)
			input.cursor("game")
			M.hold_world(run, false)
			api.effects.set("god", run.god_before == true)
			run.god_before = nil
			show_hud(run)
			obsidian.log("arcade: everyone chose, back to it")
		elseif c.finished and not c.closing_at and sync.to_choose(run.sync) then
			confirm_all(run)
			run.choice = nil -- another level is waiting: open it next frame, over the dark backdrop
			run.chained = true
		end
	end

	if not run.choice then
		local was = run.time
		run.time = run.time + dt_game
		M.announce(run, was / 60, run.time / 60)
		-- Orbital bombardment windows (src/bombard.lua): the alarm on every machine, the strikes from the host.
		if run.bombard and not run.summary then
			local ok_o, err_o = pcall(bombard.update, run.bombard, was, run.time, dt_game, everyone, api.game.is_host())
			if not ok_o then obsidian.log("arcade: bombardment: " .. tostring(err_o)) end
		end
		if not run.won and run.time >= rules.RUN_LENGTH then
			run.won = true
			level.extract_open = true
			api.ui.hint("Extract when ready, or stay liberating!")
			obsidian.log("arcade: run won, extraction open")
		end
		-- The map's objectives are off the list already (src/level.lua). The shuttle needs them done, so
		-- the host completes them, a moment later, when no machine plays the game's banner for it.
		if run.won and not run.objectives_gone and run.time >= rules.OBJECTIVES_GONE_AT and api.game.is_host() then
			run.objectives_gone = true
			local ok, why = api.mission.finish_objectives()
			obsidian.log("arcade: objectives done quietly: " .. tostring(ok) .. " " .. tostring(why))
		end
		for _, t in pairs(run.timers) do
			t.left = t.left - dt_game
			if t.left <= 0 then
				t.left = t.every
				local ok, err = pcall(t.fn)
				if not ok then obsidian.log("arcade: timer failed: " .. tostring(err)) end
			end
		end
		if api.game.is_host() then
			-- Become host mid-run, when the host leaves: the director picks up where the run is.
			if not run.hosting then
				run.hosting = true
				if run.time > 0 then
					director.take_over(run.director, run.time)
					run.alarm = run.time >= rules.ALARM_AFTER
					obsidian.log("arcade: host now, the director picks up at " .. clock(run.time))
				end
			end
			-- The game's alarm, on from the landing and kept on (src/alarm.lua).
			if squad then
				local st = api.game.state()
				local first = not run.game_alarm.raised
				if alarm.update(run.game_alarm, type(st) == "table" and st.encounter_manager, vec(squad), dt_game) then
					obsidian.log("arcade: the alarm " .. (first and "goes on" or "again, it had gone quiet"))
				end
			end
			if not run.alarm and run.time >= rules.ALARM_AFTER and squad then
				run.alarm = true
				obsidian.log("arcade: the spawner starts")
			end
			if run.alarm then
				local alive = api.enemies.count() or 0
				-- How many of one enemy key are alive, for the director's limits (director.LIMIT): counted
				-- once, and only on a frame that asks.
				local by_key
				local function alive_of(key)
					if not by_key then
						by_key = {}
						local ok_list, units = pcall(api.enemies.list)
						for _, unit in ipairs(ok_list and type(units) == "table" and units or {}) do
							local ok_alive, alive = pcall(g("Unit").alive, unit)
							local ok, path = false, nil
							if ok_alive and alive then ok, path = pcall(g("Unit").get_data, unit, "unit_path") end
							local enemy = ok and path and api.catalog.enemy(path)
							if enemy then by_key[enemy.key] = (by_key[enemy.key] or 0) + 1 end
						end
					end
					return by_key[key] or 0
				end
				local out = director.update(run.director, dt_game, #everyone, alive, alive_of)
				spawn(run, out.spawns, squad)
				if #out.spawns > 0 then
					local n, kinds = 0, {}
					for _, sp in ipairs(out.spawns) do n = n + sp.count kinds[#kinds + 1] = sp.count .. " " .. sp.key end
					run.spawned = (run.spawned or 0) + n
					obsidian.log(string.format("arcade: %s, %d alive, spawning %s", clock(run.time), alive, table.concat(kinds, ", ")))
				end
				end
		end
	end

	-- Orbs: this machine's players collect, everyone else's take theirs away.
	local players = {}
	for _, p in ipairs(everyone) do
		local n
		for i, l in ipairs(run.local_list) do if l.unit == p.unit then n = i end end
		players[#players + 1] = { pos = p.pos, is_local = p.is_local, magnet = n and player_state(run, n).stats.magnet or 1, n = n, unit = p.unit }
	end
	local _, by, picked = orbs.update(run.orbs, dt_game, players)
	run.pickup_sound_in = math.max((run.pickup_sound_in or 0) - dt_real, 0)
	local gained = 0
	for i, amount in pairs(by) do
		local n = players[i].n
		local worth = amount * (n and player_state(run, n).stats.xp_gain or 1)
		sync.collected(run.sync, worth)
		gained = gained + worth
		if n and run.local_list[n] then summary.add(run.tally, run.local_list[n].slot, "samples", picked[i] or 1) end
		-- Meritocracy: each sample, whatever the XP, takes a share of what's left of each cooldown.
		local merit = n and player_state(run, n).stats.merit or 0
		if merit > 0 and run.local_list[n] then pcall(perks.cut_cooldowns, run.local_list[n].unit, merit, picked[i] or 1) end
		if run.pickup_sound_in <= 0 then
			run.pickup_sound_in = rules.PICKUP_SOUND_GAP
			M.play_at(rules.SOUNDS.sample_pickup, rules.PICKUP_SOUND_VOLUME)
		end
	end
	-- The vacuum fills with what this machine's players collect, and goes off around the main player.
	local _, _, need = xp.level_of(sync.team_xp(run.sync))
	local main = run.local_list[1]
	if gained > 0 and vacuum.add(run.vacuum, gained, need) and main and main.pos then
		orbs.pull(run.orbs, main.pos, rules.VACUUM_RADIUS)
		pcall(api.lobby.share, "vacuum", vacuum.encode(run.vacuum, run.sync.mission, run.sync.run, main.pos, run.time))
		grant_all(run, "rerolls", 1)
	end
end

-- Whether a photo mode has the screen: Obsidian API's photo_mode effect, which clears the game's own
-- HUD for a picture. The run goes on underneath.
function M.photo()
	local ok, on = pcall(api.effects.is_on, "photo_mode")
	return ok and on == true
end

-- The XP bar and clock on top, the orbs on the ground, and the cards while choosing. During a photo
-- (M.photo) none of it is drawn; the samples on the ground are props in the level and stay in line
-- with the orbs.
function M.draw(kit, paused)
	local run = M.run
	if not run then return end
	M.kit = kit
	if M.photo() then
		if not run.exiting then samples.sync(api.world, run.orbs.list, run.dt_real) end
		return
	end
	-- The summary has the screen from the end on, and stays up as the game fades out after it: the
	-- kit fades with the game. Until it shows, the run draws nothing over the game.
	if run.summary then
		if summary.visible(run.summary) then M.draw_summary(kit, run) end
		return
	end
	if run.exiting then return end
	local total = sync.team_xp(run.sync)
	local lvl, into, need = xp.level_of(total)
	-- Over the darkened screen while choosing. Heat and the bar make way for the objectives at the right
	-- while the game shows them, and slide back to the screen's centre when it doesn't.
	local hud_layer = run.choice and cards.LAYER + 5 or 10
	kit:layer(hud_layer)
	local beside = not run.choice and level.objectives_at and os.clock() - level.objectives_at < 0.25
	-- Without Heat the centred bar already clears the objectives.
	local centred = rules.SHOW_HEAT and (cards.W - THREAT.w - THREAT.gap - BAR.w) / 2 + THREAT.w + THREAT.gap or (cards.W - BAR.w) / 2
	local target = beside and BAR.x or centred
	run.bar_x = run.bar_x and run.bar_x + (target - run.bar_x) * math.min((run.dt_real or 0) * 8, 1) or target
	local x, w = run.bar_x, BAR.w
	local heat_x = x - THREAT.gap - THREAT.w
	-- Level with the first row of the game's objective list, measured from the screen's top: the frame
	-- shrinks to the middle with the UI scale.
	local _, screen_h = g("Application").resolution()
	local _, centre = kit:point(0, screen_h * (1 - BAR.level))
	local y = centre - BAR.h / 2
	-- The pause menu has the screen to itself, beside the codex.
	if not paused or run.choice then M.draw_bar(kit, run, x, y, w, heat_x, hud_layer, lvl, into, need) end
	kit:layer(5)
	if samples.sync(api.world, run.orbs.list, run.dt_real) then
		if not paused then M.draw_sample_flashes(kit, run) end
	elseif not paused then
		M.draw_orbs(kit, run)
	end
	-- The elites' glow and names, the chests' glow and what they gave (src/elites.lua, src/chests.lua).
	if not paused and not run.choice then
		pcall(elites.draw, kit)
		pcall(chests.draw, kit, run, input.main_device() == "keyboard")
	end
	if run.choice then
		M.draw_choice(kit, run)
	else
		M.draw_cards_hud(kit, run)
	end
end

-- Over each of this machine's players' HUD cards: health and armor, or the upgrades while the map is
-- open (src/cards_hud.lua).
function M.draw_cards_hud(kit, run)
	local list = {}
	for n, l in ipairs(run.local_list) do
		local max_health, armor, health
		if l.unit then max_health, armor, health = perks.body_numbers(l.unit) end
		local p = player_state(run, n)
		list[n] = { unit = l.unit, owned = p.owned, health = health, max_health = max_health, armor = armor, rerolls = p.redraw.rerolls, banishes = p.redraw.banishes }
	end
	cards_hud.draw(kit, list)
end

-- The bar along the top and Heat beside it.
function M.draw_bar(kit, run, x, y, w, heat_x, hud_layer, lvl, into, need)
	native.box(kit, x, y, w, BAR.h, { thick = 0, tint = "#ffffffcc" })
	-- From the right: the clock, the level close to it, and the bar with the samples it has and needs.
	local heading = { font = "heading", size = 28, tracking = 1 }
	local label = "LEVEL " .. lvl
	local label_x = x + w - 14 - kit:measure("00:00", heading) - 14 - kit:measure(label, heading)
	local track = label_x - 16 - (x + 14)
	-- One dark trough, centred in the box (a kit counts y up from the bottom): the vacuum's progress as a
	-- thin yellow line under the samples, 1 apart.
	local top = y + (BAR.h - BAR.trough) / 2
	kit:rect(x + 14, top, track, BAR.trough, "#000000b0")
	kit:rect(x + 16, top + 2, (track - 4) * vacuum.fraction(run.vacuum, need), 3, "#ffbe11")
	-- The samples' fill eases to the XP and pulses brighter as samples come in (xp.bar_step).
	run.bar = run.bar or xp.bar_new()
	local fill, pulse = xp.bar_step(run.bar, sync.team_xp(run.sync), run.dt_real or 0)
	kit:rect(x + 16, top + 6, (track - 4) * fill, 18, xp.bar_color(pulse))
	native.text(kit, label, label_x, y + BAR.text_y, { font = "heading", size = 28, tracking = 1, color = native.GOLD })
	native.text(kit, clock(run.time), x + w - 14, y + BAR.text_y, { font = "heading", size = 28, tracking = 1, align = "right", color = native.WHITE })
	-- The threat, labelled Heat, on its own card just left of the bar: a pip for each step, lit as the
	-- fight grows. Archived (rules.SHOW_HEAT).
	if not rules.SHOW_HEAT then return end
	kit:layer(hud_layer)
	native.box(kit, heat_x, y, THREAT.w, BAR.h, { thick = 0, tint = "#ffffffcc" })
	native.text(kit, "HEAT", heat_x + 14, y + 16.5, { font = "heading", size = 26, tracking = 1, color = native.WHITE })
	local threat = director.threat(run.time / 60)
	for i = 1, director.THREATS do
		kit:rect(heat_x + THREAT.w - 14 - (director.THREATS - i + 1) * 16 + 4, y + 18, 12, 12, i <= threat and "#e8532f" or "#00000090")
	end
end

-- The cards, for whoever's turn it is.
-- The motion of a player's cards at `now` (src/card_anim.lua): each card's opacity, offset and
-- brightness, the banished cards on their way out, and the opacity of what fades in after the cards.
function M.choice_fx(c, p, now)
	local fx = {}
	for i, u in ipairs(p.row) do
		local a, dy
		if p.slot_at and p.slot_at[i] then a, dy = card_anim.banish_in(now - p.slot_at[i]) else a, dy = card_anim.card_in(now - (p.dealt_at or 0), i) end
		local bright = 0
		if p.picked_at then
			local pa, pdy, pb = card_anim.pick(now - p.picked_at, u.id == p.chosen)
			a, dy, bright = a * pa, dy + pdy, pb
		end
		fx[i] = { alpha = a, dy = dy, bright = bright }
	end
	local leaving = {}
	for _, l in ipairs(p.leaving or {}) do
		if not card_anim.banish_gone(now - l.at) then
			local a, dy = card_anim.banish_out(now - l.at)
			leaving[#leaving + 1] = { u = l.u, slot = l.slot, alpha = a, dy = dy }
		end
	end
	return fx, leaving, card_anim.extras(now - (c.turn_at or 0), #p.row)
end

-- The reroll and banish prompts under the cards: the keys, the counts, and whether each can be used now.
function M.tools(device, pad, b, can_reroll, can_banish)
	local keys
	if device == "keyboard" then
		keys = { reroll = { "R" }, banish = { "X" } }
	else
		local function button(name, fallback)
			local text = obsidian.ui.prompt and obsidian.ui.prompt(name, pad) or nil
			return text and text ~= "" and text or fallback
		end
		keys = { reroll = { button("#triangle", "Y") }, banish = { button("#square", "X") } }
	end
	local plain = device ~= "keyboard"
	return {
		{ keys = keys.reroll, plain = plain, name = "REROLL", count = b.rerolls, usable = can_reroll and b.rerolls > 0 },
		{ keys = keys.banish, plain = plain, name = "BANISH", count = b.banishes, usable = can_banish },
	}
end

function M.draw_choice(kit, run)
	local c = run.choice
	local now = c.clock
	local view = { waiting = c.finished, players = {}, t = os.clock(), backdrop = card_anim.backdrop(now, c.chained),
		alpha = c.closing_at and card_anim.screen_out(now - c.closing_at) or 1 }
	local alone = #c.players == 1
	-- The single player's screen, for whoever's turn it is: the last to choose while the squad finishes.
	local n = c.turn
	local p = c.players[n]
	local pad = M.pad_of(run.local_list[n], n)
	local device = alone and input.main_device() or (pad == 0 and "keyboard" or "pad")
	local b = player_state(run, n).redraw
	local open = not c.finished and not p.picked_at
	local fx, leaving, extras = M.choice_fx(c, p, now)
	local tools = M.tools(device, not alone and pad > 0 and pad or nil, b, open,
		open and (not p.strats or p.focus == "cards") and redraw.can_banish(b, p.row, p.cursor, upgrades.fallback and upgrades.fallback.id))
	view.players[1] = { name = "PLAYER " .. n, show_name = not alone, row = p.row, owned = player_state(run, n).owned, cursor = p.cursor, chosen = p.chosen,
		strats = p.strats, strat_cursor = p.strat_cursor, strat_pick = p.strat_pick, focus = p.focus,
		time_left = c.left / rules.CHOOSE_LIMIT, seconds_left = c.left, controls = M.controls(device, not alone and pad > 0 and pad or nil, p.strats ~= nil),
		tools = cards.tool_groups(kit, tools), fx = fx, leaving = leaving, extras = extras, absorbed = player_state(run, n).absorbed }
	-- The prompts: yellow under the mouse when usable, and where they are for the mouse's clicks.
	local groups = view.players[1].tools
	if p.tool_hover and groups[p.tool_hover] and not groups[p.tool_hover].dim then groups[p.tool_hover].hover = true end
	local spot = cards.layout(1, #p.row, p.strats and #p.strats or 0, not alone)[1]
	p.tool_rects = spot.tools and cards.glyph_rects(kit, spot.tools.x, spot.tools.y, groups) or nil
	input.cursor(input.main_device() == "keyboard" and "menu" or "hidden")
	cards.keycap = cards.keycap or M.read_keycap()
	cards.draw(kit, view)
end

-- Tells the squad when another faction joins: the only change the run announces, beside the shuttle.
-- Every machine says it for itself, from the run's clock.
function M.announce(run, from, to)
	for _, e in ipairs(director.events(level.home or "bugs", from, to, run.seed)) do
		if e.kind == "faction" then api.ui.hint(api.catalog.text(e.faction) .. " have joined the fight.") end
	end
end

-- The run's bar across the top, narrow enough for the objectives to its right.
THREAT = { w = 180, gap = 12 }
-- trough: the dark strip behind both lines, from the bottom: 2, 3 of yellow, 1 between, 18 of blue, 2.
BAR = { x = 680, w = 560, h = 48, level = 0.092, text_y = 15, trough = 26 }

-- What the mouse is over on a player's part of the screen, in this mod's design space: "card",
-- "strat" or "tool" (the reroll and banish prompts) and its index. nil when nothing.
function M.under_mouse(c, n, m)
	if not M.kit then return nil end
	local x, y = M.kit:point(m.x, m.y)
	local p = c.players[n]
	-- Each player chooses alone on the screen, so their cards are where a single player's are.
	local spot = cards.layout(1, #p.row, p.strats and #p.strats or 0, #c.players > 1)[1]
	-- The prompts where they were last drawn (M.draw_choice).
	return mouse.over(spot, p.tool_rects, x, y)
end

-- One of the game's sounds at a share of its normal volume, through the volume parameter its music and
-- voice chat use. That stops at the sound's normal volume, so past it the sound plays more than once at
-- the same moment: copies of a sound add up.
function M.play_at(name, volume)
	local st = api.game.state()
	local timpani = g("TimpaniWorld")
	local world = st and st.world_proxy and st.world_proxy:get_timpani_world()
	if not (world and timpani and timpani.has_event(world, name)) then return end
	local copies = math.ceil(volume)
	for _ = 1, copies do
		local id = timpani.trigger_event(world, name)
		if id then pcall(timpani.set_parameter, world, id, "volume", volume / copies) end
	end
end

-- The game's key cap, a character of its font: the part of a keyboard prompt before its letter.
function M.read_keycap()
	local lm = g("LocalizationManager")
	local mods = lm and lm.modifier_sets and lm.modifier_sets.keyboard_mouse
	for _, m in ipairs(mods or {}) do
		if m.modifier == "#mod_interact" and type(m.value) == "string" then
			local cap = m.value:match("^(.-)\194\172")
			if cap and cap ~= "" then return cap end
		end
	end
	return nil
end

-- The line under the cards, as groups of buttons and what they do: the keys for the keyboard and
-- mouse, the game's own buttons for a pad.
function M.controls(device, pad, stratagems)
	if device == "keyboard" then
		local out = { { keys = { "A", "D" }, label = "MOVE" } }
		if stratagems then out[#out + 1] = { keys = { "W", "S" }, label = "ROW" } end
		out[#out + 1] = { keys = { "E" }, label = "SELECT" }
		return out
	end
	local function button(name, fallback)
		local text = obsidian.ui.prompt and obsidian.ui.prompt(name, pad) or nil
		return text and text ~= "" and text or fallback
	end
	local out = { { keys = { button("#mod_left", "D-PAD"), button("#mod_right", "") }, label = "MOVE", plain = true } }
	if stratagems then out[#out + 1] = { keys = { button("#mod_up", ""), button("#mod_down", "") }, label = "ROW", plain = true } end
	out[#out + 1] = { keys = { button("select", "A") }, label = "SELECT", plain = true }
	return out
end

-- Pixels from the camera, into this mod's 1920x1080 design space, centred as obsidian.ui.frame puts it.
local function on_screen(orb)
	local px, py, on = api.world.to_screen(orb)
	if not on then return nil end
	local w, h = g("Application").resolution()
	local s = math.min(w / cards.W, h / cards.H)
	return (px - (w - cards.W * s) / 2) / s, (py - (h - cards.H * s) / 2) / s
end

function M.draw_orbs(kit, run)
	for _, orb in ipairs(run.orbs.list) do
		local x, y = on_screen(orb)
		if x then
			local size = orb.xp >= 20 and 16 or orb.xp >= 8 and 12 or 8
			kit:hex(x, y, size, orb.xp >= 20 and "#ffc433" or "#4aa8ff")
		end
	end
end

-- A glow where a new sample lands, fading as it settles.
function M.draw_sample_flashes(kit, run)
	for _, orb in ipairs(run.orbs.list) do
		if orb.age < samples.POP then
			local x, y = on_screen(orb)
			if x then
				local left = 1 - orb.age / samples.POP
				art.center(kit, "glow", x, y, 150 * samples.size(orb.xp), string.format("#3a8ee6%02x", math.floor(190 * left)))
			end
		end
	end
end

return M
