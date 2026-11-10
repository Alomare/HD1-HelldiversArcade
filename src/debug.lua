-- Super Earth Survivors' page in Obsidian API's in-game menu: a tool for testing a run. Upgrades by
-- their stacks, XP and levels, the clock (and with it the Heat), bosses, bombardments, elites and the upgrades' own meters.
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
	too_early = "Elites come from 3:00. Move the clock forward first.",
	at_most = "As many elites as the clock allows are out already.",
	paused = "Elite spawns are paused.",
	no_elite = "No elite is alive.",
	no_bulwark = "No Bulwark elite is alive.",
	no_dome = "The Bulwark dome is down already.",
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

local function title(kind) return kind:sub(1, 1):upper() .. kind:sub(2) end

-- Elites (src/elites.lua): spawned round the player from the host, on a base and in a number the page
-- keeps, plus the run's own schedule, clearing them, and the Shock and Bulwark kinds' own checks.
local BASES = {
	{ id = "home", label = "Mission's faction" },
	{ id = "bugs", label = "Brood Commander (Bugs)" },
	{ id = "cyborgs", label = "Warlord (Cyborgs)" },
	{ id = "illuminates", label = "Council Member (Illuminates)" },
}

local function elites_page(run)
	return function(page)
		local elites = obsidian.module("src/elites")
		local d = elites.debug
		if not api.game.is_host() then
			page:label("Only the host runs elites.")
			return
		end
		page:label(function()
			local r = run.run
			if not r then return "Start a Survivors run to use this page." end
			return elites.summary(elites.state, r.time)
		end)

		page:header("Spawn")
		page:choice("Base", { choices = BASES, default = "home", get = function() return d.base end, set = function(v) d.base = v end })
		page:number("Count", { min = 1, max = 6, step = 1, default = 1, get = function() return d.count end, set = function(v) d.count = v end })
		page:number("Distance (metres)", { min = 4, max = 40, step = 1, default = 8, get = function() return d.distance end, set = function(v) d.distance = v end })
		local function spawn(kind)
			local ok, n = elites.debug_spawn(run.run, kind)
			if ok then return "Done. " .. n .. (n == 1 and " elite" or " elites") .. " on the way." end
			return said(false, n)
		end
		for _, kind in ipairs(elites.KINDS) do
			page:action("Spawn " .. title(kind) .. " elite", function() return spawn(kind) end)
		end
		page:action("Spawn random elite", function() return spawn("random") end)

		page:header("Schedule")
		page:toggle("Pause elite spawns", {
			default = false,
			get = function() return d.paused end,
			set = function(v) d.paused = v end,
		})
		page:label("A pause lasts until the run ends.")
		page:action("Next elite now", function() return said(elites.debug_next(run.run)) end)
		page:action("Kill every elite", function()
			local ok, n = elites.debug_clear(run.run, true)
			if ok then return "Done. " .. n .. " killed, with their death effects." end
			return said(false, n)
		end)
		page:action("Remove every elite", function()
			local ok, n = elites.debug_clear(run.run, false)
			if ok then return "Done. " .. n .. " removed, with no death effects." end
			return said(false, n)
		end)

		page:header("Shock")
		page:label("Arcs only while a Helldiver out of the drop pod is within " .. elites.SHOCK_RANGE .. " m. Enemies take "
			.. elites.shock_power({}) .. ", players " .. elites.shock_power({ player = true }) .. ".")

		page:header("Bulwark")
		page:action("Break Bulwark dome", function()
			local ok, n = elites.debug_break_domes(run.run)
			if ok then return "Done. It comes back in " .. elites.DOME_BACK .. " seconds." end
			return said(false, n)
		end)
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

		page:header("Elites")
		page:label(function()
			local elites = obsidian.module("src/elites")
			if not api.game.is_host() then return "Only the host runs elites." end
			return run.run and elites.summary(elites.state, run.run.time) or ""
		end)
		page:page("Elite tools", elites_page(run))

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
