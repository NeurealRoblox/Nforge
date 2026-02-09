--!strict
-- nforge status
-- Show project state: config, builds, env, tools.

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local HELP = [[
nforge status — Show project status

USAGE:
    nforge status

Displays the current state of your nforge project: config summary,
build file status, environment variables, and installed tools.
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

local function yellow(text: string): string
	return `{stdio.color("yellow")}{text}{stdio.color("reset")}`
end

local function toolInstalled(name: string): boolean
	local result = process.exec(name, { "--version" }, { stdio = "default" })
	return result.ok
end

local function run(args: { string })
	if args[1] == "--help" or args[1] == "-h" then
		print(HELP)
		return
	end

	local cwd = process.cwd

	-- Config
	print(`\n  {stdio.style("bold")}Project{stdio.style("reset")}`)
	local configPath = `{cwd}/nforge.toml`
	if not fs.isFile(configPath) then
		print(`    {red("No nforge.toml found")}. Run 'nforge init <universe-id>' to create one.`)
		return
	end

	local content = fs.readFile(configPath)
	local config = serde.decode("toml", content)

	if config.project then
		print(`    Name:        {config.project.name or dim("not set")}`)
		print(`    Universe ID: {config.project.universe_id or dim("not set")}`)
	end

	-- Places
	local places = config.places or {}
	local placeCount = 0
	for _ in places do
		placeCount += 1
	end

	print(`\n  {stdio.style("bold")}Places{stdio.style("reset")} ({placeCount})`)
	for name, place in places do
		print(`    {name}  {dim(`ID: {place.id}`)}`)
	end
	if placeCount == 0 then
		print(`    {dim("None defined")}`)
	end

	-- Builds
	print(`\n  {stdio.style("bold")}Builds{stdio.style("reset")}`)
	local buildsDir = `{cwd}/builds`
	if fs.isDir(buildsDir) then
		local hasBuilds = false
		for name in places do
			local buildPath = `{buildsDir}/{name}.rbxl`
			if fs.isFile(buildPath) then
				hasBuilds = true
				local meta = fs.metadata(buildPath)
				local age = ""
				if meta.modifiedAt then
					local ageSeconds = os.time() - meta.modifiedAt.unixTimestamp
					if ageSeconds < 3600 then
						age = `{math.floor(ageSeconds / 60)}m ago`
					elseif ageSeconds < 86400 then
						age = `{math.floor(ageSeconds / 3600)}h ago`
					else
						local days = math.floor(ageSeconds / 86400)
						age = yellow(`{days}d ago`)
					end
				end
				print(`    {green("OK")}  {name}.rbxl  {dim(age)}`)
			else
				print(`    {dim("--")}  {name}.rbxl  {dim("not built")}`)
			end
		end
		if not hasBuilds then
			print(`    {dim("No build files yet. Run 'nforge sync' to generate them.")}`)
		end
	else
		print(`    {dim("No builds/ directory. Run 'nforge sync' to generate builds.")}`)
	end

	-- Publish targets
	local publishTargets = config.publish or {}
	local publishCount = 0
	for _ in publishTargets do
		publishCount += 1
	end

	if publishCount > 0 then
		print(`\n  {stdio.style("bold")}Publish Targets{stdio.style("reset")} ({publishCount})`)
		for name, target in publishTargets do
			local buildExists = fs.isFile(`{cwd}/{target.build}`)
			local icon = if buildExists then green("OK") else red("!!")
			print(`    {icon}  {name}  {dim(`place {target.place_id} <- {target.build}`)}`)
		end
	end

	-- Environment
	print(`\n  {stdio.style("bold")}Environment{stdio.style("reset")}`)
	local apiKey = process.env.OPEN_CLOUD_API_KEY
	local roblosec = process.env.ROBLOSECURITY
	print(
		`    OPEN_CLOUD_API_KEY  {if apiKey and #apiKey > 0 then green("set") else red("not set")}`
	)
	print(
		`    ROBLOSECURITY       {if roblosec and #roblosec > 0 then green("set") else red("not set")}`
	)

	-- Tools
	print(`\n  {stdio.style("bold")}Tools{stdio.style("reset")}`)
	local tools = { "lune", "rojo", "wally", "selene", "stylua" }
	for _, name in tools do
		local ok = pcall(toolInstalled, name)
		local installed = ok and toolInstalled(name)
		print(`    {name}  {if installed then green("installed") else dim("not found")}`)
	end

	print("")
end

return run
