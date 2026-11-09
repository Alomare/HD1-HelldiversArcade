-- Offline tests for the parts of the mode that don't need the game. From the repository's root:
--   luajit tests/run.lua
local loaded = {}
obsidian = {
	module = function(name)
		if loaded[name] == nil then loaded[name] = dofile(name .. ".lua") end
		return loaded[name]
	end,
}

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then passed = passed + 1 else failed = failed + 1 print("FAIL " .. name .. "\n" .. err) end
end

function eq(got, want, what)
	if got ~= want then error((what or "value") .. ": expected " .. tostring(want) .. ", got " .. tostring(got), 2) end
end

function near(got, want, what)
	if math.abs(got - want) > 1e-6 then error((what or "value") .. ": expected " .. want .. ", got " .. got, 2) end
end

for _, file in ipairs({ "tests/test_logic.lua", "tests/test_cards.lua", "tests/test_entry.lua", "tests/test_samples.lua", "tests/test_campaign.lua",
	"tests/test_expansion.lua", "tests/test_bosses.lua", "tests/test_battery.lua", "tests/test_grenades.lua", "tests/test_spawns.lua", "tests/test_summary.lua", "tests/test_redraw.lua", "tests/test_evolve.lua", "tests/test_cadence.lua", "tests/test_elites.lua", "tests/test_hits.lua", "tests/test_drops.lua" }) do
	local tests = dofile(file)
	for _, t in ipairs(tests) do test(file .. " " .. t[1], t[2]) end
end
print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
