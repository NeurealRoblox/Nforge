--!strict
-- Simple argument parser.

local Args = {}

-- Check if a flag exists in args (e.g. "--dry-run", "--fix")
function Args.hasFlag(args: { string }, flag: string): boolean
	for _, arg in args do
		if arg == flag then
			return true
		end
	end
	return false
end

-- Get the value after a flag (e.g. --only <name> returns <name>)
function Args.getFlagValue(args: { string }, flag: string): string?
	for i, arg in args do
		if arg == flag and args[i + 1] ~= nil then
			return args[i + 1]
		end
	end
	return nil
end

-- Get all positional args (args that don't start with --)
function Args.getPositional(args: { string }): { string }
	local result = {}
	local skipNext = false

	for i, arg in args do
		if skipNext then
			skipNext = false
			continue
		end

		if string.sub(arg, 1, 2) == "--" then
			-- If this flag takes a value, skip the next arg too
			if args[i + 1] and string.sub(args[i + 1], 1, 2) ~= "--" then
				-- Check known value-flags
				if arg == "--only" or arg == "--max-uploads" then
					skipNext = true
				end
			end
		else
			table.insert(result, arg)
		end
	end

	return result
end

return Args
