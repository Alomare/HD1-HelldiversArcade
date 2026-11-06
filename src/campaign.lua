-- A Survivors mission leaves the campaign as it was, won or lost: no mission or planet done, no planet
-- stats, no event or boss progress, and the player's own planet stays the one in the save.
--
-- What the game does at a mission's end (StateMissionEnd, the first host only): on_enter reads the
-- save's current planet and, for a win, marks its selected mission done in the planet and in
-- available_planets, finishes the planet when that was its last mission (num_completed_planets,
-- last_planet, completed_planets, boss_planets, current_planet let go), or completes a defend or attack
-- event and draws the planet's missions again. save_stats adds the mission's deaths, kills and shots to
-- the planet, and the planet being done adds to boss_influence and the leaderboard rows. All of it
-- starts from the current planet: with none, on_enter and save_stats skip every bit. So for a Survivors
-- mission the screen sees no planet, and whatever it changes in the campaign's keys anyway goes back.
-- Obsidian's loader already drops the war reports (mission_stats, completed_planets, the leaderboard
-- queues) and the CampaignManager uploads.
--
-- The hellpods open only with a planet in the save (StateMenu.update_host). The planet they take for a
-- Survivors drop is lent: it sits in the save only while update_host runs, and the save goes back to
-- the player's own planet, or none, before anything else reads or writes it.
local M = { lent = nil }

-- The campaign's keys in the save's common data.
M.KEYS = { "current_planet", "available_planets", "last_planet", "boss_planets", "dropzone_position", "next_mission_seed" }

local function g(name) return rawget(_G, name) end

function M.copy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = M.copy(x) end
	return out
end

function M.same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, x in pairs(a) do
		if not M.same(x, b[k]) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

-- The campaign's keys as they are now: each value, and a copy of it, since the game changes the save's
-- tables in place.
function M.snapshot(save)
	local snap = {}
	for _, key in ipairs(M.KEYS) do
		local v = save:get(key)
		snap[key] = { value = v, copy = M.copy(v) }
	end
	return snap
end

-- Puts back every key that changed since `snap`: the same table when only the key was replaced, the
-- copy when the table itself was changed. The keys put back, in M.KEYS order.
function M.restore(save, snap)
	local back = {}
	for _, key in ipairs(M.KEYS) do
		local was = snap[key]
		if not M.same(save:get(key), was.copy) then
			save:set(key, M.same(was.value, was.copy) and was.value or M.copy(was.copy))
			back[#back + 1] = key
		end
	end
	return back
end

local function run(save, fn, ...)
	local snap = M.snapshot(save)
	local ok, err = pcall(fn, ...)
	local back = M.restore(save, snap)
	if not ok then error(err, 0) end
	return back
end

-- StateMissionEnd.on_enter for a Survivors mission. The screen reads no current planet, and a machine
-- that isn't the first host (one that took over as host) doesn't take the mission for the planet's
-- last (params.is_last_mission). The keys put back besides the hidden planet, which should be none.
function M.mission_end(save, original, state, params, ...)
	if type(params) == "table" then params.is_last_mission = false end
	local args = { n = select("#", ...), ... }
	local back = run(save, function()
		save:set("current_planet", nil)
		original(state, params, unpack(args, 1, args.n))
	end)
	local others = {}
	for _, key in ipairs(back) do
		if key ~= "current_planet" then others[#others + 1] = key end
	end
	return others
end

-- StateMissionEnd.save_stats for a Survivors mission: no planet to add the mission's numbers to.
function M.save_stats(save, original, state, ...)
	state.current_planet, state.current_enemy_index, state.current_planet_index = nil, nil, nil
	return run(save, original, state, ...)
end

-- A planet the hellpods can take: in the save's form, with a region and a selected mission.
function M.usable(p)
	return type(p) == "table" and p.region ~= nil and type(p.missions) == "table" and type(p.selected_mission_index) == "number"
		and p.missions[p.selected_mission_index] ~= nil
end

-- The planet a Survivors drop lends the hellpods. The player's own when it's on the mission's front,
-- or else a copy of a campaign planet with a mission left, the mission's front first, or else the
-- player's own on another front. pick_planet(available, front) is src/entry.lua's.
function M.pick(own, available, front, pick_planet)
	if M.usable(own) and own.enemy == front - 1 then return own end
	local other = pick_planet(available, front)
	if other then return M.copy(other) end
	if M.usable(own) then return own end
	return nil
end

function M.lend(planet) M.lent = planet end

-- fn(...) with `planet` as the save's current planet, and the save's own one back after.
function M.with_planet(save, planet, fn, ...)
	local own = save:get("current_planet")
	if planet == nil or own == planet then return fn(...) end
	save:set("current_planet", planet)
	local ok, err = pcall(fn, ...)
	if save:get("current_planet") == planet then save:set("current_planet", own) end
	if not ok then error(err, 0) end
end

-- is_survivors(seed): src/seed.lua's. drop(): the seed the host's next drop is set to, or nil.
function M.install(is_survivors, drop)
	obsidian.hook("StateMissionEnd", "on_enter", function(original, self, params, ...)
		if not (type(params) == "table" and is_survivors(params.mission_seed)) then return original(self, params, ...) end
		local back = M.mission_end(g("SaveManager"), original, self, params, ...)
		obsidian.log("arcade: the mission's end left the campaign alone" .. (#back > 0 and (", put back: " .. table.concat(back, ", ")) or ""))
	end)
	obsidian.hook("StateMissionEnd", "save_stats", function(original, self, ...)
		if not is_survivors(self.mission_seed) then return original(self, ...) end
		local back = M.save_stats(g("SaveManager"), original, self, ...)
		if #back > 0 then obsidian.log("arcade: the mission's stats left the campaign alone, put back: " .. table.concat(back, ", ")) end
	end)
	obsidian.hook("StateMenu", "update_host", function(original, self, ...)
		local s = drop()
		if not (M.lent and is_survivors(s)) then return original(self, ...) end
		return M.with_planet(g("SaveManager"), M.lent, original, self, ...)
	end)
end

return M
