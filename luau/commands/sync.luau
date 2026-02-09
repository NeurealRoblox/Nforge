--!strict
-- nforge sync [targets...] [--dry-run]
-- Read places, copy services per sync.luau, write .rbxl to builds/.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Args = require("../util/args")
local Config = require("../util/config")
local Reporter = require("../util/reporter")

local db = roblox.getReflectionDatabase()

local HELP = [[
nforge sync — Sync places

USAGE:
    nforge sync [targets...] [--dry-run]

ARGS:
    [targets...]    Specific targets to sync (syncs all if omitted)

OPTIONS:
    --dry-run       Validate config without downloading or syncing

Reads places from Roblox, copies services/tags/properties per sync.luau,
and writes .rbxl files to builds/.
]]

-- Download a place from Roblox using the asset delivery API
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

-- Perform the sync: copy services, tags, properties from source → target
local function syncTarget(
	sourcePlace: roblox.DataModel,
	targetPlace: roblox.DataModel,
	targetConfig: any,
	sourceName: string,
	targetName: string
)
	print(`\n  Syncing: {sourceName} -> {targetName}`)

	-- Copy services
	if targetConfig.services then
		for _, serviceName in targetConfig.services do
			local ok, err = pcall(function()
				local sourceService = sourcePlace:GetService(serviceName)
				local targetService = targetPlace:GetService(serviceName)
				targetService:ClearAllChildren()

				local count = 0
				for _, child in sourceService:GetChildren() do
					child:Clone().Parent = targetService
					count += 1
				end
				Reporter.stepOk(`{serviceName} ({count} instances)`)
			end)

			if not ok then
				Reporter.stepFail(serviceName, tostring(err))
				error(`Failed to sync service {serviceName}: {err}`)
			end
		end
	end

	-- Copy StarterPlayer children
	if targetConfig.starterPlayer then
		local ok, err = pcall(function()
			local sourceStarter = sourcePlace:GetService("StarterPlayer")
			local targetStarter = targetPlace:GetService("StarterPlayer")

			for _, childName in targetConfig.starterPlayer.children or {} do
				local sourceChild = sourceStarter:FindFirstChild(childName)
				if sourceChild then
					local existing = targetStarter:FindFirstChild(childName)
					if existing then
						existing:ClearAllChildren()
						for _, child in sourceChild:GetChildren() do
							child:Clone().Parent = existing
						end
					else
						local newChild = roblox.Instance.new(sourceChild.ClassName)
						newChild.Name = childName
						newChild.Parent = targetStarter
						for _, child in sourceChild:GetChildren() do
							child:Clone().Parent = newChild
						end
					end
					Reporter.stepOk(`{childName} ({#sourceChild:GetChildren()} instances)`)
				end
			end

			if targetConfig.starterPlayer.copyProperties then
				local starterClass = db:GetClass("StarterPlayer")
				if starterClass then
					for propName in starterClass.Properties do
						pcall(function()
							targetStarter[propName] = sourceStarter[propName]
						end)
					end
				end
				Reporter.stepOk("StarterPlayer properties")
			end
		end)

		if not ok then
			Reporter.stepFail("StarterPlayer", tostring(err))
			error(`Failed to sync StarterPlayer: {err}`)
		end
	end

	-- Copy Workspace children by tags
	if targetConfig.workspaceTags and #targetConfig.workspaceTags > 0 then
		local ok, err = pcall(function()
			local sourceWorkspace = sourcePlace:GetService("Workspace")
			local targetWorkspace = targetPlace:GetService("Workspace")

			local tagCounts: { [string]: number } = {}
			for _, tagName in targetConfig.workspaceTags do
				tagCounts[tagName] = 0
			end

			for _, child in sourceWorkspace:GetChildren() do
				for _, tagName in targetConfig.workspaceTags do
					if child:HasTag(tagName) then
						while targetWorkspace:FindFirstChild(child.Name) do
							targetWorkspace:FindFirstChild(child.Name):Destroy()
						end
						child:Clone().Parent = targetWorkspace
						tagCounts[tagName] += 1
						break
					end
				end
			end

			local parts = {}
			for _, tagName in targetConfig.workspaceTags do
				table.insert(parts, `{tagName} ({tagCounts[tagName]})`)
			end
			Reporter.stepOk(`Workspace tags: {table.concat(parts, ", ")}`)
		end)

		if not ok then
			Reporter.stepFail("Workspace tags", tostring(err))
			error(`Failed to sync workspace tags: {err}`)
		end
	end

	-- Copy service properties (not children)
	if targetConfig.copyServiceProperties and #targetConfig.copyServiceProperties > 0 then
		local ok, err = pcall(function()
			for _, serviceName in targetConfig.copyServiceProperties do
				local serviceClass = db:GetClass(serviceName)
				if serviceClass then
					local sourceService = sourcePlace:GetService(serviceName)
					local targetService = targetPlace:GetService(serviceName)
					for propName in serviceClass.Properties do
						if propName == "CurrentCamera" then
							continue
						end
						pcall(function()
							targetService[propName] = sourceService[propName]
						end)
					end
				end
			end
			Reporter.stepOk(
				`Properties: {table.concat(targetConfig.copyServiceProperties, ", ")}`
			)
		end)

		if not ok then
			Reporter.stepFail("Service properties", tostring(err))
			error(`Failed to sync service properties: {err}`)
		end
	end

	-- Set specific properties
	if targetConfig.properties and type(targetConfig.properties) == "table" then
		local ok, err = pcall(function()
			for serviceName, props in targetConfig.properties do
				if type(props) == "table" then
					local service = targetPlace:GetService(serviceName)
					for propName, propValue in props do
						(service :: any)[propName] = propValue
					end
					Reporter.stepOk(`{serviceName} properties set`)
				end
			end
		end)

		if not ok then
			Reporter.stepFail("Custom properties", tostring(err))
			error(`Failed to set custom properties: {err}`)
		end
	end
