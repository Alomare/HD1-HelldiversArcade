-- The map of a Survivors mission: no objectives, and all three factions loaded with the level, on every
-- machine, before anyone drops. Boss Variety loads a second race package the same way.
local seed = obsidian.module("src/seed")
local rules = obsidian.module("src/rules")

local M = { active = false, home = nil, extract_open = false }

local FACTIONS = { "bugs", "cyborgs", "illuminates" }
local PACKAGES = "resource_packages/race_"
local OWN_HINTS = "obsidian_" -- Obsidian's notices and every mod's words (obsidian.notify)

local function packages()
	return rawget(_G, "Boot").package_manager
end

local function is_extract(o)
	return o.type == "objective_extract_lz" or o.name == "mission_objective_extract"
end

-- Whether a map piece of the environment's objective list (a name such as "mission_1x1_antenna_01") is
-- one of the kinds a Survivors map takes (rules.OBJECTIVE_KINDS).
function M.allowed_objective(name)
	if type(name) ~= "string" or name:find("fortify", 1, true) then return false end
	for _, kind in ipairs(rules.OBJECTIVE_KINDS) do
		if name:find("_" .. kind .. "_", 1, true) then return true end
	end
	return false
end

-- The game spends a mission's points (its difficulty) on objectives, each at its cost, in
-- GeneratedLevel.generate_mission. A Survivors map offers it only the allowed kinds, at their own costs,
-- so it gets as many as the game would give. nil when none of the list is allowed.
function M.allowed_objectives(list)
	local out = {}
	for _, m in ipairs(list or {}) do
		if M.allowed_objective(m.name) then out[#out + 1] = m end
	end
	return #out > 0 and out or nil
end

-- The hint box is busy: one showing or one waiting.
function M.hint_busy(hints)
	return type(hints) == "table" and (hints.current_hint ~= nil or #(hints.queued_hints or {}) > 0)
end

-- What the objective list shows in a Survivors mission: the objectives left to do while the run goes
-- on, and only the extraction once the shuttle can be called.
function M.listed(objectives, extract_open)
	local out = {}
	for _, o in ipairs(objectives or {}) do
		if extract_open then
			if is_extract(o) then out[#out + 1] = o end
		elseif not is_extract(o) and o.state == "pending" then
			out[#out + 1] = o
		end
	end
	return out
end

function M.install()
	-- Only the run's own words in a Survivors mission (src/run.lua), with Obsidian's notices: none of
	-- the game's hints. Its extraction tip, for one, says to extract once the objectives are done, which
	-- here isn't possible until the run is won. A mod's words carried by a hint of the game come with
	-- the words as their parameters (Obsidian API's hint without obsidian.notify), and pass.
	obsidian.hook("HintManager", "add_hint", function(original, self, name, override, params, ...)
		if M.active and params == nil and not (type(name) == "string" and name:sub(1, #OWN_HINTS) == OWN_HINTS) then return end
		return original(self, name, override, params, ...)
	end)
	-- The game holds a hint back while the objective list shows, and here the list stays up all run, so
	-- a hint waited for the shuttle at 12 minutes. In a Survivors mission the hint shows at once, and the
	-- list makes way for it (below).
	obsidian.hook("HintManager", "update", function(original, self, ...)
		local missions = self.mission_manager
		if not (M.active and missions) then return original(self, ...) end
		self.mission_manager = nil
		local ok, err = pcall(original, self, ...)
		self.mission_manager = missions
		if not ok then error(err, 0) end
	end)
	-- Once the shuttle can be called, the map's objectives are done without the game's banner, music
	-- and "objective completed" event (src/run.lua completes them): an objective whose state changes
	-- then is taken as having had that state all along.
	obsidian.hook("MissionManager", "update", function(original, self, ...)
		if M.active and M.extract_open then
			for _, o in ipairs(self.objectives or {}) do
				if not is_extract(o) then o.last_state = o.state end
			end
		end
		return original(self, ...)
	end)
	-- Samples here are what kills drop, so the map keeps none of its own.
	obsidian.hook("StateGame", "setup_world", function(original, self, ...)
		if seed.is_survivors(self.mission_seed) then self.num_research_samples = 0 end
		return original(self, ...)
	end)
	obsidian.hook("StateGame", "spawn_research_samples_on_all_markers", function(original, self, ...)
		if seed.is_survivors(self.mission_seed) then return end
		return original(self, ...)
	end)
	-- Wraps: the Survivors screen's map preview (MapWidget, a level with no world) shows the map's
	-- objectives before the content starts. The map of a mission played is a Survivors one only while
	-- the content runs, so outside it every mission keeps the game's own.
	obsidian.wrap("GeneratedLevel", "initialize", function(original, self, world, mission_seed, ...)
		original(self, world, mission_seed, ...)
		self.survivors = seed.is_survivors(mission_seed) and self.mission_type_name == "mission"
			and (world == nil or obsidian.expansion.running())
		-- A map preview has no world, and isn't the mission being played.
		if world == nil then return end
		M.active, M.home, M.extract_open = self.survivors, self.survivors and self.enemy or nil, false
		if self.survivors then obsidian.log("arcade: map for seed " .. tostring(mission_seed) .. ", " .. tostring(self.enemy)) end
	end)

	-- The map's objectives stay unless the rules say otherwise: samples away from the fight, of the
	-- kinds in rules.OBJECTIVE_KINDS only, as many as the game gives. Every machine builds the map the
	-- same way.
	obsidian.wrap("GeneratedLevel", "generate_mission", function(original, self, ...)
		if not self.survivors then return original(self, ...) end
		if not rules.MAP_OBJECTIVES then
			obsidian.log("arcade: no objectives")
			return
		end
		local env = self.environment
		local allowed = type(env) == "table" and M.allowed_objectives(env.mission)
		if not allowed then return original(self, ...) end
		self.environment = setmetatable({ mission = allowed }, { __index = env })
		local ok, err = pcall(original, self, ...)
		self.environment = env
		if not ok then error(err, 0) end
	end)

	-- The map keeps its extraction, which the mission needs to start, but nobody can call the shuttle
	-- until the run is won. Each player's own copy of the beacon decides whether it can be used.
	obsidian.hook("ExtractBeaconComponent", "reload_slave", function(original, self, unit, record, ...)
		original(self, unit, record, ...)
		local state = record and record.state
		if type(state) ~= "table" or type(state.can_interact) ~= "function" or state.ses_wrapped then return end
		local can = state.can_interact
		state.ses_wrapped = true
		state.can_interact = function(...)
			if M.active and not M.extract_open then return false end
			return can(...)
		end
	end)
	obsidian.hook("ExtractBeaconComponent", "should_draw_ui", function(original, self, ...)
		if M.active and not M.extract_open then return false end
		return original(self, ...)
	end)
	-- The objective list, beside the run's bar, shows what's left to do on the map, and stays up rather
	-- than fading out after the drop. Extract isn't on it until the run is won, and then it's all there
	-- is. A hint takes the list's place while it shows, as in the game, and the bar stays where it is.
	obsidian.hook("MissionManager", "draw_objective_list", function(original, self, ...)
		if not M.active then return original(self, ...) end
		if M.choosing then return end
		if M.hint_busy(self.hint_manager) then
			M.objectives_at = os.clock()
			return
		end
		local all = self.objectives
		local shown = M.listed(all, M.extract_open)
		if #shown == 0 then return end
		M.objectives_at = os.clock()
		local timer, display = self.display_objectives_timer, self.display_objectives
		self.objectives, self.display_objectives_timer, self.display_objectives = shown, math.max(timer or 0, 2), true
		local ok, err = pcall(original, self, ...)
		self.objectives, self.display_objectives_timer, self.display_objectives = all, timer, display
		if not ok then error(err, 0) end
	end)

	-- The loading screen names the mission's planet, the same one on every machine since it comes from
	-- the seed. Without it a mission started without a planet shows the key it lacks.
	obsidian.hook("StateMissionStart", "on_enter", function(original, self, params, ...)
		if type(params) == "table" and seed.is_survivors(params.mission_seed) then
			params.planet_name = seed.planet_key(params.mission_seed)
		end
		return original(self, params, ...)
	end)

	obsidian.hook("GeneratedLevel", "load_resources", function(original, self, ...)
		original(self, ...)
		if not self.survivors or self.ses_packages then return end
		self.ses_packages = {}
		for _, faction in ipairs(FACTIONS) do
			local name = PACKAGES .. faction
			if faction ~= self.enemy and name ~= self.enemy_package_name then
				packages():load_package(name, ...)
				self.ses_packages[#self.ses_packages + 1] = name
				obsidian.log("arcade: loading " .. name)
			end
		end
	end)

	obsidian.hook("GeneratedLevel", "has_loaded_resources", function(original, self, ...)
		local loaded = original(self, ...)
		if loaded and self.ses_packages then
			for _, name in ipairs(self.ses_packages) do
				if not packages():is_package_online(name) then return false end
			end
		end
		return loaded
	end)

	obsidian.hook("GeneratedLevel", "release_enemy_package", function(original, self, ...)
		local list = self.ses_packages
		original(self, ...)
		M.active, M.home = false, nil
		if not list then return end
		self.ses_packages = nil
		for _, name in ipairs(list) do packages():unload_package(name) end
		obsidian.log("arcade: unloaded the extra factions")
	end)

	-- The loading bar counts the extra packages too.
	for _, method in ipairs({ "get_package_size_in_bytes", "get_package_loaded_bytes" }) do
		obsidian.hook("GeneratedLevel", method, function(original, self, ...)
			local size = original(self, ...)
			for _, name in ipairs(self.ses_packages or {}) do
				local pm = packages()
				local fn = method == "get_package_size_in_bytes" and pm.get_size_in_bytes or pm.get_loaded_bytes
				local ok, n = pcall(fn, pm, name)
				if ok and type(n) == "number" then size = size + n end
			end
			return size
		end)
	end
end

return M
