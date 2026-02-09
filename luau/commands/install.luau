--!strict
-- nforge install
-- Install project dependencies: wally packages, sourcemap, and type patching.

local fs = require("@lune/fs")
local process = require("@lune/process")
local Reporter = require("../util/reporter")
local Tool = require("../util/tool")

local HELP = [[
nforge install — Install project dependencies

USAGE:
    nforge install

Runs wally install, generates a Rojo sourcemap, then patches
Wally package types for LSP support.
]]

local function run(args: { string })
	if args[1] == "--help" or args[1] == "-h" then
		print(HELP)
		return
	end

	print("Installing dependencies...\n")

	-- wally install
	print("  Running wally install...")
	Tool.run("wally", { "install" })
	Reporter.stepOk("wally install")

	-- rojo sourcemap
	print("  Generating sourcemap...")
	Tool.run("rojo", { "sourcemap", "-o", "sourcemap.json" })
	Reporter.stepOk("rojo sourcemap")

	-- Patch types for each package directory
	local cwd = process.cwd
	for _, dir in { "Packages", "ServerPackages", "DevPackages" } do
		if fs.isDir(`{cwd}/{dir}`) then
			print(`  Patching types for {dir}...`)
			Tool.run("wally-package-types", { "--sourcemap", "sourcemap.json", dir })
			Reporter.stepOk(`wally-package-types {dir}`)
		end
	end

	Reporter.success("Dependencies installed successfully")
end

return run
