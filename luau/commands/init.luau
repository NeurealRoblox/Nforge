--!strict
-- nforge init [universe-id]
-- Initialize or refresh nforge.toml by fetching places from the Roblox API.

local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Args = require("../util/args")
local Reporter = require("../util/reporter")

local HELP = [[
nforge init — Initialize or refresh nforge.toml

USAGE:
    nforge init <universe-id>     Create a new nforge.toml from a Roblox universe
    nforge init                   Refresh existing nforge.toml with new places

ARGS:
    <universe-id>    Roblox Universe ID (required for fresh init)

When run without arguments and nforge.toml already exists, fetches the
current list of places from the Roblox API and adds any new ones to the config.

Requires ROBLOSECURITY to be set in .env or environment for private universes.

EXAMPLES:
    nforge init 1234567890       Create nforge.toml for universe 1234567890
    nforge init                  Add any new places to existing config
]]

local function slugify(name: string): string
	local slug = string.lower(name)
	slug = string.gsub(slug, "[^%w]+", "-")
	slug = string.gsub(slug, "^-+", "")
	slug = string.gsub(slug, "-+$", "")
	if #slug == 0 then
		slug = "place"
	end
	return slug
end

local function deduplicateSlug(slug: string, used: { [string]: boolean }): string
	if not used[slug] then
		return slug
	end
	local i = 2
	while used[`{slug}-{i}`] do
		i += 1
	end
	return `{slug}-{i}`
end

local function getAuthCookie(): string?
	local cookie = process.env.ROBLOSECURITY
	if cookie and #cookie > 0 then
		return `.ROBLOSECURITY={cookie}`
	end
	return nil
end

type PlaceInfo = {
	id: number,
	name: string,
}

local function fetchPlaces(universeId: number): { PlaceInfo }
	local cookie = getAuthCookie()
	local allPlaces: { PlaceInfo } = {}
	local cursor: string? = nil

	repeat
		local url = `https://develop.roblox.com/v1/universes/{universeId}/places?limit=100&sortOrder=Asc`
		if cursor then
			url = url .. `&cursor={cursor}`
		end

		local headers: { [string]: string } = { Accept = "application/json" }
		if cookie then
			headers.Cookie = cookie
		end

		local response = net.request({
			url = url,
			headers = headers,
		})

		if not response.ok then
			if response.statusCode == 401 or response.statusCode == 403 then
				error(
					`API returned {response.statusCode}. Is ROBLOSECURITY set? `
						.. `Private universes require authentication.\n`
						.. `Set ROBLOSECURITY in .env or your environment.`
				)
			end
			error(`Failed to fetch places for universe {universeId}: {response.statusCode} {response.body}`)
		end

		local body = serde.decode("json", response.body)
		if body.data == nil then
			error("Unexpected API response: missing 'data' field")
		end

		for _, place in body.data do
			table.insert(allPlaces, {
				id = place.id,
				name = place.name,
			})
		end

		cursor = body.nextPageCursor
	until cursor == nil

	return allPlaces
end

local function freshInit(universeId: number)
	print(`Fetching places for universe {universeId}...\n`)
	local places = fetchPlaces(universeId)

	if #places == 0 then
		error(`No places found in universe {universeId}. Is the Universe ID correct?`)
	end

	Reporter.stepOk(`Found {#places} place(s)`)

	local cwd = process.cwd
	local projectName = string.match(cwd, "[/\\]([^/\\]+)$") or "my-game"

	local placesTable: { [string]: { id: number } } = {}
	local usedSlugs: { [string]: boolean } = {}

	for _, place in places do
		local slug = slugify(place.name)
		slug = deduplicateSlug(slug, usedSlugs)
		usedSlugs[slug] = true
		placesTable[slug] = { id = place.id }
		Reporter.stepOk(`{place.name} -> [{slug}] (ID: {place.id})`)
	end

	local config = {
		project = {
			name = projectName,
			universe_id = universeId,
		},
		places = placesTable,
	}

	local toml = serde.encode("toml", config)
	fs.writeFile(`{cwd}/nforge.toml`, toml)

	Reporter.success(`Created nforge.toml with {#places} place(s)`)
	print(`\n  Edit nforge.toml to add [build], [publish], and [[plugins]] sections as needed.`)
end

local function refreshInit()
	local cwd = process.cwd
	local configPath = `{cwd}/nforge.toml`

	if not fs.isFile(configPath) then
		error(`No nforge.toml found in {cwd}\nTo create a new config, run: nforge init <universe-id>`)
	end

	local content = fs.readFile(configPath)
	local config = serde.decode("toml", content)

	if config.project == nil or config.project.universe_id == nil then
		error("nforge.toml is missing [project] universe_id. Cannot refresh.")
	end

	local universeId = config.project.universe_id
	print(`Refreshing places for universe {universeId}...\n`)

	local places = fetchPlaces(universeId)
	Reporter.stepOk(`Fetched {#places} place(s) from API`)

	local existingIds: { [number]: string } = {}
	local existingPlaces = config.places or {}
	for slug, place in existingPlaces do
		if place.id then
			existingIds[place.id] = slug
		end
	end

	local usedSlugs: { [string]: boolean } = {}
	for slug in existingPlaces do
		usedSlugs[slug] = true
	end

	local addedCount = 0
	for _, place in places do
		if existingIds[place.id] == nil then
			local slug = slugify(place.name)
			slug = deduplicateSlug(slug, usedSlugs)
			usedSlugs[slug] = true

			if config.places == nil then
				config.places = {}
			end
			config.places[slug] = { id = place.id }
			addedCount += 1
			Reporter.stepOk(`New: {place.name} -> [{slug}] (ID: {place.id})`)
		end
	end

	if addedCount == 0 then
		Reporter.success("No new places to add. Config is up to date.")
		return
	end

	local toml = serde.encode("toml", config)
	fs.writeFile(configPath, toml)

	Reporter.success(`Added {addedCount} new place(s) to nforge.toml`)
end

local function run(args: { string })
	if Args.hasFlag(args, "--help") or Args.hasFlag(args, "-h") then
		print(HELP)
		return
	end

	local positional = Args.getPositional(args)
	local universeIdStr = positional[1]

	if universeIdStr then
		local universeId = tonumber(universeIdStr)
		if universeId == nil then
			error(`Invalid universe ID: '{universeIdStr}'. Must be a number.`)
		end

		local cwd = process.cwd
		if fs.isFile(`{cwd}/nforge.toml`) then
			error(
				`nforge.toml already exists in {cwd}\n`
					.. `To refresh places from the API, run: nforge init (without arguments)\n`
					.. `To start fresh, delete nforge.toml first.`
			)
		end

		freshInit(universeId)
	else
		refreshInit()
	end
end

return run
