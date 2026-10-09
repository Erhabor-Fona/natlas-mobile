# N-ATLaS Demo

A voice chatbot in Hausa, Igbo, Yorùbá, and Nigerian English — built with
`natlas_flutter` from this repo. This is the showcase artefact: speak or type,
and N-ATLaS replies in the same language.

## What it demonstrates

- **Voice in** — record, transcribe with the matching ASR model, show what was
  heard before the reply starts
- **Streaming out** — the reply renders token by token
- **Language switching** — four languages, switched from the app bar mid-chat
- **Conversation history** — prior turns are sent as context
- **Gateway health** — a banner when the gateway is unreachable, with retry

## Run it

You need a deployed gateway first — see
[docs/self-hosting.md](../../docs/self-hosting.md).

```bash
cd apps/demo
flutter pub get
flutter run
```

On first launch the app asks for your gateway URL and API key, and has a
**Test connection** button that calls `/health` so you find out about a bad URL
or key before you try to chat.

## Permissions

Microphone access is requested at runtime. The platform manifests need it
declared:

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

## Structure

```
lib/
├── main.dart                      app + theme, routes to settings on first run
├── screens/
│   ├── chat_screen.dart           the conversation: record → transcribe → stream
│   └── settings_screen.dart       gateway URL, API key, language, health test
├── widgets/
│   ├── message_bubble.dart        chat bubbles, typing dots, streaming cursor
│   └── language_picker.dart       app-bar language dropdown
└── services/
    ├── audio_recorder.dart        record package → 16 kHz mono Opus bytes
    └── settings_store.dart        SharedPreferences persistence
```

## A note on the API key

The demo stores the key in `SharedPreferences`, which is fine for a demo but
not for a shipped app. Use `flutter_secure_storage` or the platform keychain,
and consider proxying through your own backend so the key never reaches the
device.

## Recording format

`audio_recorder.dart` records Opus in Ogg at 16 kHz mono — exactly what the
Whisper-based ASR models want. The gateway's ffmpeg conversion then becomes a
no-op and uploads stay small. Any other format still works; the gateway
converts it.

---

> **N-ATLaS is an initiative of the Federal Ministry of Communications,
> Innovation and Digital Economy, and powered by Awarri Technologies.**
