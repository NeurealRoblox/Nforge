--!strict
-- Tool runner: execute external tools with error context.

local process = require("@lune/process")

local Tool = {}

-- Run an external tool, forwarding stdio. Errors if it fails.
function Tool.run(tool: string, args: { string }, cwd: string?)
	local result = process.exec(tool, args, {
		cwd = cwd or process.cwd,
		stdio = "forward",
	})

	if not result.ok then
		error(`'{tool}' exited with code {result.code}`)
	end
end

-- Run an external tool and capture stdout.
function Tool.capture(tool: string, args: { string }, cwd: string?): string
	local result = process.exec(tool, args, {
		cwd = cwd or process.cwd,
	})

	if not result.ok then
		error(`'{tool}' exited with code {result.code}\n{result.stderr}`)
	end

	return result.stdout
end

-- Open a file or URL (platform-specific).
function Tool.open(target: string)
	if process.os == "windows" then
		process.exec("cmd", { "/C", "start", "", target })
	elseif process.os == "macos" then
		process.exec("open", { target })
	else
		process.exec("xdg-open", { target })
	end
end

return Tool