end

local function run(args: { string })
	if Args.hasFlag(args, "--help") or Args.hasFlag(args, "-h") then
		print(HELP)
		return
	end

	local dryRun = Args.hasFlag(args, "--dry-run")
	local requestedTargets = Args.getPositional(args)
	local config = Config.load()

	-- Load sync.luau from the project directory
	local cwd = process.cwd
	local syncPath = `{cwd}/sync.luau`
	if not fs.isFile(syncPath) then
		error(`No sync.luau found in {cwd}\nCreate one to define how places are synced.`)
	end

	-- We need to evaluate sync.luau. We'll use a temp script that requires it and outputs JSON.
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

	-- Validate source place
	local sourceName = syncConfig.source
	local _, sourcePlace = Config.resolvePlace(config, sourceName)
	Reporter.checkOk(`source place '{sourceName}'`)

	-- Determine which targets to sync
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

	-- Validate all target places exist
	local targetCount = 0
	for targetName in targetsToSync do
		Config.resolvePlace(config, targetName)
		Reporter.checkOk(`target place '{targetName}'`)
		targetCount += 1
	end

	if dryRun then
		Reporter.success(`Dry run: {targetCount} target(s) validated successfully`)
		return
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

	-- Read source
	print("")
	task.spawn(readPlace, sourceName, sourcePlace.id)

	-- Read all targets
	for targetName in targetsToSync do
		local _, targetPlace = Config.resolvePlace(config, targetName)
		task.spawn(readPlace, targetName, targetPlace.id)
	end

	while readCount > 0 do
		task.wait()
	end

	if readError then
		error(readError)
	end

	-- Sync each target
	local successCount = 0
	for targetName, targetConfig in targetsToSync do
		syncTarget(places[sourceName], places[targetName], targetConfig, sourceName, targetName)

		-- Write output
		local outputDir = `{cwd}/builds`
		if not fs.isDir(outputDir) then
			fs.writeDir(outputDir)
		end

		local outputPath = `{outputDir}/{targetName}.rbxl`
		print(`\n  Writing {outputPath}...`)
		fs.writeFile(outputPath, roblox.serializePlace(places[targetName]))
		Reporter.stepOk(`Written {outputPath}`)
		successCount += 1
	end

	-- Also write source place
	local sourceOutputPath = `{cwd}/builds/{sourceName}.rbxl`
	print(`\n  Writing {sourceOutputPath}...`)
	fs.writeFile(sourceOutputPath, roblox.serializePlace(places[sourceName]))
	Reporter.stepOk(`Written {sourceOutputPath}`)

	Reporter.success(`Synced {successCount}/{targetCount} targets successfully`)
end

return run
