-- The Shield Generator Pack upgrade and the backpack are one pool: the player's points, the backpack's
-- points and both their regeneration. The backpack sets the shield with a command, so a hook adds the
-- upgrade to what it asks for, and what's left when the backpack goes comes back to the upgrade alone.
local api = obsidian.import("obsidian.api")

local M = { bonus = {}, pack = {}, applied = {} }

local REGEN_DELAY = 5
local OWN = "survivors"

local function merged(bonus, pack)
	return {
		from = OWN,
		shield = bonus + (pack and pack.shield or 0),
		shield_regen = bonus / 10 + (pack and pack.shield_regen or 0),
		shield_regen_delay = pack and pack.shield_regen_delay and math.min(pack.shield_regen_delay, REGEN_DELAY) or REGEN_DELAY,
		armor_min = pack and pack.armor_min, armor_max = pack and pack.armor_max,
	}
end

function M.install()
	obsidian.hook("ShieldComponent", "command_master", function(original, self, unit, ctx, command, data)
		if command == "set_shield_info" and data and data.from ~= OWN then
			local inv = api.game.master(unit, "inventory")
			M.pack[unit] = {
				shield = data.shield, shield_regen = data.shield_regen, shield_regen_delay = data.shield_regen_delay,
				armor_min = data.armor_min, armor_max = data.armor_max, backpack = inv and inv.backpack,
			}
			local bonus = M.bonus[unit] or 0
			if bonus > 0 then data = merged(bonus, M.pack[unit]) end
		end
		return original(self, unit, ctx, command, data)
	end)
end

-- Every frame for each of this machine's players.
function M.sync(unit, bonus)
	M.bonus[unit] = bonus
	local pack = M.pack[unit]
	local inv = api.game.master(unit, "inventory")
	if pack and inv and inv.backpack ~= pack.backpack then
		M.pack[unit] = nil
		pack = nil
	end
	local state = api.game.master(unit, "shield")
	if not state then return end
	if bonus <= 0 then
		-- The upgrade isn't taken: the game's own shield, as the game has it.
		M.applied[unit] = nil
		return
	end
	local total = bonus + (pack and pack.shield or 0)
	local was = M.applied[unit]
	if was ~= total then
		M.applied[unit] = total
		api.game.command(unit, "shield", "set_shield_info", merged(bonus, pack))
		api.game.command(unit, "shield", "set_shieldpoints", math.min((state.shieldpoints or 0) + (total - (was or 0)), total))
	end
	if not state.shield_activated then api.game.command(unit, "shield", "set_shield_activated", true) end
end

function M.clear()
	M.bonus, M.pack, M.applied = {}, {}, {}
end

return M
