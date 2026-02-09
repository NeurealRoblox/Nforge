--!strict
-- nforge plugins [--only <name>]
-- Build Studio plugins defined in nforge.toml.

local fs = require("@lune/fs")
local process = require("@lune/process")
local Args = require("../util/args")
local Config = require("../util/config")
local Reporter = require("../util/reporter")
local Tool = require("../util/tool")

local HELP = [[
nforge plugins — Build Studio plugins

USAGE:
    nforge plugins [--only <name>]

OPTIONS:
    --only <name>    Build only the named plugin

Builds all Studio plugins defined in nforge.toml [[plugins]].
For each plugin: runs wally install (if wally.toml exists), then rojo build.
]]

local function run(args: { string })
	if Args.hasFlag(args, "--help") or Args.hasFlag(args, "-h") then
		print(HELP)
		return
	end

	local config = Config.load()
	local plugins = config.plugins or {}

	if #plugins == 0 then
		print("No plugins defined in nforge.toml.")
		return
	end

	local onlyName = Args.getFlagValue(args, "--only")

	local pluginsToBuild = {}
	if onlyName then
		for _, plugin in plugins do
			if plugin.name == onlyName then
				table.insert(pluginsToBuild, plugin)
				break
			end
		end

		if #pluginsToBuild == 0 then
			local available = {}
			for _, plugin in plugins do
				table.insert(available, plugin.name)
			end
			error(`Unknown plugin '{onlyName}'. Available: {table.concat(available, ", ")}`)
		end
	else
		pluginsToBuild = plugins
	end

	print(`Building {#pluginsToBuild} plugin(s)...\n`)

	local failed = {}
	local cwd = process.cwd

	for i, plugin in pluginsToBuild do
		print(`  [{i}/{#pluginsToBuild}] Building '{plugin.name}'...`)

		local pluginPath = `{cwd}/{plugin.path}`

		if not fs.isDir(pluginPath) then
			Reporter.stepFail(plugin.name, `Plugin path '{plugin.path}' does not exist`)
			table.insert(failed, plugin.name)
			continue
		end

		-- wally install if wally.toml exists
		if fs.isFile(`{pluginPath}/wally.toml`) then
			local ok, err = pcall(Tool.run, "wally", { "install" }, pluginPath)
			if not ok then
				Reporter.stepFail(plugin.name, `wally install failed: {err}`)
				table.insert(failed, plugin.name)
				continue
			end
		end

		-- rojo build
		local ok, err = pcall(Tool.run, "rojo", { "build", plugin.path, "-o", plugin.output })
		if not ok then
			Reporter.stepFail(plugin.name, `rojo build failed: {err}`)
			table.insert(failed, plugin.name)
			continue
		end

		Reporter.stepOk(`{plugin.name} -> {plugin.output}`)
	end

	if #failed == 0 then
		Reporter.success(`Built {#pluginsToBuild}/{#pluginsToBuild} plugins successfully`)
	else
		Reporter.error(`{#failed}/{#pluginsToBuild} plugins failed to build`)
		print(`  Failed: {table.concat(failed, ", ")}`)
		error(`{#failed} plugin(s) failed to build`)
	end
end

return run
