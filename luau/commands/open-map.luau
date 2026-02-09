--!strict
-- nforge open-map <name>
-- Open a named place in Roblox Studio via protocol URL.

local Config = require("../util/config")
local Tool = require("../util/tool")

local HELP = [[
nforge open-map — Open a named place in Roblox Studio

USAGE:
    nforge open-map <name>

ARGS:
    <name>    Place name as defined in nforge.toml [places]

EXAMPLES:
    nforge open-map main
    nforge open-map lobby
]]

local function run(args: { string })
	if args[1] == "--help" or args[1] == "-h" then
		print(HELP)
		return
	end

	if args[1] == nil then
		error("Missing required argument: <name>\nRun 'nforge open-map --help' for usage.")
	end

	local config = Config.load()
	local resolvedName, place = Config.resolvePlace(config, args[1])

	local url = `roblox-studio:1+task:EditPlace+universeId:0+placeId:{place.id}`

	print(`Opening '{resolvedName}' (ID: {place.id}) in Roblox Studio...`)
	Tool.open(url)
end

return run
