# Shared test fixtures

Canonical request and response payloads. All three SDKs (Flutter, Go, Rust)
assert against these same files, so a change to the gateway's contract breaks
every SDK's tests at once rather than silently drifting.

| File | What it is |
|---|---|
| `chat_request.json` | `POST /v1/chat/completions` body, non-streaming |
| `chat_response.json` | `POST /v1/chat/completions` 200 response |
| `chat_stream.txt` | Raw SSE byte stream for a streamed completion |
| `transcription_response.json` | `POST /v1/audio/transcriptions` 200 response |
| `health_response.json` | `GET /health` 200 response |
| `error_401.json` | Error body shape (FastAPI `detail` key) |

## How each SDK consumes these

- **Flutter** — `test/fixtures.dart` reads them from `../../shared/fixtures/`
- **Go** — `natlas/testdata` symlinks to this directory
- **Rust** — `tests/common/mod.rs` reads them via `CARGO_MANIFEST_DIR`

When you change the gateway contract in `serve/modal_app.py`, update the
fixture here first, then fix whichever SDKs fail.
