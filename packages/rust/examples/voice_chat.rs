//! Demonstrates the natlas crate: a streamed chat, then a voice round trip if
//! an audio file is supplied.
//!
//! ```sh
//! export NATLAS_BASE_URL=https://your-gateway.modal.run
//! export NATLAS_API_KEY=your_api_key
//! cargo run --example voice_chat                   # streamed chat only
//! cargo run --example voice_chat recording.m4a     # chat + voice round trip
//! ```

use std::io::Write;
use std::time::Duration;

use futures_util::StreamExt;
use natlas::{ChatMessage, ChatRequest, Language, NAtlasClient};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let base_url = std::env::var("NATLAS_BASE_URL").map_err(|_| "set NATLAS_BASE_URL")?;
    let api_key = std::env::var("NATLAS_API_KEY").map_err(|_| "set NATLAS_API_KEY")?;

    let client = NAtlasClient::builder(base_url, api_key)
        .timeout(Duration::from_secs(180))
        .build()?;

    // ── Health ──────────────────────────────────────────────────────────────
    let health = client.health().await?;
    println!(
        "gateway {} · llm {} · {} ASR models\n",
        health.status,
        health.models.llm,
        health.models.asr.len()
    );

    // ── Streamed chat ───────────────────────────────────────────────────────
    print!("Hausa > ");
    std::io::stdout().flush()?;

    let request = ChatRequest::new(
        vec![ChatMessage::user("Sannu! Gaya mini game da Kano.")],
        Language::Hausa,
    )
    .max_tokens(256);

    let mut stream = client.chat_stream_with(request).await?;
    while let Some(chunk) = stream.next().await {
        match chunk {
            Ok(chunk) => {
                print!("{}", chunk.delta());
                std::io::stdout().flush()?;
            }
            Err(e) if e.is_unauthorized() => return Err("bad API key".into()),
            Err(e) => return Err(e.into()),
        }
    }
    println!("\n");

    // ── Voice round trip ────────────────────────────────────────────────────
    let Some(path) = std::env::args().nth(1) else {
        println!("(pass an audio file path to try the voice round trip)");
        return Ok(());
    };

    let audio = std::fs::read(&path)?;
    let result = client
        .voice_chat(audio, Language::Hausa, &path, vec![])
        .await?;

    println!(
        "heard ({:.1}s): {}\n",
        result.transcript.duration_seconds, result.transcript.text
    );
    println!("reply: {}", result.reply);

    Ok(())
}
