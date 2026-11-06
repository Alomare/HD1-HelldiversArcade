-- Elusive Tactics and Warp Pack (src/upgrades.lua): a player's dive goes farther, they get up sooner from
-- a dive, a knockdown or being downed, and Warp Pack moves them ahead as the dive starts. Each is one of
-- the game's character states, shared by every character, so each hook looks for the player whose unit
-- it is: find(unit) answers their stats, or nil.
local M = {}

M.WARP_GAP = 0.8 -- metres kept from whatever stops the warp
M.WARP_LEAST = 1.5 -- a warp shorter than this isn't made
M.CHEST = 1 -- metres over the feet the warp's line runs, so a kerb doesn't stop it

-- A warp looks like the Displacement Field's teleport (TeleportShieldComponent, with the effects of
-- characters/helldiver_private_01's teleport_shield_info, in mission_common): a burst left where the
-- player was, and one on the player where they land. Every other machine gets the first through the
-- perk's own message, rpc_teleport_shield_out, which plays only that burst, and plays the second
-- itself once the player's unit jumps there.
M.WARP_OUT = "effects/generated/teleport_shield_teleport_out"
M.WARP_IN = "effects/generated/teleport_shield_teleport_in"
M.EFFECT_NODE = "root"
M.ARRIVE = 1 -- metres from the target that count as landed, as for the perk
M.JUMP = 2.5 -- metres in one frame that count as the landing, where the target isn't known
M.WATCH = 1 -- seconds a warp is watched for its landing

-- The states that get a player up, and the timers each counts down, in the order they run. A knockdown
-- stays down, then gets up. It's a blast's, and also a Cyborg Hound's takedown: the hound's special
-- attack carries the "regular_knockdown" status (characters/cyborg_dog), which puts the player in this
-- same state, as the bug tanks' attacks do. Getting up when downed, once.
M.GET_UP = {
	CharacterStateKnockedDown = { "stay_down_timer", "get_up_timer" },
	CharacterStateDownedGetUp = { "get_up_timer" },
}
-- A dive's getting up runs on one timer that counts up to the end of the dive's recovery. It starts in
-- the dive's state, and a player holding a direction finishes it crawling (CharacterStateDodge.update
-- moves to CharacterStateCrawl), so both run it.
M.DIVE_STATES = { "CharacterStateDodge", "CharacterStateCrawl" }

local function g(name) return rawget(_G, name) end

-- Warps waiting for their landing, by unit: { target = { x, y, z } or nil, last = { x, y, z } or nil,
-- left = seconds }.
local watched = {}

