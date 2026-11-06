-- Rerolls and banishes, one player's: how many are left and which upgrades are banished. A reroll draws
-- the row again; a banish takes one card out of the player's draft for the rest of the run and draws one
-- instead. Every vacuum adds a reroll and every objective done a banish, for every player (src/run.lua
-- counts them). Runs without the game.
local rules = obsidian.module("src/rules")

local M = {}

function M.new() return { rerolls = 0, banishes = 0, banned = {} } end

-- `kind`: "rerolls" or "banishes".
function M.add(b, kind, n)
	b[kind] = math.max(0, (b[kind] or 0) + (n or 1))
end

-- How many each player gains from `count` new events: vacuums (rerolls) or objectives (banishes).
function M.gain(kind, count)
	return (kind == "rerolls" and rules.REROLL_PER_VACUUM or rules.BANISH_PER_OBJECTIVE) * math.max(0, count)
end

-- What a player may be offered: `base` (draft.roll's own filter, or nil) and nothing banished.
function M.allowed(b, base)
	return function(u)
		if b.banned[u.id] then return false end
		return not base or base(u)
	end
end

function M.can_reroll(b) return b.rerolls > 0 end

-- Whether card i of the row can go: a banish left, a card there, and not the fallback (the card that
-- comes up when nothing else can, so it never runs out).
function M.can_banish(b, row, i, fallback_id)
	local u = row and row[i]
	return b.banishes > 0 and u ~= nil and u.id ~= fallback_id
end

-- A reroll: one used and a new row from roll(), or nil with none left.
function M.reroll(b, roll)
	if not M.can_reroll(b) then return nil end
	b.rerolls = b.rerolls - 1
	return roll()
end

-- A banish of card i: one used, the upgrade banished, and in the card's place the first of roll(filter), a roll
-- of one card that leaves out the rest of the row. With nothing new to draw the card leaves the row,
-- unless it was the last. Answers the card banished and the one drawn instead (nil when it left), or nil
-- when nothing happened.
function M.banish(b, row, i, roll, fallback_id)
	if not M.can_banish(b, row, i, fallback_id) then return nil end
	local gone = row[i]
	local others = {}
	for k, u in ipairs(row) do
		if k ~= i then others[u.id] = true end
	end
	b.banned[gone.id] = true
	local new = roll(function(u) return not others[u.id] and not b.banned[u.id] end)
	local pick = new and new[1]
	if pick and (others[pick.id] or b.banned[pick.id]) then pick = nil end
	if not pick and #row <= 1 then
		b.banned[gone.id] = nil
		return nil
	end
	b.banishes = b.banishes - 1
	if pick then row[i] = pick else table.remove(row, i) end
	return gone, pick
end

return M
