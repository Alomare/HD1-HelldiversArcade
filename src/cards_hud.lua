-- What the run shows over each of this machine's players' HUD cards: their health (current and
-- maximum) and armor on a panel just above the card's left end, and, while their map is open, the
-- upgrades they have, rising with the map. Both are drawn like the card (native.panel), so their edges
-- line up with the card's.
--
-- The game draws the cards along the bottom of the screen in the HUD's 1280x720 space, y up, each one
-- growing upward from Hud:get_player_hud_pos(slot) to the card's current_height (Hud.draw_hud); opening
-- the map is the card's "map" state, and its height grows to make room. The HUD's gui puts a point on
-- the screen at pos * ui_scale + resolution_offset (HdGui.update_offsets), in pixels from the bottom
-- left, which is how obsidian.ui's kit:point takes them.
--
-- Over a card in the "normal" or "custom" state the game lists the stratagems that are cooling down
-- (Hud.draw_stratagem_cooldown_list): a row of icons from the card's left edge, starting at
-- current_height + start_position.y, each stratagem_icon.size tall (hud_settings_default: 0, -2 and
-- 32). In a stratagem's last second of cooldown the icon hops up and fades: the icon's bottom rises by
-- 3 * size * t * (1 - t) - size * (1 - t), at most a third of the icon's height. The stats go above the
-- top of that hop while the list shows, and just over the card when it doesn't.
local cards = obsidian.module("src/cards")

local M = { seen = {} }

local DEAD = { dead = true, countdown = true, wait_for_spawn = true }
-- A card not drawn for this long (the HUD hidden, a menu) shows nothing.
M.STALE = 0.25
M.GAP = 6 -- HUD units between the card's top and what the map shows over it: the counts' strip, or the upgrades' panel
M.STAT_GAP = 3 -- and the stats' panel, whose frame then clears the card's by a unit
M.STAT_SIZE = 15 -- HUD units: the numbers' height
M.COOLDOWN = { y = -2, size = 32 }
-- How far above the card's top the cooldown icons reach, at most (HUD units).
M.COOLDOWN_TOP = M.COOLDOWN.y + M.COOLDOWN.size * (1 + 1 / 3)

-- Whether the game draws a cooldown list for this inventory: a stratagem cooling down that has a
-- cooldown and uses left (Hud.draw_stratagem_cooldown_list's own tests).
function M.cooldowns_shown(inventory)
	local list = type(inventory) == "table" and inventory.stratagems
	if type(list) ~= "table" then return false end
	for _, s in ipairs(list) do
		local info = type(s) == "table" and s.loadout_info
		if type(info) == "table" and (tonumber(s.cooldown_timer) or 0) > 0 and (tonumber(info.cooldown_time) or 0) > 0
			and not (tonumber(s.uses_left) and s.uses_left <= 0) then
			return true
		end
	end
	return false
end

-- How far above a card's top, in HUD units, the stats' panel sits: over the cooldown list when it shows.
function M.stat_lift(cooling)
	return M.STAT_GAP + (cooling and M.COOLDOWN_TOP or 0)
end

-- Where a card is, in screen pixels: { unit, left, bottom, top, width, scale, state, open, cooling, at }.
function M.record(hud, unit, slot, cooling)
	local info = hud.hud_info and hud.hud_info[slot]
	local gui = hud.hd_gui
	if not (info and gui and unit) then return end
	local ok, pos = pcall(hud.get_player_hud_pos, hud, slot)
	if not ok or not pos then return end
	local s = gui.ui_scale or 1
	local ox, oy = gui.resolution_offset_x or 0, gui.resolution_offset_y or 0
	local x, y = pos.x, pos.y
	M.seen[unit] = {
		unit = unit, left = x * s + ox, bottom = y * s + oy, top = (y + (info.current_height or 0)) * s + oy,
		width = (info.width or 248) * s, scale = s, state = info.state, at = os.clock(),
		cooling = cooling == true and (info.state == "normal" or info.state == "custom"),
		-- How far the map has opened: the card's height on its way to the map's.
		open = info.state == "map" and info.target_height and info.target_height > 0
			and math.min((info.current_height or 0) / info.target_height, 1) or 0,
	}
end

-- Set while the game draws one card, by the card's cooldown list.
local cooling

function M.install()
	obsidian.hook("Hud", "draw_hud", function(original, self, dt, unit, name, slot, ...)
		cooling = false
		local r = { original(self, dt, unit, name, slot, ...) }
		pcall(M.record, self, unit, slot, cooling)
		return unpack(r)
	end)
	obsidian.hook("Hud", "draw_stratagem_cooldown_list", function(original, self, info, width, height, inventory, ...)
		local ok, shown = pcall(M.cooldowns_shown, inventory)
		if ok and shown then cooling = true end
		return original(self, info, width, height, inventory, ...)
	end)
end

function M.clear() M.seen = {} end

-- Where a card's panels go, in the kit's units: { x, y (the stats' bottom), map_y (the upgrades'
-- bottom), w, unit (the kit's units in one of the HUD's), size (the numbers' height) }.
function M.spot(kit, c)
	local x, top = kit:point(c.left, c.top)
	local right = kit:point(c.left + c.width, c.top)
	local x1 = kit:point(c.left + c.scale, c.top)
	local u = x1 - x
	return { x = x, w = right - x, unit = u, size = M.STAT_SIZE * u,
		y = top + M.stat_lift(c.cooling) * u, map_y = top + M.GAP * u }
end

-- The rerolls and banishes' strip, under the upgrades: its bottom GAP over the card's top, where it
-- stays however many upgrades there are, and the upgrades' panel TOOLS_GAP over the strip. The text
-- is TOOLS_SIZE HUD units tall (11 before, too small to read): a little over the stats' 15, 24 pixels
-- on a 1080p screen. The strip is 1.8 times that, 28.8 units.
M.TOOLS_SIZE = 16
M.TOOLS_GAP = 4

-- While the map is open, where the strip and the upgrades' panel go, in the kit's units, from M.spot:
-- { tools (the strip's bottom, or nil with no strip), owned (the upgrades' bottom) }.
function M.map_spots(s, tools)
	if not tools then return { owned = s.map_y } end
	local h = cards.tools_height(M.TOOLS_SIZE * s.unit)
	return { tools = s.map_y, owned = s.map_y + h + M.TOOLS_GAP * s.unit }
end

-- players: { { unit, owned, health, max_health, armor, rerolls, banishes } } for this machine's players,
-- the dead with no unit.
function M.draw(kit, players)
	local now = os.clock()
	for _, p in ipairs(players) do
		local c = p.unit and M.seen[p.unit]
		if c and now - c.at <= M.STALE and not DEAD[c.state] then
			local s = M.spot(kit, c)
			if c.state == "map" then
				local at = M.map_spots(s, p.rerolls ~= nil or p.banishes ~= nil)
				if at.tools then
					cards.tools_strip(kit, s.x, at.tools, s.w, p.rerolls or 0, p.banishes or 0, M.TOOLS_SIZE * s.unit, s.unit)
				end
				cards.owned_panel(kit, s.x, at.owned, s.w, p.owned, obsidian.module("src/upgrades"), 1, s.unit)
			elseif p.max_health or p.armor then
				kit:layer(cards.LAYER - 5)
				cards.stat_line(kit, s.x, s.y, s.size, p.health, p.max_health, p.armor, s.unit)
			end
		end
	end
end

return M
