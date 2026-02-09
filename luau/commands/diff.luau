--!strict
-- nforge diff [targets...]
-- Show what nforge sync would change, without writing anything.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local Args = require("../util/args")
local Config = require("../util/config")
local Reporter = require("../util/reporter")

local HELP = [[
nforge diff — Preview what sync would change

USAGE:
    nforge diff [targets...]

ARGS:
    [targets...]    Specific targets to diff (diffs all if omitted)

Downloads the source and target places from Roblox and compares them,
showing what services, children, and tagged items would be added or
removed by 'nforge sync'.

EXAMPLES:
    nforge diff            Diff all sync targets
    nforge diff lobby      Diff only lobby
]]

local function dim(text: string): string
	return `{stdio.style("dim")}{text}{stdio.style("reset")}`
end

local function green(text: string): string
	return `{stdio.color("green")}{text}{stdio.color("reset")}`
end

local function red(text: string): string
	return `{stdio.color("red")}{text}{stdio.color("reset")}`
end

local function getAuthCookie(): string
	local cookie = roblox.getAuthCookie()
	if cookie then
		return cookie
	end

	local cookieFromEnv = process.env.ROBLOSECURITY
	if cookieFromEnv and #cookieFromEnv > 0 then
		return `.ROBLOSECURITY={cookieFromEnv}`
	end

	error("Failed to find ROBLOSECURITY cookie. Log into Studio or set ROBLOSECURITY env var.")
end

local function downloadPlace(assetId: number): roblox.DataModel
	local cookie = getAuthCookie()

	local response = net.request({
		url = `https://assetdelivery.roblox.com/v2/assetId/{assetId}`,
		headers = { Accept = "application/json", Cookie = cookie },
	})

	if not response.ok then
		error(`Failed to fetch asset {assetId}: {response.statusCode} {response.body}`)
	end

	local body = serde.decode("json", response.body)
	local location = body.locations and body.locations[1] and body.locations[1].location
	if not location then
		error(`No download location for asset {assetId}`)
	end

	local cdnResponse = net.request({
		url = location,
		headers = { Cookie = cookie },
	})

	if not cdnResponse.ok then
		error(`Failed to download asset {assetId} from CDN: {cdnResponse.statusCode}`)
	end

	return roblox.deserializePlace(cdnResponse.body)
end

-- Build a set of child names from a service
local function childNameSet(service: roblox.Instance): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, child in service:GetChildren() do
		set[child.Name] = true
	end
	return set
end

-- Compare services: show what children would be added/removed
local function diffService(
	sourcePlace: roblox.DataModel,
	targetPlace: roblox.DataModel,
	serviceName: string
): (number, number)
	local sourceService = sourcePlace:GetService(serviceName)
	local targetService = targetPlace:GetService(serviceName)

	local sourceNames = childNameSet(sourceService)
	local targetNames = childNameSet(targetService)

	local added = 0
	local removed = 0

	for name in sourceNames do
		if not targetNames[name] then
			print(`      {green("+")} {name}`)
			added += 1
		end
	end

	for name in targetNames do
		if not sourceNames[name] then
			print(`      {red("-")} {name}`)
			removed += 1
		end
	end

	return added, removed
end

