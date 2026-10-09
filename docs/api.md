# Gateway API reference

The contract every SDK in this repo implements, and what `serve/modal_app.py`
serves. OpenAI-compatible where it can be, so existing tooling mostly works
unchanged.

Base URL is whatever your deployment gives you — a Modal app URL, or
`http://localhost:8000` with Docker Compose.

## Authentication

Every endpoint except `/health` requires a bearer token:

```
Authorization: Bearer <NATLAS_API_KEY>
```

The gateway compares the token against the `NATLAS_API_KEY` secret using a
constant-time hash comparison. A bad or missing token returns `401`.

---

## `GET /health`

Liveness plus which models are loaded. No auth required, so you can point an
uptime monitor at it.

**Response `200`**

```json
{
  "status": "ok",
  "models": {
    "llm": "NCAIR1/N-ATLaS",
    "asr": [
      "NCAIR1/Hausa-ASR",
      "NCAIR1/Igbo-ASR",
      "NCAIR1/Yoruba-ASR",
      "NCAIR1/NigerianAccentedEnglish"
    ]
  },
  "timestamp": 1760000000
}
```

Note that on Modal the first request after idle triggers a cold start —
the container has to load the LLM and four ASR models onto the GPU. Expect
30–90 seconds before `/health` answers. Subsequent requests are fast until the
container scales down again.

---

## `POST /v1/chat/completions`

**Request**

```json
{
  "messages": [
    { "role": "user", "content": "Sannu! Yaya aiki?" }
  ],
  "language": "ha",
  "temperature": 0.7,
  "max_tokens": 512,
  "stream": false
}
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `messages` | array | required | `role` is `system`, `user`, or `assistant` |
| `language` | string | `"en"` | `ha`, `ig`, `yo`, `en` |
| `temperature` | number | `0.7` | |
| `max_tokens` | integer | `512` | Context window is 8 092 tokens total |
| `stream` | boolean | `false` | SSE when true |

If no `system` message is present, the gateway injects one naming the language
so the model replies in it. Supply your own `system` message to override that
behaviour entirely.

The prompt is assembled with the Llama-3 chat template, which requires a
`date_string` — the gateway fills in the current date.

**Response `200`** (non-streaming)

```json
{
  "id": "chatcmpl-8f2a1c4e9b7d4e0a",
  "object": "chat.completion",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Sannu da zuwa! Ina farin cikin taimaka maka."
      }
    }
  ],
  "usage": { "prompt_tokens": 42, "completion_tokens": 18 }
}
```

**Response `200`** (streaming, `text/event-stream`)

Each event carries a delta, not the accumulated text. The stream ends with a
`[DONE]` sentinel.

```
data: {"id":"chatcmpl-8f2a…","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Sannu"}}]}

data: {"id":"chatcmpl-8f2a…","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" da"}}]}

data: [DONE]
```

A single TCP read may split an SSE line, so a client must buffer until it sees
a newline. All three SDKs in this repo do.

---

## `POST /v1/audio/transcriptions`

`multipart/form-data`.

| Part | Type | Notes |
|---|---|---|
| `file` | file | Any format ffmpeg reads — ogg/opus, m4a, mp3, wav, webm, flac |
| `language` | text | `ha`, `ig`, `yo`, `en` — picks which ASR model runs |

The gateway converts the upload to 16 kHz mono WAV with ffmpeg and splits it
into ≤28-second chunks, because the Whisper-based ASR models take a 30-second
window. Chunk transcripts are joined with a space, so recordings of any length
work without client-side handling.

```bash
curl -X POST "$NATLAS_BASE_URL/v1/audio/transcriptions" \
  -H "Authorization: Bearer $NATLAS_API_KEY" \
  -F "file=@recording.m4a" \
  -F "language=ha"
```

**Response `200`**

```json
{
  "text": "Ina son sanin yadda ake noma masara a Kano.",
  "language": "ha",
  "duration_seconds": 4.82
}
```

`language` echoes the request — the ASR models are per-language, so this is not
language detection. Send the wrong language and you get confident nonsense.

---

## Errors

FastAPI's envelope, so error bodies are `{"detail": "..."}`.

| Status | Meaning |
|---|---|
| `400` | Unsupported `language` value |
| `401` | Bad or missing bearer token |
| `422` | Audio conversion failed — ffmpeg could not read the upload |
| `429` | Rate limited |
| `500` | Model or gateway failure |

```json
{ "detail": "Invalid or missing API key" }
```

Each SDK unwraps `detail` into its own error type: `NAtlasException` (Flutter),
`*APIError` (Go), `Error::Api` (Rust).

---

## Not implemented

Deliberately out of scope for now, listed so you do not go looking:

- `GET /v1/models` — model list is in `/health` instead
- Text-to-speech — N-ATLaS ships no TTS model
- Function calling / tool use — the base model is not tuned for it
- Embeddings
- Automatic language detection

---

## Contract tests

`shared/fixtures/` holds the canonical payloads above. All three SDKs assert
against those same files, so changing the gateway contract breaks every SDK's
tests at once rather than drifting silently. Update the fixture first, then fix
what fails.
