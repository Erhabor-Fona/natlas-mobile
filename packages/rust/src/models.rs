use serde::{Deserialize, Serialize};
use std::fmt;
use std::str::FromStr;

use crate::error::Error;

/// A language supported by N-ATLaS.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Language {
    /// Hausa (`ha`).
    #[serde(rename = "ha")]
    Hausa,
    /// Igbo (`ig`).
    #[serde(rename = "ig")]
    Igbo,
    /// Yorùbá (`yo`).
    #[serde(rename = "yo")]
    Yoruba,
    /// Nigerian English (`en`).
    #[serde(rename = "en")]
    English,
}

impl Language {
    /// The gateway language code.
    pub fn code(&self) -> &'static str {
        match self {
            Language::Hausa => "ha",
            Language::Igbo => "ig",
            Language::Yoruba => "yo",
            Language::English => "en",
        }
    }

    /// Human-readable name.
    pub fn display_name(&self) -> &'static str {
        match self {
            Language::Hausa => "Hausa",
            Language::Igbo => "Igbo",
            Language::Yoruba => "Yorùbá",
            Language::English => "Nigerian English",
        }
    }

    /// Every supported language.
    pub const ALL: [Language; 4] = [
        Language::Hausa,
        Language::Igbo,
        Language::Yoruba,
        Language::English,
    ];
}

impl fmt::Display for Language {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.code())
    }
}

impl FromStr for Language {
    type Err = Error;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "ha" => Ok(Language::Hausa),
            "ig" => Ok(Language::Igbo),
            "yo" => Ok(Language::Yoruba),
            "en" => Ok(Language::English),
            other => Err(Error::UnknownLanguage(other.to_string())),
        }
    }
}

/// A single message in a conversation.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ChatMessage {
    /// One of `system`, `user`, or `assistant`.
    pub role: String,
    /// The message text.
    pub content: String,
}

impl ChatMessage {
    /// A message with the `user` role.
    pub fn user(content: impl Into<String>) -> Self {
        Self {
            role: "user".into(),
            content: content.into(),
        }
    }

    /// A message with the `assistant` role.
    pub fn assistant(content: impl Into<String>) -> Self {
        Self {
            role: "assistant".into(),
            content: content.into(),
        }
    }

    /// A message with the `system` role.
    pub fn system(content: impl Into<String>) -> Self {
        Self {
            role: "system".into(),
            content: content.into(),
        }
    }
}

/// Body of a chat completion request.
#[derive(Debug, Clone, Serialize)]
pub struct ChatRequest {
    /// The conversation so far, oldest first.
    pub messages: Vec<ChatMessage>,
    /// Which language the model should understand and reply in.
    pub language: Language,
    /// Sampling temperature. Higher is more varied.
    pub temperature: f32,
    /// Maximum tokens to generate.
    pub max_tokens: u32,
    /// Whether to stream the reply. Set automatically by the client methods.
    pub stream: bool,
}

impl ChatRequest {
    /// A non-streaming request with the default sampling settings.
    pub fn new(messages: Vec<ChatMessage>, language: Language) -> Self {
        Self {
            messages,
            language,
            temperature: 0.7,
            max_tokens: 512,
            stream: false,
        }
    }

    /// Override the sampling temperature.
    pub fn temperature(mut self, value: f32) -> Self {
        self.temperature = value;
        self
    }

    /// Override the generation cap.
    pub fn max_tokens(mut self, value: u32) -> Self {
        self.max_tokens = value;
        self
    }
}

/// Token accounting for a completion.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct Usage {
    /// Tokens consumed by the prompt.
    #[serde(default)]
    pub prompt_tokens: u32,
    /// Tokens produced by the model.
    #[serde(default)]
    pub completion_tokens: u32,
}

impl Usage {
    /// Prompt plus completion tokens.
    pub fn total_tokens(&self) -> u32 {
        self.prompt_tokens + self.completion_tokens
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct Choice {
    pub message: ChatMessage,
}

/// A non-streaming chat completion response.
#[derive(Debug, Clone, Deserialize)]
pub struct ChatResponse {
    /// Gateway-assigned completion id.
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub(crate) choices: Vec<Choice>,
    /// Token accounting for this completion.
    #[serde(default)]
    pub usage: Usage,
}

impl ChatResponse {
    /// The assistant's reply text, or `""` if there were no choices.
    pub fn content(&self) -> &str {
        self.choices
            .first()
            .map(|c| c.message.content.as_str())
            .unwrap_or("")
    }

    /// Consume the response and take ownership of the reply text.
    pub fn into_content(mut self) -> String {
        if self.choices.is_empty() {
            String::new()
        } else {
            self.choices.remove(0).message.content
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
pub(crate) struct DeltaChoice {
    #[serde(default)]
    pub delta: Delta,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub(crate) struct Delta {
    #[serde(default)]
    pub content: String,
}

/// One delta from a streamed completion.
#[derive(Debug, Clone, Deserialize)]
pub struct StreamChunk {
    /// Gateway-assigned completion id, shared across every chunk of one reply.
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub(crate) choices: Vec<DeltaChoice>,
}

impl StreamChunk {
    /// The new text in this chunk — delta only, not accumulated.
    pub fn delta(&self) -> &str {
        self.choices
            .first()
            .map(|c| c.delta.content.as_str())
            .unwrap_or("")
    }
}

/// Result of a speech-to-text request.
#[derive(Debug, Clone, Deserialize)]
pub struct Transcription {
    /// The transcribed text.
    pub text: String,
    /// The language the ASR model was run with.
    pub language: Language,
    /// Length of the submitted audio, in seconds.
    #[serde(default)]
    pub duration_seconds: f64,
}

/// A transcription paired with the model's reply to it.
#[derive(Debug, Clone)]
pub struct VoiceChatResult {
    /// What the speaker said.
    pub transcript: Transcription,
    /// What N-ATLaS replied.
    pub reply: String,
}

/// Models reported by the gateway health endpoint.
#[derive(Debug, Clone, Deserialize)]
pub struct HealthModels {
    /// Hugging Face repo id of the loaded LLM.
    pub llm: String,
    /// Hugging Face repo ids of the loaded ASR models.
    #[serde(default)]
    pub asr: Vec<String>,
}

/// Gateway liveness response.
#[derive(Debug, Clone, Deserialize)]
pub struct Health {
    /// `"ok"` when the gateway is serving.
    pub status: String,
    /// Which models are loaded.
    pub models: HealthModels,
    /// Unix timestamp of the health check.
    #[serde(default)]
    pub timestamp: i64,
}