-- Flat: a teleport lifts the player a little where they don't fit (api.player.teleport).
local function distance(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

local function plain(v) return { x = v.x, y = v.y, z = v.z } end

-- Whether a watched warp has landed with the unit at `pos`: within M.ARRIVE of a known target or,
-- without one, after a jump of M.JUMP or more since the last frame.
function M.landed(w, pos)
	if w.target then return distance(pos, w.target) <= M.ARRIVE end
	return w.last ~= nil and distance(pos, w.last) >= M.JUMP
end

local function shield()
	local aux = g("EntityAux")
	return aux and aux.get_component and aux.get_component("teleport_shield") or nil
end

-- One of the perk's effects (TeleportShieldComponent.do_effect): on the unit's node and linked to it,
-- or left at `at`.
local function effect(world, name, unit, at)
	local U, W = g("Unit"), g("World")
	local node = 0
	if unit then
		local ok, n = pcall(U.node, unit, M.EFFECT_NODE)
		if ok and n then node = n end
	end
	local id = W.create_particles(world, name, at or U.world_position(unit, node))
	if unit and id then W.link_particles(world, id, unit, node, g("Matrix4x4").identity(), "destroy") end
end

-- Each frame, from the perk's own update on every machine: the landing burst for warps that landed.
local function watch(comp, dt)
	local U = g("Unit")
	local world = comp.world_proxy:get_world()
	for unit, w in pairs(watched) do
		if not U.alive(unit) then
			watched[unit] = nil
		else
			local pos = plain(U.world_position(unit, 0))
			if M.landed(w, pos) then
				watched[unit] = nil
				effect(world, M.WARP_IN, unit)
			else
				w.last, w.left = pos, w.left - (dt or 0)
				if w.left <= 0 then watched[unit] = nil end
			end
		end
	end
end

-- How far a warp of `metres` goes when something stops the line after `blocked` metres (nil: nothing does).
function M.warp_length(metres, blocked)
	local length = blocked and math.min(metres, blocked - M.WARP_GAP) or metres
	return length >= M.WARP_LEAST and length or nil
end

-- Ahead along the dive, flat, up to whatever would stop a body walking, and only onto the level.
local function warp(api, unit, metres)
	local U, Q, V3 = g("Unit"), g("Quaternion"), g("Vector3")
	local from = U.world_position(unit, 0)
	local facing = Q.forward(U.local_rotation(unit, 0))
	local flat = V3(facing.x, facing.y, 0)
	if V3.length(flat) < 0.01 then return end
	local dir = V3.normalize(flat)
	local up = V3(0, 0, M.CHEST)
	local hit, _, distance = api.world.raycast(from + up, from + up + dir * metres, "mover_blocker")
	local length = M.warp_length(metres, hit == true and distance or nil)
	if not length then return end
	local to = from + dir * length
	local st = api.game.state()
	local map = type(st) == "table" and st.generated_level
	if map then
		local ok, on = pcall(map.is_position_on_level, map, to)
		if ok and not on then return end
	end
	-- The burst where the player leaves, here and on every other machine, then the landing's once the
	-- unit is there (watch).
	local comp = shield()
	if comp then
		local ok, err = pcall(function()
			effect(comp.world_proxy:get_world(), M.WARP_OUT, nil, from)
			comp:trigger_rpc_event_to_others("rpc_teleport_shield_out", unit)
		end)
		if not ok then obsidian.log("arcade: warp effect failed: " .. tostring(err)) end
	end
	local moved = api.player.teleport(to, unit)
	if comp and moved then watched[unit] = { target = plain(to), left = M.WATCH } end
end

-- The first of a state's timers still running counts down faster by `by`, for this frame's `dt`. They run
-- one after the other, and the next starts once the one before is gone.
function M.hurry(state, fields, dt, by)
	for _, field in ipairs(fields) do
		if type(state[field]) == "number" then
			state[field] = state[field] - dt * (by - 1)
			return
		end
	end
end

-- Elusive Tactics: as a dive starts, the enemies within DIVE_STUN_RADIUS of the player are stunned for the
-- upgrade's seconds, by this player, as hits of no power carrying the stun (Obsidian API's apply_status).
-- The game's stuns last 1 second (dog_hit_obstacle_stun) or 3 (flashbang_stun), so a length between is
-- the short one again each second. M.step runs the ones still to come, on the run's clock.
M.STUN_SHORT, M.STUN_LONG = "dog_hit_obstacle_stun", "flashbang_stun"
function M.stun_plan(seconds)
	local plan, n = {}, math.floor((seconds or 0) + 0.5)
	local from = 0
	if n >= 3 then
		plan[1] = { at = 0, status = M.STUN_LONG }
		from = 3
	end
	for i = from, n - 1 do plan[#plan + 1] = { at = i, status = M.STUN_SHORT } end
	return plan
end

M.queue, M.now = {}, 0

-- A run starting or over: stuns still to come belong to the old run's enemies and clock.
function M.clear()
	M.queue, M.now = {}, 0
end

local function stun_near(api, unit, seconds)
	local enemies = api.enemies.near(obsidian.module("src/upgrades").DIVE_STUN_RADIUS, g("Unit").world_position(unit, 0))
	if #enemies == 0 then return end
	for _, step in ipairs(M.stun_plan(seconds)) do M.queue[#M.queue + 1] = { at = M.now + step.at, status = step.status, enemies = enemies } end
	M.step(api, M.now)
end

function M.step(api, now)
	M.now = now
	for i = #M.queue, 1, -1 do
		local q = M.queue[i]
		if now >= q.at then
			table.remove(M.queue, i)
			for _, enemy in ipairs(q.enemies) do pcall(api.enemies.apply_status, enemy, q.status) end
		end
	end
end

-- A dive's recovery, once the player is getting up (dive_get_up): its timer counts up faster by `by`.
-- Before that, holding dodge keeps the player down as long as they like, so nothing changes.
function M.hurry_dive(state, dt, by)
	if state.dive_get_up and type(state.dive_timer) == "number" then
		state.dive_timer = state.dive_timer + dt * (by - 1)
	end
end

function M.install(api, find)
	obsidian.hook("CharacterStateDodge", "on_enter", function(original, unit, ctx, ...)
		original(unit, ctx, ...)
		local stats = find(unit)
		if not stats then return end
		if stats.dive ~= 1 and type(ctx.state.wanted_move_speed) == "number" then
			ctx.state.wanted_move_speed = ctx.state.wanted_move_speed * stats.dive
		end
		if (stats.dive_stun or 0) > 0 then
			local ok, err = pcall(stun_near, api, unit, stats.dive_stun)
			if not ok then obsidian.log("arcade: dive stun failed: " .. tostring(err)) end
		end
		if stats.warp > 0 and api.world.raycast then
			local ok, err = pcall(warp, api, unit, stats.warp)
			if not ok then obsidian.log("arcade: warp failed: " .. tostring(err)) end
		end
	end)
	-- Another machine's warp: its landing burst plays here once the unit jumps. The perk's own teleport
	-- sends the same message, and plays its landing itself: it goes off only from a charged shield,
	-- whose idle effect shows.
	obsidian.hook("TeleportShieldComponent", "rpc_teleport_shield_out", function(original, self, sender, unit, ...)
		original(self, sender, unit, ...)
		local U, aux = g("Unit"), g("EntityAux")
		if not (unit and U.alive(unit)) or watched[unit] then return end
		local ok, state = pcall(aux.state, unit, "teleport_shield")
		if ok and type(state) == "table" and state.teleport_shield_idle then return end
		watched[unit] = { last = plain(U.world_position(unit, 0)), left = M.WATCH }
	end)
	obsidian.hook("TeleportShieldComponent", "update_slaves", function(original, self, entities, dt, ...)
		original(self, entities, dt, ...)
		if next(watched) == nil then return end
		local ok, err = pcall(watch, self, dt)
		if not ok then
			watched = {}
			obsidian.log("arcade: warp landing failed: " .. tostring(err))
		end
	end)
	for _, state_class in ipairs(M.DIVE_STATES) do
		obsidian.hook(state_class, "update", function(original, unit, ctx, dt, ...)
			local stats = find(unit)
			if stats and stats.get_up > 1 and type(dt) == "number" then M.hurry_dive(ctx.state, dt, stats.get_up) end
			return original(unit, ctx, dt, ...)
		end)
	end
	for state_class, fields in pairs(M.GET_UP) do
		obsidian.hook(state_class, "update", function(original, unit, ctx, dt, ...)
			local stats = find(unit)
			if stats and stats.get_up > 1 and type(dt) == "number" then M.hurry(ctx.state, fields, dt, stats.get_up) end
			return original(unit, ctx, dt, ...)
		end)
	end
end

return M
