--!strict
-- nforge completions <shell>
-- Generate shell completion scripts.

local HELP = [[
nforge completions — Generate shell completions

USAGE:
    nforge completions <shell>

ARGS:
    <shell>    One of: bash, zsh, fish, powershell

EXAMPLES:
    nforge completions powershell >> $PROFILE
    nforge completions bash >> ~/.bashrc
    nforge completions zsh >> ~/.zshrc
    nforge completions fish > ~/.config/fish/completions/nforge.fish
]]

local COMMANDS = {
	"init",
	"open",
	"open-map",
	"sync",
	"diff",
	"publish",
	"deploy",
	"plugins",
	"status",
	"completions",
	"help",
}

local function bashCompletions(): string
	local cmds = table.concat(COMMANDS, " ")
	return `_nforge() \{\n`
		.. `    local cur="${'$'}\{COMP_WORDS[COMP_CWORD]\}"\n`
		.. `    local prev="${'$'}\{COMP_WORDS[COMP_CWORD-1]\}"\n`
		.. `\n`
		.. `    if [ "$COMP_CWORD" -eq 1 ]; then\n`
		.. `        COMPREPLY=( $(compgen -W "{cmds}" -- "$cur") )\n`
		.. `        return\n`
		.. `    fi\n`
		.. `\n`
		.. `    case "$prev" in\n`
		.. `        sync|publish|deploy)\n`
		.. `            COMPREPLY=( $(compgen -W "--dry-run --help" -- "$cur") )\n`
		.. `            ;;\n`
		.. `        plugins)\n`
		.. `            COMPREPLY=( $(compgen -W "--only --help" -- "$cur") )\n`
		.. `            ;;\n`
		.. `        completions)\n`
		.. `            COMPREPLY=( $(compgen -W "bash zsh fish powershell" -- "$cur") )\n`
		.. `            ;;\n`
		.. `        *)\n`
		.. `            COMPREPLY=( $(compgen -W "--help" -- "$cur") )\n`
		.. `            ;;\n`
		.. `    esac\n`
		.. `\}\n`
		.. `complete -F _nforge nforge\n`
end

local function zshCompletions(): string
	local cmds = table.concat(COMMANDS, " ")
	return `#compdef nforge\n`
		.. `\n`
		.. `_nforge() \{\n`
		.. `    local -a commands\n`
		.. `    commands=(\n`
		.. `        'init:Initialize or refresh nforge.toml from the Roblox API'\n`
		.. `        'open:Build a Rojo project, open in Studio, and start live sync'\n`
		.. `        'open-map:Open a named place in Roblox Studio'\n`
		.. `        'sync:Sync places per sync.luau'\n`
		.. `        'publish:Upload places to Roblox via Open Cloud API'\n`
		.. `        'deploy:Sync and publish in one step'\n`
		.. `        'plugins:Build Studio plugins'\n`
		.. `        'status:Show project status'\n`
		.. `        'completions:Generate shell completions'\n`
		.. `        'help:Show help message'\n`
		.. `    )\n`
		.. `\n`
		.. `    _arguments '1:command:->cmds' '*::arg:->args'\n`
		.. `\n`
		.. `    case $state in\n`
		.. `        cmds)\n`
		.. `            _describe 'command' commands\n`
		.. `            ;;\n`
		.. `        args)\n`
		.. `            case $words[1] in\n`
		.. `                sync|publish|deploy)\n`
		.. `                    _arguments '--dry-run[Validate without executing]' '--help[Show help]'\n`
		.. `                    ;;\n`
		.. `                plugins)\n`
		.. `                    _arguments '--only[Build specific plugin]:name:' '--help[Show help]'\n`
		.. `                    ;;\n`
		.. `                completions)\n`
		.. `                    _arguments '1:shell:(bash zsh fish powershell)'\n`
		.. `                    ;;\n`
		.. `            esac\n`
		.. `            ;;\n`
		.. `    esac\n`
		.. `\}\n`
		.. `\n`
		.. `_nforge\n`
end

