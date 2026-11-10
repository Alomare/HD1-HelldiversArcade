-- The mod's own images (tools/build_art.py): white shapes in one atlas that the game tints as it draws
-- them. They ship in the boot bundle, so they draw in every state. Without them (an old loader, or a
-- deploy that left the files out) the cards fall back to the game's stratagem icons.
local atlas = obsidian.module("src/atlas")

local M = { ready = false }

function M.load()
	local ui = obsidian.ui
	M.ready = ui ~= nil and ui.art ~= nil and ui.art(atlas.material, { path = atlas.path }) == true
	return M.ready
end

function M.has(name)
	return M.ready and atlas.images[name] ~= nil
end

-- An image stretched over a box. false when there's no such image.
function M.draw(kit, name, x, y, w, h, c)
	local r = M.ready and atlas.images[name]
	if not r then return false end
	local u0, v0 = r[1] / atlas.w, r[2] / atlas.h
	return kit:art(atlas.material, x, y, w, h, c, { u0, v0, u0 + r[3] / atlas.w, v0 + r[4] / atlas.h })
end

-- An atlas image for another mod to draw (Better HUD's status_effect and elite_mark): the material and
-- the image's uv, or nil when there's no such image.
function M.image(name)
	local r = M.ready and atlas.images[name]
	if not r then return nil end
	local u0, v0 = r[1] / atlas.w, r[2] / atlas.h
	return { art = atlas.material, uv = { u0, v0, u0 + r[3] / atlas.w, v0 + r[4] / atlas.h } }
end

-- An upgrade's icon for another mod to draw: its atlas image, or else the game's stratagem icon the card
-- falls back to.
function M.spec(u)
	return M.image("icon_" .. u.id) or { icon = u.icon }
end

-- A square image centred on a point.
function M.center(kit, name, cx, cy, size, c)
	return M.draw(kit, name, cx - size / 2, cy - size / 2, size, size, c)
end

-- The frame of a rarity's badge: a circle for common, a square for rare and perk, a diamond for legendary, a hexagon for evolution. Each
-- has its image, the size of its inside against its edge (a diamond's edges run at 45 degrees, so it
-- needs less), the icon's size against r, and its own size: a diamond is a square turned to fit the
-- same box, so it's drawn bigger to look as big as the others.
M.FRAMES = {
	common = { "frame_circle", 0.9, 1.15, 1 },
	rare = { "frame_square", 0.9, 1.15, 1 },
	perk = { "frame_square", 0.9, 1.15, 1 },
	legendary = { "frame_diamond", 0.86, 1.03, 1.15 },
	-- An evolution: a hexagon, a little bigger than a circle to look as big.
	evolution = { "frame_hex", 0.88, 1.08, 1.1 },
}
M.LARGEST = 1.15

-- How tall a badge of radius r is drawn, at most, whatever its rarity.
function M.badge_height(r)
	return r * 2.13 * M.LARGEST
end

-- An upgrade's badge: its rarity's frame in its color holding its icon, `r` from the centre to the
-- frame's edge.
function M.badge(kit, u, cx, cy, r, color, back, ink)
	local frame = M.FRAMES[u.rarity] or M.FRAMES.common
	if M.has(frame[1]) and M.has("icon_" .. u.id) then
		local size = r * 2.13 * frame[4]
		M.center(kit, frame[1], cx, cy, size, color)
		M.center(kit, frame[1], cx, cy, size * frame[2], back)
		M.center(kit, "icon_" .. u.id, cx, cy, r * frame[3], ink)
		return
	end
	kit:hex(cx, cy, r, color)
	kit:hex(cx, cy, r * 0.91, back, u.icon)
end

return M
