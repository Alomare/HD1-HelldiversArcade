-- Trailblazer: a sprint leaves the game's napalm fire on the ground, the Fire elites' (src/elites.lua's
-- FIRE_UNIT: 1.8 m of fire, in mission_common), a patch every STEP metres at most once every EVERY
-- seconds, and each patch goes after the upgrade's seconds (the fire's own life is 5). The fire hurts in
-- two ways, and every machine runs both for its own units: a status for whoever walks into it
-- (FlowCallbacks.status_area_enter), and a blast with a burn every half second
-- (SpawnAreaEffectComponent.update_slaves through ExplosionManager.do_explosion, the patch as the
-- exploding unit). This machine keeps both off the player who left a patch, and everyone else burns.
local hits = obsidian.module("src/hits")

local api = obsidian.import("obsidian.api")

local M = {}

M.UNIT = "gameobjects/gameobject_flamethrower_napalm_area"
M.STEP = 1.5
M.EVERY = 0.2

-- Each patch this machine's players left, and the body that left it.
M.owners = setmetatable({}, { __mode = "k" })

-- Whether a patch is due at `pos`: EVERY seconds since the last and STEP metres from it. t keeps the last.
function M.due(t, pos, now)
	if t.at and now - t.at < M.EVERY then return false end
	if t.pos then
		local dx, dy = pos.x - t.pos.x, pos.y - t.pos.y
		if dx * dx + dy * dy < M.STEP * M.STEP then return false end
	end
	t.at, t.pos = now, { x = pos.x, y = pos.y, z = pos.z }
	return true
end

-- The patches whose time is up, taken out of the list.
function M.expired(list, now)
	local out = {}
	for i = #list, 1, -1 do
		if now >= list[i].ends then out[#out + 1] = table.remove(list, i) end
	end
	return out
end

local function sprinting(unit)
	local cs = api.game.master(unit, "character")
	local sprint = api.game.global("CharacterStateSprint")
	return cs ~= nil and sprint ~= nil and cs.current_state == sprint
end

local function spawner()
	local st = api.game.state()
	return type(st) == "table" and st.entity_spawner or nil
end

local function spawn(pos)
	local s = spawner()
	if not s then return nil end
	local V3, Q = api.game.global("Vector3"), api.game.global("Quaternion")
	local ok, unit = pcall(s.spawn_entity, s, M.UNIT, V3(pos.x, pos.y, pos.z or 0), Q.identity(), nil, {})
	if not ok then
		obsidian.log("arcade: trail: no fire: " .. tostring(unit))
		return nil
	end
	return unit
end

local function despawn(unit)
	M.owners[unit] = nil
	local s = spawner()
	if s and unit and api.game.global("Unit").alive(unit) then pcall(s.despawn_entity, s, unit) end
end

-- Every frame, for each player of this machine (src/perks.lua).
function M.sync(p, unit, dt)
	p.trail = p.trail or { list = {}, clock = 0, spacing = {} }
	local t = p.trail
	t.clock = t.clock + (dt or 0)
	for _, patch in ipairs(M.expired(t.list, t.clock)) do despawn(patch.unit) end
	local seconds = p.stats.trail or 0
	if seconds <= 0 or not sprinting(unit) then return end
	local at = api.game.global("Unit").world_position(unit, 0)
	local pos = { x = at.x, y = at.y, z = at.z }
	if not M.due(t.spacing, pos, t.clock) then return end
	local patch = spawn(pos)
	if patch then
		M.owners[patch] = unit
		t.list[#t.list + 1] = { unit = patch, ends = t.clock + seconds }
	end
end

-- The run is over: the patches go before the level does.
function M.release(p)
	for _, patch in ipairs(p and p.trail and p.trail.list or {}) do despawn(patch.unit) end
	if p then p.trail = nil end
end

-- One of a patch's blasts: its hits on the player who left it are dropped as they go out.
function M.pulse(original, manager, unit, ...)
	local owner = unit ~= nil and M.owners[unit] or nil
	if owner == nil then return original(manager, unit, ...) end
	return hits.with(function(victim, interface, command)
		if victim == owner and hits.is_hit(interface, command) then return false end
	end, original, manager, unit, ...)
end

function M.install()
	obsidian.hook("FlowCallbacks", "status_area_enter", function(original, params, ...)
		if type(params) == "table" and params.touched_unit ~= nil and M.owners[params.touched_unit] ~= nil
			and M.owners[params.touched_unit] == params.touching_unit then
			return
		end
		return original(params, ...)
	end)
	obsidian.hook("ExplosionManager", "do_explosion", M.pulse)
end

return M
