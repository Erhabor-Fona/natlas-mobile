# natlas_flutter

Flutter SDK for [N-ATLaS](https://huggingface.co/NCAIR1/N-ATLaS) — Nigeria's
sovereign multilingual LLM. Hausa · Igbo · Yorùbá · Nigerian English.

Chat, streaming, speech-to-text, and drop-in widgets.

## Install

```yaml
dependencies:
  natlas_flutter: ^0.1.0
```

## Use

```dart
import 'package:natlas_flutter/natlas_flutter.dart';

final client = NAtlasClient(
  baseUrl: 'https://your-gateway.modal.run',
  apiKey: 'your_api_key',
);
```

### Chat

```dart
final response = await client.chat(
  messages: [ChatMessage.user('Sannu! Yaya aiki?')],
  language: NAtlasLanguage.hausa,
);
print(response.content);
```

### Streaming chat

```dart
await for (final chunk in client.chatStream(
  messages: [ChatMessage.user('Kedụ?')],
  language: NAtlasLanguage.igbo,
)) {
  stdout.write(chunk.delta);
}
```

Or render it directly:

```dart
NAtlasStreamText(
  stream: client.chatStream(
    messages: [ChatMessage.user('Báwo ni?')],
    language: NAtlasLanguage.yoruba,
  ),
  onComplete: (text) => print('Done: $text'),
)
```

### Speech-to-text

```dart
final result = await client.transcribe(
  audio: audioBytes,              // Uint8List
  language: NAtlasLanguage.hausa,
  filename: 'recording.m4a',
);
print(result.text);
```

### Voice chat (transcribe + reply in one call)

```dart
final result = await client.voiceChat(
  audio: audioBytes,
  language: NAtlasLanguage.hausa,
  history: previousMessages,
);
print(result.transcript.text);  // what the user said
print(result.reply);            // what N-ATLaS replied
```

### Mic button widget

```dart
NAtlasMicButton(
  onStartRecording: () async => await myRecorder.stopAndReadBytes(),
  onRecordingComplete: (bytes) async {
    final result = await client.voiceChat(
      audio: bytes,
      language: NAtlasLanguage.hausa,
    );
    setState(() => _reply = result.reply);
  },
)
```

The widget owns the recording UI state (idle / recording / processing) and
delegates the actual audio capture to whichever recorder package you use —
`record`, `flutter_sound`, or a platform channel of your own.

## Supported languages

| Enum | Code | Language |
|---|---|---|
| `NAtlasLanguage.hausa` | `ha` | Hausa |
| `NAtlasLanguage.igbo` | `ig` | Igbo |
| `NAtlasLanguage.yoruba` | `yo` | Yorùbá |
| `NAtlasLanguage.english` | `en` | Nigerian English |

## Audio formats

Pass raw bytes in any format `ffmpeg` can read — ogg/opus, m4a, mp3, wav,
webm. The gateway converts to 16 kHz mono WAV and chunks anything over 28
seconds, so long recordings work without client-side handling.

## Errors

All failures throw `NAtlasException` with `statusCode`, `message`, and
`detail`.

```dart
try {
  await client.chat(messages: msgs, language: NAtlasLanguage.hausa);
} on NAtlasException catch (e) {
  if (e.statusCode == 401) showApiKeyDialog();
}
```

## Gateway

This SDK talks to the `serve/` gateway in the parent repo. See
[docs/self-hosting.md](../../docs/self-hosting.md).

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
