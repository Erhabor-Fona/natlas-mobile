use reqwest::multipart::{Form, Part};

use crate::client::NAtlasClient;
use crate::error::{Error, Result};
use crate::models::{Language, Transcription};

impl NAtlasClient {
    /// Convert audio to text using the ASR model for `language`.
    ///
    /// `audio` may be any format ffmpeg can read — ogg/opus, m4a, mp3, wav,
    /// webm, flac. The gateway converts to 16 kHz mono WAV and chunks anything
    /// over 28 seconds, so no client-side pre-processing is needed.
    ///
    /// ```no_run
    /// # use natlas::{NAtlasClient, Language};
    /// # async fn run() -> natlas::Result<()> {
    /// let client = NAtlasClient::new("https://gateway.modal.run", "key");
    /// let audio = std::fs::read("recording.m4a").unwrap();
    ///
    /// let result = client
    ///     .transcribe(audio, Language::Hausa, "recording.m4a")
    ///     .await?;
    /// println!("{}", result.text);
    /// # Ok(())
    /// # }
    /// ```
    pub async fn transcribe(
        &self,
        audio: Vec<u8>,
        language: Language,
        filename: impl Into<String>,
    ) -> Result<Transcription> {
        if audio.is_empty() {
            return Err(Error::InvalidAudio("audio is empty".into()));
        }

        let filename = filename.into();
        let mime = mime_for_filename(&filename);

        let part = Part::bytes(audio)
            .file_name(filename)
            .mime_str(mime)
            .map_err(Error::Http)?;

        let form = Form::new()
            .text("language", language.code().to_string())
            .part("file", part);

        let response = self
            .http
            .post(self.url("/v1/audio/transcriptions"))
            .header("Authorization", self.bearer())
            .multipart(form)
            .send()
            .await?;

        let response = Self::check(response).await?;
        Ok(response.json().await?)
    }
}

fn mime_for_filename(filename: &str) -> &'static str {
    let ext = filename
        .rsplit('.')
        .next()
        .unwrap_or("")
        .to_ascii_lowercase();

    match ext.as_str() {
        "ogg" | "opus" => "audio/ogg",
        "mp3" => "audio/mpeg",
        "m4a" | "mp4" | "aac" => "audio/m4a",
        "wav" => "audio/wav",
        "webm" => "audio/webm",
        "flac" => "audio/flac",
        _ => "application/octet-stream",
    }
}

#[cfg(test)]
mod tests {
    use super::mime_for_filename;

    #[test]
    fn maps_known_extensions() {
        assert_eq!(mime_for_filename("a.ogg"), "audio/ogg");
        assert_eq!(mime_for_filename("a.M4A"), "audio/m4a");
        assert_eq!(mime_for_filename("a.wav"), "audio/wav");
        assert_eq!(mime_for_filename("noext"), "application/octet-stream");
    }
}
