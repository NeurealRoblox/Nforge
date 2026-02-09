--!strict
-- nforge publish [targets...] [--dry-run] [--max-uploads N]
-- Upload .rbxl files to Roblox via Open Cloud API.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local task = require("@lune/task")

local Args = require("../util/args")
local Config = require("../util/config")
local Reporter = require("../util/reporter")

local HELP = [[
nforge publish — Upload places to Roblox

USAGE:
    nforge publish [targets...] [--dry-run] [--max-uploads N]

ARGS:
    [targets...]         Specific targets to publish (publishes all if omitted)

OPTIONS:
    --dry-run            Validate config and build files without uploading
    --max-uploads <N>    Maximum number of concurrent uploads

Uploads .rbxl files to Roblox via the Open Cloud API.
Requires OPEN_CLOUD_API_KEY to be set in .env or environment.
]]

local MAX_RETRIES = 5

local function uploadPlace(apiKey: string, universeId: number, placeId: number, body: buffer): string?
	local url =
		`https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Published`

	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(net.request, {
			url = url,
			method = "POST",
			headers = {
				["x-api-key"] = apiKey,
				["Content-Type"] = "application/octet-stream",
			},
			body = body,
		})

		if ok and result.ok then
			return nil -- success
		end

		local errMsg = if ok
			then `Status: {result.statusCode} {result.body}`
			else tostring(result)

		if attempt == MAX_RETRIES then
			return `(attempt {attempt}/{MAX_RETRIES}) {errMsg}`
		end

		-- Exponential backoff
		task.wait(1.5 ^ (attempt - 1))
	end

	return "unreachable"
end

local function run(args: { string })
	if Args.hasFlag(args, "--help") or Args.hasFlag(args, "-h") then
		print(HELP)
		return
	end

	local dryRun = Args.hasFlag(args, "--dry-run")
	local requestedTargets = Args.getPositional(args)
	local config = Config.load()
	Reporter.checkOk("nforge.toml")

	-- Check API key
	local apiKey = process.env.OPEN_CLOUD_API_KEY
	if apiKey and #apiKey > 0 then
		Reporter.checkOk("OPEN_CLOUD_API_KEY")
	elseif not dryRun then
		Reporter.checkFail(
			"OPEN_CLOUD_API_KEY",
			"Not set. Add it to .env or set the environment variable."
		)
		error("OPEN_CLOUD_API_KEY is required for publishing")
	end

	-- Select targets
	local publishTargets = config.publish or {}
	local targetsToPublish: { { name: string, target: Config.PublishTarget } } = {}

	if #requestedTargets > 0 then
		for _, name in requestedTargets do
			local target = publishTargets[name]
			if target == nil then
				local available = {}
				for targetName in publishTargets do
					table.insert(available, targetName)
				end
				error(
					`Unknown publish target '{name}'. Available: {table.concat(available, ", ")}`
				)
			end
			table.insert(targetsToPublish, { name = name, target = target })
		end
	else
		for name, target in publishTargets do
			table.insert(targetsToPublish, { name = name, target = target })
		end
	end

	if #targetsToPublish == 0 then
		print("No publish targets defined in nforge.toml [publish].")
		return
	end

	-- Pre-flight: check all build files exist
	local allValid = true
	local cwd = process.cwd
	for _, entry in targetsToPublish do
		local buildPath = `{cwd}/{entry.target.build}`
		if fs.isFile(buildPath) then
			Reporter.checkOk(
				`target '{entry.name}' -> {entry.target.build} (place {entry.target.place_id})`
			)
		else
			Reporter.checkFail(
				`target '{entry.name}'`,
				`Build file '{entry.target.build}' does not exist. Run 'nforge sync' first.`
			)
			allValid = false
		end
	end

	if not allValid then
		error("Some build files are missing. Run 'nforge sync' to generate them.")
	end

	if dryRun then
		Reporter.success(
			`Dry run: {#targetsToPublish} target(s) validated successfully. Would upload to universe {config.project.universe_id}.`
		)
		return
	end

	print(`\n  Uploading to universe {config.project.universe_id}...\n`)

	local succeeded = 0
	local failed: { { name: string, reason: string } } = {}

	for i, entry in targetsToPublish do
		Reporter.progress(i, #targetsToPublish, `Uploading {entry.name} ({entry.target.place_id})`)

		local buildPath = `{cwd}/{entry.target.build}`
		local body = fs.readFile(buildPath)
		local startTime = os.clock()

		local err = uploadPlace(
			apiKey :: string,
			config.project.universe_id,
			entry.target.place_id,
			buffer.fromstring(body)
		)

		if err == nil then
			local elapsed = string.format("%.1fs", os.clock() - startTime)
			Reporter.progressOk(elapsed)
			succeeded += 1
		else
			Reporter.progressFail(err :: string)
			table.insert(failed, { name = entry.name, reason = err :: string })
		end
	end

	if #failed == 0 then
		Reporter.success(`Published {succeeded}/{#targetsToPublish} targets successfully`)
	else
		Reporter.error(`{#failed}/{#targetsToPublish} targets failed to publish`)
		print("  Failed:")
		for _, f in failed do
			print(`    {f.name} -- {f.reason}`)
		end
		error(`{#failed} target(s) failed to publish`)
	end
end

return run
