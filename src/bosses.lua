-- The run's bosses: the game's own Hive Lord, Siegemech and Great Eye, at the director's boss minutes
-- (director.boss_minute), on missions of difficulty M.MIN_DIFFICULTY and up, and the home faction's boss
-- music from the first one to the end of the mission.
--
-- The boss units are only in the boss packages (resource_packages/race_<faction>_boss), which a normal
-- mission doesn't load, and every machine needs the package to show the unit. So every machine works
-- out the same plan from the mission seed while the level loads, loads the packages it names with the
-- level, and the loading screen waits for them, as Boss Variety does for its rogue bosses. The host
-- spawns; each machine starts the music itself once it sees a boss.
local director = obsidian.module("src/director")
local level = obsidian.module("src/level")

local api = obsidian.import("obsidian.api")

local M = { mission = nil }

M.MIN_DIFFICULTY = 4
-- BossSettings.boss_spawn_info, by faction.
M.UNITS = {
	bugs = "characters/bug_boss/bug_boss",
	cyborgs = "characters/cyborg_boss/cyborg_boss",
	illuminates = "characters/illuminate_boss/illuminate_boss",
}
M.PACKAGE = "resource_packages/race_%s_boss"
M.RING = { 24, 32 } -- metres from the squad's centre a boss lands
M.RETRIES = 5 -- spawns the spawn manager gave up on that are tried again, at another spot
M.MUSIC_BOOST = 3 -- decibels over the player's music volume
M.CHECK_EVERY = 0.5 -- real seconds between looks for a boss

local function g(name) return rawget(_G, name) end

-- Whether a mission of `difficulty` gets bosses.
function M.allowed(difficulty)
	local d = tonumber(difficulty)
	return d ~= nil and d >= M.MIN_DIFFICULTY
end

-- Bosses planned ahead: 10:00, 20:00 and then every 5 minutes, so 64 reach past five hours.
M.PLAN_LENGTH = 64

-- The bosses of a mission: { { minute, faction } } in the director's order (director.boss_minute,
-- director.boss_faction): the first of the home faction or the one that joined at 6:00, then the three
-- in turns, never the same faction twice in a row. From the third boss on every faction has had one,
-- so every mission with bosses loads all three boss packages.
function M.plan(home, seed, count)
	local out = {}
	for i = 1, count or M.PLAN_LENGTH do
		out[i] = { minute = director.boss_minute(i), faction = director.boss_faction(home or "bugs", seed, i) }
	end
	return out
end