local function run(args: { string })
	if Args.hasFlag(args, "--help") or Args.hasFlag(args, "-h") then
		print(HELP)
		return
	end

	local requestedTargets = Args.getPositional(args)
	local config = Config.load()

	-- Load sync.luau
	local cwd = process.cwd
	local syncPath = `{cwd}/sync.luau`
	if not fs.isFile(syncPath) then
		error(`No sync.luau found in {cwd}\nCreate one to define how places are synced.`)
	end

	local evalScript =
		`local serde = require("@lune/serde")\nlocal cfg = require("./sync")\nprint(serde.encode("json", cfg))`
	local evalPath = `{cwd}/.nforge-eval-sync.luau`
	fs.writeFile(evalPath, evalScript)

	local evalResult = process.exec("lune", { "run", ".nforge-eval-sync" }, { cwd = cwd })
	fs.removeFile(evalPath)

	if not evalResult.ok then
		error(`Failed to evaluate sync.luau:\n{evalResult.stderr}`)
	end

	local syncConfig = serde.decode("json", evalResult.stdout)
	Reporter.checkOk("sync.luau")

	local sourceName = syncConfig.source
	local _, sourcePlace = Config.resolvePlace(config, sourceName)
	Reporter.checkOk(`source place '{sourceName}'`)

	-- Determine targets
	local allTargets = syncConfig.targets or {}
	local targetsToSync = {}

	if #requestedTargets > 0 then
		for _, name in requestedTargets do
			if allTargets[name] == nil then
				local available = {}
				for targetName in allTargets do
					table.insert(available, targetName)
				end
				error(`Unknown sync target '{name}'. Available: {table.concat(available, ", ")}`)
			end
			targetsToSync[name] = allTargets[name]
		end
	else
		targetsToSync = allTargets
	end

	-- Download places concurrently
	local places: { [string]: roblox.DataModel } = {}
	local readCount = 0
	local readError: string? = nil

	local function readPlace(name: string, placeId: number)
		readCount += 1
		local ok, result = pcall(downloadPlace, placeId)
		if ok then
			places[name] = result :: roblox.DataModel
			print(`  Reading '{name}' ({placeId})... OK`)
		else
			readError = `Failed to read '{name}' ({placeId}): {result}`
			print(`  Reading '{name}' ({placeId})... FAILED`)
		end
		readCount -= 1
	end

	print("")
	task.spawn(readPlace, sourceName, sourcePlace.id)
	for targetName in targetsToSync do
		local _, targetPlaceCfg = Config.resolvePlace(config, targetName)
		task.spawn(readPlace, targetName, targetPlaceCfg.id)
	end

	while readCount > 0 do
		task.wait()
	end

	if readError then
		error(readError)
	end

	-- Diff each target
	local totalAdded = 0
	local totalRemoved = 0

	for targetName, targetConfig in targetsToSync do
		print(`\n  {stdio.style("bold")}{sourceName} -> {targetName}{stdio.style("reset")}`)

		local src = places[sourceName]
		local tgt = places[targetName]

		-- Diff services
		if targetConfig.services then
			for _, serviceName in targetConfig.services do
				print(`\n    {serviceName}:`)
				local added, removed = diffService(src, tgt, serviceName)
				if added == 0 and removed == 0 then
					print(`      {dim("no changes")}`)
				end
				totalAdded += added
				totalRemoved += removed
			end
		end

		-- Diff StarterPlayer children
		if targetConfig.starterPlayer and targetConfig.starterPlayer.children then
			print(`\n    StarterPlayer:`)
			local sourceStarter = src:GetService("StarterPlayer")
			local targetStarter = tgt:GetService("StarterPlayer")
			local anyChanges = false

			for _, childName in targetConfig.starterPlayer.children do
				local sourceChild = sourceStarter:FindFirstChild(childName)
				local targetChild = targetStarter:FindFirstChild(childName)

				if sourceChild and not targetChild then
					print(`      {green("+")} {childName} {dim(`({#sourceChild:GetChildren()} children)`)}`)
					totalAdded += 1
					anyChanges = true
				elseif sourceChild and targetChild then
					local srcCount = #sourceChild:GetChildren()
					local tgtCount = #targetChild:GetChildren()
					if srcCount ~= tgtCount then
						print(`      {stdio.color("yellow")}~{stdio.color("reset")} {childName} {dim(`{tgtCount} -> {srcCount} children`)}`)
						anyChanges = true
					end
				end
			end

			if not anyChanges then
				print(`      {dim("no changes")}`)
			end
		end

		-- Diff workspace tags
		if targetConfig.workspaceTags and #targetConfig.workspaceTags > 0 then
			print(`\n    Workspace tags:`)
			local sourceWorkspace = src:GetService("Workspace")
			local targetWorkspace = tgt:GetService("Workspace")
			local anyChanges = false

			for _, tagName in targetConfig.workspaceTags do
				local sourceTagged = 0
				local targetTagged = 0

				for _, child in sourceWorkspace:GetChildren() do
					if child:HasTag(tagName) then
						sourceTagged += 1
					end
				end
				for _, child in targetWorkspace:GetChildren() do
					if child:HasTag(tagName) then
						targetTagged += 1
					end
				end

				if sourceTagged ~= targetTagged then
					print(`      {stdio.color("yellow")}~{stdio.color("reset")} {tagName} {dim(`{targetTagged} -> {sourceTagged} items`)}`)
					anyChanges = true
				end
			end

			if not anyChanges then
				print(`      {dim("no changes")}`)
			end
		end
	end

	-- Summary
	if totalAdded == 0 and totalRemoved == 0 then
		Reporter.success("No differences found. Places are in sync.")
	else
		print("")
		if totalAdded > 0 then
			print(`  {green(`+{totalAdded}`)} additions`)
		end
		if totalRemoved > 0 then
			print(`  {red(`-{totalRemoved}`)} removals`)
		end
		print(`\n  Run 'nforge sync' to apply these changes.`)
	end
end

return run
