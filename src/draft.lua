-- A row of cards for one player: rarity first, then an upgrade of that rarity, the ones already held
-- rules.HELD_WEIGHT times as likely. No upgrade at its limit,
-- none the player can't use, and none twice in a row. And the row of stratagems some levels add.
local rules = obsidian.module("src/rules")
local upgrades = obsidian.module("src/upgrades")
local evolve = obsidian.module("src/evolve")

local M = {}

-- The weight of each rarity at a level.
function M.weights(level)
	local out = {}
	for _, r in ipairs(rules.RARITIES) do
		local w = r.weight + r.per_level * (level - 1)
		if r.id == "common" then w = math.max(w, rules.RARITY_FLOOR) end
		out[r.id] = math.max(w, 0)
	end
	return out
end

-- Evolutions never come from the pool, and halves an evolution used up (absorbed) never again.
local function open(u, owned, taken, allowed, absorbed)
	return not u.evolves and not (absorbed and absorbed[u.id]) and not taken[u.id] and (u.max == nil or (owned[u.id] or 0) < u.max)
		and (not allowed or allowed(u))
end

-- owned: { [id] = stacks } for this player. rng: src/rng. allowed(upgrade): false for one this player
-- can't use. absorbed: { [id] = stacks } of the halves evolutions used up (src/evolve.lua), or nil.
-- Answers a list of upgrades. A full row (more than one card) offers an evolution the player is ready
-- for with rules.EVOLUTION_CHANCE, in place of one of its cards: one a row at the most. A banish's one
-- card never brings one.
function M.roll(owned, level, rng, count, allowed, absorbed)
	local row = M.roll_pool(owned, level, rng, count, allowed, absorbed)
	if (count or rules.CARDS) > 1 and #row > 1 then
		local ready = evolve.offers(owned, absorbed, allowed)
		if #ready > 0 and rng:random() < rules.EVOLUTION_CHANCE then
			row[rng:random(1, #row)] = ready[rng:random(1, #ready)]
		end
	end
	return row
end

function M.roll_pool(owned, level, rng, count, allowed, absorbed)
	count = count or rules.CARDS
	local weights = M.weights(level)
	local row, taken = {}, {}
	for _ = 1, count do
		-- Only rarities that still have something to offer.
		local rarities = {}
		for _, r in ipairs(rules.RARITIES) do
			for _, u in ipairs(upgrades.list) do
				if u.rarity == r.id and open(u, owned, taken, allowed, absorbed) then rarities[#rarities + 1] = r break end
			end
		end
		local rarity = rng:pick(rarities, function(r) return weights[r.id] end)
		local pick
		if rarity then
			local pool = {}
			for _, u in ipairs(upgrades.list) do
				if u.rarity == rarity.id and open(u, owned, taken, allowed, absorbed) then pool[#pool + 1] = u end
			end
			pick = rng:pick(pool, function(u) return (owned[u.id] or 0) > 0 and rules.HELD_WEIGHT or 1 end)
		end
		pick = pick or (not taken[upgrades.fallback.id] and upgrades.fallback) or nil
		if not pick then break end
		taken[pick.id] = true
		row[#row + 1] = pick
	end
	return row
end

-- Whether a level offers stratagems to a player who has `have` of them.
function M.offers_stratagems(level, have)
	return level % rules.STRATAGEM_EVERY == 0 and have < rules.STRATAGEM_LIMIT
end

-- The category a stratagem level offers: rules.STRATAGEM_CYCLE in order, round and round, from the first
-- stratagem level.
function M.stratagem_kind(level)
	local turn = math.floor(level / rules.STRATAGEM_EVERY)
	if turn < 1 then return nil end
	return rules.STRATAGEM_CYCLE[(turn - 1) % #rules.STRATAGEM_CYCLE + 1]
end

-- `count` different stratagems out of a pool ({ id, kind, ... }), all of `kind` when the pool has
-- `count` of them, or else of any kind. A player can be offered one they already have. must: ids of
-- which the row holds at least one when the pool has any (M.ANTI_TANK on the first stratagem pick).
function M.roll_stratagems(pool, rng, count, kind, must)
	local row = M.roll_any(pool, rng, count, kind)
	if not must or #row == 0 then return row end
	local wanted = {}
	for _, id in ipairs(must) do wanted[id] = true end
	for _, s in ipairs(row) do
		if wanted[s.id] then return row end
	end
	local options = {}
	for _, s in ipairs(pool) do
		if wanted[s.id] then options[#options + 1] = s end
	end
	if #options == 0 then return row end
	row[rng:random(1, #row)] = options[rng:random(1, #options)]
	return row
end

-- The support weapons the game marks anti-tank at their base level (LoadoutSettings attributes
-- attr_spec_anti_tank), each of which beats a Tank's 1000 front armor: the Recoilless Rifle (3000
-- power, through armor), the LAW (2800) and the Satchel Charge (2600). The Missile Launcher is marked
-- only at Mk3 (600 at its base, 1700 upgraded), so it's left out.
M.ANTI_TANK = { "stratagem_recoilless", "stratagem_law", "stratagem_satchelcharge" }

-- Whether a stratagem pick at `level` is the run's first, which offers M.ANTI_TANK.
function M.first_stratagem_pick(level)
	return level == rules.STRATAGEM_EVERY
end

function M.roll_any(pool, rng, count, kind)
	local left, row = {}, {}
	if kind then
		for _, s in ipairs(pool) do
			if s.kind == kind then left[#left + 1] = s end
		end
	end
	if #left < count then
		left = {}
		for i, s in ipairs(pool) do left[i] = s end
	end
	for _ = 1, math.min(count, #left) do
		row[#row + 1] = table.remove(left, rng:random(1, #left))
	end
	return row
end

return M
