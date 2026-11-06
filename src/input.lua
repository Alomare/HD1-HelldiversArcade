-- Each local player moves through their own cards with their own controller, and the first player
-- with the mouse too. While the cards are up, the mod holds the input, so the game doesn't also read
-- the presses, and keeps holding it until the key that picked a card is let go (rules.INPUT_GRACE at
-- the most): it would otherwise dive. Enter isn't a pick key, because the game opens the chat on it. This follows
-- the in-game menu of Obsidian's loader (loader/src/menu.lua).
local M = { held = false, keys = nil, last = {}, device = nil, grace = 0 }

local IFACE = "survivors_cards"
local KEYS = { left = { "left", "a" }, right = { "right", "d" }, up = { "up", "w" }, down = { "down", "s" }, select = { "e", "space" },
	reroll = { "r" }, banish = { "x" } }
-- A pad's buttons by the name ControllerSettings.pad gives them: Y is "triangle" and X is "square" there.
-- The rest go by their own names. While the cards hold the input, the game doesn't read R (reload) or the
-- pad's Y and X.
local PAD = { reroll = "triangle", banish = "square" }

local function g(name) return rawget(_G, name) end

local function users()
	local out = { g("KEYBOARD_MOUSE_USER_NAME") }
	local pads = g("PadManager")
	for _, u in ipairs(pads and pads.users or {}) do out[#out + 1] = u.name end
	return out
end

local function ensure()
	local im, pads = g("InputManager"), g("PadManager")
	local keyboard = g("KEYBOARD_MOUSE_USER_NAME")
	if im:has_interface(keyboard, IFACE) then return end
	im:create_controller_interface(keyboard, IFACE, {}, {})
	pads:create_rebindable_interface(IFACE, g("ControllerSettings").pad)
end

-- "keyboard" or "pad": what the main player used last, from the game's own setting until they press.
function M.main_device()
	if M.device then return M.device end
	local settings = g("GameSettings")
	local ok, pad = pcall(function() return settings.get_main_pad_number() end)
	return (ok and pad == g("KEYBOARD_MOUSE_PAD_NUMBER")) and "keyboard" or "pad"
end

function M.hold()
	M.grace = 0
	if M.held then
		for _, u in ipairs(users()) do g("InputManager"):take_focus(u, IFACE) end
		return true
	end
	local ok, err = pcall(function()
		ensure()
		for _, u in ipairs(users()) do g("InputManager"):take_focus(u, IFACE) end
	end)
	if not ok then obsidian.log("arcade: could not take input: " .. tostring(err)) return false end
	M.held = true
	return true
end

function M.release_now()
	M.grace = 0
	if not M.held then return end
	M.held = false
	pcall(function()
		for _, u in ipairs(users()) do g("InputManager"):release_focus(u, IFACE) end
	end)
end

-- Whether a key or button that picks a card is still down. Unsure counts as down.
local function pick_held()
	local ok, held = pcall(function()
		local kb = g("Keyboard")
		for _, key in ipairs(KEYS.select) do
			local i = kb.button_index(key)
			if i and kb.button(i) > 0 then return true end
		end
		local m = g("Mouse")
		if m and not M.no_mouse and m.button(m.button_index("left")) > 0 then return true end
		local pads = g("PadManager")
		for i = 1, #(pads and pads.users or {}) do
			local d = pads:get_inputs(IFACE, i)
			if type(d) == "table" and d.select then return true end
		end
		return false
	end)
	return not ok or held
end

-- Lets go once the key or button that picked is up, or after `seconds` of real time at the most
-- (M.update counts them down).
function M.release(seconds)
	if not seconds or seconds <= 0 then return M.release_now() end
	M.grace = seconds
end

function M.update(dt_real)
	if M.grace > 0 then
		M.grace = M.grace - dt_real
		if M.grace <= 0 or not pick_held() then M.release_now() end
	end
end

-- True while the input is held, the cards up or just gone: the chat stays shut.
function M.blocking() return M.held end

local function keyboard()
	local kb = g("Keyboard")
	if not M.keys then
		M.keys = {}
		for name, list in pairs(KEYS) do
			M.keys[name] = {}
			for _, key in ipairs(list) do
				local ok, i = pcall(kb.button_index, key)
				if ok and i then table.insert(M.keys[name], i) end
			end
		end
	end
	local out = {}
	for name, list in pairs(M.keys) do
		for _, i in ipairs(list) do
			if kb.pressed(i) == true then out[name] = true end
		end
	end
	return out
end

-- The mouse: where it is in pixels, whether it moved, and a left click this frame. nil without one.
local function mouse()
	local m = g("Mouse")
	if not m or M.no_mouse then return nil end
	local ok, out = pcall(function()
		M.mouse_ids = M.mouse_ids or { cursor = m.axis_index("cursor"), left = m.button_index("left") }
		local at = m.axis(M.mouse_ids.cursor)
		return { x = at.x, y = at.y, click = m.pressed(M.mouse_ids.left) == true }
	end)
	if not ok then M.no_mouse = true return nil end
	local last = M.mouse_at
	out.moved = last ~= nil and (math.abs(last.x - out.x) + math.abs(last.y - out.y)) > 2
	M.mouse_at = { x = out.x, y = out.y }
	return out
end

-- Presses this frame, for each input: [0] the keyboard and mouse, [1..] the pads by their order in
-- PadManager. [0].mouse is the mouse, when there is one.
function M.read()
	local kb = keyboard()
	local m = mouse()
	kb.mouse = m
	if next(kb) ~= nil and (kb.left or kb.right or kb.up or kb.down or kb.select or kb.reroll or kb.banish or (m and (m.moved or m.click))) then M.device = "keyboard" end
	local out = { [0] = kb }
	local pads = g("PadManager")
	for i = 1, #(pads and pads.users or {}) do
		local ok, d = pcall(pads.get_inputs, pads, IFACE, i)
		local now = {}
		if ok and type(d) == "table" then
			for name in pairs(KEYS) do now[name] = d[PAD[name] or name] and true or nil end
		end
		-- A pad reports what's held, so only a change counts as a press.
		local was = M.last[i] or {}
		local pressed = {}
		for name in pairs(KEYS) do
			pressed[name] = now[name] and not was[name] or nil
			if pressed[name] and i == 1 then M.device = "pad" end
		end
		M.last[i] = now
		out[i] = pressed
	end
	return out
end

-- The game's menu cursor while the keyboard and mouse are in use, none for a pad; the aiming cursor
-- back when the cards are gone.
function M.cursor(mode)
	local cm = g("CursorManager")
	if not cm then return end
	pcall(function()
		if mode == "menu" then
			cm:set_cursor("hud/cursors/menu")
			cm:set_show_cursor(true)
		elseif mode == "hidden" then
			cm:set_show_cursor(false)
		else
			cm:set_cursor("hud/cursors/game")
		end
	end)
end

return M
