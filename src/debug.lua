-- Super Earth Survivors' page in Obsidian API's in-game menu: a tool for testing a run. Upgrades by
-- their stacks, XP and levels, the clock (and with it the Heat), bosses, bombardments and the upgrades' own meters.
-- Stratagems and the rest of the player's kit are the Trainer's.
local upgrades = obsidian.module("src/upgrades")
local rules = obsidian.module("src/rules")
local director = obsidian.module("src/director")
local bosses = obsidian.module("src/bosses")
local bombard = obsidian.module("src/bombard")

local api = obsidian.import("obsidian.api")

local M = { player = 1 }

local WHY = {
	no_run = "Only during a Survivors run.",
	host_only = "Only the host can do this.",
	no_plan = "No boss in this run.",
	difficulty = "No bosses at this difficulty.",
	no_squad = "No players on the field.",
	not_due = "No boss is due yet. Move the clock forward first.",
	spawned = "That boss has already landed.",
	held = "The player already has it.",
	all_spawned = "Every boss of the run has landed.",
	not_loaded = "That faction's units aren't loaded in this mission.",
	not_in_mission = "Only in a mission.",
}

local function said(ok, why)
	if ok then return "Done" end
	return WHY[why] or tostring(why or "Not available.")
end

local function clock(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Testing goes past an upgrade's own limit: up to OVER times its stacks (an upgrade of one stack stays
-- at one, as more would do nothing).
M.OVER = 2
function M.most(u)
	local max = u.max or 9
	return max > 1 and max * M.OVER or max
end

-- One of each upgrade of a rarity the player doesn't hold yet and could be offered. The upgrades left
-- out, by name.
function M.one_of_each(run, rarity)
	local skipped = {}
	for _, u in ipairs(upgrades.list) do
		if u.rarity == rarity and run.stacks(M.player, u.id) == 0 then
			if run.allowed(M.player, u.id) then run.set_stacks(M.player, u.id, 1) else skipped[#skipped + 1] = u.name end
		end
	end
	return skipped
end

local function upgrades_page(run, rarity)
	return function(page)
		page:action("Give one of each", function()
			local skipped = M.one_of_each(run, rarity)
			if #skipped == 0 then return "Done" end
			return "Done. Left out, as the player can't use them: " .. table.concat(skipped, ", ")
		end)
		for _, u in ipairs(upgrades.list) do
			if u.rarity == rarity then
				page:number(u.name, {
					min = 0, max = M.most(u), step = 1, default = 0,
					-- An upgrade the player couldn't be offered (a stratagem not unlocked, a perk not owned, an
					-- older Obsidian API) stays out: its effect could call what the mission hasn't loaded.
					enabled = function() return run.stacks(M.player, u.id) > 0 or run.allowed(M.player, u.id) end,
					get = function() return run.stacks(M.player, u.id) end,
					set = function(v) run.set_stacks(M.player, u.id, v) end,
				})
			end
		end
	end
end

-- Evolutions: each one given directly, its halves set up first (the first at its max), or taken away,
-- which gives the halves back.
local function evolutions_page(run)
	return function(page)
		for _, e in ipairs(upgrades.EVOLUTIONS) do
			local a, b = upgrades.by_id[e.evolves[1]], upgrades.by_id[e.evolves[2]]
			page:action(e.name .. " (" .. a.name .. " + " .. b.name .. ")", function()
				if run.stacks(M.player, e.id) > 0 then
					run.set_stacks(M.player, e.id, 0)
					return "Taken away, the halves back"
				end
				return said(run.give_evolution(M.player, e.id))
			end)
		end
	end
end

-- run: src/run.lua.
function M.build(run)
	return function(page)
		local r = run.run
		if not r then
			page:label("Start a Survivors run to use this page.")
			return
		end
		local count = #r.local_list
		if count > 1 then
			local choices = {}
			for n = 1, count do choices[n] = { id = n, label = "Player " .. n } end
			page:choice("Player", { choices = choices, default = 1, get = function() return M.player end, set = function(v) M.player = v end })
		else
			M.player = 1
		end

		page:header("Upgrades")
		for _, rarity in ipairs({ "common", "rare", "legendary", "perk" }) do
			page:page(rarity:sub(1, 1):upper() .. rarity:sub(2), upgrades_page(run, rarity))
		end
		page:page("Evolutions", evolutions_page(run))
		page:action("Remove every upgrade", function()
			-- Evolutions first: taking one away gives its halves back, which go next.
			for _, e in ipairs(upgrades.EVOLUTIONS) do
				if run.stacks(M.player, e.id) > 0 then run.set_stacks(M.player, e.id, 0) end
			end
			for _, u in ipairs(upgrades.list) do
				if run.stacks(M.player, u.id) > 0 then run.set_stacks(M.player, u.id, 0) end
			end
			return "Done"
		end)

		page:header("Rerolls and banishes")
		page:action("Add 1 reroll", function() return said(run.add_redraw(M.player, "rerolls")) end)
		page:action("Add 1 banish", function() return said(run.add_redraw(M.player, "banishes")) end)

		page:header("Samples")
		page:action("Next level", function() return said(run.level_up()) end)
		page:action("Add 10 samples", function() return said(run.add_xp(10)) end)
		page:action("Add 100 samples", function() return said(run.add_xp(100)) end)

		page:header("Clock and Heat")
		page:label("Clock " .. clock(r.time) .. ", Heat " .. tostring(director.threat(r.time / 60)))
		page:number("Clock (minutes)", {
			min = 0, max = math.ceil(rules.RUN_LENGTH / 60), step = 1, default = 0,
			get = function() return math.floor((run.run and run.run.time or 0) / 60) end,
			set = function(v) run.set_minutes(v) end,
		})
		page:action("Spawn the boss due", function() return said(run.spawn_boss()) end)
		page:action("Spawn the next boss in order", function()
			if not api.game.is_host() then return said(false, "host_only") end
			local ok, why = bosses.spawn_next(run.run and run.run.squad)
			return said(ok, why == "spawned" and "all_spawned" or why)
		end)
		page:action("Start a bombardment window now", function()
			local now = run.run
			if not (now and now.bombard) then return said(false, "no_run") end
			if not api.game.is_host() then return said(false, "host_only") end
			bombard.force(now.bombard, now.time)
			bombard.alarm()
			return "Done. Strikes fall for " .. bombard.DEBUG_SECONDS .. " seconds."
		end)

		-- Elites (src/elites.lua), beside the player, from the host.
		local elites = obsidian.module("src/elites")
		page:header("Elites")
		for _, kind in ipairs(elites.KINDS) do
			page:action("Spawn a " .. kind:sub(1, 1):upper() .. kind:sub(2) .. " elite", function() return said(elites.debug_spawn(run.run, kind)) end)
		end

		page:header("Meters")
		page:action("Fill Kinetic Battery", function() return said(run.fill_battery(M.player), "no_run") end)
	end
end

function M.install(run)
	if not (api.menu and api.menu.add) then return false end
	api.menu.add("Super Earth Survivors", M.build(run))
	return true
end

return M
