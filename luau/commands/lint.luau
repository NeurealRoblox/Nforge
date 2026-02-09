--!strict
-- nforge lint [--fix]
-- Run linter (selene) and formatter (stylua).

local process = require("@lune/process")
local Args = require("../util/args")
local Reporter = require("../util/reporter")

local HELP = [[
nforge lint — Run linter and formatter

USAGE:
    nforge lint [--fix]

OPTIONS:
    --fix    Auto-fix formatting issues (runs stylua in write mode)

Runs selene for linting and stylua for formatting.
Without --fix, stylua runs in check mode (reports issues without changing files).
]]

local function run(args: { string })
	if Args.hasFlag(args, "--help") or Args.hasFlag(args, "-h") then
		print(HELP)
		return
	end

	local fix = Args.hasFlag(args, "--fix")
	local hadErrors = false

	-- selene
	print("Running selene...")
	local seleneResult = process.exec("selene", { "." }, { stdio = "forward" })
	if seleneResult.ok then
		Reporter.stepOk("selene")
	else
		Reporter.stepFail("selene", `exited with code {seleneResult.code}`)
		hadErrors = true
	end

	-- stylua
	local styluaArgs = if fix then { "." } else { "--check", "." }
	print(if fix then "Running stylua (fix mode)..." else "Running stylua (check mode)...")

	local styluaResult = process.exec("stylua", styluaArgs, { stdio = "forward" })
	if styluaResult.ok then
		Reporter.stepOk("stylua")
	else
		Reporter.stepFail("stylua", `exited with code {styluaResult.code}`)
		hadErrors = true
	end

	if hadErrors then
		Reporter.error("Lint checks failed")
		process.exit(1)
	else
		Reporter.success("All lint checks passed")
	end
end

return run
