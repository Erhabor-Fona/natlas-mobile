use crate::client::NAtlasClient;
use crate::error::Result;
use crate::models::{ChatMessage, ChatRequest, Language, VoiceChatResult};

impl NAtlasClient {
    /// Transcribe audio, send the transcript to N-ATLaS, and return both.
    ///
    /// Two HTTP round trips. If you want to show the transcript before the
    /// reply arrives, call [`NAtlasClient::transcribe`] and
    /// [`NAtlasClient::chat`] separately.
    ///
    /// ```no_run
    /// # use natlas::{NAtlasClient, Language};
    /// # async fn run() -> natlas::Result<()> {
    /// let client = NAtlasClient::new("https://gateway.modal.run", "key");
    /// let audio = std::fs::read("recording.m4a").unwrap();
    ///
    /// let result = client
    ///     .voice_chat(audio, Language::Hausa, "recording.m4a", vec![])
    ///     .await?;
    /// println!("heard: {}", result.transcript.text);
    /// println!("reply: {}", result.reply);
    /// # Ok(())
    /// # }
    /// ```
    pub async fn voice_chat(
        &self,
        audio: Vec<u8>,
        language: Language,
        filename: impl Into<String>,
        history: Vec<ChatMessage>,
    ) -> Result<VoiceChatResult> {
        let transcript = self.transcribe(audio, language, filename).await?;

        let mut messages = history;
        messages.push(ChatMessage::user(transcript.text.clone()));

        let response = self.chat_with(ChatRequest::new(messages, language)).await?;

        Ok(VoiceChatResult {
            transcript,
            reply: response.into_content(),
        })
    }
}
