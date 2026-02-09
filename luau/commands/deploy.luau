--!strict
-- nforge deploy [targets...] [--dry-run]
-- Run sync then publish in one shot.

local Args = require("../util/args")
local Reporter = require("../util/reporter")

local sync = require("./sync")
local publish = require("./publish")

local HELP = [[
nforge deploy — Sync and publish in one step

USAGE:
    nforge deploy [targets...] [--dry-run]

ARGS:
    [targets...]    Specific targets to sync and publish (all if omitted)

OPTIONS:
    --dry-run       Validate config without syncing or uploading

Runs 'nforge sync' followed by 'nforge publish'. If either step fails,
the pipeline stops.

EXAMPLES:
    nforge deploy              Sync all targets, then publish all
    nforge deploy lobby        Sync and publish only lobby
    nforge deploy --dry-run    Validate both sync and publish configs
]]

local function run(args: { string })
	if Args.hasFlag(args, "--help") or Args.hasFlag(args, "-h") then
		print(HELP)
		return
	end

	local dryRun = Args.hasFlag(args, "--dry-run")
	local dryRunLabel = if dryRun then " (dry run)" else ""

	print(`\n  === Sync{dryRunLabel} ===\n`)
	sync(args)

	print(`\n  === Publish{dryRunLabel} ===\n`)
	publish(args)

	if not dryRun then
		Reporter.success("Deploy complete: synced and published successfully")
	end
end

return run
