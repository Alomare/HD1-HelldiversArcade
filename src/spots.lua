-- Where the director's enemies come in. The game's spawn manager takes a group's spot, casts rays down
-- in a ring about 5 metres around it, and keeps the hits on the ground (between -0.2 and 1 metres up).
-- When too few land, it moves the spot a few metres at random and tries again, up to ten times, with no
-- look at the map's bounds (spawn_manager.lua, queue_group_spawn and update). So a spot just inside the
-- level, next to the border, put enemies in or behind the border walls. A spot here keeps a margin from
-- the border tiles of the map and stands on open ground, so the first ring lands and the group never
-- wanders off.
local M = {}

-- The map is made of 24-metre tiles, and the border walls stand in the edge tiles. Points this far from
-- the spot, all around, also have to be on the level (GeneratedLevel.is_position_on_level: a tile that
-- exists and isn't an edge tile).
M.MARGIN = 10
M.MARGIN_POINTS = 8
-- The ground band the spawn manager takes a hit in, and the ring checked for room for a group.
M.GROUND_LOW = -0.2
M.GROUND_HIGH = 1
M.RING = 4
M.RING_POINTS = 4
M.RING_NEEDED = 3
M.TRIES = 16

-- Whether a ray down at (x, y) finds ground the spawn manager takes: true or false, and true when
-- `ground` can't tell (nil from it).
local function on_ground(ground, x, y)
	if not ground then return true end
	local z = ground(x, y)
	if z == nil then return true end
	if z == false then return false end
	return z > M.GROUND_LOW and z < M.GROUND_HIGH
end

-- Whether enemies can come in at (x, y). on_level(x, y): true on a tile of the level that isn't an edge
-- tile. ground(x, y): the height of the first hit of a ray down, false for no hit, nil when unknown.
function M.clear(x, y, on_level, ground)
	if not on_level(x, y) then return false end
	for i = 1, M.MARGIN_POINTS do
		local a = (i - 1) * 2 * math.pi / M.MARGIN_POINTS
		if not on_level(x + math.cos(a) * M.MARGIN, y + math.sin(a) * M.MARGIN) then return false end
	end
	if not on_ground(ground, x, y) then return false end
	local landed = 0
	for i = 1, M.RING_POINTS do
		local a = (i - 1) * 2 * math.pi / M.RING_POINTS
		if on_ground(ground, x + math.cos(a) * M.RING, y + math.sin(a) * M.RING) then landed = landed + 1 end
	end
	return landed >= M.RING_NEEDED
end

-- A spot `from` to `to` metres around `pos` where enemies can come in, or nil. r: an rng (src/rng.lua).
-- checks: { on_level, ground, pull_in } as for M.clear; pull_in(x, y) answers the nearest point well
-- inside the level ({ x, y }, the game's get_closest_position_on_level), tried on the first spot when
-- every try misses, and taken when it is clear and at least `from` / 2 metres from `pos`.
function M.around(pos, from, to, r, checks)
	local first
	for _ = 1, M.TRIES do
		local angle = r:random() * math.pi * 2
		local radius = from + r:random() * (to - from)
		local x, y = pos.x + math.cos(angle) * radius, pos.y + math.sin(angle) * radius
		first = first or { x = x, y = y }
		if M.clear(x, y, checks.on_level, checks.ground) then return { x = x, y = y, z = pos.z } end
	end
	if first and checks.pull_in then
		local p = checks.pull_in(first.x, first.y)
		if p and (p.x - pos.x) ^ 2 + (p.y - pos.y) ^ 2 >= (from / 2) ^ 2 and M.clear(p.x, p.y, checks.on_level, checks.ground) then
			return { x = p.x, y = p.y, z = pos.z }
		end
	end
	-- A ground check that never lands (a ray that answers nothing useful in this map) mustn't stop every
	-- spawn: the margin from the border alone, then.
	if checks.ground then
		for _ = 1, M.TRIES do
			local angle = r:random() * math.pi * 2
			local radius = from + r:random() * (to - from)
			local x, y = pos.x + math.cos(angle) * radius, pos.y + math.sin(angle) * radius
			if M.clear(x, y, checks.on_level, nil) then return { x = x, y = y, z = pos.z } end
		end
	end
	return nil
end

-- The checks of the mission being played, from the game's level and physics, or nil off a mission.
-- raycast: Obsidian API's world.raycast.
function M.of_level(map, raycast)
	if not map then return nil end
	local V3 = rawget(_G, "Vector3")
	local checks = {}
	function checks.on_level(x, y)
		local ok, on = pcall(map.is_position_on_level, map, V3(x, y, 0))
		return ok and on and true or false
	end
	if raycast then
		function checks.ground(x, y)
			-- The spawn manager's own ray: from 100 metres up, with the same collision filter.
			local ok_cast, hit, at = pcall(raycast, { x = x, y = y, z = 100 }, { x = x, y = y, z = -100 }, "spawn_check")
			if not ok_cast then return nil end
			if hit then
				local ok, z = pcall(function() return at.z end)
				if ok and type(z) == "number" then return z end
				return nil
			end
			-- A reason in place of the hit's position: the ray couldn't be cast, so nothing is known.
			if at ~= nil then return nil end
			return false
		end
	end
	if map.get_closest_position_on_level then
		function checks.pull_in(x, y)
			local ok, p = pcall(map.get_closest_position_on_level, map, V3(x, y, 0))
			if not (ok and p) then return nil end
			local okx, px, py = pcall(function() return p.x, p.y end)
			if okx and type(px) == "number" then return { x = px, y = py } end
			return nil
		end
	end
	return checks
end

return M
