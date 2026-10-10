# Changelog

## 0.1.0

First release.

- `NAtlasClient` — chat, streaming chat, speech-to-text, and `voiceChat`
  (transcribe and reply in one call) against a self-hosted N-ATLaS gateway.
- Four languages: Hausa, Igbo, Yorùbá, and Nigerian English, each routed to
  its own fine-tuned Whisper ASR model.
- `NAtlasStreamText` — renders a streaming reply token by token with a
  blinking cursor.
- `NAtlasMicButton` — recording UI state (idle / recording / processing),
  with audio capture delegated to whichever recorder package you use.
- `NAtlasDiacriticBar` — a row of tone and dot-below keys above the system
  keyboard, switching key set by language. Yorùbá and Igbo mark tone
  semantically, and phone keyboards generally cannot produce those marks.
- Typed errors: every failure throws `NAtlasException` carrying
  `statusCode`, `message`, and `detail`.
