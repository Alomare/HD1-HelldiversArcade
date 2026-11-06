-- The mouse on the level-up cards and the end-of-run summary: what a point in the design space is over,
-- and what a frame's mouse does to a player's choice. Only the first local player uses the mouse
-- (src/run.lua). Plain tables, so it runs without the game.
local M = {}

function M.inside(r, x, y)
	return r ~= nil and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

-- On the cards' screen: "card", "strat" or "tool" (1 reroll, 2 banish) and its index, or nil. spot:
-- cards.layout's for the player; tools: the prompts' rects (cards.glyph_rects).
function M.over(spot, tools, x, y)
	for i, r in ipairs(spot.cards or {}) do
		if M.inside(r, x, y) then return "card", i end
	end
	for i, r in ipairs(spot.strats or {}) do
		if M.inside(r, x, y) then return "strat", i end
	end
	for i, r in ipairs(tools or {}) do
		if M.inside(r, x, y) then return "tool", i end
	end
	return nil
end

-- What a frame's mouse asks of a player's choice p ({ cursor, strat_cursor, focus, strats, mouse_card }):
-- kind and i from M.over, m: { moved, click }. Moving over a card or a stratagem focuses it, and a
-- click picks it. A click on a prompt answers "reroll" or "banish": a banish acts on the card last under
-- the mouse, which takes the focus. Answers what to do: nil, "pick_card", "pick_strat", "reroll" or
-- "banish".
function M.step(p, kind, i, m)
	if not (kind and m and (m.moved or m.click)) then return nil end
	if kind == "card" then
		p.cursor, p.mouse_card = i, i
		if p.strats then p.focus = "cards" end
		return m.click and "pick_card" or nil
	elseif kind == "strat" then
		p.strat_cursor = i
		if p.strats then p.focus = "strats" end
		return m.click and "pick_strat" or nil
	elseif kind == "tool" and m.click then
		if i == 1 then return "reroll" end
		if p.mouse_card then p.cursor = p.mouse_card end
		if p.strats then p.focus = "cards" end
		return "banish"
	end
	return nil
end

return M
