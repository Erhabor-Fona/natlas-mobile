# natlas

Async Rust client for [N-ATLaS](https://huggingface.co/NCAIR1/N-ATLaS) —
Nigeria's sovereign multilingual LLM. Hausa · Igbo · Yorùbá · Nigerian English.

Built on `tokio` + `reqwest`, with `serde`-typed models and `thiserror` errors.

## Install

```toml
[dependencies]
natlas = "0.1"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
futures-util = "0.3"   # only if you use chat_stream
```

## Use

```rust
use natlas::{NAtlasClient, ChatMessage, Language};

#[tokio::main]
async fn main() -> natlas::Result<()> {
    let client = NAtlasClient::new(
        std::env::var("NATLAS_BASE_URL").unwrap(),
        std::env::var("NATLAS_API_KEY").unwrap(),
    );

    let reply = client
        .chat(vec![ChatMessage::user("Sannu! Yaya aiki?")], Language::Hausa)
        .await?;

    println!("{}", reply.content());
    Ok(())
}
```

### Streaming chat

```rust
use futures_util::StreamExt;

let mut stream = client
    .chat_stream(vec![ChatMessage::user("Báwo ni?")], Language::Yoruba)
    .await?;

while let Some(chunk) = stream.next().await {
    print!("{}", chunk?.delta());
}
```

The SSE parser buffers across TCP chunk boundaries, so a delta split mid-line
still arrives intact.

### Tuning sampling

```rust
use natlas::ChatRequest;

let request = ChatRequest::new(vec![ChatMessage::user("Kedụ?")], Language::Igbo)
    .temperature(0.3)
    .max_tokens(1024);

let reply = client.chat_with(request).await?;
```

### Speech-to-text

```rust
let audio = std::fs::read("recording.m4a")?;

let result = client
    .transcribe(audio, Language::Hausa, "recording.m4a")
    .await?;

println!("{} ({:.1}s)", result.text, result.duration_seconds);
```

### Voice chat (transcribe + reply in one call)

```rust
let result = client
    .voice_chat(audio, Language::Hausa, "recording.m4a", history)
    .await?;

println!("heard: {}", result.transcript.text);
println!("reply: {}", result.reply);
```

## Errors

Everything returns `natlas::Result<T>`, with `natlas::Error` covering API,
transport, and decode failures.

```rust
match client.chat(messages, Language::Hausa).await {
    Ok(reply) => println!("{}", reply.content()),
    Err(e) if e.is_unauthorized() => eprintln!("bad API key"),
    Err(e) if e.is_rate_limited() => tokio::time::sleep(backoff).await,
    Err(e) => eprintln!("{e}"),
}
```

`Error::status()` gives the raw HTTP code when the gateway responded.

## Configuration

```rust
use std::time::Duration;

let client = NAtlasClient::builder(base_url, api_key)
    .timeout(Duration::from_secs(300))   // long generations
    .build()?;

// Or supply your own reqwest::Client for proxies, tracing, pooling:
let client = NAtlasClient::builder(base_url, api_key)
    .http_client(my_instrumented_client)
    .build()?;
```

`NAtlasClient` is `Clone` and cheap to clone — the connection pool is shared.

## Languages

| Variant | Code | Language |
|---|---|---|
| `Language::Hausa` | `ha` | Hausa |
| `Language::Igbo` | `ig` | Igbo |
| `Language::Yoruba` | `yo` | Yorùbá |
| `Language::English` | `en` | Nigerian English |

`Language::ALL` iterates all four; `Language::from_str` parses a code.

## Audio formats

Pass raw bytes in any format ffmpeg can read — ogg/opus, m4a, mp3, wav, webm,
flac. The gateway converts to 16 kHz mono WAV and chunks recordings over 28
seconds, so no client-side pre-processing is needed.

## TLS

Uses `rustls` by default — no OpenSSL dependency, which keeps cross-compiles
for embedded and container targets straightforward.

## Tests

```bash
cargo test
cargo clippy --all-targets
```

Tests run against a `wiremock` server and assert on `shared/fixtures/`, the
same payloads the Flutter and Go SDKs use.

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
