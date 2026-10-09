use futures_util::stream::{Stream, StreamExt};

use crate::client::NAtlasClient;
use crate::error::Result;
use crate::models::{ChatMessage, ChatRequest, ChatResponse, Language, StreamChunk};

impl NAtlasClient {
    /// Send messages and wait for the complete reply.
    ///
    /// ```no_run
    /// # use natlas::{NAtlasClient, ChatMessage, Language};
    /// # async fn run() -> natlas::Result<()> {
    /// let client = NAtlasClient::new("https://gateway.modal.run", "key");
    /// let reply = client
    ///     .chat(vec![ChatMessage::user("Sannu!")], Language::Hausa)
    ///     .await?;
    /// println!("{}", reply.content());
    /// # Ok(())
    /// # }
    /// ```
    pub async fn chat(
        &self,
        messages: Vec<ChatMessage>,
        language: Language,
    ) -> Result<ChatResponse> {
        self.chat_with(ChatRequest::new(messages, language)).await
    }

    /// Send a fully-specified [`ChatRequest`].
    pub async fn chat_with(&self, mut request: ChatRequest) -> Result<ChatResponse> {
        request.stream = false;

        let response = self
            .http
            .post(self.url("/v1/chat/completions"))
            .header("Authorization", self.bearer())
            .json(&request)
            .send()
            .await?;

        let response = Self::check(response).await?;
        Ok(response.json().await?)
    }

    /// Stream the reply as it is generated.
    ///
    /// Yields [`StreamChunk`]s carrying delta text only. The stream ends at the
    /// gateway's `[DONE]` sentinel.
    ///
    /// ```no_run
    /// # use natlas::{NAtlasClient, ChatMessage, Language};
    /// # use futures_util::StreamExt;
    /// # async fn run() -> natlas::Result<()> {
    /// let client = NAtlasClient::new("https://gateway.modal.run", "key");
    /// let mut stream = client
    ///     .chat_stream(vec![ChatMessage::user("Kedụ?")], Language::Igbo)
    ///     .await?;
    ///
    /// while let Some(chunk) = stream.next().await {
    ///     print!("{}", chunk?.delta());
    /// }
    /// # Ok(())
    /// # }
    /// ```
    pub async fn chat_stream(
        &self,
        messages: Vec<ChatMessage>,
        language: Language,
    ) -> Result<impl Stream<Item = Result<StreamChunk>>> {
        let mut request = ChatRequest::new(messages, language);
        request.stream = true;
        self.chat_stream_with(request).await
    }

    /// Stream a fully-specified [`ChatRequest`].
    pub async fn chat_stream_with(
        &self,
        mut request: ChatRequest,
    ) -> Result<impl Stream<Item = Result<StreamChunk>>> {
        request.stream = true;

        let response = self
            .http
            .post(self.url("/v1/chat/completions"))
            .header("Authorization", self.bearer())
            .header("Accept", "text/event-stream")
            .json(&request)
            .send()
            .await?;

        let response = Self::check(response).await?;
        Ok(sse_stream(response.bytes_stream()))
    }
}

/// Parse an SSE byte stream into [`StreamChunk`]s.
///
/// Buffers across chunk boundaries, since a single TCP read may split an SSE
/// line in half. Malformed lines are skipped rather than failing the stream.
fn sse_stream(
    bytes: impl Stream<Item = reqwest::Result<bytes::Bytes>>,
) -> impl Stream<Item = Result<StreamChunk>> {
    let state = (String::new(), false);

    bytes
        .scan(state, |(buffer, done), result| {
            if *done {
                return std::future::ready(None);
            }

            let chunk = match result {
                Ok(bytes) => bytes,
                Err(e) => return std::future::ready(Some(vec![Err(e.into())])),
            };

            buffer.push_str(&String::from_utf8_lossy(&chunk));

            let mut out = Vec::new();

            // Drain complete lines, leaving any partial tail in the buffer.
            while let Some(newline) = buffer.find('\n') {
                let line: String = buffer.drain(..=newline).collect();
                let line = line.trim();

                let Some(data) = line.strip_prefix("data: ") else {
                    continue;
                };
                let data = data.trim();

                if data == "[DONE]" {
                    *done = true;
                    break;
                }

                if let Ok(parsed) = serde_json::from_str::<StreamChunk>(data) {
                    if !parsed.delta().is_empty() {
                        out.push(Ok(parsed));
                    }
                }
            }

            std::future::ready(Some(out))
        })
        .flat_map(futures_util::stream::iter)
}
