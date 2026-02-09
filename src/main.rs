use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, ExitCode};

const VERSION: &str = "0.1.0";

struct EmbeddedFile {
    path: &'static str,
    content: &'static str,
}

const EMBEDDED_FILES: &[EmbeddedFile] = &[
    // Entry point
    EmbeddedFile {
        path: "nforge.luau",
        content: include_str!("../luau/nforge.luau"),
    },
    // Commands
    EmbeddedFile {
        path: "commands/init.luau",
        content: include_str!("../luau/commands/init.luau"),
    },
    EmbeddedFile {
        path: "commands/open.luau",
        content: include_str!("../luau/commands/open.luau"),
    },
    EmbeddedFile {
        path: "commands/open-map.luau",
        content: include_str!("../luau/commands/open-map.luau"),
    },
    EmbeddedFile {
        path: "commands/sync.luau",
        content: include_str!("../luau/commands/sync.luau"),
    },
    EmbeddedFile {
        path: "commands/diff.luau",
        content: include_str!("../luau/commands/diff.luau"),
    },
    EmbeddedFile {
        path: "commands/publish.luau",
        content: include_str!("../luau/commands/publish.luau"),
    },
    EmbeddedFile {
        path: "commands/deploy.luau",
        content: include_str!("../luau/commands/deploy.luau"),
    },
    EmbeddedFile {
        path: "commands/plugins.luau",
        content: include_str!("../luau/commands/plugins.luau"),
    },
    EmbeddedFile {
        path: "commands/status.luau",
        content: include_str!("../luau/commands/status.luau"),
    },
    EmbeddedFile {
        path: "commands/completions.luau",
        content: include_str!("../luau/commands/completions.luau"),
    },
    // Utilities
    EmbeddedFile {
        path: "util/config.luau",
        content: include_str!("../luau/util/config.luau"),
    },
    EmbeddedFile {
        path: "util/reporter.luau",
        content: include_str!("../luau/util/reporter.luau"),
    },
    EmbeddedFile {
        path: "util/tool.luau",
        content: include_str!("../luau/util/tool.luau"),
    },
    EmbeddedFile {
        path: "util/args.luau",
        content: include_str!("../luau/util/args.luau"),
    },
];

/// Returns the platform-specific cache directory for nforge.
fn cache_dir() -> PathBuf {
    if cfg!(windows) {
        let base = env::var("LOCALAPPDATA")
            .or_else(|_| env::var("APPDATA"))
            .unwrap_or_else(|_| ".".to_string());
        PathBuf::from(base).join("nforge")
    } else {
        let home = env::var("HOME").unwrap_or_else(|_| ".".to_string());
        PathBuf::from(home).join(".nforge")
    }
}

/// Writes embedded Luau files to the cache directory if the version has changed.
/// Returns the path to the luau/ directory inside the cache.
fn ensure_cached_luau() -> Result<PathBuf, String> {
    let cache = cache_dir();
    let luau_dir = cache.join("luau");
    let version_file = cache.join(".version");

    // Skip writing if already up to date
    if let Ok(v) = fs::read_to_string(&version_file) {
        if v.trim() == VERSION {
            return Ok(luau_dir);
        }
    }

    // Write all embedded files
    for file in EMBEDDED_FILES {
        let path = luau_dir.join(file.path);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("failed to create directory {}: {}", parent.display(), e))?;
        }
        fs::write(&path, file.content)
            .map_err(|e| format!("failed to write {}: {}", path.display(), e))?;
    }

    fs::write(&version_file, VERSION)
        .map_err(|e| format!("failed to write version file: {}", e))?;

    Ok(luau_dir)
}

fn main() -> ExitCode {
    // Resolve the luau/ directory.
    // Priority: luau/ next to the executable (development), then embedded cache (distribution).
    let exe_dir = env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()));

    let local_luau = exe_dir.as_ref().map(|d| d.join("luau"));
    let luau_dir = if local_luau.as_ref().is_some_and(|p| p.is_dir()) {
        local_luau.unwrap()
    } else {
        match ensure_cached_luau() {
            Ok(dir) => dir,
            Err(e) => {
                eprintln!("nforge: {}", e);
                return ExitCode::from(1);
            }
        }
    };

    let entry_script = luau_dir.join("nforge");

    // Forward all args to: lune run <entry_script> -- <user args...>
    let user_args: Vec<String> = env::args().skip(1).collect();

    let mut cmd = Command::new("lune");
    cmd.arg("run");
    cmd.arg(&entry_script);
    cmd.arg("--");
    cmd.args(&user_args);

    match cmd.status() {
        Ok(status) => ExitCode::from(status.code().unwrap_or(1) as u8),
        Err(e) => {
            eprintln!("nforge: failed to run lune: {}", e);
            eprintln!("        Is lune installed? (https://lune-org.github.io/docs)");
            ExitCode::from(1)
        }
    }
}
