-- The game's own look for a kit, from the images its HUD draws with (hud/hud, in every mission):
-- basicbox_01, a dark grey gradient that light falls on from the top; hud_icon_color_gradient_01, a bar
-- that fades out to the right and takes a tint, as the players' name bars do; wing_01, the chrome wings
-- either side of a menu's title. Black outlines round everything. Where the HUD's images aren't loaded,
-- flat shapes of the same colors stand in.
local M = {}

M.BLACK, M.FRAME, M.WHITE, M.TEXT, M.GREY = "#000000", "#5d5c56", "#ffffff", "#d4d2cb", "#8f8d86"
M.GOLD = "#ffc433"

-- The box's gradient without its own one-pixel edges.
local BOX_UV = { 0.25, 0.01, 0.75, 0.99 }

-- A panel: a black outline `thick` wide outside the box, then a thinner grey frame inside it.
-- opts: line (the outline's color), thick, frame (false for none), tint. The box's image is on the
-- HUD's gui, which draws over a kit's shapes and its own art on the same layer in most missions, but
-- under them in some (a city on the Cyborg front): so the outline is four strips around the box, never
-- under it, and this leaves the kit a layer up, for what goes on the box.
function M.box(kit, x, y, w, h, opts)
	opts = opts or {}
	local t = opts.thick or 5
	local z = kit:layer()
	if t > 0 then
		local c = opts.line or M.BLACK
		kit:rect(x - t, y - t, w + 2 * t, t, c)
		kit:rect(x - t, y + h, w + 2 * t, t, c)
		kit:rect(x - t, y, t, h, c)
		kit:rect(x + w, y, t, h, c)
	end
	if not kit:icon("basicbox_01", x, y, w, h, opts.tint or M.WHITE, BOX_UV) then
		kit:rect(x, y, w, h, "#1e1e1c")
		kit:rect(x, y + h * 0.45, w, h * 0.55, "#2b2b28")
	end
	kit:layer(z + 1)
	if opts.frame ~= false then
		local f, c = 2, opts.frame or M.FRAME
		kit:rect(x, y, w, f, c)
		kit:rect(x, y + h - f, w, f, c)
		kit:rect(x, y, f, h, c)
		kit:rect(x + w - f, y, f, h, c)
	end
end

-- A panel as the HUD's player cards are drawn (Hud.draw_panel, Hud.draw_hud_background): basicbox_01
-- tinted white at 150 of 255, with no outline of black. The image's own edge pixels make the frame, a
-- strip 2 units wide on each side and 1 unit tall at the top and bottom, all outside the box. Through
-- the same parts of the image, so a panel of the HUD card's size lines up with the card edge for edge.
-- opts: unit (how many of the kit's units make one of the HUD's, for the frame), tint. Leaves the kit a
-- layer up, as M.box does.
M.PANEL_TINT = "#ffffff96"
local EDGE_U, EDGE_V = 2 / 16, 1 / 256

-- The five parts of a panel: { x, y, w, h, uv }, the box itself last. The game's sides reach down
-- over the bottom strip's ends, so at the panel's tint the two bottom corners are drawn twice and show
-- darker. Here the sides stop at the box and the top and bottom strips take the corners.
function M.panel_parts(x, y, w, h, unit)
	local sx, sy = 2 * (unit or 1), unit or 1
	local U, V = EDGE_U, EDGE_V
	return {
		{ x - sx, y, sx, h, { 0, 2 * V, U, 1 - 2 * V } },
		{ x - sx, y + h, w + 2 * sx, sy, { U, 1 - V, 1 - U, 1 } },
		{ x + w, y, sx, h, { 1 - U, 2 * V, 1, 1 - 2 * V } },
		{ x - sx, y - sy, w + 2 * sx, sy, { U, 0, 1 - U, V } },
		{ x, y, w, h, { 2 * U, 2 * V, 1 - 2 * U, 1 - 2 * V } },
	}
end

function M.panel(kit, x, y, w, h, opts)
	opts = opts or {}
	local tint = opts.tint or M.PANEL_TINT
	local z = kit:layer()
	local parts = M.panel_parts(x, y, w, h, opts.unit)
	local box = parts[#parts]
	if kit:icon("basicbox_01", box[1], box[2], box[3], box[4], tint, box[5]) then
		for i = 1, #parts - 1 do
			local p = parts[i]
			kit:icon("basicbox_01", p[1], p[2], p[3], p[4], tint, p[5])
		end
	else
		-- Without the HUD's images: a flat dark box and a grey frame of the same size.
		kit:rect(x, y, w, h, "#1e1e1c99")
		for i = 1, #parts - 1 do
			local p = parts[i]
			kit:rect(p[1], p[2], p[3], p[4], M.FRAME)
		end
	end
	kit:layer(z + 1)
end

-- A bar that fades out towards `to` ("right" by default, or "left").
function M.bar(kit, x, y, w, h, c, to)
	local uv = to == "left" and { 0.99, 0, 0, 1 } or { 0, 0, 0.99, 1 }
	if not kit:icon("hud_icon_color_gradient_01", x, y, w, h, c, uv) then
		kit:rect(x, y, w * 0.6, h, c)
	end
end

-- A bar that fades out both ways from its middle.
function M.rule(kit, cx, y, w, h, c)
	M.bar(kit, cx - w / 2, y, w / 2, h, c, "left")
	M.bar(kit, cx, y, w / 2, h, c)
end

-- Text with the game's hard drop shadow.
function M.text(kit, s, x, y, opts)
	local shadow = {}
	for k, v in pairs(opts) do shadow[k] = v end
	shadow.color = "#000000c0"
	local d = math.max(2, math.floor((opts.size or 20) / 14))
	kit:text(s, x + d, y - d, shadow)
	kit:text(s, x, y, opts)
end

-- Chrome wings either side of a title `gap` from its middle, `h` tall.
function M.wings(kit, cx, y, gap, h, c)
	local w = h * 2
	if not kit:icon("wing_01", cx - gap - w, y, w, h, c or M.WHITE) then return false end
	kit:icon("wing_01", cx + gap, y, w, h, c or M.WHITE, { 1, 0, 0, 1 })
	return true
end

return M
