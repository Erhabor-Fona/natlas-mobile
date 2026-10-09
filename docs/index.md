# N-ATLaS Mobile SDK — documentation

The mobile and systems layer for [N-ATLaS](https://huggingface.co/NCAIR1/N-ATLaS),
Nigeria's sovereign multilingual LLM. Hausa · Igbo · Yorùbá · Nigerian English.

## Start here

1. **[Self-hosting the gateway](self-hosting.md)** — do this first. There is no
   public N-ATLaS API, so every SDK needs a gateway you deploy. One command on
   Modal.
2. Pick your SDK: **[Flutter](flutter.md)** · **[Go](go.md)** ·
   **[Rust](rust.md)**
3. **[API reference](api.md)** — the wire contract, if you are writing your own
   client or debugging one of ours.

## What this is

N-ATLaS ships as model weights on Hugging Face, with no hosted API and no
client libraries. This repo supplies both halves of what is missing for mobile
and systems work:

- **`serve/`** — a gateway that puts the LLM and all four ASR models behind one
  OpenAI-compatible base URL, deployable with a single command
- **`packages/`** — typed clients for Flutter, Go, and Rust, each implementing
  the same three endpoints

The existing [N-ATLAS-Kit](https://github.com/Kambah123/N-ATLAS-Kit) covers
JavaScript and Python — the web and server layer. This kit covers what it does
not: mobile apps, infrastructure tooling, and embedded or systems deployments.

## The three endpoints

Every SDK implements exactly these:

| Endpoint | What it does |
|---|---|
| `POST /v1/chat/completions` | Chat, with optional SSE streaming |
| `POST /v1/audio/transcriptions` | Speech-to-text, per language |
| `GET /health` | Liveness and which models are loaded |

Full detail in the [API reference](api.md).

## The models

| Model | Repo | Notes |
|---|---|---|
| LLM | `NCAIR1/N-ATLaS` | Llama-3 8B fine-tune, 8 092-token context |
| Hausa ASR | `NCAIR1/Hausa-ASR` | Whisper Small, 30 s window, 16 kHz mono |
| Igbo ASR | `NCAIR1/Igbo-ASR` | Whisper Small, 30 s window, 16 kHz mono |
| Yorùbá ASR | `NCAIR1/Yoruba-ASR` | Whisper Small, 30 s window, 16 kHz mono |
| Nigerian English ASR | `NCAIR1/NigerianAccentedEnglish` | Whisper Small, 30 s window |

All five are gated — accept the terms on each model card with your Hugging Face
account before deploying.

The ASR models are **per-language, not multilingual**. Send Yorùbá audio to the
Hausa model and you get confident nonsense rather than an error, so the
`language` parameter is not optional guesswork.

## Demo app

[`apps/demo`](../apps/demo) is a voice chatbot built on `natlas_flutter` —
speak or type in any of the four languages and N-ATLaS replies in the same one.
It is the reference for how the pieces fit together.

## Licensing

The code here is Apache-2.0. The N-ATLaS models are not — they carry an
Open-Source Research and Innovation License with a 1 000 active end-user cap and
mandatory attribution. See [NOTICE](../NOTICE) before deploying anything
public.

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
