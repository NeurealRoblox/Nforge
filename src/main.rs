use std::env;
use std::process::{Command, ExitCode};

fn main() -> ExitCode {
    // Find the luau/ directory next to this executable
    let exe_path = match env::current_exe() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("nforge: failed to locate executable: {}", e);
            return ExitCode::from(1);
        }
    };

    let install_dir = match exe_path.parent() {
        Some(dir) => dir.to_path_buf(),
        None => {
            eprintln!("nforge: failed to resolve install directory");
            return ExitCode::from(1);
        }
    };

    let entry_script = install_dir.join("luau").join("nforge");

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
