-- A small random number generator with its own state, so a test can fix its seed and the mode's draws
-- don't move the game's math.random.
local M = {}
M.__index = M

function M.new(seed)
	local s = math.floor(math.abs(seed or os.time())) % 2147483646 + 1
	return setmetatable({ s = s }, M)
end

-- Park and Miller's minimal standard: whole numbers stay exact in a double.
function M:next()
	self.s = (self.s * 16807) % 2147483647
	return self.s
end

-- A number in [0, 1), or a whole number in [a, b].
function M:random(a, b)
	local r = (self:next() - 1) / 2147483646
	if not a then return r end
	return a + math.floor(r * (b - a + 1))
end

-- One entry of `list`, each with the weight `weight(entry)`. nil for an empty list or no weight.
function M:pick(list, weight)
	local total = 0
	for _, x in ipairs(list) do total = total + math.max(weight(x), 0) end
	if total <= 0 then return nil end
	local at = self:random() * total
	for _, x in ipairs(list) do
		at = at - math.max(weight(x), 0)
		if at < 0 then return x end
	end
	return list[#list]
end

return M
