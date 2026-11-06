-- XP as research samples lying in the level: each orb is the sample of the faction whose enemy dropped
-- it, bigger the more XP it holds, with the game's own glow recolored blue (M.tint). They're props (Obsidian
-- API's api.world.prop): units on this machine only, so nothing goes over the network. All three
-- factions' packages are loaded on a Survivors map (src/level.lua), and their samples with them.
local M = { live = {}, going = {} }

-- How long a taken sample takes to shrink away, so its pickup effect starts and it doesn't just vanish.
M.LINGER = 0.15

M.UNITS = {
	bugs = "gameobjects_spec/gameobject_bug_research_object",
	cyborgs = "gameobjects_spec/gameobject_cyborg_research_object",
	illuminates = "gameobjects_spec/gameobject_illuminate_research_object",
}

-- The glow of a sample: the game's research objects share one material whose "color" (1, 0.194, 0 at
-- an intensity of 8.8) blooms into a yellow glow. Each prop here gets this color on its own material
-- instances (Mesh.material, as the game's cloaking does it), so samples outside the run keep theirs.
-- The glow is bright enough to bloom, so any green or red in it washes the middle out to white: this
-- holds little of either, for the deep blue of the XP bar's fill (#3a8ee6). 0.05, 0.3, 1 before.
M.GLOW = { 0.01, 0.07, 1 }

local function g(name) return rawget(_G, name) end

function M.tint(unit)
	local U, mesh_of, material, V3 = g("Unit"), g("Mesh"), g("Material"), g("Vector3")
	if not (unit and U and mesh_of and material and V3) then return end
	local color = V3(M.GLOW[1], M.GLOW[2], M.GLOW[3])
	for i = 0, U.num_meshes(unit) - 1 do
		local mesh = U.mesh(unit, i)
		for j = 0, mesh_of.num_materials(mesh) - 1 do material.set_vector3(mesh_of.material(mesh, j), "color", color) end
	end
end

-- How a new sample arrives: it grows out of nothing with a little overshoot, in a small hop.
M.POP = 0.4 -- seconds
M.HOP = 0.7 -- metres

function M.pop(age)
	local t = age / M.POP
	if t >= 1 then return 1 end
	local back = t - 1
	return math.max(1 + 2.70158 * back ^ 3 + 1.70158 * back ^ 2, 0.05)
end

local function hopped(orb)
	local t = orb.age / M.POP
	if t >= 1 then return orb end
	return { x = orb.x, y = orb.y, z = (orb.z or 0) + M.HOP * 4 * t * (1 - t) }
end

-- A sample's size by the XP it holds: the rarer the drop, the bigger.
function M.size(xp)
	if xp >= 60 then return 2.4 end
	if xp >= 20 then return 1.9 end
	if xp >= 8 then return 1.45 end
	return 1
end

-- Brings the props in line with the run's orbs: new orbs get one, pulled orbs move theirs, merged
-- orbs grow, and orbs that are gone take theirs away; a taken one plays the game's pickup first.
-- world: Obsidian API's api.world. dt: seconds. false when props can't be made, so the caller can
-- draw the orbs instead.
function M.sync(world, list, dt)
	if not world.prop or M.failed then return false end
	local still = {}
	for _, g in ipairs(M.going) do
		g.left = g.left - (dt or 0)
		if g.left > 0 then
			g.prop:scale(math.max(g.size * g.left / M.LINGER, 0.05))
			still[#still + 1] = g
		else
			g.prop:remove()
		end
	end
	M.going = still
	local now = {}
	for _, orb in ipairs(list) do
		if not orb.prop then
			local size = M.size(orb.xp)
			local prop, why = world.prop(M.UNITS[orb.faction] or M.UNITS.bugs, hopped(orb), { scale = size * M.pop(orb.age or 0) })
			if not prop then
				if why ~= "not_in_mission" then
					M.failed = true
					obsidian.log("arcade: no samples for XP: " .. tostring(why))
				end
				return false
			end
			orb.prop, orb.size, orb.at_x, orb.at_y = prop, size, orb.x, orb.y
			if not M.untinted then
				local ok, err = pcall(M.tint, prop.unit)
				-- Once is enough to know: the samples keep the game's glow from then on.
				if not ok then
					M.untinted = true
					obsidian.log("arcade: the samples keep the game's glow: " .. tostring(err))
				end
			end
		else
			local popping = orb.age < M.POP or not orb.settled
			if popping or orb.x ~= orb.at_x or orb.y ~= orb.at_y then
				orb.prop:move(hopped(orb))
				orb.at_x, orb.at_y = orb.x, orb.y
			end
			local size = M.size(orb.xp)
			if popping or size ~= orb.size then
				orb.prop:scale(size * M.pop(orb.age))
				orb.size = size
			end
			orb.settled = orb.age >= M.POP
		end
		now[orb] = true
	end
	for orb in pairs(M.live) do
		if not now[orb] then
			if orb.taken and orb.prop.flow then
				orb.prop:flow("on_picked_up")
				M.going[#M.going + 1] = { prop = orb.prop, left = M.LINGER, size = orb.size or 1 }
			else
				orb.prop:remove()
			end
		end
	end
	M.live = now
	return true
end

function M.clear()
	for orb in pairs(M.live) do orb.prop:remove() end
	for _, g in ipairs(M.going) do g.prop:remove() end
	M.live, M.going = {}, {}
	M.failed = false
end

return M
