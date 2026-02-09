--!strict
-- nforge open [project]
-- Build a Rojo project, open it in Studio, and start live sync.

local Config = require("../util/config")
local Tool = require("../util/tool")
local Reporter = require("../util/reporter")

local HELP = [[
nforge open — Build a Rojo project, open in Studio, and start live sync

USAGE:
    nforge open [project]

ARGS:
    [project]   Project name (uses default.project.json if omitted,
                otherwise <name>.project.json)

EXAMPLES:
    nforge open          Build default project, open, serve
    nforge open test     Build test project, open, serve
]]

local function run(args: { string })
	if args[1] == "--help" or args[1] == "-h" then
		print(HELP)
		return
	end

	local config = Config.load()
	local projectName = args[1] or "default"
	local builds = config.build or {}

	local buildConfig = builds[projectName]
	if buildConfig == nil then
		local available = {}
		for name in builds do
			table.insert(available, name)
		end
		error(
			`Unknown build project '{projectName}'. Available: {table.concat(available, ", ")}`
		)
	end

	local outputFile = buildConfig.output

	-- Build
	local rojoArgs = if projectName == "default"
		then { "build", "-o", outputFile }
		else { "build", projectName, "-o", outputFile }

	print(`Building project '{config.project.name}' -> {outputFile}`)
	Tool.run("rojo", rojoArgs)
	Reporter.stepOk(`Built {outputFile}`)

	-- Open
	print("Opening in Roblox Studio...")
	Tool.open(outputFile)

	-- Serve
	print("Starting Rojo serve...")
	local serveArgs = if projectName == "default" then { "serve" } else { "serve", projectName }

	Tool.run("rojo", serveArgs)
end

return run
