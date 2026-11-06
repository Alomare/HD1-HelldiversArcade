-- Evolutions (src/upgrades.lua's EVOLUTIONS): which a player is ready for, which halves a card pairs
-- with, the map panel's link markers, and the take that uses both halves up. Plain tables, so it runs
-- without the game.
--
-- owned: { [id] = stacks } of the upgrades in a player's build. absorbed: { [id] = stacks } of the halves
-- that evolutions used up: they are out of the build and never offered again, and the evolution applies
-- them at these stacks.
local upgrades = obsidian.module("src/upgrades")

local M = {}

local function held(owned, id) return (owned[id] or 0) > 0 end

local function at_max(owned, id)
	local u = upgrades.by_id[id]
	return u ~= nil and u.max ~= nil and (owned[id] or 0) >= u.max
end

-- Whether evolution e can still come about: not held, and neither half used up.
function M.open(e, owned, absorbed)
	absorbed = absorbed or {}
	return not held(owned, e.id) and not absorbed[e.evolves[1]] and not absorbed[e.evolves[2]]
end

-- Whether a player can be offered evolution e: both halves held, the first at its max stacks.
function M.ready(e, owned, absorbed)
	return M.open(e, owned, absorbed) and at_max(owned, e.evolves[1]) and held(owned, e.evolves[2])
end

-- The evolutions a player can be offered now, that allowed(e) lets through (nil for all).
function M.offers(owned, absorbed, allowed)
	local out = {}
	for _, e in ipairs(upgrades.EVOLUTIONS) do
		if M.ready(e, owned, absorbed) and (not allowed or allowed(e)) then out[#out + 1] = e end
	end
	return out
end

-- The small icons in a card's corner: for half of a pair that can still come about, the partner of
-- each such pair; for an evolution, its two halves. A list of upgrades.
function M.hints(u, owned, absorbed)
	if u.evolves then return { upgrades.by_id[u.evolves[1]], upgrades.by_id[u.evolves[2]] } end
	local out = {}
	for _, e in ipairs(upgrades.EVOLUTIONS) do
		if M.open(e, owned or {}, absorbed) then
			local a, b = e.evolves[1], e.evolves[2]
			local partner = (u.id == a and b) or (u.id == b and a) or nil
			if partner and upgrades.by_id[partner] then out[#out + 1] = upgrades.by_id[partner] end
		end
	end
	return out
end

-- The map panel's markers: once a player holds one half at max and the other at any stack, both
-- badges get the pair's link color. { [id] = { colors } }, in the order of EVOLUTIONS.
function M.links(owned, absorbed)
	local out = {}
	for _, e in ipairs(upgrades.EVOLUTIONS) do
		local a, b = e.evolves[1], e.evolves[2]
		if M.open(e, owned, absorbed) and held(owned, a) and held(owned, b) and (at_max(owned, a) or at_max(owned, b)) then
			for _, id in ipairs({ a, b }) do
				out[id] = out[id] or {}
				table.insert(out[id], e.link)
			end
		end
	end
	return out
end

-- Taking evolution e: both halves leave the build into absorbed, at their stacks, and e takes their place.
function M.take(owned, absorbed, e)
	for _, id in ipairs(e.evolves) do
		absorbed[id] = owned[id] or absorbed[id] or 0
		owned[id] = nil
	end
	owned[e.id] = 1
end

-- An evolution gone again (the debug page): its halves come back at the stacks they had.
function M.undo(owned, absorbed, e)
	owned[e.id] = nil
	for _, id in ipairs(e.evolves) do
		if absorbed[id] then
			if absorbed[id] > 0 then owned[id] = absorbed[id] end
			absorbed[id] = nil
		end
	end
end

-- The debug page: the halves set up for e, the first at its max and the second at what's held, or 1.
function M.set_up(owned, e)
	local a, b = upgrades.by_id[e.evolves[1]], upgrades.by_id[e.evolves[2]]
	owned[a.id] = a.max or 1
	owned[b.id] = math.max(owned[b.id] or 0, 1)
end

return M
