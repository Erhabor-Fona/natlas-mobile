# Contributing

Thanks for looking at this. The most useful contribution right now is **trying
an SDK against your own gateway and telling us what broke** — particularly if
you are a Hausa, Igbo, or Yorùbá speaker who can judge whether the replies and
transcriptions are any good.

## Reporting what you find

Open an issue with:

- which SDK and version
- the language you were using
- what you expected and what happened
- for transcription problems, roughly what you said and what came back

If a transcription is wrong, say what the audio was in words — do not attach
recordings of other people's voices without their consent.

## Development setup

You need a running gateway first — see
[docs/self-hosting.md](docs/self-hosting.md). Everything else depends on it.

```bash
export NATLAS_BASE_URL=https://your-gateway.modal.run
export NATLAS_API_KEY=your_key
```

### Flutter

```bash
cd packages/flutter
flutter pub get
flutter analyze --fatal-infos
flutter test
dart format .
```

### Go

```bash
cd packages/go
gofmt -l .          # should print nothing
go vet ./...
go test -race ./...
```

### Rust

```bash
cd packages/rust
cargo fmt
cargo clippy --all-targets -- -D warnings
cargo test --all-targets
```

### Gateway

```bash
cd serve
pip install ruff
ruff check .
```

CI runs exactly these, so a green local run means a green CI run.

## The shared-fixture rule

`shared/fixtures/` holds the canonical request and response payloads. All three
SDKs assert against those same files, which is what keeps them from drifting
apart.

If you change the wire contract in `serve/gateway.py`:

1. Update the fixture in `shared/fixtures/` first
2. Run all three test suites
3. Fix whichever SDKs now fail
4. Update [docs/api.md](docs/api.md)

Do not add a fixture for one SDK only. If a payload is worth testing, it is
worth testing in all three.

## Adding a feature

Keep the three SDKs at parity. A feature that lands in one should land in all
three, or in none — the promise of this repo is that the same thing is
available whichever language you pick. If that is too much work for one PR, say
so in the issue first and we can split it.

Naming follows each language's conventions rather than being identical across
them: `chatStream` in Dart, `ChatStream` in Go, `chat_stream` in Rust.

## Scope

In scope: client ergonomics, error handling, the gateway, docs, tests,
additional platform support.

Out of scope: anything requiring model changes (we ship no weights), text-to-
speech (N-ATLaS has no TTS model), and automatic language detection (the ASR
models are per-language).

## Licensing

Code contributions are Apache-2.0, same as the repo.

Be aware of the N-ATLaS model licence before building anything public on this
— 1 000 active end-users per rolling 30 days, mandatory attribution, no
commercial deployment without a separate licence from Awarri. See
[NOTICE](NOTICE).

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
