# nforge

Generic Roblox build, sync, and publish CLI. Config-driven, works with any Roblox game project.

## What it does

nforge is a unified command-line tool that orchestrates the common Roblox development workflow:

- **Build** Rojo projects and open them in Studio
- **Sync** code and assets between multiple places (lobby, arena, etc.)
- **Publish** places to Roblox via the Open Cloud API
- **Install** Wally dependencies with type patching
- **Build** Studio plugins
- **Lint** with Selene and StyLua
- **Run** game-specific Lune scripts

## Architecture

nforge has two parts:

1. **Rust shim** (`src/main.rs`) — A tiny compiled binary (~200KB) that finds the Luau source next to it and runs `lune run <path> -- <args>`. This is what gets distributed via aftman/GitHub releases.

2. **Luau source** (`luau/`) — All the actual logic. Written in Luau, runs on Lune. This is what contributors read and modify.

When you run `nforge publish --dry-run`, the binary just forwards to `lune run luau/nforge -- publish --dry-run`.

## Requirements

- [Lune](https://lune-org.github.io/docs) 0.9+ (for running the Luau source)
- [Rojo](https://rojo.space) (for build/serve commands)
- [Wally](https://wally.run) (for install command)
- Other tools as needed: Selene, StyLua, wally-package-types

## Installation

### From source

```bash
git clone https://github.com/your-org/nforge.git
cd nforge
cargo build --release
```

Copy `target/release/nforge.exe` (or `nforge` on Mac/Linux) **and the `luau/` directory** to a location on your PATH. The binary must be able to find `luau/` next to it.

### Via aftman (once published)

Add to your project's `aftman.toml`:
```toml
nforge = "your-org/nforge@0.1.0"
```

## Setup

### 1. Create `nforge.toml` in your project root

```toml
[project]
name = "MyGame"
universe_id = 1234567890

[build]
default = { output = "build.rbxl" }
test = { output = "test.rbxl" }

[places]
main = { id = 93003304674217 }
lobby = { id = 134773766388507 }

[publish]
lobby = { place_id = 134773766388507, build = "builds/lobby.rbxl" }
arena = { place_id = 93003304674217, build = "builds/arena.rbxl" }

[[plugins]]
name = "my-plugin"
path = "plugins/my-plugin"
output = "my-plugin.rbxm"
```

### 2. Create `sync.luau` (optional, for multi-place games)

```luau
return {
    source = "main",
    targets = {
        lobby = {
            services = {
                "ReplicatedFirst",
                "ReplicatedStorage",
                "ServerScriptService",
                "ServerStorage",
            },
            starterPlayer = {
                children = { "StarterPlayerScripts" },
                copyProperties = true,
            },
            workspaceTags = { "WeaponModel", "MechModel" },
            copyServiceProperties = { "Workspace", "StarterGui" },
            properties = {
                Players = { CharacterAutoLoads = false },
            },
        },
    },
}
```

### 3. Create `.env` (for publishing)

```
OPEN_CLOUD_API_KEY=your-api-key-here
```

Add `.env` to your `.gitignore`.

## Commands

### `nforge open [project]`
Build a Rojo project, open in Studio, and start live sync.
```bash
nforge open          # default project
nforge open test     # test project
```

### `nforge open-map <name>`
Open a named place in Roblox Studio.
```bash
nforge open-map main
nforge open-map lobby
```

### `nforge sync [targets...] [--dry-run]`
Download places from Roblox, copy services/tags per `sync.luau`, write `.rbxl` files to `builds/`.
```bash
nforge sync              # sync all targets
nforge sync lobby        # sync only lobby
nforge sync --dry-run    # validate config only
```

### `nforge publish [targets...] [--dry-run] [--max-uploads N]`
Upload `.rbxl` files to Roblox via Open Cloud API.
```bash
nforge publish               # publish all targets
nforge publish lobby          # publish only lobby
nforge publish --dry-run      # validate without uploading
```

### `nforge plugins [--only <name>]`
Build Studio plugins defined in `nforge.toml`.
```bash
nforge plugins                # build all
nforge plugins --only my-plugin
```

### `nforge install`
Install Wally dependencies, generate sourcemap, and patch types.
```bash
nforge install
```

### `nforge lint [--fix]`
Run Selene linter and StyLua formatter.
```bash
nforge lint          # check mode
nforge lint --fix    # auto-fix formatting
```

### `nforge run <script> [args...]`
Run a Lune script from the project's `lune/` directory.
```bash
nforge run get-map main output.rbxl
nforge run import-schematic MySchematic data.json
```

## Contributing

All logic lives in `luau/`. The Rust shim (`src/main.rs`) rarely needs changes.

```
luau/
  nforge.luau              # Entry point (arg parsing, dispatch)
  commands/
    open.luau              # nforge open
    open-map.luau          # nforge open-map
    sync.luau              # nforge sync (place download, service copying)
    publish.luau           # nforge publish (Open Cloud upload)
    plugins.luau           # nforge plugins
    install.luau           # nforge install
    lint.luau              # nforge lint
    run.luau               # nforge run
  util/
    config.luau            # nforge.toml parser
    reporter.luau          # Colored console output
    tool.luau              # External tool runner
    args.luau              # Argument parser
```

To test changes, run directly with Lune:
```bash
lune run luau/nforge -- publish --dry-run
```

## License

MIT