-- The boss packages a plan needs, each once.
function M.packages(plan)
	local out, seen = {}, {}
	for _, b in ipairs(plan) do
		local name = M.PACKAGE:format(b.faction)
		if not seen[name] then
			seen[name] = true
			out[#out + 1] = name
		end
	end
	return out
end

-- The place in `plan` of the boss whose minute the run's clock (`minutes`) has reached last, or nil.
function M.due(plan, minutes)
	local found = nil
	for i, b in ipairs(plan or {}) do
		if minutes >= b.minute then found = i end
	end
	return found
end

-- The music bus's volume with the boost: the game's own (Boot, from the options' music slider, 0 to 10,
-- and silent while console background music plays) plus M.MUSIC_BOOST. A muted slider stays muted.
function M.music_db(slider, bgm)
	if bgm then return -60 end
	local v = tonumber(slider) or 10
	if v <= 0 then return -60 end
	return math.min((v - 10) * 4 + M.MUSIC_BOOST, 24)
end

-- The music, per machine: off until a boss shows, then the boss track, held, at the boosted volume.
function M.new_music() return { on = false, db = nil } end

-- One look: "play" when a boss is out and the track isn't on, "volume" when the boosted volume isn't
-- the one set, nil otherwise. The caller sets s.on and s.db once each works.
function M.music_step(s, boss_seen, db)
	if not s.on then return boss_seen and "play" or nil end
	if s.db ~= db then return "volume" end
	return nil
end

local music = M.new_music()
local check_in = 0

-- The spawn manager's answers for a boss group (SpawnManager.update). The boss stays out of the
-- encounter manager's list, as Boss Variety's sentries do, so its clean-up of enemies 40 m from the
-- squad never takes it.
local CALLBACKS = {}
function CALLBACKS.on_entity_spawned(_, _, _, _, _, param)
	obsidian.log("arcade: boss " .. tostring(param and param.faction) .. " is out")
end
function CALLBACKS.on_group_failed(_, _, param)
	local b = param and M.mission and M.mission.plan[param.index]
	if not b then return end
	b.spawned = false
	b.retries = (b.retries or 0) + 1
	obsidian.log("arcade: the " .. tostring(b.faction) .. " boss found no ground, try " .. b.retries)
end

local function spot(squad)
	local angle = math.random() * math.pi * 2
	local radius = M.RING[1] + math.random() * (M.RING[2] - M.RING[1])
	return { x = squad.x + math.cos(angle) * radius, y = squad.y + math.sin(angle) * radius }
end

-- Host only: queues the boss of plan place `index` around the squad's centre.
local function queue(index, squad)
	local m = M.mission
	local b = m.plan[index]
	local path = M.UNITS[b.faction]
	local packages = g("Boot").package_manager
	-- An unloaded unit stops the game: the package must be online here, and so on every machine,
	-- since the level waited for it.
	if not (path and packages:is_package_online(M.PACKAGE:format(b.faction))) then return false, "not_loaded" end
	local st = api.game.state()
	local em = type(st) == "table" and st.encounter_manager
	local spawner = em and em.spawn_manager
	if not spawner then return false, "not_in_mission" end
	local at = spot(squad)
	local V3 = g("Vector3")
	local pos = V3(at.x, at.y, 0)
	local map = st.generated_level
	if map and map.get_closest_position_on_level then
		local ok, p = pcall(map.get_closest_position_on_level, map, pos)
		if ok and p then pos = p end
	end
	spawner:queue_group_spawn(pos, { units = { { unit_path = path, amount = 1 } } }, CALLBACKS,
		{ index = index, faction = b.faction }, nil, 0, g("Network").peer_id())
	b.spawned = true
	obsidian.log(string.format("arcade: the %s boss lands at %.0f, %.0f", b.faction, at.x, at.y))
	return true
end

-- Host only, from the director's boss spawn: the boss due at `minutes` of the run's clock, around
-- `squad` ({ x, y, z }, the squad's centre). Answers true, or false and why.
function M.spawn(minutes, squad)
	local m = M.mission
	if not m then return false, "no_plan" end
	if not M.allowed(m.difficulty) then return false, "difficulty" end
	if not squad then return false, "no_squad" end
	local index = M.due(m.plan, minutes)
	if not index then return false, "not_due" end
	if m.plan[index].spawned then return false, "spawned" end
	return queue(index, squad)
end

-- Host only, for the debug page: the first boss of the plan that hasn't landed, whatever the clock.
function M.spawn_next(squad)
	local m = M.mission
	if not m then return false, "no_plan" end
	if not M.allowed(m.difficulty) then return false, "difficulty" end
	if not squad then return false, "no_squad" end
	for i, b in ipairs(m.plan) do
		if not b.spawned then return queue(i, squad) end
	end
	return false, "spawned"
end

local function boss_out()
	for _, unit in ipairs(api.enemies.list()) do
		local info = api.enemies.info(unit)
		if info and info.boss then return true end
	end
	return false
end

local function boosted_db()
	local save, timpani = g("SaveManager"), g("Timpani")
	local slider = save and save:get("volume_music")
	local ok, bgm = pcall(function() return timpani.is_playing_bgm() end)
	return M.music_db(slider, ok and bgm == true)
end

-- Every frame of a run, on every machine. dt_real: real seconds. squad: the squad's centre, for the
-- host's retries.
function M.update(dt_real, squad)
	check_in = check_in - (dt_real or 0)
	if check_in > 0 then return end
	check_in = M.CHECK_EVERY
	local m = M.mission
	-- A boss the spawn manager couldn't place goes again from the host, at another spot.
	if m and squad and api.game.is_host() then
		for i, b in ipairs(m.plan) do
			if b.spawned == false and (b.retries or 0) <= M.RETRIES then queue(i, squad) end
		end
	end
	local home = (m and m.home) or level.home or "bugs"
	local db = music.on and boosted_db() or nil
	local look = not music.on and (m == nil or M.allowed(m.difficulty))
	local action = M.music_step(music, look and boss_out(), db)
	if action == "play" then
		local ok, why = api.music.play("music_boss_" .. home)
		if ok then
			music.on = true
			obsidian.log("arcade: boss music, " .. home)
			db = boosted_db()
			action = M.music_step(music, true, db)
		else
			obsidian.log("arcade: no boss music: " .. tostring(why))
			check_in = 5
		end
	end
	if action == "volume" then
		api.music.volume(db)
		music.db = db
	end
end

-- The run is over: the music goes back to the game, at the player's own volume.
function M.on_run_stop()
	if music.on then
		pcall(api.music.release)
		pcall(api.music.volume, false)
		obsidian.log("arcade: boss music off")
	end
	music = M.new_music()
	check_in = 0
end

-- A boss, and each part of one (characters/<faction>_boss/...), holds this share of the game's health.
-- Every machine sets an enemy's max health from its settings when the health component starts
-- (HealthComponent.setup_master on the owner, setup_slave on the others), so each machine cuts it
-- there, and the owner starts the boss at the new max. Hits cost what they always did. The share grows
-- with the squad: SQUAD_SCALE[n] times HEALTH_SHARE for n players (1 to 4), so a squad of four meets
-- half the game's boss, where before, every squad met a fifth and four players melted it.
M.HEALTH_SHARE = 0.2
M.SQUAD_SCALE = { 1, 1.5, 2, 2.5 }

-- The share of the game's health a boss holds with `players` in the squad.
function M.health_share(players)
	local n = math.max(1, math.min(math.floor(tonumber(players) or 1), #M.SQUAD_SCALE))
	return M.HEALTH_SHARE * M.SQUAD_SCALE[n]
end

-- The squad's size as every machine sees it: the game's player records with a player object, alive,
-- dead or downed. The game keeps the same records on every machine, so a boss set up on each of them
-- gets the same count (only a player joining or leaving in the same moment could tell them apart).
function M.squad_size()
	local st = api.game and api.game.state and api.game.state()
	local n = 0
	for _, record in ipairs(type(st) == "table" and type(st.players) == "table" and st.players or {}) do
		local go = record.player_go
		local ok, there = pcall(function() return go and go:exists() end)
		if ok and there then n = n + 1 end
	end
	return math.max(n, 1)
end

function M.is_boss_path(path)
	return type(path) == "string" and (path:find("^characters/bug_boss/") or path:find("^characters/cyborg_boss/")
		or path:find("^characters/illuminate_boss/")) ~= nil
end

-- Unit.get_data on a destroyed unit takes the game down in the engine, past any pcall (helldivers.exe +0x13b8e0, the lookup behind every get_data), so a unit is asked only while Unit.alive says it's there.
local function path_of(unit)
	local U = g("Unit")
	local ok_alive, alive = pcall(U.alive, unit)
	if not (ok_alive and alive) then return nil end
	for _, key in ipairs({ "settings_path", "unit_path" }) do
		local ok, path = pcall(U.get_data, unit, key)
		if ok and type(path) == "string" then return path end
	end
	return nil
end

-- A boss's max health from the game's: health_share(players) of it, at least 1. Other units keep theirs.
function M.boss_health(path, health, players)
	if type(health) ~= "number" or health <= 0 or not M.is_boss_path(path) then return health end
	return math.max(1, math.floor(health * M.health_share(players) + 0.5))
end

function M.install()
	for _, method in ipairs({ "setup_master", "setup_slave" }) do
		obsidian.hook("HealthComponent", method, function(original, self, unit, entity, ...)
			local r = { original(self, unit, entity, ...) }
			local state = type(entity) == "table" and entity.state
			local max = state and tonumber(state.max_hitpoints)
			local path = max and path_of(unit)
			local players = M.is_boss_path(path) and M.squad_size() or 1
			local cut = max and M.boss_health(path, max, players)
			if cut and cut ~= max then
				state.max_hitpoints = cut
				if method == "setup_master" then
					state.hitpoints = cut
					self:set_protected(state, "hitpoints_real", cut)
				end
				obsidian.log(string.format("arcade: %s health %d of %d, %d players", tostring(path), cut, max, players))
			end
			return unpack(r)
		end)
	end

	obsidian.hook("GeneratedLevel", "load_resources", function(original, self, ...)
		original(self, ...)
		if not self.survivors or self.arcade_boss_packages then return end
		local plan = M.plan(self.enemy, self.seed)
		M.mission = { home = self.enemy, seed = self.seed, difficulty = self.difficulty, plan = plan }
		self.arcade_boss_packages = {}
		if not M.allowed(self.difficulty) then
			obsidian.log("arcade: difficulty " .. tostring(self.difficulty) .. ", no bosses")
			return
		end
		local packages = g("Boot").package_manager
		for _, name in ipairs(M.packages(plan)) do
			if name ~= self.enemy_package_name and not packages:has_package(name) then
				packages:load_package(name, ...)
				self.arcade_boss_packages[#self.arcade_boss_packages + 1] = name
				obsidian.log("arcade: loading " .. name)
			end
		end
	end)

	obsidian.hook("GeneratedLevel", "has_loaded_resources", function(original, self, ...)
		local loaded = original(self, ...)
		if loaded and self.arcade_boss_packages then
			local packages = g("Boot").package_manager
			for _, name in ipairs(self.arcade_boss_packages) do
				if not packages:is_package_online(name) then return false end
			end
		end
		return loaded
	end)

	obsidian.hook("GeneratedLevel", "release_enemy_package", function(original, self, ...)
		local list = self.arcade_boss_packages
		original(self, ...)
		M.mission = nil
		if not list then return end
		self.arcade_boss_packages = nil
		local packages = g("Boot").package_manager
		for _, name in ipairs(list) do packages:unload_package(name) end
		if #list > 0 then obsidian.log("arcade: unloaded the boss packages") end
	end)

	-- The loading bar counts the boss packages too.
	for _, method in ipairs({ "get_package_size_in_bytes", "get_package_loaded_bytes" }) do
		obsidian.hook("GeneratedLevel", method, function(original, self, ...)
			local size = original(self, ...)
			for _, name in ipairs(self.arcade_boss_packages or {}) do
				local pm = g("Boot").package_manager
				local fn = method == "get_package_size_in_bytes" and pm.get_size_in_bytes or pm.get_loaded_bytes
				local ok, n = pcall(fn, pm, name)
				if ok and type(n) == "number" then size = size + n end
			end
			return size
		end)
	end
end

return M
