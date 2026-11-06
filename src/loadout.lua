-- The loadout screen of a Survivors drop has fewer stratagem slots than the game's, and the game places
-- them from the left with a number local to MenuScreenLoadout.draw_menu: the first at x 10, each the
-- icon's width plus 10 further on (menu_screen_loadout's bytecode). While that panel draws, the slots'
-- own pieces (their icons, their selection boxes and the mouse's areas, all known by their size) move
-- together, so the row sits in the middle.
local M = {}

local BOX = 58 -- the selection box's size, in the game's code
M.FIRST = 10 -- x of the first slot
M.GAP = 10 -- between two slots

local function g(name) return rawget(_G, name) end

-- How far the slots move to the middle of a panel `width` wide: `count` slots of `icon` width.
function M.offset(width, count, icon)
	local row = count * icon + (count - 1) * M.GAP
	return (width - row) / 2 - M.FIRST
end

-- slots(): how many slots the screen is showing, while it's a Survivors drop's; nil otherwise. A wrap,
-- since the screen is on the ship: slots() is nil until the content sets the row, and nil again once
-- the content ends and the row goes back.
function M.install(slots)
	obsidian.wrap("MenuScreenLoadout", "draw_menu", function(original, self, a1, gui, a3, a4, width, ...)
		local icon = self.stratagem_icon_size
		local count = slots()
		if not count or type(gui) ~= "table" or type(width) ~= "number" or type(icon) ~= "table" then
			return original(self, a1, gui, a3, a4, width, ...)
		end
		local dx = M.offset(width, count, icon[1])
		local function moved(pos) return g("Vector3")(pos.x + dx, pos.y, pos.z) end
		local function is_box(size) return size and size.x == BOX and size.y == BOX end

		local base = g("MenuScreenBase")
		local real_icon, real_hit = base.draw_stratagem_icon, base.is_box_selected_by_cursor
		base.draw_stratagem_icon = function(s, x, to, item, upgrade, pos, size, ...)
			if size and size.x == icon[1] and size.y == icon[2] then pos = moved(pos) end
			return real_icon(s, x, to, item, upgrade, pos, size, ...)
		end
		base.is_box_selected_by_cursor = function(s, to, pos, size, ...)
			if is_box(size) then pos = moved(pos) end
			return real_hit(s, to, pos, size, ...)
		end
		local real_image, real_rect = gui.image, gui.rect
		gui.image = function(s, texture, pos, size, ...)
			if is_box(size) then pos = moved(pos) end
			return real_image(s, texture, pos, size, ...)
		end
		gui.rect = function(s, pos, size, ...)
			if is_box(size) then pos = moved(pos) end
			return real_rect(s, pos, size, ...)
		end

		local ok, err = pcall(original, self, a1, gui, a3, a4, width, ...)
		base.draw_stratagem_icon, base.is_box_selected_by_cursor = real_icon, real_hit
		gui.image, gui.rect = nil, nil
		if not ok then error(err, 0) end
	end)
end

return M
