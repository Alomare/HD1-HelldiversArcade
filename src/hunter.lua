-- Tank Hunter (src/upgrades.lua): a hit of this machine's player on a tier 4 enemy or a boss, by the
-- director's tiers (src/director.lua, tier 4 and up), deals the player's tank_hunter share of its
-- damage once more, through armor, as Obsidian API's combat.on_hit hears it. Hooking every command the
-- game queues would cost every hit of every unit; this costs one look per hit a local player lands.
--
-- The extra hit names the player as both owner and attacker, as every hit the mod adds does, so hits
-- with the player's own body as the attacker don't count and the bonus never feeds itself. Melee and
-- the other upgrades' extra hits (burns, Kinetic Battery, Strike Back) are left out with them.
local director = obsidian.module("src/director")
local bosses = obsidian.module("src/bosses")
local summary = obsidian.module("src/summary")

local M = {}

-- A tier 4 hit of 1 damage or less isn't worth a command.
M.MIN_BONUS = 1

local function g(name) return rawget(_G, name) end

-- Whether an enemy of `path` (its unit_path) is a tank: tier 4 and up of the director, or a boss.
-- enemy_of(path): Obsidian API's catalog entry ({ key, boss }), or nil.
function M.is_tank(path, enemy_of)
	if type(path) ~= "string" then return false end
	if bosses.is_boss_path(path) then return true end
	local enemy = enemy_of and enemy_of(path)
	if not enemy then return false end
	if enemy.boss then return true end
	local tier = director.tier_of(enemy.key)
	return tier ~= nil and tier >= 4
end

-- The extra damage of a hit of `damage` from a player with share `share`, or 0.
function M.bonus(share, damage, self_hit)
	if self_hit or not (share and share > 0) or type(damage) ~= "number" then return 0 end
	local extra = damage * share
	if extra < M.MIN_BONUS then return 0 end
	return math.min(extra, 20000)
end

-- find(unit): the stats of the local player with that unit, or nil outside a run.
function M.install(api, find)
	if not (api.combat and api.combat.on_hit and api.enemies and api.enemies.damage) then return false end
	local tanks = setmetatable({}, { __mode = "k" })
	local function enemy_of(path) return api.catalog.enemy(path) end
	api.combat.on_hit(function(victim, hit)
		local stats = find(hit.owner_unit)
		local share = stats and stats.tank_hunter
		if not (share and share > 0) then return end
		local self_hit = hit.attacker_unit ~= nil and hit.attacker_unit == hit.owner_unit
		local extra = M.bonus(share, hit.damage, self_hit)
		if extra <= 0 then return end
		local tank = tanks[victim]
		local ok_alive, alive = pcall(g("Unit").alive, victim)
		if tank == nil and not (ok_alive and alive) then return end
		if tank == nil then
			-- A destroyed unit's get_data takes the game down, past the pcall (src/grenades.lua).
			local ok, path = pcall(g("Unit").get_data, victim, "unit_path")
			tank = ok and M.is_tank(path, enemy_of) or false
			tanks[victim] = tank
		end
		if tank then
			-- The run's summary counts it as Tank Hunter's, not as melee.
			summary.mark_hit(victim, "tank_hunter", hit.owner_unit)
			api.enemies.damage(victim, extra, nil, { through_armor = true })
		end
	end)
	return true
end

return M
