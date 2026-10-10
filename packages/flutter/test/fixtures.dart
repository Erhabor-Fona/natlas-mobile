import 'dart:io';

/// Loads a fixture from the repo-wide `shared/fixtures/` directory so the
/// Flutter, Go, and Rust SDKs all assert against identical payloads.
String loadFixture(String name) {
  final path = '../../shared/fixtures/$name';
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      'Fixture not found: $path (cwd: ${Directory.current.path}). '
      'Run tests from packages/flutter/.',
    );
  }
  return file.readAsStringSync();
}
