# Rust

Full API documentation lives in the package README:
**[packages/rust/README.md](../packages/rust/README.md)**

This page covers what is specific to using N-ATLaS from Rust.

## Install

```toml
[dependencies]
natlas = "0.1"
tokio = { version = "1", features = ["macros", "rt-multi-thread"] }
futures-util = "0.3"   # only for chat_stream
```

## Where this fits

Rust is the right choice here for two cases the other SDKs do not cover well:

- **Embedded and edge** — a kiosk, a set-top box, an agricultural sensor hub
  with a voice interface. `rustls` means no OpenSSL to cross-compile, so an
  `aarch64-unknown-linux-gnu` or `armv7` target is straightforward.
- **High-throughput backends** — a transcription pipeline where per-request
  overhead and memory predictability matter.

## Cross-compiling

The crate uses `rustls` rather than `native-tls` specifically so cross-compiles
do not need an OpenSSL toolchain for the target:

```bash
rustup target add aarch64-unknown-linux-gnu
cargo build --release --target aarch64-unknown-linux-gnu
```

For a Raspberry Pi or similar, [`cross`](https://github.com/cross-rs/cross)
handles the linker:

```bash
cargo install cross
cross build --release --target armv7-unknown-linux-gnueabihf
```

## Streaming

`chat_stream` returns an `impl Stream`, so it composes with the rest of the
futures ecosystem:

```rust
use futures_util::StreamExt;

let mut stream = client
    .chat_stream(vec![ChatMessage::user("Sannu!")], Language::Hausa)
    .await?;

while let Some(chunk) = stream.next().await {
    print!("{}", chunk?.delta());
    std::io::stdout().flush()?;
}
```

Each item is a `Result`, because a mid-stream transport failure can happen
after a successful response header. The SSE parser buffers across TCP chunk
boundaries, so a delta split mid-line arrives intact.

To accumulate rather than print:

```rust
let reply: String = stream
    .filter_map(|chunk| async { chunk.ok() })
    .map(|chunk| chunk.delta().to_string())
    .collect()
    .await;
```

## Concurrency

`NAtlasClient` is `Clone` and cheap to clone — the `reqwest::Client` inside
shares a connection pool. Clone it into tasks rather than creating new clients:

```rust
let client = NAtlasClient::new(base_url, api_key);

let handles: Vec<_> = paths
    .into_iter()
    .map(|path| {
        let client = client.clone();
        tokio::spawn(async move {
            let audio = tokio::fs::read(&path).await?;
            client.transcribe(audio, Language::Hausa, &path).await
        })
    })
    .collect();
```

Bound the concurrency though — a single A10G runs one vLLM engine, so unbounded
spawning just queues on the gateway:

```rust
use tokio::sync::Semaphore;
use std::sync::Arc;

let sem = Arc::new(Semaphore::new(2));
// …
let _permit = sem.clone().acquire_owned().await.unwrap();
```

## Timeouts

The default is 60 seconds, not enough for a Modal cold start:

```rust
use std::time::Duration;

let client = NAtlasClient::builder(base_url, api_key)
    .timeout(Duration::from_secs(300))
    .build()?;
```

Probe `health()` at startup so the gateway is warm before real traffic arrives.

## Custom transport

`http_client` takes any `reqwest::Client`, which is where proxies, custom
certificate roots, and middleware go:

```rust
let http = reqwest::Client::builder()
    .timeout(Duration::from_secs(300))
    .user_agent("my-kiosk/1.0")
    .build()?;

let client = NAtlasClient::builder(base_url, api_key)
    .http_client(http)
    .build()?;
```

Note that `http_client` overrides `timeout`, so set the timeout on the
`reqwest::Client` itself when you supply one.

## Avoiding the panic in `new`

`NAtlasClient::new` panics if the TLS backend cannot initialise — convenient in
a `main`, wrong in a library or a long-running service. Use the builder, which
returns a `Result`:

```rust
let client = NAtlasClient::builder(base_url, api_key).build()?;
```

## Errors

```rust
match client.chat(messages, Language::Hausa).await {
    Ok(reply) => println!("{}", reply.content()),
    Err(e) if e.is_unauthorized() => return Err("bad API key".into()),
    Err(e) if e.is_rate_limited() => tokio::time::sleep(backoff).await,
    Err(natlas::Error::Api { status: 422, detail }) => {
        eprintln!("audio rejected: {detail}");
    }
    Err(e) => return Err(e.into()),
}
```

`Error` implements `std::error::Error`, so it works with `anyhow`, `eyre`, and
`?` into a boxed error.

## Conversation history

The gateway is stateless. Send prior turns yourself, and watch the 8 092-token
context window:

```rust
let mut history: Vec<ChatMessage> = Vec::new();

// after each exchange
history.push(ChatMessage::user(user_text));
history.push(ChatMessage::assistant(reply.content().to_string()));

// trim oldest turns when the conversation gets long,
// keeping any leading system message
if history.len() > 20 {
    history.drain(..2);
}
```

## Example

[`packages/rust/examples/voice_chat.rs`](../packages/rust/examples/voice_chat.rs)
covers health, streaming, and a voice round trip:

```bash
export NATLAS_BASE_URL=https://your-gateway.modal.run
export NATLAS_API_KEY=your_key
cargo run --example voice_chat recording.m4a
```

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
