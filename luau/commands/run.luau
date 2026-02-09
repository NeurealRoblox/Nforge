--!strict
-- nforge run <script> [args...]
-- Run a Lune script from the project's lune/ directory.

local fs = require("@lune/fs")
local process = require("@lune/process")
local Tool = require("../util/tool")

local HELP = [[
nforge run — Run a Lune script

USAGE:
    nforge run <script> [args...]

ARGS:
    <script>     Script name (without .luau extension)
    [args...]    Arguments to pass to the script

Runs a Lune script from the project's lune/ directory.

EXAMPLES:
    nforge run get-map main output.rbxl true
    nforge run import-schematic MySchematic data.json
]]

local function run(args: { string })
	if args[1] == "--help" or args[1] == "-h" then
		print(HELP)
		return
	end

	local script = args[1]
	if script == nil then
		error("Missing required argument: <script>\nRun 'nforge run --help' for usage.")
	end

	local cwd = process.cwd
	if not fs.isDir(`{cwd}/lune`) then
		error(`No lune/ directory found in {cwd}`)
	end

	local luneArgs = { "run", script, "--" }
	for i = 2, #args do
		table.insert(luneArgs, args[i])
	end

	print(`Running lune script: {script}`)
	Tool.run("lune", luneArgs)
end

return run
