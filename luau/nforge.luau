--!strict
-- nforge: Generic Roblox build, sync, and publish CLI
-- Entry point — parses arguments and dispatches to command modules.

local process = require("@lune/process")
local stdio = require("@lune/stdio")

local commands = {
	init = require("./commands/init"),
	open = require("./commands/open"),
	["open-map"] = require("./commands/open-map"),
	sync = require("./commands/sync"),
	diff = require("./commands/diff"),
	publish = require("./commands/publish"),
	deploy = require("./commands/deploy"),
	plugins = require("./commands/plugins"),
	status = require("./commands/status"),
	completions = require("./commands/completions"),
}

local HELP_TEXT = [[
nforge — Generic Roblox build, sync, and publish CLI

USAGE:
    nforge <COMMAND> [OPTIONS] [ARGS]

COMMANDS:
    init [universe-id]          Initialize or refresh nforge.toml from the Roblox API
    open [project]              Build a Rojo project, open in Studio, and start live sync
    open-map <name>             Open a named place in Roblox Studio
    sync [targets...] [--dry-run]
                                Read places, copy services per sync.luau, write .rbxl to builds/
    diff [targets...]           Preview what sync would change without writing
    publish [targets...] [--dry-run] [--max-uploads N]
                                Upload .rbxl files to Roblox via Open Cloud API
    deploy [targets...] [--dry-run]
                                Sync and publish in one step
    plugins [--only <name>]     Build Studio plugins defined in nforge.toml
    status                      Show project status (config, builds, env, tools)
    completions <shell>         Generate shell completions (bash, zsh, fish, powershell)
    help                        Show this help message

OPTIONS:
    --help, -h                  Show help for a command
    --version, -V               Show version
]]

local VERSION = "0.1.0"

local args = process.args
local command = args[1]

if command == nil or command == "help" or command == "--help" or command == "-h" then
	print(HELP_TEXT)
	return
end

if command == "--version" or command == "-V" then
	print(`nforge {VERSION}`)
	return
end

local handler = commands[command]
if handler == nil then
	stdio.ewrite(`nforge: unknown command '{command}'\n`)
	stdio.ewrite(`Run 'nforge help' to see available commands.\n`)
	process.exit(1)
end

-- Remove the command name from args, pass the rest to the handler
local commandArgs = {}
for i = 2, #args do
	table.insert(commandArgs, args[i])
end

local ok, err = pcall(handler, commandArgs)
if not ok then
	stdio.ewrite(stdio.color("red"))
	stdio.ewrite(stdio.style("bold"))
	stdio.ewrite(`\nERROR: {err}\n`)
	stdio.ewrite(stdio.style("reset"))
	stdio.ewrite(stdio.color("reset"))
	process.exit(1)
end
