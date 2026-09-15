//! Check for external package sources. Allow only vendorable packages.

use std::fs;
use std::path::Path;

use crate::deps::WorkspaceInfo;
use crate::diagnostics::TidyCtx;

/// List of allowed sources for packages.
const ALLOWED_SOURCES: &[&str] = &[
    r#""registry+https://github.com/rust-lang/crates.io-index""#,
    // This is `rust_team_data` used by `site` in src/tools/rustc-perf,
    r#""git+https://github.com/rust-lang/team#db2c1ed9fbc0216e533db954cd249045c01c7406""#,
    // Phoenix-RTOS: libc in library/Cargo.lock, from library/Cargo.toml's
    // [patch.crates-io]. Update together with the lock file.
    r#""git+https://github.com/phoenix-rtos/libc-rs?branch=adamgreloch%2Fphoenix-0.2#f3626caafabada70c4b8e782f2a0b652968ae145""#,
];

/// Checks for external package sources. `root` is the path to the directory that contains the
/// workspace `Cargo.toml`.
pub fn check(root: &Path, tidy_ctx: TidyCtx) {
    let check = tidy_ctx.start_check("extdeps");

    for &WorkspaceInfo { path, submodules, .. } in crate::deps::WORKSPACES {
        if crate::deps::has_missing_submodule(root, submodules, tidy_ctx.is_running_on_ci()) {
            continue;
        }

        // FIXME check other workspaces too
        // `Cargo.lock` of rust.
        let lockfile = root.join(path).join("Cargo.lock");

        if !lockfile.exists() {
            check.error(format!("the `{path}` workspace doesn't have a Cargo.lock"));
            continue;
        }

        // Open and read the whole file.
        let cargo_lock = t!(fs::read_to_string(&lockfile));

        // Process each line.
        for line in cargo_lock.lines() {
            // Consider only source entries.
            if !line.starts_with("source = ") {
                continue;
            }

            // Extract source value.
            let source = line.split_once('=').unwrap().1.trim();

            // Ensure source is allowed.
            if !ALLOWED_SOURCES.contains(&source) {
                check.error(format!("invalid source: {}", source));
            }
        }
    }
}
