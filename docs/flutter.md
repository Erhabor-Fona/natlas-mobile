# Flutter

Full API documentation lives in the package README:
**[packages/flutter/README.md](../packages/flutter/README.md)**

This page covers what is specific to shipping N-ATLaS in a real Flutter app.

## Install

From pub.dev once published:

```yaml
dependencies:
  natlas_flutter: ^0.1.0
```

Or from this repo while developing:

```yaml
dependencies:
  natlas_flutter:
    path: ../../packages/flutter
```

## Recording audio

`natlas_flutter` deliberately does not depend on an audio recorder — there are
several good ones and forcing a choice would be wrong. The demo app uses
[`record`](https://pub.dev/packages/record):

```yaml
dependencies:
  record: ^5.1.2
  permission_handler: ^11.3.1
```

Record **Opus in Ogg at 16 kHz mono**. That is exactly what the Whisper-based
ASR models want, so the gateway's ffmpeg step becomes a no-op and uploads stay
small:

```dart
await recorder.start(
  const RecordConfig(
    encoder: AudioEncoder.opus,
    sampleRate: 16000,
    numChannels: 1,
  ),
  path: path,
);
```

See [`apps/demo/lib/services/audio_recorder.dart`](../apps/demo/lib/services/audio_recorder.dart)
for a complete wrapper, including permission handling and temp-file cleanup.

## Permissions

**Android** — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

**iOS** — `ios/Runner/Info.plist`

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Used to record your voice so N-ATLaS can understand and reply.</string>
```

Request at runtime before the first recording, not at launch.

## Streaming into the UI

Two approaches. For full control, consume the stream yourself and accumulate:

```dart
final buffer = StringBuffer();
await for (final chunk in client.chatStream(messages: msgs, language: lang)) {
  buffer.write(chunk.delta);
  setState(() => _reply = buffer.toString());
}
```

For a drop-in widget, `NAtlasStreamText` handles accumulation and renders a
blinking cursor while the stream is open:

```dart
NAtlasStreamText(
  stream: client.chatStream(messages: msgs, language: lang),
  onComplete: (text) => _saveToHistory(text),
  onError: (e) => _showError(e),
)
```

`NAtlasStreamText` subscribes in `initState`, so give it a `key` tied to the
message you are streaming — otherwise a rebuild with a new stream will not
resubscribe.

## Where to put the API key

Not in the app. Anything shipped in a Flutter binary is extractable, including
strings in compiled Dart.

For the demo, `SharedPreferences` and a settings screen are fine — the user
supplies their own key. For a shipped app, proxy through your own backend:

```
Flutter app → your API (holds the N-ATLaS key) → gateway
```

That also gives you a place to put rate limiting, which matters given the
model licence's 1 000 active end-user cap.

If you must store a key on-device, use
[`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage),
not `SharedPreferences`.

## Timeouts

The default is 60 seconds, which is not enough for a cold start on Modal — the
first request after idle loads five models onto a GPU.

```dart
final client = NAtlasClient(
  baseUrl: baseUrl,
  apiKey: apiKey,
  timeout: const Duration(minutes: 3),
);
```

Call `health()` on app start to absorb the cold start before the user tries to
chat, and show a "waking up" state rather than a spinner that looks stuck.

## Disposing

`NAtlasClient` holds an `http.Client`. Dispose it with your widget or service:

```dart
@override
void dispose() {
  _client.dispose();
  super.dispose();
}
```

## Conversation history

The gateway is stateless — it has no memory between requests. Send prior turns
yourself:

```dart
final messages = [
  ...previousTurns,          // your accumulated ChatMessages
  ChatMessage.user(newText),
];
```

Watch the 8 092-token context window. Long conversations need trimming; drop
oldest turns first, keeping any system message.

## Errors

```dart
try {
  await client.chat(messages: msgs, language: lang);
} on NAtlasException catch (e) {
  switch (e.statusCode) {
    case 401: _promptForApiKey();
    case 422: _showMessage('Could not read that audio');
    case 429: _backOffAndRetry();
    default:  _showMessage(e.message);
  }
}
```

A `TimeoutException` (not `NAtlasException`) means the request exceeded the
client timeout — usually a cold start.

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
