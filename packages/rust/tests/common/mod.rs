use std::path::PathBuf;

/// Loads a fixture from the repo-wide `shared/fixtures/` directory so the
/// Flutter, Go, and Rust SDKs assert against identical payloads.
pub fn load_fixture(name: &str) -> String {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../shared/fixtures")
        .join(name);

    std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("load fixture {}: {e}", path.display()))
}
