--!strict
-- Config loader: reads nforge.toml from the project root (current working directory).

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

export type PlaceConfig = {
	id: number,
	aliases: { string }?,
}

export type BuildConfig = {
	output: string,
}

export type PublishTarget = {
	place_id: number,
	build: string,
}

export type PluginConfig = {
	name: string,
	path: string,
	output: string,
}

export type Config = {
	project: { name: string, universe_id: number },
	build: { [string]: BuildConfig }?,
	places: { [string]: PlaceConfig }?,
	publish: { [string]: PublishTarget }?,
	plugins: { PluginConfig }?,
}

local Config = {}

function Config.load(): Config
	local cwd = process.cwd
	local configPath = `{cwd}/nforge.toml`

	if not fs.isFile(configPath) then
		error(`No nforge.toml found in {cwd}\nCreate one to configure your project.`)
	end

	local content = fs.readFile(configPath)
	local config = serde.decode("toml", content) :: Config

	if config.project == nil then
		error("nforge.toml is missing [project] section")
	end

	if config.project.name == nil then
		error("nforge.toml [project] is missing 'name'")
	end

	if config.project.universe_id == nil then
		error("nforge.toml [project] is missing 'universe_id'")
	end

	return config
end

function Config.resolvePlace(config: Config, name: string): (string, PlaceConfig)
	local places = config.places or {}

	-- Direct match
	if places[name] then
		return name, places[name]
	end

	-- Check aliases
	for placeName, place in places do
		if place.aliases then
			for _, alias in place.aliases do
				if alias == name then
					return placeName, place
				end
			end
		end
	end

	local available = {}
	for placeName in places do
		table.insert(available, placeName)
	end

	error(`Unknown place '{name}'. Available places: {table.concat(available, ", ")}`)
end

return Config