local function fishCompletions(): string
	local lines = {
		"# nforge completions for fish",
		"complete -c nforge -e",
		"complete -c nforge -n '__fish_use_subcommand' -a 'init' -d 'Initialize or refresh nforge.toml'",
		"complete -c nforge -n '__fish_use_subcommand' -a 'open' -d 'Build, open in Studio, and serve'",
		"complete -c nforge -n '__fish_use_subcommand' -a 'open-map' -d 'Open a place in Studio'",
		"complete -c nforge -n '__fish_use_subcommand' -a 'sync' -d 'Sync places per sync.luau'",
		"complete -c nforge -n '__fish_use_subcommand' -a 'publish' -d 'Upload places via Open Cloud'",
		"complete -c nforge -n '__fish_use_subcommand' -a 'deploy' -d 'Sync and publish in one step'",
		"complete -c nforge -n '__fish_use_subcommand' -a 'plugins' -d 'Build Studio plugins'",
		"complete -c nforge -n '__fish_use_subcommand' -a 'status' -d 'Show project status'",
		"complete -c nforge -n '__fish_use_subcommand' -a 'completions' -d 'Generate shell completions'",
		"complete -c nforge -n '__fish_use_subcommand' -a 'help' -d 'Show help'",
		"complete -c nforge -n '__fish_seen_subcommand_from sync publish deploy' -l dry-run -d 'Validate without executing'",
		"complete -c nforge -n '__fish_seen_subcommand_from plugins' -l only -d 'Build specific plugin' -r",
		"complete -c nforge -n '__fish_seen_subcommand_from completions' -a 'bash zsh fish powershell'",
	}
	return table.concat(lines, "\n") .. "\n"
end

local function powershellCompletions(): string
	local cmds = table.concat(COMMANDS, "', '")
	return "Register-ArgumentCompleter -Native -CommandName nforge -ScriptBlock {\n"
		.. "    param($wordToComplete, $commandAst, $cursorPosition)\n"
		.. "\n"
		.. "    $commands = @(\n"
		.. "        @{ Name = 'init'; Desc = 'Initialize or refresh nforge.toml' },\n"
		.. "        @{ Name = 'open'; Desc = 'Build, open in Studio, and serve' },\n"
		.. "        @{ Name = 'open-map'; Desc = 'Open a place in Studio' },\n"
		.. "        @{ Name = 'sync'; Desc = 'Sync places per sync.luau' },\n"
		.. "        @{ Name = 'publish'; Desc = 'Upload places via Open Cloud' },\n"
		.. "        @{ Name = 'deploy'; Desc = 'Sync and publish in one step' },\n"
		.. "        @{ Name = 'plugins'; Desc = 'Build Studio plugins' },\n"
		.. "        @{ Name = 'status'; Desc = 'Show project status' },\n"
		.. "        @{ Name = 'completions'; Desc = 'Generate shell completions' },\n"
		.. "        @{ Name = 'help'; Desc = 'Show help' }\n"
		.. "    )\n"
		.. "\n"
		.. "    $elements = $commandAst.CommandElements\n"
		.. "    if ($elements.Count -le 2) {\n"
		.. "        $commands | Where-Object { $_.Name -like \"$wordToComplete*\" } | ForEach-Object {\n"
		.. "            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ParameterValue', $_.Desc)\n"
		.. "        }\n"
		.. "    }\n"
		.. "}\n"
end

local function run(args: { string })
	if args[1] == "--help" or args[1] == "-h" then
		print(HELP)
		return
	end

	local shell = args[1]
	if shell == nil then
		error("Missing required argument: <shell>\nRun 'nforge completions --help' for usage.")
	end

	if shell == "bash" then
		print(bashCompletions())
	elseif shell == "zsh" then
		print(zshCompletions())
	elseif shell == "fish" then
		print(fishCompletions())
	elseif shell == "powershell" then
		print(powershellCompletions())
	else
		error(`Unknown shell: '{shell}'. Supported: bash, zsh, fish, powershell`)
	end
end

return run
