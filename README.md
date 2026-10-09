# N-ATLaS Mobile SDK

The mobile and systems layer for [N-ATLaS](https://huggingface.co/NCAIR1/N-ATLaS),
Nigeria's sovereign multilingual LLM — Hausa · Igbo · Yorùbá · Nigerian English.

Built for the **NITDA National AI Innovation Challenge 2026** — Problem Statement 1:
*"Build the tools that make N-ATLaS easy to build with."*

[![CI](https://github.com/Erhabor-Fona/natlas-mobile/actions/workflows/ci.yml/badge.svg)](https://github.com/Erhabor-Fona/natlas-mobile/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

---

## What's in this repo

| Package | Language | What it does |
|---|---|---|
| `packages/flutter` | Dart / Flutter | `natlas_flutter` — pub.dev package with widgets |
| `packages/go` | Go | `natlas-go` — idiomatic Go client |
| `packages/rust` | Rust | `natlas` — async Rust crate (tokio + reqwest) |
| `apps/demo` | Flutter | Voice chatbot demo app (the showcase artefact) |
| `serve/` | Python | Self-hosting gateway: vLLM + FastAPI ASR + Modal/Docker |

N-ATLAS-Kit (the existing JS/Python toolkit) solved the web and server layer.
This kit solves the **mobile and systems layer** — the Flutter SDK that puts
N-ATLaS in a published app in two lines, the Rust crate for embedded and backend
deployments, and the Go client for infrastructure teams.

> **Deploy the gateway first.** There is no public N-ATLaS API, so every SDK
> here needs an endpoint you own. It is one command on Modal —
> see [docs/self-hosting.md](docs/self-hosting.md).

---

## 30-second quickstart

### Flutter

```dart
import 'package:natlas_flutter/natlas_flutter.dart';

final client = NAtlasClient(
  baseUrl: 'https://your-gateway.modal.run',
  apiKey: 'your_api_key',
);

// Streaming chat in Hausa
await for (final chunk in client.chatStream(
  messages: [ChatMessage.user('Sannu! Menene ake nufi da gwagwarmaya?')],
  language: NAtlasLanguage.hausa,
)) {
  print(chunk.delta);
}

// Voice → text → reply (one call)
final result = await client.voiceChat(
  audio: audioBytes,          // Uint8List — ogg/opus, mp3, m4a, wav
  language: NAtlasLanguage.hausa,
);
print(result.transcript.text);  // what was said
print(result.reply);            // N-ATLaS response
```

### Go

```go
import "github.com/Erhabor-Fona/natlas-mobile/packages/go/natlas"

client := natlas.New(os.Getenv("NATLAS_BASE_URL"), os.Getenv("NATLAS_API_KEY"))

resp, err := client.Chat(ctx, &natlas.ChatRequest{
    Messages: []natlas.Message{natlas.UserMessage("Sannu!")},
    Language: natlas.Hausa,
})
fmt.Println(resp.Content())
```

### Rust

```rust
use natlas::{NAtlasClient, Language, ChatMessage};

let client = NAtlasClient::new(&base_url, &api_key);

let response = client
    .chat(vec![ChatMessage::user("Sannu!")], Language::Hausa)
    .await?;
```

---

## API surface (all three SDKs implement this)

```
POST /v1/chat/completions     — chat, with optional streaming
POST /v1/audio/transcriptions — speech-to-text (ha / ig / yo / en)
GET  /health                  — gateway liveness + model status
```

Full reference: [docs/api.md](docs/api.md)

---

## Self-hosting the gateway

The `serve/` directory puts N-ATLaS and all four ASR models behind a single
OpenAI-compatible base URL.

```bash
# Modal (recommended — scales to zero, one command)
cd serve
pip install modal
modal deploy modal_app.py

# Docker Compose (requires a local GPU)
docker compose up
```

Full guide: [docs/self-hosting.md](docs/self-hosting.md)

---

## Models

All five Hugging Face repos are **gated** — accept the terms with your HF account
and supply `HF_TOKEN` to the gateway.

| Model | Repo | Notes |
|---|---|---|
| LLM | `NCAIR1/N-ATLaS` | Llama-3 8B fine-tune, 8 092-token context |
| Hausa ASR | `NCAIR1/Hausa-ASR` | Whisper Small, 30 s window, 16 kHz mono |
| Igbo ASR | `NCAIR1/Igbo-ASR` | Whisper Small, 30 s window, 16 kHz mono |
| Yorùbá ASR | `NCAIR1/Yoruba-ASR` | Whisper Small, 30 s window, 16 kHz mono |
| Nigerian English ASR | `NCAIR1/NigerianAccentedEnglish` | Whisper Small, 30 s window |

---

## Documentation

| Page | What's in it |
|---|---|
| [docs/index.md](docs/index.md) | Overview and where to start |
| [docs/self-hosting.md](docs/self-hosting.md) | Deploy the gateway — do this first |
| [docs/api.md](docs/api.md) | The wire contract all three SDKs implement |
| [docs/flutter.md](docs/flutter.md) | Recording audio, permissions, key handling |
| [docs/go.md](docs/go.md) | Proxy patterns, concurrency, batch work |
| [docs/rust.md](docs/rust.md) | Cross-compiling, streaming, embedded targets |

## Repo layout

```
natlas-mobile/
├── packages/
│   ├── flutter/       natlas_flutter — Dart SDK + widgets
│   ├── go/            natlas — Go client (stdlib only)
│   └── rust/          natlas — async crate (tokio + reqwest + rustls)
├── apps/demo/         Flutter voice chatbot (showcase artefact)
├── serve/
│   ├── gateway.py     shared request handling + model loading
│   ├── modal_app.py   Modal deployment (recommended)
│   ├── app.py         Docker Compose entrypoint
│   └── Dockerfile     local GPU deployment
├── shared/fixtures/   canonical payloads — all three SDKs assert on these
└── docs/
```

The two deployment targets both build their FastAPI app from `gateway.py`, so
the Modal and Docker paths cannot drift apart. Likewise all three SDKs test
against `shared/fixtures/`, so a contract change breaks every SDK's tests at
once rather than silently.

## Contributing

The most useful contribution is trying an SDK and reporting what broke —
especially from Hausa, Igbo, or Yorùbá speakers who can judge output quality.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licensing

This repository's **code** is Apache-2.0.
The **N-ATLaS models** carry a separate license — 1 000 active end-users per
rolling 30 days, mandatory attribution, no commercial deployment without a
separate licence. See [NOTICE](NOTICE) before deploying anything public.

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
