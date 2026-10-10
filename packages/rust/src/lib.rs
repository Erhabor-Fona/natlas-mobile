//! Async Rust client for [N-ATLaS](https://huggingface.co/NCAIR1/N-ATLaS) —
//! Nigeria's sovereign multilingual LLM. Hausa, Igbo, Yorùbá, and Nigerian
//! English.
//!
//! ```no_run
//! use natlas::{NAtlasClient, ChatMessage, Language};
//!
//! #[tokio::main]
//! async fn main() -> natlas::Result<()> {
//!     let client = NAtlasClient::new(
//!         std::env::var("NATLAS_BASE_URL").unwrap(),
//!         std::env::var("NATLAS_API_KEY").unwrap(),
//!     );
//!
//!     let reply = client
//!         .chat(vec![ChatMessage::user("Sannu! Yaya aiki?")], Language::Hausa)
//!         .await?;
//!
//!     println!("{}", reply.content());
//!     Ok(())
//! }
//! ```
//!
//! # Streaming
//!
//! ```no_run
//! # use natlas::{NAtlasClient, ChatMessage, Language};
//! use futures_util::StreamExt;
//!
//! # async fn run() -> natlas::Result<()> {
//! # let client = NAtlasClient::new("https://gateway.modal.run", "key");
//! let mut stream = client
//!     .chat_stream(vec![ChatMessage::user("Báwo ni?")], Language::Yoruba)
//!     .await?;
//!
//! while let Some(chunk) = stream.next().await {
//!     print!("{}", chunk?.delta());
//! }
//! # Ok(())
//! # }
//! ```
//!
//! # Speech
//!
//! ```no_run
//! # use natlas::{NAtlasClient, Language};
//! # async fn run() -> natlas::Result<()> {
//! # let client = NAtlasClient::new("https://gateway.modal.run", "key");
//! let audio = std::fs::read("recording.m4a").unwrap();
//!
//! // Transcribe only
//! let text = client.transcribe(audio.clone(), Language::Hausa, "recording.m4a").await?;
//!
//! // Transcribe and reply in one call
//! let result = client.voice_chat(audio, Language::Hausa, "recording.m4a", vec![]).await?;
//! # Ok(())
//! # }
//! ```
//!
//! ---
//!
//! N-ATLaS is an initiative of the Federal Ministry of Communications,
//! Innovation and Digital Economy, and powered by Awarri Technologies.

#![warn(missing_docs)]
#![warn(clippy::all)]

mod chat;
mod client;
mod error;
mod models;
mod transcribe;
mod voice_chat;

pub use client::{NAtlasClient, NAtlasClientBuilder};
pub use error::{Error, Result};
pub use models::{
    ChatMessage, ChatRequest, ChatResponse, Health, HealthModels, Language, StreamChunk,
    Transcription, Usage, VoiceChatResult,
};
