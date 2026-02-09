# nforge Technical Specification

## Overview

nforge is a config-driven CLI tool for managing the build, sync, and publish workflow of Roblox game projects. It is designed to be generic and reusable across any Roblox project.

## System Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  nforge binary (Rust, embeds Luau source)                    │
│  src/main.rs — zero external deps                            │
│                                                              │
│  1. If luau/ exists next to binary: use it (development)     │
│  2. Otherwise: extract embedded files to cache (distribution)│
│  3. Forwards all arguments to: lune run luau/nforge -- args  │
│  4. Exits with the same exit code as Lune                    │
│                                                              │
│  Cache: %LOCALAPPDATA%\nforge\ (Win) / ~/.nforge/ (Unix)    │
│  Only re-extracts when version changes                       │
└──────────────────────┬───────────────────────────────────────┘
                       │ spawns
                       ▼
┌──────────────────────────────────────────────────────────────┐
│  Luau source (luau/)                                         │
│  Runtime: Lune 0.9+                                          │
│                                                              │
│  nforge.luau          Entry point, arg parsing, dispatch     │
│  commands/*.luau      One module per subcommand              │
│  util/*.luau          Shared utilities                       │
└──────────────────────┬───────────────────────────────────────┘
                       │ reads
                       ▼
┌──────────────────────────────────────────────────────────────┐
│  Game project (user's working directory)                     │
│                                                              │
│  nforge.toml          Project config (TOML)                  │
│  sync.luau            Place sync definitions (Luau)          │
│  .env                 Secrets (gitignored)                   │
│  default.project.json Rojo config                            │
│  lune/                Game-specific scripts                  │
└──────────────────────────────────────────────────────────────┘
```

## Runtime Dependencies

| Dependency | Version | Used by |
|------------|---------|---------|
| Lune | 0.9+ | All commands (runtime) |
| Rojo | 7.x | `open`, `install`, `plugins` |
| Wally | 0.3+ | `install`, `plugins` |
| wally-package-types | 1.x | `install` |
| Selene | 0.28+ | `lint` |
| StyLua | 2.x | `lint` |

## Configuration

### nforge.toml

Format: TOML. Located at project root.

```
[project]
  name: string           — Display name
  universe_id: number    — Roblox Universe ID

[build.<name>]
  output: string         — Output .rbxl filename

[places.<name>]
  id: number             — Roblox Place/Asset ID
  aliases: [string]?     — Optional alternative names

[publish.<name>]
  place_id: number       — Target Roblox Place ID for upload
  build: string          — Path to .rbxl file to upload

[[plugins]]
  name: string           — Plugin display name
  path: string           — Path to plugin directory (relative to project root)
  output: string         — Output .rbxm filename
```

### sync.luau

Format: Luau module that returns a table. Located at project root.

```
return {
  source: string         — Name of source place (references nforge.toml [places])
  targets: {
    [targetName]: {
      services: [string]?              — Services to fully copy (children)
      starterPlayer: {
        children: [string]?            — StarterPlayer children to copy
        copyProperties: boolean?       — Copy StarterPlayer properties
      }?
      workspaceTags: [string]?         — Copy Workspace children with these tags
      copyServiceProperties: [string]? — Copy properties (not children) of these services
      properties: {
        [serviceName]: {
          [propertyName]: any          — Set specific properties on target
        }
      }?
    }
  }
}
```

### .env

Format: KEY=VALUE pairs. Located at project root. Must be gitignored.

```
OPEN_CLOUD_API_KEY=...   — Required for `publish` command
ROBLOSECURITY=...        — Optional, for `sync` (falls back to Studio cookie)
```

## Command Specifications

### nforge init [universe-id]

**Purpose:** Initialize or refresh nforge.toml by fetching places from the Roblox API.

**Modes:**

1. **Fresh init** (`nforge init <universe-id>`):
   - Fails if `nforge.toml` already exists
   - Fetches all places in the universe via Roblox API
   - Generates slug keys from place display names (lowercase, non-alphanum to hyphens)
   - Derives project name from current directory name
   - Writes `nforge.toml` with `[project]` and `[places]` sections

2. **Refresh** (`nforge init` with existing config):
   - Reads existing `nforge.toml` to get `universe_id`
   - Fetches current places from API
   - Adds any places whose IDs don't already exist in config
   - Re-serializes and writes the file (comments are lost)

**Roblox API call:**
```
GET https://develop.roblox.com/v1/universes/{universeId}/places?limit=100&sortOrder=Asc&cursor={cursor}
Headers:
  Cookie: .ROBLOSECURITY=<cookie>  (optional, for private universes)
  Accept: application/json
Response: { data: [{ id, name, ... }], nextPageCursor, previousPageCursor }
```

**Pagination:** Loops with `cursor` param until `nextPageCursor` is nil. Uses `limit=100` (API maximum).

**Slug algorithm:**
1. Lowercase the place name
2. Replace runs of non-alphanumeric characters with a single hyphen
3. Trim leading/trailing hyphens
4. Deduplicate: if slug exists, append `-2`, `-3`, etc.

**Authentication:** ROBLOSECURITY from environment variable. Optional for public universes, required for private ones. Gives a specific error on 401/403.

### nforge open [project]

**Purpose:** Build a Rojo project, open in Studio, start live sync.

**Flow:**
1. Load `nforge.toml`, look up `[build.<project>]` (default: "default")
2. Run `rojo build [-p <project>] -o <output>`
3. Open `<output>` file (triggers Roblox Studio)
4. Run `rojo serve [<project>]` (blocks until terminated)

**Exit codes:** 0 on success, 1 if rojo fails.

### nforge open-map <name>

**Purpose:** Open a Roblox place in Studio via protocol URL.

**Flow:**
1. Load `nforge.toml`, resolve place name (checks direct match, then aliases)
2. Construct URL: `roblox-studio:1+task:EditPlace+universeId:0+placeId:<id>`
3. Open URL via platform-specific command (cmd /C start on Windows)

### nforge sync [targets...] [--dry-run]

**Purpose:** Download places from Roblox, copy services/assets between them, write .rbxl files.

**Flow:**
1. Load `nforge.toml`
2. Evaluate `sync.luau` (writes temp eval script, runs via lune, parses JSON output)
3. Validate: source place exists, all target places exist in config
4. If `--dry-run`: print validation results, exit
5. Download source + all target places concurrently via asset delivery API
6. For each target, perform sync operations:
   a. Copy service children (ClearAllChildren + Clone)
   b. Copy StarterPlayer children and optionally properties
   c. Copy Workspace children matching specified tags
   d. Copy service properties (using reflection database)
   e. Set explicit properties
7. Serialize each place and write to `builds/<name>.rbxl`

**Authentication:** Uses ROBLOSECURITY cookie (from Studio login or env var).

**Roblox API calls:**
- `GET https://assetdelivery.roblox.com/v2/assetId/<id>` — Get CDN download URL
- `GET <cdn-url>` — Download place binary

**Error handling:** Per-service [OK]/[FAIL] reporting. Fails fast on first error per target.

### nforge diff [targets...]

**Purpose:** Preview what `nforge sync` would change without writing any files.

**Flow:**
1. Load `nforge.toml` and evaluate `sync.luau` (same as sync command)
2. Download source + target places concurrently via asset delivery API
3. For each target, compare:
   a. Services: child names present in source but not target (additions) and vice versa (removals)
   b. StarterPlayer children: presence and child count differences
   c. Workspace tagged items: count differences per tag
4. Print a summary of additions and removals

**Authentication:** Same as sync (ROBLOSECURITY cookie).

### nforge publish [targets...] [--dry-run] [--max-uploads N]

**Purpose:** Upload .rbxl files to Roblox.

**Flow:**
1. Load `nforge.toml`
2. Check `OPEN_CLOUD_API_KEY` env var
3. Validate all build files exist
4. If `--dry-run`: print validation results, exit
5. For each target: read .rbxl, POST to Open Cloud API with retries

**Roblox API call:**
```
POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Published
Headers:
  x-api-key: <OPEN_CLOUD_API_KEY>
  Content-Type: application/octet-stream
Body: <raw .rbxl binary>
```

**Retry policy:** 5 attempts with exponential backoff (1s, 1.5s, 2.25s, 3.4s, 5s).

**Stale build warnings:** Before uploading, checks each build file's modification time. If older than 24 hours, prints a warning suggesting the user run `nforge sync` first.

**Error handling:** Per-target progress with [OK]/[FAIL]. Reports HTTP status and response body on failure. Summary at end showing succeeded vs failed.

### nforge deploy [targets...] [--dry-run]

**Purpose:** Run sync then publish in a single command.

**Flow:**
1. Run the sync command handler with the provided args
2. Run the publish command handler with the same args
3. If either step fails, the pipeline stops with an error

This is a convenience wrapper — it calls the same code paths as running `nforge sync` and `nforge publish` separately.

### nforge plugins [--only <name>]

**Purpose:** Build Studio plugins.

**Flow:**
1. Load `nforge.toml [[plugins]]`
2. For each plugin:
   a. If `wally.toml` exists in plugin dir: run `wally install`
   b. Run `rojo build <path> -o <output>`

### nforge install

**Purpose:** Install Wally dependencies and set up type information.

**Flow:**
1. Run `wally install`
2. Run `rojo sourcemap -o sourcemap.json`
3. For each of `Packages/`, `ServerPackages/`, `DevPackages/`:
   - If directory exists: run `wally-package-types --sourcemap sourcemap.json <dir>`

### nforge lint [--fix]

**Purpose:** Run code quality tools.

**Flow:**
1. Run `selene .`
2. Run `stylua --check .` (or `stylua .` if `--fix`)
3. Report combined pass/fail status

### nforge run <script> [args...]

**Purpose:** Run a Lune script from the project's `lune/` directory.

**Flow:**
1. Verify `lune/` directory exists
2. Run `lune run <script> -- <args...>`

### nforge status

**Purpose:** Show a dashboard of the current project state.

**Sections:**
1. **Project** — name and universe ID from nforge.toml
2. **Places** — all defined places with IDs
3. **Builds** — for each place, whether a build file exists in builds/ and its age
4. **Publish targets** — targets with build file status
5. **Environment** — whether OPEN_CLOUD_API_KEY and ROBLOSECURITY are set
6. **Tools** — whether lune, rojo, wally, selene, stylua are installed

### nforge completions <shell>

**Purpose:** Generate shell completion scripts for tab-completion.

**Supported shells:** bash, zsh, fish, powershell

**Output:** Prints the completion script to stdout. User redirects to their shell config file.

## Source File Map

```
nforge/
  Cargo.toml                    Rust shim package definition (zero dependencies)
  src/
    main.rs                     Rust binary: embeds luau/ source, extracts to cache, spawns lune
  luau/
    nforge.luau                 Entry point: parse first arg, dispatch to command module
    commands/
      init.luau                 Initialize/refresh nforge.toml from Roblox API
      open.luau                 Build + open + serve
      open-map.luau             Open place in Studio via protocol URL
      sync.luau                 Download places, copy services, write .rbxl
      diff.luau                 Preview sync changes without writing
      publish.luau              Upload .rbxl via Open Cloud API
      deploy.luau               Sync + publish pipeline
      plugins.luau              Build Studio plugins
      install.luau              Wally install + sourcemap + type patching
      lint.luau                 Selene + StyLua
      run.luau                  Lune script passthrough
      status.luau               Project status dashboard
      completions.luau          Shell completion generator
    util/
      config.luau               Parse nforge.toml, resolve place names/aliases
      reporter.luau             Colored [CHECK], [OK], [FAIL] console output
      tool.luau                 Run external processes, open files/URLs
      args.luau                 Simple flag/positional argument parser
  README.md                     User documentation
  SPEC.md                       This file
```

## Data Flow Diagrams

### Sync + Publish Pipeline

```
sync.luau (config)     nforge.toml (config)
       \                   /
        \                 /
         ▼               ▼
    ┌─────────────────────────┐
    │     nforge sync         │
    │                         │
    │  1. Download places     │◄── Roblox Asset Delivery API
    │  2. Copy services       │    (ROBLOSECURITY cookie)
    │  3. Copy tagged models  │
    │  4. Copy properties     │
    │  5. Serialize           │
    └────────┬────────────────┘
             │ writes
             ▼
    ┌─────────────────────────┐
    │    builds/*.rbxl        │
    └────────┬────────────────┘
             │ reads
             ▼
    ┌─────────────────────────┐
    │    nforge publish       │
    │                         │
    │  POST to Open Cloud API │──► Roblox
    │  with retries           │    (OPEN_CLOUD_API_KEY)
    └─────────────────────────┘
```

### Console Output Format

All commands use consistent colored output:

```
  [CHECK] label ... OK          — Pre-flight validation passed (green)
  [CHECK] label ... FAILED      — Pre-flight validation failed (red, bold)
          detail message

    [OK] label                  — Step completed successfully (green)
    [FAIL] label                — Step failed (red, bold)
          detail message

  [1/N] Uploading name... OK (3.2s)     — Progress with timing
  [1/N] Uploading name... FAILED        — Progress failure

  ERROR: message                — Fatal error (red, bold)
  Success message               — Final success (green, bold)
```
